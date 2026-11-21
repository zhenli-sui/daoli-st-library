(*
  ==================================================================
  组件名 Component  : FC_DL_SaturateMul
  分类   Category   : DL_Base
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0001_0644（信息级）｜ 16#0001_0645（故障级）｜ 16#0001_0646（故障级）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 中
  功能   Purpose    : LINT 宽域饱和乘法：nOut = clamp(nA × nB, nLo, nHi)，溢出前判定，
                      bOvF（溢出）与 bClamped（钳位已生效）两标志语义可分。
  开源溯源 Origin    : IEC 61131-3 标准语义的道莅防御性实现（clean-room，无第三方代码行）
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6.2 算术运算符（整数乘法）与 §6.6.5 类型转换语义
  平台   Platform   : 纯 IEC 61131-3（仅四则与比较），CODESYS / TwinCAT 3 / InoProShop 通用
  依赖   Depends    : 仅 Standard.library（无库调用）
  分工声明 Split     : 与 FC_DL_SaturateAdd（加）/ FC_DL_SaturateSub（减）构成「加/减/乘」
                      三件族，除法则由 FC_DL_SaturateDiv 承载；FC_DL_SaturateAdd 未覆盖
                      乘法（其模式枚举只有加与减），故本件不可省（R216 双向互引）。
  归属 Ownership     : 本件无 TYPE 声明，全部引脚为 IEC 标准原生类型。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 溢出前判定（禁先乘后判）：按四个象限分别与「域上界 ÷ 另一因子」
                         比较，比较式内只出现除法，不出现裸乘法，浮点无关、全整数精确；
                      二 MIN × -1 单独直判：MIN 的绝对值不可表示，先乘必回绕成 MIN 而
                         令「结果 < 0」误判为负溢出，故本组合在乘法之前直接判正溢出；
                      三 零因子优先：nA = 0 或 nB = 0 时积恒为 0，不做任何除法预判
                         （同时消灭预判式里的除零路径）；
                      四 nLo > nHi 判组态故障并返回 FALSE（与 FC_DL_SaturateDiv、
                         FC_DL_RealToIntSat 同口径，三件一致，禁静默交换）；
                      五 溢出与域钳两标志可分：溢出 → bOvF = TRUE 且 nOut 直达 nHi/nLo；
                         未溢出仅域钳 → bClamped = TRUE 且 bOvF = FALSE；
                      六 纯函数：无记忆量、无定时器、无边沿实例，每调用重算。
  错误码 Codes      :
    16#0001_0644【信息级】结果被域 [nLo, nHi] 钳位（未溢出，bClamped = TRUE，bValid = TRUE）
    16#0001_0645【故障级】乘法溢出（bOvF = TRUE，nOut 已按积符号钳到 nHi 或 nLo）
    16#0001_0646【故障级】组态非法 nLo > nHi（判故障返回 FALSE，nOut = 0）
  码位反证 Note     :
    0644 与 0645 不可合并：溢出与域钳在「结果数值」上不可观测区分（两者都输出边界值），
    仅靠返回值加 bValid 也无法分解（两者 bValid 不同，但 bOvF 语义才是上游限幅判据），
    故两码必需（R90 反证句：现有输出组合无法唯一还原该场景）。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 MAX × 2 → nOut = nHi、bOvF = TRUE、码 0645
    V2 MIN × -1 → nOut = nHi、bOvF = TRUE（禁回绕成 MIN）
    V3 MIN × 0 → 0 且 bOvF = FALSE
    V4 MIN × 1 → MIN 精确（无溢出、无钳位）
    V5 -3 × 5 → -15 精确
    V6 nLo > nHi → 码 0646、bError = TRUE、返回 FALSE
    V7 nLo = nHi = 100、积 = 200 → bClamped = TRUE 且 bOvF = FALSE（两标志可分）
    V8 nA = 0、nB = MIN → 0（零因子早于预判，无除零）
  修订记录 Revision  :
    2026-11-21  v1.0.0  R62 首版（批 1 · 序号 1）
  ==================================================================
*)
FUNCTION FC_DL_SaturateMul : BOOL
VAR_INPUT
    nA   : LINT; // 被乘数 [−]，完整 LINT 域 / the multiplicand over the full LINT domain
    nB   : LINT; // 乘数 [−]，完整 LINT 域 / the multiplier over the full LINT domain
    nLo  : LINT; // 输出钳位域下界 [−] / the output clamp lower bound
    nHi  : LINT; // 输出钳位域上界 [−] / the output clamp upper bound
END_VAR
VAR_OUTPUT
    nOut     : LINT;  // 钳位后结果 [−] / the clamped product
    bOvF     : BOOL;  // 乘法溢出发生（钳位已生效）[-] / a multiplicative overflow happened
    bClamped : BOOL;  // 钳位生效（含纯域钳，未溢出）[-] / the clamp took effect, domain clamp included
    bValid   : BOOL;  // 输出可用（溢出与组态故障为 FALSE）[-] / the output is usable
    eErr     : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError   : BOOL;  // 故障标志，故障级码同拍置位（R45 配对）/ the fault flag, raised with a fault level code
END_VAR
VAR
    liProd : LINT := 0; // 域内乘积中间量 [−] / the in-domain product intermediate
VAR CONSTANT
    DL_SMUL_MAX : LINT := 9223372036854775807;      // LINT 可表达上界 [−]，即 2^63−1 / the expressible LINT ceiling, two to the sixty third minus one
    DL_SMUL_MIN : LINT := -9223372036854775807 - 1; // LINT 可表达下界 [−]，以上界相反数减一表达，防字面量解析溢出 / the expressible LINT floor, written as the negated ceiling minus one to avoid a literal parse overflow
    DL_SMUL_ZERO : LINT := 0;                       // 有符号零常量 [−]，避免裸字面量 / the signed zero constant
    DL_SMUL_NEG1 : LINT := -1;                      // 负一常量 [−]，MIN × -1 判据用 / the minus one constant for the MIN times minus one criterion
END_VAR

// 段 1｜返回值与全部出口预置安全值（R45 四段式第一段）/ segment 1, preset every outlet to its safe value
FC_DL_SaturateMul := FALSE; // 返回值预置假 / preset the return false
nOut := DL_SMUL_ZERO; // 结果预置零 [−] / preset the product zero
bOvF := FALSE; // 溢出标志预置假 / preset the overflow flag false
bClamped := FALSE; // 钳位标志预置假 / preset the clamp flag false
bValid := FALSE; // 可用标志预置假，过闸后置位 / preset the validity false, raised after the gates
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 故障标志预置假 / preset the fault flag false
liProd := DL_SMUL_ZERO; // 乘积中间量清零 [−] / clear the product intermediate

// 段 2｜组态域闸：nLo > nHi 判故障早退（边界四，三件同口径）/ segment 2, the configuration gate, a reversed domain is a fault
IF nLo > nHi THEN // 钳位域反序 / the clamp domain is reversed
    eErr := 16#0001_0646; // 故障级：组态非法 nLo > nHi / fault grade, the reversed clamp domain
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 输出不可用 / the output is not usable
    nOut := DL_SMUL_ZERO; // 确定缺省值零 [−] / the deterministic default of zero
    RETURN; // 早退，不再触碰乘法 / early return, the multiplication is never touched
END_IF

// 段 3｜零因子优先：积恒为零，且消灭后续预判式的除零路径（边界三）/ segment 3, the zero factor comes first and removes every division by zero
IF (nA = DL_SMUL_ZERO) OR (nB = DL_SMUL_ZERO) THEN // 任一因子为零 / either factor is zero
    liProd := DL_SMUL_ZERO; // 积确定为零 [−] / the product is exactly zero
ELSE // 双因子非零才做溢出预判 / the overflow pre-check runs only with two nonzero factors
    // 段 4｜MIN × -1 直判正溢出（边界二）：MIN 绝对值不可表示，先乘会回绕成 MIN / segment 4, the direct check of MIN times minus one
    IF ((nA = DL_SMUL_MIN) AND (nB = DL_SMUL_NEG1)) OR ((nB = DL_SMUL_MIN) AND (nA = DL_SMUL_NEG1)) THEN // 极限组合 / the limit combination
        bOvF := TRUE; // 置溢出标志（禁回绕成 MIN）/ raise the overflow flag instead of wrapping to MIN
        bClamped := TRUE; // 钳位已生效 / the clamp took effect
        nOut := nHi; // 正溢出按符号钳上界 [−] / a positive overflow clamps to the upper bound by sign
        eErr := 16#0001_0645; // 故障级：乘法溢出 / fault grade, a multiplicative overflow
        bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
        bValid := FALSE; // 输出不可用（结果是伪造边界）/ the output is not usable, the boundary is fabricated
        RETURN; // 早退 / early return
    END_IF
    // 段 5｜四象限溢出预判（边界一）：比较式内只有除法，没有裸乘法 / segment 5, the four quadrant pre-check with divisions only
    IF (nA > DL_SMUL_ZERO) AND (nB > DL_SMUL_ZERO) THEN // 正正象限 / the positive positive quadrant
        IF nA > (DL_SMUL_MAX / nB) THEN // 超上界预判（nB ≥ 1，除子安全）/ the ceiling pre-check with a safe divisor
            bOvF := TRUE; // 置溢出标志 / raise the overflow flag
            bClamped := TRUE; // 钳位已生效 / the clamp took effect
            nOut := nHi; // 正溢出钳上界 [−] / a positive overflow clamps to the upper bound
        END_IF
    ELSIF (nA < DL_SMUL_ZERO) AND (nB < DL_SMUL_ZERO) THEN // 负负象限（积为正）/ the negative negative quadrant, a positive product
        IF nA < (DL_SMUL_MAX / nB) THEN // 超上界预判（MAX ÷ 负数为负，直比不失号）/ the ceiling pre-check against a negative quotient
            bOvF := TRUE; // 置溢出标志 / raise the overflow flag
            bClamped := TRUE; // 钳位已生效 / the clamp took effect
            nOut := nHi; // 正溢出钳上界 [−] / a positive overflow clamps to the upper bound
        END_IF
    ELSIF (nA > DL_SMUL_ZERO) AND (nB < DL_SMUL_ZERO) THEN // 正负象限（积为负）/ the positive negative quadrant, a negative product
        IF nB < (DL_SMUL_MIN / nA) THEN // 超下界预判（nA ≥ 1，除子安全）/ the floor pre-check with a safe divisor
            bOvF := TRUE; // 置溢出标志 / raise the overflow flag
            bClamped := TRUE; // 钳位已生效 / the clamp took effect
            nOut := nLo; // 负溢出钳下界 [−] / a negative overflow clamps to the lower bound
        END_IF
    ELSE // 负正象限（积为负）/ the negative positive quadrant, a negative product
        IF nA < (DL_SMUL_MIN / nB) THEN // 超下界预判（nB ≥ 1，除子安全）/ the floor pre-check with a safe divisor
            bOvF := TRUE; // 置溢出标志 / raise the overflow flag
            bClamped := TRUE; // 钳位已生效 / the clamp took effect
            nOut := nLo; // 负溢出钳下界 [−] / a negative overflow clamps to the lower bound
        END_IF
    END_IF
    IF bOvF THEN // 已判溢出：结果已直达边界，跳过域钳 / an overflow already reached the boundary, the domain clamp is skipped
        eErr := 16#0001_0645; // 故障级：乘法溢出 / fault grade, a multiplicative overflow
        bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
        bValid := FALSE; // 输出不可用 / the output is not usable
        RETURN; // 早退 / early return
    END_IF
    liProd := nA * nB; // 预判通过后域内相乘（此时必不溢出）/ multiply after the pre-check passed, so no overflow can occur
END_IF

// 段 6｜统一域钳（零因子与域内积共用同一出口，R94 早退分支后处理一致）/ segment 6, the unified domain clamp shared by both paths
IF liProd > nHi THEN // 超上界 / above the ceiling
    nOut := nHi; // 钳上界 [−] / clamp to the ceiling
    bClamped := TRUE; // 置钳位标志 / raise the clamp flag
ELSIF liProd < nLo THEN // 超下界 / below the floor
    nOut := nLo; // 钳下界 [−] / clamp to the floor
    bClamped := TRUE; // 置钳位标志 / raise the clamp flag
ELSE // 域内 / inside the domain
    nOut := liProd; // 直出乘积 [−] / pass the product through
END_IF

// 段 7｜信息级钳位码与可用位（纯域钳不置 bError，R285 分级纪律）/ segment 7, the informational clamp code without a fault flag
IF bClamped THEN // 发生纯域钳（溢出已在段 5 早退）/ a pure domain clamp happened, overflow already returned earlier
    eErr := 16#0001_0644; // 信息级：结果被域钳位 / informational, the result was clamped to the domain
END_IF
bValid := TRUE; // 域内或钳位输出均可用 / an in-domain or clamped output is usable
FC_DL_SaturateMul := TRUE; // 返回成功 / return success
END_FUNCTION
