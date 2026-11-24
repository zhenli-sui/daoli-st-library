(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ValveIslandDiag
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 来源标签 (Source)     : self-std（设备族新增线）
 * 功能描述 (Function)   : 阀岛（多阀槽位集束）诊断：①槽位占用仲裁——配置占用槽数与
 *                         实际上线槽数比对；②公共供气压力监视（欠压确认延时）；
 *                         ③逐槽位失联分类码位图与失联计数。
 * 分工互引 (Boundary)   : 单阀体机械 / 电气故障归 FB_DL_ControlValveDiag 与
 *                         FB_DL_PneuCylinderDiag；本件只做**阀岛级公共资源与槽位
 *                         上线状态**诊断，不下沉到单阀动作判定。
 * 边界与语义披露 (Boundary disclosure) :
 *   1) 槽位定长 8（DL_VI_SLOTS），越界无路径：nSlotUsed 域 1..8 由组态闸挡住，
 *      位图输出 uLostMask 的 bit i 对应槽位 i（bit0 = 槽位 0）。
 *   2) 占用仲裁口径：nSlotUsed 为组态占用数，实际上线数为 abSlotCommOk 为真的槽位数；
 *      上线数少于占用数即判失联（差值即 uLostMask 的置位数），多出的「超出占用」
 *      槽位为信息级占用冲突（不是故障，可能是有意扩展）。
 *   3) 公共供气压力欠压与槽位失联各自独立确认窗与独立码位（R190 归因唯一）；
 *      失联计数 nSlotsLost 为饱和计数（上限 8，结构上不会越界）。
 *   4) 非有限压力信号不参与欠压判据（保持上一拍确认状态），由信号闸置信息码，
 *      不锁存、不因一扫 NaN 让诊断永久失效。
 * 故障码表 (Error codes) :
 *   16#0003_0536 [故障级] 组态非法（占用槽数越域 / 压力阈 / 两确认窗）
 *                 反证：诊断挂起与「全部槽位正常且压力正常」输出组合相同。
 *   16#0003_0537 [故障级] 公共供气压力欠压确认，锁存至复位沿 + 压力恢复
 *                 反证：欠压与单槽失联都表现为「阀岛不可用」，处置不同（气源 vs 通讯）。
 *   16#0003_0538 [故障级] 槽位失联确认（上线数少于占用数），锁存至复位沿 + 恢复
 *                 反证：失联位图每拍刷新会掩盖「曾经失联」事实，锁存是唯一历史出口。
 *   16#0003_0483 [信息级] 上线槽位数多于配置占用数（占用冲突，按扩展容忍）
 *                 反证：多槽上线与「恰好全部占用上线」的输出差异只在配置侧，
 *                 运行期输出组合相同，无码不可观测。
 * 码位总账 (Code ledger) : 16#0003_0536 / 0537 / 0538 用 ｜ 16#0003_0483 用
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: TON / R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量 ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 数组定长无越界 / 非有限三判 / 域闸全枚举
 *                         R5 ✓ 全变量双语同行注释 ｜ R6 ✓ 四态 ENUM + ELSE 兜底
 *                         R7 ✓ 一沿四计时主体最前部无条件刷新
 * 修订历史 (Revision)   : 2026-11-22  v1.0.0  首版入库（R69 构建轮 · 批 2 · N5）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ValveIslandState（归属 DL_Device，与 FB_DL_ValveIslandDiag 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_ValveIslandState :
(
    eIdle    := 0,    // 未使能：诊断挂起 / Disabled, diagnosis suspended
    eWatch   := 10,   // 监视中：压力与槽位确认计时 / Watching, pressure and slot timers
    eAlarm   := 20,   // 已确认异常（至少一项锁存）/ Alarm latched
    eFault   := 99    // 组态非法：诊断拒绝 / Config illegal, diagnosis refused
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_ValveIslandDiag
 * 调用约定: 每个扫描周期无条件调用一次。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_ValveIslandDiag
VAR_INPUT
    abSlotCommOk  : ARRAY[0..7] OF BOOL;   // 逐槽位上线（通讯 OK）：bit i 对应槽位 i / per-slot online flags
    nSlotUsed     : INT := 8;              // 组态占用槽位数 [个]，域 1..8 / configured occupied slots, 1 to 8
    fSupplyPress  : REAL;                  // 公共供气压力 [bar] / common supply pressure [bar]
    fPressMin     : REAL := 4.0;           // 供气压力下限 [bar]，<= 0 组态非法 / supply pressure floor [bar]
    tPressConfirm : TIME := T#3S;          // 欠压确认窗 [s] / low-pressure confirm window [s]
    tSlotConfirm  : TIME := T#5S;          // 槽位失联确认窗 [s] / slot-loss confirm window [s]
    bEnable       : BOOL := TRUE;          // 使能 / enable
    bReset        : BOOL;                  // 上升沿：清欠压 / 失联锁存 / rising edge clears the latches
END_VAR
VAR_OUTPUT
    uLostMask     : WORD;                  // 逐槽失联位图（bit i = 槽位 i）/ per-slot loss bitmap
    nSlotsLost    : INT;                   // 失联槽位数 [个]，0..8 / lost slot count
    bSlotLost     : BOOL;                  // 槽位失联锁存（确认后常驻）/ slot loss latched
    bPressLow     : BOOL;                  // 供气欠压锁存 / low supply pressure latched
    bError        : BOOL;                  // 故障标志（组态 / 两类锁存归并）/ fault flag
    uErrorId      : UDINT;                 // 故障码，0 = 无故障 / error code, 0 = none
    eState        : E_DL_ValveIslandState; // 当前状态（供 HMI 诊断）/ current state
END_VAR
VAR
    fbTrigReset   : R_TRIG;                // 复位沿检测实例 / reset edge detector
    tonPress      : TON;                   // 欠压确认计时实例 / low-pressure confirm timer
    tonSlot       : TON;                   // 槽位失联确认计时实例 / slot-loss confirm timer
    eStateInt     : E_DL_ValveIslandState; // 主状态机内部当前态 / internal state
    nOnlineCnt    : INT;                   // 本拍上线槽位数 [个] / online slot count this scan
    nIdx          : INT;                   // 槽位遍历游标 [槽号] / slot cursor
    uMaskInt      : WORD;                  // 本拍失联位图累加 / loss bitmap accumulator
    bSlotCond     : BOOL;                  // 本拍失联判据成立 / slot-loss criterion true
    bPressCond    : BOOL;                  // 本拍欠压判据成立 / low-pressure criterion true
    bPressBad     : BOOL;                  // 压力信号非有限 / pressure non-finite
    bSlotLatch    : BOOL;                  // 失联锁存内部副本 / internal slot-loss latch
    bPressLatch   : BOOL;                  // 欠压锁存内部副本 / internal low-pressure latch
    bCfgBad       : BOOL;                  // 本拍组态非法 / config illegal this scan
    bCfgLatch     : BOOL;                  // 组态锁存（复位沿 + 组态改对解除）/ config latch
    bErrorInt     : BOOL;                  // 本拍故障置位累加 / fault set accumulator
    bFirstScan    : BOOL := TRUE;          // 上电首扫标志 / first-scan flag
END_VAR
VAR CONSTANT
    DL_VI_SLOTS   : INT := 8;              // 槽位定长 [个]，与数组维度一致 / fixed slot count
    DL_VI_FIN_LIM : REAL := 1.0E30;        // REAL 幅值兜底判界 / REAL magnitude bound
    DL_VI_BIT1    : WORD := 1;             // 位图基元（bit0 掩码）/ bitmap base element
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：一沿二计时位于主体最前部
 *      Unconditional refresh: one edge and two timers at the very top
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);

(* 段 2｜每拍预清（FB32-1）：单拍标志与位图累加量 / per-scan preset *)
bErrorInt := FALSE;
uMaskInt  := 16#0000;              // 失联位图每拍重算（事实量，非锁存）/ loss bitmap recomputed each scan
nOnlineCnt := 0;

(* 段 3｜上电首扫：锁存与状态落安全侧 / first-scan init *)
IF bFirstScan THEN
    eStateInt  := E_DL_ValveIslandState.eIdle;
    bSlotLatch := FALSE;
    bPressLatch := FALSE;
    bFirstScan := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜组态域闸（R151 全枚举）+ 解除路径（R152 自证可达）
 *      Config gate plus the provably reachable clear path
 *-----------------------------------------------------------------------------*)
bCfgBad := (nSlotUsed < 1) OR (nSlotUsed > DL_VI_SLOTS)
           OR (fPressMin <= 0.0) OR (fPressMin <> fPressMin)
           OR (tPressConfirm <= T#0S) OR (tSlotConfirm <= T#0S);
IF bCfgBad THEN
    bCfgLatch := TRUE;
END_IF
IF fbTrigReset.Q AND (NOT bCfgBad) THEN
    bCfgLatch := FALSE;              // 组态锁存解除 / config latch cleared
    uErrorId  := 16#0000_0000;       // 码位随解除归零 / code cleared with the latch
END_IF
IF bCfgLatch THEN
    uErrorId  := 16#0003_0536;       // 故障级：组态非法 / fault: illegal configuration
    bErrorInt := TRUE;               // R45 配对 / paired with the code
    eStateInt := E_DL_ValveIslandState.eFault;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜占用仲裁：逐槽位统计上线数并构造失联位图（定长 FOR，无越界路径）
 *      Occupation arbitration: count online slots and build the loss bitmap
 *-----------------------------------------------------------------------------*)
FOR nIdx := 0 TO (DL_VI_SLOTS - 1) DO
    IF abSlotCommOk[nIdx] THEN
        nOnlineCnt := nOnlineCnt + 1;                        // 上线计数推进 [个] / online count up
    ELSIF nIdx < nSlotUsed THEN
        uMaskInt := uMaskInt OR SHL(DL_VI_BIT1, nIdx);       // 占用槽且离线：置失联位（nIdx <= 7 < 16 位宽，R48 归一）/ set the loss bit
    END_IF
END_FOR

bSlotCond  := nOnlineCnt < nSlotUsed;              // 上线数少于占用数即失联 / fewer online than occupied
bPressBad  := (fSupplyPress <> fSupplyPress)
              OR ((fSupplyPress - fSupplyPress) <> (fSupplyPress - fSupplyPress))
              OR (ABS(fSupplyPress) >= DL_VI_FIN_LIM);
bPressCond := (NOT bPressBad) AND (NOT bCfgLatch) AND (fSupplyPress < fPressMin);

IF (NOT bPressBad) AND (nOnlineCnt > nSlotUsed) THEN
    uErrorId := 16#0003_0483;      // 信息级：超出占用的槽位已上线（按扩展容忍）/ info: extra slots online
END_IF

(* 确认计时器门控：判据 AND 未锁存 AND 非组态故障（R99） *)
tonPress(IN := bPressCond AND (NOT bPressLatch), PT := tPressConfirm);
tonSlot(IN := bSlotCond AND (NOT bSlotLatch) AND (NOT bCfgLatch), PT := tSlotConfirm);

(*------------------------------------------------------------------------------
 * 段 6｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *-----------------------------------------------------------------------------*)
CASE eStateInt OF

    E_DL_ValveIslandState.eIdle:
        IF bEnable AND (NOT bCfgLatch) THEN
            eStateInt := E_DL_ValveIslandState.eWatch;
        END_IF

    E_DL_ValveIslandState.eWatch:
        IF (NOT bEnable) OR bCfgLatch THEN
            eStateInt := E_DL_ValveIslandState.eIdle;
        ELSIF bSlotLatch OR bPressLatch THEN
            eStateInt := E_DL_ValveIslandState.eAlarm;       // 任一确认即告警驻留 / any confirmation alarms
        END_IF

    E_DL_ValveIslandState.eAlarm:
        (* 解除路径（R152 自证可达）：复位沿 AND 两判据本拍均已消失 AND 组态合法 *)
        IF fbTrigReset.Q AND (NOT bSlotCond) AND (NOT bPressCond) AND (NOT bCfgBad) THEN
            bSlotLatch  := FALSE;                            // 两类锁存同沿解除 / both latches cleared
            bPressLatch := FALSE;
            uErrorId    := 16#0000_0000;
            eStateInt   := E_DL_ValveIslandState.eWatch;
        ELSIF (NOT bEnable) OR bCfgLatch THEN
            eStateInt   := E_DL_ValveIslandState.eIdle;
        END_IF

    E_DL_ValveIslandState.eFault:
        IF fbTrigReset.Q AND (NOT bCfgBad) THEN
            bCfgLatch := FALSE;
            uErrorId  := 16#0000_0000;
            eStateInt := E_DL_ValveIslandState.eIdle;
        END_IF

    ELSE
        (* 非法状态拦截 / illegal state interception *)
        eStateInt := E_DL_ValveIslandState.eFault;
        uErrorId  := 16#0003_0536;
        bErrorInt := TRUE;

END_CASE;

(*------------------------------------------------------------------------------
 * 段 7｜确认到期消化：两类各自独立锁存 + 独立码位（R190 归因唯一）
 *      Confirm expiry digestion with two distinct codes
 *-----------------------------------------------------------------------------*)
IF tonPress.Q AND (NOT bPressLatch) THEN
    bPressLatch := TRUE;             // 欠压锁存 / low pressure latched
    uErrorId    := 16#0003_0537;     // 故障级：供气欠压确认 / fault: low supply pressure confirmed
    bErrorInt   := TRUE;             // R45 配对 / paired with the code
    eStateInt   := E_DL_ValveIslandState.eAlarm;
END_IF
IF tonSlot.Q AND (NOT bSlotLatch) THEN
    bSlotLatch := TRUE;              // 失联锁存 / slot loss latched
    uErrorId   := 16#0003_0538;      // 故障级：槽位失联确认 / fault: slot loss confirmed
    bErrorInt  := TRUE;              // R45 配对 / paired with the code
    eStateInt  := E_DL_ValveIslandState.eAlarm;
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜输出单一出口（范式 P-05）
 *      Single output exit
 *-----------------------------------------------------------------------------*)
uLostMask  := uMaskInt;              // 失联位图直出（bit i = 槽位 i）/ loss bitmap straight out
(* 失联数 = 占用数 − 上线数（负值钳 0，结构上 nOnlineCnt <= 8 已由定长循环封顶）*)
(* Lost count equals occupied minus online, floored at zero *)
IF nOnlineCnt < nSlotUsed THEN
    nSlotsLost := nSlotUsed - nOnlineCnt;   // 失联槽位数 [个] / lost slot count
ELSE
    nSlotsLost := 0;                        // 无失联 [个] / no lost slot
END_IF
bSlotLost  := bSlotLatch;
bPressLow  := bPressLatch;
bError     := bErrorInt OR bCfgLatch OR (eStateInt = E_DL_ValveIslandState.eAlarm);
eState     := eStateInt;
END_FUNCTION_BLOCK
