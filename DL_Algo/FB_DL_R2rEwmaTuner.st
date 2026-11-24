(*==============================================================================
 * 组件名称 (Component)  : FB_DL_R2rEwmaTuner
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 批级工艺微调族 · Run-to-Run
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅依赖 Standard.library（R_TRIG / LIMIT /
 *                         ABS），零厂商方言
 * 功能描述 (Function)   : 逐批（lot）离散更新的工艺参数自动微调器。一个批次采集
 *                         一次实测值，与目标值求偏差，经指数加权移动平均（EWMA）
 *                         平滑后按工艺增益倒数折算为参数修正量，写回下发参数。修
 *                         正量同时受「单次修正限幅」与「参数域上下限」双重约束，
 *                         做到逐批小步收敛而非一次大改，全程可用批次数、EWMA 偏差
 *                         与历史环缓冲审计。
 * 与既有件边界 (Boundary): FB_DL_PidController 是拍级连续闭环；FB_DL_RateLimiter
 *                         限的是信号变化率；本件是批级离散更新（一批只动一次），
 *                         时间尺度差三到四个数量级，三者不可互替。本件不复用
 *                         DL_MathData 的滤波件，EWMA 与限幅全部内联，避免拍级滤波
 *                         语义与批级更新语义混淆。
 * 设计要点 (Key notes)  :
 *   ① 首样本直取（R19 家族教训）：历史无 EWMA 时第一批直接取本批偏差，绝不让 0
 *      参与平均，否则前若干批严重偏置；
 *   ② 单批单次（R24 / R25）：bNewLot 上升沿开启一次事务，eCompute 算、eApply 写，
 *      两态各驻留一拍，同一批次物理上不可能重复修正；
 *   ③ 双约束：修正量先钳到正负 fCorrectionLim（信息级 1F03），参数再钳到参数域，
 *      参数到界只置 bAtLimit 不另占码位（块内码位仅 1F01~1F03 与 1F10）；
 *   ④ 码分级（R21）：1F01 / 1F02 / 1F03 为信息级，只写 uErrorId，不置 bError；
 *      bError 只反映 eFault 态（1F10 测量、目标或增益倒数非有限值，锁存待复位）；
 *   ⑤ 审计：批次计数饱和累加（16#FFFF_FFFE 封顶），偏差写入深度 10 的环形缓冲，
 *      索引环绕前做上下界校验，杜绝数组越界。
 * 开源溯源 (Origin)     : 参考 semiconductor APC（先进过程控制）公开资料与 LGF 公开
 *                         函数库中 Run-to-Run / EWMA 控制的功能分类与参数域（批事务
 *                         四段：测量、平滑、限幅、回写），只借分类、参数域与命名组
 *                         织，clean-room 实现，不构成衍生作品。引脚命名、枚举、状态
 *                         跃迁、故障码与限幅次序 100% 自有。
 * 依赖     (Depends)    : 无 DL_ 内部依赖（不得引用 DL_Motion / DL_Device /
 *                         DL_Process，层次合法性硬约束）；Standard.library: R_TRIG
 * 状态迁移 (Transitions):
 *   eIdle      -- bEnable ----------------------------------> eReady
 *   eReady     -- bNewLot 上升沿 ---------------------------> eCompute
 *   eReady     -- 输入非有限值 -----------------------------> eFault（1F10 锁存）
 *   eCompute   -- 输入非有限值 -----------------------------> eFault（1F10 锁存）
 *   eCompute   -- 无条件（当拍算出偏差、EWMA 与修正量）-----> eApply
 *   eApply     -- 无条件（当拍写参数并出 bCorrected 单拍）--> eReady
 *   eFault     -- bReset 上升沿 ----------------------------> eIdle（参数保持）
 *   非法枚举值 -- CASE ELSE 兜底 ---------------------------> eFault（1F10）
 *   任何态     -- 使能撤除（eFault 除外）-------------------> eIdle（参数保持）
 * 数据流 (Data flow)    :
 *   fMeasure 减 fTarget 得 fDev → EWMA 平滑得 fEwmaDev → 乘负的 fGainInv 得 fCorr
 *   → 单次限幅 → 叠加历史参数 → 参数域钳位 → stHist.fLastParam → fParamOut。
 *   四道关卡次序固定：先限修正量（工艺侧安全），再限参数（设备侧安全），
 *   次序颠倒会让「参数到界」被误报成「修正被限」，现场无法区分根因。
 * 码位表 (Error codes)  :
 *   16#0002_1F01【信息级】EWMA 权重 λ 越出 0~1 已双向钳位；
 *   16#0002_1F02【信息级】历史无 EWMA 样本，本批按首样本直取；
 *   16#0002_1F03【信息级】单次修正量达限幅，已钳到正负限幅值；
 *   16#0002_1F10【故障级】实测值 / 目标值 / 增益倒数非有限值，拒绝本批并锁存。
 *   码优先级：1F03 高于 1F02 高于 1F01（同一拍多条件命中时高者上报）。
 * 验收向量 (Acceptance):
 *   V1 平滑：历史 EWMA 1.0、本批偏差 +2.0、λ 0.3 → EWMA 0.3×2.0+0.7×1.0=1.3；
 *   V2 修正限幅：增益倒数 1.0、EWMA 1.3、限幅 1.0 → 修正钳到 −1.0，参数减 1.0，
 *      bAtLimit 置位，码 1F03；
 *   V3 首样本：无历史、偏差 0.5 → EWMA 0.5（不与 0 平均），码 1F02；
 *   V4 权重钳位：λ 1.5 → 实际 1.0，EWMA 等于本批偏差，码 1F01；
 *   V5 参数到界：参数已在 fParamMax 且修正为正 → 参数保持上限，bAtLimit 置位；
 *   V6 非有限：实测值写入非法浮点 → 参数不变，eState 进 eFault，码 1F10。
 * 已知限制 (Limits)     : ① 单回路单参数，多参数联动需实例化多个本块并共用同一
 *                         批号节拍；② EWMA 只抑制随机波动，不识别系统性漂移的物
 *                         理根因；③ 参数修正为线性增益假设（fGainInv 恒定），强非
 *                         线性工艺应分段使用不同 fGainInv。
 * 规格偏离 (Deviation)  : ① 规格给出的历史成员名带数组前缀却定义为 BOOL，与「布尔
 *                         量 b 前缀」红线冲突，本实现定名 bHasEwma（语义不变，仍承
 *                         担首样本直取判据）；② 规格参数域非法未分配码位，本实现
 *                         只置 bAtLimit 并保持参数域下限，不越块取码。
 * 红线自检 (Redline)    : R1 零全局变量表 / 零外部变量声明 / 零物理地址 ✓
 *                         R2 零占位符 ✓ ｜ R3 纯 IEC 61131-3 ✓
 *                         R4 防除零、防越界、浮点容差（λ 双向钳位、环索引校验）✓
 *                         R5 声明行 100% 中英双语同行注释 ✓
 *                         R6 ENUM + CASE 且 ELSE 兜底，五态各自有标签 ✓
 *                         R7 R_TRIG 实例主体最前部无条件刷新 ✓
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 11 · DL_Algo 1F00 带开带件）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   // stHist 由调用方持有（配方域持久化），跨批次不丢 EWMA
 *   fbTuner(bEnable := bLineReady, bNewLot := bLotDonePulse,
 *           fMeasure := fThicknessMeas, fTarget := fThicknessTarget,
 *           fLambda := 0.30, fGainInv := 2.0,
 *           fCorrectionLim := 0.50, fParamMin := 10.0, fParamMax := 90.0,
 *           fParamInit := 50.0, bReset := bTunerReset);
 *   // 下发值只从 fParamOut 取，禁止在外部再叠一次限幅
 *   fProcessParam := fbTuner.fParamOut;
 *   注：一个批次只允许给一个 bNewLot 上升沿；bCorrected 为单拍脉冲，可直接
 *       作为「本批已修正」事件送追溯系统。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 常见误用与现场提示 (Field notes)：
 *   1 不要在 eCompute 之外自己算 EWMA：本块的 EWMA 状态存在 stHist 内，外部
 *     再算一份会与 bHasEwma 标志脱节。
 *   2 fGainInv 是「参数单位 / 测量单位」的倒数增益：工艺增益变大时应减小该值，
 *     符号错了会越调越偏，调试期建议先给 0.1 倍保守值。
 *   3 fCorrectionLim 给 0 表示禁止修正（只审计不动作），此时 bAtLimit 常置位属
 *     正常组态，不要把 bAtLimit 当故障。
 *   4 bReset 只清 EWMA 与故障，参数保持；若需回到初始参数，请先改 fParamInit
 *     再给 bReset（下一拍装载路径不会重跑，本块以历史参数为准）。
 *   5 批次数 uLotCount 单调累加且饱和，复位不清零，可用于产能与追溯对齐。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_R2rState（归属 DL_Algo，与本功能块同文件发布）
 * 含义: Run-to-Run 批事务状态机，编号间隔 10 预留扩展位。
 *----------------------------------------------------------------------------*)
{attribute 'strict'}
{attribute 'qualified_only'}
TYPE E_DL_R2rState :
(
    eIdle    := 0,     // 空闲：未使能，参数保持历史值，等待使能 / Idle: disabled, parameter held, waiting for enable
    eReady   := 10,    // 就绪：等新批次上升沿，期间做输入有限性体检 / Ready: waiting for a new lot edge and checking input validity
    eCompute := 20,    // 计算：本拍算偏差、EWMA 与修正量（驻留一拍）/ Compute: deviation, EWMA and correction in one scan
    eApply   := 30,    // 回写：本拍写参数并出 bCorrected 单拍（驻留一拍）/ Apply: writes parameter and pulses bCorrected in one scan
    eFault   := 99     // 故障锁存：非有限值进入，仅 bReset 上升沿退出 / Fault latched: entered on non-finite input, exits on bReset edge only
) UINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 结构体: ST_DL_R2rHistory（归属 DL_Algo，与本功能块同文件发布）
 * 含义: 跨周期批历史，由调用方持有（可放配方域随配方切换清零）。
 *----------------------------------------------------------------------------*)
TYPE ST_DL_R2rHistory :
STRUCT
    fLastParam : REAL;                          // 上个批次生效参数 [参数单位]，首扫由 fParamInit 装载 / Last effective parameter in parameter units
    fLastEwma  : REAL;                          // 上个批次平滑偏差 [测量单位]，仅 bHasEwma 为 TRUE 时参与递推 / Last smoothed deviation in measurement units
    bHasEwma   : BOOL;                          // 平滑样本有效标志 [BOOL]，FALSE 表示必须首样本直取 / Smoothed sample valid flag, FALSE forces first-sample take-over
    afDevBuf   : ARRAY[1..10] OF REAL;          // 偏差环形缓冲 [测量单位]，深度 10 与 DL_HIST_DEPTH 一致 / Deviation ring buffer in measurement units, depth ten
    nBufIdx    : INT;                           // 环形缓冲写指针 [槽]，域 1~10，0 表示尚未写入 / Ring write index, range one to ten, zero means empty
END_STRUCT
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_R2rEwmaTuner
 * 调用约定: 每扫描周期无条件调用一次；批事务由上装 bNewLot 上升沿驱动。
 * 无状态泄漏: 全部状态驻留实例私有 VAR 与调用方持有的 stHist，零全局引用。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_R2rEwmaTuner
VAR_INPUT
    bEnable        : BOOL := FALSE;         // 使能 [BOOL]，FALSE 时输出保持上次参数 / Enable, FALSE holds the last parameter
    bReset         : BOOL := FALSE;         // 复位 [BOOL]，上升沿清 EWMA 与故障，参数保持 / Reset, rising edge clears EWMA and fault, keeps parameter
    bNewLot        : BOOL := FALSE;         // 新批次标志 [BOOL]，上升沿开启一次批事务 / New lot flag, rising edge opens one lot transaction
    fMeasure       : REAL := 0.0;           // 本批实测值 [工艺单位]，如膜厚 nm，非有限值判故障 / Measured value of this lot in engineering units
    fTarget        : REAL := 0.0;           // 目标值 [同测量单位]，与 fMeasure 同量纲 / Target value in the same unit as fMeasure
    fLambda        : REAL := 0.30;          // EWMA 权重 [无量纲]，域 0~1，越界双向钳位并置 1F01 / EWMA weight, domain zero to one, clamped both ways
    fGainInv       : REAL := 1.0;           // 工艺增益倒数 [参数单位每测量单位]，0 表示不修正 / Inverse process gain, zero disables correction
    fCorrectionLim : REAL := 1.0;           // 单次修正限幅 [参数单位]，取绝对值，0 表示只审计不动作 / Per-lot correction limit in parameter units, absolute value used
    fParamMin      : REAL := 0.0;           // 参数下限 [参数单位]，与上限对调时自动修复 / Parameter lower bound in parameter units, swapped bounds are repaired
    fParamMax      : REAL := 100.0;         // 参数上限 [参数单位]，等于下限表示参数被钉死 / Parameter upper bound in parameter units, equal bound pins the parameter
    fParamInit     : REAL := 50.0;          // 初始参数 [参数单位]，仅首扫装载一次 / Initial parameter in parameter units, loaded on first scan only
END_VAR
VAR_OUTPUT
    fParamOut      : REAL := 0.0;           // 下发工艺参数 [参数单位]，恒等于历史生效参数 / Output process parameter, always the historical effective value
    fEwmaDev       : REAL := 0.0;           // 平滑后偏差 [测量单位]，本批计算值保持到下批 / Smoothed deviation in measurement units
    bCorrected     : BOOL := FALSE;         // 本批已修正单拍 [BOOL]，只置一拍，下一拍入口清零 / Single-scan pulse when a correction was written
    bAtLimit       : BOOL := FALSE;         // 修正量或参数触限 [BOOL]，逐拍重算 / Correction or parameter at limit, recomputed every scan
    uLotCount      : UDINT := 0;            // 已处理批次数 [批]，饱和累加且复位不清零 / Processed lot count, saturating and not cleared by reset
    eState         : E_DL_R2rState := E_DL_R2rState.eIdle; // 主状态机当前态 [枚举] / Current state of the main state machine
    bError         : BOOL := FALSE;         // 故障锁存 [BOOL]，仅 eFault 态置位，信息级码不置位 / Latched fault, TRUE only in eFault
    uErrorId       : UDINT := 0;            // 事件或故障码 [段位 0002_1Fxx]，0 表示无事件 / Event or fault code in the 0002_1Fxx band, zero means none
END_VAR
VAR_IN_OUT
    stHist         : ST_DL_R2rHistory;      // 跨周期批历史 [结构体]，由调用方持有并持久化 / Persistent batch history held by the caller
END_VAR
VAR
    bInit          : BOOL := FALSE;         // 首扫完成标志 [BOOL]，初值 FALSE，判据恒为 NOT bInit / First-scan done flag, initial FALSE, judged by NOT bInit
    bInputsOk      : BOOL := FALSE;         // 输入有限性判据 [BOOL]，逐拍重算 / Input finiteness verdict, recomputed every scan
    bDomainDeg     : BOOL := FALSE;         // 参数域退化标志 [BOOL]，上下限重合时为 TRUE / Degenerate parameter domain flag, TRUE when bounds coincide
    fLambdaEff     : REAL := 0.30;          // 生效 EWMA 权重 [无量纲]，0~1 / Effective EWMA weight, zero to one
    fCorrLimEff    : REAL := 0.0;           // 生效单次限幅 [参数单位]，取绝对值且非负 / Effective per-lot limit, absolute and non-negative
    fLimLow        : REAL := 0.0;           // 生效参数下限 [参数单位]，已做上下对调修复 / Effective parameter lower bound after repair
    fLimHigh       : REAL := 100.0;         // 生效参数上限 [参数单位]，已做上下对调修复 / Effective parameter upper bound after repair
    fDev           : REAL := 0.0;           // 本批原始偏差 [测量单位]，等于实测减目标 / Raw deviation of this lot, measured minus target
    fCorr          : REAL := 0.0;           // 本批修正量 [参数单位]，已过单次限幅 / Correction of this lot after the per-lot limit
    fParamNew      : REAL := 0.0;           // 候选新参数 [参数单位]，已过参数域钳位 / Candidate parameter after domain clamping
    uErrInfo       : UDINT := 0;            // 本拍瞬时信息码 [段位 0002_1F01~1F03]，逐拍重算 / Transient info code, recomputed every scan
    uErrFault      : UDINT := 0;            // 锁存故障码 [段位 0002_1F10]，仅复位清除 / Latched fault code, cleared by reset only
    fbTrigNewLot   : R_TRIG;                // 新批次上升沿检测实例 / Rising edge detector for the new lot flag
    fbTrigReset    : R_TRIG;                // 复位上升沿检测实例 / Rising edge detector for the reset flag
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS   : REAL := 1.0E-6;        // 浮点判等与判零容差 [无量纲，按比较量量纲同值使用] / Float equality and zero tolerance
    DL_INF_MAX     : REAL := 1.0E30;        // 有限值幅值上限 [无量纲，按各量量纲同值使用] / Finite magnitude upper bound
    DL_LAMBDA_DEF  : REAL := 0.30;          // EWMA 权重默认回退值 [无量纲]，非有限权值时使用 / Default EWMA weight used for non-finite input
    DL_HIST_DEPTH  : INT := 10;             // 历史环缓冲深度 [批]，与结构体数组上界一致 / History ring depth in lots, matching the array bound
    DL_LOT_MAX     : UDINT := 16#FFFF_FFFE; // 批次计数饱和上限 [批]，防累加溢出 / Lot counter saturation limit against overflow
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜边沿实例无条件周期刷新（红线 R7：严禁置于 IF 或 CASE 分支内）
 *      Unconditional edge refresh, never placed inside IF or CASE branches
 *-----------------------------------------------------------------------------*)
fbTrigNewLot(CLK := bNewLot);
fbTrigReset(CLK := bReset);

(*------------------------------------------------------------------------------
 * 段 2｜瞬时输出与瞬时码预清零（单拍标志在每拍入口清零，出口只置位）
 *      Pre-clear transient outputs and info codes at scan entry
 *-----------------------------------------------------------------------------*)
bCorrected := FALSE;                        // 单拍修正脉冲预清零 [BOOL] / Pre-clear the correction pulse
bAtLimit   := FALSE;                        // 触限标志预清零，本拍按条件重算 [BOOL] / Pre-clear the at-limit flag
uErrInfo   := 0;                            // 瞬时信息码预清零，本拍按条件重算 [码] / Pre-clear the transient info code

(*------------------------------------------------------------------------------
 * 段 3｜参数域修复与 EWMA 权重双向钳位（引脚可在线改，故逐拍重算）
 *      Parameter domain repair and two-sided EWMA weight clamping
 *-----------------------------------------------------------------------------*)
IF fParamMax < fParamMin THEN
    fLimLow  := fParamMax;                  // 域上下对调修复：下限取原上限 [参数单位] / Repaired lower bound takes the original upper
    fLimHigh := fParamMin;                  // 域上下对调修复：上限取原下限 [参数单位] / Repaired upper bound takes the original lower
ELSE
    fLimLow  := fParamMin;                  // 合法下限直通 [参数单位] / Valid lower bound passed through
    fLimHigh := fParamMax;                  // 合法上限直通 [参数单位] / Valid upper bound passed through
END_IF

// 退化域判定：上下限重合时参数被钉死，任何修正都等价于到界，只置 bAtLimit 不另占码位
IF ABS(fLimHigh - fLimLow) <= DL_FLOAT_EPS THEN
    bDomainDeg := TRUE;                     // 参数域无自由度 [BOOL] / Parameter domain has no freedom
    fLimHigh   := fLimLow;                  // 收紧上限与下限对齐，保证 LIMIT 的入参有序 [参数单位] / Tighten the upper bound to keep LIMIT arguments ordered
ELSE
    bDomainDeg := FALSE;                    // 参数域有自由度 [BOOL] / Parameter domain has freedom
END_IF

// EWMA 权重 λ 双向钳位：非有限值回默认、负值钳 0、大于 1 钳 1，均置信息级 1F01
IF (fLambda <> fLambda) OR (ABS(fLambda) > DL_INF_MAX) THEN
    fLambdaEff := DL_LAMBDA_DEF;            // 非有限权值回默认 0.30 [无量纲] / Non-finite weight falls back to the default
    uErrInfo   := 16#0002_1F01;             // 【信息级】λ 越界已钳位 / Info: lambda clamped
ELSIF fLambda < 0.0 THEN
    fLambdaEff := 0.0;                      // 负权值钳到 0，EWMA 冻结在上次值 [无量纲] / Negative weight clamped to zero, EWMA frozen
    uErrInfo   := 16#0002_1F01;             // 【信息级】λ 越界已钳位 / Info: lambda clamped
ELSIF fLambda > 1.0 THEN
    fLambdaEff := 1.0;                      // 大于 1 钳到 1，退化为只看本批 [无量纲] / Weight above one clamped, only this lot used
    uErrInfo   := 16#0002_1F01;             // 【信息级】λ 越界已钳位 / Info: lambda clamped
ELSE
    fLambdaEff := fLambda;                  // 合法权值直通 [无量纲] / Valid weight passed through
END_IF

// 单次修正限幅域修复：取绝对值，非有限值按 0 处理（等效禁止修正，由 1F03 表达）
IF (fCorrectionLim <> fCorrectionLim) OR (ABS(fCorrectionLim) > DL_INF_MAX) THEN
    fCorrLimEff := 0.0;                     // 限幅非有限 → 禁止修正，保守不下发 [参数单位] / Non-finite limit disables correction conservatively
ELSE
    fCorrLimEff := ABS(fCorrectionLim);     // 限幅取绝对值，负号无工程意义 [参数单位] / Absolute limit, sign has no engineering meaning
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜输入有限性体检（NaN 自比较是 IEEE754 唯一可靠的判非数手段）
 *      Input finiteness check, NaN self-comparison is the only reliable test
 *-----------------------------------------------------------------------------*)
bInputsOk := NOT ((fMeasure <> fMeasure) OR (ABS(fMeasure) > DL_INF_MAX)
              OR (fTarget <> fTarget)   OR (ABS(fTarget) > DL_INF_MAX)
              OR (fGainInv <> fGainInv) OR (ABS(fGainInv) > DL_INF_MAX));

(*------------------------------------------------------------------------------
 * 段 5｜首扫装载（R19 唯一合法范式：bInit 初值 FALSE，判据 NOT bInit）
 *      First-scan load, the only accepted pattern for initialisation
 *-----------------------------------------------------------------------------*)
IF NOT bInit THEN
    IF (fParamInit <> fParamInit) OR (ABS(fParamInit) > DL_INF_MAX) THEN
        fParamOut := fLimLow;               // 初始参数非法 → 回退参数域下限 [参数单位] / Non-finite initial parameter falls back to the lower bound
    ELSE
        fParamOut := LIMIT(fLimLow, fParamInit, fLimHigh); // 初始参数钳入参数域 [参数单位] / Initial parameter clamped into the domain
    END_IF
    stHist.fLastParam := fParamOut;         // 历史基准同步，之后一律以历史值为准 [参数单位] / Sync the history baseline used from now on
    stHist.fLastEwma  := 0.0;               // 平滑值清零，bHasEwma 为 FALSE 时不会被使用 [测量单位] / Clear smoothed deviation, unused while the flag is FALSE
    stHist.bHasEwma   := FALSE;             // 首样本标志清零，第一批必走直取路径 [BOOL] / Clear the first-sample flag so the first lot takes over directly
    stHist.nBufIdx    := 0;                 // 环索引归零，第一批写入 1 号槽 [槽] / Ring index reset, the first lot writes slot one
    bInit             := TRUE;              // 首扫完成置位 [BOOL] / First scan completed
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜复位（R19：清 EWMA 与故障，参数保持；复位优先于本拍新故障重锁）
 *      Reset clears EWMA and faults, keeps the parameter, takes priority
 *-----------------------------------------------------------------------------*)
IF fbTrigReset.Q THEN
    uErrFault         := 0;                 // 锁存故障码清零 [码] / Clear the latched fault code
    uErrInfo          := 0;                 // 瞬时信息码清零 [码] / Clear the transient info code
    stHist.bHasEwma   := FALSE;             // 平滑样本作废，下批重新首样本直取 [BOOL] / Invalidate the smoothed sample, next lot takes over directly
    stHist.fLastEwma  := 0.0;               // 平滑值清零 [测量单位] / Clear the smoothed deviation
    stHist.nBufIdx    := 0;                 // 环索引归零，审计从空缓冲重新开始 [槽] / Ring index reset, audit restarts from an empty buffer
    fEwmaDev          := 0.0;               // 平滑偏差出口清零 [测量单位] / Clear the smoothed deviation output
    eState            := E_DL_R2rState.eIdle; // 回空闲态 [枚举] / Back to idle
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜使能撤除：回空闲并保持参数（故障锁存优先于使能撤除，防掩盖故障）
 *      Enable removal returns to idle and holds the parameter, faults win
 *-----------------------------------------------------------------------------*)
IF (NOT bEnable) AND (eState <> E_DL_R2rState.eFault) THEN
    eState := E_DL_R2rState.eIdle;          // 强制回空闲，参数由段 9 派生保持 [枚举] / Force idle, the parameter is held by the mapping section
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜主状态机（红线 R6：ENUM + CASE + ELSE 兜底，五态各有标签）
 *      Main state machine with mandatory ELSE fallback and five labelled states
 *-----------------------------------------------------------------------------*)
CASE eState OF

    E_DL_R2rState.eIdle:                    // 空闲：等使能，不做任何参数动作
        IF bEnable THEN
            eState := E_DL_R2rState.eReady; // 使能到位即进就绪 [枚举] / Enable asserted moves to ready
        END_IF

    E_DL_R2rState.eReady:                   // 就绪：等新批次沿；期间持续体检输入有限性
        IF NOT bInputsOk THEN
            uErrFault := 16#0002_1F10;      // 【故障级】输入非有限值，锁存待复位 / Fault: non-finite input latched until reset
            eState    := E_DL_R2rState.eFault;
        ELSIF fbTrigNewLot.Q THEN
            eState := E_DL_R2rState.eCompute; // 批次沿开启事务 [枚举] / Lot edge opens the transaction
        END_IF

    E_DL_R2rState.eCompute:                 // 计算：偏差 → EWMA → 修正量，本拍算完即转
        IF NOT bInputsOk THEN
            uErrFault := 16#0002_1F10;      // 【故障级】输入非有限值，锁存待复位 / Fault: non-finite input latched until reset
            eState    := E_DL_R2rState.eFault;
        ELSE
            fDev := fMeasure - fTarget;     // 本批原始偏差 [测量单位] / Raw deviation of this lot
            IF NOT stHist.bHasEwma THEN
                fEwmaDev        := fDev;    // 首样本直取，绝不与 0 平均 [测量单位] / First sample taken over directly, never averaged with zero
                stHist.bHasEwma := TRUE;    // 置样本有效标志，后续批次走递推 [BOOL] / Mark the sample valid for subsequent recursion
                uErrInfo        := 16#0002_1F02; // 【信息级】无历史样本，首样本直取 / Info: no history, first sample taken over
            ELSE
                fEwmaDev := fLambdaEff * fDev + (1.0 - fLambdaEff) * stHist.fLastEwma; // EWMA 递推 [测量单位] / EWMA recursion
            END_IF
            stHist.fLastEwma := fEwmaDev;   // 平滑值存档供下批递推 [测量单位] / Archive the smoothed value for the next lot
            fCorr := -fEwmaDev * fGainInv;  // 修正量＝负偏差乘增益倒数 [参数单位] / Correction equals negative deviation times inverse gain
            IF ABS(fCorr) > fCorrLimEff THEN
                fCorr     := LIMIT(-fCorrLimEff, fCorr, fCorrLimEff); // 单次限幅，双向钳位 [参数单位] / Per-lot two-sided clamp
                bAtLimit  := TRUE;          // 修正量触限 [BOOL] / Correction at its limit
                uErrInfo  := 16#0002_1F03;  // 【信息级】修正量达限幅 / Info: correction at the per-lot limit
            END_IF
            eState := E_DL_R2rState.eApply; // 算完立即转回写态，两态各驻留一拍 [枚举] / Move to apply, each state stays exactly one scan
        END_IF

    E_DL_R2rState.eApply:                   // 回写：参数钳入参数域 → 记审计 → 出单拍
        fParamNew := LIMIT(fLimLow, stHist.fLastParam + fCorr, fLimHigh); // 参数域第二重约束 [参数单位] / Domain clamping as the second constraint
        IF (ABS(fParamNew - fLimHigh) <= DL_FLOAT_EPS) OR (ABS(fParamNew - fLimLow) <= DL_FLOAT_EPS) THEN
            bAtLimit := TRUE;               // 参数顶到域边界，只置触限标志不另占码位 [BOOL] / Parameter pinned at a bound, flag only
        END_IF
        IF bDomainDeg THEN
            bAtLimit := TRUE;               // 退化域下任何修正都等价于到界 [BOOL] / Degenerate domain makes every correction a limit hit
        END_IF
        stHist.fLastParam := fParamNew;     // 历史参数推进，出口由段 9 派生 [参数单位] / Advance the historical parameter, mapped in the final section
        stHist.nBufIdx    := stHist.nBufIdx + 1; // 环写指针前进一格 [槽] / Advance the ring write index
        IF stHist.nBufIdx < 1 THEN
            stHist.nBufIdx := 1;            // 下界校验：索引不得小于 1 [槽] / Lower bound guard, index never below one
        ELSIF stHist.nBufIdx > DL_HIST_DEPTH THEN
            stHist.nBufIdx := 1;            // 上界校验：越界即环绕回首槽 [槽] / Upper bound guard, wrap to the first slot
        END_IF
        IF (stHist.nBufIdx >= 1) AND (stHist.nBufIdx <= DL_HIST_DEPTH) THEN
            stHist.afDevBuf[stHist.nBufIdx] := fDev; // 偏差写入环缓冲 [测量单位] / Write the deviation into the ring buffer
        END_IF
        IF uLotCount < DL_LOT_MAX THEN
            uLotCount := uLotCount + 1;     // 批次计数饱和累加，封顶不溢出 [批] / Saturating lot counter
        END_IF
        bCorrected := TRUE;                 // 单拍修正脉冲，下一拍入口由段 2 清零 [BOOL] / Single-scan correction pulse, cleared at the next scan entry
        eState     := E_DL_R2rState.eReady; // 本批事务结束，回就绪等下一批 [枚举] / Transaction finished, back to ready

    E_DL_R2rState.eFault:                   // 故障锁存：参数保持，仅复位沿退出
        bCorrected := FALSE;                // 故障态不再输出修正脉冲 [BOOL] / No correction pulse while faulted
        bAtLimit   := FALSE;                // 故障态触限标志无意义，保持清零 [BOOL] / At-limit flag cleared while faulted

    ELSE                                    // 非法状态兜底：一律回故障态并复用本块最高优先故障码
        uErrFault := 16#0002_1F10;          // 【故障级】非法状态兜底，复用 1F10 / Fault: illegal state fallback reusing 1F10
        eState    := E_DL_R2rState.eFault;  // 强制进故障锁存 [枚举] / Force the latched fault state

END_CASE

(*------------------------------------------------------------------------------
 * 段 9｜出口映射（派生式：信息级码只进 uErrorId，bError 只反映 eFault 态）
 *      Output mapping, info codes never raise the fault flag
 *-----------------------------------------------------------------------------*)
fParamOut := stHist.fLastParam;             // 下发参数恒等于历史生效参数 [参数单位] / Output parameter always mirrors the historical effective value
bError    := (eState = E_DL_R2rState.eFault); // 故障标志只由 eFault 态派生 [BOOL] / Fault flag derived from the fault state only
IF eState = E_DL_R2rState.eFault THEN
    uErrorId := uErrFault;                  // 故障态上报锁存码，不被本拍信息码覆盖 [码] / Report the latched code while faulted
ELSE
    uErrorId := uErrInfo;                   // 运行态上报本拍瞬时信息码 [码] / Report the transient info code while running
END_IF

END_FUNCTION_BLOCK
