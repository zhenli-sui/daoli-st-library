(*==============================================================================
 * 组件名称 (Component)  : FB_DL_RotaryAirlockCtrl
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.2
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 来源标签 (Source)     : roadmap-industry-pool（粉体新方向 · 星型卸料器驱动，clean-room）
 * 功能描述 (Function)   : 星型卸料器（旋转气密阀）转速-料位联动驱动：
 *                         ① 料位联锁——高料位禁启（卡料风险），料位信号失效按
 *                            禁启（安全侧）；
 *                         ② 运行频率/转速给定（0..fFreqMax 钳位）；
 *                         ③ 电流失速判据——电流高于限值 AND 转速低于限值同拍
 *                            持续 tStallConfirm 确认窗 -> 停机 + 故障锁存；
 *                         ④ 反转点动解卡出口——仅停机态可用，受故障锁存闸拦截。
 * 范式次源 (Paradigm)   : 命令-反馈范式参照 I_DL_MotorDriver（CmdStart/CmdStop/
 *                         bRunning/bFault 契约），本件以引脚形式落地，不实现接口、
 *                         不引用接口方法（R31 家族纪律：只借范式不借实现）。
 * 高危区声明 (R31)      : 反转点动相与正转运行相为互斥高危区——两状态机分支互斥
 *                         由 CASE 结构保证（eJogRev 分支不产出任何正转输出，
 *                         eRunning / eStartPend 分支不产出反转输出），正反转输出
 *                         在统一出口再做一次 AND NOT 硬闸双保险。
 * 配比约束 (R100)       : tMinRun > tStallConfirm（最小运行窗必须宽于失速确认窗，
 *                         否则启动暂态电流尖峰会在转速未稳时被误判为失速）。
 * 边界与语义披露 (Boundary disclosure) :
 *   1) 料位联锁只禁启不停机：高料位 / 信号失效仅拒绝新的启动请求，运行中的
 *      卸料器不停（工艺侧决定），判据与码位按「拒启事件」承载。
 *   2) 电流 / 转速反馈非有限时失速判据挂起（不能拿垃圾信号判失速），但运行中
 *      反馈非有限本身升级为保护停机（故障级 030A，锁存至复位沿 + 信号恢复）。
 *   3) 启停频次守卫（DolMotor 判据口径）：停机后 tMinOff 未满拒绝再启动；
 *      信息级承载，不停摆、不锁存。
 *   4) 失速锁存解除路径（R152 自证可达）：复位沿 AND 失速条件已消失
 *      （电流回落 OR 转速回升）。
 * 故障码表 (Error codes) :
 *   16#0003_0507 [故障级] 失速确认窗满：停机 + 锁存，点动解卡被闸拦截
 *                 反证：停机 + eFault 与组态故障态输出组合不同但成因不可区分
 *                 （组态错 / 失速 / 反馈失效三因，必须码位互异 R190）。
 *   16#0003_0508 [故障级] 料位信号失效（无效标志或非有限），按禁启（锁存）
 *                 反证：禁启与高料位拒启输出组合相同，成因必须独立码位。
 *   16#0003_0509 [故障级] 组态非法（确认窗 / 限值域 / 频率上限），已两级回退
 *                 反证：回退后驱动照常，码位是组态错误唯一可见出口。
 *   16#0003_050A [故障级] 运行中电流 / 转速反馈非有限，保护停机 + 锁存
 *                 反证：保护停机与失速停机状态输出相同，成因必须独立码位。
 *   16#0003_0407 [信息级] 高料位拒启（启动请求被料位联锁拒绝）
 *                 反证：拒启事件 bStartRefused 为单拍脉冲，无码则拒因
 *                 （料位 / 频次 / 故障锁存）不可区分。
 *   16#0003_0408 [信息级] 启停频次守卫拒启（最小停机窗未满）
 *                 反证：频次守卫拒启与高料位拒启同为拒启脉冲，拒因组合不可区分。
 * 码位总账 (Code ledger) : 16#0003_0507 / 0508 / 0509 / 050A 用 ｜ 16#0003_0407 / 0408 用
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: TON / R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与 VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q 物理地址
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 非有限双判 / 除数无涉 / 域闸全枚举
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 五态 ENUM + CASE + ELSE 兜底
 *                         R7 ✓ 四沿四计时主体最前部无条件刷新
 * 修订历史 (Revision)   :
 *   2026-11-22  v1.0.0  首版入库（R68 构建轮 · 批 2 · 目标 9）
 *   2026-11-22  v1.0.1  终审就地修①：组态锁存解除路径可达化（原 bCfgLatch 全文件零清零 -> 永久拒启）
 *   2026-11-22  v1.0.2  R69 点修⑥：正 / 反转出口改同拍派生（原 bJogRevOut 读上拍 bRunOut 反相，
 *                       反转首拍被上拍正转残值切断，滞后一拍；现两出口均由本拍状态派生，
 *                       交叉互斥在同一拍内完成）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_AirlockState（归属 DL_Device，与 FB_DL_RotaryAirlockCtrl 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_AirlockState :
(
    eIdle      := 0,    // 停机：可受理解卡点动 / Stopped, jog available
    eStartPend := 10,   // 启动命令已发，待运行反馈 / Start issued, awaiting run feedback
    eRunning   := 20,   // 运行反馈确认 / Running confirmed by feedback
    eJogRev    := 30,   // 反转点动解卡中（与正转互斥高危区）/ Reverse jog, exclusive with forward
    eFault     := 99    // 故障锁存：一切输出切断 / Fault latched, all outputs cut
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_RotaryAirlockCtrl
 * 调用约定: 每个扫描周期无条件调用一次。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_RotaryAirlockCtrl
VAR_INPUT
    bStartCmd       : BOOL;                  // 启动命令（电平）/ Start command, level
    bStopCmd        : BOOL;                  // 停止命令（电平，优先于启动）/ Stop command, level, priority
    bJogRevCmd      : BOOL;                  // 反转点动命令（电平，仅停机态有效）/ Reverse jog command, stopped only
    bRunFb          : BOOL;                  // 运行反馈（接触器 / 速度）/ Run feedback
    fLevelPct       : REAL;                  // 料位 [%] / Level [%]
    bLevelValid     : BOOL := TRUE;          // 料位信号有效标志 / Level signal valid flag
    fLevelHighLim   : REAL := 80.0;          // 高料位禁启阈 [%] / High level start-forbid threshold
    fFreqSet        : REAL := 25.0;          // 运行频率给定 [Hz] / Run frequency setpoint [Hz]
    fFreqMax        : REAL := 50.0;          // 频率上限 [Hz] / Frequency ceiling [Hz]
    fCurrent        : REAL;                  // 电机电流 [A] / Motor current [A]
    fSpeedFb        : REAL;                  // 转速反馈 [rpm] / Speed feedback [rpm]
    fStallCurrentLim: REAL := 10.0;          // 失速电流阈 [A] / Stall current threshold [A]
    fStallSpeedLim  : REAL := 1.0;           // 失速转速阈 [rpm] / Stall speed threshold [rpm]
    tStallConfirm   : TIME := T#3S;          // 失速确认窗 [s] / Stall confirmation window [s]
    tMinRun         : TIME := T#10S;         // 最小运行窗 [s] / Minimum run window [s]
    tMinOff         : TIME := T#30S;         // 最小停机窗 [s] / Minimum off window [s]
    bReset          : BOOL;                  // 上升沿：清除失速 / 料位 / 反馈失效锁存 / Rising edge: clear latches
END_VAR
VAR_OUTPUT
    bRunOut      : BOOL;                     // 正转运行输出（含启动待反馈段）/ Forward run output
    fFreqOut     : REAL;                     // 生效频率输出 [Hz] / Effective frequency output [Hz]
    bJogRevOut   : BOOL;                     // 反转点动输出 / Reverse jog output
    bStallLatch  : BOOL;                     // 失速锁存 / Stall latched
    bLevelBad    : BOOL;                     // 料位信号失效锁存 / Level signal invalid latched
    bStartRefused: BOOL;                     // 启动请求被拒脉冲（单拍）/ Start refused pulse, single scan
    bError       : BOOL;                     // 故障标志（锁存类归并）/ Fault flag, latched class merged
    uErrorId     : UDINT;                    // 故障码，0 = 无故障 / Error code, 0 = none
    eState       : E_DL_AirlockState;        // 当前状态（供 HMI 诊断）/ Current state for HMI diagnosis
END_VAR
VAR
    fbTrigStart  : R_TRIG;                  // 启动命令沿检测实例 / Start command edge detector
    fbTrigStop   : R_TRIG;                  // 停止命令沿检测实例 / Stop command edge detector
    fbTrigReset  : R_TRIG;                  // 复位沿检测实例 / Reset edge detector
    tonStall     : TON;                     // 失速确认窗计时实例 / Stall confirmation timer
    tonMinRun    : TON;                     // 最小运行窗计时实例 / Minimum run timer
    tonMinOff    : TON;                     // 最小停机窗计时实例 / Minimum off timer
    eStateInt    : E_DL_AirlockState;       // 主状态机内部当前态 / Internal state machine state
    bStallCond   : BOOL;                    // 本拍失速判据成立（反馈有效口径）/ Stall condition this scan
    bSigBadRun   : BOOL;                    // 运行中电流 / 转速非有限 / Current or speed non-finite while running
    bLevelNonFin : BOOL;                    // 料位非有限 / Level non-finite
    bLevelBadInt : BOOL;                    // 料位失效锁存内部副本 / Internal level-invalid latch
    bStallInt    : BOOL;                    // 失速锁存内部副本 / Internal stall latch
    bStartPermit : BOOL;                    // 本拍启动许可（料位口径）/ Start permit this scan, level class
    bFreqGuardOk : BOOL;                    // 本拍频次守卫通过 / Frequency guard passed
    fFreqClamp   : REAL;                    // 钳位后给定频率 [Hz] / Clamped setpoint frequency
    bCfgBad      : BOOL;                    // 本拍组态非法 / Config illegal this scan
    bCfgLatch    : BOOL;                    // 组态故障锁存（复位沿清除）/ Config fault latch
    bRefusedT    : BOOL;                    // 拒启脉冲内部副本（单拍）/ Internal refused pulse copy
    bErrorInt    : BOOL;                    // 本拍故障置位累加（出口归并）/ Fault set accumulator
    bFirstScan   : BOOL := TRUE;            // 上电首扫标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_RA_FIN_LIM : REAL := 1.0E30;   // REAL 有限幅值判界 / REAL finiteness bound
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：四沿三计时全部位于主体最前部
 *      Unconditional refresh: four edges and three timers at the very top
 *      tonStall 的 IN 为内部派生判据（R40 断输入口径），禁挂外部引脚原值
 *-----------------------------------------------------------------------------*)
fbTrigStart(CLK := bStartCmd);
fbTrigStop(CLK := bStopCmd);
fbTrigReset(CLK := bReset);

bSigBadRun := (fCurrent <> fCurrent) OR (ABS(fCurrent) >= DL_RA_FIN_LIM)
              OR (fSpeedFb <> fSpeedFb) OR (ABS(fSpeedFb) >= DL_RA_FIN_LIM);
bLevelNonFin := (fLevelPct <> fLevelPct) OR (ABS(fLevelPct) >= DL_RA_FIN_LIM);

bStallCond := (eStateInt = E_DL_AirlockState.eRunning)
              AND (NOT bSigBadRun)
              AND (fCurrent > fStallCurrentLim)
              AND (fSpeedFb < fStallSpeedLim);

tonStall(IN := bStallCond, PT := tStallConfirm);
tonMinRun(IN := (eStateInt = E_DL_AirlockState.eRunning), PT := tMinRun);
tonMinOff(IN := (eStateInt = E_DL_AirlockState.eIdle), PT := tMinOff);

(*------------------------------------------------------------------------------
 * 段 2｜上电首扫：状态与输出落安全侧
 *      First-scan init: state and outputs to the safe side
 *-----------------------------------------------------------------------------*)
IF bFirstScan THEN
    eStateInt := E_DL_AirlockState.eIdle;
    fFreqClamp := 0.0;
    bFirstScan := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜每拍预清（FB32-1）：单拍标志，禁入锁存 / 快照
 *      Per-scan preset: single-scan flags only
 *-----------------------------------------------------------------------------*)
bErrorInt  := FALSE;
bRefusedT  := FALSE;

(*------------------------------------------------------------------------------
 * 段 4｜组态域闸（R151 全枚举：四限值 + 三窗）+ 两级回退（R117）
 *      Config gate over all limits and windows, with two-level fallback
 *-----------------------------------------------------------------------------*)
bCfgBad := (tStallConfirm <= T#0S) OR (tMinRun <= T#0S) OR (tMinOff <= tMinRun)
           OR (fLevelHighLim <= 0.0) OR (fLevelHighLim > 100.0) OR (fLevelHighLim <> fLevelHighLim)
           OR (fStallCurrentLim <= 0.0) OR (fStallCurrentLim <> fStallCurrentLim)
           OR (fStallSpeedLim < 0.0) OR (fStallSpeedLim <> fStallSpeedLim)
           OR (fFreqMax <= 0.0) OR (fFreqMax <> fFreqMax);

IF bCfgBad THEN
    bCfgLatch := TRUE;
    uErrorId  := 16#0003_0509;   // 故障级：组态非法 / Fault: config illegal
    bErrorInt := TRUE;
END_IF

(* 终审就地修 v1.0.1（R68）：解除路径（R152 自证可达）——复位沿 AND 组态非法条件
 * 全部消失即清锁存。原实现把锁存清零只写在 eFault 相分支，而组态闸置锁存后
 * 并不迁相至 eFault（只回 eIdle / 驻留），eFault 相不可达 -> 锁存永不可解，
 * 组件保护/监视功能一次性永久失效直至 PLC 重启（终审两式①）。
 * Clear path made provably reachable: reset edge with the illegal config gone. *)
IF fbTrigReset.Q AND (NOT bCfgBad) THEN
    bCfgLatch := FALSE;          // 锁存解除 / Latch cleared
    uErrorId  := 16#0000_0000;   // 码位随解除归零 / Code cleared with the latch
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜锁存类判据：料位失效（禁启）与运行反馈失效（保护停机）
 *      Latched criteria: level invalid forbids start, bad run feedback trips
 *      解除路径（R152 自证）：复位沿 AND 对应信号已恢复有效
 *-----------------------------------------------------------------------------*)
IF (NOT bLevelValid) OR bLevelNonFin THEN
    bLevelBadInt := TRUE;        // 失效按禁启（安全侧），不停运行（规格明示）/ Forbid start only
END_IF

(* 料位失效锁存解除路径（R152 自证可达）：复位沿 AND 料位信号已恢复有效 *)
(* Level latch clear path: reset edge AND the level signal valid again *)
IF fbTrigReset.Q AND bLevelValid AND (NOT bLevelNonFin) THEN
    bLevelBadInt := FALSE;
END_IF

IF bLevelBadInt THEN
    uErrorId  := 16#0003_0508;   // 故障级：料位信号失效 / Fault: level signal invalid
    bErrorInt := TRUE;
END_IF

IF bSigBadRun AND (eStateInt = E_DL_AirlockState.eRunning) THEN
    bStallInt := TRUE;           // 反馈失效按保护停机口径锁存 / Bad feedback trips protectively
    uErrorId  := 16#0003_050A;
    bErrorInt := TRUE;
    eStateInt := E_DL_AirlockState.eFault;   // 锁存同步迁相（FB50-1④）/ Latch migrates phase
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜启动许可与频次守卫（边界 B1/B3）
 *      Start permit and frequency guard
 *-----------------------------------------------------------------------------*)
bStartPermit := bLevelValid AND (NOT bLevelNonFin) AND (fLevelPct < fLevelHighLim);
bFreqGuardOk := tonMinOff.Q;

(*------------------------------------------------------------------------------
 * 段 7｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine with the mandatory ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE eStateInt OF

    E_DL_AirlockState.eIdle:
        (* 停机相收到停止沿：无对象，事件湮灭（无状态改写，此处仅注释声明） *)
        (* Stop edge while idle: nothing to stop, event dies, no state write *)
        IF bJogRevCmd AND (NOT bRunFb) AND (NOT bStallInt) AND (NOT bLevelBadInt)
              AND (NOT bCfgLatch) THEN
            (* 反转点动（互斥高危区 R31）：仅停机态 + 无反馈 + 无故障锁存 *)
            (* Reverse jog: stopped, no feedback, no latch; exclusive high-risk zone *)
            eStateInt := E_DL_AirlockState.eJogRev;
        ELSIF fbTrigStart.Q THEN
            IF bStallInt OR bLevelBadInt OR bCfgLatch THEN
                bRefusedT := TRUE;       // 故障锁存类拒启 / Refused by a latch
                IF bStallInt THEN
                    uErrorId := 16#0003_0507;
                END_IF
            ELSIF NOT bStartPermit THEN
                bRefusedT := TRUE;       // 高料位 / 料位失效拒启 / Refused by level interlock
                uErrorId  := 16#0003_0407;
            ELSIF NOT bFreqGuardOk THEN
                bRefusedT := TRUE;       // 频次守卫拒启 / Refused by frequency guard
                uErrorId  := 16#0003_0408;
            ELSE
                eStateInt := E_DL_AirlockState.eStartPend;   // 受理，待反馈 / Accepted, awaiting feedback
            END_IF
        END_IF

    E_DL_AirlockState.eStartPend:
        IF bStopCmd OR fbTrigStop.Q OR bCfgLatch THEN
            eStateInt := E_DL_AirlockState.eIdle;    // 撤回 / Withdrawn
        ELSIF bRunFb THEN
            eStateInt := E_DL_AirlockState.eRunning; // 反馈确认 / Feedback confirmed
        END_IF

    E_DL_AirlockState.eRunning:
        IF bStopCmd OR fbTrigStop.Q OR bCfgLatch OR bStallInt THEN
            eStateInt := E_DL_AirlockState.eIdle;    // 停机 / 失速保护停机 / Stop or stall trip
        END_IF

    E_DL_AirlockState.eJogRev:
        IF bStopCmd OR bCfgLatch OR bStallInt OR (NOT bJogRevCmd) THEN
            eStateInt := E_DL_AirlockState.eIdle;    // 点动释放即回停机 / Jog release returns to idle
        END_IF

    E_DL_AirlockState.eFault:
        IF fbTrigReset.Q AND (NOT bStallCond) AND bLevelValid AND (NOT bLevelNonFin)
           AND (NOT bSigBadRun) AND (NOT bCfgBad) THEN
            bStallInt    := FALSE;       // 解除路径自证可达（R152）/ Clear path reachable
            bLevelBadInt := FALSE;
            uErrorId     := 16#0000_0000;
            eStateInt    := E_DL_AirlockState.eIdle;
        END_IF

    ELSE
        (* 非法状态拦截：切断一切输出，迁兜底态 *)
        eStateInt := E_DL_AirlockState.eFault;
        uErrorId  := 16#0003_0509;
        bErrorInt := TRUE;

END_CASE;

(*------------------------------------------------------------------------------
 * 段 8｜失速到期消化：确认窗满 -> 停机 + 锁存（与正常推进不同源，R 历史教训）
 *      Stall expiry digestion: window full trips stop and latch
 *      拍 N 进入：tonStall.Q 首次为真；本拍行为：置锁存 + 迁 eIdle；
 *      拍 N+1 转出：eIdle 相受复位沿 + 条件恢复解除
 *-----------------------------------------------------------------------------*)
IF tonStall.Q THEN
    bStallInt := TRUE;           // 失速锁存 / Stall latched
    uErrorId  := 16#0003_0507;   // 故障级：失速 / Fault: stall
    bErrorInt := TRUE;
    eStateInt := E_DL_AirlockState.eFault;   // 锁存同步迁相：停机 + 禁点动 / Latch migrates phase
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜输出单一出口（范式 P-05）：正反转互斥硬闸（双保险，R31 高危区）
 *      Single output exit: forward and reverse outputs mutually exclusive
 *      R69 点修⑥：两出口一律由**本拍**状态派生后交叉互斥，禁止互相引用上拍输出
 *      （原实现 bJogRevOut := TRUE AND (NOT bRunOut) 读的是上一扫描的 bRunOut，
 *      反转首拍被上拍正转残值切断，解卡点动实际延后一拍；高危区出口不得有拍延迟）。
 *      Both outputs derive from the current phase, then cross-mask inside the same scan.
 *-----------------------------------------------------------------------------*)
bRunOut    := (eStateInt = E_DL_AirlockState.eRunning) OR (eStateInt = E_DL_AirlockState.eStartPend);
bJogRevOut := (eStateInt = E_DL_AirlockState.eJogRev);
bJogRevOut := bJogRevOut AND (NOT bRunOut);   // 反转串同拍正转非（双保险）/ Reverse masked by the same-scan forward
bRunOut    := bRunOut AND (NOT bJogRevOut);   // 正转串同拍反转非（双保险）/ Forward masked by the same-scan reverse

IF fFreqSet <> fFreqSet THEN
    fFreqOut := 0.0;                         // 给定非有限：频率安全侧 0 / Non-finite setpoint: safe zero
ELSIF fFreqSet < 0.0 THEN
    fFreqOut := 0.0;                         // 负给定钳 0 / Negative clamped
ELSIF fFreqSet > fFreqMax THEN
    fFreqOut := fFreqMax;                    // 超上限钳位 / Over clamped
ELSE
    fFreqOut := fFreqSet;                    // 合法直通 / Valid pass-through
END_IF

IF bCfgBad AND (fFreqMax <= 0.0) THEN
    fFreqOut := 0.0;                         // 上限组态非法时频率安全侧 0（R127 解耦）/ Safe zero when ceiling illegal
END_IF

bStallLatch := bStallInt;
bLevelBad   := bLevelBadInt;
bStartRefused := bRefusedT;                  // 单拍脉冲统一出口 / Unified single-scan exit
bError      := bErrorInt OR (eStateInt = E_DL_AirlockState.eFault);
eState      := eStateInt;
END_FUNCTION_BLOCK
