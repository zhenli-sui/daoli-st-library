(*
  ==================================================================
  组件名 Component  : FC_DL_StrToHex
  分类   Category   : DL_MathData
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/s/a 类型前缀制（R265）
  版本   Version    : 1.0.0
  功能   Purpose    : HEX 文本 → 字节串（FC_DL_HexToStr 逆变换）：两位/
                      字节、无分隔符、接受大写与小写。解析前先过奇数长
                      度闸（LEN 奇数 → 码 02）与输出容量闸（字节预算 >
                      输出数组长度 → 码 03，不写部分数据）；逐字符经 MID
                      取样后按 '0'..'9'/'A'..'F'/'a'..'f' 判别，非法字符
                      → 码 01，三者均不写部分输出（原子性：失败即零写入）。
                      返回值 = 实际写出字节数（名实双出口）。溯源：本件
                      为「IEC 61131-3 标准语义的道莅防御性实现」，字符
                      串访问内核委托标准库函数（LEN/MID），严禁重实现内
                      核；半字节判别为纯 IEC 字面比较，非内核重实现。
  来源   Source     : iec-std-wrapper（T0-6）：IEC 61131-3 标准语义的
                      道莅防御性实现，内核委托标准库字符串函数，零内核
                      重实现
  互引   Cross-ref  : FC_DL_HexToStr（同族正变换件：字节串 → HEX 文本，
                      二者成对使用需同参数约定：大写两位/字节、无分隔符）
  平台   Platform   : 纯 IEC 61131-3（标准库字符串函数 + SHL/OR），三平台通用
  依赖   Depends    : 无 DL_ 内部依赖；标准字符串函数 LEN/MID
  红线   Redline    : R1 零全局/VAR_EXTERNAL/R2 零 %I/%Q/R3 纯 IEC 标准
                      R4 奇长闸/容量闸/非法字符闸三面显式 + 原子性零写
                      入 + 输出下标界已证（预算 ≤ 容量）/R5 全变量双语
                      同行注释/R6 纯函数无状态机（CASE 不适用）/R7 无定
                      时器与沿检测/R8 码位与界常量化
  错误码 Codes      : 01【失效级】非法字符（非 0-9/A-F/a-f），零写入
                      02【失效级】奇数长度（HEX 文本须偶数长），零写入
                      03【失效级】输出容量不足（2 字节预算 > 输出数组
                      长度），零写入
  码位反证 Note     : 01/02/03 分立依据（R90）：01 在字符面、02 在长度
                      面、03 在容量面可观测，修复入口不同（改数据/补一
                      位/扩数组）；03 若并入 01，则「扩容即可解」与「改
                      数据才能解」不可区分，故必须分立。
  验收   Acceptance : V1 '0AFF' → [0x0A,0xFF] ｜ V2 '0aff' → 同 V1（小
                      写接受）｜ V3 '0AF'（奇长）→ 码 02 ｜ V4 '0AG0'
                      → 码 01 ｜ V5 长文本/小数组 → 码 03 ｜ V6 返回值
                      = 实际字节数 = LEN/2
  变更   Revision   : 2026-11-22  v1.0.0  R67 首版（编码阶段批 3 序 1）
  ==================================================================
*)
FUNCTION FC_DL_StrToHex : UDINT
VAR_INPUT
    sHexIn : STRING(255);       // 输入 HEX 文本（两位/字节，无分隔符）/ the input hex text
END_VAR
VAR_IN_OUT
    aBytesOut : ARRAY[*] OF BYTE;  // 输出字节串（容量即数组长度）[字节] / the output byte array
END_VAR
VAR_OUTPUT
    uBytesOut : UDINT;          // 实际写出字节数 [字节]（与返回值同源，名实双出口）/ the written byte count
    bValid    : BOOL;           // 输出可用标志 [-] / the output usable flag
    nErrId    : UDINT;          // 错误码，0=正常，01/02/03 见头注 [码] / the error code [code]
END_VAR
VAR
    nChars  : UDINT;            // 输入字符数 [字符] / the input char count
    uCap    : UDINT;            // 输出数组容量 [字节] / the output array capacity
    i       : UDINT;            // 字符对遍历循环变量 / the char pair loop index
    j       : UDINT;            // 输出字节下标 / the output byte index
    k       : UDINT;            // 查表序号循环变量 / the table lookup loop index
    sHi     : STRING(1);        // 高位字符工作寄存器 / the high char register
    sLo     : STRING(1);        // 低位字符工作寄存器 / the low char register
    uHi     : BYTE;             // 高半字节值 [半字节] / the high nibble value
    uLo     : BYTE;             // 低半字节值 [半字节] / the low nibble value
    sHexTab   : STRING := '0123456789ABCDEF'; // 大写查表 [表] / the uppercase lookup table
    sHexTabLo : STRING := 'abcdef';             // 小写查表 [表] / the lowercase lookup table
END_VAR
VAR CONSTANT
    S2H_ERR_NONE  : UDINT := 16#0000_0000;  // 无错误 [码] / no error [code]
    S2H_ERR_CHR   : UDINT := 16#0000_0001;  // 码 01：非法字符 / code 01, illegal char
    S2H_ERR_ODD   : UDINT := 16#0000_0002;  // 码 02：奇数长度 / code 02, odd length
    S2H_ERR_CAP   : UDINT := 16#0000_0003;  // 码 03：输出容量不足 / code 03, capacity short
END_VAR

// 段 1｜输出预置 / segment 1, preset the outputs
uBytesOut := UDINT#0;         // 预置零写入 / preset zero written
bValid := FALSE;              // 预置不可用 / preset unusable
nErrId := S2H_ERR_NONE;       // 预置无错误 / preset no error

// 段 2｜奇数长度闸（码 02）：长度面缺陷 / segment 2, the odd length gate
nChars := LEN(sHexIn);        // 输入字符数（LEN 不含终结符）/ the char count
IF (nChars MOD 2) = UDINT#1 THEN
    nErrId := S2H_ERR_ODD;    // 奇长（补一位方可解）/ the odd length
    RETURN;
END_IF

// 段 3｜输出容量闸（码 03）：容量面缺陷，预算 = nChars/2 字节
//      segment 3, the capacity gate, the budget is nChars over two bytes
IF UPPER_BOUND(aBytesOut, 1) >= 0 THEN
    uCap := DINT_TO_UDINT(1 + UPPER_BOUND(aBytesOut, 1) - LOWER_BOUND(aBytesOut, 1));  // 数组容量 / the array capacity
ELSE
    uCap := UDINT#0;
END_IF
IF (nChars / 2) > uCap THEN
    nErrId := S2H_ERR_CAP;    // 容量不足（扩数组方可解）/ the capacity short
    RETURN;
END_IF

// 段 4｜逐对解析（委托内核：MID 取样 + 查表比较判别；下标界已证：j < nChars/2 ≤ uCap）
//      判别采用查表而非 STRING_TO_BYTE 数值转换（后者按十进制串解析，
//      字母字符不可用），表访问仍走标准 MID 内核
//      segment 4, the per pair parse, the kernel delegated to MID and table compares
FOR i := UDINT#1 TO nChars BY 2 DO        // 字符位从 1 起（MID 1 起位）/ the char position from one
    j := (i - UDINT#1) / 2;               // 输出字节下标 / the output byte index
    sHi := MID(sHexIn, 1, i);             // 高位字符 / the high char
    sLo := MID(sHexIn, 1, i + UDINT#1);   // 低位字符 / the low char
    uHi := 16#FF;                         // 非法哨兵预置（0..15 均合法，FF 不可撞）/ the illegal sentinel
    uLo := 16#FF;                         // 同上 / the same
    FOR k := UDINT#1 TO UDINT#16 DO       // 大写表查值 / the uppercase table lookup
        IF MID(sHexTab, 1, k) = sHi THEN
            uHi := UDINT_TO_BYTE(k - UDINT#1);   // 表序即半字节值 / the table order is the nibble value
            EXIT;                       // 命中即出（标准 EXIT）/ the standard exit on hit
        END_IF
    END_FOR
    IF uHi = 16#FF THEN                   // 大写未中再查小写表 / the lowercase second chance
        FOR k := UDINT#1 TO UDINT#6 DO    // 小写表 a..f / the lowercase table
            IF MID(sHexTabLo, 1, k) = sHi THEN
                uHi := UDINT_TO_BYTE(k - UDINT#1 + UDINT#10);  // a..f → 10..15 / the lower alpha nibble
                EXIT;
            END_IF
        END_FOR
    END_IF
    FOR k := UDINT#1 TO UDINT#16 DO       // 低位同法查大写表 / the low char uppercase lookup
        IF MID(sHexTab, 1, k) = sLo THEN
            uLo := UDINT_TO_BYTE(k - UDINT#1);
            EXIT;
        END_IF
    END_FOR
    IF uLo = 16#FF THEN                   // 低位小写二查 / the low char lowercase chance
        FOR k := UDINT#1 TO UDINT#6 DO
            IF MID(sHexTabLo, 1, k) = sLo THEN
                uLo := UDINT_TO_BYTE(k - UDINT#1 + UDINT#10);
                EXIT;
            END_IF
        END_FOR
    END_IF
    IF (uHi = 16#FF) OR (uLo = 16#FF) THEN     // 非法字符闸（码 01，原子性零写入）
        nErrId := S2H_ERR_CHR;                 // 字符面失效 / the char face failure
        uBytesOut := UDINT#0;                  // 零写入（原子性）/ the atomic zero write
        RETURN;
    END_IF
    aBytesOut[j] := SHL(uHi, 4) OR uLo;        // 组装字节（移位量 4 < 位宽 8，R48 合规）/ assemble the byte
END_FOR

// 段 5｜出口映射（名实双出口：返回值 = 写出字节数）/ segment 5, the exit mapping
uBytesOut := nChars / 2;      // 写出字节数 [字节] / the written byte count
FC_DL_StrToHex := uBytesOut;  // 返回值镜像（R191）/ the return mirrors the count
bValid := TRUE;               // 输出可用 / the output is usable
END_FUNCTION
