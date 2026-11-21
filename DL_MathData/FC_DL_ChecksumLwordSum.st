(*
  Name        : FC_DL_ChecksumLwordSum
  Category    : DL_MathData
  Version     : 1.0.0
  Purpose     : 64 位字累加和校验：LWORD 数组按模 2^64 回卷累加（高低半字条件进位，禁取模），与预置校验值位等比对出结论；/ 64-bit word checksum: modulo-2^64 wrapping accumulate of an LWORD array via conditional halfword carry (no modulo), compared bit-equal against a preset check value
  溯源        : 借 lgf-datahandling 的分类/参数域组织，clean-room 实现
  Boundary    : ① 空数组（计数 0）→ 返回 FALSE 哨兵，不返回 0 当有效和；
                ② 回卷累加用条件进位法（低半字加后回卷即进位），全程禁取模运算；
                ③ 数组长度上限常量守卫 + 计数域闸（负数/超容拒绝），遍历用 FOR 有界循环防死循环；
                ④ 预置校验值比对为整数位等（无浮点判等）；
                ⑤ 高半字加法回卷即模 2^64 语义（溢出进位出界自然丢弃）；
                ⑥ 本件为纯函数：无状态、无实例保持量、零外部全局、零物理地址。
*)
FUNCTION FC_DL_ChecksumLwordSum : BOOL
VAR_INPUT
    aData   : ARRAY[1..256] OF LWORD;        (* 待校验数据数组（有效区 1..nCount）[-] / Data array to checksum *)
    nCount  : INT := 0;                      (* 有效元素计数，域 0..256 [-] / Valid element count *)
    qwExpect: LWORD := LWORD#0;              (* 预置校验值（位等比对目标）[-] / Preset expected checksum *)
END_VAR
VAR_OUTPUT
    qwSum   : LWORD;                         (* 累加和出口（空数组时为 0 且返回 FALSE）[-] / Accumulated sum outlet *)
    bMatch  : BOOL;                          (* 比对结论：累加和与预置值位等 [-] / Match verdict, bit-equal *)
END_VAR
VAR
    _nCnt   : INT;                           (* 钳位后生效元素计数 [个] / Clamped element count *)
    _i      : INT;                           (* 遍历游标 [个] / Loop cursor *)
    _sLo    : DWORD;                         (* 累加和低半字 [-] / Sum low halfword *)
    _sHi    : DWORD;                         (* 累加和高半字 [-] / Sum high halfword *)
    _tLo    : DWORD;                         (* 低半字加法暂存（回卷检测）[-] / Low half add staging *)
    _tHi    : DWORD;                         (* 高半字加法暂存（回卷丢弃）[-] / High half add staging *)
    _eLo    : DWORD;                         (* 当前元素低半字 [-] / Element low half *)
    _eHi    : DWORD;                         (* 当前元素高半字 [-] / Element high half *)
    _cIn    : DWORD;                         (* 低半字回卷进位（0/1）[-] / Carry from low wrap *)
END_VAR
VAR CONSTANT
    DL_CKS_NMAX  : INT   := 256;             (* 数组容量上限常量守卫 [个] / Array capacity guard *)
    DL_CKS_MASKL : LWORD := LWORD#16#FFFFFFFF;   (* 低 32 位掩码常量 [-] / Low 32-bit mask *)
END_VAR

(* —— 段 1：出口与累加器预清（空数组哨兵前置，R107） —— *)
qwSum  := LWORD#0;                                       (* 累加和出口预清（哨兵零） / Sum outlet preset *)
bMatch := FALSE;                                         (* 比对结论预清 / Match preset *)
_sLo := DWORD#0;                                         (* 低半字累加清零 / Low half clear *)
_sHi := DWORD#0;                                         (* 高半字累加清零 / High half clear *)

(* —— 段 2：计数域闸 + 容量守卫（边界③） —— *)
_nCnt := nCount;                                         (* 生效计数初值 / Effective count init *)
IF (nCount < 0) OR (nCount > DL_CKS_NMAX) THEN
    FC_DL_ChecksumLwordSum := FALSE;                     (* 计数越域：哨兵拒绝（不出有效和） / Count out of domain, sentinel reject *)
    RETURN;                                              (* 提前返回（无状态残留） / Early return *)
END_IF
IF _nCnt = 0 THEN
    FC_DL_ChecksumLwordSum := FALSE;                     (* 空数组：哨兵拒绝，不返回 0 当有效和（边界①） / Empty array, sentinel reject *)
    RETURN;                                              (* 提前返回 / Early return *)
END_IF

(* —— 段 3：条件进位回卷累加（禁取模，边界②⑤；FOR 有界防死循环） —— *)
FOR _i := 1 TO _nCnt DO
    _eLo := LWORD_TO_DWORD(aData[_i] AND DL_CKS_MASKL);  (* 取元素低半字（掩码常量） / Element low half *)
    _eHi := LWORD_TO_DWORD(SHR(aData[_i], 32));          (* 取元素高半字（移 32 位常量） / Element high half *)
    _tLo := _sLo + _eLo;                                 (* 低半字相加 / Low half add *)
    IF _tLo < _sLo THEN
        _cIn := DWORD#1;                                 (* 回卷即进位（条件进位法） / Wrap implies carry *)
    ELSE
        _cIn := DWORD#0;                                 (* 无回卷无进位 / No carry *)
    END_IF
    _sLo := _tLo;                                        (* 低半字推进 / Low half advance *)
    _tHi := _sHi + _eHi + _cIn;                          (* 高半字带进位相加 / High half add with carry *)
    _sHi := _tHi;                                        (* 高半字回卷进位出界自然丢弃（模 2^64 语义） / High wrap discard *)
END_FOR

(* —— 段 4：出口组装 + 位等比对（边界④，整数无浮点） —— *)
qwSum  := SHL(DWORD_TO_LWORD(_sHi), 32) OR DWORD_TO_LWORD(_sLo);   (* 半字合成 64 位和 / Assemble 64-bit sum *)
bMatch := (qwSum = qwExpect);                            (* 位等比对（整数直比） / Bit-equal compare *)
FC_DL_ChecksumLwordSum := TRUE;                          (* 有效和结论 / Valid sum verdict *)
END_FUNCTION
