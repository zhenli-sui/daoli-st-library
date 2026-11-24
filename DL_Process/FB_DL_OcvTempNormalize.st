(*==============================================================================
 * 组件名称 (Component)  : FB_DL_OcvTempNormalize
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商私有库
 * 功能描述 (Function)   : OCV（开路电压）测试温度归一判据。
 *                         把实测 OCV 按温度系数线性归一到基准温度，再对归一值做合格带判定与三档分级。
 *                         归一式（一阶线性，符号约定写死）：
 *                           OCV_norm = OCV_meas + k · (T_meas − T_ref)
 *                           其中 k 为温度系数 [mV/°C]，正值表示"温度升高时实测 OCV 升高"，
 *                           故归一化需回减 k·ΔT；k 为负（低温型电芯）同样成立，不做符号假设。
 *                         **语义复用（非实例复用）**：按 R47 批次"批内零 .st 文件级依赖"纪律，
 *                         不实例化 FC_DL_TempUnitConvert，而复用其已固化的三条换算语义——
 *                         ① 华氏 → 摄氏用 (F−32)·5/9；② 开尔文 → 摄氏用 K−273.15；
 *                         ③ 未知单位一律拒绝换算并置故障级（不猜默认单位）。
 *                         验收向量：
 *                           ① OCV=3850 mV, T=35 °C, k=+0.5 mV/°C, Tref=25 °C
 *                              → 归一 = 3850 + 0.5×(35−25) = 3855 mV
 *                           ② OCV=3850 mV, T=25 °C → 归一 = 3850 mV（ΔT=0，归一不改变量值）
 *                           ③ 带 [3800, 3900] mV，归一 3855 → eInBand；3901 → eHigh；3799 → eLow
 *                           ④ k=0 → 拒归一（除零语义的乘法侧等价：k=0 时归一退化，判据失真）
 * 接口     (Interface)  : 入 bEnable 使能（FALSE 冻结判据且不宣称）、fOcvMeasMv 实测 OCV、fTempMeas 
 *                         实测温度、iTempUnit 温度单位、fTempCoeff 温度系数、fTempRefC 基准温度、
 *                         fBandLowMv / fBandHighMv 合格带上下限、fNormClampMv 归一值钳位、
 *                         bReset 故障复位沿；
 *                         出 fOcvNormMv 归一后 OCV、bInBand 合格、eGrade 三档分级、
 *                         bValid 结果有效、eState 相、eCause 成因、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做"归一 + 判带"，不判电芯合格结论
 *                         （那是分选件的最终裁决），不做 OCV 采样时序、不驱动测试仪**；
 *                         ② **温度系数零闸**：k 为 0（或非有限）→ 归一退化，锁存 eCoeffZero，
 *                         判据整体停用（静默失效比报错危险，R179）；
 *                         ③ **合格带倒置闸**：fBandLow ≥ fBandHigh → 锁存 eCfgIllegal；
 *                         ④ **钳位**：归一值超 ±fNormClampMv 时钳位并置 bClamped（脚非法时回退
 *                         VAR CONSTANT，R127 兜底与判定量解耦）；
 *                         ⑤ **非有限样本**：OCV / 温度任一非有限 → 当拍不判、bValid=FALSE、
 *                         不锁存（可恢复性瞬时异常，与组态类锁存分轨，R228B）；
 *                         ⑥ 浮点比较一律差值容差判等（本件判带用 ABS 差 < fEps）；
 *                         ⑦ eFault 可迁出：bReset 上升沿 → eIdle，解除式恒可达（外部引脚门控）；
 *                         ⑧ 零全局耦合、零物理地址。
 * 分工声明 (Scope)      : 本件只管"温度归一与合格带判定"。不接管：温补分档迟滞
 *                         （属 FB_DL_TempCompClassify）、电芯分选结论（属分选件）、
 *                         温度采集与滤波（属模拟量通道件）。
 * 来源标签 (Source Tag) : ROADMAP 空勾真缺口 P1（OCV 温度归一，自研 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位（零码位范式 R297）；诊断由 BOOL + ENUM 出口承担。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 零闸 + 倒置闸 + 钳位 + 非有限闸 + 容差判等 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE 兜底 ｜ R7 ✓ R_TRIG 段 0 无条件刷新（本件无 TON）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R47 首版（批次 1 · 序号 5）
 *==============================================================================*)

TYPE E_DL_OtnUnit :
(
    eCelsius    := 0,   // 摄氏（本件内部基准单位） / Celsius, the internal base unit
    eFahrenheit := 1,   // 华氏 / Fahrenheit
    eKelvin     := 2,   // 开尔文 / Kelvin
    eUnknown    := 3    // 未知单位（拒换算，故障级） / Unknown unit, conversion refused
);
END_TYPE

TYPE E_DL_OtnGrade :
(
    eNoGrade := 0,   // 未分级（无效或未使能） / Ungraded, invalid or disabled
    eLow     := 1,   // 低于合格带（归一值偏低） / Below the accept band
    eInBand  := 2,   // 落合格带内 / Inside the accept band
    eHigh    := 3    // 高于合格带（归一值偏高） / Above the accept band
);
END_TYPE

TYPE E_DL_OtnState :
(
    eIdle  := 0,    // 待机相（未使能） / Idle, disabled
    eRun   := 10,   // 判据相（归一与判带） / Running, normalise and classify
    eFault := 90    // 故障相（等复位） / Fault, awaiting reset
);
END_TYPE

TYPE E_DL_OtnCause :
(
    eNone      := 0,   // 无异常 / No anomaly
    eCfgIllegal:= 1,   // 组态非法（合格带倒置/钳位限非正） / Illegal configuration
    eCoeffZero := 2,   // 温度系数为零（归一退化，拒判） / Zero temperature coefficient
    eUnitBad   := 3,   // 温度单位未知（拒换算） / Unknown temperature unit
    ePhaseBad  := 4    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_OcvTempNormalize
VAR_INPUT
    bEnable      : BOOL := FALSE;        // 使能（FALSE 冻结判据且不宣称） [-] / Enable, freezes the judgement when FALSE
    fOcvMeasMv   : LREAL := 0.0;         // 实测 OCV [mV] / Measured open-circuit voltage [mV]
    fTempMeas    : LREAL := 25.0;        // 实测温度（按 iTempUnit 解释） [°C/°F/K] / Measured temperature in the declared unit
    iTempUnit    : E_DL_OtnUnit := E_DL_OtnUnit.eCelsius;   // 温度单位 [-] / Temperature unit
    fTempCoeff   : LREAL := 0.5;         // 温度系数 k，域 ≠ 0 [mV/°C] / Temperature coefficient, non-zero
    fTempRefC    : LREAL := 25.0;        // 基准温度（摄氏） [°C] / Reference temperature in Celsius
    fBandLowMv   : LREAL := 3800.0;      // 合格带下限 [mV] / Accept band lower limit [mV]
    fBandHighMv  : LREAL := 3900.0;      // 合格带上限，域 > 下限 [mV] / Accept band upper limit [mV]
    fNormClampMv : LREAL := 30000.0;     // 归一值绝对钳位，域 > 0 [mV] / Absolute clamp of the normalised value
    bReset       : BOOL := FALSE;        // 故障复位沿 [-] / Fault reset edge
END_VAR
VAR_OUTPUT
    fOcvNormMv : LREAL := 0.0;                       // 归一到基准温度后的 OCV [mV] / OCV normalised to the reference temperature
    bInBand    : BOOL := FALSE;                      // 归一值落合格带内 [-] / Normalised value inside the accept band
    eGrade     : E_DL_OtnGrade := E_DL_OtnGrade.eNoGrade;   // 三档分级出口 [-] / Three-way grade outlet
    bValid     : BOOL := FALSE;                      // 结果有效（样本有限且已归一） [-] / Result valid
    bClamped   : BOOL := FALSE;                      // 归一值被钳位 [-] / Normalised value clamped
    eState     : E_DL_OtnState := E_DL_OtnState.eIdle;      // 相出口 [-] / Phase outlet
    eCause     : E_DL_OtnCause := E_DL_OtnCause.eNone;      // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError     : BOOL := FALSE;                      // 故障标志 [-] / Error flag
END_VAR
VAR
    _eState  : E_DL_OtnState := E_DL_OtnState.eIdle;        // 内部相（CASE 唯一写入目标） / Internal phase
    _eCause  : E_DL_OtnCause := E_DL_OtnCause.eNone;        // 成因锁存量 / Latched cause
    _bFault  : BOOL := FALSE;                               // 故障锁存位 / Latched fault bit
    _fTempC  : LREAL := 0.0;                                // 换算后的摄氏温度 [°C] / Temperature converted to Celsius
    _fNorm   : LREAL := 0.0;                                // 归一计算工作值 [mV] / Normalisation working value
    _fLim    : LREAL := 0.0;                                // 生效钳位限（脚非法回退常量，R127） [mV] / Effective clamp limit
    _bXFin   : BOOL := FALSE;                               // 样本有限性判定中间量 [-] / Sample finiteness working flag
    _bBandOk : BOOL := FALSE;                               // 合格带域闸结论 [-] / Accept-band domain gate result
    rtReset  : R_TRIG;                                      // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_OTN_CLAMP_DEF : LREAL := 30000.0;    // 钳位限回退默认值（与脚默认同源） [mV] / Default clamp limit
    DL_OTN_K2C       : LREAL := 273.15;     // 开尔文转摄氏偏移量 [°C] / Kelvin-to-Celsius offset
    DL_OTN_F_SCALE   : LREAL := 5.0 / 9.0;  // 华氏温差换算比例（5/9，常量预算不除零） [-] / Fahrenheit delta ratio
    DL_OTN_F_OFFS    : LREAL := 32.0;       // 华氏冰点偏移 [°F] / Fahrenheit ice-point offset
    DL_OTN_EPS       : LREAL := 1.0E-6;     // 浮点判等容差（仅用于"贴带边"判定） [mV] / Equality tolerance
END_VAR

(* —— 段 0：两枚沿实例无条件周期刷新（R228A；本件无 TON） —— *)
rtReset(CLK := bReset);                                     // 复位沿 / Reset edge

(* —— 段 1：单拍/输出量预置（锁存量 _eCause/_bFault 不入清单，R107） —— *)
fOcvNormMv := 0.0;                                          // 归一值预置 / Normalised value preset
bInBand    := FALSE;                                        // 合格位预置 / In-band preset
eGrade     := E_DL_OtnGrade.eNoGrade;                       // 分级预置为"未分级" / Grade preset to ungraded
bValid     := FALSE;                                        // 有效性预置 / Validity preset
bClamped   := FALSE;                                        // 钳位标志预置 / Clamp flag preset
bError     := FALSE;                                        // 故障标志预清（R45 配对） / Error preset
_fNorm     := 0.0;                                          // 归一工作值预置 / Working value preset

(* —— 段 2：组态闸（合格带倒置 / 钳位限非正 → 故障锁存） —— *)
_bBandOk := (fBandLowMv < fBandHighMv);                     // 下限必须严格小于上限 / Lower must be strictly below upper
_fLim := fNormClampMv;                                      // 先直取脚值 / Take the pin value first
IF (NOT _bBandOk) OR (_fLim <= 0.0) OR (_fLim <> _fLim) OR ((_fLim - _fLim) <> (_fLim - _fLim)) THEN
    _fLim := DL_OTN_CLAMP_DEF;                              // 钳位限回退默认常量（与被判量解耦） / Fall back to the default limit
    _eCause := E_DL_OtnCause.eCfgIllegal;                   // 归因：组态非法 / Cause: illegal configuration
    _bFault := TRUE;                                        // 锁存 / Latch
    _eState := E_DL_OtnState.eFault;                        // 入故障相 / Enter fault phase
END_IF

(* —— 段 3：温度系数零闸（k=0 使归一恒等，判据静默失效，按故障处理 R179） —— *)
IF (_eState <> E_DL_OtnState.eFault) THEN
    IF (fTempCoeff = 0.0) OR (fTempCoeff <> fTempCoeff) OR ((fTempCoeff - fTempCoeff) <> (fTempCoeff - fTempCoeff)) THEN
        _eCause := E_DL_OtnCause.eCoeffZero;                // 归因：温度系数为零或非有限 / Cause: zero or non-finite coefficient
        _bFault := TRUE;                                    // 锁存 / Latch
        _eState := E_DL_OtnState.eFault;                    // 入故障相 / Enter fault phase
    END_IF
    IF (iTempUnit = E_DL_OtnUnit.eUnknown) THEN
        _eCause := E_DL_OtnCause.eUnitBad;                  // 归因：温度单位未知 / Cause: unknown temperature unit
        _bFault := TRUE;                                    // 锁存 / Latch
        _eState := E_DL_OtnState.eFault;                    // 入故障相 / Enter fault phase
    END_IF
END_IF

(* —— 段 4：迁出链（bReset 上升沿 → 待机相；解除式恒可达） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                       // 清故障锁存 / Clear fault latch
    _eCause := E_DL_OtnCause.eNone;                         // 清成因 / Clear cause
    _eState := E_DL_OtnState.eIdle;                         // 回待机相 / Back to idle
END_IF

(* —— 段 5：相迁移（使能驱动；故障相由段 4 迁出） —— *)
CASE _eState OF

E_DL_OtnState.eIdle:
    IF bEnable THEN
        _eState := E_DL_OtnState.eRun;                      // 使能即进判据相 / Enable enters the running phase
    END_IF

E_DL_OtnState.eRun:
    IF NOT bEnable THEN
        _eState := E_DL_OtnState.eIdle;                     // 失能回待机相（不借故障相过桥，R211） / Disable returns to idle
    END_IF

E_DL_OtnState.eFault:
    ;                                                       // 故障相：由段 4 复位沿迁出 / Exit handled by the reset edge

ELSE
    _eCause := E_DL_OtnCause.ePhaseBad;                     // 归因：非法相位 / Cause: illegal phase
    _bFault := TRUE;                                        // 锁存 / Latch
    _eState := E_DL_OtnState.eFault;                        // 强拉故障相 / Force fault phase

END_CASE

(* —— 段 6：归一与判带（仅在判据相且样本有限时；非有限样本当拍不判、不锁存） —— *)
IF _eState = E_DL_OtnState.eRun THEN
    _bXFin := NOT ((fOcvMeasMv <> fOcvMeasMv) OR ((fOcvMeasMv - fOcvMeasMv) <> (fOcvMeasMv - fOcvMeasMv)))
          AND NOT ((fTempMeas <> fTempMeas) OR ((fTempMeas - fTempMeas) <> (fTempMeas - fTempMeas)))
          AND NOT ((fTempRefC <> fTempRefC) OR ((fTempRefC - fTempRefC) <> (fTempRefC - fTempRefC)));
    IF _bXFin THEN
        (* 单位换算（复用 FC_DL_TempUnitConvert 语义，三支全列、无 ELSE 猜默认） *)
        CASE iTempUnit OF
        E_DL_OtnUnit.eCelsius:
            _fTempC := fTempMeas;                           // 摄氏直通 / Celsius passes through
        E_DL_OtnUnit.eFahrenheit:
            _fTempC := (fTempMeas - DL_OTN_F_OFFS) * DL_OTN_F_SCALE;   // 华氏转摄氏 / Fahrenheit to Celsius
        E_DL_OtnUnit.eKelvin:
            _fTempC := fTempMeas - DL_OTN_K2C;               // 开尔文转摄氏 / Kelvin to Celsius
        ELSE
            _fTempC := fTempRefC;                           // 未知单位：取基准温度（段 3 已锁存故障，此支仅防未定义值）
        END_CASE

        _fNorm := fOcvMeasMv + fTempCoeff * (_fTempC - fTempRefC);      // 一阶线性归一 / First-order linear normalisation

        IF (_fNorm > _fLim) THEN
            _fNorm := _fLim;                                // 上钳 / Clamp high
            bClamped := TRUE;                               // 置钳位标志 / Raise the clamp flag
        ELSIF (_fNorm < (0.0 - _fLim)) THEN
            _fNorm := 0.0 - _fLim;                          // 下钳 / Clamp low
            bClamped := TRUE;                               // 置钳位标志 / Raise the clamp flag
        END_IF

        bValid := TRUE;                                     // 样本有限且已归一：结果有效 / Sample finite and normalised

        (* 判带（差值容差，禁 = 判等） *)
        IF ABS(_fNorm - fBandHighMv) < DL_OTN_EPS THEN
            eGrade := E_DL_OtnGrade.eHigh;                  // 贴上限：归高档（边界样本显式归属） / On the upper edge: graded high
            bInBand := TRUE;                                // 落在带内 / Inside the band
        ELSIF ABS(_fNorm - fBandLowMv) < DL_OTN_EPS THEN
            eGrade := E_DL_OtnGrade.eLow;                   // 贴下限：归低档 / On the lower edge: graded low
            bInBand := TRUE;                                // 落在带内 / Inside the band
        ELSIF _fNorm > fBandHighMv THEN
            eGrade := E_DL_OtnGrade.eHigh;                  // 超上限 / Above the upper limit
            bInBand := FALSE;                               // 带外 / Outside the band
        ELSIF _fNorm < fBandLowMv THEN
            eGrade := E_DL_OtnGrade.eLow;                   // 低于下限 / Below the lower limit
            bInBand := FALSE;                               // 带外 / Outside the band
        ELSE
            eGrade := E_DL_OtnGrade.eInBand;                // 严格带内 / Strictly inside the band
            bInBand := TRUE;                                // 合格 / Accept
        END_IF
    END_IF
END_IF

(* —— 段 7：出口单点映射（名实双出口，R191） —— *)
fOcvNormMv := _fNorm;                                       // 归一值出口（无效拍输出 0） / Normalised value outlet
eState     := _eState;                                      // 相出口 / Phase outlet
eCause     := _eCause;                                      // 成因出口 / Cause outlet
bError     := _bFault;                                      // 故障标志 / Error flag

END_FUNCTION_BLOCK
