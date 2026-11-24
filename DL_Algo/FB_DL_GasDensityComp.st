//==============================================================================
// 功能块：FB_DL_GasDensityComp ｜ 中文名称：反应釜气体密度温压补偿
// 所属子库：DL_Algo ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：理想气体定律温压补偿——由工作温度与绝对压力换算气体密度：
//           rho = p·M / (R·T_K)，M 为介质摩尔质量 [g/mol]，R = 8.314462618
//           [J/(mol·K)]，T_K = T + 273.15。参考态密度 rho_ref 用参考温压
//           同式预计算（诊断出口）。骨架复用 FC_DL_AirDensity 的「域校验
//           + 钳位照算 + 非有限兜底」结构（该件介质常量固定为干空气/
//           水蒸气，反应釜介质摩尔质量可变，故本件以 M 引脚自持实现，
//           不调用该件——Algo 泳道内同口径双实现按 FC_DL_AirDensity 头
//           注释的零依赖纪律执行）。适用域：理想气体偏差可容忍的低压
//           工艺气（N2/Ar/H2/合成气等），近冷凝域给信息级外推提示。
// 开源溯源 (Origin)：道莅原创实现（参考理想气体状态方程与 FC_DL_AirDensity 域校验骨架 分类与参数域）
// 单位表：压力[千帕]（绝对）/ 温度[摄氏度] / 摩尔质量[克每摩尔] /
//         密度[千克每立方米] / 气体常数[J每摩尔开]
// 错误码表：16#0002_3201 信息级（温度/压力域外已钳位照算：温度域
//           [-40, 200] 摄氏度、压力域 [10, 2000] 千帕，不置 bError）/
//           16#0002_3202 信息级（理想气体外推提示：工作点温压比超出
//           参考态 0.5~2 倍温比或 10 倍压比工程带，按理想气体照算，
//           不置 bError）/ 16#0002_3205 预留禁用（不得挪用）/
//           16#0002_3210 故障级（摩尔质量 <= 0 或 > 200，或任一输入
//           非有限，组态非法，置 bError）/ 16#0002_3211 故障级（结果
//           非有限溢出，置 bError——该场景不可由 3210 的组态类判据
//           观测，属数值输出独立域）
// 状态机：E_DL_GasCompState（三态：eIdle=0 / eRun=10 / eFault=99），
//           CASE 含 ELSE 兜底，ELSE 置 3211 并冻结输出零
// 边界行为：① 摩尔质量域外或非有限 → 故障 3210 锁存，bReset 复位；
//           ② 温压域外 → 双侧钳位照算 + 信息 3201（现场宁要标注近似
//           的密度值，不因传感器越量程断链，与骨架件同策略）；
//           ③ 外推带 → 信息 3202 照算；④ 绝对温度下限 233.15 开由温度
//           下限保证，无除零面（T_K 恒正，R 为常量非零）；⑤ 未使能
//           输出冻结为零并 bValid := FALSE；⑥ 安全侧 = 故障/未使能路径
//           输出零密度，禁止残密度进入流量换算下游。
// 修订历史：v1.0.0 2026-11-17 首版（R24 派单 · ROADMAP P2 §670）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_GasCompState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 补偿使能相位，每个成员在 CASE 中有且仅有一个标签。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_GasCompState :
(
    eIdle  := 0,   // 空闲：未使能，输出冻结零 / Idle, not enabled, outputs frozen at zero
    eRun   := 10,  // 运行：使能且组态合法，每拍补偿 / Run, enabled with legal config, compensating per scan
    eFault := 99   // 故障：组态非法/非法状态 / Fault, illegal config or illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_GasDensityComp
VAR_INPUT
    fPressKpa    : LREAL := 101.325;        // 工作绝对压力 [千帕]，域 10..2000，域外钳位照算 / Working absolute pressure [kPa], domain 10..2000
    fTempC       : LREAL := 20.0;           // 工作温度 [摄氏度]，域 -40..200，域外钳位照算 / Working temperature [degC], domain -40..200
    fMolarMassG  : LREAL := 28.96;          // 介质摩尔质量 [克每摩尔]，有效域 (0, 200]，空气 28.96 / Medium molar mass [g/mol], valid range (0, 200]
    fPressRefKpa : LREAL := 101.325;        // 参考态绝对压力 [千帕]，须 > 0 / Reference absolute pressure [kPa], must be > 0
    fTempRefC    : LREAL := 20.0;           // 参考态温度 [摄氏度]，须 > -273.15 / Reference temperature [degC], must be above absolute zero
    bEnable      : BOOL;                    // 补偿使能 [—] / Compensation enable
    bReset       : BOOL;                    // 故障复位 [—]，上升沿清组态锁存 / Fault reset, rising edge clears the config latch
END_VAR
VAR_OUTPUT
    fRhoKgM3     : LREAL;                   // 补偿密度 [千克每立方米] / Compensated density [kg/m3]
    fRhoRefKgM3  : LREAL;                   // 参考态密度（诊断出口）[千克每立方米] / Reference density, diagnostics outlet [kg/m3]
    eState       : E_DL_GasCompState;       // 补偿相位 [—] / Compensation phase
    eErr         : UDINT;                   // 错误码，0 = 无错，码位 16#0002_3201 起信息级、16#0002_3210 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError       : BOOL;                    // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid       : BOOL;                    // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    _eState      : E_DL_GasCompState := E_DL_GasCompState.eIdle; // 当前相位 / Current phase
    _bParamBad   : BOOL;                    // 摩尔质量/参考态组态非法锁存 / Illegal molar mass or reference config latch
    _bInfoClamp  : BOOL;                    // 温压钳位信息当拍标志 / Temperature or pressure clamp info flag of this scan
    _bInfoExtrap : BOOL;                    // 外推带信息当拍标志 / Extrapolation-band info flag of this scan
    _fTUse       : LREAL;                   // 生效工作温度（已钳位）[摄氏度] / Effective working temperature, clamped
    _fPUse       : LREAL;                   // 生效工作压力（已钳位）[千帕] / Effective working pressure, clamped
    _fTKelvin    : LREAL;                   // 工作绝对温度 [开] / Working absolute temperature [K]
    _fTRefKelvin : LREAL;                   // 参考绝对温度 [开] / Reference absolute temperature [K]
    _bInit       : BOOL := FALSE;           // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
    _bIllegal    : BOOL;                    // 非法状态标志 / Illegal state flag
END_VAR
VAR CONSTANT
    DL_GDC_R_UNIV  : LREAL := 8.314462618;  // 通用气体常数 [焦耳每摩尔开] / Universal gas constant [J/(mol K)]
    DL_GDC_KELVIN  : LREAL := 273.15;       // 摄氏转开尔文偏移 [开] / Celsius to Kelvin offset [K]
    DL_GDC_T_MIN   : LREAL := -40.0;        // 工作温度域下限 [摄氏度] / Working temperature domain floor [degC]
    DL_GDC_T_MAX   : LREAL := 200.0;        // 工作温度域上限 [摄氏度] / Working temperature domain ceiling [degC]
    DL_GDC_P_MIN   : LREAL := 10.0;         // 工作压力域下限 [千帕] / Working pressure domain floor [kPa]
    DL_GDC_P_MAX   : LREAL := 2000.0;       // 工作压力域上限 [千帕] / Working pressure domain ceiling [kPa]
    DL_GDC_M_MAX   : LREAL := 200.0;        // 摩尔质量域上限 [克每摩尔] / Molar mass domain ceiling [g/mol]
    DL_GDC_MRATIO  : LREAL := 10.0;         // 外推带压比门限 [倍] / Extrapolation pressure-ratio threshold [ratio]
    DL_GDC_TRATIO  : LREAL := 2.0;          // 外推带温比门限（双侧 0.5~2）[倍] / Extrapolation temperature-ratio threshold [ratio]
    DL_GDC_EPS     : LREAL := 1.0E-6;       // 浮点判零容差 [混合] / Float zero tolerance
    DL_GDC_INF     : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_GDC_ZERO    : LREAL := 0.0;          // 零值常量，避免裸字面量 [混合] / Zero constant, avoids a bare literal
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：输出安全侧清零，单拍标志预清零
 *      Outputs cleared fail-safe first, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
fRhoKgM3    := DL_GDC_ZERO;              // 补偿密度先清（安全侧） / Compensated density cleared first
fRhoRefKgM3 := DL_GDC_ZERO;              // 参考密度先清 / Reference density cleared first
eErr   := 16#0000_0000;                  // 错误码每拍重算 / Error code recomputed
bError := FALSE;                         // 故障标志每拍重算 / Fault flag recomputed
bValid := FALSE;                         // 可用标志每拍重算 / Usable flag recomputed
_bInfoClamp  := FALSE;                   // 钳位信息预清零 / Clamp info pre-cleared
_bInfoExtrap := FALSE;                   // 外推信息预清零 / Extrapolation info pre-cleared
_bIllegal    := FALSE;                   // 非法状态预清零 / Illegal flag pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState    := E_DL_GasCompState.eIdle; // 相位空闲起步 / Phase starts idle
    _bParamBad := FALSE;                   // 组态锁存清零 / Config latch cleared
    _bInit     := TRUE;                    // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜组态防御闸：非有限（R79）+ 摩尔质量/参考态物理域
 *      Configuration defense gates: non-finite plus physical domains
 *-----------------------------------------------------------------------------*)
IF (fPressKpa <> fPressKpa) OR (ABS(fPressKpa) > DL_GDC_INF)
   OR (fTempC <> fTempC) OR (ABS(fTempC) > DL_GDC_INF)
   OR (fMolarMassG <> fMolarMassG) OR (ABS(fMolarMassG) > DL_GDC_INF)
   OR (fPressRefKpa <> fPressRefKpa) OR (ABS(fPressRefKpa) > DL_GDC_INF)
   OR (fTempRefC <> fTempRefC) OR (ABS(fTempRefC) > DL_GDC_INF) THEN
    _bParamBad := TRUE;                    // 非有限归组态非法锁存 / Non-finite folded into the config fault latch
END_IF
IF (NOT _bParamBad)
   AND ((fMolarMassG <= DL_GDC_EPS) OR (fMolarMassG > DL_GDC_M_MAX)
        OR (fPressRefKpa <= DL_GDC_EPS) OR (fTempRefC <= (-DL_GDC_KELVIN + 1.0))) THEN
    _bParamBad := TRUE;                    // 摩尔质量/参考态组态非法锁存 / Molar mass or reference config latched
END_IF
IF bReset THEN
    _bParamBad := FALSE;                   // 复位清组态锁存 / Reset clears the config latch
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜相位机（CASE 含 ELSE 兜底；未使能/异常一律落故障态全零）
 *      Phase machine with ELSE fallback, not-enabled or anomaly to fault
 *-----------------------------------------------------------------------------*)
IF (NOT bEnable) OR _bParamBad THEN
    _eState := E_DL_GasCompState.eFault;   // 未使能或组态非法转故障态（全零） / Not enabled or illegal config, fault with zeros
ELSE
CASE _eState OF

    E_DL_GasCompState.eIdle:               // 空闲：使能即进运行
        IF bEnable THEN
            _eState := E_DL_GasCompState.eRun; // 进运行 / To run
        END_IF

    E_DL_GasCompState.eRun:                // 运行：每拍补偿（段 5 执行）
        IF NOT bEnable THEN
            _eState := E_DL_GasCompState.eFault; // 使能撤销转故障态（全零） / Enable dropped, fault with zeros
        END_IF

    E_DL_GasCompState.eFault:              // 故障：使能且复位沿回运行
        IF bEnable AND (NOT _bParamBad) THEN
            _eState := E_DL_GasCompState.eRun; // 回运行 / Back to run
        END_IF

    ELSE                                   // 非法状态兜底（R21：CASE 必带 ELSE）
        _bIllegal := TRUE;                 // 标记非法状态 / Flag the illegal state
        _eState   := E_DL_GasCompState.eFault; // 回故障态（全零） / Back to fault, zeros
END_CASE
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜补偿计算（仅运行态）：域钳位照算 + 外推带提示 + 理想气体定律
 *      Compensation in the run phase: clamp-and-continue plus ideal-gas law
 *-----------------------------------------------------------------------------*)
IF _eState = E_DL_GasCompState.eRun THEN
    _fTUse := fTempC;                      // 工作温度生效 / Working temperature applied
    IF (_fTUse < DL_GDC_T_MIN) OR (_fTUse > DL_GDC_T_MAX) THEN
        _fTUse := MIN(MAX(_fTUse, DL_GDC_T_MIN), DL_GDC_T_MAX); // 温度双侧钳位 / Two-sided temperature clamp
        _bInfoClamp := TRUE;               // 钳位信息置位 / Clamp info raised
    END_IF
    _fPUse := fPressKpa;                   // 工作压力生效 / Working pressure applied
    IF (_fPUse < DL_GDC_P_MIN) OR (_fPUse > DL_GDC_P_MAX) THEN
        _fPUse := MIN(MAX(_fPUse, DL_GDC_P_MIN), DL_GDC_P_MAX); // 压力双侧钳位 / Two-sided pressure clamp
        _bInfoClamp := TRUE;               // 钳位信息置位 / Clamp info raised
    END_IF
    _fTKelvin    := _fTUse + DL_GDC_KELVIN;     // 工作绝对温度 [开]，下限 233.15 恒正 / Working Kelvin, floor 233.15, always positive
    _fTRefKelvin := fTempRefC + DL_GDC_KELVIN;  // 参考绝对温度 [开] / Reference Kelvin
    fRhoKgM3 := (_fPUse * 1000.0) * (fMolarMassG / 1000.0) / (DL_GDC_R_UNIV * _fTKelvin); // 理想气体密度 [千克每立方米]，分母恒正 / Ideal-gas density, denominator always positive
    fRhoRefKgM3 := (fPressRefKpa * 1000.0) * (fMolarMassG / 1000.0) / (DL_GDC_R_UNIV * _fTRefKelvin); // 参考态密度 [千克每立方米] / Reference density
    IF (_fPUse > DL_GDC_MRATIO * fPressRefKpa)
       OR (_fTKelvin < (0.5 * _fTRefKelvin)) OR (_fTKelvin > (DL_GDC_TRATIO * _fTRefKelvin)) THEN
        _bInfoExtrap := TRUE;              // 理想气体外推带提示（照算） / Extrapolation-band notice, computed as-is
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜码位出口与放行（故障级码 3 行内置 bError，R45/R101 配对）
 *      Code outlet and release, fault codes paired with bError
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN
    eErr   := 16#0002_3211;                // 故障级：状态机兜底（结果域） / Fault: state machine fallback
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bParamBad THEN
    eErr   := 16#0002_3210;                // 故障级：组态非法 / Fault: illegal configuration
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bInfoClamp THEN
    eErr := 16#0002_3201;                  // 信息级：温压域外已钳位照算 / Info: clamped, computed as-is
ELSIF _bInfoExtrap THEN
    eErr := 16#0002_3202;                  // 信息级：理想气体外推带照算 / Info: extrapolation band, computed as-is
END_IF

bValid := (NOT bError) AND (_eState = E_DL_GasCompState.eRun); // 仅运行态放行 / Usable only in the run phase
eState := _eState;                       // 相位出口 / Phase outlet
END_FUNCTION_BLOCK
