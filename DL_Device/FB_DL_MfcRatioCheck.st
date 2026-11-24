(*
  FB_DL_MfcRatioCheck  —  MFC 流量配比偏差核对 / MFC flow ratio deviation check
  分类 Category : DL_Device
  码位 Code     : 16#03_2_02
  版本 Version  : 1.0.0
  溯源 Source   : LBP 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 各路流量经标定换算（增益/偏置）后计算配比，与配比设定窗比对；
                  2) 设定回读比对带容差（浮点禁 = 判等），差异只报等级不改设定值；
                  3) 配比计算前各路流量须 > 0 且有限（分母防零），配比窗上下限须配比校验。
  边界 Boundary : ① 配比计算前各路流量 > 0 且有限（分母防零）；
                  ② 配比窗上下限配比校验（下限 <= 上限），倒置即报码；
                  ③ 设定回读比对带容差，差异只报等级不改设定值；
                  ④ 输出三行同向：配比实测 → 配比判定 → 回读不一致标志。
  依赖 Depends  : FB_DL_DeviceParamVerify（设定回读比对，每拍无条件调用）

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_0302 故障级：组态非法（配比窗倒置 / 标定增益 <= 0 / 路数越界 / 容差 <= 0）
    16#0002_0312 故障级：回读参数超差（不一致锁存）
    16#0002_0322 信息级：某路流量为 0 或非有限，本拍不出配比结论（不置 bError）
*)

TYPE E_DL_MrcPhase :
(
    eIdle    := 0,   // 空闲 / Idle
    eCalc    := 10,  // 配比计算 / Ratio computation
    eVerify  := 20,  // 回读比对 / Readback verification
    eVerdict := 30,  // 结论输出 / Verdict output
    eFault   := 90   // 故障锁定 / Fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_MfcRatioCheck
VAR_INPUT
    bEnable      : BOOL;                          // 总使能，FALSE 回空闲 / Master enable
    bSample      : BOOL := TRUE;                  // 采样使能 / Sampling enable
    bReset       : BOOL;                          // 复位，上升沿清故障与比对锁存 / Reset
    bAcknowledge : BOOL;                          // 上升沿确认回读不一致 / Rising edge acknowledges a mismatch
    nGasCount    : INT := 2;                      // 参与配比的气路数 [路]，域 2~4 / Participating gas channels, 2..4
    afFlowSccm   : ARRAY[1..4] OF REAL;           // 各路实测流量 [sccm] / Per-channel measured flow [sccm]
    afCalGain    : ARRAY[1..4] OF REAL;           // 各路标定增益 [sccm 折算比]，域 > 0 / Per-channel calibration gain
    afCalOffset  : ARRAY[1..4] OF REAL;           // 各路标定偏置 [sccm] / Per-channel calibration offset [sccm]
    fRatioSetPct : REAL := 50.0;                  // 配比设定（第 1 路占比）[%]，域 0~100 / Ratio setpoint [%]
    fRatioWinLo  : REAL := 45.0;                  // 配比窗下限 [%] / Ratio window low [%]
    fRatioWinHi  : REAL := 55.0;                  // 配比窗上限 [%] / Ratio window high [%]
    afSpCmd      : ARRAY[1..4] OF REAL;           // 各路设定指令 [sccm] / Per-channel setpoint command [sccm]
    afSpReadback : ARRAY[1..4] OF REAL;           // 各路设定回读 [sccm] / Per-channel setpoint readback [sccm]
    fReadbackTol : REAL := 1.0;                   // 回读容差 [sccm]（浮点禁 = 判等）/ Readback tolerance [sccm]
    fEps         : REAL := 1.0E-6;                // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    fRatioActPct : REAL;                          // 实测配比（第 1 路占比）[%] / Measured ratio [%]
    fTotalFlow   : REAL;                          // 标定后总流量 [sccm] / Calibrated total flow [sccm]
    bRatioOk     : BOOL;                          // 配比在窗内 / Ratio inside window
    bFlowInvalid : BOOL;                          // 流量无效标志（0 或非有限）/ Flow invalid flag
    bMismatch    : BOOL;                          // 回读不一致（保持型）/ Readback mismatch, held
    nDiffCount   : INT;                           // 回读超差路数 [路] / Out-of-tolerance channel count
    bError       : BOOL;                          // 故障标志，与故障级码配对 / Fault flag paired with fault codes
    uErrorId     : UDINT;                         // 事件码，0 = 无事件 / Event code, 0 = none
    eStateOut    : E_DL_MrcPhase;                 // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState      : E_DL_MrcPhase := E_DL_MrcPhase.eIdle;  // 内部状态 / Internal state
    rtrReset     : R_TRIG;                        // 复位沿 / Reset edge
    fbVerify     : FB_DL_DeviceParamVerify;       // 回读比对实例（无条件调用）/ Readback verify instance
    afExp       : ARRAY[1..64] OF REAL;           // 期望参数块（映射到前 4 项）/ Expected parameter block
    afAct       : ARRAY[1..64] OF REAL;           // 实际参数块（映射到前 4 项）/ Actual parameter block
    afTol       : ARRAY[1..64] OF REAL;           // 逐项容差块 / Per-item tolerance block
    nN           : INT;                           // 钳位后气路数 [路] / Clamped channel count
    nI           : INT;                           // 气路循环下标 / Channel loop index
    nDiff        : INT;                           // 本地超差计数 [路] / Local difference counter
    bCfgOk       : BOOL;                          // 组态合法标志 / Configuration valid
    bFlowOk      : BOOL;                          // 全部气路流量有效 / All flows valid
    fCalc        : REAL;                          // 单路标定后流量 [sccm] / Calibrated channel flow [sccm]
    fSum         : REAL;                          // 总流量累计 [sccm] / Total flow accumulator [sccm]
    fFirst       : REAL;                          // 第 1 路标定后流量 [sccm] / Channel-1 calibrated flow [sccm]
    uFault       : UDINT;                         // 锁存故障码 / Latched fault code
    uInfo        : UDINT;                         // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_MRC_CHMAX : INT := 4;                      // 气路上界 [路] / Channel upper bound
    DL_MRC_PCTMAX: REAL := 100.0;                 // 百分比满量程 [%] / Percentage full scale
    DL_MRC_FLMAX : REAL := 1.0E5;                 // 单路流量物理域上限 [sccm] / Channel flow domain high
END_VAR

(* === 段 0 · 实例刷新（无条件周期调用）=== *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸 === *)
nN := nGasCount;                                  // 气路数取用前钳位
IF nN < 2 THEN
    nN := 2;                                      // 配比至少两路
END_IF
IF nN > DL_MRC_CHMAX THEN
    nN := DL_MRC_CHMAX;                           // 上限钳位
END_IF
bCfgOk := (nGasCount >= 2) AND (nGasCount <= DL_MRC_CHMAX)
          AND (fRatioWinHi >= fRatioWinLo)                              // 配比窗配比校验（下限 <= 上限）
          AND (fRatioWinLo >= 0.0) AND (fRatioWinHi <= DL_MRC_PCTMAX)
          AND (fReadbackTol > fEps) AND (fRatioSetPct = fRatioSetPct)
          AND (fRatioWinLo = fRatioWinLo) AND (fRatioWinHi = fRatioWinHi);   // 含 NaN 自反
FOR nI := 1 TO DL_MRC_CHMAX DO
    IF nI <= nN THEN
        bCfgOk := bCfgOk AND (afCalGain[nI] > fEps)                    // 标定增益正域（防换算除零/反向）
                  AND (afCalGain[nI] = afCalGain[nI])                  // 增益 NaN 自反
                  AND (afCalOffset[nI] = afCalOffset[nI]);             // 偏置 NaN 自反
    END_IF
END_FOR
IF NOT bCfgOk THEN
    uFault := 16#0002_0302;                       // 故障级：组态非法
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清锁存（复位路径可达）
    bMismatch := FALSE;                           // 回读不一致同步复位
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零

(* === 段 2 · 标定换算与流量有效域（分母防零前置）=== *)
bFlowOk := TRUE;                                  // 假定有效，逐路否决
fSum := 0.0;                                      // 总流量清零
fFirst := 0.0;                                    // 第 1 路清零
FOR nI := 1 TO DL_MRC_CHMAX DO
    IF nI <= nN THEN
        IF (afFlowSccm[nI] = afFlowSccm[nI]) AND (ABS(afFlowSccm[nI]) < 1.0E30)
           AND (afFlowSccm[nI] > 0.0) AND (afFlowSccm[nI] <= DL_MRC_FLMAX) THEN
            fCalc := afFlowSccm[nI] * afCalGain[nI] + afCalOffset[nI];   // 标定换算
            IF fCalc < 0.0 THEN
                fCalc := 0.0;                                          // 负流量截零（物理不可达）
            END_IF
            fSum := fSum + fCalc;                                      // 总流量累加
            IF nI = 1 THEN
                fFirst := fCalc;                                       // 第 1 路流量
            END_IF
        ELSE
            bFlowOk := FALSE;                                          // 该路无效：本拍不出配比结论
        END_IF
    END_IF
END_FOR
bFlowInvalid := NOT bFlowOk;                      // 流量无效标志

(* === 段 3 · 比对参数块装配 + 比对实例无条件调用（先刷新，后判定）=== *)
FOR nI := 1 TO DL_MRC_CHMAX DO
    IF nI <= nN THEN
        afExp[nI] := afSpCmd[nI];                 // 期望参数装入（前 nN 项）
        afAct[nI] := afSpReadback[nI];            // 实际参数装入
        afTol[nI] := fReadbackTol;                // 逐项容差
    ELSE
        afExp[nI] := 0.0;                         // 未用项置 0（比对块按 nN 取项）
        afAct[nI] := 0.0;                         // 未用项置 0
        afTol[nI] := fReadbackTol;                // 未用项容差给默认，不影响 nN 内比对
    END_IF
END_FOR
fbVerify(bEnable := bEnable AND bCfgOk,           // 组态非法不比对
         bReset := rtrReset.Q,                    // 复位沿清比对锁存
         bAcknowledge := bAcknowledge,            // 人工确认不一致
         nItemCount := nN,                        // 比对项数 = 气路数（已钳位 2..4）
         afExpected := afExp,                     // 期望参数块
         afActual := afAct,                       // 回读参数块
         afTolerance := afTol,                    // 逐项容差（浮点禁 = 判等）
         fDefaultTol := fReadbackTol,             // 默认容差
         tVerifyTimeout := T#5S);                 // 回读超时 [ms]

(* === 段 4 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_MrcPhase.eIdle :
    bRatioOk := FALSE;                            // 空闲无配比结论
    nDiffCount := 0;                              // 超差路数清零
    IF uFault = 16#0002_0302 THEN
        _eState := E_DL_MrcPhase.eFault;          // 组态故障优先
    ELSIF bEnable AND bSample THEN
        _eState := E_DL_MrcPhase.eCalc;           // 进入计算相
    END_IF

E_DL_MrcPhase.eCalc :
    IF (NOT bFlowOk) OR (NOT bCfgOk) THEN
        bRatioOk := FALSE;                        // 无效：不出配比结论
        uInfo := 16#0002_0322;                    // 信息级：某路流量无效
    ELSIF fSum > fEps THEN
        fTotalFlow := fSum;                       // 总流量输出
        fRatioActPct := fFirst / fSum * DL_MRC_PCTMAX;   // 配比 = 第 1 路 / 总流量，分母已判非零
        bRatioOk := (fRatioActPct >= fRatioWinLo - fEps) AND (fRatioActPct <= fRatioWinHi + fEps);  // 容差窗比对
    ELSE
        fTotalFlow := 0.0;                        // 总流量近零：配比不可算
        bRatioOk := FALSE;                        // 不给结论（防除零）
        uInfo := 16#0002_0322;                    // 信息级：总流量近零
    END_IF
    _eState := E_DL_MrcPhase.eVerify;             // 转回读比对相

E_DL_MrcPhase.eVerify :
    nDiff := fbVerify.nDiffCount;                 // 取实例超差项数（本拍已刷新）
    _eState := E_DL_MrcPhase.eVerdict;            // 转结论相

E_DL_MrcPhase.eVerdict :
    nDiffCount := fbVerify.nDiffCount;            // 超差路数输出
    IF fbVerify.bMismatch THEN
        bMismatch := TRUE;                        // 置位型：回读不一致（段尾不清零）
        uFault := 16#0002_0312;                   // 故障级：回读超差
    END_IF
    IF (NOT bEnable) OR rtrReset.Q THEN
        _eState := E_DL_MrcPhase.eIdle;           // 失能/复位回空闲
    ELSIF bSample THEN
        _eState := E_DL_MrcPhase.eCalc;           // 连续采样
    END_IF

E_DL_MrcPhase.eFault :
    bRatioOk := FALSE;                            // 故障态不给配比合格结论
    IF uFault = 16#0000 THEN
        _eState := E_DL_MrcPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_MrcPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_0302;                       // 故障级：相 ID 越界
    bRatioOk := FALSE;                            // 安全侧不给合格结论
END_CASE

(* === 段 5 · 输出映射（三行同向：配比 → 判定 → 不一致标志）=== *)
IF bFlowInvalid THEN
    bRatioOk := FALSE;                            // 流量无效绝不判合格
END_IF
IF NOT bEnable THEN
    bRatioOk := FALSE;                            // 失能不给合格结论
END_IF
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
