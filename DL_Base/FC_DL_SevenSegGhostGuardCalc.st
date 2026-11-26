(* ============================================================
   DL_Base / FC_DL_SevenSegGhostGuardCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：鬼影抑制消隐时长：tBlank = 段关断延时 + 位切换时间；强驱动模式再留 50%
         余量（1.5 倍），保证「先关全段 → 换位选 → 点新段」的间隙足够
   边界：任一时长 < 0（TIME 负值）→ bCfgBad=TRUE、tBlank=T#0S（不给不可信时长）；
         tBlank > 5ms（超常规 1ms 位槽上限）→ 钳到 5ms 并置 bCfgBad；
         精度声明：本件以 DINT 毫秒为运算域
   依赖：仅 IEC 61131-3（TIME_TO_DINT / DINT_TO_TIME） ｜ 溯源：DLF-C-SEVENSEG
   ============================================================ *)
FUNCTION FC_DL_SevenSegGhostGuardCalc : BOOL
VAR_INPUT
    tSegOff      : TIME;  // 段关断延时，域 ≥ 0 [ms] / Segment turn off delay
    tDigitSwitch : TIME;  // 位选切换时间，域 ≥ 0 [ms] / Digit select switching time
    bFastMode    : BOOL;  // TRUE=强驱动，留 50% 余量 [-] / TRUE adds fifty percent margin
END_VAR
VAR_OUTPUT
    tBlank  : TIME;  // 计算所得消隐时长 [ms] / Computed blanking duration
    bCfgBad : BOOL;  // 组态非法或时长越上限 [-] / Illegal configuration or above the ceiling
END_VAR
VAR
    _nSeg   : DINT;  // 段关断延时毫秒值 [ms] / Segment turn off delay
    _nBlank : DINT;  // 消隐时长中间值 [ms] / Intermediate blanking duration
END_VAR

(* 段 0：出口预置安全侧（不消隐、标非法） *)
FC_DL_SevenSegGhostGuardCalc := FALSE;
tBlank := T#0S;  bCfgBad := TRUE;

(* 段 1：入参域闸（TIME 负值不可用于时长） *)
_nSeg := TIME_TO_DINT(tSegOff);
IF (_nSeg < 0) OR (TIME_TO_DINT(tDigitSwitch) < 0) THEN RETURN; END_IF

(* 段 2：基础消隐 = 段关断 + 位切换（ms 域相加，无 TIME 溢出路径） *)
_nBlank := _nSeg + TIME_TO_DINT(tDigitSwitch);

(* 段 3：强驱动余量 1.5 倍（整数式 blank + blank/2） *)
IF bFastMode THEN _nBlank := _nBlank + (_nBlank / 2); END_IF

(* 段 4：上限栅（超 5ms 判组态异常并钳定，出口与判据同源，N4） *)
IF _nBlank > 5 THEN
    _nBlank := 5;  bCfgBad := TRUE;
ELSE
    bCfgBad := FALSE;
END_IF
tBlank := DINT_TO_TIME(_nBlank);
FC_DL_SevenSegGhostGuardCalc := TRUE;
END_FUNCTION
