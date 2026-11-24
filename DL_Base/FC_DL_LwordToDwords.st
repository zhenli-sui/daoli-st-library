(*==============================================================================
 * 名称 : FC_DL_LwordToDwords —— LWORD 拆解为两个 DWORD（本件返回首 DWORD，dwOther 为次字）
 * 分类 / 前缀 / 版本 : DL_Base / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 将 64 位输入拆为高/低两个 32 位 DWORD。bHiFirst=TRUE 时首字（返回值）
 *            为高 32 位、次字（dwOther）为低 32 位；FALSE 时角色对调。
 *            拆解全程数值语义（移位 + 掩码），不触碰内存字节序。
 *            边界处理：lwIn 全值域合法，高低双字覆盖完整 64 位，无信息丢失。
 * 错误码 : 无故障路径（全值域合法的纯拆解），eErr 恒 0，bValid 恒 TRUE；
 *          16#0001_1A0D 为本件预留码位，当前实现不发出
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 移位量=32<64 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_LwordToDwords : DWORD
VAR_INPUT
    lwIn     : LWORD;    // 待拆解的 64 位输入 [位域] / input lword to be split
    bHiFirst : BOOL;     // TRUE=首字取高 32 位 / TRUE when first dword is the high half
END_VAR
VAR_OUTPUT
    dwOther : DWORD;   // 次字（另一半 32 位）/ the other (second) dword
    eErr    : UDINT;   // 故障码，0=正常（本件无故障路径）/ error code, 0=ok (no fault path)
    bError  : BOOL;    // 故障标志，恒 FALSE / error flag, always FALSE
    bValid  : BOOL;    // TRUE=首/次两字均可用，恒 TRUE / TRUE when both dwords are usable
END_VAR
VAR
    _dwHi : DWORD;     // 高 32 位双字 [位域] / high dword
    _dwLo : DWORD;     // 低 32 位双字 [位域] / low dword
END_VAR

eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 本件全值域合法，恒可用 / always valid

_dwHi := LWORD_TO_DWORD(SHR(lwIn, 32));      // 右移 32 位取高双字（移位量 32<64 安全）/ high dword via shift
_dwLo := LWORD_TO_DWORD(lwIn AND 16#0000_0000_FFFF_FFFF);    // 低 32 位掩码后截取 / low dword via mask

IF bHiFirst THEN                             // 首字 = 高 32 位 / first dword is high half
    FC_DL_LwordToDwords := _dwHi;            // 返回首字为高双字 / return high as first
    dwOther := _dwLo;                        // 次字为低双字 / low as other
ELSE                                         // 首字 = 低 32 位 / first dword is low half
    FC_DL_LwordToDwords := _dwLo;            // 返回首字为低双字 / return low as first
    dwOther := _dwHi;                        // 次字为高双字 / high as other
END_IF

END_FUNCTION
