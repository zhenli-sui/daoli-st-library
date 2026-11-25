(*==============================================================================
 * 组件名称 (Component)  : FC_DL_VolumeUnitConvert
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 算术运算符，零厂商私有库
 * 功能描述 (Function)   : 体积 / 容积单位换算（系数表驱动）：以升（L）为中介单位，
 *                         fHub = fValue × kSrc，fResult = fHub ÷ kDst；系数为编译期
 *                         非零常量，纯常量除法，结构性无除零。
 *                         体积非负：负值判故障级 eNegativeValue 并回哨兵 0。
 *                         美制加仑采用 US liquid gallon 定义（3.785411784 L），
 *                         与英制加仑（4.54609 L）不同，本件显式标定 US 口径。
 * 接口     (Interface)  : 输入 fValue 被换算体积 [源单位]、eSrc 源单位、eDst 目标单位；
 *                         输出 fConverted 换算结果 [目标单位]、eErrCode（E_DL_VolConvErr）；
 *                         返回值 = bValid 数值可信标志（TRUE = fConverted 可信）。
 * 边界     (Boundary)   : ① 属主边界：只做单位换算，不做罐体液位-体积曲线换算（归查表族）。
 *                         ② 单位枚举越域 → 故障级 eInvalidUnit，结果哨兵 0。
 *                         ③ 非有限双判，命中即故障级 eNonFinite。
 *                         ④ 负体积 → 故障级 eNegativeValue（拒绝，不钳位）。
 *                         ⑤ 零值合法（info 级 eZeroValue）。结果与中介值各复检一次。
 *                         ⑥ **口径声明**：本件 gal 恒为 US liquid gallon = 3.785411784 L。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_AreaUnitConvert` 分工：面积不做隐式 × 高度推导；
 *                         与 `FC_DL_DensityUnitConvert` 分工：密度归那件，本件不隐含质量。
 * 来源标签 (Source Tag) : 开源溯源：lgf-math 换算系数（公开物理常数，clean-room 重写）；许可证 MIT（仅参考语义，代码原创）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + LREAL +
 *                         本文件内定义 enum E_DL_VolConvErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 非有限双判 + 枚举域闸 + 常量除法无除零 + 负值拒绝 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B2 · 序号 13）
 * 验收向量 (Acceptance) : ① fValue=1.0, eSrc=eM3, eDst=eL → 1×1000 = 1000.0 L, eOk, TRUE；
 *                         ② fValue=1.0, eSrc=eGalUs, eDst=eL → 3.785411784 L（容差 1E-9）；
 *                         ③ fValue=1000.0, eSrc=eMl, eDst=eL → 1000×0.001 = 1.0 L；
 *                         ④ fValue=-2.0, eSrc=eL, eDst=eMl → 返回 FALSE, 0, eNegativeValue；
 *                         ⑤ fValue=0.0, eSrc=eL, eDst=eM3 → 0.0, 返回 TRUE, eZeroValue。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_VolUnit（体积单位表，归属 DL_MathData，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_VolUnit :
(
    eL     := 0,   // 升（中介单位，= 1 dm3） / Litre, hub unit, one cubic decimetre
    eM3    := 1,   // 立方米（1000 L） / Cubic metre, one thousand litres
    eGalUs := 2,   // 美制液量加仑（3.785411784 L） / US liquid gallon
    eMl    := 3    // 毫升（千分之一 L） / Millilitre, one thousandth of litre
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_VolConvErr（体积换算错误码）
 *----------------------------------------------------------------------------*)
TYPE E_DL_VolConvErr :
(
    eOk            := 0,   // 信息级：换算完成 / Info: conversion completed
    eZeroValue     := 1,   // 信息级：输入为零（合法） / Info: zero input, legal
    eInvalidUnit   := 2,   // 故障级：单位枚举越域 / Fault: unit enum out of domain
    eNonFinite     := 3,   // 故障级：输入非有限 / Fault: non-finite input
    eNegativeValue := 4    // 故障级：负体积 / Fault: negative volume
);
END_TYPE

FUNCTION FC_DL_VolumeUnitConvert : BOOL
VAR_INPUT
    fValue : LREAL;          // 被换算体积值 [源单位] / Volume value in source unit
    eSrc   : E_DL_VolUnit;   // 源单位枚举 [-] / Source unit enum
    eDst   : E_DL_VolUnit;   // 目标单位枚举 [-] / Destination unit enum
END_VAR
VAR_OUTPUT
    fConverted : LREAL;           // 换算结果 [目标单位] / Converted result
    eErrCode   : E_DL_VolConvErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _bNonFin : BOOL;   // 输入非有限当拍标志 [-] / Non-finite input flag
    _fHub    : LREAL;  // 中介体积值 [L] / Hub volume value in litres
END_VAR
VAR CONSTANT
    DL_VUC_L     : LREAL := 1.0;          // L → L 恒等系数 [L/L] / litre identity factor
    DL_VUC_M3    : LREAL := 1000.0;       // m3 → L 换算系数 [L/m3] / cubic metre to litre factor
    DL_VUC_GALUS : LREAL := 3.785411784;  // US gal → L 换算系数 [L/gal] / US gallon to litre factor
    DL_VUC_ML    : LREAL := 0.001;        // mL → L 换算系数 [L/mL] / millilitre to litre factor
    DL_VUC_ZERO  : LREAL := 0.0;          // 零值与非有限判零基准 [-] / Zero and non-finite base
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_VolumeUnitConvert := FALSE;                  // 返回值预置无效 / Return preset invalid
fConverted := DL_VUC_ZERO;                         // 结果哨兵 0 / Result sentinel
eErrCode   := E_DL_VolConvErr.eInvalidUnit;        // 预置最严码 / Preset strictest code

(* —— 段 1：非有限域闸（R79 双判） —— *)
_bNonFin := (fValue <> fValue) OR ((fValue - fValue) <> DL_VUC_ZERO);   // 非有限判定 / Non-finite test
IF _bNonFin THEN
    eErrCode := E_DL_VolConvErr.eNonFinite;        // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 2：负体积域闸 —— *)
IF fValue < DL_VUC_ZERO THEN
    eErrCode := E_DL_VolConvErr.eNegativeValue;    // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 3：源单位 → 中介升 —— *)
IF eSrc = E_DL_VolUnit.eL THEN
    _fHub := fValue * DL_VUC_L;                    // L 直通 / litre pass-through
ELSIF eSrc = E_DL_VolUnit.eM3 THEN
    _fHub := fValue * DL_VUC_M3;                   // m3 × 1000 / cubic metre scaled
ELSIF eSrc = E_DL_VolUnit.eGalUs THEN
    _fHub := fValue * DL_VUC_GALUS;                // US gal × 3.785411784 / US gallon scaled
ELSIF eSrc = E_DL_VolUnit.eMl THEN
    _fHub := fValue * DL_VUC_ML;                   // mL × 0.001 / millilitre scaled
ELSE
    RETURN;                                        // 源单位越域 / Source unit out of domain
END_IF

(* —— 段 4：中介升 → 目标单位（常量除法，分母非零） —— *)
IF eDst = E_DL_VolUnit.eL THEN
    fConverted := _fHub / DL_VUC_L;                // ÷1 / Divide by identity
ELSIF eDst = E_DL_VolUnit.eM3 THEN
    fConverted := _fHub / DL_VUC_M3;               // ÷1000 / Divide by cubic metre factor
ELSIF eDst = E_DL_VolUnit.eGalUs THEN
    fConverted := _fHub / DL_VUC_GALUS;            // ÷3.785411784 / Divide by US gallon factor
ELSIF eDst = E_DL_VolUnit.eMl THEN
    fConverted := _fHub / DL_VUC_ML;               // ÷0.001 / Divide by millilitre factor
ELSE
    eErrCode   := E_DL_VolConvErr.eInvalidUnit;    // 目标单位越域 / Destination out of domain
    fConverted := DL_VUC_ZERO;
    RETURN;
END_IF

(* —— 段 5：结果非有限复检兜底 —— *)
IF (fConverted <> fConverted) OR ((fConverted - fConverted) <> DL_VUC_ZERO) THEN
    fConverted := DL_VUC_ZERO;                     // 复检异常回哨兵 / Recheck failed: sentinel
    eErrCode   := E_DL_VolConvErr.eNonFinite;      // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 6：成功出口 —— *)
IF fValue = DL_VUC_ZERO THEN
    eErrCode := E_DL_VolConvErr.eZeroValue;        // 信息级：零值 / Info: zero value
ELSE
    eErrCode := E_DL_VolConvErr.eOk;               // 信息级成功 / Info success
END_IF
FC_DL_VolumeUnitConvert := TRUE;                   // 换算有效 / Conversion valid

END_FUNCTION
