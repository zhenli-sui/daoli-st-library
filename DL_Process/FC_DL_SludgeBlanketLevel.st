(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_SludgeBlanketLevel
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 双压力变送器静压差法反算污泥界面（泥位）高度，含密度差可测性与量程限幅
*)
FUNCTION FC_DL_SludgeBlanketLevel : BOOL
VAR_INPUT
    rP1Bar : REAL; // 上取压点压力 [bar] / upper tap pressure in bar
    rP2Bar : REAL; // 下取压点压力 [bar] / lower tap pressure in bar
    rRhoSludge : REAL; // 污泥混合液密度 [kg/m3] / sludge mixture density
    rRhoWater : REAL; // 上清液密度 [kg/m3] / supernatant density
    rSpanM : REAL; // 取压点间距（量程）[m] / tap spacing, i.e. measuring span
END_VAR
VAR_OUTPUT
    rLevelM : REAL; // 泥位高度（自下取压点起）[m] / sludge blanket level above lower tap
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    iErrCode : INT; // 事件码 0=正常 1=密度差过小不可测 2=量程非法 3=结果非有限 / event code
END_VAR
VAR CONSTANT
    rBarToPa : REAL := 1.0E5; // 巴转帕系数 [Pa/bar] / bar to pascal factor
    rGravity : REAL := 9.80665; // 标准重力加速度 [m/s2] / standard gravity
    rRhoDiffMin : REAL := 1.0; // 密度差可测下限 [kg/m3] / minimum measurable density difference
END_VAR
VAR
    rDpPa : REAL; // 压差 [Pa] / differential pressure in pascal
    rRhoDiff : REAL; // 有效密度差 [kg/m3] / effective density difference
    rLevelRaw : REAL; // 未限幅泥位 [m] / unlimited level
END_VAR

    // —— 段 0：全路径预清 —— //
    rDpPa := 0.0;
    rRhoDiff := 0.0;
    rLevelRaw := 0.0;
    rLevelM := 0.0;
    bValid := FALSE;
    iErrCode := 0;
    FC_DL_SludgeBlanketLevel := FALSE;
    // —— 段 1：量程闸 —— //
    IF rSpanM <= 0.0 THEN
        iErrCode := 2; // 量程非法，无物理意义 / invalid span, unphysical
        RETURN;
    END_IF;
    // —— 段 2：密度差可测性闸（分母闸） —— //
    rRhoDiff := rRhoSludge - rRhoWater; // 有效密度差 [kg/m3] / effective density difference
    IF ABS(rRhoDiff) < rRhoDiffMin THEN
        iErrCode := 1; // 密度差过小，压差法不可测 / density difference too small to resolve
        RETURN;
    END_IF;
    // —— 段 3：量纲链 (bar)*(Pa/bar) = Pa；(Pa)/((kg/m3)*(m/s2)) = m —— //
    rDpPa := (rP2Bar - rP1Bar) * rBarToPa; // 压差 [Pa] / differential pressure
    rLevelRaw := rDpPa / (rRhoDiff * rGravity); // 泥位 [m] / blanket level
    IF ABS(rLevelRaw) > 1.0E15 THEN
        iErrCode := 3; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    // —— 段 4：限幅 [0, rSpanM] —— //
    IF rLevelRaw < 0.0 THEN
        rLevelM := 0.0; // 负泥位无意义（取压反接或空池）/ negative level meaningless, clamp to zero
    ELSIF rLevelRaw > rSpanM THEN
        rLevelM := rSpanM; // 超量程饱和到取压间距 / saturate at tap spacing
    ELSE
        rLevelM := rLevelRaw;
    END_IF;
    bValid := TRUE;
    FC_DL_SludgeBlanketLevel := TRUE;
END_FUNCTION
