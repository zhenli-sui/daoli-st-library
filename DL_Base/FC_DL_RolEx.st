(*==============================================================================
 * 组件名称 (Component)  : FC_DL_RolEx
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library 的 SHL / SHR 内建函数，
 *                         循环语义由移位合成显式构造，无厂商 ROL 方言依赖
 * 功能一句话 (Summary)  : 循环左移防御包装：移位量对位宽取模归一后再循环，
 *                         杜绝平台相关行为，循环位不丢。
 * 功能描述 (Function)   : 对被移位位串按移位量 nN 循环左移。归一策略写死：
 *                         nN 先 MOD 32 归一到 0 到 31（nN 为 USINT 天然非负，
 *                         禁用 MOD 对负数的平台歧义取余的前提由类型系统保证）；
 *                         归一后 nN = 0 直接返回原值（整圈等价于不动，不置码）；
 *                         归一后 1 到 31 用「左移 nN OR 右移 (32 − nN)」位合成
 *                         构造循环语义，两个合成移位量均严格落在 1 到 31 安全域。
 * 溯源     (Origin)     : IEC 61131-3 标准语义的道莅防御性实现
 *                         （接口语义由 IEC 61131-3 定义，clean-room 重写，
 *                         参考公开标准条款）
 * 支持位宽 (Width Note) : 本件按 DWORD（32 位）主类型实现，仅支持 32 位位串；
 *                         BYTE / WORD 调用方先显式转换到 DWORD 后调用，再按需
 *                         截回原位宽（头注释显式声明，不做 ANY_BIT 泛型）。
 * 类型裁定 (Type Note)  : 码位段 16#0001_xxxx 为全库共享 32 位段，WORD 容量不足，
 *                         故 uDiag 采用 UDINT 承载（与库内 uErrorId : UDINT 惯例一致）
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: SHL / SHR
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 移位量 MOD 归一（合成移位
 *                         量恒在 1 到 31 安全域）｜ R5 ✓ 全变量中英双语同行注释
 *                         R6 N/A（纯函数，无 CASE/ENUM 状态机，按批 1 口径标 N/A）
 *                         R7 N/A（FC 为纯函数，无实例调用，头注释显式说明）
 * 防御行为声明 (Defense): ① 归一先行：nN ≥ 32 时先 MOD 32 归一并置信息码
 *                           16#0001_0158（已归一提示），归一后绝不出现 ≥ 位宽
 *                           的移位量，杜绝平台对超宽循环移位的歧义行为；
 *                         ② nN 为 USINT 类型天然非负，MOD 只作用于非负域，
 *                           负数取余的平台歧义（如商向零取整方向不一）从类型
 *                           系统层面被排除，该前提已在头注释写死；
 *                         ③ 归一后 nN = 0 直接返回原值且不置码（整圈无事件）；
 *                         ④ 位合成用「SHL(uIn, nN) OR SHR(uIn, 32 − nN)」，
 *                           nN 归一后为 1 到 31，故 32 − nN 恒为 1 到 31，
 *                           两个移位量均不触碰「移位量 = 位宽」禁区，循环位不丢；
 *                         ⑤ 32（位宽）提为只读常量，禁魔法数。
 * 修订历史 (Revision)   :
 *   2026-11-16  v1.0.0  首版入库（R14 批 3 · T0 快车道）
 *============================================================================*)
FUNCTION FC_DL_RolEx : DWORD
VAR_INPUT
    uIn : DWORD;   // 被循环移位位串 [位] / Bit string to be rotated
    nN  : USINT;   // 移位量 [bit]，USINT 天然非负，MOD 仅作用于非负域 / Shift amount [bit], USINT is non-negative, MOD applied on the non-negative domain only
END_VAR
VAR_OUTPUT
    uDiag : UDINT; // 诊断字，16#0001_0158=移位量已 MOD 32 归一，0=无事件 / Diag word, 16#0001_0158=shift amount reduced by MOD 32, 0=no event
END_VAR
VAR
    nNorm : USINT; // 归一后移位量 [bit]，域 0 到 31 / Normalized shift amount [bit], range 0 to 31
END_VAR
VAR CONSTANT
    DL_RO_WIDTH : USINT := 32;  // 位宽常量 [bit]，MOD 归一与合成移位共用 / Width constant [bit], shared by MOD normalization and composite shifts
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出与诊断预置：先归零，任何路径都不会留下脏诊断
 *      Pre-set the output and diag so no path ever leaves a stale diag
 *-----------------------------------------------------------------------------*)
FC_DL_RolEx := 16#0000_0000;   // 返回值预置全零 [位串] / Preset return value to all zero
uDiag       := 16#0000_0000;   // 诊断字预置无事件 / Preset diag word to no event
nNorm       := 0;              // 归一移位量预置 [bit] / Preset normalized shift to zero [bit]

(*------------------------------------------------------------------------------
 * 段 2｜移位量归一（防御声明①②）：nN MOD 32 归一到 0 到 31；
 *      nN 为 USINT 非负域，MOD 结果即数学取模，无负数取余歧义；
 *      nN ≥ 32 置信息码提示已归一（归一是正常防御行为，非故障）
 *      Shift-amount normalization (defense notes 1 and 2): nN MOD 32 reduces
 *      to 0 to 31; a reduction raises the informational code, not a fault
 *-----------------------------------------------------------------------------*)
IF nN >= DL_RO_WIDTH THEN
    nNorm := nN MOD DL_RO_WIDTH;   // 超宽归一：MOD 32 取模 [bit] / Oversized normalization: MOD 32 [bit]
    uDiag := 16#0001_0158;         // 信息码：移位量已 MOD 32 归一 / Informational: shift amount reduced by MOD 32
ELSE
    nNorm := nN;                   // 域内直通 [bit] / In-domain pass-through [bit]
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜循环移位主体（防御声明③④）：归一后 0 整圈直通原值；
 *      1 到 31 用左移与右移位合成，合成移位量恒在安全域，循环位不丢
 *      Rotation body (defense notes 3 and 4): normalized zero returns as is;
 *      one to thirty one composes SHL and SHR, both amounts stay in the safe
 *      domain so no bit is ever lost
 *-----------------------------------------------------------------------------*)
IF nNorm = 0 THEN
    FC_DL_RolEx := uIn;   // 整圈（或 0 位）等价于原值直通 [位串] / A full turn (or zero shift) returns the input unchanged
ELSE
    FC_DL_RolEx := SHL(uIn, nNorm) OR SHR(uIn, DL_RO_WIDTH - nNorm);   // 位合成循环左移 [位串] / Composite rotate left
END_IF
END_FUNCTION
