(*==============================================================================
 * 组件名称 (Component)  : FC_DL_BitSet
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅用标准 SHL / AND / OR / NOT，无任何厂商位写语法
 * 功能描述 (Function)   : 对 32 位字做"置位 / 清零"的纯函数操作：输入原值、返回新值，
 *                         不修改入参、不产生副作用，可安全用于表达式与 CASE 分支链式调用。
 *                         位索引越界时"原样返回原字"（不做任何修改），并给出错误码——
 *                         返回 0 会把整个状态字清零，在报警字场景等同于"全部报警消失"，
 *                         属危险的静默失败。
 * 开源溯源 (Origin)     : 原创实现。掩码构造方式参照 IEC 61131-3 位串运算语义，
 *                         不使用任何 CODESYS / TwinCAT 专有位访问扩展。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；无标准库功能块依赖
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3（无厂商位写方言）｜ R4 ✓ 越界原样返回 + 掩码后构造
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无状态机）｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 冷启动 · Level 0 批次）
 *============================================================================*)
FUNCTION FC_DL_BitSet : DWORD
VAR_INPUT
    uValue    : DWORD;             // 原始状态字，函数内只读 / Source status word, read-only inside the function
    uBitIndex : USINT;             // 位序号，0 = LSB，合法域 0..31 / Bit index, 0 = LSB, valid range 0..31
    bSetValue : BOOL := TRUE;      // TRUE = 置 1，FALSE = 清 0 / TRUE = set to 1, FALSE = clear to 0
END_VAR
VAR_OUTPUT
    bValid    : BOOL;              // 索引合法标志，FALSE 时返回原值 / Index valid flag, FALSE means the input is returned unchanged
    uErrorId  : UDINT;             // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    uMask      : DWORD;            // 目标单位掩码 / Single-bit target mask
    uWorkValue : UDINT;            // 提升到 UDINT 的原值工作副本 / UDINT working copy of the source value
    uWorkMask  : UDINT;            // 提升到 UDINT 的掩码工作副本 / UDINT working copy of the mask
    uShift     : UDINT;            // 提升到 UDINT 的移位量 / Shift amount promoted to UDINT
END_VAR
VAR CONSTANT
    DL_BIT_INDEX_MAX : USINT := 31;  // 32 位字的最大合法位索引 / Max legal bit index of a 32-bit word
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜返回值预置为原值（边界 B1）：异常路径下"不做任何修改"是最安全语义
 *      Pre-set return to the source value: on any error path, "change nothing" is safest
 *-----------------------------------------------------------------------------*)
FC_DL_BitSet := uValue;
bValid       := FALSE;
uErrorId     := 16#0000_0000;
uMask        := 16#0000_0000;
uWorkValue   := 16#0000_0000;
uWorkMask    := 16#0000_0000;
uShift       := 16#0000_0000;

(*------------------------------------------------------------------------------
 * 段 2｜越界拦截：先校验、后构造掩码（边界 B2，顺序即防御）
 *      Bounds interception: validate first, build the mask afterwards
 *      越界时立即返回原值，绝不执行 SHL(1, index) 以免触发未定义行为
 *-----------------------------------------------------------------------------*)
IF uBitIndex > DL_BIT_INDEX_MAX THEN
    uErrorId := 16#0001_0001;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜掩码构造：UDINT#1 左移 index 位，得到仅目标位为 1 的单位掩码
 *      Mask construction: shift UDINT#1 by index to obtain a single-bit mask
 *      使用显式类型字面量 UDINT#1，避免隐式类型转换（红线 R3）
 *-----------------------------------------------------------------------------*)
uShift    := USINT_TO_UDINT(uBitIndex);
uWorkMask := SHL(UDINT#1, uShift);
uMask     := UDINT_TO_DWORD(uWorkMask);
uWorkValue := DWORD_TO_UDINT(uValue);

(*------------------------------------------------------------------------------
 * 段 4｜置位 / 清零（边界 B3）：两条路径共用同一掩码，保证完全对称
 *      Set / clear: both paths share one mask, guaranteeing symmetry
 *      清零用 AND NOT 作用于 UDINT 全域 32 位，不得只反低 8 位而误伤其它位
 *-----------------------------------------------------------------------------*)
IF bSetValue THEN
    uWorkValue := uWorkValue OR uWorkMask;
ELSE
    uWorkValue := uWorkValue AND NOT uWorkMask;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜结果回写：经返回值输出，入参 uValue 全程未被修改（边界 B4）
 *      Result write-back through the return value, the input stays untouched
 *-----------------------------------------------------------------------------*)
FC_DL_BitSet := UDINT_TO_DWORD(uWorkValue);
bValid       := TRUE;
END_FUNCTION
