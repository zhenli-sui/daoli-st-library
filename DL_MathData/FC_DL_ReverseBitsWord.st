(*==============================================================================
 * 组件名称 (Component)  : FC_DL_ReverseBitsWord
 * 所属子库 (Sublibrary) : DL_MathData
 * 归属目录 (Directory)  : C:\Library\DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 分类/来源标签         : 函数（FUNCTION）· 纯函数 · WORD 位反转与字节交换
 *                         iec-std-wrapper / bitstring
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 IEC 标准位运算 AND/OR/SHL/SHR
 * 溯源声明 (Provenance) : IEC 61131-3 标准语义的道莅防御性实现——内部委托平台标准库语义，
 *                         外围统一错误码 / 钳位 / 双语注释，严禁重实现数学内核。
 * 功能一句话 (Summary)  : WORD 全 16 位镜像反转（分治交换法）或字节序交换双模式，
 *                         服务 LSB-first CRC、LED 点阵与大小端报文适配。
 *
 * 功能描述 (Function)   : 位反转模式用四步分治交换（1 位组、2 位组、4 位组、
 *                         8 位组两两对换）实现全位镜像，无循环、无查表、常数时间；
 *                         字节交换模式一次完成高低字节对换；模式域外走 ELSE 兜底
 *                         回退位反转并报故障码，回文输入以信息级告知恒等结果。
 * 与既有件边界 (Boundary): 与 ShlEx/ShrEx 族正交——那些件做移位，本件做镜像；
 *                         平台内建 SWAP 指令非 IEC 标准，故字节交换同样手写实现。
 * 码位说明 (Codes)      : 信息 16#0002_3044 反转完成且结果回文（wOut 等于 wIn）
 *                         故障 16#0002_3045 模式域外，已回退位反转并照常输出
 *                         段 16#02_3_44~47，本件实占 44~45 两码。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；零库函数依赖，纯 IEC 位运算符。
 * 红线自检 (Redline)    : 零全局依赖 ｜ 零 VAR_EXTERNAL ｜ 零 %I/%Q ｜ 纯 IEC 位运算
 *                         移位量 1/2/4/8 恒小于 16 位宽（归一达标）｜ 无除法面
 *                         ENUM 配 CASE 且 ELSE 兜底 ｜ 全变量双语同行注释
 * 修订历史 (Revision)   : 2026-11-18  v1.0.0  首版入库（R32 · 批 1）
 *============================================================================*)

FUNCTION FC_DL_ReverseBitsWord : BOOL
VAR_INPUT
    wIn   : WORD;                       // 源字 [位串] / Source word
    eMode : (eRevBits := 0, eRevBytes := 1);    // 模式枚举：全位反转或字节交换 / Mode enum: full bit reverse or byte swap
END_VAR
VAR_OUTPUT
    wOut    : WORD;                     // 反转结果 [位串] / Reversed result
    bPalin  : BOOL;                     // 回文标志，wOut 等于 wIn 时为真 / TRUE when the result equals the input
    uErrorId: UDINT;                    // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    w1 : WORD;    // 第一步交换结果（1 位组）[位串] / Stage one result, one-bit groups
    w2 : WORD;    // 第二步交换结果（2 位组）[位串] / Stage two result, two-bit groups
    w3 : WORD;    // 第三步交换结果（4 位组）[位串] / Stage three result, four-bit groups
    w4 : WORD;    // 第四步交换结果（8 位组，即全镜像）[位串] / Stage four result, full mirror
    uCode : UDINT; // 码位暂存，出口单点写入 [码] / Code staging
END_VAR

(* 段 1｜输出预置 / Pre-set *)
FC_DL_ReverseBitsWord := FALSE;
wOut    := 16#0000;
bPalin  := FALSE;
uErrorId := 16#0000_0000;
uCode   := 16#0000_0000;

(* 段 2｜模式分派（ENUM 配 CASE，ELSE 兜底拦截域外值）/ Mode dispatch with ELSE interception *)
CASE eMode OF

    eRevBits:
        (* 四步分治交换：相邻 1 位、2 位、4 位对换，最后高低 8 位整体对换
         * Four divide-and-conquer stages, constant time, no loop and no table *)
        w1 := ((wIn  AND 16#5555) SHL 1)  OR ((wIn  AND 16#AAAA) SHR 1);  // 相邻 1 位对换 / Adjacent one-bit swap
        w2 := ((w1   AND 16#3333) SHL 2)  OR ((w1   AND 16#CCCC) SHR 2);  // 相邻 2 位对换 / Adjacent two-bit swap
        w3 := ((w2   AND 16#0F0F) SHL 4)  OR ((w2   AND 16#F0F0) SHR 4);  // 相邻 4 位对换 / Adjacent four-bit swap
        w4 := ((w3   AND 16#00FF) SHL 8)  OR ((w3   AND 16#FF00) SHR 8);  // 高低 8 位对换，完成全镜像 / Final mirror
        wOut := w4;

    eRevBytes:
        (* 字节交换：低 8 位左移到高位，高 8 位右移到低位 / Swap the two bytes *)
        wOut := ((wIn AND 16#00FF) SHL 8) OR ((wIn AND 16#FF00) SHR 8);

ELSE
    (* 域外兜底：枚举被非法赋值（如强转越界）时回退位反转，绝不输出未定义值
     * Out-of-domain fallback: revert to bit reverse, never output an undefined value *)
    w1 := ((wIn  AND 16#5555) SHL 1)  OR ((wIn  AND 16#AAAA) SHR 1);
    w2 := ((w1   AND 16#3333) SHL 2)  OR ((w1   AND 16#CCCC) SHR 2);
    w3 := ((w2   AND 16#0F0F) SHL 4)  OR ((w2   AND 16#F0F0) SHR 4);
    w4 := ((w3   AND 16#00FF) SHL 8)  OR ((w3   AND 16#FF00) SHR 8);
    wOut := w4;
    uCode := 16#0002_3045;           // 故障级：模式域外已回退 / Fault: mode out of domain, reverted

END_CASE

(* 段 3｜回文告知与出口 / Palindrome notice and exit *)
IF wOut = wIn THEN
    bPalin := TRUE;                  // 恒等结果（回文字）告知 / Inform the identity result
    IF uCode = 16#0000_0000 THEN
        uCode := 16#0002_3044;       // 信息级：结果回文 / Info: palindromic result
    END_IF
END_IF
uErrorId := uCode;                   // 码位单点写入 / Single write point for the code
FC_DL_ReverseBitsWord := TRUE;
END_FUNCTION
