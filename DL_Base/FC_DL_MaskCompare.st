(*==============================================================================
 * 组件名称 (Component)  : FC_DL_MaskCompare
 * 所属子库 (Sublibrary) : DL_Base
 * 归属目录 (Directory)  : C:\Library\DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 分类/来源标签         : 函数（FUNCTION）· 纯函数 · 状态字掩码比较与差异定位
 *                         lgf-comparator / lgf-bitlogic / mask-compare
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 SHL / SHR /
 *                         AND / XOR，无厂商位访问方言，无实例依赖
 * 功能一句话 (Summary)  : 判「值按掩码比较是否等于期望」，并给出差异位图、差异
 *                         位数与首个差异位号，供报警直接定位到具体那一位。
 * 功能描述 (Function)   : 核心判据为「值与期望各自按掩码相与后判等」。掩码为 0 的位
 *                         不参与比较（don't-care 位），位宽参数把高于 nWidth 减 1 的
 *                         位排除在比较之外（只比低 n 位）。典型现场用途：变频器状态
 *                         字只看「运行、故障、就绪」三位的组合、远程 IO 模块状态字
 *                         忽略保留位后的整字比对、多轴使能位图的期望态一致性检查、
 *                         以及报警诊断时直接报出「差在第几位」而不是只说「不匹配」。
 * 与既有件边界 (Boundary): FC_DL_BitFieldExtract 是「取一段」（把位段取出后由调用方
 *                         自行比较）；FB_DL_StatusWordSegDecoder 是「段表批量解码」
 *                         （把状态字按段拆成多个语义位）；本件是「判等 + 差异定位」，
 *                         一次调用既回答「是否匹配」又回答「差在哪几位」。三者互补，
 *                         不互相替代。
 * 设计要点 (Key notes)  : ① 掩码与位宽两重屏蔽严格串联：先按位宽裁出有效位域，再与
 *                           调用方掩码相与，两道屏蔽同时生效，不存在「宽掩码压过窄位宽」
 *                           的漏判；
 *                         ② 位宽 32 走全一常量分支，禁止 SHL 移位量等于位宽（部分
 *                           编译器对此属未定义行为）；
 *                         ③ 差异位号由低位向高位扫描，报「最低的那个差异位」，与现场
 *                           按位号读状态字的习惯一致；
 *                         ④ 纯函数：无内部状态、无跨周期残留，同入参同结果。
 *
 * 【验收向量 / Acceptance vectors】
 *   V1  值 16#1234_5678、期望 16#0034_5678、掩码 16#00FF_FFFF
 *       → 返回真、差异位图 0、差异位数 0、首差位 负 1（高 8 位被掩掉，不参与）
 *   V2  同 V1 但期望改 16#0034_5670 → 返回假、差异位图 16#0000_0008、
 *       差异位数 1、首差位 3
 *   V3  V-A 域外：位宽 0 → 返回假、码 0220、差异位图 0（不输出脏位图）
 *   V4  V-B 边界：位宽 32、掩码全一、值 0、期望 16#8000_0000
 *       → 返回假、首差位 31（验证 32 位常量掩码路径，不做按位宽移位）
 *   V5  位宽 5、掩码 16#FFFF_FFFF、值 16#0000_0020、期望 0
 *       → 返回真、差异位图 0（第 5 位及以上被位宽裁掉，越界位不参与比较）
 *   V6  掩码 0 → 返回真、码 0140（恒匹配，提示掩码没生效）
 *
 * 开源溯源 (Origin)     : 来源标签 lgf-comparator 与 lgf-bitlogic。LGF（Libre
 *                         Graphical Framework）为免费闭源发布的公开函数库手册，
 *                         本件仅借鉴其「二进制掩码比较」块的语义域（值、期望、掩码
 *                         三引脚）与比较器组「单值、区间、掩码」的分类粒度；许可证
 *                         按其发布方条款仅作分类参考，本件零代码行、零注释、零数据
 *                         结构引用，属 clean-room 独立实现，不构成衍生作品。
 * 码位说明 (Codes)      : 信息 16#0001_013F 位宽已钳到 32 ｜ 16#0001_0140 掩码为 0
 *                         故障 16#0001_0220 位宽非法。取号见本轮规格 §3.2，与位段族
 *                         0125 到 013E 区间不重叠。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 SHL / SHR / AND /
 *                         XOR 与 INT_TO_UDINT 显式转换。
 * 镜像量清单 (R38)      : 本件无锁存副本，差异位图与差异位数都由同一份本拍差值导出，
 *                         不存在锁存量与实时量混用面。
 * 红线自检 (Redline)    : 零全局变量表依赖 ｜ 零外部变量声明 ｜ 零物理地址直写
 *                         纯 IEC 61131-3 ｜ 无除法故无除零面 ｜ 位宽 32 走常量分支
 *                         全变量双语同行注释 ｜ 状态机 N/A（纯函数）｜ 无定时器实例
 * 修订历史 (Revision)   : 2026-11-15  v1.0.0  首版入库（Round 13 · 泳道 B 位段族收口）
 *============================================================================*)

(*==============================================================================
 * 双重屏蔽示意 (Double masking)：
 *   位宽 5、掩码全一、值 16#0000_0020、期望 0
 *   第一步按位宽裁出低位域 16#0000_001F
 *   第二步与掩码相与仍为 16#0000_001F
 *   值域为 0、期望域为 0，差为 0，返回真；第 5 位虽然置位但不在契约位宽内
 *   若掩码改为 16#0000_0020 而位宽仍是 5，有效掩码变成 0，属「掩码被位宽吃掉」，
 *   此时按恒匹配处理并给出 0140，提示调用方掩码与位宽矛盾
 *============================================================================*)

FUNCTION FC_DL_MaskCompare : BOOL
VAR_INPUT
    uValue  : DWORD;                    // 待比较值 [位串] / Value under test
    uExpect : DWORD;                    // 期望值 [位串] / Expected value
    uMask   : DWORD := 16#FFFF_FFFF;    // 参与比较的位，1 参与比较、0 不关心 [位串] / Care mask, one means compare
    nWidth  : INT := 32;                // 有效位宽 [bit]，域 1 到 32 / Effective width, 1 to 32
END_VAR
VAR_OUTPUT
    uDiffBits  : DWORD;                 // 差异位图，已按位宽与掩码双重屏蔽 [位串] / Difference bitmap after both masks
    nDiffCount : INT;                   // 差异位数 [个]，域 0 到 32 / Difference bit count, 0 to 32
    nFirstDiff : INT;                   // 首个差异位号 [bit]，域 0 到 31，无差异为负 1 / First differing bit, minus one when none
    uErrorId   : UDINT;                 // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    nW         : INT;                   // 钳位后的有效位宽 [bit] / Clamped effective width
    uWidthMask : DWORD;                 // 位宽掩码，低 nW 位为 1 [位串] / Width mask with the low nW bits set
    uMaskEff   : DWORD;                 // 生效掩码，位宽掩码与调用方掩码相与 [位串] / Effective mask combining width and caller mask
    uDiff      : DWORD;                 // 值与期望按生效掩码异或的结果 [位串] / XOR result under the effective mask
    uScan      : DWORD;                 // 扫描副本，逐位右移 [位串] / Shifting scan copy
    nI         : INT;                   // 位扫描下标 [bit]，固定 0 到 31 / Bit scan index, fixed 0 to 31
    nCount     : INT;                   // 差异位计数累加 [个] / Running difference count
    nFirst     : INT;                   // 首个差异位累加，未命中保持负 1 / Running first differing bit, minus one when none
    uCode      : UDINT;                 // 码位暂存，出口单点写入 [码] / Code staging, written once at the exit
END_VAR
VAR CONSTANT
    DL_MC_MAXW    : INT := 32;                  // 最大位宽 [bit]，与位宽默认值一致 / Maximum width, matches the default width
    DL_MC_MASK32  : DWORD := 16#FFFF_FFFF;      // 满宽掩码常量，位宽 32 分支专用 [位串] / All ones mask for the 32 bit branch
    DL_MC_NONE    : INT := -1;                  // 无差异位号的表示值 [bit] / Sentinel for no differing bit
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出预置：差异类输出一律先归零，任何早退路径都不会留下脏位图
 *      Pre-set the difference outputs so early exits never publish stale bits
 *-----------------------------------------------------------------------------*)
FC_DL_MaskCompare := FALSE;
uDiffBits         := 16#0000_0000;
nDiffCount        := 0;
nFirstDiff        := DL_MC_NONE;
uErrorId          := 16#0000_0000;
uCode             := 16#0000_0000;
uDiff             := 16#0000_0000;
nCount            := 0;
nFirst            := DL_MC_NONE;

(*------------------------------------------------------------------------------
 * 段 2｜位宽闸门（边界 B1/B2）：小于 1 属逻辑错，早退；大于 32 钳位后照算
 *      Width gate: below one exits early, above thirty two is clamped
 *      位宽是契约参数，判错就把责任交回调用方，不用猜的值去凑结果
 *      The width is a contract parameter, guessing it would hide the configuration error
 *-----------------------------------------------------------------------------*)
IF nWidth < 1 THEN
    uErrorId := 16#0001_0220;   // 故障级：位宽非法，差异位图保持 0
    RETURN;
ELSIF nWidth > DL_MC_MAXW THEN
    nW    := DL_MC_MAXW;
    uCode := 16#0001_013F;      // 信息级：位宽已钳到 32
ELSE
    nW := nWidth;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜掩码构造（边界 B3）：位宽 32 用满一常量，其余用左移减一构造
 *      Mask construction: the full width case uses a constant, others shift minus one
 *      若在此处按位宽做移位，位宽 32 就会变成「移位量等于位宽」，属未定义行为
 *      Shifting by the full width here would be undefined behaviour on some compilers
 *-----------------------------------------------------------------------------*)
IF nW >= DL_MC_MAXW THEN
    uWidthMask := DL_MC_MASK32;
ELSE
    uWidthMask := SHL(DWORD#1, nW) - DWORD#1;
END_IF

uMaskEff := uMask AND uWidthMask;

(* 掩码为零属恒匹配：判据天然成立，但要提示调用方「掩码与位宽矛盾」
 * A zero mask matches anything, still worth telling the caller the mask is inert
 * 优先级低于位宽钳位码，故仅在未占用时写入
 * Lower priority than the clamp code above, written only when the slot is free *)
IF (uMaskEff = 16#0000_0000) AND (uCode = 16#0000_0000) THEN
    uCode := 16#0001_0140;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜判等与差异定位（边界 B4）：异或取差，逐位统计，先低后高
 *      Compare and locate: XOR the difference, then scan low bits first
 *      扫描固定 32 次、每次右移一位，移位量恒为 1，无动态移位风险
 *      The scan is a fixed thirty two passes shifting by one bit each time
 *-----------------------------------------------------------------------------*)
uDiff := (uValue XOR uExpect) AND uMaskEff;

IF uDiff = 16#0000_0000 THEN
    uDiffBits  := 16#0000_0000;
    nDiffCount := 0;
    nFirstDiff := DL_MC_NONE;
    FC_DL_MaskCompare := TRUE;          // 按契约位域完全一致 / Full match inside the contract bit field
ELSE
    uScan := uDiff;
    FOR nI := 0 TO (DL_MC_MAXW - 1) DO
        IF (uScan AND DWORD#1) = DWORD#1 THEN
            nCount := nCount + 1;
            IF nFirst = DL_MC_NONE THEN
                nFirst := nI;           // 首次命中即最低差异位 / The first hit is the lowest differing bit
            END_IF
        END_IF
        uScan := SHR(uScan, 1);
    END_FOR;
    uDiffBits  := uDiff;
    nDiffCount := nCount;
    nFirstDiff := nFirst;
    FC_DL_MaskCompare := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜码位单点写入：全拍只写一次，优先级已在段 2 与段 3 排定
 *      Single write point for the code, the priority was settled above
 *-----------------------------------------------------------------------------*)
uErrorId := uCode;
END_FUNCTION
