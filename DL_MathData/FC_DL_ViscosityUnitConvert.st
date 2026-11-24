(*==============================================================================
 * 组件名称 (Component)  : FC_DL_ViscosityUnitConvert
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 算术运算符，零厂商私有库
 * 功能描述 (Function)   : 运动粘度单位换算（系数表驱动）：以 mm²/s 为中介单位，
 *                         fHub = fValue × kSrc，fResult = fHub ÷ kDst；系数为编译期
 *                         非零常量，纯常量除法，结构性无除零。
 *                         **单位恒等说明**：1 cSt ≡ 1 mm²/s（厘斯定义即 mm²/s），
 *                         两成员为同一物理量不同书写，故系数均为 1.0；本件保留两个枚举
 *                         成员以适配不同 HMI 标签与协议字段，避免上游做字符串映射。
 *                         **温度不补偿（适用域声明）**：运动粘度强烈依赖温度，
 *                         本件为纯量纲换算，不引入任何温度修正；调用方必须保证
 *                         参与比较的数据同温基准（推荐 40 ℃ 基准，ISO 3448 VG 体系）。
 *                         粘度非负：负值判故障级 eNegativeValue 并回哨兵 0。
 * 接口     (Interface)  : 输入 fValue 被换算粘度 [源单位]、eSrc 源单位、eDst 目标单位；
 *                         输出 fConverted 换算结果 [目标单位]、eErrCode（E_DL_ViscConvErr）；
 *                         返回值 = bValid 数值可信标志（TRUE = fConverted 可信）。
 * 边界     (Boundary)   : ① 属主边界：只做单位换算，不做温度补偿、不做粘度-温度曲线拟合。
 *                         ② 单位枚举越域 → 故障级 eInvalidUnit，结果哨兵 0。
 *                         ③ 非有限双判，命中即故障级 eNonFinite。
 *                         ④ 负粘度 → 故障级 eNegativeValue（拒绝，不钳位）。
 *                         ⑤ 零粘度 → 信息级 eZeroValue（物理上仅真空/静止，多为未充油）。
 *                         ⑥ m²/s → mm²/s 放大 1E6，结果复检防溢出为非有限。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_DensityUnitConvert` 分工：密度换算归那件；
 *                         粘度等级（VG32 等）选型属配方管理，不在本件范围。
 * 来源标签 (Source Tag) : 开源溯源：lgf-math 换算系数（公开物理常数，clean-room 重写）；许可证 MIT（仅参考语义，代码原创）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + LREAL +
 *                         本文件内定义 enum E_DL_ViscConvErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 非有限双判 + 枚举域闸 + 常量除法无除零 + 负值拒绝 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B2 · 序号 16）
 * 验收向量 (Acceptance) : ① fValue=32.0, eSrc=eCst, eDst=eMm2s → 32×1.0 = 32 mm2/s,
 *                         ÷1.0 = 32.0, eOk, TRUE（恒等）；
 *                         ② fValue=1.0, eSrc=eM2s, eDst=eMm2s → 1×1E6 = 1000000.0 mm2/s；
 *                         ③ fValue=1000000.0, eSrc=eMm2s, eDst=eM2s → 1.0 m2/s（容差 1E-12）；
 *                         ④ fValue=-1.0, eSrc=eCst, eDst=eMm2s → 返回 FALSE, 0, eNegativeValue；
 *                         ⑤ fValue=0.0, eSrc=eCst, eDst=eMm2s → 0.0, 返回 TRUE, eZeroValue。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ViscUnit（运动粘度单位表，归属 DL_MathData，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_ViscUnit :
(
    eCst  := 0,   // 厘斯（centi-Stokes，定义上恒等于 mm2/s） / Centistokes, identically equal to mm2/s
    eMm2s := 1,   // 平方毫米每秒（中介单位） / Square millimetre per second, hub unit
    eM2s  := 2    // 平方米每秒（= 1E6 mm2/s） / Square metre per second
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ViscConvErr（运动粘度换算错误码）
 *----------------------------------------------------------------------------*)
TYPE E_DL_ViscConvErr :
(
    eOk            := 0,   // 信息级：换算完成 / Info: conversion completed
    eZeroValue     := 1,   // 信息级：零粘度（多为未充油） / Info: zero viscosity, often unfilled
    eInvalidUnit   := 2,   // 故障级：单位枚举越域 / Fault: unit enum out of domain
    eNonFinite     := 3,   // 故障级：输入非有限 / Fault: non-finite input
    eNegativeValue := 4    // 故障级：负粘度 / Fault: negative viscosity
);
END_TYPE

FUNCTION FC_DL_ViscosityUnitConvert : BOOL
VAR_INPUT
    fValue : LREAL;          // 被换算运动粘度值 [源单位] / Kinematic viscosity value in source unit
    eSrc   : E_DL_ViscUnit;  // 源单位枚举 [-] / Source unit enum
    eDst   : E_DL_ViscUnit;  // 目标单位枚举 [-] / Destination unit enum
END_VAR
VAR_OUTPUT
    fConverted : LREAL;            // 换算结果 [目标单位] / Converted result
    eErrCode   : E_DL_ViscConvErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _bNonFin : BOOL;   // 输入非有限当拍标志 [-] / Non-finite input flag
    _fHub    : LREAL;  // 中介粘度值 [mm2/s] / Hub viscosity value in square millimetres per second
END_VAR
VAR CONSTANT
    DL_VIC_CST  : LREAL := 1.0;      // cSt → mm2/s 恒等系数 [-] / Centistokes identity factor
    DL_VIC_MM2S : LREAL := 1.0;      // mm2/s → mm2/s 恒等系数 [-] / Hub identity factor
    DL_VIC_M2S  : LREAL := 1.0E6;    // m2/s → mm2/s 换算系数 [-] / Square metre per second factor
    DL_VIC_ZERO : LREAL := 0.0;      // 零粘度与非有限判零基准 [-] / Zero viscosity and non-finite base
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_ViscosityUnitConvert := FALSE;               // 返回值预置无效 / Return preset invalid
fConverted := DL_VIC_ZERO;                         // 结果哨兵 0 / Result sentinel
eErrCode   := E_DL_ViscConvErr.eInvalidUnit;       // 预置最严码 / Preset strictest code

(* —— 段 1：非有限域闸（R79 双判） —— *)
_bNonFin := (fValue <> fValue) OR ((fValue - fValue) <> DL_VIC_ZERO);   // 非有限判定 / Non-finite test
IF _bNonFin THEN
    eErrCode := E_DL_ViscConvErr.eNonFinite;       // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 2：负粘度域闸 —— *)
IF fValue < DL_VIC_ZERO THEN
    eErrCode := E_DL_ViscConvErr.eNegativeValue;   // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 3：源单位 → 中介 mm2/s —— *)
IF eSrc = E_DL_ViscUnit.eCst THEN
    _fHub := fValue * DL_VIC_CST;                  // cSt 恒等 / Centistokes identity
ELSIF eSrc = E_DL_ViscUnit.eMm2s THEN
    _fHub := fValue * DL_VIC_MM2S;                 // 直通 / Hub pass-through
ELSIF eSrc = E_DL_ViscUnit.eM2s THEN
    _fHub := fValue * DL_VIC_M2S;                  // m2/s × 1E6 / Square metre per second scaled
ELSE
    RETURN;                                        // 源单位越域 / Source unit out of domain
END_IF

(* —— 段 4：中介 mm2/s → 目标单位（常量除法，分母非零） —— *)
IF eDst = E_DL_ViscUnit.eCst THEN
    fConverted := _fHub / DL_VIC_CST;              // ÷1 恒等 / Divide by identity
ELSIF eDst = E_DL_ViscUnit.eMm2s THEN
    fConverted := _fHub / DL_VIC_MM2S;             // ÷1 / Divide by identity
ELSIF eDst = E_DL_ViscUnit.eM2s THEN
    fConverted := _fHub / DL_VIC_M2S;              // ÷1E6 / Divide by square metre per second factor
ELSE
    eErrCode   := E_DL_ViscConvErr.eInvalidUnit;   // 目标单位越域 / Destination out of domain
    fConverted := DL_VIC_ZERO;
    RETURN;
END_IF

(* —— 段 5：结果非有限复检兜底（1E6 放大后必须复检） —— *)
IF (fConverted <> fConverted) OR ((fConverted - fConverted) <> DL_VIC_ZERO) THEN
    fConverted := DL_VIC_ZERO;                     // 复检异常回哨兵 / Recheck failed: sentinel
    eErrCode   := E_DL_ViscConvErr.eNonFinite;     // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 6：成功出口 —— *)
IF fValue = DL_VIC_ZERO THEN
    eErrCode := E_DL_ViscConvErr.eZeroValue;       // 信息级：零粘度 / Info: zero viscosity
ELSE
    eErrCode := E_DL_ViscConvErr.eOk;              // 信息级成功 / Info success
END_IF
FC_DL_ViscosityUnitConvert := TRUE;                // 换算有效 / Conversion valid

END_FUNCTION
