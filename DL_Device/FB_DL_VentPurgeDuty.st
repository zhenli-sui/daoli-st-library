(*
  FB_DL_VentPurgeDuty  —  双塔吸附轮值与穿透提前切换（N2 吹扫/干燥塔轮值台）/ Twin-tower purge duty rotation
  分类 Category : DL_Device
  码位 Code     : 16#03_2_0D
  版本 Version  : 1.0.0
  来源 Source   : t2-8-isa88 — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : ISA-88 批次/阶段公开语义借鉴（设备模块轮值、阶段状态），clean-room 实现，未复制源码行
  功能 Function : 1) 轮值计时：值班塔累计运行到 tSwitchInterval（**以小时口径组态 T#8H，内部换算为 ms 计时**）
                     即切换；吸附塔压差越过 fBreakthroughKpa（穿透门限）则**提前切换**并置穿透告警；
                  2) 切换时序：先并上目标塔（tSwitchOverlap 重叠期两塔同时在线，按允许处理），重叠结束再关旧塔；
                  3) 单塔不可用则禁切：保持当前运行塔继续值班并告警（不强行切到不可用塔）；
                  4) 两塔均不可用 → bBothFault 锁存；切换重叠期出现两塔同时离线 → 严重故障 022D（独立归因）。
  边界 Boundary : ① fBreakthroughKpa <= 0 / tSwitchInterval <= 0 / tSwitchOverlap <= 0 /
                      tSwitchOverlap >= tSwitchInterval 均判组态错 020D，状态进 eFault 不投运；
                  ② 双塔同时在线仅在切换重叠期合法；非重叠期同时在线属状态异常，按切换相强制收敛（不新增码）；
                  ③ 解除式自证：bBothFault 解除 = bReset AND (bTowerAAvail OR bTowerBAvail)
                     （两条件均由引脚可满足，R28-1）；022D 解除 = bReset 且重叠期已结束；
                  ④ 切换计数器为 UINT，到 65534 后**饱和不再自增**（禁回绕，回绕会让维护周期台账归零）；
                  ⑤ bSwitchCmd 为**单拍脉冲**（脉冲语义：置位 1 个 PLC 周期），内部 _bSwitchPulse 置位后
                     段 8 统一映射，次拍段 1 清零（两段式，R187①）；
                  ⑥ 压差非有限（NaN / 超上界）时不作为切换判据（不得因坏值提前切塔），置信息级 013D。
  依赖 Depends  : 仅 Standard.library（TON / R_TRIG / ABS / MIN / MAX），零外部组件依赖
  同拍双窗配比  : tSwitchOverlap（重叠期）与 tSwitchInterval（轮值周期）同源于切换节奏；
                  配比约束 tSwitchOverlap < tSwitchInterval（组态闸强制），保证重叠期不会越过下一次轮值点

  码表 Error codes（本件格 03_2_0D，子码步进 +0x10）:
    16#0003_020D 故障级：组态非法（穿透门限 <= 0 / 轮值周期 <= 0 / 重叠期 <= 0 / 重叠期 >= 轮值周期）
    16#0003_021D 故障级：双塔均不可用（bBothFault 锁存）
    16#0003_022D 故障级：切换重叠期两塔同时离线（严重故障，独立归因）
    16#0003_023D 故障级：状态机落 ELSE 兜底（非法相位 ID）
    16#0003_010D 信息级：穿透超限提前切换（不置 bError）
    16#0003_011D 信息级：目标塔不可用，禁止切换并保持运行塔（不置 bError）
    16#0003_012D 信息级：轮值到点正常切换（不置 bError）
    16#0003_013D 信息级：压差反馈非有限，本拍不参与切换判据（不置 bError）

  修订历史 Revision :
    2026-11-18  v1.0.0  R37 首版
*)

TYPE E_DL_PurgeDutyState :
(
    eIdle      := 0,   // 空闲：未使能，双塔全停 / Idle, both towers off
    eRunA      := 10,  // A 塔值班 / Tower A online
    eRunB      := 20,  // B 塔值班 / Tower B online
    eSwitching := 30,  // 切换重叠：两塔同时在线（按允许处理）/ Switching overlap, both towers online
    eFault     := 90   // 故障：锁存待复位 / Fault, latched until reset
);
END_TYPE

FUNCTION_BLOCK FB_DL_VentPurgeDuty
VAR_INPUT
    bEnable         : BOOL := FALSE;           // 总使能，FALSE 时双塔全停 / Master enable, both towers off when low
    bReset          : BOOL := FALSE;           // 复位，上升沿清故障锁存 / Reset, rising edge clears the latch
    bTowerAAvail    : BOOL := FALSE;           // A 塔可用（无故障且再生完成）/ Tower A available
    bTowerBAvail    : BOOL := FALSE;           // B 塔可用（无故障且再生完成）/ Tower B available
    fTowerADpKpa    : REAL := 0.0;             // A 塔吸附压差 [kPa]，域 >= 0 / Tower A adsorption differential [kPa]
    fTowerBDpKpa    : REAL := 0.0;             // B 塔吸附压差 [kPa]，域 >= 0 / Tower B adsorption differential [kPa]
    fBreakthroughKpa : REAL := 3.5;            // 穿透门限 [kPa]，域 > 0 / Breakthrough threshold [kPa]
    tSwitchInterval : TIME := T#8H;            // 轮值周期（**小时口径**组态，内部换算 ms 计时）[h] / Duty interval configured in hours
    tSwitchOverlap  : TIME := T#30S;           // 切换重叠期（两塔同时在线）[ms]，域 > 0 且 < 轮值周期 / Switch overlap [ms]
    bForceSwitch    : BOOL := FALSE;           // 手动强制切换（上升沿受理，维修用）/ Manual forced switch, rising edge
END_VAR
VAR_OUTPUT
    bTowerAOnline   : BOOL;                    // A 塔在线 / Tower A online
    bSwitchCmd      : BOOL;                    // 切换指令（脉冲语义：置位 1 个 PLC 周期）/ Switch command, asserted for one PLC scan
    bBreakthroughWarn : BOOL;                  // 穿透告警（值班塔压差越门限）/ Breakthrough warning on the online tower
    bBothFault      : BOOL;                    // 双塔均不可用（锁存）/ Both towers unavailable, latched
    nSwitchCount    : UINT;                    // 累计切换次数 [次]，饱和不回绕 / Switch count, saturated, never wrapped
    fRemainSec      : REAL;                    // 本轮值班剩余时间 [s] / Remaining duty time [s]
    bValid          : BOOL;                    // 判据可用标志 / Criteria usable
    bError          : BOOL;                    // 故障标志，派生自锁存 / Fault flag derived from the latch
    nErrId          : UDINT;                   // 事件码，0 = 无事件 / Event code, 0 = no event
    eStateOut       : E_DL_PurgeDutyState;     // 状态出口，段尾单点映射 / State outlet, mapped at the tail
END_VAR
VAR
    tonDuty      : TON;                        // 轮值计时，每拍无条件调用 / Duty timer, called unconditionally
    tonOverlap   : TON;                        // 重叠期计时，每拍无条件调用 / Overlap timer, called unconditionally
    tonHeart     : TON;                        // 周期心跳窗，自复位 / Periodic heartbeat window, self-resetting
    rtReset      : R_TRIG;                     // 复位上升沿 / Reset rising edge
    rtForce      : R_TRIG;                     // 强制切换上升沿 / Forced switch rising edge
    _eState      : E_DL_PurgeDutyState := E_DL_PurgeDutyState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _uFault      : UDINT;                      // 故障码锁存 / Latched fault code
    _uInfo       : UDINT;                      // 信息码，每拍重算 / Information code, recomputed per scan
    _bFault      : BOOL;                       // 故障锁存位 / Latched fault bit
    _bBothFault  : BOOL;                       // 双塔不可用保持量 / Held both-unavailable value
    _bParamBad   : BOOL;                       // 组态非法聚合 / Configuration invalid aggregate
    _bAOnline    : BOOL;                       // A 塔在线内部量 / Internal tower A online
    _bBOnline    : BOOL;                       // B 塔在线内部量 / Internal tower B online
    _bToTowerA   : BOOL;                       // 切换目标塔（TRUE = 切往 A）/ Switch target, TRUE means tower A
    _bSwitchPulse: BOOL;                       // 内部切换单拍标志 → 段 8 映射 / Internal one-shot switch flag
    _bDpValidA   : BOOL;                       // A 塔压差有效 / Tower A differential usable
    _bDpValidB   : BOOL;                       // B 塔压差有效 / Tower B differential usable
    _bBreachA    : BOOL;                       // A 塔穿透 / Tower A broke through
    _bBreachB    : BOOL;                       // B 塔穿透 / Tower B broke through
    _bSwitchNeed : BOOL;                       // 本拍需要切换（到点 / 穿透 / 强制）/ A switch is due this scan
    _bOverlapBad : BOOL;                       // 重叠期两塔同时离线 / Both towers offline during the overlap
    _nCountAcc   : UINT;                       // 切换计数保持量 [次] / Held switch count
    _tIntervalMs : DINT;                       // 轮值周期毫秒值 [ms]，已钳位 / Duty interval in milliseconds, clamped
    _tOverlapMs  : DINT;                       // 重叠期毫秒值 [ms]，已钳位 / Overlap in milliseconds, clamped
    _bSwEntry    : BOOL;                       // 进入切换相首拍标志（单拍脉冲两段式）/ First-scan-in-switching flag
    _bHeartBrk   : BOOL := TRUE;               // 心跳窗断输入一拍 / One-scan heartbeat break
    _bDutyBrk    : BOOL := TRUE;               // 轮值计时断输入一拍（换塔重启）/ One-scan duty break to restart the timer
    _bOverlapBrk : BOOL := TRUE;               // 重叠计时断输入一拍 / One-scan overlap break
END_VAR
VAR CONSTANT
    DL_CNT_MAX_UINT : UINT := 65534;   // 切换计数饱和上限 [次]（留 1 防回绕）/ Saturation ceiling, one below the wrap
    DL_DP_LIM_KPA   : REAL := 1000.0;  // 压差有限性上限 [kPa] / Differential magnitude ceiling [kPa]
    DL_HEART_WINDOW : TIME := T#2S;    // 心跳观察窗 [ms]，自复位节拍 / Heartbeat window, self-resetting
    DL_INTERVAL_MAX_MS : DINT := 2147483000;  // 轮值周期毫秒上限（防 TIME 溢出）[ms] / Interval ceiling to avoid TIME overflow
    DL_EPS          : REAL := 1.0E-6;  // 判零容差 [1] / Zero tolerance
END_VAR

(* —— 段 0：定时器与边缘检测无条件周期刷新（R182：调用语句不得置于 IF / CASE 内） —— *)
rtReset(CLK := bReset);                                          // 复位上升沿，每拍必调
rtForce(CLK := bForceSwitch);                                    // 强制切换上升沿，每拍必调
tonHeart(IN := (NOT tonHeart.Q) AND (NOT _bHeartBrk), PT := DL_HEART_WINDOW);  // 心跳窗自复位
_bHeartBrk := FALSE;                                             // 断输入拍在调用后自清
tonDuty(IN := (((_eState = E_DL_PurgeDutyState.eRunA) OR (_eState = E_DL_PurgeDutyState.eRunB))
               AND (NOT _bDutyBrk)),
        PT := DINT_TO_TIME(_tIntervalMs));                       // 轮值计时（h 口径已换算为 ms）
_bDutyBrk := FALSE;                                              // 断输入拍在调用后自清（换塔时置位重启）
tonOverlap(IN := (_eState = E_DL_PurgeDutyState.eSwitching) AND (NOT _bOverlapBrk),
           PT := DINT_TO_TIME(_tOverlapMs));                     // 重叠期计时（表达式入参）
_bOverlapBrk := FALSE;                                           // 断输入拍在调用后自清

(* —— 段 1：单拍量预清零（计数 / 保持量 / 锁存不入清单，R187①） —— *)
_uInfo       := 16#0000_0000;   // 信息码每拍重算
bError       := FALSE;          // 故障出口每拍重算，段 7 由锁存派生
bValid       := FALSE;          // 可用标志缺省 FALSE
bSwitchCmd   := FALSE;          // 切换出口缺省 FALSE（脉冲宽度 = 1 拍）
bBreakthroughWarn := FALSE;     // 穿透告警缺省 FALSE
_bSwitchPulse := FALSE;         // 内部切换单拍标志预清零
_bParamBad   := FALSE;          // 组态非法预清零
_bSwitchNeed := FALSE;          // 切换需求预清零
_bOverlapBad := FALSE;          // 重叠离线标志预清零
_bDpValidA   := FALSE;          // A 塔压差有效标志预清零
_bDpValidB   := FALSE;          // B 塔压差有效标志预清零

(* —— 段 2：复位沿清锁存 + 按码专清（bBothFault 解除式见边界 ③） —— *)
IF rtReset.Q THEN
    IF bTowerAAvail OR bTowerBAvail THEN
        _bBothFault := FALSE;          // 解除式：复位 AND 至少一塔可用
    END_IF
    IF NOT _bBothFault THEN
        _bFault := FALSE;              // 双塔故障保持量已释放才清故障位
        _uFault := 16#0000_0000;       // 清锁存码
    END_IF
END_IF
IF (_uFault = 16#0003_021D) AND (NOT _bBothFault) THEN
    _uFault := 16#0000_0000;           // 按码专清：双塔不可用保持量已释放 → 对应码清除
    _bFault := FALSE;                  // 锁存位同步清
END_IF

(* —— 段 3：组态域闸（含 h 口径换算与上限钳位，覆盖全部换算引脚，R151） —— *)
_tIntervalMs := TIME_TO_DINT(tSwitchInterval);          // 轮值周期：TIME 以小时口径组态，转换即 ms [ms]
_tOverlapMs  := TIME_TO_DINT(tSwitchOverlap);           // 重叠期毫秒值 [ms]
IF (fBreakthroughKpa <> fBreakthroughKpa) OR (fBreakthroughKpa <= 0.0) THEN
    _bParamBad := TRUE;                                 // 穿透门限非法（切换判据的分母语义）
END_IF
IF _tIntervalMs <= 0 THEN
    _bParamBad := TRUE;                                 // 轮值周期 <= 0
END_IF
IF _tIntervalMs > DL_INTERVAL_MAX_MS THEN
    _tIntervalMs := DL_INTERVAL_MAX_MS;                 // 上限钳位（防 TIME 表示溢出）
END_IF
IF _tOverlapMs <= 0 THEN
    _bParamBad := TRUE;                                 // 重叠期 <= 0（两塔无交叠会瞬时断气）
END_IF
IF (_tIntervalMs > 0) AND (_tOverlapMs >= _tIntervalMs) THEN
    _bParamBad := TRUE;                                 // 重叠期 >= 轮值周期：重叠尚未结束就该再切（不可能组态）
END_IF
IF _bParamBad THEN
    _uFault := 16#0003_020D;                            // 故障级：组态非法
    _bFault := TRUE;                                    // 锁存位置位（复位沿可清）
    bError  := TRUE;                                    // 故障标志置位（R45 配对）
    _eState := E_DL_PurgeDutyState.eFault;              // 进故障相
END_IF

(* —— 段 4：压差有效性、穿透判据与切换需求 —— *)
_bDpValidA := (fTowerADpKpa = fTowerADpKpa) AND (fTowerADpKpa >= 0.0) AND (fTowerADpKpa <= DL_DP_LIM_KPA);  // A 塔压差有效
_bDpValidB := (fTowerBDpKpa = fTowerBDpKpa) AND (fTowerBDpKpa >= 0.0) AND (fTowerBDpKpa <= DL_DP_LIM_KPA);  // B 塔压差有效
IF (NOT _bDpValidA) OR (NOT _bDpValidB) THEN
    _uInfo := 16#0003_013D;                             // 信息级：压差非有限，本拍不参与切换判据
END_IF
_bBreachA := _bDpValidA AND (fTowerADpKpa > fBreakthroughKpa);  // A 塔穿透（仅有效值参与）
_bBreachB := _bDpValidB AND (fTowerBDpKpa > fBreakthroughKpa);  // B 塔穿透（仅有效值参与）
IF (_eState = E_DL_PurgeDutyState.eRunA) THEN
    bBreakthroughWarn := _bBreachA;                     // 在线塔为 A：告警跟随 A
ELSIF (_eState = E_DL_PurgeDutyState.eRunB) THEN
    bBreakthroughWarn := _bBreachB;                     // 在线塔为 B：告警跟随 B
END_IF

_bSwitchNeed := tonDuty.Q OR rtForce.Q OR
                ((_eState = E_DL_PurgeDutyState.eRunA) AND _bBreachA) OR
                ((_eState = E_DL_PurgeDutyState.eRunB) AND _bBreachB);  // 到点 / 强制 / 在线塔穿透
IF _bSwitchNeed AND tonDuty.Q THEN
    _uInfo := 16#0003_012D;                             // 信息级：轮值到点切换
ELSIF _bSwitchNeed AND (((_eState = E_DL_PurgeDutyState.eRunA) AND _bBreachA) OR
                        ((_eState = E_DL_PurgeDutyState.eRunB) AND _bBreachB)) THEN
    _uInfo := 16#0003_010D;                             // 信息级：穿透超限提前切换
END_IF

(* —— 段 5：双塔可用性归因（三岔：均可用 / 单塔可用 / 均不可用） —— *)
IF (NOT bTowerAAvail) AND (NOT bTowerBAvail) THEN
    _bBothFault := TRUE;                                // 双塔均不可用：保持量置位
    _uFault := 16#0003_021D;                            // 故障级：双塔均不可用
    _bFault := TRUE;                                    // 锁存
    bError  := TRUE;                                    // 故障标志置位（R45 配对）
    _eState := E_DL_PurgeDutyState.eFault;              // 进故障相
END_IF

(* —— 段 6：相位机（只做迁移与在线/切换单拍标志；出口在段 8） —— *)
CASE _eState OF

E_DL_PurgeDutyState.eIdle:
    _bAOnline := FALSE;                                 // 空闲：两塔全停（唯一清零点在本相）
    _bBOnline := FALSE;
    IF bEnable AND (NOT _bFault) AND (NOT _bParamBad) THEN
        IF bTowerAAvail THEN
            _eState := E_DL_PurgeDutyState.eRunA;       // 首轮启动：优先 A 塔
            _bAOnline := TRUE;                          // A 塔上线
            _bDutyBrk := TRUE;                          // 轮值计时从零开始
        ELSIF bTowerBAvail THEN
            _eState := E_DL_PurgeDutyState.eRunB;       // A 不可用：B 塔上线
            _bBOnline := TRUE;                          // B 塔上线
            _bDutyBrk := TRUE;                          // 轮值计时从零开始
        END_IF
    END_IF

E_DL_PurgeDutyState.eRunA:
    _bAOnline := TRUE;                                  // A 塔在线
    _bBOnline := FALSE;                                 // B 塔离线（非重叠期）
    IF (NOT bEnable) OR (NOT bTowerAAvail) THEN
        IF bTowerBAvail THEN
            _bToTowerA := FALSE;                        // A 失效：切往 B
            _eState := E_DL_PurgeDutyState.eSwitching;  // 进切换重叠
            _bSwEntry := TRUE;                          // 切换首拍标志置位（单拍脉冲）
            _bOverlapBrk := TRUE;                       // 重叠计时从零
        ELSE
            _uInfo := 16#0003_011D;                     // 信息级：目标塔不可用，禁止切换
            _eState := E_DL_PurgeDutyState.eIdle;       // 回空闲（无可用塔，段 5 已置 021D）
            _bAOnline := FALSE;
        END_IF
    ELSIF _bSwitchNeed THEN
        IF bTowerBAvail THEN
            _bToTowerA := FALSE;                        // 切往 B
            _eState := E_DL_PurgeDutyState.eSwitching;  // 进切换重叠
            _bSwEntry := TRUE;                          // 切换首拍标志置位（单拍脉冲）
            _bOverlapBrk := TRUE;                       // 重叠计时从零
        ELSE
            _uInfo := 16#0003_011D;                     // 信息级：B 不可用，保持 A 继续值班
            _bDutyBrk := TRUE;                          // 轮值计时重启（避免每拍重复判到点）
        END_IF
    END_IF

E_DL_PurgeDutyState.eRunB:
    _bAOnline := FALSE;                                 // A 塔离线（非重叠期）
    _bBOnline := TRUE;                                  // B 塔在线
    IF (NOT bEnable) OR (NOT bTowerBAvail) THEN
        IF bTowerAAvail THEN
            _bToTowerA := TRUE;                         // B 失效：切往 A
            _eState := E_DL_PurgeDutyState.eSwitching;  // 进切换重叠
            _bSwEntry := TRUE;                          // 切换首拍标志置位（单拍脉冲）
            _bOverlapBrk := TRUE;                       // 重叠计时从零
        ELSE
            _uInfo := 16#0003_011D;                     // 信息级：目标塔不可用，禁止切换
            _eState := E_DL_PurgeDutyState.eIdle;       // 回空闲
            _bBOnline := FALSE;
        END_IF
    ELSIF _bSwitchNeed THEN
        IF bTowerAAvail THEN
            _bToTowerA := TRUE;                         // 切往 A
            _eState := E_DL_PurgeDutyState.eSwitching;  // 进切换重叠
            _bSwEntry := TRUE;                          // 切换首拍标志置位（单拍脉冲）
            _bOverlapBrk := TRUE;                       // 重叠计时从零
        ELSE
            _uInfo := 16#0003_011D;                     // 信息级：A 不可用，保持 B 继续值班
            _bDutyBrk := TRUE;                          // 轮值计时重启
        END_IF
    END_IF

E_DL_PurgeDutyState.eSwitching:
    _bAOnline := TRUE;                                  // 重叠期：两塔同时在线（按允许处理）
    _bBOnline := TRUE;
    IF _bSwEntry THEN
        _bSwitchPulse := TRUE;                          // 切换指令单拍：仅进入本相首拍置位，次拍段 1 清
        _bSwEntry := FALSE;                             // 首拍标志自清（唯一置假点）
    END_IF
    IF (NOT bTowerAAvail) AND (NOT bTowerBAvail) THEN
        _bOverlapBad := TRUE;                           // 重叠期两塔均不可用：严重故障（独立归因）
        _uFault := 16#0003_022D;                        // 故障级：重叠期两塔同时离线
        _bFault := TRUE;                                // 锁存
        bError  := TRUE;                                // 故障标志置位（R45 配对）
        _bAOnline := FALSE;                             // 安全侧：两塔全停
        _bBOnline := FALSE;
        _eState := E_DL_PurgeDutyState.eFault;          // 进故障相
    ELSIF tonOverlap.Q THEN
        _bAOnline := _bToTowerA;                        // 重叠结束：仅目标塔保持在线
        _bBOnline := NOT _bToTowerA;
        IF _nCountAcc < DL_CNT_MAX_UINT THEN
            _nCountAcc := _nCountAcc + 1;               // 切换计数 +1（饱和不回绕）
        END_IF
        IF _bToTowerA THEN
            _eState := E_DL_PurgeDutyState.eRunA;       // 目标 A：进 A 值班相
        ELSE
            _eState := E_DL_PurgeDutyState.eRunB;       // 目标 B：进 B 值班相
        END_IF
        _bDutyBrk := TRUE;                              // 新一轮轮值计时从零
    END_IF

E_DL_PurgeDutyState.eFault:
    _bAOnline := FALSE;                                 // 故障：两塔全停（安全侧）
    _bBOnline := FALSE;
    IF (NOT _bFault) AND (NOT _bParamBad) AND bEnable THEN
        _eState := E_DL_PurgeDutyState.eIdle;           // 锁存已清且组态合法：回空闲重新选塔
    END_IF

ELSE
    _uFault := 16#0003_023D;                            // 故障级：相位 ID 越界（枚举兜底）
    _bFault := TRUE;                                    // 锁存
    bError  := TRUE;                                    // 故障标志置位（R45 配对）
    _bAOnline := FALSE;                                 // 兜底安全侧：两塔全停
    _bBOnline := FALSE;
    _eState := E_DL_PurgeDutyState.eFault;              // 强制回故障相
END_CASE

(* —— 段 7：故障码优先级链与在线镜像仲裁（每个 bError 置位源在此均有码，R45） —— *)
IF _bParamBad THEN
    bError := TRUE;                                     // 组态非法：码已在段 3 置位（020D）
END_IF
IF _bOverlapBad AND (NOT _bFault) THEN
    _uFault := 16#0003_022D;                            // 独立归因：重叠期离线（即使其它码未置）
    _bFault := TRUE;                                    // 锁存
    bError  := TRUE;                                    // 故障标志置位（R45 配对）
    _bAOnline := FALSE;                                 // 安全侧
    _bBOnline := FALSE;
END_IF

(* —— 段 8：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
bTowerAOnline := _bAOnline;                             // A 塔在线出口
bSwitchCmd    := _bSwitchPulse;                         // 切换指令出口：宽度恰 1 个 PLC 周期
bBothFault    := _bBothFault;                           // 双塔不可用出口（保持量）
nSwitchCount  := _nCountAcc;                            // 切换计数出口（UINT，饱和）
IF _tIntervalMs > 0 THEN
    fRemainSec := (DINT_TO_REAL(_tIntervalMs) - TIME_TO_REAL(tonDuty.ET)) / 1000.0;  // 剩余秒数（分母已证 > 0）
ELSE
    fRemainSec := 0.0;                                  // 组态非法：剩余时间无意义，置 0
END_IF
IF fRemainSec < 0.0 THEN
    fRemainSec := 0.0;                                  // 下限保护（到点后不出现负剩余）
END_IF
eStateOut := _eState;                                   // 状态出口
IF _bFault THEN
    nErrId := _uFault;                                  // 故障锁存码回放（不在故障相按当下输入重推）
    bError := TRUE;                                     // 故障出口派生自锁存
ELSE
    nErrId := _uInfo;                                   // 信息码
END_IF
bValid := bEnable AND (NOT _bFault) AND (NOT _bParamBad);  // 判据可用

END_FUNCTION_BLOCK
