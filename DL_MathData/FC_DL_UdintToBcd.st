(*
    FC_DL_UdintToBcd —— UDINT 到 8 位十进制 BCD 码饱和防御转换
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托平台内建函数，外围统一错误码/钳位/双语文档；
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R16）
    ------------------------------------------------------------------
    功能说明  : 将十进制值 nIn（0..99999999）防御性转换为 8 位十进制 BCD 码并返回；
                nIn 超出 99999999 时饱和输出 BCD 码 16#99999999，置信息级 16#0001_01D2
                （与 R9 FC_DL_WordToBcd 的 9999 饱和口径一致，域扩大 4 位）；
                钳位方向：仅上界单侧饱和至 16#99999999；
                域内按除 10 取余逐位拼装半字节：除子为常量 10，编译期恒非零，
                满足除法前判除子非零红线；8 次整除后余数归零，无溢出路径；
                纯整数域输入不存在 NaN/±INF 非有限态，故本组件无故障级路径；
                信息级码属正常防御：bError=FALSE、bValid=TRUE，输出饱和后防御值。
    错误码    : 16#0001_01D2 输入超 99999999，已饱和至 BCD 16#99999999——信息级，正常防御
                16#0001_01D3 预留禁用（信息级，不得挪用）
                16#0001_02A9 预留禁用（故障级，不得挪用）
                16#0001_02AA 预留禁用（故障级，不得挪用）
                16#0001_02AB 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R16）
*)
FUNCTION FC_DL_UdintToBcd : UDINT
VAR_INPUT
    nIn : UDINT; // 十进制值 [0..99999999] / decimal value, 0..99999999
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_BCD8_MAX    : UDINT := 99999999;    // 8 位 BCD 十进制域上界 [无量纲] / 8-digit BCD decimal domain upper bound
    DL_BCD8_SAT    : UDINT := 16#99999999; // 8 位 BCD 饱和输出码（每位半字节 9） [BCD 位] / 8-digit BCD saturating output code (nibble 9 each)
    DL_BCD_NIB_CNT : INT   := 8;           // UDINT 32 位容器 BCD 半字节总数 [个] / total BCD nibble count of 32-bit UDINT container
    DL_DEC_BASE    : UDINT := 10;          // 十进制除法基（编译期常量，恒非零） [基数] / decimal division base (compile-time constant, never zero)
END_VAR
VAR
    i      : INT;   // 半字节循环索引 [个] / nibble loop index
    uDigit : UDINT; // 当前十进制位值（0~9） [位] / current decimal digit value (0~9)
    uTmp   : UDINT; // 剩余待转换商 [无量纲] / remaining quotient to convert
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_UdintToBcd := 0; // 故障缺省返回 0 [BCD 位] / fault default returns 0
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障（整数域无故障态） / preset no fault (no fault states in integer domain)
bValid := FALSE; // 预置无效，通过饱和判定后置位 / preset invalid, set TRUE after saturation check

// 段 2｜上界单侧饱和钳位 / segment 2, upper-bound saturating clamp
IF nIn > DL_BCD8_MAX THEN
    FC_DL_UdintToBcd := DL_BCD8_SAT; // 饱和输出 BCD 16#99999999（与 R9 WordToBcd 口径一致，域扩大 4 位） / saturate to BCD 16#99999999 (aligned with R9 WordToBcd policy, domain widened by 4 digits)
    eErr := 16#0001_01D2;            // 信息级：超上界已饱和 / info level: above upper bound, saturated
    bError := FALSE;                 // 信息级饱和不置故障 / info-level saturation never raises fault
    bValid := TRUE;                  // 饱和输出有效可用 / saturated output is valid
    RETURN;                          // 立即返回 / immediate return
END_IF

// 段 3｜除 10 取余逐位拼装主体计算（末段） / segment 3, divide-by-10 remainder digit assembly main conversion (final)
uTmp := nIn; // 商初始化为输入值 / initialize quotient with input
FOR i := 0 TO DL_BCD_NIB_CNT - 1 DO
    uDigit := uTmp MOD DL_DEC_BASE;       // 除 10 取余得当前十进制位（除子常量 10 恒非零） / modulo 10 for current digit (constant divisor 10, never zero)
    FC_DL_UdintToBcd := FC_DL_UdintToBcd OR SHL(uDigit, 4 * i); // 拼装第 i 个 BCD 半字节（SHL 移位量 4*i ≤ 28 安全） / assemble i-th BCD nibble (shift 4*i <= 28, safe)
    uTmp := uTmp / DL_DEC_BASE;           // 整除 10 前进到下一位（除子常量 10 恒非零） / integer-divide by 10 to next digit (constant divisor 10, never zero)
END_FOR
bError := FALSE; // 域内转换无故障 / in-domain conversion, no fault
bValid := TRUE;  // 输出有效可用 / output valid
END_FUNCTION
