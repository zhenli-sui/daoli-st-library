(*
  FB_DL_OcvGradingBin  —  OCV 电压+内阻双判据分档与落料位决策 / OCV dual-criteria grading and bin decision
  分类 Category : DL_Process
  码位 Code     : 16#06_0_81
  版本 Version  : 1.0.0
  溯源 Source   : LGF Comparator 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 电压 + 内阻双判据同时落窗才分档，档位带由组态表给定；
                  2) 档位阈值单调递增校验，倒置即冻结并报码（不静默容错）；
                  3) 电压或内阻为 NaN 时判「不可分档」，绝不落入最低档；目标档满仓时走避让档，无可用料仓则停线。
  边界 Boundary : ① 档位阈值单调递增校验（倒置即冻结 + 报码）；
                  ② 电压/内阻任一 NaN 时判「不可分档」而非落最低档（x <> x 自反判据）；
                  ③ 满仓档位无可用料仓时停线（bLineStop），不静默落最低档；
                  ④ 电压/内阻先过物理域闸，域外按不可分档处理。
  依赖 Depends  : None

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_0681 故障级：档位阈值倒置或档数越界（组态闸锁存，需 bReset 清除）
    16#0002_0691 故障级：档位下标越界（枚举兜底路径）
    16#0002_06A1 信息级：满仓避让已生效 / 无可用料仓（不置 bError）
*)

TYPE E_DL_OcvGradePhase :
(
    eIdle       := 0,   // 空闲待料 / Idle awaiting cell
    eGrading    := 10,  // 双判据分档中 / Grading in progress
    eGraded     := 20,  // 已落档 / Graded
    eNoBin      := 30,  // 满仓避让失败 / Bin avoidance failed
    eUngradable := 40,  // 不可分档 / Ungradable cell
    eFault      := 90   // 组态故障锁定 / Configuration fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_OcvGradingBin
VAR_INPUT
    bEnable    : BOOL;                            // 总使能，FALSE 回空闲 / Master enable
    bStart     : BOOL;                            // 分档触发，上升沿取一次测量 / Trigger, rising edge latches one measurement
    bReset     : BOOL;                            // 复位，上升沿清锁存故障 / Reset, clears the latched fault
    fVoltV     : REAL;                            // 电芯开路电压 [V]，域 0.5~5.0 / Cell open-circuit voltage [V]
    fIrMohm    : REAL;                            // 电芯内阻 [mOhm]，域 0.1~500.0 / Cell internal resistance [mOhm]
    nBinCount  : INT := 1;                        // 档位总数 [档]，域 1~8 / Bin count, 1..8
    afVoltLo   : ARRAY[1..8] OF REAL;             // 各档电压下限 [V] / Per-bin voltage lower limit [V]
    afVoltHi   : ARRAY[1..8] OF REAL;             // 各档电压上限 [V] / Per-bin voltage upper limit [V]
    afIrLo     : ARRAY[1..8] OF REAL;             // 各档内阻下限 [mOhm] / Per-bin resistance lower limit [mOhm]
    afIrHi     : ARRAY[1..8] OF REAL;             // 各档内阻上限 [mOhm] / Per-bin resistance upper limit [mOhm]
    abBinFull  : ARRAY[1..8] OF BOOL;             // 各档料仓满标志 [开关] / Per-bin full flag
    nFallbackBin : INT := 0;                      // 避让档号，0 = 无避让档 / Fallback bin, 0 = none
    fEps       : REAL := 1.0E-6;                  // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    nBinOut    : INT;                             // 落料档号 1..8，0 = 不分档 / Target bin 1..8, 0 = none
    bGraded    : BOOL;                            // 本拍完成分档（单拍脉冲）/ Graded this scan, single pulse
    bUngradable: BOOL;                            // 不可分档标志（保持型）/ Ungradable flag, held
    bLineStop  : BOOL;                            // 停线请求（无可用料仓）/ Line stop request
    bConfigFault : BOOL;                          // 组态故障标志 / Configuration fault flag
    bError     : BOOL;                            // 故障标志，与故障级码配对 / Fault flag paired with fault codes
    uErrorId   : UDINT;                           // 事件码，0 = 无事件 / Event code, 0 = none
    eStateOut  : E_DL_OcvGradePhase;              // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState    : E_DL_OcvGradePhase := E_DL_OcvGradePhase.eIdle;  // 内部状态 / Internal state
    rtrStart   : R_TRIG;                          // 分档触发沿 / Grading trigger edge
    rtrReset   : R_TRIG;                          // 复位沿 / Reset edge
    bCfgOk     : BOOL;                            // 组态合法标志 / Configuration valid flag
    bMonoOk    : BOOL;                            // 单调递增校验标志 / Monotonicity valid flag
    bFinite    : BOOL;                            // 输入有限性标志 / Input finiteness flag
    bDomainOk  : BOOL;                            // 输入物理域标志 / Input physical domain flag
    nN         : INT;                             // 生效档数（钳位后）/ Effective bin count after clamping
    nI         : INT;                             // 档位循环下标 / Bin loop index
    nHit       : INT;                             // 命中档号暂存，0 = 未命中 / Hit bin, 0 = none
    nUse       : INT;                             // 最终使用档号 / Finally used bin
    fVoltLat   : REAL;                            // 触发当拍锁存的电压 [V] / Latched voltage [V]
    fIrLat     : REAL;                            // 触发当拍锁存的内阻 [mOhm] / Latched resistance [mOhm]
    bLatValid  : BOOL;                            // 锁存有效（触发后保持）/ Latched sample valid
    uFault     : UDINT;                           // 锁存故障码 / Latched fault code
    uInfo      : UDINT;                           // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_OCV_BINMAX  : INT := 8;                    // 档位数组上界 [档] / Bin array upper bound
    DL_OCV_VMIN    : REAL := 0.5;                 // 电压物理域下限 [V] / Voltage domain low [V]
    DL_OCV_VMAX    : REAL := 5.0;                 // 电压物理域上限 [V] / Voltage domain high [V]
    DL_OCV_IRMIN   : REAL := 0.1;                 // 内阻物理域下限 [mOhm] / Resistance domain low [mOhm]
    DL_OCV_IRMAX   : REAL := 500.0;               // 内阻物理域上限 [mOhm] / Resistance domain high [mOhm]
END_VAR

(* === 段 0 · 实例刷新（无条件周期调用）=== *)
rtrStart(CLK := bStart);                          // 每拍刷新分档触发沿
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸：档数域 + 阈值单调递增（倒置即锁存报码）=== *)
nN := nBinCount;                                  // 档数取用前先钳位，防数组越界
IF nN < 1 THEN
    nN := 1;
END_IF
IF nN > DL_OCV_BINMAX THEN
    nN := DL_OCV_BINMAX;
END_IF
bCfgOk := (nBinCount >= 1) AND (nBinCount <= DL_OCV_BINMAX);   // 档数越界即组态非法
bMonoOk := TRUE;                                  // 单调性先置真，逐档否决
FOR nI := 1 TO DL_OCV_BINMAX DO
    IF nI <= nN THEN
        bMonoOk := bMonoOk AND (afVoltHi[nI] > afVoltLo[nI])       // 单档电压上下限配比
                   AND (afIrHi[nI] >= afIrLo[nI]);                 // 单档内阻上下限配比
        IF nI > 1 THEN
            bMonoOk := bMonoOk AND (afVoltHi[nI] > afVoltHi[nI - 1]);   // 电压上沿严格单调递增
        END_IF
    END_IF
END_FOR
IF (NOT bCfgOk) OR (NOT bMonoOk) THEN
    uFault := 16#0002_0681;                       // 故障级：阈值倒置或档数越界，组态闸锁存
END_IF
IF rtrReset.Q AND bCfgOk AND bMonoOk THEN
    uFault := 16#0000;                            // 组态修正后复位沿解锁（故障码复位路径可达）
END_IF

(* === 段 2 · 输入域闸：NaN 用自反判据，域外按不可分档处理 === *)
bFinite := (fVoltV = fVoltV) AND (fIrMohm = fIrMohm)               // x <> x 自反判 NaN
           AND (ABS(fVoltV) < 1.0E30) AND (ABS(fIrMohm) < 1.0E30);  // 上限兜底判 Inf
bDomainOk := (fVoltV >= DL_OCV_VMIN) AND (fVoltV <= DL_OCV_VMAX)
             AND (fIrMohm >= DL_OCV_IRMIN) AND (fIrMohm <= DL_OCV_IRMAX);
IF rtrStart.Q THEN
    fVoltLat := fVoltV;                           // 触发沿锁存本次测量，分档期间不被刷新
    fIrLat := fIrMohm;                            // 内阻同步锁存
    bLatValid := TRUE;                            // 锁存有效
END_IF

(* === 段 3 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_OcvGradePhase.eIdle :
    nBinOut := 0;                                 // 未分档，档号 0
    bGraded := FALSE;                             // 分档脉冲复位（非置位型标志）
    bUngradable := FALSE;                         // 不可分档标志复位
    bLineStop := FALSE;                           // 停线请求复位
    IF uFault <> 16#0000 THEN
        _eState := E_DL_OcvGradePhase.eFault;     // 组态故障优先
    ELSIF rtrStart.Q THEN
        _eState := E_DL_OcvGradePhase.eGrading;   // 本拍进入分档相
    END_IF

E_DL_OcvGradePhase.eGrading :
    IF (NOT bFinite) OR (NOT bDomainOk) THEN
        bUngradable := TRUE;                      // 本拍行为：不可分档，绝不落最低档
        nBinOut := 0;
        uInfo := 16#0002_06A1;                    // 信息级：不可分档（不置 bError）
        _eState := E_DL_OcvGradePhase.eUngradable;
    ELSE
        nHit := 0;                                // 命中档号先清零
        FOR nI := 1 TO nN DO
            IF (fVoltLat >= afVoltLo[nI]) AND (fVoltLat <= afVoltHi[nI])
               AND (fIrLat >= afIrLo[nI]) AND (fIrLat <= afIrHi[nI]) THEN
                nHit := nI;                       // 双判据同时落窗才命中
                EXIT;
            END_IF
        END_FOR
        IF nHit = 0 THEN
            bUngradable := TRUE;                  // 双判据无交集：不可分档
            nBinOut := 0;
            _eState := E_DL_OcvGradePhase.eUngradable;
        ELSE
            nUse := nHit;                         // 默认落命中档
            IF abBinFull[nHit] THEN
                IF (nFallbackBin >= 1) AND (nFallbackBin <= nN) AND (NOT abBinFull[nFallbackBin]) THEN
                    nUse := nFallbackBin;         // 满仓避让到可用料仓
                    uInfo := 16#0002_06A1;        // 信息级：满仓避让生效
                ELSE
                    nUse := 0;                    // 无可用料仓
                    bLineStop := TRUE;            // 停线，禁止静默落最低档
                    uInfo := 16#0002_06A1;        // 信息级：无可用料仓
                    _eState := E_DL_OcvGradePhase.eNoBin;
                END_IF
            END_IF
            IF nUse >= 1 THEN
                nBinOut := nUse;                  // 落料档号输出
                bGraded := TRUE;                  // 置位型：完成脉冲，段尾不清零
                _eState := E_DL_OcvGradePhase.eGraded;
            END_IF
        END_IF
    END_IF

E_DL_OcvGradePhase.eGraded :
    bLatValid := FALSE;                           // 本拍行为：测量已消费，锁存失效
    _eState := E_DL_OcvGradePhase.eIdle;          // 转出：下一拍回空闲待料

E_DL_OcvGradePhase.eNoBin :
    bLineStop := TRUE;                            // 停线请求保持，直到人工处理
    IF rtrReset.Q THEN
        bLineStop := FALSE;                       // 复位沿解除停线（可到达的解除路径）
        uInfo := 16#0000;                         // 信息码同步清除
        _eState := E_DL_OcvGradePhase.eIdle;
    END_IF

E_DL_OcvGradePhase.eUngradable :
    IF rtrStart.Q THEN
        _eState := E_DL_OcvGradePhase.eGrading;   // 新料触发重新分档
    ELSIF rtrReset.Q THEN
        bUngradable := FALSE;                     // 复位沿清不可分档标志
        _eState := E_DL_OcvGradePhase.eIdle;
    END_IF

E_DL_OcvGradePhase.eFault :
    nBinOut := 0;                                 // 故障态不分档（安全侧）
    IF uFault = 16#0000 THEN
        _eState := E_DL_OcvGradePhase.eIdle;      // 故障已解锁则回空闲
    END_IF

ELSE
    _eState := E_DL_OcvGradePhase.eFault;         // 非法状态拦截
    nBinOut := 0;                                 // 安全侧档号
    uFault := 16#0002_0691;                       // 故障级：档位下标越界（枚举兜底路径）
END_CASE
IF NOT bEnable THEN
    _eState := E_DL_OcvGradePhase.eIdle;          // 失能最高优先回空闲
    nBinOut := 0;                                 // 档号随之为 0
    bLineStop := FALSE;                           // 失能时不停线
END_IF

(* === 段 4 · 输出映射与故障码汇总 === *)
bConfigFault := (uFault <> 16#0000);              // 组态故障标志
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
