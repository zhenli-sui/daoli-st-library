(*==============================================================================
 * 组件名称 (Component)  : FB_DL_StictionCompensator
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS / MIN / MAX），零厂商私有库
 * 功能描述 (Function)   : 阀门/执行器黏滞（stiction）在线补偿。三件事：
 *                         ① 死区宽度在线估计：指令变化量超过 fDeadbandMin 而位置几乎不动
 *                         〔|ΔfPos| < fEps〕时，判定指令被死区吃掉，按 fDbStepUp 逐步增大
 *                         死区估计 _fDbEst；位置恢复跟随（即指令与位置重新同向变化）后按
 *                         fDbDecay 慢速衰减，避免把一次扰动永久记成死区；
 *                         ② 突破补偿：指令发生超门限变化时，在指令方向叠加等于当前死区估计的
 *                         偏置，帮助执行器越过静摩擦；
 *                         ③ 脉动叠加（dither）：以 tDitherPeriod 为半周期翻转方向，幅值按
 *                         死区估计比例缩放（估计越小脉动越小），防持续大脉动加速阀杆磨损。
 * 分工声明 (Scope)      : 与 `FB_DL_ValveStictionDetect`（Device 子库）分工 —— 本件**只做补偿**，
 *                         不做诊断、不做分级、不引用 NE107 枚举；诊断与分级属主为该件。
 * 接口     (Interface)  : 输入 fCmd / fPos 指令与位置、fEps 位置微动阈值、fDeadbandMin 指令
 *                         变化门限、fDbMax 死区估计上限、fDbStepUp 每拍增量、fDbDecay 每拍
 *                         衰减量、fDitherAmp 脉动幅值上限、tDitherPeriod 脉动周期、fCompLimit
 *                         补偿量绝对硬限、bEnable 使能、bReset 复位；输出 fCmdOut 补偿后指令、
 *                         fDbEst 死区估计（供 HMI 趋势）、bCompActive 补偿生效位、eState /
 *                         eCause / bError / nErrId。
 * 边界     (Boundary)   : ① **补偿量绝对钳位**：|fCmdOut − fCmd| <= fCompLimit 为硬限（防补偿把
 *                         阀门推到危险位），超限即钳位并置信息级；
 *                         ② 死区估计达 fDbMax → 冻结不再增长并置维护级信息 —— **不是故障**：
 *                         死区变大是填料磨损趋势，报故障会导致整机停机掩盖趋势信息；
 *                         ③ 组态闸：fDitherAmp <= 0、tDitherPeriod <= T#0S、fCompLimit <= 0.0、
 *                         fDbMax <= 0.0、fDbStepUp <= 0.0、fDbDecay <= 0.0、fEps <= 0.0
 *                         任一成立 → 故障锁存（每个参与判据的引脚都在闸内，R151）；
 *                         ④ 脉动方向用 TON 单拍沿翻转实现，**不使用 MOD**（负数取余三平台
 *                         不一致，R10/R48 铁律），故无负取模与相位回绕路径；
 *                         ⑤ TON 一枚 + R_TRIG 一枚段 0 无条件周期刷新；
 *                         ⑥ 故障相迁出唯一路径 = bReset 上升沿；⑦ 零全局耦合（无 GVL / 无物理地址）。
 * 输出语义 (Fallback)   : 【R191 声明】bEnable = FALSE → 输出**直通** fCmd（补偿量清零，不冻结），
 *                         死区估计保持末值；eFault 相 → 输出**直通** fCmd 且补偿量强制 0
 *                         （安全侧：故障时不做任何指令改写，避免故障叠加补偿误动作）。
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 ∧ 当拍补偿量在硬限内（|Δ| <= fCompLimit，
 *                         当拍量，R240 范式）。自证可满足（终审两式 1）：解除式不含计时器输出，
 *                         死区估计冻结或衰减后补偿量必回落到硬限内，无恒假因子。
 * 码表     (Codes)      : 16#0002_03B1 故障级：黏滞补偿故障总码（组态非法 / 输入非有限 / 非法相位），
 *                         锁存至 bReset 上升沿，归因由 eCause 承载（R190 单件单总码）；
 *                         16#0002_04B4 信息级：非故障台账事件（补偿量触硬限钳位 / 死区估计冻结）。
 *                         加码反证（R90）：两个事件都不改变 bCompActive 终值（钳位后补偿仍生效、
 *                         冻结后补偿仍按上限执行），若不立码则台账上「补偿长期贴着硬限跑」
 *                         与「死区估计已冻结」均不可观测，故立一码；二者共用一码的依据是
 *                         「都只要求留痕不要求区分动作」，区分由 fDbEst 是否等于 fDbMax 反推。
 *                         码段说明：0002 段故障子带 03xx / 信息子带 04xx，本件取 03B1 / 04B4
 *                         （源码实扫该两槽为空，续接同子带已用最大值，未回填碎片孔洞）。
 * 开源溯源 (Origin)     : 道莅自研 clean-room（参考阀门死区估计与 dither 公开参数域，
 *                         零代码行复制；t2-5-modpid 参数域族）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R45 首版（批次 2 · 序号 7）
 *==============================================================================*)

TYPE E_DL_StcState :
(
    eIdle  := 0,     // 失能待使能（指令直通） / Idle, disabled, command pass-through
    eRun   := 10,    // 补偿运行 / Compensation running
    eFault := 90     // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_StcCause :
(
    eNone       := 0,   // 无故障成因 / No cause
    eCfgIllegal := 1,   // 组态非法 / Illegal configuration
    eNonFinite  := 2,   // 输入非有限 / Non-finite input
    ePhaseBad   := 3    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_StictionCompensator
VAR_INPUT
    fCmd          : REAL := 0.0;        // 原始指令，有效域 0.0 ~ 100.0 [%] / Raw command, domain 0.0..100.0 [%]
    fPos          : REAL := 0.0;        // 实际位置反馈，有效域 0.0 ~ 100.0 [%] / Actual position feedback [%]
    fEps          : REAL := 0.05;       // 位置微动阈值（判「几乎不动」），域 > 0.0 [%] / Position micro-motion threshold, domain > 0.0 [%]
    fDeadbandMin  : REAL := 0.30;       // 指令变化门限（判「指令已动」），域 > 0.0 [%] / Command change threshold, domain > 0.0 [%]
    fDbMax        : REAL := 5.0;        // 死区估计上限，域 > 0.0 [%] / Deadband estimate ceiling, domain > 0.0 [%]
    fDbStepUp     : REAL := 0.01;       // 死区估计每拍增量，域 > 0.0 [%/拍] / Deadband estimate increment per scan [%/scan]
    fDbDecay      : REAL := 0.002;      // 死区估计每拍衰减量，域 > 0.0 [%/拍] / Deadband estimate decay per scan [%/scan]
    fDitherAmp    : REAL := 0.20;       // 脉动幅值上限，域 > 0.0 [%] / Dither amplitude ceiling, domain > 0.0 [%]
    tDitherPeriod : TIME := T#200MS;    // 脉动半周期（方向翻转间隔），域 > T#0S [ms] / Dither half period, domain > T#0S [ms]
    fCompLimit    : REAL := 3.0;        // 补偿量绝对硬限，域 > 0.0 [%] / Absolute compensation hard limit, domain > 0.0 [%]
    bEnable       : BOOL := TRUE;       // 补偿使能，FALSE 时指令直通 [-] / Enable, FALSE passes command through
    bReset        : BOOL := FALSE;      // 复位命令，上升沿清故障 [-] / Reset command, rising edge clears fault
END_VAR
VAR_OUTPUT
    fCmdOut       : REAL;               // 补偿后指令（已过硬限与 0~100% 钳位） [%] / Compensated command, clamped [%]
    fDbEst        : REAL;               // 死区估计值（供 HMI 趋势） [%] / Deadband estimate for HMI trending [%]
    bCompActive   : BOOL;               // 补偿生效位 [-] / Compensation active flag
    eState        : E_DL_StcState;      // 状态出口，段 6 单点映射 / State outlet
    eCause        : E_DL_StcCause;      // 故障成因出口（R190 归因唯一） / Fault cause outlet
    bError        : BOOL;               // 故障锁存标志 [-] / Fault latch flag
    nErrId        : UDINT;              // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    _eState       : E_DL_StcState := E_DL_StcState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause       : E_DL_StcCause := E_DL_StcCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    tonPhase      : TON;                // 脉动相位计时（自复位），段 0 无条件调用 / Dither phase timer, self-resetting
    rtReset       : R_TRIG;             // 复位沿实例，段 0 无条件调用 / Reset edge
    _fDbEst       : REAL;               // 死区估计（锁存量） [%] / Deadband estimate, latched
    _fCmdPrev     : REAL;               // 上拍指令快照（锁存量） [%] / Previous-scan command snapshot
    _fPosPrev     : REAL;               // 上拍位置快照（锁存量） [%] / Previous-scan position snapshot
    _bDitherDir   : BOOL;               // 脉动方向（锁存量），TRUE 正向 / Dither direction, latched
    _bFrozen      : BOOL;               // 死区估计冻结标记（锁存量） [-] / Deadband estimate frozen flag
    _fDither      : REAL;               // 本拍脉动偏置 [%] / Dither offset this scan
    _fComp        : REAL;               // 本拍突破补偿偏置 [%] / Breakaway compensation bias this scan
    _fDev         : REAL;               // 补偿后与原始指令之差 [%] / Deviation between compensated and raw command
    _fRaw         : REAL;               // 钳位前输出 [%] / Pre-clamp output
    _bNonFin      : BOOL;               // 输入非有限当拍量 [-] / Non-finite input this scan
    _bCfgBad      : BOOL;               // 组态非法当拍量 [-] / Illegal configuration
    _bLimitHit    : BOOL;               // 补偿量触硬限当拍量 [-] / Compensation hard limit reached
    _bFault       : BOOL;               // 故障锁存位（锁存量） / Latched fault bit
    _uFault       : UDINT;              // 故障码锁存（锁存量） / Latched fault code
    _uInfo        : UDINT;              // 信息码，每拍重算 / Info code, recomputed each scan
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS : REAL := 1.0E-6;      // 浮点判零容差（除子与判据统一口径） [%] / Float epsilon for zero tests [%]
    DL_CMD_MAX   : REAL := 100.0;       // 指令域上限 [%] / Command domain upper bound [%]
    DL_CMD_MIN   : REAL := 0.0;         // 指令域下限 [%] / Command domain lower bound [%]
END_VAR

(* —— 段 0：当拍判据派生 + 定时器与沿实例无条件周期刷新 —— *)
_bNonFin := (fCmd <> fCmd) OR (fPos <> fPos) OR (fEps <> fEps) OR (fDeadbandMin <> fDeadbandMin)   // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive tests
         OR (fDbMax <> fDbMax) OR (fDitherAmp <> fDitherAmp) OR (fCompLimit <> fCompLimit);        // 关键参数 NaN 判 / Key parameter NaN tests
_bCfgBad := (fEps <= 0.0) OR (fDeadbandMin <= 0.0) OR (fDbMax <= 0.0) OR (fDbStepUp <= 0.0)       // 组态域闸（正域，R151 全覆盖） / Positive-domain config gate
            OR (fDbDecay <= 0.0) OR (fDitherAmp <= 0.0) OR (fCompLimit <= 0.0)                     // 脉动与硬限正域闸 / Dither and hard-limit gate
            OR (tDitherPeriod <= T#0S);                                                             // 脉动周期正域闸 / Period gate
rtReset(CLK := bReset);                                                                             // 复位沿，每拍必调（R228A） / Reset edge
tonPhase(IN := NOT tonPhase.Q, PT := tDitherPeriod);                                                // 脉动相位自复位计时（R188） / Self-resetting dither phase timer

(* —— 段 1：单拍量预清零（锁存量与快照量不入清单，R107） —— *)
_uInfo      := 16#0000_0000;       // 信息码每拍重算 / Info recomputed every scan
bCompActive := FALSE;              // 补偿生效位每拍预清 / Compensation active preset
fCmdOut     := fCmd;               // 输出缺省直通指令（安全侧） / Output defaults to raw command
nErrId      := 16#0000_0000;       // 事件码缺省无事件 / Event code default none
bError      := FALSE;              // 故障标志每拍预清，故障分支同拍置位（R45 配对） / Flag preset
_bLimitHit  := FALSE;              // 触限标记每拍预清 / Limit-hit marker preset

(* —— 段 2：复位沿 + 组态域闸 + 非有限闸 —— *)
IF rtReset.Q THEN                                                        // 当拍复位沿 / current-scan reset edge
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_StcCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
    IF _eState = E_DL_StcState.eFault THEN
        _eState := E_DL_StcState.eIdle;                                  // 故障相迁出唯一路径 / Sole exit from fault phase
    END_IF
END_IF
IF _bCfgBad THEN                                                         // 组态域闸 / Configuration gate
    _uFault := 16#0002_03B1;                                             // 故障级：黏滞补偿故障总码 / Fault-level: compensator fault code
    _bFault := TRUE;
    bError  := TRUE;                                                     // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_StcCause.eCfgIllegal;                                // 归因：组态非法 / Cause: illegal configuration
END_IF
IF (NOT _bFault) AND _bNonFin THEN                                       // 输入非有限 / Non-finite input
    _uFault := 16#0002_03B1;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_StcCause.eNonFinite;                                 // 归因：非有限 / Cause: non-finite
END_IF

(* —— 段 3：死区在线估计（指令动而位置不动 → 增大；恢复跟随 → 衰减） —— *)
IF (NOT _bFault) AND bEnable THEN
    IF (ABS(fPos - _fPosPrev) < fEps) AND (ABS(fCmd - _fCmdPrev) > fDeadbandMin) THEN   // 指令被死区吃掉 / Command swallowed by deadband
        IF _fDbEst < fDbMax THEN
            _fDbEst := MIN(_fDbEst + fDbStepUp, fDbMax);                 // 逐步增大且不越上限 / Step up with ceiling
            _bFrozen := FALSE;                                           // 解除冻结标记 / Clear frozen flag
        ELSE
            _bFrozen := TRUE;                                            // 达上限冻结（维护级信息，非故障） / Frozen at ceiling, maintenance info
            _uInfo := 16#0002_04B4;                                      // 信息级：死区估计冻结留痕 / Info: estimate frozen
        END_IF
    ELSE
        IF _fDbEst > 0.0 THEN
            _fDbEst := MAX(_fDbEst - fDbDecay, 0.0);                     // 慢速衰减且不越零 / Slow decay with floor
        END_IF
    END_IF
END_IF

(* —— 段 4：脉动方向翻转（TON 单拍沿驱动，禁用 MOD） —— *)
IF tonPhase.Q THEN                                                       // 周期沿（单拍，自复位产生） / Period tick
    _bDitherDir := NOT _bDitherDir;                                      // 方向翻转（布尔取反，无取模） / Flip direction, no modulo
END_IF

(* —— 段 5：补偿量合成 + 绝对硬限钳位 + 指令域钳位 —— *)
IF (NOT _bFault) AND bEnable THEN
    _fComp := 0.0;                                                       // 突破补偿初值 0 / Breakaway bias default 0
    IF (fCmd - _fCmdPrev) > fDeadbandMin THEN
        _fComp := _fDbEst;                                               // 正向突破补偿 / Positive breakaway bias
    ELSIF (fCmd - _fCmdPrev) < (0.0 - fDeadbandMin) THEN
        _fComp := 0.0 - _fDbEst;                                         // 负向突破补偿 / Negative breakaway bias
    END_IF
    IF fDbMax > DL_FLOAT_EPS THEN                                        // 除零前置判 / Divide-by-zero guard
        _fDither := fDitherAmp * (_fDbEst / fDbMax);                     // 脉动幅值按死区估计比例缩放 / Dither scaled by estimate ratio
    ELSE
        _fDither := 0.0;                                                 // 退化兜底（组态闸已拦，防御纵深） / Degenerate guard
    END_IF
    IF _fDither > fDitherAmp THEN                                        // 双侧钳位（上侧） / Two-sided clamp, upper
        _fDither := fDitherAmp;
    END_IF
    IF _fDither < 0.0 THEN                                               // 双侧钳位（下侧） / Two-sided clamp, lower
        _fDither := 0.0;
    END_IF
    IF NOT _bDitherDir THEN
        _fDither := 0.0 - _fDither;                                      // 反向脉动（取负不用取反运算符） / Negative dither half period
    END_IF
    _fRaw := fCmd + _fComp + _fDither;                                   // 补偿后指令（钳位前） / Pre-clamp compensated command
    _fDev := _fRaw - fCmd;                                               // 补偿偏差 / Compensation deviation
    IF _fDev > fCompLimit THEN                                           // 硬限（上侧） / Hard limit, upper
        _fRaw := fCmd + fCompLimit;
        _bLimitHit := TRUE;
    ELSIF _fDev < (0.0 - fCompLimit) THEN                                // 硬限（下侧） / Hard limit, lower
        _fRaw := fCmd - fCompLimit;
        _bLimitHit := TRUE;
    END_IF
    IF _bLimitHit THEN
        _uInfo := 16#0002_04B4;                                          // 信息级：补偿量触硬限钳位留痕 / Info: hard limit clamp recorded
    END_IF
    IF _fRaw > DL_CMD_MAX THEN                                           // 指令域上限钳位 / Command domain upper clamp
        fCmdOut := DL_CMD_MAX;
    ELSIF _fRaw < DL_CMD_MIN THEN                                        // 指令域下限钳位 / Command domain lower clamp
        fCmdOut := DL_CMD_MIN;
    ELSE
        fCmdOut := _fRaw;                                                // 域内直通 / Pass through
    END_IF
    IF ABS(fCmdOut - fCmd) > DL_FLOAT_EPS THEN                           // 存在实际改写即判补偿生效 / Compensation effective when output differs
        bCompActive := TRUE;
    END_IF
END_IF

(* —— 段 6：快照更新（主体末行，跨拍累计纪律） —— *)
_fCmdPrev := fCmd;                                                       // 指令快照（本拍末更新） / Command snapshot at body end
_fPosPrev := fPos;                                                       // 位置快照（本拍末更新） / Position snapshot at body end

(* —— 段 7：故障解除式（R240 全当拍量） —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_StcCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
END_IF

(* —— 段 7A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_StcState.eFault) THEN
    _eState := E_DL_StcState.eFault;                                     // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 8：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_StcState.eIdle:
    IF bEnable AND (NOT _bFault) THEN                                    // 出口 1：使能 / Enabled
        _eState := E_DL_StcState.eRun;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_StcState.eFault;
    END_IF

E_DL_StcState.eRun:
    IF (NOT bEnable) THEN                                                // 出口 1：失能（前置消失，R98） / Disabled
        _eState := E_DL_StcState.eIdle;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_StcState.eFault;
    END_IF

E_DL_StcState.eFault:
    ;                                                                     // 故障相：仅段 7 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _uFault := 16#0002_03B1;                                             // 故障级：非法相位兜底（归并总码） / Illegal-phase fallback
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_StcCause.ePhaseBad;                                  // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_StcState.eFault;

END_CASE

(* —— 段 9：出口单点映射（名实同源；锁存码回放；故障相安全侧） —— *)
IF _bFault THEN
    fCmdOut     := fCmd;                                                 // 故障相直通原始指令（不改写，安全侧） / Fault passes raw command untouched
    bCompActive := FALSE;                                                // 故障相补偿不生效 / Compensation inactive in fault
ELSIF NOT bEnable THEN
    fCmdOut     := fCmd;                                                 // 失能直通（R191 声明） / Disabled pass-through
    bCompActive := FALSE;                                                // 失能相不生效 / Inactive when disabled
END_IF
fDbEst := _fDbEst;                                                       // 死区估计出口（锁存量回放） / Deadband estimate outlet
IF _bFault THEN
    nErrId := _uFault;                                                   // 故障锁存码回放 / Replay latched fault code
ELSE
    nErrId := _uInfo;                                                    // 信息码 / Info code
END_IF
bError := _bFault;                                                       // 故障标志与锁存同源（名实双出口，R191） / Flag from latch
eState := _eState;                                                       // 状态出口 / State outlet
eCause := _eCause;                                                       // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
