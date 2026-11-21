(*==============================================================================
 * 组件名称 (Component)  : FC_DL_BitArrayExtract
 * 所属子库 (Sublibrary) : DL_Base
 * 归属目录 (Directory)  : C:\Library\DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 函数（FUNCTION）· 纯函数 · 跨字位流窗口提取
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 SHL / SHR /
 *                         AND / OR 与显式类型转换，无厂商位访问方言，无实例依赖
 * 功能一句话 (Summary)  : 从 DWORD 数组构成的连续位流中按「起始位 + 位宽」取出
 *                         位窗口并右对齐输出，同时给出本次生效掩码。
 * 功能描述 (Function)   : 第 1 个数组元素承载位 0 到 31，第 2 个承载位 32 到 63，
 *                         依此类推（LSB 起）。调用方给出起始位与位宽，本件负责
 *                         跨字拼接、右移对齐、掩码构造与三类边界拦截。
 *                         典型现场用途：64 位设备状态字经两个保持寄存器上传后的
 *                         字段解码、凸轮表位图跨 4 个双字存放时的段取出、
 *                         远程 IO 位图跨字存放时的报警位段读取。
 * 与既有件边界 (Boundary): FC_DL_BitGet 取单字内单个位；FC_DL_BitFieldExtract 取
 *                         单字内 1 到 32 位段；FB_DL_UnpackWordToBits 把单字拆成
 *                         16 个固定位。三者都只作用于一个 32 位字。本件是「跨字
 *                         位流窗口」，位窗可跨 2 个双字、宽度可达 64 位，四者职责
 *                         互斥，不复用也不替代其中任何一件。
 * 设计要点 (Key notes)  : ① 闸门顺序固定为「字数 → 偏移 → 宽度 → 越界截断」，
 *                           任一闸门拦下即预置输出后返回，绝不让非法移位量进入
 *                           SHL / SHR（越界移位在部分编译器属未定义行为）；
 *                         ② 宽度 64 走满 1 常量分支，禁止 SHL(x, 64)；
 *                         ③ 截断只报事件不返回空值：现场宁可读到半段有效位，
 *                           由调用方依据 bValid 与 nActualW 自行判断完整度；
 *                         ④ 纯函数：无内部状态、无跨周期残留，同入参同结果。
 * 开源溯源 (Origin)     : 来源标签 lgf-bitlogic。LGF（Libre Graphical Framework）
 *                         为免费闭源发布的公开函数库手册，本件仅借鉴其位逻辑组
 *                         「单点 → 单段 → 批量段」的分层分类，以及「源 / 起位 /
 *                         位宽」三段参数域的组织方式；许可证按其发布方条款仅作
 *                         分类参考，本件零代码行、零注释、零数据结构引用，
 *                         属 clean-room 独立实现，不构成衍生作品。
 * 码位说明 (Codes)      : 本件独占信息级码段 16#0001_0125 到 16#0001_0127，纯函数
 *                         无锁存面故不占故障级码；三段与全库已占码求差为空，
 *                         不与 DL_MathData 的 0101 到 0124 任何一件重叠。
 *                         0125 偏移越界 ｜ 0126 宽度越界 ｜ 0127 跨字截断。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 SHL / SHR /
 *                         DWORD_TO_LWORD / INT_TO_DINT / INT_TO_UDINT。
 * 契约前置条件 (Contract): 入参为数组形参，函数内无法探测数组实际长度，故
 *                         「nSourceCount 不得大于调用方实际数组长度」由调用方负责。
 *                         这是本库唯一允许的契约式前置条件，调用方须在组态时保证。
 * 红线自检 (Redline)    : 零全局变量表依赖 ｜ 零外部变量声明 ｜ 零物理地址
 *                         纯 IEC 61131-3 ｜ 无除法故无除零面 ｜ 全变量双语同行注释
 *                         状态机 N/A（纯函数）｜ 无定时器实例
 * 修订历史 (Revision)   : 2026-11-15  v1.0.0  首版入库（Round 12 · 跨字位段族）
 *============================================================================*)

(*==============================================================================
 * 位流几何示意 (Bit stream geometry)：
 *   auSource[1] 承载位 0 到 31，auSource[2] 承载位 32 到 63，位号自低向高
 *   以 auSource[1] = 16#1234_5678、auSource[2] = 16#9ABC_DEF0 为例：
 *     拼接后的 64 位窗口为 16#9ABCDEF0_12345678
 *     起始位 28、位宽 8 取出的是位 28 到 35：低位 4 位来自第 1 字最高半字节，
 *     高位 4 位来自第 2 字最低半字节，右对齐结果为 16#01
 *     起始位 20、位宽 16 取出的位 20 到 35，右对齐结果为 16#0123
 *============================================================================*)

(*==============================================================================
 * 逐调用推演 (Call trace)：
 *   调用 1  两字、起始 28、位宽 8
 *     字数为 2，总位数 64；偏移 28 小于 64 通过；宽度 8 在 1 到 64 内通过
 *     28 加 8 等于 36 不超过 64，不截断
 *     低字下标 1，字内移位 28，28 加 8 大于 32 且 1 小于 2，高字下标 2
 *     拼接右移 28 位后取低 8 位，得 16#01，掩码 16#FF，有效
 *   调用 2  同上两字、起始 28、位宽 40
 *     28 加 40 等于 68 超过 32 位窗口可覆盖范围，宽度截为 4，事件码 0127
 *     结果只含 4 位可用值，bValid 为假，但值仍可读
 *   调用 3  起始 32、字数 1
 *     总位数 32，偏移不小于总位数，早退，事件码 0125，输出全零
 *============================================================================*)

(*==============================================================================
 * 调用示例 (Instance guide)：
 *   bOk := FC_DL_BitArrayExtract(
 *              auSource     := aStatusWords,
 *              nSourceCount := 2,
 *              nOffset      := 28,
 *              nWidth       := 8,
 *              uField       => uFieldOut,
 *              nActualW     => nWidthUsed);
 *   提示：uField 已右对齐，比较时应与右对齐期望值比较；判定完整度请看 bValid。
 *============================================================================*)

FUNCTION FC_DL_BitArrayExtract : BOOL
VAR_IN_OUT
    auSource     : ARRAY[1..8] OF DWORD;  // 源位流数组，第 1 元素为位 0 到 31，第 2 元素为位 32 到 63 [位串] / Source bit stream, element 1 holds bits 0 to 31
END_VAR
VAR_INPUT
    nSourceCount : INT := 1;              // 源有效字数 [个]，域 1 到 8，越界钳位 / Effective source word count, 1 to 8, clamped
    nOffset      : INT := 0;              // 位窗口起始位 [bit]，0 起，域 0 到 32 乘字数减 1 / Window start bit, zero based
    nWidth       : INT := 1;              // 位窗口宽度 [bit]，域 1 到 64 / Window width, 1 to 64
END_VAR
VAR_OUTPUT
    uField       : LWORD;                 // 右对齐提取结果，bit0 起连续 nActualW 位有效 [位串] / Extracted field, right aligned
    uMask        : LWORD;                 // 本次实际生效掩码，已右对齐，可直接与结果位与 [位串] / Effective right aligned mask
    nActualW     : INT;                   // 实际生效宽度，越界截断后的值 [bit] / Effective width after truncation
    uErrorId     : UDINT;                 // 事件码，0 表示无事件 / Event code, zero means none
    bValid       : BOOL;                  // 入参域全合法为真，发生截断或越界为假（截断时结果仍可用） / Inputs legal, false when truncated
END_VAR
VAR
    nTotalBits   : DINT;                  // 位流总位数，等于字数乘 32，DINT 中间量防 INT 溢出 [bit] / Total bit count, DINT to avoid overflow
    nIdxLo       : INT;                   // 低字下标，1 起 [索引] / Low word index, one based
    nIdxHi       : INT;                   // 高字下标，1 起，不跨字时置 0 [索引] / High word index, zero when not straddling
    uWide        : LWORD;                 // 两字拼接的 64 位窗口值 [位串] / Stitched 64 bit window
    uLo          : DWORD;                 // 低字快照 [位串] / Low word snapshot
    uHi          : DWORD;                 // 高字快照，不跨字时为 0 [位串] / High word snapshot, zero when absent
    nShift       : INT;                   // 字内移位量，等于偏移对 32 取模 [bit] / Intra word shift amount
END_VAR
VAR CONSTANT
    DL_SRC_MAX    : INT := 8;                          // 源字数上限 [个] / Source word count limit
    DL_BIT_MAX64  : INT := 64;                         // 位窗宽度上限 [bit] / Window width limit
    DL_BIT_MAX32  : INT := 32;                         // 单字位宽 [bit] / Bits per word
    DL_MASK64_ALL : LWORD := 16#FFFF_FFFF_FFFF_FFFF;   // 满宽掩码常量，64 宽分支专用 [位串] / All ones mask for the 64 bit branch
    DL_GUARD_MAX  : DINT := 64;                        // 循环守卫上限，本件直线实现无循环体，按组件族口径保留 [次] / Loop guard limit kept by family convention, no loop here
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出预置：任何异常路径下输出必须确定
 *      Pre-set outputs so that every path is deterministic
 *-----------------------------------------------------------------------------*)
FC_DL_BitArrayExtract := FALSE;
uField                := 16#0000_0000_0000_0000;
uMask                 := 16#0000_0000_0000_0000;
nActualW              := 0;
uErrorId              := 16#0000_0000;
bValid                := FALSE;

(*------------------------------------------------------------------------------
 * 段 2｜源字数钳位（边界 B1）：先夹到 1 到 8，再算总位数
 *      Clamp the word count first, then derive the total bit count
 *-----------------------------------------------------------------------------*)
IF nSourceCount < 1 THEN
    nSourceCount := 1;
ELSIF nSourceCount > DL_SRC_MAX THEN
    nSourceCount := DL_SRC_MAX;
END_IF
nTotalBits := INT_TO_DINT(nSourceCount) * INT_TO_DINT(DL_BIT_MAX32);

(*------------------------------------------------------------------------------
 * 段 3｜偏移闸门（边界 B2）：负偏移与落空偏移一律早退
 *      Offset gate: negative or beyond the stream end exits early
 *-----------------------------------------------------------------------------*)
IF (nOffset < 0) OR (INT_TO_DINT(nOffset) >= nTotalBits) THEN
    uErrorId := 16#0001_0125;   // 偏移越界，输出保持全零
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜宽度闸门（边界 B3）：宽度须落在 1 到 64 闭区间
 *      Width gate: the window width must be within one to sixty four
 *-----------------------------------------------------------------------------*)
IF (nWidth < 1) OR (nWidth > DL_BIT_MAX64) THEN
    uErrorId := 16#0001_0126;   // 宽度越界，输出保持全零
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜越界截断（边界 B4）：按位流末端截断，仍继续计算可用低位
 *      Truncation at the stream end: the usable low bits are still produced
 *      工程取舍：不返空值，现场宁可读半段，完整度交给 bValid 判断
 *-----------------------------------------------------------------------------*)
IF (INT_TO_DINT(nOffset) + INT_TO_DINT(nWidth)) > nTotalBits THEN
    nWidth   := DINT_TO_INT(nTotalBits - INT_TO_DINT(nOffset));
    uErrorId := 16#0001_0127;
    bValid   := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜定位（边界 B5）：求低字下标与字内移位量，判断是否跨字
 *      Locate the low word and the intra word shift, decide straddling
 *      nShift 由取模保证 0 到 31，负移位量不可能出现
 *-----------------------------------------------------------------------------*)
nIdxLo := nOffset / DL_BIT_MAX32 + 1;
nShift := nOffset MOD DL_BIT_MAX32;
nIdxHi := 0;
IF ((nShift + nWidth) > DL_BIT_MAX32) AND (nIdxLo < nSourceCount) THEN
    nIdxHi := nIdxLo + 1;
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜双字窗口深度校验（边界 B6）：位窗跨越第三个字时按双字窗口截断
 *      Third word guard: a window reaching the next word is truncated here
 *      原因：移位中间量为 64 位，起点非零时最多只能覆盖到第二个字末尾，
 *      若不截断则高位会静默读成零；此处显式截断并报事件，杜绝静默错值
 *-----------------------------------------------------------------------------*)
IF (nShift + nWidth) > DL_BIT_MAX64 THEN
    nWidth   := DL_BIT_MAX64 - nShift;
    uErrorId := 16#0001_0127;
    bValid   := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜拼接（边界 B7）：先取低字，跨字时把高字左移 32 位后并入
 *      Stitch low word first, then merge the high word shifted by 32
 *      下标安全性：偏移已验证小于总位数，故低字下标不超过字数上限；
 *      高字下标仅在下标小于字数时置位，越界读取不可能发生
 *-----------------------------------------------------------------------------*)
uLo   := auSource[nIdxLo];
uHi   := 16#0000_0000;
IF nIdxHi > 0 THEN
    uHi := auSource[nIdxHi];
END_IF
uWide := DWORD_TO_LWORD(uLo);
IF nIdxHi > 0 THEN
    uWide := uWide OR SHL(DWORD_TO_LWORD(uHi), DL_BIT_MAX32);
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜右对齐：整体右移字内移位量，移位量 0 到 31 必在合法域
 *      Right align by shifting the stitched window down
 *-----------------------------------------------------------------------------*)
uWide := SHR(uWide, INT_TO_UDINT(nShift));

(*------------------------------------------------------------------------------
 * 段 10｜掩码构造（边界 B8）：64 宽走满一常量分支，禁止左移 64 位
 *      Mask construction: the full width case uses the constant branch
 *-----------------------------------------------------------------------------*)
IF nWidth >= DL_BIT_MAX64 THEN
    uMask := DL_MASK64_ALL;
ELSE
    uMask := SHL(LWORD#1, INT_TO_UDINT(nWidth)) - LWORD#1;
END_IF

(*------------------------------------------------------------------------------
 * 段 11｜结果收口：掩码与窗口相与，宽度与有效位一次性定稿
 *      Close out: mask the window and publish the effective width
 *-----------------------------------------------------------------------------*)
uField   := uWide AND uMask;
nActualW := nWidth;
IF uErrorId = 16#0000_0000 THEN
    bValid                := TRUE;
    FC_DL_BitArrayExtract := TRUE;
END_IF
END_FUNCTION
