(*
  FB_DL_FoupPurgeN2Flow  —  FOUP 氮气吹扫流量与露点监视（建立窗口 / 分级露点告警 / 注入脉冲流量计）/ FOUP N2 purge flow and dew-point supervision
  分类 Category : DL_Device
  码位 Code     : 16#03_2_0F
  版本 Version  : 1.0.0
  来源 Source   : t2-1-lgf-measurement — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : LGF 测量类文档公开语义借鉴（流量带判据、露点分级），clean-room 实现，未复制源码行
  功能 Function : 1) 注入 FB_DL_PulseFlowMeter 实例（VAR_IN_OUT，只读其流量/总量/故障输出，**本件不调用其实例体**），
                     取瞬时流量与 K 系数参与判据；
                  2) 吹扫起始（bPurgeStart 上升沿）后在 tPurgeEstablish 内流量须进入 fFlowSetLpm ± fFlowTolPct% 带，
                     否则置 bEstablishTimeout（故障级 021F）；
                  3) 露点按两级判据告警：越 fDewPointMaxC 为「越限」（023F），越 fDewSevereC 为「严重越限」（024F），
                     两码独立、独立出口（R190 归因唯一）；
                  4) 露点信号质量坏或缺失时**不当作合格**：置 022F 且 bPurgeOk := FALSE（安全侧，绝不静默放行）。
  边界 Boundary : ① fFlowSetLpm <= 0 判组态错 020F（偏差百分比的分母，R45 防除零）；
                     注入流量计 fKFactor = 0 判组态错 020F 且不投运（K 系数未标定，流量读数无物理意义）；
                     露点两级门限倒置（fDewSevereC <= fDewPointMaxC）同判组态错；
                  ② 偏差百分比对 ABS 结果限幅 DL_DEV_CLAMP_PCT，防极端读数导致 REAL 溢出与 HMI 显示异常；
                  ③ bPurgeOk 的成立条件 = 建立成功 AND 流量在带 AND 露点未越限 AND 露点信号有效 AND 无故障；
                  ④ 解除式自证：_bFault 清除 = rtReset.Q（引脚可满足）；021F 另可由「流量重新入带且持续
                     tEstablishRetry」按码专清（R188 可达清除边）；023F/024F 可由露点回落按码专清；
                  ⑤ bDewPointAlarm / bDewSevereAlarm 为保持型告警位（不随单拍读数抖动），只由复位沿或回落清除。
  依赖 Depends  : FB_DL_PulseFlowMeter（DL_Device 既有件，×1 以 VAR_IN_OUT 注入）；
                  仅 Standard.library（TON / R_TRIG / ABS / MIN / MAX）
  同拍双窗配比  : tPurgeEstablish（建立窗口）与 tDewDb（露点去抖窗）不同源；配比约束
                  tDewDb <= tPurgeEstablish，保证建立窗口内露点结论至少更新一次（R100）

  码表 Error codes（本件格 03_2_0F，子码步进 +0x10）:
    16#0003_020F 故障级：组态非法（流量设定 <= 0 / K 系数 = 0 / 容差 <= 0 / 露点门限倒置 / 时间参数 <= 0）
    16#0003_021F 故障级：吹扫建立超时（tPurgeEstablish 内流量未进入容许带）
    16#0003_022F 故障级：露点信号无效（质量坏或缺失，不当作合格）
    16#0003_023F 故障级：露点越限（超 fDewPointMaxC）
    16#0003_024F 故障级：露点严重越限（超 fDewSevereC）
    16#0003_025F 故障级：状态机落 ELSE 兜底（非法相位 ID）
    16#0003_010F 信息级：吹扫建立成功，流量已入带（不置 bError）
    16#0003_011F 信息级：流量偏差瞬时越带但未超建立窗口（不置 bError）

  修订历史 Revision :
    2026-11-18  v1.0.0  R37 首版
*)

TYPE E_DL_N2PurgeState :
(
    eIdle      := 0,   // 空闲：未吹扫 / Idle, purge not started
    eEstablish := 10,  // 建立中：等流量进入容许带 / Establishing, waiting for the flow band
    ePurged    := 20,  // 吹扫中：流量与露点均在限内 / Purging, flow and dew point inside the limits
    eTimeout   := 30,  // 超时：建立窗口耗尽，等待复位 / Timed out, waiting for a reset
    eFault     := 90   // 故障：组态或信号故障锁定 / Fault, a latched configuration or signal fault
);
END_TYPE

FUNCTION_BLOCK FB_DL_FoupPurgeN2Flow
VAR_INPUT
    bEnable        : BOOL := FALSE;             // 总使能，FALSE 时 bPurgeOk 恒假 / Master enable, low level forces bPurgeOk FALSE
    bReset         : BOOL := FALSE;             // 复位，上升沿清故障与告警锁存 / Reset, clears the fault and alarm latches
    bPurgeStart    : BOOL := FALSE;             // 吹扫起始触发（上升沿受理）/ Purge start trigger, rising edge
    fFlowSetLpm    : REAL := 20.0;              // 吹扫流量设定 [L/min]，域 > 0 / Purge flow setpoint [L/min]
    fFlowTolPct    : REAL := 10.0;              // 流量容许带 [%]，域 > 0 / Flow tolerance band [%]
    fDewPointMaxC  : REAL := -40.0;             // 露点越限门限 [°C]，域 < fDewSevereC / Dew point limit [degC]
    fDewSevereC    : REAL := -20.0;             // 露点严重越限门限 [°C]，须 > fDewPointMaxC / Severe dew point limit [degC]
    fDewPointC     : REAL := -60.0;             // 露点实测值 [°C] / Measured dew point [degC]
    bDewQualityOk  : BOOL := TRUE;              // 露点信号质量（FALSE = 坏或缺失）/ Dew point signal quality, FALSE means bad
    tPurgeEstablish : TIME := T#10S;            // 吹扫建立窗口 [ms]，域 > 0 / Purge establishment window [ms]
    tEstablishRetry : TIME := T#30S;            // 入带持续窗（021F 按码专清用）[ms]，域 > 0 / In-band dwell for the code-specific clear
    tDewDb         : TIME := T#2S;              // 露点告警去抖窗 [ms]，域 > 0 / Dew point debounce [ms]
END_VAR
VAR_OUTPUT
    bPurgeOk       : BOOL;                      // 吹扫合格（建立成功且流量/露点均在限内）/ Purge acceptable
    bEstablishTimeout : BOOL;                   // 建立超时（保持型）/ Establishment timeout, held
    bDewPointAlarm : BOOL;                      // 露点越限告警（保持型）/ Dew point alarm, held
    bDewSevereAlarm : BOOL;                     // 露点严重越限告警（保持型）/ Severe dew point alarm, held
    fFlowDeviationPct : REAL;                   // 流量偏差 [%]，已限幅 / Flow deviation [%], clamped
    fFlowActualLpm : REAL;                      // 实测流量 [L/min] / Measured flow [L/min]
    bValid         : BOOL;                      // 判据可用标志 / Criteria usable
    bError         : BOOL;                      // 故障标志，派生自锁存 / Fault flag derived from the latch
    nErrId         : UDINT;                     // 事件码，0 = 无事件 / Event code, 0 = no event
    eStateOut      : E_DL_N2PurgeState;         // 状态出口，段尾单点映射 / State outlet, mapped at the tail
END_VAR
VAR_IN_OUT
    fbFlowMeter : FB_DL_PulseFlowMeter;         // 注入的脉冲流量计实例（只读输出，本件不调用其实例体）/ Injected pulse flow meter, read only
END_VAR
VAR
    tonEstablish : TON;                         // 建立窗口计时，每拍无条件调用 / Establishment window, called unconditionally
    tonInBand    : TON;                         // 入带持续计时，每拍无条件调用 / In-band dwell timer, called unconditionally
    tonDew       : TON;                         // 露点去抖计时，每拍无条件调用 / Dew point debounce, called unconditionally
    tonHeart     : TON;                         // 周期心跳窗，自复位 / Periodic heartbeat window, self-resetting
    rtReset      : R_TRIG;                      // 复位上升沿 / Reset rising edge
    rtStart      : R_TRIG;                      // 吹扫起始上升沿 / Purge start rising edge
    _eState      : E_DL_N2PurgeState := E_DL_N2PurgeState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _uFault      : UDINT;                       // 故障码锁存 / Latched fault code
    _uInfo       : UDINT;                       // 信息码，每拍重算 / Information code, recomputed per scan
    _bFault      : BOOL;                        // 故障锁存位 / Latched fault bit
    _bCfgBad     : BOOL;                        // 组态非法聚合 / Configuration invalid aggregate
    _bInBand     : BOOL;                        // 流量在容许带 / Flow inside the tolerance band
    _bEstTimeout : BOOL;                        // 建立超时保持量 / Held establishment-timeout value
    _bDewAlarm   : BOOL;                        // 露点越限保持量 / Held dew point alarm
    _bDewSevere  : BOOL;                        // 露点严重越限保持量 / Held severe dew point alarm
    _bDewBad     : BOOL;                        // 露点信号无效 / Dew point signal unusable
    _bEstBreak   : BOOL := TRUE;                // 建立窗口断输入一拍 / One-scan establishment break
    _bInBandBrk  : BOOL := TRUE;                // 入带计时断输入一拍 / One-scan in-band break
    _bDewBrk     : BOOL := TRUE;                // 露点去抖断输入一拍 / One-scan dew break
    _bHeartBrk   : BOOL := TRUE;                // 心跳窗断输入一拍 / One-scan heartbeat break
    _fDevRaw     : REAL;                        // 未限幅偏差 [%] / Unclamped deviation [%]
    _fKFactor    : REAL;                        // 注入流量计 K 系数 [pulses/L] / Injected K-factor [pulses/L]
END_VAR
VAR CONSTANT
    DL_DEV_CLAMP_PCT : REAL := 1000.0;   // 偏差绝对值限幅 [%] / Deviation magnitude clamp [%]
    DL_DEW_LIM_C     : REAL := 200.0;    // 露点有限性上限 [°C] / Dew point magnitude ceiling [degC]
    DL_FLOW_LIM_LPM  : REAL := 100000.0; // 流量有限性上限 [L/min] / Flow magnitude ceiling [L/min]
    DL_HEART_WINDOW  : TIME := T#2S;     // 心跳观察窗 [ms]，自复位节拍 / Heartbeat window, self-resetting
END_VAR

(* —— 段 0：定时器与边缘检测无条件周期刷新（R182：调用语句不得置于 IF / CASE 内） —— *)
rtReset(CLK := bReset);                                          // 复位上升沿，每拍必调
rtStart(CLK := bPurgeStart);                                     // 吹扫起始上升沿，每拍必调
tonHeart(IN := (NOT tonHeart.Q) AND (NOT _bHeartBrk), PT := DL_HEART_WINDOW);  // 心跳窗自复位
_bHeartBrk := FALSE;                                             // 断输入拍在调用后自清
tonEstablish(IN := (_eState = E_DL_N2PurgeState.eEstablish) AND (NOT _bEstBreak), PT := tPurgeEstablish);  // 建立窗口
_bEstBreak := FALSE;                                             // 断输入拍在调用后自清
tonInBand(IN := _bInBand AND (NOT _bInBandBrk), PT := tEstablishRetry);   // 入带持续（表达式入参）
_bInBandBrk := FALSE;                                            // 断输入拍在调用后自清
tonDew(IN := _bDewBad AND (NOT _bDewBrk), PT := tDewDb);          // 露点信号无效去抖（表达式入参）
_bDewBrk := FALSE;                                               // 断输入拍在调用后自清

(* —— 段 1：单拍量预清零（告警保持量 / 锁存不入清单，R187①） —— *)
_uInfo      := 16#0000_0000;   // 信息码每拍重算
bError      := FALSE;          // 故障出口每拍重算，段 6 由锁存派生
bValid      := FALSE;          // 可用标志缺省 FALSE
bPurgeOk    := FALSE;          // 合格出口缺省 FALSE（安全侧）
_bCfgBad    := FALSE;          // 组态非法预清零
_bInBand    := FALSE;          // 在带判据预清零
_bDewBad    := FALSE;          // 露点信号无效预清零

(* —— 段 2：复位沿清锁存与告警保持量（R188 双路径） —— *)
IF rtReset.Q THEN
    _bFault     := FALSE;            // 复位沿清锁存位
    _uFault     := 16#0000_0000;     // 复位沿清锁存码
    _bEstTimeout := FALSE;           // 清建立超时保持量
    _bDewAlarm  := FALSE;            // 清露点越限告警
    _bDewSevere := FALSE;            // 清露点严重越限告警
END_IF
IF (_uFault = 16#0003_023F) AND (NOT _bDewAlarm) THEN
    _uFault := 16#0000_0000;         // 按码专清：露点回落至越限门限以下
    _bFault := FALSE;                // 锁存位同步清
END_IF
IF (_uFault = 16#0003_024F) AND (NOT _bDewSevere) THEN
    _uFault := 16#0000_0000;         // 按码专清：露点回落至严重门限以下
    _bFault := FALSE;                // 锁存位同步清
END_IF

(* —— 段 3：组态域闸（覆盖全部参与换算的引脚与注入件参数，R151） —— *)
_fKFactor := fbFlowMeter.fKFactor;                              // 读注入件 K 系数 [pulses/L]
IF (fFlowSetLpm <> fFlowSetLpm) OR (fFlowSetLpm <= 0.0) OR (fFlowSetLpm > DL_FLOW_LIM_LPM) THEN
    _bCfgBad := TRUE;                                           // 流量设定非法（偏差分母，R45 防除零）
END_IF
IF (_fKFactor <> _fKFactor) OR (_fKFactor <= 0.0) THEN
    _bCfgBad := TRUE;                                           // K 系数未组态/非有限：流量读数无物理意义，不投运
END_IF
IF (fFlowTolPct <> fFlowTolPct) OR (fFlowTolPct <= 0.0) THEN
    _bCfgBad := TRUE;                                           // 容差带非法（为 0 等于永不合格）
END_IF
IF (fDewPointMaxC <> fDewPointMaxC) OR (ABS(fDewPointMaxC) > DL_DEW_LIM_C) THEN
    _bCfgBad := TRUE;                                           // 露点越限门限非法
END_IF
IF (fDewSevereC <> fDewSevereC) OR (fDewSevereC <= fDewPointMaxC) THEN
    _bCfgBad := TRUE;                                           // 严重门限倒置（须严格大于越限门限）
END_IF
IF (TIME_TO_DINT(tPurgeEstablish) <= 0) OR (TIME_TO_DINT(tEstablishRetry) <= 0) OR
   (TIME_TO_DINT(tDewDb) <= 0) THEN
    _bCfgBad := TRUE;                                           // 三个时间参数均须 > 0
END_IF
IF _bCfgBad THEN
    _uFault := 16#0003_020F;                                    // 故障级：组态非法
    _bFault := TRUE;                                            // 锁存位置位（复位沿可清）
    bError  := TRUE;                                            // 故障标志置位（R45 配对）
    _eState := E_DL_N2PurgeState.eFault;                        // 进故障相（不投运）
END_IF

(* —— 段 4：流量与露点判据（仅无组态错时计算） —— *)
IF NOT _bCfgBad THEN
    fFlowActualLpm := fbFlowMeter.fFlowRate;                    // 注入件瞬时流量镜像 [L/min]
    IF (fFlowActualLpm <> fFlowActualLpm) OR (ABS(fFlowActualLpm) > DL_FLOW_LIM_LPM) THEN
        _bCfgBad := TRUE;                                       // 流量非有限：本拍判据不可信
        _uFault := 16#0003_020F;                                // 故障级：输入异常归入组态/输入异常码
        _bFault := TRUE;                                        // 锁存
        bError  := TRUE;                                        // 故障标志置位（R45 配对）
        _eState := E_DL_N2PurgeState.eFault;                    // 进故障相
    ELSE
        _fDevRaw := (fFlowActualLpm - fFlowSetLpm) / fFlowSetLpm * 100.0;   // 偏差 [%]（分母已证 > 0）
        fFlowDeviationPct := _fDevRaw;                          // 出口初值
        IF fFlowDeviationPct > DL_DEV_CLAMP_PCT THEN
            fFlowDeviationPct := DL_DEV_CLAMP_PCT;              // 上行限幅（防溢出与显示异常）
        END_IF
        IF fFlowDeviationPct < -DL_DEV_CLAMP_PCT THEN
            fFlowDeviationPct := -DL_DEV_CLAMP_PCT;             // 下行限幅
        END_IF
        _bInBand := (ABS(_fDevRaw) <= fFlowTolPct);             // 在带判据（用未限幅偏差判，避免限幅掩盖超差）
        IF NOT _bInBand THEN
            _uInfo := 16#0003_011F;                             // 信息级：瞬时越带（可能仍可建立）
        END_IF
    END_IF

    (* 4A 露点信号质量：坏则**不当作合格**（安全侧） *)
    IF (NOT bDewQualityOk) OR (fDewPointC <> fDewPointC) OR (ABS(fDewPointC) > DL_DEW_LIM_C) THEN
        _bDewBad := TRUE;                                       // 信号无效
        _uFault := 16#0003_022F;                                // 故障级：露点信号无效
        _bFault := TRUE;                                        // 锁存
        bError  := TRUE;                                        // 故障标志置位（R45 配对）
    END_IF

    (* 4B 露点分级判据：越限 / 严重越限两码独立，保持型告警位 *)
    IF (NOT _bDewBad) THEN
        IF fDewPointC > fDewSevereC THEN
            _bDewSevere := TRUE;                                // 严重越限保持量
            _bDewAlarm  := TRUE;                                // 严重越限同时满足越限（上位包含关系）
            _uFault := 16#0003_024F;                            // 故障级：露点严重越限
            _bFault := TRUE;                                    // 锁存
            bError  := TRUE;                                    // 故障标志置位（R45 配对）
        ELSIF fDewPointC > fDewPointMaxC THEN
            _bDewAlarm := TRUE;                                 // 越限保持量
            _uFault := 16#0003_023F;                            // 故障级：露点越限
            _bFault := TRUE;                                    // 锁存
            bError  := TRUE;                                    // 故障标志置位（R45 配对）
        ELSE
            IF fDewPointC <= (fDewPointMaxC - 1.0) THEN
                _bDewAlarm := FALSE;                            // 回落 1 °C 回差：越限告警释放
            END_IF
            IF fDewPointC <= (fDewSevereC - 1.0) THEN
                _bDewSevere := FALSE;                           // 回落 1 °C 回差：严重告警释放
            END_IF
        END_IF
    END_IF
END_IF

(* —— 段 5：相位机（只做迁移；出口在段 7） —— *)
CASE _eState OF

E_DL_N2PurgeState.eIdle:
    IF rtStart.Q AND bEnable AND (NOT _bFault) AND (NOT _bCfgBad) THEN
        _eState := E_DL_N2PurgeState.eEstablish;      // 起始触发：进建立相
        _bEstBreak := TRUE;                          // 建立窗口从零计时
        _bInBandBrk := TRUE;                         // 入带计时从零
    END_IF

E_DL_N2PurgeState.eEstablish:
    IF (NOT bEnable) OR _bFault THEN
        _eState := E_DL_N2PurgeState.eFault;         // 失能或故障：进故障相（bPurgeOk 已为假）
    ELSIF _bInBand THEN
        _eState := E_DL_N2PurgeState.ePurged;        // 流量入带（含持续窗满）：进吹扫相
        _uInfo := 16#0003_010F;                      // 信息级：吹扫建立成功
    ELSIF tonEstablish.Q THEN
        _bEstTimeout := TRUE;                        // 建立超时保持量
        _uFault := 16#0003_021F;                     // 故障级：建立超时
        _bFault := TRUE;                             // 锁存
        bError  := TRUE;                             // 故障标志置位（R45 配对）
        _eState := E_DL_N2PurgeState.eTimeout;       // 进超时相
    END_IF

E_DL_N2PurgeState.ePurged:
    IF (NOT bEnable) OR _bFault THEN
        _eState := E_DL_N2PurgeState.eFault;         // 失能或故障：进故障相
    ELSIF NOT _bInBand THEN
        IF tonEstablish.Q THEN
            _bEstTimeout := TRUE;                    // 吹扫中流量持续离带：按建立失败处理
            _uFault := 16#0003_021F;                 // 故障级：建立超时（复用同一根因码）
            _bFault := TRUE;                         // 锁存
            bError  := TRUE;                         // 故障标志置位（R45 配对）
            _eState := E_DL_N2PurgeState.eTimeout;   // 进超时相
        END_IF
    ELSIF rtStart.Q THEN
        _bEstBreak := TRUE;                          // 再次起始：重建窗口（不停吹扫）
        _bInBandBrk := TRUE;                         // 入带计时重启
    END_IF

E_DL_N2PurgeState.eTimeout:
    IF (NOT _bFault) AND (NOT _bCfgBad) AND bEnable AND _bInBand THEN
        _eState := E_DL_N2PurgeState.ePurged;        // 流量恢复入带且码已清：回吹扫相
        _bEstTimeout := FALSE;                       // 超时保持量释放（与按码专清同源）
    END_IF

E_DL_N2PurgeState.eFault:
    IF (NOT _bFault) AND (NOT _bCfgBad) AND bEnable THEN
        _eState := E_DL_N2PurgeState.eIdle;          // 锁存已清且组态合法：回空闲等下一次起始
    END_IF

ELSE
    _uFault := 16#0003_025F;                         // 故障级：相位 ID 越界（枚举兜底）
    _bFault := TRUE;                                 // 锁存
    bError  := TRUE;                                 // 故障标志置位（R45 配对）
    _eState := E_DL_N2PurgeState.eFault;             // 强制回故障相
END_CASE

(* 段 5B｜021F 按码专清：入带持续窗满且无其它故障 → 建立超时可解（R188 可达清除边） *)
IF (_uFault = 16#0003_021F) AND _bInBand AND tonInBand.Q THEN
    _uFault := 16#0000_0000;                         // 清锁存码
    _bFault := FALSE;                                // 锁存位同步清
    _bEstTimeout := FALSE;                           // 超时保持量与码同源释放
END_IF

(* —— 段 6：故障码优先级链（信号无效优先于越限，越限优先于超时；R190 归因唯一） —— *)
IF _bCfgBad THEN
    _uFault := 16#0003_020F;                         // 组态非法优先上报
    _bFault := TRUE;
    bError  := TRUE;
ELSIF _bDewBad THEN
    _uFault := 16#0003_022F;                         // 露点信号无效优先于数值判据
    _bFault := TRUE;
    bError  := TRUE;
END_IF

(* —— 段 7：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
bEstablishTimeout := _bEstTimeout;                   // 建立超时出口（保持型）
bDewPointAlarm    := _bDewAlarm;                     // 露点越限出口（保持型）
bDewSevereAlarm   := _bDewSevere;                    // 严重越限出口（保持型）
bPurgeOk := bEnable AND (_eState = E_DL_N2PurgeState.ePurged) AND _bInBand AND
            (NOT _bDewAlarm) AND (NOT _bDewBad) AND (NOT _bFault) AND (NOT _bCfgBad);  // 合格判定（全条件）
eStateOut := _eState;                                // 状态出口
IF _bFault THEN
    nErrId := _uFault;                               // 故障锁存码回放（不在故障相按当下输入重推）
    bError := TRUE;                                  // 故障出口派生自锁存
ELSE
    nErrId := _uInfo;                                // 信息码
END_IF
bValid := bEnable AND (NOT _bFault) AND (NOT _bCfgBad);  // 判据可用

END_FUNCTION_BLOCK
