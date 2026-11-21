(*==============================================================================
 * 组件名称 (Component)  : FB_DL_VacuumGaugeMux
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 真空测量 · 双表量程选择与读数融合
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版）语法，
 *                         仅依赖 Standard.library（R_TRIG / LN / EXPT / ABS）
 * 功能描述 (Function)   : 皮拉尼（粗抽）与电容膜片（精抽）双真空计的量程选择、重叠区
 *                         交叉校验与读数融合。带切换迟滞防抖动、双表一致性判定、
 *                         不一致锁存与人工确认、以及按十倍程给出的偏差量化值。
 * 分层声明 (Layering)   : ① 本件只做「两表读数融合与一致性裁决」，不做采集调度、
 *                         不做线性化（皮拉尼的非线性修正由变送器或上位标定曲线承担）；
 *                         ② 不做腔体工艺联锁（联锁由工艺层消费融合后的单值压力）；
 *                         ③ 质量码复用设备层既有信号质量枚举，不另立质量枚举。
 * 不一致策略 (Disagree) : 不一致时**不死用任一表**：锁存不一致、置故障位、输出保持上次
 *                         值。理由：切换点附近两表差一个数量级时，无法判断是粗抽表污染
 *                         还是精抽表漂移，任选其一都可能把坏值送进工艺联锁。人工核后可
 *                         用确认沿清「不一致」标志，但故障锁存保留（诊断证据留存），
 *                         两条清除路径分离。
 * 融合规则 (Fusion)     : 重叠区内取电容膜片读数（精抽段比皮拉尼高一个数量级的精度，
 *                         属物理事实而非偏好）；重叠区外按当前选择表取原值。
 * 开源溯源 (Origin)     : 来源标签 namur-ne43 加 oscat-building。原创实现（参考 NAMUR
 *                         NE43「多段有效域 + 越域即诊断」的契约形态，以及 OSCAT Building
 *                         组「域外行为显式化」的写法）。仅借契约形态与参数域，切换迟滞、
 *                         十倍程交叉校验、融合规则、枚举、状态机与全部码位 100% 本库
 *                         独立设计，clean-room 实现，零代码行复制。OSCAT 为免费开源库，
 *                         此处按最严口径只借结构，不引其代码与注释。
 * 依赖     (Depends)    : E_DL_SignalQuality（设备层既有类型，本件只引用不声明）；
 *                         Standard.library: R_TRIG / LN / EXPT / ABS / LIMIT
 * 故障码表 (Error codes):
 *   16#0003_0153【信息级】重叠区宽度越界已钳到 0 至 3 个十倍程
 *   16#0003_0154【信息级】一致性容差越界已钳到 0.05 至 3 个十倍程
 *   16#0003_0155【信息级】仅单表可用，融合质量为不确定（不置故障位）
 *   16#0003_0313【故障级】切换点非正，量程划分无意义（锁存）
 *   16#0003_0314【故障级】双表不一致或双表均失效，输出保持（锁存）
 *   16#0003_0315【故障级】非法状态兜底（锁存，终端安全态）
 * 码位占用 (Slot)       : 信息级 0153 / 0154 / 0155；故障级 0313 / 0314 / 0315。
 *                         全部落在 R12 本件分配块内，无跨块借用、无段外哨兵值。
 * 拍序纪律 (Cycle order) :
 *   ① ePhase        ：段 6 状态机（唯一位移点），段 7 复位分支是唯一回退点
 *   ② fPressurePa   ：段 8 单点写出（成功拍写新值，其余拍回写保持值）
 *   ③ bDisagreeLatch：段 6 置位、段 7 由确认沿或复位沿清除，无第三处写入
 *   ④ uErrorId      ：段 9 单一优先级链，全拍只写一次
 * 验收向量 (Acceptance) :
 *   V1 重叠区外：皮拉尼 15、电容 12、切换点 10、重叠 1 个十倍程 → 下门限 3.162，
 *      15 高于上门限故不重叠，选皮拉尼，输出 15.0，不置不一致
 *   V2 不一致：皮拉尼 100、电容 1 → 偏差 2 个十倍程超过容差 0.5 → 锁不一致、
 *      故障位置位、码 0314、输出保持上次
 *   V3 重叠区一致：皮拉尼 6、电容 4 → 6 落在 3.162 到 10 之间，偏差 0.176 在容差内，
 *      取电容表 → 输出 4.0、采信表为电容、重叠标志为真、质量为良好
 *   V4 双表失效：两表有效位均假 → 故障位置位、码 0314、输出保持
 *   V5 迟滞：当前为皮拉尼、压力 8.0（高于下门限 3.162）→ 仍为皮拉尼，不切换
 * 偏离留档 (Deviation)  :
 *   ① 规格第 3.15 节正文写「重叠区内才交叉校验」，但验收向量 V2 的工况（100 与 1）
 *      并不落在重叠区，仍要求判不一致。本件按向量实现：只要两表都可用即做交叉校验
 *      （更保守），重叠区标志单独保留用于融合规则与画面提示。
 *   ② 质量码复用既有枚举，其成员语义按 NE43 四级设计，与本件的三档结论不是一一对应。
 *      本件在声明区定义三个映射基准量（良好、不确定、坏），使「本件结论到枚举」的
 *      对应关系只有一处，避免散落在各分支里出现多种写法。
 *   ③ 三相轮转（选择、校验、回选择）每拍推进一相，故同一路读数约两到三拍完成一次
 *      完整裁决；不采用单拍跑完两相，是为了让每个相位在画面上可观测。
 *   ④ 规格内部变量清单列有「双表均无效」标志量，本件在两处直接按条件进故障并置质量码，
 *      若保留该标志则只有写没有读（只置不销），故不声明，避免死状态量。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（R12 · 泳道 C · 双表真空计融合件）
 *   2026-11-15  v1.0.1  终审修复：融合发布增加「跨相失效保护」。选择相与本相相隔一拍，
 *                       若采信表在两拍之间掉线，原实现仍按该表原值（可能是 0 或负值）
 *                       写进 fPressurePa，与本件「不死用任一表」的契约相反；改为取值表
 *                       本拍不可用即不发布（bUpdateOut 取该表可用性），输出保持上次值，
 *                       下拍回选择相重新裁决
 *============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_GaugeSel（采信表选择，归属本功能块并同文件发布）
 *       Active gauge selection owned by this block
 *-----------------------------------------------------------------------------*)
TYPE E_DL_GaugeSel :
(
    eNone        := 0,   // 未选：上电首拍或复位后，等待首次量程判定 / Not selected yet, waiting for the first decision
    ePirani      := 10,  // 皮拉尼：粗抽段，覆盖大气到十帕量级 / Pirani gauge covering the roughing range
    eCapacitance := 20   // 电容膜片：精抽段，覆盖十帕到十毫帕量级 / Capacitance gauge covering the fine range
);
END_TYPE

(*------------------------------------------------------------------------------
 * 枚举: E_DL_GaugePhase（本块相位，归属本功能块并同文件发布）
 *       Phase enumeration owned by this block
 *-----------------------------------------------------------------------------*)
TYPE E_DL_GaugePhase :
(
    eIdle          := 0,   // 待机：未使能或参数闸门未过，输出保持 / Idle, disabled or the gate has not passed
    eSelect        := 10,  // 选择：有效性判定与带迟滞的量程选择 / Selection with hysteresis
    eOverlapCheck  := 20,  // 交叉校验：十倍程偏差比较、融合与质量定级 / Cross check, fusion and quality grading
    eFault         := 99   // 故障：切换点非法、双表失效、不一致或非法状态 / Fault, needs a reset to leave
);
END_TYPE

FUNCTION_BLOCK FB_DL_VacuumGaugeMux
VAR_INPUT
    bEnable          : BOOL;                        // 使能，FALSE 时保持上次输出 [-] / Enable, the last output is held while FALSE
    bReset           : BOOL;                        // 复位故障与不一致锁存，上升沿有效 [-] / Rising edge clears the fault and the disagreement latch
    bAcknowledge     : BOOL;                        // 人工确认不一致，上升沿有效，不清故障锁存 [-] / Rising edge acknowledges a disagreement, the fault latch stays
    fPiraniPa        : REAL;                        // 皮拉尼读数 [帕]，有效域大于 1 纳帕 / Pirani reading in pascals, must exceed one nanopascal
    bPiraniValid     : BOOL;                        // 皮拉尼数据有效 [-] / Pirani reading valid flag
    fCapacitancePa   : REAL;                        // 电容膜片读数 [帕]，有效域大于 1 纳帕 / Capacitance gauge reading in pascals
    bCapacitanceValid: BOOL;                        // 电容膜片数据有效 [-] / Capacitance reading valid flag
    fSwitchPa        : REAL := 10.0;                // 切换点，皮拉尼量程上限 [帕]，域大于 0 / Switchover pressure, must exceed zero
    fOverlapDecades  : REAL := 1.0;                 // 重叠区宽度 [十倍程]，域 0 到 3 / Overlap width in decades, zero to three
    fAgreeTolDecades : REAL := 0.5;                 // 交叉校验允许偏差 [十倍程]，域 0.05 到 3 / Agreement tolerance in decades
END_VAR
VAR_OUTPUT
    fPressurePa      : REAL;                        // 融合后压力 [帕] / Fused pressure in pascals
    eActiveGauge     : E_DL_GaugeSel;               // 当前采信表 [-] / Active gauge
    bInOverlap       : BOOL;                        // 处于重叠区 [-] / Inside the overlap band
    bDisagree        : BOOL;                        // 双表不一致锁存 [-] / Disagreement latched
    fDeltaDecades    : REAL;                        // 两表偏差 [十倍程]，单表可用时为 0 / Deviation in decades, zero when only one gauge is usable
    eQuality         : E_DL_SignalQuality;          // 融合结果质量，复用既有枚举 [-] / Fused quality, reuses the existing enumeration
    bError           : BOOL;                        // 故障级锁存，仅 0313 0314 0315 置位 [-] / Latched fault, only fault level codes set it
    uErrorId         : UDINT;                       // 事件码，0 表示无事件 [代码] / Event code, zero means none
    eState           : E_DL_GaugePhase;             // 主状态机当前相位 [-] / Current phase of the main state machine
END_VAR
VAR
    fbTrigReset      : R_TRIG;                      // 复位沿检测，主周期无条件刷新 [-] / Reset edge detector, refreshed unconditionally
    fbTrigAck        : R_TRIG;                      // 确认沿检测，主周期无条件刷新 [-] / Acknowledge edge detector, refreshed unconditionally
    ePhase           : E_DL_GaugePhase := E_DL_GaugePhase.eIdle; // 内部相位，对外经 eState 输出 [-] / Internal phase exported as eState
    bInit            : BOOL := FALSE;               // 首扫标志，初值 FALSE，判据取非 [-] / First-scan flag initialised FALSE
    bFaultLatch      : BOOL;                        // 故障锁存，仅复位分支清除 [-] / Fault latch, cleared by the reset path only
    bDisagreeLatch   : BOOL;                        // 不一致锁存，确认沿或复位沿清除 [-] / Disagreement latch, cleared by the acknowledge or the reset edge
    uErrInt          : UDINT;                       // 故障级码寄存，锁存型 [代码] / Latched fault level code register
    uInfoCode        : UDINT;                       // 本拍信息级码，每拍重算 [代码] / Info level code recomputed every scan
    fHiSwitch        : REAL := 10.0;                // 切到电容的上门限 [帕] / Upper switch threshold
    fLoSwitch        : REAL := 3.162;               // 切回皮拉尼的下门限 [帕] / Lower switch threshold
    fOverUse         : REAL := 1.0;                 // 生效重叠宽度 [十倍程] / Effective overlap width
    fTolUse          : REAL := 0.5;                 // 生效交叉校验容差 [十倍程] / Effective agreement tolerance
    fLogPir          : REAL;                        // 皮拉尼十倍程 [十倍程] / Pirani log10 value
    fLogCap          : REAL;                        // 电容十倍程 [十倍程] / Capacitance log10 value
    fSelPa           : REAL;                        // 当前采信表读数 [帕] / Reading of the selected gauge
    fNew             : REAL;                        // 本次融合结果 [帕] / Fused result of this scan
    fLast            : REAL;                        // 上次成功输出的压力 [帕] / Last successfully published pressure
    eSel             : E_DL_GaugeSel := E_DL_GaugeSel.eNone; // 本次选择结果 [-] / Selected gauge of this scan
    bPirOk           : BOOL;                        // 皮拉尼可用（有效且大于下限且有限）[-] / Pirani usable flag
    bCapOk           : BOOL;                        // 电容可用 [-] / Capacitance usable flag
    bPirFin          : BOOL;                        // 皮拉尼读数有限 [-] / Pirani reading finite flag
    bCapFin          : BOOL;                        // 电容读数有限 [-] / Capacitance reading finite flag
    bUpdateOut       : BOOL;                        // 本拍有新的融合结果 [-] / A new fused result is available
    eQualGood        : E_DL_SignalQuality := E_DL_SignalQuality.eGood;        // 质量映射基准：良好（声明区取值，体内只与基准量比较）[-] / Quality mapping baseline, good
    eQualUncertain   : E_DL_SignalQuality := E_DL_SignalQuality.eUnderRange;  // 质量映射基准：不确定（借欠量程位表达「量测可信度下降」）[-] / Quality mapping baseline, uncertain
    eQualBad         : E_DL_SignalQuality := E_DL_SignalQuality.eWireBreakLow; // 质量映射基准：坏（借线路故障位表达「不可采信」）[-] / Quality mapping baseline, bad
END_VAR
VAR CONSTANT
    DL_LN10          : REAL := 2.302585093;         // 十的自然对数 [-] / Natural logarithm of ten
    DL_P_MIN         : REAL := 1.0E-9;              // 最小可接受压力 [帕]，防对数域零与负 / Minimum acceptable pressure preventing log of zero
    DL_P_MAX         : REAL := 1.0E9;               // 压力合理上限，超出视为非有限 [帕] / Pressure sanity limit
    DL_SWITCH_HYST   : REAL := 0.5;                 // 迟滞系数，重叠宽度的一半用于下门限 / Hysteresis factor, half of the overlap width
    DL_DEC_MIN       : REAL := 0.0;                 // 重叠宽度下限 [十倍程] / Lower overlap width
    DL_DEC_MAX       : REAL := 3.0;                 // 重叠宽度上限 [十倍程] / Upper overlap width
    DL_TOL_MIN       : REAL := 0.05;                // 容差下限 [十倍程] / Lower tolerance
    DL_TOL_MAX       : REAL := 3.0;                 // 容差上限 [十倍程] / Upper tolerance
    DL_ONE           : REAL := 1.0;                 // 实数一，防魔数 [无量纲] / Real one used instead of a magic number
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出确定性默认值（单拍标志与派生量每拍预清零，R25 第一律）
 *      Deterministic defaults first, derived flags pre-cleared every scan
 *-----------------------------------------------------------------------------*)
uInfoCode    := 16#0000_0000;                   // 信息级码每拍重算（Info code recomputed every scan）
bInOverlap   := FALSE;                          // 重叠标志预清零（Overlap flag pre-cleared）
fDeltaDecades := 0.0;                           // 偏差量预清零（Deviation pre-cleared）
bUpdateOut   := FALSE;                          // 融合更新标志预清零（Fused update flag pre-cleared）
bPirFin      := FALSE;                          // 皮拉尼有限标志预清零（Pirani finite flag pre-cleared）
bCapFin      := FALSE;                          // 电容有限标志预清零（Capacitance finite flag pre-cleared）

(*------------------------------------------------------------------------------
 * 段 2｜沿检测无条件刷新（红线：实例在 CASE 之外每拍必刷）
 *      Edge detection refreshed unconditionally outside the CASE
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);
fbTrigAck(CLK := bAcknowledge);

(*------------------------------------------------------------------------------
 * 段 3｜首扫初始化（唯一合法范式：初值 FALSE，判据取非）
 *      First-scan initialisation following the single legal pattern
 *-----------------------------------------------------------------------------*)
IF NOT bInit THEN
    fLast          := 0.0;                      // 上次输出压力清零（Last pressure cleared）
    fNew           := 0.0;                      // 融合中间量清零（Fused temporary cleared）
    eSel           := E_DL_GaugeSel.eNone;      // 采信表置未选（Gauge selection reset）
    bFaultLatch    := FALSE;                    // 故障锁存清零（Fault latch cleared）
    bDisagreeLatch := FALSE;                    // 不一致锁存清零（Disagreement latch cleared）
    uErrInt        := 16#0000_0000;             // 故障码清零（Fault code cleared）
    fPressurePa    := 0.0;                      // 压力出口清零（Pressure outlet cleared）
    eActiveGauge   := E_DL_GaugeSel.eNone;      // 采信表出口置未选（Gauge outlet reset）
    eQuality       := eQualUncertain;           // 质量出口置不确定（Quality outlet set to uncertain）
    ePhase         := E_DL_GaugePhase.eIdle;    // 相位复位为待机（Phase reset to idle）
    bInit          := TRUE;                     // 首扫只做一次（First scan runs once）
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜参数闸门（切换点非正属故障级；重叠宽度与容差越界属信息级，只钳位）
 *      Parameter gate, only the switchover pressure is fault level
 *-----------------------------------------------------------------------------*)
IF fSwitchPa <= DL_P_MIN THEN
    bFaultLatch := TRUE;                        // 切换点非法：锁故障（Illegal switchover pressure, latch a fault）
    uErrInt     := 16#0003_0313;                // 0313 切换点非正（Switchover pressure not positive）
    fHiSwitch   := DL_ONE;                      // 门限给安全值，避免本拍出现零除（Safe threshold avoids a division by zero）
    fLoSwitch   := DL_ONE;                      // 下门限同样给安全值（Lower threshold set to the safe value）
ELSE
    fHiSwitch := fSwitchPa;                     // 上门限即切换点（Upper threshold is the switchover pressure）
    IF fOverlapDecades < DL_DEC_MIN THEN
        fOverUse   := DL_DEC_MIN;               // 负宽度无意义：钳到 0（Negative width clamped to zero）
        uInfoCode  := 16#0003_0153;             // 0153 重叠宽度越界已钳位（Overlap width clamped）
    ELSIF fOverlapDecades > DL_DEC_MAX THEN
        fOverUse   := DL_DEC_MAX;               // 超上限钳位（Clamped to the upper bound）
        uInfoCode  := 16#0003_0153;             // 0153 重叠宽度越界已钳位（Overlap width clamped）
    ELSE
        fOverUse   := fOverlapDecades;          // 合法宽度直通（Valid width passed through）
    END_IF
    fLoSwitch := fSwitchPa / EXPT(10.0, fOverUse * DL_SWITCH_HYST); // 下门限按半宽十倍程折算（Lower threshold from half of the overlap width）
END_IF

IF fAgreeTolDecades < DL_TOL_MIN THEN
    fTolUse   := DL_TOL_MIN;                    // 容差下限钳位（Tolerance clamped to the lower bound）
    uInfoCode := 16#0003_0154;                  // 0154 容差越界已钳位（Tolerance clamped）
ELSIF fAgreeTolDecades > DL_TOL_MAX THEN
    fTolUse   := DL_TOL_MAX;                    // 容差上限钳位（Tolerance clamped to the upper bound）
    uInfoCode := 16#0003_0154;                  // 0154 容差越界已钳位（Tolerance clamped）
ELSE
    fTolUse   := fAgreeTolDecades;              // 合法容差直通（Valid tolerance passed through）
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜有限性闸门与可用性判定（对数域前置拦截：零与负数在取对数前剔除）
 *      Finiteness gate and usability check, guarding the logarithm domain
 *-----------------------------------------------------------------------------*)
bPirFin := NOT ((fPiraniPa <> fPiraniPa) OR (ABS(fPiraniPa) > DL_P_MAX)); // 皮拉尼有限判定（Pirani finiteness test）
bCapFin := NOT ((fCapacitancePa <> fCapacitancePa) OR (ABS(fCapacitancePa) > DL_P_MAX)); // 电容有限判定（Capacitance finiteness test）
bPirOk  := bPiraniValid AND bPirFin AND (fPiraniPa >= DL_P_MIN);   // 三道闸：有效位、有限、大于下限（Three gates）
bCapOk  := bCapacitanceValid AND bCapFin AND (fCapacitancePa >= DL_P_MIN); // 三道闸：有效位、有限、大于下限（Three gates）

(*------------------------------------------------------------------------------
 * 段 6｜主状态机（枚举每个成员均有标签，末尾 ELSE 兜底到终端安全态）
 *      Main state machine, one label per member plus a trailing ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE ePhase OF

    E_DL_GaugePhase.eIdle: // 待机：故障或未使能则停留，否则进入选择
        IF bFaultLatch THEN
            ePhase := E_DL_GaugePhase.eFault;   // 参数已锁故障：进故障态（Gate failed, enter the fault state）
        ELSIF bEnable THEN
            ePhase := E_DL_GaugePhase.eSelect;  // 进选择态（Enter the selection phase）
        END_IF

    E_DL_GaugePhase.eSelect: // 选择：先判双表失效，再按迟滞维持或切换
        IF (NOT bPirOk) AND (NOT bCapOk) THEN
            IF NOT bFaultLatch THEN
                bFaultLatch := TRUE;            // 锁故障，保留首出码（Latch the fault keeping the first code）
                uErrInt     := 16#0003_0314;    // 0314 双表失效（Both gauges failed）
            END_IF
            eQuality := eQualBad;               // 质量定为坏（Quality marked bad）
            ePhase   := E_DL_GaugePhase.eFault; // 进故障态（Enter the fault state）
        ELSE
            IF eSel = E_DL_GaugeSel.eNone THEN
                (* 首次选择：能进精抽段（读数不高于切换点）就先上电容表，否则用皮拉尼 *)
                IF bCapOk AND bPirOk THEN
                    IF fPiraniPa <= fHiSwitch THEN
                        eSel := E_DL_GaugeSel.eCapacitance; // 已在精抽段（Already in the fine range）
                    ELSE
                        eSel := E_DL_GaugeSel.ePirani;      // 仍在大气压侧（Still on the atmosphere side）
                    END_IF
                ELSIF bCapOk THEN
                    eSel := E_DL_GaugeSel.eCapacitance;     // 只有电容可用（Only the capacitance gauge is usable）
                ELSE
                    eSel := E_DL_GaugeSel.ePirani;          // 只有皮拉尼可用（Only the Pirani gauge is usable）
                END_IF
            END_IF
            IF eSel = E_DL_GaugeSel.ePirani THEN
                IF (NOT bPirOk) AND bCapOk THEN
                    eSel := E_DL_GaugeSel.eCapacitance; // 皮拉尼失效即切电容（Pirani lost, switch over at once）
                ELSIF bCapOk AND (fPiraniPa <= fLoSwitch) THEN
                    eSel := E_DL_GaugeSel.eCapacitance; // 降到下门限以下才切（Switch only below the lower threshold）
                END_IF
            ELSIF eSel = E_DL_GaugeSel.eCapacitance THEN
                IF (NOT bCapOk) AND bPirOk THEN
                    eSel := E_DL_GaugeSel.ePirani;      // 电容失效即切皮拉尼（Capacitance lost, switch back at once）
                ELSIF bPirOk AND (fCapacitancePa >= fHiSwitch) THEN
                    eSel := E_DL_GaugeSel.ePirani;      // 升到上门限以上才切（Switch only above the upper threshold）
                END_IF
            ELSE
                eSel := E_DL_GaugeSel.ePirani;          // 未选态残留兜底（Defensive fallback for the unselected state）
            END_IF
            ePhase := E_DL_GaugePhase.eOverlapCheck;    // 进交叉校验态（Enter the cross check phase）
        END_IF

    E_DL_GaugePhase.eOverlapCheck: // 交叉校验与融合
        IF eSel = E_DL_GaugeSel.eCapacitance THEN
            fSelPa := fCapacitancePa;               // 采信表读数取电容（Reading of the selected gauge）
        ELSE
            fSelPa := fPiraniPa;                    // 采信表读数取皮拉尼（Reading of the selected gauge）
        END_IF
        bInOverlap := (fSelPa >= fLoSwitch) AND (fSelPa <= fHiSwitch); // 重叠区判定（Overlap band test）
        fLogPir := 0.0;                             // 十倍程预清零（Log value pre-cleared）
        fLogCap := 0.0;                             // 十倍程预清零（Log value pre-cleared）
        IF bPirOk THEN
            fLogPir := LN(fPiraniPa) / DL_LN10;     // 取对数，前置闸门已排除零与负（Log guarded by the usability gate）
        END_IF
        IF bCapOk THEN
            fLogCap := LN(fCapacitancePa) / DL_LN10; // 取对数，前置闸门已排除零与负（Log guarded by the usability gate）
        END_IF
        IF bPirOk AND bCapOk THEN
            fDeltaDecades := ABS(fLogPir - fLogCap); // 两表偏差量化到十倍程（Deviation quantified in decades）
        END_IF
        IF (NOT bPirOk) AND (NOT bCapOk) THEN
            IF NOT bFaultLatch THEN
                bFaultLatch := TRUE;                // 锁故障（Latch the fault）
                uErrInt     := 16#0003_0314;        // 0314 双表失效（Both gauges failed）
            END_IF
            eQuality := eQualBad;                   // 质量定为坏（Quality marked bad）
            ePhase   := E_DL_GaugePhase.eFault;     // 进故障态（Enter the fault state）
        ELSIF bPirOk AND bCapOk AND (fDeltaDecades > fTolUse) THEN
            bDisagreeLatch := TRUE;                 // 锁不一致（Latch the disagreement）
            IF NOT bFaultLatch THEN
                bFaultLatch := TRUE;                // 锁故障（Latch the fault）
                uErrInt     := 16#0003_0314;        // 0314 双表不一致（Gauges disagree）
            END_IF
            eQuality := eQualBad;                   // 质量定为坏（Quality marked bad）
            ePhase   := E_DL_GaugePhase.eFault;     // 进故障态，输出保持（Enter the fault state, output held）
        ELSE
            IF bInOverlap AND bCapOk THEN
                fNew := fCapacitancePa;             // 重叠区取电容（融合取电容表） / Fusion takes the capacitance gauge in the overlap band
                bUpdateOut := TRUE;                 // 取值前已验可用，本拍有新结果 / The source was validated, publish it
            ELSE
                (* 重叠区外按选择表取原值：三个成员逐个给出取值口径，不留隐式分支 *)
                (* Outside the overlap band the selected gauge is used, one explicit label per member *)
                CASE eSel OF
                    E_DL_GaugeSel.eNone:
                        fNew := fPiraniPa;          // 未选态兜底取皮拉尼（Unselected fallback uses the Pirani gauge）
                    E_DL_GaugeSel.ePirani:
                        fNew := fPiraniPa;          // 选皮拉尼（The Pirani gauge is selected）
                    E_DL_GaugeSel.eCapacitance:
                        fNew := fCapacitancePa;     // 选电容膜片（The capacitance gauge is selected）
                    ELSE
                        fNew := fPiraniPa;          // 非法枚举值兜底（Illegal enumeration value fallback）
                END_CASE
                (* 跨相失效保护：选择相与本相相隔一拍，读数可能已掉线，取值表本拍不可用即不发布 *)
                (* Cross-phase guard: the selected gauge may have dropped out between the two phases *)
                IF eSel = E_DL_GaugeSel.eCapacitance THEN
                    bUpdateOut := bCapOk;           // 采信电容：本拍仍可用才发布 / Publish only while the capacitance gauge is usable
                ELSE
                    bUpdateOut := bPirOk;           // 采信皮拉尼：本拍仍可用才发布 / Publish only while the Pirani gauge is usable
                END_IF
            END_IF
            IF bPirOk AND bCapOk THEN
                eQuality := eQualGood;              // 双表可用且一致：良好（Both usable and consistent, good）
            ELSE
                eQuality := eQualUncertain;         // 单表可用：不确定（Single gauge, uncertain）
                uInfoCode := 16#0003_0155;          // 0155 单表可用（Single gauge usable）
            END_IF
            ePhase := E_DL_GaugePhase.eSelect;      // 回选择态，下拍重新判定（Back to selection）
        END_IF

    E_DL_GaugePhase.eFault: // 故障：输出保持，等复位沿（Fault, outputs held until the reset edge）
        eQuality := eQualBad;                       // 故障期质量定为坏（Quality marked bad during a fault）

    ELSE
        bFaultLatch := TRUE;                        // 非法状态兜底锁存（Illegal state latched）
        uErrInt     := 16#0003_0315;                // 0315 非法状态兜底（Illegal state fallback code）
        ePhase      := E_DL_GaugePhase.eFault;      // 进终端安全态（Enter the terminal safe state）
END_CASE

(*------------------------------------------------------------------------------
 * 段 7｜人工确认与复位（确认只清不一致标志，复位清故障锁存，两条路径分离）
 *      Acknowledge clears only the disagreement; reset clears the fault latch
 *-----------------------------------------------------------------------------*)
IF fbTrigAck.Q THEN
    bDisagreeLatch := FALSE;                    // 人工已核：清不一致（Acknowledged, clear the disagreement）
END_IF
IF fbTrigReset.Q THEN
    bDisagreeLatch := FALSE;                    // 复位清不一致（Reset clears the disagreement）
    bFaultLatch    := FALSE;                    // 复位清故障锁存（Reset clears the fault latch）
    uErrInt        := 16#0000_0000;             // 复位清故障码（Reset clears the fault code）
    eSel           := E_DL_GaugeSel.eNone;      // 选择表回未选，重新按读数判定（Selection reset to unselected）
    IF ePhase = E_DL_GaugePhase.eFault THEN
        ePhase := E_DL_GaugePhase.eIdle;        // 故障态复位回待机（Fault returns to idle）
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜压力出口单点写出（成功拍写新值并刷新保持寄存器，其余拍回写保持值）
 *      Single write point of the pressure outlet with an explicit hold register
 *-----------------------------------------------------------------------------*)
IF bUpdateOut THEN
    fPressurePa := fNew;                        // 成功拍写出新值（Publish the new value）
    fLast       := fNew;                        // 刷新保持寄存器（Refresh the hold register）
ELSE
    fPressurePa := fLast;                       // 其余拍回写保持值，杜绝坏表值进联锁（Hold the last good value）
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜码位定级与出口（单一优先级链，全拍只写一次 uErrorId）
 *      Single priority chain and outlet mapping
 *-----------------------------------------------------------------------------*)
eActiveGauge := eSel;                           // 采信表出口（Active gauge outlet）
bDisagree    := bDisagreeLatch;                 // 不一致出口（Disagreement outlet）
eState       := ePhase;                         // 相位出口（Phase outlet）
bError       := bFaultLatch;                    // 故障位只反映故障级锁存（Fault bit reflects the latch only）
IF bError THEN
    uErrorId := uErrInt;                        // 故障级码优先透出（Fault level code has priority）
ELSE
    uErrorId := uInfoCode;                      // 无故障透出本拍信息级码（Info code exposed otherwise）
END_IF
END_FUNCTION_BLOCK
