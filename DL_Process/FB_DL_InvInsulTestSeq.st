(*
  FB_DL_InvInsulTestSeq  —  逆变器绝缘测试加压-保持-泄放联锁顺控 / Inverter insulation test sequence with discharge interlock
  分类 Category : DL_Process
  码位 Code     : 16#06_0_98
  版本 Version  : 1.0.0
  溯源 Source   : ISA-88 相模型语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 加压-保持-泄放三态顺控（复用 FB_DL_InterlockMatrix 联锁前置）；
                  2) 加压中急停立即转泄放相（安全侧打断）；
                  3) 泄放未确认前禁放行下工序；相完成仅在泄放反馈确认后置位。
  边界 Boundary : ① 泄放未确认前禁放行下工序（安全侧默认，bTestOk 不置位）；
                  ② 加压中急停立即转泄放相（打断优先级最高）；
                  ③ 各相超时独立 TON 升级；
                  ④ 测试电压反馈无效判「不可判」而非 OK；
                  ⑤ 输出三行同向：相状态 → 测试结论 → 联锁出口。
  依赖 Depends  : FB_DL_InterlockMatrix × 1（联锁前置，每拍无条件调用）

  码表 Error codes（本件子码步进 16#30 · 本格 98 与既有 9X 子码段冲突，错位至 C8/D8 避让）:
    16#0002_06C8 故障级：组态非法（任一相时长 <= 0 / 电压门限 <= 0）
    16#0002_06D8 故障级：相超时（加压/保持/泄放任一相在限时内未完成，锁存需复位）
    16#0002_06B8 信息级：电压反馈无效判不可判 / 泄放未确认不放行（不置 bError）
*)

TYPE E_DL_IitPhase :
(
    eIdle       := 0,  // 空闲 / Idle
    ePressurize := 10, // 加压相 / HV apply phase
    eHold       := 20, // 保持相 / Hold phase
    eDischarge  := 30, // 泄放相 / Discharge phase
    eDone       := 40, // 测试完成（泄放已确认）/ Test done, discharge confirmed
    eFault      := 90  // 超时/联锁故障锁定 / Timeout or interlock fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_InvInsulTestSeq
VAR_INPUT
    bTestCmd      : BOOL;                           // 测试启动命令 / Test start command
    bEStop        : BOOL;                           // 急停（加压/保持相打断转泄放）/ Emergency stop
    bVoltFbOk     : BOOL;                           // 电压反馈有效前置 / Voltage feedback valid flag
    fVoltFb       : REAL;                           // 测试电压反馈 [V] / Test voltage feedback [V]
    fVoltSp       : REAL := 1000.0;                 // 测试电压设定 [V]，域 > 0 / Test voltage setpoint [V]
    fVoltWinV     : REAL := 50.0;                   // 保持相电压窗半宽 [V]，域 > 0 / Hold voltage window [V]
    bDischargeFb  : BOOL;                           // 泄放反馈（残压低于安全值）/ Discharge feedback, residual below safe
    bReset        : BOOL;                           // 复位，上升沿清故障 / Reset, clears fault
    tApplyMax     : TIME := T#10S;                  // 加压相限时 [s]，域 > 0 / Apply phase timeout
    tHoldMax      : TIME := T#5S;                   // 保持相限时 [s]，域 > 0 / Hold phase timeout
    tDischMax     : TIME := T#30S;                  // 泄放相限时 [s]，域 > 0 / Discharge phase timeout
    fEps          : REAL := 1.0E-6;                 // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    bApplyHv      : BOOL;                           // 加压出口 / HV apply output
    bDischargeCmd : BOOL;                           // 泄放命令出口 / Discharge command output
    bTestOk       : BOOL;                           // 测试结论（仅在泄放确认后置位）/ Test verdict, only after discharge confirmed
    bInterlock    : BOOL;                           // 联锁出口（TRUE = 允许加压）/ Interlock output
    bIndeterminate: BOOL;                           // 不可判标志（反馈无效）/ Indeterminate flag
    bError        : BOOL;                           // 故障标志，与故障级码配对 / Fault flag
    uErrorId      : UDINT;                          // 事件码，0 = 无事件 / Event code
    eStateOut     : E_DL_IitPhase;                  // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState       : E_DL_IitPhase := E_DL_IitPhase.eIdle;  // 内部状态 / Internal state
    fbIlk         : FB_DL_InterlockMatrix;          // 联锁矩阵实例（无条件调用）/ Interlock matrix instance
    rtrStart      : R_TRIG;                         // 启动沿 / Start edge
    rtrReset      : R_TRIG;                         // 复位沿 / Reset edge
    tonApply      : TON;                            // 加压相超时（独立 TON）/ Apply timeout
    tonHold       : TON;                            // 保持相超时 / Hold timeout
    tonDisch      : TON;                            // 泄放相超时 / Discharge timeout
    abCondOk      : ARRAY[0..15] OF BOOL;           // 联锁条件表 / Interlock condition table
    auInvertMask  : WORD;                           // 取反掩码 / Invert mask
    auTripMask    : WORD;                           // 停机级掩码 / Trip-class mask
    bCfgOk        : BOOL;                           // 组态合法标志 / Configuration valid
    bVoltOk       : BOOL;                           // 电压反馈本拍有效 / Voltage feedback valid
    bVoltInWin    : BOOL;                           // 保持相电压在窗 / Hold voltage in window
    bIlkPermit    : BOOL;                           // 联锁放行 / Interlock permit
    uFault        : UDINT;                          // 锁存故障码 / Latched fault code
    uInfo         : UDINT;                          // 信息级码 / Information code
END_VAR

(* === 段 0 · 实例刷新 === *)
rtrStart(CLK := bTestCmd);                        // 每拍刷新启动沿
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸 === *)
bCfgOk := (TIME_TO_REAL(tApplyMax) > fEps) AND (TIME_TO_REAL(tHoldMax) > fEps)
          AND (TIME_TO_REAL(tDischMax) > fEps)    // 三相时长正域
          AND (fVoltSp > fEps) AND (fVoltWinV > fEps)   // 电压设定与窗正域
          AND (fVoltSp = fVoltSp) AND (fVoltWinV = fVoltWinV);  // NaN 自反
IF NOT bCfgOk THEN
    uFault := 16#0002_06C8;                       // 故障级：组态非法
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清锁存（解除路径可达）
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零

(* === 段 2 · 相超时定时器（独立 TON，相离开即断输入，R40）=== *)
tonApply(IN := (_eState = E_DL_IitPhase.ePressurize), PT := tApplyMax);   // 加压相超时
tonHold(IN := (_eState = E_DL_IitPhase.eHold), PT := tHoldMax);           // 保持相超时
tonDisch(IN := (_eState = E_DL_IitPhase.eDischarge), PT := tDischMax);    // 泄放相超时
IF tonApply.Q OR tonHold.Q OR tonDisch.Q THEN
    uFault := 16#0002_06D8;                       // 故障级：任一相超时（锁存，非死等）
END_IF

(* === 段 3 · 联锁矩阵（无条件调用：急停未触发 + 电压反馈有效 + 复位态）=== *)
abCondOk[0] := NOT bEStop;                        // 条件 0 = 急停未触发
abCondOk[1] := bVoltFbOk;                         // 条件 1 = 电压反馈有效
abCondOk[2] := bDischargeFb OR (_eState = E_DL_IitPhase.eIdle);   // 条件 2 = 初始无残压或空闲态
auInvertMask := 16#0000;                          // 不取反
auTripMask := 16#0007;                            // 三条件均停机级
fbIlk(abConditionOk := abCondOk,                  // 条件表
      auInvertMask := auInvertMask,               // 取反掩码
      auTripMask := auTripMask,                   // 停机级掩码
      bEnable := TRUE,                            // 矩阵恒使能（安全联锁语义由条件表与停机级掩码承载）
      bReset := rtrReset.Q);                      // 复位沿透传
bIlkPermit := fbIlk.bPermitToRun;                 // 联锁放行
bInterlock := bIlkPermit;                         // 联锁出口

(* === 段 4 · 电压反馈域闸与保持窗判定 === *)
bVoltOk := bVoltFbOk AND (fVoltFb = fVoltFb) AND (fVoltFb >= 0.0) AND (fVoltFb < 1.0E30);  // NaN 自反 + 非负域
bVoltInWin := bVoltOk AND (ABS(fVoltFb - fVoltSp) <= fVoltWinV + fEps);   // 保持相电压在窗
IF (_eState = E_DL_IitPhase.eHold) AND (NOT bVoltOk) THEN
    uInfo := 16#0002_06B8;                        // 信息级：电压反馈无效判不可判
END_IF
bIndeterminate := (NOT bVoltOk) AND ((_eState = E_DL_IitPhase.eHold)
                    OR (_eState = E_DL_IitPhase.ePressurize));   // 不可判标志（非 OK）

(* === 段 5 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_IitPhase.eIdle :
    bTestOk := FALSE;                             // 空闲未完成
    IF uFault <> 16#0000 THEN
        _eState := E_DL_IitPhase.eFault;          // 故障优先
    ELSIF rtrStart.Q AND bIlkPermit AND bCfgOk THEN
        _eState := E_DL_IitPhase.ePressurize;     // 联锁放行才进加压相
    END_IF

E_DL_IitPhase.ePressurize :
    bApplyHv := bIlkPermit AND (uFault = 16#0000);   // 加压出口（联锁+无故障门控）
    bDischargeCmd := FALSE;                       // 加压相不出泄放命令
    IF bEStop THEN
        _eState := E_DL_IitPhase.eDischarge;      // 急停立即转泄放相（打断优先级最高）
    ELSIF uFault <> 16#0000 THEN
        _eState := E_DL_IitPhase.eFault;          // 超时转故障
    ELSIF bVoltInWin THEN
        _eState := E_DL_IitPhase.eHold;           // 电压进窗转保持相
    END_IF

E_DL_IitPhase.eHold :
    bApplyHv := TRUE;                             // 保持相维持加压
    bDischargeCmd := FALSE;                       // 保持相不出泄放命令
    IF bEStop THEN
        _eState := E_DL_IitPhase.eDischarge;      // 急停立即转泄放相
    ELSIF uFault <> 16#0000 THEN
        _eState := E_DL_IitPhase.eFault;          // 超时转故障
    ELSIF tonHold.Q THEN
        _eState := E_DL_IitPhase.eDischarge;      // 保持时限到转泄放相（正常流程）
    END_IF

E_DL_IitPhase.eDischarge :
    bApplyHv := FALSE;                            // 泄放相撤加压
    bDischargeCmd := TRUE;                        // 泄放命令保持
    IF uFault <> 16#0000 THEN
        _eState := E_DL_IitPhase.eFault;          // 泄放超时转故障
    ELSIF bDischargeFb AND (NOT bEStop) THEN
        bTestOk := TRUE;                          // 泄放反馈确认：相完成仅此时置位
        _eState := E_DL_IitPhase.eDone;           // 转完成相
    ELSE
        uInfo := 16#0002_06B8;                    // 信息级：泄放未确认不放行
    END_IF

E_DL_IitPhase.eDone :
    bApplyHv := FALSE;                            // 完成相撤加压
    bDischargeCmd := FALSE;                       // 完成相撤泄放命令
    bTestOk := TRUE;                              // 结论保持（防同拍抹除）
    IF rtrStart.Q THEN
        bTestOk := FALSE;                         // 新启动沿重开
        _eState := E_DL_IitPhase.ePressurize;     // 回加压相
    END_IF

E_DL_IitPhase.eFault :
    bApplyHv := FALSE;                            // 故障相撤加压
    bDischargeCmd := TRUE;                        // 故障安全侧：泄放命令保持
    bTestOk := FALSE;                             // 故障不出结论
    IF uFault = 16#0000 THEN
        _eState := E_DL_IitPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_IitPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_06C8;                       // 故障级：相 ID 越界复用组态码段
END_CASE

(* === 段 6 · 输出映射 === *)
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
