(*
  ==================================================================
  组件名 Component  : FC_DL_DtlStringConv
  分类   Category   : DL_MathData
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : 日期时间 ↔ ASCII 串双向转换。定长 19 字符格式
                      'YYYY-MM-DD HH:MM:SS'。eStrToComp：串 → 六分量（分隔符
                      与数字位逐一校验，FIND 数字表解码）；eCompToStr：六分量
                      → 串（数字查表装配）。超长按 19 截断评估并置 bTrunc
                      （255 截断标志语义：入串超库上限 255 或超定长均置位）。
                      LGF Converter 组 DTL↔String 语义 clean-room。
  来源   Source     : T2-1-lgf-converter（LGF Converter 组 DTL↔String 语义）
  溯源   Origin     : 定长日期串装配/解析为公开工程语义，clean-room 自研实现，
                      未复制 LGF 或任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: LEN / MID / CONCAT /
                      FIND，无私有库）
  分工声明 Split     : 与 FC_DL_AsciiFrameParse 分工——后者做 STX/ETX 仪表
                      帧解析，本件做定长日期时间串双向转换。
  作者   Author     : 道莅代码库 · PLC 编程专家（R59）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 值域闸（eCompToStr）：年 1970..2999 / 月 1..12 /
                         日 1..31 / 时 0..23 / 分秒 0..59，越域置 bError；
                      二 格式闸（eStrToComp）：定长 19、分隔符位置（5/8 =
                         '-'，11 = ' '，14/17 = ':'）、数字位非数字 → bError；
                      三 255 截断标志：LEN > 19 按前 19 位截断评估并置
                         bTrunc（信息级），LEN > 255 直接置 bError；
                      四 无除法无浮点（纯整数与串操作，无除零/非有限风险）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R59 首版（批 2 · 序号 6）
  ==================================================================
*)

TYPE E_DL_DtcMode :
(
    eStrToComp := 0, // 串 → 六分量 / the string to components direction
    eCompToStr := 1  // 六分量 → 串 / the components to string direction
);
END_TYPE

FUNCTION FC_DL_DtlStringConv : BOOL
VAR_INPUT
    eMode   : E_DL_DtcMode; // 转换方向枚举 [-] / the conversion direction enum
    sIn     : STRING(255) := ''; // 入串（eStrToComp 方向）[-] / the input string, the to components entry
    nYear   : DINT := 2000; // 年分量 [年]，域 1970..2999，eCompToStr 方向 / the year component
    nMonth  : DINT := 1;    // 月分量 [月]，域 1..12 / the month component
    nDay    : DINT := 1;    // 日分量 [日]，域 1..31 / the day component
    nHour   : DINT := 0;    // 时分量 [时]，域 0..23 / the hour component
    nMinute : DINT := 0;    // 分分量 [分]，域 0..59 / the minute component
    nSecond : DINT := 0;    // 秒分量 [秒]，域 0..59 / the second component
END_VAR
VAR_OUTPUT
    sOut    : STRING(23) := ''; // 出串 'YYYY-MM-DD HH:MM:SS' [-] / the output string, the fixed format
    oYear   : DINT := 0;   // 年分量输出 [年] / the year outlet
    oMonth  : DINT := 0;   // 月分量输出 [月] / the month outlet
    oDay    : DINT := 0;   // 日分量输出 [日] / the day outlet
    oHour   : DINT := 0;   // 时分量输出 [时] / the hour outlet
    oMinute : DINT := 0;   // 分分量输出 [分] / the minute outlet
    oSecond : DINT := 0;   // 秒分量输出 [秒] / the second outlet
    bValid  : BOOL := FALSE; // 结果可用标志 [-] / the result usable flag
    bTrunc  : BOOL := FALSE; // 截断标志（入串超定长 19 按前 19 位评估）[-] / the truncation flag, the long input evaluated by the first nineteen
    bError  : BOOL := FALSE; // 故障标志（格式/值域/超 255）[-] / the fault flag
END_VAR
VAR CONSTANT
    DL_DTC_DIGITS : STRING(10) := '0123456789'; // 数字字符表（FIND 解码基准）/ the digit table for the FIND decoding
    DL_DTC_LENFIX : DINT := 19; // 定长 [字符] / the fixed length
    DL_DTC_LENMAX : DINT := 255; // 库串上限 [字符] / the library string cap
END_VAR
VAR
    nLen   : DINT;  // 入串长度 [字符] / the input length
    sCh    : STRING(1); // 单字符工作量 [-] / the one char work value
    nPos   : DINT;  // 字表命中位（0 = 非数字）[位] / the table hit position, zero means non digit
    nI     : DINT;  // 数字位遍历索引 [位] / the digit position index
    nJ     : DINT;  // 字段遍历索引 [个] / the field index
    nVal   : DINT;  // 字段解析值工作量 [-] / the field parsed value work
    nDiv   : DINT;  // 位除子工作量（10 的幂，DINT 整除取位）[-] / the digit divisor, a power of ten
    aVal   : ARRAY[0..5] OF DINT; // 六分量装配工作数组 / the six component work array
    aField : ARRAY[0..5] OF DINT; // 六字段起始位组（1 基）/ the six field start positions, one based
    aWidth : ARRAY[0..5] OF DINT; // 六字段宽度组 [字符] / the six field widths
    aSep   : ARRAY[0..5] OF STRING(1); // 字段间分隔符组（末项空）/ the separators, the last empty
    bNeg   : BOOL;  // 保留（本件无符号语义，恒假）[-] / reserved, constant false
END_VAR

// 段 1｜返回值与输出预置（四段式第一段，R45）/ segment 1, preset the return and the outputs
FC_DL_DtlStringConv := FALSE; // 受理预置假 / preset the accepted false
sOut := ''; // 出串预置空 / preset the output empty
oYear := 0; oMonth := 0; oDay := 0; // 分量输出预置零 / preset the outlets zero
oHour := 0; oMinute := 0; oSecond := 0; // 分量输出预置零 / preset the outlets zero
bValid := FALSE; // 有效预置假 / preset the valid false
bTrunc := FALSE; // 截断预置假 / preset the trunc false
bError := FALSE; // 故障预置假 / preset the fault false
bNeg := FALSE; // 保留位恒假 / the reserved constant false

// 段 2｜方向一：串 → 六分量（格式闸 + 数字表解码 + 值域闸）/ segment 2, the string to components direction
IF eMode = E_DL_DtcMode.eStrToComp THEN // 方向一受理 / the direction one
    nLen := LEN(sIn); // 取长 / take the length
    IF nLen > DL_DTC_LENMAX THEN // 超 255 库上限：故障级 / beyond the cap, fault grade
        bError := TRUE; // 置故障 / raise the fault
        RETURN; // 早退 / return early
    END_IF
    IF nLen > DL_DTC_LENFIX THEN // 超定长：按前 19 位截断评估（信息级）/ beyond the fixed length, evaluate by the head
        bTrunc := TRUE; // 置截断标志 / raise the truncation
    ELSIF nLen < DL_DTC_LENFIX THEN // 短于定长：格式故障 / shorter than the fixed length
        bError := TRUE; // 置故障 / raise the fault
        RETURN; // 早退 / return early
    END_IF
    aField[0] := 1;  aWidth[0] := 4; // 年字段 YYYY / the year field
    aField[1] := 6;  aWidth[1] := 2; // 月字段 MM / the month field
    aField[2] := 9;  aWidth[2] := 2; // 日字段 DD / the day field
    aField[3] := 12; aWidth[3] := 2; // 时字段 HH / the hour field
    aField[4] := 15; aWidth[4] := 2; // 分字段 MI / the minute field
    aField[5] := 18; aWidth[5] := 2; // 秒字段 SS / the second field
    FOR nJ := 0 TO 5 DO // 逐字段解析 / per field parse
        nVal := 0; // 字段值清零 / clear the field value
        FOR nI := 0 TO aWidth[nJ] - 1 DO // 逐数字位 / per digit position
            sCh := MID(sIn, 1, aField[nJ] + nI); // 取单字符 / take one char
            nPos := FIND(DL_DTC_DIGITS, sCh); // 字表命中位 / the table hit position
            IF nPos = 0 THEN // 非数字字符 / a non digit char
                bError := TRUE; // 置故障（非法字符闸）/ raise the fault
                RETURN; // 早退 / return early
            END_IF
            nVal := (nVal * 10) + (nPos - 1); // 十进制装配 / assemble the decimal
        END_FOR
        aVal[nJ] := nVal; // 记字段值 / store the field value
    END_FOR
    IF (MID(sIn, 1, 5) <> '-') OR (MID(sIn, 1, 8) <> '-')
    OR (MID(sIn, 1, 11) <> ' ') OR (MID(sIn, 1, 14) <> ':')
    OR (MID(sIn, 1, 17) <> ':') THEN // 分隔符位置闸 / the separator gates
        bError := TRUE; // 置故障 / raise the fault
        RETURN; // 早退 / return early
    END_IF
    IF (aVal[0] < 1970) OR (aVal[0] > 2999) OR (aVal[1] < 1) OR (aVal[1] > 12)
    OR (aVal[2] < 1) OR (aVal[2] > 31) OR (aVal[3] > 23)
    OR (aVal[4] > 59) OR (aVal[5] > 59) THEN // 值域闸（边界一）/ the value domain gates
        bError := TRUE; // 置故障 / raise the fault
        RETURN; // 早退 / return early
    END_IF
    oYear := aVal[0]; oMonth := aVal[1]; oDay := aVal[2]; // 分量出口 / the outlets
    oHour := aVal[3]; oMinute := aVal[4]; oSecond := aVal[5]; // 分量出口 / the outlets
    bValid := TRUE; // 结果可用 / the result usable
    FC_DL_DtlStringConv := TRUE; // 受理 / accept

// 段 3｜方向二：六分量 → 串（值域闸 + 数字查表装配）/ segment 3, the components to string direction
ELSIF eMode = E_DL_DtcMode.eCompToStr THEN // 方向二受理 / the direction two
    IF (nYear < 1970) OR (nYear > 2999) OR (nMonth < 1) OR (nMonth > 12)
    OR (nDay < 1) OR (nDay > 31) OR (nHour > 23) OR (nHour < 0)
    OR (nMinute > 59) OR (nMinute < 0) OR (nSecond > 59) OR (nSecond < 0) THEN // 值域闸（边界一）/ the value domain gates
        bError := TRUE; // 置故障 / raise the fault
        RETURN; // 早退 / return early
    END_IF
    aVal[0] := nYear; aVal[1] := nMonth; aVal[2] := nDay; // 装配值组 / load the values
    aVal[3] := nHour; aVal[4] := nMinute; aVal[5] := nSecond; // 装配值组 / load the values
    aField[0] := 4; aField[1] := 2; aField[2] := 2; // 宽度组 / the widths
    aField[3] := 2; aField[4] := 2; aField[5] := 2; // 宽度组 / the widths
    aSep[0] := '-'; aSep[1] := '-'; aSep[2] := ' '; // 分隔符组 / the separators
    aSep[3] := ':'; aSep[4] := ':'; aSep[5] := '';  // 分隔符组（末项空）/ the separators, the last empty
    sOut := ''; // 出串清零 / clear the output
    FOR nJ := 0 TO 5 DO // 逐字段装配 / per field assembly
        sOut := CONCAT(sOut, aSep[nJ]); // 先接分隔符 / append the separator first
        nDiv := 1; // 位除子起步（10^(宽-1)）/ the divisor starts at one
        FOR nI := 1 TO aField[nJ] - 1 DO // 宽度减一次乘十 / the width minus one multiplies by ten
            nDiv := nDiv * 10; // 除子推进 / advance the divisor
        END_FOR
        FOR nI := 1 TO aField[nJ] DO // 高位到低位逐位 / per digit from the high position down
            sCh := MID(DL_DTC_DIGITS, 1, ((aVal[nJ] / nDiv) MOD 10) + 1); // DINT 整除取位查表（无浮点无 EXPT）/ the DINT divide and pick by the table
            sOut := CONCAT(sOut, sCh); // 接字符 / append the char
            nDiv := nDiv / 10; // 除子降位 / drop the divisor one decade
        END_FOR
    END_FOR
    bValid := TRUE; // 结果可用 / the result usable
    FC_DL_DtlStringConv := TRUE; // 受理 / accept
ELSE // 非法方向枚举兜底 / the illegal direction fallback
    bError := TRUE; // 置故障 / raise the fault
END_IF
END_FUNCTION
