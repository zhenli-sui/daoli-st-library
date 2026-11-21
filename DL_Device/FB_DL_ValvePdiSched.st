// =====================================================================
// FB_DL_ValvePdiSched.st
// 阀岛 PDI 批量读取调度（多槽轮询编排 + 槽超时监护 + 各槽错误码回放台账）
// Valve island PDI read scheduling across slots with timeout watch
// 所属子库: DL_Device    版本: v1.0.0    兼容: CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 码位: 16#0003_03E8 ~ 16#0003_03EC (本件独占 5 槽, 勿复用)
// 溯源: 道莅 clean-room 防御性实现
//       来源组标签: valve-island, pdi, scheduling, diagnostics
// 结构体属主: ST_DL_PdiSlotCfg —— 本文件为全库唯一属主, 其他件只引用不重声明
// 修改记录: R30 初版 (ROUND_PLAN_R30 序 4)
// 分层声明: 本件只做多实例分槽调度编排, 传输层能力经回读注入引脚消费,
//           与库内 PDI 读取调度件保持调度与传输分层语义一致, 不重复实现传输
// =====================================================================
// ---------------------------------------------------------------------
// 结构体定义: ST_DL_PdiSlotCfg (全库唯一属主, 其他件只引用不重声明)
// ---------------------------------------------------------------------
TYPE ST_DL_PdiSlotCfg :
STRUCT
    tSlotTimeout : TIME;    // 槽传输超时 T#10MS~T#60S / Slot transfer timeout [s]
    uRetryMax    : USINT;   // 槽最大重试次数 0~10 次 / Max retry count per slot
    uDevIndex    : USINT;   // 槽逻辑设备序号 1~99（语义编号, 非物理地址）/ Logical device index
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB_DL_ValvePdiSched
VAR_INPUT
    bEnable       : BOOL  := FALSE;   // 使能 / Enable
    auSlots       : USINT := 2;       // 并行槽配置数 1~4, 越界钳位 / Configured slot count 1..4, clamped
    tPollCycle    : TIME  := T#100MS; // 轮询节拍 T#10MS~T#60S / Poll cycle period [ms]
    astSlotCfg    : ARRAY[1..4] OF ST_DL_PdiSlotCfg;  // 各槽配置结构体数组注入 / Per-slot config array injected
    abSlotEn      : ARRAY[1..4] OF BOOL;  // 各槽使能表 / Per-slot enable table
    aubSlotStat   : ARRAY[1..4] OF USINT; // 各槽传输层状态回读注入: 0=空闲 1=忙 2=完成 3=错误 / Per-slot transfer status injected
    auiSlotErrIn  : ARRAY[1..4] OF UDINT; // 各槽传输层错误码注入回放 / Per-slot transfer error code injected
END_VAR
VAR_OUTPUT
    uActiveSlot   : USINT := 0;       // 当前活动槽号 1~4, 0 = 无 / Active slot 1..4, 0 = none
    auErrSlot     : ARRAY[1..4] OF UDINT;  // 各槽错误码回放台账 / Per-slot error code replay ledger
    bAllSlotsOk   : BOOL  := FALSE;   // 全部使能槽无错误 / All enabled slots error-free
    eErr          : UDINT := 16#0003_03E8;  // 错误码 / Error code
END_VAR
VAR
    tonPoll       : TON;              // 轮询节拍定时器, 每拍无条件刷新 / Poll cycle timer, refreshed every cycle
    rtrPoll       : R_TRIG;           // 轮询节拍上升沿, 每拍无条件刷新 / Poll tick edge, refreshed every cycle
    aTonTmo       : ARRAY[1..4] OF TON;   // 各槽传输超时定时器, 每拍无条件刷新 / Per-slot timeout timers, refreshed every cycle
    uSlotCnt      : USINT := 1;       // 钳位后的有效槽数 1~4 / Clamped slot count 1..4
    bClampInfo    : BOOL  := FALSE;   // 槽数越界钳位信息标记 / Slot-count clamp info flag
    bAnyEn        : BOOL  := FALSE;   // 存在使能槽标记 / Any enabled slot flag
    bTrspErr      : BOOL  := FALSE;   // 任一槽传输层错误标记 / Any-slot transfer error flag
    bTmoErr       : BOOL  := FALSE;   // 任一槽超时错误标记 / Any-slot timeout error flag
    uNext         : USINT := 1;       // 轮转探测槽号 / Rotation probe slot
    uProbe        : USINT := 0;       // 轮转探测守卫计数 / Rotation probe guard counter
    uZi           : INT   := 1;       // 1..4 数组下标 / Array subscript 1..4
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占, 勿复用）:
//   16#0003_03E8 信息 调度正常（轮询进行中）
//   16#0003_03E9 故障 活动槽传输超时（码同步回放至该槽 auErrSlot）,
//                解除式 = 该槽重新激活且传输层状态回到空闲且注入错误码为零
//   16#0003_03EA 信息 组态槽数越界已钳位 1..4, 或无使能槽（活动槽记 0）
//   16#0003_03EB 故障 任一槽传输层错误码注入非零（回放至对应槽）, 解除式同 03E9
//   16#0003_03EC 信息 待机未使能
// ---------------------------------------------------------------------

// ---- 槽数组态钳位 / Slot count clamp ----
bClampInfo := FALSE;                    // 钳位信息标记复位 / Reset clamp flag
uSlotCnt   := auSlots;                  // 取组态值 / Take configured value
IF auSlots < 1 THEN
    uSlotCnt   := 1;                    // 下界钳位 / Clamp to lower bound
    bClampInfo := TRUE;                 // 置钳位信息 / Set clamp info
END_IF
IF auSlots > 4 THEN
    uSlotCnt   := 4;                    // 上界钳位 / Clamp to upper bound
    bClampInfo := TRUE;                 // 置钳位信息 / Set clamp info
END_IF

// ---- 使能槽存在性扫描 / Enabled-slot existence scan ----
bAnyEn := FALSE;                        // 复位存在标记 / Reset existence flag
FOR uZi := 1 TO 4 DO
    IF abSlotEn[uZi] AND (INT_TO_USINT(uZi) <= uSlotCnt) THEN
        bAnyEn := TRUE;                 // 存在有效使能槽 / Valid enabled slot exists
    END_IF
END_FOR

// ---- 未使能待机处理 / Standby when disabled ----
IF NOT bEnable THEN
    uActiveSlot := 0;                   // 活动槽清零 / Clear active slot
END_IF

// ---- 轮询节拍与边沿实例无条件周期刷新 / Unconditional poll timer and edge refresh ----
tonPoll(IN := bEnable, PT := tPollCycle);       // 节拍计时 / Cycle timing
rtrPoll(CLK := tonPoll.Q);                      // 节拍沿检测 / Tick edge detection

// ---- 节拍沿触发轮转到下一使能槽（单拍至多推进一次, 单拍单发）
//      Tick edge advances to next enabled slot, at most once per cycle ----
IF rtrPoll.Q AND bEnable AND bAnyEn THEN
    uNext  := uActiveSlot;              // 从当前槽起探测 / Probe from current slot
    uProbe := 0;                        // 守卫计数清零 / Clear guard counter
    WHILE uProbe < 4 DO
        uNext := uNext + 1;             // 探测下一槽号 / Probe next slot
        IF uNext > uSlotCnt THEN
            uNext := 1;                 // 回绕到首槽 / Wrap to first slot
        END_IF
        uProbe := uProbe + 1;           // 守卫计数推进 / Advance guard counter
        IF abSlotEn[uNext] AND (uNext <= uSlotCnt) THEN
            uActiveSlot := uNext;       // 锁定新活动槽 / Lock new active slot
            uProbe := 4;                // 提前退出循环 / Early exit loop
        END_IF
    END_WHILE
ELSIF (NOT bAnyEn) OR (uActiveSlot > uSlotCnt) THEN
    uActiveSlot := 0;                   // 无使能槽或槽号越界, 记 0 / No enabled slot or out of range
END_IF

// ---- 各槽超时监护与错误码台账（定时器逐实例无条件刷新）/ Per-slot timeout watch and error ledger ----
bTrspErr := FALSE;                      // 传输错误标记复位 / Reset transfer error flag
bTmoErr  := FALSE;                      // 超时错误标记复位 / Reset timeout error flag
FOR uZi := 1 TO 4 DO
    IF bEnable AND (INT_TO_USINT(uZi) = uActiveSlot) AND (aubSlotStat[uZi] = 1) THEN
        aTonTmo[uZi](IN := TRUE, PT := astSlotCfg[uZi].tSlotTimeout);   // 活动槽忙计时 / Active busy timing
        IF aTonTmo[uZi].Q THEN
            auErrSlot[uZi] := 16#0003_03E9;     // 槽超时码回放台账 / Slot timeout code to ledger
            bTmoErr := TRUE;                    // 置超时错误标记 / Set timeout flag
        END_IF
    ELSE
        aTonTmo[uZi](IN := FALSE, PT := astSlotCfg[uZi].tSlotTimeout);  // 非活动槽显式复位 / Explicit reset
    END_IF
    // 传输层错误码注入回放（照记账不停摆: 记录后调度继续轮转）/ Replay injected error, scheduling continues
    IF auiSlotErrIn[uZi] <> 0 THEN
        auErrSlot[uZi] := auiSlotErrIn[uZi];    // 回放注入错误码 / Replay injected error code
        bTrspErr := TRUE;                       // 置传输错误标记 / Set transfer error flag
    END_IF
    // 错误解除: 该槽回空闲且注入错误码为零且非当前活动槽 / Release: idle, no injected error, not active
    IF (aubSlotStat[uZi] = 0) AND (auiSlotErrIn[uZi] = 0) AND (INT_TO_USINT(uZi) <> uActiveSlot) THEN
        auErrSlot[uZi] := 0;                    // 清该槽台账 / Clear slot ledger
    END_IF
END_FOR

// ---- 全槽正常输出 / All-slots-ok output ----
bAllSlotsOk := bEnable;                 // 基线: 使能且无任一槽错误 / Baseline: enabled
FOR uZi := 1 TO 4 DO
    IF abSlotEn[uZi] AND (auErrSlot[uZi] <> 0) THEN
        bAllSlotsOk := FALSE;           // 任一使能槽有错误码即不正常 / Any enabled slot with error
    END_IF
END_FOR

// ---- 错误码仲裁 / Error arbitration ----
IF NOT bEnable THEN
    eErr := 16#0003_03EC;               // 待机未使能 / Standby
ELSIF bTrspErr THEN
    eErr := 16#0003_03EB;               // 传输层错误回放 / Transfer error replay
ELSIF bTmoErr THEN
    eErr := 16#0003_03E9;               // 槽超时 / Slot timeout
ELSIF bClampInfo OR (uActiveSlot = 0) THEN
    eErr := 16#0003_03EA;               // 钳位或无使能槽信息 / Clamp or no-enabled-slot info
ELSE
    eErr := 16#0003_03E8;               // 调度正常 / Scheduling normal
END_IF

END_FUNCTION_BLOCK
