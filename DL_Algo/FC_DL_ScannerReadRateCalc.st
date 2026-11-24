(*
  DL Factory R83 | FC_DL_ScannerReadRateCalc
  功能：按读码总次数与首读成功数算首读率，并算失败件平均重读次数与未读率。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
FUNCTION FC_DL_ScannerReadRateCalc : REAL
VAR_INPUT
    diTotal   : DINT; // 读码总次数（含重读）[次] / Total read attempts incl. retries [-]
    diFirstOk : DINT; // 首次即读成功次数 [次] / First-attempt successes [-]
    diRetry   : DINT; // 重读累计次数 [次] / Total retries [-]
    diNoRead  : DINT; // 最终未读次数 [次] / Final no-reads [-]
END_VAR
VAR_OUTPUT
    fFsrPct    : REAL; // 首读率 FSR [%] / First-scan rate [%]
    fAvgRetry  : REAL; // 失败件平均重读次数 [次/件] / Mean retries per failed read [-]
    fNoReadPct : REAL; // 最终未读率 [%] / Final no-read rate [%]
    xValid     : BOOL; // 计算有效性标志 / Calculation validity flag
END_VAR
VAR
    diFail : DINT; // 首读失败件数 [次] / First-read failures [-]
END_VAR
// 出口预置：四出口统一预置（R256）
fFsrPct := 0.0; fAvgRetry := 0.0; fNoReadPct := 0.0; xValid := FALSE;
// 计数器域闸：任一项为负或首读超总数即判采集异常（整数无 NaN，仍做符号与次序检查）
IF diTotal <= 0 OR diFirstOk < 0 OR diRetry < 0 OR diNoRead < 0 OR diFirstOk > diTotal OR diNoRead > diTotal THEN
    FC_DL_ScannerReadRateCalc := -1.0; RETURN;  // 哨兵 -1：计数域越界 / Sentinel -1: counter domain violation
END_IF
// 首读率：首读成功 ÷ 总次数 × 100（先转 REAL 再除，避免整数截断）
fFsrPct := (DINT_TO_REAL(diFirstOk) / DINT_TO_REAL(diTotal)) * 100.0; // 首读率 [%] / First-scan rate
// 首读失败件数：总数 - 首读成功，非负由上面的次序闸保证
diFail := diTotal - diFirstOk;     // 首读失败数 [次] / First-read failures [-]
// 平均重读：重读次数 ÷ 失败件数，分母分支显式判零（R4/R21）
IF diFail > 0 THEN                 // 失败件数分母显式零闸 / Explicit zero gate on failure count
    fAvgRetry := DINT_TO_REAL(diRetry) / DINT_TO_REAL(diFail); // 平均重读 [次/件] / Mean retries
ELSE
    fAvgRetry := 0.0;               // 全首读通过，无重读 / All first-read, no retries
END_IF
// 未读率：未读次数 ÷ 总次数 × 100（总次数已判正）
fNoReadPct := (DINT_TO_REAL(diNoRead) / DINT_TO_REAL(diTotal)) * 100.0; // 未读率 [%] / No-read rate
xValid := TRUE;                           // 链路有效 / Chain valid
FC_DL_ScannerReadRateCalc := fFsrPct;     // 返回首读率 [%] / Return first-scan rate [%]
END_FUNCTION
