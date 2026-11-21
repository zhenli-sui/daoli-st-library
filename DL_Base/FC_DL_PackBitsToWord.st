(*==============================================================================
 * 组件名称 (Component)  : FC_DL_PackBitsToWord
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅用标准 SHL / OR / NOT，无任何厂商位写语法
 * 功能描述 (Function)   : 把 16 路离散 BOOL 状态打包成一个标准报警字 WORD，
 *                         供 Modbus / PROFINET 上传或写入设备状态字。
 *                         位序约定写死：数组索引 0 → bit0（LSB），不提供位序开关。
 *                         可选整体取反，适配低电平有效的报警点。
 * 开源溯源 (Origin)     : 原创实现。位序遵循 IEC 61131-3 位串类型"第 0 位为 LSB"规定。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；无标准库功能块依赖
 *
 * 【uErrorId 显式豁免声明 / Explicit uErrorId exemption】
 *   本函数不设 uErrorId 输出引脚。理由：唯一可能的失败态是"数组维度与循环上界
 *   不一致"，而该风险已由编译期定长数组 ARRAY[0..15] 与 VAR CONSTANT
 *   DL_PACK_BIT_COUNT 双重约束消除，函数不存在任何运行期失败路径。引入一个恒为 0
 *   的错误码引脚只会增加调用方噪音。此为对"错误统一经 uErrorId 输出"规则的
 *   显式豁免，依据 ROUND_PLAN §2.6 决策记录（P3），已在手册与演进日志备案。
 *   This function intentionally has no uErrorId output: the only conceivable failure
 *   mode (array dimension vs loop bound mismatch) is removed at compile time by the
 *   fixed-size array plus a VAR CONSTANT bound, leaving no runtime failure path.
 *
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3（无厂商位写方言）｜ R4 ✓ 维度硬绑定 + 下标双检
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无状态机）｜ R7 N/A（无实例调用）
 *                         豁免项：uErrorId（见上，编译期无失败路径）
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 冷启动 · Level 0 批次）
 *============================================================================*)
FUNCTION FC_DL_PackBitsToWord : WORD
VAR_INPUT
    abBits     : ARRAY[0..15] OF BOOL;   // 16 路离散状态，索引 0 对应 bit0 / 16 discrete states, index 0 maps to bit0
    bInvertAll : BOOL := FALSE;          // 整体取反，适配低电平有效的报警点 / Invert all bits for active-low alarm points
END_VAR
VAR
    uResult : WORD;    // 打包结果 / Packed result word
    nIndex  : INT;     // 循环索引，值域 0..15 / Loop index, range 0..15
    uWork   : UDINT;   // 打包中间寄存器，避免 WORD 移位溢出 / Intermediate register in UDINT to avoid WORD shift overflow
END_VAR
VAR CONSTANT
    DL_PACK_BIT_COUNT : INT := 16;   // 打包位数，必须与数组维度严格一致 / Packed bit count, must equal the array dimension
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜初始化：结果清零，中间寄存器清零（不依赖实例残留值）
 *      Initialization: clear result and intermediate register
 *-----------------------------------------------------------------------------*)
uResult := 16#0000;
uWork   := 16#0000_0000;

(*------------------------------------------------------------------------------
 * 段 2｜逐位组装（边界 B1/B3）：循环上界走常量，禁止魔法数 15
 *      Bit-by-bit assembly: the loop bound comes from a constant, no magic number
 *      位序唯一约定：索引 i 的数据写入 bit i，即索引 0 → LSB
 *      Single bit-order convention: data at index i goes to bit i, index 0 = LSB
 *-----------------------------------------------------------------------------*)
FOR nIndex := 0 TO (DL_PACK_BIT_COUNT - 1) DO
    (* 数组下标上下界双检（红线 R4）：下界 0、上界 DL_PACK_BIT_COUNT-1 *)
    (* Array index double check: lower bound 0 and upper bound DL_PACK_BIT_COUNT-1 *)
    IF (nIndex >= 0) AND (nIndex <= (DL_PACK_BIT_COUNT - 1)) THEN
        IF abBits[nIndex] THEN
            (* SHL 在 UDINT 域执行，纯 IEC 语义，无厂商位写方言 *)
            (* SHL runs in the UDINT domain, pure IEC semantics, no bit-write dialect *)
            uWork := uWork OR SHL(UDINT#1, INT_TO_UDINT(nIndex));
        END_IF
    END_IF
END_FOR;

(*------------------------------------------------------------------------------
 * 段 3｜截断到 WORD 域：只保留低 16 位
 *      Truncate to the WORD domain: keep the low 16 bits only
 *-----------------------------------------------------------------------------*)
uResult := UDINT_TO_WORD(uWork);

(*------------------------------------------------------------------------------
 * 段 4｜整体取反（边界 B4）：在组装完成后一次性执行，语义清晰且少 16 次分支
 *      Global inversion executed once after assembly, clearer and cheaper
 *-----------------------------------------------------------------------------*)
IF bInvertAll THEN
    uResult := NOT uResult;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜结果回写：调用方须显式初始化 BOOL 数组，不得依赖平台默认 FALSE（边界 B5）
 *      Result write-back: callers must initialize the BOOL array explicitly
 *-----------------------------------------------------------------------------*)
FC_DL_PackBitsToWord := uResult;
END_FUNCTION
