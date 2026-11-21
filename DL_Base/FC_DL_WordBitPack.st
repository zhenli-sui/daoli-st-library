(*==============================================================================
 * 组件名称 (Component)  : FC_DL_WordBitPack
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.1
 * 分类     (Category)   : 位逻辑纯函数（Function · Bit Logic）
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（SHL / SHR / AND / OR / NOT），
 *                         零厂商方言
 * 功能简介 (Function)   : 按位偏移 + 位宽参数把字段值合入目标字（打包），同拍
 *                         经输出引脚回读该位段旧值（解包），一个函数完成
 *                         「读-改-写」原子语义：uExtracted 给出改动前的位段
 *                         内容，返回值给出改动后的整字。字段值右对齐，超出
 *                         位宽的高位被掩码忽略。偏移+宽度越界或宽度为 0 时
 *                         拒绝执行：返回原字不动、uExtracted 返回 0、置故障码
 *                         （禁止半写，防位段被撕裂）。纯函数：无状态、无副作用。
 *                         与已入库 FC_DL_PackBitsToWord（16 点 BOOL 打包整字）、
 *                         FB_DL_UnpackWordToBits（整字展开 16 点）职责分离——
 *                         本块是任意位段（偏移/宽度参数化）的打包解包原子。
 * 开源溯源 (Origin)     : 原创实现（参考 LGF 库 Bit Logic 位逻辑分类的功能域
 *                         与参数域，来源标签 lgf-bitlogic），读-改-写掩码法为
 *                         公开经典位运算手法，仅借分类/参数域/命名，clean-room
 *                         实现，未复制任何厂商私有库源码，不构成衍生作品。
 * 日期     (Date)       : 2026-11-15 ｜ 作者 (Author): Daoli Library
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: SHL / SHR / AND / OR / NOT
 *
 *------------------------------------------------------------------------------
 * 【引脚契约 / Pin contract】
 *   输入 uTarget    : WORD  — 目标载体字（旧内容），打包基址；
 *   输入 uField     : WORD  — 待合入字段值（右对齐，超出位宽的高位被忽略）；
 *   输入 nOffset    : USINT — 位段起始偏移 [bit]，合法域 0~15；
 *   输入 nWidth     : USINT — 位段宽度 [bit]，合法域 1~16；
 *   输出 uExtracted : WORD  — 该位段的旧值（右对齐回读，即解包结果）；
 *   输出 uErrorId   : UDINT — 故障码，0 = 无故障；16#0001_0108 = 位段越界拒绝；
 *   返回值          : WORD  — 合成后的字（拒绝路径返回原字不动）。
 *
 * 【边界防错清单 / Boundary guard list】
 *   B1 nWidth = 0 或 nWidth > 16 或 nOffset >= 16 或 nOffset + nWidth > 16 →
 *      置故障，返回原字不动、uExtracted 返回 0（禁止半写：宁可整拍不动，
 *      绝不撕裂位段）。四项判据缺一不可：nWidth / nOffset 引脚类型为 USINT
 *      （域 0~255），若只判 nOffset + nWidth > 16，则 15 + 250 = 265 在 USINT
 *      域内回绕成 9 从而漏判，随后 SHL 位移 250 位落入平台未定义行为
 *      （v1.0.1 终审补齐，原 v1.0.0 只有两项判据）。
 *   B2 掩码构造：宽度 16 时左移 16 位行为按「满宽度掩码显式分支」处理，
 *      不依赖平台移位语义（部分平台 SHL(x,16) 结果为 0 或回绕，口径不一）；
 *   B3 字段值合入前先按位段宽度掩码截断（高位越宽忽略），再左移对齐；
 *   B4 纯函数无状态，同输入同输出；拒绝路径输入输出零修改；
 *   B5 逐项判界后 nOffset <= 15 且 nWidth <= 16，加法上界 31 不越 USINT 域，
 *      全部移位计数值严格小于 16（平台无关）。
 *
 * 【原子语义声明 / Atomic semantics】
 *   「读-改-写」原子指单次调用内完成三步：读（uExtracted 回读旧位段）、
 *   改（掩码清旧段）、写（新字段值入段）；调用方在同一表达式中同时取得
 *   改前值与改后值，无需两次调用，避免了两次调用之间字段值被外部修改的
 *   时序缝隙。注意：原子性限于本函数单次调用内部，跨多个调用方的整字
 *   互斥仍需上层仲裁（本函数不持锁、不触碰任何共享存储）。
 *
 * 【调用示例 / Call example】
 *   「把模式号 3 写入状态字的 bit4~bit7，同时留档旧模式」
 *   wOldMode := FC_DL_WordBitPack(uTarget := wStatus, uField := 3,
 *                                 nOffset := 4, nWidth := 4,
 *                                 uExtracted => wOldMode, uErrorId => uErr);
 *
 * 【平台移植注意 / Porting notes】
 *   各平台 SHL/SHR 对移位计数 ≥ 数据宽度的行为定义不一（结果 0 / 回绕 /
 *   未定义），本函数通过边界 B1（越界拒绝）与 B2（满宽度显式分支）从设计上
 *   规避了该平台差异，全部移位计数值均严格小于 16，不触发任何方言行为。
 *
 * 【同族职责分离 / Family separation】
 *   FC_DL_PackBitsToWord：16 点 BOOL → 整字（固定全字打包，无偏移参数）；
 *   FB_DL_UnpackWordToBits：整字 → 16 点 BOOL（固定全字解包）；
 *   本函数：任意位段（偏移/宽度参数化）打包 + 解包回读，三者正交不互调。
 *
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓ ｜ R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 标准位运算 ✓ ｜ R4 越界拒绝禁半写/
 *                           出口唯一/无除法/循环界常量无死锁 ✓
 *                         R5 全变量中英双语同行注释 ✓ ｜ R6 N/A（纯函数无状态机）
 *                         R7 N/A（无定时器/边沿实例）｜ R8 位宽/偏移/掩码全常量化 ✓
 * 验收向量 (Acceptance) :
 *   V1  uTarget=16#0000, uField=16#3,  nOffset=4,  nWidth=4
 *       → 返回 16#0030, uExtracted = 16#0000, uErrorId = 0
 *   V2  uTarget=16#00FF, uField=16#0,  nOffset=0,  nWidth=8
 *       → 返回 16#0000, uExtracted = 16#00FF, uErrorId = 0
 *   V3  uTarget=16#0000, uField=16#F,  nOffset=12, nWidth=4
 *       → 返回 16#F000, uExtracted = 16#0000, uErrorId = 0
 *   V4  uTarget=16#1234, uField=16#A,  nOffset=4,  nWidth=4
 *       → 返回 16#12A4, uExtracted = 16#0003, uErrorId = 0
 *   V5  uTarget=16#1234, uField=16#AA, nOffset=4,  nWidth=5
 *       → 返回 16#12A4, uExtracted = 16#0003, uErrorId = 0
 *       【验算注记 / Verification note】ROUND_PLAN_R9 §9 V5 表原载期望返回
 *       16#1264；按「右对齐 + 超宽高位忽略」语义逐位验算：
 *         掩码 = 5 个 1 左移 4 位           = 16#01F0
 *         uField 16#AA 截低 5 位（16#AA AND 16#1F）= 16#0A
 *         字段左移 4 位                     = 16#00A0
 *         载体清段 16#1234 AND NOT 16#01F0  = 16#1204
 *         合成 16#1204 OR 16#00A0           = 16#12A4
 *       【R9 终审裁定 / Final ruling】总监逐位独立复核，结果 16#12A4：位 4~8
 *       由 0_1010 覆盖后为 0001_0010_1010_0100。16#1264 的位 4~8 = 0_0110
 *       （字段值 6），与本组入参 16#AA、宽度 5、偏移 4 无任何推导路径，
 *       判定为**计划向量笔误**：代码对、向量错。已同步勘误 ROUND_PLAN_R9.md
 *       §9 V5 表（16#1264 → 16#12A4 并附勘误脚注），保留 R8「公式对、
 *       向量错」口径的勘误留痕；本组件实现不做改动。
 *   V6  uTarget=16#1234, uField=16#1,  nOffset=15, nWidth=2
 *       → 返回 16#1234（原字不动）, uExtracted = 16#0000,
 *         uErrorId = 16#0001_0108（偏移+宽度越界拒绝）
 *   V7  uTarget=16#1234, uField=16#1,  nOffset=15, nWidth=250（v1.0.1 新增）
 *       → 返回 16#1234（原字不动）, uExtracted = 16#0000,
 *         uErrorId = 16#0001_0108（宽度单项越界拒绝；若只判「偏移+宽度>16」，
 *         15+250 在 USINT 域回绕为 9 会漏判，故宽度 / 偏移各自设界）
 *
 * 【故障码表 / Error code table】
 *   16#0001_0108  位段越界拒绝：nWidth = 0 / nWidth > 16 / nOffset >= 16 /
 *                 nOffset + nWidth > 16，返回原字不动、uExtracted = 0，
 *                 瞬时码每次调用重算（0108 空闲，0101~0107 已被计数/步进/
 *                 BCD 族登记，0109 已被 MonthWindowCheck 登记，010A 起空闲）。
 *
 * 【实现选择 / Implementation choice】
 *   两掩码法：段掩码 uMask = width 个 1 左移 offset（清旧段 + 提旧值共用），
 *   字段掩码 uFieldMask = SHR(uMask, nOffset)（截断超宽高位）；合成式
 *   (uTarget AND NOT uMask) OR SHL(uField AND uFieldMask, nOffset)，三个
 *   中间量全部显式命名，无嵌套魔法表达式；满宽度（width = 16）走显式分支
 *   直接赋 16#FFFF，规避平台移位语义差异（边界 B2）。
 *
 * 【逐步验算表 / Step-by-step walkthrough（供终审逐组代回验算）】
 *   V1 掩码 16#00F0；uExtracted = 0；清段 0；合段 3<<4 = 16#0030 ✓
 *   V2 掩码 16#00FF；uExtracted = 16#00FF；清段后 0；合段 0 → 16#0000 ✓
 *   V3 掩码 16#F000；uExtracted = 0；合段 16#F<<12 = 16#F000 ✓
 *   V4 掩码 16#00F0；uExtracted = (16#34 AND 16#F0)>>4 = 3；
 *      清段 16#1204；合段 16#A<<4 = 16#A0 → 16#12A4 ✓
 *   V5 掩码 16#01F0；uExtracted = (16#34 AND 16#F0)>>4 = 3；
 *      字段截断 16#AA AND SHR(16#01F0,4) = 16#AA AND 16#1F = 16#0A；
 *      清段 16#1204；合段 16#0A<<4 = 16#A0 → 16#12A4（差异注记见上）✓
 *   V6 15 + 2 = 17 > 16 → 拒绝：原字 16#1234 原样返回、uExtracted = 0、
 *      置 0001_0108 ✓
 *
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（Round 09 · 泳道 A · LGF Bit Logic 组）
 *   2026-11-15  v1.0.1  终审修复：参数防御补「nWidth > 16」「nOffset >= 16」
 *                       两项单项判界（原实现只判 nOffset + nWidth > 16，USINT
 *                       域 15 + 250 回绕为 9 可绕过校验并触发平台未定义移位）；
 *                       同步落定 V5 向量裁定（计划表 16#1264 → 代码实测语义
 *                       16#12A4，计划文件已勘误）
 *============================================================================*)
FUNCTION FC_DL_WordBitPack : WORD          // 返回合成后的字 / Returns the assembled word
VAR_INPUT
    uTarget  : WORD;                       // 目标载体字（旧内容）/ Target carrier word (previous content)
    uField   : WORD;                       // 待合入字段值，右对齐，超宽高位被忽略 / Field value to merge, right-aligned, bits above width ignored
    nOffset  : USINT;                      // 位段起始偏移 [bit]，合法域 0~15 / Field start offset [bit], legal range 0~15
    nWidth   : USINT;                      // 位段宽度 [bit]，合法域 1~16 / Field width [bit], legal range 1~16
END_VAR
VAR_OUTPUT
    uExtracted : WORD;                     // 该位段旧值，右对齐回读（解包结果）/ Previous field value, right-aligned (unpack result)
    uErrorId   : UDINT;                    // 故障码，0 = 无故障，0001_0108 = 越界拒绝 / Error code, 0 = none, 0001_0108 = out-of-range rejected
END_VAR
VAR
    uMask      : WORD;                     // 位段掩码：width 个 1 左移 offset / Field mask: width ones shifted left by offset
    uMaskInv   : WORD;                     // 掩码反相：清旧段用 / Inverted mask for clearing the old field
    uFieldMask : WORD;                     // 字段掩码：段掩码右对齐，截超宽高位 / Field-side mask, right-aligned, truncates oversized bits
    uFieldTrim : WORD;                     // 截断后的字段值（右对齐）/ Trimmed field value (right-aligned)
    uFieldAlgn : WORD;                     // 对齐后的字段值（左移 offset）/ Aligned field value (shifted left by offset)
    uBase      : WORD;                     // 清段后的载体字 / Carrier word with the old field cleared
    bValid     : BOOL;                     // 参数合法标志（拒绝路径闸门）/ Parameter validity flag (rejection-path gate)
END_VAR
VAR CONSTANT
    DL_WORD_BITS : USINT := 16;            // WORD 位宽 [bit] / Width of a WORD [bit]
    DL_WORD_FULL : WORD  := 16#FFFF;       // 满字掩码（宽度 16 显式分支用）/ Full-word mask for the explicit width-16 branch
    DL_BIT_ONE   : WORD  := 16#0001;       // 单位种子（掩码构造显式 WORD 化，防字面量平台默认类型差异）/ One-bit seed, explicit WORD typing to avoid platform literal defaults
    DL_BIT_ERR_RNG: UDINT := 16#0001_0108; // 位段越界拒绝故障码 / Error code for out-of-range rejection
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜安全预置（P-01 范式）：拒绝路径返回原字、uExtracted 返回 0
 *      Safe preset: rejection paths return the original word, uExtracted = 0
 *-----------------------------------------------------------------------------*)
uErrorId     := 16#0000_0000;              // 故障码预清零，正常路径末尾保持 0 / Error code preset to zero, stays 0 on the normal path
uExtracted   := 16#0000;                   // 解包结果预清零，合法路径段 3 回读覆盖 / Unpack result preset to zero, overwritten by stage 3 on legal paths
bValid       := TRUE;                      // 参数合法性预置为通过（Validity preset to pass）

(*------------------------------------------------------------------------------
 * 段 2｜参数防御（边界 B1）：宽度 0 / 宽度 > 16 / 偏移 >= 16 / 偏移+宽度 > 16
 *      任一命中即整体拒绝，禁半写
 *      Parameter guard (B1): zero width, width above 16, offset at or above 16,
 *      or offset plus width above 16 rejects the whole call
 *      单项判界先于求和判界：USINT 域内 15 + 250 = 265 会回绕成 9，
 *      只判求和会漏判并让 SHL 移位 250 位落入平台未定义行为（v1.0.1 补齐）
 *      Single checks precede the sum check because the USINT sum wraps
 *-----------------------------------------------------------------------------*)
IF (nWidth = 0) OR (nWidth > DL_WORD_BITS) OR (nOffset >= DL_WORD_BITS) OR
   (nOffset + nWidth > DL_WORD_BITS) THEN
    bValid   := FALSE;                     // 参数非法，置拒绝闸门 / Invalid parameters, close the rejection gate
    uErrorId := DL_BIT_ERR_RNG;            // 置位段越界拒绝故障码 / Raise out-of-range rejection code
END_IF

IF bValid THEN
    (*--------------------------------------------------------------------------
     * 段 3｜解包回读（读）：旧位段右对齐提取，同拍返回给调用方留档
     *      Unpack read-back (read): old field extracted right-aligned
     *-------------------------------------------------------------------------*)
    IF nWidth = DL_WORD_BITS THEN
        uMask := DL_WORD_FULL;             // 满宽度显式分支：直接全字掩码 / Explicit width-16 branch: full-word mask directly
    ELSE
        uMask := SHL(SHL(DL_BIT_ONE, nWidth) - 1, nOffset); // width 个 1 左移 offset（种子显式 WORD 化）/ width ones shifted left by offset (explicit WORD seed)
    END_IF
    uMaskInv := NOT uMask;                 // 掩码反相，清旧段用 / Invert mask for clearing the old field
    uExtracted := SHR(uTarget AND uMask, nOffset); // 旧位段右对齐回读 / Read back old field, right-aligned

    (*--------------------------------------------------------------------------
     * 段 4｜打包合成（改 + 写）：清旧段 → 字段截断 → 对齐 → 按位或
     *      Pack and merge (modify + write): clear, trim, align, merge
     *   单步数据流：
     *     uTarget AND uMaskInv ──► uBase（旧段清零的载体）
     *     uFieldMask = SHR(uMask, nOffset)（段掩码右对齐）
     *     uField AND uFieldMask ──► uFieldTrim（超宽高位忽略）
     *     uFieldTrim SHL nOffset ──► uFieldAlgn（对齐到目标位段）
     *     uBase OR uFieldAlgn ──► 返回值（合成后的字）
     *-------------------------------------------------------------------------*)
    uBase      := uTarget AND uMaskInv;    // 载体字清旧段（载体 cleared of old field）
    uFieldMask := SHR(uMask, nOffset);     // 段掩码右对齐（mask aligned to field side）
    uFieldTrim := uField AND uFieldMask;   // 字段截断，超宽高位忽略（trim oversized bits）
    uFieldAlgn := SHL(uFieldTrim, nOffset); // 字段对齐到目标位段（align field to target bits）
    FC_DL_WordBitPack := uBase OR uFieldAlgn; // 读-改-写合成出口 / Read-modify-write merge exit
ELSE
    FC_DL_WordBitPack := uTarget;          // 拒绝路径：原字原样返回，禁半写 / Rejection path: return the original word untouched
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜出口一致性（边界 B4）：唯一出口，拒绝与合法路径互不残留
 *      Exit consistency (B4): single exit, no cross-path residue
 *-----------------------------------------------------------------------------*)
(* 拒绝路径时 uExtracted 保持段 1 预置的 0，合法路径为段 3 回读旧值：
   两条路径的 uExtracted 语义均在头注释契约中写死，无隐式行为 *)
END_FUNCTION
