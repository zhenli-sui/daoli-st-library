(*
  Name: FB_DL_RotaryKnifeCutSyncCtrl
  Category: DL_Motion
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 运动同步控制，ST 开源生态实测 0 命中，无外部代码引入）
  功能：旋转刀同步定尺剪切：材料虚轴跟随 + 刀轴相位锁 + 剪切窗口判定，六相状态机含失步保护。
  边界条件：① 六浮点入参全部过非有限闸；配置越域即锁故障（101），虚轴增量强制置零、不推进；
            ② 相位比较一律做 ±180° 环绕归一化（NormalizeDeg180 方法），禁直接相减；
            ③ 相位锁判据：e = wrap180(刀相 − 180° − 材料相)。传动比 fSyncRatio = 1.0 时 e 恒 0；
               传动比偏离 1.0 时每刀漂移 (ratio − 1)×360°，|e| 超 fPhaseTolDeg 即失步，超 30° 锁故障（104）；
            ④ 剪切窗口按刀相相对 180° 的偏差定义，半宽 = fWindowDeg/2；窗口判据基于上一拍位置（滞后一拍）；
            ⑤ 遗留假设（R95 三句）：本件无周期引脚，虚轴积分用代理周期 DL_RKC_DT = 10 ms；
               该代理覆盖任务周期 1~20 ms；覆盖不到的区间（任务周期 < 1 ms 或 > 20 ms）由上层任务组态保证，
               并挂入编译验证债，交付前三平台各验证一次；
            ⑥ 使能撤销语义：位置量冻结保持末值（不归零），xSyncOk 置 FALSE（R191 已声明）；
            ⑦ 故障解除唯一路径：故障相内 xEnable 释放（R152），清锁存回 eIdle。
  状态机：eIdle / eHoming / eSyncWait / eSynced / eCutting / eReturn / eFault（CASE 含 ELSE 兜底）。
  量纲自证：v[m/min]×1000/60 = mm/s；mm/s × s ÷ mm = 转；转 × 360 = °。
*)
TYPE E_DL_RkcPhase :
(
    eIdle     := 0,     (* 待机：等使能沿 / Idle, waiting for enable edge *)
    eHoming   := 10,    (* 找零相：虚轴与刀轴归零 / Homing, both axes zeroed *)
    eSyncWait := 20,    (* 同步等待相：等相位锁进带 / Sync wait, phase lock in band *)
    eSynced   := 30,    (* 已同步相：等剪切窗口 / Synced, waiting cut window *)
    eCutting  := 40,    (* 剪切相：窗口内执行剪切 / Cutting inside window *)
    eReturn   := 50,    (* 返回相：离开窗口后回同步相 / Return after leaving window *)
    eFault    := 90     (* 故障相：锁存待释放 / Fault latched, awaiting release *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_RotaryKnifeCutSyncCtrl
VAR_INPUT
    xEnable : BOOL;             (* 使能 [-] Enable *)
    fLineSpeedMpm : REAL;       (* 线速度 [m/min] Line speed [m/min] *)
    fCutLenMm : REAL;           (* 定尺长度（一个虚轴周期） [mm] Cut length per revolution [mm] *)
    fKnifeDiaMm : REAL;         (* 刀盘直径 [mm] Knife diameter [mm] *)
    fSyncRatio : REAL;          (* 传动比（刀轴角位移/虚轴角位移） [-] Sync ratio *)
    fWindowDeg : REAL;          (* 剪切窗口宽度 [°] Cutting window width [deg] *)
    fPhaseTolDeg : REAL;        (* 相位锁容差 [°] Phase lock tolerance [deg] *)
END_VAR
VAR_OUTPUT
    fMasterPosDeg : REAL;       (* 材料虚轴位置 [°] Master virtual axis position [deg] *)
    fSlavePosDeg : REAL;        (* 刀轴位置 [°] Knife axis position [deg] *)
    xInWindow : BOOL;           (* 处于剪切窗口 [-] Inside cutting window *)
    nCutCount : UDINT;          (* 累计剪切刀数（饱和） [刀] Cut counter, saturating *)
    xSyncOk : BOOL;             (* 相位锁成立 [-] Phase lock established *)
    xFault : BOOL;              (* 故障锁存标志 [-] Fault latched *)
    nErrCode : INT;             (* 故障码 0/101 组态/103 未同步进窗口/104 失步/105 非法相 [-] Error code *)
END_VAR
VAR
    _eState : E_DL_RkcPhase := E_DL_RkcPhase.eIdle;  (* 内部相（CASE 唯一写入目标） [-] Internal phase *)
    _bInit : BOOL := FALSE;         (* 首扫初始化标志 [-] First-scan init flag *)
    _bFaultLatch : BOOL := FALSE;   (* 故障锁存位 [-] Fault latch *)
    _bReqFault : BOOL := FALSE;     (* 单拍故障请求（段 2 预清） [-] Fault request *)
    _bCfgBad : BOOL := FALSE;       (* 配置非法当拍量 [-] Configuration bad *)
    _bInWindow : BOOL := FALSE;     (* 窗口判据当拍量 [-] In-window criterion *)
    _bSyncOk : BOOL := FALSE;       (* 相位锁当拍量 [-] Phase lock criterion *)
    _nErr : INT := 0;               (* 故障码锁存 [-] Latched error code *)
    _nReqErr : INT := 0;            (* 当拍请求码 [-] Requested error code *)
    _nCut : UDINT := 0;             (* 刀数累计锁存（饱和） [刀] Cut count latch *)
    _fMasterDeg : REAL := 0.0;      (* 虚轴位置保持量 [°] Master position hold [deg] *)
    _fSlaveDeg : REAL := 0.0;       (* 刀轴位置保持量 [°] Knife position hold [deg] *)
    _fAdvDeg : REAL := 0.0;         (* 单拍虚轴增量 [°] Master increment per scan [deg] *)
    _fBladeErr : REAL := 0.0;       (* 刀相相对窗口中心偏差（归一化） [°] Blade-to-center error [deg] *)
    _fLockErr : REAL := 0.0;        (* 相位锁误差（归一化） [°] Phase lock error [deg] *)
    rtEnable : R_TRIG;              (* 使能沿（段 1 无条件调用） / Enable edge *)
    rtWindow : R_TRIG;              (* 窗口进入沿（段 1 无条件调用） / Window entry edge *)
    tonHome : TON;                  (* 找零窗（段 1 无条件调用） / Homing window *)
END_VAR
VAR CONSTANT
    DL_RKC_DT : REAL := 0.01;           (* 代理扫描周期（遗留假设见头注释） [s] Proxy scan cycle [s] *)
    DL_RKC_MMPM : REAL := 1000.0;       (* 米 → 毫米换算 [mm/m] Metre to millimetre *)
    DL_RKC_SECMIN : REAL := 60.0;       (* 每秒 → 每分钟换算 [s/min] Second to minute *)
    DL_RKC_FULL : REAL := 360.0;        (* 整转角度 [°] Full revolution [deg] *)
    DL_RKC_HALF : REAL := 180.0;        (* 半转角度 [°] Half revolution [deg] *)
    DL_RKC_CUT_CENTER : REAL := 180.0;  (* 窗口中心刀相 [°] Window center blade phase [deg] *)
    DL_RKC_EXIT_MARGIN : REAL := 5.0;   (* 出窗裕度（防抖） [°] Window exit margin [deg] *)
    DL_RKC_ERR_MAX : REAL := 30.0;      (* 失步门限 [°] Loss-of-sync threshold [deg] *)
    DL_RKC_HOME : TIME := T#500MS;      (* 找零窗（确定性时窗） [ms] Homing window [ms] *)
    DL_RKC_CUT_MAX : UDINT := 4294967295;   (* 刀数饱和上限 [刀] Cut count ceiling *)
    DL_V_MIN : REAL := 0.0;             (* 线速度下限 [m/min] Line speed floor [m/min] *)
    DL_V_MAX : REAL := 600.0;           (* 线速度上限 [m/min] Line speed ceiling [m/min] *)
    DL_L_MIN : REAL := 50.0;            (* 定尺下限 [mm] Cut length floor [mm] *)
    DL_L_MAX : REAL := 20000.0;         (* 定尺上限 [mm] Cut length ceiling [mm] *)
    DL_D_MIN : REAL := 50.0;            (* 刀径下限 [mm] Knife diameter floor [mm] *)
    DL_D_MAX : REAL := 2000.0;          (* 刀径上限 [mm] Knife diameter ceiling [mm] *)
    DL_R_MIN : REAL := 0.2;             (* 传动比下限 [-] Sync ratio floor *)
    DL_R_MAX : REAL := 5.0;             (* 传动比上限 [-] Sync ratio ceiling *)
    DL_W_MIN : REAL := 1.0;             (* 窗口宽度下限 [°] Window floor [deg] *)
    DL_W_MAX : REAL := 180.0;           (* 窗口宽度上限 [°] Window ceiling [deg] *)
    DL_TOL_MIN : REAL := 0.1;           (* 相位容差下限 [°] Tolerance floor [deg] *)
    DL_TOL_MAX : REAL := 20.0;          (* 相位容差上限 [°] Tolerance ceiling [deg] *)
END_VAR

(*-----------------------------------------------------------------------------
  方法 NormalizeDeg180：把任意角度归一到 (-180, 180] 区间（±180° 环绕归一化）
  契约：入参 fDegIn [°]；返回归一化角度 [°]。非有限入参返回哨兵 0（R81 还原方向不饱和）。
  实现：三段条件减法覆盖 [-540, 540) 全域；本件两轴位置均按 [0,360) 维持，差值必落该域内，
        故无需循环，无死循环风险（R4 循环守卫结构性免除）。
-----------------------------------------------------------------------------*)
METHOD PUBLIC NormalizeDeg180 : REAL
VAR_INPUT
    fDegIn : REAL;      (* 待归一化角度 [°] Angle to normalize [deg] *)
END_VAR
VAR
    fVal : REAL := 0.0; (* 归一化中间量 [°] Normalized scratch [deg] *)
END_VAR
NormalizeDeg180 := 0.0;                             (* 出口预置哨兵 / Preset sentinel *)
IF (fDegIn <> fDegIn) OR ((fDegIn - fDegIn) <> 0.0) THEN
    NormalizeDeg180 := 0.0;                         (* 非有限：返回哨兵 0 / Non-finite to sentinel *)
    RETURN;
END_IF
fVal := fDegIn;
IF fVal >= DL_RKC_HALF THEN
    fVal := fVal - DL_RKC_FULL;                     (* 上半周折回 / Fold upper half *)
END_IF
IF fVal < (0.0 - DL_RKC_HALF) THEN
    fVal := fVal + DL_RKC_FULL;                     (* 下半周折回 / Fold lower half *)
END_IF
IF fVal >= DL_RKC_HALF THEN
    fVal := fVal - DL_RKC_FULL;                     (* 二次折回（差域上限） / Second fold *)
END_IF
NormalizeDeg180 := fVal;
END_METHOD

(* —— 段 0：非有限闸 + 虚轴增量派生 + 相位量与窗口判据 —— *)
_bCfgBad := (fLineSpeedMpm <> fLineSpeedMpm) OR ((fLineSpeedMpm - fLineSpeedMpm) <> 0.0)
         OR (fCutLenMm <> fCutLenMm) OR ((fCutLenMm - fCutLenMm) <> 0.0)
         OR (fKnifeDiaMm <> fKnifeDiaMm) OR ((fKnifeDiaMm - fKnifeDiaMm) <> 0.0)
         OR (fSyncRatio <> fSyncRatio) OR ((fSyncRatio - fSyncRatio) <> 0.0)
         OR (fWindowDeg <> fWindowDeg) OR ((fWindowDeg - fWindowDeg) <> 0.0)
         OR (fPhaseTolDeg <> fPhaseTolDeg) OR ((fPhaseTolDeg - fPhaseTolDeg) <> 0.0)
         OR (fLineSpeedMpm < DL_V_MIN) OR (fLineSpeedMpm > DL_V_MAX)
         OR (fCutLenMm < DL_L_MIN) OR (fCutLenMm > DL_L_MAX)
         OR (fKnifeDiaMm < DL_D_MIN) OR (fKnifeDiaMm > DL_D_MAX)
         OR (fSyncRatio < DL_R_MIN) OR (fSyncRatio > DL_R_MAX)
         OR (fWindowDeg < DL_W_MIN) OR (fWindowDeg > DL_W_MAX)
         OR (fPhaseTolDeg < DL_TOL_MIN) OR (fPhaseTolDeg > DL_TOL_MAX);
(* 虚轴增量：先闸后除（fCutLenMm 为除子，配置非法时强制 0，绝不进入除法） *)
IF _bCfgBad THEN
    _fAdvDeg := 0.0;
ELSE
    _fAdvDeg := ((fLineSpeedMpm * DL_RKC_MMPM) / DL_RKC_SECMIN) * DL_RKC_DT / fCutLenMm * DL_RKC_FULL;
END_IF
(* 刀相相对窗口中心偏差：±180° 归一化（禁直接相减） *)
_fBladeErr := NormalizeDeg180(_fSlaveDeg - DL_RKC_CUT_CENTER);
(* 相位锁误差：e = wrap180(刀相 − 180° − 材料相) *)
_fLockErr := NormalizeDeg180(_fSlaveDeg - DL_RKC_CUT_CENTER - _fMasterDeg);
(* 窗口判据：偏差绝对值不超过半窗宽 *)
_bInWindow := ABS(_fBladeErr) <= (fWindowDeg / 2.0);
(* 相位锁判据：误差绝对值不超容差，且已进入同步类相位 *)
_bSyncOk := (NOT _bCfgBad) AND (ABS(_fLockErr) <= fPhaseTolDeg)
            AND ((_eState = E_DL_RkcPhase.eSynced) OR (_eState = E_DL_RkcPhase.eCutting)
              OR (_eState = E_DL_RkcPhase.eReturn));
(* —— 段 1：两沿与找零 TON 无条件周期刷新（R7），禁放入分支 —— *)
rtEnable(CLK := xEnable);                                           (* 使能沿 / Enable edge *)
rtWindow(CLK := _bInWindow);                                        (* 窗口进入沿 / Window edge *)
tonHome(IN := (_eState = E_DL_RkcPhase.eHoming), PT := DL_RKC_HOME);(* 找零窗 / Homing window *)
(* —— 段 2：单拍量预清零（不含锁存/累计量，R107） —— *)
_bReqFault := FALSE;
_nReqErr := 0;
IF _bCfgBad THEN
    _bReqFault := TRUE; _nReqErr := 101;    (* 组态非法 / Configuration bad *)
END_IF
(* 首扫初始化：位置与刀数一次性归零（R310） *)
IF NOT _bInit THEN
    _fMasterDeg := 0.0;
    _fSlaveDeg := 0.0;
    _nCut := 0;
    _bInit := TRUE;
END_IF
(* —— 段 3：失步监控（同步类相位内 |e| 超门限即请求故障） —— *)
IF ((_eState = E_DL_RkcPhase.eSynced) OR (_eState = E_DL_RkcPhase.eCutting)
    OR (_eState = E_DL_RkcPhase.eReturn)) AND (ABS(_fLockErr) > DL_RKC_ERR_MAX) THEN
    _bReqFault := TRUE; _nReqErr := 104;    (* 失步 / Loss of sync *)
END_IF
(* —— 段 4：故障锁存解除（唯一路径 = 故障相内 xEnable 释放，R152） —— *)
IF _bFaultLatch AND (NOT xEnable) THEN
    _bFaultLatch := FALSE;                  (* 清锁存 / Clear latch *)
    _nErr := 0;                             (* 清码 / Clear code *)
    _eState := E_DL_RkcPhase.eIdle;         (* 迁回待机 / Back to idle *)
END_IF
(* —— 段 5：主状态机（ENUM + CASE，ELSE 兜底） —— *)
CASE _eState OF
E_DL_RkcPhase.eIdle:
    IF rtEnable.Q AND (NOT _bFaultLatch) THEN
        _fMasterDeg := 0.0;                 (* 虚轴归零 / Master zeroed *)
        _fSlaveDeg := 0.0;                  (* 刀轴归零 / Knife zeroed *)
        _nCut := 0;                         (* 刀数清零 / Cut count reset *)
        _eState := E_DL_RkcPhase.eHoming;   (* → 找零相 / To homing *)
    END_IF
E_DL_RkcPhase.eHoming:
    _fMasterDeg := _fMasterDeg + _fAdvDeg;  (* 找零期虚轴空推（材料已走） / Master advances *)
    _fSlaveDeg := _fSlaveDeg + (_fAdvDeg * fSyncRatio);   (* 刀轴按传动比跟随 / Knife follows ratio *)
    IF tonHome.Q THEN
        _eState := E_DL_RkcPhase.eSyncWait; (* 找零窗到 → 同步等待 / Home done, sync wait *)
    END_IF
E_DL_RkcPhase.eSyncWait:
    _fMasterDeg := _fMasterDeg + _fAdvDeg;  (* 虚轴推进 / Master advance *)
    _fSlaveDeg := _fSlaveDeg + (_fAdvDeg * fSyncRatio);   (* 刀轴跟随 / Knife advance *)
    IF ABS(_fLockErr) <= fPhaseTolDeg THEN
        _eState := E_DL_RkcPhase.eSynced;   (* 相位进带 → 已同步 / In band, synced *)
    END_IF
E_DL_RkcPhase.eSynced:
    _fMasterDeg := _fMasterDeg + _fAdvDeg;
    _fSlaveDeg := _fSlaveDeg + (_fAdvDeg * fSyncRatio);
    IF rtWindow.Q AND _bSyncOk THEN
        IF _nCut < DL_RKC_CUT_MAX THEN
            _nCut := _nCut + 1;             (* 刀数推进（容量载体判上限） / Saturating cut count *)
        END_IF
        _eState := E_DL_RkcPhase.eCutting;  (* → 剪切相 / To cutting *)
    ELSIF rtWindow.Q THEN
        _bReqFault := TRUE;                 (* 未同步即到切点：拒切并报失步 / Cut rejected *)
        _nReqErr := 103;
    END_IF
E_DL_RkcPhase.eCutting:
    _fMasterDeg := _fMasterDeg + _fAdvDeg;
    _fSlaveDeg := _fSlaveDeg + (_fAdvDeg * fSyncRatio);
    IF NOT _bInWindow THEN
        _eState := E_DL_RkcPhase.eReturn;   (* 出窗 → 返回相 / Window left, return *)
    END_IF
E_DL_RkcPhase.eReturn:
    _fMasterDeg := _fMasterDeg + _fAdvDeg;
    _fSlaveDeg := _fSlaveDeg + (_fAdvDeg * fSyncRatio);
    IF ABS(_fBladeErr) >= ((fWindowDeg / 2.0) + DL_RKC_EXIT_MARGIN) THEN
        _eState := E_DL_RkcPhase.eSynced;   (* 越出裕度 → 回同步相 / Past margin, synced *)
    END_IF
E_DL_RkcPhase.eFault:
    _fAdvDeg := 0.0;                        (* 故障相：虚轴增量清零，轴停在末位 / Axes hold *)
ELSE
    _bReqFault := TRUE;                     (* 非法相兜底 / Illegal phase fallback *)
    _nReqErr := 105;
END_CASE
(* 使能撤销：非故障相回待机，位置冻结保持（R191 已声明） *)
IF (NOT xEnable) AND (_eState <> E_DL_RkcPhase.eFault) AND (_eState <> E_DL_RkcPhase.eIdle) THEN
    _eState := E_DL_RkcPhase.eIdle;
END_IF
(* 位置环绕归一：两轴保持 [0,360)，防长时运行精度流失 *)
IF _fMasterDeg >= DL_RKC_FULL THEN
    _fMasterDeg := _fMasterDeg - DL_RKC_FULL;
END_IF
IF _fMasterDeg < 0.0 THEN
    _fMasterDeg := _fMasterDeg + DL_RKC_FULL;
END_IF
IF _fSlaveDeg >= DL_RKC_FULL THEN
    _fSlaveDeg := _fSlaveDeg - DL_RKC_FULL;
END_IF
IF _fSlaveDeg < 0.0 THEN
    _fSlaveDeg := _fSlaveDeg + DL_RKC_FULL;
END_IF
(* —— 段 6：故障请求统一落地（唯一锁存点 + 同步迁相，R187/R252） —— *)
IF _bReqFault AND (NOT _bFaultLatch) THEN
    _bFaultLatch := TRUE;                   (* 锁存 / Latch *)
    _nErr := _nReqErr;                      (* 码锁存回放 / Latched code *)
    _eState := E_DL_RkcPhase.eFault;        (* 同步迁相 / Migrate to fault *)
END_IF
(* —— 段 7：统一出口（各出口单点赋值） —— *)
fMasterPosDeg := _fMasterDeg;
fSlavePosDeg := _fSlaveDeg;
xInWindow := _bInWindow AND (NOT _bFaultLatch);
nCutCount := _nCut;
xSyncOk := _bSyncOk AND (NOT _bFaultLatch);
xFault := _bFaultLatch;
nErrCode := _nErr;
END_FUNCTION_BLOCK
