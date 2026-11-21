(*==============================================================================
 * 组件名称 (Component)  : FB_DL_BoilerBlowdownSeq
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 锅炉排污顺控。触发源三选一：定时（tInterval 到）／电导率超
 *                         fCondLimitUs／手动 bManTrigger 上升沿 → eOpen（开排污阀，时长 tBlowTime，
 *                         单次硬上限 tBlowMax）→ eSettle（关阀后稳定 tSettleTime）→ eDone。
 *                         联锁：低水位 bLevelLow 为真 → **禁止开启**（干烧风险）；若排污中水位转低
 *                         则立即关阀并置故障；排污期间水位下降量超 fLevelDropMaxPct → 中止并置码。
 * 接口     (Interface)  : 输入 bEnable 使能、tInterval 定时排污周期、fCondUs 实测电导率、
 *                         fCondLimitUs 电导率上限、bManTrigger 手动触发、bLevelLow 低水位联锁、
 *                         fLevelPct 水位、fLevelDropMaxPct 排污期允许水位降幅、tBlowTime 排污时长、
 *                         tBlowMax 单次排污硬上限、tSettleTime 关阀稳定时长、bReset 复位；
 *                         输出 bValveCmd 排污阀命令、nBlowCount 累计排污次数（锁存量，复位不清零）、
 *                         eState、eCause、bError、nErrId。
 * 边界     (Boundary)   : ① 组态闸：tBlowTime <= T#0S、tBlowMax <= tBlowTime、tInterval <= T#0S、
 *                         fCondLimitUs <= 0.0、fLevelDropMaxPct <= 0.0、tSettleTime <= T#0S 或任一
 *                         浮点引脚 NaN → 故障锁存，**且非法时 bValveCmd 直接为 FALSE**（安全侧：阀关）；
 *                         ② 排污水量/时长硬钳位：单次 PT = MIN(tBlowTime, tBlowMax)，防卡阀长时间
 *                         排污把锅炉抽空（钳在 PT 而非事后判，结构性杜绝超时溢流）；
 *                         ③ **周期定时器自复位**：tonInterval 的 IN := NOT tonInterval.Q（R188），
 *                         不依赖外部沿清零，节拍窗永不卡死；
 *                         ④ TON 三枚 + R_TRIG 三枚段 0 无条件周期刷新（R228A）；
 *                         ⑤ 故障相迁出唯一路径 = bReset 上升沿；⑥ 零全局耦合（无 GVL / 无物理地址）。
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 ∧ 水位已恢复（bLevelLow = FALSE 且水位降幅
 *                         已回落到 fLevelDropMaxPct 之内，均为当拍量，R240 范式）。
 *                         自证可满足（终审两式 1）：三枚 TON 的 IN 挂相位，故障相内恒假 → Q 恒假；
 *                         水位回升由补水泵保证（外部职责），故路径物理可达、无恒假因子。
 * 码表     (Codes)      : 16#0005_03A8 故障级：排污顺控故障总码（组态非法 / 低水位联锁 /
 *                         水位降幅超限 / 非法相位），锁存至 bReset 上升沿，归因由 eCause 承载
 *                         （R190 单件单总码，各成因独立赋值点）；16#0005_04D0 信息级：单次排污完成。
 *                         加码反证（R90）：完成时 bValveCmd 已关、eState 驻留 eDone，与「一直待在
 *                         eDone」出口同值；累计次数 nBlowCount 的变化虽可观测，但它是累计台账，
 *                         无法分辨当前这一次归零，故立一码记录每次排污动作的完成沿。
 *                         码段说明：0005 段故障子带 03xx / 信息子带 04xx，本件取 03A8 / 04D0
 *                         （源码实扫该两槽为空，续接同子带已用最大值，未回填碎片孔洞）。
 * 开源溯源 (Origin)     : 道莅自研 clean-room（参考锅炉排污公用工程语义与参数域，
 *                         零代码行复制；t1-2-oscat-building 族）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R45 首版（批次 4 · 序号 20）
 *==============================================================================*)

TYPE E_DL_BbsState :
(
    eIdle   := 0,     // 待触发（阀关） / Idle, valve closed
    eOpen   := 10,    // 排污阀开启计时 / Blowdown valve open
    eSettle := 20,    // 关阀后稳定 / Settling after valve closure
    eDone   := 30,    // 本次排污完成 / Blowdown done
    eFault  := 90     // 故障锁存相（阀关） / Fault latched phase, valve closed
);
END_TYPE

TYPE E_DL_BbsCause :
(
    eNone         := 0,  // 无故障成因 / No cause
    eCfgIllegal   := 1,  // 组态非法 / Illegal configuration
    eLevelLowLock := 2,  // 低水位联锁（禁止开启或中途关阀） / Low-level interlock
    eLevelDrop    := 3,  // 排污期水位降幅超限 / Level drop over limit during blowdown
    ePhaseBad     := 4   // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_BoilerBlowdownSeq
VAR_INPUT
    bEnable         : BOOL := TRUE;       // 排污功能使能 [-] / Blowdown enabled
    tInterval       : TIME := T#8H;       // 定时排污周期，域 > T#0S [ms] / Periodic blowdown interval [ms]
    fCondUs         : REAL := 0.0;        // 实测电导率 [µS/cm] / Measured conductivity [uS/cm]
    fCondLimitUs    : REAL := 3000.0;     // 电导率上限（超限触发排污），域 > 0.0 [µS/cm] / Conductivity limit, domain > 0.0 [uS/cm]
    bManTrigger     : BOOL := FALSE;      // 手动触发（上升沿有效） [-] / Manual trigger, rising edge
    bLevelLow       : BOOL := FALSE;      // 低水位联锁（TRUE 禁止开启，已开立即关阀） [-] / Low-level interlock
    fLevelPct       : REAL := 60.0;       // 水位 [%] / Water level [%]
    fLevelDropMaxPct: REAL := 8.0;        // 排污期允许水位降幅，域 > 0.0 [%] / Allowed level drop during blowdown [%]
    tBlowTime       : TIME := T#30S;      // 单次排污时长，域 > T#0S [ms] / Blowdown duration [ms]
    tBlowMax        : TIME := T#60S;      // 单次排污硬上限，域 > tBlowTime [ms] / Hard blowdown ceiling [ms]
    tSettleTime     : TIME := T#10S;      // 关阀稳定时长，域 > T#0S [ms] / Post-close settling time [ms]
    bReset          : BOOL := FALSE;      // 复位命令，上升沿清故障（不清累计次数） [-] / Reset clears fault, count preserved
END_VAR
VAR_OUTPUT
    bValveCmd       : BOOL;               // 排污阀命令（故障/组态非法恒 FALSE） [-] / Blowdown valve command, FALSE in fault
    nBlowCount      : UDINT;              // 累计排污次数（锁存量，复位不清零） [次] / Cumulative blowdown count, kept across resets
    eState          : E_DL_BbsState;      // 状态出口，段 6 单点映射 / State outlet
    eCause          : E_DL_BbsCause;      // 故障成因出口（R190 归因唯一） / Fault cause outlet
    bError          : BOOL;               // 故障锁存标志 [-] / Fault latch flag
    nErrId          : UDINT;              // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    _eState         : E_DL_BbsState := E_DL_BbsState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause         : E_DL_BbsCause := E_DL_BbsCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    tonInterval     : TON;                // 周期定时（自复位），段 0 无条件调用 / Self-resetting interval timer
    tonBlow         : TON;                // 排污计时（PT 已硬钳位），段 0 无条件调用 / Blowdown timer with clamped preset
    tonSettle       : TON;                // 关阀稳定计时，段 0 无条件调用 / Settle timer
    rtMan           : R_TRIG;             // 手动触发沿实例，段 0 无条件调用 / Manual trigger edge
    rtLevelLow      : R_TRIG;             // 低水位上升沿实例，段 0 无条件调用 / Low-level rising edge
    rtReset         : R_TRIG;             // 复位沿实例，段 0 无条件调用 / Reset edge
    _tBlowPreset    : TIME;               // 排污计时预置（MIN(tBlowTime, tBlowMax) 当拍量） [ms] / Clamped blowdown preset [ms]
    _fLevelAtStart  : REAL;               // 排污起始水位快照（锁存量） [%] / Level snapshot at blowdown start, latched
    _bSnapshotOk    : BOOL;               // 起始水位快照有效（锁存量） [-] / Start-level snapshot valid
    _fLevelDrop     : REAL;               // 本次水位降幅（当拍量） [%] / Level drop this blowdown [%]
    _nBlowCount     : UDINT;              // 累计排污次数（锁存量，复位不清零） [次] / Cumulative count, kept across resets
    _bCondOver      : BOOL;               // 电导率超限当拍量 [-] / Conductivity over limit
    _bNonFin        : BOOL;               // 输入非有限当拍量 [-] / Non-finite input this scan
    _bCfgBad        : BOOL;               // 组态非法当拍量 [-] / Illegal configuration
    _bDropExcess    : BOOL;               // 水位降幅超限当拍量 [-] / Level drop over limit
    _bLevelOk       : BOOL;               // 水位已恢复当拍量（解除可达性判据） [-] / Level recovered verdict
    _bFault         : BOOL;               // 故障锁存位（锁存量） / Latched fault bit
    _uFault         : UDINT;              // 故障码锁存（锁存量） / Latched fault code
    _uInfo          : UDINT;              // 信息码，每拍重算 / Info code, recomputed each scan
END_VAR
VAR CONSTANT
    DL_COUNT_MAX : UDINT := 16#FFFF_FFFE; // 累计次数饱和上限，留加 1 裕度防溢出 [次] / Count saturation limit with margin [count]
END_VAR

(* —— 段 0：当拍判据派生 + 3 枚 TON（含自复位周期定时）与 3 枚 R_TRIG 无条件刷新 —— *)
IF tBlowTime < tBlowMax THEN                                             // 硬钳位：取小者，结构性防超时溢流 / Hard clamp to the smaller preset
    _tBlowPreset := tBlowTime;
ELSE
    _tBlowPreset := tBlowMax;
END_IF
_bCondOver := fCondUs > fCondLimitUs;                                    // 电导率超限当拍量 / Conductivity over limit
_bNonFin   := (fCondUs <> fCondUs) OR (fLevelPct <> fLevelPct)           // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive tests
           OR (fCondLimitUs <> fCondLimitUs) OR (fLevelDropMaxPct <> fLevelDropMaxPct);
_fLevelDrop := _fLevelAtStart - fLevelPct;                               // 本次水位降幅 / Level drop this blowdown
_bDropExcess := _bSnapshotOk AND (_fLevelDrop > fLevelDropMaxPct);       // 降幅超限当拍量 / Drop over limit
_bLevelOk := (NOT bLevelLow) AND ((NOT _bSnapshotOk) OR (_fLevelDrop <= fLevelDropMaxPct));   // 水位已恢复（解除判据） / Level recovered
_bCfgBad := (tBlowTime <= T#0S) OR (tBlowMax <= tBlowTime) OR (tInterval <= T#0S)              // 时间正域与配比闸（R151） / Time gates and ratio constraints
            OR (fCondLimitUs <= 0.0) OR (fLevelDropMaxPct <= 0.0) OR (tSettleTime <= T#0S);     // 浮点与稳定时间闸 / Float and settle gates
rtMan(CLK := bManTrigger);                                                                     // 手动沿，每拍必调（R228A） / Manual edge
rtLevelLow(CLK := bLevelLow);                                                                   // 低水位沿，每拍必调 / Low-level edge
rtReset(CLK := bReset);                                                                         // 复位沿，每拍必调 / Reset edge
tonInterval(IN := NOT tonInterval.Q, PT := tInterval);                                          // 周期定时自复位（R188），IN 取自身 Q 反 / Self-resetting interval timer
tonBlow(IN := (_eState = E_DL_BbsState.eOpen), PT := _tBlowPreset);                             // 排污计时（PT 已钳位，IN 绑相位） / Blowdown timer
tonSettle(IN := (_eState = E_DL_BbsState.eSettle), PT := tSettleTime);                          // 关阀稳定计时（IN 绑相位） / Settle timer

(* —— 段 1：单拍量预清零（锁存量不入清单，R107） —— *)
_uInfo       := 16#0000_0000;      // 信息码每拍重算 / Info recomputed every scan
bValveCmd    := FALSE;             // 阀命令缺省关（安全侧，任何分支须显式开） / Valve defaults closed, safe side
nBlowCount   := _nBlowCount;       // 累计次数镜像（锁存量回放，复位不清零） / Cumulative count mirror
nErrId       := 16#0000_0000;      // 事件码缺省无事件 / Event code default none
bError       := FALSE;             // 故障标志每拍预清，故障分支同拍置位（R45 配对） / Flag preset

(* —— 段 2：复位沿 + 组态域闸 + 低水位联锁 —— *)
IF rtReset.Q THEN                                                        // 当拍复位沿 / current-scan reset edge
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_BbsCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
    _bSnapshotOk := FALSE;                                               // 起始水位快照重新武装 / Re-arm the start-level snapshot
    IF _eState = E_DL_BbsState.eFault THEN
        _eState := E_DL_BbsState.eIdle;                                  // 故障相迁出唯一路径 / Sole exit from fault phase
    END_IF
END_IF
IF _bCfgBad OR _bNonFin THEN                                             // 组态非法（含非有限） → 故障且阀关 / Illegal config, fault with valve closed
    _uFault := 16#0005_03A8;                                             // 故障级：排污顺控故障总码 / Fault-level: blowdown fault code
    _bFault := TRUE;
    bError  := TRUE;                                                     // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_BbsCause.eCfgIllegal;                                // 归因：组态非法 / Cause: illegal configuration
END_IF
IF (NOT _bFault) AND bLevelLow THEN                                      // 低水位联锁：禁止开启；已开则立即关阀 / Low-level interlock
    _uFault := 16#0005_03A8;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_BbsCause.eLevelLowLock;                              // 归因：低水位联锁 / Cause: low-level interlock
END_IF
IF (NOT _bFault) AND _bDropExcess THEN                                   // 排污期水位降幅超限 → 中止 / Level drop over limit, abort
    _uFault := 16#0005_03A8;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_BbsCause.eLevelDrop;                                 // 归因：水位降幅超限 / Cause: level drop over limit
END_IF

(* —— 段 3：故障解除式（R240 全当拍量） —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bNonFin) AND _bLevelOk THEN
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_BbsCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
END_IF

(* —— 段 3A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_BbsState.eFault) THEN
    _eState := E_DL_BbsState.eFault;                                     // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 4：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_BbsState.eIdle:
    IF (NOT bEnable) THEN                                                // 出口 1：未使能，明确驻留 / Disabled, explicit stay
        _eState := E_DL_BbsState.eIdle;
    ELSIF (NOT _bFault) AND (NOT bLevelLow)                              // 出口 2：三触发源之一命中且水位允许 / Any of the three triggers with level permission
          AND (tonInterval.Q OR _bCondOver OR rtMan.Q) THEN
        (* 周期窗无需手动复位：tonInterval 的 IN := NOT Q 自复位，下一拍自动重走一窗（R188） / The interval window self-restarts, no manual reset *)
        _fLevelAtStart := fLevelPct;                                     // 锁存起始水位（唯一写入点） / Latch the start level
        _bSnapshotOk := TRUE;                                            // 快照有效 / Snapshot valid
        _eState := E_DL_BbsState.eOpen;                                  // 进排污相 / Enter blowdown phase
    ELSIF _bFault THEN                                                   // 出口 3：故障锁存 / Fault latched
        _eState := E_DL_BbsState.eFault;
    END_IF

E_DL_BbsState.eOpen:
    IF tonBlow.Q THEN                                                    // 出口 1：排污时长到 / Blowdown time elapsed
        _eState := E_DL_BbsState.eSettle;
    ELSIF bLevelLow THEN                                                 // 出口 2：水位转低（前置消失，R98；故障由段 2 置） / Level low during blowdown
        _eState := E_DL_BbsState.eFault;
    END_IF

E_DL_BbsState.eSettle:
    IF tonSettle.Q THEN                                                  // 出口 1：稳定时长到 / Settle time elapsed
        IF _nBlowCount < DL_COUNT_MAX THEN
            _nBlowCount := _nBlowCount + 1;                              // 累计排污次数递增（单点写入） / Cumulative count increment
        END_IF
        _uInfo := 16#0005_04D0;                                          // 信息级：单次排污完成 / Info: one blowdown completed
        _eState := E_DL_BbsState.eDone;
    ELSIF bLevelLow THEN                                                 // 出口 2：稳定期水位转低 / Level low while settling
        _eState := E_DL_BbsState.eIdle;
    END_IF

E_DL_BbsState.eDone:
    IF (NOT bEnable) OR bLevelLow THEN                                   // 出口 1：未使能或水位低，回空闲 / Disabled or level low returns idle
        _eState := E_DL_BbsState.eIdle;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_BbsState.eFault;
    END_IF

E_DL_BbsState.eFault:
    ;                                                                     // 故障相：仅段 3 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _uFault := 16#0005_03A8;                                             // 故障级：非法相位兜底（归并总码） / Illegal-phase fallback
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_BbsCause.ePhaseBad;                                  // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_BbsState.eFault;

END_CASE

(* —— 段 5：出口单点映射（名实同源；锁存码回放；阀安全侧） —— *)
IF _bFault OR _bCfgBad OR (NOT bEnable) OR bLevelLow THEN
    bValveCmd := FALSE;                                                  // 故障/组态非法/失能/低水位：阀恒关 / Valve forced closed
ELSE
    bValveCmd := (_eState = E_DL_BbsState.eOpen);                        // 仅排污相开阀 / Valve open only in the blowdown phase
END_IF
IF _bFault THEN
    nErrId := _uFault;                                                   // 故障锁存码回放 / Replay latched fault code
ELSE
    nErrId := _uInfo;                                                    // 信息码 / Info code
END_IF
bError := _bFault;                                                       // 故障标志与锁存同源（名实双出口，R191） / Flag from latch
eState := _eState;                                                       // 状态出口 / State outlet
eCause := _eCause;                                                       // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
