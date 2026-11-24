(*
  FB_DL_AndonRespTimeReport  —  安灯呼叫→应答→解除三段计时与四级响应分档 / Andon call-ack-clear timing with four response buckets
  分类 Category : DL_Process
  码位 Code     : 16#06_0_89
  版本 Version  : 1.0.0
  溯源 Source   : OMAC PackML + ISA-18.2 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 呼叫→应答→解除三段各自计时，每段计时器在进入相时复位，防上一轮残值续累；
                  2) 响应时长按四级门限分档，附各档累计计数与应答样本分母；
                  3) 呼叫未应答即解除时不计入应答时长统计（应答样本分母单独计数，口径显式）。
  边界 Boundary : ① 三段计时器各自在进入相时复位（tCallDur / tAckDur / tClearDur 置 0）；
                  ② 未应答即解除不计入应答时长统计（nAckSamples 为分母，显式输出）；
                  ③ 分档边界两条验收向量见下方「验收向量」段（正好整除 / 上限+1）；
                  ④ 结论三行同向：当前段计时 → 分档等级 → 活动标志。
  依赖 Depends  : None

  验收向量（分档边界，TIME 门限 5s / 15s / 30s）:
    V1 正好整除：应答时长 = 5.000 s → 等级 1（取 <= 门限，闭区间）；
    V2 上限 +1  ：应答时长 = 5.001 s → 等级 2；
    V3 上限 +1  ：应答时长 = 30.001 s → 等级 4；
    V4 未应答解除：tCallDur 计入、nAckSamples 不增、tAckDur 保持 0。
  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_0689 故障级：分档门限非严格递增（须 L1 < L2 < L3）
    16#0002_0699 故障级：相 ID 越界（枚举兜底路径）
    16#0002_06A9 信息级：未应答即解除，本次不计入应答时长统计（不置 bError）
*)

TYPE E_DL_AndonPhase :
(
    eIdle     := 0,   // 空闲 / Idle
    eCalling  := 10,  // 呼叫中（等应答）/ Calling, waiting for ack
    eAcked    := 20,  // 已应答（等解除）/ Acknowledged, waiting for clear
    eCleared  := 30,  // 已解除（本轮结束）/ Cleared, round finished
    eFault    := 90   // 故障锁定 / Fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_AndonRespTimeReport
VAR_INPUT
    bEnable      : BOOL;                          // 总使能，FALSE 回空闲 / Master enable
    bReset       : BOOL;                          // 复位，上升沿清故障与台账 / Reset, clears fault and ledger
    bCall        : BOOL;                          // 安灯呼叫信号（电平）/ Andon call signal, level
    bAck         : BOOL;                          // 应答信号（电平）/ Acknowledgement signal
    bClear       : BOOL;                          // 呼叫解除信号（电平）/ Call clear signal
    tCycle       : TIME := T#10MS;                // 任务周期 [ms]，计时累加步长 / Task cycle [ms]
    atLvlLimit   : ARRAY[1..3] OF TIME;           // 四级分档门限 [ms]，须严格递增 / Four-level bucket limits [ms]
    tAckTimeout  : TIME := T#120S;                // 应答超时 [ms]，0 = 不监控 / Ack timeout [ms]
END_VAR
VAR_OUTPUT
    tCallDur     : TIME;                          // 本轮呼叫时长 [ms]（含未应答轮）/ Current call duration [ms]
    tAckDur      : TIME;                          // 本轮应答时长 [ms] / Current response duration [ms]
    tClearDur    : TIME;                          // 本轮解除时长 [ms] / Current clear duration [ms]
    tRespAvg     : TIME;                          // 应答时长累计 [ms]（分母见 nAckSamples）/ Response time total [ms]
    nAckSamples  : INT;                           // 应答样本数 [次]（统计分母，显式）/ Acked sample count, explicit denominator
    nLevel       : INT;                           // 本轮响应分档 1~4，0 = 无结论 / Response bucket 1..4, 0 = none
    anLvlCount   : ARRAY[1..4] OF INT;            // 各档累计次数 [次] / Per-level counters
    bActive      : BOOL;                          // 呼叫活动标志 / Call active flag
    bAckTimeout  : BOOL;                          // 应答超时标志（保持型）/ Ack timeout, held
    bError       : BOOL;                          // 故障标志，与故障级码配对 / Fault flag paired with fault codes
    uErrorId     : UDINT;                         // 事件码，0 = 无事件 / Event code, 0 = none
    eStateOut    : E_DL_AndonPhase;               // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState      : E_DL_AndonPhase := E_DL_AndonPhase.eIdle;  // 内部状态 / Internal state
    rtrReset     : R_TRIG;                        // 复位沿 / Reset edge
    tonAckTo     : TON;                           // 应答超时计时（无条件刷新）/ Ack timeout timer
    bCfgOk       : BOOL;                          // 门限组态合法 / Bucket limits valid
    bAckCounted  : BOOL;                          // 本轮已计应答样本 / Ack counted this round
    nI           : INT;                           // 台账循环下标 / Ledger loop index
    nLvlBuf      : INT;                           // 分档暂存 / Bucket buffer
    uFault       : UDINT;                         // 锁存故障码 / Latched fault code
    uInfo        : UDINT;                         // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_AND_LVLMAX : INT := 4;                     // 分档总数 [档] / Bucket count
    DL_AND_CNTMAX : INT := 32000;                 // 台账计数上限 [次]，防 INT 溢出 / Ledger counter ceiling
END_VAR

(* === 段 0 · 实例刷新（无条件周期调用）=== *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿
tonAckTo(IN := (_eState = E_DL_AndonPhase.eCalling), PT := tAckTimeout);   // 应答超时计时，无条件刷新

(* === 段 1 · 组态闸：分档门限严格递增 === *)
bCfgOk := (atLvlLimit[1] > T#0MS) AND (atLvlLimit[2] > atLvlLimit[1])
          AND (atLvlLimit[3] > atLvlLimit[2]);   // 严格递增，倒置即组态报码
IF NOT bCfgOk THEN
    uFault := 16#0002_0689;                       // 故障级：分档门限非法
END_IF
IF rtrReset.Q THEN
    uFault := 16#0000;                            // 复位沿清锁存
    bAckTimeout := FALSE;                         // 超时标志同步复位
    FOR nI := 1 TO DL_AND_LVLMAX DO
        anLvlCount[nI] := 0;                      // 台账清零（复位口径显式）
    END_FOR
    nAckSamples := 0;                             // 应答样本分母清零
    tRespAvg := T#0MS;                            // 应答累计清零
END_IF

(* === 段 2 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_AndonPhase.eIdle :
    bActive := FALSE;                             // 空闲无活动呼叫
    nLevel := 0;                                  // 分档无结论
    tCallDur := T#0MS;                            // 呼叫计时复位（进入新轮前清零）
    tAckDur := T#0MS;                             // 应答计时复位
    tClearDur := T#0MS;                           // 解除计时复位
    bAckCounted := FALSE;                         // 本轮未计样本
    uInfo := 16#0000;                             // 信息码清零
    IF uFault <> 16#0000 THEN
        _eState := E_DL_AndonPhase.eFault;        // 故障优先
    ELSIF bEnable AND bCall THEN
        tCallDur := T#0MS;                        // 进入呼叫相：计时器复位（防残值续累）
        bActive := TRUE;                          // 活动标志置位
        _eState := E_DL_AndonPhase.eCalling;
    END_IF

E_DL_AndonPhase.eCalling :
    bActive := TRUE;                              // 呼叫活动
    tCallDur := tCallDur + tCycle;                // 呼叫时长累加
    IF bAck THEN
        tCallDur := tCallDur;                     // 呼叫时长定格（本拍不再累加）
        tAckDur := T#0MS;                         // 进入应答相：应答计时器复位
        _eState := E_DL_AndonPhase.eAcked;        // 本拍行为：转已应答相
    ELSIF tonAckTo.Q THEN
        bAckTimeout := TRUE;                      // 置位型：应答超时（段尾不清零）
    ELSIF NOT bCall THEN
        uInfo := 16#0002_06A9;                    // 信息级：未应答即解除，不计入应答统计
        _eState := E_DL_AndonPhase.eCleared;      // 直接转解除相（分母口径不污染）
    END_IF

E_DL_AndonPhase.eAcked :
    bActive := TRUE;                              // 仍在处理中
    tAckDur := tAckDur + tCycle;                  // 应答时长累加
    IF NOT bAckCounted THEN
        tRespAvg := tRespAvg + tAckDur;           // 应答时长累计入台账
        nAckSamples := nAckSamples + 1;           // 分母 +1（显式口径）
        bAckCounted := TRUE;                      // 本轮已计样本，防重复累加
    END_IF
    IF (NOT bCall) OR bClear THEN
        tClearDur := T#0MS;                       // 进入解除相：解除计时器复位
        _eState := E_DL_AndonPhase.eCleared;      // 转解除相
    END_IF

E_DL_AndonPhase.eCleared :
    tClearDur := tClearDur + tCycle;              // 解除时长累加
    IF NOT bCall THEN
        bActive := FALSE;                         // 呼叫已撤销：活动标志落 0（三行同向）
        IF tAckDur <= atLvlLimit[1] THEN
            nLvlBuf := 1;                         // 分档 1：应答 <= L1（闭区间，正好整除落在本级）
        ELSIF tAckDur <= atLvlLimit[2] THEN
            nLvlBuf := 2;                         // 分档 2：L1 < 应答 <= L2
        ELSIF tAckDur <= atLvlLimit[3] THEN
            nLvlBuf := 3;                         // 分档 3：L2 < 应答 <= L3
        ELSE
            nLvlBuf := DL_AND_LVLMAX;             // 分档 4：应答 > L3（上限 +1 落最高档）
        END_IF
        nLevel := nLvlBuf;                        // 分档结果输出
        IF (nLvlBuf >= 1) AND (nLvlBuf <= DL_AND_LVLMAX) THEN
            IF anLvlCount[nLvlBuf] < DL_AND_CNTMAX THEN
                anLvlCount[nLvlBuf] := anLvlCount[nLvlBuf] + 1;   // 台账计数，饱和防溢出
            END_IF
        END_IF
        _eState := E_DL_AndonPhase.eIdle;         // 本轮结束回空闲（下轮计时器在空闲相复位）
    END_IF

E_DL_AndonPhase.eFault :
    bActive := FALSE;                             // 故障态无活动
    nLevel := 0;                                  // 分档无结论
    IF uFault = 16#0000 THEN
        _eState := E_DL_AndonPhase.eIdle;         // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_AndonPhase.eFault;            // 非法状态拦截
    uFault := 16#0002_0699;                       // 故障级：相 ID 越界（枚举兜底路径）
    nLevel := 0;                                  // 安全侧无分档
END_CASE
IF NOT bEnable THEN
    _eState := E_DL_AndonPhase.eIdle;             // 失能最高优先回空闲
    bActive := FALSE;                             // 活动标志落 0
    nLevel := 0;                                  // 分档无结论
END_IF

(* === 段 3 · 输出映射（三行同向：段计时 → 分档 → 活动标志）=== *)
IF bCall AND (NOT bActive) THEN
    bActive := TRUE;                              // 呼叫电平与活动标志对齐（防状态机滞后一拍漏报）
END_IF
IF NOT bCall AND (_eState <> E_DL_AndonPhase.eCleared) THEN
    bActive := FALSE;                             // 呼叫撤销且不在解除相：活动标志落 0
END_IF
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
