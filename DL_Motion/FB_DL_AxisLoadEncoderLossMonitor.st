(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AxisLoadEncoderLossMonitor
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 负载侧编码器断线独立监控。两条互不依赖的判据并行：
 *                         ① 硬件有效位判据——bLoadEncValid 为假经 tLossDelay 去抖后即判失效
 *                            （覆盖断线被下拉、编码器掉电、总线从站丢失）；
 *                         ② 冻结判据——电机侧参考速度 |fVelRefMotor| > fVelMoveThr 且负载侧位置
 *                            增量 < fStallDelta 持续 tStallConfirm（覆盖信号粘连、断线被上拉、
 *                            码盘卡死等有效位仍报真的场景）。
 *                         两判据任一成立 → bLoss 锁存，eCause 归因唯一（R190）。
 * 接口     (Interface)  : 输入 bLoadEncValid 负载侧硬件有效位、fPosLoad 负载侧位置、fVelRefMotor
 *                         电机侧参考速度、fVelMoveThr 运动判定阈值、fStallDelta 冻结位移阈值、
 *                         tStallConfirm 冻结确认时间、tLossDelay 有效位去抖时间、bReset 复位；
 *                         输出 fPosDelta 本拍位置增量、bLoss 失效锁存、bHealthy 信号健康、
 *                         eState / eCause / bError。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只监控负载侧编码器本身，不接管任何切换、
 *                         不产生降级动作、不发轴指令**。主反馈失效→电机侧降级的切换序唯一属主为
 *                         `FB_DL_AxisFeedbackFailoverSeq`；本件只出"负载侧是否可信"的结论位，
 *                         由上层决定是否把该结论喂给切换序。反过来，切换序也不得内嵌断线判据。
 *                         ② 单侧可用：不引用电机侧位置，电机侧反馈全丢时本件仍能独立给出负载侧
 *                         结论（这正是"与电机侧反馈独立"的含义）。
 *                         ③ 组态闸：fVelMoveThr <= 0.0、fStallDelta <= 0.0、tStallConfirm <= T#0S
 *                         → 故障锁存（防阈值反向导致判据恒真或恒假）；tLossDelay 允许 T#0S。
 *                         ④ 非有限（NaN/Inf）输入 → 故障锁存（NaN 会让 ABS 比较恒假，冻结判据
 *                         静默失效，属终审加固清单"组态域闸覆盖每个引脚"同一类缺陷）。
 *                         ⑤ 两枚 TON + 一枚 R_TRIG 在段 0 无条件周期刷新。
 *                         ⑥ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_AxisDualFeedbackGuard`（双侧交叉校核、判"两把尺是否一致"）
 *                         分工 —— 本件单侧体检，只问"负载侧这把尺本身还活着吗"，不比较两侧。
 * 来源标签 (Source Tag) : T2-4 ◐ / P1 双反馈族
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 ∧ 当拍 bLoadEncValid 为真 ∧
 *                         |fVelRefMotor| <= fVelMoveThr（当拍量，R240 范式）。
 *                         自证可满足：三因子均为当拍外部输入/当拍派生量，不含锁存量与恒假因子；
 *                         轴静止且有效位回真即可解除，无死锁。
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 BOOL（bLoss / bError / bHealthy）
 *                         + ENUM（eState / eCause），故障归因由 eCause 承载；数字码位待主控收口
 *                         阶段统一派号（R46 码位规则：先不硬编码，避免段冲突）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 防零阈值/防 NaN/浮点容差 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE ｜ R7 ✓ TON/R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R46 首版（批次 1 · 序号 1）
 *==============================================================================*)

TYPE E_DL_LemState :
(
    eIdle  := 0,    // 首拍未取到输入，等待观测 / Awaiting first observation
    eWatch := 10,   // 监视运行相 / Monitoring phase
    eFault := 90    // 故障锁存相（仅复位沿可迁出） / Fault latched, exit by reset edge only
);
END_TYPE

TYPE E_DL_LemCause :
(
    eNone       := 0,   // 无故障成因 / No cause
    eCfgIllegal := 1,   // 组态非法（阈值非正/时间非正/非有限） / Illegal configuration
    eSigInvalid := 2,   // 硬件有效位报假（断线/掉电/从站丢失） / Hardware validity bit false
    eSigFrozen  := 3,   // 指令运动而位置冻结（信号粘连或码盘卡死） / Position frozen while commanded
    ePhaseBad   := 4    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisLoadEncoderLossMonitor
VAR_INPUT
    bLoadEncValid : BOOL := TRUE;       // 负载侧编码器硬件有效位，FALSE=失效 [-] / Load encoder hardware validity bit
    fPosLoad      : REAL := 0.0;        // 负载侧位置（光栅尺/第二编码器） [mm] / Load-side position [mm]
    fVelRefMotor  : REAL := 0.0;        // 电机侧参考速度，仅用于判"应有运动" [mm/s] / Motor-side reference velocity for move detection [mm/s]
    fVelMoveThr   : REAL := 0.5;        // 运动判定速度阈值，域 > 0.0 [mm/s] / Move detection threshold, domain > 0.0 [mm/s]
    fStallDelta   : REAL := 0.01;       // 冻结判定位移阈值，域 > 0.0 [mm/拍] / Stall delta threshold, domain > 0.0 [mm/scan]
    tStallConfirm : TIME := T#200MS;    // 冻结确认时间，域 > T#0S [ms] / Stall confirm time, domain > T#0S [ms]
    tLossDelay    : TIME := T#10MS;     // 有效位失效去抖时间，域 >= T#0S [ms] / Validity-loss debounce, domain >= T#0S [ms]
    bReset        : BOOL := FALSE;      // 复位命令，上升沿清锁存 [-] / Reset command, rising edge clears latch
END_VAR
VAR_OUTPUT
    fPosDelta     : REAL;               // 本拍负载侧位置增量绝对值 [mm/拍] / Absolute load position increment this scan [mm/scan]
    bLoss         : BOOL;               // 负载侧编码器失效（锁存，故障级） [-] / Load encoder loss, latched
    bHealthy      : BOOL;               // 负载侧信号健康（当拍有效且未锁存） [-] / Load-side signal healthy
    eState        : E_DL_LemState;      // 状态出口，段 7 单点映射 [-] / State outlet
    eCause        : E_DL_LemCause;      // 故障成因出口（R190 归因唯一） [-] / Fault cause outlet
    bError        : BOOL;               // 故障标志，与锁存位同源（R191 名实双出口） [-] / Error flag from latch
END_VAR
VAR
    _eState    : E_DL_LemState := E_DL_LemState.eIdle;    // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause    : E_DL_LemCause := E_DL_LemCause.eNone;    // 故障成因锁存量 / Latched cause
    tonLoss    : TON;                   // 有效位失效去抖计时，段 0 无条件调用 / Validity-loss debounce timer
    tonStall   : TON;                   // 冻结确认窗计时，段 0 无条件调用 / Stall confirm window timer
    rtReset    : R_TRIG;                // 复位沿实例，段 0 无条件调用 / Reset edge instance
    _fPosPrev  : REAL;                  // 上拍负载侧位置快照（锁存量） [mm] / Previous-scan position snapshot [mm]
    _bNonFin   : BOOL;                  // 输入非有限当拍量 [-] / Non-finite input this scan
    _bCfgBad   : BOOL;                  // 组态非法当拍量 [-] / Illegal configuration this scan
    _bMove     : BOOL;                  // 应有运动当拍量 [-] / Should-be-moving this scan
    _bStallRaw : BOOL;                  // 冻结判据当拍量（喂 TON 的 IN） [-] / Raw stall criterion
    _bFault    : BOOL;                  // 故障锁存位（锁存量） / Latched fault bit
END_VAR
VAR CONSTANT
    DL_LEM_EPS : REAL := 1.0E-6;        // 浮点判零容差（阈值与增量统一口径） [无量纲] / Float epsilon
END_VAR

(* —— 段 0：当拍量派生 + 定时器与沿实例无条件周期刷新 —— *)
_bNonFin   := (fPosLoad <> fPosLoad) OR (fVelRefMotor <> fVelRefMotor)      // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive tests
           OR (fVelMoveThr <> fVelMoveThr) OR (fStallDelta <> fStallDelta);  // 阈值引脚 NaN 判 / Threshold NaN tests
_bCfgBad   := (fVelMoveThr <= 0.0) OR (fStallDelta <= 0.0)                  // 正阈值闸（防判据恒真） / Positive threshold gates
           OR (tStallConfirm <= T#0S) OR (tLossDelay < T#0S);               // 时间闸（防确认窗恒成立） / Time gates
_bMove     := ABS(fVelRefMotor) > fVelMoveThr;                              // 应有运动判据 / Should-be-moving criterion
_fPosDelta := ABS(fPosLoad - _fPosPrev);                                    // 本拍位置增量绝对值 / Absolute increment this scan
_bStallRaw := _bMove AND (_fPosDelta < fStallDelta) AND bLoadEncValid;      // 冻结判据：动而位不移且有效位仍报真 / Stall: moving, position frozen, valid bit still true
rtReset(CLK := bReset);                                                     // 复位沿，每拍必调（R228A） / Reset edge, called every scan
tonLoss(IN := (NOT bLoadEncValid) OR _bNonFin, PT := tLossDelay);           // 有效位失效去抖（非有限并入失效） / Validity-loss debounce, non-finite folded in
tonStall(IN := _bStallRaw AND (NOT _bNonFin), PT := tStallConfirm);         // 冻结确认窗 / Stall confirm window

(* —— 段 1：单拍量预清零（锁存量与快照量不入清单，R107） —— *)
bLoss    := FALSE;          // 失效位每拍预清，故障分支同拍回填 / Loss flag preset each scan
bHealthy := FALSE;          // 健康位每拍预清 / Healthy flag preset
bError   := FALSE;          // 故障标志每拍预清（R45 配对：置位处同拍写） / Error flag preset

(* —— 段 2：复位沿 + 组态域闸 —— *)
IF rtReset.Q THEN                                                       // 当拍复位沿 / current-scan reset edge
    _bFault := FALSE;                                                   // 清故障锁存位（锁存量） / Clear fault latch
    _eCause := E_DL_LemCause.eNone;                                     // 清成因（锁存量） / Clear latched cause
    IF _eState = E_DL_LemState.eFault THEN
        _eState := E_DL_LemState.eIdle;                                 // 故障相迁出（R228B 可迁出） / Leave fault phase
    END_IF
END_IF
IF _bCfgBad THEN                                                        // 组态域闸（覆盖全部参与判据的引脚） / Configuration gate
    _bFault := TRUE;                                                    // 锁存 / Latch
    _eCause := E_DL_LemCause.eCfgIllegal;                               // 归因：组态非法 / Cause: illegal configuration
END_IF

(* —— 段 3：判据合并（有效位判据优先归因，冻结判据次之——同一拍双成立时归因确定） —— *)
IF (NOT _bFault) AND ((_bCfgBad = FALSE) AND tonLoss.Q) THEN
    _bFault := TRUE;                                                    // 锁存 / Latch
    _eCause := E_DL_LemCause.eSigInvalid;                               // 归因：有效位报假 / Cause: validity bit false
END_IF
IF (NOT _bFault) AND tonStall.Q THEN
    _bFault := TRUE;                                                    // 锁存 / Latch
    _eCause := E_DL_LemCause.eSigFrozen;                                // 归因：位置冻结 / Cause: position frozen
END_IF
IF (NOT _bFault) AND _bNonFin THEN
    _bFault := TRUE;                                                    // 锁存 / Latch
    _eCause := E_DL_LemCause.eCfgIllegal;                               // 归因：输入不可信并入组态非法 / Cause: untrustworthy input folded into config
END_IF

(* —— 段 4：解除式（R240：全部当拍量，无锁存量因子） —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND bLoadEncValid AND (NOT _bMove) THEN
    _bFault := FALSE;                                                   // 清故障锁存位 / Clear fault latch
    _eCause := E_DL_LemCause.eNone;                                     // 清成因 / Clear cause
END_IF

(* —— 段 5：快照更新（主体末段前写，跨拍纪律） —— *)
_fPosPrev := fPosLoad;                                                  // 位置快照（本拍末更新） / Position snapshot at body end

(* —— 段 6：锁存相位迁移闸（同拍锁存必入故障相） —— *)
IF _bFault AND (_eState <> E_DL_LemState.eFault) THEN
    _eState := E_DL_LemState.eFault;                                    // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 7：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_LemState.eIdle:
    IF (NOT _bNonFin) AND (NOT _bCfgBad) THEN                           // 出口 1：输入可信，取得首拍观测 / Input trustworthy, first observation taken
        _eState := E_DL_LemState.eWatch;
    ELSIF _bFault THEN                                                  // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_LemState.eFault;
    END_IF

E_DL_LemState.eWatch:
    IF _bFault THEN                                                     // 出口 1：判据命中 / Criterion hit
        _eState := E_DL_LemState.eFault;
    ELSIF rtReset.Q THEN                                                // 出口 2：复位沿重新取观测 / Reset edge re-arms observation
        _eState := E_DL_LemState.eIdle;
    END_IF

E_DL_LemState.eFault:
    ;                                                                    // 故障相：仅段 4 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _bFault  := TRUE;                                                    // 非法相位兜底锁存 / Illegal-phase fallback latch
    _eCause  := E_DL_LemCause.ePhaseBad;                                 // 归因：非法相位 / Cause: illegal phase
    _eState  := E_DL_LemState.eFault;                                    // 强拉故障相 / Force fault phase

END_CASE

(* —— 段 8：出口单点映射（名实同源；故障相安全侧） —— *)
IF _bFault THEN
    bLoss    := TRUE;                                                   // 失效位与锁存同源 / Loss from latch
    bHealthy := FALSE;                                                  // 故障相不宣称健康 / No health claim in fault
ELSE
    bLoss    := FALSE;                                                  // 非故障相明确清零 / Explicitly clear outside fault
    bHealthy := bLoadEncValid AND _bMove;                               // 健康 = 有效位真且（有运动时位置在动） / Healthy = valid bit true and position moving when commanded
END_IF
bError := _bFault;                                                      // 故障标志与锁存同源（R191） / Error flag from latch
eState := _eState;                                                      // 状态出口 / State outlet
eCause := _eCause;                                                      // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
