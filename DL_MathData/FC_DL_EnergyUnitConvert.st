(*==============================================================================
 * 组件名称 (Component)  : FC_DL_EnergyUnitConvert
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 算术运算符，零厂商私有库
 * 功能描述 (Function)   : 能量单位换算（系数表驱动）：以千焦（kJ）为中介单位，
 *                         fHub = fValue × kSrc，fResult = fHub ÷ kDst；系数为编译期
 *                         非零常量，纯常量除法，结构性无除零。
 *                         **符号语义**：能量允许负值（电能回馈 / 热流反向 / 净能耗为负），
 *                         故本件**不做负值拒绝**，仅在结果非有限时兜底。此点与
 *                         长度/质量/体积等几何量件不同，属显式量纲差异，已在此声明。
 *                         口径：cal 取热化学卡（4.1868 J）；BTU 取 IT 表（1055.05585262 J）。
 * 接口     (Interface)  : 输入 fValue 被换算能量 [源单位]、eSrc 源单位、eDst 目标单位；
 *                         输出 fConverted 换算结果 [目标单位]、eErrCode（E_DL_EnergyConvErr）；
 *                         返回值 = bValid 数值可信标志（TRUE = fConverted 可信）。
 * 边界     (Boundary)   : ① 属主边界：只做单位换算，不做累计电量计费、不做峰谷分段统计。
 *                         ② 单位枚举越域 → 故障级 eInvalidUnit，结果哨兵 0。
 *                         ③ 非有限双判，命中即故障级 eNonFinite。
 *                         ④ 负值合法（回馈 / 反向），不置任何码。
 *                         ⑤ 零值 → 信息级 eZeroValue。
 *                         ⑥ kJ ↔ kWh 跨越 3600 倍，结果复检防非有限。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_PowerUnitConvert` 分工：功率是能量对时间的导数，
 *                         能量累计与功率积分（含时基）归调用方的累计 FB，本件不内联时间。
 * 来源标签 (Source Tag) : 开源溯源：lgf-math 换算系数（公开物理常数，clean-room 重写）；许可证 MIT（仅参考语义，代码原创）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + LREAL +
 *                         本文件内定义 enum E_DL_EnergyConvErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 非有限双判 + 枚举域闸 + 常量除法无除零（负值按量纲放行） ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B2 · 序号 17）
 * 验收向量 (Acceptance) : ① fValue=1.0, eSrc=eKwh, eDst=eKj → 1×3600 = 3600.0 kJ, eOk, TRUE；
 *                         ② fValue=4186.8, eSrc=eKj, eDst=eCal → 4186.8×1.0 = 4186.8 kJ,
 *                         ÷0.0041868 = 1000000.0 cal（容差 1E-3）；
 *                         ③ fValue=1.0, eSrc=eBtu, eDst=eKj → 1.05505585262 kJ（容差 1E-12）；
 *                         ④ fValue=-2.5, eSrc=eKwh, eDst=eKj → -9000.0 kJ（负值合法）, eOk, TRUE；
 *                         ⑤ fValue=0.0, eSrc=eKj, eDst=eKwh → 0.0, 返回 TRUE, eZeroValue。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_EnergyUnit（能量单位表，归属 DL_MathData，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_EnergyUnit :
(
    eKj   := 0,   // 千焦（中介单位） / Kilojoule, hub unit
    eKwh  := 1,   // 千瓦时（= 3600 kJ） / Kilowatt hour
    eCal  := 2,   // 卡（热化学卡，= 0.0041868 kJ） / Thermochemical calorie
    eBtu  := 3    // 英热单位（IT 表，= 1.05505585262 kJ） / British thermal unit, IT table
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_EnergyConvErr（能量换算错误码）
 * 分级: 本件无「负值」故障码——能量负值属合法物理语义（回馈/反向）。
 *----------------------------------------------------------------------------*)
TYPE E_DL_EnergyConvErr :
(
    eOk        := 0,   // 信息级：换算完成 / Info: conversion completed
    eZeroValue := 1,   // 信息级：输入为零（合法） / Info: zero input, legal
    eInvalidUnit := 2, // 故障级：单位枚举越域 / Fault: unit enum out of domain
    eNonFinite := 3    // 故障级：输入非有限 / Fault: non-finite input
);
END_TYPE

FUNCTION FC_DL_EnergyUnitConvert : BOOL
VAR_INPUT
    fValue : LREAL;            // 被换算能量值（可负） [源单位] / Energy value, negative allowed, in source unit
    eSrc   : E_DL_EnergyUnit;  // 源单位枚举 [-] / Source unit enum
    eDst   : E_DL_EnergyUnit;  // 目标单位枚举 [-] / Destination unit enum
END_VAR
VAR_OUTPUT
    fConverted : LREAL;              // 换算结果（可负） [目标单位] / Converted result, may be negative
    eErrCode   : E_DL_EnergyConvErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _bNonFin : BOOL;   // 输入非有限当拍标志 [-] / Non-finite input flag
    _fHub    : LREAL;  // 中介能量值 [kJ] / Hub energy value in kilojoules
END_VAR
VAR CONSTANT
    DL_EUC_KJ   : LREAL := 1.0;             // kJ → kJ 恒等系数 [-] / Hub identity factor
    DL_EUC_KWH  : LREAL := 3600.0;          // kWh → kJ 换算系数 [kJ/kWh] / Kilowatt hour to kilojoule factor
    DL_EUC_CAL  : LREAL := 0.0041868;       // cal → kJ 换算系数 [kJ/cal] / Calorie to kilojoule factor
    DL_EUC_BTU  : LREAL := 1.05505585262;   // BTU(IT) → kJ 换算系数 [kJ/BTU] / BTU to kilojoule factor
    DL_EUC_ZERO : LREAL := 0.0;             // 零值与非有限判零基准 [-] / Zero and non-finite base
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_EnergyUnitConvert := FALSE;                  // 返回值预置无效 / Return preset invalid
fConverted := DL_EUC_ZERO;                         // 结果哨兵 0 / Result sentinel
eErrCode   := E_DL_EnergyConvErr.eInvalidUnit;     // 预置最严码 / Preset strictest code

(* —— 段 1：非有限域闸（R79 双判） —— *)
_bNonFin := (fValue <> fValue) OR ((fValue - fValue) <> DL_EUC_ZERO);   // 非有限判定 / Non-finite test
IF _bNonFin THEN
    eErrCode := E_DL_EnergyConvErr.eNonFinite;     // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 2：极性说明（能量负值合法，本段仅注释占位，不做拦截） —— *)
(* Negative energy is physically legal, so no polarity gate is applied here. *)

(* —— 段 3：源单位 → 中介 kJ —— *)
IF eSrc = E_DL_EnergyUnit.eKj THEN
    _fHub := fValue * DL_EUC_KJ;                   // 直通 / Hub pass-through
ELSIF eSrc = E_DL_EnergyUnit.eKwh THEN
    _fHub := fValue * DL_EUC_KWH;                  // kWh × 3600 / Kilowatt hour scaled
ELSIF eSrc = E_DL_EnergyUnit.eCal THEN
    _fHub := fValue * DL_EUC_CAL;                  // cal × 0.0041868 / Calorie scaled
ELSIF eSrc = E_DL_EnergyUnit.eBtu THEN
    _fHub := fValue * DL_EUC_BTU;                  // BTU × 1.05505585262 / BTU scaled
ELSE
    RETURN;                                        // 源单位越域 / Source unit out of domain
END_IF

(* —— 段 4：中介 kJ → 目标单位（常量除法，分母非零） —— *)
IF eDst = E_DL_EnergyUnit.eKj THEN
    fConverted := _fHub / DL_EUC_KJ;               // ÷1 / Divide by identity
ELSIF eDst = E_DL_EnergyUnit.eKwh THEN
    fConverted := _fHub / DL_EUC_KWH;              // ÷3600 / Divide by kilowatt hour factor
ELSIF eDst = E_DL_EnergyUnit.eCal THEN
    fConverted := _fHub / DL_EUC_CAL;              // ÷0.0041868 / Divide by calorie factor
ELSIF eDst = E_DL_EnergyUnit.eBtu THEN
    fConverted := _fHub / DL_EUC_BTU;              // ÷1.05505585262 / Divide by BTU factor
ELSE
    eErrCode   := E_DL_EnergyConvErr.eInvalidUnit; // 目标单位越域 / Destination out of domain
    fConverted := DL_EUC_ZERO;
    RETURN;
END_IF

(* —— 段 5：结果非有限复检兜底 —— *)
IF (fConverted <> fConverted) OR ((fConverted - fConverted) <> DL_EUC_ZERO) THEN
    fConverted := DL_EUC_ZERO;                     // 复检异常回哨兵 / Recheck failed: sentinel
    eErrCode   := E_DL_EnergyConvErr.eNonFinite;   // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 6：成功出口 —— *)
IF fValue = DL_EUC_ZERO THEN
    eErrCode := E_DL_EnergyConvErr.eZeroValue;     // 信息级：零值 / Info: zero value
ELSE
    eErrCode := E_DL_EnergyConvErr.eOk;            // 信息级成功 / Info success
END_IF
FC_DL_EnergyUnitConvert := TRUE;                   // 换算有效 / Conversion valid

END_FUNCTION
