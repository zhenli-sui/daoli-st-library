(*==============================================================================
 * 名称 : FC_DL_BytesToWord —— 双字节按序组装 WORD（显式大小端参数）
 * 分类 / 前缀 / 版本 : DL_Base / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 将高/低两个 BYTE 按 bBigEndian 指定的顺序组装为 WORD：大端时
 *            byHi 为高 8 位、byLo 为低 8 位；小端时两者角色对调。
 *            装配全程使用数值语义（BYTE_TO_WORD + SHL/AND/OR），不触碰内存序。
 *            边界处理：byHi/byLo 全值域合法（BYTE 天然 ≤255），无溢出可能。
 * 错误码 : 无故障路径（全值域合法的纯装配），eErr 恒 0，bValid 恒 TRUE；
 *          16#0001_1A09 为本件预留码位，当前实现不发出
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC（禁指针/联合体）｜ R4 ✓ 移位量=8 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_BytesToWord : WORD
VAR_INPUT
    byHi       : BYTE;     // 语义高位字节 [0..255] / semantically high byte
    byLo       : BYTE;     // 语义低位字节 [0..255] / semantically low byte
    bBigEndian : BOOL;     // TRUE=大端装配（byHi 在高位）/ TRUE for big-endian assembly
END_VAR
VAR_OUTPUT
    eErr   : UDINT;    // 故障码，0=正常（本件无故障路径）/ error code, 0=ok (no fault path)
    bError : BOOL;     // 故障标志，恒 FALSE / error flag, always FALSE
    bValid : BOOL;     // TRUE=返回值可用，恒 TRUE / TRUE when return value is usable
END_VAR
VAR
    _wH : WORD;        // 高字节拓宽值 [0..255] / widened high byte
    _wL : WORD;        // 低字节拓宽值 [0..255] / widened low byte
END_VAR

eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 本件全值域合法，恒可用 / always valid

_wH := BYTE_TO_WORD(byHi);                   // 高字节零拓宽至 16 位（无符号安全）/ widen high byte zero-extended
_wL := BYTE_TO_WORD(byLo);                   // 低字节零拓宽至 16 位（无符号安全）/ widen low byte zero-extended

IF bBigEndian THEN                           // 大端：byHi 占高 8 位 / big-endian: byHi goes high
    FC_DL_BytesToWord := SHL(_wH, 8) OR _wL; // 高字节左移 8 位后并入低字节（移位量 8<16 安全）/ compose
ELSE                                         // 小端：byLo 占高 8 位 / little-endian: byLo goes high
    FC_DL_BytesToWord := SHL(_wL, 8) OR _wH; // 低字节左移 8 位后并入高字节 / compose swapped
END_IF

END_FUNCTION
