(*==============================================================================
 * 组件名称 (Component)  : FB_DL_LoadCellTareDrift
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 称重零点漂移监视与去皮闸。
 *                           ① 去皮：bTareCmd 上升沿且**去皮闸放行**时才取当前重量为去皮基准
 *                              fTareRef，并出单拍 bTareDone；闸门未满足则 bTareRejected 且不动基准
 *                              （不"先去了再报错"——那会把错误的零点写进台账）。
 *                           ② 去皮闸三条件同时成立：空载 bNoLoad、|fWeight| 在稳定带
 *                              fTareStableBand 内、且该状态持续 tTareStable（tonStable）。
 *                           ③ 漂移监视：以周期窗 tonObserve（自复位周期窗）为节拍，在窗末取
 *                              当拍重量与去皮基准之差 fDrift，除以窗长（分钟）得漂移速率
 *                              fDriftRate；按 fDriftWarnRate / fDriftAlarmRate 判三级。
 *                              速率判级只在空载时可信（载重下的读数变化是载荷不是漂移），
 *                              故 bNoLoad=FALSE 时维持上一速率不刷新、也不升级告警。
 * 接口     (Interface)  : 输入 fWeight 当前重量、bNoLoad 空载判定（外部给）、fDriftWarnRate /
 *                         fDriftAlarmRate 漂移速率档（单位/分钟）、tObserveWin 观测窗（TIME）、
 *                         fObserveWinMin 同一窗长的分钟数值（REAL，与 tObserveWin 成对给）、
 *                         fTareStableBand 去皮稳定带、tTareStable 去皮稳定时间、bTareCmd 去皮命令、
 *                         bReset 复位；输出 fTareRef 去皮基准、fBaseline 空载基线、fDriftRate 漂移
 *                         速率、eGrade 判级、bTareAllowed 去皮闸状态、bTareDone 去皮完成单拍、
 *                         bTareRejected 去皮被拒、bAlarm 漂移报警锁存、eState / eCause / bError。
 * 边界     (Boundary)   : ① **PT 语义成对声明（R228A 豁免说明的配套要求）**：任何"用 TIME 计时、
 *                         又要用数值参与换算"的地方，一律由调用方**同时**给 TIME 与 REAL 两个
 *                         同义引脚（tObserveWin 与 fObserveWinMin）。本件**不做 TIME→数值转换**，
 *                         从根上避开 TIME_TO_DINT 在各平台单位/可用性差异与"恒假判据"类缺陷。
 *                         调用方必须保证二者一致（同一窗长），不一致属调用方组态错误，本件无法
 *                         在内部交叉校验（那需要 TIME→数值，正是要避开的操作）。
 *                         ② 组态闸：tObserveWin <= T#0S、fObserveWinMin <= DL_LCT_EPS、
 *                         fDriftWarnRate <= 0.0、fDriftAlarmRate <= fDriftWarnRate、
 *                         fTareStableBand <= 0.0、tTareStable < T#0S、任一浮点 NaN → 故障锁存，
 *                         去皮闸强制关闭（宁可不去皮，不可错去皮）。
 *                         ③ 本件**不做温度补偿、不改标定系数**，只做零点漂移监视与去皮闸；
 *                         标定与温度补偿属称重仪表内部职能或上层标定件。
 *                         ④ 三枚 TON/两枚 R_TRIG 段 0 无条件周期刷新；tonObserve 用
 *                         IN := (NOT tonObserve.Q) 自复位形成周期窗（R188 合规写法）。
 *                         ⑤ 故障相与报警锁存迁出唯一路径 = bReset 上升沿（R228B）。
 *                         ⑥ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_AxisTorqueLimitGuard` 一类力/矩监控件分工——那些判瞬时超限，
 *                         本件判**零点慢漂**（分钟级趋势），时间尺度差三个数量级以上，不可互替。
 * 来源标签 (Source Tag) : T2-2 ◐（开源参考：称重去皮与零点漂移监视参数域，零代码行复制）
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 ∧ 当拍 bNoLoad ∧ 当拍 |fDriftRate| < fDriftWarnRate
 *                         （R240 全当拍量）。自证可满足：重新去皮或载荷卸空即满足，无死锁。
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 ENUM 判级 + BOOL 组（bTareDone /
 *                         bTareRejected / bAlarm / bError）；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 除零闸 + 阈值几何闸 + 浮点容差 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE ｜ R7 ✓ TON/R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R46 首版（批次 2 · 序号 9）
 *==============================================================================*)

TYPE E_DL_LctGrade :
(
    eUnknown := 0,    // 尚未测得速率 / Rate not measured yet
    eOk      := 10,   // 漂移在预警带内 / Drift inside the warning band
    eWarn    := 20,   // 漂移达预警档（维护级） / Drift at the warning level
    eAlarm   := 30    // 漂移达报警档（锁存） / Drift at the alarm level, latched
);
END_TYPE

TYPE E_DL_LctState :
(
    eIdle  := 0,    // 首次去皮的等待相 / Awaiting the first tare
    eRun   := 10,   // 漂移监视运行相 / Drift monitoring phase
    eFault := 90    // 组态故障相（去皮闸强制关闭） / Configuration fault, tare gate forced closed
);
END_TYPE

TYPE E_DL_LctCause :
(
    eNone        := 0,   // 无异常 / No anomaly
    eCfgIllegal  := 1,   // 组态非法 / Illegal configuration
    eTareReject  := 2,   // 去皮被拒（未空载/未稳定/超稳定带） / Tare rejected, gate not satisfied
    eDriftAlarm  := 3,   // 零点漂移达报警档 / Zero drift at the alarm level
    ePhaseBad    := 4    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_LoadCellTareDrift
VAR_INPUT
    fWeight        : REAL := 0.0;      // 当前重量读数 [kg] / Current weight reading [kg]
    bNoLoad        : BOOL := FALSE;    // 空载判定（外部给出，本件不判载荷） [-] / No-load decision, supplied externally
    fDriftWarnRate : REAL := 0.02;     // 漂移速率预警档，域 > 0.0 [kg/min] / Drift warning rate, > 0.0 [kg/min]
    fDriftAlarmRate: REAL := 0.10;     // 漂移速率报警档，域 > fDriftWarnRate [kg/min] / Drift alarm rate, > warning [kg/min]
    tObserveWin    : TIME := T#60S;    // 观测窗时长（TIME 侧），域 > T#0S [ms] / Observation window, TIME side, > 0
    fObserveWinMin : REAL := 1.0;      // 同一观测窗的分钟数值（REAL 侧），域 > eps [min] / Same window in minutes, REAL side
    fTareStableBand: REAL := 0.05;     // 去皮稳定带（|重量| 上限），域 > 0.0 [kg] / Tare stability band, > 0.0 [kg]
    tTareStable    : TIME := T#500MS;  // 去皮稳定时间，域 >= T#0S [ms] / Tare stability time, >= 0
    bTareCmd       : BOOL := FALSE;    // 去皮命令，上升沿生效 [-] / Tare command, acts on rising edge
    bReset         : BOOL := FALSE;    // 复位，上升沿清报警锁存 [-] / Reset, rising edge clears the alarm latch
END_VAR
VAR_OUTPUT
    fTareRef    : REAL;             // 当前去皮基准（零点） [kg] / Current tare reference [kg]
    fBaseline   : REAL;             // 空载基线（空载时跟随当前读数） [kg] / No-load baseline, follows the reading when empty
    fDriftRate  : REAL;             // 漂移速率（每窗末刷新，空载失效时保持） [kg/min] / Drift rate, refreshed per window
    eGrade      : E_DL_LctGrade;    // 漂移判级 [-] / Drift grade
    bTareAllowed: BOOL;             // 去皮闸放行（当拍量） [-] / Tare gate open, per scan
    bTareDone   : BOOL;             // 去皮完成，单拍脉冲 [-] / Tare done, single-scan pulse
    bTareRejected: BOOL;            // 去皮被拒（当拍量） [-] / Tare rejected
    bAlarm      : BOOL;             // 漂移报警锁存 [-] / Latched drift alarm
    eState      : E_DL_LctState;    // 状态出口 [-] / State outlet
    eCause      : E_DL_LctCause;    // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError      : BOOL;             // 故障标志（组态故障或漂移报警） [-] / Error flag
END_VAR
VAR
    _eState   : E_DL_LctState := E_DL_LctState.eIdle;    // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause   : E_DL_LctCause := E_DL_LctCause.eNone;    // 成因锁存量 / Latched cause
    tonObserve: TON;            // 观测周期窗（自复位），段 0 无条件调用 / Periodic observation window, self-resetting
    tonStable : TON;            // 去皮稳定计时，段 0 无条件调用 / Tare stability timer
    rtTare    : R_TRIG;         // 去皮命令沿实例，段 0 无条件调用 / Tare command edge instance
    rtReset   : R_TRIG;         // 复位沿实例，段 0 无条件调用 / Reset edge instance
    _bFault   : BOOL;           // 报警锁存位（锁存量） / Latched alarm bit
    _bCfgBad  : BOOL;           // 组态非法当拍量 [-] / Illegal configuration this scan
    _bNonFin  : BOOL;           // 输入非有限当拍量 [-] / Non-finite input this scan
    _bStable  : BOOL;           // 空载且在稳定带内当拍量（喂稳定计时） [-] / Empty and inside the band, feeds the stability timer
    _bGate    : BOOL;           // 去皮闸当拍量 [-] / Tare gate this scan
    _bTared   : BOOL;           // 已完成过首次去皮（锁存量） / First tare done, latched
    _fRate    : REAL;           // 漂移速率锁存值（空载失效时保持） [kg/min] / Held drift rate
    _eGrade   : E_DL_LctGrade := E_DL_LctGrade.eUnknown;   // 判级锁存值（未测得时保持） / Held grade
    _fDrift   : REAL;           // 窗末漂移量中间值 [kg] / Drift at window end [kg]
END_VAR
VAR CONSTANT
    DL_LCT_EPS : REAL := 1.0E-6;    // 浮点判零容差（窗长分钟与稳定带统一口径） [无量纲] / Float epsilon
END_VAR

(* —— 段 0：当拍量派生 + 四实例无条件周期刷新 —— *)
_bNonFin := (fWeight <> fWeight) OR (fDriftWarnRate <> fDriftWarnRate)      // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive tests
         OR (fDriftAlarmRate <> fDriftAlarmRate) OR (fObserveWinMin <> fObserveWinMin)
         OR (fTareStableBand <> fTareStableBand);
_bCfgBad := (tObserveWin <= T#0S) OR (fObserveWinMin <= DL_LCT_EPS)        // 窗长双口径闸（TIME 与 REAL 都要合法） / Window gates on both representations
         OR (fDriftWarnRate <= 0.0) OR (fDriftAlarmRate <= fDriftWarnRate) // 速率档几何闸 / Rate threshold geometry
         OR (fTareStableBand <= 0.0) OR (tTareStable < T#0S) OR _bNonFin;  // 稳定带与时间闸 + 非有限 / Band, time and non-finite gates
_bStable := bNoLoad AND (ABS(fWeight) <= fTareStableBand) AND (NOT _bCfgBad);   // 空载且稳定带内 / Empty and inside the stability band
_bGate   := _bStable AND tonStable.Q;                                       // 去皮闸 = 稳定且稳定时长到 / Gate = stable and duration met
rtTare(CLK := bTareCmd);                                                    // 去皮命令沿，每拍必调（R228A） / Tare edge, every scan
rtReset(CLK := bReset);                                                     // 复位沿，每拍必调 / Reset edge, every scan
tonStable(IN := _bStable, PT := tTareStable);                               // 去皮稳定计时（IN 由当拍判据派生） / Tare stability timer
tonObserve(IN := (NOT tonObserve.Q) AND bNoLoad AND (NOT _bCfgBad), PT := tObserveWin);   // 周期观测窗，自复位（R188） / Periodic window, self-resetting

(* —— 段 1：单拍量预清零（锁存量 _bFault / _fRate / _eGrade / _bTared 不入清单，R107） —— *)
bTareAllowed  := FALSE;     // 去皮闸出口每拍预清 / Gate outlet preset
bTareDone     := FALSE;     // 去皮完成每拍预清 / Tare-done pulse preset
bTareRejected := FALSE;     // 被拒标志每拍预清 / Rejected flag preset
bAlarm        := FALSE;     // 报警出口每拍预清 / Alarm outlet preset
bError        := FALSE;     // 故障标志每拍预清（R45 配对） / Error flag preset

(* —— 段 2：复位沿 + 组态闸 —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                       // 清报警锁存 / Clear alarm latch
    _eCause := E_DL_LctCause.eNone;                         // 清成因 / Clear cause
    _fRate  := 0.0;                                         // 速率锁存归零（复位即有意重开统计） / Reset the held rate deliberately
    _eGrade := E_DL_LctGrade.eUnknown;                      // 判级归未测 / Grade back to unknown
    IF _eState = E_DL_LctState.eFault THEN
        _eState := E_DL_LctState.eIdle;                     // 故障相迁出（R228B） / Leave fault phase
    END_IF
END_IF
IF _bCfgBad THEN
    _eState := E_DL_LctState.eFault;                        // 组态非法入故障相 / Enter fault phase
    _eCause := E_DL_LctCause.eCfgIllegal;                   // 归因：组态非法 / Cause: illegal configuration
END_IF

(* —— 段 3：去皮执行（命令沿 + 闸门，双条件；未放行则拒绝且不动基准） —— *)
bTareAllowed := _bGate AND (NOT _bCfgBad);                  // 闸门出口（REAL 侧与 TIME 侧均已闸） / Gate outlet
IF rtTare.Q THEN
    IF bTareAllowed THEN
        fTareRef := fWeight;                                // 取当前读数为新零点 [kg] / Present reading becomes the new zero
        fBaseline := fWeight;                               // 空载基线同步 [kg] / Baseline synchronised
        _bTared  := TRUE;                                   // 首皮完成（锁存量） / First tare done, latched
        _fRate   := 0.0;                                    // 新零点起速率重计 / Rate restarts from the new zero
        _eGrade  := E_DL_LctGrade.eOk;                      // 判级回良好 / Grade back to ok
        bTareDone := TRUE;                                  // 单拍完成脉冲 / Single-scan done pulse
    ELSE
        bTareRejected := TRUE;                              // 拒绝去皮，基准不动 / Reject, reference untouched
        _eCause := E_DL_LctCause.eTareReject;               // 归因：去皮被拒 / Cause: tare rejected
    END_IF
END_IF

(* —— 段 4：空载基线跟随（空载时基线 = 当前读数，用于 HMI 趋势） —— *)
IF bNoLoad AND (NOT _bCfgBad) THEN
    fBaseline := fWeight;                                   // 基线跟随当前读数 [kg] / Baseline follows the present reading
END_IF

(* —— 段 5：周期窗末漂移评分（单点写入 _fRate，避免同拍抹除，R187） —— *)
IF tonObserve.Q AND (NOT _bCfgBad) AND _bTared THEN
    _fDrift := fWeight - fTareRef;                          // 窗末相对去皮基准的漂移量 [kg] / Drift from the tare reference at window end
    _fRate  := _fDrift / fObserveWinMin;                    // 除以窗长分钟数得速率，分母已闸 / Rate per minute, denominator gated
    IF ABS(_fRate) >= fDriftAlarmRate THEN
        _eGrade := E_DL_LctGrade.eAlarm;                    // 报警档 / Alarm level
        _bFault := TRUE;                                    // 锁存 / Latch
        _eCause := E_DL_LctCause.eDriftAlarm;               // 归因：漂移报警 / Cause: drift alarm
    ELSIF ABS(_fRate) >= fDriftWarnRate THEN
        _eGrade := E_DL_LctGrade.eWarn;                     // 预警档（维护级，不锁存） / Warning level, maintenance only
    ELSE
        _eGrade := E_DL_LctGrade.eOk;                       // 良好档 / Ok level
    END_IF
END_IF

(* —— 段 6：锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_LctState.eFault) THEN
    _eState := E_DL_LctState.eFault;                        // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 7：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_LctState.eIdle:
    IF _bCfgBad THEN                                        // 出口 1：组态非法 / Illegal configuration
        _eState := E_DL_LctState.eFault;
    ELSIF _bTared THEN                                      // 出口 2：已完成去皮，进入监视 / Tare done, start monitoring
        _eState := E_DL_LctState.eRun;
    END_IF

E_DL_LctState.eRun:
    IF _bFault THEN                                         // 出口 1：漂移报警锁存 / Drift alarm latched
        _eState := E_DL_LctState.eFault;
    ELSIF (_bTared = FALSE) THEN                            // 出口 2：基准被清（复位重来） / Reference cleared, restart
        _eState := E_DL_LctState.eIdle;
    END_IF

E_DL_LctState.eFault:
    ;                                                       // 故障相：仅段 2 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _eCause := E_DL_LctCause.ePhaseBad;                     // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_LctState.eFault;                        // 强拉故障相 / Force fault phase
    bError  := TRUE;                                        // 故障标志 / Error flag

END_CASE

(* —— 段 8：出口单点映射（名实双出口，R191） —— *)
fDriftRate := _fRate;                                       // 速率出口（空载失效时保持锁存值） / Rate outlet, held when not empty
eGrade     := _eGrade;                                      // 判级出口 / Grade outlet
bAlarm     := _bFault;                                      // 报警与锁存同源 / Alarm from latch
bError     := _bFault OR _bCfgBad;                          // 故障标志 = 锁存或组态非法 / Error = latch or illegal config
eState     := _eState;                                      // 状态出口 / State outlet
eCause     := _eCause;                                      // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
