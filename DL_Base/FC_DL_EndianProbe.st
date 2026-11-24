(*==============================================================================
 * 名称 : FC_DL_EndianProbe —— 运行期字节序探针（纯 IEC 语义层判定）
 * 分类 / 前缀 / 版本 : DL_Base / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 返回 FALSE（判定为小端约定）且 bValid=TRUE。判定依据（非含糊占位）：
 *            (1) IEC 61131-3 第 3 版对 SHL/SHR/AND/OR 及 WORD_TO_BYTE 等转换的
 *                定义均在「数值语义」层，与目标机内存字节排布完全无关——把
 *                WORD 16#0102 经 SHR(...,8) 取出的是数值高字节 16#01，任何
 *                平台上该结论一致，故移位序列无法探测内存序；
 *            (2) R3 红线禁用 POINTER/REFERENCE/UNION，纯 IEC 层不存在合法的
 *                内存字节重解释手段，因此运行期探针在本库约束下不可实现；
 *            (3) 本库所有字节序件一律显式携带 bBigEndian/bHiFirst 参数、按
 *                数值语义装配/拆解，不依赖内存序，故探针恒判 FALSE（库级
 *                约定：小端数值语义），bValid 恒 TRUE 表示该约定全平台成立。
 * 错误码 : 无故障路径（常量语义判定），eErr 恒 0，bValid 恒 TRUE；
 *          16#0001_1A0C 为本件预留码位，当前实现不发出
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC（禁指针/联合体）｜ R4 ✓ N/A 无浮点 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_EndianProbe : BOOL
VAR_OUTPUT
    eErr   : UDINT;    // 故障码，0=正常（本件无故障路径）/ error code, 0=ok (no fault path)
    bError : BOOL;     // 故障标志，恒 FALSE / error flag, always FALSE
    bValid : BOOL;     // TRUE=判定结论可用，恒 TRUE / TRUE when verdict is usable
END_VAR

eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 数值语义约定全平台成立 / verdict usable on all platforms

FC_DL_EndianProbe := FALSE;                  // 恒判 FALSE：库级小端数值语义约定 / always FALSE by library convention

END_FUNCTION
