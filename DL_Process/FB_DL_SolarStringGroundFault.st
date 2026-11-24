//==============================================================================
// 功能块：FB_DL_SolarStringGroundFault ｜ 中文名称：光伏组串对地绝缘阻抗检测
// 所属子库：DL_Process ｜ 版本：v1.0.1 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：光伏组串对地绝缘阻抗检测（不平衡电桥法）：由正/负母线对地电压与组串母线
//           电压推算正极、负极与并联对地绝缘电阻，按两级阈值告警（确认拍数 + 锁存）。
//           本件仅监视不控：不触发脱扣、不切组串、不做绝缘老化趋势记录（趋势归上位）。
// 开源溯源 (Origin)：道莅原创实现（参考 不平衡电桥法公开测量原理 分类与参数域）
// 单位表：母线及对地电压[V] / 绝缘电阻与桥阻[kΩ] / 阈值[kΩ] / 确认拍数[拍] /
//         失衡比值[无量纲] / 电压判零容差[V]
// ------------------------------------------------------------------------------
// 量纲链（R108 量纲组合表，编码前逐式复核，禁凭记忆落码）：
//   设 Gp = 1/Rp、Gn = 1/Rn 分别为正/负母线对地漏电导，G_t = Gp + Gn 为总漏电导，
//   Rb 为测量桥阻。桥阻上的压降为 (Vbus − Vp − Vn)，其上电流即总漏电流：
//     G_t [1/kΩ] = (Vbus − Vp − Vn) / (Rb × (Vp + Vn))        —— 量纲：V/(kΩ·V) = 1/kΩ
//   两端漏电按对地电压分压比分配（同一漏电网络的基尔霍夫关系）：
//     Gp / Gn = Vn / Vp   →   Gp = G_t × Vn/(Vp+Vn)，Gn = G_t × Vp/(Vp+Vn)
//   取倒数得电阻（kΩ）：
//     R_t = 1/G_t = Rb × (Vp + Vn) / (Vbus − Vp − Vn)
//     Rp  = R_t × (Vp + Vn) / Vn
//     Rn  = R_t × (Vp + Vn) / Vp
//   复核：Rp/Rn = Vp/Vn（与电桥分压比一致）；并联合成 1/(1/Rp + 1/Rn) = R_t（自洽）。
//   注意（本件最高风险点）：R_t 的除子为 (Vbus − Vp − Vn)。当组串绝缘趋于无穷（正负
//   完全平衡、Vp + Vn 逼近 Vbus）时 R_t 趋于无穷；此时若照抄「Rb × (Vbus/(Vp+Vn) − 1)」
//   这种乘式写法，会得到趋于 0 的伪阻值（量纲虽为 kΩ，物理上却是倒数关系），从而把
//   绝缘良好误判成对地短路并误告警。本件一律用除式，并对「完全平衡退化」给出显式分支：
//   (Vbus − Vp − Vn) ≤ 1.0 V 时判为绝缘无穷大，取上限哨兵 1.0E9 kΩ 输出、不告警、
//   不计告警确认拍数（不冒充实测值，HMI 以饱和值显示）。
// ------------------------------------------------------------------------------
// 错误码表：16#0005_0410 信息级（母线电压 ≤ 0，或 Vp + Vn 近零，或单极对地电压非正：
//           绝缘推算不可判，禁止输出伪阻值，bUndecidable 置位，不置 bError）/
//           16#0005_0411 信息级（单极对地阻抗失衡提示：max(Rp,Rn)/min(Rp,Rn) > 3，
//           不置 bError）/ 16#0005_035A 故障级（桥阻非正或告警阈值倒置，置 bError）/
//           16#0005_035B 故障级（输入非有限，置 bError，阻值输出回零）/ 16#0005_035C
//           故障级兜底（状态机落 ELSE 非法状态，置 bError）。码位 16#0005 段。
// 状态机：E_DL_StringInsState（eIdle=0 待机 / eMeasure=10 正常推算 / eUndecidable=20
//           推算不可判 / eAlarm=30 告警锁存后监视 / eFault=99 故障兜底），CASE 含 ELSE
//           兜底，ELSE 置 035C 且阻值回零、许可撤。
// 边界行为：① 量纲链见上（除式 + 完全平衡退化显式分支）；② Vp + Vn ≤ 1.0 V 或
//           fBusV ≤ 0 → 信息 0410 + bUndecidable := TRUE + bValid := FALSE（推算不可判
//           时禁止输出伪阻值）；单极对地电压非正同理（分压比不可算）；③ fBridgeKOhm ≤ 0
//           或 fAlarmKOhm ≥ fWarnKOhm → 故障 035A；④ 非有限（NaN 自反判 + Inf 幅值上限
//           判）→ 故障 035B，阻值回零；⑤ 分级：R_t < 告警阈值 → bAlarm；R_t < 预警阈值
//           → bWarn；均需连续 nConfirmSamples 拍确认，确认后锁存至 bReset（防单点误报
//           停机）；⑥ 失衡判据 max/min > 3.0（常量），命中即 bUnbalanced + 信息 0411；
//           ⑦ 失能 → 不判、bValid := FALSE，但绝不清除已锁存的 bWarn/bAlarm（告警是
//           历史事实，只能人工复位）。
// 验收向量（算法已证，手算）：① Vbus = 600 V、Vp = 300 V、Vn = 300 V、Rb = 100 kΩ →
//           Vbus − Vp − Vn = 0 → 完全平衡退化分支 → R_t = 1.0E9 kΩ 哨兵、bWarn/bAlarm
//           均为 FALSE（若用乘式写法此处会得 0 kΩ 并误告警，本向量即该风险的回归用例）；
//           ② Vbus = 600 V、Vp = 310 V、Vn = 290 V、Rb = 100 kΩ → Vbus − Vp − Vn = 0 V
//           仍属退化（差值阈值内）→ 同样取 1.0E9 kΩ 上限哨兵；改取 Vp = 310 V、Vn = 280 V（差 10 V）→
//           R_t = 100 × 590 / 10 = 5900 kΩ、Rp = 5900 × 590/280 ≈ 12432 kΩ、
//           Rn = 5900 × 590/310 ≈ 11229 kΩ，失衡比 1.11 < 3 → 不告警不失衡；
//           ③ 阈值 告警 100、预警 1000 kΩ，实测 R_t = 80 kΩ → 连续 3 拍确认 → bAlarm
//           锁存；④ Vp + Vn = 0.5 V → 信息 0410 + bUndecidable + bValid := FALSE。
//           编译器已证（三平台）：未跑，由收口方登记。
// 修订历史：v1.0.0 2026-11-17 首版（R25 派单 · §4.20）
//           v1.0.1 2026-11-17 终审补域端点闸（对外引脚契约零变更）：预警阈值 fWarnKOhm 若被配到
//           ≥ 上限哨兵 DL_SGF_R_MAX（1.0E9 kΩ），完全平衡退化分支输出的哨兵值会被判为「低于预警阈值」
//           而误报警（把绝缘良好判成异常）。组态闸补一项 fWarnKOhm >= DL_SGF_R_MAX → 035A。
//           总监独立验算裁定：派单书 §4.20 的乘式 Rb x (Vbus/(Vp+Vn) − 1) 分子分母倒置（完全平衡
//           时得 0 kΩ、单极短路时得无穷），本件除式 Rb x (Vp+Vn)/(Vbus − Vp − Vn) 在两端均取正确
//           极限（D→0 ⇒ R→∞；Vp+Vn→0 ⇒ R→0），编码侧改法正确，派单书须勘误。
//==============================================================================
(*------------------------------------------------------------------------------
 * 枚举: E_DL_StringInsState（归属 DL_Process，与 FB_DL_SolarStringGroundFault 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_StringInsState :
(
    eIdle        := 0,   // 待机：失能，不推算不判定 / Idle, neither computed nor judged
    eMeasure     := 10,  // 正常推算：阻值有效 / Normal measurement, valid resistances
    eUndecidable := 20,  // 推算不可判：母线或对地电压条件不成立 / Undecidable, the voltage conditions do not hold
    eAlarm       := 30,  // 告警锁存后监视：阻值仍有效 / Monitoring after a latched alarm
    eFault       := 99   // 故障兜底：组态非法/非有限/非法状态 / Fault fallback
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_SolarStringGroundFault
 * 调用约定: 每个扫描周期无条件调用一次；电压量由直流侧采样与滤波层刷新。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_SolarStringGroundFault
VAR_INPUT
    fPosToGroundV   : LREAL;                       // 正母线对地电压 [V] / Positive bus voltage to ground [V]
    fNegToGroundV   : LREAL;                       // 负母线对地电压（幅值）[V] / Negative bus voltage to ground, magnitude [V]
    fBusV           : LREAL;                       // 组串母线电压 [V]，须 > 0 / String bus voltage [V], must be > 0
    fBridgeKOhm     : LREAL := 100.0;              // 测量桥电阻 [kΩ]，须 > 0 / Measurement bridge resistance [kΩ], must be > 0
    fWarnKOhm       : LREAL := 1000.0;             // 预警阈值 [kΩ] / Warning threshold [kΩ]
    fAlarmKOhm      : LREAL := 100.0;              // 告警阈值 [kΩ]，须 < 预警阈值 / Alarm threshold [kΩ], must be below the warning
    nConfirmSamples : INT := 3;                    // 告警确认拍数 [拍]，域 1~20 / Alarm confirmation samples, domain 1..20
    bEnable         : BOOL;                        // 总使能 / Master enable
    bReset          : BOOL;                        // 复位，上升沿清告警锁存 / Reset, rising edge clears the latched alarms
END_VAR
VAR_OUTPUT
    fInsPosKOhm     : LREAL;                       // 正极对地绝缘电阻 [kΩ] / Positive-to-ground insulation resistance [kΩ]
    fInsNegKOhm     : LREAL;                       // 负极对地绝缘电阻 [kΩ] / Negative-to-ground insulation resistance [kΩ]
    fInsTotalKOhm   : LREAL;                       // 并联对地绝缘电阻 [kΩ] / Parallel insulation resistance [kΩ]
    bWarn           : BOOL;                        // 预警（确认后锁存至 bReset）/ Warning, latched until reset after confirmation
    bAlarm          : BOOL;                        // 告警（确认后锁存至 bReset）/ Alarm, latched until reset after confirmation
    bUnbalanced     : BOOL;                        // 正负极失衡（max/min > 3）/ Positive-negative imbalance
    bUndecidable    : BOOL;                        // 推算不可判（禁止使用阻值输出）/ Undecidable, the resistance outputs must not be used
    eErr            : UDINT;                       // 错误码，0 = 无错，码位 16#0005_0410 起信息级、16#0005_035A 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError          : BOOL;                        // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid          : BOOL;                        // 阻值输出可用标志，不可判/失能/故障闸显式 FALSE / Resistance usable flag, explicit FALSE when undecidable, disabled or faulted
    eState          : E_DL_StringInsState;         // 主状态机当前状态 / Current state of the main state machine
END_VAR
VAR
    fbReset         : R_TRIG;                      // 复位上升沿检测实例 / Reset rising edge detector
    fSumV           : LREAL;                       // 对地电压之和 Vp + Vn [V] / Sum of the ground voltages [V]
    fDiffV          : LREAL;                       // 母线电压盈余 Vbus − (Vp + Vn) [V] / Bus voltage surplus [V]
    fTotalKOhm      : LREAL;                       // 并联绝缘电阻工作值 [kΩ] / Parallel insulation working value [kΩ]
    fPosKOhm        : LREAL;                       // 正极绝缘电阻工作值 [kΩ] / Positive insulation working value [kΩ]
    fNegKOhm        : LREAL;                       // 负极绝缘电阻工作值 [kΩ] / Negative insulation working value [kΩ]
    fRatio          : LREAL;                       // 失衡比值 max/min [无量纲] / Imbalance ratio max/min
    fMaxKOhm        : LREAL;                       // 两极大值 [kΩ] / Maximum of both poles [kΩ]
    fMinKOhm        : LREAL;                       // 两极小值 [kΩ] / Minimum of both poles [kΩ]
    nConfirmEff     : INT;                         // 钳位后的确认拍数 [拍] / Clamped confirmation samples
    nWarnCnt        : INT;                         // 预警连续确认计数 [拍] / Consecutive warning samples
    nAlarmCnt       : INT;                         // 告警连续确认计数 [拍] / Consecutive alarm samples
    bNonFin         : BOOL;                        // 非有限判定中间标志 / Non-finite detection intermediate flag
    bUndecidableNow : BOOL;                        // 本拍不可判标志 / Undecidable this scan
    bDegenerate     : BOOL;                        // 完全平衡退化标志 / Fully balanced degenerate case
    bWarnNow        : BOOL;                        // 本拍预警判据 / Warning predicate this scan
    bAlarmNow       : BOOL;                        // 本拍告警判据 / Alarm predicate this scan
    bFirstScan      : BOOL := TRUE;                // 上电首拍标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_SGF_CODE_INFO_1 : UDINT := 16#0005_0410;    // 信息级槽 1（推算不可判） / info slot 1
    DL_SGF_CODE_INFO_2 : UDINT := 16#0005_0411;    // 信息级槽 2（单极对地阻抗失衡提示） / info slot 2
    DL_SGF_CODE_FLT_1  : UDINT := 16#0005_035A;    // 故障级槽 1（桥阻/阈值组态非法） / fault slot 1
    DL_SGF_CODE_FLT_2  : UDINT := 16#0005_035B;    // 故障级槽 2（输入非有限） / fault slot 2
    DL_SGF_CODE_FLT_3  : UDINT := 16#0005_035C;    // 故障级槽 3（非法状态兜底） / fault slot 3
    DL_SGF_R_MAX       : LREAL := 1.0E9;           // 绝缘电阻上限哨兵（完全平衡退化取值）[kΩ] / Insulation ceiling sentinel [kΩ]
    DL_SGF_VMIN        : LREAL := 1.0;             // 对地电压和与母线盈余判零门限 [V] / Voltage sum and surplus threshold [V]
    DL_SGF_IMB_RATIO   : LREAL := 3.0;             // 失衡比值门限 [无量纲] / Imbalance ratio threshold
    DL_SGF_CONF_MIN    : INT := 1;                 // 确认拍数下限 [拍] / Confirmation floor [samples]
    DL_SGF_CONF_MAX    : INT := 20;                // 确认拍数上限 [拍] / Confirmation ceiling [samples]
    DL_SGF_ZERO        : LREAL := 0.0;             // 零值常量，避免裸字面量 [—] / Zero constant, avoids a bare literal
    DL_SGF_TOL         : LREAL := 1.0E-6;          // 浮点比较容差 [—] / Float comparison tolerance
    DL_SGF_INF         : LREAL := 1.7976931348623157E308; // LREAL 幅值上限，Inf 判据 / LREAL magnitude ceiling
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 5）：复位沿检测在任意分支之外周期调用
 *----------------------------------------------------------------------------*)
fbReset(CLK := bReset);                            // 复位沿检测无条件刷新 / reset edge refreshed unconditionally

(*------------------------------------------------------------------------------
 * 段 2｜复位沿处理（改写置于沿后，防吞沿 R39）：清告警锁存与确认计数
 *----------------------------------------------------------------------------*)
IF fbReset.Q THEN
    eState := E_DL_StringInsState.eIdle;
    eErr   := 16#0000_0000;                        // 复位清码 / reset clears the code
    bError := FALSE;                               // 复位清故障 / reset clears the fault
    bWarn  := FALSE;                               // 预警锁存清（仅人工复位可清）/ warning latch cleared
    bAlarm := FALSE;                               // 告警锁存清（仅人工复位可清）/ alarm latch cleared
    nWarnCnt := 0;                                 // 预警确认计数清 / warning counter cleared
    nAlarmCnt := 0;                                // 告警确认计数清 / alarm counter cleared
    bFirstScan := TRUE;                            // 重新首拍化 / re-initialize first scan
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜非有限输入闸：035B + 阻值回零（故障路径输出安全值而非上次值，红线 6）
 *----------------------------------------------------------------------------*)
bNonFin := (fPosToGroundV <> fPosToGroundV) OR (ABS(fPosToGroundV) >= DL_SGF_INF)
        OR (fNegToGroundV <> fNegToGroundV) OR (ABS(fNegToGroundV) >= DL_SGF_INF)
        OR (fBusV <> fBusV) OR (ABS(fBusV) >= DL_SGF_INF)
        OR (fBridgeKOhm <> fBridgeKOhm) OR (ABS(fBridgeKOhm) >= DL_SGF_INF)
        OR (fWarnKOhm <> fWarnKOhm) OR (ABS(fWarnKOhm) >= DL_SGF_INF)
        OR (fAlarmKOhm <> fAlarmKOhm) OR (ABS(fAlarmKOhm) >= DL_SGF_INF);   // 引脚非有限汇总 / pins non-finite
IF bNonFin THEN
    eState := E_DL_StringInsState.eFault;          // 进故障相 / enter fault state
    eErr   := DL_SGF_CODE_FLT_2;                   // 故障级：输入非有限 / fault: non-finite input
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                               // 阻值不可用 / resistances unusable
    fInsPosKOhm := DL_SGF_ZERO;                    // 正极阻值回零安全侧 / positive resistance zeroed, safe side
    fInsNegKOhm := DL_SGF_ZERO;                    // 负极阻值回零安全侧 / negative resistance zeroed, safe side
    fInsTotalKOhm := DL_SGF_ZERO;                  // 并联阻值回零安全侧 / parallel resistance zeroed, safe side
    bUnbalanced := FALSE;                          // 失衡标志撤 / imbalance withdrawn
    bUndecidable := FALSE;                         // 不可判标志撤（故障优先）/ undecidable withdrawn, fault outranks
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜组态合法性闸：桥阻须为正（否则除零）、告警阈值须严格小于预警阈值
 *----------------------------------------------------------------------------*)
IF (fBridgeKOhm <= DL_SGF_TOL) OR (fAlarmKOhm >= fWarnKOhm - DL_SGF_TOL)
   OR (fWarnKOhm >= DL_SGF_R_MAX) THEN
    eState := E_DL_StringInsState.eFault;          // 进故障相 / enter fault state
    eErr   := DL_SGF_CODE_FLT_1;                   // 故障级：桥阻/阈值组态非法 / fault: bridge or threshold configuration invalid
    bError := TRUE;                                // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
    bValid := FALSE;                               // 阻值不可用 / resistances unusable
    fInsPosKOhm := DL_SGF_ZERO;                    // 正极阻值回零安全侧 / positive resistance zeroed
    fInsNegKOhm := DL_SGF_ZERO;                    // 负极阻值回零安全侧 / negative resistance zeroed
    fInsTotalKOhm := DL_SGF_ZERO;                  // 并联阻值回零安全侧 / parallel resistance zeroed
    bUnbalanced := FALSE;                          // 失衡标志撤 / imbalance withdrawn
    bUndecidable := FALSE;                         // 不可判标志撤 / undecidable withdrawn
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜组态钳位：确认拍数钳到 1~20（域外按边界钳，不新占码位）
 *----------------------------------------------------------------------------*)
nConfirmEff := nConfirmSamples;                    // 先取引脚值 / take the pin value first
IF nConfirmEff < DL_SGF_CONF_MIN THEN
    nConfirmEff := DL_SGF_CONF_MIN;                // 下限钳位 [拍] / clipped to the floor
END_IF
IF nConfirmEff > DL_SGF_CONF_MAX THEN
    nConfirmEff := DL_SGF_CONF_MAX;                // 上限钳位 [拍] / clipped to the ceiling
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜不可判闸（R42 家族：推算不成立时禁止输出伪阻值）：
 *       母线电压 ≤ 0、对地电压和近零、或任一极对地电压非正 → 0410 + bUndecidable
 *       此时阻值输出回零且 bValid := FALSE，绝不给出"看起来能信"的数字
 *----------------------------------------------------------------------------*)
fSumV := fPosToGroundV + fNegToGroundV;            // 对地电压之和 [V] / sum of the ground voltages [V]
bUndecidableNow := (fBusV <= DL_SGF_TOL)
                OR (fSumV <= DL_SGF_VMIN)
                OR (fPosToGroundV <= DL_SGF_TOL)
                OR (fNegToGroundV <= DL_SGF_TOL);  // 不可判判据（四项任一）/ undecidable predicate
IF bUndecidableNow THEN
    bUndecidable := TRUE;                          // 不可判标志置位 / undecidable raised
    bValid := FALSE;                               // 阻值不可用（禁伪阻值）/ resistances unusable
    fInsPosKOhm := DL_SGF_ZERO;                    // 正极阻值回零 / positive resistance zeroed
    fInsNegKOhm := DL_SGF_ZERO;                    // 负极阻值回零 / negative resistance zeroed
    fInsTotalKOhm := DL_SGF_ZERO;                  // 并联阻值回零 / parallel resistance zeroed
    bUnbalanced := FALSE;                          // 不可判时不判失衡 / no imbalance verdict when undecidable
    nWarnCnt := 0;                                 // 确认计数清零（不可判拍不计入）/ confirmation counters cleared
    nAlarmCnt := 0;
    bWarnNow := FALSE;                             // 本拍不出判据 / no predicate this scan
    bAlarmNow := FALSE;
    eState := E_DL_StringInsState.eUndecidable;    // 进不可判相 / enter the undecidable state
    eErr := DL_SGF_CODE_INFO_1;                    // 信息级：绝缘推算不可判 / info: insulation not decidable
    bError := FALSE;                               // 信息级不置 bError（R45/R101）/ info never raises bError
ELSE
    (*--------------------------------------------------------------------------
     * 段 7｜量纲链落码（除式，禁乘式）：R_t = Rb x (Vp + Vn) / (Vbus − Vp − Vn)
     *   完全平衡退化（Vbus − Vp − Vn ≤ 1.0 V，绝缘趋无穷）→ 显式取上限哨兵，
     *   绝不让除子趋零、也绝不用乘式（乘式会把无穷绝缘算成 0 kΩ 并误告警）
     *-------------------------------------------------------------------------*)
    bDegenerate := FALSE;                          // 退化标志初值 / degenerate seed
    fDiffV := fBusV - fSumV;                       // 母线盈余 [V] / bus surplus [V]
    IF fDiffV <= DL_SGF_VMIN THEN
        bDegenerate := TRUE;                       // 完全平衡退化分支（显式）/ explicit degenerate branch
        fTotalKOhm := DL_SGF_R_MAX;                // 绝缘取上限哨兵 [kΩ] / insulation takes the ceiling sentinel
        fPosKOhm := DL_SGF_R_MAX;                  // 正极阻值同为上限哨兵 [kΩ] / positive takes the ceiling sentinel
        fNegKOhm := DL_SGF_R_MAX;                  // 负极阻值同为上限哨兵 [kΩ] / negative takes the ceiling sentinel
    ELSE
        fTotalKOhm := fBridgeKOhm * fSumV / fDiffV;                      // 并联绝缘电阻 [kΩ] / parallel insulation [kΩ]
        IF fTotalKOhm > DL_SGF_R_MAX THEN
            fTotalKOhm := DL_SGF_R_MAX;            // 上限饱和（防溢出）[kΩ] / ceiling saturation
        END_IF
        fPosKOhm := fTotalKOhm * fSumV / fNegToGroundV;                  // 正极 = R_t x (Vp+Vn)/Vn（除子段 6 已判非零）[kΩ] / positive pole
        fNegKOhm := fTotalKOhm * fSumV / fPosToGroundV;                  // 负极 = R_t x (Vp+Vn)/Vp [kΩ] / negative pole
        IF fPosKOhm > DL_SGF_R_MAX THEN
            fPosKOhm := DL_SGF_R_MAX;              // 上限饱和 [kΩ] / ceiling saturation
        END_IF
        IF fNegKOhm > DL_SGF_R_MAX THEN
            fNegKOhm := DL_SGF_R_MAX;              // 上限饱和 [kΩ] / ceiling saturation
        END_IF
    END_IF
    fInsPosKOhm := fPosKOhm;                       // 正极阻值出口 [kΩ] / positive resistance outlet
    fInsNegKOhm := fNegKOhm;                       // 负极阻值出口 [kΩ] / negative resistance outlet
    fInsTotalKOhm := fTotalKOhm;                   // 并联阻值出口 [kΩ] / parallel resistance outlet
    bUndecidable := FALSE;                         // 推算成立：不可判标志撤 / decidable, the flag drops
    bValid := TRUE;                                // 阻值可用 / resistances usable
    bError := FALSE;                               // 推算路径无故障 / no fault on the measurement path

    (*--------------------------------------------------------------------------
     * 段 8｜失衡判据：max(Rp,Rn) / min(Rp,Rn) > 3.0（除子先判零，退化时比值记 1）
     *-------------------------------------------------------------------------*)
    fMaxKOhm := fPosKOhm;                          // 极大值种子 / maximum seed
    IF fNegKOhm > fMaxKOhm THEN
        fMaxKOhm := fNegKOhm;                      // 负极更大 / the negative pole is larger
    END_IF
    fMinKOhm := fPosKOhm;                          // 极小值种子 / minimum seed
    IF fNegKOhm < fMinKOhm THEN
        fMinKOhm := fNegKOhm;                      // 负极更小 / the negative pole is smaller
    END_IF
    IF fMinKOhm > DL_SGF_TOL THEN
        fRatio := fMaxKOhm / fMinKOhm;             // 失衡比值（除子已判非零）[无量纲] / imbalance ratio
    ELSE
        fRatio := 1.0;                             // 极小值为零：比值不可算，按不失衡处理（不可判支路已前置）/ ratio unusable, treated as balanced
    END_IF
    bUnbalanced := (fRatio > DL_SGF_IMB_RATIO);    // 失衡判据 / imbalance predicate

    (*--------------------------------------------------------------------------
     * 段 9｜两级阈值确认与锁存：连续 nConfirmEff 拍低于阈值才置位，置位后锁存
     *       退化分支（绝缘哨兵）天然远高于阈值，不会触发，无需特判
     *-------------------------------------------------------------------------*)
    bAlarmNow := (fTotalKOhm < fAlarmKOhm);        // 告警判据 [kΩ] / alarm predicate
    bWarnNow := (fTotalKOhm < fWarnKOhm);          // 预警判据 [kΩ] / warning predicate
    IF bAlarmNow THEN
        IF nAlarmCnt < nConfirmEff THEN
            nAlarmCnt := nAlarmCnt + 1;            // 告警确认计数自增（上限即确认拍数）/ alarm counter increments up to the confirmation count
        END_IF
    ELSE
        nAlarmCnt := 0;                            // 断链即清零（防间歇性漏电被"攒"成告警）/ counter cleared on any drop-out
    END_IF
    IF bWarnNow THEN
        IF nWarnCnt < nConfirmEff THEN
            nWarnCnt := nWarnCnt + 1;              // 预警确认计数自增 / warning counter increments
        END_IF
    ELSE
        nWarnCnt := 0;                             // 断链即清零 / counter cleared
    END_IF
    IF nAlarmCnt >= nConfirmEff THEN
        bAlarm := TRUE;                            // 告警锁存（仅 bReset 可清）/ alarm latched, clearable only by reset
    END_IF
    IF nWarnCnt >= nConfirmEff THEN
        bWarn := TRUE;                             // 预警锁存（仅 bReset 可清）/ warning latched
    END_IF
    IF bAlarm THEN
        bWarn := TRUE;                             // 告警成立必然伴随预警（分级语义自洽）/ an alarm implies the warning
    END_IF

    (*--------------------------------------------------------------------------
     * 段 10｜出口码优先级：告警 > 预警 > 失衡提示 > 无错（同拍只能出一个码）
     *-------------------------------------------------------------------------*)
    IF bAlarm THEN
        eErr := 16#0000_0000;                      // 告警为状态量（bAlarm 出口），不占信息码位 / the alarm is a status, no info slot used
        eState := E_DL_StringInsState.eAlarm;      // 进告警监视相 / enter the alarm-monitoring state
    ELSIF bWarn THEN
        eErr := 16#0000_0000;                      // 预警同为状态量 / the warning is a status too
        eState := E_DL_StringInsState.eMeasure;    // 阻值仍有效，留在推算相 / resistances valid, stay in the measurement state
    ELSIF bUnbalanced THEN
        eErr := DL_SGF_CODE_INFO_2;                // 信息级：单极对地阻抗失衡提示 / info: single-pole imbalance hint
        eState := E_DL_StringInsState.eMeasure;    // 留推算相 / stay in the measurement state
    ELSE
        eErr := 16#0000_0000;                      // 无提示 / no hint
        eState := E_DL_StringInsState.eMeasure;    // 推算相 / measurement state
    END_IF
    IF bDegenerate AND (NOT bAlarm) AND (NOT bWarn) THEN
        eErr := 16#0000_0000;                      // 完全平衡（绝缘哨兵）无错，HMI 以饱和值显示 / balanced insulation reports no code
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 11｜状态机：CASE 含 ELSE 兜底（非法状态 → 035C + 阻值回零 + 许可撤）
 *       失能闸在此收口：不判、bValid := FALSE，但绝不清除已锁存的告警
 *----------------------------------------------------------------------------*)
CASE eState OF

    E_DL_StringInsState.eIdle:
        bValid := FALSE;                           // 失能闸显式不可用（R72）/ explicit FALSE on the disable gate
        fInsPosKOhm := DL_SGF_ZERO;                // 正极阻值回零 / positive resistance zeroed
        fInsNegKOhm := DL_SGF_ZERO;                // 负极阻值回零 / negative resistance zeroed
        fInsTotalKOhm := DL_SGF_ZERO;              // 并联阻值回零 / parallel resistance zeroed
        bUnbalanced := FALSE;                      // 失能不判失衡 / no imbalance verdict when disabled
        bUndecidable := FALSE;                     // 失能不报不可判 / no undecidable flag when disabled
        eErr := 16#0000_0000;                      // 待机无错 / no error in idle
        bError := FALSE;                           // 待机无故障 / no fault in idle
        // 失能绝不清除已锁存的 bWarn/bAlarm（历史事实，仅人工复位可清）/ a latched alarm survives a disable
        IF bEnable THEN
            eState := E_DL_StringInsState.eMeasure; // 使能进推算相 / enable enters the measurement state
            bFirstScan := FALSE;                   // 首拍标志清除 / first-scan flag cleared
        END_IF

    E_DL_StringInsState.eMeasure:
        bValid := TRUE;                            // 阻值可用 / resistances usable
        bError := FALSE;                           // 推算相无故障 / no fault on the measurement path
        IF NOT bEnable THEN
            eState := E_DL_StringInsState.eIdle;   // 失能回待机（退出条件一）/ disable, first exit
            bValid := FALSE;                       // 失能闸显式不可用 / explicit FALSE on the disable gate
        ELSIF bUndecidableNow THEN
            eState := E_DL_StringInsState.eUndecidable;   // 电压条件不成立转不可判（退出条件二）/ voltage conditions fail, second exit
        END_IF

    E_DL_StringInsState.eUndecidable:
        bValid := FALSE;                           // 阻值不可用（禁伪阻值，R42 家族）/ resistances unusable
        bError := FALSE;                           // 信息级不置 bError / info never raises bError
        eErr := DL_SGF_CODE_INFO_1;                // 信息级：绝缘推算不可判 / info: insulation not decidable
        IF NOT bEnable THEN
            eState := E_DL_StringInsState.eIdle;   // 失能回待机（退出条件一）/ disable, first exit
        ELSIF (NOT bUndecidableNow) THEN
            eState := E_DL_StringInsState.eMeasure;   // 电压条件恢复回推算相（退出条件二）/ conditions recovered, second exit
        END_IF

    E_DL_StringInsState.eAlarm:
        bValid := TRUE;                            // 阻值可用（告警期间继续监视）/ resistances usable, monitoring continues
        bError := FALSE;                           // 告警是状态量不是故障码 / an alarm is a status, not a fault code
        eErr := 16#0000_0000;                      // 不占信息码位 / no info slot used
        IF NOT bEnable THEN
            eState := E_DL_StringInsState.eIdle;   // 失能回待机（退出条件一，锁存保留）/ disable, first exit, the latch survives
            bValid := FALSE;                       // 失能闸显式不可用 / explicit FALSE on the disable gate
        ELSIF bUndecidableNow THEN
            eState := E_DL_StringInsState.eUndecidable;   // 电压条件不成立转不可判（退出条件二）/ undecidable, second exit
        ELSIF (NOT bAlarm) THEN
            eState := E_DL_StringInsState.eMeasure; // 复位清锁存后回推算相（退出条件三）/ latch cleared by reset, third exit
        END_IF

    E_DL_StringInsState.eFault:
        bValid := FALSE;                           // 故障闸显式不可用（R72）/ explicit FALSE on the fault gate
        bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
        fInsPosKOhm := DL_SGF_ZERO;                // 正极阻值回零安全侧 / positive resistance zeroed, safe side
        fInsNegKOhm := DL_SGF_ZERO;                // 负极阻值回零安全侧 / negative resistance zeroed, safe side
        fInsTotalKOhm := DL_SGF_ZERO;              // 并联阻值回零安全侧 / parallel resistance zeroed, safe side
        bUnbalanced := FALSE;                      // 故障态不判失衡 / no imbalance verdict in fault
        bUndecidable := FALSE;                     // 故障态不报不可判 / no undecidable flag in fault
        IF eErr = 16#0000_0000 THEN
            eErr := DL_SGF_CODE_FLT_3;             // 入口无码时按非法状态兜底（R45：bError 必须有对应码）/ illegal-state fallback
        END_IF
        IF bEnable AND (fBridgeKOhm > DL_SGF_TOL) AND (fAlarmKOhm < fWarnKOhm - DL_SGF_TOL) THEN
            eState := E_DL_StringInsState.eIdle;   // 组态恢复且使能才回待机（退出条件 ≥2）/ recover only when the configuration is sane
        END_IF

    ELSE
        eState := E_DL_StringInsState.eFault;      // 非法状态兜底 / illegal-state fallback
        eErr := DL_SGF_CODE_FLT_3;                 // 故障级兜底：非法状态 / fault fallback: illegal state
        bError := TRUE;                            // 故障级必置 bError（R45 配对）/ fault-class pairs with bError
        bValid := FALSE;                           // 阻值不可用 / resistances unusable
        fInsPosKOhm := DL_SGF_ZERO;                // 正极阻值回零安全侧 / positive resistance zeroed, safe side
        fInsNegKOhm := DL_SGF_ZERO;                // 负极阻值回零安全侧 / negative resistance zeroed, safe side
        fInsTotalKOhm := DL_SGF_ZERO;              // 并联阻值回零安全侧 / parallel resistance zeroed, safe side
        bUnbalanced := FALSE;                      // 失衡标志撤 / imbalance withdrawn

END_CASE
END_FUNCTION_BLOCK
