(*==============================================================================
 * 组件名称 (Component)  : FC_DL_BitArrayInsert
 * 所属子库 (Sublibrary) : DL_Base
 * 归属目录 (Directory)  : C:\Library\DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 函数（FUNCTION）· 原子位窗写 · 跨字读改写
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 SHL / SHR /
 *                         AND / OR / NOT 与显式类型转换，无厂商位访问方言
 * 功能一句话 (Summary)  : 把 64 位值按「起始位 + 位宽」原子写入 DWORD 数组位流的
 *                         指定窗口，只改窗口内的位，并报出实际改动字数。
 * 功能描述 (Function)   : 与 FC_DL_BitArrayExtract 严格成对：提取件读窗口，
 *                         本件写窗口。窗口跨字时先算出两个字的完整新值，再按
 *                         低字、高字顺序一次性回写，避免半更新撕裂。
 *                         典型现场用途：64 位使能字与报警屏蔽字下发、凸轮表位图
 *                         整段更新、远程 IO 位图按字段改写而不动邻位。
 * 与既有件边界 (Boundary): FC_DL_BitSet 只置单字内单个位；FC_DL_WordBitPack 只把
 *                         多个位段打包进一个 WORD；本件是跨字位流窗口的读改写，
 *                         带改动计数与原子写回语义，三者职责互斥。
 * 副作用声明 (Side effect): 本件是「纯函数语义 + 受控副作用」：无内部状态、同入参
 *                         同结果，但会原地修改形参指向的目标数组。副作用范围仅限
 *                         形参数组的窗口内位，绝不触碰窗口外位，也绝不写数组之外。
 *                         严禁把本件当只读函数使用。
 * 设计要点 (Key notes)  : ① 先算完全部新值再回写，杜绝读一半写一半；
 *                         ② 先比较后计数：值未变的字不计入改动数，也不产生写动作，
 *                           减少下游无谓刷新；
 *                         ③ 宽度 64 走满 1 常量分支，禁止左移 64 位；
 *                         ④ 越界截断后仍写可用位并置 bValid 为假，现场可读可查。
 * 开源溯源 (Origin)     : 来源标签 lgf-bitlogic。LGF 为免费闭源发布的公开函数库
 *                         手册，本件仅借鉴其位逻辑组「打包与提取双向成对」的组织
 *                         方式与「批量位串三口分工」的分类骨架；许可证按其发布方
 *                         条款仅作分类参考，本件零代码行、零注释、零数据结构引用，
 *                         属 clean-room 独立实现，不构成衍生作品。
 * 码位说明 (Codes)      : 本件独占信息级码段 16#0001_0128 到 16#0001_012A，纯函数
 *                         语义无锁存面故不占故障级码；与提取件的 0125 到 0127 相邻
 *                         不重叠，与全库已占码求差为空。
 *                         0128 偏移越界 ｜ 0129 宽度越界 ｜ 012A 跨字截断。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 SHL / SHR / NOT /
 *                         DWORD_TO_LWORD / LWORD_TO_DWORD / INT_TO_DINT / INT_TO_UDINT。
 * 契约前置条件 (Contract): 函数内无法探测数组实际长度，故「nTargetCount 不得大于
 *                         调用方实际数组长度」由调用方负责，组态时须保证。
 * 红线自检 (Redline)    : 零全局变量表依赖 ｜ 零外部变量声明 ｜ 零物理地址
 *                         纯 IEC 61131-3 ｜ 无除法故无除零面 ｜ 全变量双语同行注释
 *                         状态机 N/A（纯函数）｜ 无定时器实例 ｜ 移位量恒小于 64
 * 修订历史 (Revision)   : 2026-11-15  v1.0.0  首版入库（Round 12 · 跨字位段族）
 *============================================================================*)

(*==============================================================================
 * 读改写示意 (Read modify write)：
 *   目标两字初值 16#FFFF_FFFF 与 16#FFFF_FFFF，起始位 28、位宽 8、写入 16#A5
 *   掩码 16#FF 左移 28 位后覆盖第 1 字的高 4 位与第 2 字的低 4 位
 *   第 1 字新值 16#5FFF_FFFF，第 2 字新值 16#FFFF_FFFA，改动字数 2
 *   窗口外的位一字不动，这是本件与「整字覆盖」最本质的差别
 *============================================================================*)

(*==============================================================================
 * 逐调用推演 (Call trace)：
 *   调用 1  初值全 1、起始 28、位宽 8、写入 16#A5
 *     字数 2，总位数 64；偏移 28 通过；宽度 8 通过；28 加 8 等于 36 不截断
 *     低字下标 1，移位 28，跨字判据成立，高字下标 2
 *     掩码 16#FF，生效值 16#A5，展开后低字得 16#5FFF_FFFF、高字得 16#FFFF_FFFA
 *     两字都与旧值不同，改动计数 2，写回后返回真
 *   调用 2  初值 16#0000_000F、起始 0、位宽 4、写入 16#F
 *     新值与旧值相同，改动计数 0，不发写动作，目标保持原值
 *   调用 3  起始 30、位宽 8、字数 1、写入 16#FF
 *     30 加 8 超过 32，宽度截为 2，事件码 012A，只写最高两位的 16#3
 *============================================================================*)

FUNCTION FC_DL_BitArrayInsert : BOOL
VAR_IN_OUT
    auTarget     : ARRAY[1..8] OF DWORD;  // 被写入的目标位流数组，本函数原地修改窗口内位 [位串] / Target bit stream, window bits modified in place
END_VAR
VAR_INPUT
    uValue       : LWORD;                 // 待写入值，只用低 nWidth 位，超宽位忽略 [位串] / Value to write, only the low window bits are used
    nTargetCount : INT := 1;              // 目标有效字数 [个]，域 1 到 8，越界钳位 / Effective target word count, 1 to 8, clamped
    nOffset      : INT := 0;              // 写入窗口起始位 [bit]，0 起 / Window start bit, zero based
    nWidth       : INT := 8;              // 写入窗口宽度 [bit]，域 1 到 64 / Window width, 1 to 64
END_VAR
VAR_OUTPUT
    nChanged     : INT;                   // 实际发生改动的字数 [个]，值未变的字不计入 / Number of words actually modified
    uApplied     : LWORD;                 // 实际写入的右对齐值，已按宽度截断 [位串] / Value actually applied, width masked
    uMask        : LWORD;                 // 本次生效掩码，右对齐 [位串] / Effective right aligned mask
    nActualW     : INT;                   // 实际生效宽度 [bit] / Effective width after truncation
    uErrorId     : UDINT;                 // 事件码，0 表示无事件 / Event code, zero means none
    bValid       : BOOL;                  // 全合法为真，截断或越界为假 / All inputs legal, false when truncated
END_VAR
VAR
    nTotalBits   : DINT;                  // 目标位流总位数，等于字数乘 32 [bit] / Total bit count of the target stream
    nIdxLo       : INT;                   // 低字下标，1 起 [索引] / Low word index, one based
    nIdxHi       : INT;                   // 高字下标，0 表示不跨字 [索引] / High word index, zero when not straddling
    nShift       : INT;                   // 字内移位量，等于偏移对 32 取模 [bit] / Intra word shift amount
    uWinWide     : LWORD;                 // 已左移到窗口位置的写入值 [位串] / Window value shifted into place
    uMaskWide    : LWORD;                 // 已左移到窗口位置的掩码 [位串] / Window mask shifted into place
    uOldLo       : DWORD;                 // 低字旧值 [位串] / Previous low word
    uOldHi       : DWORD;                 // 高字旧值，不跨字时为 0 [位串] / Previous high word, zero when absent
    uNewLo       : DWORD;                 // 低字新值 [位串] / New low word
    uNewHi       : DWORD;                 // 高字新值，不跨字时为 0 [位串] / New high word, zero when absent
END_VAR
VAR CONSTANT
    DL_MASK64_ALL : LWORD := 16#FFFF_FFFF_FFFF_FFFF;   // 满宽掩码常量，64 宽分支专用 [位串] / All ones mask for the 64 bit branch
    DL_SRC_MAX    : INT := 8;                          // 目标字数上限 [个] / Target word count limit
    DL_BIT_MAX64  : INT := 64;                         // 位窗宽度上限 [bit] / Window width limit
    DL_BIT_MAX32  : INT := 32;                         // 单字位宽 [bit] / Bits per word
    DL_SHIFT32    : UDINT := 32;                       // 高字取回的固定移位量 [bit] / Fixed shift for the high word
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出预置：异常路径下全部输出确定
 *      Pre-set outputs so that every path is deterministic
 *-----------------------------------------------------------------------------*)
FC_DL_BitArrayInsert := FALSE;
nChanged             := 0;
uApplied             := 16#0000_0000_0000_0000;
uMask                := 16#0000_0000_0000_0000;
nActualW             := 0;
uErrorId             := 16#0000_0000;
bValid               := FALSE;

(*------------------------------------------------------------------------------
 * 段 2｜字数钳位与总位数（边界 B1）：先夹到 1 到 8
 *      Clamp the word count, then derive the total bit count
 *-----------------------------------------------------------------------------*)
IF nTargetCount < 1 THEN
    nTargetCount := 1;
ELSIF nTargetCount > DL_SRC_MAX THEN
    nTargetCount := DL_SRC_MAX;
END_IF
nTotalBits := INT_TO_DINT(nTargetCount) * INT_TO_DINT(DL_BIT_MAX32);

(*------------------------------------------------------------------------------
 * 段 3｜偏移闸门（边界 B2）：负偏移与落空偏移早退，绝不写半个字
 *      Offset gate: negative or beyond the stream end exits without writing
 *-----------------------------------------------------------------------------*)
IF (nOffset < 0) OR (INT_TO_DINT(nOffset) >= nTotalBits) THEN
    uErrorId := 16#0001_0128;   // 偏移越界，目标数组一字未动
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜宽度闸门（边界 B3）：宽度须落在 1 到 64 闭区间
 *      Width gate: the window width must be within one to sixty four
 *-----------------------------------------------------------------------------*)
IF (nWidth < 1) OR (nWidth > DL_BIT_MAX64) THEN
    uErrorId := 16#0001_0129;   // 宽度越界，目标数组一字未动
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜越界截断（边界 B4）：按位流末端截断，之后仍写可用低位
 *      Truncation at the stream end, the usable low bits are still written
 *-----------------------------------------------------------------------------*)
IF (INT_TO_DINT(nOffset) + INT_TO_DINT(nWidth)) > nTotalBits THEN
    nWidth   := DINT_TO_INT(nTotalBits - INT_TO_DINT(nOffset));
    uErrorId := 16#0001_012A;
    bValid   := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜定位（边界 B5）：低字下标、字内移位量与跨字判据
 *      Locate the low word, the intra word shift and the straddle flag
 *-----------------------------------------------------------------------------*)
nIdxLo := nOffset / DL_BIT_MAX32 + 1;
nShift := nOffset MOD DL_BIT_MAX32;
nIdxHi := 0;
IF ((nShift + nWidth) > DL_BIT_MAX32) AND (nIdxLo < nTargetCount) THEN
    nIdxHi := nIdxLo + 1;
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜双字窗口深度校验（边界 B6）：跨到第三个字时按双字窗口截断
 *      Third word guard: a window reaching the next word is truncated here
 *      起点非零时 64 位移位中间量只能覆盖到第二个字末尾，超出部分若继续写
 *      会把高位静默写成零，故显式截断并报事件
 *-----------------------------------------------------------------------------*)
IF (nShift + nWidth) > DL_BIT_MAX64 THEN
    nWidth   := DL_BIT_MAX64 - nShift;
    uErrorId := 16#0001_012A;
    bValid   := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜掩码与生效值（边界 B7）：64 宽走常量分支，禁止左移 64 位
 *      Mask and applied value: the full width case uses the constant branch
 *-----------------------------------------------------------------------------*)
IF nWidth >= DL_BIT_MAX64 THEN
    uMask := DL_MASK64_ALL;
ELSE
    uMask := SHL(LWORD#1, INT_TO_UDINT(nWidth)) - LWORD#1;
END_IF
uApplied := uValue AND uMask;

(*------------------------------------------------------------------------------
 * 段 9｜展开到窗口位置：字内移位量 0 到 31，左移后必然落在 64 位内
 *      Shift mask and value up into the window position
 *      断言口径：段 6 与段 7 已保证移位量加宽度不超过 64，故此处不会溢出位宽
 *-----------------------------------------------------------------------------*)
uMaskWide := SHL(uMask, INT_TO_UDINT(nShift));
uWinWide  := SHL(uApplied, INT_TO_UDINT(nShift));

(*------------------------------------------------------------------------------
 * 段 10｜取旧值并逐字算出新值，此段只读不写
 *      Read the old words and compute the new ones, still no write here
 *-----------------------------------------------------------------------------*)
uOldLo := auTarget[nIdxLo];
uOldHi := 16#0000_0000;
IF nIdxHi > 0 THEN
    uOldHi := auTarget[nIdxHi];
END_IF
uNewLo := (uOldLo AND NOT LWORD_TO_DWORD(uMaskWide)) OR LWORD_TO_DWORD(uWinWide);
uNewHi := 16#0000_0000;
IF nIdxHi > 0 THEN
    uNewHi := (uOldHi AND NOT LWORD_TO_DWORD(SHR(uMaskWide, DL_SHIFT32))) OR LWORD_TO_DWORD(SHR(uWinWide, DL_SHIFT32));
END_IF

(*------------------------------------------------------------------------------
 * 段 11｜先比较后计数（边界 B8）：值未变的字不算改动，也不产生写动作
 *      Compare before counting: unchanged words are neither counted nor written
 *-----------------------------------------------------------------------------*)
IF uNewLo <> uOldLo THEN
    nChanged := nChanged + 1;
END_IF
IF (nIdxHi > 0) AND (uNewHi <> uOldHi) THEN
    nChanged := nChanged + 1;
END_IF

(*------------------------------------------------------------------------------
 * 段 12｜原子写回：新值全部算完之后再按低字、高字顺序落盘
 *      Atomic write back after all new values are known
 *      若值未变则跳过写动作，避免下游映像刷新产生无谓的总线负载
 *-----------------------------------------------------------------------------*)
IF uNewLo <> uOldLo THEN
    auTarget[nIdxLo] := uNewLo;
END_IF
IF (nIdxHi > 0) AND (uNewHi <> uOldHi) THEN
    auTarget[nIdxHi] := uNewHi;
END_IF

(*------------------------------------------------------------------------------
 * 段 13｜收口：宽度定稿，无事件时置有效与返回真
 *      Close out: publish the effective width, legal calls return true
 *-----------------------------------------------------------------------------*)
nActualW := nWidth;
IF uErrorId = 16#0000_0000 THEN
    bValid               := TRUE;
    FC_DL_BitArrayInsert := TRUE;
END_IF
END_FUNCTION
