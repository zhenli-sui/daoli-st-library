(*==============================================================================
 * 名称 : FC_DL_DwordsToLword —— 两个 DWORD 合成 LWORD（显式高低序参数）
 * 分类 / 前缀 / 版本 : DL_Base / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 将两个 32 位 DWORD 合成为 64 位 LWORD：bFirstIsHigh=TRUE 时 dwFirst
 *            为高 32 位、dwSecond 为低 32 位；FALSE 时角色对调。
 *            合成全程数值语义（DWORD_TO_LWORD + SHL/OR），不触碰内存序。
 *            边界处理：两双字覆盖完整 64 位，无溢出；与 FC_DL_LwordToDwords
 *            互为逆运算（同参数口径下往返一致）。
 * 错误码 : 无故障路径（全值域合法的纯合成），eErr 恒 0，bValid 恒 TRUE；
 *          16#0001_1A0E 为本件预留码位，当前实现不发出
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 移位量=32<64 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_DwordsToLword : LWORD
VAR_INPUT
    dwFirst     : DWORD;   // 首个输入双字 [位域] / first input dword
    dwSecond    : DWORD;   // 第二个输入双字 [位域] / second input dword
    bFirstIsHigh: BOOL;    // TRUE=dwFirst 为高 32 位 / TRUE when dwFirst is the high half
END_VAR
VAR_OUTPUT
    eErr   : UDINT;    // 故障码，0=正常（本件无故障路径）/ error code, 0=ok (no fault path)
    bError : BOOL;     // 故障标志，恒 FALSE / error flag, always FALSE
    bValid : BOOL;     // TRUE=返回值可用，恒 TRUE / TRUE when return value is usable
END_VAR
VAR
    _dwHi : DWORD;     // 判定后的高 32 位 / resolved high dword
    _dwLo : DWORD;     // 判定后的低 32 位 / resolved low dword
END_VAR

eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 本件全值域合法，恒可用 / always valid

IF bFirstIsHigh THEN                         // dwFirst 为高 32 位 / dwFirst is high
    _dwHi := dwFirst;                        // 取 dwFirst 为高 / take dwFirst as high
    _dwLo := dwSecond;                       // 取 dwSecond 为低 / take dwSecond as low
ELSE                                         // dwSecond 为高 32 位 / dwSecond is high
    _dwHi := dwSecond;                       // 取 dwSecond 为高 / take dwSecond as high
    _dwLo := dwFirst;                        // 取 dwFirst 为低 / take dwFirst as low
END_IF

FC_DL_DwordsToLword := SHL(DWORD_TO_LWORD(_dwHi), 32) OR DWORD_TO_LWORD(_dwLo);    // 高 32 位左移后并入低 32 位（移位量 32<64 安全）/ compose

END_FUNCTION
