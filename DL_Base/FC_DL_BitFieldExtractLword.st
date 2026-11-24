(*
  ==================================================================
  组件名 Component  : FC_DL_BitFieldExtractLword
  分类   Category   : DL_Base
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : LWORD 单字段提取（起始位 + 宽度 → 右对齐字段值）。全程零
                      64 位移位：先拆高低两个 DWORD 半区，再在半区内做 <=31 位的
                      移位与常量掩码，跨半区时用 DWORD_TO_LWORD 升位拼接。
  来源   Source     : t2-1-lgf-bitlogic（LGF BitLogic 位域提取族 64 位变体）
  溯源   Origin     : 位域提取属公开位运算语义，clean-room 自研实现，未复制 LGF
                      或任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（AND / OR / SHR / SHL 只作用在 DWORD 域，
                      移位量恒 <32；LWORD 域只出现 AND 与整除），三平台通用
  分工声明 Split     : 与 FC_DL_BitFieldExtract（32 位属主）互引——后者管 DWORD
                      域单字提取；本件为 LWORD 域半区拆分版，不重声明既有位域类型。
  作者   Author     : 道莅代码库 · PLC 编程专家（R60）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 全程零 64 位移位：高 32 位以「整除 2^32 再 LWORD_TO_DWORD」
                         取得（LWORD 域只做 AND 与整除，不做移位），半区内移位量
                         经 MOD 32 归一后恒在 0..31（R48）；
                      二 宽度 32 的掩码走常量 16#FFFF_FFFF，禁写 SHL(x, 32)；
                      三 非 32 对齐下「宽 64 跨两字」在本实现物理不可达（宽 64 只
                         能起始于位 0），此偏离显式声明：start + width > 64 时主动
                         收窄宽度并置截断信息级码，不静默出半个字段；
                      四 非法域：宽度为 0 或起始位 > 63 判故障级码，输出 0 且 bErr；
                      五 无状态纯函数：局部量一律段 1 显式预置（R254）。
  错误码   Codes    :
    16#0001_0616【故障级】字段域非法（宽度 0 或起始位 >63），输出 0
    16#0001_0617【信息级】字段越出 64 位容器，宽度已收窄（bTrunc 同步置位）
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 src=16#FFFF_FFFF_FFFF_FFFF、start=60、width=4 → 字段 16#F，bTrunc=FALSE
    V2 src=16#1234_5678_9ABC_DEF0、start=28、width=8 → 字段 16#BC（跨半区）
    V3 src 任意、start=62、width=8 → 宽度收窄为 2、bTrunc=TRUE、码 0617
    V4 width=0 → bErr=TRUE、码 0616、字段 0
  修订记录 Revision  :
    2026-11-21  v1.0.0  R60 首版（批 2 · 序号 5）
  ==================================================================
*)
FUNCTION FC_DL_BitFieldExtractLword : LWORD
VAR_INPUT
    uSrc   : LWORD; // 源字 [位串] / the source word
    uStart : UINT;  // 字段起始位号 [位]，合法域 0..63 / the field start bit, legal from zero to sixty three
    uWidth : UINT;  // 字段宽度 [位]，合法域 1..64 / the field width, legal from one to sixty four
END_VAR
VAR_OUTPUT
    bTrunc : BOOL;  // 宽度被收窄（越出容器）[-] / the width was narrowed at the container edge
    bErr   : BOOL;  // 域非法标志 [-] / the illegal domain flag
    eErr   : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError : BOOL;  // 错误标志，eErr 非 0 时为真 / the error flag, true when eErr is nonzero
END_VAR
VAR
    dwLow    : DWORD; // 源字低半区 [位串] / the low half of the source
    dwHigh   : DWORD; // 源字高半区 [位串] / the high half of the source
    dwMask   : DWORD; // 半区内字段掩码 [位串] / the field mask inside a half
    dwMaskHi : DWORD; // 跨半区时高半区剩余宽度掩码 [位串] / the remaining width mask on the high half
    dwPart1  : DWORD; // 跨半区低位片段 [位串] / the low fragment of a cross half field
    dwPart2  : DWORD; // 跨半区高位片段 [位串] / the high fragment of a cross half field
    nStart   : UINT;  // 归一后的起始位号 [位] / the normalised start bit
    nWidth   : UINT;  // 归一（收窄）后的宽度 [位] / the normalised width
    nLowW    : UINT;  // 跨半区时低半区可容纳宽度 [位] / the width the low half can hold
    nShift   : UINT;  // 半区内移位量 [位]，恒 0..31 / the shift amount inside a half, always zero through thirty one
END_VAR
VAR CONSTANT
    DL_BFE_32    : UINT := 32;                      // 半区位宽 [位] / the half width
    DL_BFE_ALL   : DWORD := 16#FFFF_FFFF;           // 32 位全一掩码（禁用 SHL(x, 32)）/ the full thirty two bit mask
    DL_BFE_2P32  : LWORD := 16#0000_0001_0000_0000; // 2 的 32 次幂，用于取高半区（LWORD 域整除，不做移位）/ two to the thirty second, used to take the high half by division
END_VAR

// 段 1｜返回值与错误状态预置安全值（四段式第一段，R45）+ 局部量显式预置（R254）/ segment 1, the preset of the return, the codes and the local guards
FC_DL_BitFieldExtractLword := 16#0000_0000_0000_0000; // 返回值预置零 / preset the return to zero
bTrunc := FALSE; // 截断标志预置假 / preset the truncation flag false
bErr := FALSE; // 域非法标志预置假 / preset the domain fault flag false
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 错误标志预置假 / preset the error flag false
nStart := 0; // 起始位预置零 / preset the start bit zero
nWidth := 0; // 宽度预置零 / preset the width zero
nLowW := 0; // 低半区宽度预置零 / preset the low half width zero
nShift := 0; // 移位量预置零 / preset the shift amount zero
dwMask := 16#0000_0000; // 掩码预置零 / preset the mask zero
dwMaskHi := 16#0000_0000; // 高位掩码预置零 / preset the high mask zero
dwPart1 := 16#0000_0000; // 低位片段预置零 / preset the low fragment zero
dwPart2 := 16#0000_0000; // 高位片段预置零 / preset the high fragment zero

// 段 2｜域闸（下界早退 + 上界钳位，边界三）/ segment 2, the domain gate with the early return and the narrowing
IF (uWidth < 1) OR (uStart > 63) THEN // 宽度为零或起始位越域 / a zero width or a start beyond the container
    bErr := TRUE; // 置域非法标志 / raise the domain fault flag
    eErr := 16#0001_0616; // 故障级：字段域非法 / fault grade, the field domain is illegal
    bError := TRUE; // 置错误标志（R45 配对）/ raise the error flag, paired with the fault code
    RETURN; // 早退：返回值保持零 / early return with the field zero
END_IF
nStart := uStart; // 域内接管起始位 / take the start bit inside the domain
nWidth := uWidth; // 域内接管宽度 / take the width inside the domain
IF (UINT_TO_UDINT(nStart) + UINT_TO_UDINT(nWidth)) > 64 THEN // 越出 64 位容器 / beyond the sixty four bit container
    nWidth := 64 - nStart; // 主动收窄到容器边界（边界三偏离声明）/ narrow to the container edge with the declared deviation
    bTrunc := TRUE; // 置截断标志 / raise the truncation flag
    eErr := 16#0001_0617; // 信息级：宽度已收窄 / informational, the width narrowed
    bError := TRUE; // 置错误标志 / raise the error flag
END_IF

// 段 3｜半区拆分（零 64 位移位，边界一）：低半区截断取，高半区整除取 / segment 3, the half split with no sixty four bit shift
dwLow := LWORD_TO_DWORD(uSrc); // 低半区：截断取低 32 位 / the low half by truncation
dwHigh := LWORD_TO_DWORD(uSrc / DL_BFE_2P32); // 高半区：整除 2^32 后取低 32 位 / the high half by the division

// 段 4｜字段提取与跨半区拼接（掩码先于移位构造，移位量恒 <32）/ segment 4, the extraction and the cross half splice
IF (nWidth = 32) THEN // 宽 32：常量全一掩码（禁 SHL(x, 32)）/ a full half width uses the constant mask
    dwMask := DL_BFE_ALL; // 常量掩码 / the constant mask
ELSE // 宽 1..31：SHL(1, nWidth) - 1，移位量最大 31 结构性安全 / widths one through thirty one
    dwMask := SHL(DWORD#1, nWidth) - DWORD#1; // 低位起的 nWidth 个一并 / the nWidth low bits set
END_IF
IF nStart >= DL_BFE_32 THEN // 字段整段落在高半区 / the field lies entirely in the high half
    nShift := nStart - DL_BFE_32; // 半区内移位量 0..31 / the shift inside the half, zero through thirty one
    FC_DL_BitFieldExtractLword := DWORD_TO_LWORD(SHR(dwHigh AND dwMask, nShift)); // 高半区提取后升位 / extract from the high half then widen
ELSIF (UINT_TO_UDINT(nStart) + UINT_TO_UDINT(nWidth)) <= 32 THEN // 字段整段落在低半区 / the field lies entirely in the low half
    nShift := nStart; // 半区内移位量 0..31 / the shift inside the half, zero through thirty one
    FC_DL_BitFieldExtractLword := DWORD_TO_LWORD(SHR(dwLow AND dwMask, nShift)); // 低半区提取后升位 / extract from the low half then widen
ELSE // 跨半区：低片段 + 高片段移位拼接（nStart 必在 1..31）/ a cross half field, both fragments spliced
    nLowW := 32 - nStart; // 低半区可容纳宽度 1..31 / the width the low half holds, one through thirty one
    IF nLowW >= 32 THEN // 结构性不可达（nStart ≥ 1 恒真），显式兜底防掩码移位越界 / structurally unreachable, kept as an explicit guard
        nLowW := 31; // 兜底收窄到 31 位 / narrow to thirty one bits
    END_IF
    dwPart1 := SHR(dwLow AND (SHL(DWORD#1, nLowW) - DWORD#1), nStart); // 低片段右移到最低位 / shift the low fragment down to bit zero
    dwMaskHi := SHL(DWORD#1, nWidth - nLowW) - DWORD#1; // 高半区剩余宽度掩码 / the remaining width mask on the high half
    dwPart2 := SHL(dwHigh AND dwMaskHi, nLowW); // 高片段左移到低片段之上（移位量 1..31）/ shift the high fragment above the low one
    FC_DL_BitFieldExtractLword := DWORD_TO_LWORD(dwPart1 OR dwPart2); // 两片段拼合后升位 / splice then widen
END_IF

// 段 5｜结果复检：字段宽度上界自证（nWidth ≤ 64，拼接已按半区完成，无溢出路径）/ segment 5, the result recheck
IF bTrunc AND (nWidth >= 1) THEN // 收窄后仍为合法宽度 / the narrowed width is still legal
    eErr := 16#0001_0617; // 信息级：宽度已收窄（回放，防段 4 覆盖）/ informational, the width narrowed, replayed against the overwrite
END_IF
END_FUNCTION
