(*
  FB_DL_PouchSwellingGauge  —  软包电芯鼓胀厚度巡检分级 / Pouch cell swelling thickness gauge and grading
  分类 Category : DL_Device
  码位 Code     : 16#03_2_15
  段位说明      : 03_2 段低半字节 00~0F 已满（05 为历史空穴留存），进位 15 段续号（R192）
  版本 Version  : 1.0.0
  来源 Source   : t2-1-lgf-measurement — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : clean-room 实现，Welford 在线方差递推公开算法语义，未复制任何源码行
                  （统计语义对齐 FB_DL_SignalStatistics；分级语义对齐 FC_DL_LimitClassify，均不实例化）
  功能 Function : 1) 厚度归一（fThicknessMm − fZeroOffsetMm）后按批 Welford 递推均值/标准差（防大数累加误差）；
                  2) 单件双口径分级：绝对限 fAbsLimitMm 与 Z 分数 |x − mean|/σ > fZScoreLimit，越限立置 abItemNg[k]；
                  3) 批内一致性评价：σ > fBatchSigmaLimitMm 判 bBatchAbnormal（判据取「批内异常」而非单件越限）；
                  4) 批尾自动清零（计数/均值/NG 位全清，下批重来）。
  边界 Boundary : ① fAbsLimitMm <= 0 或 nBatchSize < 2（无法算 σ）判组态错；
                  ② nBatchSize > 数组上界按 MIN 钳制并置信息码（禁 TRUNC(x)+1 型写法，R28-2）；
                  ③ 批内 σ < 1E-6 mm 时 Z 分数不计算、只走绝对限（防除零）；
                  ④ fThicknessMm 非有限（NaN 用 x<>x 自反）判信号无效置码且不纳入统计（不污染均值）；
                  ⑤ 单件越限立刻置 abItemNg[k] 且本件锁存至批尾（解除式 = 批尾清零，可由 nBatchSize 满足）；
                  ⑥ 无状态机：统计件无 ENUM/CASE，判据均为每拍重算或批内锁存（批尾清零承载解除）。
  依赖 Depends  : 仅 Standard.library（ABS/SQRT/MIN）；语义对齐 FB_DL_SignalStatistics / FC_DL_LimitClassify（已注册）
  码表 Error codes（本件格 03_2_15，子码步进 +0x100）:
    16#0003_0115 信息级：批尾清零（批次评价已给出，不置故障）
    16#0003_0215 故障级：组态非法（绝对限 <= 0 / 批容量 < 2）
    16#0003_0315 信息级：批容量超数组上界，已按 MIN 钳制
    16#0003_0415 信息级：测量值非有限（NaN/Inf），本件不纳入统计
    16#0003_0515 信息级：批内 σ 近零，Z 分数不计算只走绝对限
    16#0003_0615 故障级：批内异常（σ 越限，批内一致性判废）

  修订历史 Revision :
    2026-11-18  v1.0.0  R38 首版
*)

FUNCTION_BLOCK FB_DL_PouchSwellingGauge
VAR_INPUT
    fThicknessMm       : REAL := 0.0;      // 测厚原始值 [mm] / Raw thickness measurement
    fZeroOffsetMm      : REAL := 0.0;      // 零点偏移 [mm] / Zero offset
    fAbsLimitMm        : REAL := 5.0;      // 绝对上限 [mm]，域 > 0 / Absolute thickness ceiling
    nBatchSize         : INT   := 32;      // 批内样本数上限 [件]，域 >= 2 / Batch size ceiling
    fBatchSigmaLimitMm : REAL := 0.05;     // 批内离散度上限 [mm]，域 > 0 / Batch sigma limit
    fZScoreLimit       : REAL := 4.0;      // Z 分数判废限 [无量纲]，域 > 0 / Z-score scrap limit
END_VAR
VAR_OUTPUT
    fThicknessNormMm   : REAL;             // 归一厚度 [mm] = 原始 − 零偏 / Normalized thickness
    fBatchMeanMm       : REAL;             // 批内均值 [mm] / Batch running mean
    fBatchSigmaMm      : REAL;             // 批内标准差 [mm] / Batch running sigma
    abItemNg           : ARRAY[0..63] OF BOOL;   // 逐件 NG 锁存（批尾清零）/ Per-item NG latch, cleared at batch end
    bItemNg            : BOOL;             // 本件 NG（每拍重算）/ Current item NG
    bBatchAbnormal     : BOOL;             // 批内异常（σ 越限，批尾结算）/ Batch abnormal verdict
    nErrId             : UDINT;            // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    _nCount   : INT;                     // 批内已收件数 [件] / Items collected in batch
    _nIdx     : INT;                     // 当前件序号 [0..63] / Current item index
    _nEffBatch: INT;                     // 生效批容量（钳制后）[件] / Effective batch capacity
    _rMean    : LREAL;                   // Welford 均值 / Welford mean
    _rM2      : LREAL;                   // Welford M2 累计 / Welford M2 accumulator
    _rDelta   : LREAL;                   // Welford 增量暂存 / Welford delta scratch
    _rSigma   : LREAL;                   // 批内 σ 暂存 / Batch sigma scratch
    _rX       : LREAL;                   // 归一值宽域暂存 / Normalized value scratch
    _bClamped : BOOL;                    // 批容量钳制标志（每拍重算）/ Capacity clamped flag
    _uInfo    : UDINT;                   // 信息码，每拍重算 / Info code
    _bCfgBad  : BOOL;                    // 组态非法聚合 / Configuration invalid aggregate
    _k        : INT;                     // 批尾清零循环计数 / Batch-clear loop counter
END_VAR
VAR CONSTANT
    nMaxItems : INT   := 64;      // NG 数组上界 [件] / NG array upper bound
    rSigFloor : LREAL := 1.0E-6;  // σ 近零阈值 [mm] / Near-zero sigma floor
    rFinLim   : REAL  := 1.0E15;  // 非有限值筛查幅值上限 / Non-finite screening cap
END_VAR

(* —— 段 1：单拍量预清零与组态闸（统计件，锁存量 _nCount/_rMean/_rM2/abItemNg 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;         // 信息码每拍重算
bItemNg := FALSE;               // 本件 NG 缺省 FALSE
_bCfgBad := FALSE;              // 组态非法预清零
_bClamped := FALSE;             // 钳制标志预清零
nErrId := 16#0000_0000;         // 事件码缺省无事件

IF (fAbsLimitMm <> fAbsLimitMm) OR (fAbsLimitMm <= 0.0) THEN
    _bCfgBad := TRUE;           // 绝对限非法
END_IF
IF (fBatchSigmaLimitMm <> fBatchSigmaLimitMm) OR (fBatchSigmaLimitMm <= 0.0)
   OR (fZScoreLimit <= 0.0) THEN
    _bCfgBad := TRUE;           // 离散度限/Z 限非法
END_IF
IF nBatchSize < 2 THEN
    _bCfgBad := TRUE;           // 批容量 < 2 无法算 σ（规格强制）
END_IF
IF _bCfgBad THEN
    nErrId := 16#0003_0215;     // 故障级：组态非法
    RETURN;                     // 不进入统计（出口维持安全缺省）
END_IF

IF nBatchSize > nMaxItems THEN
    _nEffBatch := nMaxItems;    // MIN 取上界钳制（禁 TRUNC(x)+1 型写法）
    _bClamped := TRUE;          // 钳制标志
    _uInfo := 16#0003_0315;     // 信息级：批容量已钳制
ELSE
    _nEffBatch := nBatchSize;   // 域内直接生效
END_IF

(* —— 段 2：归一厚度与非有限筛查（NaN 用 x<>x 自反判定） —— *)
fThicknessNormMm := fThicknessMm - fZeroOffsetMm;    // 归一厚度
_rX := LREAL(fThicknessNormMm);
IF (_rX <> _rX) OR (ABS(_rX) > LREAL(rFinLim)) THEN
    _uInfo := 16#0003_0415;     // 信息级：测量非有限，不纳入统计（不污染均值）
    RETURN;                     // 本拍结束（统计量维持）
END_IF

(* —— 段 3：Welford 递推（防大数累加误差）与单件双口径分级 —— *)
IF _nCount < _nEffBatch THEN
    _nCount := _nCount + 1;                 // 收件计数（上限由条件守，不回绕）
    _rDelta := _rX - _rMean;                // 增量
    _rMean  := _rMean + _rDelta / LREAL(_nCount);      // 均值递推（计数 >= 1，无除零）
    _rM2    := _rM2 + _rDelta * (_rX - _rMean);        // M2 递推
END_IF
fBatchMeanMm := REAL(_rMean);               // 均值出口

IF _nCount >= 2 THEN
    _rSigma := SQRT(_rM2 / LREAL(_nCount - 1));        // 批内 σ（样本方差，分母 >= 1）
    fBatchSigmaMm := REAL(_rSigma);                    // σ 出口
END_IF

(* —— 段 4：单件双口径分级（绝对限 + Z 分数，σ 近零只走绝对限） —— *)
IF _rX > LREAL(fAbsLimitMm) THEN
    bItemNg := TRUE;                        // 绝对限越限
END_IF
IF (_nCount >= 2) AND (_rSigma >= rSigFloor) THEN
    IF ABS(_rX - _rMean) / _rSigma > LREAL(fZScoreLimit) THEN
        bItemNg := TRUE;                    // Z 分数越限
    END_IF
ELSIF (_nCount >= 2) AND (_rSigma < rSigFloor) THEN
    _uInfo := 16#0003_0515;     // 信息级：σ 近零只走绝对限（防除零）
END_IF
IF bItemNg THEN
    _nIdx := MIN(_nCount - 1, nMaxItems - 1);   // 件序号钳制（防越界）
    abItemNg[_nIdx] := TRUE;                    // 越限立刻置位并锁存至批尾（解除式 = 批尾清零）
END_IF

(* —— 段 5：批尾结算与清零（批容量到点：先评价后清零） —— *)
IF _nCount >= _nEffBatch THEN
    IF _rSigma > LREAL(fBatchSigmaLimitMm) THEN
        bBatchAbnormal := TRUE;             // 批内异常：σ 越限（判据取批内一致性）
        _uInfo := 16#0003_0615;             // 故障级：批内异常（信息通道承载判废结论）
    ELSE
        bBatchAbnormal := FALSE;            // 批内一致
    END_IF
    _uInfo := 16#0003_0115;     // 信息级：批尾清零
    _nCount := 0;               // 计数清零
    _rMean  := 0.0;             // 均值清零
    _rM2    := 0.0;             // M2 清零
    _rSigma := 0.0;             // σ 暂存清零
    fBatchMeanMm := 0.0;        // 统计出口复位
    fBatchSigmaMm := 0.0;
    FOR _k := 0 TO (nMaxItems - 1) DO
        abItemNg[_k] := FALSE;  // 逐件 NG 锁存批尾清零（解除式自证路径）
    END_FOR
END_IF

(* —— 段 6：出口单点映射 —— *)
IF bBatchAbnormal THEN
    nErrId := 16#0003_0615;     // 批内异常判废码（结算拍回放）
ELSIF _uInfo <> 16#0000_0000 THEN
    nErrId := _uInfo;           // 信息码
END_IF

END_FUNCTION_BLOCK
