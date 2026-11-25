(*==============================================================================
 * 组件名称 (Component)  : FC_DL_ConcentrationUnitConvert
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 算术运算符，零厂商私有库
 * 功能描述 (Function)   : 气体浓度单位换算：ppm（体积比）↔ %（体积比）↔ mg/m³（质量浓度）。
 *                         以 ppm 为中介单位：
 *                           %      → ppm   : × 10000
 *                           mg/m3  → ppm   : × Vm / M           （Vm = 22.414 L/mol）
 *                           ppm    → mg/m3 : × M / Vm
 *                         **标况假设（显式声明）**：Vm = 22.414 L/mol 为 0 ℃、101.325 kPa
 *                         干气理想气体摩尔体积；本件不做温压修正，非标况数据必须先由调用方
 *                         折算至标况再调用本件。摩尔质量 M 由引脚传入（g/mol），
 *                         不同气体（CO / CH4 / VOC 等）必须分别给值。
 * 接口     (Interface)  : 输入 fValue 被换算浓度 [源单位]、eSrc 源单位、eDst 目标单位、
 *                         fMolarMass 摩尔质量 [g/mol]（**换算必需，必须 > 0**）；
 *                         输出 fConverted 换算结果 [目标单位]、eErrCode（E_DL_ConcConvErr）；
 *                         返回值 = bValid 数值可信标志（TRUE = fConverted 可信）。
 * 边界     (Boundary)   : ① 属主边界：只做单位换算，不做温压折算、不做多组分加权、不做报警阈值比较。
 *                         ② **除零防护（R4 硬要求）**：mg/m³ ↔ ppm 两个方向都含除以 M 或除以 Vm 的
 *                         路径，进入分支前先判 fMolarMass > 0，否则故障级 eInvalidMolarMass 早退。
 *                         ③ 全部浮点入参非有限双判（fValue 与 fMolarMass 逐一枚举）。
 *                         ④ 浓度非负：负值 → 故障级 eNegativeValue（浓度无负值语义）。
 *                         ⑤ 单位枚举越域 → 故障级 eInvalidUnit，结果哨兵 0。
 *                         ⑥ ppm 与 % 为体积比，其换算不依赖 M；mg/m³ 参与的两向换算才依赖 M。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_HumidityUnitConvert` 分工：湿度归那件；
 *                         与气体检测 FB（未入库）分工：报警分级与延时归那件，本件只换算数值。
 * 来源标签 (Source Tag) : 开源溯源：lgf-math 换算系数（公开物理常数，clean-room 重写）；许可证 MIT（仅参考语义，代码原创）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + LREAL +
 *                         本文件内定义 enum E_DL_ConcConvErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 摩尔质量前置判零 + 全浮点非有限双判 + 负值拒绝 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B2 · 序号 20）
 * 验收向量 (Acceptance) : ① fValue=1.0(%) , eSrc=ePercent, eDst=ePpm → 1×10000 = 10000.0 ppm, eOk, TRUE；
 *                         ② fValue=10000.0, eSrc=ePpm, eDst=ePercent → 1.0 %, eOk；
 *                         ③ fValue=100.0(mg/m3), eSrc=eMgM3, eDst=ePpm, fMolarMass=28.01(CO) →
 *                         100×22.414/28.01 ≈ 80.0214 ppm（容差 1E-3）；
 *                         ④ fValue=80.0214, eSrc=ePpm, eDst=eMgM3, fMolarMass=28.01 →
 *                         80.0214×28.01/22.414 ≈ 100.0 mg/m3（容差 1E-2，与 ③ 互逆）；
 *                         ⑤ fMolarMass=0.0 → 返回 FALSE, 0, eInvalidMolarMass（除零防护分支）；
 *                         ⑥ fValue=-1.0, eSrc=ePpm, eDst=ePercent → 返回 FALSE, 0, eNegativeValue。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ConcUnit（气体浓度单位表，归属 DL_MathData，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_ConcUnit :
(
    ePpm     := 0,   // 百万分之一（体积比，中介单位） / Parts per million by volume, hub unit
    ePercent := 1,   // 体积百分数（= 10000 ppm） / Volume percent
    eMgM3    := 2    // 毫克每立方米（质量浓度，需摩尔质量换算） / Milligrams per cubic metre, needs molar mass
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ConcConvErr（浓度换算错误码）
 *----------------------------------------------------------------------------*)
TYPE E_DL_ConcConvErr :
(
    eOk               := 0,   // 信息级：换算完成 / Info: conversion completed
    eZeroValue        := 1,   // 信息级：输入为零（合法） / Info: zero input, legal
    eInvalidUnit      := 2,   // 故障级：单位枚举越域 / Fault: unit enum out of domain
    eNonFinite        := 3,   // 故障级：入参非有限 / Fault: non-finite input
    eNegativeValue    := 4,   // 故障级：负浓度 / Fault: negative concentration
    eInvalidMolarMass := 5    // 故障级：摩尔质量非正，除零风险 / Fault: molar mass not positive, division-by-zero risk
);
END_TYPE

FUNCTION FC_DL_ConcentrationUnitConvert : BOOL
VAR_INPUT
    fValue     : LREAL;         // 被换算浓度值 [源单位] / Concentration value in source unit
    eSrc       : E_DL_ConcUnit; // 源单位枚举 [-] / Source unit enum
    eDst       : E_DL_ConcUnit; // 目标单位枚举 [-] / Destination unit enum
    fMolarMass : LREAL;         // 摩尔质量（换算必需，必须 > 0） [g/mol] / Molar mass, mandatory and positive [g/mol]
END_VAR
VAR_OUTPUT
    fConverted : LREAL;             // 换算结果 [目标单位] / Converted result
    eErrCode   : E_DL_ConcConvErr;  // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _bNonFin : BOOL;   // 入参非有限当拍标志 [-] / Non-finite input flag
    _bNeedMol: BOOL;   // 本次换算是否需要摩尔质量 [-] / Whether molar mass is used in this conversion
    _fHub    : LREAL;  // 中介浓度值 [ppm] / Hub concentration value in ppm
END_VAR
VAR CONSTANT
    DL_CUC_PCT   : LREAL := 10000.0;   // % → ppm 换算系数（1% = 10000 ppm） [-] / Percent to ppm factor
    DL_CUC_VM    : LREAL := 22.414;    // 标况摩尔体积（0 ℃, 101.325 kPa） [L/mol] / Molar volume at standard conditions
    DL_CUC_ONE   : LREAL := 1.0;       // ppm 恒等系数 [-] / ppm identity factor
    DL_CUC_ZERO  : LREAL := 0.0;       // 零基准与非有限判零基准 [-] / Zero and non-finite base
    DL_CUC_TINY  : LREAL := 1.0E-9;    // 参数近似零阈值 [g/mol] / Near-zero parameter threshold
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_ConcentrationUnitConvert := FALSE;           // 返回值预置无效 / Return preset invalid
fConverted := DL_CUC_ZERO;                         // 结果哨兵 0 / Result sentinel
eErrCode   := E_DL_ConcConvErr.eInvalidUnit;       // 预置最严码 / Preset strictest code

(* —— 段 1：非有限域闸（fValue 与 fMolarMass 逐一枚举，禁止漏闸） —— *)
_bNonFin := (fValue <> fValue) OR ((fValue - fValue) <> DL_CUC_ZERO);            // 浓度值非有限 / Concentration non-finite
_bNonFin := _bNonFin OR (fMolarMass <> fMolarMass) OR ((fMolarMass - fMolarMass) <> DL_CUC_ZERO);  // 摩尔质量非有限 / Molar mass non-finite
IF _bNonFin THEN
    eErrCode := E_DL_ConcConvErr.eNonFinite;       // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 2：单位枚举域闸 —— *)
IF (eSrc <> E_DL_ConcUnit.ePpm) AND (eSrc <> E_DL_ConcUnit.ePercent) AND (eSrc <> E_DL_ConcUnit.eMgM3) THEN
    RETURN;                                        // 源单位越域 / Source unit out of domain
END_IF
IF (eDst <> E_DL_ConcUnit.ePpm) AND (eDst <> E_DL_ConcUnit.ePercent) AND (eDst <> E_DL_ConcUnit.eMgM3) THEN
    RETURN;                                        // 目标单位越域 / Destination unit out of domain
END_IF

(* —— 段 3：负浓度域闸 —— *)
IF fValue < DL_CUC_ZERO THEN
    eErrCode := E_DL_ConcConvErr.eNegativeValue;   // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 4：摩尔质量前置判零（凡涉及 mg/m3 的换算方向都必须先过此闸） —— *)
_bNeedMol := (eSrc = E_DL_ConcUnit.eMgM3) OR (eDst = E_DL_ConcUnit.eMgM3);   // 是否需要摩尔质量 / Molar mass needed flag
IF _bNeedMol THEN
    IF fMolarMass < DL_CUC_TINY THEN
        eErrCode := E_DL_ConcConvErr.eInvalidMolarMass;   // 故障级：摩尔质量非正 / Fault: non-positive molar mass
        RETURN;                                            // 早退，杜绝除以非正量 / Early exit, avoids division by non-positive value
    END_IF
END_IF

(* —— 段 5：源单位 → 中介 ppm —— *)
IF eSrc = E_DL_ConcUnit.ePpm THEN
    _fHub := fValue * DL_CUC_ONE;                  // ppm 直通 / ppm pass-through
ELSIF eSrc = E_DL_ConcUnit.ePercent THEN
    _fHub := fValue * DL_CUC_PCT;                  // % × 10000 / Percent scaled
ELSE
    _fHub := fValue * DL_CUC_VM / fMolarMass;      // mg/m3 × Vm / M（M 已在段 4 判正） / Mass to volume ppm
END_IF

(* —— 段 6：中介 ppm → 目标单位 —— *)
IF eDst = E_DL_ConcUnit.ePpm THEN
    fConverted := _fHub / DL_CUC_ONE;              // ÷1 直通 / Divide by identity
ELSIF eDst = E_DL_ConcUnit.ePercent THEN
    fConverted := _fHub / DL_CUC_PCT;              // ÷10000 / Divide by percent factor
ELSE
    fConverted := _fHub * fMolarMass / DL_CUC_VM;  // ppm × M / Vm（Vm 为常量 22.414，M 已判正） / Volume to mass
END_IF

(* —— 段 7：结果非有限复检兜底 —— *)
IF (fConverted <> fConverted) OR ((fConverted - fConverted) <> DL_CUC_ZERO) THEN
    fConverted := DL_CUC_ZERO;                     // 复检异常回哨兵 / Recheck failed: sentinel
    eErrCode   := E_DL_ConcConvErr.eNonFinite;     // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 8：成功出口 —— *)
IF fValue = DL_CUC_ZERO THEN
    eErrCode := E_DL_ConcConvErr.eZeroValue;       // 信息级：零值 / Info: zero value
ELSE
    eErrCode := E_DL_ConcConvErr.eOk;              // 信息级成功 / Info success
END_IF
FC_DL_ConcentrationUnitConvert := TRUE;            // 换算有效 / Conversion valid

END_FUNCTION
