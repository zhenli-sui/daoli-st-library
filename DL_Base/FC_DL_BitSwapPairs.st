(*==============================================================================
 * 名称 : FC_DL_BitSwapPairs —— BYTE 内相邻比特对交换（4 对：0↔1,2↔3,4↔5,6↔7）
 * 分类 / 前缀 / 版本 : DL_Base / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 将 BYTE 的 4 个相邻位对两两交换后返回：偶数位整体左移 1、奇数位
 *            整体右移 1，再按位或合成（掩码 16#55 取偶位、16#AA 取奇位）。
 *            边界处理：全 0 / 全 1 / 对称位型（如 16#66）交换后为原值，属合法
 *            结果；移位量恒 1（< 8 位宽），结构性无越界移位。
 * 错误码 : 无故障路径（全值域合法的纯变换），eErr 恒 0，bValid 恒 TRUE；
 *          16#0001_1A06 为本件预留码位，当前实现不发出
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 移位量=1 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_BitSwapPairs : BYTE
VAR_INPUT
    byIn : BYTE;       // 待交换的输入字节 [位域] / input byte for pair swap
END_VAR
VAR_OUTPUT
    eErr   : UDINT;    // 故障码，0=正常（本件无故障路径）/ error code, 0=ok (no fault path)
    bError : BOOL;     // 故障标志，恒 FALSE / error flag, always FALSE
    bValid : BOOL;     // TRUE=返回值可用，恒 TRUE / TRUE when return value is usable
END_VAR
VAR
    _byEven : BYTE;    // 偶数位左移后的分量 [位域] / even-bit component shifted left
    _byOdd  : BYTE;    // 奇数位右移后的分量 [位域] / odd-bit component shifted right
END_VAR

eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 本件全值域合法，恒可用 / always valid

_byEven := SHL(byIn AND BYTE#16#55, 1);      // 偶位掩码后左移 1 位（<8 安全）/ even bits shifted up by one
_byOdd  := SHR(byIn AND BYTE#16#AA, 1);      // 奇位掩码后右移 1 位（<8 安全）/ odd bits shifted down by one
FC_DL_BitSwapPairs := _byEven OR _byOdd;     // 两分量按位或合成 / compose by bitwise or

END_FUNCTION
