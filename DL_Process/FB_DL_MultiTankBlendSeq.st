(*
  ============================================================
  组件名 : FB_DL_MultiTankBlendSeq
  分类   : DL_Process
  功能   : 多罐调和批次序列（A 进料 → B 进料 → 循环调和 → 取样 → 排料 → 完成），含超容、进料超时、收敛超时、取样超时、排料超时、人工中止、配方无效共七类故障锁存
  开源溯源 : internal-design（本轮无外部代码逐行引用）；参考语义 : 无外部参考
  复杂度 : C4
  版本   : 1.0.0
  ============================================================
*)

(*-----------------------------------------------------------------------------
 * 状态迁移表（ENUM 成员 → 出口；每成员均有可到达出口，零无界驻留相）：
 *   eIdle      → eFillA  : bStart 且 bRecipeValid 且组态闸通过 且 总量 ≤ rMaxVolume
 *   eIdle      ── 保持，直到 bStart（待机相以启动命令为唯一出口，属许可型驻留）
 *   eFillA     → eFillB  : rVolAct ≥ rVolA_sp（含 1E-6 容差）
 *   eFillA     → eFault  : tonFill.Q（码 1）｜bAbort 沿（码 5）｜rVolAct > rMaxVolume（码 4）｜bStart 撤除（无码回空闲）
 *   eFillB     → eCirculate : rVolAct ≥ (rVolA_sp + rVolB_sp) - 1E-6
 *   eFillB     → eFault  : tonFill.Q（码 1）｜bAbort 沿（码 5）｜超容（码 4）｜组态闸失效（码 6）
 *   eCirculate → eSample : 温度与浓度同时进带并持续 tCircStable（tonStable.Q）
 *   eCirculate → eFault  : tonCirc.Q（码 2）｜bAbort 沿（码 5）
 *   eSample    → eRelease : bSampleDone（外部取样完成电平）
 *   eSample    → eFault   : tonSample.Q（码 3）｜bAbort 沿（码 5）
 *   eRelease   → eDone    : bLevelLow（低液位信号，排料到位）
 *   eRelease   → eFault   : tonRelease.Q（码 7）｜bAbort 沿（码 5）
 *   eDone      → eIdle    : bStart 撤除（完成相以撤令为唯一出口，属人工确认型驻留）
 *   eFault     → eIdle    : bAbort 上升沿 或（bStart = FALSE 且 bAbort = FALSE）
 *   ELSE（非法枚举值，非任何成员）→ eFault（码 8）
 *
 * 故障码表（nFaultCode，0 = 无故障；非首码均附「现有输出不可观测」反证句，R90）：
 *   1 进料超时      : tFillTimeout 覆盖 eFillA + eFillB（进 eFillA 时计时器自然复位）。
 *   2 循环收敛超时  : 反证——eFault 相动作全撤后 bValveA/bValveB/bAgitator/bDischarge 全 FALSE、
 *                     eState 同为 eFault，复用码 1 会使「调和未收敛」与「进料过慢」在 HMI 上不可区分。
 *   3 取样超时      : 反证——取样相外部回执缺失，阀位与搅拌状态在故障撤除后与码 2 完全同形，
 *                     复用码 2 会把「外部取样单元不回报」误判为工艺收敛失败，运维方向相悖。
 *   4 超罐容        : 反证——超容判据在进料前即可成立（无阀位动作、无累计体积），
 *                     复用码 1 会把「配方总量超罐容」报成「进料慢」，掩盖配方错误。
 *   5 人工中止      : 反证——操作员主动撤令属安全审计事件，与任何超时码的因果主体不同，
 *                     合并后无法区分「设备不动」与「人按了停」。
 *   6 配方无效      : 反证——非法配方在进料前拦截，此时无累计体积、无阀位输出，
 *                     与超时类码位的时序签名互斥，必须独立成码以便前置拦截可被观测。
 *   7 排料超时      : 反证——排料相 bDischarge 独占且 bLevelLow 缺失，故障撤除后与码 1/2/3 的
 *                     观测量全同，复用码 1 会让运维去查进料阀而非排料阀。
 *   8 非法状态枚举  : 反证——非法枚举值为程序缺陷而非工艺事件，必须与现场工艺故障分离，
 *                     否则固件错误会被误排为设备故障。
 *
 * 依赖     : 仅 IEC 61131-3 标准库（TON / R_TRIG / ABS / LIMIT），零厂商私有库
 * 分工声明 : 循环泵输出不在本件接口（上层以 eState = eCirculate 派生泵命令）；
 *            温度/浓度闭环调节归温控件与浓度调节件；本件只做批次时序与保护，不做连续调节。
 * 归属     : E_DL_BlendState 归属本文件（全库唯一定义，R264；引用件只引用不重声明）。
 * 修订历史 : 2026-11-25  v1.0.0  首版（编码席 dlf-plc-coder，第二批 C4）
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 边界与红线自检：
 * ① 六个 TON 与一个 R_TRIG 全部在 CASE 外无条件周期调用（R7）；时间类 IN 均含 NOT .Q 自复位项
 *    与 NOT 故障锁存项（R188 / FB50-1③），CASE 内只读 .Q。
 * ② 出口命令（bValveA/bValveB/bAgitator/bDischarge/bSampleReq）在段 0 每拍预置 FALSE，
 *    CASE 内只置 TRUE —— eIdle 与 eFault 相零残留（上轮 MAJOR「故障后残留旧输出」型缺陷已封堵）。
 * ③ bDone 由相位派生（bDone := _eState = eDone），不是单拍脉冲，从结构上排除「同拍置位又撤销」（FB33-1）。
 * ④ 故障码 _nFault 一律锁存至 eFault 复位分支，故障相内不按当下输入重算（FB33-1③ / R152）。
 * ⑤ 除零防护：进度式除子 _rVolTotal 先过 > 1E-6 与 _bCfgOk 双检（R4）。
 * ⑥ 相内等待出口 ≥2（R98）：eSample = bSampleDone ｜ tonSample.Q ｜ bAbort 沿 ｜ bStart 撤除；
 *    eRelease = bLevelLow ｜ tonRelease.Q ｜ bAbort 沿 ｜ bStart 撤除。
 * ⑦ 组态域闸：参与任何判据换算的 10 个浮点入参全部显式枚举（含 rMaxVolume），NaN 用自反比较、
 *    Inf 用差值自减双判（R151 / R79），非有限不入保持槽。
 * ⑧ 零全局耦合：无 GVL / VAR_EXTERNAL / %I / %Q（R1 / R2）。
 * ⑨ 相位写入点共三处且互斥：段 3（bAbort 沿只置锁存，不写相位）、段 4 CASE、段 6 迁移闸。
 *----------------------------------------------------------------------------*)

TYPE E_DL_BlendState :
(
    eIdle      := 0, // 空闲：全部阀位关闭，等启动与配方有效 idle: all valves closed, waiting for start and a valid recipe
    eFillA     := 1, // A 罐进料相：开 A 阀累计至 rVolA_sp fill A: A valve open until rVolA_sp is reached
    eFillB     := 2, // B 罐进料相：开 B 阀累计至 A+B 总量 fill B: B valve open until the A+B total is reached
    eCirculate := 3, // 循环调和相：搅拌运行，温度与浓度双判进带 circulate: agitation with temperature and concentration both inside band
    eSample    := 4, // 取样相：置取样请求等外部完成 sample: sample request raised, waiting for the external completion
    eRelease   := 5, // 排料相：开排料阀至低液位 release: discharge valve open until the low level signal
    eFault     := 6, // 故障锁存相：全部阀位撤除，只由复位出口迁出 fault: all valves withdrawn, left only by the reset outlet
    eDone      := 7  // 批次完成相：bStart 撤除后回空闲 done: returns to idle when bStart is withdrawn
);
END_TYPE

FUNCTION_BLOCK FB_DL_MultiTankBlendSeq
VAR_INPUT
    bStart          : BOOL := FALSE;          // 启动/运行许可（电平）：撤除即安全停机回空闲 [bool] start and run permissive, a dropped level stops safely
    bAbort          : BOOL := FALSE;          // 人工中止（上升沿）：置故障码 5 并锁存 [bool] manual abort rising edge, latches fault code 5
    bRecipeValid    : BOOL := FALSE;          // 配方有效回执：FALSE 时禁止启动并置码 6 [bool] recipe valid receipt, FALSE blocks the start with code 6
    rVolA_sp        : REAL := 0.0;            // A 组分配方体积设定 [m3] recipe volume setpoint of component A [m3]
    rVolB_sp        : REAL := 0.0;            // B 组分配方体积设定 [m3] recipe volume setpoint of component B [m3]
    rVolAct         : REAL := 0.0;            // 当前累计进料量（A+B 合计）[m3] accumulated feed volume of A plus B [m3]
    rTempAct        : REAL := 0.0;            // 混合物实测温度 [degC] measured blend temperature [degC]
    rTempSp         : REAL := 0.0;            // 调和温度设定 [degC] blend temperature setpoint [degC]
    rTempBand       : REAL := 0.0;            // 温度进带允许偏差，域 > 1E-6 [K] temperature band tolerance, domain > 1E-6 [K]
    rConcAct        : REAL := 0.0;            // 混合物实测浓度 [%] measured blend concentration [%]
    rConcSp         : REAL := 0.0;            // 调和浓度设定 [%] blend concentration setpoint [%]
    rConcBand       : REAL := 0.0;            // 浓度进带允许偏差，域 > 1E-6 [%] concentration band tolerance, domain > 1E-6 [%]
    tFillTimeout    : TIME := T#10M;          // 进料总超时窗，覆盖 eFillA + eFillB [s] total feed timeout covering fill A and fill B [s]
    tCircTimeout    : TIME := T#30M;          // 循环调和相超时窗 [s] circulation phase timeout window [s]
    tSampleTimeout  : TIME := T#5M;           // 取样相等待外部回执超时窗 [s] sample phase external receipt timeout [s]
    rMaxVolume      : REAL := 10.0;           // 罐体最大有效容积，域 > 0 [m3] tank maximum usable volume, domain > 0 [m3]
    bSampleDone     : BOOL := FALSE;          // 外部取样完成回执（电平）[bool] external sampling done receipt level
    bLevelLow       : BOOL := FALSE;          // 排料低液位信号（排料到位）[bool] discharge low level signal
    tCircStable     : TIME := T#15S;          // 温度与浓度同时在带内的持续确认窗 [s] continuous in-band confirmation window [s]
    tReleaseTimeout : TIME := T#15M;          // 排料相超时窗（低液位不到的兜底）[s] release phase timeout fallback [s]
END_VAR
VAR_OUTPUT
    bValveA      : BOOL;                      // A 组分进料阀命令（段 0 预置，CASE 只置位）[bool] component A feed valve command
    bValveB      : BOOL;                      // B 组分进料阀命令（段 0 预置，CASE 只置位）[bool] component B feed valve command
    bAgitator    : BOOL;                      // 搅拌器命令（循环相与取样相保持开）[bool] agitator command, held in circulation and sampling
    bDischarge   : BOOL;                      // 排料阀命令（仅排料相）[bool] discharge valve command, release phase only
    bSampleReq   : BOOL;                      // 取样请求（仅取样相，电平保持）[bool] sample request, level held in the sample phase
    eState       : E_DL_BlendState;           // 相位出口（段 7 单点映射）[-] phase outlet mapped once in section 7
    bDone        : BOOL;                      // 批次完成（由相位派生，非单拍脉冲）[bool] batch done, derived from the phase as a level
    nFaultCode   : INT;                       // 故障码 0 无 1 进料超时 2 收敛超时 3 取样超时 4 超容 5 人工中止 6 配方无效 7 排料超时 8 非法状态 [码] fault code
    rProgressPct : REAL;                      // 进料完成度 0..100（其后各相恒 100）[%] feed completion percentage, constant 100 in later phases [%]
    bError       : BOOL;                      // 故障锁存标志（取锁存位，R45 配对出口）[bool] fault latch flag used as the paired outlet
END_VAR
VAR
    _eState       : E_DL_BlendState := E_DL_BlendState.eIdle;   // 内部相位（CASE 唯一比较目标）[-] internal phase compared by the CASE
    _bFaultLatch  : BOOL := FALSE;                              // 故障锁存位（仅复位出口清除）[bool] fault latch, cleared only by the reset outlet
    _nFault       : INT := 0;                                   // 锁存故障码（故障期回放，不按当下输入重算）[码] latched fault code replayed during the fault phase
    _bCfgOk       : BOOL := FALSE;                              // 组态与入参域闸通过标志 [bool] configuration and input domain gate flag
    _bRunActive   : BOOL := FALSE;                              // 运行相关相标志（进料到排料）[bool] running phase flag from fill to release
    _bInBand      : BOOL := FALSE;                               // 温度与浓度同时进带标志 [bool] both temperature and concentration inside band
    _bValveA      : BOOL := FALSE;                              // 内部 A 阀命令状态 [bool] internal A valve command state
    _bValveB      : BOOL := FALSE;                              // 内部 B 阀命令状态 [bool] internal B valve command state
    _bAgitator    : BOOL := FALSE;                              // 内部搅拌命令状态 [bool] internal agitator command state
    _bDischarge   : BOOL := FALSE;                              // 内部排料阀命令状态 [bool] internal discharge valve command state
    _bSampleReq   : BOOL := FALSE;                              // 内部取样请求状态 [bool] internal sample request state
    _rVolTotal    : REAL := 0.0;                                // 配方总量 = A + B [m3] recipe total volume of A plus B [m3]
    _rProg        : REAL := 0.0;                                // 进料完成度中间量 [%] feed completion intermediate value [%]
    rtAbort       : R_TRIG;                                     // bAbort 上升沿实例（段 2 无条件调用）[bool] abort rising edge instance
    tonFill       : TON;                                        // 进料总超时计时（覆盖两进料相，段 2 无条件调用）[s] total feed timeout covering both fill phases
    tonCirc       : TON;                                        // 循环调和相超时计时（段 2 无条件调用）[s] circulation timeout
    tonStable     : TON;                                        // 双判进带持续确认计时（段 2 无条件调用）[s] in-band persistence timer
    tonSample     : TON;                                        // 取样相等待回执超时计时（段 2 无条件调用）[s] sample receipt timeout
    tonRelease    : TON;                                        // 排料相超时计时（段 2 无条件调用）[s] release timeout
END_VAR
VAR CONSTANT
    DL_BLD_ZERO     : REAL := 0.0;        // 浮点零基准 [m3] float zero base
    DL_BLD_ONE      : REAL := 1.0;        // 浮点一基准 [%] float one base
    DL_BLD_HUNDRED  : REAL := 100.0;      // 百分比满量程 [%] percent full scale
    DL_BLD_EPS      : REAL := 1.0E-6;     // 体积与宽容差基准 [m3] volume and band tolerance base
    DL_BLD_T_MIN    : TIME := T#100MS;    // 时间参数下限 [s] lower bound of the time parameters
    DL_BLD_T_MAX    : TIME := T#4H;       // 时间参数上限 [s] upper bound of the time parameters
END_VAR

(* —— 段 0：出口命令预置与派生量计算（CASE 内只置 TRUE，杜绝故障相残留） —— *)
_bValveA    := FALSE;                                               // A 阀命令每拍先撤 [bool] A valve withdrawn first each scan
_bValveB    := FALSE;                                               // B 阀命令每拍先撤 [bool] B valve withdrawn first each scan
_bAgitator  := FALSE;                                               // 搅拌命令每拍先撤 [bool] agitator withdrawn first each scan
_bDischarge := FALSE;                                               // 排料阀命令每拍先撤 [bool] discharge withdrawn first each scan
_bSampleReq := FALSE;                                               // 取样请求每拍先撤 [bool] sample request withdrawn first each scan
_rProg      := DL_BLD_ZERO;                                         // 进度中间量每拍清零 [%] progress intermediate cleared each scan
_rVolTotal  := rVolA_sp + rVolB_sp;                                 // 配方总量求和 [m3] recipe total volume
_bRunActive := (_eState = E_DL_BlendState.eFillA) OR (_eState = E_DL_BlendState.eFillB)
               OR (_eState = E_DL_BlendState.eCirculate) OR (_eState = E_DL_BlendState.eSample)
               OR (_eState = E_DL_BlendState.eRelease);             // 运行相关相标志（用状态量，R99）[bool] running phase flag from the state
_bInBand    := FALSE;                                               // 进带标志复位 [bool] in-band flag reset
IF (rTempBand > DL_BLD_ZERO) AND (rConcBand > DL_BLD_ZERO) THEN
    IF (ABS(rTempAct - rTempSp) <= rTempBand) AND (ABS(rConcAct - rConcSp) <= rConcBand) THEN
        _bInBand := TRUE;                                           // 双判同时进带 [bool] both criteria inside band
    END_IF
END_IF

(* —— 段 1：组态域闸与容量保护（十个浮点入参全枚举，非有限双判 R151 / R79） —— *)
_bCfgOk := TRUE;                                                    // 组态闸标志初值 [bool] configuration flag initial value
IF (rVolA_sp <> rVolA_sp) OR ((rVolA_sp - rVolA_sp) <> DL_BLD_ZERO)
   OR (rVolB_sp <> rVolB_sp) OR ((rVolB_sp - rVolB_sp) <> DL_BLD_ZERO)
   OR (rVolAct <> rVolAct) OR ((rVolAct - rVolAct) <> DL_BLD_ZERO)
   OR (rMaxVolume <> rMaxVolume) OR ((rMaxVolume - rMaxVolume) <> DL_BLD_ZERO)
   OR (rTempAct <> rTempAct) OR ((rTempAct - rTempAct) <> DL_BLD_ZERO)
   OR (rTempSp <> rTempSp) OR ((rTempSp - rTempSp) <> DL_BLD_ZERO)
   OR (rTempBand <> rTempBand) OR ((rTempBand - rTempBand) <> DL_BLD_ZERO)
   OR (rConcAct <> rConcAct) OR ((rConcAct - rConcAct) <> DL_BLD_ZERO)
   OR (rConcSp <> rConcSp) OR ((rConcSp - rConcSp) <> DL_BLD_ZERO)
   OR (rConcBand <> rConcBand) OR ((rConcBand - rConcBand) <> DL_BLD_ZERO) THEN
    _bCfgOk := FALSE;                                               // 非有限入参：拒收（NaN 自反 + Inf 差值自减）[bool] non finite input rejected
END_IF
IF _bCfgOk THEN
    IF (rVolA_sp < DL_BLD_ZERO) OR (rVolB_sp < DL_BLD_ZERO) OR (rMaxVolume <= DL_BLD_ZERO) THEN
        _bCfgOk := FALSE;                                           // 负体积或非正罐容 [bool] negative volume or non positive capacity
    ELSIF (_rVolTotal <= DL_BLD_ZERO) THEN
        _bCfgOk := FALSE;                                           // 配方总量为零 [bool] zero recipe total volume
    ELSIF (rTempBand < DL_BLD_EPS) OR (rConcBand < DL_BLD_EPS) THEN
        _bCfgOk := FALSE;                                           // 容差带为零或负 [bool] zero or negative tolerance band
    ELSIF (tFillTimeout < DL_BLD_T_MIN) OR (tFillTimeout > DL_BLD_T_MAX) THEN
        _bCfgOk := FALSE;                                           // 进料超时越域 [bool] feed timeout out of domain
    ELSIF (tCircTimeout < DL_BLD_T_MIN) OR (tCircTimeout > DL_BLD_T_MAX) THEN
        _bCfgOk := FALSE;                                           // 循环超时越域 [bool] circulation timeout out of domain
    ELSIF (tSampleTimeout < DL_BLD_T_MIN) OR (tSampleTimeout > DL_BLD_T_MAX) THEN
        _bCfgOk := FALSE;                                           // 取样超时越域 [bool] sample timeout out of domain
    ELSIF (tCircStable < DL_BLD_T_MIN) OR (tCircStable > DL_BLD_T_MAX) THEN
        _bCfgOk := FALSE;                                           // 进带确认窗越域 [bool] in-band window out of domain
    ELSIF (tReleaseTimeout < DL_BLD_T_MIN) OR (tReleaseTimeout > DL_BLD_T_MAX) THEN
        _bCfgOk := FALSE;                                           // 排料超时越域 [bool] release timeout out of domain
    ELSIF NOT bRecipeValid THEN
        _bCfgOk := FALSE;                                           // 配方无效回执为假 [bool] recipe valid receipt is false
    END_IF
END_IF
IF (NOT _bCfgOk) AND (NOT _bFaultLatch) AND (bStart OR _bRunActive) THEN
    _nFault      := 6;                                              // 故障级：配方无效 / 参数非法 [码] fault: invalid recipe or parameter
    _bFaultLatch := TRUE;                                           // 置故障锁存 [bool] latch the fault
    bError       := TRUE;                                           // R45 配对：故障标志同拍置位 [bool] paired error flag
END_IF
IF (NOT _bFaultLatch) AND (bStart OR _bRunActive) THEN
    IF _rVolTotal > rMaxVolume THEN
        _nFault      := 4;                                          // 故障级：配方总量超罐容 [码] fault: recipe total exceeds tank volume
        _bFaultLatch := TRUE;                                       // 置故障锁存 [bool] latch the fault
        bError       := TRUE;                                       // R45 配对：故障标志同拍置位 [bool] paired error flag
    END_IF
END_IF

(* —— 段 2：边沿与定时器（CASE 外无条件周期调用，R7；IN 含 NOT .Q 自复位与 NOT 锁存，R188） —— *)
rtAbort(CLK := bAbort);                                             // bAbort 边沿无条件刷新 [bool] abort edge refreshed unconditionally
tonFill(IN := ((_eState = E_DL_BlendState.eFillA) OR (_eState = E_DL_BlendState.eFillB))
              AND (NOT tonFill.Q) AND (NOT _bFaultLatch),
        PT := tFillTimeout);                                        // 进料总超时（跨两相累计，进相自然复位）[s] total feed timeout across both phases
tonCirc(IN := (_eState = E_DL_BlendState.eCirculate) AND (NOT tonCirc.Q) AND (NOT _bFaultLatch),
        PT := tCircTimeout);                                        // 循环调和超时 [s] circulation timeout
tonStable(IN := (_eState = E_DL_BlendState.eCirculate) AND _bInBand AND (NOT tonStable.Q)
               AND (NOT _bFaultLatch),
          PT := tCircStable);                                       // 双判进带持续确认 [s] in-band persistence confirmation
tonSample(IN := (_eState = E_DL_BlendState.eSample) AND (NOT tonSample.Q) AND (NOT _bFaultLatch),
          PT := tSampleTimeout);                                    // 取样回执超时 [s] sample receipt timeout
tonRelease(IN := (_eState = E_DL_BlendState.eRelease) AND (NOT tonRelease.Q) AND (NOT _bFaultLatch),
           PT := tReleaseTimeout);                                  // 排料超时 [s] release timeout

(* —— 段 3：人工中止优先消化（置锁存不写相位，迁相由段 6 统一执行，R21 / R275） —— *)
IF rtAbort.Q AND (NOT _bFaultLatch) THEN
    _nFault      := 5;                                              // 故障级：人工中止 [码] fault: manual abort
    _bFaultLatch := TRUE;                                           // 置故障锁存 [bool] latch the fault
    bError       := TRUE;                                           // R45 配对：故障标志同拍置位 [bool] paired error flag
END_IF

(* —— 段 4：主状态机（相位写入点之二；每成员独立标签，ELSE 只兜非法值） —— *)
CASE _eState OF
E_DL_BlendState.eIdle :                                             // 空闲相：全部阀位已撤，等启动与配方许可
    IF bStart AND _bCfgOk AND (NOT bAbort) AND (NOT _bFaultLatch) THEN
        _eState := E_DL_BlendState.eFillA;                          // 迁移：进入 A 进料相（次拍开阀）[phase] move to fill A
    END_IF

E_DL_BlendState.eFillA :                                            // A 进料相：开 A 阀
    _bValveA := TRUE;                                               // 开 A 组分进料阀 [bool] open the component A feed valve
    IF rVolAct >= (rVolA_sp - DL_BLD_EPS) THEN
        _eState := E_DL_BlendState.eFillB;                          // 迁移：A 组分量已到位 [phase] component A volume reached
    ELSIF rVolAct > rMaxVolume THEN
        _nFault      := 4;                                          // 故障级：累计体积超罐容 [码] fault: accumulated volume over capacity
        _bFaultLatch := TRUE;                                       // 置故障锁存 [bool] latch the fault
        bError       := TRUE;                                       // R45 配对：故障标志同拍置位 [bool] paired error flag
    END_IF

E_DL_BlendState.eFillB :                                            // B 进料相：开 B 阀至总量
    _bValveB := TRUE;                                               // 开 B 组分进料阀 [bool] open the component B feed valve
    IF rVolAct >= (_rVolTotal - DL_BLD_EPS) THEN
        _eState := E_DL_BlendState.eCirculate;                      // 迁移：总量到位进入循环调和 [phase] total volume reached, start circulation
    ELSIF rVolAct > rMaxVolume THEN
        _nFault      := 4;                                          // 故障级：累计体积超罐容 [码] fault: accumulated volume over capacity
        _bFaultLatch := TRUE;                                       // 置故障锁存 [bool] latch the fault
        bError       := TRUE;                                       // R45 配对：故障标志同拍置位 [bool] paired error flag
    END_IF

E_DL_BlendState.eCirculate :                                        // 循环调和相：搅拌运行，温度与浓度双判
    _bAgitator := TRUE;                                             // 搅拌保持开（保证均质）[bool] agitator held on for homogeneity
    IF tonStable.Q THEN
        _eState := E_DL_BlendState.eSample;                         // 迁移：双判进带持续满足 [phase] both criteria held inside band
    END_IF

E_DL_BlendState.eSample :                                           // 取样相：请求外部取样并等待回执
    _bAgitator  := TRUE;                                            // 取样期间保持搅拌（样品代表性）[bool] agitator held during sampling
    _bSampleReq := TRUE;                                            // 置取样请求（电平保持）[bool] sample request level held
    IF bSampleDone THEN
        _eState := E_DL_BlendState.eRelease;                        // 迁移（出口 1）：外部取样完成 [phase] external sampling completed
    END_IF

E_DL_BlendState.eRelease :                                          // 排料相：开排料阀至低液位
    _bDischarge := TRUE;                                            // 开排料阀（搅拌停，避免抽空涡流）[bool] open the discharge valve
    IF bLevelLow THEN
        _eState := E_DL_BlendState.eDone;                           // 迁移（出口 1）：低液位到位 [phase] low level reached
    END_IF

E_DL_BlendState.eDone :                                             // 完成相：bDone 由相位派生，等撤令
    IF NOT bStart THEN
        _eState := E_DL_BlendState.eIdle;                           // 迁移：撤除启动命令回空闲 [phase] start withdrawn, back to idle
    END_IF

E_DL_BlendState.eFault :                                            // 故障锁存相：阀位已由段 6 全撤
    IF rtAbort.Q OR ((NOT bStart) AND (NOT bAbort)) THEN
        _bFaultLatch := FALSE;                                      // 复位出口：清故障锁存 [bool] clear the fault latch
        _nFault      := 0;                                          // 复位出口：清故障码 [码] clear the fault code
        _eState      := E_DL_BlendState.eIdle;                      // 复位出口：迁回空闲 [phase] back to idle
    END_IF

ELSE                                                                // 非法枚举值兜底（R6 / FB32-5）
    IF NOT _bFaultLatch THEN
        _nFault      := 8;                                          // 故障级：非法状态枚举值 [码] fault: illegal state enum value
        _bFaultLatch := TRUE;                                       // 置故障锁存 [bool] latch the fault
        bError       := TRUE;                                       // R45 配对：故障标志同拍置位 [bool] paired error flag
    END_IF
    _eState := E_DL_BlendState.eFault;                              // 非法值一律落安全相 [phase] illegal value falls into the safe phase
END_CASE

(* —— 段 5：超时看门狗锁存（本拍合法事件优先于超时：状态已迁出则该相看门狗不生效，R275） —— *)
IF tonFill.Q AND (NOT _bFaultLatch)
   AND ((_eState = E_DL_BlendState.eFillA) OR (_eState = E_DL_BlendState.eFillB)) THEN
    _nFault      := 1;                                              // 故障级：进料超时 [码] fault: feed timeout
    _bFaultLatch := TRUE;                                           // 置故障锁存 [bool] latch the fault
    bError       := TRUE;                                           // R45 配对：故障标志同拍置位 [bool] paired error flag
END_IF
IF tonCirc.Q AND (NOT _bFaultLatch) AND (_eState = E_DL_BlendState.eCirculate) THEN
    _nFault      := 2;                                              // 故障级：循环收敛超时 [码] fault: circulation convergence timeout
    _bFaultLatch := TRUE;                                           // 置故障锁存 [bool] latch the fault
    bError       := TRUE;                                           // R45 配对：故障标志同拍置位 [bool] paired error flag
END_IF
IF tonSample.Q AND (NOT _bFaultLatch) AND (_eState = E_DL_BlendState.eSample) THEN
    _nFault      := 3;                                              // 故障级：取样超时 [码] fault: sampling timeout
    _bFaultLatch := TRUE;                                           // 置故障锁存 [bool] latch the fault
    bError       := TRUE;                                           // R45 配对：故障标志同拍置位 [bool] paired error flag
END_IF
IF tonRelease.Q AND (NOT _bFaultLatch) AND (_eState = E_DL_BlendState.eRelease) THEN
    _nFault      := 7;                                              // 故障级：排料超时 [码] fault: release timeout
    _bFaultLatch := TRUE;                                           // 置故障锁存 [bool] latch the fault
    bError       := TRUE;                                           // R45 配对：故障标志同拍置位 [bool] paired error flag
END_IF

(* —— 段 6：段尾故障迁移闸 + 撤令安全停机 + 故障/空闲相动作全撤（FB50-1④ / R191 显式声明） —— *)
IF _bFaultLatch AND (_eState <> E_DL_BlendState.eFault) THEN
    _eState := E_DL_BlendState.eFault;                              // 锁存即迁相（锁存与迁相分离，R21）[phase] a latch forces the fault phase
END_IF
IF (NOT bStart) AND _bRunActive AND (NOT _bFaultLatch) THEN
    (* 撤令语义（R191 二选一，本件选「降级为安全值 + 回空闲，不置故障码」）：阀位全撤、相位回空闲 *)
    _eState := E_DL_BlendState.eIdle;                               // 撤令即安全停机回空闲 [phase] withdrawn start stops safely into idle
END_IF
IF (_eState = E_DL_BlendState.eFault) OR (_eState = E_DL_BlendState.eIdle) THEN
    _bValveA    := FALSE;                                           // 空闲/故障：A 阀全撤 [bool] A valve withdrawn in idle and fault
    _bValveB    := FALSE;                                           // 空闲/故障：B 阀全撤 [bool] B valve withdrawn in idle and fault
    _bAgitator  := FALSE;                                           // 空闲/故障：搅拌全撤 [bool] agitator withdrawn in idle and fault
    _bDischarge := FALSE;                                           // 空闲/故障：排料阀全撤 [bool] discharge withdrawn in idle and fault
    _bSampleReq := FALSE;                                           // 空闲/故障：取样请求撤除 [bool] sample request withdrawn in idle and fault
END_IF

(* —— 段 7：统一出口（相位映射 + 进度换算 + 锁存码回放；单一写入点） —— *)
IF ((_eState = E_DL_BlendState.eFillA) OR (_eState = E_DL_BlendState.eFillB)) AND _bCfgOk THEN
    IF _rVolTotal > DL_BLD_EPS THEN
        _rProg := LIMIT(DL_BLD_ZERO, (rVolAct * DL_BLD_HUNDRED) / _rVolTotal, DL_BLD_HUNDRED); // 进料完成度（除子已双检，R4）[%] feed completion
    END_IF
ELSIF (_eState = E_DL_BlendState.eCirculate) OR (_eState = E_DL_BlendState.eSample)
   OR (_eState = E_DL_BlendState.eRelease) OR (_eState = E_DL_BlendState.eDone) THEN
    _rProg := DL_BLD_HUNDRED;                                       // 进料已完成，其后各相进度满量程 [%] feed finished, later phases at full scale
END_IF
bValveA      := _bValveA;                                           // A 阀命令出口 [bool] A valve command outlet
bValveB      := _bValveB;                                           // B 阀命令出口 [bool] B valve command outlet
bAgitator    := _bAgitator;                                         // 搅拌命令出口 [bool] agitator command outlet
bDischarge   := _bDischarge;                                        // 排料阀命令出口 [bool] discharge command outlet
bSampleReq   := _bSampleReq;                                        // 取样请求出口 [bool] sample request outlet
eState       := _eState;                                            // 相位出口 [phase] phase outlet
bDone        := (_eState = E_DL_BlendState.eDone);                  // 完成位由相位派生（非单拍脉冲）[bool] done derived from the phase
nFaultCode   := _nFault;                                            // 故障码出口（锁存回放）[码] fault code outlet replayed from the latch
rProgressPct := _rProg;                                             // 进度出口 [%] progress outlet
bError       := _bFaultLatch;                                       // 故障标志取锁存位 [bool] fault flag from the latch
END_FUNCTION_BLOCK
