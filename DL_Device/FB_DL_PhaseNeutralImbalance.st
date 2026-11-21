(*
  FB_DL_PhaseNeutralImbalance  —  三相不平衡度与中性线电流判据 / Three-phase imbalance and neutral current criterion
  分类 Category : DL_Device
  码位 Code     : 16#03_2_03
  版本 Version  : 1.0.0
  溯源 Source   : NAMUR NE107 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 三相电压/电流任一为 0 或 NaN 时改判「缺相」，不计算不平衡率（除零前置）；
                  2) 不平衡率按「最大相偏差 / 三相均值 × 100%」定义（见下方定义段），分警告/跳闸两级；
                  3) 中性线电流超限与不平衡分级各自独立码值（归因唯一，不合并）。
  边界 Boundary : ① 三相任一为 0 或 NaN 改判缺相（除零前置），不出不平衡率；
                  ② 不平衡率定义在头注释写死（最大相偏差 / 均值）；
                  ③ 中性线超限与不平衡分级各自独立码值；
                  ④ 输出三行同向：不平衡率 → 分级标志 → 缺相标志。
  依赖 Depends  : None

  不平衡率定义（写死，不随组态变化）:
    fImbalPct = MAX(|Vi − Vavg|) / Vavg × 100%，Vi 为三线电压，Vavg 为三线均值 [V]。
    电流不平衡同式，本件对电压与电流分别计算后取较大者作为综合不平衡率。
  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_0303 故障级：不平衡跳闸级越限（保持型，需 bReset）
    16#0002_0313 故障级：中性线电流越限（独立码，需 bReset）
    16#0002_0323 信息级：缺相识别（不置 bError，由上层停机逻辑处理）
*)

TYPE E_DL_PniPhase :
(
    eIdle    := 0,   // 空闲 / Idle
    eMeasure := 10,  // 测量判定 / Measurement
    eWarn    := 20,  // 不平衡警告 / Imbalance warning
    eTrip    := 30,  // 不平衡跳闸 / Imbalance trip
    eLoss    := 40,  // 缺相 / Phase loss
    eFault   := 90   // 故障锁定 / Fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_PhaseNeutralImbalance
VAR_INPUT
    bEnable      : BOOL;                          // 总使能，FALSE 回空闲 / Master enable
    bReset       : BOOL;                          // 复位，上升沿清跳闸与中性线锁存 / Reset
    afVoltV      : ARRAY[1..3] OF REAL;           // 三线电压 [V]，域 0~600 / Line voltages [V]
    afCurrA      : ARRAY[1..3] OF REAL;           // 三线电流 [A]，域 0~2000 / Line currents [A]
    fNeutralA    : REAL;                          // 中性线电流 [A]，域 0~2000 / Neutral current [A]
    fImbalWarnPct: REAL := 10.0;                  // 不平衡警告门限 [%]，域 > 0 / Imbalance warning limit [%]
    fImbalTripPct: REAL := 20.0;                  // 不平衡跳闸门限 [%]，须 > 警告门限 / Imbalance trip limit [%]
    fNeutralMaxA : REAL := 30.0;                  // 中性线电流上限 [A]，域 > 0 / Neutral current limit [A]
    fEps         : REAL := 1.0E-6;                // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    fImbalPct    : REAL;                          // 综合不平衡率 [%] / Combined imbalance [%]
    nLossPhase   : INT;                           // 缺相线号 1~3，0 = 无缺相 / Lost phase 1..3, 0 = none
    bPhaseLoss   : BOOL;                          // 缺相标志 / Phase loss flag
    bImbalWarn   : BOOL;                          // 不平衡警告（保持型）/ Imbalance warning, held
    bImbalTrip   : BOOL;                          // 不平衡跳闸（保持型）/ Imbalance trip, held
    bNeutralOver : BOOL;                          // 中性线超限（保持型）/ Neutral over-current, held
    bError       : BOOL;                          // 故障标志，与故障级码配对 / Fault flag paired with fault codes
    uErrorId     : UDINT;                         // 事件码，0 = 无事件 / Event code, 0 = none
    eStateOut    : E_DL_PniPhase;                 // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState      : E_DL_PniPhase := E_DL_PniPhase.eIdle;  // 内部状态 / Internal state
    rtrReset     : R_TRIG;                        // 复位沿 / Reset edge
    bCfgOk       : BOOL;                          // 组态合法标志 / Configuration valid
    bPhaseOk     : BOOL;                          // 三相全部有效标志 / All three phases valid
    nI           : INT;                           // 相循环下标 / Phase loop index
    fVAvg        : REAL;                          // 电压三相均值 [V] / Mean line voltage [V]
    fIAvg        : REAL;                          // 电流三相均值 [A] / Mean line current [A]
    fVMaxDev     : REAL;                          // 电压最大相偏差 [V] / Maximum voltage deviation [V]
    fIMaxDev     : REAL;                          // 电流最大相偏差 [A] / Maximum current deviation [A]
    fVImb        : REAL;                          // 电压不平衡率 [%] / Voltage imbalance [%]
    fIImb        : REAL;                          // 电流不平衡率 [%] / Current imbalance [%]
    fDevBuf      : REAL;                          // 单相偏差暂存 [V] 或 [A] / Per-phase deviation buffer
    uFault       : UDINT;                         // 锁存故障码 / Latched fault code
    uInfo        : UDINT;                         // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_PNI_VMAX  : REAL := 600.0;                 // 电压物理域上限 [V] / Voltage domain high [V]
    DL_PNI_IMAX  : REAL := 2000.0;                // 电流物理域上限 [A] / Current domain high [A]
    DL_PNI_PCTMAX: REAL := 100.0;                 // 百分比满量程 [%] / Percentage full scale [%]
END_VAR

(* === 段 0 · 实例刷新（无条件周期调用）=== *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸与三相有效域（除零前置）=== *)
bCfgOk := (fImbalWarnPct > fEps) AND (fImbalTripPct > fImbalWarnPct + fEps)
          AND (fNeutralMaxA > fEps) AND (fImbalWarnPct = fImbalWarnPct)
          AND (fImbalTripPct = fImbalTripPct) AND (fNeutralMaxA = fNeutralMaxA);   // 含 NaN 自反
bPhaseOk := TRUE;                                 // 假定三相有效，逐相否决
nLossPhase := 0;                                  // 缺相线号清零
FOR nI := 1 TO 3 DO
    IF (afVoltV[nI] <> afVoltV[nI]) OR (afCurrA[nI] <> afCurrA[nI])                // NaN 自反判据
       OR (afVoltV[nI] <= fEps) OR (afCurrA[nI] <= fEps)                            // 0 值判缺相
       OR (afVoltV[nI] > DL_PNI_VMAX) OR (afCurrA[nI] > DL_PNI_IMAX) THEN           // 域外
        bPhaseOk := FALSE;                         // 该相无效：整组不出不平衡率
        IF nLossPhase = 0 THEN
            nLossPhase := nI;                      // 首出缺相线号（物理线号连续编址）
        END_IF
    END_IF
END_FOR
bPhaseLoss := NOT bPhaseOk;                        // 缺相标志
IF rtrReset.Q THEN
    uFault := 16#0000;                             // 复位沿清锁存（两个故障码共用同一复位路径）
    bImbalTrip := FALSE;                           // 跳闸标志复位
    bNeutralOver := FALSE;                         // 中性线超限复位
    bImbalWarn := FALSE;                           // 警告标志复位
END_IF
uInfo := 16#0000;                                  // 信息码每拍清零

(* === 段 2 · 不平衡率计算（仅三相全有效时执行）=== *)
IF bPhaseOk THEN
    fVAvg := (afVoltV[1] + afVoltV[2] + afVoltV[3]) / 3.0;    // 三相电压均值，分母为常量 3
    fIAvg := (afCurrA[1] + afCurrA[2] + afCurrA[3]) / 3.0;    // 三相电流均值
    fVMaxDev := 0.0;                                          // 电压最大偏差清零
    fIMaxDev := 0.0;                                          // 电流最大偏差清零
    FOR nI := 1 TO 3 DO
        fDevBuf := ABS(afVoltV[nI] - fVAvg);                  // 单相电压偏差绝对值
        IF fDevBuf > fVMaxDev THEN
            fVMaxDev := fDevBuf;                              // 记录最大电压偏差
        END_IF
        fDevBuf := ABS(afCurrA[nI] - fIAvg);                  // 单相电流偏差绝对值
        IF fDevBuf > fIMaxDev THEN
            fIMaxDev := fDevBuf;                              // 记录最大电流偏差
        END_IF
    END_FOR
    IF fVAvg > fEps THEN                                       // 均值分母防除零
        fVImb := fVMaxDev / fVAvg * DL_PNI_PCTMAX;             // 电压不平衡率 [%]
    ELSE
        fVImb := 0.0;
    END_IF
    IF fIAvg > fEps THEN                                       // 均值分母防除零
        fIImb := fIMaxDev / fIAvg * DL_PNI_PCTMAX;             // 电流不平衡率 [%]
    ELSE
        fIImb := 0.0;
    END_IF
    IF fVImb >= fIImb THEN
        fImbalPct := fVImb;                                    // 综合不平衡率取较大者
    ELSE
        fImbalPct := fIImb;
    END_IF
ELSE
    fImbalPct := 0.0;                                          // 缺相：不出不平衡率（防除零）
    uInfo := 16#0002_0323;                                     // 信息级：缺相识别
END_IF

(* === 段 3 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_PniPhase.eIdle :
    IF uFault <> 16#0000 THEN
        _eState := E_DL_PniPhase.eFault;           // 故障优先
    ELSIF bEnable AND (NOT bCfgOk) THEN
        _eState := E_DL_PniPhase.eFault;           // 组态非法入故障态
        uFault := 16#0002_0303;                    // 故障级：组态非法按跳闸级记录
    ELSIF bEnable AND bPhaseLoss THEN
        _eState := E_DL_PniPhase.eLoss;            // 缺相优先于不平衡判定
    ELSIF bEnable THEN
        _eState := E_DL_PniPhase.eMeasure;         // 进入测量相
    END_IF

E_DL_PniPhase.eMeasure :
    IF bPhaseLoss THEN
        _eState := E_DL_PniPhase.eLoss;            // 缺相：转缺相相
    ELSIF bCfgOk AND (fImbalPct >= fImbalTripPct) THEN
        bImbalTrip := TRUE;                        // 置位型：跳闸（段尾不清零）
        uFault := 16#0002_0303;                    // 故障级：不平衡跳闸
        _eState := E_DL_PniPhase.eTrip;
    ELSIF bCfgOk AND (fImbalPct >= fImbalWarnPct) THEN
        bImbalWarn := TRUE;                        // 置位型：警告
        _eState := E_DL_PniPhase.eWarn;
    ELSE
        bImbalWarn := FALSE;                       // 回到门限下：警告解除（可到达的解除路径）
        bImbalTrip := FALSE;                       // 跳闸未触发即清（非锁存态）
    END_IF

E_DL_PniPhase.eWarn :
    bImbalWarn := TRUE;                            // 警告保持
    IF fImbalPct >= fImbalTripPct THEN
        bImbalTrip := TRUE;                        // 升级跳闸
        uFault := 16#0002_0303;                    // 故障级码
        _eState := E_DL_PniPhase.eTrip;
    ELSIF fImbalPct < (fImbalWarnPct - 1.0) THEN
        bImbalWarn := FALSE;                       // 降到门限 -1% 以下解除（迟滞）
        _eState := E_DL_PniPhase.eMeasure;
    END_IF

E_DL_PniPhase.eTrip :
    bImbalTrip := TRUE;                            // 跳闸保持，需人工复位
    IF rtrReset.Q THEN
        uFault := 16#0000;                         // 复位沿解锁
        bImbalTrip := FALSE;                       // 跳闸解除
        _eState := E_DL_PniPhase.eMeasure;
    END_IF

E_DL_PniPhase.eLoss :
    IF NOT bPhaseLoss THEN
        uInfo := 16#0000;                          // 缺相恢复：信息码清除
        _eState := E_DL_PniPhase.eMeasure;         // 回测量相（可到达的解除路径）
    END_IF

E_DL_PniPhase.eFault :
    bImbalTrip := FALSE;                           // 故障态不保留跳闸位（避免双码歧义）
    IF uFault = 16#0000 THEN
        _eState := E_DL_PniPhase.eIdle;            // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_PniPhase.eFault;               // 非法状态拦截
    uFault := 16#0002_0303;                        // 故障级：相 ID 越界
    fImbalPct := 0.0;                              // 安全侧不平衡率归 0
END_CASE

(* === 段 4 · 中性线独立判据（与不平衡分级各自独立码值）=== *)
IF (fNeutralA = fNeutralA) AND (fNeutralA > fNeutralMaxA) AND (fNeutralA <= DL_PNI_IMAX) THEN
    bNeutralOver := TRUE;                          // 置位型：中性线超限
    uFault := 16#0002_0313;                        // 故障级：中性线超限（独立码）
ELSIF (fNeutralA = fNeutralA) AND (fNeutralA <= (fNeutralMaxA - 1.0)) THEN
    IF bNeutralOver AND (uFault = 16#0002_0313) THEN
        uFault := 16#0000;                         // 中性线回落且无其它故障：清码
    END_IF
    bNeutralOver := FALSE;                         // 超限解除（迟滞 1 A，可到达的解除路径）
END_IF
IF (fNeutralA <> fNeutralA) THEN
    uInfo := 16#0002_0323;                         // 中性线值非有限：信息级提示
END_IF
IF NOT bEnable THEN
    _eState := E_DL_PniPhase.eIdle;                // 失能最高优先回空闲
    bImbalTrip := FALSE;                           // 跳闸位复位
    bImbalWarn := FALSE;                           // 警告位复位
    bNeutralOver := FALSE;                         // 中性线超限复位
END_IF

(* === 段 5 · 输出映射（三行同向：不平衡率 → 分级 → 缺相）=== *)
IF bPhaseLoss THEN
    bImbalPct := 0.0;                              // 缺相期间不平衡率输出 0（不出结论）
END_IF
bError := (uFault <> 16#0000);                     // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                            // 故障级优先上报
ELSE
    uErrorId := uInfo;                             // 否则上报信息级码
END_IF
eStateOut := _eState;                              // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
