(*==============================================================================
 * 组件名称 (Component)  : FC_DL_BitArrayRotate
 * 所属子库 (Sublibrary) : DL_Base
 * 归属目录 (Directory)  : C:\Library\DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 分类/来源标签         : 函数（FUNCTION）· 纯函数 · 跨字整串循环移位
 *                         lgf-bitlogic / bit-manipulation / cross-word
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 SHL / SHR /
 *                         OR / ABS 与显式类型转换，无厂商位访问方言，无实例依赖
 * 功能一句话 (Summary)  : 把 1 到 4 个 DWORD 视为一条 32 到 128 位的位串，整体
 *                         左移或右移 n 位，移出最高字的位回卷到最低字。
 * 功能描述 (Function)   : 第 1 个数组元素承载位 0 到 31，第 2 个承载位 32 到 63，
 *                         依此类推（每字内 LSB 起）。整体旋转与单字循环移位不同：
 *                         位串总宽 W 等于 32 乘有效字数，左移 s 位时目标位 i 取自
 *                         源位 (i 减 s) 对 W 取模，因此最高字移出的位回卷到第 1 字
 *                         最低位。典型现场用途：多字报警位图的时段轮转显示、
 *                         4 字 128 点位图的交接班整体顺延、循环缓冲区位索引的
 *                         整体平移、旋转编码器多字计数的位窗口对齐。
 * 与既有件边界 (Boundary): FC_DL_BitArrayExtract 是「抽」、FC_DL_BitArrayInsert 是
 *                         「插」、本件是「转」。前两件按位窗口做局部读写，本件只做
 *                         整条位串的循环平移，位序总量守恒、位宽不变。三者构成
 *                         位段族三件套，职责互斥、参数域不重叠。
 * 为什么不用标准 ROL     : IEC 的 ROL 只在单字内循环，跨字无定义；多字拼成 64 位
 *                         或 128 位中间量再移位的写法，在移位量等于位宽时属未定义
 *                         行为，且各平台对超宽中间量的支持不一致。本件按字就地
 *                         运算，移位量一律落在 1 到 31 的合法域。
 * 设计要点 (Key notes)  : ① 闸门顺序固定为「字数 → 移位归约 → 逐字合成」，字数非法
 *                           直接早退且不写目标；
 *                         ② 移位量先取绝对值再对总宽取模，永远不把原始 nShift 送进
 *                           SHL / SHR；
 *                         ③ 方向归一裁定：nShift 的符号优先于 bLeft，负值恒为右移，
 *                           非负时由 bLeft 决定左或右（详见下方方向表）；
 *                         ④ 结果先落到局部暂存数组，全部算完再整体写回，因而目标
 *                           与源同址（别名）时不会读到被覆盖的中间值；
 *                         ⑤ 纯函数：无内部状态、无跨周期残留，同入参同结果。
 *
 * 【方向归一表 / Direction normalisation table】
 *   nShift < 0            → 右移，量取绝对值，bLeft 被忽略
 *   nShift >= 0, bLeft    → 左移，量为 nShift
 *   nShift >= 0, bLeft 假 → 右移，量为 nShift
 *   左移量最终统一折算成 0 到 W 减 1 的左旋量，右移按「W 减量」等值换算
 *
 * 【验收向量 / Acceptance vectors】
 *   V1  nWords=2, aSrc=[16#8000_0001, 16#0000_0000], nShift=1, bLeft=真
 *       → aDst=[16#0000_0002, 16#0000_0001]，nEffectiveShift=1（最高位回卷第 2 字）
 *   V2  nWords=2, 同一源, nShift=1, bLeft=假
 *       → aDst=[16#4000_0000, 16#8000_0000]，nEffectiveShift=63（最低位回卷最高字）
 *   V3  V-B 边界：nWords=2, nShift=64 → 归约后 nEffectiveShift=0，输出等于输入，
 *       置 013D（整圈也是「移位量被归约」，必须有人说一声）
 *   V4  V-A 域外：nWords=0 → 返回 FALSE、021F、aDst 原样不动（不写半张图）
 *   V5  V-B 边界：nWords=9 → 钳到 4、置 013E、按 4 字旋转
 *   V6  单字：nWords=1, aSrc[1]=16#8000_0001, nShift=1, bLeft=真
 *       → aDst[1]=16#0000_0003（单字内首尾位同时回卷，验证取模路径）
 *
 * 开源溯源 (Origin)     : 来源标签 lgf-bitlogic。LGF（Libre Graphical Framework）
 *                         为免费闭源发布的公开函数库手册，本件仅借鉴其位逻辑组
 *                         「单点、单段、批量段」的分层分类，以及「源、目标、移位量」
 *                         三段参数域的组织方式；许可证按其发布方条款仅作分类参考，
 *                         本件零代码行、零注释、零数据结构引用，属 clean-room
 *                         独立实现，不构成衍生作品。
 * 码位说明 (Codes)      : 信息 16#0001_013D 移位量已归约 ｜ 16#0001_013E 字数已钳位
 *                         故障 16#0001_021F 字数非法。三段取号见本轮规格 §3.2，
 *                         与位段族既有 0125 到 0127 区间不重叠。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 SHL / SHR /
 *                         ABS 与 INT_TO_DINT / DINT_TO_INT。
 * 契约前置条件 (Contract): 入参为定长数组形参，函数内无法探测调用方数组实际长度，
 *                         故「nWords 不得大于调用方数组长度」由调用方在组态时保证。
 * 镜像量清单 (R38)      : 本件无锁存副本，边界量全部由入口标量 nWords 与 nShift
 *                         自身导出，不存在锁存量与实时量混用面。
 * 红线自检 (Redline)    : 零全局变量表依赖 ｜ 零外部变量声明 ｜ 零物理地址直写
 *                         纯 IEC 61131-3 ｜ 无除法故无除零面 ｜ 空移位量走常量分支
 *                         全变量双语同行注释 ｜ 状态机 N/A（纯函数）｜ 无定时器实例
 * 修订历史 (Revision)   : 2026-11-15  v1.0.0  首版入库（Round 13 · 泳道 B 位段族收口）
 *============================================================================*)

(*==============================================================================
 * 位串几何示意 (Bit string geometry)：
 *   两字共 64 位，位 0 到 31 在第 1 字，位 32 到 63 在第 2 字
 *   源 16#8000_0001 与 16#0000_0000 的置位点是位 0 与位 31
 *   左旋 1 位：位 0 到 1、位 31 到 32，故结果第 1 字 16#0000_0002、
 *   第 2 字 16#0000_0001，位宽守恒（仍是两个置位点）
 *   右旋 1 位：位 0 到 63、位 31 到 30，故结果第 1 字 16#4000_0000、
 *   第 2 字 16#8000_0000
 *============================================================================*)

(*==============================================================================
 * 逐调用推演 (Call trace)：
 *   调用 1  两字、左移 1
 *     字数 2 合法；总宽 64；左移量 1，对 64 取模仍为 1，k 为 0、r 为 1
 *     第 1 字取源字 1 左移 1 或源字 2 右移 31，得 16#0000_0002
 *     第 2 字取源字 2 左移 1 或源字 1 右移 31，得 16#0000_0001
 *   调用 2  两字、右移 1
 *     折算左旋量 64 减 1 等于 63，k 为 1、r 为 31
 *     r 非零，第 1 字取源字 2 左移 31 或源字 1 右移 1，得 16#4000_0000
 *   调用 3  字数 0
 *     闸门 1 拦下，返回假、码 021F，目标数组一次都没写
 *============================================================================*)

(*==============================================================================
 * 调用示例 (Instance guide)：
 *   bOk := FC_DL_BitArrayRotate(
 *              aSrc            := aAlarmMap,
 *              nWords          := 4,
 *              nShift          := 8,
 *              bLeft           := TRUE,
 *              aDst            := aAlarmMapShifted,
 *              nEffectiveShift => nUsed,
 *              uErrorId        => uCode);
 *   提示：nEffectiveShift 是归约后的左旋量，不是入参原值；要判「有没有整圈」
 *         请比对 16#0001_013D 是否出现。
 *============================================================================*)

FUNCTION FC_DL_BitArrayRotate : BOOL
VAR_INPUT
    aSrc   : ARRAY[1..4] OF DWORD;  // 源位图，第 1 元素为位 0 到 31，未用字填 0 [位串] / Source bitmap, element 1 holds bits 0 to 31, unused words zeroed
    nWords : INT;                   // 有效字数 [个]，域 1 到 4，越界按钳位规则处理 / Effective word count, 1 to 4, clamped
    nShift : INT;                   // 移位位数 [bit]，负值恒为右移，域负 32767 到 32767 / Shift amount, negative always means right
    bLeft  : BOOL;                  // 方向选择，真为左移（向高位），假为右移；nShift 为负时本引脚被忽略 / TRUE rotates left, ignored when nShift is negative
END_VAR
VAR_IN_OUT
    aDst   : ARRAY[1..4] OF DWORD;  // 目标位图，允许与源同址；失败路径不写入 [位串] / Destination bitmap, may alias the source, untouched on failure
END_VAR
VAR_OUTPUT
    nEffectiveShift : INT;          // 归一后实际左旋量 [bit]，域 0 到总宽减 1 / Effective left rotation after normalisation
    uErrorId        : UDINT;        // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    nW        : INT;                // 钳位后的有效字数 [个] / Clamped effective word count
    nWidthBit : DINT;               // 位串总宽，等于字数乘 32，DINT 中间量防溢出 [bit] / Total bit width in DINT
    nMag      : DINT;               // 移位量绝对值 [bit] / Absolute shift magnitude
    nMod      : DINT;               // 绝对值对总宽取模的结果 [bit] / Magnitude reduced modulo the width
    nLeft     : DINT;               // 折算后的左旋量 [bit]，域 0 到总宽减 1 / Normalised left rotation amount
    nWordOfs  : DINT;               // 左旋量折算的整字偏移 k [字] / Whole word offset derived from the rotation
    nBitOfs   : INT;                // 左旋量折算的字内偏移 r [bit]，域 0 到 31 / Intra word offset, 0 to 31
    bRight    : BOOL;               // 实际方向，真为右移 / Effective direction, TRUE means right
    nJ        : INT;                // 目标字下标，1 起 [索引] / Destination word index, one based
    nIdxA     : INT;                // 左移贡献源字的下标，0 起算后加 1 [索引] / Source index for the left shifted contribution
    nIdxB     : INT;                // 右移贡献源字的下标，0 起算后加 1 [索引] / Source index for the right shifted contribution
    uA        : DWORD;              // 左移贡献源字快照 [位串] / Snapshot of the left shifted source word
    uB        : DWORD;              // 右移贡献源字快照 [位串] / Snapshot of the right shifted source word
    aTmp      : ARRAY[1..4] OF DWORD;   // 结果暂存区，全部算完才写回目标，保证别名安全 [位串] / Staging buffer, written back only after the whole result is ready
END_VAR
VAR CONSTANT
    DL_BAR_MAXW  : INT := 4;    // 最大字数 [个]，与形参维度字面量一致 / Maximum word count, must match the array dimension
    DL_BAR_WBITS : INT := 32;   // 单字位宽 [bit] / Bits per word
    DL_BAR_SHMAX : DINT := 127; // 规格允许的移位量绝对值上限 [bit] / Documented shift magnitude limit
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出预置：任何路径下的可读输出必须确定
 *      Pre-set the readable outputs so every path is deterministic
 *      目标数组刻意不预置：失败契约要求「原样不动」，先写就破了契约
 *      The destination is deliberately left untouched, the failure contract keeps it as is
 *-----------------------------------------------------------------------------*)
FC_DL_BitArrayRotate := FALSE;
nEffectiveShift     := 0;
uErrorId            := 16#0000_0000;
nW                  := 0;
nBitOfs             := 0;
nWordOfs            := 0;
bRight              := FALSE;
nMod                := 0;
nLeft               := 0;

(*------------------------------------------------------------------------------
 * 段 2｜字数闸门（边界 B1/B2）：小于 1 属逻辑错，早退且不写目标
 *      Word count gate: below one is a logic error, exit early without writing
 *      大于 4 属契约超界，钳位后照算，现场宁可转错半张图也不要空输出
 *      Above four is a contract breach, clamped and still computed
 *-----------------------------------------------------------------------------*)
IF nWords < 1 THEN
    uErrorId := 16#0001_021F;   // 故障级：字数非法，目标数组保持原样
    RETURN;
ELSIF nWords > DL_BAR_MAXW THEN
    nW       := DL_BAR_MAXW;
    uErrorId := 16#0001_013E;   // 信息级：字数已钳到 4
ELSE
    nW := nWords;
END_IF

nWidthBit := INT_TO_DINT(nW) * INT_TO_DINT(DL_BAR_WBITS);

(*------------------------------------------------------------------------------
 * 段 3｜移位量归约（边界 B3/B4）：先取绝对值，再对总宽取模
 *      Shift reduction: take the magnitude first, then reduce modulo the width
 *      归约后左旋量必落在 0 到总宽减 1，永远不会出现按位宽移位的未定义行为
 *      After reduction the amount stays inside zero to width minus one
 *-----------------------------------------------------------------------------*)
nMag   := ABS(INT_TO_DINT(nShift));
bRight := (nShift < 0) OR (NOT bLeft);
nMod   := nMag MOD nWidthBit;

IF nMod = 0 THEN
    nLeft := 0;                                   // 整圈或零移位：结果等于输入 / Whole turns or no shift
ELSIF bRight THEN
    nLeft := nWidthBit - nMod;                    // 右移 nMod 等价于左旋 总宽减 nMod / Right by n equals left by width minus n
ELSE
    nLeft := nMod;
END_IF

(* 归约事件（信息级）：超规格上限或跨越整圈都要报，整圈也是「被归约」）
 * Reduction notice: above the documented limit or wrapped a whole turn, both reported
 * 优先级低于段 2 的钳位码，故仅在未占用时写入
 * Lower priority than the clamp code above, written only when the slot is free *)
IF ((nMag > DL_BAR_SHMAX) OR (nMag >= nWidthBit)) AND (uErrorId = 16#0000_0000) THEN
    uErrorId := 16#0001_013D;
END_IF

nEffectiveShift := DINT_TO_INT(nLeft);
nWordOfs        := nLeft / INT_TO_DINT(DL_BAR_WBITS);   // 除数是非零常量，无除零面 / Constant non-zero divisor
nBitOfs         := DINT_TO_INT(nLeft MOD INT_TO_DINT(DL_BAR_WBITS));

(*------------------------------------------------------------------------------
 * 段 4｜逐字合成（边界 B5）：整字偏移定位后，用两次单字移位拼出每个目标字
 *      Per word synthesis: locate by whole word offset, then stitch with two shifts
 *      下标算术：先补 DL_BAR_MAXW 倍字数把负偏移抬到非负，再取模，
 *      因此不可能对负操作数取模，也不用循环修下标
 *      Index arithmetic stays non-negative before the modulo, no repair loop needed
 *      内层移位量 r 域 1 到 31，互补移位量 32 减 r 域 1 到 31，均为合法域
 *-----------------------------------------------------------------------------*)
FOR nJ := 1 TO nW DO

    nIdxA := DINT_TO_INT(((INT_TO_DINT(nJ) - 1 - nWordOfs) + INT_TO_DINT(DL_BAR_MAXW * nW)) MOD INT_TO_DINT(nW));
    nIdxB := DINT_TO_INT(((INT_TO_DINT(nJ) - 2 - nWordOfs) + INT_TO_DINT(DL_BAR_MAXW * nW)) MOD INT_TO_DINT(nW));

    uA := aSrc[nIdxA + 1];   // 下标域 1 到 4，源形参维度同为 1 到 4 / Index stays inside one to four
    uB := aSrc[nIdxB + 1];

    IF nBitOfs = 0 THEN
        aTmp[nJ] := uA;                                        // 无字内偏移：整字搬运 / No intra word offset
    ELSE
        aTmp[nJ] := SHL(uA, nBitOfs) OR SHR(uB, DL_BAR_WBITS - nBitOfs);
    END_IF

END_FOR;
FOR nJ := nW + 1 TO DL_BAR_MAXW DO
    aTmp[nJ] := 16#0000_0000;   // 未参与的字在暂存区置零 / Unused words cleared in the staging buffer
END_FOR;

(*------------------------------------------------------------------------------
 * 段 5｜写回（边界 B6）：全部算完再整表写回，别名调用不会读到半途值
 *      Write back: the whole table lands at once, alias calls never read a half result
 *      未参与的字同样清零，避免上一张图的残留位被误读成有效点
 *      Unused words are cleared as well, stale bits from a previous map cannot leak through
 *-----------------------------------------------------------------------------*)
FOR nJ := 1 TO DL_BAR_MAXW DO
    aDst[nJ] := aTmp[nJ];
END_FOR;

FC_DL_BitArrayRotate := TRUE;   // 归约与钳位都属信息级，结果仍可用 / Info level events only, the result is usable
END_FUNCTION
