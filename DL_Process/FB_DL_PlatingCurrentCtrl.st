(*
  FB_DL_PlatingCurrentCtrl  —  电镀槽位电流密度闭环与液位联锁 / Plating bath current-density control with level interlock
  分类 Category : DL_Process
  码位 Code     : 16#06_0_96
  版本 Version  : 1.0.0
  溯源 Source   : LBP（Lediberg Process Library）语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 电流设定 = 目标电流密度 × 可镀面积（面积换算），钳到整流器量程域；
                  2) 液位低于下限禁投并保持（联锁可解除），液位无效按低液位安全侧处理；
                  3) 回读与设定偏差持续超窗分级告警。
  边界 Boundary : ① 面积 <= 0 拒算（除零前置，面积换算分母域闸）；
                  ② 液位无效按低液位安全侧处理（R42 家族：无效不作有效低判）；
                  ③ 回读与设定偏差持续超窗分级（信息级持续告警 → 超时升级故障级）；
                  ④ 面积换算结果钳到整流器量程域并置钳位标志；
                  ⑤ 输出三行同向：电流设定 → 投入许可 → 分级告警。
  依赖 Depends  : 无实例依赖（面积换算与偏差分级自含实现）

  码表 Error codes（本件子码步进 16#30 · 本格 96 与既有 9X 子码段冲突，错位至 C6/D6 避让）:
    16#0002_06C6 故障级：组态非法（密度或量程 <= 0 / 量程倒置 / 液位限倒置 / 偏差窗 <= 0）
    16#0002_06D6 故障级：回读偏差持续超窗升级（锁存需复位）
    16#0002_06B6 信息级：液位低禁投保持 / 面积非法拒算 / 回读偏差超窗提示（不置 bError）
*)

TYPE E_DL_PlcPhase :
(
    eIdle     := 0,  // 空闲 / Idle
    ePlating  := 10, // 投入运行（电流闭环）/ Plating in operation
    eLockout  := 20, // 液位低禁投保持 / Level-low lockout
    eFrozen   := 30, // 反馈无效冻结 / Frozen by invalid feedback
    eFault    := 90  // 故障锁定 / Fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_PlatingCurrentCtrl
VAR_INPUT
    bEnable       : BOOL;                           // 总使能，FALSE 回空闲 / Master enable
    bReset        : BOOL;                           // 复位，上升沿清故障 / Reset, clears fault
    fDensitySp    : REAL := 2.0;                    // 目标电流密度 [A/dm²]，域 > 0 / Target current density [A/dm2]
    fAreaDm2      : REAL;                           // 可镀面积 [dm²]，域 > 0 / Platable area [dm2]
    fRectMaxA     : REAL := 1000.0;                 // 整流器量程上限 [A]，域 > 0 / Rectifier range high [A]
    fRectReadA    : REAL;                           // 整流器回读电流 [A] / Rectifier readback current [A]
    fLevelPct     : REAL;                           // 槽液位 [%] / Bath level [%]
    fLevelLoPct   : REAL := 20.0;                   // 液位下限 [%]，域 >= 0 / Level low limit [%]
    fDevWinA      : REAL := 20.0;                   // 回读偏差窗 [A]，域 > 0 / Readback deviation window [A]
    uDevConfirm   : UINT := 10;                     // 偏差升级确认拍数 [拍] / Deviation escalation confirm scans
    fEps          : REAL := 1.0E-6;                 // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    fCurrentSpA   : REAL;                           // 电流设定输出 [A]，已钳量程域 / Current setpoint output [A]
    bPlatingOk    : BOOL;                           // 投入运行标志 / Plating in operation flag
    bInterlock    : BOOL;                           // 液位联锁出口（TRUE = 禁投）/ Level interlock output
    bClamped      : BOOL;                           // 换算结果钳位标志 / Setpoint clamped flag
    bDevWarn      : BOOL;                           // 回读偏差超窗提示（信息级）/ Readback deviation warning
    bError        : BOOL;                           // 故障标志，与故障级码配对 / Fault flag
    uErrorId      : UDINT;                          // 事件码，0 = 无事件 / Event code
    eStateOut     : E_DL_PlcPhase;                  // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState       : E_DL_PlcPhase := E_DL_PlcPhase.eIdle;  // 内部状态 / Internal state
    rtrReset      : R_TRIG;                         // 复位沿 / Reset edge
    bCfgOk        : BOOL;                           // 组态合法标志 / Configuration valid
    bAreaOk       : BOOL;                           // 面积本拍有效（> 0 除零前置）/ Area valid this scan
    bLevelOk      : BOOL;                           // 液位本拍有效 / Level valid this scan
    bLevelLow     : BOOL;                           // 液位低（无效按低处理，安全侧）/ Level low, invalid treated as low
    bRectOk       : BOOL;                           // 回读本拍有效 / Readback valid this scan
    bDevOver      : BOOL;                           // 回读偏差超窗（电平）/ Deviation over window
    uDevCnt       : UINT;                           // 偏差升级确认计数 [拍] / Deviation escalation counter
    fSpRawA       : REAL;                           // 面积换算原始设定 [A] / Raw converted setpoint [A]
    uFault        : UDINT;                          // 锁存故障码 / Latched fault code
    uInfo         : UDINT;                          // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_PLC_INFMAX : REAL := 1.0E30;                 // 有限值幅值上限 [A] / Finite magnitude bound [A]
END_VAR

(* === 段 0 · 实例刷新 === *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸 === *)
bCfgOk := (fDensitySp > fEps) AND (fRectMaxA > fEps)  // 密度与量程正域
          AND (fDevWinA > fEps)                   // 偏差窗正域
          AND (fDensitySp = fDensitySp) AND (fRectMaxA = fRectMaxA);  // NaN 自反
IF NOT bCfgOk THEN
    uFault := 16#0002_06C6;                       // 故障级：组态非法
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清锁存（解除路径可达）
    uDevCnt := UINT#0;                            // 偏差计数复位
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零

(* === 段 2 · 输入域闸（面积除零前置 / 液位无效按低安全侧 / 回读域闸）=== *)
bAreaOk := (fAreaDm2 = fAreaDm2) AND (fAreaDm2 > fEps) AND (fAreaDm2 < DL_PLC_INFMAX);  // 面积正域（<= 0 拒算）
bLevelOk := (fLevelPct = fLevelPct) AND (fLevelPct >= 0.0) AND (fLevelPct <= 100.0);    // 液位域闸
bRectOk := (fRectReadA = fRectReadA) AND (fRectReadA >= 0.0) AND (fRectReadA < DL_PLC_INFMAX);  // 回读域闸
IF NOT bAreaOk THEN
    uInfo := 16#0002_06B6;                        // 信息级：面积非法拒算
END_IF
IF bLevelOk THEN
    bLevelLow := fLevelPct < fLevelLoPct;         // 有效液位低于下限
ELSE
    bLevelLow := TRUE;                            // 液位无效按低液位安全侧处理（R42 家族）
END_IF

(* === 段 3 · 面积换算与量程钳位 === *)
fSpRawA := 0.0;                                   // 原始设定缺省 0（拒算口径）
IF bAreaOk THEN
    fSpRawA := fDensitySp * fAreaDm2;             // 设定 = 密度 × 面积 [A]
END_IF
bClamped := bAreaOk AND (fSpRawA > fRectMaxA);    // 钳位标志本拍重算
IF fSpRawA > fRectMaxA THEN
    fSpRawA := fRectMaxA;                         // 钳到整流器量程域上限
END_IF
IF fSpRawA < 0.0 THEN
    fSpRawA := 0.0;                               // 下限安全侧钳位
END_IF

(* === 段 4 · 回读偏差分级判据（本拍重算）=== *)
bDevOver := bRectOk AND (ABS(fRectReadA - fSpRawA) > fDevWinA + fEps);  // 偏差超窗（电平）
IF bDevOver THEN
    uDevCnt := uDevCnt + UINT#1;                  // 超窗确认计数累加
    IF uDevCnt >= uDevConfirm THEN
        uFault := 16#0002_06D6;                   // 故障级：偏差持续超窗升级（锁存）
    ELSE
        uInfo := 16#0002_06B6;                    // 信息级：回读偏差超窗提示
    END_IF
ELSE
    uDevCnt := UINT#0;                            // 未超窗计数归零
END_IF
bDevWarn := bDevOver AND (uFault = 16#0000);      // 提示出口（未升级时）

(* === 段 5 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_PlcPhase.eIdle :
    bPlatingOk := FALSE;                          // 空闲未投入
    IF uFault <> 16#0000 THEN
        _eState := E_DL_PlcPhase.eFault;          // 故障优先
    ELSIF NOT bAreaOk THEN
        _eState := E_DL_PlcPhase.eIdle;           // 面积非法不出设定，保持空闲
    ELSIF bLevelLow THEN
        _eState := E_DL_PlcPhase.eLockout;        // 液位低进禁投
    ELSIF bEnable AND bCfgOk THEN
        _eState := E_DL_PlcPhase.ePlating;        // 投入运行
    END_IF

E_DL_PlcPhase.ePlating :
    bPlatingOk := TRUE;                           // 投入标志
    IF uFault <> 16#0000 THEN
        _eState := E_DL_PlcPhase.eFault;          // 偏差升级转故障
    ELSIF bLevelLow THEN
        _eState := E_DL_PlcPhase.eLockout;        // 液位低禁投保持（联锁可解除）
    ELSIF NOT bEnable THEN
        _eState := E_DL_PlcPhase.eIdle;           // 失能回空闲
    END_IF

E_DL_PlcPhase.eLockout :
    bPlatingOk := FALSE;                          // 禁投不投入
    IF NOT bLevelLow THEN
        _eState := E_DL_PlcPhase.ePlating;        // 液位恢复回投入（联锁解除路径可达）
    ELSIF NOT bEnable THEN
        _eState := E_DL_PlcPhase.eIdle;           // 失能回空闲
    END_IF

E_DL_PlcPhase.eFrozen :
    bPlatingOk := FALSE;                          // 冻结不投入
    IF bEnable AND (uFault = 16#0000) THEN
        _eState := E_DL_PlcPhase.ePlating;        // 恢复回投入（解除路径可达）
    END_IF

E_DL_PlcPhase.eFault :
    bPlatingOk := FALSE;                          // 故障不投入
    IF uFault = 16#0000 THEN
        uDevCnt := UINT#0;                        // 解锁计数复位
        _eState := E_DL_PlcPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_PlcPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_06C6;                       // 故障级：相 ID 越界复用组态码段
END_CASE
bInterlock := bLevelLow OR (_eState = E_DL_PlcPhase.eFault);   // 联锁出口段尾单点映射

(* === 段 6 · 输出映射 === *)
IF (_eState = E_DL_PlcPhase.ePlating) AND bAreaOk THEN
    fCurrentSpA := fSpRawA;                       // 投入相：输出换算设定
ELSE
    fCurrentSpA := 0.0;                           // 其余相：设定回零（安全侧）
END_IF
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
