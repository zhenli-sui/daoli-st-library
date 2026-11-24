(*==============================================================================
 * 名称 : FC_DL_DwordToWords —— DWORD 拆解为两个 WORD（本件返回首字，wOther 为次字）
 * 分类 / 前缀 / 版本 : DL_Base / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 将 32 位输入拆为高/低两个 16 位 WORD。bHiFirst=TRUE 时首字（返回值）
 *            为高字、次字（wOther）为低字；FALSE 时角色对调（首字=低字）。
 *            「首/次」仅表拆解顺序，与内存字节序无关（数值语义拆解）。
 *            边界处理：dwIn 全值域合法，高低字覆盖完整 32 位，无信息丢失。
 * 错误码 : 无故障路径（全值域合法的纯拆解），eErr 恒 0，bValid 恒 TRUE；
 *          16#0001_1A0A 为本件预留码位，当前实现不发出
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 移位量=16 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_DwordToWords : WORD
VAR_INPUT
    dwIn     : DWORD;    // 待拆解的 32 位输入 [位域] / input dword to be split
    bHiFirst : BOOL;     // TRUE=首字取高字 / TRUE when first word is the high word
END_VAR
VAR_OUTPUT
    wOther : WORD;     // 次字（另一半）/ the other (second) word
    eErr   : UDINT;    // 故障码，0=正常（本件无故障路径）/ error code, 0=ok (no fault path)
    bError : BOOL;     // 故障标志，恒 FALSE / error flag, always FALSE
    bValid : BOOL;     // TRUE=首/次两字均可用，恒 TRUE / TRUE when both words are usable
END_VAR
VAR
    _wHi : WORD;       // 高 16 位字 [位域] / high word
    _wLo : WORD;       // 低 16 位字 [位域] / low word
END_VAR

eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 本件全值域合法，恒可用 / always valid

_wHi := DWORD_TO_WORD(SHR(dwIn, 16));        // 右移 16 位取高字（截断安全）/ high word via shift
_wLo := DWORD_TO_WORD(dwIn AND 16#0000_FFFF);// 低 16 位掩码后截取 / low word via mask

IF bHiFirst THEN                             // 首字 = 高字 / first word is high word
    FC_DL_DwordToWords := _wHi;              // 返回首字为高字 / return high as first
    wOther := _wLo;                          // 次字为低字 / low as other
ELSE                                         // 首字 = 低字 / first word is low word
    FC_DL_DwordToWords := _wLo;              // 返回首字为低字 / return low as first
    wOther := _wHi;                          // 次字为高字 / high as other
END_IF

END_FUNCTION
