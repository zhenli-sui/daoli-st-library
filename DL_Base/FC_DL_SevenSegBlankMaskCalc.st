(* ============================================================
   DL_Base / FC_DL_SevenSegBlankMaskCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：前导零消隐掩码。uDigitMask 为在位位图（bit i = 第 i+1 位存在），
         uDigits 为有效位数，输出 = 在位位图 ∧ 低 uDigits 位全 1
   边界：uDigits = 0 → 全灭 16#00；uDigits > 8 → 钳到 8 并置码 1（防移位越界）；
         移位量恒 ≤ 7（8 位时改用全 1 常量，禁 SHL 8 位）
   依赖：仅 IEC 61131-3（SHL） ｜ 溯源：DLF-C-SEVENSEG（内部原创线）
   ============================================================ *)
FUNCTION FC_DL_SevenSegBlankMaskCalc : BOOL
VAR_INPUT
    uDigitMask : BYTE;  // 在位位图（bit i = 第 i+1 位存在）[-] / Presence bitmap of the digits
    uDigits    : UINT;  // 有效位数，0 = 无有效位 [位] / Significant digit count
END_VAR
VAR_OUTPUT
    uMask  : BYTE;   // 前导零消隐后允许点亮的位掩码 [-] / Blank mask of allowed digits
    uErrId : UDINT;  // 出口码 0 正常 / 1 有效位数超 8 已钳 [-] / Outlet code
END_VAR
VAR
    _uDigitsUse : UINT;  // 钳定后的有效位数 [位] / Clamped significant digit count
    _uLowOnes   : BYTE;  // 低 n 位全 1 掩码 [-] / Mask with the low n bits set
    _uShiftSrc  : BYTE;  // 移位源（显式 BYTE，禁字面量被推成 DINT）[-] / Explicit BYTE shift source
    _nShift     : INT;   // 归一后移位量（域闸已证 1~7）[位] / Normalized shift amount
END_VAR

(* 段 0：出口预置安全侧（全灭，N3） *)
FC_DL_SevenSegBlankMaskCalc := FALSE;
uMask := 16#00;  uErrId := 0;  _uLowOnes := 16#00;

(* 段 1：位数域闸（0 = 全灭；> 8 钳定并报码） *)
IF uDigits = 0 THEN
    uMask := 16#00;  FC_DL_SevenSegBlankMaskCalc := TRUE;  RETURN;
END_IF
IF uDigits > 8 THEN
    _uDigitsUse := 8;  uErrId := 1;
ELSE
    _uDigitsUse := uDigits;
END_IF

(* 段 2：低 n 位全 1（n = 8 时用全 1 常量，禁 8 位移位；
   移位源与移位量均显式定型：BYTE 源 + INT 量，禁裸字面量被推成 DINT，R48） *)
IF _uDigitsUse >= 8 THEN
    _uLowOnes := 16#FF;
ELSE
    _uShiftSrc := 16#01;                       // 字面量按 BYTE 目标定型
    _nShift    := UINT_TO_INT(_uDigitsUse);    // 域闸已证 1~7，恒 < 位宽 8
    _uLowOnes  := SHL(_uShiftSrc, _nShift) - 16#01;
END_IF

(* 段 3：与在位位图求交（不得点亮硬件不存在的位） + 单一出口裁决（N4） *)
uMask := uDigitMask AND _uLowOnes;
FC_DL_SevenSegBlankMaskCalc := TRUE;
END_FUNCTION
