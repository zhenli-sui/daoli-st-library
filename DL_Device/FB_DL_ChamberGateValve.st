//==============================================================================
// 功能块：FB_DL_ChamberGateValve ｜ 中文名称：真空腔体闸阀双位置互锁驱动
// 所属子库：DL_Device ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：真空腔体闸阀驱动——开/关到位双反馈确认、抽气侧联锁（抽气中
//           禁开）、双反馈/双命令矛盾防御、移动态超时保护；双输出互斥
//           断言（任一拍 NOT(bOpenOut AND bCloseOut)）结构性成立。
// 开源溯源 (Origin)：道莅 clean-room 防御性实现
// 单位表：阀状态[—]／反馈/命令[—]／超时[ms]
// 错误码表：16#0003_017E 信息级（开/关命令同拍，拒绝并执行关优先——安全
//           侧，不置 bError）/ 16#0003_017F 信息级（抽气中收到开命令，
//           拒绝，不置 bError）/ 16#0003_034E 故障级（双到位反馈同拍为
//           TRUE，到位矛盾，输出全断，置 bError）/ 16#0003_034F 故障级
//           （移动态超时无反馈，输出全断，置 bError）/ 16#0003_0350 故障
//           级兜底（状态机落 ELSE，置 bError）
// 状态机：E_DL_GateValveState（eIdle=0 / eOpening=10 / eClosing=20 /
//           eOpened=30 / eClosed=40 / eFault=99；六态，移动语义按方向
//           拆分为 eOpening/eClosing，对应派单摘要中的 eMoving），CASE 含
//           ELSE 兜底，ELSE 置 0350 并回 eFault
// 边界行为：① 双反馈同拍 TRUE → 故障 034E、输出全断（任何命令都不再
//           输出，直至矛盾消失）；② 双命令同拍 TRUE → 拒绝 + 信息 017E
//           （关优先）；③ 抽气中收到开命令 → 拒绝 + 信息 017F；④ 移动态
//           超时无反馈 → 故障 034F + 输出全断；⑤ 双输出互斥由 IF/ELSE
//           单源赋值结构保证，无显式互斥代码路径。
// 依赖纪律：仅 Standard.library；零同层/跨层调用。
// 修订历史：v1.0.0 2026-11-17 首版（R23 派单 · ROADMAP 半导体 P1 §424）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_GateValveState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 闸阀驱动相位，每个成员在 CASE 中有且仅有一个标签。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_GateValveState :
(
    eIdle    := 0,   // 待机：无命令，输出全断 / Idle, no command, outputs off
    eOpening := 10,  // 开启中：开输出有效，等开到位反馈 / Opening, waiting for the open feedback
    eClosing := 20,  // 关闭中：关输出有效，等关到位反馈 / Closing, waiting for the closed feedback
    eOpened  := 30,  // 已开到位：开反馈确认 / Opened, open feedback confirmed
    eClosed  := 40,  // 已关到位：关反馈确认 / Closed, closed feedback confirmed
    eFault   := 99   // 故障：矛盾/超时/非法状态，输出全断 / Fault, contradiction, timeout or illegal state, outputs off
);
END_TYPE

FUNCTION_BLOCK FB_DL_ChamberGateValve
VAR_INPUT
    bOpenCmd       : BOOL;                  // 开阀命令 [—]，电平有效 / Open command, level active
    bCloseCmd      : BOOL;                  // 关阀命令 [—]，电平有效 / Close command, level active
    bOpenedFb      : BOOL;                  // 开到位反馈 [—] / Opened-position feedback
    bClosedFb      : BOOL;                  // 关到位反馈 [—] / Closed-position feedback
    bPumpingActive : BOOL;                  // 抽气进行中 [—]，抽气中禁开（联锁源） / Pumping active, opening forbidden while pumping
    tFbTimeout     : TIME := T#5S;          // 移动态反馈超时 [ms] / Moving-state feedback timeout [ms]
    bReset         : BOOL;                  // 故障复位 [—]，上升沿退出 eFault / Fault reset, rising edge leaves the fault state
END_VAR
VAR_OUTPUT
    bOpenOut       : BOOL;                  // 开阀输出 [—] / Open output
    bCloseOut      : BOOL;                  // 关阀输出 [—] / Close output
    eValveState    : E_DL_GateValveState;   // 阀相位 [—] / Valve phase
    eErr           : UDINT;                 // 错误码，0 = 无错 / Error code, 0 = no error
    bError         : BOOL;                  // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid         : BOOL;                  // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbMove         : TON;                   // 移动态反馈超时计时，段 6 无条件刷新 [ms] / Moving feedback timeout
    _eState        : E_DL_GateValveState := E_DL_GateValveState.eIdle; // 当前相位 / Current phase
    _bInit         : BOOL := FALSE;         // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
    _bFbContradict : BOOL;                  // 双反馈矛盾当拍标志 / Both-feedback contradiction flag
    _bIllegal      : BOOL;                  // 非法状态标志 / Illegal state flag
    _bRejectInfo   : UINT;                  // 拒绝信息码暂存（0 = 无） / Staged rejection info code, zero for none
END_VAR
VAR CONSTANT
    DL_GV_CODE_REJ_BOTH : UINT := 1;        // 双命令拒绝标记 [—] / Rejection marker for dual commands
    DL_GV_CODE_REJ_PUMP : UINT := 2;        // 抽气联锁拒绝标记 [—] / Rejection marker for the pumping interlock
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：双输出先全断（安全侧），单拍标志预清零
 *      Both outputs cleared first, fail-safe, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
bOpenOut  := FALSE;                         // 开阀输出先清（安全侧） / Open output cleared first
bCloseOut := FALSE;                         // 关阀输出先清（安全侧） / Close output cleared first
eErr      := 16#0000_0000;                  // 错误码每拍重算 / Error code recomputed
bError    := FALSE;                         // 故障标志每拍重算 / Fault flag recomputed
bValid    := FALSE;                         // 可用标志每拍重算 / Usable flag recomputed
_bFbContradict := FALSE;                    // 矛盾标志预清零 / Contradiction flag pre-cleared
_bIllegal := FALSE;                         // 非法状态标志预清零 / Illegal flag pre-cleared
_bRejectInfo := 0;                          // 拒绝标记预清零 / Rejection marker pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState := E_DL_GateValveState.eIdle;   // 相位待机起步 / Phase starts idle
    _bInit  := TRUE;                        // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜到位矛盾闸：双反馈同拍 TRUE → 故障 034E 输出全断
 *      Contradiction gate: both position feedbacks TRUE at the same scan
 *-----------------------------------------------------------------------------*)
IF bOpenedFb AND bClosedFb THEN
    _bFbContradict := TRUE;                 // 到位矛盾当拍成立 / Contradiction active this scan
    _eState := E_DL_GateValveState.eFault;  // 转故障态 / Go to the fault state
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜命令防御闸：双命令 → 关优先拒绝；抽气中开命令 → 拒绝
 *      Command defense gates: close priority and the pumping interlock
 *-----------------------------------------------------------------------------*)
IF bOpenCmd AND bCloseCmd THEN
    _bRejectInfo := DL_GV_CODE_REJ_BOTH;    // 双命令拒绝标记 / Dual-command rejection marker
ELSIF bOpenCmd AND bPumpingActive THEN
    _bRejectInfo := DL_GV_CODE_REJ_PUMP;    // 抽气联锁拒绝标记 / Pumping interlock rejection marker
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜移动态超时计时无条件刷新（R40：CASE 之外每拍必调）
 *      Moving timeout refreshed unconditionally per R40
 *-----------------------------------------------------------------------------*)
fbMove(IN := (_eState = E_DL_GateValveState.eOpening)
             OR (_eState = E_DL_GateValveState.eClosing), PT := tFbTimeout); // 移动态反馈超时 / Moving feedback timeout

(*------------------------------------------------------------------------------
 * 段 6｜相位机（只做迁移；输出在段 7 按相置位）
 *      Phase machine, transitions only, outputs assigned in segment seven
 *-----------------------------------------------------------------------------*)
IF NOT _bFbContradict THEN                  // 矛盾当拍冻结相位机 / The machine freezes while the contradiction holds
CASE _eState OF

    E_DL_GateValveState.eIdle:             // 待机：合法命令进入移动态
        IF bCloseCmd AND (NOT bOpenCmd) THEN
            _eState := E_DL_GateValveState.eClosing; // 关命令生效 / Close command accepted
        ELSIF bOpenCmd AND (NOT bCloseCmd) AND (NOT bPumpingActive) THEN
            _eState := E_DL_GateValveState.eOpening; // 开命令生效（抽气中不开） / Open command accepted, not while pumping
        END_IF

    E_DL_GateValveState.eOpening:          // 开启中：到位确认或超时
        IF bOpenedFb THEN
            _eState := E_DL_GateValveState.eOpened;  // 开到位 / Opened confirmed
        ELSIF bCloseCmd AND (NOT bOpenCmd) THEN
            _eState := E_DL_GateValveState.eClosing; // 移动中反向，允许（安全侧就近停） / Reverse while moving, allowed
        ELSIF fbMove.Q THEN
            _eState := E_DL_GateValveState.eFault;   // 超时无反馈，故障全断 / Timeout, fault with outputs off
        END_IF

    E_DL_GateValveState.eClosing:          // 关闭中：到位确认或超时
        IF bClosedFb THEN
            _eState := E_DL_GateValveState.eClosed;  // 关到位 / Closed confirmed
        ELSIF bOpenCmd AND (NOT bCloseCmd) AND (NOT bPumpingActive) THEN
            _eState := E_DL_GateValveState.eOpening; // 移动中反向，允许（抽气联锁仍生效） / Reverse while moving, interlock still applied
        ELSIF fbMove.Q THEN
            _eState := E_DL_GateValveState.eFault;   // 超时无反馈，故障全断 / Timeout, fault with outputs off
        END_IF

    E_DL_GateValveState.eOpened:           // 已开：关命令即转关闭
        IF bCloseCmd THEN
            _eState := E_DL_GateValveState.eClosing; // 关命令生效 / Close command accepted
        END_IF

    E_DL_GateValveState.eClosed:           // 已关：开命令须过抽气联锁
        IF bOpenCmd AND (NOT bPumpingActive) THEN
            _eState := E_DL_GateValveState.eOpening; // 开命令生效 / Open command accepted
        END_IF

    E_DL_GateValveState.eFault:            // 故障：矛盾消失且复位沿才回待机
        IF bReset AND (NOT bOpenedFb) AND (NOT bClosedFb) THEN
            _eState := E_DL_GateValveState.eIdle;    // 原因消失回待机 / The cause is gone, back to idle
        END_IF

    ELSE                                   // 非法状态兜底（R21：CASE 必带 ELSE）
        _bIllegal := TRUE;                 // 标记非法状态 / Flag the illegal state
        _eState   := E_DL_GateValveState.eFault; // 回故障态（安全侧全断） / Back to fault, fail-safe
END_CASE
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜输出置位：IF/ELSE 单源赋值，双输出互斥结构性成立
 *      Output assignment, mutual exclusion holds structurally
 *-----------------------------------------------------------------------------*)
CASE _eState OF
    E_DL_GateValveState.eOpening:          // 开启中：只给开输出 / Opening: only the open output
        bOpenOut := TRUE;                  // 开阀输出 / Open output
    E_DL_GateValveState.eClosing:          // 关闭中：只给关输出 / Closing: only the close output
        bCloseOut := TRUE;                 // 关阀输出 / Close output
    ELSE                                   // 其余相输出全断（含故障） / Otherwise all off, including fault
        bOpenOut  := FALSE;                // 开阀输出断 / Open output off
        bCloseOut := FALSE;                // 关阀输出断 / Close output off
END_CASE

IF _bIllegal THEN
    eErr   := 16#0003_0350;                // 故障级：状态机兜底 / Fault: state machine fallback
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bFbContradict THEN
    eErr   := 16#0003_034E;                // 故障级：双反馈到位矛盾 / Fault: both-feedback contradiction
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF (_eState = E_DL_GateValveState.eFault) THEN
    eErr   := 16#0003_034F;                // 故障级：移动态超时无反馈 / Fault: moving timeout without feedback
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bRejectInfo = DL_GV_CODE_REJ_BOTH THEN
    eErr := 16#0003_017E;                  // 信息级：双命令拒绝，关优先 / Info: dual commands rejected, close priority
ELSIF _bRejectInfo = DL_GV_CODE_REJ_PUMP THEN
    eErr := 16#0003_017F;                  // 信息级：抽气中开命令拒绝 / Info: open command rejected while pumping
END_IF

bValid := NOT bError;                      // 故障级输出不可用 / Outputs unusable on fault
END_FUNCTION_BLOCK
