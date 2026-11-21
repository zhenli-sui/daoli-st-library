(*
  FB_DL_FilmTensionStepper  —  收卷步进张力叠加微调 / Rewinder stepped tension overlay trim
  分类 Category : DL_Motion
  码位 Code     : 16#04_0_A0
  版本 Version  : 1.0.0
  溯源 Source   : LGF Technology 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 张力偏差经限斜率步进累加为叠加偏置，叠加量限幅到张力带允许域（防累计漂移把轴拉飞）；
                  2) 只在叠加通道写入，不改基础轴目标（叠加 != 改目标）；
                  3) 张力反馈无效时冻结叠加并保持末次有效偏置，恢复后从保持点继续（无扰）。
  边界 Boundary : ① 叠加偏置总量限幅到张力带允许域（±fOffsetMax）；
                  ② 步进增量限斜率（每拍 <= fStepMax），且只写叠加通道不改基础轴目标；
                  ③ 张力反馈无效时冻结叠加并保持末次有效偏置；
                  ④ 输出三行同向：叠加偏置 → 合成位置 → 冻结标志。
  依赖 Depends  : FB_DL_SuperimposedMove（叠加通道执行，每拍无条件调用）

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_04A0 故障级：组态非法（增益/步进/叠加上限/任务周期 <= 0 或张力带上下限倒置）
    16#0002_04B0 故障级：叠加层执行故障（映射自依赖实例的故障标志）
    16#0002_04C0 信息级：张力反馈无效，叠加已冻结（不置 bError）
*)

TYPE E_DL_FtsPhase :
(
    eIdle    := 0,   // 空闲 / Idle
    eTrim    := 10,  // 叠加微调 / Overlay trimming
    eFrozen  := 20,  // 反馈无效冻结 / Frozen by invalid feedback
    eFault   := 90   // 故障锁定 / Fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_FilmTensionStepper
VAR_INPUT
    bEnable       : BOOL;                          // 总使能，FALSE 冻结叠加 / Master enable
    bReset        : BOOL;                          // 复位，上升沿清故障并归零叠加 / Reset, clears fault and zeroes overlay
    bZeroNow      : BOOL;                          // 叠加归零请求（走斜坡）/ Overlay zero request
    fTensionActN  : REAL;                          // 张力实测反馈 [N]，域 > 0 / Measured tension feedback [N]
    fTensionSpN   : REAL := 50.0;                  // 张力设定 [N]，域 > 0 / Tension setpoint [N]
    fBandN        : REAL := 5.0;                   // 张力带半宽 [N]，域 > 0 / Tension band half width [N]
    fOffsetMaxMm  : REAL := 3.0;                   // 叠加偏置上限 [mm]，域 > 0 / Overlay magnitude limit [mm]
    fOffsetSpeed  : REAL := 2.0;                   // 叠加斜坡限速 [mm/s]，域 > 0 / Overlay ramp speed [mm/s]
    fStepMaxMm    : REAL := 0.05;                  // 单拍步进上限 [mm]，域 > 0 / Step limit per scan [mm]
    fGainMmPerN   : REAL := 0.02;                  // 偏差到偏置增益 [mm/N]，域 > 0 / Error-to-offset gain
    fBasePosMm    : REAL := 0.0;                   // 基础轴位置（仅读，不改）/ Base axis position, read only
    fTaskCycle    : REAL := 0.01;                  // 任务周期 [s]，域 > 0 / Task cycle [s]
    fEps          : REAL := 1.0E-6;                // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    fOffsetCmdMm  : REAL;                          // 叠加偏置指令 [mm]（仅叠加通道）/ Overlay offset command [mm]
    fOffsetActMm  : REAL;                          // 叠加偏置实际值 [mm] / Actual overlay offset [mm]
    fSuperPosMm   : REAL;                          // 合成位置 [mm] = 基础 + 叠加 / Superimposed position [mm]
    bLimited      : BOOL;                          // 偏置已限幅标志 / Offset limited flag
    bFrozen       : BOOL;                          // 叠加冻结标志（保持型）/ Overlay frozen, held
    bError        : BOOL;                          // 故障标志，与故障级码配对 / Fault flag paired with fault codes
    uErrorId      : UDINT;                         // 事件码，0 = 无事件 / Event code, 0 = none
    eStateOut     : E_DL_FtsPhase;                 // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState       : E_DL_FtsPhase := E_DL_FtsPhase.eIdle;  // 内部状态 / Internal state
    rtrReset      : R_TRIG;                        // 复位沿 / Reset edge
    fbOverlay     : FB_DL_SuperimposedMove;        // 叠加通道实例（无条件调用）/ Superimposed move instance
    bCfgOk        : BOOL;                          // 组态合法标志 / Configuration valid
    bFbOk         : BOOL;                          // 张力反馈有效 / Feedback valid
    bInBand       : BOOL;                          // 偏差在张力带内（含容差）/ Error inside band
    fErrN         : REAL;                          // 张力偏差 [N] = 设定 − 实测 / Tension error [N]
    fStepMm       : REAL;                          // 本拍步进量 [mm] / Step this scan [mm]
    fCmdNextMm    : REAL;                          // 下一拍偏置指令 [mm] / Next offset command [mm]
    fCmdHoldMm    : REAL;                          // 保持的偏置指令 [mm] / Held offset command [mm]
    uFault        : UDINT;                         // 锁存故障码 / Latched fault code
    uInfo         : UDINT;                         // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_FTS_TMAX   : REAL := 10000.0;               // 张力物理域上限 [N] / Tension domain high [N]
    DL_FTS_MMMAX  : REAL := 100.0;                 // 偏置物理域上限 [mm] / Offset domain high [mm]
END_VAR

(* === 段 0 · 实例刷新（无条件周期调用）=== *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸与反馈域闸 === *)
bCfgOk := (fGainMmPerN > fEps) AND (fStepMaxMm > fEps) AND (fOffsetMaxMm > fEps)
          AND (fOffsetSpeed > fEps) AND (fTaskCycle > fEps) AND (fBandN > fEps)
          AND (fTensionSpN > fEps) AND (fOffsetMaxMm <= DL_FTS_MMMAX)
          AND (fGainMmPerN = fGainMmPerN) AND (fTensionSpN = fTensionSpN);   // 含 NaN 自反
IF NOT bCfgOk THEN
    uFault := 16#0002_04A0;                       // 故障级：组态非法
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清锁存（复位路径可达）
    fCmdHoldMm := 0.0;                            // 复位归零偏置
    bFrozen := FALSE;                             // 冻结标志同步复位
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零
bFbOk := (fTensionActN = fTensionActN) AND (ABS(fTensionActN) < 1.0E30)
         AND (fTensionActN > 0.0) AND (fTensionActN <= DL_FTS_TMAX);   // NaN 自反 + 正域闸
IF bFbOk THEN
    fErrN := fTensionSpN - fTensionActN;          // 偏差 = 设定 − 实测
    bInBand := ABS(fErrN) <= (fBandN + fEps);     // 带内判据（浮点容差）
ELSE
    fErrN := 0.0;                                 // 无效反馈：偏差不出结论
    bInBand := TRUE;                              // 无效时视作带内（不动叠加）
END_IF

(* === 段 2 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_FtsPhase.eIdle :
    fCmdNextMm := fCmdHoldMm;                     // 空闲保持当前偏置
    IF uFault <> 16#0000 THEN
        _eState := E_DL_FtsPhase.eFault;          // 故障优先
    ELSIF NOT bEnable THEN
        _eState := E_DL_FtsPhase.eFrozen;         // 失能即冻结
    ELSIF NOT bFbOk THEN
        bFrozen := TRUE;                          // 反馈无效：冻结
        uInfo := 16#0002_04C0;                    // 信息级：叠加已冻结
        _eState := E_DL_FtsPhase.eFrozen;
    ELSIF bEnable THEN
        _eState := E_DL_FtsPhase.eTrim;           // 进入微调相
    END_IF

E_DL_FtsPhase.eTrim :
    bFrozen := FALSE;                             // 微调相不冻结
    IF (NOT bEnable) OR (NOT bFbOk) THEN
        bFrozen := TRUE;                          // 反馈丢失/失能：冻结
        uInfo := 16#0002_04C0;                    // 信息级：叠加已冻结
        _eState := E_DL_FtsPhase.eFrozen;
    ELSIF bInBand THEN
        fCmdNextMm := fCmdHoldMm;                 // 带内：保持偏置（不继续累加）
        IF bZeroNow THEN
            fCmdNextMm := 0.0;                    // 归零请求：目标置 0（仍走斜坡）
        END_IF
    ELSE
        fStepMm := fErrN * fGainMmPerN;           // 偏差折算步进
        IF fStepMm > fStepMaxMm THEN
            fStepMm := fStepMaxMm;                // 步进上限（正向限斜率）
        END_IF
        IF fStepMm < -fStepMaxMm THEN
            fStepMm := -fStepMaxMm;               // 步进下限（负向限斜率）
        END_IF
        fCmdNextMm := fCmdHoldMm + fStepMm;       // 累加步进
        IF fCmdNextMm > fOffsetMaxMm THEN
            fCmdNextMm := fOffsetMaxMm;           // 叠加总量上限（防漂移拉飞）
        END_IF
        IF fCmdNextMm < -fOffsetMaxMm THEN
            fCmdNextMm := -fOffsetMaxMm;          // 叠加总量下限
        END_IF
    END_IF
    fCmdHoldMm := fCmdNextMm;                     // 偏置指令记账（仅叠加通道）
    IF ABS(fCmdNextMm) >= (fOffsetMaxMm - fEps) THEN
        bLimited := TRUE;                         // 触限标志
    ELSE
        bLimited := FALSE;                        // 未触限，逐拍重算
    END_IF

E_DL_FtsPhase.eFrozen :
    bFrozen := TRUE;                              // 冻结标志保持
    fCmdNextMm := fCmdHoldMm;                     // 保持末次有效偏置（不清零、不外推）
    IF bFbOk AND bEnable AND (uFault = 16#0000) THEN
        bFrozen := FALSE;                         // 反馈恢复：解冻（可到达的解除路径）
        uInfo := 16#0000;                         // 信息码清除
        _eState := E_DL_FtsPhase.eTrim;           // 从保持点继续（无扰）
    END_IF

E_DL_FtsPhase.eFault :
    bFrozen := TRUE;                              // 故障态冻结
    fCmdNextMm := fCmdHoldMm;                     // 保持偏置（不追发新指令）
    IF uFault = 16#0000 THEN
        _eState := E_DL_FtsPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_FtsPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_04A0;                       // 故障级：相 ID 越界
    bFrozen := TRUE;                              // 安全侧冻结
    fCmdNextMm := 0.0;                            // 安全侧偏置 0
END_CASE

(* === 段 3 · 叠加通道实例（每拍无条件调用，只写叠加不改基础目标）=== *)
fbOverlay(bEnable := bEnable AND (NOT bFrozen) AND (uFault = 16#0000),   // 冻结/故障时不推进斜坡
          fBasePos := fBasePosMm,                 // 基础轴位置（只读，不改目标）
          fOffsetCmd := fCmdNextMm,               // 叠加偏置指令
          fMaxOffset := fOffsetMaxMm,             // 偏移限幅
          fMaxOffsetSpeed := fOffsetSpeed,        // 偏移斜坡限速
          fTaskCycle := fTaskCycle,               // 任务周期
          bZeroNow := bZeroNow AND (NOT bFrozen));// 归零请求（冻结期间不生效）

(* === 段 4 · 输出映射（三行同向：偏置 → 合成位置 → 冻结标志）=== *)
fOffsetCmdMm := fCmdNextMm;                       // 偏置指令输出
IF fbOverlay.bActive THEN
    fOffsetActMm := fbOverlay.fOffsetAct;         // 叠加实际值
    fSuperPosMm := fbOverlay.fSuperPos;           // 合成位置
ELSE
    fOffsetActMm := fCmdHoldMm;                   // 未激活：保持偏置
    fSuperPosMm := fBasePosMm + fCmdHoldMm;       // 合成位置按记账值计算
END_IF
IF fbOverlay.bError THEN
    uFault := 16#0002_04B0;                       // 故障级：叠加层执行故障（映射依赖实例）
END_IF
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
