(*
  FB_DL_StringerTrend  —  串焊机多通道焊接温度曲线在线监视 / Stringer multi-channel soldering temperature monitor
  分类 Category : DL_Process
  码位 Code     : 16#06_0_8E
  版本 Version  : 1.0.0
  溯源 Source   : LGF Measurement 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 逐通道焊接温度峰值窗判定（窗口均值 ± 带宽 → OK / 偏高 / 偏高三档）；
                  2) 首异常通道号输出 + 批次综合 bBatchOk；
                  3) 告警出口经 FB_DL_AlarmManager 分级（通道 i → 报警通道 i）。
  边界 Boundary : ① 通道数 < 2 不出统计结论（单点无峰谷可言，组态闸拒算）；
                  ② 任一通道实测无效（NaN/幅值越域）从统计剔除并在 abChanMask 标出；
                  ③ 链速为 0 时峰值窗不外推：保持上次窗并置 bHold；
                  ④ 分档边界按 R28 终审二式覆盖「正好整除」与「上限 + 1」两条向量（容差闭区间归属）；
                  ⑤ 输出三行同向：通道分档 → 首异常通道 → 批次结论。
  依赖 Depends  : FB_DL_SignalStatistics × 16（逐通道统计，每拍无条件调用）
                  FB_DL_AlarmManager × 1（分级告警出口，每拍无条件调用）

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_068E 故障级：组态非法（通道数 < 2 或 > 16 / 峰值带宽 <= 0 / 告警优先级表越界）
    16#0002_069E 故障级：相 ID 越界（枚举兜底路径）
    16#0002_06AE 信息级：链速为 0 峰值窗保持 / 有效通道不足 2 本拍不出结论（不置 bError）
*)

TYPE E_DL_StrBand :
(
    eOk     := 0,   // 峰值在窗内 / Peak in window
    eHigh   := 10,  // 峰值偏高 / Peak above window
    eLow    := 20,  // 峰值偏低 / Peak below window
    eFrozen := 30   // 通道无效冻结 / Channel frozen by invalid input
);
END_TYPE

TYPE E_DL_StrPhase :
(
    eIdle    := 0,  // 空闲 / Idle
    eWatch   := 10, // 在线监视 / Online monitoring
    eHold    := 20, // 链速为 0 窗保持 / Window held at zero chain speed
    eFault   := 90  // 组态故障锁定 / Configuration fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_StringerTrend
VAR_INPUT
    bEnable       : BOOL;                           // 总使能，FALSE 回空闲 / Master enable
    bReset        : BOOL;                           // 复位，上升沿清组态故障 / Reset, clears configuration fault
    aTempC        : ARRAY[1..16] OF REAL;           // 各通道焊接温度 [°C] / Channel soldering temperature [degC]
    nChanCount    : INT := 12;                      // 通道数 [路]，2..16 / Channel count
    fChainSpd     : REAL := 40.0;                   // 链速 [mm/s]，0 = 停链 / Chain speed [mm/s]
    fPeakBandK    : REAL := 8.0;                    // 峰值窗半宽 [K]，域 > 0 / Peak window half width [K]
    fPeakBaseC    : REAL := 235.0;                  // 峰值窗中心基准 [°C] / Peak window center [degC]
    nStatWindow   : INT := 32;                      // 统计窗口长度 [样本] / Statistics window length [sample]
    uHoldScans    : UINT := 10;                     // 链速 0 保持确认拍数 [拍] / Zero-speed hold confirm scans
    fEps          : REAL := 1.0E-6;                 // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    aeBand        : ARRAY[1..16] OF E_DL_StrBand;   // 逐通道峰值窗分档 / Per-channel band judgment
    nFirstAbnChan : INT;                            // 首异常通道号 1..16，0 = 无 / First abnormal channel
    bBatchOk      : BOOL;                           // 批次综合结论（全部有效通道在窗）/ Batch overall verdict
    bHold         : BOOL;                           // 链速为 0 窗保持标志 / Zero-speed window hold flag
    abChanMask    : ARRAY[1..16] OF BOOL;           // 通道无效掩码（TRUE = 剔除）/ Channel invalid mask
    bError        : BOOL;                           // 故障标志，与故障级码配对 / Fault flag
    uErrorId      : UDINT;                          // 事件码，0 = 无事件 / Event code
    eStateOut     : E_DL_StrPhase;                  // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState       : E_DL_StrPhase := E_DL_StrPhase.eIdle;  // 内部状态 / Internal state
    afbStat       : ARRAY[1..16] OF FB_DL_SignalStatistics;  // 逐通道统计实例（无条件调用）/ Per-channel statistics
    fbAlm         : FB_DL_AlarmManager;             // 分级告警实例（无条件调用）/ Alarm manager instance
    rtrReset      : R_TRIG;                         // 复位沿 / Reset edge
    abAlmSrc      : ARRAY[0..15] OF BOOL;           // 告警源打包（通道 i-1）/ Alarm source packing
    auPrio        : ARRAY[0..15] OF USINT;          // 告警优先级表（警告级）/ Alarm priority table
    bCfgOk        : BOOL;                           // 组态合法标志 / Configuration valid
    bChanOk       : BOOL;                           // 单通道本拍有效 / Single channel valid this scan
    bWinOk        : BOOL;                           // 统计窗已就绪（bStatValid）/ Statistics window ready
    bOutWin       : BOOL;                           // 峰值越窗（电平）/ Peak out of window
    nValidCnt     : INT;                            // 有效通道计数 [路] / Valid channel count
    nI            : INT;                            // 遍历索引 / Loop index
    uZeroCnt      : UINT;                           // 链速 0 确认计数 [拍] / Zero-speed confirm counter
    uFault        : UDINT;                          // 锁存故障码 / Latched fault code
    uInfo         : UDINT;                          // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_STR_CMAX   : INT := 16;                      // 通道数上限 [路] / Channel count upper bound
    DL_STR_INFMAX : REAL := 1.0E30;                 // 温度有限值幅值上限 [°C] / Temperature finite bound [degC]
END_VAR

(* === 段 0 · 实例刷新 === *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸 === *)
bCfgOk := (nChanCount >= 2) AND (nChanCount <= DL_STR_CMAX)    // 通道数域闸（< 2 拒算）
          AND (fPeakBandK > fEps)                                // 峰值带宽正域
          AND (fPeakBaseC = fPeakBaseC) AND (ABS(fPeakBaseC) < DL_STR_INFMAX);  // 基准 NaN 自反 + 幅值
IF NOT bCfgOk THEN
    uFault := 16#0002_068E;                       // 故障级：组态非法
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清锁存（解除路径可达）
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零
FOR nI := 0 TO 15 DO
    auPrio[nI] := 2;                              // 全通道告警统一警告级
    abAlmSrc[nI] := FALSE;                        // 告警源本拍清零后重填
END_FOR

(* === 段 2 · 链速判定与逐通道统计（实例无条件调用）=== *)
IF ABS(fChainSpd) < fEps THEN
    uZeroCnt := uZeroCnt + UINT#1;                // 链速为 0：确认计数累加
    IF uZeroCnt >= uHoldScans THEN
        bHold := TRUE;                            // 连续 N 拍 0 速：窗保持
        uInfo := 16#0002_06AE;                    // 信息级：链速为 0 峰值窗保持
    END_IF
ELSE
    uZeroCnt := UINT#0;                           // 链速恢复：计数清零
    bHold := FALSE;                               // 保持解除（可达路径：链速恢复即解除）
END_IF
nValidCnt := 0;                                   // 有效通道计数清零
nFirstAbnChan := 0;                               // 首异常通道清零（本拍重算）
bBatchOk := TRUE;                                 // 批次结论先假设成立
FOR nI := 1 TO DL_STR_CMAX DO
    aeBand[nI] := E_DL_StrBand.eOk;               // 分档先取 OK（逐通道覆盖）
    IF nI <= nChanCount THEN
        bChanOk := (aTempC[nI] = aTempC[nI]) AND (ABS(aTempC[nI]) < DL_STR_INFMAX);  // NaN 自反 + 幅值闸
        abChanMask[nI] := NOT bChanOk;            // 无效掩码标出
        afbStat[nI](fIn := aTempC[nI],            // 统计实例无条件调用
                    bSample := bChanOk AND bEnable AND (NOT bHold),  // 无效/保持拍不采新样本
                    nWindow := nStatWindow,       // 窗口长度透传
                    bClear := rtrReset.Q);        // 复位沿清窗
        bWinOk := bChanOk AND afbStat[nI].bStatValid;   // 统计结论有效性（n >= 2）
        IF bChanOk THEN
            nValidCnt := nValidCnt + 1;           // 有效通道计数
        ELSE
            aeBand[nI] := E_DL_StrBand.eFrozen;   // 无效通道：冻结档
            bBatchOk := FALSE;                    // 存在无效通道批次不出 OK
        END_IF
        IF bWinOk THEN
            bOutWin := (afbStat[nI].fMax > fPeakBaseC + fPeakBandK + fEps)   // 峰值超上限（含容差）
                       OR (afbStat[nI].fMax < fPeakBaseC - fPeakBandK - fEps);  // 峰值低于下限
            IF bOutWin THEN
                IF afbStat[nI].fMax > fPeakBaseC THEN
                    aeBand[nI] := E_DL_StrBand.eHigh;   // 偏高档
                ELSE
                    aeBand[nI] := E_DL_StrBand.eLow;    // 偏低档
                END_IF
                bBatchOk := FALSE;                // 越窗通道拉低批次结论
                abAlmSrc[nI - 1] := TRUE;         // 告警源打包（0 基映射）
                IF nFirstAbnChan = 0 THEN
                    nFirstAbnChan := nI;          // 首异常通道记录
                END_IF
            END_IF
        ELSE
            IF bChanOk AND (nValidCnt >= 1) AND (nValidCnt < 2) THEN
                uInfo := 16#0002_06AE;            // 信息级：有效通道不足 2 本拍不出结论
            END_IF
            bBatchOk := FALSE;                    // 统计未就绪不出批次 OK
        END_IF
    ELSE
        abChanMask[nI] := TRUE;                   // 超出组态通道数：掩码标出
        aeBand[nI] := E_DL_StrBand.eFrozen;       // 冻结档
    END_IF
END_FOR

(* === 段 3 · 告警实例（无条件调用）=== *)
fbAlm(abAlarmActive := abAlmSrc,                  // 逐通道告警源
      auPriority := auPrio,                       // 统一警告级
      bAck := rtrReset.Q,                         // 复位沿确认首出
      bEnable := bEnable AND bCfgOk);             // 使能且组态合法

(* === 段 4 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_StrPhase.eIdle :
    IF uFault <> 16#0000 THEN
        _eState := E_DL_StrPhase.eFault;          // 故障优先
    ELSIF bEnable AND bCfgOk THEN
        _eState := E_DL_StrPhase.eWatch;          // 使能进监视相
    END_IF

E_DL_StrPhase.eWatch :
    IF (uFault <> 16#0000) OR (NOT bEnable) THEN
        _eState := E_DL_StrPhase.eFault;          // 故障/失能转出
    ELSIF bHold THEN
        _eState := E_DL_StrPhase.eHold;           // 链速 0 转窗保持相
    END_IF

E_DL_StrPhase.eHold :
    IF (uFault <> 16#0000) OR (NOT bEnable) THEN
        _eState := E_DL_StrPhase.eFault;          // 故障/失能转出
    ELSIF NOT bHold THEN
        _eState := E_DL_StrPhase.eWatch;          // 链速恢复回监视（解除路径可达）
    END_IF

E_DL_StrPhase.eFault :
    IF uFault = 16#0000 THEN
        _eState := E_DL_StrPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_StrPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_069E;                       // 故障级：相 ID 越界
END_CASE

(* === 段 5 · 输出映射 === *)
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
