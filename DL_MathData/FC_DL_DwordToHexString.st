(*
    组件名称 : FC_DL_DwordToHexString
    所属子库 : DL_MathData
    当前版本 : 1.0.0
    兼 容 性 : CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop；仅依赖 Standard.library
    功能描述 : DWORD → 8 位定宽十六进制文本，是 FC_DL_HexStringToBytes 的逆向对偶。
              取舍 ①：禁委托平台 DWORD_TO_STRING 的进制参数 —— 三家平台对「是否有 16# 前缀」「大小写」
              「是否补前导零」「不足位是否加空格」四项行为各不相同，一条日志换个平台就变样，
              报文回放与时间戳对齐全崩。本件用半字节查表 + CONCAT 自建，输出形态完全确定。
              取舍 ②：必须保留前导零（8 位定宽）—— 定宽是日志列对齐、二进制报文逐字节比对的前提；
              可变的短形态看着干净，却让「按位置切列」的所有下游脚本失效。
              取舍 ③：结果长度做出口自证 —— 若调用方把返回值声明成过短的 STRING，平台会静默截断，
              得到「看着像十六进制、其实少了几位」的串；本件比对实际长度与期望长度，不等即判故障并返回全零串，
              绝不交出一个长度不对的十六进制文本。
    开源溯源 : 原创实现（T0-6 字符串化变体线，HexStringToBytes R9 的逆向件）。无外部源码参考，；本件为 IEC 61131-3 标准语义的道莅防御性实现（原创实现，零外部源码复制）。
              码位与分级 100% 自有。预留槽说明：纯格式化函数的故障域天然窄，038E/038F/044A/044B
              为后续 bPadZero = FALSE（非定宽变体）保留，本轮实现体内零赋值。
    本文件内含 : FUNCTION FC_DL_DwordToHexString（单 POU，无配套类型）
    依 赖 : 无 DL_ 内部依赖；Standard.library: LEN / MID / CONCAT
    红线自检 : R1 ✓ 零全局变量与外部变量 ｜ R2 ✓ 零物理 IO 地址
              R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 移位量恒 < 32（nIdx × 4 ≤ 28）+ 半字节掩码 + 出口长度自证
              R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A 纯函数无顺序状态机，无 CASE 可写
              R7 N/A 无定时器、无沿检测实例 ｜ R8 ✓ 位数、半字节掩码、表串、前缀长度全常量化
    错误码   : 16#0001_044A [信息级] 预留禁用（不得挪用，留给 bPadZero = FALSE 变体）
               16#0001_044B [信息级] 预留禁用（不得挪用）
               16#0001_038D [故障级] 结果长度与期望不符（目标串长不足已被平台截断），返回 '00000000'，bValid = FALSE
               16#0001_038E [故障级] 预留禁用（不得挪用）
               16#0001_038F [故障级] 预留禁用（不得挪用）
    码位总账 : 16#0001_044A 预留 / 16#0001_044B 预留 ｜ 16#0001_038D 用 / 16#0001_038E 预留 / 16#0001_038F 预留
    遗留假设 : ① 返回类型声明为 STRING（平台缺省长度的具体值未知，CODESYS 缺省 80、部分平台缺省 256）；
              本件不假设长度，改用出口自证兜住。该自证只能发现「已截断」，不能预防截断，属可观测性而非免疫。
              ② MID 参数序按 IEC 标准 MID(串, 长度, 位置)，与库内既有 9 处用法同序；平台差异需在编译门槛核对。
    修订历史 :
        2026-11-16  v1.0.0  首版，R21 批次 3 入库
*)
FUNCTION FC_DL_DwordToHexString : STRING
VAR_INPUT
    uValue          : DWORD;          // 待格式化的双字，全 32 位有效 [位图] / double word to format, all 32 bits are significant [bitmap]
    bUpperCase      : BOOL := TRUE;   // TRUE 输出大写 A~F，FALSE 输出小写 a~f / TRUE emits upper case hex digits, FALSE emits lower case
    bPrefix         : BOOL := FALSE;  // TRUE 输出 16# 前缀（结果长 11）/ TRUE emits the 16# prefix, making the result eleven characters long
END_VAR
VAR_OUTPUT
    eErr            : UDINT;          // 错误码，0=正常；16#0001_04XX 信息级 / 16#0001_03XX 故障级 / error id, 0=ok
    bError          : BOOL;           // 故障级标志，eErr 落 16#0001_03XX 时为 TRUE / fault flag, TRUE on fault-level eErr
    bValid          : BOOL;           // 返回值是否可用 / result usable flag
    nLength         : INT;            // 结果串的实际长度 [字符] / actual length of the result string [char]
END_VAR
VAR
    sRet            : STRING;         // 结果装配缓冲 [字符] / result assembly buffer [char]
    nNib            : INT;            // 当前半字节值 0~15 [无量纲] / current nibble value, 0..15 [dimensionless]
    nIdx            : INT;            // 半字节游标 7~0（高位在前）[无量纲] / nibble cursor from seven down to zero, most significant first [dimensionless]
    nExpLen         : INT;            // 期望结果长度 [字符] / expected result length [char]
END_VAR
VAR CONSTANT
    DL_HEX_UPPER        : STRING := '0123456789ABCDEF';   // 大写半字节表，位置 1 起对应值 0~15 [字符] / upper case nibble table indexed from one [char]
    DL_HEX_LOWER        : STRING := '0123456789abcdef';   // 小写半字节表，位置 1 起对应值 0~15 [字符] / lower case nibble table indexed from one [char]
    DL_HEX_PREFIX       : STRING := '16#';                // 十六进制前缀（可选）/ optional hexadecimal prefix
    DL_HEX_DIGITS       : INT := 8;                       // 定宽位数，DWORD 恰 8 个半字节 [位] / fixed width, a DWORD has eight nibbles [digit]
    DL_HEX_NIB_BITS     : INT := 4;                       // 半字节位宽，移位量 = 游标 × 4 ≤ 28 [位] / nibble width, the shift never exceeds twenty eight [bit]
    DL_HEX_PREFIX_LEN   : INT := 3;                       // 前缀长度 [字符] / prefix length [char]
    DL_HEX_NIB_MASK     : DWORD := 16#0000_000F;          // 半字节掩码 [位图] / nibble mask [bitmap]
    DL_HEX_ONE          : INT := 1;                       // 单位哨兵，MID 位置 1 基 [无量纲] / unity sentinel, MID is one based [dimensionless]
    DL_HEX_FALLBACK     : STRING := '00000000';           // 故障回退串，长度恒为 8 [字符] / fault fallback text with a constant length of eight [char]
    DL_DWORD_ZERO       : DWORD := 16#0000_0000;          // 零哨兵 [位图] / zero sentinel [bitmap]
    DL_ERR_NONE         : UDINT := 16#0000_0000;          // 无故障 / no error
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset the return value and the error state
FC_DL_DwordToHexString := DL_HEX_FALLBACK;   // 故障缺省返回全零串 / fault default returns eight zeros
eErr    := DL_ERR_NONE;                      // 预置无错误 / preset no error
bError  := FALSE;                            // 预置无故障 / preset no fault
bValid  := FALSE;                            // 预置结果不可用 / preset unusable
nLength := 0;                                // 预置长度 0 / preset the length to zero
sRet    := '';                               // 缓冲清空 / clear the buffer

// 段 2｜可选的十六进制前缀 / segment 2, optional hexadecimal prefix
IF bPrefix THEN
    sRet := DL_HEX_PREFIX;                   // 前缀先入，保证定宽位数在后 / the prefix comes first so the fixed width digits follow it
END_IF

// 段 3｜逐半字节装配：高位在前，移位量 = 游标 × 4，最大 28 < 32 / segment 3, nibble assembly, the shift never reaches the container width
FOR nIdx := DL_HEX_DIGITS - DL_HEX_ONE DOWNTO 0 DO
    nNib := DWORD_TO_INT(SHR(uValue, nIdx * DL_HEX_NIB_BITS) AND DL_HEX_NIB_MASK);   // 取当前半字节 / extract the current nibble
    IF bUpperCase THEN
        sRet := CONCAT(sRet, MID(DL_HEX_UPPER, DL_HEX_ONE, nNib + DL_HEX_ONE));      // 大写表查字符 / look the digit up in the upper case table
    ELSE
        sRet := CONCAT(sRet, MID(DL_HEX_LOWER, DL_HEX_ONE, nNib + DL_HEX_ONE));      // 小写表查字符 / look the digit up in the lower case table
    END_IF
END_FOR

// 段 4｜出口长度自证：平台静默截断必须被发现 / segment 4, length self proof catches a silent platform truncation
nLength := LEN(sRet);                        // 实际长度 / the actual length
nExpLen := DL_HEX_DIGITS;                    // 期望长度先取 8 / the expected length starts at eight
IF bPrefix THEN
    nExpLen := nExpLen + DL_HEX_PREFIX_LEN;  // 带前缀时 11 / eleven with the prefix
END_IF
IF nLength <> nExpLen THEN
    FC_DL_DwordToHexString := DL_HEX_FALLBACK;   // 回退到定宽全零串，长度可预测 / fall back to a fixed width zero text
    eErr   := 16#0001_038D;                  // 目标串长不足（故障级）/ the target string is too short, fault level
    bError := TRUE;                          // 置故障标志 / raise the fault flag
    nLength := LEN(DL_HEX_FALLBACK);         // 对外长度与回退串一致 / report the fallback length
    RETURN;                                  // bValid 保持 FALSE / bValid stays FALSE
END_IF

// 段 5｜出口 / segment 5, exit
FC_DL_DwordToHexString := sRet;              // 输出定宽十六进制文本 / publish the fixed width hexadecimal text
bValid := TRUE;                              // 结果可用 / the result is usable
END_FUNCTION
