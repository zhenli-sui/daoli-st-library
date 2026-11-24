(*
  ==================================================================
  组件名 Component  : FC_DL_SolveLinear3
  分类   Category   : DL_MathData
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : 三阶线性方程组 A·x = b 求解。部分主元高斯消元（行选
                      最大主元 + 行交换）+ 相对奇异判据（主元绝对值 < 相对
                      容差 × 系数矩阵最大绝对值判奇异）+ 非有限入参闸。
                      与 FC_DL_Matrix3Inverse 分工互引：本件直接解 Ax=b，
                      后者求显式逆矩阵。
  来源   Source     : t2-1-lgf-math（公开数值教材 clean-room）
  溯源   Origin     : 部分主元高斯消元为公开数值教材算法，clean-room 自研
                      实现，未复制任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
  分工声明 Split     : 与 FC_DL_Matrix3Inverse 分工——Matrix3Inverse 输出显式
                      逆矩阵供多次多右端项复用；本件单次单右端项直接求解，
                      不输出逆矩阵，不做行列式出口。
  作者   Author     : 道莅代码库 · PLC 编程专家（R58）
  ------------------------------------------------------------------
  功能说明  : 四段式防御（R45）：预置 → 非有限 / 奇异域闸 → 域内消元回代 →
              结果非有限复检兜底。消元全程行交换受固定三阶界约束（无死循环
              风险）；除子均为已证非零的主元或主元相对容差护栏。
  修订记录  : 2026-11-21 v1.0.0 首次入库（R58 批 2 · 序号 5）
*)
FUNCTION FC_DL_SolveLinear3 : BOOL
VAR_IN_OUT
    aA : ARRAY[0..2, 0..2] OF LREAL; // 系数矩阵 A [混合]，消元不改写调用方副本 / the coefficient matrix A, the caller copy untouched
    afB : ARRAY[0..2] OF LREAL;      // 右端向量 b [混合] / the right hand vector b
END_VAR
VAR_OUTPUT
    afX    : ARRAY[0..2] OF LREAL; // 解向量 x [混合] / the solution vector x
    bSingular : BOOL;              // 奇异判定（相对判据命中）[-] / the singular verdict by the relative criterion
    bNonFinite: BOOL;              // 入参非有限判定 [-] / the non finite input verdict
END_VAR
VAR
    afW   : ARRAY[0..2, 0..2] OF LREAL; // 工作系数副本 [混合] / the working coefficient copy
    afR   : ARRAY[0..2] OF LREAL;       // 工作右端副本 [混合] / the working right hand copy
    nI    : DINT;   // 行遍历索引 [行] / the row loop index
    nJ    : DINT;   // 列遍历索引 [列] / the column loop index
    nK    : DINT;   // 消元内层索引 [行] / the elimination inner index
    nPiv  : DINT;   // 主元行索引 [行] / the pivot row index
    lrMaxA: LREAL;  // 系数矩阵最大绝对值 [混合] / the max absolute coefficient
    lrPiv : LREAL;  // 当前主元值 [混合] / the current pivot value
    lrTmp : LREAL;  // 交换与消元工作量 [混合] / the swap and elimination work value
    lrFac : LREAL;  // 消元因子 [无量纲] / the elimination factor
    lrSum : LREAL;  // 回代累加工作量 [混合] / the back substitution sum
END_VAR
VAR CONSTANT
    DL_SL3_REL_EPS : LREAL := 1.0E-12; // 相对奇异容差 [无量纲] / the relative singularity tolerance
END_VAR

// 段 1｜返回值与错误状态预置安全值（四段式第一段，R45）/ segment 1, preset the return and error states
FC_DL_SolveLinear3 := FALSE; // 受理标志预置假 / preset the accepted flag false
bSingular := FALSE; // 奇异标志预置假 / preset the singular flag false
bNonFinite := FALSE; // 非有限标志预置假 / preset the non finite flag false
afX[0] := 0.0; // 解向量预置零（分量一）/ preset the solution zero, the entry one
afX[1] := 0.0; // 解向量预置零（分量二）/ preset the solution zero, the entry two
afX[2] := 0.0; // 解向量预置零（分量三）/ preset the solution zero, the entry three

// 段 2｜非有限入参闸（自反双判据全覆盖 12 个量，R79 / R151）/ segment 2, the non finite input gate over all twelve entries
FOR nI := 0 TO 2 DO // 行遍历 / the row loop
    IF (afB[nI] <> afB[nI]) OR ((afB[nI] - afB[nI]) <> (afB[nI] - afB[nI])) THEN // 右端非有限 / a non finite right hand
        bNonFinite := TRUE; // 置非有限标志 / raise the non finite flag
    END_IF
    FOR nJ := 0 TO 2 DO // 列遍历 / the column loop
        IF (aA[nI, nJ] <> aA[nI, nJ]) OR ((aA[nI, nJ] - aA[nI, nJ]) <> (aA[nI, nJ] - aA[nI, nJ])) THEN // 系数非有限 / a non finite coefficient
            bNonFinite := TRUE; // 置非有限标志 / raise the non finite flag
        END_IF
    END_FOR
END_FOR
IF bNonFinite THEN // 非有限命中：返回预置安全解 / a non finite hit, return the preset safe solution
    RETURN; // 早退（解向量保持预置零）/ return early with the preset zero
END_IF

// 段 3｜工作副本装填 + 矩阵最大绝对值（相对奇异判据基准）/ segment 3, the working copies and the max absolute coefficient
lrMaxA := 0.0; // 基准预置零 / preset the base zero
FOR nI := 0 TO 2 DO // 行遍历 / the row loop
    afR[nI] := afB[nI]; // 装右端副本 / load the right hand copy
    FOR nJ := 0 TO 2 DO // 列遍历 / the column loop
        afW[nI, nJ] := aA[nI, nJ]; // 装系数副本 / load the coefficient copy
        IF ABS(aA[nI, nJ]) > lrMaxA THEN // 更新最大绝对值 / update the max absolute
            lrMaxA := ABS(aA[nI, nJ]); // 记录基准 / record the base
        END_IF
    END_FOR
END_FOR

// 段 4｜部分主元前向消元（行选最大主元 + 行交换，固定三阶界）/ segment 4, the partial pivot forward elimination
FOR nK := 0 TO 1 DO // 消元主列遍历（末列免消）/ the pivot column loop
    nPiv := nK; // 主元行预置当前行 / preset the pivot row
    lrPiv := ABS(afW[nK, nK]); // 当前主元绝对值 / the current pivot magnitude
    FOR nI := nK + 1 TO 2 DO // 候选行遍历 / the candidate row loop
        IF ABS(afW[nI, nK]) > lrPiv THEN // 更大候选主元 / a larger candidate pivot
            nPiv := nI; // 更新主元行 / update the pivot row
            lrPiv := ABS(afW[nI, nK]); // 更新主元值 / update the pivot value
        END_IF
    END_FOR
    IF lrPiv < (DL_SL3_REL_EPS * lrMaxA) THEN // 相对奇异判据命中 / the relative singularity hit
        bSingular := TRUE; // 置奇异标志 / raise the singular flag
        RETURN; // 早退（解向量保持预置零）/ return early with the preset zero
    END_IF
    IF nPiv <> nK THEN // 需要行交换 / a row swap needed
        FOR nJ := 0 TO 2 DO // 交换系数行 / swap the coefficient rows
            lrTmp := afW[nK, nJ]; // 暂存行 K / hold row K
            afW[nK, nJ] := afW[nPiv, nJ]; // 主元行上调 / the pivot row up
            afW[nPiv, nJ] := lrTmp; // 原行落位 / the old row down
        END_FOR
        lrTmp := afR[nK]; // 交换右端同行 / swap the right hand
        afR[nK] := afR[nPiv]; // 右端同步 / sync the right hand
        afR[nPiv] := lrTmp; // 右端落位 / settle the right hand
    END_IF
    FOR nI := nK + 1 TO 2 DO // 下方行消元 / eliminate the rows below
        lrFac := afW[nI, nK] / afW[nK, nK]; // 消元因子（主元已证过容差闸）/ the elimination factor
        FOR nJ := nK TO 2 DO // 行内系数更新 / update the row coefficients
            afW[nI, nJ] := afW[nI, nJ] - lrFac * afW[nK, nJ]; // 系数消元 / eliminate the coefficient
        END_FOR
        afR[nI] := afR[nI] - lrFac * afR[nK]; // 右端消元 / eliminate the right hand
    END_FOR
END_FOR
IF ABS(afW[2, 2]) < (DL_SL3_REL_EPS * lrMaxA) THEN // 末主元相对奇异复检 / the last pivot relative singularity recheck
    bSingular := TRUE; // 置奇异标志 / raise the singular flag
    RETURN; // 早退 / return early
END_IF

// 段 5｜回代求解（除子均为主元，已证过容差闸）/ segment 5, the back substitution
FOR nI := 2 TO 0 BY -1 DO // 自下而上回代（DINT 递减步进固定界）/ the upward back substitution with a fixed bound
    lrSum := afR[nI]; // 右端起算 / start from the right hand
    FOR nJ := nI + 1 TO 2 DO // 已解分量累加 / accumulate the solved entries
        lrSum := lrSum - afW[nI, nJ] * afX[nJ]; // 扣已解项 / subtract the solved term
    END_FOR
    afX[nI] := lrSum / afW[nI, nI]; // 解出本分量（主元已证）/ solve the entry
END_FOR

// 段 6｜结果非有限复检兜底（防御纵深，正常路径不可达）/ segment 6, the result recheck as defense in depth
FOR nI := 0 TO 2 DO // 分量遍历 / the entry loop
    IF (afX[nI] <> afX[nI]) OR ((afX[nI] - afX[nI]) <> (afX[nI] - afX[nI])) THEN // 解分量非有限 / a non finite solution entry
        afX[nI] := 0.0; // 分量归零兜底 / zero the entry
        FC_DL_SolveLinear3 := FALSE; // 不予受理 / refuse the acceptance
        RETURN; // 早退 / return early
    END_IF
END_FOR
FC_DL_SolveLinear3 := TRUE; // 求解受理 / accept the solution
END_FUNCTION
