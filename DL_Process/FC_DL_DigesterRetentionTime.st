(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_DigesterRetentionTime
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 消化罐水力停留时间 HRT、固体停留时间 SRT 与容积负荷估算
  口径声明: 容积负荷按进料 VS 浓度假定 25 kg/m3 折算（现场标定前作为默认口径），
            SRT 分母取「废弃污泥流量 + 进料量的 2%（随出流带出固体）」
*)
FUNCTION FC_DL_DigesterRetentionTime : BOOL
VAR_INPUT
    rReactorM3 : REAL; // 反应器有效容积 [m3] / reactor working volume
    rFeedM3Day : REAL; // 进料流量 [m3/d] / feed flow
    rRecycleM3Day : REAL; // 废弃污泥（排泥）流量 [m3/d] / waste sludge flow
END_VAR
VAR_OUTPUT
    rHrtDay : REAL; // 水力停留时间 [d] / hydraulic retention time
    rSrtDay : REAL; // 固体停留时间 [d] / solids retention time
    rLoadingKgM3d : REAL; // 容积有机负荷 [kgVS/(m3·d)] / volumetric organic loading
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    iErrCode : INT; // 事件码 0=正常 1=进料流量非法 2=SRT 小于 HRT 已按 HRT 饱和 3=结果非有限 / event code
END_VAR
VAR CONSTANT
    rVsConcAssumed : REAL := 25.0; // 进料 VS 浓度假定值 [kgVS/m3] / assumed feed VS concentration
    rCarryFrac : REAL := 0.02; // 出流带出固体占进料比 [-] / solids carry-out fraction of feed
END_VAR
VAR
    rQTotalM3d : REAL; // 总吞吐流量 [m3/d] / total through flow
    rQOutM3d : REAL; // 固体出流当量流量 [m3/d] / solids outflow equivalent
    rHrtRaw : REAL; // 未校验 HRT [d] / unchecked HRT
    rSrtRaw : REAL; // 未校验 SRT [d] / unchecked SRT
    rLoadingRaw : REAL; // 未校验负荷 [kgVS/(m3·d)] / unchecked loading
END_VAR

    // —— 段 0：全路径预清 —— //
    rQTotalM3d := 0.0;
    rQOutM3d := 0.0;
    rHrtRaw := 0.0;
    rSrtRaw := 0.0;
    rLoadingRaw := 0.0;
    rHrtDay := 0.0;
    rSrtDay := 0.0;
    rLoadingKgM3d := 0.0;
    bValid := FALSE;
    iErrCode := 0;
    FC_DL_DigesterRetentionTime := FALSE;
    // —— 段 1：分母闸（总吞吐流量 = 进料 + 回流/排泥） —— //
    rQTotalM3d := rFeedM3Day + rRecycleM3Day; // 总吞吐 [m3/d] / total through flow
    IF (rQTotalM3d <= 0.0) OR (rFeedM3Day <= 0.0) THEN
        iErrCode := 1; // 流量非法，停留时间无定义 / invalid flow, retention time undefined
        RETURN;
    END_IF;
    IF rReactorM3 <= 0.0 THEN
        iErrCode := 1; // 容积非法 / invalid volume
        RETURN;
    END_IF;
    // —— 段 2：量纲链 (m3)/(m3/d) = d —— //
    rHrtRaw := rReactorM3 / rQTotalM3d; // HRT [d] / hydraulic retention time
    IF ABS(rHrtRaw) > 1.0E15 THEN
        iErrCode := 3; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    rHrtDay := rHrtRaw;
    // —— 段 3：SRT 分母 = 排泥量 + 进料×2%（分母闸：不得为零） —— //
    rQOutM3d := rRecycleM3Day + rFeedM3Day * rCarryFrac; // 固体出流当量 [m3/d] / solids outflow equivalent
    IF rQOutM3d <= 1.0E-9 THEN
        rSrtDay := rHrtDay; // 无排泥即无固体流出，SRT 退化按 HRT 计 / no wasting, SRT falls back to HRT
        iErrCode := 2; // 信息级：SRT 按 HRT 饱和 / info level: SRT saturated at HRT
    ELSE
        rSrtRaw := rReactorM3 / rQOutM3d; // SRT [d] / solids retention time
        IF ABS(rSrtRaw) > 1.0E15 THEN
            rSrtRaw := rHrtDay; // 非有限兜底 / non-finite fallback
            iErrCode := 3;
        END_IF;
        IF rSrtRaw < rHrtDay THEN
            rSrtDay := rHrtDay; // SRT 不可能小于 HRT，饱和到 HRT / SRT cannot be below HRT
            iErrCode := 2; // 信息级：SRT 参数不自洽 / info level: SRT parameters inconsistent
        ELSE
            rSrtDay := rSrtRaw;
        END_IF
    END_IF;
    // —— 段 4：容积负荷（量纲 (m3/d)×(kg/m3)/(m3) = kg/(m3·d)） —— //
    rLoadingRaw := rFeedM3Day * rVsConcAssumed / rReactorM3; // 容积负荷 [kgVS/(m3·d)] / volumetric loading
    IF ABS(rLoadingRaw) > 1.0E15 THEN
        rLoadingKgM3d := 0.0;
        iErrCode := 3; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    rLoadingKgM3d := rLoadingRaw;
    bValid := TRUE;
    FC_DL_DigesterRetentionTime := TRUE;
END_FUNCTION
