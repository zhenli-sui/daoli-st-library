(*==============================================================================
 * 组件名称 (Component)  : FB_DL_RateOfChangeFilter
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（ABS / MIN / MAX / TIME_TO_REAL），零厂商私有库
 * 功能描述 (Function)   : 变化率限幅滤波（斜坡限速）。每周期允许的最大增量
 *                         fMaxStep = fMaxRate × fDt（fDt 由 tSampleTime 显式给定），
 *                         输出增量被钳制在 ±fMaxStep 内：
 *                           fOut := fOut + LIMIT(fIn - fOut, -fMaxStep, +fMaxStep)
 *                         作用：抑制阶跃冲击（传感器跳变、通信坏包、量程切换瞬态），
 *                         保护下游执行机构与 PID 微分项，同时不引入一阶滞后（稳态无误差）。
 *                         与低通滤波的本质差别：本件**稳态增益恒为 1、无相位滞后**，
 *                         只在斜率上设限；阶跃会被摊成斜坡而非指数逼近。
 * 接口     (Interface)  : 输入 bEnable 使能、bReset 复位输出到当前输入、fIn 采样输入 [EU]、
 *                         fMaxRate 最大变化率 [EU/s]、tSampleTime 采样周期 [s]；
 *                         输出 fOut 限幅输出 [EU]、fMaxStep 本拍允许最大增量 [EU]、
 *                         bLimited 本拍是否发生限幅、bValid 输出有效、bError、uErrorId。
 * 边界     (Boundary)   : ① 属主边界：只做斜率限幅，不做低通 / 中值 / 死区（另件）。
 *                         ② 非有限防御覆盖 **fIn 与 fMaxRate 两个浮点入参**（漏一个即该判据静默失效）。
 *                         ③ 除零/非法参数防护：fMaxRate <= 0 → 故障级 16#0005_0003（不静默当 0 处理，
 *                         否则输出会被永久冻结而现场看不出原因）；tSampleTime < 10MS →
 *                         钳到 10MS 并置信息码 16#0005_0001。
 *                         ④ 复位语义：bReset=TRUE 当拍 fOut := fIn 且不计限幅，恢复无爬升。
 *                         ⑤ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_LowPassFilter` 分工：一阶惯性与相位滞后归那件、
 *                         纯斜率限幅归本件；与 `FB_DL_GatedUpdateFilter` 分工：门控归那件。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 16#0005_0000 无故障 / 16#0005_0001 采样周期非法已钳位（信息级）/
 *                         16#0005_0002 输入非有限（故障级）/ 16#0005_0003 变化率非法（故障级）/
 *                         16#0005_0005 非法状态（故障级）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 双浮点入参非有限判 + 变化率域闸 + 周期下限钳位 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ 四态 ENUM + CASE + ELSE 兜底 ｜ R7 N/A（无 TON / 边沿实例）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B3 · 序号 11）
 * 验收向量 (Acceptance) : ① fMaxRate=10, tSampleTime=T#100MS（fDt=0.1s）→ fMaxStep=1.0，
 *                         阶跃 0→100：第 1 拍 fOut=1.0、第 2 拍 fOut=2.0，bLimited=TRUE；
 *                         ② 稳态后 fIn 恒 100 → fOut 追到 100.0 时 bLimited=FALSE，无稳态误差；
 *                         ③ fMaxRate=0 → uErrorId=16#0005_0003，bError=TRUE，fOut 冻结；
 *                         ④ tSampleTime=T#1MS → 钳到 0.01s，uErrorId=16#0005_0001（不置 bError）；
 *                         ⑤ bReset=TRUE 一拍 → fOut 立即等于 fIn。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_RocState（变化率限幅状态机，归属 DL_Algo，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_RocState :
(
    eInit  := 0,    // 首扫 / 复位后：输出直取输入 / First scan or after reset: output follows input
    eRun   := 10,   // 运行态：按 fMaxStep 限幅 / Running: rate-limited stepping
    eHold  := 20,   // 保持态：未使能，输出冻结 / Hold: disabled, output frozen
    eFault := 99    // 故障态：输出冻结，等待 bEnable 跌落或 bReset / Fault: frozen until cleared
);
END_TYPE

FUNCTION_BLOCK FB_DL_RateOfChangeFilter
VAR_INPUT
    bEnable     : BOOL := FALSE;     // 使能，FALSE 冻结输出 / Enable, FALSE freezes output
    bReset      : BOOL := FALSE;     // 复位到当前输入（单拍有效） / Reset to current input, single scan
    fIn         : LREAL := 0.0;      // 采样输入 [EU] / Sampling input [EU]
    fMaxRate    : LREAL := 1.0;      // 最大变化率，必须 > 0 [EU/s] / Max rate of change, must be positive [EU/s]
    tSampleTime : TIME := T#100MS;   // 采样周期 [s]，小于 10ms 钳位 / Sampling period, clamped to 10ms
END_VAR
VAR_OUTPUT
    fOut     : LREAL;   // 限幅输出 [EU] / Rate-limited output [EU]
    fMaxStep : LREAL;   // 本拍允许最大增量 [EU] / Maximum allowed step this scan [EU]
    bLimited : BOOL;    // 本拍是否发生限幅 [-] / Whether limiting occurred this scan
    bValid   : BOOL;    // 输出有效标志 [-] / Output valid flag
    bError   : BOOL;    // 故障标志，与 uErrorId 联动 [-] / Fault flag coupled with uErrorId
    uErrorId : UDINT;   // 故障码，0 = 无故障 [-] / Error code, zero means healthy
END_VAR
VAR
    _fDt      : LREAL;         // 生效采样周期秒值 [s] / Effective sampling period in seconds
    _fDelta   : LREAL;         // 输入与输出的偏差 [EU] / Deviation between input and output
    _fStep    : LREAL;         // 本拍实际步进（已钳位） [EU] / Actual clamped step [EU]
    _bNonFin  : BOOL;          // 入参非有限标志 [-] / Non-finite input flag
    eState    : E_DL_RocState; // 状态机当前状态 [-] / Current state
END_VAR
VAR CONSTANT
    DL_ROC_DT_MIN  : LREAL := 0.01;     // 采样周期防御下限 [s] / Defensive sampling period floor [s]
    DL_ROC_ZERO    : LREAL := 0.0;      // 零基准（含非有限判零） [-] / Zero base including non-finite probe
    DL_ROC_MS      : LREAL := 1000.0;   // 毫秒转秒因子 [ms/s] / Milliseconds per second
END_VAR

(* —— 段 1：采样周期域闸（不中断扫描，只钳位并置信息码） —— *)
uErrorId := 16#0005_0000;                          // 预置无故障 / Preset healthy
IF tSampleTime < T#10MS THEN
    _fDt     := DL_ROC_DT_MIN;                     // 周期过小钳位 / Too small period clamped
    uErrorId := 16#0005_0001;                      // 信息级：采样周期已钳位 / Info: period clamped
ELSE
    _fDt := TIME_TO_REAL(tSampleTime) / DL_ROC_MS; // TIME 换算秒值 / Convert to seconds
END_IF

(* —— 段 2：非有限防御（fIn 与 fMaxRate 逐一枚举，禁止漏闸） —— *)
_bNonFin := (fIn <> fIn) OR ((fIn - fIn) <> DL_ROC_ZERO);            // 输入非有限 / Input non-finite
_bNonFin := _bNonFin OR (fMaxRate <> fMaxRate) OR ((fMaxRate - fMaxRate) <> DL_ROC_ZERO);  // 变化率非有限
IF _bNonFin THEN
    eState   := eFault;                            // 强制故障态 / Force fault state
    uErrorId := 16#0005_0002;                      // 故障级：入参非有限 / Fault: non-finite input
END_IF

(* —— 段 3：变化率域闸（必须严格为正，否则限幅无意义且输出会被永久冻结） —— *)
IF fMaxRate <= DL_ROC_ZERO THEN
    eState   := eFault;                            // 参数非法进故障态 / Illegal parameter goes to fault
    uErrorId := 16#0005_0003;                      // 故障级：变化率非法 / Fault: illegal rate
    fMaxStep := DL_ROC_ZERO;                       // 步长出口回 0（诊断量仍可读） / Step outlet zeroed
END_IF

(* —— 段 4：复位请求 → 回首扫 —— *)
IF bReset THEN
    eState := eInit;
END_IF

(* —— 段 5：状态派生 —— *)
IF NOT bEnable THEN
    eState := eHold;                               // 未使能：冻结 / Disabled: freeze
ELSIF eState = eFault THEN
    eState := eFault;                              // 故障态保持 / Fault holds
ELSIF eState = eInit THEN
    eState := eInit;                               // 首扫保持一拍 / Init holds one scan
ELSE
    eState := eRun;
END_IF

(* —— 段 6：主状态机（CASE 覆盖 + ELSE 兜底） —— *)
CASE eState OF

    eInit:
        fOut     := fIn;                           // 首拍直取输入，无历史瞬态 / First scan follows input
        fMaxStep := fMaxRate * _fDt;               // 步长按当前参数计算 / Step from current parameters
        bLimited := FALSE;
        bValid   := TRUE;
        eState   := eRun;

    eRun:
        fMaxStep := fMaxRate * _fDt;               // 本拍允许最大增量 [EU] / Maximum step this scan
        _fDelta  := fIn - fOut;                    // 偏差 / Deviation
        IF _fDelta > fMaxStep THEN
            _fStep   := fMaxStep;                  // 正向限幅 / Positive limiting
            bLimited := TRUE;
        ELSIF _fDelta < (DL_ROC_ZERO - fMaxStep) THEN
            _fStep   := DL_ROC_ZERO - fMaxStep;    // 负向限幅 / Negative limiting
            bLimited := TRUE;
        ELSE
            _fStep   := _fDelta;                   // 未超限：直接跟上（稳态无误差） / Within limit: track directly
            bLimited := FALSE;
        END_IF
        fOut   := fOut + _fStep;                   // 斜坡推进 / Ramp forward
        bValid := TRUE;

    eHold:
        (* 未使能：输出与步长诊断量保持上拍值 / Disabled: output and step diagnostics frozen *)
        bValid := FALSE;

    eFault:
        (* 故障态：输出冻结保持上拍值（不推 0，避免下游误判为真实零） / Fault: output frozen *)
        bValid := FALSE;

    ELSE
        eState   := eFault;
        bValid   := FALSE;
        fMaxStep := DL_ROC_ZERO;
        uErrorId := 16#0005_0005;                  // 故障级：非法状态 / Fault: illegal state

END_CASE;

(* —— 段 7：出口结果复检（非有限兜底，名实双出口） —— *)
IF (fOut <> fOut) OR ((fOut - fOut) <> DL_ROC_ZERO) THEN
    eState   := eFault;                            // 结果异常进故障态 / Abnormal result goes to fault
    bValid   := FALSE;
    uErrorId := 16#0005_0002;                      // 故障级码 / Fault-level code
END_IF
bError := (uErrorId <> 16#0005_0000) AND (uErrorId <> 16#0005_0001);   // 信息级不置 bError / Info level excluded

END_FUNCTION_BLOCK
