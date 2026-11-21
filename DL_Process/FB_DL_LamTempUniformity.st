(*
  FB_DL_LamTempUniformity  —  层压板面多测点温度均匀性诊断 / Laminator plate multi-point temperature uniformity diagnostics
  分类 Category : DL_Process
  码位 Code     : 16#06_0_87
  版本 Version  : 1.0.0
  溯源 Source   : LGF Measurement 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 多测点（1..8）温度极差与样本标准差双判据诊断板面均匀性；
                  2) 任一测点失效（无效/NaN/域外）从统计中剔除并在掩码标出，绝不以 0 degC 充当有效值；
                  3) 有效测点 < 2 时不出极差结论（单点极差恒 0 会误判均匀），只报信息级码。
  边界 Boundary : ① 测点数 < 2 不出极差结论；
                  ② 任一测点失效从统计剔除并在掩码标出（禁 0 degC 充当有效值）；
                  ③ 均匀性门限按工艺窗口给常量（VAR CONSTANT），禁写裸数值；
                  ④ 结论三行同向：均值 → 极差 → 均匀标志。
  依赖 Depends  : FB_DL_SignalStatistics（极差稳定性趋势统计，每拍无条件调用）

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_0687 故障级：测点配置越界（nPointCount 不在 1..8）
    16#0002_0697 故障级：有效测点数为 0（全部失效，无法出任何结论）
    16#0002_06A7 信息级：有效测点 < 2，不出极差结论（不置 bError）
*)

TYPE E_DL_LtuPhase :
(
    eIdle    := 0,   // 空闲 / Idle
    eCollect := 10,  // 测点采集 / Point sampling
    eJudge   := 20,  // 判据计算 / Criterion evaluation
    eVerdict := 30,  // 结论输出 / Verdict output
    eFault   := 90   // 故障锁定 / Fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_LamTempUniformity
VAR_INPUT
    bEnable      : BOOL;                          // 总使能，FALSE 回空闲 / Master enable
    bSample      : BOOL := TRUE;                  // 采样使能，TRUE 每拍更新结论 / Sampling enable
    bReset       : BOOL;                          // 复位，上升沿清故障与趋势窗 / Reset
    nPointCount  : INT := 4;                      // 测点总数 [点]，域 1~8 / Point count, 1..8
    afTempC      : ARRAY[1..8] OF REAL;           // 各测点温度 [degC]，域 −20~400 / Per-point temperature [degC]
    abPointValid : ARRAY[1..8] OF BOOL;           // 各测点通道有效标志 / Per-point channel valid flag
END_VAR
VAR_OUTPUT
    fMeanC       : REAL;                          // 有效测点温度均值 [degC] / Mean over valid points [degC]
    fRangeC      : REAL;                          // 极差（最大 − 最小）[degC] / Peak-to-peak [degC]
    fStdDevC     : REAL;                          // 样本标准差（n−1）[degC] / Sample standard deviation [degC]
    nValidPts    : INT;                           // 有效测点数 [点] / Valid point count
    abValidMask  : ARRAY[1..8] OF BOOL;           // 有效测点掩码 [开关]，索引 = 物理测点号 / Valid point mask
    bUniform     : BOOL;                          // 均匀合格（极差与标准差双判据均过）/ Uniform, both criteria pass
    bWarn        : BOOL;                          // 均匀性告警（保持型）/ Uniformity warning, held
    bError       : BOOL;                          // 故障标志，与故障级码配对 / Fault flag paired with fault codes
    uErrorId     : UDINT;                         // 事件码，0 = 无事件 / Event code, 0 = none
    eStateOut    : E_DL_LtuPhase;                 // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState      : E_DL_LtuPhase := E_DL_LtuPhase.eIdle;  // 内部状态 / Internal state
    rtrReset     : R_TRIG;                        // 复位沿 / Reset edge
    statRange    : FB_DL_SignalStatistics;        // 极差趋势统计（无条件调用）/ Range trend statistics
    nN           : INT;                           // 钳位后测点数 [点] / Clamped point count
    nI           : INT;                           // 测点循环下标 / Point loop index
    nValid       : INT;                           // 有效测点计数 [点] / Valid point counter
    fSum         : REAL;                          // 温度和 [degC] / Temperature sum [degC]
    fMin         : REAL;                          // 有效最小值 [degC] / Valid minimum [degC]
    fMax         : REAL;                          // 有效最大值 [degC] / Valid maximum [degC]
    fMeanBuf     : REAL;                          // 均值暂存 [degC] / Mean buffer [degC]
    fDevSum      : REAL;                          // 偏差平方和 [degC^2] / Squared deviation sum
    fVar         : REAL;                          // 样本方差 [degC^2] / Sample variance
    bStatOk      : BOOL;                          // 统计量可算标志 / Statistics computable
    uFault       : UDINT;                         // 锁存故障码 / Latched fault code
    uInfo        : UDINT;                         // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_LTU_PTMAX   : INT := 8;                    // 测点数组上界 [点] / Point array bound
    DL_LTU_RANGEMAX: REAL := 3.0;                 // 工艺允许极差上限 [degC]（工艺窗口常量）/ Process range limit [degC]
    DL_LTU_STDMAX  : REAL := 1.5;                 // 工艺允许标准差上限 [degC]（工艺窗口常量）/ Process std limit [degC]
    DL_LTU_TMIN    : REAL := -20.0;               // 测点物理域下限 [degC] / Point domain low [degC]
    DL_LTU_TMAX    : REAL := 400.0;               // 测点物理域上限 [degC] / Point domain high [degC]
END_VAR

(* === 段 0 · 实例刷新（无条件周期调用）=== *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸与测点掩码（失效点剔除，禁 0 degC 充数）=== *)
nN := nPointCount;                                // 测点数取用前钳位
IF nN < 1 THEN
    nN := 1;
END_IF
IF nN > DL_LTU_PTMAX THEN
    nN := DL_LTU_PTMAX;
END_IF
IF (nPointCount < 1) OR (nPointCount > DL_LTU_PTMAX) THEN
    uFault := 16#0002_0687;                       // 故障级：测点配置越界
END_IF
IF rtrReset.Q THEN
    uFault := 16#0000;                            // 复位沿清锁存
    bWarn := FALSE;                               // 告警同步复位
END_IF

(* === 段 2 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_LtuPhase.eIdle :
    bStatOk := FALSE;                             // 空闲不可算
    uInfo := 16#0000;                             // 信息码清零
    IF uFault = 16#0002_0687 THEN
        _eState := E_DL_LtuPhase.eFault;          // 组态故障优先
    ELSIF bEnable AND bSample THEN
        _eState := E_DL_LtuPhase.eCollect;        // 进入采集相
    END_IF

E_DL_LtuPhase.eCollect :
    nValid := 0;                                  // 有效点计数清零
    fSum := 0.0;                                  // 温度和清零
    fMin := 1.0E30;                               // 最小值初值取极大
    fMax := -1.0E30;                              // 最大值初值取极小
    FOR nI := 1 TO DL_LTU_PTMAX DO
        IF nI <= nN THEN
            abValidMask[nI] := abPointValid[nI]
                               AND (afTempC[nI] = afTempC[nI])                    // NaN 自反判据
                               AND (ABS(afTempC[nI]) < 1.0E30)                    // Inf 上限兜底
                               AND (afTempC[nI] >= DL_LTU_TMIN)
                               AND (afTempC[nI] <= DL_LTU_TMAX);                  // 物理域闸
            IF abValidMask[nI] THEN
                nValid := nValid + 1;                 // 有效点累加
                fSum := fSum + afTempC[nI];           // 温度和累加
                IF afTempC[nI] < fMin THEN
                    fMin := afTempC[nI];              // 更新最小值
                END_IF
                IF afTempC[nI] > fMax THEN
                    fMax := afTempC[nI];              // 更新最大值
                END_IF
            END_IF
        ELSE
            abValidMask[nI] := FALSE;                 // 超出配置的测点掩码置 FALSE
        END_IF
    END_FOR
    nValidPts := nValid;                          // 有效点输出
    IF nValid >= 1 THEN
        fMeanBuf := fSum / INT_TO_REAL(nValid);   // 均值分母已判 > 0
    ELSE
        fMeanBuf := 0.0;                          // 无效点：均值不出结论
    END_IF
    fMeanC := fMeanBuf;                           // 均值输出
    _eState := E_DL_LtuPhase.eJudge;              // 转判据相

E_DL_LtuPhase.eJudge :
    IF nValidPts >= 2 THEN
        fRangeC := fMax - fMin;                   // 极差：点数 >= 2 才有意义
        fDevSum := 0.0;                           // 偏差平方和清零
        FOR nI := 1 TO DL_LTU_PTMAX DO
            IF (nI <= nN) AND abValidMask[nI] THEN
                fDevSum := fDevSum + (afTempC[nI] - fMeanC) * (afTempC[nI] - fMeanC);   // 逐点累加偏差平方
            END_IF
        END_FOR
        fVar := fDevSum / INT_TO_REAL(nValidPts - 1);   // 样本方差，分母 n−1 >= 1
        IF fVar > 0.0 THEN
            fStdDevC := SQRT(fVar);               // 标准差
        ELSE
            fStdDevC := 0.0;                      // 方差非正：标准差 0
        END_IF
        bStatOk := TRUE;                          // 统计量有效
    ELSE
        fRangeC := 0.0;                           // 点数不足：极差不出结论
        fStdDevC := 0.0;                          // 标准差不出结论
        bStatOk := FALSE;                         // 统计量无效
        uInfo := 16#0002_06A7;                    // 信息级：有效测点 < 2
    END_IF
    _eState := E_DL_LtuPhase.eVerdict;            // 转结论相

E_DL_LtuPhase.eVerdict :
    IF bStatOk THEN
        bUniform := (fRangeC <= DL_LTU_RANGE_MAX + 1.0E-6) AND (fStdDevC <= DL_LTU_STDMAX + 1.0E-6);  // 双判据带容差
        IF NOT bUniform THEN
            bWarn := TRUE;                        // 置位型：均匀性告警（段尾不清零）
        ELSE
            bWarn := FALSE;                       // 恢复均匀即解除告警（可到达的解除路径）
        END_IF
    ELSE
        bUniform := FALSE;                        // 无法判定：不给合格结论
    END_IF
    IF (NOT bEnable) OR rtrReset.Q THEN
        _eState := E_DL_LtuPhase.eIdle;           // 失能/复位回空闲
    ELSIF bSample THEN
        _eState := E_DL_LtuPhase.eCollect;        // 连续采样
    END_IF

E_DL_LtuPhase.eFault :
    bUniform := FALSE;                            // 故障态不给合格结论
    bStatOk := FALSE;                             // 统计无效
    IF uFault = 16#0000 THEN
        _eState := E_DL_LtuPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_LtuPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_0697;                       // 故障级：相 ID 越界（枚举兜底路径）
END_CASE

(* === 段 3 · 极差趋势统计实例（每拍无条件调用）=== *)
statRange(fIn := fRangeC,                         // 极差序列
          bSample := bStatOk AND bSample,         // 仅结论有效时采样
          nWindow := 32,                          // 窗口 32 点
          bClear := rtrReset.Q);                  // 复位清窗

(* === 段 4 · 输出映射（三行同向：均值 → 极差 → 均匀标志）=== *)
IF nValidPts = 0 THEN
    uFault := 16#0002_0697;                       // 故障级：全部测点失效，无法出结论
END_IF
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
