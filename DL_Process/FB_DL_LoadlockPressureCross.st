(*
  FB_DL_LoadlockPressureCross  —  Loadlock 双表压力交叉校验与误开门拦截 / Loadlock dual-gauge cross check and door interlock
  分类 Category : DL_Process
  码位 Code     : 16#06_0_83
  版本 Version  : 1.0.0
  溯源 Source   : ISA-18.2 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 双表压力各自过 NE43 有效域后计算偏差，偏差越窗即判交叉故障并锁存首出表号；
                  2) 任一表无效即禁开门（禁用无效值参与偏差计算）；
                  3) 开门许可仅由「双表一致 AND 压力到位」两条件同时满足产生，解除路径可达。
  边界 Boundary : ① 双表各自 NE43 有效域闸，任一无效即禁开门，禁用无效值参与偏差计算；
                  ② 偏差窗上下限配比约束（容差 > 0、目标压力 > 0、迟滞 ≤ 容差/2），非法即组态报码；
                  ③ 许可解锁条件可从「双表一致 AND 压力到位」到达（FB33-2 可达性）；
                  ④ 拦截态三行同向：许可 FALSE → 偏差记录保持 → 拦截标志 TRUE。
  依赖 Depends  : FB_DL_ToleranceWindow（偏差窗判定，每拍无条件调用）

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_0683 故障级：偏差窗组态非法（容差 <= 0 或迟滞 > 容差/2 或目标压力 <= 0）
    16#0002_0693 故障级：表 A / 表 B 信号无效（NE43 域外或缺省），禁开门
    16#0002_06A3 信息级：交叉偏差越窗（信息记录，故障锁存由 0683 族承担）
*)

TYPE E_DL_LlxcPhase :
(
    eIdle    := 0,   // 空闲 / Idle
    eCheck   := 10,  // 偏差校验中 / Cross check running
    ePermit  := 20,  // 允许开门 / Door permitted
    eBlocked := 30,  // 拦截（表无效或偏差越窗）/ Blocked
    eFault   := 90   // 故障锁定 / Fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_LoadlockPressureCross
VAR_INPUT
    bEnable       : BOOL;                         // 总使能，FALSE 禁开门 / Master enable, FALSE forbids door
    bReset        : BOOL;                         // 复位，上升沿清锁存 / Reset, clears latches
    fPressAKPa    : REAL;                         // 表 A 压力 [kPa abs]，域 0.001~200 / Gauge A pressure [kPa abs]
    bValidAK      : BOOL;                         // 表 A 信号有效（NE43 已在传感器侧判定）/ Gauge A signal valid
    fPressBKPa    : REAL;                         // 表 B 压力 [kPa abs]，域 0.001~200 / Gauge B pressure [kPa abs]
    bValidBK      : BOOL;                         // 表 B 信号有效 / Gauge B signal valid
    fDevMaxKPa    : REAL := 0.5;                  // 允许交叉偏差 [kPa]，域 > 0 / Allowed cross deviation [kPa]
    fDevHystKPa   : REAL := 0.05;                 // 偏差窗迟滞 [kPa]，域 0~容差/2 / Deviation hysteresis [kPa]
    fPressTargetKPa : REAL := 101.3;              // 开门目标压力 [kPa abs]，域 > 0 / Door-open target pressure
    fPressTolKPa  : REAL := 5.0;                  // 压力到位容差 [kPa]，域 > 0 / Pressure-in-place tolerance
    fEps          : REAL := 1.0E-6;               // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    bDoorPermit   : BOOL;                         // 开门许可（唯一放行信号）/ Door permit, the only release
    bCrossFault   : BOOL;                         // 交叉故障标志（保持型）/ Cross fault flag, held
    bPressInPlace : BOOL;                         // 压力到位标志 / Pressure in place
    fDevKPa       : REAL;                         // 当前双表偏差 [kPa] / Current cross deviation [kPa]
    nFirstOut     : INT;                          // 首出表号 1 = A，2 = B，0 = 无 / First-out gauge, 0 = none
    bError        : BOOL;                         // 故障标志，与故障级码配对 / Fault flag paired with fault codes
    uErrorId      : UDINT;                        // 事件码，0 = 无事件 / Event code, 0 = none
    eStateOut     : E_DL_LlxcPhase;               // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState       : E_DL_LlxcPhase := E_DL_LlxcPhase.eIdle;  // 内部状态 / Internal state
    rtrReset      : R_TRIG;                       // 复位沿 / Reset edge
    fbDevWin      : FB_DL_ToleranceWindow;        // 偏差窗判定实例（无条件调用）/ Deviation window instance
    bCfgOk        : BOOL;                         // 组态合法标志 / Configuration valid
    bAOk          : BOOL;                         // 表 A 有效（域闸后）/ Gauge A valid after gating
    bBOk          : BOOL;                         // 表 B 有效（域闸后）/ Gauge B valid after gating
    bCrossOk      : BOOL;                         // 双表一致标志 / Gauges agree flag
    fDevAbs       : REAL;                         // 偏差绝对值 [kPa] / Absolute deviation [kPa]
    uFault        : UDINT;                        // 锁存故障码 / Latched fault code
    uInfo         : UDINT;                        // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_LL_PMIN    : REAL := 0.001;                // 压力物理域下限 [kPa abs] / Pressure domain low
    DL_LL_PMAX    : REAL := 200.0;                // 压力物理域上限 [kPa abs] / Pressure domain high
END_VAR

(* === 段 0 · 实例刷新（无条件周期调用）=== *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · NE43 有效域闸：任一表无效即不参与偏差计算 === *)
bAOk := bValidAK AND (fPressAKPa = fPressAKPa) AND (ABS(fPressAKPa) < 1.0E30)
        AND (fPressAKPa >= DL_LL_PMIN) AND (fPressAKPa <= DL_LL_PMAX);       // 表 A NaN 自反 + 域闸
bBOk := bValidBK AND (fPressBKPa = fPressBKPa) AND (ABS(fPressBKPa) < 1.0E30)
        AND (fPressBKPa >= DL_LL_PMIN) AND (fPressBKPa <= DL_LL_PMAX);       // 表 B NaN 自反 + 域闸
fDevKPa := fPressAKPa - fPressBKPa;               // 偏差仅在域内可信，域外由状态机拦截
fDevAbs := ABS(fDevKPa);                          // 偏差绝对值

(* === 段 2 · 组态闸：偏差窗配比约束（上限 > 下限）=== *)
bCfgOk := (fDevMaxKPa > fEps) AND (fPressTolKPa > fEps) AND (fPressTargetKPa > fEps)
          AND (fDevHystKPa >= 0.0) AND (fDevHystKPa <= (fDevMaxKPa * 0.5))
          AND (fDevMaxKPa = fDevMaxKPa) AND (fPressTolKPa = fPressTolKPa)
          AND (fPressTargetKPa = fPressTargetKPa);                            // 含 NaN 自反判据
IF NOT bCfgOk THEN
    uFault := 16#0002_0683;                       // 故障级：偏差窗组态非法
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 组态修正后复位沿解锁
END_IF

(* === 段 3 · 偏差窗实例（每拍无条件调用，输入逐拍注入）=== *)
fbDevWin(bEnable := bAOk AND bBOk,                // 仅双表均有效才判窗（无效值禁参与）
         fTarget := 0.0,                          // 目标 = 零偏差
         fActual := fDevKPa,                      // 实际 = 双表偏差
         fTolerance := fDevMaxKPa,                // 公差半带宽
         fHysteresis := fDevHystKPa);             // 迟滞防边界抖动
bCrossOk := fbDevWin.bOk;                         // 双表一致判据（含迟滞）
bPressInPlace := (ABS(fPressAKPa - fPressTargetKPa) <= fPressTolKPa)
                 AND (ABS(fPressBKPa - fPressTargetKPa) <= fPressTolKPa);   // 压力到位双表同向判定

(* === 段 4 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_LlxcPhase.eIdle :
    bDoorPermit := FALSE;                         // 空闲禁开门
    bCrossFault := FALSE;                         // 交叉故障复位（非置位型）
    nFirstOut := 0;                               // 首出复位
    uInfo := 16#0000;                             // 信息码清零
    IF uFault = 16#0002_0683 THEN
        _eState := E_DL_LlxcPhase.eFault;         // 组态故障优先
    ELSE
        _eState := E_DL_LlxcPhase.eCheck;         // 进入校验相
    END_IF

E_DL_LlxcPhase.eCheck :
    IF (NOT bAOk) OR (NOT bBOk) THEN
        nFirstOut := 1;                           // 表 A 无效优先记首出（A 为主表）
        IF bAOk AND (NOT bBOk) THEN
            nFirstOut := 2;                       // 仅 B 无效则首出记 B
        END_IF
        uFault := 16#0002_0693;                   // 故障级：双表信号无效，禁开门
        _eState := E_DL_LlxcPhase.eBlocked;       // 本拍行为：拦截
    ELSIF bCfgOk AND bCrossOk AND bPressInPlace THEN
        _eState := E_DL_LlxcPhase.ePermit;        // 双表一致 AND 压力到位 → 许可
    ELSIF (NOT bCrossOk) THEN
        IF fbDevWin.bHighOut THEN
            nFirstOut := 1;                       // 表 A 偏高为首出
        ELSIF fbDevWin.bLowOut THEN
            nFirstOut := 2;                       // 表 B 偏高（偏差为负）为首出
        END_IF
        bCrossFault := TRUE;                      // 交叉偏差越窗，锁存
        uInfo := 16#0002_06A3;                    // 信息级：偏差越窗记录
        _eState := E_DL_LlxcPhase.eBlocked;
    ELSE
        _eState := E_DL_LlxcPhase.eBlocked;       // 其余情况一律拦截（压力未到位）
    END_IF

E_DL_LlxcPhase.ePermit :
    bDoorPermit := TRUE;                          // 许可保持（逐拍重算条件）
    IF (NOT bAOk) OR (NOT bBOk) OR (NOT bCrossOk) OR (NOT bPressInPlace) OR (NOT bEnable) THEN
        _eState := E_DL_LlxcPhase.eBlocked;       // 任一条件丢失立即撤销许可（可到达的撤销路径）
    END_IF
    IF rtrReset.Q THEN
        bCrossFault := FALSE;                     // 复位沿清交叉故障锁存
        uInfo := 16#0000;                         // 信息码同步清除
        _eState := E_DL_LlxcPhase.eCheck;
    END_IF

E_DL_LlxcPhase.eBlocked :
    bDoorPermit := FALSE;                         // 拦截态许可强制 FALSE（安全侧）
    IF bAOk AND bBOk AND bCrossOk AND bPressInPlace AND (uFault = 16#0000) THEN
        _eState := E_DL_LlxcPhase.ePermit;        // 解除路径：条件恢复即可达许可（FB33-2 可达性）
    END_IF
    IF rtrReset.Q THEN
        IF bAOk AND bBOk THEN
            uFault := 16#0000;                    // 表恢复后复位沿解锁
        END_IF
        bCrossFault := FALSE;                     // 交叉故障锁存清除
        uInfo := 16#0000;                         // 信息码清除
    END_IF

E_DL_LlxcPhase.eFault :
    bDoorPermit := FALSE;                         // 故障态禁开门
    IF uFault = 16#0000 THEN
        _eState := E_DL_LlxcPhase.eCheck;         // 组态修正后回校验
    END_IF

ELSE
    _eState := E_DL_LlxcPhase.eFault;             // 非法状态拦截
    bDoorPermit := FALSE;                         // 安全侧禁开门
    uFault := 16#0002_0683;                       // 故障级：相 ID 越界（枚举兜底路径）
END_CASE
IF NOT bEnable THEN
    bDoorPermit := FALSE;                         // 失能最高优先禁开门
    _eState := E_DL_LlxcPhase.eIdle;              // 回空闲
END_IF

(* === 段 5 · 输出映射（安全三行同向）=== *)
IF NOT (bAOk AND bBOk) THEN
    bDoorPermit := FALSE;                         // 双保险：任一表无效最终仍禁开门
END_IF
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
