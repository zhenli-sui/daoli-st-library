(*==============================================================================
 * 组件名称 (Component)  : FC_DL_AccelUnitConvert
 * 所属子库 (Sublibrary) : DL_MathData ｜ 版本 (Version) : 1.0.0 ｜ 2026-11-23
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 算术运算符，零厂商私有库
 * 功能描述 (Function)   : 加速度单位互转（系数表驱动）：以 m/s² 为中介单位，
 *                         fHub = fValue × kSrc，fResult = fHub ÷ kDst；系数为编译期非零常量，
 *                         纯常量除法，结构性无除零。枚举源/目标越界一律由 CASE ... ELSE
 *                         拦截并返回 0 哨兵（禁静默换算）。
 *                         **重力常数口径**：标准重力加速度 g₀ = 9.80665 m/s²（ISO 80000-3 /
 *                         CGPM 1901 定义值），非本地纬度实测值；本件不做纬度修正。
 * 接口     (Interface)  : 输入 fValue 被换算加速度 [源单位]、eSrc 源单位、eDst 目标单位；
 *                         输出 fConverted 换算结果 [目标单位]、eErrCode（E_DL_AccConvErr）；
 *                         返回值 = 数值可信标志（TRUE = fConverted 可信）。
 * 边界     (Boundary)   : ① 加速度为矢量分量，负值合法（减速 / 反向），不设符号闸。
 *                         ② 单位枚举越域 → 故障级 eInvalidUnit，结果哨兵 0。
 *                         ③ 非有限双判（NaN / ±Inf），命中即故障级 eNonFinite。
 *                         ④ 中介值与结果各复检一次（四段式第四段）。
 *                         ⑤ 零值合法（自由落体失重即 0 g），置信息级 eZeroValue。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 码表     (Codes)      : 本件不占用全局数字码位（R297 零码位范式）；出口为 BOOL + LREAL +
 *                         本文件内 enum E_DL_AccConvErr（全库唯一属主）。
 * 分工声明 (Scope)      : 速度归 FC_DL_SpeedUnitConvert，力归 FC_DL_ForceUnitConvert；
 *                         g 与 m/s² 属加速度量纲，本件专属。
 * 归属     (Ownership)  : E_DL_AccUnit / E_DL_AccConvErr 归属本文件（全库唯一属主，R264）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC ｜ R4 ✓ 非有限双判 +
 *                         CASE ELSE 枚举兜底 + 常量除法无除零 ｜ R5 ✓ 逐行同行双语注释
 *                         R6 ✓ CASE ELSE 兜底（无状态机相位） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R78-B2 首版
 * 验收向量 (Acceptance) :
 *   A1 fValue=9.80665, eSrc=eMps2, eDst=eG → 1.0（容差 1E-12）；
 *   A2 fValue=1.0, eSrc=eG, eDst=eMps2 → 9.80665；
 *   A3 fValue=-2.0, eSrc=eMps2, eDst=eG → -0.20394324259558562（负值合法）；
 *   A4 fValue=5.0, eSrc=eMps2, eDst=非法值 7 → 0 哨兵, eInvalidUnit, 返回 FALSE；
 *   A5 fValue=0.0, eSrc=eG, eDst=eMps2 → 0.0, eZeroValue, 返回 TRUE。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_AccUnit（加速度单位表，归属本文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_AccUnit :
(
    eMps2 := 0,   // 米每二次方秒（中介单位） / Metre per second squared, hub unit
    eG    := 1    // 标准重力加速度（9.80665 m/s²） / Standard gravity, 9.80665 m/s²
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_AccConvErr（加速度换算出口码；信息级 = 0..9，故障级 = 10 起）
 *----------------------------------------------------------------------------*)
TYPE E_DL_AccConvErr :
(
    eOk          := 0,   // 信息级：换算完成 / Info: conversion completed
    eZeroValue   := 1,   // 信息级：零加速度（失重 / 静止） / Info: zero acceleration, result still trustworthy
    eInvalidUnit := 10,  // 故障级：单位枚举越域 / Fault: unit enum out of domain
    eNonFinite   := 11   // 故障级：输入或结果非有限 / Fault: non-finite input or result
);
END_TYPE

FUNCTION FC_DL_AccelUnitConvert : BOOL
VAR_INPUT
    fValue : LREAL;         // 被换算加速度 [源单位] / Acceleration value in the source unit
    eSrc   : E_DL_AccUnit;  // 源单位枚举 [-] / Source unit enum
    eDst   : E_DL_AccUnit;  // 目标单位枚举 [-] / Destination unit enum
END_VAR
VAR_OUTPUT
    fConverted : LREAL;           // 换算结果 [目标单位] / Converted result in the destination unit
    eErrCode   : E_DL_AccConvErr;  // 出口码 [-] / Outlet code
END_VAR
VAR
    _bBadValue : BOOL;   // 输入非有限标志 [-] / Non-finite input flag
    _fHub      : LREAL;  // 中介加速度值 [m/s²] / Hub acceleration value in metres per second squared
END_VAR
VAR CONSTANT
    DL_ACC_ZERO  : LREAL := 0.0;       // 零基准与零值判定基准 [-] / Zero base
    DL_ACC_MPS2  : LREAL := 1.0;       // m/s² → m/s² 恒等系数 [-] / Hub identity factor
    DL_ACC_G     : LREAL := 9.80665;   // g → m/s² 换算系数（标准重力） / Standard gravity factor
    DL_ACC_EPS   : LREAL := 1.0E-12;   // 零值判定容差 [-] / Zero-detection tolerance
END_VAR

(* —— 段 0：出口预置安全侧 —— *)
FC_DL_AccelUnitConvert := FALSE;                     // 返回值预置不可信 / Return preset not trustworthy
fConverted := DL_ACC_ZERO;                           // 结果哨兵 0 / Result sentinel
eErrCode   := E_DL_AccConvErr.eInvalidUnit;          // 预置最严码 / Preset strictest code

(* —— 段 1：非有限域闸（R79 双判） —— *)
_bBadValue := (fValue <> fValue) OR ((fValue - fValue) <> DL_ACC_ZERO);      // 输入非有限 / Input non-finite
IF _bBadValue THEN
    eErrCode := E_DL_AccConvErr.eNonFinite;          // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 2：源单位 → 中介 m/s²（CASE ELSE 拦截越域，R6） —— *)
CASE eSrc OF
    E_DL_AccUnit.eMps2 :
        _fHub := fValue * DL_ACC_MPS2;               // 直通 / Hub pass-through
    E_DL_AccUnit.eG :
        _fHub := fValue * DL_ACC_G;                  // g × 9.80665 / Gravity scaled to metres per second squared
ELSE
    _fHub     := DL_ACC_ZERO;                        // 中介值回哨兵 / Hub back to sentinel
    eErrCode  := E_DL_AccConvErr.eInvalidUnit;       // 故障级：源单位越域 / Fault: source unit out of domain
    RETURN;
END_CASE

(* —— 段 3：中介 m/s² → 目标单位（除数为常量，均非零） —— *)
CASE eDst OF
    E_DL_AccUnit.eMps2 :
        fConverted := _fHub / DL_ACC_MPS2;           // ÷1 / Divide by identity
    E_DL_AccUnit.eG :
        fConverted := _fHub / DL_ACC_G;              // ÷9.80665 / Divide by standard gravity factor
ELSE
    fConverted := DL_ACC_ZERO;                       // 结果回哨兵 / Result back to sentinel
    eErrCode   := E_DL_AccConvErr.eInvalidUnit;      // 故障级：目标单位越域 / Fault: destination out of domain
    RETURN;
END_CASE

(* —— 段 4：中介值与结果复检（四段式第四段） —— *)
IF (_fHub <> _fHub) OR ((_fHub - _fHub) <> DL_ACC_ZERO)
    OR (fConverted <> fConverted) OR ((fConverted - fConverted) <> DL_ACC_ZERO) THEN
    fConverted := DL_ACC_ZERO;                       // 复检异常回哨兵 / Recheck failed: sentinel
    eErrCode   := E_DL_AccConvErr.eNonFinite;        // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 5：成功出口（零值单列信息码） —— *)
IF (fValue < DL_ACC_EPS) AND (fValue > -DL_ACC_EPS) THEN
    eErrCode := E_DL_AccConvErr.eZeroValue;          // 信息级：零加速度 / Info: zero acceleration
ELSE
    eErrCode := E_DL_AccConvErr.eOk;                 // 信息级：换算完成 / Info: conversion completed
END_IF
FC_DL_AccelUnitConvert := TRUE;                      // 换算有效 / Conversion valid
END_FUNCTION
