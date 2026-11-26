(* ============================================================
   DL_Base / FC_DL_SevenSegMinusFlagCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：修饰段叠加 —— 负号段 g(bit6) 与小数点段 dp(bit7) 按位或叠加到字形段码；
         契约对齐 FC_DL_SevenSegBcdDecode：该件头注指名 dp 叠加归本件负责，
         且该件已按 bCommonAnode 输出带极性的段码，本件同口径补极性引脚。
   极性：bCommonAnode=FALSE → 共阴高有效（置位 = 点亮）；TRUE → 共阳低有效。
         实现内部一律先归一到共阴域叠加，再回到调用方口径——禁在共阳（低有效）
         码上直接置位（那会把对应段置 1 即熄灭，表现为「叠加即灭段」）。
   边界：段占用冲突（请求位在原段码中已亮）→ 冲突位不叠加、返回 FALSE
         （签名无独立 BOOL 口，返回值承载 bOverflow 语义，与名称同源以免名实不符）；
         无修饰请求 → 原样透传（极性原样，不做取反）返回 TRUE
   依赖：仅 IEC 61131-3（AND / OR / XOR） ｜ 溯源：DLF-C-SEVENSEG（内部原创线）
   ============================================================ *)
FUNCTION FC_DL_SevenSegMinusFlagCalc : BOOL
VAR_INPUT
    uSegCode      : BYTE;  // 原字形段码（含极性，不含修饰段）[-] / Base glyph code carrying the polarity
    bCommonAnode  : BOOL;  // TRUE=共阳低有效 / FALSE=共阴高有效 [-] / TRUE for common anode wiring
    bMinus        : BOOL;  // 请求叠加负号段 g [-] / Request the minus segment
    bDecimalPoint : BOOL;  // 请求叠加小数点段 dp [-] / Request the decimal point segment
END_VAR
VAR_OUTPUT
    uSegCodeOut : BYTE;  // 叠加后段码（与输入同极性）[-] / Resulting code in the same polarity
END_VAR
VAR
    _uWant : BYTE;  // 请求叠加的修饰段掩码（共阴域高有效）[-] / Requested modifier mask in the common cathode domain
    _uBase : BYTE;  // 极性归一后的共阴高有效段码 [-] / Base code normalized to the common cathode domain
    _uOut  : BYTE;  // 共阴域叠加结果 [-] / Overlaid code in the common cathode domain
END_VAR

(* 段 0：出口预置（空码，N3） *)
FC_DL_SevenSegMinusFlagCalc := TRUE;
uSegCodeOut := 16#00;  _uWant := 16#00;  _uBase := 16#00;  _uOut := 16#00;

(* 段 1：极性归一（共阳低有效取反到共阴高有效域，叠加只在共阴域进行） *)
IF bCommonAnode THEN
    _uBase := uSegCode XOR 16#FF;               // 低有效码逐位取反 → 高有效语义
ELSE
    _uBase := uSegCode;
END_IF

(* 段 1b：组装修饰掩码（g = 16#40，dp = 16#80，共阴域高有效） *)
IF bMinus THEN _uWant := _uWant OR 16#40; END_IF
IF bDecimalPoint THEN _uWant := _uWant OR 16#80; END_IF

(* 段 2：无修饰请求 → 原样透传（极性随原码，不做取反） *)
IF _uWant = 16#00 THEN
    uSegCodeOut := uSegCode;  FC_DL_SevenSegMinusFlagCalc := TRUE;  RETURN;
END_IF

(* 段 3：段占用冲突检测（判据与出口同源：均基于归一后的原始段码） *)
IF (_uBase AND _uWant) <> 16#00 THEN
    uSegCodeOut := uSegCode;                 // 冲突位不重复叠加，保持原码
    FC_DL_SevenSegMinusFlagCalc := FALSE;    // 返回值承载段占用冲突语义
    RETURN;
END_IF

(* 段 4：叠加（共阴域位或，再按调用方口径回送，单一出口裁决 N4） *)
_uOut := _uBase OR _uWant;
IF bCommonAnode THEN
    uSegCodeOut := _uOut XOR 16#FF;          // 回到共阳低有效口径（置 0 = 点亮）
ELSE
    uSegCodeOut := _uOut;
END_IF
FC_DL_SevenSegMinusFlagCalc := TRUE;
END_FUNCTION
