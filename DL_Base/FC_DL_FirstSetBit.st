(*==============================================================================
 * 组件名称 (Component)  : FC_DL_FirstSetBit
 * 溯源说明 (Provenance): 道莅 clean-room 防御性实现（IEC 61131-3 纯净实现，闭源文档仅借语义，零代码行）
 * 所属子库 (Sublibrary) : DL_Base / BitString
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），仅用
 *                         Standard.library 的 SHR / AND
 * 组件分类 (Category)   : 函数（FUNCTION）· 纯函数 · 位串搜索
 * 功能一句话 (Summary)  : 在 8/16/32/64 位有效位宽内定位**首个置位位**，支持
 *                         低位优先与高位优先两种扫描方向，返回 0 基位号。
 *
 * 本件存在的意义 (Why this unit exists)
 *   位串族已有读写（BitGet/BitSet）、统计（BitCount）、提取（BitFieldExtract）、
 *   批量（BitArray*）、旋转与掩码比较，唯独**搜索**缺位。现场「状态字 →
 *   首个故障位号」「IO 字 → 首个空位」每次都要手写一遍循环，各处写法不一，
 *   64 位宽还有 SHL(x,64) 这类未定义行为的踩坑面。本件把搜索收成一个件。
 *
 * 边界安全 (Boundary)
 *   ① uWidth 不在 {8,16,32,64} → 钳到最近的合法值并置信息 0463（钳位后可继续
 *      工作，属正常防御）；uWidth = 0 → 故障 03B1、bFound = FALSE、bValid = FALSE
 *      （零位宽没有仲裁对象，属非法参数，不是正常结论）；
 *   ② 宽 64 用**常量掩码** DL_MASK64，全程不出现 SHL/SHR 的移位量等于位宽的
 *      写法（R10/R48 两次实证该行为未定义）；移位量恒满足 0 ≤ 移位量 ≤ 63；
 *   ③ 屏蔽后全零 → bFound = FALSE、bValid = TRUE + 信息 0462：「没有置位位」
 *      是合法结论，不是错误；
 *   ④ 高位优先模式下被屏蔽位绝不参与仲裁——先屏蔽、后扫描，顺序不可反；
 *   ⑤ 两个方向都用 WHILE + 守卫计数器（上限 = 有效位宽），超限即退出，
 *      结构性防死锁；高位优先用「步数递增、位号递减」的写法，规避 UINT 下溢。
 * 遗留假设 (Assumption)
 *   LWORD 型 VAR_INPUT 在汇川 InoProShop 的可用性属 P0 编译验证项
 *   （R22 风险表已挂账），本件不降级为 DWORD 双拼，以保持位宽语义完整。
 *
 * 错误码    : 16#0001_0462 屏蔽后全零，无置位位（bFound = FALSE）——信息级，正常结论非错误
 *             16#0001_0463 有效位宽不在 8/16/32/64，已钳位到最近合法值——信息级，正常防御
 *             16#0001_03B1 有效位宽为 0，无法仲裁——故障级，bFound = FALSE 且 bValid = FALSE
 *             16#0001_03B2 预留禁用（故障级，不得挪用）
 *             16#0001_03B3 预留禁用（故障级，不得挪用）
 * 码位总账  : 16#0001_0462 用 / 16#0001_0463 用 ｜ 16#0001_03B1 用 / 16#0001_03B2 预留 / 16#0001_03B3 预留
 * 状态机    : N/A —— 纯函数无顺序状态机
 * 采样约定  : 纯组合函数，无定时器、无内部驻留状态
 * 依赖说明  : 无 DL_ 内部依赖；仅 Standard.library 的 SHR / AND
 * 验收向量  : V1 16#00A0/宽8/低位优先 → uBitIndex=5，bFound=TRUE，TRUE
 *             V2 16#00A0/宽8/高位优先 → uBitIndex=7，bFound=TRUE，TRUE
 *             V3 16#0100/宽8/低位优先 → 屏蔽后全零，bFound=FALSE，bValid=TRUE，eErr=0462，FALSE
 *             V4 16#0100/宽16/低位优先 → uBitIndex=8，bFound=TRUE（掩码边界主向量）
 *             V5 宽 0 → FALSE，eErr=03B1，bValid=FALSE，bError=TRUE
 *             V6 宽 12 → 钳到 16 且 eErr=0463，仍按 16 位仲裁
 *             V7 16#8000_0000_0000_0000/宽64/高位优先 → uBitIndex=63（禁 SHL 64 主向量）
 * 红线自检  : 全局变量声明零使用 / 外部变量访问零使用 / 物理地址零使用 ｜ 纯 IEC 61131-3 ｜ 无除法
 *             无浮点 ｜ 移位量恒小于位宽 ｜ 循环双守卫 ｜ 全变量双语同行注释
 *             状态机 N/A ｜ 无定时器实例 ｜ 掩码与位宽全部常量化
 * 修订历史  : 2026-11-16  v1.0.0  首版入库（R22 · 批 1 · 位串族第四轴）
 *============================================================================*)

FUNCTION FC_DL_FirstSetBit : BOOL
VAR_INPUT
    uValue      : LWORD;                       // 待搜索位串，全域有效 / bit string to search, the whole word is readable
    uWidth      : UINT := 64;                  // 有效位宽 [位]，8/16/32/64 / effective width in bits, 8/16/32/64
    bHighFirst  : BOOL := FALSE;               // TRUE 高位优先 / FALSE 低位优先 / TRUE scans from the top, FALSE from the bottom
END_VAR
VAR_OUTPUT
    uBitIndex   : UINT;                        // 首个置位位号，0 基 [位号] / first set bit index, 0-based
    bFound      : BOOL;                        // 是否找到置位位 / whether a set bit was found
    eErr        : UDINT;                       // 错误码，0 表示无错 / error code, 0 means no error
    bError      : BOOL;                        // 故障级标志，仅故障级错误置位 / fault-class flag, set only on fault-level codes
    bValid      : BOOL;                        // 结论可用标志（全零结论亦为可用） / conclusion usable flag, TRUE for an all-zero conclusion too
END_VAR
VAR
    uWUse       : UINT;                        // 生效有效位宽 [位]，已钳位 / effective width after clamping
    uI          : UINT;                        // 当前候选位号 [位号] / candidate bit index
    uSteps      : UINT;                        // 高位优先的步数计数 [步] / step counter for the downward scan
    uGuard      : UINT;                        // 循环守卫计数器 [次] / loop guard counter
    xMask       : LWORD;                       // 有效位宽掩码 [位串] / mask of the effective width
    xMasked     : LWORD;                       // 屏蔽后的位串 [位串] / bit string after masking
END_VAR
VAR CONSTANT
    DL_W8       : UINT := 8;                   // 合法位宽之一 [位] / one of the legal widths
    DL_W16      : UINT := 16;                  // 合法位宽之一 [位] / one of the legal widths
    DL_W32      : UINT := 32;                  // 合法位宽之一 [位] / one of the legal widths
    DL_W64      : UINT := 64;                  // 合法位宽之一 [位] / one of the legal widths
    DL_W_ZERO   : UINT := 0;                   // 位宽零值，用于非法判定 [位] / zero width, used by the illegal test
    DL_MASK8    : LWORD := 16#0000_0000_0000_00FF; // 8 位掩码常量 [位串] / 8-bit mask constant
    DL_MASK16   : LWORD := 16#0000_0000_0000_FFFF; // 16 位掩码常量 [位串] / 16-bit mask constant
    DL_MASK32   : LWORD := 16#0000_0000_FFFF_FFFF; // 32 位掩码常量 [位串] / 32-bit mask constant
    DL_MASK64   : LWORD := 16#FFFF_FFFF_FFFF_FFFF; // 64 位全一掩码常量，替代 SHL(x,64) [位串] / 64-bit all-ones mask, replaces SHL(x,64)
    DL_BIT_ONE  : LWORD := 16#0000_0000_0000_0001; // 位取用的与掩码 [位串] / AND mask used to test a single bit
    DL_ZERO_LW  : LWORD := 16#0000_0000_0000_0000; // 位串零值 [位串] / zero bit string
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜返回值与输出预置（L1/L9）
 *      Preset the return value and every output
 *-----------------------------------------------------------------------------*)
FC_DL_FirstSetBit := FALSE;                     // 返回值预置未找到 / preset to not found
uBitIndex := 0;                                 // 位号预置 0 [位号] / index preset to zero
bFound    := FALSE;                             // 找到标志预置 FALSE / found flag preset to FALSE
eErr      := 16#0000_0000;                      // 错误码预置无错 / error code preset to none
bError    := FALSE;                             // 故障标志预置 FALSE / fault flag preset to FALSE
bValid    := FALSE;                             // 结论可用预置 FALSE / usable flag preset to FALSE
uWUse     := DL_W64;                            // 位宽预置最大合法值 / width preset to the maximum legal value
xMask     := DL_MASK64;                         // 掩码预置全一 / mask preset to all ones
xMasked   := DL_ZERO_LW;                        // 屏蔽结果预置零 / masked value preset to zero
uI        := 0;                                 // 位号游标预置 0 / index cursor preset to zero
uSteps    := 0;                                 // 步数计数预置 0 / step counter preset to zero
uGuard    := 0;                                 // 守卫预置 0 / guard preset to zero

(*------------------------------------------------------------------------------
 * 段 2｜位宽闸门（零宽属故障级；非标准宽度钳到最近合法值）
 *      Width gate: zero is a fault, non-standard widths clamp to the nearest legal value
 *-----------------------------------------------------------------------------*)
IF uWidth = DL_W_ZERO THEN
    eErr   := 16#0001_03B1;                     // 故障级：零位宽无法仲裁 / fault: zero width, nothing to arbitrate
    bError := TRUE;                             // 置故障标志 / raise the fault flag
    bValid := FALSE;                            // 结论不可用 / conclusion unusable
    bFound := FALSE;                            // 未找到 / not found
    RETURN;                                     // 早退路径已统一后处理 / the early exit is fully post-processed
END_IF

IF uWidth <= DL_W8 THEN
    uWUse := DL_W8;                             // 钳到 8 位 / clamped to eight bits
    IF uWidth <> DL_W8 THEN
        eErr := 16#0001_0463;                   // 信息级：位宽已钳位 / informational: width clamped
    END_IF
ELSIF uWidth <= DL_W16 THEN
    uWUse := DL_W16;                            // 钳到 16 位 / clamped to sixteen bits
    IF uWidth <> DL_W16 THEN
        eErr := 16#0001_0463;                   // 信息级：位宽已钳位 / informational: width clamped
    END_IF
ELSIF uWidth <= DL_W32 THEN
    uWUse := DL_W32;                            // 钳到 32 位 / clamped to thirty-two bits
    IF uWidth <> DL_W32 THEN
        eErr := 16#0001_0463;                   // 信息级：位宽已钳位 / informational: width clamped
    END_IF
ELSE
    uWUse := DL_W64;                            // 钳到 64 位（含 > 64 的越界输入） / clamped to sixty-four bits
    IF uWidth <> DL_W64 THEN
        eErr := 16#0001_0463;                   // 信息级：位宽已钳位 / informational: width clamped
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜掩码选择（常量掩码，绝不出现 SHL/SHR 移位量等于位宽的写法）
 *      Mask selection by constants, never a shift amount equal to the width
 *-----------------------------------------------------------------------------*)
IF uWUse = DL_W8 THEN
    xMask := DL_MASK8;                          // 8 位掩码 / eight-bit mask
ELSIF uWUse = DL_W16 THEN
    xMask := DL_MASK16;                         // 16 位掩码 / sixteen-bit mask
ELSIF uWUse = DL_W32 THEN
    xMask := DL_MASK32;                         // 32 位掩码 / thirty-two-bit mask
ELSE
    xMask := DL_MASK64;                         // 64 位全一掩码 / sixty-four-bit all-ones mask
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜先屏蔽后扫描（顺序不可反：被屏蔽位绝不参与仲裁）
 *      Mask before scanning, the order cannot be reversed
 *-----------------------------------------------------------------------------*)
xMasked := uValue AND xMask;                    // 无效高位一律清零 / invalid high bits cleared

IF xMasked = DL_ZERO_LW THEN
    eErr   := 16#0001_0462;                     // 信息级：全零，无置位位 / informational: all zero, no set bit
    bFound := FALSE;                            // 未找到 / not found
    bValid := TRUE;                             // 「没有置位位」是合法结论 / an all-zero conclusion is legal
    FC_DL_FirstSetBit := FALSE;                 // 返回未找到 / return not found
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜扫描（两方向各一套守卫：低位升扫 / 高位降扫，降扫用步数规避下溢）
 *      Scan in both directions, each with its own guard, the downward scan counts steps
 *-----------------------------------------------------------------------------*)
IF NOT bHighFirst THEN
    WHILE (NOT bFound) AND (uI < uWUse) AND (uGuard <= uWUse) DO
        IF (SHR(xMasked, uI) AND DL_BIT_ONE) <> DL_ZERO_LW THEN
            bFound    := TRUE;                  // 命中置位位 / a set bit was hit
            uBitIndex := uI;                    // 记录 0 基位号 / record the 0-based index
        ELSE
            uI := uI + 1;                       // 未命中则升位 / advance when not hit
        END_IF
        uGuard := uGuard + 1;                   // 守卫累计，上限即位宽 / guard bounded by the width
    END_WHILE
ELSE
    WHILE (NOT bFound) AND (uSteps < uWUse) AND (uGuard <= uWUse) DO
        uI := uWUse - 1 - uSteps;               // 位号 = 位宽 − 1 − 步数，恒不下溢 / index never underflows
        IF (SHR(xMasked, uI) AND DL_BIT_ONE) <> DL_ZERO_LW THEN
            bFound    := TRUE;                  // 命中置位位 / a set bit was hit
            uBitIndex := uI;                    // 记录 0 基位号 / record the 0-based index
        ELSE
            uSteps := uSteps + 1;               // 未命中则降位 / step down when not hit
        END_IF
        uGuard := uGuard + 1;                   // 守卫累计 / guard incremented
    END_WHILE
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜出口（未命中属结构性不可达，复用 0462 兜底，R90 不加码）
 *      Exit: a miss is structurally unreachable, the fallback reuses 0462
 *-----------------------------------------------------------------------------*)
IF NOT bFound THEN
    eErr   := 16#0001_0462;                     // 兜底复用：无置位位 / fallback reuse: no set bit
    bValid := TRUE;                             // 结论仍可用 / the conclusion is still usable
    uBitIndex := 0;                             // 位号归 0 / index back to zero
    FC_DL_FirstSetBit := FALSE;                 // 返回未找到 / return not found
    RETURN;
END_IF

bValid := TRUE;                                 // 结论可用 / conclusion usable
FC_DL_FirstSetBit := TRUE;                      // 返回找到 / return found
END_FUNCTION
