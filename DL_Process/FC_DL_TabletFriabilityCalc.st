(*
  DL Factory R84 | FC_DL_TabletFriabilityCalc
  功能：算片剂脆碎度并扣除测试中粉尘损失，按 ≤1.0% 判合格
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_TabletFriabilityCalc : REAL
VAR_INPUT
    fW0G : REAL := 6.5; // 测试前片重（脱气后） [g] / mass before the test [g]
    fW1G : REAL := 6.45; // 测试后片重（除尘后） [g] / mass after the test [g]
    fDustG : REAL := 0.01; // 粉尘损失扣除量 [g] / dust loss to be deducted [g]
    fLimitPct : REAL := 1.0; // 脆碎度合格上限 [%] / friability acceptance limit [%]
END_VAR
VAR_OUTPUT
    fLossG : REAL; // 净质量损失 [g] / net mass loss [g]
    xPass : BOOL; // 脆碎度判合格 [-] / friability passed [-]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fGrossG : REAL; // 毛质量损失 [g] / gross mass loss [g]
    fFriPct : REAL; // 脆碎度中间量 [%] / friability intermediate [%]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_TabletFriabilityCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fLossG := 0.0; // 净损失预置零 [g] / net loss preset zero [g]
xPass := FALSE; // 合格位预置 FALSE [-] / pass preset false [-]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 质量域闸（R4/R20）
IF NOT (fW0G > -1.0E30 AND fW0G < 1.0E30) OR NOT (fW1G > -1.0E30 AND fW1G < 1.0E30) OR NOT (fDustG > -1.0E30 AND fDustG < 1.0E30) OR NOT (fLimitPct > -1.0E30 AND fLimitPct < 1.0E30) THEN
    RETURN; // 任一入参为 NaN/Inf 一律拒绝 [-] / any NaN or Inf input rejected [-]
END_IF
IF fW0G < 1.0E-9 OR fW1G < 0.0 OR fDustG < 0.0 OR fLimitPct <= 0.0 THEN
    RETURN; // 初重分母闸 + 其余量正域闸 [g, %] / initial mass denominator gate and positive domains [g, %]
END_IF
IF fW1G > fW0G THEN
    RETURN; // 终重大于初重违反质量守恒，拒算 [g] / final above initial violates mass balance [g]
END_IF

// 段 3｜净损失 = 毛损失 − 粉尘扣除（下限钳零）
fGrossG := fW0G - fW1G; // g − g = g / [g] minus [g] = [g]
fLossG := fGrossG - fDustG; // g − g = g / [g] minus [g] = [g]
IF fLossG < 0.0 THEN
    fLossG := 0.0; // 粉尘扣过量时净损失钳零，不产生负脆碎度 [g] / clamp to zero, never negative [g]
END_IF

// 段 4｜脆碎度 = 净损失 / 初重 × 100
fFriPct := (fLossG / fW0G) * 100.0; // g ÷ g × 100 = % / [g] / [g] × 100 = [%]
IF NOT (fFriPct > -1.0E30 AND fFriPct < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF
xPass := fFriPct <= fLimitPct; // 直比上限，禁浮点等值 [-] / direct compare against the limit [-]
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_TabletFriabilityCalc := fFriPct; // 返回脆碎度 [%] / return the friability [%]
END_FUNCTION
