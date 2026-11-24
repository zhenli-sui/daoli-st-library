(*
  FB_DL_TrackerAngleYearWin  —  跟踪支架年度角度表切换 / Tracker annual angle-table switching
  分类 Category : DL_Motion
  码位 Code     : 16#04_0_A1
  版本 Version  : 1.0.0
  溯源 Source   : LGF DateAndTimer 语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 年窗 + 月窗双闸同时生效才允许角度表切换（任一窗不开即禁止）；
                  2) 角度表切换仅在「双窗生效 + 支架静止」时执行；运动中切换排队到停止（bSwitchPending）；
                  3) 表版本号锁存，切换瞬间只给出新版本号单点，防半新半旧。
  边界 Boundary : ① 年窗/月窗参数越界钳位照算（报码不拒算）；
                  ② 仅在「双窗同时生效 + 支架静止」执行切换，运动中排队到停止；
                  ③ 表版本锁存防切换瞬间半新半旧；
                  ④ 输出三行同向：双窗标志 → 版本号 → 切换待决标志。
  依赖 Depends  : FB_DL_YearWindowCheck、FB_DL_MonthWindowCheck（均每拍无条件调用）

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_04A1 故障级：年窗组态非法（空窗/日期越界钳位后仍非法）
    16#0002_04B1 故障级：月窗组态非法（目标日为 0 或窗宽越界）
    16#0002_04C1 信息级：日期注入越界已钳位照算 / 运动中的切换排队（不置 bError）
*)

TYPE E_DL_TayPhase :
(
    eIdle    := 0,   // 空闲 / Idle
    eWait    := 10,  // 等双窗与静止 / Waiting for both windows and standstill
    ePending := 20,  // 切换排队中 / Switch pending
    eSwitch  := 30,  // 执行切换 / Switching
    eFault   := 90   // 组态故障锁定 / Configuration fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_TrackerAngleYearWin
VAR_INPUT
    bEnable       : BOOL;                          // 总使能，FALSE 回空闲 / Master enable
    bReset        : BOOL;                          // 复位，上升沿清组态故障 / Reset, clears configuration fault
    nYear         : INT := 2026;                   // 当前年 [年]，域 1970~2099 / Current year [year]
    nMonth        : INT := 1;                      // 当前月 [月]，域 1~12 / Current month [month]
    nDay          : INT := 1;                      // 当前日 [日]，域 1~31 / Current day [day]
    nStartYear    : INT := 2026;                   // 年窗起始年 [年] / Window start year [year]
    nStartMonth   : INT := 1;                      // 年窗起始月 [月] / Window start month [month]
    nStartDay     : INT := 1;                       // 年窗起始日 [日] / Window start day [day]
    nEndYear      : INT := 2026;                   // 年窗结束年 [年] / Window end year [year]
    nEndMonth     : INT := 12;                     // 年窗结束月 [月] / Window end month [month]
    nEndDay       : INT := 31;                     // 年窗结束日 [日] / Window end day [day]
    nTargetDay    : INT := 15;                     // 月窗目标日（正 = 第 N 天，负 = 月末倒数）[日] / Month target day
    nWindowDays   : INT := 3;                      // 月窗宽度 [日]，域 1~31 / Month window width [days]
    nYearMonth    : INT := 3;                      // 年度窗生效月份 [月]，域 1~12 / Yearly month [month]
    bTrackerStill : BOOL;                          // 支架静止标志（速度为 0 且无运动命令）/ Tracker standstill flag
    nTableVerNew  : INT := 2;                      // 新角度表版本号 [版本]，域 >= 1 / New angle table version
    nTableVerCur  : INT := 1;                      // 当前生效版本号 [版本]，域 >= 1 / Current active version
END_VAR
VAR_OUTPUT
    bYearWin      : BOOL;                          // 年窗生效 / Year window active
    bMonthWin     : BOOL;                          // 月窗生效 / Month window active
    bBothWin      : BOOL;                          // 双窗同时生效 / Both windows active
    nTableVerLatched : INT;                        // 锁存并生效的表版本号 [版本] / Latched table version
    bSwitchPending: BOOL;                          // 切换排队中（运动中）/ Switch pending during motion
    bSwitched     : BOOL;                          // 切换完成（单拍脉冲）/ Switch completed, single pulse
    bError        : BOOL;                          // 故障标志，与故障级码配对 / Fault flag paired with fault codes
    uErrorId      : UDINT;                         // 事件码，0 = 无事件 / Event code, 0 = none
    eStateOut     : E_DL_TayPhase;                 // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState       : E_DL_TayPhase := E_DL_TayPhase.eIdle;  // 内部状态 / Internal state
    rtrReset      : R_TRIG;                        // 复位沿 / Reset edge
    fbYearWin     : FB_DL_YearWindowCheck;         // 年窗实例（无条件调用）/ Year window instance
    fbMonthWin    : FB_DL_MonthWindowCheck;        // 月窗实例（无条件调用）/ Month window instance
    nYearC        : INT;                           // 钳位后当前年 [年] / Clamped current year
    nMonthC       : INT;                           // 钳位后当前月 [月] / Clamped current month
    nDayC         : INT;                           // 钳位后当前日 [日] / Clamped current day
    bYWin         : BOOL;                          // 年窗结果暂存 / Year window buffer
    bMWin         : BOOL;                          // 月窗结果暂存 / Month window buffer
    uFault        : UDINT;                         // 锁存故障码 / Latched fault code
    uInfo         : UDINT;                         // 信息级码 / Information code
END_VAR
VAR CONSTANT
    DL_TAY_YMIN   : INT := 1970;                   // 年份物理域下限 [年] / Year domain low
    DL_TAY_YMAX   : INT := 2099;                   // 年份物理域上限 [年] / Year domain high
    DL_TAY_DMAX   : INT := 31;                     // 日物理域上限 [日] / Day domain high
END_VAR

(* === 段 0 · 实例刷新（无条件周期调用）=== *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 参数钳位（越界钳定照算，报码不拒算）=== *)
nYearC := nYear;                                  // 年份钳位
IF nYearC < DL_TAY_YMIN THEN
    nYearC := DL_TAY_YMIN;
END_IF
IF nYearC > DL_TAY_YMAX THEN
    nYearC := DL_TAY_YMAX;
END_IF
nMonthC := nMonth;                                // 月份钳位
IF nMonthC < 1 THEN
    nMonthC := 1;
END_IF
IF nMonthC > 12 THEN
    nMonthC := 12;
END_IF
nDayC := nDay;                                    // 日期钳位
IF nDayC < 1 THEN
    nDayC := 1;
END_IF
IF nDayC > DL_TAY_DMAX THEN
    nDayC := DL_TAY_DMAX;
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零
IF (nYear <> nYearC) OR (nMonth <> nMonthC) OR (nDay <> nDayC) THEN
    uInfo := 16#0002_04C1;                        // 信息级：日期注入越界已钳位照算
END_IF

(* === 段 2 · 年窗实例（每拍无条件调用）=== *)
fbYearWin(bEnable := bEnable,
          bReset := rtrReset.Q,
          nYear := nYearC,
          nMonth := nMonthC,
          nDay := nDayC,
          nStartYear := nStartYear,
          nStartMonth := nStartMonth,
          nStartDay := nStartDay,
          nEndYear := nEndYear,
          nEndMonth := nEndMonth,
          nEndDay := nEndDay,
          bIncludeEnd := TRUE);                   // 结束日含当天（闭区间）
bYWin := fbYearWin.bInWindow;                     // 年窗结果
bYearWin := bYWin;                                // 年窗输出
IF fbYearWin.bInvalidConfig THEN
    uFault := 16#0002_04A1;                       // 故障级：年窗组态非法（空窗）
END_IF

(* === 段 3 · 月窗实例（每拍无条件调用）=== *)
fbMonthWin(bEnable := bEnable,
           nYear := INT_TO_DINT(nYearC),          // 标准转换函数
           nMonth := INT_TO_DINT(nMonthC),
           nDay := INT_TO_DINT(nDayC),
           nTargetDay := INT_TO_DINT(nTargetDay),
           nWindowDays := INT_TO_DINT(nWindowDays),
           bYearly := TRUE,                       // 年度窗：仅生效月份开放
           nYearMonth := INT_TO_DINT(nYearMonth));
bMWin := fbMonthWin.bInWindow;                    // 月窗结果
bMonthWin := bMWin;                               // 月窗输出
IF (nTargetDay = 0) OR (nWindowDays < 1) OR (nWindowDays > DL_TAY_DMAX)
   OR (nYearMonth < 1) OR (nYearMonth > 12) THEN
    uFault := 16#0002_04B1;                       // 故障级：月窗组态非法
END_IF
IF rtrReset.Q THEN
    uFault := 16#0000;                            // 复位沿清锁存（复位路径可达）
    bSwitched := FALSE;                           // 切换脉冲复位（非置位型）
END_IF
bBothWin := bYWin AND bMWin;                      // 双窗同时生效

(* === 段 4 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_TayPhase.eIdle :
    bSwitched := FALSE;                           // 空闲无切换脉冲
    bSwitchPending := FALSE;                      // 无排队
    IF uFault <> 16#0000 THEN
        _eState := E_DL_TayPhase.eFault;          // 组态故障优先
    ELSIF bEnable THEN
        _eState := E_DL_TayPhase.eWait;           // 进入等待相
    END_IF

E_DL_TayPhase.eWait :
    IF NOT bBothWin THEN
        bSwitchPending := FALSE;                  // 双窗不满足：排队取消
    ELSIF bBothWin AND (NOT bTrackerStill) THEN
        bSwitchPending := TRUE;                   // 运动中：排队到停止
        uInfo := 16#0002_04C1;                    // 信息级：运动中的切换排队
        _eState := E_DL_TayPhase.ePending;
    ELSIF bBothWin AND bTrackerStill AND (nTableVerNew <> nTableVerCur) THEN
        _eState := E_DL_TayPhase.eSwitch;         // 双窗 + 静止 + 版本不同：执行切换
    ELSE
        nTableVerLatched := nTableVerCur;         // 版本一致：锁存当前版本
    END_IF

E_DL_TayPhase.ePending :
    bSwitchPending := TRUE;                       // 排队标志保持
    IF NOT bBothWin THEN
        bSwitchPending := FALSE;                  // 窗关闭：排队取消
        _eState := E_DL_TayPhase.eWait;
    ELSIF bTrackerStill THEN
        bSwitchPending := FALSE;                  // 支架静止：排队结束（可到达的解除路径）
        _eState := E_DL_TayPhase.eSwitch;         // 转执行切换
    END_IF

E_DL_TayPhase.eSwitch :
    IF bTrackerStill AND bBothWin THEN
        nTableVerLatched := nTableVerNew;         // 单点锁存新版本（防半新半旧）
        bSwitched := TRUE;                        // 置位型：切换完成脉冲（段尾不清零）
        _eState := E_DL_TayPhase.eWait;           // 回等待相
    ELSIF NOT bTrackerStill THEN
        bSwitchPending := TRUE;                   // 运动中：回排队（不切换）
        _eState := E_DL_TayPhase.ePending;
    ELSIF NOT bBothWin THEN
        _eState := E_DL_TayPhase.eWait;           // 窗关闭：放弃切换
    END_IF

E_DL_TayPhase.eFault :
    bSwitchPending := FALSE;                      // 故障态取消排队
    nTableVerLatched := nTableVerCur;             // 版本保持当前（不切表）
    IF uFault = 16#0000 THEN
        _eState := E_DL_TayPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_TayPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_04A1;                       // 故障级：相 ID 越界
    nTableVerLatched := nTableVerCur;             // 安全侧保持当前版本
    bSwitched := FALSE;                           // 安全侧不报切换
END_CASE
IF NOT bEnable THEN
    _eState := E_DL_TayPhase.eIdle;               // 失能最高优先回空闲
    bSwitchPending := FALSE;                      // 取消排队
    bSwitched := FALSE;                           // 切换脉冲复位
END_IF

(* === 段 5 · 输出映射（三行同向：双窗 → 版本号 → 排队标志）=== *)
IF nTableVerLatched < 1 THEN
    nTableVerLatched := nTableVerCur;             // 版本号非法兜底：保持当前（防 0 版本）
END_IF
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
