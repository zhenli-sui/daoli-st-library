(*
  DL Factory R84 | FC_DL_RawMealResidueCalc
  功能：生料 80µm/200µm 双档筛余与细度系数，按目标带判合格并给磨机加减料建议
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_RawMealResidueCalc : REAL
VAR_INPUT
    fRes80 : REAL := 14.0; // 80µm 筛余 [%] / residue on the 80 micron sieve [%]
    fRes200Um : REAL := 1.8; // 200µm 筛余实测值 [%] / residue on the 200 micron sieve [%]
    fLo80 : REAL := 10.0; // 80µm 筛余合格下限 [%] / lower acceptance bound [%]
    fHi80 : REAL := 18.0; // 80µm 筛余合格上限 [%] / upper acceptance bound [%]
END_VAR
VAR_OUTPUT
    fRes200 : REAL; // 200µm 筛余回显（链路校验） [%] / 200 micron residue echo [%]
    iAdvice : INT; // 磨机建议 1=加料 0=保持 −1=减料 [-] / mill advice [-]
    xPass : BOOL; // 细度判合格 [-] / fineness passed [-]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fFinCoef : REAL; // 细度系数（80µm/200µm 比值） [-] / fineness coefficient [-]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_RawMealResidueCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fRes200 := 0.0; // 200µm 筛余回显预置零 [%] / residue echo preset zero [%]
iAdvice := 0; // 建议预置保持 [-] / advice preset to hold [-]
xPass := FALSE; // 合格位预置 FALSE [-] / pass preset false [-]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 域闸（R4/R20）
IF NOT (fRes80 > -1.0E30 AND fRes80 < 1.0E30) OR NOT (fRes200Um > -1.0E30 AND fRes200Um < 1.0E30) OR NOT (fLo80 > -1.0E30 AND fLo80 < 1.0E30) OR NOT (fHi80 > -1.0E30 AND fHi80 < 1.0E30) THEN
    RETURN; // 任一入参为 NaN/Inf 一律拒绝 [-] / any NaN or Inf input rejected [-]
END_IF
IF fRes80 < 0.0 OR fRes200Um < 0.0 OR fRes80 > 100.0 OR fRes200Um > 100.0 THEN
    RETURN; // 筛余百分比域闸 (0~100) [%] / residue percentage domain gate [%]
END_IF
IF NOT (fLo80 < fHi80) THEN
    RETURN; // 目标带组态闸：下限必须严格小于上限 [%] / acceptance band config gate [%]
END_IF

// 段 3｜细度系数（200µm 筛余趋零时按极小值兜底）
fFinCoef := fRes80 / MAX(fRes200Um, 1.0E-9); // % ÷ % = 无量纲（比值越大即粗颗粒占比越集中） / [%] / [%] = [-]
IF NOT (fFinCoef > -1.0E30 AND fFinCoef < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF

// 段 4｜合格判定与磨机建议（筛余偏高=偏粗→减料；偏低=偏细→加料）
IF fRes80 > fHi80 THEN
    iAdvice := -1; // 偏粗：建议减料（提高粉磨细度） [-] / coarse, reduce the feed [-]
    xPass := FALSE; // 超上限不合格 [-] / above the band, fail [-]
ELSIF fRes80 < fLo80 THEN
    iAdvice := 1; // 偏细：建议加料（提高产量） [-] / fine, increase the feed [-]
    xPass := FALSE; // 低于下限同样不合格（细度即电耗） [-] / below the band, fail [-]
ELSE
    iAdvice := 0; // 带内：保持当前喂料 [-] / in band, hold the feed [-]
    xPass := TRUE; // 带内合格 [-] / in band, pass [-]
END_IF
fRes200 := fRes200Um; // 回显 200µm 筛余实测值（校验链路量） [%] / echo the 200 micron residue [%]
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_RawMealResidueCalc := fRes80; // 返回 80µm 筛余 [%] / return the 80 micron residue [%]
END_FUNCTION
