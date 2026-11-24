//==============================================================================
// 函数：FC_DL_DeadtimeTapCalc ｜ 中文名称：死区时间→离散拍数向上取整换算
// 所属子库：DL_Algo ｜ 版本：v1.0.0 ｜ 日期：2026-11-23
// 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop（纯标准库）
// 功能描述：nTicks = CEIL(tDeadtime / tSample) 换算原子（Smith 预估器/
//           死区补偿前置）。取整纪律（终审必查项）：禁 TRUNC(x)+1 写法——
//           先 TRUNC 得整商，再按余量 > 容差进位；整商已达 DINT 上限且仍有
//           余量时饱和钳位 + bSaturated 声明（防进位溢出回绕）。
//           分工声明：离散拍数原子属本件；Smith 预估本体属
//           FB_DL_SmithPredictor，互不替代。
// 开源溯源 (Origin)：原创实现（自研-std 标准包装线，零外部源码行，clean-room
//           独立编写）
// 公开接口清单：输入 tDeadtime / tSample；输出 nTicks / bSaturated / bValid
// 错误码表：纯函数无状态机码轨；无效输入经 bValid = FALSE 表达（哨兵返回
//           0），饱和经 bSaturated 声明，本件不占用 16#0002 段码位
// 状态机：N/A（纯函数，无状态，可重入）
// 边界行为：① tSample <= 0（采样拍长非法）→ 拒绝（哨兵 0 返回）；
//           ② tDeadtime < 0 → 拒绝；tDeadtime = 0 合法（nTicks = 0）；
//           ③ 余量 > 1.0E-6 才进位（纯整除不虚进一位）；
//           ④ 商超 DINT 上限且有进位需求 → 饱和钳 2147483647 + bSaturated；
//           ⑤ 非有限输入 → 哨兵 0 返回。
// 修订历史：v1.0.0 2026-11-23 首版（R73 派单 · 批 3 · 序 18）
//==============================================================================

(*------------------------------------------------------------------------------
 * 调用示例：n := FC_DL_DeadtimeTapCalc(tDeadtime := T#2S, tSample := T#100MS,
 *                                       bSaturated => bSat, bValid => bOk);
 * 注意：n = 20；bSaturated = TRUE 时结果为饱和钳位值，禁入 Smith 本体。
 *-----------------------------------------------------------------------------*)
FUNCTION FC_DL_DeadtimeTapCalc : DINT
VAR_INPUT
    tDeadtime : TIME;                  // 死区时间 [毫秒] / Dead time [ms]
    tSample   : TIME;                  // 离散采样拍长 [毫秒] / Discrete sample period [ms]
END_VAR
VAR_OUTPUT
    bSaturated : BOOL;                 // 饱和钳位声明（TRUE 时结果为钳位值）/ Saturation declaration
    bValid     : BOOL;                 // 结果有效标志，FALSE 时返回哨兵 0 / Result validity flag
END_VAR
VAR CONSTANT
    DL_DT_DINTMAX : DINT   := 2147483647; // DINT 正向上限 / DINT positive ceiling
    DL_DT_EPS     : LREAL  := 1.0E-6;   // 余量进位容差 [拍] / Carry tolerance [taps]
    DL_DT_ZERO    : DINT   := 0;        // 无效哨兵返回值 / Sentinel return for invalid
    DL_DT_MS_PER_S: LREAL  := 1000.0;   // 毫秒→秒换算系数 [毫秒每秒] / ms-to-s scale [ms per s]
END_VAR
VAR
    fDeadSec : LREAL;                  // 死区时间换算秒 [秒] / Dead time in seconds [s]
    fSmpSec  : LREAL;                  // 采样拍长换算秒 [秒] / Sample period in seconds [s]
    fQuot    : LREAL;                  // 实数商 [拍] / Real quotient [taps]
    nQuot    : DINT;                   // TRUNC 整商 [拍] / Truncated integer quotient [taps]
    fRemain  : LREAL;                  // 余量 [拍] / Remainder fraction [taps]
END_VAR

// ---- 段 1｜出口默认值（纯函数无实例，无定时器/沿刷新义务）----
bSaturated := FALSE;                  // 饱和声明默认 FALSE / Saturation preset FALSE
bValid := FALSE;                      // 缺省无效 / Invalid by default

// ---- 段 2｜TIME → 秒换算（标准显式转换 R10；TIME 上限 DWORD 毫秒域足够）----
fDeadSec := DINT_TO_LREAL(TIME_TO_DINT(tDeadtime)) / DL_DT_MS_PER_S; // 死区秒值 [秒] / Dead time seconds
fSmpSec  := DINT_TO_LREAL(TIME_TO_DINT(tSample)) / DL_DT_MS_PER_S;   // 拍长秒值 [秒] / Sample seconds

// ---- 段 3｜域闸：拍长正域 + 死区非负域（TIME 为无符号毫秒，仍双闸防御）----
IF (fSmpSec <= 0.0) OR (fDeadSec < 0.0) THEN
    FC_DL_DeadtimeTapCalc := DL_DT_ZERO; // 域外拒绝：哨兵零返回 / Out of domain, refused
    RETURN;                            // 结构早退 / early exit
END_IF

// ---- 段 4｜商主体与取整纪律：先 TRUNC 整商，余量超容差才进位（禁 TRUNC+1）----
fQuot   := fDeadSec / fSmpSec;        // 实数商 [拍]，分母已过正域闸 / Real quotient, denominator gated
IF fQuot <> fQuot THEN                // 商非有限兜底（双有限入参理论上不可达，R90 复检）
    FC_DL_DeadtimeTapCalc := DL_DT_ZERO; // 非有限商哨兵返回 / Non-finite quotient, sentinel return
    RETURN;                            // 结构早退 / early exit
END_IF
IF fQuot >= DINT_TO_LREAL(DL_DT_DINTMAX) THEN // 实数上限兜底：商超 DINT 域直接饱和（防 TRUNC 溢出回绕，R28）
    FC_DL_DeadtimeTapCalc := DL_DT_DINTMAX; // 饱和钳位出口 / Saturating outlet
    bSaturated := TRUE;                // 饱和声明置位 / Saturation declared
    bValid := TRUE;                    // 饱和是合法结论（调用方判 bSaturated）/ Saturation is a valid conclusion
    RETURN;                            // 结构早退 / early exit
END_IF
nQuot   := TRUNC(fQuot);              // TRUNC 整商（向零取整，商恒非负；上限已预闸不溢）/ Truncated quotient, ceiling pre-gated
fRemain := fQuot - DINT_TO_LREAL(nQuot); // 余量 [拍] / Remainder fraction
IF fRemain > DL_DT_EPS THEN           // 余量超容差才进位（纯整除不虚进一位）/ Carry only on real remainder
    IF nQuot >= DL_DT_DINTMAX THEN
        nQuot := DL_DT_DINTMAX;      // 整商已顶上限：饱和钳位不进位（防回绕）/ Quotient at ceiling, saturate
        bSaturated := TRUE;          // 饱和声明置位 / Saturation declared
    ELSE
        nQuot := nQuot + 1;          // 正常进位一位 / Normal one-tap carry
    END_IF
END_IF
FC_DL_DeadtimeTapCalc := nQuot;       // 离散拍数 [拍] / Discrete tap count
bValid := TRUE;                       // 全部防御通过：结果有效 / Result valid
END_FUNCTION
