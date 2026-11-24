(*==============================================================================
 * 组件名称 (Component)  : FC_DL_BcdToWord
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.1
 * 分类     (Category)   : 数制转换纯函数（Function · Converter）
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（SHR / AND / FOR），零厂商方言
 * 功能简介 (Function)   : 16 位 BCD 码字（4 个十进制半字节，每半字节 4 位代表
 *                         一位十进制数 0~9）转 UINT 十进制数值 [0~9999]。
 *                         逐半字节校验：任一半字节 > 9（即 A~F 非法码）立即置
 *                         故障码并返回 0，绝不返回部分累加结果，防静默错值。
 *                         纯函数：无内部状态、无副作用、相同输入必得相同输出，
 *                         可安全用于表达式内联与多任务并发调用（无共享数据）。
 *                         面向 BCD 拨码开关读数、BCD 编码仪表读数、BCD 格式
 *                         寄存器解析等场景的 Level 0 原子构件。
 * 开源溯源 (Origin)     : 原创实现（参考 LGF 库 Converter 转换器分类的功能域
 *                         与参数域，来源标签 lgf-converter），BCD 码权值展开
 *                         为公开经典数制定义，仅借分类/参数域/命名，clean-room
 *                         实现，未复制任何厂商私有库源码，不构成衍生作品。
 * 日期     (Date)       : 2026-11-15 ｜ 作者 (Author): Daoli Library
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: SHR / AND
 *
 *------------------------------------------------------------------------------
 * 【引脚契约 / Pin contract】
 *   输入 uBcd    : WORD   — BCD 码字，位域布局 [千|百|十|个]，每半字节 0~9 合法
 *                          （bit 布局：bit15~12 千位 / bit11~8 百位 /
 *                           bit7~4 十位 / bit3~0 个位）；
 *   输出 uErrorId: UDINT  — 故障码，0 = 无故障；16#0001_0105 = 存在非法半字节；
 *   返回值       : UINT   — 十进制数值 [0~9999]；错误路径固定返回 0。
 *
 * 【边界防错清单 / Boundary guard list】
 *   B1 逐半字节校验 > 9 即置故障返回 0（快速失败，不返回部分结果，防静默错值）；
 *   B2 移位量由半字节序号 × 4 经常量推导并注释，无移位魔法数；
 *   B3 权值由常量基数 10 自乘推导（1→10→100→1000），无位权魔法数；
 *   B4 纯函数出口唯一，无内部状态、无副作用，同输入同输出；
 *   B5 全程 WORD/USINT/UINT 显式类型转换，无隐式窄化风险。
 *
 * 【调用示例 / Call example】
 *   uDipValue := FC_DL_BcdToWord(uBcd := wDipSwitchWord, uErrorId => uDipErr);
 *   IF uDipErr <> 0 THEN 「BCD 拨码异常，走旁路默认批号」 END_IF
 *
 * 【平台移植注意 / Porting notes】
 *   SHR 的移位计数参数在 IEC 61131-3 中为 ANY_INT，各平台均支持 USINT 实参；
 *   WORD_TO_USINT 为标准显式类型转换，零方言。
 *
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓ ｜ R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 标准运算 ✓ ｜ R4 非法半字节全检测/
 *                           出口唯一/无除法无数组无循环死锁风险 ✓
 *                         R5 全变量中英双语同行注释 ✓ ｜ R6 N/A（纯函数无状态机）
 *                         R7 N/A（无定时器/边沿实例）｜ R8 移位量/权值/阈值全常量化 ✓
 * 验收向量 (Acceptance) :
 *   V1  uBcd = 16#0123 → 返回 123，  uErrorId = 0
 *   V2  uBcd = 16#9999 → 返回 9999， uErrorId = 0
 *   V3  uBcd = 16#0000 → 返回 0，    uErrorId = 0
 *   V4  uBcd = 16#001A → 返回 0，    uErrorId = 16#0001_0105（非法半字节 A）
 *   V5  uBcd = 16#0999 → 返回 999，  uErrorId = 0
 *
 * 【故障码表 / Error code table】
 *   16#0001_0105  非法 BCD 半字节（半字节值 10~15），本拍返回 0，瞬时码每次
 *                 调用重算；码段 16#0001_xxxx 经 DL_Base/DL_MathData 码表核对
 *                 未占用（0105 空闲，0101~0104 已被计数/步进族登记）。
 *
 * 【实现选择 / Implementation choice】
 *   权值累加法而非除余法：BCD 半字节天然是位权展开（个/十/百/千），逐半字节
 *   提取后乘权累加，权值由常量基数 10 自乘推导，无移位魔法数（移位量 = 半字节
 *   序号 × 4，由 DL_BCD_NIB_SHIFT 常量给出并注释）。非法半字节检测前置在累加
 *   之前，命中即 RETURN，保证错误路径零部分结果。
 *
 * 【工程背景与应用场景 / Background and use cases】
 *   ① 电柜门上的 BCD 拨码开关（4 位十进制地址/批号设定）经输入映像字读入
 *      后转十进制参与批号管理；
 *   ② 老式 BCD 输出仪表（计数器/长度计/温控表）的并行 BCD 总线读数解析；
 *   ③ 与上位系统约定 BCD 格式的寄存器（如某些仪表协议保持字）入库前转十进制；
 *   ④ 作为 FC_DL_WordToBcd 的对称逆变换，构成 BCD 编解码原子对。
 *
 * 【位域布局图 / Bit-field layout】
 *      bit15..bit12   bit11..bit8    bit7..bit4     bit3..bit0
 *     +------------+ +-----------+ +-----------+ +-----------+
 *     | 千位 0~9   | | 百位 0~9  | | 十位 0~9  | | 个位 0~9  |
 *     +------------+ +-----------+ +-----------+ +-----------+
 *      nNib = 3       nNib = 2      nNib = 1       nNib = 0
 *      权值 1000      权值 100      权值 10        权值 1
 *
 * 【同族职责分离 / Family separation】
 *   本函数只做 BCD 码字 → 十进制单向转换；逆向转换由同轮 FC_DL_WordToBcd
 *   承担（含超 9999 溢出饱和），两者配对使用但互不调用，保持 Level 0 零内耦；
 *   字节序问题与本函数无关（半字节序恒为高位在左），字节排列转换请先过
 *   FC_DL_SwapBytes16 族再进本函数。
 *
 * 【异常与诊断行为 / Exception and diagnostic behavior】
 *   ① 检测到非法半字节：返回 0 + 故障码 16#0001_0105，同拍生效，无锁存
 *      （纯函数无状态，每次调用独立判定，诊断链由调用方维护）；
 *   ② 返回 0 与值 0 的区分：必须结合 uErrorId 判断——uErrorId = 0 且返回 0
 *      为合法的"BCD 值就是 0"；uErrorId 非 0 且返回 0 为拒绝路径，两者语义
 *      不同，调用方禁止只看返回值；
 *   ③ 本函数不修改任何输入、不触碰任何外部存储，异常不影响后续调用。
 *
 * 【误用警示 / Misuse warnings】
 *   ✗ 把二进制值直接当 BCD 传入（如 16#0064 实际十进制 100 被读成 BCD 64）；
 *   ✗ 忽略 uErrorId 只取返回值参与控制运算；
 *   ✗ 在同一表达式中混用本函数与 FC_DL_WordToBcd 期望幂等抵消（两者均正确
 *     但各自带错误路径，抵消链会吞掉中间诊断）。
 *
 * 【逐位验算表 / Bit-level walkthrough（供终审逐组代回验算）】
 *   V1 16#0123 = 0000_0001_0010_0011：
 *       个位半字节 = 0011 = 3；十位 = 0010 = 2；百位 = 0001 = 1；千位 = 0000 = 0
 *       → 3×1 + 2×10 + 1×100 + 0×1000 = 123 ✓
 *   V2 16#9999：四个半字节均为 1001 = 9，全合法
 *       → 9×1 + 9×10 + 9×100 + 9×1000 = 9999 ✓
 *   V3 16#0000：四个半字节均为 0，全合法 → 0 ✓
 *   V4 16#001A：十位半字节 = 1010 = 16#A = 10 > 9（合法上限 9）
 *       → 命中边界 B1，置 0001_0105，返回 0 ✓
 *   V5 16#0999 = 0000_1001_1001_1001：
 *       个位 = 9；十位 = 9；百位 = 9；千位 = 0 → 9 + 90 + 900 + 0 = 999 ✓
 *
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（Round 09 · 泳道 A · LGF Converter 组）
 *   2026-11-15  v1.0.1  终审修复：位权累加的类型转换由 `UINT(uDigit)` 强制转换
 *                       写法改为标准函数 `USINT_TO_UINT(uDigit)`（全库此前零
 *                       强制转换写法，公约三要求显式 *_TO_* 转换以保证
 *                       InoProShop / TwinCAT 三平台一致）；数值结果不变
 *============================================================================*)
FUNCTION FC_DL_BcdToWord : UINT            // 返回十进制数值 [0~9999] / Returns decimal value [0~9999]
VAR_INPUT
    uBcd    : WORD;                        // BCD 码字，每个 4 位半字节代表一位十进制数 0~9 / BCD-coded word, each 4-bit nibble is one decimal digit 0~9
END_VAR
VAR_OUTPUT
    uErrorId: UDINT;                       // 故障码，0 = 无故障，16#0001_0105 = 非法半字节 / Error code, 0 = none, 0001_0105 = invalid nibble
END_VAR
VAR
    nNib    : USINT;                       // 半字节序号 [0~3]，0 = 个位半字节 / Nibble index [0~3], 0 = units nibble
    uDigit  : USINT;                       // 当前半字节十进制值 [0~15]，> 9 即非法 / Current nibble value [0~15], above 9 is invalid
    uResult : UINT;                        // 累加结果工作副本 [0~9999] / Accumulated result working copy [0~9999]
    uWeight : UINT;                        // 当前半字节十进制权值 [1/10/100/1000] / Decimal weight of current nibble [1/10/100/1000]
    uShift  : USINT;                       // 当前半字节右移量 [bit]，= 序号 × 4 / Right-shift amount [bit] of current nibble, index times 4
END_VAR
VAR CONSTANT
    DL_BCD_NIBS     : USINT := 4;          // WORD 含半字节数 [个] / Number of nibbles in a WORD
    DL_BCD_RADIX    : UINT  := 10;         // 十进制权基数，权值按此自乘推导 / Decimal radix base, weights derived by squaring this
    DL_BCD_NIB_SHIFT: USINT := 4;          // 相邻半字节间隔 [bit]，4 位一位 / Bit gap between adjacent nibbles [bit], 4 bits per digit
    DL_BCD_NIB_MASK : WORD  := 16#000F;    // 半字节提取掩码（低 4 位）/ Nibble extraction mask (low 4 bits)
    DL_BCD_DIG_MAX  : USINT := 9;          // 合法半字节上限 [9]，10~15 为非法码 / Legal nibble upper bound [9], 10~15 are illegal codes
    DL_BCD_ERR_NIB  : UDINT := 16#0001_0105; // 非法半字节故障码 / Error code for invalid nibble
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜安全预置（P-01 范式）：错误路径一律返回 0，绝不返回部分累加值
 *      Safe preset: error paths always return 0, never a partial accumulation
 *      纯函数无内部状态，本段每拍重算，不依赖上一次调用的任何残留值
 *      Pure function holds no internal state; this stage recomputes each call
 *-----------------------------------------------------------------------------*)
uErrorId := 16#0000_0000;                  // 故障码预清零，正常路径末尾保持 0 / Error code preset to zero, stays 0 on the normal path
uResult  := 0;                             // 累加结果清零（Accumulator cleared）
uWeight  := 1;                             // 权值从个位 1 起步（Weight starts at units place 1）

(*------------------------------------------------------------------------------
 * 段 2｜逐半字节提取与校验（边界 B1/B2/B3）
 *      Per-nibble extraction and validation (guards B1/B2/B3)
 *      移位量推导注释：第 nNib 个半字节位于位 [nNib×4, nNib×4+3]，
 *      故右移 uShift = nNib × DL_BCD_NIB_SHIFT 后取低 4 位即该位十进制值
 *      Shift derivation: nibble nNib occupies bits [nNib*4 .. nNib*4+3];
 *      right-shift by uShift = nNib * DL_BCD_NIB_SHIFT, then mask low 4 bits
 *      循环界 0..3 为常量上界，天然无死循环风险，无需额外防死锁计数器
 *      Loop bound 0..3 is a constant upper bound, deadlock-free by construction
 *-----------------------------------------------------------------------------*)
FOR nNib := 0 TO (DL_BCD_NIBS - 1) DO
    uShift := nNib * DL_BCD_NIB_SHIFT;     // 右移量 = 半字节序号 × 4 [bit] / Shift amount = nibble index times 4 [bit]
    uDigit := WORD_TO_USINT(SHR(uBcd, uShift) AND DL_BCD_NIB_MASK); // 提取当前半字节 [0~15] / Extract current nibble [0~15]

    (*--------------------------------------------------------------------------
     * 单步数据流（每半字节一次，四步流水）：
     *   uBcd ──SHR(uShift)──► 右对齐 ──AND 16#000F──► uDigit[0~15]
     *        ──判 > 9──► 非法：置码返回 0 ／ 合法：×uWeight 累加入 uResult
     *   Single-step data flow (once per nibble, four-stage pipeline):
     *   uBcd --SHR(uShift)--> aligned --AND 16#000F--> uDigit[0~15]
     *        --check above 9--> illegal: raise code, return 0
     *                          legal  : multiply by uWeight, accumulate
     *-------------------------------------------------------------------------*)

    (*--------------------------------------------------------------------------
     * 边界 B1：非法半字节快速失败——检测前置在累加之前，命中即退，
     *          保证错误路径零部分结果（上层拿到 0 必伴随非零故障码）
     *          Guard B1: fail fast before accumulation; error path yields
     *          zero partial result (return 0 always paired with nonzero code)
     *-------------------------------------------------------------------------*)
    IF uDigit > DL_BCD_DIG_MAX THEN        // 半字节值 10~15 为非法 BCD 码 / Nibble value 10~15 is an illegal BCD code
        uErrorId := DL_BCD_ERR_NIB;        // 置非法半字节故障码 / Raise invalid-nibble error code
        FC_DL_BcdToWord := 0;              // 拒绝路径返回 0，防静默错值 / Rejection path returns 0, no silent wrong value
        RETURN;                            // 快速失败出口，不再累加（Fast-fail exit, no further accumulation）
    END_IF

    uResult := uResult + USINT_TO_UINT(uDigit) * uWeight; // 位权累加：数值 × 当位权值（显式标准转换函数）/ Weighted accumulation with the standard explicit conversion
    uWeight := uWeight * DL_BCD_RADIX;     // 权值升位：1 → 10 → 100 → 1000 / Weight steps up: 1 -> 10 -> 100 -> 1000
END_FOR

(*------------------------------------------------------------------------------
 * 段 3｜结果回写（边界 B4）：纯函数出口唯一，无副作用
 *      Result write-back: single exit of the pure function, no side effect
 *      验收向量：16#0123 → 123；16#9999 → 9999；16#001A → 0 且置 0001_0105
 *      Acceptance vectors: 16#0123 -> 123; 16#9999 -> 9999; 16#001A -> 0 with 0001_0105
 *      上界自证：4 个半字节全 9 时 uResult = 9999 < 65535（UINT 域），无溢出
 *      Upper-bound proof: all-9 nibbles give 9999 < 65535 (UINT domain), no overflow
 *-----------------------------------------------------------------------------*)
FC_DL_BcdToWord := uResult;                // 全部半字节合法，返回累加结果 / All nibbles legal, return accumulated result
END_FUNCTION
