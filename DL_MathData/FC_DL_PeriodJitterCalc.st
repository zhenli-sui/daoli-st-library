(*
  Name        : FC_DL_PeriodJitterCalc
  Category    : DL_MathData
  Version     : 1.0.0
  Purpose     : 周期序列抖动统计（双精度数组）：均值、样本标准差（n-1 分母）、峰峰抖动（max-min）；/ Period-sequence jitter statistics over a double-precision array: mean, sample standard deviation (n-1) and peak-to-peak jitter (max-min)
  溯源        : 借 t2-1-lgf-math 的分类/参数域组织，clean-room 实现
  Boundary    : ① 计数域钳位：nCount 钳 0..64（容量常量），少于 2 个有效样本时 bValid = FALSE（样本标准差无定义），返回 0.0 哨兵；
                ② 入口有限性闸：任一被统计元素 NaN（x = x 自反）或 Inf（(x-x) = (x-x) 差判）→ 整体 bValid = FALSE（不静默跳过，防抖动被低估）；
                ③ 除零前置：均值除子为常量 1000 换算与 nCount（>= 2 已闸），标准差除子 nCount-1（>= 1 已闸）；
                ④ 数组下标游标 1..nCount 有界遍历（下标全量钳位），不越容量域；
                ⑤ 返回值 = 峰峰抖动 [s]，bValid = FALSE 时不得使用返回值（上层契约）。
*)
FUNCTION FC_DL_PeriodJitterCalc : LREAL
VAR_INPUT
    afPeriods : ARRAY[1..64] OF LREAL;       (* 周期样本数组（连续周期测量值）[s] / Period samples array *)
    nCount    : INT;                         (* 有效样本数，域 0..64（越域钳位）[个] / Valid sample count, clamped *)
END_VAR
VAR_OUTPUT
    fMean     : LREAL;                       (* 周期均值 [s] / Mean period *)
    fStdDev   : LREAL;                       (* 样本标准差（n-1 分母）[s] / Sample standard deviation *)
    bValid    : BOOL;                        (* 结果有效标志（FALSE 时返回值为哨兵零点）[-] / Result validity flag *)
END_VAR
VAR CONSTANT
    DL_PJC_NMAX  : INT   := 64;              (* 数组容量上限（与形参数组域一致）[个] / Array capacity *)
    DL_PJC_NMIN  : INT   := 2;               (* 样本数下限（标准差最少两点）[个] / Sample lower bound *)
    DL_PJC_EPS   : LREAL := 1.0E-12;         (* 双精度判零容差 [s] / Double-precision epsilon *)
    DL_PJC_ONE   : LREAL := 1.0;             (* 游标递进常量 [-] / Cursor step constant *)
END_VAR
VAR
    _nEff  : INT;                            (* 钳位后生效样本数 [个] / Effective sample count *)
    _nIdx  : INT;                            (* 统计游标（每趟重置，R227）[-] / Stats cursor *)
    _fSum  : LREAL;                          (* Σx 中间量 [s] / Sum intermediate *)
    _fMeanI: LREAL;                          (* 均值中间量 [s] / Mean intermediate *)
    _fVar  : LREAL;                          (* Σ(x-x̄)² 中间量 [s²] / Squared-deviation sum *)
    _fStdI : LREAL;                          (* 标准差中间量 [s] / Std intermediate *)
    _fMin  : LREAL;                          (* 样本最小值 [s] / Sample minimum *)
    _fMax  : LREAL;                          (* 样本最大值 [s] / Sample maximum *)
    _bFin  : BOOL;                           (* 全体样本有限性当拍量 / Joint sample finiteness *)
END_VAR

(* —— 段 0：计数域钳位 + 有限性预置 —— *)
bValid := TRUE;                                                                (* 有效标志预置（任一闸命中即翻 FALSE） / Validity preset *)
_nEff := nCount;                                                               (* 生效样本数初值 / Effective count init *)
IF _nEff < 0 THEN
    _nEff := 0;                                                                (* 计数下限钳 0 / Lower clamp *)
END_IF
IF _nEff > DL_PJC_NMAX THEN
    _nEff := DL_PJC_NMAX;                                                      (* 计数上限钳容量（下标全量钳位） / Upper clamp to capacity *)
END_IF

(* —— 段 1：样本数下限闸（少于 2 点标准差无定义，边界①） —— *)
IF _nEff < DL_PJC_NMIN THEN
    bValid := FALSE;                                                           (* 样本不足：整体无效 / Insufficient samples *)
END_IF

(* —— 段 2：入口有限性闸（逐元素 NaN 自反 + Inf 差判，任一非有限整体拒判，边界②） —— *)
IF bValid THEN
    _bFin := TRUE;                                                             (* 有限性联合量预置 / Finiteness preset *)
    _nIdx := 1;                                                                (* 游标起头 / Cursor reset *)
    WHILE _nIdx <= _nEff DO
        IF NOT ((afPeriods[_nIdx] = afPeriods[_nIdx])                          (* NaN 自反闸 / NaN reflex gate *)
                AND ((afPeriods[_nIdx] - afPeriods[_nIdx]) = (afPeriods[_nIdx] - afPeriods[_nIdx]))) THEN
            _bFin := FALSE;                                                    (* 命中非有限样本 / Non-finite sample hit *)
        END_IF
        _nIdx := _nIdx + DL_PJC_ONE;                                           (* 游标递进（有界遍历） / Cursor advance *)
    END_WHILE
    IF NOT _bFin THEN
        bValid := FALSE;                                                       (* 整体无效（不静默跳过） / Overall invalid *)
    END_IF
END_IF

(* —— 段 3：无效输入早退（出口归零 + 哨兵零点返回） —— *)
IF NOT bValid THEN
    fMean := 0.0;                                                              (* 清均值出口 / Clear mean outlet *)
    fStdDev := 0.0;                                                            (* 清标准差出口 / Clear std outlet *)
    FC_DL_PeriodJitterCalc := 0.0;                                             (* 哨兵零点返回 / Sentinel zero return *)
    RETURN;
END_IF

(* —— 段 4：一趟求 Σx/min/max —— *)
_fSum := 0.0;                                                                  (* Σx 预清 / Sum preset *)
_fMin := afPeriods[1];                                                         (* 最小值初值取首样本 / Min init *)
_fMax := afPeriods[1];                                                         (* 最大值初值取首样本 / Max init *)
_nIdx := 1;                                                                    (* 游标起头（R227） / Cursor reset *)
WHILE _nIdx <= _nEff DO
    _fSum := _fSum + afPeriods[_nIdx];                                         (* Σx [s] / Sum *)
    IF afPeriods[_nIdx] < _fMin THEN
        _fMin := afPeriods[_nIdx];                                             (* 更新最小值 / Update min *)
    END_IF
    IF afPeriods[_nIdx] > _fMax THEN
        _fMax := afPeriods[_nIdx];                                             (* 更新最大值 / Update max *)
    END_IF
    _nIdx := _nIdx + DL_PJC_ONE;                                               (* 游标递进 / Cursor advance *)
END_WHILE

(* —— 段 5：均值与标准差（除子均已过闸，边界③） —— *)
_fMeanI := _fSum / INT_TO_LREAL(_nEff);                                        (* 均值：除子 nEff >= 2 [s] / Mean, divisor >= 2 *)
fMean := _fMeanI;                                                              (* 均值出口 / Mean outlet *)
_fVar := 0.0;                                                                  (* 平方和预清 / Squares preset *)
_nIdx := 1;                                                                    (* 游标重起 / Cursor reset *)
WHILE _nIdx <= _nEff DO
    _fVar := _fVar + (afPeriods[_nIdx] - _fMeanI) * (afPeriods[_nIdx] - _fMeanI);   (* 平方项恒非负 [s²] / Squared deviation *)
    _nIdx := _nIdx + DL_PJC_ONE;                                               (* 游标递进 / Cursor advance *)
END_WHILE
_fStdI := SQRT(_fVar / INT_TO_LREAL(_nEff - 1));                               (* 样本标准差：除子 nEff-1 >= 1 [s] / Sample std, divisor >= 1 *)
fStdDev := _fStdI;                                                             (* 标准差出口 / Std outlet *)

(* —— 段 6：返回峰峰抖动（max-min，无除法） —— *)
FC_DL_PeriodJitterCalc := _fMax - _fMin;                                       (* 峰峰抖动返回 [s] / Peak-to-peak jitter return *)
END_FUNCTION
