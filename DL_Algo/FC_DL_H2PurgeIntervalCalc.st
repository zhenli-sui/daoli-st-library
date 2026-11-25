(*
  DL Factory R88 | FC_DL_H2PurgeIntervalCalc
  功能：按阳极容积与杂质累积速率算吹扫周期 t=V·r_imp/(η_purge·Q_H2)，超 30 min 提示吹扫过疏
  开源溯源：无（clean-room 自研，依据公开工艺公式 杂质累积-吹扫置换平衡式 t=V·Δc/(c_prod·Q)，许可证=MIT，借鉴点=公式结构）
  规则：R1-R16 全遵守；R88 简单件标量形（纯标量入参出参，无循环体、无方法、无属性、无数组）
*)
FUNCTION FC_DL_H2PurgeIntervalCalc : REAL
VAR_INPUT
    fAnodeVolL : REAL := 20.0; // 阳极侧气体容积 V_anode [L] / anode gas volume [L]
    fImpurityRatePct : REAL := 1.0; // 杂质累积速率（每周期占容积的分数，工程近似） [%/周期] / impurity build up per cycle [pct]
    fPurgeEffPct : REAL := 60.0; // 单次吹扫置换效率 η_purge [%] / purge replacement efficiency [pct]
    fH2FlowLpm : REAL := 10.0; // 吹扫氢气流量 Q_H2（标准状态） [L/min] / purge hydrogen flow [L/min]
    fMaxMin : REAL := 30.0; // 吹扫周期上限（超过则杂质可能超限） [min] / maximum purge interval [min]
END_VAR
VAR_OUTPUT
    fIntervalMin : REAL; // 吹扫周期 t [min] / purge interval [min]
    xTooLong : BOOL; // TRUE=周期超过上限，吹扫过疏 [-] / TRUE when the interval is too long [-]
END_VAR
VAR
    fDenom : REAL; // 分母 η_purge·Q_H2（除零判据） [%·L/min] / denominator, the divisor [pct*L/min]
    fImpVolL : REAL; // 单周期杂质累积体积（近似） [L] / impurity volume per cycle [L]
END_VAR

// 段 1｜出口预置
FC_DL_H2PurgeIntervalCalc := -1.0; // 哨兵返回 -1（无效） [-] / sentinel return -1, invalid [-]
fIntervalMin := 0.0; // 吹扫周期预置零 [min] / interval preset zero [min]
xTooLong := FALSE; // 过疏位预置 FALSE（未判定前不报警） [-] / too-long flag preset false [-]

// 段 2｜非有限拦截 + 域闸
IF NOT (fAnodeVolL > -1.0E30 AND fAnodeVolL < 1.0E30) OR NOT (fImpurityRatePct > -1.0E30 AND fImpurityRatePct < 1.0E30) OR NOT (fPurgeEffPct > -1.0E30 AND fPurgeEffPct < 1.0E30) THEN
    RETURN; // 容积/杂质速率/置换效率任一非有限即拒算 [-] / any non finite input rejected [-]
END_IF
IF NOT (fH2FlowLpm > -1.0E30 AND fH2FlowLpm < 1.0E30) OR NOT (fMaxMin > -1.0E30 AND fMaxMin < 1.0E30) THEN
    RETURN; // 吹扫流量/周期上限任一非有限则判据静默失效，故先拦 [-] / these pins must be finite [-]
END_IF
IF fAnodeVolL < 1.0E-9 OR fImpurityRatePct <= 0.0 OR fH2FlowLpm < 1.0E-9 THEN
    RETURN; // 容积/杂质速率正域闸 + 吹扫流量正域闸（分母不得为零） [L, %, L/min] / positive gates
END_IF
IF fPurgeEffPct <= 0.0 OR fPurgeEffPct > 100.0 OR fMaxMin <= 0.0 THEN
    RETURN; // 置换效率开区间闸 (0,100] + 周期上限正域闸 [%, min] / efficiency and limit gates
END_IF

// 段 3｜计算（工程近似式：杂质按容积分数线性累积，忽略反应消耗与扩散）
fImpVolL := fAnodeVolL * fImpurityRatePct * 0.01; // L × % × 0.01 = L，单周期杂质体积 [L] / [L] impurity per cycle [L]
fDenom := (fPurgeEffPct * 0.01) * fH2FlowLpm; // %×0.01 得无量纲效率 λ × (L/min) = L/min，分母 [L/min] / [-] x [L/min] = [L/min]
IF fDenom < 1.0E-9 THEN
    RETURN; // 除法前分母闸：η·Q 必须大于 1E-9 才可作除数 [%·L/min] / denominator gate [pct*L/min]
END_IF
fIntervalMin := fImpVolL / fDenom; // L ÷ (L/min) = min，量纲自洽（R88 修正：效率先归一化） [min] / [L] / [L/min] = [min]

// 段 4｜判定与饱和
IF NOT (fIntervalMin > -1.0E30 AND fIntervalMin < 1.0E30) THEN
    RETURN; // 结果非有限再拦一次 [-] / re-check the result for finiteness [-]
END_IF
xTooLong := fIntervalMin > fMaxMin; // 严格大于上限为过疏，等于上限仍判合格 [min] / strict compare [min]

// 段 5｜出口自检
IF fIntervalMin < 0.0 THEN
    RETURN; // 出口自检：周期不得为负（负值说明输入符号错） [min] / interval must not be negative [min]
END_IF
FC_DL_H2PurgeIntervalCalc := fIntervalMin; // 返回吹扫周期 [min] / return the purge interval [min]
END_FUNCTION
