(*==============================================================================
 * 组件名称 (Component)  : FC_DL_HumidityUnitConvert
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准数学（EXP），零厂商私有库
 * 功能描述 (Function)   : 湿度换算：相对湿度 RH% ↔ 绝对湿度 AH[g/m³]。
 *                         饱和水汽压用 Magnus 近似式（WMO 常用系数）：
 *                           Psat(T) = 6.112 × EXP(17.62 × T / (243.12 + T))    [hPa]
 *                           AH = (RH/100) × 216.7 × Psat(T) / (T + 273.15)    [g/m3]
 *                           RH = AH × (T + 273.15) / (216.7 × Psat(T)) × 100  [%]
 *                         两式互为反函数（AH 侧以 fValue 为 AH 求 RH，反之亦然），
 *                         故本件自成闭环，不依赖外部湿度表。
 * 接口     (Interface)  : 输入 fValue 被换算湿度 [源单位]、eSrc 源单位、eDst 目标单位、
 *                         fTempC 干球温度 [℃]（**换算必需，非可选**）；
 *                         输出 fConverted 换算结果 [目标单位]、eErrCode（E_DL_HumConvErr）；
 *                         返回值 = bValid 数值可信标志（TRUE = fConverted 可信）。
 * 边界     (Boundary)   : ① 属主边界：只做 RH↔AH 换算，不做露点 / 焓值 / 湿球温度计算。
 *                         ② **适用域**：干球温度 -40..80 ℃（Magnus 式标定域），超域 → 故障级
 *                         eTempOutOfRange（外推会显著失真，禁止静默外推）。
 *                         ③ **全部浮点入参做非有限双判**（fValue 与 fTempC 逐一枚举，
 *                         含换算用的温度量，防止 NaN 温度使结果静默失效）。
 *                         ④ RH 源值域 0..100，超域 → 故障级 eRhOutOfRange。
 *                         AH 源值必须非负，负值 → 故障级 eNegativeValue。
 *                         ⑤ 反算 RH 结果超 100（过饱和）→ 钳位 100 并置信息级 eClampRh。
 *                         ⑥ 分母防护：Psat 恒 > 0（指数函数）；(243.12+T) 在适用域内恒 >= 203.12；
 *                         (T+273.15) 在适用域内恒 >= 233.15；另加显式判零分支作双保险。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_ConcentrationUnitConvert` 分工：气体浓度归那件；
 *                         与露点/焓值件（未入库）分工：本件不含相变焓计算。
 * 来源标签 (Source Tag) : 开源溯源：lgf-math 换算系数（公开物理常数，clean-room 重写）；许可证 MIT（仅参考语义，代码原创）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + LREAL +
 *                         本文件内定义 enum E_DL_HumConvErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 全部浮点入参非有限双判 + 温度域闸 + RH 域闸 + 分母显式判零 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B2 · 序号 19）
 * 验收向量 (Acceptance) : ① fValue=50.0(RH), eSrc=eRhPercent, eDst=eAbsGm3, fTempC=25.0 →
 *                         Psat=6.112×EXP(17.62×25/268.12)=31.6713 hPa（容差 1E-3），
 *                         AH=0.5×216.7×31.6713/298.15 ≈ 11.511 g/m3（容差 1E-2）；
 *                         ② fValue=11.511, eSrc=eAbsGm3, eDst=eRhPercent, fTempC=25.0 →
 *                         RH ≈ 50.0 %（容差 1E-2，与 ① 互逆）；
 *                         ③ eSrc=eDst 直通：fValue=42.0 原样返回，eOk；
 *                         ④ fTempC=100.0 → 返回 FALSE, 0, eTempOutOfRange；
 *                         ⑤ fValue=120.0(RH), eSrc=eRhPercent → 返回 FALSE, 0, eRhOutOfRange。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_HumUnit（湿度单位表，归属 DL_MathData，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_HumUnit :
(
    eRhPercent := 0,   // 相对湿度（百分数） [%RH] / Relative humidity in percent
    eAbsGm3    := 1    // 绝对湿度（每立方米水汽克数） [g/m3] / Absolute humidity in grams per cubic metre
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_HumConvErr（湿度换算错误码）
 *----------------------------------------------------------------------------*)
TYPE E_DL_HumConvErr :
(
    eOk             := 0,   // 信息级：换算完成 / Info: conversion completed
    eClampRh        := 1,   // 信息级：反算 RH 过饱和已钳位 100 / Info: computed RH clamped to 100
    eInvalidUnit    := 2,   // 故障级：单位枚举越域 / Fault: unit enum out of domain
    eNonFinite      := 3,   // 故障级：入参非有限 / Fault: non-finite input
    eTempOutOfRange := 4,   // 故障级：干球温度超出 Magnus 标定域 / Fault: dry-bulb temperature out of calibrated range
    eRhOutOfRange   := 5,   // 故障级：RH 源值超出 0..100 / Fault: RH source out of range
    eNegativeValue  := 6    // 故障级：AH 源值为负 / Fault: negative absolute humidity
);
END_TYPE

FUNCTION FC_DL_HumidityUnitConvert : BOOL
VAR_INPUT
    fValue : LREAL;         // 被换算湿度值 [源单位] / Humidity value in source unit
    eSrc   : E_DL_HumUnit;  // 源单位枚举 [-] / Source unit enum
    eDst   : E_DL_HumUnit;  // 目标单位枚举 [-] / Destination unit enum
    fTempC : LREAL;         // 干球温度（换算必需） [℃] / Dry-bulb temperature, mandatory for conversion [degC]
END_VAR
VAR_OUTPUT
    fConverted : LREAL;           // 换算结果 [目标单位] / Converted result
    fSatPress  : LREAL;           // 饱和水汽压（诊断用） [hPa] / Saturation vapour pressure, diagnostic [hPa]
    eErrCode   : E_DL_HumConvErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _bNonFin : BOOL;   // 入参非有限当拍标志 [-] / Non-finite input flag
    _fDen    : LREAL;  // 显式分母防护量 [-] / Explicit denominator guard value
    _fRat    : LREAL;  // 中间比值（RH 分数 / 缩放后 AH） [-] / Intermediate ratio
END_VAR
VAR CONSTANT
    DL_HUC_A     : LREAL := 17.62;     // Magnus 分子系数 [-] / Magnus numerator coefficient
    DL_HUC_B     : LREAL := 243.12;    // Magnus 分母常数 [℃] / Magnus denominator constant
    DL_HUC_C     : LREAL := 6.112;     // 0 ℃ 饱和水汽压 [hPa] / Saturation pressure at zero degC
    DL_HUC_K     : LREAL := 216.7;     // 水汽气体常数换算因子 [g/m3 per hPa] / Water vapour conversion factor
    DL_HUC_KABS  : LREAL := 273.15;    // 摄氏转开尔文偏移 [K] / Celsius to Kelvin offset
    DL_HUC_HUND  : LREAL := 100.0;     // 百分数换算因子 [-] / Percent scaling factor
    DL_HUC_TMIN  : LREAL := -40.0;     // 干球温度下限 [℃] / Dry-bulb lower bound [degC]
    DL_HUC_TMAX  : LREAL := 80.0;      // 干球温度上限 [℃] / Dry-bulb upper bound [degC]
    DL_HUC_RHMAX : LREAL := 100.0;     // 相对湿度上限 [%RH] / Relative humidity ceiling
    DL_HUC_ZERO  : LREAL := 0.0;       // 零基准与非有限判零基准 [-] / Zero and non-finite base
    DL_HUC_TINY  : LREAL := 1.0E-9;    // 分母近似零阈值 [-] / Near-zero denominator threshold
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_HumidityUnitConvert := FALSE;                // 返回值预置无效 / Return preset invalid
fConverted := DL_HUC_ZERO;                         // 结果哨兵 0 / Result sentinel
fSatPress  := DL_HUC_ZERO;                         // 饱和压哨兵 0 / Saturation pressure sentinel
eErrCode   := E_DL_HumConvErr.eInvalidUnit;        // 预置最严码 / Preset strictest code

(* —— 段 1：非有限域闸（每个浮点入参逐一枚举：湿度值与温度值） —— *)
_bNonFin := (fValue <> fValue) OR ((fValue - fValue) <> DL_HUC_ZERO);      // 湿度值非有限 / Humidity non-finite
_bNonFin := _bNonFin OR (fTempC <> fTempC) OR ((fTempC - fTempC) <> DL_HUC_ZERO);  // 温度值非有限 / Temperature non-finite
IF _bNonFin THEN
    eErrCode := E_DL_HumConvErr.eNonFinite;        // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 2：干球温度域闸（Magnus 标定域，禁止外推） —— *)
IF (fTempC < DL_HUC_TMIN) OR (fTempC > DL_HUC_TMAX) THEN
    eErrCode := E_DL_HumConvErr.eTempOutOfRange;   // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 3：单位枚举域闸（两侧成员逐一比较） —— *)
IF (eSrc <> E_DL_HumUnit.eRhPercent) AND (eSrc <> E_DL_HumUnit.eAbsGm3) THEN
    RETURN;                                        // 源单位越域：保持预置故障码 / Source unit out of domain
END_IF
IF (eDst <> E_DL_HumUnit.eRhPercent) AND (eDst <> E_DL_HumUnit.eAbsGm3) THEN
    RETURN;                                        // 目标单位越域：保持预置故障码 / Destination unit out of domain
END_IF

(* —— 段 4：饱和水汽压计算（分母 243.12+T 在适用域内 >= 203.12，仍显式判零） —— *)
_fDen := DL_HUC_B + fTempC;                        // Magnus 分母 / Magnus denominator
IF _fDen < DL_HUC_TINY THEN
    eErrCode := E_DL_HumConvErr.eTempOutOfRange;   // 分母异常：判温度越域 / Abnormal denominator: treat as out of range
    RETURN;
END_IF
fSatPress := DL_HUC_C * EXP(DL_HUC_A * fTempC / _fDen);   // 饱和水汽压 [hPa] / Saturation vapour pressure

(* —— 段 5：源值域闸（RH 侧 0..100，AH 侧非负） —— *)
IF eSrc = E_DL_HumUnit.eRhPercent THEN
    IF (fValue < DL_HUC_ZERO) OR (fValue > DL_HUC_RHMAX) THEN
        eErrCode := E_DL_HumConvErr.eRhOutOfRange; // 故障级：RH 越域 / Fault: RH out of range
        RETURN;
    END_IF
ELSE
    IF fValue < DL_HUC_ZERO THEN
        eErrCode := E_DL_HumConvErr.eNegativeValue; // 故障级：AH 为负 / Fault: negative absolute humidity
        RETURN;
    END_IF
END_IF

(* —— 段 6：换算主分支 —— *)
IF eSrc = eDst THEN
    fConverted := fValue;                          // 同单位直通，无舍入 / Same unit pass-through without rounding
    eErrCode   := E_DL_HumConvErr.eOk;             // 信息级成功 / Info success
ELSIF (eSrc = E_DL_HumUnit.eRhPercent) AND (eDst = E_DL_HumUnit.eAbsGm3) THEN
    _fRat := fValue / DL_HUC_HUND;                 // RH 化分数 / RH to fraction
    _fDen := fTempC + DL_HUC_KABS;                 // 绝对温标 / Absolute temperature
    IF _fDen < DL_HUC_TINY THEN
        eErrCode := E_DL_HumConvErr.eTempOutOfRange;  // 分母异常防护 / Denominator guard
        RETURN;
    END_IF
    fConverted := _fRat * DL_HUC_K * fSatPress / _fDen;   // AH = (RH/100)*216.7*Psat/(T+273.15)
    eErrCode   := E_DL_HumConvErr.eOk;             // 信息级成功 / Info success
ELSE
    (* AH → RH：分母 = 216.7 × Psat，Psat 恒正，仍显式判零作双保险 *)
    _fDen := DL_HUC_K * fSatPress;                 // 分母：水汽因子 × 饱和压 / Denominator: factor times saturation pressure
    IF _fDen < DL_HUC_TINY THEN
        eErrCode := E_DL_HumConvErr.eTempOutOfRange;  // 分母近似零防护 / Near-zero denominator guard
        RETURN;
    END_IF
    _fRat      := fValue * (fTempC + DL_HUC_KABS) / _fDen;   // AH × (T+273.15) / (216.7×Psat)
    fConverted := _fRat * DL_HUC_HUND;             // 化百分数 / Scale to percent
    IF fConverted > DL_HUC_RHMAX THEN
        fConverted := DL_HUC_RHMAX;                // 过饱和钳位 100 / Clamp supersaturation to 100
        eErrCode   := E_DL_HumConvErr.eClampRh;    // 信息级钳位码 / Info clamp code
    ELSE
        eErrCode   := E_DL_HumConvErr.eOk;         // 信息级成功 / Info success
    END_IF
END_IF

(* —— 段 7：结果非有限复检兜底（含饱和压复检） —— *)
IF (fConverted <> fConverted) OR ((fConverted - fConverted) <> DL_HUC_ZERO) THEN
    fConverted := DL_HUC_ZERO;                     // 复检异常回哨兵 / Recheck failed: sentinel
    eErrCode   := E_DL_HumConvErr.eNonFinite;      // 故障级码 / Fault-level code
    RETURN;
END_IF
IF (fSatPress <> fSatPress) OR ((fSatPress - fSatPress) <> DL_HUC_ZERO) OR (fSatPress < DL_HUC_ZERO) THEN
    fConverted := DL_HUC_ZERO;                     // 饱和压异常：结果不可信 / Abnormal saturation pressure
    fSatPress  := DL_HUC_ZERO;
    eErrCode   := E_DL_HumConvErr.eNonFinite;      // 故障级码 / Fault-level code
    RETURN;
END_IF

FC_DL_HumidityUnitConvert := TRUE;                 // 换算有效 / Conversion valid

END_FUNCTION
