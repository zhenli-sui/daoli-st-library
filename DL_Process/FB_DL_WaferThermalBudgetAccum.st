(*==============================================================================
 * 组件名称 (Component)  : FB_DL_WaferThermalBudgetAccum
 * 所属子库 (Sublibrary) : DL_Process
 * 归属目录 (Directory)  : C:\Library\DL_Process
 * 当前版本 (Version)    : 1.0.1
 * 分类/来源标签         : 功能块（FUNCTION_BLOCK）· 半导体热预算 · Arrhenius 积分
 *                         industry-pool / semiconductor / thermal-budget
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 TON / EXP / ABS
 * 溯源声明 (Provenance) : 道莅自研 clean-room——只借公开规范条款与工程惯例，零代码行复制。
 * 功能一句话 (Summary)  : 晶圆热预算累计：温度对时间的 Arrhenius 加权积分
 *                         （归一到参考温度等效秒），超工艺窗口锁存告警。
 *
 * 量纲链（R25 P2 模板）：
 *   输入 fWaferTempC [degC] → 开尔文 T [K] = fWaferTempC + 273.15
 *   权重 w [无量纲] = EXP(fEaOverK × (1/fTRefK − 1/T))，参考温度处 w 恒为 1
 *   预算 fBudgetEqS [s@fTRefC] = Σ(w × Δt)，Δt 由采样节拍定时器导出 [s]
 *   判据 fBudgetEqS 与 fBudgetLimit [s@fTRefC] 同量纲直接比较
 *
 * 功能描述 (Function)   : 三态状态机：空闲/累计/超限锁存。工艺进行中按节拍
 *                         采样温度，每拍把 w × 节拍秒累入预算；温度非物理
 *                         （≤ −273.15 degC 或非有限）报故障冻结累计；预算超
 *                         上限转入超限相锁存告警（故障级 3025），仅复位指令
 *                         可解除（可达解除路径）；复位以信息级 3023 告知。
 * 与既有件边界 (Boundary): 本件只做预算累计与超限告警，不控温；温控归
 *                         工艺温控环，本件是良率保护层。
 * 码位说明 (Codes)      : 信息 16#0006_3023 预算复位执行，锁存告警解除
 *                         故障 16#0006_3024 温度非物理域（≤ −273.15 degC 或非有限）
 *                         故障 16#0006_3025 热预算超工艺窗口，已锁存告警
 *                         段 16#06_0_23~27 首槽信息级、次槽起故障级。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 TON / EXP。
 * 红线自检 (Redline)    : 零全局依赖 ｜ 零 VAR_EXTERNAL ｜ 零 %I/%Q ｜ 纯 IEC 标准库
 *                         NaN/Inf 精确判据拦截 ｜ 浮点比较带 fEps 容差
 *                         ENUM 配 CASE 且 ELSE 兜底 ｜ TON 每周期无条件刷新
 *                         全变量双语同行注释 ｜ 量纲链头注释齐备（R25 P2）
 * 修订历史 (Revision)   : 2026-11-18  v1.0.0  首版入库（R32 · 批 4）
 *                        2026-11-18  v1.0.1  R33 返修：温度恢复清 3024；复位沿提前段 1 全局；采样节拍正域闸（≤0 置 3024 跳过累计）
 *============================================================================*)

FUNCTION_BLOCK FB_DL_WaferThermalBudgetAccum
VAR_INPUT
    bRun         : BOOL;                // 累计使能 / Enable
    bInProcess   : BOOL;                // 工艺进行中 [事件]，真才累计 / Process active flag
    fWaferTempC  : LREAL;               // 晶圆温度 [degC] / Wafer temperature
    fTRefC       : LREAL := 200.0;      // 参考温度 [degC]，等效秒归一基准 / Reference temperature
    fEaOverK     : LREAL := 8000.0;     // 活化能除气体常数 [K]，Arrhenius 斜率 / Ea over k in kelvin
    tSample      : TIME  := T#1S;       // 采样节拍 [s] / Sampling pace period
    fBudgetLimit : LREAL := 3600.0;     // 预算上限 [s@fTRefC] / Budget limit in reference seconds
    bReset       : BOOL;                // 复位指令 [事件]，沿触发清预算与锁存 / Reset command, edge triggered
    fEps         : LREAL := 1.0E-6;     // 浮点判零容差 [实数域] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    ePhase    : (ePhaseIdle := 0, ePhaseAccum := 1, ePhaseExceeded := 2);    // 相枚举输出 / Phase output enum
    fBudgetEqS: LREAL;                  // 等效参考秒累计 [s@fTRefC] / Accumulated budget
    fWeightNow: LREAL;                  // 当前权重 [无量纲] / Current Arrhenius weight
    bExceeded : BOOL;                   // 超限锁存告警 / Latched over-limit alarm
    bError    : BOOL;                   // 故障标志，与故障码配对 / Fault flag paired with codes
    uErrorId  : UDINT;                  // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    _eState  : (eStIdle := 0, eStAccum := 1, eStExceeded := 2);  // 内部状态机 / Internal state machine
    tonPace  : TON;     // 采样节拍定时器 [s]，每拍无条件刷新 / Sampling pace timer
    rTrigRst : R_TRIG;  // 复位上升沿检测，每拍无条件刷新 / Reset edge detection
    fTK      : LREAL;   // 开尔文温度 [K] / Kelvin temperature
    fTRefK   : LREAL;   // 参考开尔文 [K] / Reference in kelvin
    fDeltaS  : LREAL;   // 本拍等效秒增量 [s@fTRefC] / Budget increment this scan
    bTempOk  : BOOL;    // 温度有效标志 / Temperature validity flag
    fPaceS   : LREAL;   // 节拍秒值 [s]，一次导出 / Pace seconds, derived once
    uCode    : UDINT;   // 码位暂存，出口单点写入 [码] / Code staging
    bTempOkPrev : BOOL; // 上拍温度有效快照，恢复沿判据 / Previous validity snapshot
    bPaceOk  : BOOL;    // 采样节拍正域闸标志（tSample > 0）/ Positive pace domain gate
END_VAR
VAR CONSTANT
    DL_WTA_ABS0 : LREAL := 273.15;      // 绝对零度 [degC] / Absolute zero in celsius
    DL_WTA_MS2S : LREAL := 1000.0;      // 毫秒到秒系数 [ms/s] / Milliseconds per second
END_VAR

(* 段 1｜定时器与边沿无条件刷新 + 全局复位 + 节拍正域闸（R33 返修：复位沿提前到全局，不再只挂 eStExceeded）
 *      Timers and edges refreshed unconditionally, global reset edge, positive pace domain gate *)
tonPace(IN := NOT tonPace.Q, PT := tSample);    // 节拍自复位振荡（红线 7，Q 每节拍单拍脉冲）/ Self-reset pace
rTrigRst(CLK := bReset);                        // 复位沿检测 / Reset edge detection
IF fPaceS < 0.0001 THEN
    fPaceS := DINT_TO_LREAL(TIME_TO_DINT(tSample)) / DL_WTA_MS2S;   // 节拍秒值一次导出 / Derive pace once
END_IF
bPaceOk := (tSample > T#0S) AND (fPaceS > fEps); // 节拍正域闸：≤0 时置 3024 并跳过累计 / Positive pace gate
IF rTrigRst.Q THEN
    (* 全局复位：预算清零、锁存解除、回空闲，任何相均可达 / Global reset reachable from any phase *)
    fBudgetEqS := 0.0;          // 预算清零 / Clear the budget
    bExceeded := FALSE;         // 解除锁存 / Release the latch
    uCode := 16#0006_3023;      // 信息级：复位执行 / Info: reset executed
    _eState := eStIdle;         // 拍 N+1 回空闲重部署 / To idle for redeploy
END_IF

(* 段 2｜温度有效性（NaN 自反、Inf 上限、绝对零物理域）/ Temperature validity *)
fTK := fWaferTempC + DL_WTA_ABS0;               // 摄氏转开尔文 / Celsius to kelvin
fTRefK := fTRefC + DL_WTA_ABS0;                 // 参考转开尔文 / Reference to kelvin
bTempOk := (fWaferTempC = fWaferTempC)          // NaN 自反判据 / NaN reflexivity
           AND (ABS(fWaferTempC) < 1.0E308)     // Inf 上限判据 / Inf limit
           AND (fWaferTempC > -DL_WTA_ABS0)     // 绝对零物理域 / Above absolute zero
           AND (fTRefK > fEps);                 // 参考温度防零除 / Reference above zero
IF bTempOk AND (NOT bTempOkPrev) AND (uCode = 16#0006_3024) THEN
    uCode := 16#0000_0000;          // 温度恢复沿清 3024（复位可达，不动 3025 锁存）/ Recovery clears 3024
END_IF
bTempOkPrev := bTempOk;             // 有效标志快照 / Validity snapshot

(* 段 3｜状态机主分派（ENUM 配 CASE，ELSE 兜底）/ State dispatch with ELSE interception *)
CASE _eState OF

    eStIdle:
        (* 本拍行为：预算保持；使能且数据有效拍 N+1 转累计 / Hold; arm when valid *)
        bExceeded := FALSE;             // 空闲无告警 / No alarm in idle
        IF bRun AND bTempOk AND (NOT bInProcess) THEN
            fBudgetEqS := 0.0;          // 进累计前清预算 / Clear before accumulating
        END_IF
        IF bRun AND bTempOk THEN
            _eState := eStAccum;        // 拍 N 空闲相满足，拍 N+1 转累计 / To accumulating next scan
        END_IF
        IF NOT bTempOk THEN
            uCode := 16#0006_3024;      // 故障级：温度非物理域 / Fault: non-physical temperature
        END_IF

    eStAccum:
        (* 本拍行为：工艺进行中按节拍累加 Arrhenius 权重秒 / Accumulate weighted seconds *)
        IF NOT bRun THEN
            _eState := eStIdle;         // 拍 N+1 回空闲 / To idle next scan
        ELSIF NOT bTempOk THEN
            uCode := 16#0006_3024;      // 故障级：温度非物理域，累计冻结 / Fault: freeze
            bTempOk := FALSE;
        ELSE
            fWeightNow := EXP(fEaOverK * (1.0 / fTRefK - 1.0 / fTK));   // Arrhenius 权重 / Arrhenius weight
            IF bInProcess AND tonPace.Q AND bPaceOk THEN
                fDeltaS := fWeightNow * fPaceS;     // 本拍等效秒增量 / Increment in reference seconds
                fBudgetEqS := fBudgetEqS + fDeltaS; // 预算累加 / Accumulate the budget
            END_IF
            IF NOT bPaceOk THEN
                uCode := 16#0006_3024;  // 节拍非正域（tSample ≤ 0）：置码并跳过累计，禁止静默 / Non-positive pace: code and skip
            END_IF
            IF fBudgetEqS > fBudgetLimit THEN
                _eState := eStExceeded; // 拍 N+1 转超限锁存 / To exceeded next scan
                bExceeded := TRUE;      // 超限告警锁存 / Latch the alarm
                uCode := 16#0006_3025;  // 故障级：预算超限 / Fault: budget exceeded
            END_IF
        END_IF

    eStExceeded:
        (* 本拍行为：停止累计保持告警；解除路径已提前至段 1 全局复位沿（R33 返修）
         * Stop accumulating, keep the alarm; clear path is the global reset edge in segment 1 *)
        bExceeded := TRUE;              // 锁存回放，防止中途被旁路覆盖 / Latch replay
        uCode := 16#0006_3025;          // 故障级回放 / Fault replay

ELSE
    _eState := eStIdle;                 // 非法状态拦截回空闲 / Illegal state to idle
    uCode := 16#0006_3024;              // 故障：状态越界 / Fault: state out of range
END_CASE

(* 段 4｜出口装配 / Exit assembly *)
ePhase := ePhaseIdle;                   // 相映射刷新 / Refresh the phase mapping
IF _eState = eStAccum THEN
    ePhase := ePhaseAccum;
ELSIF _eState = eStExceeded THEN
    ePhase := ePhaseExceeded;
END_IF
bError := (uCode >= 16#0006_3024) AND (uCode <= 16#0006_3025);  // 故障级码带判定 / Fault band check
uErrorId := uCode;                      // 码位单点写入 / Single write point
END_FUNCTION_BLOCK
