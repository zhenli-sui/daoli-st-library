(*==============================================================================
 * 组件名称 (Component)  : FB_DL_EnergyKpiAggregator
 * 溯源说明 (Provenance) : 道莅 clean-room 防御性实现（PackML 深化）
 * 所属子库 (Sublibrary) : DL_Process / Kpi
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；
 *                         纯 IEC 61131-3（第 3 版），仅用标准库 TON
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 单位产量能耗 KPI 聚合
 * 功能一句话 (Summary)  : KPI 窗口内电能累计除以产量计数，得 kWh 每千件。
 * 边界与安全 (Boundary) : ①能量增量小于 0 视为表翻转拒收并置码；
 *                         ②NaN 能量增量拒收（自反判）；
 *                         ③窗口产量为 0 → 保持上次 KPI + 零产量掩码（不做除零）；
 *                         ④KPI 窗口 TON 无条件周期刷新；
 *                         ⑤bReset 清全部窗口累计与有效标志。
 * 错误码    : 16#0005_0365 能量增量非法（负值表翻转或 NaN）——故障级（单拍）
 *             16#0005_0366 零产量掩码激活（窗口产量为 0）——信息级（持续态）
 * 码位总账  : 16#0005_0365 用 / 16#0005_0366 用
 * 修改记录  : v1.0.0 R26 初版
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_EnergyKpiAggregator
VAR_INPUT
    fEnergyDelta : LREAL; // 周期电能增量 [kWh] / Per-cycle energy increment [kWh]
    uProdDelta   : ULINT; // 周期产量增量 [件] / Per-cycle production increment [pcs]
    tKpiWindow   : TIME;  // KPI 统计窗时长 [ms] / KPI window duration [ms]
    bReset       : BOOL;  // 复位：清累计与有效标志 / Reset: clear accumulators and valid flag
END_VAR
VAR_OUTPUT
    fKpi         : LREAL; // 单位产量能耗 [kWh/千件] / Energy per thousand pieces [kWh/kpcs]
    bKpiValid    : BOOL;  // KPI 已有有效结论 / KPI has a valid result
    bZeroProdMask: BOOL;  // 零产量掩码激活 / Zero-production mask active
    eErr         : UDINT; // 本周期错误码，0=无错 / Error code this cycle, 0 = none
END_VAR
VAR
    fEneWin  : LREAL; // 窗内电能累计 [kWh] / In-window energy sum
    uProdWin : ULINT; // 窗内产量累计 [件] / In-window production sum
    tonWin   : TON;   // KPI 窗定时器（无条件刷新）/ KPI window timer
    fEneGrd  : LREAL; // 能量增量守卫副本 / Energy increment guard copy
    fProdReal: LREAL; // 产量实数临时量（除法用）/ Production real temp for division
END_VAR

// ---------- 能量增量防御：负值表翻转与 NaN 拒收 ----------
fEneGrd := fEnergyDelta;
eErr := 0;
IF (fEneGrd <> fEneGrd) OR ((fEneGrd - fEneGrd) <> (fEneGrd - fEneGrd)) THEN
    eErr := 16#0005_0365;                     // NaN 拒收 / NaN rejected
ELSIF fEneGrd < 0.0 THEN
    eErr := 16#0005_0365;                     // 表翻转拒收 / Meter rollover rejected
ELSE
    fEneWin := fEneWin + fEneGrd;             // 合法增量入窗 / Valid increment accumulated
    uProdWin := uProdWin + uProdDelta;        // 产量入窗 / Production accumulated
END_IF

// ---------- 复位：清窗累计与有效标志 ----------
IF bReset THEN
    fEneWin := 0.0;
    uProdWin := ULINT#0;
    fKpi := 0.0;
    bKpiValid := FALSE;
    bZeroProdMask := FALSE;
END_IF

// ---------- 无条件周期刷新：KPI 窗定时器 ----------
tonWin(IN := TRUE, PT := tKpiWindow);

// ---------- 窗到时结算：除法前判零，零产量掩码保持 ----------
IF tonWin.Q THEN
    IF uProdWin > ULINT#0 THEN
        fProdReal := ULINT_TO_LREAL(uProdWin); // 产量实数 / Production as real
        fKpi := fEneWin / (fProdReal / 1000.0); // kWh 每千件（分母前判零）/ kWh per kpcs, zero-guarded
        bKpiValid := TRUE;                    // 有效结论成立 / Valid result set
        bZeroProdMask := FALSE;               // 掩码撤销 / Mask withdrawn
    ELSE
        bZeroProdMask := TRUE;                // 零产量掩码激活 / Zero-production mask
        eErr := 16#0005_0366;                 // 零产量掩码码 / Mask code
        // fKpi 保持上次结论（锁存语义，禁清零）/ fKpi holds last result (no clear)
    END_IF
    fEneWin := 0.0;                           // 窗累计清零 / Window sums cleared
    uProdWin := ULINT#0;
END_IF

END_FUNCTION_BLOCK
