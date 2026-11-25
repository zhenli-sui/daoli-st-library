// FC_DL_FermentAttenuationCalc v1.0.0
// 开源溯源：clean-room 自研（族 DL_Process，ST 生态实测 0 命中，无外部代码引入）
(*
  功能: 表观发酵度 = 100·(原浓 − 表观浓)/原浓 [%]；酒精度 ≈ (原浓 − 表观浓)·0.51 [%v/v]
        （0.51 为工程换算因数，非严格蒸馏法值）。发酵度超 95% 判化验异常。
  邻件/码位: 是进入双乙酰还原升温的前置判据，与 FC_DL_WortBoilEvaporationCalc 的原浓定标耦合；
             16#0002_9234 = 非有限、原浓非正、表观浓大于原浓或为负、发酵度超 95% 拒收。
*)
FUNCTION FC_DL_FermentAttenuationCalc : REAL
VAR_INPUT
    fOrigExtract     : REAL := 12.0;    // 原麦汁浓度 [°P]，域 > 0 / Original extract [degP]
    fApparentExtract : REAL := 3.0;     // 表观浓度 [°P]，域 <= 原浓 / Apparent extract [degP]
END_VAR
VAR_OUTPUT
    fApparentAtten : REAL;              // 表观发酵度 [%]，域 <= 95 / Apparent attenuation [%]
    fAlcoholVol    : REAL;              // 酒精度 [%v/v] / Alcohol by volume [%v/v]
    bValid         : BOOL;              // 结果有效回执 [-] / Result validity receipt
    uErrorId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
// 段 0：全路径出口安全缺省 / Safe defaults on all outlets
fApparentAtten := 0.0;                  // 发酵度缺省零 / Attenuation default zero
fAlcoholVol := 0.0;                     // 酒精度缺省零 / Alcohol default zero
bValid := FALSE;                        // 有效回执预清 / Validity preset clear
uErrorId := 16#0000;                    // 事件码预清 / Event code preset clear
FC_DL_FermentAttenuationCalc := 0.0;    // 返回值缺省零（镜像发酵度）/ Return default zero
// 段 1：非有限闸（两入参全枚举）/ Non-finite gate over all inputs
IF (fOrigExtract <> fOrigExtract) OR (fApparentExtract <> fApparentExtract)
   OR (ABS(fOrigExtract) >= 3.0E38) OR (ABS(fApparentExtract) >= 3.0E38) THEN
    uErrorId := 16#0002_9234;   // 入参非有限拒收 / Non-finite input reject
    RETURN;
END_IF
// 段 2：域闸（原浓为正防除零 + 表观浓不得大于原浓，R4）/ Domain gate
IF fOrigExtract <= 1.0E-6 THEN
    uErrorId := 16#0002_9234;   // 原浓非正 / Non-positive original extract
    RETURN;
END_IF
IF fApparentExtract > fOrigExtract THEN
    uErrorId := 16#0002_9234;   // 表观浓大于原浓，发酵不可为负 / Apparent above original
    RETURN;
END_IF
IF fApparentExtract < 0.0 THEN
    uErrorId := 16#0002_9234;   // 表观浓度为负 / Negative apparent extract
    RETURN;
END_IF
// 段 3：主计算（发酵度 → 酒精度）/ Main computation
fApparentAtten := 100.0 * (fOrigExtract - fApparentExtract) / fOrigExtract;  // 发酵度 [%] / Attenuation
fAlcoholVol := (fOrigExtract - fApparentExtract) * 0.51;                     // 酒精度 [%v/v] / Alcohol
// 段 4：出口闸（双输出非有限复核 + 95% 上限判定）/ Outlet gate
IF (fApparentAtten <> fApparentAtten) OR (fAlcoholVol <> fAlcoholVol)
   OR (ABS(fApparentAtten) >= 3.0E38) OR (ABS(fAlcoholVol) >= 3.0E38)
   OR (fApparentAtten < 0.0) OR (fAlcoholVol < 0.0) THEN
    fApparentAtten := 0.0;      // 复核失败回缺省 / Fallback on recheck failure
    fAlcoholVol := 0.0;         // 复核失败回缺省 / Fallback on recheck failure
    uErrorId := 16#0002_9234;   // 出口复核拒收 / Output recheck reject
    RETURN;
END_IF
IF fApparentAtten > 95.0 THEN
    uErrorId := 16#0002_9234;   // 信息级：发酵度超 95% 判化验异常 / Info: attenuation above 95
    RETURN;                     // bValid 保持 FALSE / Validity stays false
END_IF
bValid := TRUE;                 // 有效回执 / Validity receipt
FC_DL_FermentAttenuationCalc := fApparentAtten;     // 返回值镜像发酵度 / Return mirrors attenuation
END_FUNCTION
