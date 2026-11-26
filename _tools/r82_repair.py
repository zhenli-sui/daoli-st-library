# -*- coding: utf-8 -*-
"""R82 本轮新件定点回修（不占存量修复名额，依 R80 先例）
处置闸席 6 项逻辑 MAJOR + 审校 2 项 BLOCK。
每处替换都带断言，任一失败即中止并打印，避免静默改错文件。
"""
import io, sys

P = r'C:\Library\DL_Process\%s.st'
done = []


def patch(fname, pairs):
    path = P % fname
    s = io.open(path, encoding='utf-8').read()
    o = s
    for old, new in pairs:
        if old not in s:
            print('!! MISS in %s : %r' % (fname, old[:70]))
            sys.exit(1)
        if s.count(old) != 1:
            print('!! AMBIGUOUS in %s (%d) : %r' % (fname, s.count(old), old[:70]))
            sys.exit(1)
        s = s.replace(old, new)
    io.open(path, 'w', encoding='utf-8').write(s)
    done.append((fname, len(s.split('\n')) - len(o.split('\n'))))


# ---- 1. BLOCK：催化剂 RUL 符号错（LN(1/act)+LN(1/0.7) 应为 减） ----
patch('FC_DL_CatalystActivityDecay', [(
    "    rRulRaw := (LN(1.0 / rActivity) + rLnInv07) / rK; // 量纲 (-)/(1/h) = h / remaining life in hours",
    "    // 量纲 (-)/(1/h) = h；目标时刻 LN(1/0.7)/k 减去已运行量 LN(1/act)/k\n"
    "    rRulRaw := (rLnInv07 - LN(1.0 / rActivity)) / rK; // 剩余寿命 [h] / remaining life in hours"
)])

# ---- 2. BLOCK：NaN 穿透（NaN 与任何数比较均为假，原判据漏掉）----
patch('FB_DL_CoagDoseJarTestSeq', [(
    "        IF (rJarResultMgL <= DL_CDJ_EPS) OR (ABS(rJarResultMgL) > DL_CDJ_FIN) THEN",
    "        // NaN 与任何数比较均为假，故用 NOT(正向域) 做兜底，NaN 必落进非法分支\n"
    "        IF NOT ((rJarResultMgL > DL_CDJ_EPS) AND (rJarResultMgL <= DL_CDJ_FIN)) THEN"
), (
    "            _rDelta := (rJarResultMgL - _rBaseMgL) / _rBaseMgL;      // 相对偏差（分母已闸）/ Relative deviation, the denominator is guarded",
    "            _rDelta := (rJarResultMgL - _rBaseMgL) / _rBaseMgL;      // 相对偏差（分母已闸）/ Relative deviation, the denominator is guarded\n"
    "            IF ABS(_rDelta) > DL_CDJ_FIN THEN\n"
    "                _rDelta := 0.0;                                      // 偏差非有限即弃用，保基准 / non-finite deviation discarded\n"
    "            END_IF"
)])

# ---- 3. MAJOR：火炬 bOver 恒 FALSE（管径本就按限速反算，回算流速必等于限速）----
patch('FC_DL_FlareFlowSizing', [(
    "VAR\n    rVelDesign : REAL;",
    "VAR\n    DL_FLARE_DIA_MIN : REAL := 0.08; // 工程最小放空管径 [m] / minimum practical flare diameter\n    rVelDesign : REAL;"
), (
    "    bOver := rVelMs > rVelLimitMs; // 越限标志 [-] / over-limit flag",
    "    // 管径由限速反算，回算流速恒等于限速，故 bOver 必须改判「所需管径小于工程最小管径」\n"
    "    bOver := rDiaRaw < DL_FLARE_DIA_MIN; // 需更小管径才满足限速，即实际将超速 / needs smaller dia, will over-speed"
)])

# ---- 4. MAJOR：泥饼回收率恒 100%（分子分母同为质量平衡产物，代数恒等式）----
patch('FC_DL_CakeSolidsCalc', [(
    "    rCakeM3h : REAL; // 出泥饼体积流量 [m3/h] / cake flow",
    "    rCakeM3h : REAL; // 出泥饼体积流量 [m3/h] / cake flow\n"
    "    rFiltrateTsPct : REAL; // 滤液含固率 [%]，固体损失实测 / filtrate solids, measured loss"
), (
    "    rFeedSolid := rFeedTsPct * rFeedM3h; // 进泥固体负荷 [%·m3/h] / feed solids product",
    "    rFeedSolid := rFeedTsPct * rFeedM3h; // 进泥固体负荷 [%·m3/h] / feed solids product\n"
    "    IF rFiltrateTsPct < 0.0 THEN\n"
    "        rFiltrateTsPct := 0.0; // 负含固率防御 / negative solids guard\n"
    "    END_IF"
), (
    "    rRecoveryRaw := rCakeSolid / rFeedSolid * 100.0; // 回收率 [%] / recovery",
    "    // 原式 cakeSolid/feedSolid 恒等于 1（cakeTs 由平衡反算），改为按滤液固体损失实测：\n"
    "    // 量纲: (m3/h)*(%) / ((m3/h)*(%)) = 无量纲，乘 100 得 %\n"
    "    rLossSolid := rFiltrateTsPct * (rFeedM3h - rCakeM3h); // 滤液带走固体 [%·m3/h] / solids lost with filtrate\n"
    "    rRecoveryRaw := (rFeedSolid - rLossSolid) / rFeedSolid * 100.0; // 回收率 [%] / recovery by loss"
), (
    "    rCakeSolid := rCakeTsPct * rCakeM3h; // 泥饼固体负荷 [%·m3/h] / cake solids product",
    "    rCakeSolid := rCakeTsPct * rCakeM3h; // 泥饼固体负荷 [%·m3/h] / cake solids product\n"
    "    rLossSolid : REAL; // 滤液固体损失占位（下方赋值）/ filtrate solids loss (assigned below)"
)])

# ---- 5. MAJOR：脱水物料平衡回收率同型恒等式 ----
patch('FC_DL_DewaterMassBalance', [(
    "    rCakeTsPct : REAL; // 泥饼含固率 [%] / cake total solids",
    "    rCakeTsPct : REAL; // 泥饼含固率 [%] / cake total solids\n"
    "    rFiltrateTsPct : REAL; // 滤液含固率 [%]，固体损失实测 / filtrate solids, measured loss"
), (
    "        rRecoveryPct := rCakeM3h * rCakeTsPct / rFeedSolid * 100.0; // 回收率 [%] / recovery",
    "        // 原式分子为平衡产物，恒等于 100%，改为按滤液损失实测\n"
    "        IF rFiltrateTsPct < 0.0 THEN\n"
    "            rFiltrateTsPct := 0.0; // 负含固率防御 / negative solids guard\n"
    "        END_IF\n"
    "        rLossSolid := rFiltrateTsPct * rFiltrateM3h; // 滤液带走固体 [%·m3/h] / lost solids\n"
    "        rRecoveryPct := (rFeedSolid - rLossSolid) / rFeedSolid * 100.0; // 回收率 [%] / recovery by loss"
)])

# ---- 6. MAJOR：OLR 把 COD 当 VS/TS 用（量纲对但物理量冒充）----
patch('FC_DL_OrganicLoadRate', [(
    "    rVsTsRatio : REAL; // VS/TS 比 [-]，典型 0.7 / volatile to total solids ratio",
    "    rVsTsRatio : REAL; // VS/TS 比 [-]，典型 0.7 / volatile to total solids ratio\n"
    "    rTsKgM3 : REAL; // 进料总固体浓度 [kg/m3] / feed total solids concentration"
), (
    "    rCodKgM3 := rCodMgL * rMgLToKgM3; // COD 浓度 [kg/m3] / COD in kg/m3\n"
    "    rVsRaw := rFeedM3Day * rCodKgM3 * rVsTsRatio; // VS 量 [kgVS/d] / volatile solids per day",
    "    rCodKgM3 := rCodMgL * rMgLToKgM3; // COD 浓度 [kg/m3]，仅作参考量 / COD reference only\n"
    "    // 量纲: (m3/d)*(kg/m3)*(-) = kgVS/d；VS 必须由 TS 乘 VS/TS 得，不得用 COD 冒充\n"
    "    rVsRaw := rFeedM3Day * rTsKgM3 * rVsTsRatio; // VS 量 [kgVS/d] / volatile solids per day"
)])

# ---- 7. MAJOR：组分负值未闸，CH4 可超 100% ----
patch('FC_DL_MethaneRatioCalc', [(
    "    IF rCh4Raw < 0.0 THEN",
    "    IF (rCo2Pct < 0.0) OR (rN2Pct < 0.0) OR (rO2Pct < 0.0) THEN\n"
    "        iErrCode := 4; // 组分负值：传感器非法，甲烷不可信 / negative component: invalid sensor\n"
    "        bValid := FALSE;\n"
    "        FC_DL_MethaneRatioCalc := TRUE;\n"
    "        RETURN;\n"
    "    END_IF\n"
    "    IF rCh4Raw > 100.0 THEN\n"
    "        rCh4Pct := 100.0; // 组分和偏低导致外推超 100%，饱和 / extrapolated above 100 percent, clamp\n"
    "    ELSIF rCh4Raw < 0.0 THEN"
)])

# ---- 8. MAJOR：HTU 缺压力因子（Kga 单位为 atm 基，必须除操作压力）----
patch('FC_DL_PackedBedHtu', [(
    "    rNtu : REAL; // 传质单元数 NTU [-] / number of transfer units",
    "    rNtu : REAL; // 传质单元数 NTU [-] / number of transfer units\n"
    "    rPressAtm : REAL; // 操作压力 [atm]，Kga 为 atm 基 / operating pressure, Kga basis"
), (
    "    rHtuRaw := rGasKmolH / (rKgaKmolM3h * rAreaM2); // HTU [m] / height of transfer unit",
    "    // Kga 以 atm 为基准，故分母必须乘操作压力；漏乘 P 会把 HTU 高估 P 倍\n"
    "    // 量纲: (kmol/h) / (kmol/(m3·h·atm) × m2 × atm) = m\n"
    "    rHtuRaw := rGasKmolH / (rKgaKmolM3h * rAreaM2 * rPressAtm); // HTU [m] / height of transfer unit"
)])

print('patched %d files:' % len(done))
for n, d in done:
    print('  %-34s Δ行 %+d' % (n, d))
