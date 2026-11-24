(*
  DL Factory R84 | FC_DL_ClinkerFreeLimeCalc
  功能：融合化学法与在线估算得游离石灰含量，按 ≤1.5% 判合格并给烧成度分级
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守
*)
FUNCTION FC_DL_ClinkerFreeLimeCalc : REAL
VAR_INPUT
    fCaOLabPct : REAL := -1.0; // 化学法实测 f-CaO（负值表示本次无化验值） [%] / lab free lime, negative means not available [%]
    fCaOEstPct : REAL := 1.2; // 在线估算 f-CaO [%] / online estimated free lime [%]
    fLabWeight : REAL := 0.7; // 化验值权重（0~1） [-] / laboratory weight [0,1]
    fLimitPct : REAL := 1.5; // 合格上限 [%] / acceptance limit [%]
    fUnderLoPct : REAL := 0.5; // 过烧判据下限（低于即判过烧） [%] / overburn lower bound [%]
END_VAR
VAR_OUTPUT
    iBurnGrade : INT; // 烧成度分级 0=过烧 1=正常 2=欠烧 [-] / burning grade [-]
    xPass : BOOL; // f-CaO 判合格 [-] / free lime passed [-]
    xValid : BOOL; // 计算结果有效标志 [-] / calculation valid flag [-]
END_VAR
VAR
    fW : REAL; // 实际采用权重（钳位后） [-] / effective weight after clamping [-]
    fCaOPct : REAL; // 融合后 f-CaO [%] / fused free lime [%]
END_VAR

// 段 1｜出口预置（R256）
FC_DL_ClinkerFreeLimeCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
iBurnGrade := 1; // 分级预置正常 [-] / grade preset to normal [-]
xPass := FALSE; // 合格位预置 FALSE [-] / pass preset false [-]
xValid := FALSE; // 计算完成前不认结果 [-] / unusable before calculation [-]

// 段 2｜非有限拦截 + 域闸（R4/R20）
IF NOT (fCaOLabPct > -1.0E30 AND fCaOLabPct < 1.0E30) OR NOT (fCaOEstPct > -1.0E30 AND fCaOEstPct < 1.0E30) OR NOT (fLabWeight > -1.0E30 AND fLabWeight < 1.0E30) THEN
    RETURN; // 化验值/估算值/权重任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF fCaOEstPct < 0.0 OR NOT (fLimitPct > -1.0E30 AND fLimitPct < 1.0E30) OR NOT (fUnderLoPct > -1.0E30 AND fUnderLoPct < 1.0E30) THEN
    RETURN; // 估算值非负 + 阈值有限闸 [%] / non negative estimate and finite thresholds [%]
END_IF
IF fLimitPct <= 0.0 OR fUnderLoPct < 0.0 OR NOT (fUnderLoPct < fLimitPct) THEN
    RETURN; // 阈值组态闸：0 ≤ 过烧下限 < 合格上限 [%] / threshold config gate [%]
END_IF

// 段 3｜权重钳位与融合（化验值缺失时权重强制归零）
fW := fLabWeight; // 无量纲权重 [-] / dimensionless weight [-]
IF fCaOLabPct < 0.0 THEN
    fW := 0.0; // 无化验值：全部采用在线估算 [-] / no lab value, use the estimate only [-]
END_IF
IF fW > 1.0 THEN
    fW := 1.0; // 权重上限钳位 [-] / clamp the weight high [-]
END_IF
IF fW < 0.0 THEN
    fW := 0.0; // 权重下限钳位 [-] / clamp the weight low [-]
END_IF
IF fW >= 1.0 THEN
    fCaOPct := fCaOLabPct; // 全信化验值 [%] / trust the lab value entirely [%]
ELSE
    fCaOPct := (fCaOLabPct * fW) + (fCaOEstPct * (1.0 - fW)); // % × - + % × - = % / [%] × [-] + [%] × [-] = [%]
END_IF
IF NOT (fCaOPct > -1.0E30 AND fCaOPct < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / second finiteness gate [-]
END_IF

// 段 4｜合格判定与烧成度分级（f-CaO 高=欠烧，低=过烧）
IF fCaOPct > fLimitPct THEN
    iBurnGrade := 2; // 欠烧：f-CaO 超上限 [-] / underburnt, free lime above the limit [-]
    xPass := FALSE; // 不合格 [-] / fail [-]
ELSIF fCaOPct < fUnderLoPct THEN
    iBurnGrade := 0; // 过烧：f-CaO 过低（浪费热耗） [-] / overburnt, free lime too low [-]
    xPass := TRUE; // 仍判合格（质量达标，但需节能） [-] / still passing on quality [-]
ELSE
    iBurnGrade := 1; // 正常区间 [-] / normal band [-]
    xPass := TRUE; // 合格 [-] / pass [-]
END_IF
xValid := TRUE; // 链路有效 [-] / chain valid [-]
FC_DL_ClinkerFreeLimeCalc := fCaOPct; // 返回游离石灰 [%] / return the free lime [%]
END_FUNCTION
