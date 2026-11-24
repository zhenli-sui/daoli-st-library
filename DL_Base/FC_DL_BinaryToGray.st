(*==============================================================================
 * 组件名称 (Component)  : FC_DL_BinaryToGray
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅用标准 SHL / SHR / XOR / AND，无厂商方言
 * 功能描述 (Function)   : 二进制 → 格雷码纯映射函数，用于"向绝对值编码器写目标位置"
 *                         以及"生成格雷码测试序列验证 FC_DL_GrayToBinary"。
 *                         与 FC_DL_GrayToBinary 严格互逆：GrayToBinary(BinaryToGray(x)) = x
 *                         （x 位于 0..2^w-1 且位宽一致时）。
 *                         输入先掩码再去脏高位；位宽 32 时掩码特判全 1，避免 SHL(1,32)。
 * 算法     (Algorithm)  : G = (B XOR (B >> 1)) AND mask，单表达式实现，禁止 FOR。
 * 开源溯源 (Origin)     : 原创实现。格雷码定义为公开经典算法，掩码与钳位为本库工程加固。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；无标准库功能块依赖
 * 互逆性自检 (Inverse Check): 手册给出的验证用例——对 0..2^w-1 全序列，
 *                         FC_DL_GrayToBinary(FC_DL_BinaryToGray(x, w), w) 必须等于 x。
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 位宽钳位 + SHL(1,32) 特判 + 先掩码后异或
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无状态机）｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 冷启动 · Level 0 批次）
 *============================================================================*)
FUNCTION FC_DL_BinaryToGray : UDINT
VAR_INPUT
    uBinaryValue : UDINT;         // 二进制原始值，允许带高位脏数据 / Raw binary value, dirty high bits tolerated
    uBitWidth    : USINT := 32;   // 有效位宽 1..32，越界按边界钳位 / Valid bit width 1..32, clamped at the boundaries
END_VAR
VAR_OUTPUT
    bValid       : BOOL;          // 位宽合法标志，FALSE 表示参数越界已钳位 / Width valid flag, FALSE means clamped
    uErrorId     : UDINT;         // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    uMask        : UDINT;         // 位宽掩码，仅保留有效位 / Bit-width mask keeping valid bits only
    uWidth       : USINT;         // 钳位后的有效位宽 / Clamped effective bit width
    uMaskedValue : UDINT;         // 已剔除脏高位的规范化输入 / Normalized input with dirty high bits removed
END_VAR
VAR CONSTANT
    DL_GRAY_WIDTH_MIN : USINT := 1;    // 最小合法位宽 [bit] / Min legal bit width [bit]
    DL_GRAY_WIDTH_MAX : USINT := 32;   // 最大合法位宽 [bit] / Max legal bit width [bit]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜返回值与工作变量预置：任何路径下返回值确定
 *      Initialize return value and working variables for determinism
 *-----------------------------------------------------------------------------*)
FC_DL_BinaryToGray := 16#0000_0000;
bValid             := TRUE;
uErrorId           := 16#0000_0000;
uMask              := 16#0000_0000;
uWidth             := uBitWidth;
uMaskedValue       := 16#0000_0000;

(*------------------------------------------------------------------------------
 * 段 2｜位宽钳位（边界 B1）：钳位 + 告警，但继续计算有效结果
 *      Width clamping: clamp and warn while still producing a valid result
 *-----------------------------------------------------------------------------*)
IF uBitWidth < DL_GRAY_WIDTH_MIN THEN
    uWidth   := DL_GRAY_WIDTH_MIN;
    bValid   := FALSE;
    uErrorId := 16#0001_0001;
ELSIF uBitWidth > DL_GRAY_WIDTH_MAX THEN
    uWidth   := DL_GRAY_WIDTH_MAX;
    bValid   := FALSE;
    uErrorId := 16#0001_0001;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜掩码构造（边界 B2）：位宽 32 特判全 1，绝不执行 SHL(1,32)
 *      Mask construction: all-ones at width 32, SHL(1,32) is never executed
 *-----------------------------------------------------------------------------*)
IF uWidth >= DL_GRAY_WIDTH_MAX THEN
    uMask := 16#FFFF_FFFF;
ELSE
    uMask := SHL(UDINT#1, USINT_TO_UDINT(uWidth)) - 16#0000_0001;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜先掩码（边界 B4）：顺序不可交换
 *      Mask first: the order is not interchangeable
 *      若先异或后掩码，脏高位会经右移渗入有效位区间，掩码只能截断结果、
 *      无法还原已被污染的低位，因此必须先规范化输入
 *-----------------------------------------------------------------------------*)
uMaskedValue := uBinaryValue AND uMask;

(*------------------------------------------------------------------------------
 * 段 5｜单表达式转换（边界 B3）：G = (B XOR (B >> 1)) AND mask
 *      Single-expression conversion, no loop by design
 *-----------------------------------------------------------------------------*)
FC_DL_BinaryToGray := (uMaskedValue XOR SHR(uMaskedValue, 1)) AND uMask;
END_FUNCTION
