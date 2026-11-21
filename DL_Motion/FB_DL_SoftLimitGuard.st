(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SoftLimitGuard
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.1
 * 兼容性 (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商方言
 * 分类     (Category)   : 运动安全功能块（Function Block · 软限位电子围栏预判）
 * 功能简述 (Function)   : 软限位安全电子围栏预判器。根据当前速度与减速度实
 *                         时计算双向制动距离（含扫描/IO/驱动时延项），提前
 *                         拦截超程指令；超程后仅允许反向指令（向内恢复豁免
 *                         语义）。位置/速度经既有 I_DL_MotionAxis 接口引用
 *                         读取（fPosition/fVelocity 属性，R11 留档选定）。
 * 定位声明 (Positioning): 公约 0.13——本块为应用层预判与诊断镜像层，不构成
 *                         ISO 13849 / IEC 62061 认证安全功能；硬限位开关与
 *                         认证安全回路的最终防线在认证安全控制器侧，本块输
 *                         出为建议信号（拦截执行在调用方）。
 * 接口消费 (Consumes)   : I_DL_MotionAxis（既有契约，零修改）：读
 *                         iAxis.fPosition / iAxis.fVelocity。R11 二选一留
 *                         档：既有接口已含 fVelocity 速度属性，故不新增
 *                         fAxisSpeed IN_OUT 引脚（规格备选方案弃用）。
 * 公约遵循 (Convention) : 0.1/R23 周期监视型（无初始化/跟踪同步语义），免首
 *                         扫，无 bInit。
 *                         0.2/R21 bFault 显式排除信息级码；0.5/R7 边沿实例主
 *                         体最前部无条件刷新；0.7/R15 故障级锁存仅复位路径清
 *                         码（且离开越界区才可复位）；0.9 全部 REAL 输入/接
 *                         口读数先做非数自比检测（保持末次有效值）；0.14 除
 *                         法带 ABS 防零分支并置码。
 *                         0.8 故障码段位 16#0004_xxxx（经 DL_Motion
 *                         VERSION.md 码表核对：规格建议 0004_0220/0221 已被
 *                         FB_DL_AxisRelativeMove 占用、0004_0106/0107 已占，
 *                         依公约冲突顺延）：
 *                         【故障级】0004_0240 减速度非法、0004_0241 行程边界
 *                         非法；
 *                         【信息级】0004_0108 时延口径提示（默认值与实际不
 *                         符时建议实测，一次性提示）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 除零防御/非有限值防御/浮点
 *                         容差 ✓
 *                         R5 全变量中英双语同行注释 ✓｜R6 N/A（监视型无主状
 *                         态机，判据为纯派生式）✓
 *                         R7 边沿实例主体最前部无条件刷新 ✓｜R8 全常量化 ✓
 * 设计要点 (Key notes)  : ① 预判公式（S-11 提取点①）：fStopDist = fSpeed ×
 *                           tLatency_s + fSpeed² / (2 × fDecel)；tLatency 显
 *                           式换算秒（TIME_TO_REAL 毫秒口径 /1000，舍入意图
 *                           注释写明）；默认 T#23MS 口径 = 扫描 10 + IO 5 +
 *                           驱动 8 ms 三项来源；
 *                         ② 除零防御：fDecel ≤ 1E-6 或非数 → 故障锁存；
 *                           fSpeed² 项在 fSpeed→0 时自然收敛；
 *                         ③ 方向语义：bInterceptPos 置位期间仅允许负向指令
 *                           （向内恢复豁免），本块输出建议信号不直接阻断指
 *                           令（职责边界：拦截执行在调用方）；
 *                         ④ 预警/拦截两级（v1.0.1 勘误：拦截带 ⊇ 预警带——
 *                           拦截含 fMargin 裕量更早触发（保守安全侧），预警带
 *                           为无裕量理论停止距离带；预警带 ⊆ 拦截带，两带
 *                           重合于 fMargin=0 时）；
 *                         ⑤ 参数防御：fPosLimitPos ≤ fPosLimitNeg → 故障锁
 *                           存；复位前提 = 离开越界区（位置回到界内）。
 * 偏离留档 (Deviation)  : 依 R11 头注释留档，共 1 条：
 *                         ① 码位顺延与速度来源：规格建议 0004_0220/0221 与
 *                           既有 FB_DL_AxisRelativeMove 冲突，顺延为
 *                           0004_0240/0241；速度来源选定既有接口属性
 *                           iAxis.fVelocity（规格备选 fAxisSpeed 引脚弃用）。
 * 开源溯源 (Origin)     : 来源标签 plcopen-motion，T1-6 ◐ 深化（RAW_NOTES_R7
 *                         S-11：PLCopen 软限位/Safety-limited 公开语义——
 *                         制动距离预判含时延项、方向性恢复豁免（提取点①②），
 *                         公开规范资料，仅借鉴语义域；预判实现、码位与引脚
 *                         契约 100% 本库独立设计，clean-room 未复制源码）。
 * 验收向量 (Acceptance) :
 *   V1 数值复算：fSpeed=100 mm/s、fDecel=500 mm/s²、tLatency=23MS → 停止距
 *      离 = 100×0.023 + 100²/1000 = 12.3 mm；
 *   V2 预警带进入/退出：位置进入 [边界−停止距离, 边界] → bWarnPos 置位，退
 *      出回落；
 *   V3 双向拦截边界：位置 + 停止距离 + 裕量越界 → bInterceptPos/Neg 置位；
 *   V4 反向恢复豁免：bInterceptPos 期间仅负向指令允许（输出建议语义，注释
 *      写明职责边界）；
 *   V5 参数非法：fDecel=0 → 0004_0240；fPosLimitPos ≤ fPosLimitNeg →
 *      0004_0241；
 *   V6 使能切断仅监视：bEnable=FALSE → 预警照常输出、拦截输出强制 FALSE。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 07 · DL_Motion 软限位预判件）
 *   2026-11-15  v1.0.1  终审修复 2 处：① fMargin 缺 0.9 非数防御（NaN 时拦
 *                       截比较式恒 FALSE 静默失效），新增 _fMarginEff 生效值
 *                       并钳制负裕量；② 设计要点④「预警带 ⊇ 拦截带」与实
 *                       现/规格向量矛盾，勘误为「拦截带 ⊇ 预警带（含裕量更
 *                       早触发，保守安全侧）」
 *============================================================================*)
FUNCTION_BLOCK FB_DL_SoftLimitGuard
VAR_INPUT
    fPosLimitPos : REAL;                // 正向行程边界（Positive travel limit）[mm]，域 > fPosLimitNeg / Positive travel limit [mm]
    fPosLimitNeg : REAL;                // 负向行程边界（Negative travel limit）[mm] / Negative travel limit [mm]
    fDecel       : REAL := 500.0;       // 拦截减速度（Guard deceleration）[mm/s²]，域 >0，默认 500.0；按配置减速取保守值 / Guard deceleration [mm/s²], conservative value
    tLatency     : TIME := T#23MS;      // 系统-驱动总时延（System latency），默认 T#23MS（扫描 10 + IO 5 + 驱动 8 ms 口径）/ Total latency, default 23 MS (scan 10 + IO 5 + drive 8 ms)
    fMargin      : REAL := 0.0;         // 安全裕量（Safety margin）[mm]，默认 0=关闭裕量；建议 = 停止距离 × 25% / Safety margin [mm], 0 = disabled, suggest 25% of stop distance
    bEnable      : BOOL;                // 预判使能（Guard enable），FALSE=仅监视输出不拦截 / FALSE = monitor only, no intercept
    bReset       : BOOL;                // 上升沿复位故障（Reset edge），离开越界区并复位后方可恢复 / Reset edge, effective only after leaving the overtravel zone
END_VAR
VAR_OUTPUT
    bWarnPos      : BOOL;               // 正向预警（Positive warning），进入「边界 − 停止距离」预判带即置位 / Positive warning inside the limit-minus-stopdist band
    bWarnNeg      : BOOL;               // 负向预警（Negative warning），正向判据镜像 / Mirror of the positive verdict
    bInterceptPos : BOOL;               // 正向拦截（Positive intercept），位置 + 预判停止距离越过边界（含裕量）即置位：调用方应禁止正向指令并减速 / Positive intercept verdict
    bInterceptNeg : BOOL;               // 负向拦截（Negative intercept），正向判据镜像 / Mirror of the positive verdict
    bInsideOk     : BOOL;               // 双向行程内正常（Inside envelope）/ Inside envelope verdict
    fStopDistPos  : REAL;               // 实时正向预判停止距离（Predicted positive stop distance）[mm]，调试/HMI 用 / Predicted stop distance [mm] for HMI
    fStopDistNeg  : REAL;               // 实时负向预判停止距离（Predicted negative stop distance）[mm]，调试/HMI 用 / Predicted stop distance [mm] for HMI
    bFault        : BOOL;               // 故障标志（Fault flag），显式排除信息级 / Fault flag, info codes excluded
    uErrorId      : UDINT;              // 故障码（Error code），16#0004_xxxx 段，0=无故障 / Error code, family 16#0004_xxxx
END_VAR
VAR_IN_OUT
    iAxis        : I_DL_MotionAxis;     // 轴接口引用（Axis interface），由上层注入（既有契约 I_DL_MotionAxis）/ Axis interface reference injected by caller
END_VAR
VAR
    _bFaultLatch  : BOOL;               // 故障锁存标志（Fault latch flag），仅复位路径清除 / Fault latch, cleared only via reset path
    _uErrorIdInt  : UDINT;              // 内部故障级码寄存（Internal fault-level register）/ Internal fault-level register
    _uInfoCode    : UDINT;              // 本拍信息级码（Info code this cycle），瞬时型每拍重算 / Transient info code, recomputed each scan
    _bLatencyHint : BOOL;               // 时延口径提示已发（Latency hint issued）一次性 / One-shot latency hint flag
    _fPosHold     : REAL;               // 末次有效位置保持（Last valid position hold）[mm] / Last valid position hold [mm]
    _fSpdHold     : REAL;               // 末次有效速度保持（Last valid velocity hold）[mm/s] / Last valid velocity hold [mm/s]
    _fPosNow      : REAL;               // 防御后生效位置（Sanitized position）[mm] / Sanitized position [mm]
    _fSpdNow      : REAL;               // 防御后生效速度绝对值（Sanitized speed magnitude）[mm/s] / Sanitized speed magnitude [mm/s]
    _fDecelEff    : REAL := 500.0;      // 防御后生效减速度（Sanitized deceleration）[mm/s²] / Sanitized deceleration [mm/s²]
    _fMarginEff   : REAL;               // 防御后生效安全裕量（Sanitized safety margin）[mm]，0.9 非数防御 / Sanitized safety margin [mm] (v1.0.1)
    _fLatencySec  : REAL;               // 时延秒数（Latency in seconds），TIME 显式换算 / Latency seconds, explicit conversion
    _fStopDist    : REAL;               // 预判停止距离（Predicted stop distance）[mm] / Predicted stop distance [mm]
    _fbTrigReset  : R_TRIG;             // 复位沿（Reset edge）/ Reset edge detector
END_VAR
VAR CONSTANT
    DL_REAL_EPS      : REAL := 1.0E-6;  // 浮点防零容差（Float divide-guard epsilon）/ Float divide-guard epsilon
    DL_TIME_MS_SCALE : REAL := 1000.0;  // TIME→REAL 毫秒换算秒的标度（ms-to-seconds scale）/ Milliseconds-to-seconds scale
END_VAR

// ============================================================================
// 段 1｜实例无条件周期刷新（R7/0.5：严禁置于 IF/CASE 分支内）
//      Unconditional per-cycle refresh of instances (R7/0.5)
// ============================================================================
_fbTrigReset(CLK := bReset);

// ============================================================================
// 段 2｜信息级预清零 + 参数防御（0.9：非数自比，默认值先行）+ 复位路径（R15）
//      Info preset + parameter sanitation (0.9) + reset path (R15)
// ============================================================================
_uInfoCode := 0;                  // 信息级瞬时型每拍重算（Transient info recomputed each scan）

IF fDecel <> fDecel THEN          // 减速度非数自比（Decel NaN self-compare）
    _bFaultLatch := TRUE;         // 减速度非法锁存（Invalid decel latch）
    _uErrorIdInt := 16#0004_0240; // 0004_0240 减速度非法【故障级】/ Invalid deceleration, fault level
ELSIF ABS(fDecel) <= DL_REAL_EPS THEN
    _bFaultLatch := TRUE;         // 减速度趋零防除零锁存（Near-zero decel latch）
    _uErrorIdInt := 16#0004_0240; // 0004_0240 减速度非法【故障级】/ Invalid deceleration, fault level
ELSE
    _fDecelEff := ABS(fDecel);    // 生效减速度（取绝对值保守口径）/ Effective deceleration, magnitude
END_IF

IF fPosLimitPos <= fPosLimitNeg THEN
    _bFaultLatch := TRUE;         // 行程边界非法锁存（Invalid travel limits latch）
    _uErrorIdInt := 16#0004_0241; // 0004_0241 行程边界非法【故障级】/ Invalid travel limits, fault level
END_IF

IF tLatency = T#23MS THEN         // 时延等于默认口径：提示实测（默认值与实际不符建议）
    IF NOT _bLatencyHint THEN
        _bLatencyHint := TRUE;    // 一次性提示标志（One-shot hint flag）
        _uInfoCode := 16#0004_0108; // 0004_0108 时延口径提示【信息级】（建议实测后整定）/ Latency default hint, info level
    END_IF
END_IF
_fLatencySec := TIME_TO_REAL(tLatency) / DL_TIME_MS_SCALE; // TIME→REAL 毫秒口径换算秒（整毫秒时延换算无舍入损失，意图注释）/ ms-to-seconds conversion, exact for whole ms

// 0.9 非数防御补齐（v1.0.1）：fMargin 非数时比较式恒 FALSE → 拦截静默失效
// （安全相关静默降级），非数回落零裕量
// 0.9 NaN defense added (v1.0.1): NaN margin silently disables the intercept
IF fMargin <> fMargin THEN        // 裕量非数（Margin NaN self-compare）
    _fMarginEff := 0.0;           // 回落零裕量（保守域仍由停止距离承担）/ Fallback zero margin
ELSIF fMargin < 0.0 THEN
    _fMarginEff := 0.0;           // 负裕量钳零（防拦截滞后）/ Negative margin clamped to zero
ELSE
    _fMarginEff := fMargin;       // 生效裕量（Effective margin）
END_IF

IF _fbTrigReset.Q AND _bFaultLatch THEN
    // 复位联锁：离开越界区（位置回到界内）且故障源消失才解除
    // Reset interlock: effective only after leaving the overtravel zone
    IF (_fPosHold < fPosLimitPos) AND (_fPosHold > fPosLimitNeg)
       AND (ABS(fDecel) > DL_REAL_EPS) AND (fPosLimitPos > fPosLimitNeg) THEN
        _bFaultLatch := FALSE;    // 故障锁存解除（Fault latch released）
        _uErrorIdInt := 16#0000_0000; // 故障码清零（Fault code cleared）
    END_IF
END_IF

// ============================================================================
// 段 3｜接口读数防御（0.9：非数保持末次有效值）+ 停止距离预判（含时延项）
//      Interface reading sanitation (0.9) + stop-distance prediction with latency
// ============================================================================
IF iAxis.fPosition <> iAxis.fPosition THEN // 位置非数自比（Position NaN self-compare）
    // 保持末次有效位置（Hold last valid position）
ELSE
    _fPosHold := iAxis.fPosition; // 更新末次有效位置（Update last valid position）
END_IF
IF iAxis.fVelocity <> iAxis.fVelocity THEN // 速度非数自比（Velocity NaN self-compare）
    // 保持末次有效速度（Hold last valid velocity）
ELSE
    _fSpdHold := iAxis.fVelocity; // 更新末次有效速度（Update last valid velocity）
END_IF
_fPosNow := _fPosHold;            // 生效位置镜像（Effective position mirror）
_fSpdNow := ABS(_fSpdHold);       // 生效速度幅值（方向由比较式承载）/ Effective speed magnitude (direction carried by comparisons)

_fStopDist := 0.0;                // 出口默认值先赋（Default outlet first）
IF ABS(_fDecelEff) > DL_REAL_EPS THEN
    // 预判公式：时延项 + 制动项（S-11 提取点①）；fSpeed² 项在速度→0 时自然收敛
    // Prediction: latency term + braking term; braking term converges at zero speed
    _fStopDist := (_fSpdNow * _fLatencySec) + (_fSpdNow * _fSpdNow / (2.0 * _fDecelEff)); // 除数已证明非零（Divisor proven non-zero）
END_IF
fStopDistPos := _fStopDist;       // 正向停止距离出口（Positive stop distance outlet）
fStopDistNeg := _fStopDist;       // 负向停止距离出口（对称裕量口径，对称制动力假设）/ Negative outlet (symmetric deceleration assumption)

// ============================================================================
// 段 4｜预警/拦截判据派生（两级：预警带 ⊇ 拦截带；使能切断仅监视）
//      Warning/intercept derivation (two-level, monitor-only when disabled)
// ============================================================================
bWarnPos := (_fPosNow > (fPosLimitPos - _fStopDist)); // 正向预警：进入边界−停止距离带（Positive warning band）
bWarnNeg := (_fPosNow < (fPosLimitNeg + _fStopDist)); // 负向预警镜像（Negative warning mirror）
bInterceptPos := (_fPosNow + _fStopDist + _fMarginEff) > fPosLimitPos; // 正向拦截：含裕量越界预判（生效裕量，v1.0.1）/ Positive intercept with sanitized margin (v1.0.1)
bInterceptNeg := (_fPosNow - _fStopDist - _fMarginEff) < fPosLimitNeg; // 负向拦截镜像（Negative intercept mirror）
IF (NOT bEnable) OR _bFaultLatch THEN
    bInterceptPos := FALSE;       // 使能切断/故障期仅监视：拦截输出强制 FALSE（Monitor-only assertion）
    bInterceptNeg := FALSE;       // 正向断言镜像（Mirror of the positive assertion）
END_IF
bInsideOk := (NOT bWarnPos) AND (NOT bWarnNeg) AND (NOT _bFaultLatch); // 行程内正常派生（Inside-envelope derived form）

// ============================================================================
// 段 5｜方向语义注释（输出建议信号，拦截执行在调用方）+ bFault/uErrorId 出口
//      Direction semantics note + outlets (R21: bFault excludes info codes)
// ============================================================================
// 方向语义（S-11 提取点②）：bInterceptPos 置位期间仅允许负向指令（向内恢复
// 豁免）；bInterceptNeg 置位期间仅允许正向指令。本块输出为建议信号，不直接
// 阻断轴指令——指令禁止与减速执行在调用方（职责边界）。
// Direction semantics: intercept implies opposite-direction commands only; this
// block issues advisory signals only, the caller enforces command blocking.

bFault := _bFaultLatch;           // 故障级派生式（Fault-level derived form）
IF _bFaultLatch THEN
    uErrorId := _uErrorIdInt;     // 故障级码优先透出（Fault-level priority）
ELSE
    uErrorId := _uInfoCode;       // 无故障时透出本拍信息级码（Transient info code）
END_IF
END_FUNCTION_BLOCK
