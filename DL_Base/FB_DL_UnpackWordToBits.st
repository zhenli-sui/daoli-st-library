(*==============================================================================
 * 组件名称 (Component)  : FB_DL_UnpackWordToBits
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商方言
 * 功能描述 (Function)   : 把通信收到的 16 位状态字 WORD 解包成 16 个独立 BOOL，
 *                         支持位取反掩码（适配常闭点），并输出"整字内容变化"的
 *                         单扫描周期事件与取反后的置位总数。
 *                         位序约定：数组索引 0 → bit0（LSB）。
 *                         R_TRIG 在主体最前部无条件刷新；上周期字在输出赋值完成之后更新。
 * 开源溯源 (Origin)     : 原创实现。变化检测采用标准异或比较 + R_TRIG 上升沿，
 *                         未使用任何厂商专有解包指令。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 上周期值更新时序 + 下标双检 + 使能语义
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无顺序状态机，仅边沿锁存）
 *                         R7 ✓ R_TRIG 主体最前部无条件刷新
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 冷启动 · Level 0 批次）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_UnpackWordToBits
VAR_INPUT
    uWord       : WORD;              // 待解包的状态字，原始值 / Source status word, raw value
    uInvertMask : WORD := 16#0000;   // 位取反掩码，对应位为 1 则输出取反 / Invert mask, a 1 bit inverts the matching output
    bEnable     : BOOL := TRUE;      // 使能标志，FALSE 时所有输出位为 FALSE / Enable flag, FALSE forces all output bits FALSE
END_VAR
VAR_OUTPUT
    abBits      : ARRAY[0..15] OF BOOL;  // 解包结果，索引 0 = bit0 / Unpacked bits, index 0 = bit0
    bChanged    : BOOL;              // 整字内容变化，单扫描周期脉冲 / Word content changed, one-scan pulse
    uBitCount   : USINT;             // 当前置位总数，值域 0..16，供冗余校验 / Popcount 0..16 for redundancy check
    uErrorId    : UDINT;             // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    fbTrigChange : R_TRIG;           // 整字变化检测实例 / Word change detector instance
    uXorWord     : WORD;             // 本周期与上周期的差异位（原始字比较） / XOR of current and previous raw word
    uLastWord    : WORD;             // 上周期状态字，用于差异比较 / Previous word used for difference comparison
    nIndex       : INT;              // 循环索引，值域 0..15 / Loop index, range 0..15
    uOutWord     : WORD;             // 应用取反掩码后的输出字 / Output word after applying the invert mask
    uWork        : UDINT;            // 位提取用的 UDINT 工作副本 / UDINT working copy for bit extraction
    uShift       : UDINT;            // 提升到 UDINT 的移位量 / Shift amount promoted to UDINT
    nCount       : USINT;            // 临时置位计数，值域 0..16 / Temporary popcount, range 0..16
END_VAR
VAR CONSTANT
    DL_UNPACK_BIT_COUNT : INT := 16; // 解包位数，必须与数组维度严格一致 / Unpacked bit count, must equal the array dimension
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7 / 边界 B1）：差异比较与 R_TRIG 调用均在主体最前部
 *      Unconditional refresh zone: XOR comparison and R_TRIG call stay at the very top
 *      比较对象是"原始 uWord"，取反掩码不参与比较（边界 B3）——掩码一变若参与
 *      比较，就会被误报成现场信号跳变，把组态动作伪装成过程动作
 *      Comparison uses the raw uWord; the invert mask never participates (boundary B3)
 *-----------------------------------------------------------------------------*)
uXorWord := uWord XOR uLastWord;
fbTrigChange(CLK := (uXorWord <> 16#0000));

(*------------------------------------------------------------------------------
 * 段 2｜取反掩码应用（边界 B3）：只作用于输出位，不回头影响变化检测
 *      Invert mask applies to output bits only, never feeds back into change detection
 *-----------------------------------------------------------------------------*)
uOutWord := uWord XOR uInvertMask;
uWork    := WORD_TO_UDINT(uOutWord);
nCount   := 16#00;
uErrorId := 16#0000_0000;

IF bEnable THEN
    (*--------------------------------------------------------------------------
     * 段 3｜逐位解包 + 置位统计（边界 B4/B5）
     *      Bit-by-bit unpacking plus popcount (boundaries B4/B5)
     *      统计对象是取反后的输出位，保证 HMI 看到的位与计数同源
     *      Counting uses the post-invert bits so HMI bits and count stay consistent
     *-------------------------------------------------------------------------*)
    FOR nIndex := 0 TO (DL_UNPACK_BIT_COUNT - 1) DO
        IF (nIndex >= 0) AND (nIndex <= (DL_UNPACK_BIT_COUNT - 1)) THEN
            uShift := INT_TO_UDINT(nIndex);
            IF (SHR(uWork, uShift) AND 16#0000_0001) <> 16#0000_0000 THEN
                abBits[nIndex] := TRUE;
                nCount         := nCount + 16#01;
            ELSE
                abBits[nIndex] := FALSE;
            END_IF
        ELSE
            (* 下标越界兜底：理论上不可达（循环上界即数组上界），仍显式上报 *)
            (* Index out-of-range fallback: unreachable in theory, still reported explicitly *)
            uErrorId := 16#0001_0007;
        END_IF
    END_FOR;

    uBitCount := nCount;

    (* 变化事件：仅在使能时对外可见，禁用期间的差异由 uLastWord 继续跟踪吸收 *)
    (* Change event is visible only while enabled, differences while disabled are absorbed *)
    bChanged := fbTrigChange.Q;
ELSE
    (*--------------------------------------------------------------------------
     * 段 4｜使能失效语义（边界 B6）：输出位全 FALSE、计数清零
     *      Disabled: all output bits FALSE and the popcount cleared
     *-------------------------------------------------------------------------*)
    FOR nIndex := 0 TO (DL_UNPACK_BIT_COUNT - 1) DO
        IF (nIndex >= 0) AND (nIndex <= (DL_UNPACK_BIT_COUNT - 1)) THEN
            abBits[nIndex] := FALSE;
        END_IF
    END_FOR;

    uBitCount := 16#00;
    bChanged  := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜上周期字更新（边界 B2，硬性顺序）：必须在输出赋值完成之后
 *      Previous word update: must happen strictly after the outputs are assigned
 *      若提前到段 1 之前或之中，异或结果恒为 0，变化事件将永久失效
 *-----------------------------------------------------------------------------*)
uLastWord := uWord;
END_FUNCTION_BLOCK
