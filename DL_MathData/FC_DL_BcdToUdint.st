(*
    FC_DL_BcdToUdint —— 8 位十进制 BCD 码到 UDINT 防御转换
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
    功能说明  : 将 8 位十进制 BCD 码输入（每半字节 0~9）防御性转换为 UDINT 并返回；
                逐半字节合法性校验：任一半字节值 > 9（即 16#A~16#F 非法 BCD 码）判为
                故障级 16#0001_02A6，返回 0 且 bValid=FALSE；
                域内按半字节以 10 为基加权累加还原十进制值（乘子为常量基 10 的幂，
                最大权值 10^7、最大累加和 99999999，均在 UDINT 域内无溢出）；
                校验覆盖范围说明：UDINT 为 32 位容器，恰含 8 个 BCD 半字节（k=0..7），
                完整覆盖 8 位十进制域 0..99999999；k=8..15 的半字节在 32 位容器中不存在，
                且移位量 ≥32 属跨平台未定义行为，故不实施越界校验；
                本组件无钳位路径（非法半字节直接故障拦截，域内值精确还原）。
    错误码    : 16#0001_02A6 存在非法 BCD 半字节（半字节值 16#A~16#F）——故障级，返回 0
                16#0001_01D0 预留禁用（信息级，不得挪用）
                16#0001_01D1 预留禁用（信息级，不得挪用）
                16#0001_02A7 预留禁用（故障级，不得挪用）
                16#0001_02A8 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R16）
*)
FUNCTION FC_DL_BcdToUdint : UDINT
VAR_INPUT
    uBcd : UDINT; // 8 位十进制 BCD 码 [BCD 位]，每半字节 0~9 / 8-digit BCD code, each nibble 0~9
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_BCD_NIB_MASK : UDINT := 16#F;  // 半字节掩码 [BCD 位] / nibble mask
    DL_BCD_NIB_MAX  : UDINT := 16#9;  // 合法 BCD 半字节上界 9 [BCD 位] / valid BCD nibble upper bound 9
    DL_BCD_NIB_CNT  : INT   := 8;     // UDINT 32 位容器 BCD 半字节总数 [个] / total BCD nibble count of 32-bit UDINT container
    DL_DEC_BASE     : UDINT := 10;    // 十进制加权基 [基数] / decimal weighting base
END_VAR
VAR
    i       : INT;   // 半字节循环索引 [个] / nibble loop index
    uNib    : UDINT; // 当前半字节值 [BCD 位] / current nibble value
    uWeight : UDINT; // 当前半字节十进制权值（10^i） [倍] / current nibble decimal weight (10^i)
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_BcdToUdint := 0; // 故障缺省返回 0 [无量纲] / fault default returns 0
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障 / preset no fault
bValid := FALSE; // 预置无效，通过全半字节校验后置位 / preset invalid, set TRUE after all-nibble check passes

// 段 2｜逐半字节校验与十进制加权累加（末段） / segment 2, per-nibble validation and decimal weighted accumulation (final)
uWeight := 1; // 最低半字节权值 10^0 [倍] / lowest nibble weight 10^0
FOR i := 0 TO DL_BCD_NIB_CNT - 1 DO
    uNib := SHR(uBcd, 4 * i) AND DL_BCD_NIB_MASK; // 取第 i 个半字节（SHR 移位量 4*i ≤ 28 安全） / extract i-th nibble (shift 4*i <= 28, safe)
    IF uNib > DL_BCD_NIB_MAX THEN
        FC_DL_BcdToUdint := 0;    // 故障级返回 0，清除部分累加值 / fault level returns 0, clear partial accumulation
        eErr   := 16#0001_02A6;   // 非法 BCD 半字节故障码 / invalid BCD nibble fault id
        bError := TRUE;           // 置故障标志 / set fault flag
        bValid := FALSE;          // 输出无效 / output invalid
        RETURN;                   // 立即返回 / immediate return
    END_IF
    FC_DL_BcdToUdint := FC_DL_BcdToUdint + uNib * uWeight; // 半字节加权累加（最大 99999999 无溢出） / weighted accumulation (max 99999999, no overflow)
    uWeight := uWeight * DL_DEC_BASE; // 权值升位 ×10（最大 10^7，UDINT 域内无溢出） / weight times 10 (max 10^7, no UDINT overflow)
END_FOR
bError := FALSE; // 全部半字节合法，无故障 / all nibbles valid, no fault
bValid := TRUE;  // 输出有效可用 / output valid
END_FUNCTION
