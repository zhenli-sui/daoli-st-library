(*
  Component : FC_DL_CathodeMoistureSpecCalc
  Category  : DL_Process
  Function  : 水分限值与所需干燥时间反算（一阶指数干燥模型 t = -τ × LN(M目标/M初始)）
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 rMoistInitPct 初始水分 [%]、rMoistTargetPct 目标水分限值 [%]、
             rDryTauMin 干燥时间常数 [min]、rDryTimeMaxMin 工艺允许最长干燥时间 [min]；
             输出 rDryMin 计算所需干燥时间 [min]、rMoistRatio 水分比 [-]、
             xSpecAchievable 目标在当前允许时间内可达、xValid 有效标志、nFaultCode 故障码。
  边界     : 须 初始水分 > 目标水分 > 0；时间常数为分母须 >1.0E-9 [min]；允许时长须 >0；
             模型不含恒速段与临界含水率，仅适用于降速干燥段（物料表面已不饱和）；
             目标不可达只置 xSpecAchievable=FALSE 为信息级，不置故障。
  码位     : 9801 输入非有限（故障级）；9802 水分关系非法（故障级）；9803 时间常数或允许时长越域（故障级）。
*)
FUNCTION FC_DL_CathodeMoistureSpecCalc : BOOL
VAR_INPUT
    rMoistInitPct   : LREAL := 5.0;      // 初始水分 [%] EN: the initial moisture content
    rMoistTargetPct : LREAL := 0.05;     // 目标水分限值 [%] EN: the target moisture limit
    rDryTauMin      : LREAL := 20.0;     // 干燥时间常数 [min] EN: the drying time constant
    rDryTimeMaxMin  : LREAL := 180.0;    // 工艺允许最长干燥时间 [min] EN: the longest drying time allowed by the process
END_VAR
VAR_OUTPUT
    rDryMin         : LREAL;             // 计算所需干燥时间 [min] EN: the computed drying time required
    rMoistRatio     : LREAL;             // 目标与初始水分之比 [-] EN: the ratio of the target to the initial moisture
    xSpecAchievable : BOOL;              // 目标在允许时间内可达（信息级） EN: the target is reachable within the allowed time, information class only
    xValid          : BOOL;              // 输出可信标志 EN: the outputs are valid
    nFaultCode      : INT;               // 0=无故障 9801=输入非有限 9802=水分关系非法 9803=常数或时长越域 EN: zero none, 9801 non finite, 9802 illegal moisture relation, 9803 constant or duration out of range
END_VAR
VAR
    xFinAll : BOOL;                      // 四输入同时有限 EN: all four inputs are finite
    rRat    : LREAL;                     // 水分比中间值 [-] EN: the interim moisture ratio
    rLn     : LREAL;                     // 水分比对数 [-] EN: the logarithm of the moisture ratio
    rT      : LREAL;                     // 干燥时间中间值 [min] EN: the interim drying time
END_VAR
VAR CONSTANT
    DL_CMS_Z      : LREAL := 0.0;        // 浮点零常量 EN: the floating point zero constant
    DL_CMS_MIN    : LREAL := 1.0E-9;     // 分母绝对值下限 EN: the lower bound of the divisor magnitude
    DL_CMS_C_BAD  : INT := 9801;         // 输入非有限 EN: a non finite input
    DL_CMS_C_REL  : INT := 9802;         // 水分关系非法 EN: an illegal moisture relation
    DL_CMS_C_RANG : INT := 9803;         // 时间常数或允许时长越域 EN: the constant or the duration is out of range
END_VAR

// 段1｜出口预置
FC_DL_CathodeMoistureSpecCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rDryMin := DL_CMS_Z;                      // 干燥时间预置零 [min] EN: preset the drying time to zero
rMoistRatio := DL_CMS_Z;                  // 水分比预置零 [-] EN: preset the moisture ratio to zero
xSpecAchievable := FALSE;                 // 可达标志预置假 EN: preset the reachability flag to false
xValid := FALSE;                          // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                          // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：四输入全列
xFinAll := (rMoistInitPct = rMoistInitPct) AND ((rMoistInitPct - rMoistInitPct) = DL_CMS_Z)
        AND (rMoistTargetPct = rMoistTargetPct) AND ((rMoistTargetPct - rMoistTargetPct) = DL_CMS_Z)
        AND (rDryTauMin = rDryTauMin) AND ((rDryTauMin - rDryTauMin) = DL_CMS_Z)
        AND (rDryTimeMaxMin = rDryTimeMaxMin) AND ((rDryTimeMaxMin - rDryTimeMaxMin) = DL_CMS_Z);   // 四输入有限性 EN: the finiteness of all four inputs
IF NOT xFinAll THEN                                                                                 // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_CMS_C_BAD;                                                                     // 非有限码 EN: the non finite code
    RETURN;                                                                                         // 早退 EN: return early
END_IF

// 段3｜域闸：水分关系 初始 > 目标 > 0；时间常数与允许时长为正
IF (rMoistTargetPct <= DL_CMS_Z) OR (rMoistInitPct <= rMoistTargetPct) THEN                          // 水分关系闸 EN: the moisture relation gate
    nFaultCode := DL_CMS_C_REL;                                                                     // 关系非法码 EN: the relation code
    RETURN;                                                                                         // 早退 EN: return early
END_IF
IF (rDryTauMin < DL_CMS_MIN) OR (rDryTimeMaxMin <= DL_CMS_Z) THEN                                    // 常数与时长闸 EN: the constant and duration gate
    nFaultCode := DL_CMS_C_RANG;                                                                    // 越域码 EN: the out of range code
    RETURN;                                                                                         // 早退 EN: return early
END_IF

// 段4｜主体：t = -τ × LN(目标/初始)，比值已证在 (0,1)
rRat := rMoistTargetPct / rMoistInitPct;                                                            // 水分比 [-] EN: the moisture ratio
rLn := LN(rRat);                                                                                    // 水分比对数，已证 <0 [-] EN: the logarithm of the ratio, proven negative
rT := -rDryTauMin * rLn;                                                                            // 所需干燥时间 [min] EN: the drying time required
IF (rT <> rT) OR (rT < DL_CMS_Z) THEN                                                               // 结果复检 EN: recheck the result
    nFaultCode := DL_CMS_C_RANG;                                                                    // 复检失败码 EN: the recheck failure code
    RETURN;                                                                                         // 早退，出口保持零哨兵 EN: return early with the zero sentinels
END_IF

// 段5｜出口：可达性为信息级判据
rDryMin := rT;                                                                                      // 干燥时间出口 [min] EN: the drying time output
rMoistRatio := rRat;                                                                                // 水分比出口 [-] EN: the moisture ratio output
xSpecAchievable := rT <= rDryTimeMaxMin;                                                            // 可达性判定 EN: the reachability verdict
xValid := TRUE;                                                                                     // 结果可信 EN: the results are valid
FC_DL_CathodeMoistureSpecCalc := TRUE;                                                              // 返回真 EN: return true
END_FUNCTION
