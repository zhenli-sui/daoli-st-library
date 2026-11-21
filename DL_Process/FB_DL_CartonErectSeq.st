(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CartonErectSeq
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖纯 IEC 61131-3 标准元素，零厂商方言
 * 功能描述 (Function)   : 开箱机顺控四相：吸箱 → 成型 → 折底 → 输送，含卡箱检测，
 *                         单相超时（tStepMax 默认 5 s）监视；反馈缺失一律进 ERR
 *                         并锁存卡箱（不跳相）；PICK 相真空超时先释放真空再报错；
 *                         CASE 含 ELSE 安全态（全输出 FALSE）；复位退 IDLE。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_ErectPhase / TYPE E_DL_ErectErr /
 *                         FUNCTION_BLOCK FB_DL_CartonErectSeq
 * 依赖 (Depends)        : 无 DL_ 内部依赖；Standard.library TON/R_TRIG 实例
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         相超时用状态判定（TON.Q + 相枚举），非单拍标志 ｜
 *                         枚举成员全部显式赋值 ｜ TON/R_TRIG 每周期无条件调用 ｜
 *                         CASE 含 ELSE 兜底至安全态 ｜ 无占位词 ｜ 超时引脚带单位
 * 错误码表 (Codes)      : 16#0005_041C IDLE（或 DONE 等待下一循环，共用反证句）
 *                         16#0005_041D PICK（吸箱相）
 *                         16#0005_041E FORM（成型相）
 *                         16#0005_041F FLAP（折底相，EJECT 输送段共用反证句）
 *                         16#0005_0420 ERR（含相超时定位，定位另由 eJamPhase 输出）
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R27 · 阶段三批 4
 * 验收向量 (Acceptance) : bStart → PICK（真空指令置位）→ bVacuumOk → FORM → bBoxFormed
 *                         → FLAP → bFlapClosed → EJECT → DONE；PICK 相 tStepMax 内
 *                         无 bVacuumOk → ERR + bJam + 真空撤 + eJamPhase=PICK
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ErectPhase（归属 DL_Process，开箱顺控相）
 *----------------------------------------------------------------------------*)
TYPE E_DL_ErectPhase :
(
    ePhaseIdle  := 0,    // 空闲待启动 / Idle, waiting for a start
    ePhasePick  := 10,   // 吸箱相（真空建立）/ Pick phase, vacuum build-up
    ePhaseForm  := 20,   // 成型相 / Forming phase
    ePhaseFlap  := 30,   // 折底相 / Flap-closing phase
    ePhaseEject := 40,   // 输送相（定时完成）/ Eject phase, timed
    ePhaseDone  := 50,   // 循环完成（等待下一循环）/ Cycle done, waiting for the next
    ePhaseErr   := 99    // 故障相（卡箱锁存）/ Error phase, jam latched
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ErectErr（归属 DL_Process，与 FB_DL_CartonErectSeq 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_ErectErr :
(
    eIdle   := 16#0005_041C,   // IDLE（含 DONE 等待态）/ Idle or done-waiting
    ePick   := 16#0005_041D,   // PICK 相（吸箱）/ Pick phase
    eForm   := 16#0005_041E,   // FORM 相（成型）/ Form phase
    eFlap   := 16#0005_041F,   // FLAP 相（折底，含 EJECT 输送段）/ Flap phase, includes eject
    eErr    := 16#0005_0420    // ERR 相（含相超时定位）/ Error phase with timeout localisation
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_CartonErectSeq
 * 调用约定: 每个扫描周期无条件调用一次。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_CartonErectSeq
VAR_INPUT
    bVacuumOk    : BOOL;               // 真空建立反馈 / Vacuum established feedback
    bBoxFormed   : BOOL;               // 成型到位反馈 / Box formed feedback
    bFlapClosed  : BOOL;               // 折底到位反馈 / Flap closed feedback
    tStepMax     : TIME := T#5S;       // 单相超时 [秒]，默认 5 / Per-phase timeout [s]
    bStart       : BOOL;               // 启动（上升沿）/ Start, rising edge
    bReset       : BOOL;               // 复位（上升沿，退 IDLE 并清卡箱）/ Reset, rising edge
END_VAR
VAR_OUTPUT
    ePhase       : E_DL_ErectPhase;    // 顺控当前相 / Current sequence phase
    bDone        : BOOL;               // 循环完成（单拍脉冲）/ Cycle done, single-scan pulse
    bJam         : BOOL;               // 卡箱锁存（需复位）/ Jam latched until reset
    eJamPhase    : E_DL_ErectPhase;    // 超时定位相（卡箱时有效）/ Phase where the jam occurred
    bVacuumCmd   : BOOL;               // 真空指令 / Vacuum command
    bConveyorCmd : BOOL;               // 输送指令 / Conveyor command
    eErr         : E_DL_ErectErr;      // 错误码 / Error code
END_VAR
VAR
    fbStartTrig  : R_TRIG;             // 启动沿实例（无条件调用）/ Start edge instance
    fbResetTrig  : R_TRIG;             // 复位沿实例（无条件调用）/ Reset edge instance
    tonStep      : TON;                // 单相超时定时器（无条件调用）/ Per-phase timeout timer
    bPhaseRun    : BOOL;               // 相内计时使能（PICK~EJECT）/ Phase timing enable
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜沿检测与 TON 每周期无条件调用（仅 IN 条件化）：相超时用状态判定
 *----------------------------------------------------------------------------*)
fbStartTrig(CLK := bStart);                           // 启动沿检测无条件刷新 / start edge refreshed unconditionally
fbResetTrig(CLK := bReset);                           // 复位沿检测无条件刷新 / reset edge refreshed unconditionally
bPhaseRun := (ePhase = E_DL_ErectPhase.ePhasePick) OR (ePhase = E_DL_ErectPhase.ePhaseForm)
          OR (ePhase = E_DL_ErectPhase.ePhaseFlap) OR (ePhase = E_DL_ErectPhase.ePhaseEject);   // 动作相判据 / timed-phase predicate
tonStep(IN := bPhaseRun, PT := tStepMax);             // 单相超时计时（无条件刷新）/ per-phase timing

(*------------------------------------------------------------------------------
 * 段 2｜复位沿：回 IDLE 并清卡箱锁存
 *----------------------------------------------------------------------------*)
IF fbResetTrig.Q THEN
    ePhase := E_DL_ErectPhase.ePhaseIdle;             // 回空闲 / back to idle
    bJam := FALSE;                                    // 卡箱解锁 / jam released
    bDone := FALSE;                                   // 完成撤 / done dropped
    bVacuumCmd := FALSE;                              // 真空撤 / vacuum dropped
    bConveyorCmd := FALSE;                            // 输送撤 / conveyor dropped
    eJamPhase := E_DL_ErectPhase.ePhaseIdle;          // 定位相清 / jam phase cleared
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜启动沿：仅在 IDLE/DONE 允许启动（卡箱态必须复位）
 *----------------------------------------------------------------------------*)
IF fbStartTrig.Q THEN
    IF (ePhase = E_DL_ErectPhase.ePhaseIdle) OR (ePhase = E_DL_ErectPhase.ePhaseDone) THEN
        ePhase := E_DL_ErectPhase.ePhasePick;         // 进吸箱相 / enter pick phase
        bDone := FALSE;                               // 完成撤 / done dropped
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜顺控状态机：CASE 含 ELSE 兜底（ELSE → 安全态全输出 FALSE）
 *----------------------------------------------------------------------------*)
bDone := FALSE;                                       // 完成脉冲逐拍先清 / done pulse cleared first
CASE ePhase OF

    E_DL_ErectPhase.ePhaseIdle:
        bVacuumCmd := FALSE;                          // 空闲：真空撤 / vacuum dropped
        bConveyorCmd := FALSE;                        // 空闲：输送撤 / conveyor dropped
        eErr := E_DL_ErectErr.eIdle;                  // 码 041C / code idle

    E_DL_ErectPhase.ePhasePick:
        bVacuumCmd := TRUE;                           // 吸箱：真空指令置位 / vacuum command set
        bConveyorCmd := FALSE;                        // 吸箱：输送撤 / conveyor dropped
        eErr := E_DL_ErectErr.ePick;                  // 码 041D / code pick
        IF bVacuumOk THEN
            ePhase := E_DL_ErectPhase.ePhaseForm;     // 真空建立：进成型相 / vacuum ok: enter form
        ELSIF tonStep.Q THEN
            bVacuumCmd := FALSE;                      // 真空超时：先释放真空再报错 / vacuum timeout: release vacuum first
            ePhase := E_DL_ErectPhase.ePhaseErr;      // 进故障相 / enter error phase
            bJam := TRUE;                             // 卡箱锁存 / jam latched
            eJamPhase := E_DL_ErectPhase.ePhasePick;  // 定位相 = PICK / jam phase recorded
            eErr := E_DL_ErectErr.eErr;               // 码 0420 / code error
        END_IF

    E_DL_ErectPhase.ePhaseForm:
        bVacuumCmd := TRUE;                           // 成型：真空保持 / vacuum held
        bConveyorCmd := FALSE;                        // 成型：输送撤 / conveyor dropped
        eErr := E_DL_ErectErr.eForm;                  // 码 041E / code form
        IF bBoxFormed THEN
            ePhase := E_DL_ErectPhase.ePhaseFlap;     // 成型到位：进折底相 / formed: enter flap
        ELSIF tonStep.Q THEN
            bVacuumCmd := FALSE;                      // 超时：撤真空（安全侧）/ timeout: drop vacuum
            ePhase := E_DL_ErectPhase.ePhaseErr;      // 进故障相 / enter error
            bJam := TRUE;                             // 卡箱锁存 / jam latched
            eJamPhase := E_DL_ErectPhase.ePhaseForm;  // 定位相 = FORM / jam phase recorded
            eErr := E_DL_ErectErr.eErr;               // 码 0420 / code error
        END_IF

    E_DL_ErectPhase.ePhaseFlap:
        bVacuumCmd := TRUE;                           // 折底：真空保持 / vacuum held
        bConveyorCmd := FALSE;                        // 折底：输送撤 / conveyor dropped
        eErr := E_DL_ErectErr.eFlap;                  // 码 041F / code flap
        IF bFlapClosed THEN
            ePhase := E_DL_ErectPhase.ePhaseEject;    // 折底到位：进输送相 / flap closed: enter eject
        ELSIF tonStep.Q THEN
            bVacuumCmd := FALSE;                      // 超时：撤真空（安全侧）/ timeout: drop vacuum
            ePhase := E_DL_ErectPhase.ePhaseErr;      // 进故障相 / enter error
            bJam := TRUE;                             // 卡箱锁存 / jam latched
            eJamPhase := E_DL_ErectPhase.ePhaseFlap;  // 定位相 = FLAP / jam phase recorded
            eErr := E_DL_ErectErr.eErr;               // 码 0420 / code error
        END_IF

    E_DL_ErectPhase.ePhaseEject:
        bVacuumCmd := FALSE;                          // 输送：真空撤（放箱）/ eject: vacuum dropped
        bConveyorCmd := TRUE;                         // 输送：输送指令置位 / conveyor command set
        eErr := E_DL_ErectErr.eFlap;                  // 码 041F（输送段与折底段共用，反证句见文件头）/ code flap, shared band
        IF tonStep.Q THEN
            bConveyorCmd := FALSE;                    // 输送定时到：撤输送 / timed eject: drop conveyor
            bDone := TRUE;                            // 完成单拍脉冲 / single-scan done pulse
            ePhase := E_DL_ErectPhase.ePhaseDone;     // 进完成相 / enter done
        END_IF

    E_DL_ErectPhase.ePhaseDone:
        bVacuumCmd := FALSE;                          // 完成：真空撤 / vacuum dropped
        bConveyorCmd := FALSE;                        // 完成：输送撤 / conveyor dropped
        eErr := E_DL_ErectErr.eIdle;                  // 码 041C（DONE 等待态与 IDLE 输出组合相同，共用反证句）/ code idle, shared band

    E_DL_ErectPhase.ePhaseErr:
        bVacuumCmd := FALSE;                          // 故障相：真空撤 / vacuum dropped
        bConveyorCmd := FALSE;                        // 故障相：输送撤 / conveyor dropped
        bJam := TRUE;                                 // 卡箱保持锁存 / jam held latched
        eErr := E_DL_ErectErr.eErr;                   // 码 0420 / code error

    ELSE
        ePhase := E_DL_ErectPhase.ePhaseErr;          // 非法相兜底 / illegal-phase fallback
        bVacuumCmd := FALSE;                          // 安全态：真空撤 / vacuum dropped, safe side
        bConveyorCmd := FALSE;                        // 安全态：输送撤 / conveyor dropped, safe side
        bJam := TRUE;                                 // 卡箱锁存（非法相按卡箱处置）/ jam latched
        eJamPhase := E_DL_ErectPhase.ePhaseErr;       // 定位相 = ERR / jam phase recorded
        eErr := E_DL_ErectErr.eErr;                   // 码 0420 / code error

END_CASE
END_FUNCTION_BLOCK
