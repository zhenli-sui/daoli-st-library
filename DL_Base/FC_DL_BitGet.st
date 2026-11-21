(*==============================================================================
 * 组件名称 (Component)  : FC_DL_BitGet
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅用标准 SHR / AND 运算，无任何厂商位访问语法
 * 功能描述 (Function)   : 从 32 位状态字中安全提取指定位（Hamming 单位提取）。
 *                         位索引合法域 0..31（0 = LSB）。越界时"先判后算"，
 *                         立即返回 FALSE 并输出 16#0001_0001，绝不把越界移位量
 *                         交给 SHL/SHR 去执行（越界移位在各平台行为不一致，是
 *                         跨平台移植的经典暗坑）。
 * 开源溯源 (Origin)     : 原创实现。位序约定遵循 IEC 61131-3 对位串类型
 *                         "第 0 位为最低有效位"的规定。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；无标准库功能块依赖
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3（无厂商位访问方言）｜ R4 ✓ 越界先判后算 + 返回值兜底
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无状态机）｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 冷启动 · Level 0 批次）
 *============================================================================*)
FUNCTION FC_DL_BitGet : BOOL
VAR_INPUT
    uValue    : DWORD;    // 待检测的 32 位状态字 / Source 32-bit status word
    uBitIndex : USINT;    // 位序号，0 = LSB，合法域 0..31 / Bit index, 0 = LSB, valid range 0..31
END_VAR
VAR_OUTPUT
    bValid    : BOOL;     // 索引合法标志，FALSE 时返回值为保底 FALSE / Index valid flag, FALSE means result is a safe FALSE
    uErrorId  : UDINT;    // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    uWork     : UDINT;    // 提升到 UDINT 的工作副本，规避混合类型移位 / UDINT working copy to avoid mixed-type shifts
    uShift    : UDINT;    // 提升到 UDINT 的移位量 / Shift amount promoted to UDINT
END_VAR
VAR CONSTANT
    DL_BIT_INDEX_MAX : USINT := 31;  // 32 位字的最大合法位索引 / Max legal bit index of a 32-bit word
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜返回值与标志预置：任何异常路径下返回值必须确定
 *      Pre-set return value and flags: the result must be deterministic on every path
 *      部分平台函数返回值未赋值时残留上次调用值，故先给 FALSE（边界 B4）
 *-----------------------------------------------------------------------------*)
FC_DL_BitGet := FALSE;
bValid       := FALSE;
uErrorId     := 16#0000_0000;
uWork        := 16#0000_0000;

(*------------------------------------------------------------------------------
 * 段 2｜越界先判后算（边界 B1）：禁止先移位再校验
 *      Bounds check before any shift (boundary B1): never shift first and check later
 *      USINT 全域 0..255，凡 > 31 者均属非法移位量，统一按参数越界处理
 *-----------------------------------------------------------------------------*)
IF uBitIndex > DL_BIT_INDEX_MAX THEN
    uErrorId := 16#0001_0001;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜位提取（边界 B2/B3）：统一提升到 UDINT 后移位，再显式掩码取最低位
 *      Bit extraction: promote to UDINT, shift, then mask the LSB explicitly
 *      禁止使用以点号直取单一位的厂商方言；禁止依赖"非零即真"的隐式布尔转换
 *-----------------------------------------------------------------------------*)
uWork  := DWORD_TO_UDINT(uValue);
uShift := USINT_TO_UDINT(uBitIndex);
uWork  := SHR(uWork, uShift);
uWork  := uWork AND 16#0000_0001;

IF uWork <> 16#0000_0000 THEN
    FC_DL_BitGet := TRUE;
END_IF

(* 校验通过：索引合法，结果可信 *)
(* Check passed: index is legal and the result is trustworthy *)
bValid := TRUE;
END_FUNCTION
