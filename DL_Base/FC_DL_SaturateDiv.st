(*
  ==================================================================
  组件名 Component  : FC_DL_SaturateDiv
  分类   Category   : DL_Base
  前缀   Naming     : FC_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0001_0647（信息级）｜ 16#0001_0648 / 0649 / 064A（故障级）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 中
  功能   Purpose    : LINT 宽域饱和除法：nOut = clamp(nNum ÷ nDen, nLo, nHi)，判据有序
                      （除零 → MIN÷-1 → 正常除 → 域钳），整数商向零截断。
  开源溯源 Origin    : IEC 61131-3 标准语义的道莅防御性实现（clean-room，无第三方代码行）
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6.2 算术运算符（整数除法，商向零截断）
  平台   Platform   : 纯 IEC 61131-3（仅四则与比较），CODESYS / TwinCAT 3 / InoProShop 通用
  依赖   Depends    : 仅 Standard.library（无库调用）
  分工声明 Split     : FC_DL_DivDintSafeChk 为「安全除 + 商出口 + 布尔返回」的判据件
                      （DINT 域、无钳位域）；FC_DL_DivLrealSafe 为浮点域安全除；
                      本件为宽域（LINT）饱和除，带钳位域与三段标志。三者边界：
                      需要「除零仅判不钳」用前者，需要「浮点除法」用中者，
                      需要「整数宽域 + 钳位域 + 溢出标志」用本件（R216 双向互引）。
  归属 Ownership     : 本件无 TYPE 声明，全部引脚为 IEC 标准原生类型。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 判据严格有序：① 除数为零 → 早退（禁走钳位，钳位会把非法
                         结果伪装成合法边界）；② MIN ÷ -1 → 溢出钳 nHi；③ 正常除；
                         ④ 结果钳域 [nLo, nHi]；
                      二 商向零截断（IEC 语义）：-7 ÷ 2 = -3 而非 -4；本件不做四舍五入，
                         工程舍入口径归 FC_DL_RoundSat，有效位舍入归 FC_DL_RoundSigFigs；
                      三 nLo > nHi 判组态故障并返回 FALSE（与 FC_DL_SaturateMul、
                         FC_DL_RealToIntSat 同口径，三件一致，禁静默交换）；
                      四 纯函数：无记忆量、无定时器、无边沿实例，每调用重算。
  错误码 Codes      :
    16#0001_0647【信息级】结果被域 [nLo, nHi] 钳位（未溢出、未除零，bValid = TRUE）
    16#0001_0648【故障级】除数为零（nOut = 0，bValid = FALSE，早退不走钳位）
    16#0001_0649【故障级】MIN ÷ -1 溢出（nOut 钳 nHi，bOvF = TRUE）
    16#0001_064A【故障级】组态非法 nLo > nHi（判故障返回 FALSE，nOut = 0）
  码位反证 Note     :
    0648 不可并入 0647：除零结果与钳位结果在数值出口上同为边界值或零，上游无法由
    nOut 与 bClamped 组合区分「输入非法」与「输入合法但被限幅」，两码必需（R90）。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 5 ÷ 0 → 0、bDivZero = TRUE、bValid = FALSE、码 0648（不走钳位）
    V2 MIN ÷ -1 → nHi、bOvF = TRUE、码 0649
    V3 MIN ÷ 1 → MIN 精确
    V4 1 ÷ MIN → 0，bClamped = FALSE（未触钳位，仅截断）
    V5 -7 ÷ 2 → -3（向零截断，非 -4）
    V6 nLo > nHi → 码 064A、返回 FALSE
    V7 100 ÷ 3 = 33（截断）、域 [0, 20] → bClamped = TRUE、码 0647、bValid = TRUE
    V8 MIN ÷ -3 → 正常除（除子非 -1）不溢出
  修订记录 Revision  :
    2026-11-21  v1.0.0  R62 首版（批 1 · 序号 2）
  ==================================================================
*)
FUNCTION FC_DL_SaturateDiv : BOOL
VAR_INPUT
    nNum : LINT; // 被除数 [−]，完整 LINT 域 / the dividend over the full LINT domain
    nDen : LINT; // 除数 [−]，零为非法（判故障）/ the divisor, zero is illegal and raises a fault
    nLo  : LINT; // 输出钳位域下界 [−] / the output clamp lower bound
    nHi  : LINT; // 输出钳位域上界 [−] / the output clamp upper bound
END_VAR
VAR_OUTPUT
    nOut     : LINT;  // 钳位后商 [−] / the clamped quotient
    bDivZero : BOOL;  // 除数为零 [-] / the divisor is zero
    bOvF     : BOOL;  // 溢出发生（MIN ÷ -1）[-] / an overflow happened on MIN divided by minus one
    bClamped : BOOL;  // 钳位生效（含纯域钳）[-] / the clamp took effect, domain clamp included
    bValid   : BOOL;  // 输出可用（除零与组态故障为 FALSE）[-] / the output is usable
    eErr     : UDINT; // 错误码，0 = 正常 / the error code, zero is ok
    bError   : BOOL;  // 故障标志，故障级码同拍置位（R45 配对）/ the fault flag, raised with a fault level code
END_VAR
VAR
    liQuot : LINT := 0; // 域内商中间量 [−] / the in-domain quotient intermediate
VAR CONSTANT
    DL_SDIV_MAX : LINT := 9223372036854775807;      // LINT 可表达上界 [−]，独立命名不与乘法件冲突 / the expressible LINT ceiling under its own name
    DL_SDIV_MIN : LINT := -9223372036854775807 - 1; // LINT 可表达下界 [−]，以上界相反数减一表达 / the expressible LINT floor written as the negated ceiling minus one
    DL_SDIV_ZERO : LINT := 0;                       // 有符号零常量 [−] / the signed zero constant
    DL_SDIV_NEG1 : LINT := -1;                      // 负一常量 [−]，MIN ÷ -1 判据用 / the minus one constant for the MIN divided by minus one criterion
END_VAR

// 段 1｜返回值与全部出口预置安全值（R45 四段式第一段）/ segment 1, preset every outlet to its safe value
FC_DL_SaturateDiv := FALSE; // 返回值预置假 / preset the return false
nOut := DL_SDIV_ZERO; // 结果预置零 [−] / preset the quotient zero
bDivZero := FALSE; // 除零标志预置假 / preset the divide by zero flag false
bOvF := FALSE; // 溢出标志预置假 / preset the overflow flag false
bClamped := FALSE; // 钳位标志预置假 / preset the clamp flag false
bValid := FALSE; // 可用标志预置假，过闸后置位 / preset the validity false, raised after the gates
eErr := 16#0000_0000; // 错误码预置正常 / preset the code to ok
bError := FALSE; // 故障标志预置假 / preset the fault flag false
liQuot := DL_SDIV_ZERO; // 商中间量清零 [−] / clear the quotient intermediate

// 段 2｜组态域闸：nLo > nHi 判故障早退（边界三，三件同口径）/ segment 2, the configuration gate, a reversed domain is a fault
IF nLo > nHi THEN // 钳位域反序 / the clamp domain is reversed
    eErr := 16#0001_064A; // 故障级：组态非法 nLo > nHi / fault grade, the reversed clamp domain
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 输出不可用 / the output is not usable
    nOut := DL_SDIV_ZERO; // 确定缺省值零 [−] / the deterministic default of zero
    RETURN; // 早退 / early return
END_IF

// 段 3｜判据①除数为零：早退，绝不行钳位（边界一，钳位会把非法伪装成合法边界）/ segment 3, the divisor zero gate, clamped never runs
IF nDen = DL_SDIV_ZERO THEN // 除数为零 / the divisor is zero
    bDivZero := TRUE; // 置除零标志 / raise the divide by zero flag
    nOut := DL_SDIV_ZERO; // 确定缺省值零 [−] / the deterministic default of zero
    eErr := 16#0001_0648; // 故障级：除数为零 / fault grade, the divisor is zero
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 输出不可用 / the output is not usable
    RETURN; // 早退，不做任何除法与钳位 / early return without any division or clamping
END_IF

// 段 4｜判据②MIN ÷ -1 溢出（MIN 的绝对值不可表示，先除必回绕）/ segment 4, the MIN divided by minus one overflow
IF (nNum = DL_SDIV_MIN) AND (nDen = DL_SDIV_NEG1) THEN // 极限组合 / the limit combination
    bOvF := TRUE; // 置溢出标志（禁回绕成 MIN）/ raise the overflow flag instead of wrapping to MIN
    bClamped := TRUE; // 钳位已生效 / the clamp took effect
    nOut := nHi; // 正溢出按符号钳上界 [−] / a positive overflow clamps to the upper bound by sign
    eErr := 16#0001_0649; // 故障级：MIN ÷ -1 溢出 / fault grade, the MIN divided by minus one overflow
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    bValid := FALSE; // 输出不可用 / the output is not usable
    RETURN; // 早退 / early return
END_IF

// 段 5｜判据③正常除：整数商向零截断（边界二，IEC 语义，-7 ÷ 2 = -3）/ segment 5, the normal division with the quotient truncated toward zero
IF nNum = DL_SDIV_ZERO THEN // 零被除数：商确为零，免一次除法 / a zero dividend gives an exact zero quotient, no division needed
    liQuot := DL_SDIV_ZERO; // 商为零 [−] / the quotient is zero
ELSE // 非零被除数才真除（除子已在段 3 证非零）/ the real division only for a nonzero dividend, the divisor is proven nonzero
    liQuot := nNum / nDen; // 向零截断（-7 ÷ 2 = -3，非 -4）[−] / truncated toward zero, minus seven over two gives minus three
END_IF

// 段 6｜判据④统一域钳（零被除数与正常除共用同一出口，R94）/ segment 6, the unified domain clamp shared by both paths
IF liQuot > nHi THEN // 超上界 / above the ceiling
    nOut := nHi; // 钳上界 [−] / clamp to the ceiling
    bClamped := TRUE; // 置钳位标志 / raise the clamp flag
ELSIF liQuot < nLo THEN // 超下界 / below the floor
    nOut := nLo; // 钳下界 [−] / clamp to the floor
    bClamped := TRUE; // 置钳位标志 / raise the clamp flag
ELSE // 域内 / inside the domain
    nOut := liQuot; // 直出商 [−] / pass the quotient through
END_IF

// 段 7｜信息级钳位码与可用位（纯域钳不置 bError，R285）/ segment 7, the informational clamp code without a fault flag
IF bClamped THEN // 发生纯域钳 / a pure domain clamp happened
    eErr := 16#0001_0647; // 信息级：结果被域钳位 / informational, the result was clamped to the domain
END_IF
bValid := TRUE; // 域内或钳位输出均可用 / an in-domain or clamped output is usable
FC_DL_SaturateDiv := TRUE; // 返回成功 / return success
END_FUNCTION
