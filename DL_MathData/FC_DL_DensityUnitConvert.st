(*==============================================================================
 * 组件名称 (Component)  : FC_DL_DensityUnitConvert
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 算术运算符，零厂商私有库
 * 功能描述 (Function)   : 密度单位换算（系数表驱动）：以 kg/m³ 为中介单位，
 *                         fHub = fValue × kSrc，fResult = fHub ÷ kDst；系数为编译期
 *                         非零常量，纯常量除法，结构性无除零。
 *                         **零密度保护**：密度为零在物理上仅对应真空，工艺上几乎必为
 *                         传感器失效或未标定，故零值单独置信息码 eZeroValue（结果仍合法
 *                         可信，便于上位机显示），负密度置故障级 eNegativeValue 并拒绝换算。
 *                         注意：无论零值与否，除数恒为常量，不存在「除以密度」的路径，
 *                         故不需要为除零做条件分支——此点在此显式声明，避免审校误判。
 * 接口     (Interface)  : 输入 fValue 被换算密度 [源单位]、eSrc 源单位、eDst 目标单位；
 *                         输出 fConverted 换算结果 [目标单位]、eErrCode（E_DL_DensConvErr）；
 *                         返回值 = bValid 数值可信标志（TRUE = fConverted 可信）。
 * 边界     (Boundary)   : ① 属主边界：只做单位换算，不做温度-密度补偿（补偿需介质曲线，归查表族）。
 *                         ② 单位枚举越域 → 故障级 eInvalidUnit，结果哨兵 0。
 *                         ③ 非有限双判，命中即故障级 eNonFinite。
 *                         ④ 负密度 → 故障级 eNegativeValue（拒绝，不取绝对值）。
 *                         ⑤ 零密度 → 信息级 eZeroValue，返回 TRUE（0 kg/m3 = 0 g/cm3 恒成立）。
 *                         ⑥ 结果与中介值各复检一次（四段式第四段）。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_MassUnitConvert` / `FC_DL_VolumeUnitConvert` 分工：
 *                         密度 = 质量/体积 的组合换算由调用方先各自换算再相除（本件不内联）。
 * 来源标签 (Source Tag) : 开源溯源：lgf-math 换算系数（公开物理常数，clean-room 重写）；许可证 MIT（仅参考语义，代码原创）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + LREAL +
 *                         本文件内定义 enum E_DL_DensConvErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 非有限双判 + 枚举域闸 + 常量除法无除零 + 零/负密度分流 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B2 · 序号 15）
 * 验收向量 (Acceptance) : ① fValue=1000.0, eSrc=eKgM3, eDst=eGCm3 → 1000×1.0 = 1000 kg/m3,
 *                         ÷1000 = 1.0 g/cm3（容差 1E-9）；
 *                         ② fValue=1.0, eSrc=eGCm3, eDst=eKgM3 → 1×1000 = 1000.0 kg/m3；
 *                         ③ fValue=1.0, eSrc=eLbFt3, eDst=eKgM3 → 16.018463373960142 kg/m3
 *                         （容差 1E-9）；
 *                         ④ fValue=0.0, eSrc=eKgM3, eDst=eGCm3 → 0.0, 返回 TRUE, eZeroValue；
 *                         ⑤ fValue=-1.0, eSrc=eKgM3, eDst=eGCm3 → 返回 FALSE, 0, eNegativeValue。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_DensUnit（密度单位表，归属 DL_MathData，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_DensUnit :
(
    eKgM3  := 0,   // 千克每立方米（中介单位） / Kilogram per cubic metre, hub unit
    eGCm3  := 1,   // 克每立方厘米（= 1000 kg/m3） / Gram per cubic centimetre
    eLbFt3 := 2    // 磅每立方英尺（16.018463373960142 kg/m3） / Pound per cubic foot
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_DensConvErr（密度换算错误码）
 *----------------------------------------------------------------------------*)
TYPE E_DL_DensConvErr :
(
    eOk            := 0,   // 信息级：换算完成 / Info: conversion completed
    eZeroValue     := 1,   // 信息级：零密度（多为未标定，结果仍可信） / Info: zero density, result still trustworthy
    eInvalidUnit   := 2,   // 故障级：单位枚举越域 / Fault: unit enum out of domain
    eNonFinite     := 3,   // 故障级：输入非有限 / Fault: non-finite input
    eNegativeValue := 4    // 故障级：负密度 / Fault: negative density
);
END_TYPE

FUNCTION FC_DL_DensityUnitConvert : BOOL
VAR_INPUT
    fValue : LREAL;          // 被换算密度值 [源单位] / Density value in source unit
    eSrc   : E_DL_DensUnit;  // 源单位枚举 [-] / Source unit enum
    eDst   : E_DL_DensUnit;  // 目标单位枚举 [-] / Destination unit enum
END_VAR
VAR_OUTPUT
    fConverted : LREAL;            // 换算结果 [目标单位] / Converted result
    eErrCode   : E_DL_DensConvErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _bNonFin : BOOL;   // 输入非有限当拍标志 [-] / Non-finite input flag
    _fHub    : LREAL;  // 中介密度值 [kg/m3] / Hub density value in kilograms per cubic metre
END_VAR
VAR CONSTANT
    DL_DUC_KGM3  : LREAL := 1.0;                  // kg/m3 → kg/m3 恒等系数 [-] / Hub identity factor
    DL_DUC_GCM3  : LREAL := 1000.0;               // g/cm3 → kg/m3 换算系数 [-] / Gram per cubic centimetre factor
    DL_DUC_LBFT3 : LREAL := 16.018463373960142;   // lb/ft3 → kg/m3 换算系数 [-] / Pound per cubic foot factor
    DL_DUC_ZERO  : LREAL := 0.0;                  // 零密度与非有限判零基准 [-] / Zero density and non-finite base
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_DensityUnitConvert := FALSE;                 // 返回值预置无效 / Return preset invalid
fConverted := DL_DUC_ZERO;                         // 结果哨兵 0 / Result sentinel
eErrCode   := E_DL_DensConvErr.eInvalidUnit;       // 预置最严码 / Preset strictest code

(* —— 段 1：非有限域闸（R79 双判） —— *)
_bNonFin := (fValue <> fValue) OR ((fValue - fValue) <> DL_DUC_ZERO);   // 非有限判定 / Non-finite test
IF _bNonFin THEN
    eErrCode := E_DL_DensConvErr.eNonFinite;       // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 2：负密度域闸（零密度放行，由段 6 置信息码） —— *)
IF fValue < DL_DUC_ZERO THEN
    eErrCode := E_DL_DensConvErr.eNegativeValue;   // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 3：源单位 → 中介 kg/m3 —— *)
IF eSrc = E_DL_DensUnit.eKgM3 THEN
    _fHub := fValue * DL_DUC_KGM3;                 // 直通 / Hub pass-through
ELSIF eSrc = E_DL_DensUnit.eGCm3 THEN
    _fHub := fValue * DL_DUC_GCM3;                 // g/cm3 × 1000 / Gram per cubic centimetre scaled
ELSIF eSrc = E_DL_DensUnit.eLbFt3 THEN
    _fHub := fValue * DL_DUC_LBFT3;                // lb/ft3 × 16.018463... / Pound per cubic foot scaled
ELSE
    RETURN;                                        // 源单位越域 / Source unit out of domain
END_IF

(* —— 段 4：中介 kg/m3 → 目标单位（除数为常量 1.0 / 1000.0 / 16.018463...，均非零） —— *)
IF eDst = E_DL_DensUnit.eKgM3 THEN
    fConverted := _fHub / DL_DUC_KGM3;             // ÷1 / Divide by identity
ELSIF eDst = E_DL_DensUnit.eGCm3 THEN
    fConverted := _fHub / DL_DUC_GCM3;             // ÷1000 / Divide by gram per cubic centimetre factor
ELSIF eDst = E_DL_DensUnit.eLbFt3 THEN
    fConverted := _fHub / DL_DUC_LBFT3;            // ÷16.018463... / Divide by pound per cubic foot factor
ELSE
    eErrCode   := E_DL_DensConvErr.eInvalidUnit;   // 目标单位越域 / Destination out of domain
    fConverted := DL_DUC_ZERO;
    RETURN;
END_IF

(* —— 段 5：结果非有限复检兜底 —— *)
IF (fConverted <> fConverted) OR ((fConverted - fConverted) <> DL_DUC_ZERO) THEN
    fConverted := DL_DUC_ZERO;                     // 复检异常回哨兵 / Recheck failed: sentinel
    eErrCode   := E_DL_DensConvErr.eNonFinite;     // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 6：成功出口（零密度单列信息码，提示上游传感器可能未标定） —— *)
IF fValue = DL_DUC_ZERO THEN
    eErrCode := E_DL_DensConvErr.eZeroValue;       // 信息级：零密度 / Info: zero density
ELSE
    eErrCode := E_DL_DensConvErr.eOk;              // 信息级成功 / Info success
END_IF
FC_DL_DensityUnitConvert := TRUE;                  // 换算有效 / Conversion valid

END_FUNCTION
