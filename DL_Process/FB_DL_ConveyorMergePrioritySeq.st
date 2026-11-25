(*
  ============================================================
  组件名 : FB_DL_ConveyorMergePrioritySeq
  分类   : DL_Process
  功能   : 汇流合流优先权仲裁（主线优先、支线不饿死、抢占恢复、堵车计数告警、堵死与授权超时故障锁存）
  开源溯源 : internal-design（本轮无外部代码逐行引用）；参考语义 : 无外部参考
  复杂度 : C3
  版本   : 1.0.0
  ============================================================
*)

(*-----------------------------------------------------------------------------
 * 状态迁移表（ENUM 成员 → 出口；每成员均有可到达出口，零无界驻留相）：
 *   eIdle       → eGrantMain   : bReqMain（主线请求优先，含两路同时请求）
 *   eIdle       → eGrantBranch : 仅 bReqBranch 且无主线请求
 *   eIdle       ── 保持，直到任一请求（待机相以请求为唯一出口，属许可型驻留）
 *   eGrantMain  → eGrantBranch : bZoneMainClear 落沿（车辆已进入主线段，本次授权完成）且 bReqBranch
 *   eGrantMain  → eHoldBranch  : bZoneMainClear 落沿 且无支线请求（保持拦住支线）
 *   eGrantMain  → eJamWait     : bJamMain（主线堵车）
 *   eGrantMain  → eFault       : tonGrant.Q（码 2 单次授权超 tGrantMax）
 *   eGrantBranch→ eGrantMain   : bZoneBranchClear 落沿 且（抢占登记 或 主线再请求）
 *   eGrantBranch→ eIdle        : bZoneBranchClear 落沿 且无主线请求
 *   eGrantBranch→ eJamWait     : bJamBranch（支线堵车）
 *   eGrantBranch→ eFault       : tonGrant.Q（码 2 单次授权超 tGrantMax）
 *   eHoldBranch → eGrantMain   : bReqMain
 *   eHoldBranch → eGrantBranch : bReqBranch 且无主线请求
 *   eHoldBranch → eIdle        : 两路请求均已消失（进相前置条件消失，R98）
 *   eJamWait    → eIdle        : 对应堵车信号消失 ｜ rtJamReset.Q（bJamReset 上升沿）
 *   eJamWait    → eFault       : tonJamWait.Q（主线成因码 1 / 支线成因码 3）
 *   eFault      → eIdle        : bJamReset 上升沿（段 3 已清锁存，段 4 判锁存位迁相）
 *   ELSE（非法枚举值，非任何成员）→ eFault（码 5）
 *
 * 故障码表（nFaultCode，0 = 无故障；非首码均附「现有输出不可观测」反证句，R90）：
 *   1 主线堵死   : eJamWait 内主线堵车信号持续超 tJamTimeout（归因成员 _bJamFromMain = TRUE）。
 *   2 授权超时   : 反证——单次授权超 tGrantMax 时 eJamWait 未进入，堵车信号仍为假；
 *                  复用码 1 会把「光栅/清空信号失效」报成「物理堵料」，运维去拆包而非查光栅。
 *   3 支线堵死   : 反证——支线成因由 _bJamFromMain = FALSE 唯一标记，故障相动作全撤后
 *                  bGrantMainOut/bGrantBranchOut 同为 FALSE、eState 同为 eFault；若复用码 1，
 *                  运维将疏通主线而放过真正堵塞的支线（方向性误判，R146）。
 *   4 输入非法   : 反证——非有限速度或时间/计数参数越域时无任何请求沿、无授权动作，
 *                  与码 1/2/3 的时序签名互斥，必须独立成码以便组态错误可被前置拦截。
 *   5 非法状态   : 反证——非法枚举值为程序缺陷而非现场事件，合并入任一工艺码会让固件
 *                  错误被误排为设备故障，故独立成码。
 *
 * 依赖     : 仅 IEC 61131-3 标准库（TON / R_TRIG / F_TRIG / ABS），零厂商私有库
 * 分工声明 : 皮带驱动变频与速度环归驱动件；物理堵料检测（光电/限位）归现场检测件，
 *            本件只做「授权仲裁 + 堵车计数 + 安全撤权」，不做速度闭环也不做机械保护。
 * 归属     : E_DL_MergePrioState 归属本文件（全库唯一定义，R264；引用件只引用不重声明）。
 * 修订历史 : 2026-11-25  v1.0.0  首版（编码席 dlf-plc-coder，第二批 C3）
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 边界与红线自检：
 * ① 四个 TON 与三个沿实例（rtJamReset / ftMainClear / ftBranchClear）全部在 CASE 外无条件周期调用
 *    （R7）；时间类 IN 均含 NOT .Q 自复位项与 NOT 故障锁存项（R188 / FB50-1③），CASE 内只读 .Q。
 * ② 三个授权/保持出口在段 0 每拍预置 FALSE，CASE 内只置 TRUE —— eIdle 与 eFault 零残留。
 * ③ nJamCount 的写入点共三处且互不叠加：段 3 复位沿清零、eGrantMain/eGrantBranch 堵车事件入相 +1
 *    （一事件一次）、段 5 支线等待满窗 +1；不存在两处同拍 ±1 的双向计数（实战规则 1③）。
 * ④ 告警位 bJamAlarm 为纯派生式（计数超门槛 或 授权相内低速征兆），不独立锁存、无自引用赋值，
 *    计数被 bJamReset 清零后告警自动消失（R28 5.9 派生位纪律）。
 * ⑤ 堵车归因唯一：_bJamFromMain 在入相赋值点唯一，超时分支按该成员分列码 1 / 码 3（R190）。
 * ⑥ 复位沿作用域逐项声明（FB50-2②）：清堵车计数 / 清故障锁存与故障码 / 迁相回空闲，三项各写明。
 * ⑦ 低速征兆（|v| < 0.05）只参与告警计数，不单独触发故障（偏低类只降级，R146）。
 * ⑧ 零全局耦合：无 GVL / VAR_EXTERNAL / %I / %Q（R1 / R2）；无 FOR / WHILE / REPEAT（R271 N/A）。
 * ⑨ 相位写入点共两处且互斥：段 4 CASE、段 6 段尾迁移闸（无第三处旁路写相位）。
 *----------------------------------------------------------------------------*)

TYPE E_DL_MergePrioState :
(
    eIdle        := 0,                                              // 空闲：三路出口全撤，等请求 idle: all three outlets withdrawn, waiting for a request
    eGrantMain   := 1,                                              // 主线授权相：放行主线，支线请求挂起 main grant: main line released, branch requests parked
    eGrantBranch := 2,                                              // 支线授权相：放行支线，主线再请求时登记抢占 branch grant: branch released, a new main request registers preemption
    eHoldBranch  := 3,                                              // 支线保持拦截相：主线通过后拦住支线，等下一请求 hold branch: branch blocked after a main pass until the next request
    eJamWait     := 4,                                              // 堵车等待相：撤全部授权，等堵车信号消失或复位 jam wait: all grants withdrawn until the jam signal clears or a reset arrives
    eFault       := 5                                               // 故障锁存相：全部授权撤除，只由 bJamReset 沿迁出 fault: all grants withdrawn, left only by the bJamReset edge
);
END_TYPE

FUNCTION_BLOCK FB_DL_ConveyorMergePrioritySeq
VAR_INPUT
    bReqMain          : BOOL := FALSE;                              // 主线合流请求（电平）[bool] main line merge request level
    bReqBranch        : BOOL := FALSE;                              // 支线合流请求（电平）[bool] branch line merge request level
    bZoneMainClear    : BOOL := FALSE;                              // 主线段清空确认（TRUE = 段内无车）[bool] main segment clear confirmation, TRUE means empty
    bZoneBranchClear  : BOOL := FALSE;                              // 支线段清空确认（TRUE = 段内无车）[bool] branch segment clear confirmation, TRUE means empty
    bJamMain          : BOOL := FALSE;                              // 主线堵车检测（现场检测件给出）[bool] main line jam detection from the field device
    bJamBranch        : BOOL := FALSE;                              // 支线堵车检测（现场检测件给出）[bool] branch line jam detection from the field device
    rSpeedMain        : REAL := 0.0;                                // 主线实测线速度 [m/s] measured main line speed [m/s]
    rSpeedBranch      : REAL := 0.0;                                // 支线实测线速度 [m/s] measured branch line speed [m/s]
    tGrantMax         : TIME := T#30S;                              // 单次授权最长占用窗 [s] maximum single grant window [s]
    tJamTimeout       : TIME := T#60S;                              // 堵车持续判与支线等待计数窗 [s] jam persistence and branch wait counting window [s]
    nJamResetCountMax : INT := 3;                                   // 支线等待计数告警门槛，域 0..10000 [次] branch wait count alarm threshold, domain 0..10000
    bJamReset         : BOOL := FALSE;                              // 堵车复位（上升沿）：清计数与故障锁存 [bool] jam reset rising edge, clears the count and the fault latch
END_VAR
VAR_OUTPUT
    bGrantMainOut   : BOOL;                                         // 主线放行授权（段 0 预置，CASE 只置位）[bool] main line release grant
    bGrantBranchOut : BOOL;                                         // 支线放行授权（段 0 预置，CASE 只置位）[bool] branch line release grant
    bHoldBranchOut  : BOOL;                                         // 支线拦截保持（段 0 预置，CASE 只置位）[bool] branch line hold command
    eState          : E_DL_MergePrioState;                          // 相位出口（段 7 单点映射）[-] phase outlet mapped once in section 7
    nJamCount       : INT;                                          // 支线等待/堵车累计次数 [次] accumulated branch wait and jam event count
    bJamAlarm       : BOOL;                                         // 支线饥饿告警（计数派生，非故障）[bool] branch starvation alarm derived from the count, not a fault
    nFaultCode      : INT;                                          // 故障码 0 无 1 主线堵死 2 授权超时 3 支线堵死 4 输入非法 5 非法状态 [码] fault code
    bError          : BOOL;                                         // 故障锁存标志（取锁存位，R45 配对出口）[bool] fault latch flag used as the paired outlet
END_VAR
VAR
    _eState         : E_DL_MergePrioState := E_DL_MergePrioState.eIdle; // 内部相位（CASE 唯一比较目标）[-] internal phase compared by the CASE
    _bFaultLatch    : BOOL := FALSE;                                // 故障锁存位（仅 bJamReset 沿清除）[bool] fault latch, cleared only by the bJamReset edge
    _nFault         : INT := 0;                                     // 锁存故障码（故障期回放，不按当下输入重算）[码] latched fault code replayed in the fault phase
    _nJamCnt        : INT := 0;                                     // 内部支线等待与堵车计数 [次] internal branch wait and jam count
    _bCfgOk         : BOOL := FALSE;                                // 组态与入参域闸通过标志 [bool] configuration and input domain gate flag
    _bRunActive     : BOOL := FALSE;                                // 仲裁相关相标志（授权/保持/堵车等待）[bool] arbitration phase flag
    _bGrantMain     : BOOL := FALSE;                                // 内部主线授权状态 [bool] internal main grant state
    _bGrantBranch   : BOOL := FALSE;                                // 内部支线授权状态 [bool] internal branch grant state
    _bHoldBranch    : BOOL := FALSE;                                // 内部支线拦截状态 [bool] internal branch hold state
    _bPreemptPending : BOOL := FALSE;                               // 主线抢占登记（支线授权期间挂起）[bool] main preemption pending during a branch grant
    _bJamFromMain   : BOOL := TRUE;                                 // 堵车归因：TRUE 主线成因 / FALSE 支线成因（R190）[bool] jam attribution, TRUE for main and FALSE for branch
    _bSlowMain      : BOOL := FALSE;                                // 主线低速征兆（|v| < 门限）[bool] main line low speed symptom
    _bSlowBranch    : BOOL := FALSE;                                // 支线低速征兆（|v| < 门限）[bool] branch line low speed symptom
    rtJamReset      : R_TRIG;                                       // bJamReset 上升沿实例（段 2 无条件调用）[bool] jam reset rising edge instance
    ftMainClear     : F_TRIG;                                       // 主线段清空落沿实例（段 2 无条件调用）[bool] main segment clear falling edge instance
    ftBranchClear   : F_TRIG;                                       // 支线段清空落沿实例（段 2 无条件调用）[bool] branch segment clear falling edge instance
    tonGrant        : TON;                                          // 单次授权占用计时（段 2 无条件调用）[s] single grant occupancy timer
    tonJamWait      : TON;                                          // 堵车持续判计时（段 2 无条件调用）[s] jam persistence timer
    tonBranchWait   : TON;                                          // 支线等待满窗计数计时（段 2 无条件调用）[s] branch wait counting timer
END_VAR
VAR CONSTANT
    DL_MRG_ZERO      : REAL := 0.0;                                 // 浮点零基准 [m/s] float zero base
    DL_MRG_V_MIN     : REAL := 0.05;                                // 低速征兆门限 [m/s] low speed symptom threshold [m/s]
    DL_MRG_T_MIN     : TIME := T#100MS;                             // 时间参数下限 [s] lower bound of the time parameters
    DL_MRG_T_MAX     : TIME := T#2H;                                // 时间参数上限 [s] upper bound of the time parameters
    DL_MRG_CNT_MAX   : INT := 10000;                                // 计数门槛上限 [次] upper bound of the count threshold
    DL_MRG_CNT_ZERO  : INT := 0;                                    // 计数零基准 [次] count zero base
    DL_MRG_CNT_ONE   : INT := 1;                                    // 计数步长 [次] count step
END_VAR

(* —— 段 0：出口命令预置与派生量（CASE 内只置 TRUE，杜绝故障相残留） —— *)
_bGrantMain   := FALSE;                                             // 主线授权每拍先撤 [bool] main grant withdrawn first each scan
_bGrantBranch := FALSE;                                             // 支线授权每拍先撤 [bool] branch grant withdrawn first each scan
_bHoldBranch  := FALSE;                                             // 支线拦截每拍先撤 [bool] branch hold withdrawn first each scan
_bRunActive   := (_eState = E_DL_MergePrioState.eGrantMain) OR (_eState = E_DL_MergePrioState.eGrantBranch)
                 OR (_eState = E_DL_MergePrioState.eHoldBranch) OR (_eState = E_DL_MergePrioState.eJamWait); // 仲裁相标志（用状态量，R99）[bool] arbitration phase flag
_bSlowMain    := (ABS(rSpeedMain) < DL_MRG_V_MIN);                  // 主线低速征兆（非有限值此判恒假，由域闸兜住）[bool] main low speed symptom
_bSlowBranch  := (ABS(rSpeedBranch) < DL_MRG_V_MIN);                // 支线低速征兆（非有限值此判恒假，由域闸兜住）[bool] branch low speed symptom

(* —— 段 1：组态域闸（全部浮点入参与时间/计数参数枚举，非有限双判 R151 / R79） —— *)
_bCfgOk := TRUE;                                                    // 组态闸标志初值 [bool] configuration flag initial value
IF (rSpeedMain <> rSpeedMain) OR ((rSpeedMain - rSpeedMain) <> DL_MRG_ZERO)
   OR (rSpeedBranch <> rSpeedBranch) OR ((rSpeedBranch - rSpeedBranch) <> DL_MRG_ZERO) THEN
    _bCfgOk := FALSE;                                               // 非有限速度：拒收（NaN 自反 + Inf 差值自减）[bool] non finite speed rejected
END_IF
IF _bCfgOk THEN
    IF (tGrantMax < DL_MRG_T_MIN) OR (tGrantMax > DL_MRG_T_MAX) THEN
        _bCfgOk := FALSE;                                           // 授权窗越域 [bool] grant window out of domain
    ELSIF (tJamTimeout < DL_MRG_T_MIN) OR (tJamTimeout > DL_MRG_T_MAX) THEN
        _bCfgOk := FALSE;                                           // 堵车窗越域 [bool] jam window out of domain
    ELSIF (nJamResetCountMax < DL_MRG_CNT_ZERO) OR (nJamResetCountMax > DL_MRG_CNT_MAX) THEN
        _bCfgOk := FALSE;                                           // 告警门槛越域 [bool] alarm threshold out of domain
    END_IF
END_IF
IF (NOT _bCfgOk) AND (NOT _bFaultLatch) AND (bReqMain OR bReqBranch OR _bRunActive) THEN
    _nFault      := 4;                                              // 故障级：输入非法（非有限/越域）[码] fault: illegal input
    _bFaultLatch := TRUE;                                           // 置故障锁存 [bool] latch the fault
    bError       := TRUE;                                           // R45 配对：故障标志同拍置位 [bool] paired error flag
END_IF

(* —— 段 2：沿与定时器（CASE 外无条件周期调用，R7；IN 含 NOT .Q 自复位与 NOT 锁存，R188） —— *)
rtJamReset(CLK := bJamReset);                                       // 复位沿无条件刷新 [bool] reset edge refreshed unconditionally
ftMainClear(CLK := bZoneMainClear);                                 // 主线段清空落沿刷新 [bool] main clear falling edge refreshed
ftBranchClear(CLK := bZoneBranchClear);                             // 支线段清空落沿刷新 [bool] branch clear falling edge refreshed
tonGrant(IN := ((_eState = E_DL_MergePrioState.eGrantMain) OR (_eState = E_DL_MergePrioState.eGrantBranch))
              AND (NOT tonGrant.Q) AND (NOT _bFaultLatch),
         PT := tGrantMax);                                          // 单次授权占用计时 [s] single grant occupancy timer
tonJamWait(IN := (_eState = E_DL_MergePrioState.eJamWait) AND (NOT tonJamWait.Q) AND (NOT _bFaultLatch),
           PT := tJamTimeout);                                      // 堵车持续判计时 [s] jam persistence timer
tonBranchWait(IN := bReqBranch AND (NOT bReqMain)
                 AND ((_eState = E_DL_MergePrioState.eGrantMain) OR (_eState = E_DL_MergePrioState.eHoldBranch))
                 AND (NOT tonBranchWait.Q) AND (NOT _bFaultLatch),
              PT := tJamTimeout);                                   // 支线被拦等待满窗计数 [s] branch blocked wait counting timer

(* —— 段 3：复位沿优先消化（作用域逐项声明，FB50-2②；先消化沿再消化超时，R275） —— *)
IF rtJamReset.Q THEN
    _nJamCnt := DL_MRG_CNT_ZERO;                                    // 复位沿作用域①：清支线等待与堵车计数 [次] reset scope one, clear the wait count
    IF _bFaultLatch THEN
        _bFaultLatch := FALSE;                                      // 复位沿作用域②：清故障锁存 [bool] reset scope two, clear the fault latch
        _nFault      := 0;                                          // 复位沿作用域③：清故障码 [码] reset scope three, clear the fault code
    END_IF
END_IF

(* —— 段 4：主状态机（相位写入点之一；每成员独立标签，ELSE 只兜非法值，FB32-5） —— *)
CASE _eState OF
E_DL_MergePrioState.eIdle :                                         // 空闲相：三路出口已撤
    IF bReqMain THEN
        _bPreemptPending := FALSE;                                  // 新周期清抢占登记 [bool] clear the preemption flag for the new cycle
        _eState := E_DL_MergePrioState.eGrantMain;                  // 迁移：主线优先 [phase] main line has priority
    ELSIF bReqBranch THEN
        _bPreemptPending := FALSE;                                  // 新周期清抢占登记 [bool] clear the preemption flag for the new cycle
        _eState := E_DL_MergePrioState.eGrantBranch;                // 迁移：仅支线请求 [phase] branch request only
    END_IF

E_DL_MergePrioState.eGrantMain :                                    // 主线授权相
    _bGrantMain := TRUE;                                            // 放行主线 [bool] release the main line
    IF bJamMain THEN
        _bJamFromMain := TRUE;                                      // 归因：主线成因（唯一赋值点，R190）[bool] attribution to the main line
        _nJamCnt      := _nJamCnt + DL_MRG_CNT_ONE;                 // 一次堵车事件一次计数 [次] one count per jam event
        _eState       := E_DL_MergePrioState.eJamWait;              // 迁移：撤权进堵车等待 [phase] withdraw and wait for the jam to clear
    ELSIF ftMainClear.Q THEN
        IF bReqBranch THEN
            _eState := E_DL_MergePrioState.eGrantBranch;            // 迁移：主线段已进车，放行支线 [phase] main entry done, release the branch
        ELSE
            _eState := E_DL_MergePrioState.eHoldBranch;             // 迁移：无支线请求，保持拦住支线 [phase] no branch request, hold the branch
        END_IF
    END_IF

E_DL_MergePrioState.eGrantBranch :                                  // 支线授权相
    _bGrantBranch := TRUE;                                          // 放行支线 [bool] release the branch line
    IF bReqMain THEN
        _bPreemptPending := TRUE;                                   // 登记主线抢占（支线通过后立即恢复主线）[bool] register main preemption
    END_IF
    IF bJamBranch THEN
        _bJamFromMain := FALSE;                                     // 归因：支线成因（唯一赋值点，R190）[bool] attribution to the branch line
        _nJamCnt      := _nJamCnt + DL_MRG_CNT_ONE;                 // 一次堵车事件一次计数 [次] one count per jam event
        _eState       := E_DL_MergePrioState.eJamWait;              // 迁移：撤权进堵车等待 [phase] withdraw and wait for the jam to clear
    ELSIF ftBranchClear.Q THEN
        IF _bPreemptPending OR bReqMain THEN
            _bPreemptPending := FALSE;                              // 抢占已兑现，清登记 [bool] preemption honoured, clear the flag
            _eState := E_DL_MergePrioState.eGrantMain;              // 迁移：支线通过后恢复主线 [phase] branch passed, restore the main line
        ELSE
            _eState := E_DL_MergePrioState.eIdle;                   // 迁移：无主线请求回空闲重新仲裁 [phase] no main request, back to idle
        END_IF
    END_IF

E_DL_MergePrioState.eHoldBranch :                                   // 支线保持拦截相
    _bHoldBranch := TRUE;                                           // 保持拦住支线 [bool] hold the branch line
    IF bReqMain THEN
        _eState := E_DL_MergePrioState.eGrantMain;                  // 迁移（出口 1）：主线请求 [phase] main request arrives
    ELSIF bReqBranch THEN
        _eState := E_DL_MergePrioState.eGrantBranch;                // 迁移（出口 2）：仅支线请求，不再拦 [phase] branch only, stop holding
    ELSIF (NOT bReqMain) AND (NOT bReqBranch) THEN
        _eState := E_DL_MergePrioState.eIdle;                       // 迁移（出口 3）：进相前置条件消失 [phase] both requests gone, the hold precondition vanished
    END_IF

E_DL_MergePrioState.eJamWait :                                      // 堵车等待相：三路授权已撤
    IF rtJamReset.Q THEN
        _eState := E_DL_MergePrioState.eIdle;                       // 迁移（出口 1）：人工复位直接回空闲 [phase] manual reset back to idle
    ELSIF _bJamFromMain AND (NOT bJamMain) THEN
        _eState := E_DL_MergePrioState.eIdle;                       // 迁移（出口 2）：主线堵车信号消失 [phase] main jam signal gone
    ELSIF (NOT _bJamFromMain) AND (NOT bJamBranch) THEN
        _eState := E_DL_MergePrioState.eIdle;                       // 迁移（出口 3）：支线堵车信号消失 [phase] branch jam signal gone
    END_IF

E_DL_MergePrioState.eFault :                                        // 故障锁存相：三路授权已由段 6 全撤
    IF NOT _bFaultLatch THEN
        _eState := E_DL_MergePrioState.eIdle;                       // 复位沿已在段 3 清锁存，此处迁回空闲 [phase] the latch was cleared in section 3
    END_IF

ELSE                                                                // 非法枚举值兜底（R6 / FB32-5）
    IF NOT _bFaultLatch THEN
        _nFault      := 5;                                          // 故障级：非法状态枚举值 [码] fault: illegal state enum value
        _bFaultLatch := TRUE;                                       // 置故障锁存 [bool] latch the fault
        bError       := TRUE;                                       // R45 配对：故障标志同拍置位 [bool] paired error flag
    END_IF
    _eState := E_DL_MergePrioState.eFault;                          // 非法值一律落安全相 [phase] illegal value falls into the safe phase
END_CASE

(* —— 段 5：超时看门狗与支线等待计数（状态已迁出则该相看门狗不生效，R275） —— *)
IF tonGrant.Q AND (NOT _bFaultLatch)
   AND ((_eState = E_DL_MergePrioState.eGrantMain) OR (_eState = E_DL_MergePrioState.eGrantBranch)) THEN
    _nFault      := 2;                                              // 故障级：单次授权超时 [码] fault: single grant timeout
    _bFaultLatch := TRUE;                                           // 置故障锁存 [bool] latch the fault
    bError       := TRUE;                                           // R45 配对：故障标志同拍置位 [bool] paired error flag
END_IF
IF tonJamWait.Q AND (NOT _bFaultLatch) AND (_eState = E_DL_MergePrioState.eJamWait) THEN
    IF _bJamFromMain THEN
        _nFault := 1;                                               // 故障级：主线堵死 [码] fault: main line blocked
    ELSE
        _nFault := 3;                                               // 故障级：支线堵死 [码] fault: branch line blocked
    END_IF
    _bFaultLatch := TRUE;                                           // 置故障锁存 [bool] latch the fault
    bError       := TRUE;                                           // R45 配对：故障标志同拍置位 [bool] paired error flag
END_IF
IF tonBranchWait.Q AND (NOT _bFaultLatch) AND (NOT rtJamReset.Q) THEN
    _nJamCnt := _nJamCnt + DL_MRG_CNT_ONE;                          // 支线被拦满一个窗 → 累计一次（单点写入；复位沿同拍优先，R275）[次] one count per blocked window
END_IF

(* —— 段 6：段尾故障迁移闸 + 故障/空闲相授权全撤（FB50-1④） —— *)
IF _bFaultLatch AND (_eState <> E_DL_MergePrioState.eFault) THEN
    _eState := E_DL_MergePrioState.eFault;                          // 锁存即迁相（锁存与迁相分离，R21）[phase] a latch forces the fault phase
END_IF
IF (_eState = E_DL_MergePrioState.eFault) OR (_eState = E_DL_MergePrioState.eIdle)
   OR (_eState = E_DL_MergePrioState.eJamWait) THEN
    _bGrantMain   := FALSE;                                         // 安全侧：主线授权全撤 [bool] main grant withdrawn on the safe side
    _bGrantBranch := FALSE;                                         // 安全侧：支线授权全撤 [bool] branch grant withdrawn on the safe side
    _bHoldBranch  := FALSE;                                         // 安全侧：支线拦截全撤 [bool] branch hold withdrawn on the safe side
END_IF

(* —— 段 7：统一出口（相位映射 + 计数与告警派生 + 锁存码回放；告警为纯派生位，无独立锁存） —— *)
bGrantMainOut   := _bGrantMain;                                     // 主线授权出口 [bool] main grant outlet
bGrantBranchOut := _bGrantBranch;                                   // 支线授权出口 [bool] branch grant outlet
bHoldBranchOut  := _bHoldBranch;                                    // 支线拦截出口 [bool] branch hold outlet
eState          := _eState;                                         // 相位出口 [phase] phase outlet
nJamCount       := _nJamCnt;                                        // 计数出口 [次] count outlet
bJamAlarm       := ((_nJamCnt > nJamResetCountMax) AND (nJamResetCountMax >= DL_MRG_CNT_ZERO))
                   OR (((_eState = E_DL_MergePrioState.eGrantMain) AND _bSlowMain)
                       OR ((_eState = E_DL_MergePrioState.eGrantBranch) AND _bSlowBranch)); // 告警纯派生：计数超门槛 或 授权中低速征兆（R28 5.9）
nFaultCode      := _nFault;                                         // 故障码出口（锁存回放）[码] fault code outlet replayed from the latch
bError          := _bFaultLatch;                                    // 故障标志取锁存位 [bool] fault flag from the latch
END_FUNCTION_BLOCK
