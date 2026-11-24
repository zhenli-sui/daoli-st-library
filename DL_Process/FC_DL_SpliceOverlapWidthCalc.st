(*
  DL Factory R83 | FC_DL_SpliceOverlapWidthCalc
  功能：按幅宽与搭接比例算接卷搭接宽度，并给出单次接卷胶带总长度。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_SpliceOverlapWidthCalc : REAL
VAR_INPUT
    fWebWidthMm : REAL; // 料带幅宽 [mm] / Web width [mm]
    fTensionN   : REAL; // 接卷张力 [N] / Splicing tension [N]
    fSpeedMpm   : REAL; // 接卷瞬间线速度 [m/min] / Line speed at splice [m/min]
    fOverlapPct : REAL; // 搭接比例（占幅宽，0~100）[%] / Overlap ratio of web width [%]
END_VAR
VAR_OUTPUT
    fOverlapMm : REAL; // 搭接宽度 [mm] / Overlap width [mm]
    fTapeLenMm : REAL; // 单次接卷胶带总长（双侧+封边余量）[mm] / Total tape length [mm]
    xValid     : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
VAR
    fTensK   : REAL; // 张力修正系数 [-]/ Tension correction factor
    fSpeedK  : REAL; // 速度修正系数 [-]/ Speed correction factor
    cTapeEnd : REAL := 50.0; // 封边余量常量 [mm]，下方已引用（R19）/ Tape end allowance [mm]
END_VAR
// 出口预置：三出口统一预置（R256）
fOverlapMm := 0.0; fTapeLenMm := 0.0; xValid := FALSE;
// 非有限拦截 + 量纲自检（R20/R21）
IF NOT (fWebWidthMm > -1.0E30 AND fWebWidthMm < 1.0E30) OR NOT (fTensionN > -1.0E30 AND fTensionN < 1.0E30) OR NOT (fSpeedMpm > -1.0E30 AND fSpeedMpm < 1.0E30) OR NOT (fOverlapPct > -1.0E30 AND fOverlapPct < 1.0E30) OR fWebWidthMm <= 0.0 OR fOverlapPct <= 0.0 THEN
    FC_DL_SpliceOverlapWidthCalc := -1.0; RETURN;  // 哨兵 -1：非有限或量纲越界 / Sentinel -1
END_IF
// 搭接比例域闸：上限 50%（超过即为整幅贴合，工艺不允许）
IF fOverlapPct > 50.0 THEN
    fOverlapPct := 50.0;            // 比例上限钳位 [%] / Clamp ratio to 50 percent
END_IF
// 修正系数：张力与速度越高，搭接需加宽以抗剥离（两项均为无量纲比值）
fTensK  := 1.0 + fTensionN / 2000.0;   // 张力修正，2000 N 对应 +100% [-] / Tension correction
fSpeedK := 1.0 + fSpeedMpm / 5000.0;   // 速度修正，5000 m/min 对应 +100% [-] / Speed correction
// 搭接宽度：幅宽 × 比例 × 双修正（mm × 无量纲 × 无量纲 = mm）
fOverlapMm := fWebWidthMm * (fOverlapPct / 100.0) * fTensK * fSpeedK; // 搭接宽度 [mm] / Overlap
// 胶带总长：上下两条主胶带 + 两端封边余量（mm）
fTapeLenMm := 2.0 * fOverlapMm + cTapeEnd;     // 胶带总长 [mm] / Total tape length [mm]
xValid     := TRUE;                            // 链路有效 / Chain valid
FC_DL_SpliceOverlapWidthCalc := fOverlapMm;    // 返回搭接宽度 [mm] / Return overlap width [mm]
END_FUNCTION
