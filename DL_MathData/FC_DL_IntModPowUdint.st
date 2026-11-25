(*==============================================================================
 * 组件名称 : FC_DL_IntModPowUdint ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 模幂运算，返回 nBase^nExp MOD nMod。供校验码、伪随机、整数密钥类运算调用方。
 *            防乘溢出：任何一次乘法都拆成 32 步「加倍-加法」，每步先以「nMod − 加数 是否
 *            够减」判进位再即时归约，故累加积与倍增被乘数恒 < nMod，全程不出现回绕。
 * 契约     : nMod = 0 → 返回 0、bError := TRUE（模数缺失，模幂无定义）；
 *            nMod = 1 → 返回 0、bValid := TRUE（任何数模 1 恒 0，非故障）；
 *            其余 → 返回精确结果、bValid := TRUE、bError 保持 FALSE。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现：快速乘内联），无标准库函数调用
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 除零前置（nMod ≥ 2 后才有 MOD 与除）+ 乘前归约
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突
 * 遗留假设 : 指数位宽固定 UDINT 32 位（内层 FOR 0..31 定长）；两路乘法（nRes × nPow 与
 *            nPow × nPow）合并进同一 32 步循环并行累加，指数位为 0 时积 1 算出后丢弃
 *            （换来「一段代码两用、零重复」，代价是每外层位最多 32 步空转）；
 *            末位之后多做一次倍增无害（nDbl 恒 < nMod），故不设位序守卫。
 * 修订历史 : 2026-11-24 R79-B 首版（整数数论族 9/8 补位）
 *============================================================================*)
FUNCTION FC_DL_IntModPowUdint : UDINT
VAR_INPUT
    nBase : UDINT := 0; // 底数 [无量纲] / the base of the power
    nExp  : UDINT := 0; // 指数 [无量纲] / the exponent
    nMod  : UDINT := 0; // 模数，须 ≥ 2 才有意义 [无量纲] / the modulus, meaningful from two upwards
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError : BOOL;  // 模数为零时为真 / TRUE when the modulus is zero
    bValid : BOOL;  // 返回值可用标志 / TRUE when the return value is usable
END_VAR
VAR CONSTANT
    DL_ZERO : UDINT := 0; // 无符号零哨兵 / unsigned zero sentinel
    DL_ONE  : UDINT := 1; // 无符号一哨兵 / unsigned one sentinel
    DL_TWO  : UDINT := 2; // 无符号二哨兵，右移与奇偶判据 / unsigned two, the halving and parity base
    DL_BIT0 : DINT  := 0;  // 位循环起点 [位] / the bit loop start index
    DL_BITN : DINT  := 31; // 位循环终点，UDINT 位宽减一 [位] / the bit loop end index
END_VAR
VAR
    nRes  : UDINT; // 结果累加量，恒 < nMod [无量纲] / the result accumulator, always below the modulus
    nPow  : UDINT; // 当前幂底，恒 < nMod [无量纲] / the current power base, always below the modulus
    nExpW : UDINT; // 指数工作副本，逐位右移 [无量纲] / the exponent working copy, shifted per bit
    nMr   : UDINT; // 乘法 1 的乘数（结果量）[无量纲] / the multiplier of the first product
    nMq   : UDINT; // 乘法 2 的乘数（幂底自乘）[无量纲] / the multiplier of the squaring product
    nDbl  : UDINT; // 共用的倍增被乘数，恒 < nMod [无量纲] / the shared doubled multiplicand, always below the modulus
    nAdd  : UDINT; // 本步实际加数，位为 0 时取 0 [无量纲] / the addend of this step, zero on a cleared bit
    nAccR : UDINT; // 乘法 1 的积，恒 < nMod [无量纲] / the accumulator of the first product
    nAccQ : UDINT; // 乘法 2 的积，恒 < nMod [无量纲] / the accumulator of the squaring product
    nBit  : DINT;  // 位循环计数 0..31 [位] / the bit loop counter
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_IntModPowUdint := DL_ZERO;  // 缺省零 / default zero
eErr   := 0;                      // 零码位范式 / zero-code rule
bError := FALSE;                  // 预置无故障 / preset no fault
bValid := FALSE;                  // 域闸前不认返回值 / the return value is unusable until the gates pass

// 段 2｜模数域闸：零模数故障、一模数恒零 / segment 2, the modulus gates
IF nMod = DL_ZERO THEN
    bError := TRUE;               // 模数缺失，模幂无定义 / without a modulus the operation is undefined
    RETURN;                       // 返回 0 / return the preset zero
END_IF
IF nMod = DL_ONE THEN
    bValid := TRUE;               // 任何数模 1 恒 0，属合法结果 / any value modulo one is zero, a legal result
    RETURN;                       // 返回 0 / return the preset zero
END_IF

// 段 3｜初值：nRes = 1、nPow = nBase MOD nMod（nMod ≥ 2 已证，MOD 安全）/ segment 3, the initial values
nRes  := DL_ONE;                  // 乘法单位元 / the multiplicative identity
nPow  := nBase MOD nMod;          // 底数先归约 / reduce the base first
nExpW := nExp;                    // 指数工作副本 / the exponent working copy

// 段 4｜二进制模幂：指数位自低向高，每轮并行算 nRes × nPow 与 nPow × nPow / segment 4, the binary modular power
WHILE nExpW > DL_ZERO DO
    nMr   := nRes;                // 乘法 1 的乘数 / the first multiplier
    nMq   := nPow;                // 乘法 2 的乘数 / the squaring multiplier
    nDbl  := nPow;                // 两路共用被乘数 / the shared multiplicand
    nAccR := DL_ZERO;             // 积 1 清零 / clear the first accumulator
    nAccQ := DL_ZERO;             // 积 2 清零 / clear the second accumulator
    FOR nBit := DL_BIT0 TO DL_BITN DO
        nAdd := DL_ZERO;                                                     // 加数缺省 0（位为 0 即空加）/ default addend, an empty add on a cleared bit
        IF (nMr MOD DL_TWO) = DL_ONE THEN nAdd := nDbl; END_IF               // 位为 1 才置加数 / load the addend on a set bit
        IF nAccR >= (nMod - nAdd) THEN nAccR := nAccR - (nMod - nAdd); ELSE nAccR := nAccR + nAdd; END_IF  // 加后即时归约，永不溢出 / add and reduce at once
        nAdd := DL_ZERO;                                                     // 加数复用前清零 / clear the reused addend
        IF (nMq MOD DL_TWO) = DL_ONE THEN nAdd := nDbl; END_IF               // 平方路的同款取数 / the same pick for the squaring
        IF nAccQ >= (nMod - nAdd) THEN nAccQ := nAccQ - (nMod - nAdd); ELSE nAccQ := nAccQ + nAdd; END_IF  // 平方路累加 / accumulate the squaring
        nMr := nMr / DL_TWO;                                                 // 乘数 1 右移一位 / shift the first multiplier
        nMq := nMq / DL_TWO;                                                 // 乘数 2 右移一位 / shift the second multiplier
        IF nDbl >= (nMod - nDbl) THEN nDbl := nDbl - (nMod - nDbl); ELSE nDbl := nDbl + nDbl; END_IF        // 被乘数倍增 mod nMod / double the multiplicand modulo the modulus
    END_FOR
    IF (nExpW MOD DL_TWO) = DL_ONE THEN nRes := nAccR; END_IF                // 指数位为 1 才采信积 1 / adopt the first product only on a set exponent bit
    nPow  := nAccQ;               // 平方结果无条件生效 / the squaring always takes effect
    nExpW := nExpW / DL_TWO;      // 指数右移一位 / shift the exponent
END_WHILE

// 段 5｜出口 / segment 5, the exit
FC_DL_IntModPowUdint := nRes;     // 回写结果 / publish the result
bValid := TRUE;                   // 返回值可用 / the return value is usable
END_FUNCTION
