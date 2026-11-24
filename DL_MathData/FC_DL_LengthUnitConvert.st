(*==============================================================================
 * 组件名称 (Component)  : FC_DL_LengthUnitConvert
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 算术运算符，零厂商私有库
 * 功能描述 (Function)   : 长度工程量单位换算（系数表驱动）：以米（m）为中介单位，
 *                         fHub = fValue × kSrc，fResult = fHub ÷ kDst；
 *                         kSrc / kDst 为编译期非零常量，纯常量除法，结构性无除零。
 *                         长度物理量非负：负值判故障级 eNegativeValue 并回哨兵 0；
 *                         零值合法（0 mm = 0 m，info 级 eZeroValue）。
 * 接口     (Interface)  : 输入 fValue 被换算长度 [源单位]、eSrc 源单位、eDst 目标单位；
 *                         输出 fConverted 换算结果 [目标单位]、eErrCode 错误码（E_DL_LenConvErr）；
 *                         返回值 = bValid 数值可信标志（TRUE = fConverted 可信）。
 * 边界     (Boundary)   : ① 属主边界：只做单位换算，不做量程标定、不做累计行程管理。
 *                         ② 单位枚举越域（非四成员之一）→ 故障级 eInvalidUnit，结果哨兵 0。
 *                         ③ 全浮点入参做非有限双判（NaN 自反 / Inf 差自减），任一非有限 →
 *                         故障级 eNonFinite。中介值与结果各复检一次（四段式第四段）。
 *                         ④ 负长度 → 故障级 eNegativeValue（物理量不可为负，拒绝换算而非钳位，
 *                         避免掩盖上游符号错误）。钳位会静默改值，故不采用。
 *                         ⑤ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_PressUnitConvert` 同族不同量（压力含负压域、长度不含）；
 *                         与 `FC_DL_AreaUnitConvert` 分工：长度 ↔ 面积不做隐式平方推导。
 * 来源标签 (Source Tag) : 开源溯源：lgf-math 换算系数（公开物理常数，clean-room 重写）；许可证 MIT（仅参考语义，代码原创）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + LREAL + 本文件内定义
 *                         enum E_DL_LenConvErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 非有限双判 + 枚举域闸 + 常量除法无除零 + 负值拒绝 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B2 · 序号 11）
 * 验收向量 (Acceptance) : ① fValue=1000, eSrc=eMm, eDst=eM → 1000×0.001 = 1.0 m, eOk, TRUE；
 *                         ② fValue=1.0, eSrc=eInch, eDst=eMm → 1×0.0254 = 0.0254 m,
 *                         ÷0.001 = 25.4 mm（容差 1E-9）；
 *                         ③ fValue=1.0, eSrc=eFt, eDst=eM → 0.3048 m, eOk；
 *                         ④ fValue=-5.0, eSrc=eMm, eDst=eM → 返回 FALSE, fConverted=0, eNegativeValue；
 *                         ⑤ fValue=0.0, eSrc=eMm, eDst=eFt → 0.0, 返回 TRUE, eZeroValue。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_LengthUnit（长度单位表，归属 DL_MathData，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_LengthUnit :
(
    eMm   := 0,   // 毫米（中介单位 m 的千分之一） / Millimetre, one thousandth of hub metre
    eM    := 1,   // 米（中介单位） / Metre, hub unit
    eInch := 2,   // 英寸（25.4 mm） / Inch, exactly 25.4 mm
    eFt   := 3    // 英尺（12 英寸） / Foot, twelve inches
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_LenConvErr（长度换算错误码）
 * 分级: eNegativeValue / eInvalidUnit / eNonFinite 为故障级（返回 FALSE）；
 *       eOk / eZeroValue 为信息级（返回 TRUE）。
 *----------------------------------------------------------------------------*)
TYPE E_DL_LenConvErr :
(
    eOk            := 0,   // 信息级：换算完成 / Info: conversion completed
    eZeroValue     := 1,   // 信息级：输入为零（合法） / Info: zero input, legal
    eInvalidUnit   := 2,   // 故障级：单位枚举越域 / Fault: unit enum out of domain
    eNonFinite     := 3,   // 故障级：输入非有限 / Fault: non-finite input
    eNegativeValue := 4    // 故障级：负长度 / Fault: negative length
);
END_TYPE

FUNCTION FC_DL_LengthUnitConvert : BOOL
VAR_INPUT
    fValue : LREAL;            // 被换算长度值 [源单位] / Length value in source unit
    eSrc   : E_DL_LengthUnit;  // 源单位枚举 [-] / Source unit enum
    eDst   : E_DL_LengthUnit;  // 目标单位枚举 [-] / Destination unit enum
END_VAR
VAR_OUTPUT
    fConverted : LREAL;            // 换算结果 [目标单位] / Converted result in destination unit
    eErrCode   : E_DL_LenConvErr;  // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _bNonFin : BOOL;   // 输入非有限当拍标志 [-] / Non-finite input flag
    _fHub    : LREAL;  // 中介长度值 [m] / Hub length value in metres
END_VAR
VAR CONSTANT
    DL_LUC_MM   : LREAL := 0.001;    // mm → m 换算系数 [m/mm] / mm to m factor
    DL_LUC_M    : LREAL := 1.0;      // m → m 恒等系数 [m/m] / m identity factor
    DL_LUC_INCH : LREAL := 0.0254;   // inch → m 换算系数 [m/inch] / inch to m factor
    DL_LUC_FT   : LREAL := 0.3048;   // ft → m 换算系数 [m/ft] / foot to m factor
    DL_LUC_ZERO : LREAL := 0.0;      // 零值与非有限判零基准 [-] / Zero and non-finite base
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_LengthUnitConvert := FALSE;                  // 返回值预置无效 / Return preset invalid
fConverted := DL_LUC_ZERO;                         // 结果哨兵 0 / Result sentinel zero
eErrCode   := E_DL_LenConvErr.eInvalidUnit;        // 预置最严码 / Preset strictest code

(* —— 段 1：非有限域闸（R79 双判：NaN 自反 + Inf 差自减） —— *)
_bNonFin := (fValue <> fValue) OR ((fValue - fValue) <> DL_LUC_ZERO);   // 非有限判定 / Non-finite test
IF _bNonFin THEN
    eErrCode := E_DL_LenConvErr.eNonFinite;        // 故障级码 / Fault-level code
    RETURN;                                        // 早退保持哨兵 / Early exit with sentinel
END_IF

(* —— 段 2：负长度域闸（物理量不可为负，拒绝而非钳位） —— *)
IF fValue < DL_LUC_ZERO THEN
    eErrCode := E_DL_LenConvErr.eNegativeValue;    // 故障级码 / Fault-level code
    RETURN;                                        // 早退保持哨兵 / Early exit with sentinel
END_IF

(* —— 段 3：源单位 → 中介米（按枚举成员逐值比较，不依赖 ENUM→INT 强转方言） —— *)
IF eSrc = E_DL_LengthUnit.eMm THEN
    _fHub := fValue * DL_LUC_MM;                   // mm × 0.001 / mm scaled
ELSIF eSrc = E_DL_LengthUnit.eM THEN
    _fHub := fValue * DL_LUC_M;                    // m 直通 / metre pass-through
ELSIF eSrc = E_DL_LengthUnit.eInch THEN
    _fHub := fValue * DL_LUC_INCH;                 // inch × 0.0254 / inch scaled
ELSIF eSrc = E_DL_LengthUnit.eFt THEN
    _fHub := fValue * DL_LUC_FT;                   // ft × 0.3048 / foot scaled
ELSE
    RETURN;                                        // 源单位越域：保持预置故障码 / Source unit out of domain
END_IF

(* —— 段 4：中介米 → 目标单位（常量除法，分母非零结构性无除零） —— *)
IF eDst = E_DL_LengthUnit.eMm THEN
    fConverted := _fHub / DL_LUC_MM;               // ÷0.001 / Divide by mm factor
ELSIF eDst = E_DL_LengthUnit.eM THEN
    fConverted := _fHub / DL_LUC_M;                // ÷1 / Divide by identity
ELSIF eDst = E_DL_LengthUnit.eInch THEN
    fConverted := _fHub / DL_LUC_INCH;             // ÷0.0254 / Divide by inch factor
ELSIF eDst = E_DL_LengthUnit.eFt THEN
    fConverted := _fHub / DL_LUC_FT;               // ÷0.3048 / Divide by foot factor
ELSE
    eErrCode   := E_DL_LenConvErr.eInvalidUnit;    // 目标单位越域 / Destination unit out of domain
    fConverted := DL_LUC_ZERO;                     // 结果回哨兵 / Result back to sentinel
    RETURN;                                        // 早退 / Early exit
END_IF

(* —— 段 5：结果非有限复检兜底（四段式第四段） —— *)
IF (fConverted <> fConverted) OR ((fConverted - fConverted) <> DL_LUC_ZERO) THEN
    fConverted := DL_LUC_ZERO;                     // 复检异常回哨兵 / Recheck failed: sentinel
    eErrCode   := E_DL_LenConvErr.eNonFinite;      // 故障级码 / Fault-level code
    RETURN;                                        // 早退 / Early exit
END_IF

(* —— 段 6：成功出口（零值单独置信息码，仍算有效换算） —— *)
IF fValue = DL_LUC_ZERO THEN
    eErrCode := E_DL_LenConvErr.eZeroValue;        // 信息级：零值 / Info: zero value
ELSE
    eErrCode := E_DL_LenConvErr.eOk;               // 信息级成功 / Info success
END_IF
FC_DL_LengthUnitConvert := TRUE;                   // 换算有效 / Conversion valid

END_FUNCTION
