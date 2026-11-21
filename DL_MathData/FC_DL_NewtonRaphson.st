(*
  ==================================================================
  组件名 Component  : FC_DL_NewtonRaphson
  分类   Category   : DL_MathData
  版本   Version    : 1.0.0
  功能   Purpose    : 一元非线性方程牛顿迭代求根。主入口以多项式系数
                      a0..a8（下标即 x 的幂次）为方程定义，Horner 法一次
                      遍历同时得 f(x) 与解析 f'(x)；若置 bUseNumDiff 则改走
                      迭代内前向差分求导，免解析导数。副入口 FC_DL_NewtonStep
                      承载函数指针不可用时的两入口范式：调用侧用两个自有 FC
                      分别算出 f 与 f'，再逐步喂入 NewtonStep 推进迭代。
  防死锁 Anti-deadlock:
                      一 迭代次数硬上限 DL_NR_ITER_CAP = 200，入参超限钳到上限，
                         小于 1 钳 1；
                      二 收敛容差双端钳定 1E-12 / 1E-1，防「永不达标空转」与
                         「未迭代即判收敛」；
                      三 导数绝对值小于 lrDerivEps 立即退出并置 eDerivZero；
                      四 迭代量或残差出非有限值立即退出并置 eNonFinite；
                      五 残差连续 DL_NR_STALL_CAP 次无改善判停滞退出（eNoRoot）；
                      六 单步位移限幅 ±DL_NR_STEP_MAX，防坏导数放大成越界跳变。
  溯源   Origin     : 牛顿-拉夫逊迭代为公开数值方法。来源标签 t2-1-lgf-math（函数库
                      数学件分类域）；本件 clean-room 实现，仅借鉴来源分类与参数域
                      组织，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（LREAL / WHILE / ABS / 无私有库、无方言转换）
  作者   Author     : 道莅代码库 · PLC 编程专家（R55）
  ------------------------------------------------------------------
  输入契约 Input contract:
                      afCoef 为引用型入参，由调用方持有并绑定，容量固定 9 项；
                      高阶项系数填 0 即按低阶多项式自然退化，无需裁剪数组。
  输出契约 Output contract:
                      eStatus 六态互斥；bConverged 仅 eOk 拍为 TRUE；bError 在一切
                      非 eOk 状态为 TRUE（含 eMaxIter 未达成，供上层判据用）；
                      bValid 仅在「根值有限 且 收敛或停滞」时为 TRUE；
                      根值非有限时出口回退初值 lrX0，非有限值不穿透出口。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R55 首版（批 1 · 序号 1）
  ==================================================================
*)

TYPE E_DL_NrStatus :
(
    eOk        := 0,    // 收敛：残差已达容差 / converged, residual within tolerance
    eMaxIter   := 10,   // 达迭代上限未收敛 / iteration cap reached without convergence
    eDerivZero := 20,   // 导数近零：牛顿方向不可用 / derivative near zero, direction unusable
    eNonFinite := 30,   // 迭代中出非有限值（发散）/ non-finite value during iteration, diverged
    eBadArg    := 40,   // 入参非法：系数全零或入参非有限 / illegal argument, zero polynomial or non-finite input
    eNoRoot    := 50    // 停滞：残差连续无改善 / stalled, residual stopped improving
);
END_TYPE

FUNCTION FC_DL_NewtonRaphson : LREAL
VAR_IN_OUT
    afCoef      : ARRAY[0..8] OF LREAL;      // 多项式系数 a0..a8，下标即 x 的幂次 [无量纲]，引用型入参由调用方绑定 / coefficients a0..a8, subscript is the power of x [dimensionless], reference parameter bound by caller
END_VAR
VAR_INPUT
    lrX0        : LREAL := 0.0;              // 迭代初值 [无量纲] / initial guess [dimensionless]
    lrTol       : LREAL := 1.0E-9;           // 残差收敛容差 [无量纲]，双端钳定 / residual tolerance [dimensionless], clamped both ends
    lrDerivEps  : LREAL := 1.0E-10;          // 导数近零阈值 [无量纲]，导子绝对值小于即退出 / derivative near-zero threshold [dimensionless]
    nMaxIterIn  : INT := 50;                 // 期望最大迭代次数 [次]，超硬上限被钳 / requested max iterations [count], hard capped
    bUseNumDiff : BOOL := FALSE;             // 真 = 迭代内前向差分求导，假 = 解析导数 / true for in-loop forward difference, false for analytic derivative
    lrDiffStep  : LREAL := 1.0E-6;           // 差分步长 [无量纲]，域 大于零 / forward difference step [dimensionless], domain greater than zero
END_VAR
VAR_OUTPUT
    eStatus     : E_DL_NrStatus := E_DL_NrStatus.eOk; // 求根结果状态 [枚举] / root finding status [enum]
    nIterUsed   : INT := 0;                  // 实际迭代次数 [次] / iterations actually used [count]
    lrResidual  : LREAL := 0.0;              // 末次残差绝对值 [无量纲] / last absolute residual [dimensionless]
    bConverged  : BOOL := FALSE;             // 是否收敛 [-] / converged flag
    bError      : BOOL := FALSE;             // 是否未达成（任何非 eOk 状态）[-] / not achieved flag for any non-ok status
    bValid      : BOOL := FALSE;             // 根值是否可交付使用 [-] / root deliverable flag
END_VAR
VAR
    lrX         : LREAL := 0.0;              // 当前迭代点 [无量纲] / current iterate [dimensionless]
    lrFx        : LREAL := 0.0;              // 当前函数值 f(x) [无量纲] / current function value [dimensionless]
    lrFxH       : LREAL := 0.0;              // 差分点上函数值 f(x+h) [无量纲] / function value at the difference point [dimensionless]
    lrDf        : LREAL := 0.0;              // 当前导数值 f'(x) [无量纲] / current derivative value [dimensionless]
    lrStep      : LREAL := 0.0;              // 本步位移量 [无量纲] / current Newton step [dimensionless]
    lrResPrev   : LREAL := 0.0;              // 上一轮残差绝对值，停滞判据用 [无量纲] / previous residual for stall detection [dimensionless]
    lrTolUse    : LREAL := 1.0E-9;           // 钳定后的实际容差 [无量纲] / clamped effective tolerance [dimensionless]
    lrEpsUse    : LREAL := 1.0E-10;          // 钳定后的实际导数阈值 [无量纲] / clamped effective derivative threshold [dimensionless]
    lrHUse      : LREAL := 1.0E-6;           // 钳定后的实际差分步长 [无量纲] / clamped effective difference step [dimensionless]
    nIdx        : INT := 0;                  // 系数下标游标，向下递减 [下标] / coefficient index cursor, decremented [index]
    nIter       : INT := 0;                  // 迭代计数 [次] / iteration counter [count]
    nMaxIter    : INT := 1;                  // 钳定后的迭代上限 [次] / clamped iteration cap [count]
    nStall      : INT := 0;                  // 残差无改善连续计数 [次] / consecutive no-improvement count [count]
    bLoop       : BOOL := FALSE;             // 迭代循环续行标志 [-] / loop continuation flag
    bFinite     : BOOL := FALSE;             // 根值有限性判定暂存 [-] / root finiteness latch
    bCoefNz     : BOOL := FALSE;             // 多项式非全零判定暂存 [-] / non-zero polynomial latch
END_VAR
VAR CONSTANT
    DL_NR_ORD       : INT := 8;              // 多项式最高幂次，等于系数数组上界 [幂次] / highest polynomial order, equals coefficient upper bound
    DL_NR_ITER_CAP  : INT := 200;            // 迭代次数硬上限，防死锁 [次] / hard iteration cap against deadlock [count]
    DL_NR_TOL_MIN   : LREAL := 1.0E-12;      // 容差下限，防永不达标空转 [无量纲] / tolerance lower bound [dimensionless]
    DL_NR_TOL_MAX   : LREAL := 1.0E-1;       // 容差上限，防未迭代即判收敛 [无量纲] / tolerance upper bound [dimensionless]
    DL_NR_EPS_MIN   : LREAL := 1.0E-15;      // 导数阈值下限，防零阈致除零 [无量纲] / derivative threshold lower bound [dimensionless]
    DL_NR_STALL_CAP : INT := 5;              // 残差无改善连续次数上限 [次] / stall count cap [count]
    DL_NR_STEP_MAX  : LREAL := 1.0E9;        // 单步位移绝对上限 [无量纲] / single step absolute cap [dimensionless]
    DL_NR_H_MIN     : LREAL := 1.0E-9;       // 差分步长下限 [无量纲] / difference step lower bound [dimensionless]
    DL_NR_H_MAX     : LREAL := 1.0E-1;       // 差分步长上限 [无量纲] / difference step upper bound [dimensionless]
END_VAR

// 段 1｜返回值与错误状态预置，任何早退路径不留脏码 / segment 1, preset return value and error states, no dirty code on any early exit
FC_DL_NewtonRaphson := lrX0; // 返回值预置初值，非有限根时即以此值出口 / preset return to the initial guess, also the fallback when the root is non-finite
eStatus    := E_DL_NrStatus.eOk; // 状态预置收敛，后续按判定改写 / preset status to converged, rewritten by the following gates
nIterUsed  := 0; // 迭代计数出口预置零 / preset iteration count outlet to zero
lrResidual := 0.0; // 残差出口预置零 / preset residual outlet to zero
bConverged := FALSE; // 收敛标志预置假 / preset converged flag to false
bError     := FALSE; // 错误标志预置假 / preset error flag to false
bValid     := FALSE; // 有效标志预置假 / preset valid flag to false
lrX        := lrX0; // 迭代点从初值起步 / start the iterate from the initial guess

// 段 2｜入参域闸：容差双端钳定、迭代上限钳定、差分步长钳定、初值有限性 / segment 2, argument domain gate for tolerance, iteration cap, difference step and initial guess finiteness
lrTolUse := lrTol; // 容差默认直通 / tolerance passes through by default
IF lrTolUse <> lrTolUse THEN // 自反判 NaN / self-inequality detects NaN
    lrTolUse := DL_NR_TOL_MIN; // NaN 回落下限 / NaN falls back to the lower bound
END_IF
IF lrTolUse < DL_NR_TOL_MIN THEN // 容差过小 / tolerance too small
    lrTolUse := DL_NR_TOL_MIN; // 抬到下限，防永不达标空转 / raised to the lower bound against endless spinning
ELSIF lrTolUse > DL_NR_TOL_MAX THEN // 容差过大 / tolerance too large
    lrTolUse := DL_NR_TOL_MAX; // 压到上限，防未迭代即判收敛 / pressed to the upper bound against premature convergence
END_IF

lrEpsUse := lrDerivEps; // 导数阈值默认直通 / derivative threshold passes through by default
IF lrEpsUse <> lrEpsUse THEN // 自反判 NaN / self-inequality detects NaN
    lrEpsUse := DL_NR_EPS_MIN; // NaN 回落下限 / NaN falls back to the lower bound
END_IF
IF lrEpsUse < DL_NR_EPS_MIN THEN // 阈值过小 / threshold too small
    lrEpsUse := DL_NR_EPS_MIN; // 抬到下限，防除子近零 / raised against a near-zero divisor
ELSIF lrEpsUse > 1.0E-3 THEN // 阈值过大 / threshold too large
    lrEpsUse := 1.0E-3; // 压到 1E-3，防正常导数被误判近零 / pressed to 1E-3 against false near-zero verdicts
END_IF

lrHUse := lrDiffStep; // 差分步长默认直通 / difference step passes through by default
IF lrHUse <> lrHUse THEN // 自反判 NaN / self-inequality detects NaN
    lrHUse := 1.0E-6; // NaN 回落默认步长 / NaN falls back to the default step
END_IF
IF lrHUse < DL_NR_H_MIN THEN // 步长过小 / step too small
    lrHUse := DL_NR_H_MIN; // 抬到下限，防差分除子近零 / raised against a near-zero difference divisor
ELSIF lrHUse > DL_NR_H_MAX THEN // 步长过大 / step too large
    lrHUse := DL_NR_H_MAX; // 压到上限，防差分失真 / pressed against difference distortion
END_IF

nMaxIter := nMaxIterIn; // 迭代上限默认直通 / iteration cap passes through by default
IF nMaxIter < 1 THEN // 上限非法 / illegal cap
    nMaxIter := 1; // 钳到最少一次 / clamped to at least one iteration
ELSIF nMaxIter > DL_NR_ITER_CAP THEN // 上限越硬顶 / cap above the hard ceiling
    nMaxIter := DL_NR_ITER_CAP; // 钳到硬上限，防死锁 / clamped to the hard ceiling against deadlock
END_IF

// 段 3｜初值与系数有限性闸：非有限即判入参非法，不进迭代 / segment 3, finiteness gate on the initial guess and coefficients, illegal arguments never enter the loop
IF (lrX0 <> lrX0) OR ((lrX0 - lrX0) <> (lrX0 - lrX0)) THEN // 初值 NaN 或无穷 / initial guess is NaN or infinity
    eStatus := E_DL_NrStatus.eBadArg; // 入参非法 / illegal argument
    bError  := TRUE; // 置错误标志 / raise error flag
    bValid  := FALSE; // 出口不可用 / outlet unusable
    nIterUsed := 0; // 零次迭代 / zero iterations executed
    RETURN; // 早退，返回预置初值 / early exit with the preset initial guess
END_IF

bCoefNz := FALSE; // 多项式非全零标志预置假 / preset non-zero polynomial flag to false
nIdx := 0; // 下标游标归零 / reset the index cursor
WHILE nIdx <= DL_NR_ORD DO // 系数有限性与非全零双重扫查 / dual sweep for coefficient finiteness and non-zero content
    IF (afCoef[nIdx] <> afCoef[nIdx]) OR ((afCoef[nIdx] - afCoef[nIdx]) <> (afCoef[nIdx] - afCoef[nIdx])) THEN // 单项非有限 / single coefficient non-finite
        eStatus := E_DL_NrStatus.eBadArg; // 入参非法 / illegal argument
        bError  := TRUE; // 置错误标志 / raise error flag
        bValid  := FALSE; // 出口不可用 / outlet unusable
        RETURN; // 早退，返回预置初值 / early exit with the preset initial guess
    END_IF
    IF ABS(afCoef[nIdx]) > 0.0 THEN // 存在非零系数 / a non-zero coefficient exists
        bCoefNz := TRUE; // 置非全零标志 / raise the non-zero flag
    END_IF
    nIdx := nIdx + 1; // 游标递增，上界由 8 约束 / increment the cursor, upper bound fixed by eight
END_WHILE
IF NOT bCoefNz THEN // 全零多项式，任何点都是根 / zero polynomial, every point is a root
    eStatus := E_DL_NrStatus.eBadArg; // 入参非法，无求根意义 / illegal argument, root finding is meaningless
    bError  := TRUE; // 置错误标志 / raise error flag
    bValid  := FALSE; // 出口不可用 / outlet unusable
    RETURN; // 早退，返回预置初值 / early exit with the preset initial guess
END_IF

// 段 4｜牛顿迭代主循环：每轮先求值求导，再四级出口闸（收敛 / 导数近零 / 非有限 / 停滞）/ segment 4, Newton main loop with four exit gates per round
nIter    := 0; // 迭代计数清零 / reset the iteration counter
nStall   := 0; // 停滞计数清零 / reset the stall counter
lrResPrev := 0.0; // 残差快照清零 / reset the residual snapshot
bLoop    := TRUE; // 循环续行标志置真 / arm the loop continuation flag
WHILE bLoop AND (nIter < nMaxIter) DO // 循环条件含硬上限，双保险 / loop condition carries the hard cap as a second safety
    nIter := nIter + 1; // 迭代计数递增 / increment the iteration counter

    // 段 4.1｜Horner 同步求 f(x) 与解析 f'(x)，单遍复杂度 O(n) / segment 4.1, Horner yields both value and analytic derivative in one pass
    lrFx := afCoef[DL_NR_ORD]; // 从最高幂次系数起步 / start from the highest order coefficient
    lrDf := 0.0; // 导数累加器清零 / reset the derivative accumulator
    nIdx := DL_NR_ORD - 1; // 从次高幂次开始递减 / start one order below the highest
    WHILE nIdx >= 0 DO // 显式递减，规避负步进 FOR 的可移植风险 / explicit decrement avoids the portability risk of negative-step FOR
        lrDf := lrDf * lrX + lrFx; // 导数 Horner 递推 / derivative Horner recursion
        lrFx := lrFx * lrX + afCoef[nIdx]; // 函数值 Horner 递推 / value Horner recursion
        nIdx := nIdx - 1; // 游标递减 / decrement the cursor
    END_WHILE

    // 段 4.2｜差分模式覆盖解析导数（外部两入口不可用时的替代通路）/ segment 4.2, difference mode overrides the analytic derivative as the fallback path
    IF bUseNumDiff THEN // 差分模式生效 / difference mode active
        lrFxH := afCoef[DL_NR_ORD]; // 差分点求值从最高幂次系数起步 / difference point evaluation starts from the highest coefficient
        nIdx  := DL_NR_ORD - 1; // 差分求值下标重新起步 / restart the index cursor for the shifted evaluation
        WHILE nIdx >= 0 DO // 差分点同构 Horner / identical Horner at the shifted point
            lrFxH := lrFxH * (lrX + lrHUse) + afCoef[nIdx]; // 以 x + h 为自变量求值 / evaluate at x plus h
            nIdx  := nIdx - 1; // 游标递减 / decrement the cursor
        END_WHILE
        lrDf := (lrFxH - lrFx) / lrHUse; // 前向差分导数，除子已钳定大于零 / forward difference derivative, divisor proven positive
    END_IF

    // 段 4.3｜非有限闸：函数值或导数非有限即判发散退出，出口保持上拍值 / segment 4.3, non-finite gate, exit on divergence and keep the last healthy outlet
    IF (lrFx <> lrFx) OR ((lrFx - lrFx) <> (lrFx - lrFx)) OR (lrDf <> lrDf) OR ((lrDf - lrDf) <> (lrDf - lrDf)) THEN // 值或导数 NaN 或无穷 / value or derivative is NaN or infinity
        eStatus := E_DL_NrStatus.eNonFinite; // 发散退出 / diverged exit
        bLoop   := FALSE; // 终止循环 / terminate the loop
    ELSE
        lrResidual := ABS(lrFx); // 残差取绝对值 / residual as an absolute value
        IF lrResidual <= lrTolUse THEN // 收敛出口 / convergence exit
            bConverged := TRUE; // 置收敛标志 / raise the converged flag
            eStatus    := E_DL_NrStatus.eOk; // 状态记收敛 / record the converged status
            bLoop      := FALSE; // 终止循环 / terminate the loop
        ELSIF ABS(lrDf) < lrEpsUse THEN // 导数近零出口 / derivative near-zero exit
            eStatus := E_DL_NrStatus.eDerivZero; // 方向不可用 / direction unusable
            bLoop   := FALSE; // 终止循环 / terminate the loop
        ELSE
            lrStep := -lrFx / lrDf; // 牛顿位移，除子绝对值已证不小于阈值 / Newton step, divisor magnitude proven not below the threshold
            IF lrStep > DL_NR_STEP_MAX THEN // 正越界 / positive overflow
                lrStep := DL_NR_STEP_MAX; // 上钳到步长上限 / clamp to the positive step cap
            ELSIF lrStep < -DL_NR_STEP_MAX THEN // 负越界 / negative overflow
                lrStep := -DL_NR_STEP_MAX; // 下钳到步长上限 / clamp to the negative step cap
            END_IF
            lrX := lrX + lrStep; // 推进迭代点 / advance the iterate
            IF (lrX <> lrX) OR ((lrX - lrX) <> (lrX - lrX)) THEN // 新点非有限 / new point non-finite
                eStatus := E_DL_NrStatus.eNonFinite; // 发散退出 / diverged exit
                bLoop   := FALSE; // 终止循环 / terminate the loop
            ELSE
                IF (nIter > 1) AND (lrResidual >= lrResPrev * 0.999) THEN // 残差无实质改善 / residual did not improve materially
                    nStall := nStall + 1; // 停滞计数递增 / increment the stall counter
                ELSE
                    nStall := 0; // 有改善则清零 / clear on improvement
                END_IF
                lrResPrev := lrResidual; // 更新残差快照 / refresh the residual snapshot
                IF nStall >= DL_NR_STALL_CAP THEN // 停滞达上限 / stall count reached the cap
                    eStatus := E_DL_NrStatus.eNoRoot; // 判停滞退出 / stalled exit
                    bLoop   := FALSE; // 终止循环 / terminate the loop
                END_IF
            END_IF
        END_IF
    END_IF
END_WHILE

// 段 5｜循环自然结束仍未收敛者判达上限（eOk 以外的既有状态不覆盖）/ segment 5, a natural loop end without convergence is an iteration-cap verdict, existing non-ok statuses are preserved
IF bLoop AND (NOT bConverged) AND (eStatus = E_DL_NrStatus.eOk) THEN // 循环用完次数且无其它出口 / iterations exhausted with no other exit
    eStatus := E_DL_NrStatus.eMaxIter; // 达上限未收敛 / cap reached without convergence
END_IF

// 段 6｜统一出口：有限性闸 + 根值交付 + 标志落定 / segment 6, unified outlet with finiteness gate, root delivery and flag settling
nIterUsed := nIter; // 迭代次数出口落定 / settle the iteration count outlet
bFinite   := (lrX = lrX) AND ((lrX - lrX) = (lrX - lrX)); // 根值有限性判定，NaN 用自反、无穷用差值自减 / root finiteness by self-inequality for NaN and self-difference for infinity
IF bFinite THEN // 根值有限 / root is finite
    FC_DL_NewtonRaphson := lrX; // 交付根值 / deliver the root
    bValid := bConverged OR (eStatus = E_DL_NrStatus.eNoRoot); // 收敛或停滞的有限根可交付，其余状态仅供诊断 / finite roots from convergence or stall are deliverable, other statuses are diagnostic only
ELSE
    FC_DL_NewtonRaphson := lrX0; // 非有限：退回初值，非有限值不穿透出口 / non-finite, fall back to the initial guess so nothing non-finite passes the outlet
    bValid := FALSE; // 出口不可用 / outlet unusable
END_IF
bError := NOT (eStatus = E_DL_NrStatus.eOk); // 任何非收敛状态均置错误标志，供上层判据 / any non-converged status raises the error flag for the upper layer
END_FUNCTION

(*
  ------------------------------------------------------------------
  FC_DL_NewtonStep —— 两入口推进单步（函数指针不可用时的配套入口）
  ------------------------------------------------------------------
  功能说明  : 供调用侧「两入口」使用：调用侧分别用自有 FC 算出 f(x) 与 f'(x)，
              把两个数值与本拍迭代点喂入本 FC，得到推进后的下一个迭代点。
              本 FC 无内部状态，调用侧持有循环与迭代上限（自身需另设硬上限）。
              与主入口同一套出口闸：值/导数非有限、导数近零、位移越界均拒绝推进。
  输出契约  : lrNextX 在拒推拍保持 lrX（不推进，等价于出口保持上拍值）；
              bStepOk 仅在本次推进合法时为 TRUE；eStatus 复用同一枚举。
  修订记录  : 2026-11-20 v1.0.0 R55 首版（与主入口同文件交付）
*)
FUNCTION FC_DL_NewtonStep : LREAL
VAR_INPUT
    lrX         : LREAL := 0.0;              // 当前迭代点 [无量纲] / current iterate [dimensionless]
    lrF         : LREAL := 0.0;              // 外部入口一算出的函数值 f(x) [无量纲] / function value from external entry one [dimensionless]
    lrDf        : LREAL := 0.0;              // 外部入口二算出的导数值 f'(x) [无量纲] / derivative value from external entry two [dimensionless]
    lrDerivEps  : LREAL := 1.0E-10;          // 导数近零阈值 [无量纲] / derivative near-zero threshold [dimensionless]
    lrStepMax   : LREAL := 1.0E9;            // 单步位移绝对上限 [无量纲] / single step absolute cap [dimensionless]
END_VAR
VAR_OUTPUT
    bStepOk     : BOOL := FALSE;             // 本次推进是否合法 [-] / whether this advance is legal
    eStatus     : E_DL_NrStatus := E_DL_NrStatus.eOk; // 推进结果状态 [枚举] / advance status [enum]
END_VAR
VAR
    lrStep      : LREAL := 0.0;              // 本步位移量 [无量纲] / current step [dimensionless]
    lrEps       : LREAL := 1.0E-10;          // 钳定后的导数阈值 [无量纲] / clamped derivative threshold [dimensionless]
    lrCap       : LREAL := 1.0E9;            // 钳定后的位移上限 [无量纲] / clamped step cap [dimensionless]
END_VAR
VAR CONSTANT
    DL_NS_EPS_MIN : LREAL := 1.0E-15;        // 导数阈值下限，防零阈致除零 [无量纲] / derivative threshold lower bound against division by zero
    DL_NS_CAP_MIN : LREAL := 1.0E-3;         // 位移上限下限，防零上限锁死推进 [无量纲] / step cap lower bound against a locked advance
END_VAR

// 段 1｜出口预置：默认不推进，保持传入迭代点 / segment 1, preset the outlet to no advance, keeping the incoming iterate
FC_DL_NewtonStep := lrX; // 拒推拍返回原点 / return the incoming point when the advance is rejected
bStepOk := FALSE; // 推进标志预置假 / preset the advance flag to false
eStatus := E_DL_NrStatus.eOk; // 状态预置收敛 / preset status to converged

// 段 2｜阈值与上限域闸 / segment 2, domain gate for the threshold and the cap
lrEps := lrDerivEps; // 阈值默认直通 / threshold passes through by default
IF lrEps <> lrEps THEN // 自反判 NaN / self-inequality detects NaN
    lrEps := DL_NS_EPS_MIN; // NaN 回落下限 / NaN falls back to the lower bound
END_IF
IF lrEps < DL_NS_EPS_MIN THEN // 阈值过小 / threshold too small
    lrEps := DL_NS_EPS_MIN; // 抬到下限 / raised to the lower bound
END_IF
lrCap := lrStepMax; // 位移上限默认直通 / step cap passes through by default
IF lrCap <> lrCap THEN // 自反判 NaN / self-inequality detects NaN
    lrCap := 1.0E9; // NaN 回落默认上限 / NaN falls back to the default cap
END_IF
IF lrCap < DL_NS_CAP_MIN THEN // 上限过小 / cap too small
    lrCap := DL_NS_CAP_MIN; // 抬到下限，防推进被锁死 / raised against a locked advance
END_IF

// 段 3｜三入口有限性闸：任一项非有限即拒绝推进 / segment 3, finiteness gate on all three inputs, any non-finite term rejects the advance
IF (lrX <> lrX) OR ((lrX - lrX) <> (lrX - lrX)) OR (lrF <> lrF) OR ((lrF - lrF) <> (lrF - lrF)) OR (lrDf <> lrDf) OR ((lrDf - lrDf) <> (lrDf - lrDf)) THEN // 任一项 NaN 或无穷 / any term is NaN or infinity
    eStatus := E_DL_NrStatus.eNonFinite; // 非有限拒绝 / rejected as non-finite
    RETURN; // 早退，出口保持传入点 / early exit with the outlet held at the incoming point
END_IF

// 段 4｜导数闸与位移限幅 / segment 4, derivative gate and step clamp
IF ABS(lrDf) < lrEps THEN // 导数近零 / derivative near zero
    eStatus := E_DL_NrStatus.eDerivZero; // 方向不可用 / direction unusable
    RETURN; // 早退，出口保持传入点 / early exit with the outlet held at the incoming point
END_IF
lrStep := -lrF / lrDf; // 牛顿位移，除子绝对值已证不小于阈值 / Newton step, divisor magnitude proven not below the threshold
IF lrStep > lrCap THEN // 正越界 / positive overflow
    lrStep := lrCap; // 上钳 / clamp upward
ELSIF lrStep < -lrCap THEN // 负越界 / negative overflow
    lrStep := -lrCap; // 下钳 / clamp downward
END_IF

// 段 5｜推进与结果有限性复检 / segment 5, advance and finiteness recheck
FC_DL_NewtonStep := lrX + lrStep; // 推进到下一个迭代点 / advance to the next iterate
IF (FC_DL_NewtonStep <> FC_DL_NewtonStep) OR ((FC_DL_NewtonStep - FC_DL_NewtonStep) <> (FC_DL_NewtonStep - FC_DL_NewtonStep)) THEN // 新点非有限 / new point non-finite
    eStatus := E_DL_NrStatus.eNonFinite; // 判发散 / diverged verdict
    FC_DL_NewtonStep := lrX; // 退回原迭代点 / fall back to the incoming iterate
    bStepOk := FALSE; // 推进标志保持假 / advance flag stays false
    RETURN; // 早退 / early exit
END_IF
bStepOk := TRUE; // 推进合法 / the advance is legal
eStatus := E_DL_NrStatus.eOk; // 状态记正常 / record the normal status
END_FUNCTION
