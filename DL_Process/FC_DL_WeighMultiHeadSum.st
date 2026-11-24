(*
  ============================================================
  组件名 : FC_DL_WeighMultiHeadSum
  分类   : DL_Process
  功能   : 多头组合称重穷举，选出不低于目标欠量下限且偏差最小的头组合位图
  开源溯源 : internal-design（本轮无外部代码逐行引用）
             参考语义 : 无外部参考
  复杂度 : C2
  版本   : 1.0.0
  ============================================================
*)

FUNCTION FC_DL_WeighMultiHeadSum : REAL
VAR_INPUT
    aWeight   : ARRAY[0..7] OF REAL; // 八只称重头实测值 [kg] measured weights of eight heads [kg]
    nHeads    : INT; // 参与组合的头数 1~8 [个] engaged head count from one to eight [count]
    rTarget   : REAL; // 目标组合重量 [kg] target combination weight [kg]
    rAllowTol : REAL; // 允许欠量容差 [kg] allowed under weight tolerance [kg]
END_VAR
VAR_OUTPUT
    rBestSum   : REAL; // 最优组合和 [kg] best combination sum [kg]
    nBestMask  : INT; // 最优组合位图 [位图] best combination bit mask [bit map]
    nBestCount : INT; // 最优组合头数 [个] head count of the best combination [count]
    bValid     : BOOL; // 结果有效标志 result validity flag
END_VAR
VAR
    nMask  : INT := 0; // 组合位图游标 [位图] combination mask cursor [bit map]
    nBit   : INT := 0; // 位游标 0~7 [位] bit cursor from zero to seven [bit]
    nRem   : INT := 0; // 位图右移余量 [位图] mask remainder while shifting [bit map]
    nCnt   : INT := 0; // 当前组合头数 [个] head count of the current mask [count]
    rSum   : REAL := 0.0; // 当前组合和 [kg] sum of the current mask [kg]
    rBest  : REAL := 0.0; // 当前最优组合和 [kg] best sum found so far [kg]
    rErr   : REAL := 0.0; // 当前组合偏差绝对值 [kg] absolute deviation of the current mask [kg]
    rMin   : REAL := 0.0; // 当前最小偏差绝对值 [kg] smallest absolute deviation so far [kg]
    rFloor : REAL := 0.0; // 允许的组合和下限 [kg] lower admissible sum [kg]
    bHit   : BOOL := FALSE; // 找到候选组合标志 candidate found flag
    _bFin  : BOOL := FALSE; // 实数输入有限性判定 finiteness verdict of the real inputs
END_VAR

// 段 1｜出口预置 preset the exit
FC_DL_WeighMultiHeadSum := 0.0; // 缺省返回零 default zero return
rBestSum := 0.0; // 最优和预置零 best sum preset to zero
nBestMask := 0; // 位图预置零 bit mask preset to zero
nBestCount := 0; // 头数预置零 head count preset to zero
bValid := FALSE; // 计算完成前不认结果 unusable before the calculation
// 段 2｜头数闸与有限闸 head count gate and finiteness gate
_bFin := (rTarget = rTarget) AND (rAllowTol = rAllowTol); // 两实数输入自反判定 self comparison of both real inputs
IF (NOT _bFin) OR (nHeads < 1) OR (nHeads > 8) THEN
    RETURN; // 头数越界或非有限即无效 an out of range head count or a non finite input is void
END_IF
rFloor := rTarget - ABS(rAllowTol); // 允许下限取容差幅值 the floor uses the tolerance magnitude
// 段 3｜穷举 255 个非零组合 exhaustive walk of two hundred fifty five non empty masks
FOR nMask := 1 TO 255 DO
    nCnt := 0; // 组合头数清零 clear the head count
    rSum := 0.0; // 组合和清零 clear the sum
    nRem := nMask; // 余量取位图 the remainder starts from the mask
    FOR nBit := 0 TO 7 DO
        IF ((nRem MOD 2) = 1) AND (nBit < nHeads) THEN
            nCnt := nCnt + 1; // 头数累加 accumulate the head count
            rSum := rSum + aWeight[nBit]; // 重量累加 accumulate the weight
        END_IF
        nRem := nRem / 2; // 整数除二右移一位 integer division by two shifts one bit
    END_FOR
    // 段 4｜候选判据与最优保持 candidate verdict and the best hold
    IF (nCnt > 0) AND (rSum >= rFloor) THEN
        rErr := ABS(rSum - rTarget); // 组合偏差绝对值 absolute deviation of the mask
        IF (NOT bHit) OR (rErr < rMin) THEN
            rMin := rErr; // 更新最小偏差 refresh the smallest deviation
            rBest := rSum; // 更新最优组合和 refresh the best sum
            nBestMask := nMask; // 更新最优位图 refresh the best mask
            nBestCount := nCnt; // 更新最优头数 refresh the best head count
            bHit := TRUE; // 置候选命中标志 raise the candidate flag
        END_IF
    END_IF
END_FOR
// 段 5｜出口与命中判定 the exit and the hit verdict
IF bHit THEN
    rBestSum := rBest; // 最优和落定 land the best sum
    bValid := TRUE; // 结果可用 result usable
    FC_DL_WeighMultiHeadSum := rBest; // 函数返回最优和 return the best sum
END_IF
END_FUNCTION
