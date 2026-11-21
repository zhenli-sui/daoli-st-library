(*
  FB_DL_TrackerWindStow  —  跟踪支架大风保护收拢 / Tracker wind-stow protection
  分类 Category : DL_Process
  码位 Code     : 16#06_0_8C
  版本 Version  : 1.0.0
  溯源 Source   : LGF Technology 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 风速超「高阈值（带迟滞）」或趋势判据（风速爬升率超限持续 N 拍）→ 置收拢命令；
                  2) 解除条件：风速回落到解除阈值以下 + 最短驻留时间到 → 自动解除（解除路径可达）；
                  3) 收拢角度命令钳位到行程域，防组态越程。
  边界 Boundary : ① 风速非有限或 < 0 判无效：冻结输出保持末次命令并置信息码；
                  ② 高/解除阈值倒置或爬升率门限 <= 0 出厂报码不运行（组态闸）；
                  ③ 趋势窗确认拍数不足不出趋势结论（N 拍未满不参与判据）；
                  ④ 输出三行同向：收拢命令 → 安全角度 → 趋势告警标志。
  依赖 Depends  : FB_DL_Differentiator（风速爬升率，每拍无条件调用）

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_068C 故障级：组态非法（高/解除阈值倒置、爬升率门限 <= 0、收拢角行程域倒置）
    16#0002_069C 故障级：相 ID 越界（枚举兜底路径）
    16#0002_06AC 信息级：风速无效冻结输出 / 趋势确认拍数不足不出结论（不置 bError）
*)

TYPE E_DL_TwsPhase :
(
    eIdle    := 0,   // 空闲待机 / Idle
    eMonitor := 10,  // 风况监视 / Wind monitoring
    eStow    := 20,  // 大风收拢命令保持 / Stow command held
    eRelease := 30,  // 解除驻留等待（风速已回落）/ Release dwell after wind dropped
    eFrozen  := 40,  // 风速无效冻结 / Frozen by invalid wind
    eFault   := 90   // 组态故障锁定 / Configuration fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_TrackerWindStow
VAR_INPUT
    bEnable        : BOOL;                          // 总使能，FALSE 回空闲 / Master enable
    bReset         : BOOL;                          // 复位，上升沿清组态故障 / Reset, clears configuration fault
    fWindSpeed     : REAL;                          // 风速实测 [m/s]，域 >= 0 / Measured wind speed [m/s]
    fWindHigh      : REAL := 25.0;                  // 大风收拢阈值 [m/s]，须 > 解除阈值 / Stow threshold [m/s]
    fWindRelease   : REAL := 18.0;                  // 解除阈值 [m/s]，带迟滞 / Release threshold [m/s]
    fRiseRateMax   : REAL := 2.0;                   // 风速爬升率门限 [m/s per s]，域 > 0 / Rise-rate limit [m/s per s]
    uRiseConfirm   : UINT := 5;                     // 趋势确认拍数 [拍]，0 = 禁用趋势判据 / Trend confirm scans [scan]
    fStowAngle     : REAL := 60.0;                  // 安全收拢角度 [deg] / Safety stow angle [deg]
    fAngleMax      : REAL := 75.0;                  // 行程域上限 [deg]，收拢角钳位域 / Travel domain high [deg]
    fAngleMin      : REAL := -75.0;                 // 行程域下限 [deg] / Travel domain low [deg]
    fDwellSec      : REAL := 30.0;                  // 解除最短驻留 [s]，域 > 0 / Min release dwell [s]
    fTaskCycle     : REAL := 0.1;                   // 任务周期 [s]，域 > 0 / Task cycle [s]
    fEps           : REAL := 1.0E-6;                // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    bStowCmd       : BOOL;                          // 收拢命令出口（保持型）/ Stow command output, held
    fStowAngleCmd  : REAL;                          // 安全角度命令 [deg]，已钳行程域 / Safe angle command [deg], clamped
    bTrendAlarm    : BOOL;                          // 趋势判据命中标志（本拍重算）/ Trend criterion hit flag
    bFrozen        : BOOL;                          // 冻结标志（风速无效）/ Frozen by invalid wind
    bError         : BOOL;                          // 故障标志，与故障级码配对 / Fault flag paired with fault codes
    uErrorId       : UDINT;                         // 事件码，0 = 无事件 / Event code, 0 = none
    eStateOut      : E_DL_TwsPhase;                 // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState        : E_DL_TwsPhase := E_DL_TwsPhase.eIdle;  // 内部状态 / Internal state
    fbDiff         : FB_DL_Differentiator;          // 风速爬升率实例（无条件调用）/ Rise-rate instance
    rtrReset       : R_TRIG;                        // 复位沿 / Reset edge
    rtrWindOk      : R_TRIG;                        // 风速恢复沿（解除冻结重计驻留）/ Wind-valid edge
    tonDwell       : TON;                           // 解除驻留定时器（IN := NOT Q 自复位见 R33-2 用法不适用，此处电平触发）/ Release dwell timer
    bCfgOk         : BOOL;                          // 组态合法标志 / Configuration valid
    bWindOk        : BOOL;                          // 本拍风速有效 / Wind valid this scan
    bOverHigh      : BOOL;                          // 超高阈值（电平）/ Above stow threshold, level
    bBelowRelease  : BOOL;                          // 低于解除阈值（电平）/ Below release threshold, level
    bTrendHit      : BOOL;                          // 趋势判据命中（电平）/ Trend criterion hit
    uTrendCnt      : UINT;                          // 趋势确认计数 [拍] / Trend confirm counter [scan]
    fRateEff       : REAL;                          // 本拍爬升率 [m/s per s] / Rise rate this scan [m/s per s]
    uFault         : UDINT;                         // 锁存故障码 / Latched fault code
    uInfo          : UDINT;                         // 信息级码（本拍重算）/ Information code
END_VAR
VAR CONSTANT
    DL_TWS_INF_MAX : REAL := 1.0E30;                // 有限值判定幅值上限 [m/s] / Finite magnitude bound [m/s]
    DL_TWS_ANG_MAX : REAL := 180.0;                 // 角度物理域上限 [deg] / Angle domain high [deg]
END_VAR

(* === 段 0 · 实例刷新（无条件周期调用）=== *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿
rtrWindOk(CLK := bWindOk);                        // 每拍刷新风速恢复沿
fbDiff(bEnable := bCfgOk AND bEnable,             // 组态闸过才使能微分（每拍仍无条件调用实例）
       fIn := fWindSpeed,                         // 被微分量为风速
       tFiltTime := T#2S,                         // 爬升率低通 2 s 抑制阵风毛刺
       tSampleTime := REAL_TO_TIME(MAX(fTaskCycle, 0.01) * 1000.0),  // 周期换算 [ms]
       rRateMax := 1.0E10,                        // 速率上限放开，门限由本件判
       rRateMin := -1.0E10);                      // 速率下限放开

(* === 段 1 · 组态闸与输入域闸 === *)
bCfgOk := (fWindHigh > fWindRelease + fEps)       // 高阈值须高于解除阈值（迟滞带为正）
          AND (fWindHigh > fEps) AND (fWindRelease > fEps)
          AND (fRiseRateMax > fEps) AND (fDwellSec > fEps) AND (fTaskCycle > fEps)
          AND (fAngleMax > fAngleMin + fEps)      // 行程域不倒置
          AND (fWindHigh = fWindHigh) AND (fStowAngle = fStowAngle);  // NaN 自反
IF NOT bCfgOk THEN
    uFault := 16#0002_068C;                       // 故障级：组态非法
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清锁存（解除路径可达）
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零（R189：信息级可每拍重算）
bWindOk := (fWindSpeed = fWindSpeed) AND (fWindSpeed >= 0.0)
           AND (fWindSpeed < DL_TWS_INF_MAX);     // NaN 自反 + 非负域 + 幅值闸
IF NOT bWindOk THEN
    uInfo := 16#0002_06AC;                        // 信息级：风速无效冻结
END_IF
fStowAngleCmd := fStowAngle;                      // 角度命令先取组态值
IF fStowAngleCmd > fAngleMax THEN
    fStowAngleCmd := fAngleMax;                   // 钳到行程域上限
END_IF
IF fStowAngleCmd < fAngleMin THEN
    fStowAngleCmd := fAngleMin;                   // 钳到行程域下限
END_IF
IF ABS(fStowAngleCmd) > DL_TWS_ANG_MAX THEN
    fStowAngleCmd := 0.0;                         // 钳位后仍越物理域：安全侧回 0 度
END_IF

(* === 段 2 · 风况判据（本拍重算，非锁存）=== *)
bOverHigh := bWindOk AND (fWindSpeed >= fWindHigh);             // 电平判据：超高阈值
bBelowRelease := bWindOk AND (fWindSpeed <= fWindRelease);      // 电平判据：低于解除阈值
bTrendHit := FALSE;                                             // 趋势结论默认不成立
IF bWindOk AND fbDiff.bValid THEN
    fRateEff := fbDiff.fRateOut;                  // 取滤波后爬升率
    IF (uRiseConfirm > UINT#0) AND (fRateEff >= fRiseRateMax) THEN
        uTrendCnt := uTrendCnt + UINT#1;          // 命中拍计数累加
        IF uTrendCnt >= uRiseConfirm THEN
            bTrendHit := TRUE;                    // 连续 N 拍超门限：趋势结论成立
        END_IF
    ELSE
        uTrendCnt := UINT#0;                      // 未命中：确认计数归零重计
    END_IF
ELSE
    uTrendCnt := UINT#0;                          // 风速无效/微分未就绪：不出趋势结论
    IF bCfgOk AND (uRiseConfirm > UINT#0) THEN
        uInfo := 16#0002_06AC;                    // 信息级：趋势窗确认拍数不足不出结论
    END_IF
END_IF
bTrendAlarm := bTrendHit;                         // 趋势告警出口（本拍重算）

(* === 段 3 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
tonDwell(IN := (_eState = E_DL_TwsPhase.eRelease) AND bBelowRelease,   // 驻留计时只在解除相且风已回落
         PT := REAL_TO_TIME(fDwellSec * 1000.0));                      // 驻留时长换算 [ms]
CASE _eState OF
E_DL_TwsPhase.eIdle :
    bStowCmd := FALSE;                            // 空闲不收拢
    IF uFault <> 16#0000 THEN
        _eState := E_DL_TwsPhase.eFault;          // 故障优先
    ELSIF NOT bEnable THEN
        _eState := E_DL_TwsPhase.eIdle;           // 失能保持空闲
    ELSIF NOT bWindOk THEN
        _eState := E_DL_TwsPhase.eFrozen;         // 风速无效进冻结
    ELSIF bOverHigh OR bTrendHit THEN
        _eState := E_DL_TwsPhase.eStow;           // 阈值或趋势任一命中：收拢
    ELSE
        _eState := E_DL_TwsPhase.eMonitor;        // 正常进入监视相
    END_IF

E_DL_TwsPhase.eMonitor :
    bStowCmd := FALSE;                            // 监视相不收拢
    IF (NOT bWindOk) OR (uFault <> 16#0000) THEN
        _eState := E_DL_TwsPhase.eFrozen;         // 无效/故障转冻结
    ELSIF bOverHigh OR bTrendHit THEN
        _eState := E_DL_TwsPhase.eStow;           // 命中转收拢
    END_IF

E_DL_TwsPhase.eStow :
    bStowCmd := TRUE;                             // 收拢命令保持（同拍抹除防护：仅解除相清）
    IF NOT bWindOk THEN
        _eState := E_DL_TwsPhase.eFrozen;         // 收拢中风速无效：冻结保持命令
    ELSIF bBelowRelease THEN
        _eState := E_DL_TwsPhase.eRelease;        // 风已回落：进解除驻留相
    END_IF

E_DL_TwsPhase.eRelease :
    bStowCmd := TRUE;                             // 驻留期内命令仍保持（防回弹抖动）
    IF NOT bWindOk THEN
        _eState := E_DL_TwsPhase.eFrozen;         // 驻留中风速无效：冻结保持命令
    ELSIF bOverHigh OR bTrendHit THEN
        _eState := E_DL_TwsPhase.eStow;           // 风复起：回到收拢相（驻留定时器由 IN 条件自清）
    ELSIF tonDwell.Q THEN
        bStowCmd := FALSE;                        // 驻留满且风持续回落：解除命令
        uTrendCnt := UINT#0;                      // 趋势计数同步清零
        _eState := E_DL_TwsPhase.eMonitor;        // 回监视相（解除路径可达）
    END_IF

E_DL_TwsPhase.eFrozen :
    bFrozen := TRUE;                              // 冻结标志保持
    (* 收拢命令为输出保持量：冻结期间不清零，恢复后按状态续判 *)
    IF bWindOk AND (uFault = 16#0000) THEN
        bFrozen := FALSE;                         // 风速恢复：解冻（可到达的解除路径）
        IF rtrWindOk.Q THEN
            uTrendCnt := UINT#0;                  // 恢复沿重计趋势确认
        END_IF
        _eState := E_DL_TwsPhase.eMonitor;        // 回监视相
    END_IF

E_DL_TwsPhase.eFault :
    bFrozen := TRUE;                              // 故障态冻结
    bStowCmd := TRUE;                             // 故障安全侧：保持收拢命令
    IF uFault = 16#0000 THEN
        _eState := E_DL_TwsPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_TwsPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_069C;                       // 故障级：相 ID 越界
    bFrozen := TRUE;                              // 安全侧冻结
    bStowCmd := TRUE;                             // 安全侧保持收拢
END_CASE

(* === 段 4 · 输出映射 === *)
bFrozen := (_eState = E_DL_TwsPhase.eFrozen) OR (_eState = E_DL_TwsPhase.eFault);  // 冻结标志段尾单点映射
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
