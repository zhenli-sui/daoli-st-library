(*==============================================================================
 * 组件名称 (Component)  : FC_DL_AreaUnitConvert
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 算术运算符，零厂商私有库
 * 功能描述 (Function)   : 面积单位换算（系数表驱动）：以平方米（m²）为中介单位，
 *                         fHub = fValue × kSrc，fResult = fHub ÷ kDst；系数为编译期
 *                         非零常量，纯常量除法，结构性无除零。
 *                         **量纲警告**：面积系数是长度系数的平方（mm² = 1E-6 m²、
 *                         ft² = 0.09290304 m²），不可与长度系数混用；本件显式使用
 *                         平方后的常量，禁止由长度族推导。
 *                         面积非负：负值判故障级 eNegativeValue 并回哨兵 0。
 * 接口     (Interface)  : 输入 fValue 被换算面积 [源单位]、eSrc 源单位、eDst 目标单位；
 *                         输出 fConverted 换算结果 [目标单位]、eErrCode（E_DL_AreaConvErr）；
 *                         返回值 = bValid 数值可信标志（TRUE = fConverted 可信）。
 * 边界     (Boundary)   : ① 属主边界：只做单位换算，不做体积 = 面积 × 行程 的推导。
 *                         ② 单位枚举越域 → 故障级 eInvalidUnit，结果哨兵 0。
 *                         ③ 非有限双判，命中即故障级 eNonFinite。
 *                         ④ 负面积 → 故障级 eNegativeValue（拒绝，不钳位）。
 *                         ⑤ 零值合法（info 级 eZeroValue）。结果与中介值各复检一次。
 *                         ⑥ 极小量纲提示：mm² 值域可极大（1 m² = 1E6 mm²），LREAL 尾数
 *                         53 位，最大可表 1.8E308，无溢出风险；但仍做非有限复检。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_LengthUnitConvert` 分工：长度归那件，本件自带平方系数，
 *                         严禁调用长度件再平方（会引入两次舍入误差并破坏枚举域闸）。
 * 来源标签 (Source Tag) : 开源溯源：lgf-math 换算系数（公开物理常数，clean-room 重写）；许可证 MIT（仅参考语义，代码原创）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + LREAL +
 *                         本文件内定义 enum E_DL_AreaConvErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 非有限双判 + 枚举域闸 + 常量除法无除零 + 负值拒绝 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B2 · 序号 14）
 * 验收向量 (Acceptance) : ① fValue=1.0, eSrc=eM2, eDst=eMm2 → 1×1.0 = 1 m2,
 *                         ÷1E-6 = 1000000.0 mm2（容差 1E-3）；
 *                         ② fValue=1.0, eSrc=eFt2, eDst=eM2 → 1×0.09290304 = 0.09290304 m2；
 *                         ③ fValue=1000000.0, eSrc=eMm2, eDst=eM2 → 1000000×1E-6 = 1.0 m2；
 *                         ④ fValue=-1.0, eSrc=eM2, eDst=eFt2 → 返回 FALSE, 0, eNegativeValue。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_AreaUnit（面积单位表，归属 DL_MathData，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_AreaUnit :
(
    eMm2 := 0,   // 平方毫米（1E-6 m2） / Square millimetre
    eM2  := 1,   // 平方米（中介单位） / Square metre, hub unit
    eFt2 := 2    // 平方英尺（0.09290304 m2，= 0.3048^2） / Square foot
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_AreaConvErr（面积换算错误码）
 *----------------------------------------------------------------------------*)
TYPE E_DL_AreaConvErr :
(
    eOk            := 0,   // 信息级：换算完成 / Info: conversion completed
    eZeroValue     := 1,   // 信息级：输入为零（合法） / Info: zero input, legal
    eInvalidUnit   := 2,   // 故障级：单位枚举越域 / Fault: unit enum out of domain
    eNonFinite     := 3,   // 故障级：输入非有限 / Fault: non-finite input
    eNegativeValue := 4    // 故障级：负面积 / Fault: negative area
);
END_TYPE

FUNCTION FC_DL_AreaUnitConvert : BOOL
VAR_INPUT
    fValue : LREAL;          // 被换算面积值 [源单位] / Area value in source unit
    eSrc   : E_DL_AreaUnit;  // 源单位枚举 [-] / Source unit enum
    eDst   : E_DL_AreaUnit;  // 目标单位枚举 [-] / Destination unit enum
END_VAR
VAR_OUTPUT
    fConverted : LREAL;            // 换算结果 [目标单位] / Converted result
    eErrCode   : E_DL_AreaConvErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _bNonFin : BOOL;   // 输入非有限当拍标志 [-] / Non-finite input flag
    _fHub    : LREAL;  // 中介面积值 [m2] / Hub area value in square metres
END_VAR
VAR CONSTANT
    DL_AUC_MM2  : LREAL := 1.0E-6;      // mm2 → m2 换算系数（0.001^2） [m2/mm2] / square millimetre to square metre factor
    DL_AUC_M2   : LREAL := 1.0;         // m2 → m2 恒等系数 [m2/m2] / square metre identity factor
    DL_AUC_FT2  : LREAL := 0.09290304;  // ft2 → m2 换算系数（0.3048^2） [m2/ft2] / square foot to square metre factor
    DL_AUC_ZERO : LREAL := 0.0;         // 零值与非有限判零基准 [-] / Zero and non-finite base
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_AreaUnitConvert := FALSE;                    // 返回值预置无效 / Return preset invalid
fConverted := DL_AUC_ZERO;                         // 结果哨兵 0 / Result sentinel
eErrCode   := E_DL_AreaConvErr.eInvalidUnit;       // 预置最严码 / Preset strictest code

(* —— 段 1：非有限域闸（R79 双判） —— *)
_bNonFin := (fValue <> fValue) OR ((fValue - fValue) <> DL_AUC_ZERO);   // 非有限判定 / Non-finite test
IF _bNonFin THEN
    eErrCode := E_DL_AreaConvErr.eNonFinite;       // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 2：负面积域闸 —— *)
IF fValue < DL_AUC_ZERO THEN
    eErrCode := E_DL_AreaConvErr.eNegativeValue;   // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 3：源单位 → 中介平方米 —— *)
IF eSrc = E_DL_AreaUnit.eMm2 THEN
    _fHub := fValue * DL_AUC_MM2;                  // mm2 × 1E-6 / square millimetre scaled
ELSIF eSrc = E_DL_AreaUnit.eM2 THEN
    _fHub := fValue * DL_AUC_M2;                   // m2 直通 / square metre pass-through
ELSIF eSrc = E_DL_AreaUnit.eFt2 THEN
    _fHub := fValue * DL_AUC_FT2;                  // ft2 × 0.09290304 / square foot scaled
ELSE
    RETURN;                                        // 源单位越域 / Source unit out of domain
END_IF

(* —— 段 4：中介平方米 → 目标单位（常量除法，分母非零） —— *)
IF eDst = E_DL_AreaUnit.eMm2 THEN
    fConverted := _fHub / DL_AUC_MM2;              // ÷1E-6（放大 1e6，注意量纲） / Divide by square millimetre factor
ELSIF eDst = E_DL_AreaUnit.eM2 THEN
    fConverted := _fHub / DL_AUC_M2;               // ÷1 / Divide by identity
ELSIF eDst = E_DL_AreaUnit.eFt2 THEN
    fConverted := _fHub / DL_AUC_FT2;              // ÷0.09290304 / Divide by square foot factor
ELSE
    eErrCode   := E_DL_AreaConvErr.eInvalidUnit;   // 目标单位越域 / Destination out of domain
    fConverted := DL_AUC_ZERO;
    RETURN;
END_IF

(* —— 段 5：结果非有限复检兜底（量级放大 1e6 后必须复检） —— *)
IF (fConverted <> fConverted) OR ((fConverted - fConverted) <> DL_AUC_ZERO) THEN
    fConverted := DL_AUC_ZERO;                     // 复检异常回哨兵 / Recheck failed: sentinel
    eErrCode   := E_DL_AreaConvErr.eNonFinite;     // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 6：成功出口 —— *)
IF fValue = DL_AUC_ZERO THEN
    eErrCode := E_DL_AreaConvErr.eZeroValue;       // 信息级：零值 / Info: zero value
ELSE
    eErrCode := E_DL_AreaConvErr.eOk;              // 信息级成功 / Info success
END_IF
FC_DL_AreaUnitConvert := TRUE;                     // 换算有效 / Conversion valid

END_FUNCTION
