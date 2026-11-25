(*==============================================================================
 * 名称 : FC_DL_WordsToDword —— 两个 WORD 合成 DWORD（显式高低序参数）
 * 分类 / 前缀 / 版本 : DL_Base / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 将两个 16 位 WORD 合成为 32 位 DWORD：bFirstIsHigh=TRUE 时 wFirst
 *            为高字、wSecond 为低字；FALSE 时角色对调。
 *            合成全程数值语义（WORD_TO_DWORD + SHL/OR），不触碰内存序。
 *            边界处理：两字覆盖完整 32 位，无溢出；与 FC_DL_DwordToWords 互为
 *            逆运算（同参数口径下往返一致）。
 * 错误码 : 无故障路径（全值域合法的纯合成），eErr 恒 0，bValid 恒 TRUE；
 *          16#0001_1A0B 为本件预留码位，当前实现不发出
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 移位量=16 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_WordsToDword : DWORD
VAR_INPUT
    wFirst      : WORD;    // 首个输入字 [位域] / first input word
    wSecond     : WORD;    // 第二个输入字 [位域] / second input word
    bFirstIsHigh: BOOL;    // TRUE=wFirst 为高字 / TRUE when wFirst is the high word
END_VAR
VAR_OUTPUT
    eErr   : UDINT;    // 故障码，0=正常（本件无故障路径）/ error code, 0=ok (no fault path)
    bError : BOOL;     // 故障标志，恒 FALSE / error flag, always FALSE
    bValid : BOOL;     // TRUE=返回值可用，恒 TRUE / TRUE when return value is usable
END_VAR
VAR
    _wHi : WORD;       // 判定后的高字 [位域] / resolved high word
    _wLo : WORD;       // 判定后的低字 [位域] / resolved low word
END_VAR

eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 本件全值域合法，恒可用 / always valid

IF bFirstIsHigh THEN                         // wFirst 为高字 / wFirst is high
    _wHi := wFirst;                          // 取 wFirst 为高字 / take wFirst as high
    _wLo := wSecond;                         // 取 wSecond 为低字 / take wSecond as low
ELSE                                         // wSecond 为高字 / wSecond is high
    _wHi := wSecond;                         // 取 wSecond 为高字 / take wSecond as high
    _wLo := wFirst;                          // 取 wFirst 为低字 / take wFirst as low
END_IF

FC_DL_WordsToDword := SHL(WORD_TO_DWORD(_wHi), 16) OR WORD_TO_DWORD(_wLo);    // 高字左移 16 位后并入低字（移位量 16<32 安全）/ compose

END_FUNCTION
