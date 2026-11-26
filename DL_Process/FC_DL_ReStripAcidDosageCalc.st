(*
  Component : FC_DL_ReStripAcidDosageCalc
  Category  : DL_Process
  Function  : 反萃酸耗核算：稀土摩尔量 × 当量系数 → 纯酸 kg/h 与所需酸液体积流量、酸浓度校核
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契化     : 输入 rOrgReConcGpl 负载有机相稀土浓度 [g/L]、rFlowOrgM3h 有机相流量 [m3/h]、
             rReMolWeight 稀土平均摩尔质量 [g/mol]、rAcidEquiv 每摩尔稀土耗酸当量 [mol/mol]、
             rAcidMolWeight 酸摩尔质量 [g/mol]、rAcidConcGpl 配酸浓度 [g/L]；
             输出 rReMolH 稀土摩尔流率 [mol/h]、rAcidKgH 纯酸耗量 [kg/h]、rAcidSolM3h 所需酸液体积流量 [m3/h]、
             rAcidExcessPct 实际配酸相对需求的富余率 [%]、xConcOk 浓度配置可行、xValid 有效标志、nFaultCode 故障码。
  边界     : 单位链：g/L × m3/h = 1000 g/h，再除 g/mol 得 mol/h，故 mol/h = 浓度 × 流量 × 1000 / 摩尔质量；
             纯酸 kg/h = mol/h × 当量 × (g/mol) / 1000；g/L 与 kg/m3 数值相等，故酸液 m3/h = kg/h ÷ (g/L)；
             所有摩尔质量与当量须 >1.0E-6，配酸浓度须 >1.0E-9 [g/L]，否则判 9802；
             xConcOk 的判据是「配酸浓度足以在有机相流量同等体积下供足酸量」，不足为信息级告警。
  码位     : 9801 输入非法（故障级）；9802 摩尔质量/当量/配酸浓度越域（故障级）。
*)
FUNCTION FC_DL_ReStripAcidDosageCalc : BOOL
VAR_INPUT
    rOrgReConcGpl   : LREAL := 20.0;    // 负载有机相稀土浓度 [g/L] EN: the rare earth concentration of the loaded organic phase
    rFlowOrgM3h     : LREAL := 5.0;     // 有机相体积流量 [m3/h] EN: the volumetric flow of the organic phase
    rReMolWeight    : LREAL := 140.0;   // 稀土元素平均摩尔质量 [g/mol] EN: the average molar mass of the rare earth element
    rAcidEquiv      : LREAL := 3.0;     // 每摩尔稀土耗酸当量 [mol/mol] EN: the acid equivalents consumed per mole of rare earth
    rAcidMolWeight  : LREAL := 36.46;   // 酸摩尔质量（盐酸缺省） [g/mol] EN: the molar mass of the acid, hydrochloric by default
    rAcidConcGpl    : LREAL := 200.0;   // 配酸浓度 [g/L] EN: the concentration of the prepared acid solution
END_VAR
VAR_OUTPUT
    rReMolH        : LREAL;             // 稀土摩尔流率 [mol/h] EN: the molar flow of the rare earth
    rAcidKgH       : LREAL;             // 纯酸耗量 [kg/h] EN: the pure acid mass flow required
    rAcidSolM3h    : LREAL;             // 所需酸液体积流量 [m3/h] EN: the acid solution volumetric flow required
    rAcidExcessPct : LREAL;             // 配酸富余率（相对同体积供酸能力） [%] EN: the surplus of the prepared acid against the demand at the same volume
    xConcOk        : BOOL;              // 配酸浓度足以供酸（信息级） EN: the acid concentration is sufficient, information class only
    xValid         : BOOL;              // 输出可信标志 EN: the outputs are valid
    nFaultCode     : INT;               // 0=无故障 9801=输入非法 9802=摩尔质量或浓度越域 EN: zero none, 9801 illegal input, 9802 molar mass or concentration out of range
END_VAR
VAR
    xFinAll  : BOOL;                    // 六输入同时有限 EN: all six inputs are finite
    rMolH    : LREAL;                   // 摩尔流率中间值 [mol/h] EN: the interim molar flow
    rAcidKg  : LREAL;                   // 纯酸流量中间值 [kg/h] EN: the interim pure acid mass flow
    rSolM3h  : LREAL;                   // 酸液流量中间值 [m3/h] EN: the interim acid solution flow
    rSupply  : LREAL;                   // 同等体积下的供酸能力 [kg/h] EN: the acid supply capability at the same volumetric flow
END_VAR
VAR CONSTANT
    DL_RSD_Z      : LREAL := 0.0;       // 浮点零常量 EN: the floating point zero constant
    DL_RSD_K1000  : LREAL := 1000.0;    // 升-立方米与克-千克换算系数 EN: the litre to cubic metre and gram to kilogram factor
    DL_RSD_HUND   : LREAL := 100.0;     // 百分数换算系数 EN: the percent conversion factor
    DL_RSD_MIN    : LREAL := 1.0E-6;    // 摩尔质量与当量的下限 EN: the lower bound of the molar mass and equivalents
    DL_RSD_C_BAD  : INT := 9801;        // 输入非法 EN: an illegal input
    DL_RSD_C_RANGE: INT := 9802;        // 摩尔质量或配酸浓度越域 EN: the molar mass or the acid concentration is out of range
END_VAR

// 段1｜出口预置
FC_DL_ReStripAcidDosageCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rReMolH := DL_RSD_Z;                    // 摩尔流率预置零 [mol/h] EN: preset the molar flow to zero
rAcidKgH := DL_RSD_Z;                   // 纯酸耗量预置零 [kg/h] EN: preset the acid mass flow to zero
rAcidSolM3h := DL_RSD_Z;                // 酸液流量预置零 [m3/h] EN: preset the acid solution flow to zero
rAcidExcessPct := DL_RSD_Z;             // 富余率预置零 [%] EN: preset the surplus to zero
xConcOk := FALSE;                       // 浓度可行标志预置假 EN: preset the concentration flag to false
xValid := FALSE;                        // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                        // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：六个浮点入参全列
xFinAll := (rOrgReConcGpl = rOrgReConcGpl) AND ((rOrgReConcGpl - rOrgReConcGpl) = DL_RSD_Z)
        AND (rFlowOrgM3h = rFlowOrgM3h) AND ((rFlowOrgM3h - rFlowOrgM3h) = DL_RSD_Z)
        AND (rReMolWeight = rReMolWeight) AND ((rReMolWeight - rReMolWeight) = DL_RSD_Z)
        AND (rAcidEquiv = rAcidEquiv) AND ((rAcidEquiv - rAcidEquiv) = DL_RSD_Z)
        AND (rAcidMolWeight = rAcidMolWeight) AND ((rAcidMolWeight - rAcidMolWeight) = DL_RSD_Z)
        AND (rAcidConcGpl = rAcidConcGpl) AND ((rAcidConcGpl - rAcidConcGpl) = DL_RSD_Z);   // 六输入有限性 EN: the finiteness of all six inputs
IF NOT xFinAll THEN                                                                          // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_RSD_C_BAD;                                                              // 输入非法码 EN: the illegal input code
    RETURN;                                                                                  // 早退 EN: return early
END_IF

// 段3｜域闸：四个除数逐一过下限（摩尔质量两枚、当量、配酸浓度），流量与浓度非负
IF (rReMolWeight < DL_RSD_MIN) OR (rAcidMolWeight < DL_RSD_MIN)
   OR (rAcidEquiv < DL_RSD_MIN) OR (ABS(rAcidConcGpl) < DL_RSD_MIN)
   OR (rFlowOrgM3h < DL_RSD_Z) OR (rOrgReConcGpl < DL_RSD_Z) THEN
    nFaultCode := DL_RSD_C_RANGE;                                                            // 越域码 EN: the out of range code
    RETURN;                                                                                  // 早退 EN: return early
END_IF

// 段4｜主体：mol/h → 纯酸 kg/h → 酸液 m3/h
rMolH := (rOrgReConcGpl * rFlowOrgM3h * DL_RSD_K1000) / rReMolWeight;                       // 稀土摩尔流率 [mol/h] EN: the rare earth molar flow
rAcidKg := (rMolH * rAcidEquiv * rAcidMolWeight) / DL_RSD_K1000;                             // 纯酸耗量 [kg/h] EN: the pure acid mass flow
rSolM3h := rAcidKg / rAcidConcGpl;                                                           // 酸液体积流量 [m3/h] EN: the acid solution flow, g/L equals kg/m3

// 段5｜结果复检：三路输出非有限或为负一律出口
IF (rMolH <> rMolH) OR (rAcidKg <> rAcidKg) OR (rSolM3h <> rSolM3h)
   OR (rMolH < DL_RSD_Z) OR (rAcidKg < DL_RSD_Z) OR (rSolM3h < DL_RSD_Z) THEN
    nFaultCode := DL_RSD_C_RANGE;                                                            // 复检失败码 EN: the recheck failure code
    RETURN;                                                                                  // 早退，出口保持零哨兵 EN: return early with the zero sentinels
END_IF

// 段6｜浓度校核：同等有机相体积下的供酸能力，不足仅信息级告警
rSupply := rAcidConcGpl * rFlowOrgM3h;                                                       // 同体积供酸能力 [kg/h] EN: the acid supply capability at the same volume
IF (rSupply > DL_RSD_Z) AND (rAcidKg > DL_RSD_MIN) THEN                                       // 供酸能力与酸耗双分母有效 EN: both divisors are usable
    rAcidExcessPct := ((rSupply - rAcidKg) / rAcidKg) * DL_RSD_HUND;                         // 富余率 [%] EN: the surplus percent
    xConcOk := rSupply >= rAcidKg;                                                           // 浓度足以供酸 EN: the concentration is sufficient
ELSE
    rAcidExcessPct := DL_RSD_Z;                                                              // 供酸能力或酸耗为零时给零 [%] EN: give zero when either divisor is zero
    xConcOk := FALSE;                                                                        // 不可供酸 EN: cannot supply
END_IF
rReMolH := rMolH;                                                                            // 摩尔流率出口 [mol/h] EN: the molar flow output
rAcidKgH := rAcidKg;                                                                         // 纯酸耗量出口 [kg/h] EN: the acid mass flow output
rAcidSolM3h := rSolM3h;                                                                      // 酸液流量出口 [m3/h] EN: the acid solution flow output
xValid := TRUE;                                                                              // 结果可信 EN: the results are valid
FC_DL_ReStripAcidDosageCalc := TRUE;                                                         // 返回真 EN: return true
END_FUNCTION
