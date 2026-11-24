(*==============================================================================
 * 组件名称 (Component)  : FC_DL_ShrEx
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library 的 SHR 内建函数，无厂商方言
 * 功能一句话 (Summary)  : 右移防御包装：移位量钳位归一 + 超宽结果零值显式化。
 * 功能描述 (Function)   : 对被移位位串按移位量 nN 右移（逻辑右移，高位补 0）。
 *                         nN ≥ 32（位宽）时走常量路径直接置 0（严禁 SHR(x, n)
 *                         中 n ≥ 位宽的未定义/平台歧义行为，R10 BitFieldExtract
 *                         先例口径）；nN < 32 才委托内建 SHR。纯函数，无内部
 *                         状态、无跨周期残留。
 * 溯源     (Origin)     : IEC 61131-3 标准语义的道莅防御性实现
 *                         （接口语义由 IEC 61131-3 定义，clean-room 重写，
 *                         参考公开标准条款）
 * 支持位宽 (Width Note) : 本件按 DWORD（32 位）主类型实现，仅支持 32 位位串；
 *                         BYTE / WORD 调用方先显式转换到 DWORD 后调用，再按需
 *                         截回原位宽（头注释显式声明，不做 ANY_BIT 泛型）。
 * 类型裁定 (Type Note)  : 码位段 16#0001_xxxx 为全库共享 32 位段，WORD 容量不足，
 *                         故 uDiag 采用 UDINT 承载（与库内 uErrorId : UDINT 惯例一致）
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: SHR
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 移位量钳位（nN ≥ 32 走常量
 *                         路径）｜ R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（纯函数，
 *                         无 CASE/ENUM 状态机，按批 1 口径标 N/A）
 *                         R7 N/A（FC 为纯函数，无实例调用，头注释显式说明）
 * 防御行为声明 (Defense): ① nN ≥ 32 时结果直接置 16#0000_0000 并置信息码
 *                           16#0001_0157，不调内建 SHR（部分平台移位量 ≥ 位宽
 *                           属未定义行为或结果歧义，本库统一为「超宽置 0」）；
 *                         ② nN 为 USINT 类型天然非负，nN < 0 不可能发生，
 *                           无负移位量防御分支（类型系统层面保证）；
 *                         ③ 32（位宽）提为只读常量，禁魔法数。
 * 修订历史 (Revision)   :
 *   2026-11-16  v1.0.0  首版入库（R14 批 3 · T0 快车道）
 *============================================================================*)
FUNCTION FC_DL_ShrEx : DWORD
VAR_INPUT
    uIn : DWORD;   // 被移位位串 [位] / Bit string to be shifted
    nN  : USINT;   // 移位量 [bit]，USINT 天然非负 / Shift amount [bit], USINT is non-negative by type
END_VAR
VAR_OUTPUT
    uDiag : UDINT; // 诊断字，16#0001_0157=移位量超宽结果置 0，0=无事件 / Diag word, 16#0001_0157=oversized shift yields zero, 0=no event
END_VAR
VAR CONSTANT
    DL_SR_WIDTH : USINT := 32;  // 位宽常量 [bit]，与 DWORD 位宽一致 / Width constant [bit], matches the DWORD width
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出与诊断预置：先归零，任何路径都不会留下脏诊断
 *      Pre-set the output and diag so no path ever leaves a stale diag
 *-----------------------------------------------------------------------------*)
FC_DL_ShrEx := 16#0000_0000;   // 返回值预置全零 [位串] / Preset return value to all zero
uDiag       := 16#0000_0000;   // 诊断字预置无事件 / Preset diag word to no event

(*------------------------------------------------------------------------------
 * 段 2｜移位量闸门（边界 B1）：nN ≥ 位宽走常量路径直接置 0，不调内建
 *      Shift-amount gate (B1): nN greater or equal to the width takes the
 *      constant path yielding zero, the built-in SHR is never called
 *      严禁把 nN = 32 送进 SHR —— 部分编译器对该移位量属未定义行为
 *      Never feed nN = 32 into SHR, undefined behaviour on some compilers
 *-----------------------------------------------------------------------------*)
IF nN >= DL_SR_WIDTH THEN
    FC_DL_ShrEx := 16#0000_0000;   // 超宽常量路径：结果置 0 [位串] / Oversized constant path: result is zero
    uDiag       := 16#0001_0157;   // 信息码：移位量超宽，结果已置 0 / Informational: oversized shift, result set to zero
ELSE
    FC_DL_ShrEx := SHR(uIn, nN);   // 域内委托内建 SHR，移位量 0 到 31 安全 [位串] / In-domain delegate to built-in SHR, shift amount 0 to 31 is safe
END_IF
END_FUNCTION
