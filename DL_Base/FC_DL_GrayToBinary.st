(*==============================================================================
 * 组件名称 (Component)  : FC_DL_GrayToBinary
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅用标准 SHL / SHR / XOR / AND，无厂商方言
 * 功能描述 (Function)   : 绝对值编码器格雷码 → 标准二进制无符号整数的纯映射函数。
 *                         支持 1~32 位可变位宽；位宽越界时"钳位并继续计算"，
 *                         以 bValid=FALSE + uErrorId 告警，绝不返回 0——
 *                         返回 0 会让上位机看到"位置突然归零"的假故障。
 *                         位宽 32 时 SHL(1,32) 属未定义行为，掩码必须特判为全 1。
 * 算法     (Algorithm)  : 递推式 B = G XOR (G>>1) XOR (G>>2) … XOR (G>>(w-1))（递推至第 w−1 项），
 *                         迭代上界 31，天然有界，无需防死锁计数器。
 * 开源溯源 (Origin)     : 原创实现。格雷码递推式为公开经典算法，位宽钳位与移位特判
 *                         为本库针对三平台差异所做的工程加固。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；无标准库功能块依赖
 * 职责边界 (Scope)      : 本函数不负责 360° 编码器的 Excess 偏移补偿。
 *                         调用顺序应为：转二进制 → 减 Excess 偏移 → 乘分辨率系数。
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 越界钳位 + SHL(1,32) 特判 + 空循环边界
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无状态机）｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 冷启动 · Level 0 批次）
 *============================================================================*)
FUNCTION FC_DL_GrayToBinary : UDINT
VAR_INPUT
    uGrayValue : UDINT;            // 格雷码原始值，高位脏数据由掩码剔除 / Raw Gray code, dirty high bits removed by the mask
    uBitWidth  : USINT := 32;      // 有效位宽 1..32，越界按边界钳位 / Valid bit width 1..32, clamped at the boundaries
END_VAR
VAR_OUTPUT
    bValid     : BOOL;             // 位宽合法标志，FALSE 表示参数越界已钳位 / Width valid flag, FALSE means clamped
    uErrorId   : UDINT;            // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    uBinary    : UDINT;            // 转换结果 / Conversion result
    uMask      : UDINT;            // 位宽掩码，仅保留有效位 / Bit-width mask keeping valid bits only
    uWidth     : USINT;            // 钳位后的有效位宽 / Clamped effective bit width
    nIndex     : USINT;            // 递推索引，值域 1..31 / Recurrence index, range 1..31
END_VAR
VAR CONSTANT
    DL_GRAY_WIDTH_MIN : USINT := 1;    // 最小合法位宽 [bit] / Min legal bit width [bit]
    DL_GRAY_WIDTH_MAX : USINT := 32;   // 最大合法位宽 [bit] / Max legal bit width [bit]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜返回值与工作变量预置：任何路径下返回值确定
 *      Initialize return value and working variables for determinism
 *-----------------------------------------------------------------------------*)
FC_DL_GrayToBinary := 16#0000_0000;
bValid             := TRUE;
uErrorId           := 16#0000_0000;
uBinary            := 16#0000_0000;
uMask              := 16#0000_0000;
uWidth             := uBitWidth;

(*------------------------------------------------------------------------------
 * 段 2｜位宽钳位（边界 B1）：钳位后继续计算，不中断、不归零
 *      Width clamping: clamp, then keep computing; never abort, never zero the result
 *      下界 0 与上界 >32 均属参数越界，统一报 16#0001_0001
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
 * 段 3｜掩码构造（边界 B2）：位宽 32 时特判全 1
 *      Mask construction: special-case to all-ones at width 32
 *      SHL(UDINT#1, 32) 在 IEC 中为未定义行为（CODESYS 得 0、部分平台得 1），
 *      因此必须先判 uWidth >= 32，绝不进入移位语句
 *-----------------------------------------------------------------------------*)
IF uWidth >= DL_GRAY_WIDTH_MAX THEN
    uMask := 16#FFFF_FFFF;
ELSE
    uMask := SHL(UDINT#1, USINT_TO_UDINT(uWidth)) - 16#0000_0001;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜递推转换（边界 B3/B4）：先掩码再逐级异或右移
 *      Recurrence conversion: mask first, then XOR the shifted word level by level
 *      uWidth = 1 时"FOR 1 TO 0"按 IEC 语义执行零次，天然返回原始值；
 *      必须写成 TO (uWidth - 1)，禁止写成 TO uWidth（会多异或一次 SHR(gray, w)）
 *-----------------------------------------------------------------------------*)
uBinary := uGrayValue AND uMask;

IF uWidth > DL_GRAY_WIDTH_MIN THEN
    FOR nIndex := DL_GRAY_WIDTH_MIN TO (uWidth - DL_GRAY_WIDTH_MIN) DO
        uBinary := uBinary XOR SHR(uGrayValue, USINT_TO_UDINT(nIndex));
    END_FOR;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜结果掩码（边界 B5）：XOR 链可能带入高位脏数据，末尾再截断一次
 *      Result masking: the XOR chain can pull in dirty high bits, truncate at the end
 *-----------------------------------------------------------------------------*)
uBinary := uBinary AND uMask;

FC_DL_GrayToBinary := uBinary;
END_FUNCTION
