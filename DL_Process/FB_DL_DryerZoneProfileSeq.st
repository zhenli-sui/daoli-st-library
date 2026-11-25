(*
  ============================================================
  组件名 : FB_DL_DryerZoneProfileSeq
  分类   : DL_Process
  功能   : 多温区烘干升温曲线执行（预热 → 斜率限制升温 → 保温 → 冷却 → 完成），含超温退避、升温超时、区号越界、超温持续、人工停止、冷却超时六类保护
  开源溯源 : internal-design（本轮无外部代码逐行引用）；参考语义 : 无外部参考
  复杂度 : C4
  版本   : 1.0.0
  ============================================================
*)

(*-----------------------------------------------------------------------------
 * 状态迁移表（ENUM 成员 → 出口；每成员均有可到达出口，零无界驻留相）：
 *   eIdle     → ePreheat  : bStart 且 bStop = FALSE 且区号合法且组态闸通过
 *   eIdle     ── 保持，直到启动（待机相以启动命令为唯一出口，属许可型驻留）
 *   ePreheat  → eRampUp   : 全部有效区 aTempAct ≥ 目标×0.3 - 保温带 ｜ 超温退避（设定冻结）
 *   ePreheat  → eFault    : tonRamp.Q（码 1 升温超时）｜ rtStop.Q（码 4 人工停止）
 *   eRampUp   → eSoak     : 最冷区 aTempAct ≥ (目标 - 保温带) - 1E-6
 *   eRampUp   ── 超温退避时驻留本相（不退相，只撤加热并冻结 aTempSp，超温持续由码 3 兜底）
 *   eRampUp   → eFault    : tonRamp.Q（码 1）｜ tonOverTemp.Q（码 3）｜ rtStop.Q（码 4）
 *   eSoak     → eCoolDown : tonSoak.Q（保温时间到）
 *   eSoak     → eRampUp   : 超温退避（设定冻结后回升温相）
 *   eSoak     → eFault    : tonOverTemp.Q（码 3）｜ rtStop.Q（码 4）
 *   eCoolDown → eDone     : 最热区 aTempAct ≤ 目标×0.2 + 1E-6
 *   eCoolDown → eFault    : tonCool.Q（码 5 冷却超时）｜ rtStop.Q（码 4）
 *   eDone     → eIdle     : bStart 撤除 ｜ rtStop.Q（完成相撤令）
 *   eFault    → eIdle     : bStop 上升沿（清锁存、清全部设定与输出）
 *   ELSE（非法枚举值，非任何成员）→ eFault（码 7）
 *
 * 故障码表（nFaultCode，0 = 无故障；非首码均附「现有输出不可观测」反证句，R90）：
 *   1 升温超时   : tonRamp 覆盖 ePreheat + eRampUp（相序串行，进 ePreheat 时计时器自然复位）。
 *   2 区号越界   : 反证——区号越域时 aTempSp 全零、bHeaterEnable = FALSE，与码 1 的输出组合同形，
 *                  复用码 1 会把「组态写错温区数」报成「加热能力不足」，导致加功率的错误处置。
 *   3 超温持续   : 反证——bHeaterEnable 已由退避撤除、aTempSp 冻结，故障相动作全撤后与码 1 的
 *                  观测量一致；复用码 1 会掩盖「超温保护未及时动作」这一安全相关首因。
 *   4 人工停止   : 反证——操作员主动停机属安全审计事件，必须与设备异常分离，
 *                  否则无法在停机记录中区分人为与故障。
 *   5 冷却超时   : 反证——冷却相 bHeaterEnable = FALSE 且 bCoolFanEnable = TRUE，故障撤除后
 *                  与码 1 全同；复用码 1 会让运维去查加热回路而非冷却风机/水路。
 *   6 参数非法   : 反证——非法参数在启动瞬间即拦截，此时无加热、无爬升历史，
 *                  与任何超时码的时序签名互斥，必须独立成码。
 *   7 非法状态   : 反证——非法枚举值为程序缺陷而非工艺事件，合并入任一工艺码会让固件错误
 *                  被误排为现场故障，必须独立成码。
 *
 * 依赖     : 仅 IEC 61131-3 标准库（TON / R_TRIG / ABS / LIMIT），零厂商私有库
 * 代理节拍 : R95 三句声明——① 代理值为固定 100ms 爬升节拍（DL_DRY_DT），本件无采样周期引脚；
 *            ② 覆盖任务周期 ≤ 100ms 的常规配置；③ 任务周期 > 100ms 的区间由上层循环周期
 *            监视件负责，本件不做补偿（周期超限时爬升偏慢，属验收债项）。
 * 分工声明 : 各温区独立 PID 与加热功率分配归温区调节件；本件只输出区级温度设定曲线与
 *            加热/冷却使能，不做连续调节、不做风机电流保护。
 * 归属     : E_DL_DryerState 归属本文件（全库唯一定义，R264；引用件只引用不重声明）。
 * 修订历史 : 2026-11-25  v1.0.0  首版（编码席 dlf-plc-coder，第二批 C4）
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 边界与红线自检：
 * ① 五个 TON 与一个 R_TRIG 全部在 CASE 外无条件周期调用（R7）；时间类 IN 均含 NOT .Q 自复位项
 *    与 NOT 故障锁存项（R188 / FB50-1③），CASE 内只读 .Q。
 * ② aTempSp 是「保持槽」而非单拍量：段 7 统一出口按相映射，eIdle / eFault 相强制全零，
 *    且段 6 在故障/空闲相把内部曲线 _aSpRamp 一并清零 —— 上轮 MAJOR 型「故障后残留旧设定」已双重封堵。
 * ③ 超温退避（R191 显式声明）：段 6 撤加热但不迁相，aTempSp 冻结于当前值；超温持续超
 *    tOverTempLimit 才由 tonOverTemp 锁存码 3。段 5 判定序保证同拍时码 3 优先于码 1。
 * ④ 斜率限制：eRampUp 内 aTempSp 每 100ms 节拍只推进 rRampRate/60 × 0.1 K，并饱和到
 *    (目标 - 保温带)，不存在阶跃路径；未装区（下标 ≥ _nZoneClamp）恒写 0。
 * ⑤ 看门狗使能域（R145）：tonRamp / tonSoak / tonCool 的 IN 只取相驻留本身，不叠加业务条件补集。
 * ⑥ 三族循环（R271）：本件只用 FOR，逐对计数 FOR ↔ END_FOR 相等（交付前行数复核）。
 * ⑦ 组态域闸枚举全部浮点入参（含数组四个元素）：aTempAct[0..3] / rTempTarget / rRampRate /
 *    rSoakBand / rOverTempLimit，NaN 自反 + Inf 差值自减双判（R151 / R79）。
 * ⑧ 零全局耦合：无 GVL / VAR_EXTERNAL / %I / %Q（R1 / R2）。
 * ⑨ 相位写入点共两处且互斥：段 4 CASE、段 6 段尾迁移闸。
 *----------------------------------------------------------------------------*)

TYPE E_DL_DryerState :
(
    eIdle     := 0, // 空闲：加热与冷却全停，区级设定全零 idle: heater and fan off, all zone setpoints zero
    ePreheat  := 1, // 预热相：各区设定升至目标×0.3，加热使能 preheat: zone setpoints at 0.3 of the target, heater enabled
    eRampUp   := 2, // 升温相：按 rRampRate 斜率限制爬升 ramp up: climbing with the slope limited by rRampRate
    eSoak     := 3, // 保温相：设定保持目标温度等 tSoakTime soak: setpoints held at the target until tSoakTime elapses
    eCoolDown := 4, // 冷却相：关加热、开冷却风机，设定全零 cool down: heater off, cooling fan on, setpoints zero
    eFault    := 5, // 故障锁存相：加热与冷却全停，设定全零，只由 bStop 沿迁出 fault: all outputs off, left only by the bStop edge
    eDone     := 6  // 完成相：曲线结束，等撤令 done: profile finished, waiting for the start to be withdrawn
);
END_TYPE

FUNCTION_BLOCK FB_DL_DryerZoneProfileSeq
VAR_INPUT
    bStart          : BOOL := FALSE;                          // 启动/运行许可（电平）：撤除即回空闲 [bool] start and run permissive level
    bStop           : BOOL := FALSE;                          // 人工停止（上升沿）：运行中置码 4，故障相为复位沿 [bool] manual stop rising edge, code 4 while running and the reset edge in fault
    nZoneCount      : INT := 4;                               // 装机温区数，有效域 1..4 [区] installed zone count, valid domain 1..4
    aTempAct        : ARRAY[0..3] OF REAL;                    // 各区实测温度 [degC] measured temperature per zone [degC]
    rTempTarget     : REAL := 80.0;                           // 工艺目标温度，域 > 0 [degC] process target temperature, domain > 0 [degC]
    rRampRate       : REAL := 2.0;                             // 升温斜率，域 > 0 [K/min] ramp rate, domain > 0 [K/min]
    rSoakBand       : REAL := 2.0;                            // 保温带（升温转保温的余量），域 ≥ 0 [K] soak band used by the ramp to soak transition [K]
    tSoakTime       : TIME := T#30M;                          // 保温时长 [s] soak duration [s]
    rOverTempLimit  : REAL := 100.0;                          // 超温保护门限，域 > rTempTarget [degC] over temperature limit, domain above the target [degC]
    tRampTimeout    : TIME := T#60M;                          // 预热+升温总超时窗，亦作冷却超时窗 [s] preheat and ramp timeout, also used by the cooling phase
    tOverTempLimit  : TIME := T#10S;                          // 超温持续判故障窗 [s] over temperature persistence window before the fault [s]
END_VAR
VAR_OUTPUT
    aTempSp          : ARRAY[0..3] OF REAL;                   // 各区温度设定曲线（段 7 统一映射，空闲/故障相强制全零）[degC] zone setpoint profile forced to zero in idle and fault
    eState           : E_DL_DryerState;                       // 相位出口（段 7 单点映射）[-] phase outlet mapped once in section 7
    bHeaterEnable    : BOOL;                                  // 加热总使能（超温退避与故障/空闲相强制 FALSE）[bool] heater master enable forced off on retreat and in idle/fault
    bCoolFanEnable   : BOOL;                                  // 冷却风机使能（仅冷却相）[bool] cooling fan enable, cooling phase only
    bOverTempAlarm   : BOOL;                                  // 超温告警（本体超温 或 超温故障锁存派生）[bool] over temperature alarm derived from the condition or the latched code
    bDone            : BOOL;                                  // 曲线完成（由相位派生，非单拍脉冲）[bool] profile done derived from the phase as a level
    nFaultCode       : INT;                                   // 故障码 0 无 1 升温超时 2 区号越界 3 超温持续 4 人工停止 5 冷却超时 6 参数非法 7 非法状态 [码] fault code
    rRampProgressPct : REAL;                                  // 最冷区温度相对目标的完成度 0..100 [%] coldest zone temperature versus target in percent [%]
    bError           : BOOL;                                  // 故障锁存标志（取锁存位，R45 配对出口）[bool] fault latch flag used as the paired outlet
END_VAR
VAR
    _eState       : E_DL_DryerState := E_DL_DryerState.eIdle;  // 内部相位（CASE 唯一比较目标）[-] internal phase compared by the CASE
    _bFaultLatch  : BOOL := FALSE;                             // 故障锁存位（仅 bStop 沿清除）[bool] fault latch, cleared only by the bStop edge
    _nFault       : INT := 0;                                  // 锁存故障码（故障期回放，不按当下输入重算）[码] latched fault code replayed in the fault phase
    _bCfgOk       : BOOL := FALSE;                             // 组态与入参域闸通过标志 [bool] configuration and input domain gate flag
    _bRunActive   : BOOL := FALSE;                             // 曲线执行相标志（预热到冷却）[bool] profile running phase flag from preheat to cool down
    _bHeater      : BOOL := FALSE;                             // 内部加热使能状态 [bool] internal heater enable state
    _bCoolFan     : BOOL := FALSE;                             // 内部冷却风机状态 [bool] internal cooling fan state
    _bOverTemp    : BOOL := FALSE;                             // 任一有效区超温标志 [bool] any active zone over the limit
    _aSpRamp      : ARRAY[0..3] OF REAL;                       // 内部区级设定保持槽（保持槽，非单拍量）[degC] internal zone setpoint holding slots
    _nZoneClamp   : INT := 1;                                  // 区数钳位值 1..4 [区] clamped zone count
    _nIdx         : INT := 0;                                  // 区遍历下标（FOR 专用）[区] zone loop index
    _rMinAct      : REAL := 0.0;                               // 有效区实测温度最小值（最冷区）[degC] minimum measured temperature of the active zones [degC]
    _rMaxAct      : REAL := 0.0;                               // 有效区实测温度最大值（最热区）[degC] maximum measured temperature of the active zones [degC]
    _rPreheatSp   : REAL := 0.0;                               // 预热设定 = 目标 × 0.3 [degC] preheat setpoint at 0.3 of the target [degC]
    _rCoolSp      : REAL := 0.0;                               // 冷却终点 = 目标 × 0.2 [degC] cooling end point at 0.2 of the target [degC]
    _rRampCeil    : REAL := 0.0;                               // 升温上限 = 目标 - 保温带 [degC] ramp ceiling at the target minus the soak band [degC]
    _rStep        : REAL := 0.0;                               // 单个节拍的爬升增量 [K] ramp increment of one tick [K]
    _rDtStep      : REAL := 0.0;                               // 本拍节拍秒数（非节拍拍为 0）[s] tick seconds of this scan, zero on non tick scans [s]
    _rProg        : REAL := 0.0;                               // 完成度中间量 [%] progress intermediate value [%]
    rtStop        : R_TRIG;                                    // bStop 上升沿实例（段 2 无条件调用）[bool] stop rising edge instance
    tonDtTick     : TON;                                       // 爬升节拍发生器（段 2 无条件调用，IN := NOT .Q 自复位）[s] ramp tick generator with self reset
    tonRamp       : TON;                                       // 预热+升温总超时计时（段 2 无条件调用）[s] preheat and ramp timeout
    tonSoak       : TON;                                       // 保温时长计时（段 2 无条件调用）[s] soak duration timer
    tonCool       : TON;                                       // 冷却超时计时（段 2 无条件调用）[s] cooling timeout timer
    tonOverTemp   : TON;                                       // 超温持续计时（段 2 无条件调用）[s] over temperature persistence timer
END_VAR
VAR CONSTANT
    DL_DRY_ZERO          : REAL := 0.0;      // 浮点零基准 [degC] float zero base
    DL_DRY_ONE           : REAL := 1.0;      // 浮点一基准 [-] float one base
    DL_DRY_HUNDRED       : REAL := 100.0;    // 百分比满量程 [%] percent full scale
    DL_DRY_SIXTY         : REAL := 60.0;     // 每分钟秒数（K/min → K/s 换算）[s] seconds per minute for the K/min conversion
    DL_DRY_EPS           : REAL := 1.0E-6;   // 温度比较容差 [K] temperature comparison tolerance
    DL_DRY_PREHEAT_RATIO : REAL := 0.3;      // 预热比例（目标×0.3）[-] preheat ratio of the target
    DL_DRY_COOL_RATIO    : REAL := 0.2;      // 冷却终点比例（目标×0.2）[-] cooling end ratio of the target
    DL_DRY_DT_SEC        : REAL := 0.1;      // 爬升节拍秒数 [s] ramp tick length in seconds
    DL_DRY_DT            : TIME := T#100MS;  // 爬升节拍周期 [s] ramp tick period
    DL_DRY_IDX_MIN       : INT := 1;         // 区下标起点（下标 0 由初值行处理）[区] zone index start whose index zero is handled by the initialisation line
    DL_DRY_ZONE_MAX      : INT := 3;         // 区下标上限（定长数组上界）[区] zone index upper bound of the fixed array
    DL_DRY_ZONE_CNT_MAX  : INT := 4;         // 温区数上限（定长数组元素个数）[区] zone count upper bound of the fixed array
    DL_DRY_T_MIN         : TIME := T#100MS;  // 时间参数下限 [s] lower bound of the time parameters
    DL_DRY_T_MAX         : TIME := T#8H;     // 时间参数上限 [s] upper bound of the time parameters
END_VAR

(* —— 段 0：安全侧出口预置、区数钳位、温度极值与超温判据（CASE 只置 TRUE / 只推进曲线） —— *)
_bHeater   := FALSE;                                                // 加热使能每拍先撤（CASE 内只置 TRUE）[bool] heater withdrawn first each scan
_bCoolFan  := FALSE;                                                // 冷却风机每拍先撤（CASE 内只置 TRUE）[bool] cooling fan withdrawn first each scan
_rProg     := DL_DRY_ZERO;                                          // 完成度中间量每拍清零 [%] progress intermediate cleared each scan
_nZoneClamp := LIMIT(DL_DRY_IDX_MIN, nZoneCount, DL_DRY_ZONE_CNT_MAX); // 区数钳位 1..4（数组下标安全）[区] clamp the zone count
_rPreheatSp := rTempTarget * DL_DRY_PREHEAT_RATIO;                  // 预热设定 = 目标 × 0.3 [degC] preheat setpoint
_rCoolSp    := rTempTarget * DL_DRY_COOL_RATIO;                     // 冷却终点 = 目标 × 0.2 [degC] cooling end point
_rRampCeil  := rTempTarget - rSoakBand;                             // 升温上限 = 目标 - 保温带 [degC] ramp ceiling
IF _rRampCeil < DL_DRY_ZERO THEN
    _rRampCeil := DL_DRY_ZERO;                                      // 上限负值钳零（防负爬升目标）[degC] clamp a negative ceiling to zero
END_IF
_rMinAct   := aTempAct[0];                                          // 最冷区初值取下标 0 [degC] coldest zone seeded with index zero
_rMaxAct   := aTempAct[0];                                          // 最热区初值取下标 0 [degC] hottest zone seeded with index zero
_bOverTemp := (aTempAct[0] > rOverTempLimit);                       // 下标 0 的超温判据 [bool] over temperature check of index zero
FOR _nIdx := DL_DRY_IDX_MIN TO DL_DRY_ZONE_MAX DO
    IF _nIdx < _nZoneClamp THEN
        IF aTempAct[_nIdx] < _rMinAct THEN
            _rMinAct := aTempAct[_nIdx];                            // 刷新最冷区 [degC] refresh the coldest zone
        END_IF
        IF aTempAct[_nIdx] > _rMaxAct THEN
            _rMaxAct := aTempAct[_nIdx];                            // 刷新最热区 [degC] refresh the hottest zone
        END_IF
        IF aTempAct[_nIdx] > rOverTempLimit THEN
            _bOverTemp := TRUE;                                     // 任一有效区超温 [bool] any active zone over the limit
        END_IF
    END_IF
END_FOR
_bRunActive := (_eState = E_DL_DryerState.ePreheat) OR (_eState = E_DL_DryerState.eRampUp)
               OR (_eState = E_DL_DryerState.eSoak) OR (_eState = E_DL_DryerState.eCoolDown); // 曲线执行相标志（用状态量，R99）[bool] profile running flag

(* —— 段 1：组态域闸（浮点入参含数组四元素全枚举；区号越界独立成员判定，R151 / R79） —— *)
_bCfgOk := TRUE;                                                    // 组态闸标志初值 [bool] configuration flag initial value
IF (aTempAct[0] <> aTempAct[0]) OR ((aTempAct[0] - aTempAct[0]) <> DL_DRY_ZERO)
   OR (aTempAct[1] <> aTempAct[1]) OR ((aTempAct[1] - aTempAct[1]) <> DL_DRY_ZERO)
   OR (aTempAct[2] <> aTempAct[2]) OR ((aTempAct[2] - aTempAct[2]) <> DL_DRY_ZERO)
   OR (aTempAct[3] <> aTempAct[3]) OR ((aTempAct[3] - aTempAct[3]) <> DL_DRY_ZERO)
   OR (rTempTarget <> rTempTarget) OR ((rTempTarget - rTempTarget) <> DL_DRY_ZERO)
   OR (rRampRate <> rRampRate) OR ((rRampRate - rRampRate) <> DL_DRY_ZERO)
   OR (rSoakBand <> rSoakBand) OR ((rSoakBand - rSoakBand) <> DL_DRY_ZERO)
   OR (rOverTempLimit <> rOverTempLimit) OR ((rOverTempLimit - rOverTempLimit) <> DL_DRY_ZERO) THEN
    _bCfgOk := FALSE;                                               // 非有限入参：拒收（NaN 自反 + Inf 差值自减）[bool] non finite input rejected
END_IF
IF (bStart OR _bRunActive) AND (NOT _bFaultLatch) THEN
    IF (nZoneCount < DL_DRY_IDX_MIN) OR (nZoneCount > DL_DRY_ZONE_CNT_MAX) THEN
        _nFault      := 2;                                          // 故障级：区号越界（独立成因，R190）[码] fault: zone count out of domain
        _bFaultLatch := TRUE;                                       // 置故障锁存 [bool] latch the fault
        bError       := TRUE;                                       // R45 配对：故障标志同拍置位 [bool] paired error flag
    ELSE
        IF (NOT _bCfgOk) THEN
            _nFault      := 6;                                      // 故障级：参数非法（非有限/越域）[码] fault: illegal parameter
            _bFaultLatch := TRUE;                                   // 置故障锁存 [bool] latch the fault
            bError       := TRUE;                                   // R45 配对：故障标志同拍置位 [bool] paired error flag
        ELSIF (rTempTarget <= DL_DRY_ZERO) OR (rRampRate <= DL_DRY_ZERO) THEN
            _nFault      := 6;                                      // 故障级：目标或斜率非正 [码] fault: non positive target or ramp rate
            _bFaultLatch := TRUE;                                   // 置故障锁存 [bool] latch the fault
            bError       := TRUE;                                   // R45 配对：故障标志同拍置位 [bool] paired error flag
        ELSIF (rSoakBand < DL_DRY_ZERO) OR (rSoakBand >= rTempTarget) THEN
            _nFault      := 6;                                      // 故障级：保温带越域 [码] fault: soak band out of domain
            _bFaultLatch := TRUE;                                   // 置故障锁存 [bool] latch the fault
            bError       := TRUE;                                   // R45 配对：故障标志同拍置位 [bool] paired error flag
        ELSIF rOverTempLimit <= rTempTarget THEN
            _nFault      := 6;                                      // 故障级：超温门限不高于目标（必然误报）[码] fault: over temperature limit not above the target
            _bFaultLatch := TRUE;                                   // 置故障锁存 [bool] latch the fault
            bError       := TRUE;                                   // R45 配对：故障标志同拍置位 [bool] paired error flag
        ELSIF (tSoakTime < DL_DRY_T_MIN) OR (tSoakTime > DL_DRY_T_MAX) THEN
            _nFault      := 6;                                      // 故障级：保温时长越域 [码] fault: soak time out of domain
            _bFaultLatch := TRUE;                                   // 置故障锁存 [bool] latch the fault
            bError       := TRUE;                                   // R45 配对：故障标志同拍置位 [bool] paired error flag
        ELSIF (tRampTimeout < DL_DRY_T_MIN) OR (tRampTimeout > DL_DRY_T_MAX) THEN
            _nFault      := 6;                                      // 故障级：升温超时越域 [码] fault: ramp timeout out of domain
            _bFaultLatch := TRUE;                                   // 置故障锁存 [bool] latch the fault
            bError       := TRUE;                                   // R45 配对：故障标志同拍置位 [bool] paired error flag
        ELSIF (tOverTempLimit < DL_DRY_T_MIN) OR (tOverTempLimit > DL_DRY_T_MAX) THEN
            _nFault      := 6;                                      // 故障级：超温持续窗越域 [码] fault: over temperature window out of domain
            _bFaultLatch := TRUE;                                   // 置故障锁存 [bool] latch the fault
            bError       := TRUE;                                   // R45 配对：故障标志同拍置位 [bool] paired error flag
        END_IF
    END_IF
END_IF

(* —— 段 2：沿、定时器与节拍推进（CASE 外无条件周期调用，R7；IN 含 NOT .Q 自复位，R188） —— *)
rtStop(CLK := bStop);                                               // bStop 边沿无条件刷新 [bool] stop edge refreshed unconditionally
tonDtTick(IN := NOT tonDtTick.Q, PT := DL_DRY_DT);                  // 爬升节拍发生器（自复位周期窗）[s] self resetting ramp tick
_rDtStep := DL_DRY_ZERO;                                            // 非节拍拍增量秒数置零 [s] zero tick seconds on non tick scans
IF tonDtTick.Q THEN
    _rDtStep := DL_DRY_DT_SEC;                                      // 节拍拍推进 0.1s [s] advance 0.1 s on a tick scan
END_IF
tonRamp(IN := ((_eState = E_DL_DryerState.ePreheat) OR (_eState = E_DL_DryerState.eRampUp))
              AND (NOT tonRamp.Q) AND (NOT _bFaultLatch),
        PT := tRampTimeout);                                        // 预热+升温总超时（只看相驻留，R145）[s] preheat and ramp timeout on dwell only
tonSoak(IN := (_eState = E_DL_DryerState.eSoak) AND (NOT tonSoak.Q) AND (NOT _bFaultLatch),
        PT := tSoakTime);                                           // 保温时长 [s] soak duration
tonCool(IN := (_eState = E_DL_DryerState.eCoolDown) AND (NOT tonCool.Q) AND (NOT _bFaultLatch),
        PT := tRampTimeout);                                        // 冷却超时（同一时间引脚，两窗相序串行不重叠）[s] cooling timeout sharing the same pin
tonOverTemp(IN := _bOverTemp AND (_eState <> E_DL_DryerState.eIdle) AND (NOT tonOverTemp.Q)
                AND (NOT _bFaultLatch),
            PT := tOverTempLimit);                                  // 超温持续计时 [s] over temperature persistence

(* —— 段 3：人工停止优先消化（置锁存不写相位，迁相由段 6，R21 / R275） —— *)
IF rtStop.Q AND _bRunActive AND (NOT _bFaultLatch) THEN
    _nFault      := 4;                                              // 故障级：人工停止 [码] fault: manual stop
    _bFaultLatch := TRUE;                                           // 置故障锁存 [bool] latch the fault
    bError       := TRUE;                                           // R45 配对：故障标志同拍置位 [bool] paired error flag
END_IF

(* —— 段 4：主状态机（相位写入点之一；每成员独立标签，ELSE 只兜非法值，FB32-5） —— *)
CASE _eState OF
E_DL_DryerState.eIdle :                                             // 空闲相：设定与输出全零
    FOR _nIdx := 0 TO DL_DRY_ZONE_MAX DO
        _aSpRamp[_nIdx] := DL_DRY_ZERO;                             // 空闲相曲线保持槽清零（防空闲残留）[degC] clear the holding slots while idle
    END_FOR
    IF bStart AND (NOT bStop) AND _bCfgOk AND (NOT _bFaultLatch) THEN
        _eState := E_DL_DryerState.ePreheat;                        // 迁移：进入预热相 [phase] move to preheat
    END_IF

E_DL_DryerState.ePreheat :                                          // 预热相：各区设定 = 目标×0.3
    _bHeater := TRUE;                                               // 加热使能 [bool] heater enabled
    FOR _nIdx := 0 TO DL_DRY_ZONE_MAX DO
        IF _nIdx < _nZoneClamp THEN
            _aSpRamp[_nIdx] := _rPreheatSp;                         // 有效区写预热设定 [degC] active zone preheat setpoint
        ELSE
            _aSpRamp[_nIdx] := DL_DRY_ZERO;                         // 未装区恒零 [degC] uninstalled zone forced to zero
        END_IF
    END_FOR
    IF _bOverTemp THEN
        _eState := E_DL_DryerState.eRampUp;                         // 迁移：超温退避回升温相（设定冻结，加热由段 6 撤）[phase] retreat to ramp up
    ELSIF _rMinAct >= (_rPreheatSp - rSoakBand) THEN
        _eState := E_DL_DryerState.eRampUp;                         // 迁移：全部有效区达预热温度 [phase] preheat temperature reached
    END_IF

E_DL_DryerState.eRampUp :                                           // 升温相：斜率限制爬升（核心相）
    _bHeater := TRUE;                                               // 加热使能 [bool] heater enabled
    IF NOT _bOverTemp THEN
        _rStep := (rRampRate * _rDtStep) / DL_DRY_SIXTY;            // K/min × 节拍秒 / 60 → 单节拍增量 [K] per tick increment
        FOR _nIdx := 0 TO DL_DRY_ZONE_MAX DO
            IF _nIdx < _nZoneClamp THEN
                IF (_aSpRamp[_nIdx] + _rStep) < _rRampCeil THEN
                    _aSpRamp[_nIdx] := _aSpRamp[_nIdx] + _rStep;    // 斜率限制推进 [degC] slope limited advance
                ELSE
                    _aSpRamp[_nIdx] := _rRampCeil;                  // 饱和到升温上限（无阶跃超调）[degC] saturate at the ramp ceiling
                END_IF
            ELSE
                _aSpRamp[_nIdx] := DL_DRY_ZERO;                     // 未装区恒零 [degC] uninstalled zone forced to zero
            END_IF
        END_FOR
    END_IF
    IF (NOT _bOverTemp) AND (_rMinAct >= (_rRampCeil - DL_DRY_EPS)) THEN
        _eState := E_DL_DryerState.eSoak;                           // 迁移：最冷区到目标-保温带且未超温（防超温期抖动迁移）[phase] coldest zone reached the ceiling
    END_IF

E_DL_DryerState.eSoak :                                             // 保温相：设定保持目标温度
    _bHeater := TRUE;                                               // 加热使能 [bool] heater enabled
    FOR _nIdx := 0 TO DL_DRY_ZONE_MAX DO
        IF _nIdx < _nZoneClamp THEN
            _aSpRamp[_nIdx] := rTempTarget;                         // 有效区保温设定 = 目标 [degC] active zone soak setpoint
        ELSE
            _aSpRamp[_nIdx] := DL_DRY_ZERO;                         // 未装区恒零 [degC] uninstalled zone forced to zero
        END_IF
    END_FOR
    IF _bOverTemp THEN
        _eState := E_DL_DryerState.eRampUp;                         // 迁移：超温退避回升温相（设定冻结）[phase] retreat to ramp up
    ELSIF tonSoak.Q THEN
        _eState := E_DL_DryerState.eCoolDown;                       // 迁移：保温时间到 [phase] soak time elapsed
    END_IF

E_DL_DryerState.eCoolDown :                                         // 冷却相：关加热、开冷却风机
    _bCoolFan := TRUE;                                              // 冷却风机使能 [bool] cooling fan enabled
    FOR _nIdx := 0 TO DL_DRY_ZONE_MAX DO
        _aSpRamp[_nIdx] := DL_DRY_ZERO;                             // 冷却无加热需求，设定全零 [degC] no heating demand while cooling
    END_FOR
    IF _rMaxAct <= (_rCoolSp + DL_DRY_EPS) THEN
        _eState := E_DL_DryerState.eDone;                           // 迁移：最热区降到目标×0.2 [phase] hottest zone cooled down
    END_IF

E_DL_DryerState.eDone :                                             // 完成相：bDone 由相位派生
    FOR _nIdx := 0 TO DL_DRY_ZONE_MAX DO
        _aSpRamp[_nIdx] := DL_DRY_ZERO;                             // 完成相设定全零 [degC] setpoints zero after completion
    END_FOR
    IF (NOT bStart) OR rtStop.Q THEN
        _eState := E_DL_DryerState.eIdle;                           // 迁移：撤令或按停止回空闲 [phase] withdrawn start or a stop press returns to idle
    END_IF

E_DL_DryerState.eFault :                                            // 故障锁存相：输出与设定已由段 6 全撤
    FOR _nIdx := 0 TO DL_DRY_ZONE_MAX DO
        _aSpRamp[_nIdx] := DL_DRY_ZERO;                             // 故障相曲线保持槽清零 [degC] clear the holding slots in fault
    END_FOR
    IF rtStop.Q THEN
        _bFaultLatch := FALSE;                                      // 复位出口：清故障锁存 [bool] clear the fault latch
        _nFault      := 0;                                          // 复位出口：清故障码 [码] clear the fault code
        _eState      := E_DL_DryerState.eIdle;                      // 复位出口：迁回空闲（次拍 bStop 仍为 TRUE 不会误启动）[phase] back to idle
    END_IF

ELSE                                                                // 非法枚举值兜底（R6 / FB32-5）
    IF NOT _bFaultLatch THEN
        _nFault      := 7;                                          // 故障级：非法状态枚举值 [码] fault: illegal state enum value
        _bFaultLatch := TRUE;                                       // 置故障锁存 [bool] latch the fault
        bError       := TRUE;                                       // R45 配对：故障标志同拍置位 [bool] paired error flag
    END_IF
    _eState := E_DL_DryerState.eFault;                              // 非法值一律落安全相 [phase] illegal value falls into the safe phase
END_CASE

(* —— 段 5：超时看门狗锁存（判定序：超温持续优先于升温超时，同拍时码 3 优先，R190 归因唯一） —— *)
IF tonOverTemp.Q AND (NOT _bFaultLatch) AND (_eState <> E_DL_DryerState.eIdle) THEN
    _nFault      := 3;                                              // 故障级：超温持续 [码] fault: sustained over temperature
    _bFaultLatch := TRUE;                                           // 置故障锁存 [bool] latch the fault
    bError       := TRUE;                                           // R45 配对：故障标志同拍置位 [bool] paired error flag
END_IF
IF tonRamp.Q AND (NOT _bFaultLatch)
   AND ((_eState = E_DL_DryerState.ePreheat) OR (_eState = E_DL_DryerState.eRampUp)) THEN
    _nFault      := 1;                                              // 故障级：升温超时 [码] fault: ramp timeout
    _bFaultLatch := TRUE;                                           // 置故障锁存 [bool] latch the fault
    bError       := TRUE;                                           // R45 配对：故障标志同拍置位 [bool] paired error flag
END_IF
IF tonCool.Q AND (NOT _bFaultLatch) AND (_eState = E_DL_DryerState.eCoolDown) THEN
    _nFault      := 5;                                              // 故障级：冷却超时 [码] fault: cooling timeout
    _bFaultLatch := TRUE;                                           // 置故障锁存 [bool] latch the fault
    bError       := TRUE;                                           // R45 配对：故障标志同拍置位 [bool] paired error flag
END_IF
IF (NOT _bCfgOk) AND (NOT _bFaultLatch) AND _bRunActive THEN
    _nFault      := 6;                                              // 故障级：运行中出现非有限测量 [码] fault: non finite measurement during the run
    _bFaultLatch := TRUE;                                           // 置故障锁存 [bool] latch the fault
    bError       := TRUE;                                           // R45 配对：故障标志同拍置位 [bool] paired error flag
END_IF

(* —— 段 6：超温退避动作 + 段尾故障迁移闸 + 故障/空闲相动作与曲线全撤（FB50-1④） —— *)
IF _bOverTemp AND (_eState <> E_DL_DryerState.eFault) THEN
    _bHeater := FALSE;                                              // 超温退避：撤加热但不迁相（设定冻结，R191 显式声明）[bool] retreat: heater off without a phase change
END_IF
IF _bFaultLatch AND (_eState <> E_DL_DryerState.eFault) THEN
    _eState := E_DL_DryerState.eFault;                              // 锁存即迁相（锁存与迁相分离，R21）[phase] a latch forces the fault phase
END_IF
IF ((NOT bStart) AND _bRunActive AND (NOT _bFaultLatch)) OR (_eState = E_DL_DryerState.eFault) THEN
    (* 撤令语义（R191 二选一，本件选「降级为安全值 + 回空闲，不置故障码」）：加热与风机全停、曲线清零 *)
    IF (NOT bStart) AND (NOT _bFaultLatch)
       AND ((_eState = E_DL_DryerState.ePreheat) OR (_eState = E_DL_DryerState.eRampUp)
            OR (_eState = E_DL_DryerState.eSoak) OR (_eState = E_DL_DryerState.eCoolDown)) THEN
        _eState := E_DL_DryerState.eIdle;                           // 撤令即安全停机回空闲（用当拍相位判，不误吞 eDone）[phase] withdrawn start stops safely into idle
    END_IF
    _bHeater  := FALSE;                                             // 安全侧：加热全停 [bool] heater off on the safe side
    _bCoolFan := FALSE;                                             // 安全侧：冷却风机全停 [bool] cooling fan off on the safe side
    FOR _nIdx := 0 TO DL_DRY_ZONE_MAX DO
        _aSpRamp[_nIdx] := DL_DRY_ZERO;                             // 安全侧：曲线保持槽全零 [degC] clear all holding slots
    END_FOR
END_IF
IF _eState = E_DL_DryerState.eIdle THEN
    _bHeater  := FALSE;                                             // 空闲相：加热全停 [bool] heater off while idle
    _bCoolFan := FALSE;                                             // 空闲相：风机全停 [bool] cooling fan off while idle
    FOR _nIdx := 0 TO DL_DRY_ZONE_MAX DO
        _aSpRamp[_nIdx] := DL_DRY_ZERO;                             // 空闲相：曲线保持槽全零 [degC] clear all holding slots while idle
    END_FOR
END_IF

(* —— 段 7：统一出口（曲线映射 + 使能映射 + 完成度 + 锁存码回放；单点写入） —— *)
FOR _nIdx := 0 TO DL_DRY_ZONE_MAX DO
    IF (_eState = E_DL_DryerState.eIdle) OR (_eState = E_DL_DryerState.eFault)
       OR (_eState = E_DL_DryerState.eDone) THEN
        aTempSp[_nIdx] := DL_DRY_ZERO;                              // 空闲/故障/完成相：设定强制全零（MAJOR 型残留的双保险）[degC] setpoints forced to zero
    ELSE
        aTempSp[_nIdx] := _aSpRamp[_nIdx];                          // 运行相：映射内部曲线保持槽 [degC] map the internal holding slots
    END_IF
END_FOR
IF (rTempTarget > DL_DRY_EPS) AND _bCfgOk THEN
    _rProg := LIMIT(DL_DRY_ZERO, (_rMinAct * DL_DRY_HUNDRED) / rTempTarget, DL_DRY_HUNDRED); // 最冷区完成度（除子已双检，R4）[%] coldest zone progress
END_IF
bHeaterEnable    := _bHeater AND (_eState <> E_DL_DryerState.eIdle) AND (_eState <> E_DL_DryerState.eFault); // 加热使能出口（空闲/故障相强制 FALSE）[bool] heater enable outlet
bCoolFanEnable   := _bCoolFan AND (_eState <> E_DL_DryerState.eIdle) AND (_eState <> E_DL_DryerState.eFault); // 冷却风机出口（空闲/故障相强制 FALSE）[bool] cooling fan outlet
bOverTempAlarm   := _bOverTemp OR (_nFault = 3);                    // 超温告警：本体超温 或 超温故障锁存派生 [bool] over temperature alarm
eState           := _eState;                                        // 相位出口 [phase] phase outlet
bDone            := (_eState = E_DL_DryerState.eDone);               // 完成位由相位派生（非单拍脉冲）[bool] done derived from the phase
nFaultCode       := _nFault;                                        // 故障码出口（锁存回放）[码] fault code outlet replayed from the latch
rRampProgressPct := _rProg;                                         // 完成度出口 [%] progress outlet
bError           := _bFaultLatch;                                   // 故障标志取锁存位 [bool] fault flag from the latch
END_FUNCTION_BLOCK
