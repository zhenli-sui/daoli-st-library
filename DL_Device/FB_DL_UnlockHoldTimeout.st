(*
  Component : FB_DL_UnlockHoldTimeout
  Category  : DL_Device
  Type      : FB
  Version   : 1.0.0
  CodeSeg   : 16#03_1_02
  Summary   : 安全门解锁保持超时监视：解锁有效但门未开持续超阈 → 电磁铁/机械卡滞提示，事件沿计数留痕。
              Door unlock hold timeout monitor: unlocked but not opened over limit, solenoid or jam hint with edge-counted ledger.
  溯源声明  : 道莅自研 clean-room
  边界安全  : 只消费 FB_DL_GuardLockDoor 对外输出引脚（不侵入其内部状态）；超时阈值 tHoldLimMs
              提为输入引脚（带 ms 单位，禁魔法数）并做正域闸（> 0，防 TON 无效整定）；
              提示为非锁存自清（条件消失即清），事件计数走上升沿防电平重复累加；
              TON 每拍无条件刷新（段 0）；全浮点比较带 fEps 容差。
  复用      : 消费 FB_DL_GuardLockDoor 的对外输出引脚（bUnlockActive / bDoorOpened），无实例依赖
*)

FUNCTION_BLOCK FB_DL_UnlockHoldTimeout
VAR_INPUT
    bRun          : BOOL;              (* 监视使能 · Enable *)
    bUnlockActive : BOOL;              (* 解锁有效输出 [开关]，来自门控 FB 对外引脚 · Unlock active from door FB *)
    bDoorOpened   : BOOL;              (* 门已开开关 [开关] · Door opened switch *)
    tHoldLimMs    : TIME  := T#3000MS; (* 解锁保持超时阈 [ms] · Hold timeout limit *)
    fEps          : LREAL := 1.0E-6;   (* 浮点判零容差 [实数域] · Floating zero tolerance *)
END_VAR
VAR_OUTPUT
    bHoldNow  : BOOL;                   (* 当前处于超时判据窗口内 [开关] · In the hold judgement window *)
    bJamWarn  : BOOL;                   (* 卡滞提示 [提示]，非锁存自清 · Jam hint, self-clearing *)
    nJamCount : UDINT;                  (* 卡滞事件累计 [次]，沿计数防回卷 · Jam event count *)
    bError    : BOOL;                   (* 故障标志，与故障码配对 · Fault flag paired with codes *)
    uErrorId  : UDINT;                  (* 事件码 16#0000_0102，0 无事件 · Event code *)
END_VAR
VAR
    uCode   : WORD;    (* 码位暂存，每拍重算 [码] · Code staging *)
    tonHold : TON;     (* 解锁保持计时 [ms]，每拍无条件刷新 · Hold timing timer *)
    bWarnPrv: BOOL;    (* 上拍提示快照，事件沿判据 · Previous warn snapshot *)
    nCycles : UDINT;   (* 监视拍计数 [拍]，防回卷 · Monitor scan count *)
END_VAR
VAR CONSTANT
    DL_UHT_WRAP : UDINT := 4294967290;  (* 计数防回卷余量 [次] · Counter wrap guard *)
END_VAR

(* === 段 0 · 实例刷新（每拍无条件，红线 7）=== *)
tonHold(IN := bRun AND bUnlockActive AND (NOT bDoorOpened), PT := tHoldLimMs);
                                        (* 解锁有效且门未开：保持计时 / Hold timing while unlocked and closed *)
bHoldNow := tonHold.Q;                  (* 判据窗口在报状态 / Window active status *)

(* === 段 1 · 输入校验与量程闸 === *)
uCode := 16#0000;                       // 每拍清码（可达清零基线）/ Clear codes each scan
IF tHoldLimMs <= T#0MS THEN
    uCode := 16#0102;                   // 故障级：超时阈非正域，监视失效 / Fault: non-positive limit
END_IF

(* === 段 2 · 主逻辑：保持超时判据（非锁存自清）=== *)
IF bRun AND (uCode = 16#0000) THEN
    bJamWarn := tonHold.Q;              (* 超时到点即提示；解锁或开门条件消失下拍自清 / Hint while timed out *)
    IF bJamWarn AND (NOT bWarnPrv) THEN
        IF nJamCount < DL_UHT_WRAP THEN
            nJamCount := nJamCount + 1; (* 事件上升沿计数，防电平重复累加 / Edge-counted event *)
        END_IF
    END_IF
    IF nCycles < DL_UHT_WRAP THEN
        nCycles := nCycles + 1;         (* 监视拍计数 / Monitor scan count *)
    END_IF
ELSE
    bJamWarn := FALSE;                  (* 撤使能提示清零（可达清零路径）/ Clear on disable *)
END_IF
bWarnPrv := bJamWarn;                   (* 提示快照 / Warn snapshot *)

(* === 段 3 · 输出映射与故障码 === *)
bError := (uCode <> 16#0000) OR bJamWarn;   (* 故障标志：域外码或卡滞提示 / Fault flag *)
IF bJamWarn THEN
    uErrorId := WORD_TO_UDINT(16#0102); (* 码位 16#0000_0102 解锁保持超时 / Hold timeout code *)
ELSE
    uErrorId := WORD_TO_UDINT(uCode);   (* 域外码或零 / Domain code or zero *)
END_IF
END_FUNCTION_BLOCK
