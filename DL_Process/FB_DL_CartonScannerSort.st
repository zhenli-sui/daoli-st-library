(*
  Component : FB_DL_CartonScannerSort
  Category  : DL_Process
  Type      : FB
  Version   : 1.0.0
  CodeSeg   : 16#06_0_3C
  Summary   : 纸箱扫码分道：读码判定 + 分道放行调度（与输送段 Zone 握手防追尾），读码失败走旁路 NG 道。
              Carton scanner sort: read verdict plus lane dispatch with zone handshake, read fail bypasses to the NG lane.
  溯源声明  : 道莅自研 clean-room
  边界安全  : 与 FB_DL_ConveyorZone 段间握手经 VAR_IN_OUT（ioZoneFree / ioDispatchAck），不写对方内部状态；
              步进超时 tAckMs 提为输入引脚，超时回安全步（NG 旁路，不堵线）；条码号负值域拦截；
              分道放行单拍脉冲防重复放行；CASE 必带 ELSE 安全步；TON 每拍无条件刷新。
  复用      : 与 FB_DL_ConveyorZone 握手（VAR_IN_OUT 引脚级，无实例依赖）；复用 FB_DL_StepSequencer 步进语义（clean-room 自含实现）
*)

FUNCTION_BLOCK FB_DL_CartonScannerSort
VAR_INPUT
    bRun      : BOOL;                   (* 调度使能 · Enable *)
    bScanTrig : BOOL;                   (* 扫码触发 [事件]，到位传感器 · Scan trigger pulse *)
    bReadOk   : BOOL;                   (* 读码成功反馈 [开关] · Read success feedback *)
    nCode     : DINT;                   (* 条码号 [号]，负值拦截 · Barcode number *)
    nLaneCnt  : INT := 3;               (* 合格分道数 [道]，域 1 到 3 · OK lane count *)
    tAckMs    : TIME  := T#2000MS;      (* 放行应答超时 [ms] · Dispatch ack timeout *)
    fEps      : LREAL := 1.0E-6;        (* 浮点判零容差 [实数域] · Floating zero tolerance *)
END_VAR
VAR_IN_OUT
    ioZoneFree    : BOOL;               (* 上游 Zone 空闲握手 [引脚] · Zone free handshake *)
    ioDispatchAck : BOOL;               (* 分道执行应答 [引脚]，由 Zone 件置位 · Dispatch ack from zone *)
END_VAR
VAR_OUTPUT
    eStep    : (eStpWait := 0, eStpDispatch := 1, eStpAck := 2);     (* 步枚举输出 / Step output enum *)
    nLaneSel : INT;                     (* 选中道号 [道]，1 到 nLaneCnt，0 为 NG 旁路 · Selected lane *)
    bDispatch: BOOL;                    (* 分道放行脉冲 [脉冲] · Dispatch pulse *)
    nOkCount : UDINT;                   (* 合格道累计 [件]，防回卷 · OK count *)
    nNgCount : UDINT;                   (* NG 旁路累计 [件]，防回卷 · NG count *)
    bError   : BOOL;                    (* 故障标志，与故障码配对 · Fault flag paired with codes *)
    uErrorId : UDINT;                   (* 事件码 16#0000_003C，0 无事件 · Event code *)
END_VAR
VAR
    _eState : (eStWait := 0, eStDispatch := 1, eStAck := 2);    (* 内部步进状态 / Internal step state *)
    uCode   : WORD;     (* 码位暂存，每拍重算 [码] · Code staging *)
    tonAck  : TON;      (* 应答超时计时 [ms]，每拍无条件刷新 · Ack timeout timer *)
    bTrigPrv: BOOL;     (* 上拍触发快照，上升沿判据 · Previous trigger snapshot *)
    bTrig   : BOOL;     (* 扫码上升沿 [脉冲] · Scan rising edge *)
    nCycles : UDINT;    (* 分道累计 [件]，防回卷 · Dispatch count *)
END_VAR
VAR CONSTANT
    DL_CSS_WRAP : UDINT := 4294967290;  (* 计数防回卷余量 [件] · Counter wrap guard *)
END_VAR

(* === 段 0 · 实例刷新（每拍无条件，红线 7）=== *)
tonAck(IN := (_eState = eStAck), PT := tAckMs);     (* 应答超时计时 / Ack timeout timing *)
bTrig := bScanTrig AND (NOT bTrigPrv);              (* 扫码上升沿 / Scan rising edge *)
bTrigPrv := bScanTrig;                              (* 快照更新 / Snapshot *)

(* === 段 1 · 输入校验与量程闸 === *)
uCode := 16#0000;                       // 每拍清码（可达清零基线）/ Clear codes each scan
IF (nLaneCnt < 1) OR (nLaneCnt > 3) OR (tAckMs <= T#0MS) THEN
    uCode := 16#003C;                   // 故障级：整定域外，调度冻结 / Fault: tuning domain invalid
END_IF

(* === 段 2 · 主逻辑：步进状态机（步进 CASE 必带 ELSE 安全步）=== *)
CASE _eState OF
    eStWait:                            (* 等待步：触发且 Zone 空闲才进入分派 / Wait for trigger and zone *)
        nLaneSel := 0;                  (* 道号清零待选 / Clear lane selection *)
        bDispatch := FALSE;             (* 放行脉冲收口 / Dispatch pulse off *)
        IF bRun AND (uCode = 16#0000) AND bTrig AND ioZoneFree THEN
            _eState := eStDispatch;     (* 拍 N 条件满足，拍 N+1 分派 / To dispatch next scan *)
        END_IF
    eStDispatch:                        (* 分派步：读码判定选道，失败走 NG 旁路不堵线 / Select lane, fail bypasses *)
        IF bReadOk AND (nCode >= 0) THEN
            nLaneSel := (UDINT_TO_DINT(INT_TO_UDINT(1)) + (nCode MOD UDINT_TO_DINT(INT_TO_UDINT(nLaneCnt))));
                                        (* 均衡选道：1 + 条码 mod 道数 / Balanced lane pick *)
            IF nOkCount < DL_CSS_WRAP THEN
                nOkCount := nOkCount + 1;   (* 合格计数 / Count OK *)
            END_IF
        ELSE
            nLaneSel := 0;              (* 读码失败：NG 旁路道 / Read fail: NG bypass lane *)
            IF nNgCount < DL_CSS_WRAP THEN
                nNgCount := nNgCount + 1;   (* NG 计数 / Count NG *)
            END_IF
        END_IF
        bDispatch := TRUE;              (* 放行脉冲发出 / Issue the dispatch pulse *)
        _eState := eStAck;              (* 拍 N 分派，拍 N+1 等应答 / To ack next scan *)
    eStAck:                             (* 应答步：应答回等待，超时安全步 / Await ack, timeout to safe step *)
        bDispatch := FALSE;             (* 脉冲单拍收口 / One-scan pulse off *)
        IF ioDispatchAck THEN
            _eState := eStWait;         (* 应答确认回等待 / Acked back to wait *)
        ELSIF tonAck.Q THEN
            _eState := eStWait;         (* 超时回安全等待步（NG 旁路语义，不堵线）/ Timeout to safe step *)
            uCode := 16#003C;           (* 故障级：应答超时 / Fault: ack timeout *)
        END_IF
ELSE
    _eState := eStWait;                 (* ELSE 兜底回安全等待步 / ELSE fallback to safe step *)
    bDispatch := FALSE;
    nLaneSel := 0;
END_CASE

(* === 段 3 · 输出映射与故障码（CASE 内未触碰输出枚举）=== *)
eStep := eStpWait;                      (* 步映射默认 / Default mapping *)
IF _eState = eStDispatch THEN
    eStep := eStpDispatch;              (* 分派步映射 / Map dispatch *)
ELSIF _eState = eStAck THEN
    eStep := eStpAck;                   (* 应答步映射 / Map ack *)
END_IF
IF nOkCount + nNgCount > DL_CSS_WRAP THEN
    nCycles := nOkCount + nNgCount;     (* 分道累计与两计数口径对齐 / Align the dispatch ledger *)
END_IF
bError := (uCode <> 16#0000);           (* 故障标志配对 / Fault flag paired *)
uErrorId := WORD_TO_UDINT(uCode);       (* 码位单点写入（16#0000_003C 形态）/ Single write point *)
END_FUNCTION_BLOCK
