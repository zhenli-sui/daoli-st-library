(*==============================================================================
 * 组件名称 (Component)  : FC_DL_PowerUnitConvert
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 算术运算符，零厂商私有库
 * 功能描述 (Function)   : 功率单位换算（系数表驱动）：以千瓦（kW）为中介单位，
 *                         fHub = fValue × kSrc，fResult = fHub ÷ kDst；系数为编译期
 *                         非零常量，纯常量除法，结构性无除零。
 *                         **符号语义**：功率允许负值（电动/发电四象限、能量回馈），
 *                         故本件**不做负值拒绝**，仅在结果非有限时兜底。
 *                         口径：HP 取机械马力（mechanical horsepower = 745.6998715822702 W），
 *                         非公制马力（735.49875 W）；两者差 1.4%，已在枚举注释中显式标定。
 * 接口     (Interface)  : 输入 fValue 被换算功率 [源单位]、eSrc 源单位、eDst 目标单位；
 *                         输出 fConverted 换算结果 [目标单位]、eErrCode（E_DL_PowerConvErr）；
 *                         返回值 = bValid 数值可信标志（TRUE = fConverted 可信）。
 * 边界     (Boundary)   : ① 属主边界：只做单位换算，不做功率因数修正、不做有功/无功分解。
 *                         ② 单位枚举越域 → 故障级 eInvalidUnit，结果哨兵 0。
 *                         ③ 非有限双判，命中即故障级 eNonFinite。
 *                         ④ 负值合法（回馈 / 发电象限），不置任何码。
 *                         ⑤ 零值 → 信息级 eZeroValue。
 *                         ⑥ kW ↔ W 跨越 1000 倍，结果复检防非有限。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_EnergyUnitConvert` 分工：能量归那件；功率 × 时间 = 能量
 *                         的积分由调用方按时基完成（本件不持有时间量）。
 * 来源标签 (Source Tag) : 开源溯源：lgf-math 换算系数（公开物理常数，clean-room 重写）；许可证 MIT（仅参考语义，代码原创）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + LREAL +
 *                         本文件内定义 enum E_DL_PowerConvErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 非有限双判 + 枚举域闸 + 常量除法无除零（负值按量纲放行） ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B2 · 序号 18）
 * 验收向量 (Acceptance) : ① fValue=1.0, eSrc=eHp, eDst=eKw → 1×0.7456998715822702 = 0.7456998715822702 kW；
 *                         ② fValue=1.0, eSrc=eKw, eDst=eW → 1×1.0 = 1 kW, ÷0.001 = 1000.0 W；
 *                         ③ fValue=745.6998715822702, eSrc=eW, eDst=eHp → 0.7456998715822702 kW,
 *                         ÷0.7456998715822702 = 1.0 HP（容差 1E-12）；
 *                         ④ fValue=-11.0, eSrc=eKw, eDst=eW → -11000.0 W（负值合法）, eOk, TRUE；
 *                         ⑤ fValue=0.0, eSrc=eKw, eDst=eHp → 0.0, 返回 TRUE, eZeroValue。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_PowerUnit（功率单位表，归属 DL_MathData，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_PowerUnit :
(
    eKw := 0,   // 千瓦（中介单位） / Kilowatt, hub unit
    eHp := 1,   // 机械马力（= 0.7456998715822702 kW） / Mechanical horsepower
    eW  := 2    // 瓦（= 0.001 kW） / Watt
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_PowerConvErr（功率换算错误码）
 * 分级: 本件无「负值」故障码——功率负值属合法物理语义（回馈/发电）。
 *----------------------------------------------------------------------------*)
TYPE E_DL_PowerConvErr :
(
    eOk          := 0,   // 信息级：换算完成 / Info: conversion completed
    eZeroValue   := 1,   // 信息级：输入为零（合法） / Info: zero input, legal
    eInvalidUnit := 2,   // 故障级：单位枚举越域 / Fault: unit enum out of domain
    eNonFinite   := 3    // 故障级：输入非有限 / Fault: non-finite input
);
END_TYPE

FUNCTION FC_DL_PowerUnitConvert : BOOL
VAR_INPUT
    fValue : LREAL;           // 被换算功率值（可负） [源单位] / Power value, negative allowed, in source unit
    eSrc   : E_DL_PowerUnit;  // 源单位枚举 [-] / Source unit enum
    eDst   : E_DL_PowerUnit;  // 目标单位枚举 [-] / Destination unit enum
END_VAR
VAR_OUTPUT
    fConverted : LREAL;             // 换算结果（可负） [目标单位] / Converted result, may be negative
    eErrCode   : E_DL_PowerConvErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _bNonFin : BOOL;   // 输入非有限当拍标志 [-] / Non-finite input flag
    _fHub    : LREAL;  // 中介功率值 [kW] / Hub power value in kilowatts
END_VAR
VAR CONSTANT
    DL_PUC2_KW   : LREAL := 1.0;                  // kW → kW 恒等系数 [-] / Hub identity factor
    DL_PUC2_HP   : LREAL := 0.7456998715822702;   // HP → kW 换算系数 [kW/HP] / Mechanical horsepower factor
    DL_PUC2_W    : LREAL := 0.001;                // W → kW 换算系数 [kW/W] / Watt factor
    DL_PUC2_ZERO : LREAL := 0.0;                  // 零值与非有限判零基准 [-] / Zero and non-finite base
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_PowerUnitConvert := FALSE;                   // 返回值预置无效 / Return preset invalid
fConverted := DL_PUC2_ZERO;                        // 结果哨兵 0 / Result sentinel
eErrCode   := E_DL_PowerConvErr.eInvalidUnit;      // 预置最严码 / Preset strictest code

(* —— 段 1：非有限域闸（R79 双判） —— *)
_bNonFin := (fValue <> fValue) OR ((fValue - fValue) <> DL_PUC2_ZERO);   // 非有限判定 / Non-finite test
IF _bNonFin THEN
    eErrCode := E_DL_PowerConvErr.eNonFinite;      // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 2：极性说明（功率负值合法，本段仅注释占位，不做拦截） —— *)
(* Negative power is physically legal (regenerative quadrant), so no polarity gate is applied. *)

(* —— 段 3：源单位 → 中介 kW —— *)
IF eSrc = E_DL_PowerUnit.eKw THEN
    _fHub := fValue * DL_PUC2_KW;                  // 直通 / Hub pass-through
ELSIF eSrc = E_DL_PowerUnit.eHp THEN
    _fHub := fValue * DL_PUC2_HP;                  // HP × 0.7456998715822702 / Horsepower scaled
ELSIF eSrc = E_DL_PowerUnit.eW THEN
    _fHub := fValue * DL_PUC2_W;                   // W × 0.001 / Watt scaled
ELSE
    RETURN;                                        // 源单位越域 / Source unit out of domain
END_IF

(* —— 段 4：中介 kW → 目标单位（常量除法，分母非零） —— *)
IF eDst = E_DL_PowerUnit.eKw THEN
    fConverted := _fHub / DL_PUC2_KW;              // ÷1 / Divide by identity
ELSIF eDst = E_DL_PowerUnit.eHp THEN
    fConverted := _fHub / DL_PUC2_HP;              // ÷0.7456998715822702 / Divide by horsepower factor
ELSIF eDst = E_DL_PowerUnit.eW THEN
    fConverted := _fHub / DL_PUC2_W;               // ÷0.001 / Divide by watt factor
ELSE
    eErrCode   := E_DL_PowerConvErr.eInvalidUnit;  // 目标单位越域 / Destination out of domain
    fConverted := DL_PUC2_ZERO;
    RETURN;
END_IF

(* —— 段 5：结果非有限复检兜底 —— *)
IF (fConverted <> fConverted) OR ((fConverted - fConverted) <> DL_PUC2_ZERO) THEN
    fConverted := DL_PUC2_ZERO;                    // 复检异常回哨兵 / Recheck failed: sentinel
    eErrCode   := E_DL_PowerConvErr.eNonFinite;    // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 6：成功出口 —— *)
IF fValue = DL_PUC2_ZERO THEN
    eErrCode := E_DL_PowerConvErr.eZeroValue;      // 信息级：零值 / Info: zero value
ELSE
    eErrCode := E_DL_PowerConvErr.eOk;             // 信息级成功 / Info success
END_IF
FC_DL_PowerUnitConvert := TRUE;                    // 换算有效 / Conversion valid

END_FUNCTION
