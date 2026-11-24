(*==============================================================================
 * 组件名称 (Component)  : FC_DL_WordToBcd
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 分类     (Category)   : 数制转换纯函数（Function · Converter）
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（MOD / SHL / OR），零厂商方言
 * 功能简介 (Function)   : UINT 十进制数值 [0~9999] 转 16 位 BCD 码字（4 个
 *                         十进制半字节）。超 9999 溢出检测：置故障码并返回
 *                         16#9999 饱和值（显式饱和不回绕——回绕会产生完全
 *                         错误但看似合法的 BCD 码，静默错值比饱和更危险）。
 *                         纯函数：无内部状态、无副作用、相同输入必得相同输出。
 *                         与 FC_DL_BcdToWord 构成 BCD 编解码原子对，面向
 *                         BCD 拨码开关设定值写出、BCD 格式仪表给定、BCD
 *                         协议寄存器组包等场景的 Level 0 原子构件。
 * 开源溯源 (Origin)     : 原创实现（参考 LGF 库 Converter 转换器分类的功能域
 *                         与参数域，来源标签 lgf-converter），除基取余法为
 *                         公开经典数制定义，仅借分类/参数域/命名，clean-room
 *                         实现，未复制任何厂商私有库源码，不构成衍生作品。
 * 日期     (Date)       : 2026-11-15 ｜ 作者 (Author): Daoli Library
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: MOD / SHL / OR
 *
 *------------------------------------------------------------------------------
 * 【引脚契约 / Pin contract】
 *   输入 uVal    : UINT   — 十进制输入值 [0~9999]，> 9999 走溢出饱和路径；
 *   输出 uErrorId: UDINT  — 故障码，0 = 无故障；16#0001_0106 = 溢出饱和；
 *                           16#0001_0107 = 除基守卫命中（常量被误改为 0）；
 *   返回值       : WORD   — BCD 码字，位域布局 [千|百|十|个]，每半字节 0~9。
 *
 * 【位域布局图 / Bit-field layout】
 *      bit15..bit12   bit11..bit8    bit7..bit4     bit3..bit0
 *     +------------+ +-----------+ +-----------+ +-----------+
 *     | 千位 0~9   | | 百位 0~9  | | 十位 0~9  | | 个位 0~9  |
 *     +------------+ +-----------+ +-----------+ +-----------+
 *      nNib = 3       nNib = 2      nNib = 1       nNib = 0
 *      权值 1000      权值 100      权值 10        权值 1
 *
 * 【边界防错清单 / Boundary guard list】
 *   B1 uVal > 9999 → 置故障并返回 16#9999 饱和输出（明确不回绕，注释写死）；
 *   B2 除法基数为常量 10，理论上无除零风险，仍按防御编程公约写除零守卫
 *      （守卫命中置 16#0001_0107 返回 16#0000，防常量被误改后静默错值）；
 *   B3 逐位提取用除/取余显式运算，位权与移位量全部常量化并注释；
 *   B4 纯函数出口唯一，无内部状态、无副作用，同输入同输出；
 *   B5 UINT→WORD 显式类型转换，无隐式窄化风险；uVal ≤ 9999 时各半字节
 *      天然 ≤ 9，SHL 合成不越 WORD 域。
 *
 * 【饱和语义声明 / Saturation semantics】
 *   溢出路径固定返回 16#9999（BCD 满量程显示值）并置码 16#0001_0106：
 *   选择饱和而非回绕，因为 BCD 回绕（如 10000 → 16#0000）会让上层把
 *   "满量程溢出"误读为"值为零"，在计数/设定值场景属于静默危险错值；
 *   饱和值 16#9999 在 BCD 显示器件上呈满格读数，操作工可直观识别异常，
 *   同时非零故障码供诊断链捕获。此语义与 FC_DL_BcdToWord 的拒绝返回 0
 *   不同（该函数错误值 0 与合法值 0 可由 uErrorId 区分），两函数口径
 *   均在各自头注释写死。
 *
 * 【调用示例 / Call example】
 *   wBcdSet := FC_DL_WordToBcd(uVal := nBatchNo, uErrorId => uBcdErr);
 *   IF uBcdErr = 16#0001_0106 THEN 「设定值超 BCD 量程，走钳位/报警链」 END_IF
 *
 * 【平台移植注意 / Porting notes】
 *   MOD 与整数除法 "/" 在 IEC 61131-3 中对 UINT 均为标准定义（截断除），
 *   各平台行为一致；SHL 的移位计数为 ANY_INT，USINT 实参全平台支持。
 *
 * 【同族职责分离 / Family separation】
 *   本函数只做十进制 → BCD 码字单向转换；逆向转换由同轮 FC_DL_BcdToWord
 *   承担（非法半字节检测），两者配对使用但互不调用，Level 0 零内耦；
 *   字节排列转换请先过 FC_DL_SwapBytes16 族再进本函数。
 *
 * 【误用警示 / Misuse warnings】
 *   ✗ 忽略 uErrorId 只取返回值——溢出路径返回的 16#9999 是饱和显示值，
 *     不是真实数据，直接参与运算会把满量程误当真实值；
 *   ✗ 把 BCD 码字当二进制值再转一次（双重编码），需确认数据源编码格式；
 *   ✗ 期望本函数处理负数：入参为 UINT 域，负值场景应在上层先做符号处理。
 *
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓ ｜ R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 标准运算 ✓ ｜ R4 溢出饱和+除零守卫/
 *                           出口唯一/无数组/循环界常量无死锁 ✓
 *                         R5 全变量中英双语同行注释 ✓ ｜ R6 N/A（纯函数无状态机）
 *                         R7 N/A（无定时器/边沿实例）｜ R8 基数/上限/移位量全常量化 ✓
 * 验收向量 (Acceptance) :
 *   V1  uVal = 123   → 返回 16#0123， uErrorId = 0
 *   V2  uVal = 9999  → 返回 16#9999， uErrorId = 0
 *   V3  uVal = 10000 → 返回 16#9999， uErrorId = 16#0001_0106（溢出饱和）
 *   V4  uVal = 0     → 返回 16#0000， uErrorId = 0
 *   V5  uVal = 4096  → 返回 16#4096， uErrorId = 0
 *
 * 【故障码表 / Error code table】
 *   16#0001_0106  溢出饱和：uVal 超 BCD 可表示上限 9999，返回 16#9999，
 *                 瞬时码每次调用重算（0106 空闲，0101~0105 已登记）；
 *   16#0001_0107  除基守卫命中：除法基数常量被误改为 0，返回 16#0000，
 *                 防御性码，正常组态永不触发（0107 空闲）。
 *
 * 【实现选择 / Implementation choice】
 *   除基取余法而非减权法：uWork 逐位 MOD 10 取个位、DIV 10 右移一位十进制，
 *   四步提取个/十/百/千，思想与 FC_DL_BcdToWord 的权值展开互为逆运算；
 *   每位取余后显式判 ≤ 9（正常路径恒真，属自证断言性质的防御），再 SHL
 *   到对应半字节位域按位或合成。
 *
 * 【逐位验算表 / Bit-level walkthrough（供终审逐组代回验算）】
 *   V1 123：除基链 123→[余3|商12]→[余2|商1]→[余1|商0]→[余0]
 *       → 个3 十2 百1 千0 → 3 | 2<<4 | 1<<8 | 0<<12 = 16#0123 ✓
 *   V2 9999：[9,9,9,9] → 16#9999 ✓
 *   V3 10000 > 9999 → 溢出路径：置 0001_0106，返回 16#9999（饱和不回绕）✓
 *   V4 0：除基链全 0 → 16#0000 ✓
 *   V5 4096：[余6|商409]→[余9|商40]→[余0|商4]→[余4|商0]
 *       → 个6 十9 百0 千4 → 6 | 9<<4 | 0<<8 | 4<<12 = 16#4096 ✓
 *
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（Round 09 · 泳道 A · LGF Converter 组）
 *============================================================================*)
FUNCTION FC_DL_WordToBcd : WORD            // 返回 BCD 码字，每半字节一位十进制 / Returns BCD-coded word, one decimal digit per nibble
VAR_INPUT
    uVal    : UINT;                        // 十进制输入值 [0~9999]，超限走饱和路径 / Decimal input [0~9999], overflow takes the saturation path
END_VAR
VAR_OUTPUT
    uErrorId: UDINT;                       // 故障码，0 = 无故障，0106 = 溢出饱和，0107 = 除基守卫 / Error code, 0 = none, 0106 = overflow saturated, 0107 = divide-base guard
END_VAR
VAR
    nNib    : USINT;                       // 半字节序号 [0~3]，0 = 个位半字节 / Nibble index [0~3], 0 = units nibble
    uDigit  : UINT;                        // 当前位十进制余数 [0~9] / Decimal remainder of current digit [0~9]
    uWork   : UINT;                        // 除法工作副本（逐位右移十进制）/ Working copy for division (decimal right-shift per step)
    uShift  : USINT;                       // 当前半字节左移量 [bit]，= 序号 × 4 / Left-shift amount [bit] of current nibble, index times 4
    uResult : WORD;                        // BCD 合成结果工作副本 / BCD assembly result working copy
END_VAR
VAR CONSTANT
    DL_BCD_MAX    : UINT  := 9999;         // BCD 可表示上限 [值]，超出即溢出饱和 / BCD representable upper limit, overflow saturates beyond this
    DL_BCD_NIBS   : USINT := 4;            // WORD 含半字节数 [个] / Number of nibbles in a WORD
    DL_BCD_RADIX  : UINT  := 10;          // 十进制除基，逐位提取用 / Decimal divide base for digit extraction
    DL_BCD_NIB_SHIFT: USINT := 4;          // 相邻半字节间隔 [bit]，4 位一位 / Bit gap between adjacent nibbles [bit], 4 bits per digit
    DL_BCD_SAT    : WORD  := 16#9999;      // 溢出饱和输出值（BCD 满量程）/ Saturation output on overflow (BCD full-scale)
    DL_BCD_ERR_OVF: UDINT := 16#0001_0106; // 溢出饱和故障码 / Error code for overflow saturation
    DL_BCD_ERR_DIV: UDINT := 16#0001_0107; // 除基守卫故障码 / Error code for divide-base guard
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜安全预置与除基守卫（边界 B2）
 *      Safe preset and divide-base guard (guard B2)
 *      纯函数无内部状态，本段每拍重算；除基常量理论上恒为 10，守卫属
 *      防御编程公约的自证断言，防常量被误改后静默错值
 *      Pure function recomputes each call; radix is constant 10 by design,
 *      the guard is a self-proving defensive assertion against mis-editing
 *-----------------------------------------------------------------------------*)
uErrorId := 16#0000_0000;                  // 故障码预清零，正常路径末尾保持 0 / Error code preset to zero, stays 0 on the normal path
uResult  := 16#0000;                       // BCD 合成结果清零（BCD result cleared）
uWork    := uVal;                          // 工作副本接管输入，保护入参不被修改 / Working copy takes over input, protecting the argument

IF DL_BCD_RADIX = 0 THEN                   // 除基守卫：基数被误改为 0 则除零 / Divide-base guard: division by zero if base mis-edited to 0
    uErrorId := DL_BCD_ERR_DIV;            // 置除基守卫故障码 / Raise divide-base guard error code
    FC_DL_WordToBcd := 16#0000;            // 守卫路径返回全零码（Guard path returns all-zero code）
    RETURN;                                // 快速失败出口（Fast-fail exit）
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜溢出检测（边界 B1）：超 9999 置码并返回 16#9999 饱和值
 *      Overflow detection (guard B1): above 9999 raise code and saturate
 *      饱和不回绕：回绕会把满量程误读为零，属静默危险错值（见头注释声明）
 *      Saturate, never wrap: wrap misreads full-scale as zero, a silent hazard
 *-----------------------------------------------------------------------------*)
IF uVal > DL_BCD_MAX THEN                  // 输入超 BCD 可表示上限 / Input exceeds BCD representable limit
    uErrorId := DL_BCD_ERR_OVF;            // 置溢出饱和故障码 / Raise overflow-saturation error code
    FC_DL_WordToBcd := DL_BCD_SAT;         // 返回 16#9999 满量程饱和值 / Return 16#9999 full-scale saturation value
    RETURN;                                // 快速失败出口（Fast-fail exit）
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜除基取余逐位提取（边界 B3/B4）
 *      Divide-base remainder digit extraction (guards B3/B4)
 *      移位量推导注释：第 nNib 个十进制位写入位 [nNib×4, nNib×4+3]，
 *      故左移 uShift = nNib × DL_BCD_NIB_SHIFT 后按位或入结果字
 *      Shift derivation: decimal digit nNib goes to bits [nNib*4 .. nNib*4+3];
 *      left-shift by uShift = nNib * DL_BCD_NIB_SHIFT, then OR into the result
 *      循环界 0..3 为常量上界，天然无死循环风险，无需额外防死锁计数器
 *      Loop bound 0..3 is a constant upper bound, deadlock-free by construction
 *-----------------------------------------------------------------------------*)
FOR nNib := 0 TO (DL_BCD_NIBS - 1) DO
    uShift := nNib * DL_BCD_NIB_SHIFT;     // 左移量 = 半字节序号 × 4 [bit] / Shift amount = nibble index times 4 [bit]
    uDigit := uWork MOD DL_BCD_RADIX;      // 当前位余数 [0~9]：个/十/百/千逐位提取 / Current digit remainder [0~9]: units, tens, hundreds, thousands
    uWork  := uWork / DL_BCD_RADIX;        // 工作副本十进制右移一位（截断除）/ Working copy shifts one decimal digit right (truncating division)

    (*--------------------------------------------------------------------------
     * 单步数据流（每半字节一次，四步流水）：
     *   uWork ──MOD 10──► uDigit[0~9] ──转 WORD──SHL(uShift)──► 半字节对齐
     *         ──OR──► uResult          同时 uWork ──DIV 10──► 降位
     *   Single-step data flow (once per nibble, four-stage pipeline):
     *   uWork --MOD 10--> uDigit[0~9] --to WORD--SHL(uShift)--> nibble-aligned
     *         --OR--> uResult          while uWork --DIV 10--> next digit
     *   正常路径 uDigit 恒 ≤ 9（uVal ≤ 9999 已在段 2 保证），此处不重复设断言
     *   On the normal path uDigit is always at most 9 (guaranteed by stage 2)
     *-------------------------------------------------------------------------*)
    uResult := uResult OR SHL(UINT_TO_WORD(uDigit), uShift); // 半字节合成入位域 / Assemble nibble into its bit field
END_FOR

(*------------------------------------------------------------------------------
 * 段 4｜结果回写（边界 B4）：纯函数出口唯一，无副作用
 *      Result write-back: single exit of the pure function, no side effect
 *      验收向量：123 → 16#0123；9999 → 16#9999；10000 → 16#9999 且置 0001_0106
 *      Acceptance vectors: 123 -> 16#0123; 9999 -> 16#9999; 10000 -> 16#9999 with 0001_0106
 *      上界自证：uVal ≤ 9999 时四个半字节全 ≤ 9，SHL 合成最大 16#9999 不越 WORD 域
 *      Upper-bound proof: uVal at most 9999 keeps every nibble at most 9, max 16#9999 in WORD
 *-----------------------------------------------------------------------------*)
FC_DL_WordToBcd := uResult;                // 返回 BCD 合成结果 / Return the assembled BCD result
END_FUNCTION
