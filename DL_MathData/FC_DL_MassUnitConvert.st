(*==============================================================================
 * 组件名称 (Component)  : FC_DL_MassUnitConvert
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 算术运算符，零厂商私有库
 * 功能描述 (Function)   : 质量工程量单位换算（系数表驱动）：以千克（kg）为中介单位，
 *                         fHub = fValue × kSrc，fResult = fHub ÷ kDst；系数为编译期
 *                         非零常量，纯常量除法，结构性无除零。
 *                         质量非负：负值判故障级 eNegativeValue 并回哨兵 0（称重去皮负数
 *                         属上游补偿问题，必须显式拒绝，禁止在此静默取绝对值）。
 * 接口     (Interface)  : 输入 fValue 被换算质量 [源单位]、eSrc 源单位、eDst 目标单位；
 *                         输出 fConverted 换算结果 [目标单位]、eErrCode（E_DL_MassConvErr）；
 *                         返回值 = bValid 数值可信标志（TRUE = fConverted 可信）。
 * 边界     (Boundary)   : ① 属主边界：只做单位换算，不做去皮 / 标定 / 累计称重。
 *                         ② 单位枚举越域 → 故障级 eInvalidUnit，结果哨兵 0。
 *                         ③ 非有限双判（NaN 自反 / Inf 差自减），命中即故障级 eNonFinite。
 *                         ④ 负质量 → 故障级 eNegativeValue（拒绝换算，不钳位）。
 *                         ⑤ 零值合法（info 级 eZeroValue）。结果与中介值各复检一次。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_LengthUnitConvert` 同族不同量；与称重 FB 分工：
 *                         重量采集与稳定判据归称重 FB，本件只做单位间换算。
 * 来源标签 (Source Tag) : 开源溯源：lgf-math 换算系数（公开物理常数，clean-room 重写）；许可证 MIT（仅参考语义，代码原创）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + LREAL +
 *                         本文件内定义 enum E_DL_MassConvErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 非有限双判 + 枚举域闸 + 常量除法无除零 + 负值拒绝 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B2 · 序号 12）
 * 验收向量 (Acceptance) : ① fValue=1000, eSrc=eG, eDst=eKg → 1000×0.001 = 1.0 kg, eOk, TRUE；
 *                         ② fValue=1.0, eSrc=eLb, eDst=eG → 1×0.45359237 = 0.45359237 kg,
 *                         ÷0.001 = 453.59237 g（容差 1E-9）；
 *                         ③ fValue=16.0, eSrc=eOz, eDst=eLb → 16×0.028349523125 =
 *                         0.45359237 kg, ÷0.45359237 = 1.0 lb（容差 1E-9）；
 *                         ④ fValue=-1.0, eSrc=eKg, eDst=eG → 返回 FALSE, 0, eNegativeValue。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_MassUnit（质量单位表，归属 DL_MathData，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_MassUnit :
(
    eG  := 0,   // 克（中介单位 kg 的千分之一） / Gram, one thousandth of hub kilogram
    eKg := 1,   // 千克（中介单位） / Kilogram, hub unit
    eLb := 2,   // 磅（常衡，0.45359237 kg） / Pound avoirdupois
    eOz := 3    // 盎司（常衡，1/16 磅） / Ounce avoirdupois, one sixteenth of pound
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_MassConvErr（质量换算错误码）
 *----------------------------------------------------------------------------*)
TYPE E_DL_MassConvErr :
(
    eOk            := 0,   // 信息级：换算完成 / Info: conversion completed
    eZeroValue     := 1,   // 信息级：输入为零（合法） / Info: zero input, legal
    eInvalidUnit   := 2,   // 故障级：单位枚举越域 / Fault: unit enum out of domain
    eNonFinite     := 3,   // 故障级：输入非有限 / Fault: non-finite input
    eNegativeValue := 4    // 故障级：负质量 / Fault: negative mass
);
END_TYPE

FUNCTION FC_DL_MassUnitConvert : BOOL
VAR_INPUT
    fValue : LREAL;          // 被换算质量值 [源单位] / Mass value in source unit
    eSrc   : E_DL_MassUnit;  // 源单位枚举 [-] / Source unit enum
    eDst   : E_DL_MassUnit;  // 目标单位枚举 [-] / Destination unit enum
END_VAR
VAR_OUTPUT
    fConverted : LREAL;            // 换算结果 [目标单位] / Converted result
    eErrCode   : E_DL_MassConvErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _bNonFin : BOOL;   // 输入非有限当拍标志 [-] / Non-finite input flag
    _fHub    : LREAL;  // 中介质量值 [kg] / Hub mass value in kilograms
END_VAR
VAR CONSTANT
    DL_MUC_G    : LREAL := 0.001;           // g → kg 换算系数 [kg/g] / gram to kilogram factor
    DL_MUC_KG   : LREAL := 1.0;             // kg → kg 恒等系数 [kg/kg] / kilogram identity factor
    DL_MUC_LB   : LREAL := 0.45359237;      // lb → kg 换算系数（常衡精确定义） [kg/lb] / pound to kilogram factor
    DL_MUC_OZ   : LREAL := 0.028349523125;  // oz → kg 换算系数（lb/16） [kg/oz] / ounce to kilogram factor
    DL_MUC_ZERO : LREAL := 0.0;             // 零值与非有限判零基准 [-] / Zero and non-finite base
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_MassUnitConvert := FALSE;                    // 返回值预置无效 / Return preset invalid
fConverted := DL_MUC_ZERO;                         // 结果哨兵 0 / Result sentinel
eErrCode   := E_DL_MassConvErr.eInvalidUnit;       // 预置最严码 / Preset strictest code

(* —— 段 1：非有限域闸（R79 双判） —— *)
_bNonFin := (fValue <> fValue) OR ((fValue - fValue) <> DL_MUC_ZERO);   // 非有限判定 / Non-finite test
IF _bNonFin THEN
    eErrCode := E_DL_MassConvErr.eNonFinite;       // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 2：负质量域闸（拒绝换算，不静默取绝对值） —— *)
IF fValue < DL_MUC_ZERO THEN
    eErrCode := E_DL_MassConvErr.eNegativeValue;   // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 3：源单位 → 中介千克 —— *)
IF eSrc = E_DL_MassUnit.eG THEN
    _fHub := fValue * DL_MUC_G;                    // g × 0.001 / gram scaled
ELSIF eSrc = E_DL_MassUnit.eKg THEN
    _fHub := fValue * DL_MUC_KG;                   // kg 直通 / kilogram pass-through
ELSIF eSrc = E_DL_MassUnit.eLb THEN
    _fHub := fValue * DL_MUC_LB;                   // lb × 0.45359237 / pound scaled
ELSIF eSrc = E_DL_MassUnit.eOz THEN
    _fHub := fValue * DL_MUC_OZ;                   // oz × 0.028349523125 / ounce scaled
ELSE
    RETURN;                                        // 源单位越域 / Source unit out of domain
END_IF

(* —— 段 4：中介千克 → 目标单位（常量除法，分母非零） —— *)
IF eDst = E_DL_MassUnit.eG THEN
    fConverted := _fHub / DL_MUC_G;                // ÷0.001 / Divide by gram factor
ELSIF eDst = E_DL_MassUnit.eKg THEN
    fConverted := _fHub / DL_MUC_KG;               // ÷1 / Divide by identity
ELSIF eDst = E_DL_MassUnit.eLb THEN
    fConverted := _fHub / DL_MUC_LB;               // ÷0.45359237 / Divide by pound factor
ELSIF eDst = E_DL_MassUnit.eOz THEN
    fConverted := _fHub / DL_MUC_OZ;               // ÷0.028349523125 / Divide by ounce factor
ELSE
    eErrCode   := E_DL_MassConvErr.eInvalidUnit;   // 目标单位越域 / Destination out of domain
    fConverted := DL_MUC_ZERO;
    RETURN;
END_IF

(* —— 段 5：结果非有限复检兜底 —— *)
IF (fConverted <> fConverted) OR ((fConverted - fConverted) <> DL_MUC_ZERO) THEN
    fConverted := DL_MUC_ZERO;                     // 复检异常回哨兵 / Recheck failed: sentinel
    eErrCode   := E_DL_MassConvErr.eNonFinite;     // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 6：成功出口 —— *)
IF fValue = DL_MUC_ZERO THEN
    eErrCode := E_DL_MassConvErr.eZeroValue;       // 信息级：零值 / Info: zero value
ELSE
    eErrCode := E_DL_MassConvErr.eOk;              // 信息级成功 / Info success
END_IF
FC_DL_MassUnitConvert := TRUE;                     // 换算有效 / Conversion valid

END_FUNCTION
