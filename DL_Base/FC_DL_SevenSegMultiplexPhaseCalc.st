(* ============================================================
   DL_Base / FC_DL_SevenSegMultiplexPhaseCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：多路扫描相位解算：每位槽时长 tSlot = tScan / uDigitCnt，
         位索引 uDigitIdx = (tNow MOD tScan) / tSlot（0 基）
   边界：uDigitCnt = 0（位缺失）→ 索引 0、tSlot=T#0S；uDigitCnt > 8 → 钳到 8；
         tScan ≤ 0 → 不做除法（R4 除零闸）；槽时长 < 1ms → 抬到 1ms，
         防位索引恒 0 的隐性命中；全程整数域，无浮点判等
   依赖：仅 IEC 61131-3（TIME_TO_DINT / DINT_TO_TIME） ｜ 溯源：DLF-C-SEVENSEG
   ============================================================ *)
FUNCTION FC_DL_SevenSegMultiplexPhaseCalc : BOOL
VAR_INPUT
    tNow      : TIME;  // 当前时刻（任务时基）[ms] / Current task time base
    uDigitCnt : UINT;  // 扫描位数，域 1~8 [位] / Scanned digit count
    tScan     : TIME;  // 整帧扫描周期，域 > 0 [ms] / Frame scan period
END_VAR
VAR_OUTPUT
    uDigitIdx : UINT;  // 当前位索引（0 基）[-] / Current digit index starting at zero
    tSlot     : TIME;  // 每位保持时间 [ms] / Hold time of one digit slot
END_VAR
VAR
    _nScanMs : DINT;  // 帧周期毫秒值 [ms] / Frame period in milliseconds
    _nCnt    : DINT;  // 钳定后位数 [位] / Clamped digit count
    _nSlotMs : DINT;  // 每槽毫秒值 [ms] / Slot duration in milliseconds
    _nIdx    : DINT;  // 位索引中间值 [-] / Intermediate digit index
END_VAR

(* 段 0：出口预置安全侧（索引 0、槽时长 0） *)
FC_DL_SevenSegMultiplexPhaseCalc := FALSE;
uDigitIdx := 0;  tSlot := T#0S;

(* 段 1：位数域闸（0 = 无位可扫；> 8 钳定） *)
IF uDigitCnt = 0 THEN RETURN; END_IF
_nCnt := UINT_TO_DINT(uDigitCnt);
IF _nCnt > 8 THEN _nCnt := 8; END_IF

(* 段 2：帧周期域闸（≤ 0 不做除法） *)
_nScanMs := TIME_TO_DINT(tScan);
IF _nScanMs <= 0 THEN RETURN; END_IF

(* 段 3：槽时长（除子 ∈ 1..8，除零结构不可达） *)
_nSlotMs := _nScanMs / _nCnt;
IF _nSlotMs < 1 THEN _nSlotMs := 1; END_IF        // 抬到 1ms，防索引恒 0
tSlot := DINT_TO_TIME(_nSlotMs);

(* 段 4：帧内余量与位索引（钳到 0..cnt−1，防越界） *)
_nIdx := TIME_TO_DINT(tNow);
IF _nIdx < 0 THEN _nIdx := 0; END_IF              // 时刻回绕：按 0 处理
_nIdx := (_nIdx MOD _nScanMs) / _nSlotMs;         // 两除子均已证 > 0
IF _nIdx >= _nCnt THEN _nIdx := _nCnt - 1; END_IF
IF _nIdx < 0 THEN _nIdx := 0; END_IF
uDigitIdx := DINT_TO_UINT(_nIdx);

(* 段 5：单一出口裁决（N4） *)
FC_DL_SevenSegMultiplexPhaseCalc := TRUE;
END_FUNCTION
