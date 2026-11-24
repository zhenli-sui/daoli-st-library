(*
  FB_DL_GloveBoxAtmoCtrl  —  手套箱气氛联锁 / Glove-box atmosphere interlock control
  分类 Category : DL_Device
  码位 Code     : 16#03_2_06
  版本 Version  : 1.0.0
  溯源 Source   : NAMUR NE107 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 水/氧含量双路越限判定（带迟滞），任一路越限禁开门；
                  2) 开门许可经 FB_DL_InterlockMatrix 双条件联锁出口（复用）；
                  3) 净化循环请求与开门互斥仲裁；NE107 六态映射出口。
  边界 Boundary : ① 任一路无效按「越限」安全侧禁开门（R42 家族）；
                  ② 门限带迟滞防反复禁投；
                  ③ 越限解除须双路均回窗 + 最短维持时间（FB33-2 可达）；
                  ④ 净化请求与开门互斥仲裁（净化优先）；
                  ⑤ 未知状态归 eUnknown 绝不归 eOk；
                  ⑥ 输出三行同向：开门许可 → 净化请求 → NE107 态。
  依赖 Depends  : FB_DL_InterlockMatrix × 1（双条件联锁出口，每拍无条件调用）
                  E_DL_Ne107Status（属主件 I_DL_DeviceHealth，只引用不重声明）

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_0306 故障级：组态非法（门限倒置 / 迟滞 <= 0 / 维持时间 <= 0）
    16#0002_0316 故障级：相 ID 越界（枚举兜底路径）
    16#0002_0326 信息级：双路越限开门闭锁维持中 / 无效通道按越限处理（不置 bError）
*)

TYPE E_DL_GbaPhase :
(
    eIdle   := 0,  // 空闲 / Idle
    eWatch  := 10, // 气氛监视 / Atmosphere watching
    ePurge  := 20, // 净化循环请求保持 / Purge request held
    eFault  := 90  // 组态故障锁定 / Configuration fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_GloveBoxAtmoCtrl
VAR_INPUT
    bEnable       : BOOL;                           // 总使能，FALSE 回空闲 / Master enable
    bReset        : BOOL;                           // 复位，上升沿清组态故障 / Reset, clears fault
    fH2oPpm       : REAL;                           // 水含量 [ppm] / Water content [ppm]
    fO2Ppm        : REAL;                           // 氧含量 [ppm] / Oxygen content [ppm]
    fH2oMaxPpm    : REAL := 5.0;                    // 水含量门限 [ppm] / Water limit [ppm]
    fO2MaxPpm     : REAL := 10.0;                   // 氧含量门限 [ppm] / Oxygen limit [ppm]
    fHystPpm      : REAL := 0.5;                    // 迟滞回差 [ppm]，域 > 0 / Hysteresis band [ppm]
    bDoorReq      : BOOL;                           // 开门请求 / Door request
    tSustainMin   : TIME := T#30S;                  // 回窗最短维持时间 [s]，域 > 0 / Min sustain time after back-in-window
    fEps          : REAL := 1.0E-6;                 // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    bDoorPermit   : BOOL;                           // 开门许可出口（联锁矩阵放行）/ Door permit output
    bPurgeReq     : BOOL;                           // 净化循环请求（互斥仲裁后）/ Purge cycle request
    eNe107        : E_DL_Ne107Status;               // NE107 六态映射出口 / NE107 status mapping
    bError        : BOOL;                           // 故障标志，与故障级码配对 / Fault flag
    uErrorId      : UDINT;                          // 事件码，0 = 无事件 / Event code
    eStateOut     : E_DL_GbaPhase;                  // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState       : E_DL_GbaPhase := E_DL_GbaPhase.eIdle;  // 内部状态 / Internal state
    fbIlk         : FB_DL_InterlockMatrix;          // 联锁矩阵实例（无条件调用）/ Interlock matrix instance
    rtrReset      : R_TRIG;                         // 复位沿 / Reset edge
    tonSustain    : TON;                            // 回窗维持计时器 / Back-in-window sustain timer
    abCondOk      : ARRAY[0..15] OF BOOL;           // 联锁条件表（ch0 水 / ch1 氧）/ Interlock condition table
    auInvertMask  : WORD;                           // 取反掩码（不取反）/ Invert mask
    auTripMask    : WORD;                           // 停机级掩码（双路均停机级）/ Trip-class mask
    bCfgOk        : BOOL;                           // 组态合法标志 / Configuration valid
    bH2oOk        : BOOL;                           // 水路本拍有效 / Water channel valid
    bO2Ok         : BOOL;                           // 氧路本拍有效 / Oxygen channel valid
    bH2oInWin     : BOOL;                           // 水路在窗（含迟滞）/ Water in window
    bO2InWin      : BOOL;                           // 氧路在窗（含迟滞）/ Oxygen in window
    bAnyOver      : BOOL;                           // 任一路越限或无效（电平）/ Any channel over or invalid
    bAllInWin     : BOOL;                           // 双路均在窗 / Both in window
    bSustainOk    : BOOL;                           // 维持时间已满足 / Sustain time met
    bHystWaterUp  : BOOL;                           // 水路迟滞越限状态（持有）/ Water over-limit hysteresis state
    bHystO2Up     : BOOL;                           // 氧路迟滞越限状态（持有）/ Oxygen over-limit hysteresis state
    uFault        : UDINT;                          // 锁存故障码 / Latched fault code
    uInfo         : UDINT;                          // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_GBA_INFMAX : REAL := 1.0E30;                 // 含量有限值幅值上限 [ppm] / Content finite bound [ppm]
END_VAR

(* === 段 0 · 实例刷新 === *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸 === *)
bCfgOk := (fH2oMaxPpm > fHystPpm) AND (fO2MaxPpm > fHystPpm)   // 门限须大于迟滞带（防带翻转）
          AND (fHystPpm > fEps)                   // 迟滞正域
          AND (TIME_TO_REAL(tSustainMin) > fEps)  // 维持时间正域
          AND (fH2oMaxPpm = fH2oMaxPpm) AND (fO2MaxPpm = fO2MaxPpm);  // NaN 自反
IF NOT bCfgOk THEN
    uFault := 16#0002_0306;                       // 故障级：组态非法
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清锁存（解除路径可达）
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零

(* === 段 2 · 双路域闸与迟滞越限判定 === *)
bH2oOk := (fH2oPpm = fH2oPpm) AND (fH2oPpm >= 0.0) AND (fH2oPpm < DL_GBA_INFMAX);  // 水路 NaN 自反 + 非负域
bO2Ok := (fO2Ppm = fO2Ppm) AND (fO2Ppm >= 0.0) AND (fO2Ppm < DL_GBA_INFMAX);       // 氧路域闸
IF bH2oOk THEN
    IF fH2oPpm >= fH2oMaxPpm THEN
        bHystWaterUp := TRUE;                     // 越门限置迟滞状态
    ELSIF fH2oPpm < fH2oMaxPpm - fHystPpm THEN
        bHystWaterUp := FALSE;                    // 回差带内解除（防反复禁投）
    END_IF
ELSE
    bHystWaterUp := TRUE;                         // 无效按越限安全侧（R42 家族）
    uInfo := 16#0002_0326;                        // 信息级：无效通道按越限处理
END_IF
IF bO2Ok THEN
    IF fO2Ppm >= fO2MaxPpm THEN
        bHystO2Up := TRUE;                        // 越门限置迟滞状态
    ELSIF fO2Ppm < fO2MaxPpm - fHystPpm THEN
        bHystO2Up := FALSE;                       // 回差带内解除
    END_IF
ELSE
    bHystO2Up := TRUE;                            // 无效按越限安全侧
    uInfo := 16#0002_0326;                        // 信息级：无效通道按越限处理
END_IF
bAnyOver := bHystWaterUp OR bHystO2Up;            // 任一路越限或无效
bAllInWin := (NOT bHystWaterUp) AND (NOT bHystO2Up);   // 双路均在窗

(* === 段 3 · 回窗最短维持时间（FB33-2：越限解除须回窗 + 最短维持）=== *)
tonSustain(IN := bAllInWin, PT := tSustainMin);   // 双路回窗才开始计时（越限即断输入复位）
bSustainOk := tonSustain.Q;                       // 维持时间满足
IF bAnyOver AND (NOT bAllInWin) THEN
    uInfo := 16#0002_0326;                        // 信息级：越限闭锁维持中
END_IF

(* === 段 4 · 联锁矩阵实例（无条件调用，双条件停机级）=== *)
abCondOk[0] := bH2oOk AND (NOT bHystWaterUp);     // 条件 0 = 水路有效且在窗
abCondOk[1] := bO2Ok AND (NOT bHystO2Up);         // 条件 1 = 氧路有效且在窗
auInvertMask := 16#0000;                          // 不取反
auTripMask := 16#0003;                            // 双路均停机级（bit0/bit1）
fbIlk(abConditionOk := abCondOk,                  // 条件表
      auInvertMask := auInvertMask,               // 取反掩码
      auTripMask := auTripMask,                   // 停机级掩码
      bEnable := bEnable AND bCfgOk,              // 使能透传
      bReset := rtrReset.Q);                      // 复位沿透传

(* === 段 5 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_GbaPhase.eIdle :
    IF uFault <> 16#0000 THEN
        _eState := E_DL_GbaPhase.eFault;          // 故障优先
    ELSIF bEnable AND bCfgOk AND bAnyOver THEN
        _eState := E_DL_GbaPhase.ePurge;          // 越限进净化请求相
    ELSIF bEnable AND bCfgOk THEN
        _eState := E_DL_GbaPhase.eWatch;          // 进监视相
    END_IF

E_DL_GbaPhase.eWatch :
    IF uFault <> 16#0000 THEN
        _eState := E_DL_GbaPhase.eFault;          // 故障转出
    ELSIF bAnyOver THEN
        _eState := E_DL_GbaPhase.ePurge;          // 越限转净化相
    END_IF

E_DL_GbaPhase.ePurge :
    IF uFault <> 16#0000 THEN
        _eState := E_DL_GbaPhase.eFault;          // 故障转出
    ELSIF bSustainOk AND (NOT bAnyOver) THEN
        _eState := E_DL_GbaPhase.eWatch;          // 双路回窗 + 维持满足：解除（路径可达）
    END_IF

E_DL_GbaPhase.eFault :
    IF uFault = 16#0000 THEN
        _eState := E_DL_GbaPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_GbaPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_0316;                       // 故障级：相 ID 越界
END_CASE

(* === 段 6 · 输出映射（净化优先互斥仲裁）=== *)
bPurgeReq := (_eState = E_DL_GbaPhase.ePurge);    // 净化请求（净化相保持）
bDoorPermit := fbIlk.bPermitToRun AND bSustainOk AND (NOT bPurgeReq);   // 许可 = 矩阵放行 + 维持满足 + 与净化互斥
IF (NOT bH2oOk) OR (NOT bO2Ok) THEN
    eNe107 := E_DL_Ne107Status.eFailure;          // 任一路无效：失效态（信号不可信）
ELSIF bAnyOver THEN
    eNe107 := E_DL_Ne107Status.eOutOfSpec;        // 越限：超出规格态
ELSIF bPurgeReq THEN
    eNe107 := E_DL_Ne107Status.eCheckFunction;    // 净化循环中：功能检查态
ELSIF bEnable AND bCfgOk THEN
    eNe107 := E_DL_Ne107Status.eOk;               // 正常态
ELSE
    eNe107 := E_DL_Ne107Status.eUnknown;          // 未取得有效数据：未知态（绝不归 eOk）
END_IF
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
