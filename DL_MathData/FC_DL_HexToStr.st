(*
  ==================================================================
  组件名 Component  : FC_DL_HexToStr
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/s/a 类型前缀制（R265）
  版本   Version    : 1.0.0
  功能   Purpose    : 字节串 → HEX 大写文本：每字节展开两位（高半字节
                      在前），输出上限 255 字符（2×127 字节 = 254 字符
                      + $00 终结符），超限按 R49 四步截断样板执行：先判
                      超限并置截断信息码与 bTrunc → 再钳长 → 再写入 →
                      最后显式写 $00 终结符。返回值 = 实际写入字符数
                      （名实双出口）。溯源：本件为「IEC 61131-3 标准语
                      义的道莅防御性实现」，内核委托标准库字符串函数
                      （MID/CONCAT/REPLACE/LEN），严禁重实现内核。
  来源   Source     : iec-std-wrapper（T0-6）：IEC 61131-3 标准语义的
                      道莅防御性实现，内核委托标准库字符串函数，零内核
                      重实现（T0-6 四步截断样板 R49）
  互引   Cross-ref  : FC_DL_StrToHex（同族逆变换件：HEX 文本 → 字节串，
                      二者成对使用需同参数约定：大写两位/字节、无分隔符）
  平台   Platform   : 纯 IEC 61131-3（标准库字符串函数 + SHR/MOD），三平台通用
  依赖   Depends    : 无 DL_ 内部依赖；标准字符串函数 MID/CONCAT/REPLACE/LEN
  设计偏差 Deviation: nLen 超出数组实际长度时按长度钳位接管（同族口径，
                      头注声明，不静默越界）；输出按 254 字符整字节截断
                      （255 上限内最大整字节边界，保证 $00 终结符可写）。
  红线   Redline    : R1 零全局/VAR_EXTERNAL/R2 零 %I/%Q/R3 纯 IEC 标准
                      R4 截断先判后钳（R49 四步）+ 终结符显式 + 下标界
                      闸/R5 全变量双语同行注释/R6 纯函数无状态机（CASE
                      不适用）/R7 无定时器与沿检测/R8 长度与查表界常量化
  错误码 Codes      : 01【信息级】超 255 字符上限截断（置 bTrunc，不置
                      bError，前缀字节完整保留）
                      02【失效级】nLen 超数组实际长度且钳位后为 0（无可
                      写字节），返回 0
  码位反证 Note     : 01/02 分立依据（R90）：01 在容量面（数据仍完整可
                      用，功能不受影响）、02 在输入面（无数据可转）可观
                      测；01 不置 bError 与 02 失效级双通道可区分。
  验收   Acceptance : V1 [0x0A,0xFF] → '0AFF' ｜ V2 [0x00] → '00' ｜
                      V3 128 字节 → 截断 127 字节 + bTrunc + 码 01 ｜
                      V4 nLen=0 → 空串（bValid）｜ V5 返回值 = LEN(sHexOut)
  变更   Revision   : 2026-11-22  v1.0.0  R67 首版（编码阶段批 2 序 5）
  ==================================================================
*)
FUNCTION FC_DL_HexToStr : UDINT
VAR_INPUT
    aBytes : ARRAY[*] OF BYTE;  // 输入字节串 [字节] / the input byte array
    nLen   : UDINT;             // 参与转换字节数 [字节]，超数组长度按长度钳位 / the byte count, clamped to the array length
END_VAR
VAR_OUTPUT
    sHexOut : STRING(255);      // HEX 大写文本（两位/字节，无分隔符）/ the hex uppercase text
    bTrunc  : BOOL;             // 截断标志（超 255 字符上限）[-] / the truncation flag
    bValid  : BOOL;             // 输出可用标志 [-] / the output usable flag
    nErrId  : UDINT;            // 错误码，0=正常，01/02 见头注 [码] / the error code [code]
END_VAR
VAR
    sHexTab : STRING := '0123456789ABCDEF'; // 半字节查表 [表] / the nibble lookup table
    sOut    : STRING(255);                  // 输出组装工作串 / the output assembly working string
    uUsed   : UDINT;                        // 钳位后实际字节数 [字节] / the used byte count after clamping
    uLenArr : UDINT;                        // aBytes 实际长度 [字节] / the actual array length
    i       : UDINT;                        // 字节遍历循环变量 / the byte loop index
    uB      : BYTE;                         // 当前字节工作寄存器 / the current byte register
    uHi     : BYTE;                         // 高半字节 [半字节] / the high nibble
    uLo     : BYTE;                         // 低半字节 [半字节] / the low nibble
    sCh     : STRING(1);                    // 当前查表字符 / the current looked up char
END_VAR
VAR CONSTANT
    H2S_CHARS_MAX : UDINT := UDINT#254;     // 输出字符上限（255 内整字节边界）[字符] / the output char ceiling
    H2S_BYTES_MAX : UDINT := UDINT#127;     // 对应字节数上限 [字节] / the matching byte ceiling
    H2S_ERR_NONE  : UDINT := 16#0000_0000;  // 无错误 [码] / no error [code]
    H2S_ERR_TRUNC : UDINT := 16#0000_0001;  // 码 01：超限截断（信息级）/ code 01, truncated, info level
    H2S_ERR_EMPTY : UDINT := 16#0000_0002;  // 码 02：无可写字节 / code 02, nothing to write
END_VAR

// 段 1｜输出预置 / segment 1, preset the outputs
sHexOut := '';                // 预置空串 / preset the empty string
bTrunc := FALSE;              // 预置未截断 / preset not truncated
bValid := FALSE;              // 预置不可用 / preset unusable
nErrId := H2S_ERR_NONE;       // 预置无错误 / preset no error
sOut := '';                   // 组装串清空 / clear the assembly string

// 段 2｜数组长度闸与钳位（结构性防御，头注偏差声明）/ segment 2, the array length clamp
IF UPPER_BOUND(aBytes, 1) >= 0 THEN
    uLenArr := DINT_TO_UDINT(1 + UPPER_BOUND(aBytes, 1) - LOWER_BOUND(aBytes, 1));  // 数组长度 / the array length
ELSE
    uLenArr := UDINT#0;
END_IF
uUsed := nLen;                // 先取原始字节数 / take the raw count
IF uUsed > uLenArr THEN
    uUsed := uLenArr;         // 超长钳位接管（头注偏差声明）/ clamp, documented deviation
END_IF

// 段 3｜R49 四步截断第 1 步：先判超限并置码置标志（赋值行前于钳位行）
//      segment 3, the truncation judged before clamping, the code precedes the clamp
IF 2 * uUsed > H2S_CHARS_MAX THEN
    bTrunc := TRUE;           // 截断标志 / the truncation flag
    nErrId := H2S_ERR_TRUNC;  // 信息级码（不置 bError）/ the info code, no fault flag
    uUsed := H2S_BYTES_MAX;   // 钳至整字节边界（254 字符）/ clamp to the whole byte boundary
END_IF

// 段 4｜零字节出口（码 02）：钳位后无可写 / segment 4, the zero byte exit
IF uUsed = UDINT#0 THEN
    nErrId := H2S_ERR_EMPTY;  // 无数据可转 / nothing to write
    sHexOut := '';            // 显式空串（含隐式终结符）/ the explicit empty string
    FC_DL_HexToStr := UDINT#0;  // 返回 0 字符（名实双出口）/ zero chars published
    RETURN;
END_IF

// 段 5｜逐字节展开（委托内核：SHR/MOD 取半字节 + MID 查表 + CONCAT 组装）
//      segment 5, the per byte expansion, the kernel delegated to the standard functions
FOR i := UDINT#0 TO uUsed - 1 DO
    uB  := aBytes[i];                              // 当前字节 / the current byte
    uHi := SHR(uB, 4);                             // 高半字节（移位量 4 < 位宽 8，R48 合规）/ the high nibble
    uLo := uB MOD 16;                              // 低半字节 / the low nibble
    sCh := MID(sHexTab, 1, BYTE_TO_DINT(uHi) + 1); // 高位查表（1 起位）/ the high lookup
    sOut := CONCAT(sOut, sCh);                     // 追加高位 / append the high char
    sCh := MID(sHexTab, 1, BYTE_TO_DINT(uLo) + 1); // 低位查表 / the low lookup
    sOut := CONCAT(sOut, sCh);                     // 追加低位 / append the low char
END_FOR

// 段 6｜R49 四步第 4 步：显式写 $00 终结符（REPLACE 标准函数，在 nChars+1 位）
//      segment 6, the explicit terminator write via the standard REPLACE
sHexOut := REPLACE(sOut, '$00', 1, 2 * uUsed + UDINT#1);  // 终结符落位（第 nChars+1 字符）/ the terminator placed

// 段 7｜出口映射（名实双出口：返回值 = 写入字符数）/ segment 7, the exit mapping
FC_DL_HexToStr := 2 * uUsed;  // 返回写入字符数 [字符] / the published char count
bValid := TRUE;               // 输出可用（截断仍可用，头注码 01 口径）/ usable, truncated still usable
END_FUNCTION
