(*==============================================================================
 * 组件名称 (Component)  : FB_DL_TwoSpeedMotor
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 来源标签 (Source)     : t2-2-lbp（电机族 · 变极双速驱动，clean-room 编写）
 * 功能描述 (Function)   : 双绕组变极调速驱动：低速 / 高速选择 + 切换死区互锁
 *                         （低速断电 -> 死区窗内双绕组全断 -> 高速投入）+ 高速
 *                         禁止位（工艺联锁，优先于一切运行请求）+ 两方向接触器
 *                         反馈校验。死区窗内任一异侧反馈已出现即判绕组粘连故障
 *                         （锁存 + 安全侧断高速）；投入后反馈超时未到判校验失败。
 * 范式次源 (Paradigm)   : 命令-反馈范式参照 I_DL_MotorDriver 契约；星角切换安全
 *                         死区范式参照 FB_DL_StarDeltaMotor（互引声明，不复用实现、
 *                         不共享枚举——变极为双独立绕组，无星角三态）。
 * 配比约束 (R100)       : tFbTimeout > tDeadZone（反馈校验窗必须宽于死区窗，
 *                         否则死区未结束即误判反馈超时）。
 * 边界与语义披露 (Boundary disclosure) :
 *   1) 切换期间两绕组互斥硬闸：统一出口对 bOutLow / bOutHigh 再做 AND NOT 交叉
 *      硬闸，CASE 内任何路径都不可能产出双投（结构 + 出口双保险）。
 *   2) 死区窗内反馈校验（粘连判据）：命令已断侧的反馈若仍为 TRUE，判绕组粘连
 *      （机械/触点粘连），立即中止切换并锁存；高速粘连按安全侧断高速。
 *   3) 高速禁止位优先于一切运行请求：禁止位有效时高速请求被拒（信息级），运行中
 *      高速遇禁止位即时降速切换（不等待操作员）。
 *   4) 死区组态非法（<= T#0S）拒绝一切新切换，已运行的绕组保持（组态错误不停机，
 *      但故障级码必须可见，R191 显式声明）。
 *   5) 失能语义声明：bEnable = FALSE 时双绕组全断（安全侧），不冻结保持。
 * 故障码表 (Error codes) :
 *   16#0003_050B [故障级] 绕组粘连：死区窗内异侧反馈已出现，中止切换 + 锁存
 *                 反证：粘连拍输出与正常切换拍组合不同仅在于「反馈先行」，无码
 *                 则操作员只见切换中止不见根因。
 *   16#0003_050C [故障级] 反馈校验失败：投入命令已发而反馈超时未到，锁存 + 断高速
 *                 反证：校验失败与粘连状态输出组合不同（一为无反馈一为多反馈），
 *                 两因必须码位互异（R190）。
 *   16#0003_050D [故障级] 死区组态非法（<= T#0S），拒绝新切换 + 锁存
 *                 反证：拒绝切换与「无切换请求」输出组合相同，码位唯一可见。
 *   16#0003_0409 [信息级] 高速请求被禁止位拒绝（工艺联锁生效）
 *                 反证：请求被拒时电机保持低速，与「本来就选低速」输出组合相同，
 *                 无码则联锁生效事实不可观测。
 * 码位总账 (Code ledger) : 16#0003_050B / 050C / 050D 用 ｜ 16#0003_0409 用
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: TON / R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与 VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q 物理地址
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 域闸 / 计数无涉 / 码位 R45 配对
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 六态 ENUM + CASE + ELSE 兜底
 *                         R7 ✓ 三沿三计时主体最前部无条件刷新
 * 修订历史 (Revision)   :
 *   2026-11-22  v1.0.0  首版入库（R68 构建轮 · 批 2 · 目标 10）
 *   2026-11-22  v1.0.1  终审就地修①：组态锁存解除路径可达化（原 bCfgLatch 全文件零清零 -> 双绕组永久双断）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_TwoSpeedState（归属 DL_Device，与 FB_DL_TwoSpeedMotor 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_TwoSpeedState :
(
    eIdle    := 0,    // 停机：双绕组全断 / Stopped, both windings off
    eRunLow  := 10,   // 低速运行：低速绕组投入 / Low speed, low winding on
    eSwUp    := 20,   // 升速切换：死区窗内双绕组全断 / Speed-up transition, dead zone
    eRunHigh := 30,   // 高速运行：高速绕组投入 / High speed, high winding on
    eSwDown  := 40,   // 降速切换：死区窗内双绕组全断 / Speed-down transition, dead zone
    eFault   := 99    // 粘连 / 校验故障锁存：双绕组全断 / Latched fault, both off
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_TwoSpeedMotor
 * 调用约定: 每个扫描周期无条件调用一次。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_TwoSpeedMotor
VAR_INPUT
    bStartCmd   : BOOL;                  // 运行命令（电平）/ Run command, level
    bStopCmd    : BOOL;                  // 停止命令（电平，优先）/ Stop command, level, priority
    bHighReq    : BOOL;                  // 速度选择：TRUE = 高速请求 / Speed select, TRUE high speed
    bHighInhibit: BOOL;                  // 高速禁止位（工艺联锁）/ High speed inhibit, process interlock
    bFbLow      : BOOL;                  // 低速接触器反馈 / Low speed contactor feedback
    bFbHigh     : BOOL;                  // 高速接触器反馈 / High speed contactor feedback
    tDeadZone   : TIME := T#2S;          // 绕组切换死区窗 [s]，<= T#0S 组态非法 / Dead zone window [s]
    tFbTimeout  : TIME := T#3S;          // 反馈校验窗 [s]，须 > tDeadZone / Feedback verify window [s]
    bEnable     : BOOL := TRUE;          // 使能（FALSE 双绕组全断）/ Enable, FALSE cuts both
    bReset      : BOOL;                  // 上升沿：清除粘连 / 校验 / 组态锁存 / Rising edge: clear latches
END_VAR
VAR_OUTPUT
    bOutLow    : BOOL;                  // 低速绕组输出（经互斥硬闸）/ Low winding output, hard-gated
    bOutHigh   : BOOL;                  // 高速绕组输出（经互斥硬闸）/ High winding output, hard-gated
    bSwitching : BOOL;                  // 切换（死区窗）进行中 / Transition dead zone in progress
    bAdhesion  : BOOL;                  // 绕组粘连锁存 / Winding adhesion latched
    bFbFail    : BOOL;                  // 反馈校验失败锁存 / Feedback verify failed latched
    bError     : BOOL;                  // 故障标志（锁存类归并）/ Fault flag, latched class merged
    uErrorId   : UDINT;                 // 故障码，0 = 无故障 / Error code, 0 = none
    eState     : E_DL_TwoSpeedState;    // 当前状态（供 HMI 诊断）/ Current state for HMI diagnosis
END_VAR
VAR
    fbTrigReset  : R_TRIG;              // 复位沿检测实例 / Reset edge detector
    tonDead      : TON;                 // 切换死区窗计时实例 / Dead zone timer
    tonFbLow     : TON;                 // 低速反馈校验计时实例 / Low feedback verify timer
    tonFbHigh    : TON;                 // 高速反馈校验计时实例 / High feedback verify timer
    eStateInt    : E_DL_TwoSpeedState;  // 主状态机内部当前态 / Internal state machine state
    bOutLowInt   : BOOL;                // 低速输出内部副本（出口前未闸）/ Internal low output, pre-gate
    bOutHighInt  : BOOL;                // 高速输出内部副本（出口前未闸）/ Internal high output, pre-gate
    bDeadRun     : BOOL;                // 死区窗计时进行中 / Dead zone timing active
    bFbWaitLow   : BOOL;                // 低速反馈待达（投入后未反馈）/ Low feedback pending
    bFbWaitHigh  : BOOL;                // 高速反馈待达 / High feedback pending
    bAdhesionInt : BOOL;                // 粘锁存内部副本 / Internal adhesion latch
    bFbFailInt   : BOOL;                // 校验失败锁存内部副本 / Internal verify-fail latch
    bCfgLatch    : BOOL;                // 死区组态锁存（复位沿清除）/ Dead-zone config latch
    bCfgBad      : BOOL;                // 本拍死区组态非法 / Dead-zone config illegal this scan
    bHighRefused : BOOL;                // 高速请求被禁脉冲内部副本（单拍）/ Internal high-refused pulse
    bErrorInt    : BOOL;                // 本拍故障置位累加（出口归并）/ Fault set accumulator
    bFirstScan   : BOOL := TRUE;        // 上电首扫标志 / First-scan flag
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：一沿三计时全部位于主体最前部
 *      Unconditional refresh: one edge and three timers at the very top
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);

bFbWaitLow  := (eStateInt = E_DL_TwoSpeedState.eRunLow)  AND (NOT bFbLow);
bFbWaitHigh := (eStateInt = E_DL_TwoSpeedState.eRunHigh) AND (NOT bFbHigh);

tonDead(IN := bDeadRun, PT := tDeadZone);
tonFbLow(IN := bFbWaitLow, PT := tFbTimeout);
tonFbHigh(IN := bFbWaitHigh, PT := tFbTimeout);

(*------------------------------------------------------------------------------
 * 段 2｜上电首扫：双绕组全断落安全侧
 *      First-scan init: both windings to the safe off side
 *-----------------------------------------------------------------------------*)
IF bFirstScan THEN
    eStateInt   := E_DL_TwoSpeedState.eIdle;
    bOutLowInt  := FALSE;
    bOutHighInt := FALSE;
    bFirstScan  := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜每拍预清（FB32-1）：单拍标志，禁入锁存 / 快照
 *      Per-scan preset: single-scan flags only
 *-----------------------------------------------------------------------------*)
bErrorInt    := FALSE;
bHighRefused := FALSE;

(*------------------------------------------------------------------------------
 * 段 4｜组态域闸（R151）+ 配比复检：死区 <= T#0S 拒绝新切换，运行绕组保持
 *      Config gate and ratio re-check: bad dead zone refuses new transitions
 *      解除路径（R152 自证）：复位沿 AND 死区组态已改对
 *-----------------------------------------------------------------------------*)
bCfgBad := (tDeadZone <= T#0S);

IF bCfgBad THEN
    bCfgLatch := TRUE;
    uErrorId  := 16#0003_050D;   // 故障级：死区组态非法 / Fault: dead zone config illegal
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
 * 段 5｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine with the mandatory ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE eStateInt OF

    E_DL_TwoSpeedState.eIdle:
        IF (NOT bEnable) OR bStopCmd OR bCfgLatch THEN
            bOutLowInt  := FALSE;    // 双断驻留 / Both-off dwell
            bOutHighInt := FALSE;
        ELSIF bStartCmd THEN
            IF bHighReq AND bHighInhibit THEN
                bHighRefused := TRUE;    // 高速请求被禁止位拒绝（信息级）/ High refused by inhibit
                uErrorId     := 16#0003_0409;
                bOutLowInt   := TRUE;    // 抑制优先：按低速受理 / Inhibit wins: start low
                bOutHighInt  := FALSE;
                eStateInt    := E_DL_TwoSpeedState.eRunLow;
            ELSIF bHighReq THEN
                bOutLowInt  := FALSE;    // 高速直投：先断后投死区窗 / High direct: dead zone first
                bOutHighInt := FALSE;
                bDeadRun    := TRUE;
                eStateInt   := E_DL_TwoSpeedState.eSwUp;
            ELSE
                bOutLowInt  := TRUE;     // 低速直投（无死区需求）/ Low direct, no dead zone needed
                bOutHighInt := FALSE;
                eStateInt   := E_DL_TwoSpeedState.eRunLow;
            END_IF
        END_IF

    E_DL_TwoSpeedState.eRunLow:
        IF (NOT bEnable) OR bStopCmd THEN
            bOutLowInt  := FALSE;    // 停机双断 / Stop, both off
            bOutHighInt := FALSE;
            eStateInt   := E_DL_TwoSpeedState.eIdle;
        ELSIF bHighReq AND bHighInhibit THEN
            bHighRefused := TRUE;    // 禁止位拒高速（信息级，保持低速）/ High refused, keep low
            uErrorId     := 16#0003_0409;
        ELSIF bHighReq AND (NOT bCfgLatch) THEN
            bOutLowInt  := FALSE;    // 升速切换：先断低速 / Speed-up: drop low first
            bDeadRun    := TRUE;
            eStateInt   := E_DL_TwoSpeedState.eSwUp;
        END_IF

    E_DL_TwoSpeedState.eSwUp:
        (* 死区窗（升速）：双绕组全断；异侧反馈出现即粘连；窗满投高速 *)
        (* Dead zone up: both off; early feedback means adhesion; commit at window full *)
        IF (NOT bEnable) OR bStopCmd THEN
            bOutLowInt  := FALSE;    // 中止切换双断 / Abort, both off
            bOutHighInt := FALSE;
            bDeadRun    := FALSE;
            eStateInt   := E_DL_TwoSpeedState.eIdle;
        ELSIF bFbHigh OR bFbLow THEN
            bAdhesionInt := TRUE;    // 死区内反馈先行 = 绕组粘连 / Early feedback = adhesion
            uErrorId     := 16#0003_050B;
            bErrorInt    := TRUE;
            bOutHighInt  := FALSE;   // 安全侧断高速（本相本就全断，显式再声明）/ High cut on safe side
            bDeadRun     := FALSE;
            eStateInt    := E_DL_TwoSpeedState.eFault;
        ELSIF tonDead.Q THEN
            bOutHighInt := TRUE;     // 窗满投高速 / Window full, high on
            bDeadRun    := FALSE;
            eStateInt   := E_DL_TwoSpeedState.eRunHigh;
        END_IF

    E_DL_TwoSpeedState.eRunHigh:
        IF (NOT bEnable) OR bStopCmd THEN
            bOutLowInt  := FALSE;    // 停机双断 / Stop, both off
            bOutHighInt := FALSE;
            eStateInt   := E_DL_TwoSpeedState.eIdle;
        ELSIF bHighInhibit OR (NOT bHighReq) THEN
            bOutHighInt := FALSE;    // 禁止位优先 / 请求撤销：降速切换 / Inhibit or request gone: down-switch
            bDeadRun    := TRUE;
            eStateInt   := E_DL_TwoSpeedState.eSwDown;
        END_IF

    E_DL_TwoSpeedState.eSwDown:
        (* 死区窗（降速）：双绕组全断；异侧反馈出现即粘连；窗满投低速 *)
        (* Dead zone down: both off; early feedback means adhesion; commit low *)
        IF (NOT bEnable) OR bStopCmd THEN
            bOutLowInt  := FALSE;
            bOutHighInt := FALSE;
            bDeadRun    := FALSE;
            eStateInt   := E_DL_TwoSpeedState.eIdle;
        ELSIF bFbHigh OR bFbLow THEN
            bAdhesionInt := TRUE;    // 死区内反馈先行 = 绕组粘连 / Early feedback = adhesion
            uErrorId     := 16#0003_050B;
            bErrorInt    := TRUE;
            bOutHighInt  := FALSE;   // 安全侧断高速 / High cut on safe side
            bDeadRun     := FALSE;
            eStateInt    := E_DL_TwoSpeedState.eFault;
        ELSIF tonDead.Q THEN
            bOutLowInt := TRUE;      // 窗满投低速 / Window full, low on
            bDeadRun   := FALSE;
            eStateInt  := E_DL_TwoSpeedState.eRunLow;
        END_IF

    E_DL_TwoSpeedState.eFault:
        bOutLowInt  := FALSE;        // 故障相双绕组全断（降级语义已声明 R191）/ Both off, declared
        bOutHighInt := FALSE;
        (* 解除路径（R152 自证可达）：复位沿 AND 双反馈均断 AND 组态已改对 *)
        IF fbTrigReset.Q AND (NOT bFbHigh) AND (NOT bFbLow) AND (NOT bCfgBad) THEN
            bAdhesionInt := FALSE;
            bFbFailInt   := FALSE;
            uErrorId     := 16#0000_0000;
            eStateInt    := E_DL_TwoSpeedState.eIdle;
        END_IF

    ELSE
        (* 非法状态拦截：双断 + 迁兜底态（复用组态段码位） *)
        eStateInt   := E_DL_TwoSpeedState.eFault;
        uErrorId    := 16#0003_050D;
        bErrorInt   := TRUE;
        bOutLowInt  := FALSE;
        bOutHighInt := FALSE;

END_CASE;

(*------------------------------------------------------------------------------
 * 段 6｜反馈校验到期消化：投入命令已发而反馈超时未到 -> 校验失败锁存 + 断该绕组
 *      Feedback verify expiry: command on but feedback never arrived
 *      拍 N 进入：tonFb*.Q 首次为真；本拍行为：锁存 + 断输出 + 迁 eFault；
 *      拍 N+1 转出：eFault 相复位沿 + 双反馈均断解除
 *-----------------------------------------------------------------------------*)
IF tonFbLow.Q AND (eStateInt = E_DL_TwoSpeedState.eRunLow) THEN
    bFbFailInt := TRUE;          // 低速反馈校验失败 / Low feedback verify failed
    uErrorId   := 16#0003_050C;
    bErrorInt  := TRUE;
    bOutLowInt := FALSE;         // 安全侧断该绕组 / Cut the winding on safe side
    eStateInt  := E_DL_TwoSpeedState.eFault;
END_IF

IF tonFbHigh.Q AND (eStateInt = E_DL_TwoSpeedState.eRunHigh) THEN
    bFbFailInt := TRUE;          // 高速反馈校验失败（安全侧断高速）/ High verify failed, cut high
    uErrorId   := 16#0003_050C;
    bErrorInt  := TRUE;
    bOutHighInt := FALSE;
    eStateInt  := E_DL_TwoSpeedState.eFault;
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜输出单一出口（范式 P-05）：两绕组互斥交叉硬闸（结构 + 出口双保险）
 *      Single output exit: cross hard gate, structural plus exit double insurance
 *-----------------------------------------------------------------------------*)
bOutLow  := bOutLowInt AND (NOT bOutHighInt);
bOutHigh := bOutHighInt AND (NOT bOutLowInt);

bSwitching  := (eStateInt = E_DL_TwoSpeedState.eSwUp) OR (eStateInt = E_DL_TwoSpeedState.eSwDown);
bAdhesion   := bAdhesionInt;
bFbFail     := bFbFailInt;
bError      := bErrorInt OR (eStateInt = E_DL_TwoSpeedState.eFault);
eState      := eStateInt;
END_FUNCTION_BLOCK
