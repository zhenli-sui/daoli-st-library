(*
  FB_DL_FlyingCutSync  —  飞剪同步切（相位取模 / 切窗判据 / 电子齿轮追赶 / 单拍下刀）/ Flying-cut synchronisation
  分类 Category : DL_Motion
  码位 Code     : 16#04_0_A3
  版本 Version  : 1.0.1
  来源 Source   : t1-6-plcopen — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : PLCopen 飞剪/电子齿轮公开语义借鉴，clean-room 实现，仅借相位取模与切窗概念，未复制源码行
  功能 Function : 1) 主轴位置对 fCutLengthMm 取模（FLOOR 口径，负向同样收敛）得切长相位 fPhaseMm；
                  2) 相位落在 [fSyncWindowStartMm, fSyncWindowEndMm] 内置 bInSyncWindow，窗口内方允许下刀；
                  3) 同步误差 fSyncErrorMm = 刀轴位置 − 相位 × fCutOverlapRatio，进 fSyncTolMm 才发下刀脉冲；
                  4) 下刀脉冲 bCutCmd 为**单拍脉冲**（脉冲语义：置位 1 个 PLC 周期），由内部 _bCutPulse 置位、
                     段 8 统一出口映射，次拍段 1 清零，绝不在 CASE 内二次写输出（N2 / R187①）；
                  5) 切完按 tCutDwell 保压（刀在料内停留），保压结束进回程相，等相位越过窗尾再回等待相；
                  6) 每圈只允许一刀：以圈索引 fTurnsInt 与 _nCutTurnIdx 比较做单圈互锁（防同圈重刀）。
  边界 Boundary : ① fCutLengthMm <= 0 判组态错（取模除零前置，R45）；窗口起止倒置或宽 <= 0 判组态错且不运行；
                      fSyncTolMm <= 0 / fCutOverlapRatio <= 0 同判组态错，码 00A3，状态进 eFault；
                  ② 未同步时**禁止** bCutCmd：互锁写在件内（窗口 + 容差 + 单圈 + 主轴正向四条件同时成立），
                     不外抛给上层组合逻辑（防上层漏联锁切刀撞料）；
                  ③ nCutCount 到 uCountPreset 后 bPresetReached 置位；计数在 UDINT 上限前饱和**不回绕**，
                     预置比较用「增量前预判」而非事后比较（不给 TRUNC(x)+1 型写法，R28-3）；
                  ④ 切窗内主轴反转立即判废并置 01A3（反转期刀轴与料带速度矢量相反，下刀即撕料）；
                  ⑤ uCountPreset = 0 视为「不启用预置」：bPresetReached 恒 FALSE，置信息级 07A3；
                  ⑥ 解除路径自证：_bFault 清除 = rtReset.Q（引脚可满足）；01A3 另可由「主轴恢复正向
                     且相位出新窗」按码专清（两路径互不掩盖，R188）。
  依赖 Depends  : I_DL_MotionAxis / E_DL_AxisState（DL_Motion 既有契约件，零修改，只注入不实例化）；
                  仅 Standard.library（TON / R_TRIG / ABS / MIN / MAX）
  同拍双窗配比  : tCutDwell（刀内停留）与 tonGuard 自复位心跳窗不同源；配比约束
                  tCutDwell <= DL_GUARD_WINDOW / 2，保证保压段内至少一次心跳判活（R100）

  码表 Error codes（本件格 04_0_A3，子码步进 +0x10）:
    16#0004_00A3 故障级：组态非法（切长 <= 0 / 窗口倒置或宽 <= 0 / 容差 <= 0 / 重叠比 <= 0）
    16#0004_01A3 故障级：切窗内主轴反转，本次切割判废
    16#0004_03A3 故障级：状态机落 ELSE 兜底（非法相位 ID）
    16#0004_04A3 信息级：下刀脉冲已发出（bCutCmd 单拍同源，不置 bError）
    16#0004_05A3 信息级：切割计数达预置（bPresetReached 同拍置位，不置 bError）
    16#0004_06A3 信息级：切窗内同步超差，本次跳过不下刀（互锁生效，不置 bError）
    16#0004_07A3 信息级：预置计数未组态（uCountPreset = 0，预置出口恒 FALSE）

  修订历史 Revision :
    2026-11-18  v1.0.0  R37 首版
*)

TYPE E_DL_FlyingCutState :
(
    eIdle       := 0,   // 空闲：未使能，不出切窗判据 / Idle, no window evaluation while disabled
    eWaiting    := 10,  // 等待：等相位进入切窗 / Waiting for the phase to enter the cut window
    eSyncWindow := 20,  // 窗内：按容差追赶，达标即下刀 / Inside the window, chasing the tolerance
    eCutting    := 30,  // 切割：刀在料内保压（tCutDwell）/ Cutting, the knife dwells inside the web
    eReturning  := 40,  // 回程：等相位越过窗尾，准备下一圈 / Returning, waiting for the phase to pass the window end
    eFault      := 90   // 故障：组态非法或反转判废锁定 / Fault, illegal configuration or a latched reversal reject
);
END_TYPE

FUNCTION_BLOCK FB_DL_FlyingCutSync
VAR_INPUT
    bEnable        : BOOL := FALSE;              // 总使能，FALSE 时禁止下刀 / Master enable, a low level forbids cutting
    bReset         : BOOL := FALSE;              // 复位，上升沿清故障锁存 / Reset, rising edge clears the latch
    fCutLengthMm   : REAL := 1000.0;             // 单刀切长（取模基数）[mm]，域 > 0 / Cut length, the modulo base [mm]
    fSyncWindowStartMm : REAL := 5.0;            // 切窗起点相位 [mm]，域 >= 0 / Window start phase [mm]
    fSyncWindowEndMm   : REAL := 45.0;           // 切窗终点相位 [mm]，须 > 起点 / Window end phase [mm]
    fCutOverlapRatio   : REAL := 1.0;            // 刀轴等效行程与相位之比 [1]，域 > 0 / Knife travel per phase unit [1]
    tCutDwell      : TIME := T#120MS;            // 刀内保压时间 [ms]，域 > 0 / Knife dwell inside the web [ms]
    fSyncTolMm     : REAL := 0.5;                // 允许下刀的同步误差 [mm]，域 > 0 / Sync tolerance permitting a cut [mm]
    uCountPreset   : UDINT := 10000;             // 切割计数预置 [次]，0 = 不启用预置 / Cut count preset, zero disables it
END_VAR
VAR_OUTPUT
    bCutCmd        : BOOL;                       // 下刀指令（脉冲语义：置位 1 个 PLC 周期）/ Cut command, asserted for exactly one PLC scan
    bInSyncWindow  : BOOL;                       // 相位处于切窗内 / Phase inside the cut window
    fSyncErrorMm   : REAL;                       // 同步误差 [mm]，刀轴位置 − 相位×重叠比 / Sync error [mm]
    fPhaseMm       : REAL;                       // 当前切长相位 [mm]，域 [0, fCutLengthMm) / Present phase inside one cut [mm]
    nCutCount      : UDINT;                      // 累计切割次数 [次]，饱和不回绕 / Accumulated cut count, saturated, never wrapped
    bPresetReached : BOOL;                       // 计数达预置标志（保持型）/ Preset reached flag, held
    bValid         : BOOL;                       // 判据可用标志 / Criteria usable
    bError         : BOOL;                       // 故障标志，派生自锁存 / Fault flag derived from the latch
    nErrId         : UDINT;                      // 事件码，0 = 无事件 / Event code, 0 = no event
    eStateOut      : E_DL_FlyingCutState;        // 状态出口，段尾单点映射 / State outlet, mapped at the tail
END_VAR
VAR_IN_OUT
    iMasterAxis    : I_DL_MotionAxis;            // 料带线轴接口引用（注入，不实例化）/ Web master axis reference, injected
    iCutAxis       : I_DL_MotionAxis;            // 刀轴接口引用（注入，不实例化）/ Knife axis reference, injected
END_VAR
VAR
    tonDwell       : TON;                        // 刀内保压计时，每拍无条件调用 / Knife dwell timer, called unconditionally
    tonGuard       : TON;                        // 周期心跳窗，自复位 / Periodic guard window, self-resetting
    rtReset        : R_TRIG;                     // 复位上升沿 / Reset rising edge
    _eState        : E_DL_FlyingCutState := E_DL_FlyingCutState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _uFault        : UDINT;                      // 故障码锁存 / Latched fault code
    _uInfo         : UDINT;                      // 信息码，每拍重算 / Information code, recomputed per scan
    _bFault        : BOOL;                       // 故障锁存位 / Latched fault bit
    _bParamBad     : BOOL;                       // 组态非法聚合 / Configuration invalid aggregate
    _bCutPulse     : BOOL;                       // 内部下刀单拍标志 → 段 8 映射 / Internal one-shot cut flag
    _bPresetReached: BOOL;                       // 预置到达保持量 / Held preset-reached value
    _bSameTurn     : BOOL;                       // 本圈已下刀（单圈互锁）/ A cut already happened in this turn
    _bWindowNow    : BOOL;                       // 本拍窗内判据 / Window predicate this scan
    _bReverse      : BOOL;                       // 切窗内主轴反转 / Master reversal inside the window
    _fTurns        : REAL;                       // 位置除切长的商（圈数，实数）/ Turn count as a real quotient
    _fPhase        : REAL;                       // 切长相位 [mm] / Phase inside one cut [mm]
    _fSyncErr      : REAL;                       // 同步误差 [mm] / Sync error [mm]
    _fExpPos       : REAL;                       // 刀轴期望等效行程 [mm] / Expected knife equivalent travel [mm]
    _dTurnsInt     : DINT;                       // FLOOR 后的圈索引（负向同样收敛）/ Floor turn index, negative safe
    _uCountAcc     : UDINT;                      // 计数保持量 [次] / Held count value
    _nCutTurnIdx   : DINT := -1;                 // 最后一次下刀的圈索引（-1=尚无下刀，防初值吃首圈）/ Turn index, -1 = none yet
    _bGuardBreak   : BOOL := TRUE;               // 心跳窗断输入一拍 / One-scan guard break
END_VAR
VAR CONSTANT
    DL_CNT_MAX     : UDINT := 16#FFFF_FFFE;      // 计数饱和上限（留 1 位防溢出）[次] / Saturation ceiling, one below the wrap
    DL_EPS         : REAL  := 1.0E-6;            // 判零容差 [1] / Zero tolerance
    DL_GUARD_WINDOW : TIME := T#2S;              // 心跳观察窗 [ms]，自复位节拍 / Guard window, self-resetting
    DL_WIN_MAX_MM  : REAL  := 1.0E6;             // 相位与搜索量绝对值上限 [mm] / Magnitude ceiling for phases [mm]
END_VAR

(* —— 段 0：定时器与边缘检测无条件周期刷新（R182：调用语句本身不得置于 IF 内） —— *)
rtReset(CLK := bReset);                                          // 复位上升沿，每拍必调
tonGuard(IN := (NOT tonGuard.Q) AND (NOT _bGuardBreak), PT := DL_GUARD_WINDOW);  // 心跳窗自复位
_bGuardBreak := FALSE;                                           // 断输入拍在调用后自清
tonDwell(IN := (_eState = E_DL_FlyingCutState.eCutting), PT := tCutDwell);       // 保压计时（表达式入参）

(* —— 段 1：单拍量预清零（计数 / 预置 / 锁存不入清单，R187①） —— *)
_uInfo   := 16#0000_0000;   // 信息码每拍重算
bError   := FALSE;          // 故障出口每拍重算，段 7 由锁存派生
bValid   := FALSE;          // 判据可用缺省 FALSE
bCutCmd  := FALSE;          // 下刀出口缺省 FALSE（段 8 单点映射，脉冲宽度 = 1 拍）
_bCutPulse := FALSE;        // 内部下刀单拍标志预清零
_bParamBad := FALSE;        // 组态非法预清零
_bWindowNow := FALSE;       // 窗内判据预清零
_bReverse := FALSE;         // 反转标志预清零
_bSameTurn := FALSE;        // 单圈互锁标志预清零

(* —— 段 2：复位沿清锁存（按码专清 + 恢复沿清码，R188） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;            // 复位沿清锁存位
    _uFault := 16#0000_0000;     // 复位沿清锁存码
END_IF

(* —— 段 3：组态域闸（覆盖全部参与判据换算的引脚，R151） —— *)
IF (fCutLengthMm <> fCutLengthMm) OR (fCutLengthMm <= 0.0) OR (fCutLengthMm > DL_WIN_MAX_MM) THEN
    _bParamBad := TRUE;          // 切长非法：取模除零前置（R45）
END_IF
IF (fSyncWindowStartMm <> fSyncWindowStartMm) OR (fSyncWindowStartMm < 0.0) THEN
    _bParamBad := TRUE;          // 窗起点非法
END_IF
IF (fSyncWindowEndMm <> fSyncWindowEndMm) OR (fSyncWindowEndMm <= fSyncWindowStartMm) THEN
    _bParamBad := TRUE;          // 窗止倒置或宽度 <= 0
END_IF
IF (NOT _bParamBad) AND ((fSyncWindowEndMm - fSyncWindowStartMm) <= 0.0) THEN
    _bParamBad := TRUE;          // 窗宽 <= 0（显式复检，防浮点相消导致宽度判据静默失效）
END_IF
IF (fSyncTolMm <> fSyncTolMm) OR (fSyncTolMm <= 0.0) THEN
    _bParamBad := TRUE;          // 同步容差非法（互锁门限为 0 等于永不下刀）
END_IF
IF (fCutOverlapRatio <> fCutOverlapRatio) OR (fCutOverlapRatio <= 0.0) THEN
    _bParamBad := TRUE;          // 重叠比非法（期望行程的比例因子）
END_IF
IF TIME_TO_DINT(tCutDwell) <= 0 THEN
    _bParamBad := TRUE;          // 保压时间非法（零保压会让刀在料内瞬时撤回）
END_IF
IF _bParamBad THEN
    _uFault := 16#0004_00A3;     // 故障级：组态非法
    _bFault := TRUE;             // 锁存位置位（复位沿可清）
    bError  := TRUE;             // 故障标志置位（R45 配对）
    _eState := E_DL_FlyingCutState.eFault;  // 状态机进故障相
END_IF

(* —— 段 4：相位取模与同步误差（仅无组态错时计算） —— *)
IF NOT _bParamBad THEN
    _fTurns := iMasterAxis.fPosition / fCutLengthMm;               // 圈数商（分母已证 > 0）
    _dTurnsInt := REAL_TO_DINT(_fTurns);                           // 向零截断
    IF (_fTurns < 0.0) AND (ABS(_fTurns - DINT_TO_REAL(_dTurnsInt)) > DL_EPS) THEN
        _dTurnsInt := _dTurnsInt - 1;                              // 负向修正为 FLOOR，保证相位恒 >= 0
    END_IF
    _fPhase := iMasterAxis.fPosition - (DINT_TO_REAL(_dTurnsInt) * fCutLengthMm);  // 切长相位 [mm]
    IF _fPhase < 0.0 THEN
        _fPhase := _fPhase + fCutLengthMm;                         // 相消残差归正（浮点尾差兜底）
    END_IF
    IF _fPhase >= fCutLengthMm THEN
        _fPhase := _fPhase - fCutLengthMm;                         // 上行越界折回一格
    END_IF
    _bWindowNow := (_fPhase >= fSyncWindowStartMm) AND (_fPhase <= fSyncWindowEndMm);  // 窗内判据
    _fExpPos := _fPhase * fCutOverlapRatio;                        // 刀轴期望等效行程 [mm]
    _fSyncErr := iCutAxis.fPosition - _fExpPos;                    // 同步误差 [mm]
    IF _bWindowNow AND (iMasterAxis.fVelocity < -DL_EPS) THEN
        _bReverse := TRUE;                                         // 窗内主轴反转：判废
    END_IF
    IF _dTurnsInt = _nCutTurnIdx THEN
        _bSameTurn := TRUE;                                        // 本圈已下刀：单圈互锁生效
    END_IF
    fPhaseMm     := _fPhase;                                       // 相位出口
    fSyncErrorMm := _fSyncErr;                                     // 误差出口
END_IF
bInSyncWindow := _bWindowNow;                                      // 窗内出口（诊断与上层互锁共用）

(* 段 4B｜按码专清：01A3 的恢复沿条件依赖本拍相位与速度，故必须置于段 4 之后判（R188 可达清除边） *)
IF (_uFault = 16#0004_01A3) AND _bFault AND (iMasterAxis.fVelocity > DL_EPS) AND (NOT _bWindowNow) THEN
    _uFault := 16#0000_0000;          // 主轴恢复正向且相位已出新窗：反转判废可解
    _bFault := FALSE;                 // 锁存位同步清（与 rtReset.Q 路径互不掩盖）
END_IF

(* —— 段 5：相位机（只做迁移与内部单拍标志；输出在段 8） —— *)
CASE _eState OF

E_DL_FlyingCutState.eIdle:
    IF bEnable AND (NOT _bFault) AND (NOT _bParamBad) THEN
        _eState := E_DL_FlyingCutState.eWaiting;                   // 使能且无故障：进等待相
    END_IF

E_DL_FlyingCutState.eWaiting:
    IF (NOT bEnable) THEN
        _eState := E_DL_FlyingCutState.eIdle;                      // 失能：回空闲，禁止下刀
    ELSIF _bReverse THEN
        _uFault := 16#0004_01A3;                                   // 故障级：切窗内主轴反转
        _bFault := TRUE;                                           // 锁存
        bError  := TRUE;                                           // 故障标志置位（R45 配对）
        _eState := E_DL_FlyingCutState.eFault;                     // 进故障相
    ELSIF _bWindowNow THEN
        _eState := E_DL_FlyingCutState.eSyncWindow;                // 进窗：开始追赶
    END_IF

E_DL_FlyingCutState.eSyncWindow:
    IF (NOT bEnable) THEN
        _eState := E_DL_FlyingCutState.eIdle;                      // 失能：退出窗内（不下刀）
    ELSIF _bReverse THEN
        _uFault := 16#0004_01A3;                                   // 故障级：切窗内主轴反转
        _bFault := TRUE;                                           // 锁存
        bError  := TRUE;                                           // 故障标志置位（R45 配对）
        _eState := E_DL_FlyingCutState.eFault;                     // 进故障相
    ELSIF NOT _bWindowNow THEN
        _uInfo := 16#0004_06A3;                                    // 信息级：出窗未达容差，本次跳过
        _eState := E_DL_FlyingCutState.eWaiting;                    // 回等待相，等下一圈
    ELSIF _bSameTurn THEN
        _eState := E_DL_FlyingCutState.eWaiting;                    // 本圈已切：不许重刀，回等待
    ELSIF ABS(_fSyncErr) <= fSyncTolMm THEN
        _bCutPulse := TRUE;                                        // 四条件同时成立：置内部下刀单拍
        _nCutTurnIdx := _dTurnsInt;                                // 记录本圈已下刀（单圈互锁）
        _eState := E_DL_FlyingCutState.eCutting;                   // 进保压相
        _bGuardBreak := TRUE;                                      // 心跳窗重启（保压段重新判活）
        IF _uCountAcc < DL_CNT_MAX THEN
            _uCountAcc := _uCountAcc + 1;                          // 计数 +1（饱和不回绕，R28-3）
        END_IF
        IF (uCountPreset > 0) AND (_uCountAcc >= uCountPreset) THEN
            IF NOT _bPresetReached THEN
                _uInfo := 16#0004_05A3;                            // 信息级：计数达预置（首次置位拍）
            END_IF
            _bPresetReached := TRUE;                               // 预置到达保持量置位
        END_IF
    ELSE
        _uInfo := 16#0004_06A3;                                    // 信息级：窗内同步超差，互锁生效不下刀
    END_IF

E_DL_FlyingCutState.eCutting:
    IF tonDwell.Q THEN
        _eState := E_DL_FlyingCutState.eReturning;                 // 保压完成：进回程相
    END_IF

E_DL_FlyingCutState.eReturning:
    IF (NOT bEnable) THEN
        _eState := E_DL_FlyingCutState.eIdle;                      // 失能：回空闲
    ELSIF (_fPhase > fSyncWindowEndMm) OR (_fPhase < fSyncWindowStartMm) THEN
        _eState := E_DL_FlyingCutState.eWaiting;                   // 相位已出窗：回等待相等下一圈
    END_IF

E_DL_FlyingCutState.eFault:
    IF (NOT _bFault) AND (NOT _bParamBad) AND bEnable THEN
        _eState := E_DL_FlyingCutState.eWaiting;                   // 锁存已清且组态合法：回等待相
    END_IF

ELSE
    _uFault := 16#0004_03A3;                                       // 故障级：相位 ID 越界（枚举兜底）
    _bFault := TRUE;                                               // 锁存
    bError  := TRUE;                                               // 故障标志置位（R45 配对）
    _eState := E_DL_FlyingCutState.eFault;                         // 强制回故障相
END_CASE

(* —— 段 6：预置比较（保持量推进 + 计数上限兜底，禁 TRUNC(x)+1 型写法） —— *)
IF uCountPreset = 0 THEN
    _bPresetReached := FALSE;             // 未组态预置：出口恒 FALSE（不做数值比较）
    _uInfo := 16#0004_07A3;               // 信息级：预置未组态
ELSIF _uCountAcc >= uCountPreset THEN
    _bPresetReached := TRUE;              // 已达预置：保持置位（不随计数变化回落）
END_IF

(* —— 段 7：故障码优先级链（每个 bError 置位源在此均有码，R45 配对） —— *)
IF _bParamBad THEN
    _uFault := 16#0004_00A3;              // 组态非法优先上报（其余码不得掩盖）
    _bFault := TRUE;                      // 锁存
    bError  := TRUE;                      // 故障标志置位
END_IF

(* —— 段 8：出口单点映射（名实同源；脉冲两段式已在段 1 与段 5 完成） —— *)
bCutCmd        := _bCutPulse;             // 下刀出口：仅本拍置位，宽度恰 1 个 PLC 周期
nCutCount      := _uCountAcc;             // 计数出口
bPresetReached := _bPresetReached;        // 预置出口（保持型）
eStateOut      := _eState;                // 状态出口
IF _bFault THEN
    nErrId := _uFault;                    // 故障锁存码回放（不在故障相按当下输入重推）
    bError := TRUE;                       // 故障出口派生自锁存
ELSE
    nErrId := _uInfo;                     // 信息码
END_IF
bValid := bEnable AND (NOT _bFault) AND (NOT _bParamBad);  // 判据可用：使能且无故障且组态合法

END_FUNCTION_BLOCK
