(*
  ==================================================================
  组件名 Component  : FC_DL_PmvComfortIndex
  分类   Category   : DL_Algo
  复杂度 Complexity  : 中
  版本   Version    : 1.0.1
  功能   Purpose    : PMV / PPD 热舒适指标计算（ISO 7730 公开 Fanger 六参数
                      公式链）。输入空气温度 / 平均辐射温度 / 空气流速 / 水
                      蒸汽分压 / 新陈代谢率 / 服装热阻，输出 PMV（钳 ±3）与
                      PPD（0..100%），供 HVAC 优化目标函数使用。
  来源   Source     : t1-oscat-building（热舒适域）
  溯源   Origin     : Fanger PMV 公式与 PPD 映射为 ISO 7730 公开标准公式链，
                      clean-room 自研实现，未复制 OSCAT 或任何厂商私有库
                      源码。
  平台   Platform   : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
  分工声明 Split     : 与 FC_DL_HumidAirEnthalpy 分工——后者做湿空气焓值，本
                      件只做热舒适指标；与 FB_DL_NightPurgeSeq 分工——后者
                      为夜间吹扫顺控，本件为评价指标（无状态纯函数）。
  作者   Author     : 道莅代码库 · PLC 编程专家（R58）
  ------------------------------------------------------------------
  功能说明  : 四段式防御（R45）：预置 → 域闸门（六参数非有限 + ISO 7730 适用
              域：Ta/Tr 10..40 摄氏度，v 0..1 米每秒，pa 0..2.7 千帕，M 46.5..
              232 瓦每平方米，Icl 0..2 克罗，越域钳位信息级）→ 域内迭代求
              服装表面温度 tcl（固定 20 次迭代有界环，不动点收敛，无死循环
              风险）→ 结果非有限复检兜底。
  错误语义  : bError = TRUE 仅故障级（非有限入参）；bClamped = TRUE 信息级
              （六参数越域钳位，返回钳位口径结果）；bValid = TRUE 表示结果
              可用。
  修订记录  : 2026-11-21 v1.0.0 首次入库（R58 批 2 · 序号 6）
              2026-11-21 v1.0.1 R59 返修中①：段 6 补 fPpdPct 非有限/越界复检，拦负底数经 EXPT 的 NaN 穿透
*)
FUNCTION FC_DL_PmvComfortIndex : BOOL
VAR_INPUT
    fTaC   : LREAL; // 空气干球温度 [摄氏度]，域 10..40 / the air dry bulb temperature [degree celsius]
    fTrC   : LREAL; // 平均辐射温度 [摄氏度]，域 10..40 / the mean radiant temperature [degree celsius]
    fVaMs  : LREAL; // 空气流速 [米每秒]，域 0..1 / the air velocity [meter per second]
    fPaKpa : LREAL; // 水蒸汽分压 [千帕]，域 0..2.7 / the water vapour partial pressure [kilopascal]
    fMetW  : LREAL; // 新陈代谢率 [瓦每平方米]，域 46.5..232 / the metabolic rate [watt per square meter]
    fIclClo: LREAL; // 服装热阻 [克罗]，域 0..2 / the clothing insulation [clo]
END_VAR
VAR_OUTPUT
    fPmv    : LREAL; // PMV 预测平均投票（钳 ±3）[无量纲] / the predicted mean vote, clamped
    fPpdPct : LREAL; // PPD 预测不满意百分比 [百分数] / the predicted percentage dissatisfied [percent]
    bValid  : BOOL;  // 结果可用标志 [-] / the result usable flag
    bClamped: BOOL;  // 六参数越域钳位发生（信息级）[-] / an out of domain clamp happened, informational
    bError  : BOOL;  // 故障标志（非有限入参）[-] / the fault flag, a non finite input
END_VAR
VAR
    lrTa   : LREAL; // 空气温度工作量 [摄氏度] / the air temperature work value
    lrTr   : LREAL; // 辐射温度工作量 [摄氏度] / the radiant temperature work value
    lrVa   : LREAL; // 流速工作量 [米每秒] / the velocity work value
    lrPa   : LREAL; // 蒸汽分压工作量 [千帕] / the vapour pressure work value
    lrMet  : LREAL; // 新陈代谢工作量 [瓦每平方米] / the metabolic work value
    lrIcl  : LREAL; // 服装热阻工作量 [克罗] / the insulation work value
    lrMw   : LREAL; // 净机械功（本库取外部功为 0）[瓦每平方米] / the external work, zero in this library
    lrFcl  : LREAL; // 服装面积因子 [无量纲] / the clothing area factor
    lrTcl  : LREAL; // 服装表面温度迭代值 [摄氏度] / the clothing surface temperature iterate
    lrTclN : LREAL; // 服装表面温度下一迭代值 [摄氏度] / the next clothing surface iterate
    lrHc   : LREAL; // 对流换热系数 [瓦每平方米每开尔文] / the convective heat transfer coefficient
    lrLoad : LREAL; // 热负荷项 [瓦每平方米] / the thermal load term
    lrPmvW : LREAL; // PMV 未钳工作量 [无量纲] / the unclamped PMV work value
    nI     : DINT;  // 固定迭代索引 [次] / the fixed iteration index
END_VAR
VAR CONSTANT
    DL_PMV_ITER   : DINT  := 20;                 // 服装温度定点迭代次数 [次]（有界环，无死循环）/ the clothing temperature fixed iterations
    DL_PMV_RELAX  : LREAL := 0.75;               // 迭代松弛因子 [无量纲]，防定点振荡 / the iteration relaxation factor
    DL_PMV_ABSMAX : LREAL := 3.0;                // PMV 出口钳位界 [无量纲] / the PMV clamp bound
    DL_PMV_TAMIN  : LREAL := 10.0;               // 空气温度域下界 [摄氏度] / the air temperature floor
    DL_PMV_TAMAX  : LREAL := 40.0;               // 空气温度域上界 [摄氏度] / the air temperature ceiling
    DL_PMV_VAMAX  : LREAL := 1.0;                // 流速域上界 [米每秒] / the velocity ceiling
    DL_PMV_PAMAX  : LREAL := 2.7;                // 蒸汽分压域上界 [千帕] / the vapour pressure ceiling
    DL_PMV_METMIN : LREAL := 46.5;               // 新陈代谢域下界 [瓦每平方米] / the metabolic floor
    DL_PMV_METMAX : LREAL := 232.0;              // 新陈代谢域上界 [瓦每平方米] / the metabolic ceiling
    DL_PMV_ICLMAX : LREAL := 2.0;                // 服装热阻域上界 [克罗] / the insulation ceiling
END_VAR

// 段 1｜返回值与错误状态预置安全值（四段式第一段，R45）/ segment 1, preset the return and error states
FC_DL_PmvComfortIndex := FALSE; // 受理标志预置假 / preset the accepted flag false
fPmv := 0.0; // PMV 预置中性零 / preset the PMV neutral zero
fPpdPct := 5.0; // PPD 预置下限 5%（PMV = 0 的对应值）/ preset the PPD floor five percent
bValid := FALSE; // 有效标志预置假 / preset the valid flag false
bClamped := FALSE; // 钳位标志预置假 / preset the clamp flag false
bError := FALSE; // 故障标志预置假 / preset the fault flag false

// 段 2｜非有限入参闸（六参数自反双判据全覆盖，R79 / R151）/ segment 2, the non finite gate over the six inputs
IF (fTaC <> fTaC) OR ((fTaC - fTaC) <> (fTaC - fTaC)) THEN // 空气温度非有限 / a non finite air temperature
    bError := TRUE; // 置故障标志（R45 配对）/ raise the fault flag
END_IF
IF (fTrC <> fTrC) OR ((fTrC - fTrC) <> (fTrC - fTrC)) THEN // 辐射温度非有限 / a non finite radiant temperature
    bError := TRUE; // 置故障标志 / raise the fault flag
END_IF
IF (fVaMs <> fVaMs) OR ((fVaMs - fVaMs) <> (fVaMs - fVaMs)) THEN // 流速非有限 / a non finite velocity
    bError := TRUE; // 置故障标志 / raise the fault flag
END_IF
IF (fPaKpa <> fPaKpa) OR ((fPaKpa - fPaKpa) <> (fPaKpa - fPaKpa)) THEN // 蒸汽分压非有限 / a non finite vapour pressure
    bError := TRUE; // 置故障标志 / raise the fault flag
END_IF
IF (fMetW <> fMetW) OR ((fMetW - fMetW) <> (fMetW - fMetW)) THEN // 新陈代谢非有限 / a non finite metabolic rate
    bError := TRUE; // 置故障标志 / raise the fault flag
END_IF
IF (fIclClo <> fIclClo) OR ((fIclClo - fIclClo) <> (fIclClo - fIclClo)) THEN // 服装热阻非有限 / a non finite insulation
    bError := TRUE; // 置故障标志 / raise the fault flag
END_IF
IF bError THEN // 非有限命中：返回预置安全值 / a non finite hit, return the preset safe values
    RETURN; // 早退 / return early
END_IF

// 段 3｜ISO 7730 适用域钳位（信息级，越域判据按方向分列 R146）/ segment 3, the applicability clamps, informational
lrTa := fTaC; // 装空气温度 / load the air temperature
IF lrTa < DL_PMV_TAMIN THEN // 低于下界 / below the floor
    lrTa := DL_PMV_TAMIN; // 钳到下界 / clamp to the floor
    bClamped := TRUE; // 信息级钳位 / the informational clamp
ELSIF lrTa > DL_PMV_TAMAX THEN // 高于上界 / above the ceiling
    lrTa := DL_PMV_TAMAX; // 钳到上界 / clamp to the ceiling
    bClamped := TRUE; // 信息级钳位 / the informational clamp
END_IF
lrTr := fTrC; // 装辐射温度 / load the radiant temperature
IF lrTr < DL_PMV_TAMIN THEN // 低于下界 / below the floor
    lrTr := DL_PMV_TAMIN; // 钳到下界 / clamp to the floor
    bClamped := TRUE; // 信息级钳位 / the informational clamp
ELSIF lrTr > DL_PMV_TAMAX THEN // 高于上界 / above the ceiling
    lrTr := DL_PMV_TAMAX; // 钳到上界 / clamp to the ceiling
    bClamped := TRUE; // 信息级钳位 / the informational clamp
END_IF
lrVa := fVaMs; // 装流速 / load the velocity
IF lrVa < 0.0 THEN // 负流速（物理不可达，钳零）/ a negative velocity, clamped to zero
    lrVa := 0.0; // 钳到零 / clamp to zero
    bClamped := TRUE; // 信息级钳位 / the informational clamp
ELSIF lrVa > DL_PMV_VAMAX THEN // 高于上界 / above the ceiling
    lrVa := DL_PMV_VAMAX; // 钳到上界 / clamp to the ceiling
    bClamped := TRUE; // 信息级钳位 / the informational clamp
END_IF
lrPa := fPaKpa; // 装蒸汽分压 / load the vapour pressure
IF lrPa < 0.0 THEN // 负分压钳零 / a negative pressure clamped to zero
    lrPa := 0.0; // 钳到零 / clamp to zero
    bClamped := TRUE; // 信息级钳位 / the informational clamp
ELSIF lrPa > DL_PMV_PAMAX THEN // 高于上界 / above the ceiling
    lrPa := DL_PMV_PAMAX; // 钳到上界 / clamp to the ceiling
    bClamped := TRUE; // 信息级钳位 / the informational clamp
END_IF
lrMet := fMetW; // 装新陈代谢率 / load the metabolic rate
IF lrMet < DL_PMV_METMIN THEN // 低于下界 / below the floor
    lrMet := DL_PMV_METMIN; // 钳到下界 / clamp to the floor
    bClamped := TRUE; // 信息级钳位 / the informational clamp
ELSIF lrMet > DL_PMV_METMAX THEN // 高于上界 / above the ceiling
    lrMet := DL_PMV_METMAX; // 钳到上界 / clamp to the ceiling
    bClamped := TRUE; // 信息级钳位 / the informational clamp
END_IF
lrIcl := fIclClo; // 装服装热阻 / load the insulation
IF lrIcl < 0.0 THEN // 负热阻钳零 / a negative insulation clamped to zero
    lrIcl := 0.0; // 钳到零 / clamp to zero
    bClamped := TRUE; // 信息级钳位 / the informational clamp
ELSIF lrIcl > DL_PMV_ICLMAX THEN // 高于上界 / above the ceiling
    lrIcl := DL_PMV_ICLMAX; // 钳到上界 / clamp to the ceiling
    bClamped := TRUE; // 信息级钳位 / the informational clamp
END_IF

// 段 4｜服装面积因子与服装表面温度定点迭代（固定 20 次有界环）/ segment 4, the area factor and the clothing temperature iteration
IF lrIcl <= 0.5 THEN // 低热阻面积因子分支（ISO 7730 公开分段）/ the low insulation branch
    lrFcl := 1.0 + 0.2 * lrIcl; // 面积因子 / the area factor
ELSE // 高热阻面积因子分支 / the high insulation branch
    lrFcl := 1.05 + 0.1 * lrIcl; // 面积因子 / the area factor
END_IF
lrTcl := lrTa; // 迭代初值取空气温度（安全侧收敛起点）/ the iterate starts at the air temperature
lrMw := 0.0; // 本库外部机械功取零（坐立轻活动场景）/ the external work is zero in this library
FOR nI := 1 TO DL_PMV_ITER DO // 固定界迭代环，无死循环风险 / the fixed bound iteration loop
    lrHc := 12.1 * SQRT(lrVa); // 对流换热候选一（流速项）/ the convective candidate one
    IF 2.38 * EXPT(ABS(lrTcl - lrTa), 0.25) > lrHc THEN // 候选二更大则取大（ISO 7730 取大规则）/ take the larger candidate
        lrHc := 2.38 * EXPT(ABS(lrTcl - lrTa), 0.25); // 取候选二 / take the candidate two
    END_IF
    lrTclN := 35.7 - 0.028 * (lrMet - lrMw) - 0.155 * lrIcl * (3.96E-8 * lrFcl * (EXPT(lrTcl + 273.15, 4.0) - EXPT(lrTr + 273.15, 4.0)) + lrFcl * lrHc * (lrTcl - lrTa)); // ISO 7730 标准隐式定点式（右端含 tcl，靠固定环迭代收敛）/ the ISO 7730 implicit fixed point form, converged by the fixed loop
    lrTcl := lrTcl + DL_PMV_RELAX * (lrTclN - lrTcl); // 松弛更新 / the relaxed update
END_FOR

// 段 5｜PMV 主式与 PPD 映射（ISO 7730 公开公式链）/ segment 5, the PMV formula and the PPD mapping
lrHc := 12.1 * SQRT(lrVa); // 出口段对流系数重算（与迭代末值口径一致）/ the outlet convective coefficient
IF 2.38 * EXPT(ABS(lrTcl - lrTa), 0.25) > lrHc THEN // 取大规则 / the larger rule
    lrHc := 2.38 * EXPT(ABS(lrTcl - lrTa), 0.25); // 取候选二 / take the candidate two
END_IF
lrLoad := (lrMet - lrMw) // 热负荷项组装（Fanger 展开式）/ assemble the thermal load
        - 3.05E-3 * (5733.0 - 6.99 * (lrMet - lrMw) - lrPa * 1000.0) // 呼吸显热项（分压换算帕）/ the respiration sensible term
        - 0.42 * ((lrMet - lrMw) - 58.15) // 呼吸潜热项 / the respiration latent term
        - 1.7E-5 * lrMet * (5867.0 - lrPa * 1000.0) // 皮肤蒸发项 / the skin evaporation term
        - 0.0014 * lrMet * (34.0 - lrTa) // 皮肤对流项 / the skin convection term
        - 3.96E-8 * lrFcl * (EXPT(lrTcl + 273.15, 4.0) - EXPT(lrTr + 273.15, 4.0)) // 辐射项 / the radiation term
        - lrFcl * lrHc * (lrTcl - lrTa); // 服装对流项 / the clothing convection term
lrPmvW := (0.303 * EXP(-0.036 * lrMet) + 0.028) * lrLoad; // PMV 权重式 / the PMV weighted form
IF lrPmvW > DL_PMV_ABSMAX THEN // PMV 上钳 / clamp the PMV up
    fPmv := DL_PMV_ABSMAX; // 钳到上界 / clamp to the bound
ELSIF lrPmvW < -DL_PMV_ABSMAX THEN // PMV 下钳 / clamp the PMV down
    fPmv := -DL_PMV_ABSMAX; // 钳到下界 / clamp to the bound
ELSE // 域内直通 / inside the domain
    fPmv := lrPmvW; // 直通结果 / pass through
END_IF
fPpdPct := 100.0 - 95.0 * EXP(-0.03353 * EXPT(fPmv, 4.0) - 0.2179 * fPmv * fPmv); // PPD 映射式 / the PPD mapping

// 段 6｜结果非有限复检兜底（防御纵深，正常路径不可达）/ segment 6, the result recheck as defense in depth
IF (fPmv <> fPmv) OR ((fPmv - fPmv) <> (fPmv - fPmv)) THEN // PMV 非有限 / a non finite PMV
    fPmv := 0.0; // 归中性零 / zero to the neutral
    fPpdPct := 5.0; // PPD 回下限 / the PPD to the floor
    bValid := FALSE; // 降有效标志 / drop the valid flag
    RETURN; // 早退（受理标志保持假）/ return early, refused
END_IF
// R59 修 R58 中①：fPpdPct 复检三件套（负底数经 EXPT(fPmv,4.0) 可产生 NaN 穿透，PMV 复检不覆盖本输出）
IF (fPpdPct <> fPpdPct) OR ((fPpdPct - fPpdPct) <> (fPpdPct - fPpdPct)) THEN // PPD 非有限（NOT ISFINITE 等价自反判式）/ a non finite PPD
    fPpdPct := 5.0; // 回安全下限 / to the safe floor
    bValid := FALSE; // 降有效标志 / drop the valid flag
    RETURN; // 早退（受理标志保持假）/ return early, refused
END_IF
IF fPpdPct < 0.0 THEN // 负 PPD 钳零（信息级）/ a negative PPD clamped to zero
    fPpdPct := 0.0; bClamped := TRUE; // 钳到下界 0 并置信息级 / clamp to the floor zero
ELSIF fPpdPct > 100.0 THEN // 越上界回夹到 [0,100] / above the ceiling, re-clamped into the band
    fPpdPct := 100.0; bClamped := TRUE; // 钳到上界 100 并置信息级 / clamp to the ceiling hundred
END_IF
bValid := TRUE; // 结果可用 / the result usable
FC_DL_PmvComfortIndex := TRUE; // 求解受理 / accept the result
END_FUNCTION
