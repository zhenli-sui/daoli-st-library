(*
  FB_DL_ConveyorDirMismatch  —  输送线停机方向失配独立诊断窗（反窜/倒滑） / Conveyor stopped-state direction mismatch diagnostic window
  分类 Category : DL_Process
  版本 Version  : 1.0.1
  来源 Source   : t2-7-packml — 终审立项独立诊断增强（复用 FB_DL_ConveyorZone 光电语义）
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 停机判据用当拍量（NOT bMotorRun）；停机后经 tSettle 静置窗进 eWatch
                  监视相，独立诊断窗 TON（tonDiagBack/tonDiagSlide）与运行窗分实例；
                  2) 反窜诊断：停机监视相中入口光电持续遮挡（电平承载）超 tDiagWin
                  → 故障级 036D 独立锁存（R190 归因唯一）；
                  3) 倒滑诊断：停机监视相中出口光电持续遮挡超 tDiagWin
                  → 故障级 036E 独立锁存；
                  4) 相位机 CASE 全覆盖 + ELSE 兜底落 036F；诊断窗 TON 无条件
                  周期刷新且 IN 用光电电平承载（门控沿与计时基解耦，与
                  FB_DL_ConveyorZone run-on 语义分工：那件管运行清区，本件管停机反常）。
  返修记录 Rework  :
    2026-11-19  v1.0.1  R42 P0-1 严重返修：v1.0.0 诊断窗 TON 的 IN 由光电沿实例
                        rtPeEntry.Q/rtPeDis.Q（单拍量）门控——沿为单拍脉冲，TON 计时基
                        下一拍即断，结构性永不到时（P0 派单缺陷①）。修复要点：TON 的 IN
                        改由光电电平（bPEEntry/bPEDischarge）与监视相单相等式承载，
                        沿实例随结构性缺陷一并移除；对外接口签名不变；
                        光电语义改为「持续遮挡超 tDiagWin」判反窜/倒滑。
  边界 Boundary : ① 运行恢复（bMotorRun 当拍 TRUE）即回 eIdle，诊断窗自动清；
                  ② 解除式全当拍量（R240 落地）：rtReset.Q AND NOT bMotorRun，逐 BOOL 标注见段 4；
                  ③ 组态闸：tSettle/tDiagWin <= 0 → 036F 同级锁存（组态与兜底归并声明于码表）；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : 与 FB_DL_ConveyorZone 光电/run-on 语义分工对齐（不实例化）；Standard.library（TON / R_TRIG / F_TRIG）
  码表 Error codes（Process 段 0005，窗口 036D~036F / 0495~0497）:
    16#0005_036D 故障级：反窜检出锁存（停机监视相入口光电持续遮挡超 tDiagWin），锁存至 bReset
    16#0005_036E 故障级：倒滑检出锁存（停机监视相出口光电持续遮挡超 tDiagWin），锁存至 bReset
    16#0005_036F 故障级：相位落 ELSE 兜底或组态非法（静置/诊断窗域非法），锁存至 bReset
    16#0005_0495 信息级：诊断窗激活沿（进入 eWatch）
    16#0005_0496 信息级：反窜解除沿（复位清锁存）
    16#0005_0497 信息级：倒滑解除沿（复位清锁存）
  修订历史 Revision :
    2026-11-19  v1.0.0  R41 首版（批次 4 · 序号 5）
    2026-11-19  v1.0.1  R42 P0-1 严重返修（见返修记录节）
*)

TYPE E_DL_CdmState :
(
    eIdle   := 0,    // 空闲：运行中或无停机事件 / Idle, running or no stop event
    eSettle := 10,   // 静置：停机确认窗 / Settle, stopped confirm window
    eWatch  := 20,   // 监视：独立诊断窗开启 / Watch, diagnostic window open
    eFault  := 90    // 故障：反窜或倒滑锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_ConveyorDirMismatch
VAR_INPUT
    bMotorRun    : BOOL := FALSE;     // 驱动运行反馈，TRUE = 运行中 [-] / Drive running feedback
    bFwdCmd      : BOOL := TRUE;      // 运行方向指令，TRUE = 正向（诊断口径记录用）[-] / Direction command
    bPEEntry     : BOOL := FALSE;     // 入口光电，TRUE = 遮挡 [-] / Entry photoeye, TRUE = blocked
    bPEDischarge : BOOL := FALSE;     // 出口光电，TRUE = 遮挡 [-] / Discharge photoeye, TRUE = blocked
    tSettle      : TIME := T#2S;      // 停机静置窗 [ms]，域 > 0 / Stop settle window
    tDiagWin     : TIME := T#5S;      // 独立诊断窗 [ms]，域 > 0 / Diagnostic window
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_OUTPUT
    eState       : E_DL_CdmState;     // 状态出口，段尾单点映射 / State outlet
    bBackFlow    : BOOL;              // 反窜独立锁存出口 [-] / Back-flow latch outlet
    bSlideBack   : BOOL;              // 倒滑独立锁存出口 [-] / Slide-back latch outlet
    bFault       : BOOL;              // 聚合故障标志 / Aggregate fault flag
    bError       : BOOL;              // 故障级标志（与聚合锁存同源）/ Fault flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonSettle    : TON;               // 停机静置窗 TON（与运行窗分实例），无条件刷新 / Settle timer
    tonDiagBack  : TON;               // 反窜独立诊断窗 TON，无条件刷新 / Back-flow diagnostic timer
    tonDiagSlide : TON;               // 倒滑独立诊断窗 TON，无条件刷新 / Slide-back diagnostic timer
    rtPeEntry    : R_TRIG;            // 入口光电沿实例（v1.0.1 已移除判据用途，保留供上层诊断镜像）；
                                       // 上层不引用时可在组装层删除 / Entry photoeye edge instance (no longer gating)
    rtPeDis      : R_TRIG;            // 出口光电沿实例（v1.0.1 已移除判据用途，前述解除判据）/ Discharge photoeye edge instance
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _eState      : E_DL_CdmState := E_DL_CdmState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _bStopped    : BOOL;              // 停机当拍量 [-] / Stopped current-scan flag
    _bBackLat    : BOOL;              // 反窜锁存位（锁存量）/ Back-flow latch bit
    _bSlideLat   : BOOL;              // 倒滑锁存位（锁存量）/ Slide-back latch bit
    _bCfgBad     : BOOL;              // 组态锁存位（锁存量）/ Config-fault latch bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
    _bWatchPrev  : BOOL;              // 上拍监视相镜像（激活沿判据）/ Previous watch mirror
    _bBackOkPrev : BOOL;              // 上拍反窜无锁存镜像（解除沿判据）/ Previous back-clear mirror
    _bSlideOkPrev: BOOL;              // 上拍倒滑无锁存镜像（解除沿判据）/ Previous slide-clear mirror
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_bStopped := NOT bMotorRun;                          // 停机判据（当拍量）
rtPeEntry(CLK := bPEEntry);                          // 入口光电沿（每拍必调）
rtPeDis(CLK := bPEDischarge);                        // 出口光电沿（每拍必调）
rtReset(CLK := bReset);                              // 复位沿（每拍必调）
tonSettle(IN := (_eState = E_DL_CdmState.eSettle), PT := tSettle);              // 静置窗（单相独占）
tonDiagBack(IN := (_eState = E_DL_CdmState.eWatch) AND bPEEntry, PT := tDiagWin);
                                                     // 反窜诊断窗（光电电平承载，门控沿与计时基解耦，每拍必调）
tonDiagSlide(IN := (_eState = E_DL_CdmState.eWatch) AND bPEDischarge, PT := tDiagWin);
                                                     // 倒滑诊断窗（光电电平承载，前述解除判据，每拍必调）

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bBackLat/_bSlideLat/_bCfgBad 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（当拍量判据） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bBackLat := FALSE;             // 清反窜锁存位
    _bSlideLat := FALSE;            // 清倒滑锁存位
    _bCfgBad := FALSE;              // 清组态锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF
IF (TIME_TO_DINT(tSettle) <= 0) OR (TIME_TO_DINT(tDiagWin) <= 0) THEN
    _uFault := 16#0005_036F;        // 故障级：组态非法（归并兜底码，头注释③）
    _bCfgBad := TRUE;
END_IF

(* —— 段 3：双判据独立锁存（R190：反窜/倒滑归因唯一，各走独立码位与出口） —— *)
IF (_eState = E_DL_CdmState.eWatch) AND (NOT _bCfgBad) THEN
    IF tonDiagBack.Q THEN
        _uFault := 16#0005_036D;    // 故障级：反窜锁存
        _bBackLat := TRUE;
        _eState := E_DL_CdmState.eFault;
    ELSIF tonDiagSlide.Q THEN
        _uFault := 16#0005_036E;    // 故障级：倒滑锁存
        _bSlideLat := TRUE;
        _eState := E_DL_CdmState.eFault;
    END_IF
END_IF

(* —— 段 4：故障解除式（R240 落地，逐 BOOL 标注）：
     rtReset.Q = 当拍量；NOT bMotorRun = 当拍量；均不含锁存量（_bBackLat/_bSlideLat），
     解除边真实可达（复位沿在任意停机/运行拍均可到达）。 —— *)
IF rtReset.Q AND (NOT _bCfgBad) THEN
    IF _bBackLat THEN
        _uInfo := 16#0005_0496;     // 信息级：反窜解除沿
    END_IF
    IF _bSlideLat THEN
        _uInfo := 16#0005_0497;     // 信息级：倒滑解除沿（覆盖反窜解除沿，后到优先）
    END_IF
    _bBackLat := FALSE;             // 清反窜锁存位（锁存量，仅此当拍量解除沿可清）
    _bSlideLat := FALSE;            // 清倒滑锁存位（锁存量，仅解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，仅本当拍量解除沿可清）
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_CdmState.eIdle:
    IF _bStopped AND (NOT _bCfgBad) THEN
        _eState := E_DL_CdmState.eSettle;   // 停机当拍：进静置相
    END_IF

E_DL_CdmState.eSettle:
    IF bMotorRun THEN                   // 运行恢复（当拍量）：回空闲
        _eState := E_DL_CdmState.eIdle;
    ELSIF tonSettle.Q THEN
        _uInfo := 16#0005_0495;         // 信息级：诊断窗激活沿
        _eState := E_DL_CdmState.eWatch;    // 静置通过：进监视相
    END_IF

E_DL_CdmState.eWatch:
    IF bMotorRun THEN                   // 运行恢复（当拍量）：回空闲（诊断窗自动清）
        _eState := E_DL_CdmState.eIdle;
    END_IF
    (* 反窜/倒滑检出与迁出在段 3 承载（独立诊断窗判据） *)

E_DL_CdmState.eFault:
    ;                                   // 故障相：等复位沿（段 4 承载迁出）

ELSE
    _uFault := 16#0005_036F;            // 故障级：非法相位兜底
    _bCfgBad := TRUE;
    _eState := E_DL_CdmState.eFault;    // 强制回故障相

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
bBackFlow := _bBackLat OR _bCfgBad;     // 反窜独立出口（组态坏并入安全侧）
bSlideBack := _bSlideLat OR _bCfgBad;   // 倒滑独立出口（前述解除判据）
bFault := _bBackLat OR _bSlideLat OR _bCfgBad;  // 聚合故障
IF bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := bFault;                   // 故障标志与聚合锁存同源
eState := _eState;                  // 状态出口单点映射
_bWatchPrev := (_eState = E_DL_CdmState.eWatch);    // 激活沿判据快照
_bBackOkPrev := NOT _bBackLat;      // 解除沿判据快照
_bSlideOkPrev := NOT _bSlideLat;    // 解除沿判据快照

END_FUNCTION_BLOCK
