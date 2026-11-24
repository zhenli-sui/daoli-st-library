// FC_DL_GearRatioCalc v1.0.0
// 开源溯源：self-cleanroom / 机械传动族
(*
  道莅工业代码库 | DL_Motion | FC_DL_GearRatioCalc
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  功能: 齿轮减速比与负载惯量比换算：减速比 i = n_in/n_out = z_out/z_in，
        折算负载惯量 J_ref = J_load / i²（负载侧经减速机折算至电机侧）
  邻件关系: 与 GearInPhaseAlign（齿轮相位对齐）同族 —— 差异点：相位件做
            啮合相位对齐动作，本件为纯比值/折算计算件，无相位语义；
            本件码位 16#0002_2601
*)
FUNCTION FC_DL_GearRatioCalc : REAL
VAR_INPUT
    fSpeedIn   : REAL := 0.0;   // 输入转速 n_in [rpm]，域 > 0 / Input speed [rpm], domain > 0
    fSpeedOut  : REAL := 0.0;   // 输出转速 n_out [rpm]，域 > 0 / Output speed [rpm], domain > 0
    fLoadInertia: REAL := 0.0;  // 负载侧惯量 J_load [kg·m²]，域 >= 0 / Load-side inertia [kg·m2]
    fEps       : REAL := 1.0E-6;// 判零容差 [rpm|kg·m²] / Zero tolerance
END_VAR
VAR_OUTPUT
    fRatio     : REAL;          // 减速比 i = n_in/n_out [1] / Gear ratio
    fInertiaRef: REAL;          // 折算至电机侧负载惯量 J_load/i² [kg·m²] / Load inertia referred to motor side
    bValid     : BOOL;          // 结果有效回执 [-] / Result validity receipt
    uErrorId   : UDINT;         // 事件码，0 = 无事件；16#0002_2601 = 域外拒收 / Event code
END_VAR

// —— 段 0：全路径缺省 —— //
fRatio := 0.0;                   // 减速比缺省零 / Ratio default zero
fInertiaRef := 0.0;              // 折算惯量缺省零 / Referred inertia default zero
bValid := FALSE;                 // 有效回执预清 / Validity preset
uErrorId := 16#0000;             // 事件码预清 / Event code preset
FC_DL_GearRatioCalc := 0.0;      // 返回值缺省零（镜像减速比）/ Return default mirrors ratio

// —— 段 1：非有限闸 —— //
IF (fSpeedIn <> fSpeedIn) OR (fSpeedOut <> fSpeedOut) OR (fLoadInertia <> fLoadInertia)
   OR (ABS(fSpeedIn) >= 3.0E38) OR (ABS(fSpeedOut) >= 3.0E38) OR (ABS(fLoadInertia) >= 3.0E38) THEN
    uErrorId := 16#0002_2601;    // 输入非有限拒收 / Non-finite reject
    RETURN;
END_IF

// —— 段 2：分母防零与域闸（R4） —— //
IF (fSpeedOut < fEps) OR (fSpeedIn < fEps) OR (fLoadInertia < 0.0) THEN
    uErrorId := 16#0002_2601;    // 信息级：转速非正（分母为零风险）或惯量为负 / Info level: nonpositive speed or negative inertia
    RETURN;                      // 不计算返回 / Return without computation
END_IF

// —— 段 3：主计算（分母已过闸） —— //
fRatio := fSpeedIn / fSpeedOut;  // 减速比 i = n_in/n_out / Ratio
IF fRatio < fEps THEN
    uErrorId := 16#0002_2601;    // 信息级：减速比退化近零（疑输入颠倒）/ Info level: degenerate ratio
    RETURN;
END_IF
fInertiaRef := fLoadInertia / (fRatio * fRatio);   // 折算惯量 J_load/i²（i² 非零已过闸）/ Referred inertia
bValid := TRUE;                  // 有效回执 / Validity receipt
FC_DL_GearRatioCalc := fRatio;   // 返回值 = 减速比 / Return equals ratio
END_FUNCTION
