(*==============================================================================
 * 名称 : FC_DL_BitReverse8 —— BYTE 位序完全反转（bit0↔bit7 镜像）
 * 分类 / 前缀 / 版本 : DL_Base / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 将 BYTE 的 8 个位按镜像序重排后返回（第 i 位映射到第 7-i 位）。
 *            边界处理：全 0 / 全 1 / 回文位型（如 16#18）均原值返回，属合法结果；
 *            循环固定 8 次，无越界移位（i 与 7-i 均 ≤7 < 8 位宽）。
 * 错误码 : 无故障路径（全值域合法的纯变换），eErr 恒 0，bValid 恒 TRUE；
 *          16#0001_1A02 为本件预留码位，当前实现不发出
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 移位量≤7 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_BitReverse8 : BYTE
VAR_INPUT
    byIn : BYTE;       // 待反转的输入字节 [位域] / input byte to be bit-reversed
END_VAR
VAR_OUTPUT
    eErr   : UDINT;    // 故障码，0=正常（本件无故障路径）/ error code, 0=ok (no fault path)
    bError : BOOL;     // 故障标志，恒 FALSE / error flag, always FALSE
    bValid : BOOL;     // TRUE=返回值可用，恒 TRUE / TRUE when return value is usable
END_VAR
VAR
    _i     : INT;      // 位扫描游标 [位] / bit scan cursor
    _dwBit : BYTE;     // 当前读出位对应的单比特值 [位域] / single-bit walker for read side
END_VAR

FC_DL_BitReverse8 := BYTE#16#00;             // 返回值预设全 0 / preset return to zero
eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 本件全值域合法，恒可用 / always valid

FOR _i := 0 TO 7 DO                          // 逐位镜像搬运 / mirror bits one by one
    _dwBit := SHL(BYTE#16#01, _i);           // 读侧单比特（_i≤7 安全）/ single bit on read side
    IF (byIn AND _dwBit) <> BYTE#16#00 THEN  // 源位为 1 才搬运 / copy only when source bit set
        FC_DL_BitReverse8 := FC_DL_BitReverse8 OR SHL(BYTE#16#01, 7 - _i);    // 写入镜像位（7-_i≤7 安全）/ set mirrored bit
    END_IF
END_FOR

END_FUNCTION
