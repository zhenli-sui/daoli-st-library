(*==============================================================================
 * 组件名称 (Component)  : FC_DL_BitFieldExtract
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 函数（FUNCTION）· 纯函数 · 位段提取（打包的逆运算）
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅用标准 SHL / SHR / AND 位运算，
 *                         无任何厂商位访问方言，零标准库功能块依赖
 * 功能描述 (Function)   : 从 32 位源字中按「位偏移 + 位宽」提取任意宽度位段并
 *                         右对齐输出，同时给出本次实际生效的右对齐掩码，便于
 *                         调用方直接做位与判断。典型场景：通信状态字拆字段、
 *                         编码器状态位解析、驱动器 Statusword 位段解码、
 *                         Modbus 寄存器多字段拆分。
 * 与既有件边界 (Boundary): FC_DL_BitGet 取单个位；FB_DL_UnpackWordToBits 把
 *                         WORD 拆成 16 个固定位；本件取任意宽度位段（宽度
 *                         1 到 32，允许跨半字节、允许跨字节）。三者职责互斥，
 *                         本件是 FC_DL_WordBitPack（多位段打包进 WORD）的
 *                         逆运算件，不得与上述任一件重复实现。
 * 设计要点 (Key notes)  : ① 越界先判后算：偏移或宽度非法时立即早退，绝不把
 *                           非法移位量交给 SHL / SHR 执行（越界移位在部分
 *                           编译器为未定义行为，是跨平台移植的经典暗坑）；
 *                         ② 32 位满宽走常量全 1 掩码分支，禁止 SHL(1, 32)；
 *                         ③ 跨字截断按「可用低位段」继续计算，不返回 0，
 *                           保证现场仍能读到有效低位，仅置 bValid = FALSE；
 *                         ④ 纯函数语义：无内部状态、无跨周期残留，同一入参
 *                           组合在任何周期返回同一结果，可重入。
 * 开源溯源 (Origin)     : lgf-bitlogic。参考 LGF（Libre Graphical Framework）
 *                         公开函数库「Bit Logic」分类中位域提取类函数的功能
 *                         分类与参数域（源字 / 起始位 / 位宽 三段参数形态），
 *                         只借分类、参数域与命名习惯，算法与实现 100% 自有
 *                         clean-room，未参考任何源码行，不构成衍生作品。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 SHL / SHR
 * 故障码表 (Error codes):
 *   16#0001_0113【信息级】位偏移越界（须 0 到 31），结果 0，bValid = FALSE
 *   16#0001_0114【信息级】位宽越界（须 1 到 32），结果 0，bValid = FALSE
 *   16#0001_0115【信息级】跨字截断，按可用位计算，bValid = FALSE
 *   信息级码只进 uErrorId，不置任何故障位（本件无故障位，纯函数无锁存）。
 * 验收向量 (Acceptance) :
 *   V1 源 16#DEAD_BEEF / 偏移 8 / 宽 8 → 结果 16#BE，掩码 16#FF，bValid = TRUE
 *   V2 偏移 31 / 宽 4 → 实际宽 1，结果 1，码 0115，bValid = FALSE
 *   V3 偏移 0 / 宽 32 → 结果等于源字，掩码 16#FFFF_FFFF（走满宽常量分支）
 *   V4 偏移 -1 → 早退，结果 0，码 0113
 *   V5 宽 33 → 早退，结果 0，码 0114
 * 红线自检 (Redline)    : R1 零全局变量表与外部变量引用 ｜ R2 零物理地址直写
 *                         R3 纯 IEC 61131-3（无厂商位访问方言）｜ R4 越界先判后算
 *                         + 无除法故无除零面 ｜ R5 全变量中英双语同行注释
 *                         R6 N/A（纯函数无状态机）｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 10 · Level 0 位逻辑族回补）
 *============================================================================*)

(*==============================================================================
 * 位段几何示意 (Field geometry)：
 *   源字 31 位在左、0 位在右（本库统一 LSB = 0 约定）
 *     b31 b30 b29 b28 b27 b26 b25 b24 b23 b22 b21 b20 b19 b18 b17 b16
 *     b15 b14 b13 b12 b11 b10 b09 b08 b07 b06 b05 b04 b03 b02 b01 b00
 *   以 uSource = 16#DEAD_BEEF、nOffset = 8、nWidth = 8 为例：
 *     16#DEAD_BEEF 的二进制低 24 位为 1011 1110 1010 1101 1110 1110 1111
 *     从第 8 位起取 8 位，正好覆盖第 8 到第 15 位，其值为 16#BE
 *     掩码右对齐后为 16#0000_00FF，结果 16#0000_00BE
 *   以 nOffset = 31、nWidth = 4 为例（跨字截断）：
 *     只有第 31 位可用，实际宽度被截为 1，掩码为 16#0000_0001
 *     结果等于源字最高位，bValid 为 FALSE，码 0115
 *   以 nOffset = 0、nWidth = 32 为例（满宽特例）：
 *     掩码走常量分支 16#FFFF_FFFF，结果恒等于源字，零移位零风险
 *============================================================================*)

(*==============================================================================
 * 逐拍推演 (Cycle-by-cycle trace，本件为纯函数，推演即调用推演)：
 *   调用 1  uSource=16#DEAD_BEEF, nOffset=8, nWidth=8
 *     段 1 预置：结果 0、掩码 0、实际宽 0、码 0、有效 FALSE
 *     段 2 偏移 8 合法，通过
 *     段 3 宽度 8 合法，通过
 *     段 4 8 加 8 等于 16，不超过 32，不截断，实际宽 8
 *     段 5 实际宽 8 小于 32，掩码 左移 8 位减 1 得 16#FF
 *     段 6 源字右移 8 位后与掩码相与，得 16#BE
 *     段 7 码为 0，有效置 TRUE，返回 TRUE
 *   调用 2  nOffset=31, nWidth=4
 *     段 2 通过，段 3 通过
 *     段 4 31 加 4 等于 35，超过 32，实际宽截为 1，码 0115，有效 FALSE
 *     段 5 实际宽 1，掩码为 1
 *     段 6 源字右移 31 位后与 1 相与，结果为该位本身
 *     段 7 码非 0，不置有效，返回 FALSE（但结果可用）
 *   调用 3  nOffset=-1
 *     段 2 判负成立，码 0113，立即返回 FALSE，不做任何移位
 *============================================================================*)

(*==============================================================================
 * 调用示例 (Instance guide)：
 *   本件为纯函数，直接调用即可，无需实例化，可多处并发调用：
 *     bOk := FC_DL_BitFieldExtract(
 *                uSource := uDriveStatusWord,
 *                nOffset := 8,
 *                nWidth  := 4);
 *     IF bOk AND (uField = 16#0000_0002) THEN
 *         bReadyToSwitchOn := TRUE;
 *     END_IF
 *   若调用方需要「取整字中某一段并直接比较」，请先用 uMask 判断：
 *     bAnySet := (uField AND uMask) <> 16#0000_0000;
 *   提示：uField 已右对齐，比较时应与右对齐的期望值比较，不要与未右移的
 *   寄存器值比较，这是现场最常见的误判来源。
 *============================================================================*)

(*==============================================================================
 * 常见误用与现场提示 (Field notes)：
 *   1 把 nWidth 填 32 而 nOffset 填非 0，会走截断分支拿到部分结果，表面看
 *     「能读到数」，实则高位缺失；请同时看 bValid 与 uErrorId；
 *   2 判定「位段是否为某值」时直接比 uField 而不看 uMask，在截断情形下会
 *     把「宽度不足」误判为「值不符」，故障定位会走偏；
 *   3 源字为有符号整数时不要先转 DINT 再进来，符号扩展会把高位置 1，
 *     导致高位段解析出意外的 1；本件的入参是位串语义，不做符号解释；
 *   4 本件不修改源字，纯只读；若现场需要「读改回」（先提取再写回），
 *     请配合已入库的 FC_DL_WordBitPack 使用，不要在本件内加写出口。
 *============================================================================*)

FUNCTION FC_DL_BitFieldExtract : BOOL
VAR_INPUT
    uSource  : DWORD;      // 源字，任意 32 位值，不做符号解释 [位串] / Source word, raw 32-bit, no sign interpretation
    nOffset  : INT := 0;   // 位段起始偏移，0 = LSB，有效域 0 到 31 [bit] / Start bit offset, 0 = LSB, valid 0 to 31
    nWidth   : INT := 1;   // 位段宽度，有效域 1 到 32 [bit] / Field width, valid 1 to 32
END_VAR
VAR_OUTPUT
    uField   : DWORD;      // 提取结果，bit0 起连续 nWidth 位有效（右对齐）[位串] / Extracted field, right aligned from bit0
    uMask    : DWORD;      // 本次实际生效掩码，已右对齐，可直接与结果做位与 [位串] / Effective right-aligned mask
    nActualW : INT;        // 实际生效宽度，越界截断后的值，1 到 32 [bit] / Effective width after truncation, 1 to 32
    uErrorId : UDINT;      // 事件码，0 = 无事件 / Event code, 0 = no event
    bValid   : BOOL;       // 入参域全部合法 = TRUE；发生截断 = FALSE（结果仍可用） / All inputs legal = TRUE, truncated = FALSE
END_VAR
VAR
    uShiftAmt : UDINT;     // 移位量中间量，由 INT 显式转换以规避混合类型移位 [bit] / Shift amount temp, explicitly promoted to UDINT
END_VAR
VAR CONSTANT
    DL_BIT_MAX  : INT := 32;              // 字长上限 [bit]（DWORD 为 32 位） / Word width upper bound [bit]
    DL_BIT_MIN  : INT := 1;               // 最小可提取宽度 [bit] / Minimum extractable width [bit]
    DL_MASK_ALL : DWORD := 16#FFFF_FFFF;  // 全 1 掩码，满宽分支专用 [位串] / All-ones mask for the full-width branch
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜返回值与输出预置：任何异常路径下输出必须确定
 *      Pre-set return value and outputs: deterministic on every path
 *      部分平台函数返回值未赋值时残留上次调用值，故先给 FALSE 与 0
 *-----------------------------------------------------------------------------*)
FC_DL_BitFieldExtract := FALSE;
uField   := 16#0000_0000;
uMask    := 16#0000_0000;
nActualW := 0;
uErrorId := 16#0000_0000;
bValid   := FALSE;

(*------------------------------------------------------------------------------
 * 段 2｜偏移越界先判后算（边界 B1）：负偏移与超 31 一律早退
 *      Offset bounds check before any shift (boundary B1)
 *      nOffset 为有符号 INT，负数必须显式拦截，否则会被当成巨大移位量
 *-----------------------------------------------------------------------------*)
IF (nOffset < 0) OR (nOffset >= DL_BIT_MAX) THEN
    uErrorId := 16#0001_0113;   // 位偏移越界，结果 0
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜位宽越界先判后算（边界 B2）：宽度须落在 1 到 32 闭区间
 *      Width bounds check before any shift (boundary B2)
 *-----------------------------------------------------------------------------*)
IF (nWidth < DL_BIT_MIN) OR (nWidth > DL_BIT_MAX) THEN
    uErrorId := 16#0001_0114;   // 位宽越界，结果 0
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜跨字截断（边界 B3）：偏移加宽度或超过 32 位时按可用位截断
 *      Cross-word truncation (boundary B3): clamp to the available high bits
 *      工程取舍：不返 0 而返部分位段，现场仍可读到有效低位并自行判 bValid
 *-----------------------------------------------------------------------------*)
nActualW := nWidth;
IF (nOffset + nWidth) > DL_BIT_MAX THEN
    nActualW := DL_BIT_MAX - nOffset;   // 只保留落在字内的位
    uErrorId := 16#0001_0115;           // 跨字截断，结果按可用位有效
    bValid   := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜掩码构造（边界 B4）：满宽走常量分支，禁止 SHL(1, 32)
 *      Mask construction (boundary B4): full width uses the constant mask branch
 *      SHL(DWORD#1, 32) 在多数 32 位编译器上属未定义行为（移位量等于位宽），
 *      故宽度恰为 32 时必须走 DL_MASK_ALL 常量，绝不进移位路径
 *-----------------------------------------------------------------------------*)
IF nActualW >= DL_BIT_MAX THEN
    uMask := DL_MASK_ALL;                                   // 满宽：全 1 常量，零移位
ELSE
    uShiftAmt := INT_TO_UDINT(nActualW);                    // 显式转换，规避混合类型移位
    uMask     := SHL(DWORD#1, uShiftAmt) - DWORD#1;         // 低 n 位置 1：2 的 n 次方减 1
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜位段提取（边界 B5）：先右移后掩码，次序不得颠倒
 *      Field extraction: shift right first, then mask, order must not be swapped
 *      若先掩码后右移，落在高位的垃圾位会被一起保留，结果将随源字高位变化
 *-----------------------------------------------------------------------------*)
uShiftAmt := INT_TO_UDINT(nOffset);                         // 偏移显式转无符号移位量
uField    := SHR(uSource, uShiftAmt) AND uMask;             // 右对齐位段

(*------------------------------------------------------------------------------
 * 段 7｜合法收口：仅在未发生截断时置 bValid 与返回 TRUE
 *      Legal close-out: only a non-truncated call sets bValid and returns TRUE
 *-----------------------------------------------------------------------------*)
IF uErrorId = 16#0000_0000 THEN
    bValid                := TRUE;
    FC_DL_BitFieldExtract := TRUE;
END_IF

(*------------------------------------------------------------------------------
 * 反例提示（现场高频误用）：把 nWidth 直接填成 32 而 nOffset 填非 0，会走到截断
 * 分支拿到部分结果，表面看「能读到数」，实则高位缺失；调试时请同时看 bValid
 * 与 uErrorId，不要只看 uField 是否非零。
 *-----------------------------------------------------------------------------*)
END_FUNCTION
