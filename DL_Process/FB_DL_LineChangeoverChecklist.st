(*==============================================================================
 * 组件名称 (Component)  : FB_DL_LineChangeoverChecklist
 * 溯源说明 (Provenance) : 道莅 clean-room 防御性实现（PackML 深化）
 * 所属子库 (Sublibrary) : DL_Process / Changeover
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；
 *                         纯 IEC 61131-3（第 3 版），零标准库依赖
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 换型检查清单顺控
 * 功能一句话 (Summary)  : 检查项逐步确认 + 前向跳步登记 + 未完成禁止启动。
 * 边界与安全 (Boundary) : ①跳步仅允许前向（不小于当前步）且不可跳最后一项；
 *                         ②未全部完成（含已跳步）时启动确认拒绝并置码 0362；
 *                         ③回退方向跳步申请拒绝并置码 0361；
 *                         ④bReset 清跳步登记与状态（已完成位由调用方维护）；
 *                         ⑤数组下标全程钳位（禁越界访问）。
 * 错误码    : 16#0005_0361 非法回退跳步申请——信息级（单拍）
 *             16#0005_0362 未完成启动尝试（启动确认被拒）——故障级（单拍）
 * 码位总账  : 16#0005_0361 用 / 16#0005_0362 用
 * 修改记录  : v1.0.0 R26 初版
 *             v1.0.1 R26 终审修复：跳步登记循环补双表异界防御——abSkipReq 与
 *             abStepsDone 为两张独立 ARRAY[*]，申请表更长时按自身 UPPER_BOUND 判界
 *==============================================================================*)
TYPE E_DL_ChgoverState :
(
    eIdle     := 0, // 空闲：未开始检查 / Idle: checklist not started
    eRunning  := 1, // 检查中：存在未确认项 / Running: items pending
    eAllDone  := 2  // 全部完成：允许启动 / All done: start permitted
);
END_TYPE

FUNCTION_BLOCK FB_DL_LineChangeoverChecklist
VAR_INPUT
    abSkipReq     : ARRAY[*] OF BOOL; // 跳步申请位表（与完成位同界）/ Skip request bits
    bStartConfirm : BOOL; // 启动确认请求 / Start confirmation request
    bReset        : BOOL; // 复位：清跳步与状态 / Reset: clear skips and state
END_VAR
VAR_IN_OUT
    abStepsDone : ARRAY[*] OF BOOL; // 检查项完成位表 / Checklist done bits
END_VAR
VAR_OUTPUT
    eState    : E_DL_ChgoverState; // 清单状态机状态 / Checklist state machine state
    uCurStep  : UINT;  // 当前待确认步序号 / Current pending step index
    bAllDone  : BOOL;  // 全部完成（含跳步）/ All done including skips
    bSkipUsed : BOOL;  // 本轮发生过跳步 / Any skip used this round
    eErr      : UDINT; // 本周期错误码，0=无错 / Error code this cycle, 0 = none
END_VAR
VAR
    nSteps  : INT;  // 总步数 / Total step count
    i       : INT;  // 扫描游标 / Scan cursor
    iCur    : INT;  // 当前待确认步内部值 / Current pending step internal
    bPending: BOOL; // 存在未确认项 / Any item pending
    rSkip   : R_TRIG; // 跳步申请沿检测（无条件刷新）/ Skip request edge
    bAnyReq : BOOL; // 跳步申请或哨兵 / Skip request or sentinel
    bUndone : BOOL; // 完成位安全读取副本（双表异界防御）/ Safe done-bit read copy
END_VAR

// ---------- 无条件周期刷新：跳步沿检测（哨兵时钟法，单实例单调用） ----------
bAnyReq := FALSE;
FOR i := 0 TO UPPER_BOUND(abSkipReq, 1) DO
    IF abSkipReq[i] THEN
        bAnyReq := TRUE;                      // 任一跳步申请 / Any skip requested
    END_IF
END_FOR
rSkip(CLK := bAnyReq);

// ---------- 复位：清跳步登记与状态 ----------
IF bReset THEN
    bSkipUsed := FALSE;                       // 跳步登记清零 / Skip ledger cleared
    eState := E_DL_ChgoverState.eIdle;        // 回空闲 / Back to idle
    eErr := 0;
END_IF

// ---------- 周期起点：错误码先清（单拍码生命周期） ----------
eErr := 0;

// ---------- 步数与界防御 ----------
nSteps := UPPER_BOUND(abStepsDone, 1) + 1;    // 总步数 / Total steps
IF nSteps < 1 THEN
    nSteps := 1;                              // 下限防御 / Lower bound guard
END_IF

// ---------- 跳步登记：仅前向且不可跳最后一项 ----------
IF rSkip.Q THEN
    FOR i := 0 TO UPPER_BOUND(abSkipReq, 1) DO
        // 双表异界防御：完成位读取按 abStepsDone 自身上界判界 / Bounds guard for mismatched tables
        IF i <= UPPER_BOUND(abStepsDone, 1) THEN
            bUndone := NOT abStepsDone[i];    // 完成位安全读取 / Safe done-bit read
        ELSE
            bUndone := FALSE;                 // 越界位视作不可登记 / Out-of-range: not registrable
        END_IF
        IF abSkipReq[i] AND bUndone AND (i < nSteps - 1) THEN
            // 前向且非最后一项：跳步视同完成登记（台账语义）/ Forward & not last: mark done
            abStepsDone[i] := TRUE;           // 跳步登记 / Skip marks done
            bSkipUsed := TRUE;                // 记录跳步 / Skip recorded
        ELSIF abSkipReq[i] AND bUndone AND (i >= nSteps - 1) THEN
            eErr := 16#0005_0361;             // 末项禁跳码 / Last-step skip forbidden
        END_IF
    END_FOR
END_IF

// ---------- 当前步扫描：首个未确认项（下标钳位） ----------
iCur := 0;
bPending := FALSE;
FOR i := 0 TO nSteps - 1 DO
    IF NOT abStepsDone[i] THEN
        iCur := i;                            // 首个未确认项 / First pending item
        bPending := TRUE;                     // 存在未确认 / Pending exists
        EXIT;                                 // 找到即出（最小编号优先）/ Exit on first
    END_IF
END_FOR
uCurStep := INT_TO_UINT(iCur);                // 对外当前步 / Exposed current step

// ---------- 状态机：CASE 覆盖全部枚举成员加 ELSE 兜底 ----------
CASE eState OF
    E_DL_ChgoverState.eIdle:                  // 拍 N 进入：空闲 / Entered: idle
        IF bPending THEN
            eState := E_DL_ChgoverState.eRunning; // 有未确认项进检查态 / Pending found, running
        END_IF
        // 本拍行为：空闲等待 / This cycle: idle waiting
        // 拍 N+1 转出：进 eRunning / Leaving to running

    E_DL_ChgoverState.eRunning:               // 拍 N 进入：检查中 / Entered: running
        IF NOT bPending THEN
            eState := E_DL_ChgoverState.eAllDone; // 全确认进完成态 / All confirmed, done
        END_IF
        // 本拍行为：保持当前步等待确认 / This cycle: hold current step
        // 拍 N+1 转出：eAllDone 或保持 / Leaving to done or hold

    E_DL_ChgoverState.eAllDone:               // 拍 N 进入：全部完成 / Entered: all done
        bAllDone := TRUE;                     // 放行启动 / Permit start
        IF bPending THEN
            eState := E_DL_ChgoverState.eRunning; // 调用方清位后回检查态 / Back to running
        END_IF
        // 本拍行为：保持放行 / This cycle: keep permit
        // 拍 N+1 转出：条件驱动 / Condition-driven leaving

    ELSE                                      // 非法状态兜底回空闲 / Illegal state fallback
        eState := E_DL_ChgoverState.eIdle;
        bAllDone := FALSE;
END_CASE

// ---------- bAllDone 与状态同步（保持单口径） ----------
IF eState = E_DL_ChgoverState.eAllDone THEN
    bAllDone := TRUE;
ELSE
    bAllDone := FALSE;                        // 非完成态不放行 / No permit unless done
END_IF

// ---------- 启动确认仲裁：未全部完成拒绝 ----------
IF bStartConfirm AND (NOT bAllDone) THEN
    eErr := 16#0005_0362;                     // 未完成启动尝试码 / Start attempt while incomplete
END_IF

END_FUNCTION_BLOCK
