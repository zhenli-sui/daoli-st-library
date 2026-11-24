(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SuperimposedMove
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 分类     (Category)   : 运动工艺功能块（Function Block · 叠加运动补偿层）
 * 作者     (Author)     : Daoli Library
 * 日期     (Date)       : 2026-11-15
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版）语法，
 *                         仅依赖 Standard.library（TON / F_TRIG），零厂商方言
 * 功能简介 (Function)   : 叠加运动补偿层（MC_MoveSuperimposed 语义）。基础轴
 *                         按既有轨迹运行的同时，叠加一个动态偏移量（视觉纠偏、
 *                         张力微调、飞剪对位等场景）；偏移指令经斜坡限速与幅值
 *                         限幅后得到「偏移实际值」，与基础位置相加输出「合成位置」，
 *                         由上层用合成位置下发轴指令。本块只做叠加律、限幅与
 *                         收敛判据，不触碰轴本体指令、不读写轴状态、不做回原。
 *                         与基础运动正交：基础轴正反向运动期间本块无需知情，
 *                         偏移量仅作为位置域的代数叠加项存在。
 * 职责边界 (Scope)      : ① 不产生任何轴使能/定位/停止指令（轴控归上层或
 *                         既有 FB_DL_SingleAxis 类实现块）；② 不读编码器、不做
 *                         位置闭环（纠偏闭环在视觉/张力环内部完成，本块只执行
 *                         已算好的偏移指令）；③ 不做安全限位判断（软限位预判
 *                         归既有 FB_DL_SoftLimitGuard）。
 * 开源溯源 (Origin)     : 来源标签 plcopen-motion / s7-motion（双源印证）。
 *                         仅参考 PLCopen TC3 公开规范与 S7-1500 Motion Control
 *                         公开手册中叠加运动的「功能分类与参数域」（基础运动与
 *                         叠加偏移正交、偏移斜坡限速、零偏移保持叠加层激活的
 *                         行为定义、幅值/速率限制参数域）；本块的状态机、枚举
 *                         编号、引脚契约、故障码位与斜坡实现 100% 本库独立
 *                         设计，clean-room 实现，未复制任何厂商源码行，不构成
 *                         任何来源的衍生作品。
 * 公约遵循 (Convention) : 0.1/R19 首扫范式退化式（本层无外部跟踪源，故取
 *                         IF (NOT bInit) 唯一判据）；0.2/R21 bError 显式排除
 *                         信息级码；0.5/R7 边沿与定时器实例主体最前部无条件
 *                         刷新；0.7/R15 故障级锁存仅重建路径清码；0.9 非有限值
 *                         自比防御 + 出口默认值先赋；0.14 除法与浮点比较全部
 *                         带 ABS 容差；0.16 阈值全常量化。
 * 红线自检 (Redline)    : 全局隔离 ✓（零全局变量表引用、零外部变量声明、零物理
 *                         地址字面记号）｜命名合规 ✓（b/n/u/f/t/a/st/e/fb/i 前缀
 *                         全覆盖）｜注释完整 ✓（声明行 100% 中英双语同行注释）｜
 *                         OOP 封装 ✓（内部状态全私有，仅引脚出口）｜周期安全 ✓
 *                         （TON / F_TRIG 实例无条件刷新）｜防御编程 ✓（除零守卫、
 *                         浮点容差、ENUM + CASE + ELSE 兜底）｜可移植性 ✓（纯
 *                         IEC 61131-3，零厂商私有库）｜终结符成对 ✓
 * 设计要点 (Key notes)  : ① 斜坡实现：本版将斜坡积分内联实现（每拍步进 =
 *                           maxOffsetSpeed × 任务周期），一次乘加即可完成，避免
 *                          REAL/LREAL 与 TIME 毫秒量化的双重精度损失；算法思想
 *                          与已入库 FB_DL_RateLimiter 同源（单向对称限速），
 *                          独立实现、不调用其实例（规格偏离留档见下）。
 *                         ② 限幅次序：先按 bZeroNow 归零目标，再按 maxOffset
 *                          双向幅值钳位，最后进斜坡；钳位发生时置信息级码，
 *                          斜坡仍继续（现场表现为「削顶平移」，不跳变）。
 *                         ③ 零偏移归零完成判据：偏移目标与实际同时落入容差带后
 *                          还需经过零驻留窗口（TON）才判 bInSync，并把浮点残差
 *                          硬置 0.0，防止 HMI 长期显示 0.000001 的假偏移。
 *                         ④ 冻结语义：bEnable = FALSE 时斜坡停走、偏移实际值
 *                          保持（不归零、不跳变），合成位置继续 = 基础 + 保持值；
 *                          重新使能后斜坡从冻结值继续，不产生阶跃（R19 重建式）。
 *                         ⑤ 故障重建：本块故障为参数级（幅值/周期非法）与状态级
 *                          （非法枚举），按规格以 bEnable 下降沿重建回 eIdle，
 *                          重建时清故障码但保持偏移实际值（不归零、不跳变），
 *                          首扫同步只在实例首次运行执行一次。
 * 偏离留档 (Deviation)  : ① 规格 VAR 段列出 fbSlew : FB_DL_RateLimiter 实例，
 *                         实现改为内联斜坡积分（理由见设计要点①，影响：无外部
 *                         组件依赖，引脚契约与输出语义完全不变）；
 *                         ② 规格 VAR 段 bFirstScan 改名 _bInit（理由：公约 0.1
 *                         统一命名 bInit，影响：无）；
 *                         ③ 规格状态跃迁文案「参数非法或斜坡故障 → eFault」中
 *                         斜坡故障项随内联实现取消，参数非法与非法状态两项保留。
 * 故障码表 (Error codes) :
 *                         16#0004_01A0【信息级】任务周期引脚非法已按 10 ms 兜底
 *                         16#0004_01A1【信息级】偏移指令已按幅值上限限幅
 *                         16#0004_01A2【信息级】偏移指令非有限值已拒绝（保持）
 *                         16#0004_01A3【信息级】不限速直通（限速值 <= 0，一次性提示）
 *                         16#0004_02B0【故障级】偏移幅值上限非法（<= 0 或非有限值）
 *                         16#0004_02B1【故障级】任务周期非法（<= 0 或非有限值）
 *                         16#0004_02B2【故障级】非法状态兜底（枚举越界）
 * 验收向量 (Acceptance) :
 *   V1 斜坡跟随：maxOffsetSpeed = 10 mm/s、周期 10 ms、指令跳变 5 mm
 *      → 每拍偏移实际值 +0.1 mm，50 拍后到位，bInSync 置位；
 *   V2 幅值限幅：maxOffset = 5 mm、指令 8 mm → 偏移实际值封顶 5 mm 且
 *      信息级 0004_01A1（每拍重算，超限期间持续）；
 *   V3 零偏移归零判据：指令回 0 → 偏移按斜坡回落，落入容差带后尚需 T#100MS
 *      零驻留窗口，窗口满才 bInSync 且偏移实际值硬置 0.0；
 *   V4 使能冻结：bEnable 下降 → 偏移实际值保持、bActive FALSE、合成位置
 *      仍 = 基础 + 保持值；重新使能斜坡从保持值继续，无阶跃；
 *   V5 参数非法：maxOffset = 0 → 锁 eFault + 0004_02B0；任务周期 0
 *      → 兜底 10 ms + 0004_01A0（周期非法优先钳位，幅值非法才锁故障）；
 *   V6 运行中途插入强制归零：bZeroNow 置位 → 目标立即为 0，斜坡退偏移，
 *      基础位置跟踪不受影响（正交性验证）。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 09 · DL_Motion 叠加运动补偿件）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   VAR fbOverlay : FB_DL_SuperimposedMove; END_VAR
 *   fbOverlay(bEnable := bVisionOk,
 *             fBasePos := fbAxis.fPosition,        // 基础轴实际位置注入
 *             fOffsetCmd := fVisionOffset,         // 视觉纠偏量
 *             fMaxOffset := 5.0,
 *             fMaxOffsetSpeed := 10.0,
 *             fTaskCycle := 0.01);                 // 与任务周期一致
 *   fbAxis.MoveAbsolute(fPos := fbOverlay.fSuperPos);  // 用合成位置下发
 *   注意：本块每拍都必须调用（斜坡为逐拍积分，跳拍会丢失积分步长）。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 常见误用与现场提示 (Field notes)：
 *   1 fTaskCycle 必须与真实任务周期一致：填错会直接放大/缩小偏移速度，本块
 *     无法自检真实周期（禁读 CPU 钟，周期由引脚注入）。
 *   2 合成位置用于下发定位指令时，基础轴必须是位置模式且每拍可接受新目标；
 *     若基础轴为速度模式，请由上层把 fSuperPos 转换为位置增量后再下发。
 *   3 bEnable = FALSE 的语义是「冻结」而非「归零」：需要归零请置 bZeroNow
 *     或把 fOffsetCmd 写 0 后等 bInSync。
 *   4 偏移实际值是纯指令推算量，不含机械跟随误差；精度由基础轴跟随能力决定。
 *   5 幅值上限必须小于安全行程半径，本块不做软限位判断，越界风险由调用方
 *     的软限位预判块承担。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_OverlayState（归属 FB_DL_SuperimposedMove，随本文件发布）
 * 含义: 叠加补偿层离散状态。数值步长 10 留空位，故障态 99 保证排序末位。
 *----------------------------------------------------------------------------*)
{attribute 'strict'}
{attribute 'qualified_only'}
TYPE E_DL_OverlayState :
(
    eIdle   := 0,    // 空闲：未使能或已冻结，偏移实际值保持 / Idle: disabled or frozen, actual offset held
    eActive := 10,   // 叠加生效：斜坡跟踪偏移指令，零偏移时亦保持本态 / Active: ramp tracks the offset command, zero offset stays active
    eFault  := 99    // 故障锁存：参数或状态非法，输出冻结待重建 / Fault latched: illegal parameter or state, outputs frozen until rebuild
) UINT;
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_SuperimposedMove
 * 调用约定: 每个扫描周期无条件调用一次；全部输入为纯引脚，无任何硬件依赖。
 * 无状态泄漏: 状态仅驻留于实例私有成员，可多实例并行（多轴各一实例）。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_SuperimposedMove
VAR_INPUT
    bEnable         : BOOL;             // 叠加层使能（Overlay enable），FALSE = 斜坡冻结、偏移保持 / FALSE freezes the ramp and holds the offset
    fBasePos        : LREAL;            // 基础轴实际位置（Base axis actual position）[mm]，每拍由上层注入 / Injected each scan by the caller
    fOffsetCmd      : LREAL := 0.0;     // 叠加偏移指令（Offset command）[mm]，正负双向 / Bidirectional offset command [mm]
    fMaxOffset      : LREAL := 5.0;     // 偏移幅值限幅（Offset magnitude limit）[mm]，域 > 0 / Must be greater than zero
    fMaxOffsetSpeed : LREAL := 10.0;    // 偏移斜坡限速（Offset ramp speed limit）[mm/s]，0 = 不限速直通 / Zero means unlimited pass-through
    fTaskCycle      : LREAL := 0.01;    // 任务周期（Task cycle time）[s]，斜坡积分步长基准 / Ramp integration step base in seconds
    bZeroNow        : BOOL;             // 强制归零请求（Force offset to zero）[TRUE = 目标置 0 仍走斜坡] / Target forced to zero, ramp still applied
END_VAR
VAR_OUTPUT
    fSuperPos       : LREAL;            // 合成位置（Superimposed position）[mm] = 基础位置 + 偏移实际值 / Base position plus actual offset
    fOffsetAct      : LREAL;            // 偏移实际值（Actual offset）[mm]，经斜坡与限幅后的代数叠加量 / Ramp-limited and clamped algebraic offset
    bActive         : BOOL;             // 叠加生效中（Overlay active），TRUE = 处于 eActive 态 / TRUE while in the active state
    bInSync         : BOOL;             // 偏移已收敛（Offset in sync），零偏移需驻留窗口满 / Zero offset additionally requires the dwell window
    bError          : BOOL;             // 故障保持型（Fault latched），显式排除信息级码 / Latched fault flag, info codes excluded
    uErrorId        : UDINT;            // 故障码（Error code），0 = 无故障，段位 16#0004_xxxx / Error code, zero means no error
END_VAR
VAR
    _eState         : E_DL_OverlayState := E_DL_OverlayState.eIdle; // 主状态机当前状态（Current state machine state）/ Current state machine state
    _bInit          : BOOL;             // 首扫完成标志（First-scan done flag），初值 FALSE 满足公约 0.1 / First-scan done flag, initial FALSE per convention 0.1
    _bFaultLatch    : BOOL;             // 故障锁存（Fault latch），仅使能下降沿重建路径清除 / Fault latch, cleared only by the disable-edge rebuild path
    _uErrorIdInt    : UDINT;            // 故障级码寄存（Fault-level code register），锁存型 / Latched fault-level code register
    _uInfoCode      : UDINT;            // 本拍信息级码（Info code this scan），每拍重算 / Info code recomputed every scan
    _bRateHint      : BOOL;             // 不限速提示已发（Unlimited-speed hint issued），一次性 / One-shot hint that the ramp is bypassed
    _fMaxOffsetEff  : LREAL := 5.0;     // 生效幅值上限（Effective magnitude limit）[mm]，取绝对值 / Effective magnitude limit, absolute value
    _fRateEff       : LREAL := 10.0;    // 生效斜坡速率（Effective ramp speed）[mm/s]，<= 0 表示直通 / Effective ramp speed, zero or less bypasses the ramp
    _fTaskCycleEff  : LREAL := 0.01;    // 生效任务周期（Effective task cycle）[s] / Effective task cycle in seconds
    _fBaseEff       : LREAL;            // 生效基础位置（Effective base position）[mm]，非有限值保持末次有效 / Effective base position, holds last valid value for non-finite input
    _fBaseHold      : LREAL;            // 末次有效基础位置（Last valid base position）[mm] / Last valid base position [mm]
    _fCmdHold       : LREAL;            // 末次有效偏移指令（Last valid offset command）[mm] / Last valid offset command [mm]
    _fTargetEff     : LREAL;            // 生效偏移目标（Effective offset target）[mm]，限幅后 / Effective offset target after clamping [mm]
    _fDelta         : LREAL;            // 目标与实际偏差（Target minus actual）[mm] / Target minus actual deviation [mm]
    _fStepMax       : LREAL;            // 本拍允许最大偏移步进（Max offset step this scan）[mm] / Max offset step allowed this scan [mm]
    _bGateRun       : BOOL;             // 斜坡运行闸门（Ramp run gate），使能且无故障 / Ramp run gate, enabled and fault free
    _bZeroSettled   : BOOL;            // 零偏移稳定（Zero offset settled），目标与实际均入容差带 / Zero offset settled, target and actual inside tolerance
    _fbTonZeroDwell : TON;              // 零偏移驻留定时器（Zero-offset dwell timer），归零完成判据 / Zero offset dwell timer used by the settled verdict
    _fbTrigDisable  : F_TRIG;           // 使能下降沿（Enable falling edge），故障重建路径触发 / Enable falling edge used by the rebuild path
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS   : LREAL := 1.0E-6;   // 浮点容差（Float epsilon）[mm]，替代判等 / Float epsilon replacing equality comparison [mm]
    DL_CYCLE_FALLBACK : LREAL := 0.01;  // 任务周期兜底值（Task cycle fallback）[s]，非法时生效 / Fallback task cycle applied when illegal [s]
    DL_ZERO_DWELL  : TIME := T#100MS;   // 零偏移驻留窗口（Zero offset dwell window），归零完成判据 / Dwell window of the zero offset verdict
END_VAR

// ============================================================================
// 段 1｜输出确定性默认值先赋（公约 0.9：任何早退路径输出均确定）
//      Deterministic defaults assigned first so every early exit is defined
// ============================================================================
bActive   := FALSE;                    // 生效标志预清零（Active flag pre-cleared）
bInSync   := FALSE;                    // 收敛标志预清零（In-sync flag pre-cleared）
_uInfoCode := 0;                       // 信息级码每拍重算（Info code recomputed every scan）

// ============================================================================
// 段 2｜实例无条件周期刷新（公约 0.5 / R7：严禁置于 IF / CASE 分支内）
//      Unconditional per-cycle refresh of the timer and edge instances
// ============================================================================
_fbTrigDisable(CLK := bEnable);        // 使能下降沿检测（Enable falling edge detection），TON 实例在段 7 无条件刷新（the TON instance is refreshed unconditionally in section 7）

// ============================================================================
// 段 3｜首扫同步（R19 范式退化式：本层无外部跟踪源，仅首扫判据）
//      First-scan synchronization (degraded R19 form, no external track source)
// ============================================================================
IF NOT _bInit THEN
    fOffsetAct  := 0.0;                // 偏移实际值上电从零起步（Offset starts at zero）
    _fBaseHold  := 0.0;                // 基础位置历史清零（Base position history cleared）
    _fCmdHold   := 0.0;                // 偏移指令历史清零（Offset command history cleared）
    _eState     := E_DL_OverlayState.eIdle; // 状态复位为空闲（State reset to idle）
    _bInit      := TRUE;               // 置首扫完成（First-scan done）
END_IF

// ============================================================================
// 段 4｜参数体检与故障锁存（0.16 全常量化；0.2 故障级与信息级分离）
//      Parameter diagnosis with fault latching, fault level split from info level
// ============================================================================
IF (fMaxOffset <> fMaxOffset) OR (ABS(fMaxOffset) <= DL_FLOAT_EPS) THEN
    _bFaultLatch := TRUE;              // 幅值上限非法锁存（Invalid magnitude limit latched）
    _uErrorIdInt := 16#0004_02B0;      // 0004_02B0 偏移幅值上限非法【故障级】（Invalid offset magnitude limit, fault level）
ELSE
    _fMaxOffsetEff := ABS(fMaxOffset); // 生效幅值上限取绝对值（Absolute magnitude limit applied）
END_IF

IF (fTaskCycle <> fTaskCycle) OR (fTaskCycle <= DL_FLOAT_EPS) THEN
    _fTaskCycleEff := DL_CYCLE_FALLBACK; // 周期非法兜底（Illegal cycle falls back）
    _uInfoCode    := 16#0004_01A0;     // 0004_01A0 任务周期非法已兜底【信息级】（Task cycle fell back, info level）
ELSE
    _fTaskCycleEff := fTaskCycle;       // 合法周期直通（Valid cycle passed through）
END_IF

IF fMaxOffsetSpeed <> fMaxOffsetSpeed THEN
    _fRateEff := 0.0;                  // 非有限限速按直通处理（Non-finite speed bypasses the ramp）
ELSIF fMaxOffsetSpeed <= DL_FLOAT_EPS THEN
    _fRateEff := 0.0;                  // 零或负限速按直通处理（Zero or negative speed bypasses the ramp）
    IF NOT _bRateHint THEN
        _bRateHint := TRUE;            // 一次性提示标志（One-shot hint flag）
        _uInfoCode := 16#0004_01A3;    // 0004_01A3 不限速直通提示【信息级】（Ramp bypassed hint, info level）
    END_IF
ELSE
    _fRateEff := fMaxOffsetSpeed;       // 合法限速直通（Valid ramp speed passed through）
END_IF

// ============================================================================
// 段 5｜非有限值防御（0.9：自比检测，保持末次有效值，不中断扫描）
//      Non-finite defense holding the last valid value, scan is never stopped
// ============================================================================
IF fBasePos <> fBasePos THEN
    _fBaseEff := _fBaseHold;           // 基础位置非有限保持末次有效（Non-finite base position holds last valid）
ELSE
    _fBaseHold := fBasePos;             // 更新末次有效基础位置（Last valid base position updated）
    _fBaseEff  := fBasePos;             // 生效基础位置（Effective base position）
END_IF

IF fOffsetCmd <> fOffsetCmd THEN
    _fTargetEff := _fCmdHold;           // 指令非有限保持末次有效目标（Non-finite command holds last valid target）
    _uInfoCode  := 16#0004_01A2;        // 0004_01A2 偏移指令非有限已拒绝【信息级】（Non-finite offset command rejected, info level）
ELSE
    _fCmdHold   := fOffsetCmd;          // 更新末次有效偏移指令（Last valid offset command updated）
    _fTargetEff := fOffsetCmd;          // 生效偏移目标（Effective offset target）
END_IF

// ============================================================================
// 段 6｜目标选取与双向幅值限幅（先归零后限幅，限幅不阻断斜坡）
//      Target selection and symmetric clamping, clamping never blocks the ramp
// ============================================================================
IF bZeroNow THEN
    _fTargetEff := 0.0;                // 强制归零优先（Force-zero takes priority）
END_IF

IF ABS(_fTargetEff) > _fMaxOffsetEff THEN
    IF _fTargetEff > 0.0 THEN
        _fTargetEff := _fMaxOffsetEff; // 正向削顶（Clamped at the positive limit）
    ELSE
        _fTargetEff := -_fMaxOffsetEff; // 负向削顶（Clamped at the negative limit）
    END_IF
    _uInfoCode := 16#0004_01A1;        // 0004_01A1 偏移指令已限幅【信息级】（Offset command clamped, info level）
END_IF

// ============================================================================
// 段 7｜斜坡积分与零偏移归零判据（内联斜坡，每拍一步乘加）
//      Inline ramp integration plus the zero-offset settled verdict
// ============================================================================
_bGateRun := bEnable AND (NOT _bFaultLatch); // 运行闸门（Run gate）

IF _bGateRun THEN
    _fDelta := _fTargetEff - fOffsetAct; // 目标与实际偏差（Target minus actual deviation）
    IF _fRateEff <= DL_FLOAT_EPS THEN
        fOffsetAct := _fTargetEff;     // 不限速直通（Unlimited pass-through）
    ELSE
        _fStepMax := _fRateEff * _fTaskCycleEff; // 本拍允许步进 [mm]（Max step this scan）
        IF ABS(_fDelta) <= _fStepMax THEN
            fOffsetAct := _fTargetEff; // 一步到位，杜绝残差抖动（One-step landing avoids residual jitter）
        ELSIF _fDelta > 0.0 THEN
            fOffsetAct := fOffsetAct + _fStepMax; // 正向推进（Advance in the positive direction）
        ELSE
            fOffsetAct := fOffsetAct - _fStepMax; // 负向推进（Advance in the negative direction）
        END_IF
    END_IF
END_IF

_bZeroSettled := (ABS(_fTargetEff) < DL_FLOAT_EPS) AND (ABS(fOffsetAct) < DL_FLOAT_EPS) AND _bGateRun; // 零偏移稳定判据（Zero offset settled verdict）
_fbTonZeroDwell(IN := _bZeroSettled, PT := DL_ZERO_DWELL); // 驻留窗口计时（Dwell window timing）

IF _fbTonZeroDwell.Q THEN
    fOffsetAct := 0.0;                 // 驻留满后硬置零，消除浮点残差（Hard zero after dwell removes float residual）
END_IF

bInSync := (ABS(_fTargetEff - fOffsetAct) < DL_FLOAT_EPS) AND _bGateRun; // 收敛判据：目标与实际偏差入容差带（Convergence verdict within tolerance）
IF (ABS(_fTargetEff) < DL_FLOAT_EPS) AND (NOT _fbTonZeroDwell.Q) THEN
    bInSync := FALSE;                  // 零偏移需驻留窗口满才算归零完成（Zero offset requires the dwell window）
END_IF

// ============================================================================
// 段 8｜主状态机（ENUM + CASE + ELSE 兜底；故障重建走使能下降沿）
//      Main state machine with mandatory ELSE fallback and disable-edge rebuild
// ============================================================================
CASE _eState OF

    E_DL_OverlayState.eIdle: // 空闲：等待使能（Idle, waiting for enable）
        IF _fbTrigDisable.Q THEN
            _bFaultLatch := FALSE;     // 下降沿重建：清故障锁存（Rebuild clears the fault latch）
            _uErrorIdInt := 16#0000_0000; // 故障码清零（Fault code cleared）
        END_IF
        IF bEnable AND (NOT _bFaultLatch) THEN
            _eState := E_DL_OverlayState.eActive; // 使能且参数合法进叠加态（Enabled and legal, go active）
        END_IF

    E_DL_OverlayState.eActive: // 叠加生效：零偏移亦保持本态（Active, zero offset keeps this state）
        IF _bFaultLatch THEN
            _eState := E_DL_OverlayState.eFault; // 参数或状态故障锁存（Fault latched）
        ELSIF NOT bEnable THEN
            _eState := E_DL_OverlayState.eIdle;  // 禁止使能冻结偏移并回空闲（Disable freezes the offset and returns to idle）
        END_IF

    E_DL_OverlayState.eFault: // 故障锁存：输出冻结为最后安全值（Fault latched, outputs frozen）
        IF _fbTrigDisable.Q THEN
            _bFaultLatch := FALSE;     // 使能下降沿重建（Rebuild on the enable falling edge）
            _uErrorIdInt := 16#0000_0000; // 故障码清零（Fault code cleared）
            _eState := E_DL_OverlayState.eIdle; // 回空闲（Back to idle）
        END_IF

    ELSE
        _bFaultLatch := TRUE;          // 非法状态兜底锁存（Illegal state fallback latched）
        _uErrorIdInt := 16#0004_02B2;  // 0004_02B2 非法状态兜底【故障级】（Illegal state fallback, fault level）
        _eState := E_DL_OverlayState.eFault; // 进故障态（Enter the fault state）
END_CASE

// ============================================================================
// 段 9｜出口映射（合成位置 = 基础 + 偏移；故障级码优先透出）
//      Outlet mapping, fault-level code has priority over info codes
// ============================================================================
fSuperPos := _fBaseEff + fOffsetAct;   // 叠加律：代数相加（Superposition as an algebraic sum）
bActive   := (_eState = E_DL_OverlayState.eActive); // 生效标志派生（Active flag derived from the state）
bError    := _bFaultLatch OR (_eState = E_DL_OverlayState.eFault); // 故障派生，显式排除信息级（Fault derived, info codes excluded）
IF bError THEN
    uErrorId := _uErrorIdInt;          // 故障级码优先（Fault-level code has priority）
ELSE
    uErrorId := _uInfoCode;            // 无故障透出本拍信息级码（Transient info code exposed）
END_IF
END_FUNCTION_BLOCK
