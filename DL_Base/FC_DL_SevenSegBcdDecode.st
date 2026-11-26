(* ============================================================
   DL_Base / FC_DL_SevenSegBcdDecode ｜ v1.0.0 ｜ 2026-11-25
   功能：BCD 位（0~9）→ 七段段码。段位 bit0=a bit1=b bit2=c bit3=d bit4=e
         bit5=f bit6=g bit7=dp；bCommonAnode=TRUE 整字节取反（共阳低有效）
   边界：输入 > 9 → 全灭（共阴 16#00 / 共阳 16#FF）且 bValid=FALSE；
         小数点叠加不属本件（签名无 dp 引脚），由 FC_DL_SevenSegMinusFlagCalc 负责；
         本文件 16# 常量均为段掩码，非事件码位（R83 不入账）
   依赖：仅 IEC 61131-3（NOT） ｜ 溯源：DLF-C-SEVENSEG（内部原创线）
   ============================================================ *)
FUNCTION FC_DL_SevenSegBcdDecode : BOOL
VAR_INPUT
    uBcd         : BYTE;  // BCD 位值，域 0~9 [-] / BCD digit, domain zero to nine
    bCommonAnode : BOOL;  // TRUE=共阳低有效 / FALSE=共阴高有效 [-] / TRUE for common anode
END_VAR
VAR_OUTPUT
    uSegCode : BYTE;  // 七段段码（含极性，不含 dp）[-] / Segment code with polarity, without dp
    bValid   : BOOL;  // 输入在 BCD 域内 [-] / Input inside the BCD domain
END_VAR
VAR
    _uRaw : BYTE;  // 共阴原始段码 [-] / Raw common cathode code
END_VAR

(* 段 0：出口预置安全侧（全灭按极性，N3） *)
FC_DL_SevenSegBcdDecode := FALSE;
_uRaw := 16#00;
bValid := FALSE;
IF bCommonAnode THEN uSegCode := 16#FF; ELSE uSegCode := 16#00; END_IF

(* 段 1：BCD 域闸（> 9 保持全灭，不做隐式回绕） *)
IF uBcd > 9 THEN RETURN; END_IF

(* 段 2：字形查表（段掩码常量，非码位） *)
CASE uBcd OF
0: _uRaw := 16#3F;   // 段 abcdef / Segments a to f
1: _uRaw := 16#06;   // 段 bc / Segments b and c
2: _uRaw := 16#5B;   // 段 abdeg / Segments a b d e g
3: _uRaw := 16#4F;   // 段 abcdg / Segments a b c d g
4: _uRaw := 16#66;   // 段 bcfg / Segments b c f g
5: _uRaw := 16#6D;   // 段 acdfg / Segments a c d f g
6: _uRaw := 16#7D;   // 段 acdefg / Segments a c d e f g
7: _uRaw := 16#07;   // 段 abc / Segments a b c
8: _uRaw := 16#7F;   // 全七段 / All seven segments
9: _uRaw := 16#6F;   // 段 abcdfg / Segments a b c d f g
ELSE
    _uRaw := 16#00;  // 兜底全灭 / Fallback blanks all
END_CASE

(* 段 3：极性切换 + 单一出口裁决（N4） *)
IF bCommonAnode THEN uSegCode := NOT _uRaw; ELSE uSegCode := _uRaw; END_IF
bValid := TRUE;  FC_DL_SevenSegBcdDecode := TRUE;
END_FUNCTION
