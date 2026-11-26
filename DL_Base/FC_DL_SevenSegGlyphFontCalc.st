(* ============================================================
   DL_Base / FC_DL_SevenSegGlyphFontCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：自定义字形字模查表：段掩码（bit0=a … bit6=g，不含 dp）在标准字形表中
         精确匹配，命中输出槽号 uFontSlot（0~15），未命中置 bMiss
   边界：uSlotCnt = 0 → 无槽可查（bMiss=TRUE、槽号 0）；uSlotCnt > 16 → 钳到
         表容量；数组下标一律 INT 循环索引并夹到本表固定界 0..15（固定长度数组
         故用编译期常量界，LOWER_BOUND/UPPER_BOUND 仅接受变长数组，R17）
   依赖：仅 IEC 61131-3（INT_TO_BYTE） ｜ 溯源：DLF-C-SEVENSEG
   ============================================================ *)
FUNCTION FC_DL_SevenSegGlyphFontCalc : BOOL
VAR_INPUT
    uSegMask : BYTE;  // 段掩码（不含 dp）[-] / Segment mask without the decimal point
    uSlotCnt : UINT;  // 可查字形槽数，域 1~16 [槽] / Number of glyph slots to search
END_VAR
VAR_OUTPUT
    uFontSlot : BYTE;  // 命中的字形槽号 [-] / Matched glyph slot number
    bMiss     : BOOL;  // 未命中任何槽 [-] / No glyph slot matched
END_VAR
VAR
    auFont : ARRAY[0..15] OF BYTE;  // 标准字形表（0~9 与 A~F）[-] / Standard glyph table
    _nCnt  : INT;                   // 钳定后槽数 [槽] / Clamped slot count
    _nIdx  : INT;                   // 循环索引（整数、已夹界）[-] / Bounded loop index
    _bHit  : BOOL;                  // 命中标志 [-] / Match found flag
END_VAR

(* 段 0：出口预置安全侧（槽 0、未命中） *)
FC_DL_SevenSegGlyphFontCalc := FALSE;
uFontSlot := 0;  bMiss := TRUE;  _bHit := FALSE;

(* 段 1：字模表装配（段掩码常量，非码位） *)
auFont[0] := 16#3F;   auFont[1] := 16#06;   auFont[2] := 16#5B;   auFont[3] := 16#4F;
auFont[4] := 16#66;   auFont[5] := 16#6D;   auFont[6] := 16#7D;   auFont[7] := 16#07;
auFont[8] := 16#7F;   auFont[9] := 16#6F;   auFont[10] := 16#77;  auFont[11] := 16#7C;
auFont[12] := 16#39;  auFont[13] := 16#5E;  auFont[14] := 16#79;  auFont[15] := 16#71;

(* 段 2：槽数域闸（0 = 无槽；> 16 钳到表容量） *)
IF uSlotCnt = 0 THEN
    bMiss := TRUE;  FC_DL_SevenSegGlyphFontCalc := TRUE;  RETURN;
END_IF
IF UINT_TO_INT(uSlotCnt) > 15 THEN         // 15 = 固定表上界（auFont[0..15]）
    _nCnt := 16;                              // 钳定到表容量，防越界
ELSE
    _nCnt := UINT_TO_INT(uSlotCnt);
END_IF

(* 段 3：线性查表（索引恒在固定界 0..15 内） *)
FOR _nIdx := 0 TO (_nCnt - 1) DO
    IF (_nIdx >= 0) AND (_nIdx <= 15) THEN
        IF auFont[_nIdx] = uSegMask THEN
            uFontSlot := INT_TO_BYTE(_nIdx);  // 命中：输出槽号
            _bHit := TRUE;
            EXIT;
        END_IF
    END_IF
END_FOR

(* 段 4：单一出口裁决（N4：命中位与槽号同源） *)
bMiss := NOT _bHit;  FC_DL_SevenSegGlyphFontCalc := TRUE;
END_FUNCTION
