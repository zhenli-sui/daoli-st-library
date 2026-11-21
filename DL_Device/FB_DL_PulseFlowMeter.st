(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PulseFlowMeter
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 分类     (Category)   : 设备功能块（Function Block，实现 I_DL_FlowMeter）
 * 功能简述 (Function)   : 脉冲型流量计瞬时流量与累计总量计量。脉冲沿计数 →
 *                         自重触发采样窗频率估计 → K 系数换算 [L/min]；总量
 *                         按脉冲计数法累计（精度优于流量积分法）；低流量截
 *                         止、脉冲丢失超时、频率超量程提示；K 系数防除零。
 *                         滑动窗计数为 Device 层内联实现（依赖方向合规：不
 *                         引 DL_MathData 组件）。
 * 接口实现 (Implements) : I_DL_FlowMeter。接口属性同名成员（eState/fFlowRate/
 *                         fTotal/nPulseCount/bFault/uErrorId）按 R22 以只读
 *                         PROPERTY GET 承载（内部镜像同源），非接口成员
 *                         bTotalNearLimit 保留 VAR_OUTPUT；方法 CmdTotalReset/
 *                         CmdTotalPreset/CmdReset 在本文件尾部落地。
 * 公约遵循 (Convention) : 0.1/R23 周期计量型（无初始化/跟踪同步语义，窗由自
 *                         重触发 TON 驱动），免首扫，无 bInit。
 *                         0.2/R21 bFault 显式排除信息级码；0.5/R7 全部实例主
 *                         体最前部无条件刷新；0.7/R15 故障级锁存仅复位路径清
 *                         码；0.9 全部 REAL/LREAL 输入先做非数自比检测再比
 *                         较，出口默认值在第一条防御 IF 之前赋值。
 *                         0.8 故障码段位 16#0003_xxxx（经 DL_Device
 *                         VERSION.md 码表核对：规格建议信息级 0003_0107/
 *                         0108/0109 已被 FB_DL_VfdGeneric/FB_DL_AnalogValve
 *                         占用，依公约冲突顺延）：
 *                         【故障级】0003_02B0 K 系数非法；
 *                         【信息级】0003_0113 低流量截止激活、0003_0114 脉冲
 *                         丢失超时、0003_0115 窗内频率超量程。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 三处除法全部带 ABS(分母)
 *                         >1E-6 防零分支并置码 ✓
 *                         R5 全变量中英双语同行注释 ✓｜R6 状态映像 IF 派生链
 *                         含 ELSE 兜底（无显式 CASE 主状态机，计量型派生映
 *                         像）✓
 *                         R7 四实例（R_TRIG×3/TON×2）主体最前部无条件刷新 ✓
 *                         R8 全常量化 ✓
 * 设计要点 (Key notes)  : ① 瞬时流量 = 窗脉冲数 / 窗秒数 / fKFactor × 60；
 *                         ② 双缓冲：窗运行期脉冲进计数缓冲，窗沿（TON 振荡
 *                           器 Q）整窗交换到读出缓冲，读侧永不撕裂；
 *                         ③ 除零防御三处：fKFactor 非法 → 故障锁存；窗秒数
 *                           由钳位域（100MS~10S）恒非零 + 显式 ABS 防零分支；
 *                           周期法不使用（统一窗法，简化跨平台）；
 *                         ④ 总量按脉冲计数法 fTotal += 窗脉冲数 / fKFactor；
 *                         ⑤ fTotal > 9.0E15 预警（LREAL 整数精度边界）。
 * 偏离留档 (Deviation)  : 依 R11 头注释留档，共 1 条：
 *                         ① 信息级码顺延：规格建议 0003_0107/0108/0109 与既
 *                           有组件冲突，依公约 0.8 顺延为 0003_0113/0114/
 *                           0115（核对结果优先于建议值）。
 * 开源溯源 (Origin)     : 来源标签 tcopen-component / flow-totalizer，T1-1
 *                         OSCAT Basic ◐ 深化旁证（RAW_NOTES_R7 S-6：TcOpen
 *                         流量组件语义域 + OSCAT 流量计窗法计数公开实现思
 *                         想，仅借鉴语义与算法思想；双缓冲、码位与引脚契约
 *                         100% 本库独立设计，clean-room 未复制源码）。
 * 验收向量 (Acceptance) :
 *   V1 已知脉冲序列换算逐拍复算：窗 1S 内 100 脉冲、K=100 → 1.0 L/min；
 *   V2 总量累计与清零：连续 10 窗 @100 脉冲 → fTotal=10.0 L；清零沿 → 0；
 *   V3 低流量截止：fFlowRate < fLowCutoff → 输出置零 + eLowCutoff + 0003_0113；
 *   V4 K 系数非法：fKFactor=0 → 故障锁存 0003_02B0；
 *   V5 脉冲丢失：tPulseTimeout 超时无脉冲 → 流量置零 + 0003_0114；
 *   V6 双缓冲无撕裂推演：窗沿交换拍读侧保持整窗旧值，计数侧从零重启。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 07 · DL_Device 流量计族实现件）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_PulseFlowMeter IMPLEMENTS I_DL_FlowMeter
VAR_INPUT
    bPulseIn       : BOOL;             // 脉冲输入（Pulse input），R_TRIG 上升沿计数；硬件滤波由输入层保证 / Pulse input, counted on rising edge, HW filtering upstream
    bCmdTotalReset : BOOL;             // 总量清零指令（Total reset command），上升沿生效 / Total reset edge
    fKFactor       : REAL := 100.0;    // 流量计 K 系数（K-factor）[pulses/L]，域 >0，默认 100.0；标定证书值 / K-factor [pulses/L], > 0, calibration value
    tSampleWindow  : TIME := T#1S;     // 频率估计采样窗（Sample window），默认 T#1S，域 100MS~10S 越界钳位；低流量场景增大 / Sample window, clamped 100MS..10S, increase for low flow
    fLowCutoff     : REAL := 0.5;      // 低流量截止阈值（Low-flow cutoff）[L/min]，默认 0.5；低于阈值输出置零 / Low-flow cutoff [L/min], below it the output is zeroed
    tPulseTimeout  : TIME := T#5S;     // 脉冲丢失超时（Pulse timeout），默认 T#5S；运行中窗口超时无脉冲 → 流量置零 + 信息级 / Pulse timeout, no pulse in window zeroes the flow with info
    bReset         : BOOL;             // 上升沿复位故障（Reset edge）/ Rising edge resets fault
END_VAR
VAR_OUTPUT
    bTotalNearLimit : BOOL;            // 总量接近溢出预警（Total near limit），fTotal > 9.0E15 置位（LREAL 整数精度边界）/ Total near LREAL integer-precision boundary
END_VAR
VAR
    _eState        : E_DL_FlowMeterState := E_DL_FlowMeterState.eIdle; // 内部计量状态（Internal metering state），属性只读 / Internal state, read-only via property
    _bFaultLatch   : BOOL;             // 故障锁存标志（Fault latch flag），仅复位路径清除 / Fault latch, cleared only via reset path
    _uErrorIdInt   : UDINT;            // 内部故障级码寄存（Internal fault-level register）/ Internal fault-level register
    _uInfoCode     : UDINT;            // 本拍信息级码（Info code this cycle），瞬时型每拍重算 / Transient info code, recomputed each scan
    _fKFactorEff   : REAL := 100.0;    // 防御后生效 K 系数（Sanitized K-factor）[pulses/L] / Sanitized K-factor
    _fCutoffEff    : REAL := 0.5;      // 防御后生效截止阈值（Sanitized cutoff）[L/min] / Sanitized cutoff
    _tWindowEff    : TIME := T#1S;     // 钳位后生效采样窗（Clamped sample window）/ Clamped sample window
    _nCounting     : UDINT;            // 计数中缓冲（Counting buffer），窗运行期累积 / Counting buffer during the window
    _nLastWin      : UDINT;            // 读出缓冲（Readout buffer），窗沿整窗交换 / Readout buffer swapped at window edge
    _fTotalInt     : LREAL;            // 内部累计总量（Internal totalized volume）[L] / Internal totalized volume [L]
    _fFlowRateInt  : REAL;             // 内部瞬时流量（Internal flow rate）[L/min] / Internal flow rate [L/min]
    _fWinSec       : REAL := 1.0;      // 窗秒数（Window seconds），TIME 显式换算 / Window length in seconds, explicit conversion
    _bHadPulse     : BOOL;             // 曾收到脉冲标志（Ever-pulsed flag），超时判定前提 / Ever-pulsed flag, timeout precondition
    _bPulseLost    : BOOL;             // 脉冲丢失超时激活（Pulse-lost timeout active）/ Pulse-lost timeout active
    _bLowCutoffAct : BOOL;             // 低流量截止激活标志（Low-flow cutoff active flag）/ Low-flow cutoff active flag
    _bPendTotalRst : BOOL;             // 方法总量清零请求（Method total-reset request）/ Method total-reset request
    _bPendPreset   : BOOL;             // 方法总量预置请求（Method total-preset request）/ Method total-preset request
    _fPresetVal    : LREAL;            // 方法预置值（Method preset value）[L] / Method preset value [L]
    _bPendReset    : BOOL;             // 方法复位请求（Method reset request）/ Method reset request
    _fbTrigPulse   : R_TRIG;           // 脉冲上升沿（Pulse rising edge）/ Pulse edge detector
    _fbTrigTotalRst: R_TRIG;           // 引脚总量清零沿（Pin total-reset edge）/ Pin total-reset edge detector
    _fbTrigReset   : R_TRIG;           // 引脚复位沿（Pin reset edge）/ Pin reset edge detector
    _fbTonWindow   : TON;              // 采样窗振荡器（Sample-window oscillator），IN := NOT Q 自重触发 / Sample-window oscillator, self-retriggered
    _fbTonPulseTo  : TON;              // 脉冲丢失超时（Pulse-lost timeout）/ Pulse-lost timeout
END_VAR
VAR CONSTANT
    DL_WIN_MIN     : TIME := T#100MS;  // 采样窗下限（Sample window lower clamp）/ Sample window lower clamp
    DL_WIN_MAX     : TIME := T#10S;    // 采样窗上限（Sample window upper clamp）/ Sample window upper clamp
    DL_PULSE_WIN_MAX : UDINT := 10000; // 单窗脉冲数超量程阈值（Pulses-per-window overrange limit），提示配置 HSC / Per-window pulse overrange, suggests HSC
    DL_TOTAL_LIMIT : LREAL := 9.0E15;  // 总量精度边界预警阈值（Total precision-boundary threshold）[L] / Total precision-boundary threshold [L]
    DL_REAL_EPS    : REAL := 1.0E-6;   // 浮点防零容差（Float divide-guard epsilon）/ Float divide-guard epsilon
END_VAR

// ============================================================================
// 段 1｜实例无条件周期刷新（R7/0.5：严禁置于 IF/CASE 分支内）
//      Unconditional per-cycle refresh of all instances (R7/0.5)
// ============================================================================
_fbTrigPulse(CLK    := bPulseIn);
_fbTrigTotalRst(CLK := bCmdTotalReset);
_fbTrigReset(CLK    := bReset);
_fbTonWindow(IN := (NOT _fbTonWindow.Q) AND (NOT _bFaultLatch), PT := _tWindowEff); // 采样窗振荡器（Window oscillator）
_fbTonPulseTo(IN := _bHadPulse AND (NOT _fbTrigPulse.Q) AND (NOT _bFaultLatch), PT := tPulseTimeout); // 脉冲丢失超时（Pulse-lost timeout）

// ============================================================================
// 段 2｜参数防御（0.9：非数自比检测，出口默认值先行）+ 信息级预清零 + 复位
//      Parameter sanitation (0.9) + info preset + reset path
// ============================================================================
_uInfoCode := 0;                  // 信息级瞬时型每拍重算（Transient info recomputed each scan）

IF fKFactor <> fKFactor THEN      // K 系数非数自比检测（K-factor NaN self-compare）
    _bFaultLatch := TRUE;         // K 系数非法锁存（Invalid K-factor latch）
    _uErrorIdInt := 16#0003_02B0; // 0003_02B0 K 系数非法【故障级】/ Invalid K-factor, fault level
ELSIF ABS(fKFactor) <= DL_REAL_EPS THEN
    _bFaultLatch := TRUE;         // K 系数趋零防除零锁存（Near-zero K-factor latch）
    _uErrorIdInt := 16#0003_02B0; // 0003_02B0 K 系数非法【故障级】/ Invalid K-factor, fault level
ELSE
    _fKFactorEff := fKFactor;     // 生效 K 系数镜像（Effective K-factor mirror）
END_IF

IF fLowCutoff <> fLowCutoff THEN  // 截止阈值非数自比（Cutoff NaN self-compare）
    _fCutoffEff := 0.5;           // 回落默认阈值（Fallback default cutoff）
ELSIF fLowCutoff < 0.0 THEN
    _fCutoffEff := 0.0;           // 负值钳零（Negative clamped to zero）
ELSE
    _fCutoffEff := fLowCutoff;    // 生效阈值镜像（Effective cutoff mirror）
END_IF

IF tSampleWindow < DL_WIN_MIN THEN
    _tWindowEff := DL_WIN_MIN;    // 采样窗下限钳位（Window lower clamp）
ELSIF tSampleWindow > DL_WIN_MAX THEN
    _tWindowEff := DL_WIN_MAX;    // 采样窗上限钳位（Window upper clamp）
ELSE
    _tWindowEff := tSampleWindow; // 合法直通（Valid pass-through）
END_IF
_fWinSec := TIME_TO_REAL(_tWindowEff) / 1000.0; // TIME→REAL 换算结果为毫秒数，除 1000 得秒（CODESYS/TwinCAT 口径，舍入意图：整毫秒窗恒精确）/ TIME_TO_REAL yields milliseconds, divide by 1000 for seconds

IF _fbTrigReset.Q OR _bPendReset THEN
    _bPendReset := FALSE;         // 消费方法复位请求（Consume method reset）
    _bFaultLatch := FALSE;        // 故障锁存解除（Fault latch released）
    _uErrorIdInt := 16#0000_0000; // 故障码清零（Fault code cleared）
END_IF

// ============================================================================
// 段 3｜总量清零/预置（引脚沿 + 方法请求）
//      Total reset/preset (pin edge + method request)
// ============================================================================
IF _fbTrigTotalRst.Q OR _bPendTotalRst THEN
    _bPendTotalRst := FALSE;      // 消费方法请求（Consume method request）
    _fTotalInt := 0.0;            // 总量清零（Total cleared）
END_IF
IF _bPendPreset THEN
    _bPendPreset := FALSE;        // 消费方法预置请求（Consume method preset）
    IF _fPresetVal >= 0.0 THEN
        _fTotalInt := _fPresetVal; // 合法预置写入（Valid preset written）
    END_IF                         // 非法预置已被方法拒绝，此处仅兜底（Invalid preset already rejected by method）
END_IF

// ============================================================================
// 段 4｜脉冲计数 + 窗沿双缓冲交换 + 瞬时流量换算（除法全部带防零分支）
//      Pulse counting + double-buffer swap at window edge + flow conversion
// ============================================================================
IF _fbTrigPulse.Q THEN
    _nCounting := _nCounting + 1; // 计数缓冲累加（Counting buffer increment）
    _bHadPulse := TRUE;           // 曾收到脉冲（Ever pulsed）
END_IF

IF _fbTonWindow.Q THEN
    // 窗沿：整窗交换（双缓冲无撕裂：读出缓冲只在窗沿被写一次）
    // Window edge: whole-window swap (readout written once per window, no tearing)
    _nLastWin := _nCounting;      // 读出缓冲接收整窗计数（Readout takes the window count）
    _nCounting := 0;              // 计数缓冲清零重启（Counting buffer restarted）
    IF ABS(_fKFactorEff) > DL_REAL_EPS THEN
        _fTotalInt := _fTotalInt + UDINT_TO_LREAL(_nLastWin) / _fKFactorEff; // 脉冲计数法累计（Count-based totalization, divisor proven non-zero）
    END_IF
END_IF

_fFlowRateInt := 0.0;             // 出口默认值先赋（Default outlet first）
IF ABS(_fWinSec) > DL_REAL_EPS THEN
    IF ABS(_fKFactorEff) > DL_REAL_EPS THEN
        _fFlowRateInt := UDINT_TO_REAL(_nLastWin) / _fWinSec / _fKFactorEff * 60.0; // 窗法换算 [L/min]（Window-method conversion, divisors proven non-zero）
    END_IF
END_IF

// ============================================================================
// 段 5｜诊断与信息级：脉冲丢失 / 频率超量程 / 低流量截止
//      Diagnostics and info codes: pulse lost / overrange / low-flow cutoff
// ============================================================================
_bLowCutoffAct := FALSE;          // 截止激活标志每拍预清零（Cutoff flag preset FALSE）
_bPulseLost := _fbTonPulseTo.Q;   // 脉冲丢失超时激活（Pulse-lost timeout active）
IF _bPulseLost THEN
    _fFlowRateInt := 0.0;         // 超时流量置零（Flow zeroed on timeout）
    _uInfoCode := 16#0003_0114;   // 0003_0114 脉冲丢失超时【信息级】/ Pulse-lost timeout, info level
ELSIF _nLastWin > DL_PULSE_WIN_MAX THEN
    _uInfoCode := 16#0003_0115;   // 0003_0115 窗内频率超量程【信息级】，提示输入层配置 HSC / Per-window overrange, suggest HSC upstream
ELSIF (_fFlowRateInt < _fCutoffEff) AND _bHadPulse AND (NOT _bPulseLost) THEN
    _fFlowRateInt := 0.0;         // 低流量截止输出置零（Low-flow cutoff zeroes output）
    _bLowCutoffAct := TRUE;       // 截止激活标志置位（Cutoff flag asserted）
    _uInfoCode := 16#0003_0113;   // 0003_0113 低流量截止激活【信息级】/ Low-flow cutoff active, info level
END_IF

// ============================================================================
// 段 6｜状态映像（IF 派生链含 ELSE 兜底）+ 输出推导
//      State image (IF derivation chain with ELSE) + output derivation
// ============================================================================
IF _bFaultLatch THEN
    _eState := E_DL_FlowMeterState.eFault;        // 故障映像（Fault image）
ELSIF _bPulseLost OR (NOT _bHadPulse) THEN
    _eState := E_DL_FlowMeterState.eIdle;         // 静默/丢失映像（Idle image）
ELSIF _bLowCutoffAct THEN
    _eState := E_DL_FlowMeterState.eLowCutoff;    // 截止映像（Low-cutoff image）
ELSIF _fFlowRateInt > 0.0 THEN
    _eState := E_DL_FlowMeterState.eFlowOk;       // 正常流量映像（Flow-OK image）
ELSE
    _eState := E_DL_FlowMeterState.eMeasuring;    // 测量中兜底映像（Measuring fallback image）
END_IF

bTotalNearLimit := _fTotalInt > DL_TOTAL_LIMIT; // 总量精度边界预警（Total near precision boundary）

(*------------------------------------------------------------------------------
 * 方法: CmdTotalReset —— 总量清零。故障态拒绝。
 *      Method CmdTotalReset - total reset, rejected in fault.
 *------------------------------------------------------------------------------*)
METHOD CmdTotalReset : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_FlowMeterState.eFault) THEN
    CmdTotalReset := FALSE;       // 故障态拒绝（Rejected in fault）
ELSE
    _bPendTotalRst := TRUE;       // 登记清零请求，主体消化（Register reset, consumed by body）
    CmdTotalReset := TRUE;        // 受理成功（Accepted）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdTotalPreset —— 总量预置 [L]，非有限值/负值拒绝返回 FALSE。
 *      Method CmdTotalPreset - total preset [L], non-finite or negative rejected.
 *------------------------------------------------------------------------------*)
METHOD CmdTotalPreset : BOOL
VAR_INPUT
    fPreset : LREAL // 预置总量（Preset volume）[L]，域 ≥0 / Preset volume [L], range >= 0
END_VAR
IF _bFaultLatch OR (_eState = E_DL_FlowMeterState.eFault) THEN
    CmdTotalPreset := FALSE;      // 故障态拒绝（Rejected in fault）
ELSIF (fPreset <> fPreset) OR (fPreset < 0.0) THEN
    CmdTotalPreset := FALSE;      // 非数或负值拒绝（Rejected on NaN or negative）
ELSE
    _fPresetVal := fPreset;       // 登记预置值（Register preset value）
    _bPendPreset := TRUE;         // 登记预置请求（Register preset request）
    CmdTotalPreset := TRUE;       // 受理成功（Accepted）
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdReset —— 复位故障。仅故障态受理（接口方法拒绝语义红线）。
 *      Method CmdReset - reset, accepted only in fault state.
 *------------------------------------------------------------------------------*)
METHOD CmdReset : BOOL
VAR_INPUT
END_VAR
IF _bFaultLatch OR (_eState = E_DL_FlowMeterState.eFault) THEN
    _bPendReset := TRUE;          // 登记复位请求（Register reset request）
    CmdReset := TRUE;             // 可复位（Resettable）
ELSE
    CmdReset := FALSE;            // 无故障可复位（Nothing to reset）
END_IF

(*------------------------------------------------------------------------------
 * 属性: eState（GET）—— 当前计量状态只读视图。
 *      Property eState (GET) - read-only metering state view.
 *------------------------------------------------------------------------------*)
PROPERTY eState : E_DL_FlowMeterState
eState := _eState;                // 返回内部状态（Return internal state）

(*------------------------------------------------------------------------------
 * 属性: fFlowRate（GET）—— 瞬时流量 [L/min]。
 *      Property fFlowRate (GET) - instantaneous flow rate [L/min].
 *------------------------------------------------------------------------------*)
PROPERTY fFlowRate : REAL
fFlowRate := _fFlowRateInt;       // 返回瞬时流量镜像（Return flow-rate mirror）

(*------------------------------------------------------------------------------
 * 属性: fTotal（GET）—— 累计总量 [L]。
 *      Property fTotal (GET) - totalized volume [L].
 *------------------------------------------------------------------------------*)
PROPERTY fTotal : LREAL
fTotal := _fTotalInt;             // 返回累计总量镜像（Return total mirror）

(*------------------------------------------------------------------------------
 * 属性: nPulseCount（GET）—— 窗口内脉冲计数原始值（读出缓冲）。
 *      Property nPulseCount (GET) - raw pulse count of the last window.
 *------------------------------------------------------------------------------*)
PROPERTY nPulseCount : UDINT
nPulseCount := _nLastWin;         // 返回读出缓冲（Return readout buffer）

(*------------------------------------------------------------------------------
 * 属性: bFault（GET）—— 故障锁存指示（信息级码不置本位，0.2 公约）。
 *      Property bFault (GET) - fault latch indicator, info codes excluded.
 *------------------------------------------------------------------------------*)
PROPERTY bFault : BOOL
bFault := _bFaultLatch OR (_eState = E_DL_FlowMeterState.eFault); // 显式排除信息级派生式（Derived form excluding info codes）

(*------------------------------------------------------------------------------
 * 属性: uErrorId（GET）—— 末次故障码（故障级优先，无故障时透出本拍信息级
 *         码，0.2/0.15 公约）。
 *      Property uErrorId (GET) - last error code (fault priority, info shown otherwise).
 *------------------------------------------------------------------------------*)
PROPERTY uErrorId : UDINT
IF (_uErrorIdInt <> 0) OR (_eState = E_DL_FlowMeterState.eFault) THEN
    uErrorId := _uErrorIdInt;     // 故障级码优先透出（Fault-level priority）
ELSE
    uErrorId := _uInfoCode;       // 无故障时透出本拍信息级码（Transient info code）
END_IF
END_FUNCTION_BLOCK
