(*==============================================================================
 * 组件名称 (Component)  : FC_DL_DynViscosityUnitConvert
 * 所属子库 (Sublibrary) : DL_MathData ｜ 版本 (Version) : 1.0.0 ｜ 2026-11-23
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 算术运算符，零厂商私有库
 * 功能描述 (Function)   : 动力粘度（dynamic viscosity，绝对粘度）单位互转，系数表驱动：
 *                         以 Pa·s 为中介单位，fHub = fValue × kSrc，fResult = fHub ÷ kDst；
 *                         系数为编译期非零常量，纯常量除法，结构性无除零。
 *                         **单位恒等说明**：1 cP ≡ 1 mPa·s（厘泊定义即毫帕·秒，两者为同一
 *                         物理量的两种书写），故两成员系数均为 1.0E-3；保留两个枚举成员
 *                         仅为适配不同 HMI 标签与协议字段，避免上游做字符串映射。
 *                         **与运动粘度的分工（关键）**：动力粘度 [Pa·s] 与运动粘度 [m²/s]
 *                         差一个密度因子（ν = η / ρ），本件不做该换算；运动粘度件为
 *                         FC_DL_ViscosityUnitConvert（mm²/s 族）。
 *                         负粘度物理上不存在 → 故障级 eNegativeValue 拒绝（不取绝对值）。
 * 接口     (Interface)  : 输入 fValue 被换算动力粘度 [源单位]、eSrc 源单位、eDst 目标单位；
 *                         输出 fConverted 换算结果 [目标单位]、eErrCode（E_DL_DynViscConvErr）；
 *                         返回值 = 数值可信标志。
 * 边界     (Boundary)   : ① 单位枚举越域 → 故障级 eInvalidUnit，结果哨兵 0。
 *                         ② 非有限双判（NaN / ±Inf），命中即故障级 eNonFinite。
 *                         ③ 负粘度 → 故障级 eNegativeValue（拒绝换算）。
 *                         ④ 零粘度 → 信息级 eZeroValue（物理上仅真空 / 静止，多为未充油），
 *                            结果仍可信并返回 TRUE（0 Pa·s = 0 cP 恒成立）。
 *                         ⑤ 中介值与结果各复检一次（四段式第四段）。
 *                         ⑥ 温度不补偿：动力粘度强依赖温度，本件为纯量纲换算，
 *                            调用方必须保证参与比较的数据同温基准（推荐 40 ℃）。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 码表     (Codes)      : 本件不占用全局数字码位（R297 零码位范式）；出口为 BOOL + LREAL +
 *                         本文件内 enum E_DL_DynViscConvErr（全库唯一属主）。
 * 分工声明 (Scope)      : 运动粘度归 FC_DL_ViscosityUnitConvert（E_DL_ViscUnit 属主）；
 *                         粘度-温度曲线拟合与油品换油判定不在本件范围。
 * 归属     (Ownership)  : E_DL_DynViscUnit / E_DL_DynViscConvErr 归属本文件（全库唯一属主，R264）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC ｜ R4 ✓ 非有限双判 +
 *                         CASE ELSE 兜底 + 常量除法无除零 + 负值闸 ｜ R5 ✓ 逐行同行双语注释
 *                         R6 ✓ CASE ELSE 兜底 ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R78-B2 首版（因 FC_DL_ViscosityUnitConvert
 *                         名称为运动粘度件占用，本件按动力粘度口径另立名）
 * 验收向量 (Acceptance) :
 *   A1 fValue=1000.0, eSrc=eCp, eDst=ePas → 1.0（容差 1E-12）；
 *   A2 fValue=1.0, eSrc=ePas, eDst=eCp → 1000.0；
 *   A3 fValue=1.0, eSrc=eCp, eDst=eMPas → 1.0（恒等关系）；
 *   A4 fValue=-5.0, eSrc=eCp, eDst=ePas → 0 哨兵, eNegativeValue, 返回 FALSE；
 *   A5 fValue=0.0, eSrc=ePas, eDst=eCp → 0.0, eZeroValue, 返回 TRUE。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_DynViscUnit（动力粘度单位表，归属本文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_DynViscUnit :
(
    ePas  := 0,   // 帕斯卡秒（中介单位，SI 一致单位） / Pascal second, hub unit
    eCp   := 1,   // 厘泊（= 1.0E-3 Pa·s） / Centipoise, equals 1.0E-3 Pa s
    eMPas := 2    // 毫帕秒（= 1.0E-3 Pa·s，与厘泊恒等） / Millipascal second, identical to centipoise
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_DynViscConvErr（动力粘度换算出口码；信息级 = 0..9，故障级 = 10 起）
 *----------------------------------------------------------------------------*)
TYPE E_DL_DynViscConvErr :
(
    eOk            := 0,   // 信息级：换算完成 / Info: conversion completed
    eZeroValue     := 1,   // 信息级：零粘度（多为未充油） / Info: zero viscosity, result still trustworthy
    eInvalidUnit   := 10,  // 故障级：单位枚举越域 / Fault: unit enum out of domain
    eNonFinite     := 11,  // 故障级：输入或结果非有限 / Fault: non-finite input or result
    eNegativeValue := 12   // 故障级：负粘度 / Fault: negative viscosity
);
END_TYPE

FUNCTION FC_DL_DynViscosityUnitConvert : BOOL
VAR_INPUT
    fValue : LREAL;             // 被换算动力粘度 [源单位] / Dynamic viscosity value in the source unit
    eSrc   : E_DL_DynViscUnit;  // 源单位枚举 [-] / Source unit enum
    eDst   : E_DL_DynViscUnit;  // 目标单位枚举 [-] / Destination unit enum
END_VAR
VAR_OUTPUT
    fConverted : LREAL;                 // 换算结果 [目标单位] / Converted result in the destination unit
    eErrCode   : E_DL_DynViscConvErr;   // 出口码 [-] / Outlet code
END_VAR
VAR
    _bBadValue : BOOL;   // 输入非有限标志 [-] / Non-finite input flag
    _fHub      : LREAL;  // 中介动力粘度 [Pa·s] / Hub dynamic viscosity in pascal second
END_VAR
VAR CONSTANT
    DL_DVC_ZERO : LREAL := 0.0;       // 零基准与零值判定基准 [-] / Zero base
    DL_DVC_PAS  : LREAL := 1.0;       // Pa·s → Pa·s 恒等系数 [-] / Hub identity factor
    DL_DVC_CP   : LREAL := 1.0E-3;    // cP → Pa·s 换算系数 [-] / Centipoise factor
    DL_DVC_MPAS : LREAL := 1.0E-3;    // mPa·s → Pa·s 换算系数 [-] / Millipascal second factor
    DL_DVC_EPS  : LREAL := 1.0E-12;   // 零值判定容差 [-] / Zero-detection tolerance
END_VAR

(* —— 段 0：出口预置安全侧 —— *)
FC_DL_DynViscosityUnitConvert := FALSE;              // 返回值预置不可信 / Return preset not trustworthy
fConverted := DL_DVC_ZERO;                           // 结果哨兵 0 / Result sentinel
eErrCode   := E_DL_DynViscConvErr.eInvalidUnit;      // 预置最严码 / Preset strictest code

(* —— 段 1：非有限域闸（R79 双判） —— *)
_bBadValue := (fValue <> fValue) OR ((fValue - fValue) <> DL_DVC_ZERO);      // 输入非有限 / Input non-finite
IF _bBadValue THEN
    eErrCode := E_DL_DynViscConvErr.eNonFinite;      // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 2：负粘度域闸（零值放行，由段 6 置信息码） —— *)
IF fValue < DL_DVC_ZERO THEN
    eErrCode := E_DL_DynViscConvErr.eNegativeValue;  // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 3：源单位 → 中介 Pa·s（CASE ELSE 拦截越域） —— *)
CASE eSrc OF
    E_DL_DynViscUnit.ePas :
        _fHub := fValue * DL_DVC_PAS;                // 直通 / Hub pass-through
    E_DL_DynViscUnit.eCp :
        _fHub := fValue * DL_DVC_CP;                 // cP × 1E-3 / Centipoise scaled
    E_DL_DynViscUnit.eMPas :
        _fHub := fValue * DL_DVC_MPAS;               // mPa·s × 1E-3 / Millipascal second scaled
ELSE
    _fHub    := DL_DVC_ZERO;                         // 中介值回哨兵 / Hub back to sentinel
    eErrCode := E_DL_DynViscConvErr.eInvalidUnit;    // 故障级：源单位越域 / Fault: source out of domain
    RETURN;
END_CASE

(* —— 段 4：中介 Pa·s → 目标单位（除数为常量，均非零） —— *)
CASE eDst OF
    E_DL_DynViscUnit.ePas :
        fConverted := _fHub / DL_DVC_PAS;            // ÷1 / Divide by identity
    E_DL_DynViscUnit.eCp :
        fConverted := _fHub / DL_DVC_CP;             // ÷1E-3 / Divide by centipoise factor
    E_DL_DynViscUnit.eMPas :
        fConverted := _fHub / DL_DVC_MPAS;           // ÷1E-3 / Divide by millipascal second factor
ELSE
    fConverted := DL_DVC_ZERO;                       // 结果回哨兵 / Result back to sentinel
    eErrCode   := E_DL_DynViscConvErr.eInvalidUnit;  // 故障级：目标单位越域 / Fault: destination out of domain
    RETURN;
END_CASE

(* —— 段 5：中介值与结果复检（四段式第四段） —— *)
IF (_fHub <> _fHub) OR ((_fHub - _fHub) <> DL_DVC_ZERO)
    OR (fConverted <> fConverted) OR ((fConverted - fConverted) <> DL_DVC_ZERO) THEN
    fConverted := DL_DVC_ZERO;                       // 复检异常回哨兵 / Recheck failed: sentinel
    eErrCode   := E_DL_DynViscConvErr.eNonFinite;    // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 6：成功出口（零值单列信息码，提示上游可能未充油） —— *)
IF (fValue < DL_DVC_EPS) AND (fValue > -DL_DVC_EPS) THEN
    eErrCode := E_DL_DynViscConvErr.eZeroValue;      // 信息级：零粘度 / Info: zero viscosity
ELSE
    eErrCode := E_DL_DynViscConvErr.eOk;             // 信息级：换算完成 / Info: conversion completed
END_IF
FC_DL_DynViscosityUnitConvert := TRUE;               // 换算有效 / Conversion valid
END_FUNCTION
