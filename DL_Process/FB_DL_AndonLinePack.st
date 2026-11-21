(*
  Component : FB_DL_AndonLinePack
  Category  : DL_Process
  Type      : FB
  Version   : 1.0.0
  CodeSeg   : 16#06_0_40
  Summary   : 包装线安灯分级呼叫与响应报表：三级呼叫仲裁锁存 + 呼叫/应答/解除三段独立计时 + 台账。
              Andon line pack: three-level call arbitration latch, independent call/ack/clear timers, response ledger.
  溯源声明  : 仅借 t2-isa182 安灯呼叫分级与报表口径域，代码 clean-room（T2 借鉴件）
  边界安全  : 三段计时（呼叫→应答→解除）各自独立 TON 实例，禁止共用（按派单要点）；
              仲裁锁存：高级别呼叫可抢占低级别，解除路径可达（对应级别复位指令沿）；
              响应/解除超时为非锁存提示；呼叫/应答计数走沿防电平重复累加；计数防回卷；
              CASE 必带 ELSE 兜底；TON 每拍无条件刷新（段 0）。
  复用      : 复用 FB_DL_AndonCallSystem 仲裁语义 + FB_DL_RuntimeMeter 台账口径（clean-room 自含实现，无实例依赖）
*)

FUNCTION_BLOCK FB_DL_AndonLinePack
VAR_INPUT
    bRun      : BOOL;                   (* 安灯使能 · Enable *)
    bCallL1   : BOOL;                   (* 一级呼叫 [事件]，轻微 · Level 1 call *)
    bCallL2   : BOOL;                   (* 二级呼叫 [事件]，一般 · Level 2 call *)
    bCallL3   : BOOL;                   (* 三级呼叫 [事件]，紧急 · Level 3 call *)
    bAckCmd   : BOOL;                   (* 应答指令 [事件]，沿触发 · Ack command, edge *)
    bClearCmd : BOOL;                   (* 解除指令 [事件]，沿触发 · Clear command, edge *)
    tAckLimMs : TIME  := T#60000MS;     (* 呼叫→应答超时阈 [ms] · Ack timeout limit *)
    tClrLimMs : TIME  := T#300000MS;    (* 应答→解除超时阈 [ms] · Clear timeout limit *)
    fEps      : LREAL := 1.0E-6;        (* 浮点判零容差 [实数域] · Floating zero tolerance *)
END_VAR
VAR_OUTPUT
    eActive : (eAlNone := 0, eAlL1 := 1, eAlL2 := 2, eAlL3 := 3);   (* 激活级别枚举输出 / Active level output enum *)
    bAcked  : BOOL;                     (* 已应答标志 [开关] · Acked flag *)
    bAckTmOut: BOOL;                    (* 呼叫→应答超时提示（非锁存）· Ack timeout hint *)
    bClrTmOut: BOOL;                    (* 应答→解除超时提示（非锁存）· Clear timeout hint *)
    nRespCnt: UDINT;                    (* 超时响应累计 [次]，防回卷 · Timeout response count *)
    nCloseCnt: UDINT;                   (* 正常解除累计 [次]，防回卷 · Normal close count *)
    bError  : BOOL;                     (* 故障标志，与故障码配对 · Fault flag paired with codes *)
    uErrorId: UDINT;                    (* 事件码 16#0000_0040，0 无事件 · Event code *)
END_VAR
VAR
    _eState  : (eStCalm := 0, eStCalling := 1, eStAcked := 2);   (* 内部状态机 / Internal state machine *)
    _nLevel  : INT;     (* 内部激活级别 [级]，与输出枚举分离 / Internal level *)
    uCode    : WORD;    (* 码位暂存，每拍重算 [码] · Code staging *)
    tonAck   : TON;     (* 呼叫→应答计时 [ms]，独立实例 1 · Ack timer, instance 1 *)
    tonClr   : TON;     (* 应答→解除计时 [ms]，独立实例 2 · Clear timer, instance 2 *)
    rTrigAck : R_TRIG;  (* 应答沿检测 · Ack edge *)
    rTrigClr : R_TRIG;  (* 解除沿检测 · Clear edge *)
    bCallNow : BOOL;    (* 仲裁后呼叫有效 [开关] · Arbitrated call active *)
    bAckTmPrv: BOOL;    (* 上拍应答超时提示快照，沿判据 · Previous ack hint snapshot *)
    bClrTmPrv: BOOL;    (* 上拍解除超时提示快照，沿判据 · Previous clear hint snapshot *)
    nCycles  : UDINT;   (* 呼叫周期计数 [次]，防回卷 · Call cycle count *)
END_VAR
VAR CONSTANT
    DL_ALP_WRAP : UDINT := 4294967290;  (* 计数防回卷余量 [次] · Counter wrap guard *)
END_VAR

(* === 段 0 · 实例刷新（每拍无条件，红线 7）=== *)
tonAck(IN := (_eState = eStCalling), PT := tAckLimMs);  (* 呼叫→应答独立计时 / Independent ack timer *)
tonClr(IN := (_eState = eStAcked), PT := tClrLimMs);    (* 应答→解除独立计时 / Independent clear timer *)
rTrigAck(CLK := bAckCmd);                               (* 应答沿检测 / Ack edge *)
rTrigClr(CLK := bClearCmd);                             (* 解除沿检测 / Clear edge *)

(* === 段 1 · 输入校验与量程闸 === *)
uCode := 16#0000;                       // 每拍清码（可达清零基线）/ Clear codes each scan
IF (tAckLimMs <= T#0MS) OR (tClrLimMs <= T#0MS) THEN
    uCode := 16#0040;                   // 故障级：超时阈非正域 / Fault: non-positive timeout limits
END_IF

(* === 段 2 · 主逻辑：三级仲裁与状态机 === *)
(* 仲裁：高级别抢占，同级不重复计数 / Arbitrate: higher level preempts *)
IF bCallL3 THEN
    bCallNow := TRUE;                   (* 三级最高优先 / Level 3 first *)
    IF _nLevel < 3 THEN
        _nLevel := 3;                   (* 抢占升级 / Preempt to level 3 *)
        IF nCycles < DL_ALP_WRAP THEN
            nCycles := nCycles + 1;     (* 新呼叫周期计数 / Count the new call *)
        END_IF
    END_IF
ELSIF bCallL2 THEN
    bCallNow := TRUE;
    IF _nLevel < 2 THEN
        _nLevel := 2;
        IF nCycles < DL_ALP_WRAP THEN
            nCycles := nCycles + 1;
        END_IF
    END_IF
ELSIF bCallL1 THEN
    bCallNow := TRUE;
    IF _nLevel < 1 THEN
        _nLevel := 1;
        IF nCycles < DL_ALP_WRAP THEN
            nCycles := nCycles + 1;
        END_IF
    END_IF
ELSE
    bCallNow := FALSE;                  (* 无呼叫 / No call *)
END_IF
CASE _eState OF
    eStCalm:                            (* 平静相：无激活告警 / Calm: no active alarm *)
        IF bCallNow AND bRun THEN
            _eState := eStCalling;      (* 拍 N 呼叫进入，拍 N+1 呼叫相 / To calling *)
        END_IF
    eStCalling:                         (* 呼叫相：等应答，超时提示非锁存 / Calling: await ack *)
        IF rTrigAck.Q THEN
            _eState := eStAcked;        (* 拍 N 应答沿，拍 N+1 已应答相 / To acked *)
        ELSIF (NOT bCallNow) THEN
            _eState := eStCalm;         (* 呼叫源撤清回平静（可达解除路径 1）/ Call source gone *)
            _nLevel := 0;               (* 级别清零 / Clear the level *)
        ELSIF tonAck.Q THEN
            bAckTmOut := TRUE;          (* 超时提示（非锁存，本拍置位）/ Timeout hint this scan *)
        END_IF
    eStAcked:                           (* 已应答相：等解除 / Acked: await clear *)
        IF rTrigClr.Q THEN
            _eState := eStCalm;         (* 解除回平静（可达解除路径 2）/ Clear to calm *)
            _nLevel := 0;
            IF nCloseCnt < DL_ALP_WRAP THEN
                nCloseCnt := nCloseCnt + 1;     (* 正常解除计数 / Count the normal close *)
            END_IF
        ELSIF tonClr.Q THEN
            bClrTmOut := TRUE;          (* 解除超时提示（非锁存）/ Clear timeout hint *)
        END_IF
ELSE
    _eState := eStCalm;                 (* ELSE 兜底回平静相 / ELSE fallback to calm *)
    _nLevel := 0;
END_CASE

(* === 段 3 · 输出映射与故障码（CASE 内未触碰输出枚举）=== *)
eActive := eAlNone;                     (* 级别映射默认 / Default mapping *)
IF _eState <> eStCalm THEN
    IF _nLevel = 3 THEN
        eActive := eAlL3;               (* 三级映射 / Map level 3 *)
    ELSIF _nLevel = 2 THEN
        eActive := eAlL2;               (* 二级映射 / Map level 2 *)
    ELSIF _nLevel = 1 THEN
        eActive := eAlL1;               (* 一级映射 / Map level 1 *)
    END_IF
END_IF
bAcked := (_eState = eStAcked);         (* 已应答标志 / Acked flag *)
IF (NOT bCallNow) AND (_eState = eStCalm) THEN
    bAckTmOut := FALSE;                 (* 超时提示可达清零 / Reachable clear of hints *)
    bClrTmOut := FALSE;
END_IF
IF NOT bRun THEN
    _eState := eStCalm;                 (* 撤使能回平静（可达解除路径 3）/ Disable to calm *)
    _nLevel := 0;
END_IF
IF bAckTmOut AND (NOT bAckTmPrv) THEN
    IF nRespCnt < DL_ALP_WRAP THEN
        nRespCnt := nRespCnt + 1;       (* 超时响应上升沿计数，防电平重复累加 / Edge-counted timeout responses *)
    END_IF
END_IF
IF bClrTmOut AND (NOT bClrTmPrv) THEN
    IF nRespCnt < DL_ALP_WRAP THEN
        nRespCnt := nRespCnt + 1;       (* 解除超时上升沿计数 / Edge-counted clear timeouts *)
    END_IF
END_IF
bAckTmPrv := bAckTmOut;                 (* 提示快照更新 / Update the hint snapshots *)
bClrTmPrv := bClrTmOut;
bError := (uCode <> 16#0000);           (* 故障标志配对 / Fault flag paired *)
uErrorId := WORD_TO_UDINT(uCode);       (* 码位单点写入（16#0000_0040 形态）/ Single write point *)
END_FUNCTION_BLOCK
