(*
  FB_DL_CellVolumeCheck  —  电芯厚度激光测距校验 / Cell thickness laser-range verification
  分类 Category : DL_Device
  码位 Code     : 16#03_2_01
  版本 Version  : 1.0.0
  溯源 Source   : 道莅自研 clean-room，NE43 语义域参照 NAMUR NE43 公开规范
  功能 Function : 1) 激光测距原始值先按 NE43 判有效性（断线/欠量程/超量程），无效值不得参与超差计算；
                  2) 厚度基准（标定常数）为 0 或非正时拒测并置码；
                  3) 超差判定用公差带 + 迟滞，防边界抖动反复分档。
  边界 Boundary : ① 测距原始域先按 NE43 判有效性，无效值不参与超差计算；
                  ② 厚度基准为 0 或未标定时拒测并置码；
                  ③ 超差判定用公差带 + 迟滞（FB_DL_ToleranceWindow），防边界抖动；
                  ④ 输出三行同向：厚度值 → 判定结果 → 拒测标志。
  依赖 Depends  : FB_DL_ToleranceWindow（公差带 + 迟滞判定，每拍无条件调用）；
                  I_DL_AnalogSensor（内联替代：接口无法直接实例化，NE43 判据本件内联实现，仅引用其 E_DL_SignalQuality 枚举）

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_0301 故障级：厚度基准（标定常数）非正或未标定，拒测
    16#0002_0311 故障级：公差参数非法（公差 <= 0 或迟滞 > 公差/2）
    16#0002_0321 信息级：测距原始值 NE43 域外（欠量程/超量程/断线），本拍不判超差
*)

TYPE E_DL_CvcPhase :
(
    eIdle    := 0,   // 空闲 / Idle
    eRange   := 10,  // 测距有效域判定 / Range validity check
    eJudge   := 20,  // 厚度公差判定 / Thickness tolerance judgment
    eReject  := 30,  // 拒测 / Measurement rejected
    eFault   := 90   // 故障锁定 / Fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_CellVolumeCheck
VAR_INPUT
    bEnable      : BOOL;                          // 总使能，FALSE 回空闲 / Master enable
    bSample      : BOOL := TRUE;                  // 采样使能 / Sampling enable
    bReset       : BOOL;                          // 复位，上升沿清故障与拒测 / Reset
    fDistMm      : REAL;                          // 激光测距原始值 [mm]，量程由组态给定 / Raw laser distance [mm]
    fThickRefMm  : REAL := 0.0;                   // 厚度基准（标定常数）[mm]，域 > 0 才有效 / Thickness reference (calibrated) [mm]
    fTolMm       : REAL := 0.05;                  // 厚度公差半带宽 [mm]，域 > 0 / Thickness tolerance half band [mm]
    fHystMm      : REAL := 0.005;                 // 迟滞回差 [mm]，域 0~公差/2 / Hysteresis [mm]
    fRangeLoMm   : REAL := 0.0;                   // 测距量程下限 [mm] / Range low [mm]
    fRangeHiMm   : REAL := 200.0;                 // 测距量程上限 [mm] / Range high [mm]
    fEps         : REAL := 1.0E-6;                // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    fThickMm     : REAL;                          // 实测厚度 [mm]（激光测距换算后的厚度值）/ Measured thickness [mm]
    eQuality     : E_DL_SignalQuality;            // NE43 信号质量分级（引用既有枚举，不重声明）/ NE43 quality grade
    bInTol       : BOOL;                          // 厚度在公差带内 / Thickness within tolerance
    bOverTol     : BOOL;                          // 超差（带迟滞，保持型）/ Out of tolerance, held
    bReject      : BOOL;                          // 拒测标志（保持型）/ Measurement rejected, held
    bError       : BOOL;                          // 故障标志，与故障级码配对 / Fault flag paired with fault codes
    uErrorId     : UDINT;                         // 事件码，0 = 无事件 / Event code, 0 = none
    eStateOut    : E_DL_CvcPhase;                 // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState      : E_DL_CvcPhase := E_DL_CvcPhase.eIdle;  // 内部状态 / Internal state
    rtrReset     : R_TRIG;                        // 复位沿 / Reset edge
    fbTol        : FB_DL_ToleranceWindow;         // 公差带实例（无条件调用）/ Tolerance window instance
    bCfgOk       : BOOL;                          // 公差组态合法 / Tolerance configuration valid
    bRefOk       : BOOL;                          // 厚度基准有效（已标定）/ Reference valid
    bRangeOk     : BOOL;                          // 测距量程有效（NE43 eGood）/ Range valid
    eQualBuf     : E_DL_SignalQuality;            // NE43 质量暂存 / Quality buffer
    fThickBuf    : REAL;                          // 厚度暂存 [mm] / Thickness buffer
    uFault       : UDINT;                         // 锁存故障码 / Latched fault code
    uInfo        : UDINT;                         // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_CVC_RMAX  : REAL := 1000.0;                // 测距量程物理域上限 [mm] / Range domain high [mm]
END_VAR

(* === 段 0 · 实例刷新（无条件周期调用）=== *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · NE43 判据（内联替代 I_DL_AnalogSensor，仅引用其质量枚举）=== *)
IF (fDistMm <> fDistMm) OR (ABS(fDistMm) >= 1.0E30) THEN
    eQualBuf := E_DL_SignalQuality.eOpenLoop;     // NaN/Inf：按回路开路处理
ELSIF fDistMm < fRangeLoMm - 1.0 THEN
    eQualBuf := E_DL_SignalQuality.eWireBreakLow; // 低于量程 1 mm 以上：低侧断线
ELSIF fDistMm < fRangeLoMm THEN
    eQualBuf := E_DL_SignalQuality.eUnderRange;   // 量程下沿内：欠量程
ELSIF fDistMm > fRangeHiMm + 1.0 THEN
    eQualBuf := E_DL_SignalQuality.eWireBreakHigh;// 高于量程 1 mm 以上：高侧断线
ELSIF fDistMm > fRangeHiMm THEN
    eQualBuf := E_DL_SignalQuality.eOverRange;    // 量程上沿内：超量程
ELSE
    eQualBuf := E_DL_SignalQuality.eGood;         // 有效测量域
END_IF
eQuality := eQualBuf;                             // 质量分级输出（单点写入）
bRangeOk := (eQualBuf = E_DL_SignalQuality.eGood);    // 仅 eGood 参与超差计算

(* === 段 2 · 组态闸：厚度基准与公差参数 === *)
bRefOk := (fThickRefMm > fEps) AND (fThickRefMm < DL_CVC_RMAX)
          AND (fThickRefMm = fThickRefMm);        // 基准非正/未标定 → 拒测
bCfgOk := (fTolMm > fEps) AND (fHystMm >= 0.0) AND (fHystMm <= (fTolMm * 0.5))
          AND (fRangeHiMm > fRangeLoMm) AND (fTolMm = fTolMm);         // 含 NaN 自反
IF NOT bRefOk THEN
    uFault := 16#0002_0301;                       // 故障级：基准非正或未标定
END_IF
IF NOT bCfgOk THEN
    uFault := 16#0002_0311;                       // 故障级：公差参数非法
END_IF
IF rtrReset.Q AND bRefOk AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清锁存（复位路径可达）
    bReject := FALSE;                             // 拒测标志同步复位
    bOverTol := FALSE;                            // 超差标志同步复位
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零

(* === 段 3 · 公差带实例（每拍无条件调用，仅有效值参与）=== *)
fbTol(bEnable := bEnable AND bRangeOk AND bRefOk AND bCfgOk,   // 无效值不参与超差计算
      fTarget := fThickRefMm,                     // 目标厚度 = 标定基准
      fActual := fDistMm,                         // 实测测距（本件口径：测距即厚度）
      fTolerance := fTolMm,                       // 公差半带宽
      fHysteresis := fHystMm);                    // 迟滞防抖
IF bRangeOk THEN
    fThickBuf := fDistMm;                         // 有效值：厚度 = 测距
    fThickMm := fThickBuf;                        // 厚度输出
ELSE
    uInfo := 16#0002_0321;                        // 信息级：测距域外，本拍不判超差
END_IF

(* === 段 4 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_CvcPhase.eIdle :
    bInTol := FALSE;                              // 空闲无判定
    IF (uFault = 16#0002_0301) OR (uFault = 16#0002_0311) THEN
        _eState := E_DL_CvcPhase.eFault;          // 组态故障优先
    ELSIF bEnable AND bSample THEN
        _eState := E_DL_CvcPhase.eRange;          // 进入域判定相
    END_IF

E_DL_CvcPhase.eRange :
    IF (NOT bRangeOk) OR (NOT bRefOk) THEN
        bReject := TRUE;                          // 无效/未标定：拒测
        _eState := E_DL_CvcPhase.eReject;
    ELSE
        _eState := E_DL_CvcPhase.eJudge;          // 有效：转公差判定
    END_IF

E_DL_CvcPhase.eJudge :
    bInTol := fbTol.bOk;                          // 公差带内判定（含迟滞）
    IF fbTol.bOk THEN
        bOverTol := FALSE;                        // 恢复合格：解除超差（可到达的解除路径）
    ELSE
        bOverTol := TRUE;                         // 置位型：超差（段尾不清零）
    END_IF
    IF (NOT bEnable) OR rtrReset.Q THEN
        _eState := E_DL_CvcPhase.eIdle;           // 失能/复位回空闲
    ELSIF bSample THEN
        _eState := E_DL_CvcPhase.eRange;          // 连续采样
    END_IF

E_DL_CvcPhase.eReject :
    bReject := TRUE;                              // 拒测标志保持
    bInTol := FALSE;                              // 拒测期不给合格结论
    IF bRangeOk AND bRefOk AND bEnable THEN
        bReject := FALSE;                         // 恢复有效：解除拒测
        _eState := E_DL_CvcPhase.eJudge;
    END_IF

E_DL_CvcPhase.eFault :
    bReject := TRUE;                              // 故障态拒测（安全侧）
    bInTol := FALSE;                              // 不给合格结论
    IF uFault = 16#0000 THEN
        _eState := E_DL_CvcPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_CvcPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_0311;                       // 故障级：相 ID 越界
    bInTol := FALSE;                              // 安全侧不给合格结论
    bReject := TRUE;                              // 安全侧拒测
END_CASE
IF NOT bEnable THEN
    _eState := E_DL_CvcPhase.eIdle;               // 失能最高优先回空闲
    bInTol := FALSE;                              // 失能不给合格结论
END_IF

(* === 段 5 · 输出映射（三行同向：厚度 → 判定 → 拒测）=== *)
IF NOT bRangeOk THEN
    bInTol := FALSE;                              // 无效值绝不判合格
END_IF
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
