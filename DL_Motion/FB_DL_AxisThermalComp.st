(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AxisThermalComp
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（ABS），零厂商私有库
 * 功能描述 (Function)   : 轴热变形行程比例补偿：温度差 fTempDiffK（相对参考温，
 *                         K）经一阶热模型（时间常数 fTauS 可配）滤波后乘热
 *                         膨胀标度 fScaleUmK（µm/K）换算为行程补偿量：
 *                           α = fCy ÷ (fTauS + fCy)（离散一阶步长，域钳 [0,1]）
 *                           fFiltK = fFiltK + α × (fTempDiffK − fFiltK)
 *                           fCompValMm = fFiltK × fScaleUmK ÷ 1000
 *                         温度超域（|fTempDiffK| > fTMaxK）钳位并置信息码
 *                         eTempClamped；bEnable=FALSE 直通输出 0（规格指定，
 *                         R191 声明：未使能期强制归零而非冻结保持）。
 * 接口     (Interface)  : 输入 fTempDiffK 温度差（相对参考温） [K]、fScaleUmK
 *                         热膨胀标度（域 > 0） [µm/K]、fTauS 一阶热模型时间
 *                         常数（域 > 0） [s]、fTMaxK 温度差域半宽（域 > 0）
 *                         [K]、fCycle 扫描周期（<=0 用缺省） [s]、bEnable
 *                         使能、bReset 复位；输出 fCompValMm 行程补偿
 *                         [mm]、fFiltK 滤波后温度差（诊断透读） [K]、
 *                         eErrCode 错误码、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只算热补偿量，不测温度、
 *                         不接管轴使能**；温度采集归模拟量输入层。
 *                         ② 步长 α：fTauS <= 0 走组态锁存（规格域 > 0），
 *                         正常域 α = fCy/(fTauS+fCy) ∈ (0,1) 结构性稳定
 *                         （分母两项恒正，无除零）。
 *                         ③ 非有限判据（R79 双判）先行：温度差/标度非有限时
 *                         输出保持上次滤波值对应补偿量（冻结），置信息码
 *                         eInputHold，不污染滤波态。
 *                         ④ 组态闸：fScaleUmK <= 0、fTauS <= 0、fTMaxK <= 0
 *                         → 锁存故障，输出强制 0，解除沿 = bReset 上升沿。
 *                         ⑤ µm→mm 换算用常量除法（÷1000 非零常量，无除零）。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_AxisScrewPitchComp` 分工：几何螺距误差归
 *                         那件、热变形比例项归本件；与 `FB_DL_LeadLagCompensator`
 *                         分工：通用超前滞后归那件，本件内嵌一阶滤波为热模型
 *                         属主实现（不引用，独立验收）。
 * 来源标签 (Source Tag) : 自研线（一阶热模型与线性热膨胀为公开物理定义 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 LREAL 组 +
 *                         ENUM 错误码；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 步长域稳定 + 温度域钳位 + 非有限冻结 + 组态锁存
 *                         ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（无 ENUM 状态机） ｜ R7 ✓ 一 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R50 首版（批次 2 · 序号 8）
 * 验收向量 (Acceptance) : ① fScaleUmK=10, fTauS=60, fCycle=0.01：温度差恒
 *                         20 K 滤波收敛后 fFiltK→20，fCompValMm = 20×10÷1000
 *                         = 0.2 mm（稳态，eOk）；② 温度差 100 K，fTMaxK=80
 *                         → 钳 80 → 收敛后 fCompValMm = 0.8 mm，
 *                         eTempClamped；③ bEnable=FALSE → fCompValMm=0
 *                         （直通零，规格声明）；④ fTauS=0 → 锁存 eCfgBad。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_AtcErr（错误码；信息级不置 bError，故障级恒伴 bError=TRUE）
 *----------------------------------------------------------------------------*)
TYPE E_DL_AtcErr :
(
    eOk          := 0,   // 正常 / Normal
    eCfgBad      := 1,   // 故障级：组态非法（标度/时间常数/域半宽） / Fault: illegal configuration
    eTempClamped := 2,   // 信息级：温度差超域已钳位 / Info: temperature diff clamped
    eInputHold   := 3    // 信息级：输入非有限，滤波态冻结 / Info: non-finite input, filter state frozen
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisThermalComp
VAR_INPUT
    fTempDiffK : LREAL := 0.0;        // 温度差（相对参考温） [K] / Temperature difference from reference [K]
    fScaleUmK  : LREAL := 10.0;       // 热膨胀标度，域 > 0 [µm/K] / Thermal expansion scale [um/K]
    fTauS      : LREAL := 60.0;       // 一阶热模型时间常数，域 > 0 [s] / First-order thermal time constant [s]
    fTMaxK     : LREAL := 80.0;       // 温度差域半宽（对称 ±），域 > 0 [K] / Temperature domain half-width [K]
    fCycle     : LREAL := 0.0;        // 扫描周期（<=0 用缺省） [s] / Scan cycle, default used when <= 0
    bEnable    : BOOL := FALSE;       // 使能（FALSE=输出直通 0，规格声明） [-] / Enable, FALSE forces zero output
    bReset     : BOOL := FALSE;       // 复位，上升沿清组态故障锁存 [-] / Reset, rising edge clears cfg latch
END_VAR
VAR_OUTPUT
    fCompValMm : LREAL;               // 行程补偿输出（叠加位置设定侧） [mm] / Travel compensation output [mm]
    fFiltK     : LREAL;               // 滤波后温度差（诊断透读） [K] / Filtered temperature difference [K]
    eErrCode   : E_DL_AtcErr;         // 错误码出口 / Error code outlet
    bError     : BOOL;                // 故障标志（组态锁存） [-] / Error flag, latched
END_VAR
VAR
    _fFilt    : LREAL := 0.0;         // 滤波温度差锁存（冻结源） [K] / Filtered temperature latch
    _fCy      : LREAL;                // 当拍有效周期 [s] / Effective cycle this scan
    _fAlpha   : LREAL;                // 离散一阶步长（域 (0,1)） [-] / Discrete first-order step
    _fTempUse : LREAL;                // 钳位后温度差 [K] / Clamped temperature difference
    _bNonFin  : BOOL;                 // 输入非有限当拍量 [-] / Non-finite input this scan
    _bClamped : BOOL;                 // 本拍发生温度钳位 [-] / Temperature clamped this scan
    _bCfgBad  : BOOL;                 // 组态非法当拍量 [-] / Illegal configuration this scan
    _bErrLatch: BOOL;                 // 组态故障锁存位（解除沿 = bReset 上升沿） / Latched config fault
    rtReset   : R_TRIG;               // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_ATC_CYDEF  : LREAL := 0.01;    // 缺省扫描周期 [s] / Default scan cycle
    DL_ATC_UM2MM  : LREAL := 1000.0;  // µm→mm 换算常量（非零，无除零） [µm/mm] / um per mm constant
    DL_ATC_ZERO   : LREAL := 0.0;     // 判零基准 [K] / Zero base
    DL_ATC_ONE    : LREAL := 1.0;     // 步长钳位上界 [-] / Step ceiling
END_VAR

(* —— 段 0：非有限判 + 组态闸 + 周期派生 + 沿刷新 —— *)
_bNonFin := (fTempDiffK <> fTempDiffK) OR ((fTempDiffK - fTempDiffK) <> DL_ATC_ZERO)
         OR (fScaleUmK <> fScaleUmK) OR ((fScaleUmK - fScaleUmK) <> DL_ATC_ZERO);   // 输入非有限（R79 双判） / Non-finite inputs
_bCfgBad := (fScaleUmK <= DL_ATC_ZERO) OR (fTauS <= DL_ATC_ZERO) OR (fTMaxK <= DL_ATC_ZERO);   // 组态域闸 / Configuration gate
IF fCycle > DL_ATC_ZERO THEN
    _fCy := fCycle;                                // 组态周期有效 / Configured cycle valid
ELSE
    _fCy := DL_ATC_CYDEF;                          // 周期缺省兜底 / Default cycle fallback
END_IF
rtReset(CLK := bReset);                            // 复位沿，每拍必调 / Reset edge, every scan

(* —— 段 1：复位沿与组态锁存 —— *)
IF rtReset.Q THEN
    _bErrLatch := FALSE;                           // 清组态锁存（R188 声明：解除沿 = bReset 上升沿） / Clear cfg latch
END_IF
IF _bCfgBad AND (NOT _bErrLatch) THEN
    _bErrLatch := TRUE;                            // 锁存 / Latch
END_IF

(* —— 段 2：温度域钳位（非有限冻结滤波态，不污染） —— *)
_bClamped := FALSE;                                // 钳位量预清 / Clamp preset
_fTempUse := DL_ATC_ZERO;                          // 安全侧起步 0 / Safe-side start
IF (NOT _bErrLatch) AND (NOT _bNonFin) THEN
    _fTempUse := fTempDiffK;                       // 温度差工作副本 / Temperature working copy
    IF _fTempUse > fTMaxK THEN
        _fTempUse := fTMaxK;                       // 超上域钳位（规格） / Clamp high
        _bClamped := TRUE;                         // 记钳位 / Mark clamp
    ELSIF _fTempUse < (-fTMaxK) THEN
        _fTempUse := -fTMaxK;                      // 超下域钳位（对称 ±） / Clamp low symmetric
        _bClamped := TRUE;                         // 记钳位 / Mark clamp
    END_IF
END_IF

(* —— 段 3：一阶热模型递推与补偿合成（故障期冻结；未使能直通 0） —— *)
IF (NOT _bErrLatch) AND (NOT _bNonFin) THEN
    _fAlpha := _fCy / (fTauS + _fCy);              // 步长（分母两项恒正，无除零；fTauS>0 已闸） / Step size
    _fFilt := _fFilt + _fAlpha * (_fTempUse - _fFilt);   // 一阶热模型递推 / First-order thermal recursion
    IF bEnable THEN
        fCompValMm := _fFilt * fScaleUmK / DL_ATC_UM2MM;   // 补偿 = 滤波温差×标度÷1000 [mm] / Compensation synthesis
    ELSE
        fCompValMm := DL_ATC_ZERO;                 // 未使能直通 0（R191 声明：强制归零） / Disabled: forced zero
    END_IF
ELSIF (NOT _bErrLatch) AND _bNonFin THEN
    fCompValMm := _fFilt * fScaleUmK / DL_ATC_UM2MM;   // 非有限冻结：按上次滤波值输出（头注释③） / Freeze at last filtered value
ELSE
    fCompValMm := DL_ATC_ZERO;                     // 故障安全侧 0 / Fault safe-side zero
END_IF

(* —— 段 4：出口单点映射（名实双出口同源，R191） —— *)
fFiltK := _fFilt;                                  // 滤波温差透读出口 / Filtered temperature readout
IF _bErrLatch THEN
    bError := TRUE;                                // 故障标志（R45 配对） / Error flag
    eErrCode := E_DL_AtcErr.eCfgBad;               // 故障级码 / Fault code
ELSE
    bError := FALSE;                               // 无故障级条件 / No fault
    IF _bNonFin THEN
        eErrCode := E_DL_AtcErr.eInputHold;        // 信息级：冻结口径 / Info: frozen
    ELSIF _bClamped THEN
        eErrCode := E_DL_AtcErr.eTempClamped;      // 信息级：钳位口径 / Info: clamped
    ELSE
        eErrCode := E_DL_AtcErr.eOk;               // 正常 / Normal
    END_IF
END_IF

END_FUNCTION_BLOCK
