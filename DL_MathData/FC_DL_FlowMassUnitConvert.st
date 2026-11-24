(*==============================================================================
 * 组件名称 (Component)  : FC_DL_FlowMassUnitConvert
 * 所属子库 (Sublibrary) : DL_MathData ｜ 版本 (Version) : 1.0.0 ｜ 2026-11-23
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 算术运算符，零厂商私有库
 * 功能描述 (Function)   : 质量流量单位互转（系数表驱动）：以 kg/h 为中介单位，
 *                         fHub = fValue × kSrc，fResult = fHub ÷ kDst；系数为编译期非零常量，
 *                         纯常量除法，结构性无除零。枚举源/目标越界由 CASE ... ELSE 拦截并
 *                         返回 0 哨兵。**与体积流量的分工**：本件只换质量流量，
 *                         体积流量（m³/h / L/min / SCFM）归 FC_DL_FlowUnitConvert；
 *                         两者之间的换算需介质密度，属组合换算，由调用方分两步完成。
 * 接口     (Interface)  : 输入 fValue 被换算质量流量 [源单位]、eSrc 源单位、eDst 目标单位；
 *                         输出 fConverted 换算结果 [目标单位]、eErrCode（E_DL_FlowMassConvErr）；
 *                         返回值 = 数值可信标志。
 * 边界     (Boundary)   : ① 质量流量可反向（倒罐 / 回流），负值合法，不设符号闸。
 *                         ② 单位枚举越域 → 故障级 eInvalidUnit，结果哨兵 0。
 *                         ③ 非有限双判，命中即故障级 eNonFinite。
 *                         ④ 中介值与结果各复检一次（四段式第四段）。
 *                         ⑤ 零值合法（停流），置信息级 eZeroValue。
 *                         ⑥ 换算系数为国际定义值：1 t = 1000 kg（公吨，非短吨）；
 *                            1 lb = 0.45359237 kg（国际磅，1959 约定值）。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 码表     (Codes)      : 本件不占用全局数字码位（R297 零码位范式）；出口为 BOOL + LREAL +
 *                         本文件内 enum E_DL_FlowMassConvErr（全库唯一属主）。
 * 分工声明 (Scope)      : 体积流量归 FC_DL_FlowUnitConvert；质量/体积互转需密度，
 *                         本件不内联密度（R216 单一职责）。
 * 归属     (Ownership)  : E_DL_FlowMassUnit / E_DL_FlowMassConvErr 归属本文件（全库唯一属主，R264）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC ｜ R4 ✓ 非有限双判 +
 *                         CASE ELSE 兜底 + 常量除法无除零 ｜ R5 ✓ 逐行同行双语注释 ｜ R6 ✓ CASE ELSE
 *                         R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R78-B2 首版
 * 验收向量 (Acceptance) :
 *   A1 fValue=1.0, eSrc=eTH, eDst=eKgH → 1000.0；
 *   A2 fValue=1000.0, eSrc=eKgH, eDst=eTH → 1.0（容差 1E-12）；
 *   A3 fValue=1.0, eSrc=eLbH, eDst=eKgH → 0.45359237；
 *   A4 fValue=-250.0, eSrc=eKgH, eDst=eTH → -0.25（反向流合法）；
 *   A5 fValue=2.0, eSrc=非法值 9, eDst=eKgH → 0 哨兵, eInvalidUnit, 返回 FALSE。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_FlowMassUnit（质量流量单位表，归属本文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_FlowMassUnit :
(
    eKgH  := 0,   // 千克每小时（中介单位） / Kilogram per hour, hub unit
    eTH   := 1,   // 公吨每小时（= 1000 kg/h） / Metric tonne per hour, equals 1000 kg/h
    eLbH  := 2    // 磅每小时（= 0.45359237 kg/h） / Pound per hour, equals 0.45359237 kg/h
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_FlowMassConvErr（质量流量换算出口码；信息级 = 0..9，故障级 = 10 起）
 *----------------------------------------------------------------------------*)
TYPE E_DL_FlowMassConvErr :
(
    eOk          := 0,   // 信息级：换算完成 / Info: conversion completed
    eZeroValue   := 1,   // 信息级：零流量（停流） / Info: zero flow, result still trustworthy
    eInvalidUnit := 10,  // 故障级：单位枚举越域 / Fault: unit enum out of domain
    eNonFinite   := 11   // 故障级：输入或结果非有限 / Fault: non-finite input or result
);
END_TYPE

FUNCTION FC_DL_FlowMassUnitConvert : BOOL
VAR_INPUT
    fValue : LREAL;              // 被换算质量流量 [源单位] / Mass flow value in the source unit
    eSrc   : E_DL_FlowMassUnit;  // 源单位枚举 [-] / Source unit enum
    eDst   : E_DL_FlowMassUnit;  // 目标单位枚举 [-] / Destination unit enum
END_VAR
VAR_OUTPUT
    fConverted : LREAL;                 // 换算结果 [目标单位] / Converted result in the destination unit
    eErrCode   : E_DL_FlowMassConvErr;   // 出口码 [-] / Outlet code
END_VAR
VAR
    _bBadValue : BOOL;   // 输入非有限标志 [-] / Non-finite input flag
    _fHub      : LREAL;  // 中介质量流量 [kg/h] / Hub mass flow in kilogram per hour
END_VAR
VAR CONSTANT
    DL_FMC_ZERO : LREAL := 0.0;          // 零基准与零值判定基准 [-] / Zero base
    DL_FMC_KGH  : LREAL := 1.0;          // kg/h → kg/h 恒等系数 [-] / Hub identity factor
    DL_FMC_TH   : LREAL := 1000.0;       // t/h → kg/h 换算系数 [-] / Metric tonne per hour factor
    DL_FMC_LBH  : LREAL := 0.45359237;   // lb/h → kg/h 换算系数 [-] / Pound per hour factor
    DL_FMC_EPS  : LREAL := 1.0E-12;      // 零值判定容差 [-] / Zero-detection tolerance
END_VAR

(* —— 段 0：出口预置安全侧 —— *)
FC_DL_FlowMassUnitConvert := FALSE;                  // 返回值预置不可信 / Return preset not trustworthy
fConverted := DL_FMC_ZERO;                           // 结果哨兵 0 / Result sentinel
eErrCode   := E_DL_FlowMassConvErr.eInvalidUnit;     // 预置最严码 / Preset strictest code

(* —— 段 1：非有限域闸（R79 双判） —— *)
_bBadValue := (fValue <> fValue) OR ((fValue - fValue) <> DL_FMC_ZERO);      // 输入非有限 / Input non-finite
IF _bBadValue THEN
    eErrCode := E_DL_FlowMassConvErr.eNonFinite;     // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 2：源单位 → 中介 kg/h（CASE ELSE 拦截越域） —— *)
CASE eSrc OF
    E_DL_FlowMassUnit.eKgH :
        _fHub := fValue * DL_FMC_KGH;                // 直通 / Hub pass-through
    E_DL_FlowMassUnit.eTH :
        _fHub := fValue * DL_FMC_TH;                 // t/h × 1000 / Metric tonne per hour scaled
    E_DL_FlowMassUnit.eLbH :
        _fHub := fValue * DL_FMC_LBH;                // lb/h × 0.45359237 / Pound per hour scaled
ELSE
    _fHub    := DL_FMC_ZERO;                         // 中介值回哨兵 / Hub back to sentinel
    eErrCode := E_DL_FlowMassConvErr.eInvalidUnit;   // 故障级：源单位越域 / Fault: source out of domain
    RETURN;
END_CASE

(* —— 段 3：中介 kg/h → 目标单位（除数为常量，均非零） —— *)
CASE eDst OF
    E_DL_FlowMassUnit.eKgH :
        fConverted := _fHub / DL_FMC_KGH;            // ÷1 / Divide by identity
    E_DL_FlowMassUnit.eTH :
        fConverted := _fHub / DL_FMC_TH;             // ÷1000 / Divide by metric tonne factor
    E_DL_FlowMassUnit.eLbH :
        fConverted := _fHub / DL_FMC_LBH;            // ÷0.45359237 / Divide by pound per hour factor
ELSE
    fConverted := DL_FMC_ZERO;                       // 结果回哨兵 / Result back to sentinel
    eErrCode   := E_DL_FlowMassConvErr.eInvalidUnit; // 故障级：目标单位越域 / Fault: destination out of domain
    RETURN;
END_CASE

(* —— 段 4：中介值与结果复检（四段式第四段） —— *)
IF (_fHub <> _fHub) OR ((_fHub - _fHub) <> DL_FMC_ZERO)
    OR (fConverted <> fConverted) OR ((fConverted - fConverted) <> DL_FMC_ZERO) THEN
    fConverted := DL_FMC_ZERO;                       // 复检异常回哨兵 / Recheck failed: sentinel
    eErrCode   := E_DL_FlowMassConvErr.eNonFinite;   // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 5：成功出口（零值单列信息码） —— *)
IF (fValue < DL_FMC_EPS) AND (fValue > -DL_FMC_EPS) THEN
    eErrCode := E_DL_FlowMassConvErr.eZeroValue;     // 信息级：零流量 / Info: zero flow
ELSE
    eErrCode := E_DL_FlowMassConvErr.eOk;            // 信息级：换算完成 / Info: conversion completed
END_IF
FC_DL_FlowMassUnitConvert := TRUE;                   // 换算有效 / Conversion valid
END_FUNCTION
