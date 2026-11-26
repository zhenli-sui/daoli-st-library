(* ============================================================
   DL_Base / FC_DL_SevenSegHexCodeCalc ｜ v1.0.0 ｜ 2026-11-25
   功能：0~15 十六进制字形段码（A~F 近似字形），段位口径同族（bit0=a … bit6=g）
   边界：uHex > 15 → 全灭 + 码 1；bHexMode=FALSE 且 10~15 → 全灭 + 码 2；
         共阳「全灭」= 16#FF，极性切换在单一出口段完成（N4）；
         16# 常量均为段掩码，非事件码位（R83 不入账）
   依赖：仅 IEC 61131-3（NOT / BYTE_TO_UDINT） ｜ 溯源：DLF-C-SEVENSEG（内部原创线）
   ============================================================ *)
FUNCTION FC_DL_SevenSegHexCodeCalc : BOOL
VAR_INPUT
    uHex         : BYTE;  // 十六进制位值，域 0~15 [-] / Hexadecimal digit, domain zero to fifteen
    bHexMode     : BOOL;  // TRUE=十六进制 / FALSE=BCD 严格校验 [-] / TRUE enables hexadecimal glyphs
    bCommonAnode : BOOL;  // TRUE=共阳低有效 [-] / TRUE for common anode active low
END_VAR
VAR_OUTPUT
    uSegCode : BYTE;   // 七段段码（含极性，不含 dp）[-] / Segment code with polarity
    uErrId   : UDINT;  // 出口码 0 正常 / 1 超 15 / 2 BCD 域外 [-] / Outlet code
END_VAR
VAR
    _uRaw : BYTE;  // 共阴原始段码 [-] / Raw common cathode code
END_VAR

(* 段 0：出口预置安全侧（全灭按极性、码取最严） *)
FC_DL_SevenSegHexCodeCalc := FALSE;
_uRaw := 16#00;  uErrId := 1;
IF bCommonAnode THEN uSegCode := 16#FF; ELSE uSegCode := 16#00; END_IF

(* 段 1：输入域闸与模式闸（BYTE 无符号，单侧判即够） *)
IF BYTE_TO_UDINT(uHex) > 15 THEN RETURN; END_IF
IF (NOT bHexMode) AND (BYTE_TO_UDINT(uHex) > 9) THEN uErrId := 2; RETURN; END_IF

(* 段 2：字形查表（段掩码常量） *)
CASE uHex OF
0:  _uRaw := 16#3F;  // 字形 0 / Glyph zero
1:  _uRaw := 16#06;  // 字形 1 / Glyph one
2:  _uRaw := 16#5B;  // 字形 2 / Glyph two
3:  _uRaw := 16#4F;  // 字形 3 / Glyph three
4:  _uRaw := 16#66;  // 字形 4 / Glyph four
5:  _uRaw := 16#6D;  // 字形 5 / Glyph five
6:  _uRaw := 16#7D;  // 字形 6 / Glyph six
7:  _uRaw := 16#07;  // 字形 7 / Glyph seven
8:  _uRaw := 16#7F;  // 字形 8 / Glyph eight
9:  _uRaw := 16#6F;  // 字形 9 / Glyph nine
10: _uRaw := 16#77;  // 近似字形 A / Approximated glyph A
11: _uRaw := 16#7C;  // 近似字形 b / Approximated glyph b
12: _uRaw := 16#39;  // 近似字形 C / Approximated glyph C
13: _uRaw := 16#5E;  // 近似字形 d / Approximated glyph d
14: _uRaw := 16#79;  // 近似字形 E / Approximated glyph E
15: _uRaw := 16#71;  // 近似字形 F / Approximated glyph F
ELSE
    _uRaw := 16#00;  // 兜底全灭 / Fallback blanks all
END_CASE

(* 段 3：极性切换 + 单一出口裁决（N4） *)
IF bCommonAnode THEN uSegCode := NOT _uRaw; ELSE uSegCode := _uRaw; END_IF
uErrId := 0;  FC_DL_SevenSegHexCodeCalc := TRUE;
END_FUNCTION
