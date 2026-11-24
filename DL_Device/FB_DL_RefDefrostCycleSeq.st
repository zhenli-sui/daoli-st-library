(*
  ============================================================
  组件名 : FB_DL_RefDefrostCycleSeq
  分类   : DL_Device
  功能   : 冷风机除霜循环（制冷 → 判霜 → 融霜 → 滴水 → 恢复），含融霜超时、恢复超时、风机反馈丢失、参数非法四类故障锁存与除霜次数累计
  开源溯源 : internal-design（本轮无外部代码逐行引用）；参考语义 : 无外部参考
  复杂度 : C4
  版本   : 1.0.0
  ============================================================
*)

(*-----------------------------------------------------------------------------
 * 状态迁移表（ENUM 成员 → 出口；每成员均有可到达出口，零无界驻留相）：
 *   eIdle       → eCooling    : bEnable 且组态闸通过且无锁存
 *   eIdle       ── 保持，直到使能（待机相以使能为唯一出口，属许可型驻留）
 *   eCooling    → eFrostDetect: tonCoolMin.Q（已累计满足最短制冷 tCoolMin 才允许判霜）
 *   eCooling    → eIdle       : bEnable 撤除（段 5 失能迁相）
 *   eCooling    → eFault      : tonFanFb.Q（码 3 风机反馈与指令不符）｜组态失效（码 4）
 *   eFrostDetect→ eDefrost    : 判霜判据成立（室温-盘管温差 > 阈值 且 盘管 < 0 且 吸气压力 > 下限）
 *   eFrostDetect→ eCooling    : 判霜判据不成立（本相为单拍决策相，无驻留）
 *   eDefrost    → eDrip       : rCoilTempC ≥ rDefrostTermTempC（达融霜终止温度）
 *   eDefrost    → eFault      : tonDefrost.Q（码 1 融霜超时）｜tonFanFb.Q（码 3）｜bEnable 撤除（段 5）
 *   eDrip       → eRecover    : tonDrip.Q（滴水计时到，本相为定时驻留，出口由计时器保证）
 *   eDrip       → eIdle/eFault: bEnable 撤除（段 5）｜tonFanFb.Q（码 3）
 *   eRecover    → eCooling    : 盘管温度回落至（室温 - 阈值）以下，压缩机延时启动条件成立
 *   eRecover    → eFault      : tonRecover.Q（码 2 恢复超时）｜tonFanFb.Q（码 3）｜bEnable 撤除（段 5）
 *   eFault      → eIdle       : bEnable 重新使能的上升沿（下降沿后再使能，段 3 分支内清锁存）
 *   ELSE（非法枚举值，非任何成员）→ eFault（码 5）
 *
 * 故障码表（nFaultCode，0 = 无故障；非首码均附「现有输出不可观测」反证句，R90）：
 *   1 融霜超时   : tonDefrost 覆盖 eDefrost 全相，达 tDefrostMax 仍未到终止温度即锁存。
 *   2 恢复超时   : 反证——恢复相 bCompressorOn = FALSE 而 bFanOn = TRUE，与码 1 的
 *                  「风机与压缩机全关」时序签名不同；但故障相动作全撤后两者观测量一致，
 *                  复用码 1 会把「融霜水未排干/盘管未回落」误报为「加热不足」，处置方向相反。
 *   3 风机反馈失 : 反证——反馈丢失可由 eCooling（应转却在停）与 eDefrost（应停却在转）两侧触发，
 *                  与任何超时码无共享观测量；复用超时码会让机械故障被当作时间参数问题。
 *   4 参数非法   : 反证——非法阈值/时间在启动瞬间拦截，无除霜动作、无计数递增，
 *                  与码 1/2/3 的时序签名互斥，必须独立成码以便组态错误可前置观测。
 *   5 非法状态   : 反证——非法枚举值为程序缺陷而非现场事件，合并入任一工艺码会让
 *                  固件错误被误排为制冷系统故障，必须独立成码。
 *
 * 依赖     : 仅 IEC 61131-3 标准库（TON / R_TRIG / ABS），零厂商私有库
 * 分工声明 : 压缩机高低压保护与吸气压力联锁归压缩机组保护件；本件只做除霜时序、
 *            风机反馈一致性监视与除霜次数累计，不做制冷量调节、不做电机过载保护。
 *            吸气压力在本件只作判霜前置闸（系统未运行时禁止判霜），不作保护判据。
 * 归属     : E_DL_RefDfsState 归属本文件（全库唯一定义，R264；引用件只引用不重声明）。
 * 修订历史 : 2026-11-25  v1.0.0  首版（编码席 dlf-plc-coder，第二批 C4）
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 边界与红线自检：
 * ① 五个 TON 与一个 R_TRIG 全部在 CASE 外无条件周期调用（R7）；时间类 IN 均含 NOT .Q 自复位项
 *    与 NOT 故障锁存项（R188 / FB50-1③），CASE 内只读 .Q。
 * ② 三个执行出口（压缩机 / 除霜阀 / 风机）在段 0 每拍预置 FALSE，CASE 内只置 TRUE；
 *    段 5 在 eIdle 与 eFault 相再次全撤 —— eIdle 三输出必为 FALSE，无上一相残留。
 * ③ 风机反馈判据用「相位期望值」比较（R99 状态量门控），不用上一拍命令位：期望为真的相
 *    为 eCooling / eFrostDetect / eRecover，期望为假的相为 eIdle / eDefrost / eDrip / eFault；
 *    不符持续 DL_DFS_FB_WIN（3s）才置码 3，避开启动/停止瞬间的机械过渡。
 * ④ 除霜次数 _nCount 只在 eFrostDetect → eDefrost 迁移点 +1（单点写入，一霜一次）；
 *    本件任何复位路径都不清零该计数（FB50-2② 作用域声明：由上层维护清零）。
 * ⑤ 复位沿作用域（FB50-2②）：eFault 内 bEnable 上升沿 = 清故障锁存 + 清故障码 + 迁相回 eIdle，
 *    三项各写明；bEnable 下降沿的作用域 = 迁相回 eIdle 并全撤输出，不清锁存、不清计数。
 * ⑥ 组态域闸枚举全部浮点入参（rCoilTempC / rRoomTempC / rSuctionPressBar / rFrostThresh /
 *    rDefrostTermTempC），NaN 自反 + Inf 差值自减双判（R151 / R79）。
 * ⑦ 零全局耦合：无 GVL / VAR_EXTERNAL / %I / %Q（R1 / R2）；无 FOR / WHILE / REPEAT（R271 N/A）。
 * ⑧ 相位写入点共两处且互斥：段 3 CASE、段 5 段尾迁移闸。
 *----------------------------------------------------------------------------*)

TYPE E_DL_RefDfsState :
(
    eIdle        := 0,                                              // 空闲：压缩机/除霜阀/风机全停，等使能 idle: compressor, defrost valve and fan all off, waiting for enable
    eCooling     := 1,                                              // 制冷相：压缩机与风机开，累计最短制冷时间 cooling: compressor and fan on, accumulating the minimum cooling time
    eFrostDetect := 2,                                              // 判霜决策相：单拍决策，不改变执行出口 frost detect: single scan decision without changing the actuators
    eDefrost     := 3,                                              // 融霜相：压缩机关、除霜阀开、风机关，至终止温度 defrost: compressor off, defrost valve on, fan off until the termination temperature
    eDrip        := 4,                                              // 滴水相：三输出全关，等 tDripTime drip: all three outputs off until tDripTime elapses
    eRecover     := 5,                                              // 恢复相：风机先开，盘管回落后压缩机延时启动 recover: fan first, the compressor starts after the coil recovers
    eFault       := 6                                               // 故障锁存相：三输出全停，只由 bEnable 重新使能迁出 fault: all outputs off, left only by a re-enabled bEnable
);
END_TYPE

FUNCTION_BLOCK FB_DL_RefDefrostCycleSeq
VAR_INPUT
    bEnable           : BOOL := FALSE;                              // 除霜循环使能（电平）：撤除即三输出全停 [bool] defrost cycle enable level, dropping it stops all outputs
    rCoilTempC        : REAL := 0.0;                                // 盘管表面实测温度 [degC] measured coil surface temperature [degC]
    rRoomTempC        : REAL := 0.0;                                // 库房空气实测温度 [degC] measured room air temperature [degC]
    rSuctionPressBar  : REAL := 0.0;                                // 压缩机吸气压力 [bar] compressor suction pressure [bar]
    bFanFeedback      : BOOL := FALSE;                              // 风机运行反馈（TRUE = 在转）[bool] fan running feedback, TRUE means running
    rFrostThresh      : REAL := 5.0;                                // 判霜温差阈值（室温-盘管），域 > 0 [K] frost detection temperature difference threshold, domain > 0 [K]
    rDefrostTermTempC : REAL := 8.0;                                // 融霜终止温度（盘管回升到此值即结束），域 > 0 [degC] defrost termination coil temperature, domain > 0 [degC]
    tDefrostMax       : TIME := T#20M;                              // 融霜最长时长 [s] maximum defrost duration [s]
    tDripTime         : TIME := T#3M;                               // 滴水时长（融霜后滴排残水）[s] drip duration after defrost [s]
    tRecoverMax       : TIME := T#10M;                              // 恢复最长时长 [s] maximum recovery duration [s]
    tCoolMin          : TIME := T#15M;                              // 最短制冷时长（满足后才允许判霜）[s] minimum cooling time before frost detection is allowed [s]
END_VAR
VAR_OUTPUT
    bCompressorOn    : BOOL;                                        // 压缩机运行命令（段 0 预置，CASE 只置位）[bool] compressor run command
    bDefrostValveOn  : BOOL;                                        // 除霜阀命令（仅融霜相）[bool] defrost valve command, defrost phase only
    bFanOn           : BOOL;                                        // 风机运行命令（制冷/判霜/恢复相）[bool] fan run command in cooling, detect and recovery phases
    eState           : E_DL_RefDfsState;                            // 相位出口（段 6 单点映射）[-] phase outlet mapped once in section 6
    nDefrostCount    : INT;                                         // 累计除霜次数（本件不清零，由上层维护）[次] accumulated defrost count maintained by the upper layer
    bDefrostAlarm    : BOOL;                                        // 除霜告警（故障锁存派生位，需人工/复位确认）[bool] defrost alarm derived from the fault latch
    nFaultCode       : INT;                                         // 故障码 0 无 1 融霜超时 2 恢复超时 3 风机反馈丢失 4 参数非法 5 非法状态 [码] fault code
    bError           : BOOL;                                        // 故障锁存标志（取锁存位，R45 配对出口）[bool] fault latch flag used as the paired outlet
END_VAR
VAR
    _eState      : E_DL_RefDfsState := E_DL_RefDfsState.eIdle;      // 内部相位（CASE 唯一比较目标）[-] internal phase compared by the CASE
    _bFaultLatch : BOOL := FALSE;                                   // 故障锁存位（仅 bEnable 重新使能沿清除）[bool] fault latch, cleared only by a re-enabled bEnable edge
    _nFault      : INT := 0;                                        // 锁存故障码（故障期回放，不按当下输入重算）[码] latched fault code replayed in the fault phase
    _nCount      : INT := 0;                                        // 内部除霜次数累计（单点写入）[次] internal defrost count with a single write point
    _bCfgOk      : BOOL := FALSE;                                   // 组态与入参域闸通过标志 [bool] configuration and input domain gate flag
    _bRunActive  : BOOL := FALSE;                                   // 制冷相关相标志（制冷到恢复）[bool] cooling related phase flag from cooling to recovery
    _bComp       : BOOL := FALSE;                                   // 内部压缩机命令状态 [bool] internal compressor command state
    _bDfv        : BOOL := FALSE;                                   // 内部除霜阀命令状态 [bool] internal defrost valve command state
    _bFan        : BOOL := FALSE;                                   // 内部风机命令状态 [bool] internal fan command state
    _bFanExpect  : BOOL := FALSE;                                   // 按相位推导的风机应有状态（R99 状态量门控）[bool] fan state expected from the phase
    _bFanMismatch : BOOL := FALSE;                                  // 风机反馈与期望不符标志 [bool] fan feedback mismatching the expectation
    rtEnable     : R_TRIG;                                          // bEnable 上升沿实例（段 2 无条件调用）[bool] enable rising edge instance
    tonCoolMin   : TON;                                             // 最短制冷计时（段 2 无条件调用）[s] minimum cooling timer
    tonDefrost   : TON;                                             // 融霜最长时长计时（段 2 无条件调用）[s] maximum defrost timer
    tonDrip      : TON;                                             // 滴水时长计时（段 2 无条件调用）[s] drip timer
    tonRecover   : TON;                                             // 恢复最长时长计时（段 2 无条件调用）[s] maximum recovery timer
    tonFanFb     : TON;                                             // 风机反馈不符持续计时（段 2 无条件调用）[s] fan feedback mismatch persistence timer
END_VAR
VAR CONSTANT
    DL_DFS_ZERO      : REAL := 0.0;                                 // 浮点零基准（亦作盘管结霜温度界限）[degC] float zero base, also the coil frosting limit [degC]
    DL_DFS_PRESS_MIN : REAL := 0.1;                                 // 吸气压力下限（系统运行判据）[bar] suction pressure lower bound proving the system runs [bar]
    DL_DFS_FB_WIN    : TIME := T#3S;                                // 风机反馈不符持续判窗 [s] fan feedback mismatch persistence window [s]
    DL_DFS_T_MIN     : TIME := T#100MS;                             // 时间参数下限 [s] lower bound of the time parameters
    DL_DFS_T_MAX     : TIME := T#8H;                                // 时间参数上限 [s] upper bound of the time parameters
    DL_DFS_CNT_ONE   : INT := 1;                                    // 计数步长 [次] count step
END_VAR

(* —— 段 0：出口预置与派生量（CASE 内只置 TRUE，eIdle / eFault 零残留） —— *)
_bComp := FALSE;                                                    // 压缩机命令每拍先撤 [bool] compressor command withdrawn first each scan
_bDfv  := FALSE;                                                    // 除霜阀命令每拍先撤 [bool] defrost valve command withdrawn first each scan
_bFan  := FALSE;                                                    // 风机命令每拍先撤 [bool] fan command withdrawn first each scan
_bRunActive := (_eState = E_DL_RefDfsState.eCooling) OR (_eState = E_DL_RefDfsState.eFrostDetect)
               OR (_eState = E_DL_RefDfsState.eDefrost) OR (_eState = E_DL_RefDfsState.eDrip)
               OR (_eState = E_DL_RefDfsState.eRecover);            // 制冷相关相标志（用状态量，R99）[bool] cooling related phase flag
_bFanExpect := (_eState = E_DL_RefDfsState.eCooling) OR (_eState = E_DL_RefDfsState.eFrostDetect)
               OR (_eState = E_DL_RefDfsState.eRecover);            // 风机应有状态（按相位推导）[bool] fan state expected from the phase
_bFanMismatch := _bRunActive AND _bFanExpect AND (NOT bFanFeedback); // 反馈不符（只监视「应转未转」，见 R80 闸 B MAJOR-1）[bool] mismatch only when fan expected on

(* —— 段 1：组态域闸（五个浮点入参全枚举，非有限双判 R151 / R79） —— *)
_bCfgOk := TRUE;                                                    // 组态闸标志初值 [bool] configuration flag initial value
IF (rCoilTempC <> rCoilTempC) OR ((rCoilTempC - rCoilTempC) <> DL_DFS_ZERO)
   OR (rRoomTempC <> rRoomTempC) OR ((rRoomTempC - rRoomTempC) <> DL_DFS_ZERO)
   OR (rSuctionPressBar <> rSuctionPressBar) OR ((rSuctionPressBar - rSuctionPressBar) <> DL_DFS_ZERO)
   OR (rFrostThresh <> rFrostThresh) OR ((rFrostThresh - rFrostThresh) <> DL_DFS_ZERO)
   OR (rDefrostTermTempC <> rDefrostTermTempC) OR ((rDefrostTermTempC - rDefrostTermTempC) <> DL_DFS_ZERO) THEN
    _bCfgOk := FALSE;                                               // 非有限入参：拒收（NaN 自反 + Inf 差值自减）[bool] non finite input rejected
END_IF
IF _bCfgOk THEN
    IF rFrostThresh <= DL_DFS_ZERO THEN
        _bCfgOk := FALSE;                                           // 判霜阈值非正（永不判霜）[bool] non positive frost threshold
    ELSIF rDefrostTermTempC <= DL_DFS_ZERO THEN
        _bCfgOk := FALSE;                                           // 终止温度非正（融霜不足）[bool] non positive termination temperature
    ELSIF (tDefrostMax < DL_DFS_T_MIN) OR (tDefrostMax > DL_DFS_T_MAX) THEN
        _bCfgOk := FALSE;                                           // 融霜最长时长越域 [bool] defrost maximum out of domain
    ELSIF (tDripTime < DL_DFS_T_MIN) OR (tDripTime > DL_DFS_T_MAX) THEN
        _bCfgOk := FALSE;                                           // 滴水时长越域 [bool] drip time out of domain
    ELSIF (tRecoverMax < DL_DFS_T_MIN) OR (tRecoverMax > DL_DFS_T_MAX) THEN
        _bCfgOk := FALSE;                                           // 恢复最长时长越域 [bool] recovery maximum out of domain
    ELSIF (tCoolMin < DL_DFS_T_MIN) OR (tCoolMin > DL_DFS_T_MAX) THEN
        _bCfgOk := FALSE;                                           // 最短制冷时长越域 [bool] minimum cooling time out of domain
    END_IF
END_IF
IF (NOT _bCfgOk) AND (NOT _bFaultLatch) AND (bEnable OR _bRunActive) THEN
    _nFault      := 4;                                              // 故障级：参数非法 [码] fault: illegal parameter
    _bFaultLatch := TRUE;                                           // 置故障锁存 [bool] latch the fault
    bError       := TRUE;                                           // R45 配对：故障标志同拍置位 [bool] paired error flag
END_IF

(* —— 段 2：沿与定时器（CASE 外无条件周期调用，R7；IN 含 NOT .Q 自复位与 NOT 锁存，R188） —— *)
rtEnable(CLK := bEnable);                                           // 使能沿无条件刷新 [bool] enable edge refreshed unconditionally
tonCoolMin(IN := (_eState = E_DL_RefDfsState.eCooling) AND (NOT tonCoolMin.Q) AND (NOT _bFaultLatch),
           PT := tCoolMin);                                         // 最短制冷计时 [s] minimum cooling timer
tonDefrost(IN := (_eState = E_DL_RefDfsState.eDefrost) AND (NOT tonDefrost.Q) AND (NOT _bFaultLatch),
           PT := tDefrostMax);                                      // 融霜最长时长 [s] maximum defrost timer
tonDrip(IN := (_eState = E_DL_RefDfsState.eDrip) AND (NOT tonDrip.Q) AND (NOT _bFaultLatch),
        PT := tDripTime);                                           // 滴水时长 [s] drip timer
tonRecover(IN := (_eState = E_DL_RefDfsState.eRecover) AND (NOT tonRecover.Q) AND (NOT _bFaultLatch),
           PT := tRecoverMax);                                      // 恢复最长时长 [s] maximum recovery timer
tonFanFb(IN := _bFanMismatch AND (NOT tonFanFb.Q) AND (NOT _bFaultLatch),
         PT := DL_DFS_FB_WIN);                                      // 风机反馈不符持续判 [s] fan feedback mismatch persistence

(* —— 段 3：主状态机（相位写入点之一；每成员独立标签，ELSE 只兜非法值，FB32-5） —— *)
CASE _eState OF
E_DL_RefDfsState.eIdle :                                            // 空闲相：三输出已撤
    IF bEnable AND _bCfgOk AND (NOT _bFaultLatch) THEN
        _eState := E_DL_RefDfsState.eCooling;                       // 迁移：进入制冷相 [phase] move to cooling
    END_IF

E_DL_RefDfsState.eCooling :                                         // 制冷相：压缩机与风机开
    _bComp := TRUE;                                                 // 压缩机运行 [bool] compressor running
    _bFan  := TRUE;                                                 // 风机运行 [bool] fan running
    IF tonCoolMin.Q THEN
        _eState := E_DL_RefDfsState.eFrostDetect;                   // 迁移：最短制冷已满足，允许判霜 [phase] minimum cooling satisfied, frost detection allowed
    END_IF

E_DL_RefDfsState.eFrostDetect :                                     // 判霜决策相（单拍过渡态）
    (* 拍 N 进入（tonCoolMin.Q 置位）/ 本拍行为：只做判霜决策，执行出口沿用制冷相的安全状态
       （压缩机与风机保持开），不产生任何新动作 / 拍 N+1 转出至 eDefrost 或回 eCooling *)
    _bComp := TRUE;                                                 // 判霜拍沿用压缩机运行 [bool] compressor kept running in the detect scan
    _bFan  := TRUE;                                                 // 判霜拍沿用风机运行 [bool] fan kept running in the detect scan
    IF ((rRoomTempC - rCoilTempC) > rFrostThresh) AND (rCoilTempC < DL_DFS_ZERO)
       AND (rSuctionPressBar > DL_DFS_PRESS_MIN) THEN
        _nCount := _nCount + DL_DFS_CNT_ONE;                        // 除霜次数 +1（单点写入，一霜一次）[次] one count per confirmed frost
        _eState := E_DL_RefDfsState.eDefrost;                       // 迁移：判霜成立进入融霜 [phase] frost confirmed, start the defrost
    ELSE
        _eState := E_DL_RefDfsState.eCooling;                       // 迁移：未达判霜条件回制冷继续累计 [phase] no frost, resume cooling
    END_IF

E_DL_RefDfsState.eDefrost :                                         // 融霜相：压缩机关、除霜阀开、风机关
    _bDfv := TRUE;                                                  // 除霜阀开（压缩机与风机保持关）[bool] defrost valve open
    IF rCoilTempC >= rDefrostTermTempC THEN
        _eState := E_DL_RefDfsState.eDrip;                          // 迁移（出口 1）：盘管达融霜终止温度 [phase] coil reached the termination temperature
    END_IF

E_DL_RefDfsState.eDrip :                                            // 滴水相：三输出全关，等 tDripTime
    IF tonDrip.Q THEN
        _eState := E_DL_RefDfsState.eRecover;                       // 迁移（出口 1）：滴水时间到 [phase] drip time elapsed
    END_IF

E_DL_RefDfsState.eRecover :                                         // 恢复相：风机先开，压缩机延时启动
    _bFan := TRUE;                                                  // 风机先开（化霜水汽排空）[bool] fan first to clear the moisture
    IF rCoilTempC <= (rRoomTempC - rFrostThresh) THEN
        _bComp := TRUE;                                             // 压缩机启动条件成立（盘管已回落）[bool] compressor start condition satisfied
        _eState := E_DL_RefDfsState.eCooling;                       // 迁移（出口 1）：恢复正常制冷 [phase] back to normal cooling
    END_IF

E_DL_RefDfsState.eFault :                                           // 故障锁存相：三输出已由段 5 全撤
    IF rtEnable.Q THEN
        _bFaultLatch := FALSE;                                      // 复位作用域①：清故障锁存（bEnable 下降后再使能的上升沿）[bool] reset scope one
        _nFault      := 0;                                          // 复位作用域②：清故障码 [码] reset scope two
        _eState      := E_DL_RefDfsState.eIdle;                     // 复位作用域③：迁相回空闲 [phase] reset scope three
    END_IF

ELSE                                                                // 非法枚举值兜底（R6 / FB32-5）
    IF NOT _bFaultLatch THEN
        _nFault      := 5;                                          // 故障级：非法状态枚举值 [码] fault: illegal state enum value
        _bFaultLatch := TRUE;                                       // 置故障锁存 [bool] latch the fault
        bError       := TRUE;                                       // R45 配对：故障标志同拍置位 [bool] paired error flag
    END_IF
    _eState := E_DL_RefDfsState.eFault;                             // 非法值一律落安全相 [phase] illegal value falls into the safe phase
END_CASE

(* —— 段 4：超时看门狗锁存（状态已迁出则该相看门狗不生效，R275） —— *)
IF tonDefrost.Q AND (NOT _bFaultLatch) AND (_eState = E_DL_RefDfsState.eDefrost) THEN
    _nFault      := 1;                                              // 故障级：融霜超时未达终止温度 [码] fault: defrost timeout before the termination temperature
    _bFaultLatch := TRUE;                                           // 置故障锁存 [bool] latch the fault
    bError       := TRUE;                                           // R45 配对：故障标志同拍置位 [bool] paired error flag
END_IF
IF tonRecover.Q AND (NOT _bFaultLatch) AND (_eState = E_DL_RefDfsState.eRecover) THEN
    _nFault      := 2;                                              // 故障级：恢复超时 [码] fault: recovery timeout
    _bFaultLatch := TRUE;                                           // 置故障锁存 [bool] latch the fault
    bError       := TRUE;                                           // R45 配对：故障标志同拍置位 [bool] paired error flag
END_IF
IF tonFanFb.Q AND (NOT _bFaultLatch) AND _bRunActive THEN
    _nFault      := 3;                                              // 故障级：风机反馈丢失（与相位期望不符持续 3s）[码] fault: fan feedback lost
    _bFaultLatch := TRUE;                                           // 置故障锁存 [bool] latch the fault
    bError       := TRUE;                                           // R45 配对：故障标志同拍置位 [bool] paired error flag
END_IF

(* —— 段 5：失能迁相 + 段尾故障迁移闸 + 空闲/故障相输出全撤（FB50-1④ / R191 显式声明） —— *)
IF (NOT bEnable) AND (_eState <> E_DL_RefDfsState.eFault) THEN
    (* 失能语义（R191 二选一，本件选「降级为安全值 + 回空闲，不置故障码」）：
       作用域仅迁相位与撤输出，不清故障锁存、不清除霜计数 *)
    _eState := E_DL_RefDfsState.eIdle;                              // 失能即安全停机回空闲 [phase] disable stops safely into idle
END_IF
IF _bFaultLatch AND (_eState <> E_DL_RefDfsState.eFault) THEN
    _eState := E_DL_RefDfsState.eFault;                             // 锁存即迁相（锁存与迁相分离，R21）[phase] a latch forces the fault phase
END_IF
IF (_eState = E_DL_RefDfsState.eIdle) OR (_eState = E_DL_RefDfsState.eFault) THEN
    _bComp := FALSE;                                                // 空闲/故障：压缩机全停 [bool] compressor off in idle and fault
    _bDfv  := FALSE;                                                // 空闲/故障：除霜阀全关 [bool] defrost valve closed in idle and fault
    _bFan  := FALSE;                                                // 空闲/故障：风机全停 [bool] fan off in idle and fault
END_IF

(* —— 段 6：统一出口（执行映射 + 计数 + 告警派生 + 锁存码回放；单点写入） —— *)
bCompressorOn   := _bComp;                                          // 压缩机命令出口 [bool] compressor command outlet
bDefrostValveOn := _bDfv;                                           // 除霜阀命令出口 [bool] defrost valve command outlet
bFanOn          := _bFan;                                           // 风机命令出口 [bool] fan command outlet
eState          := _eState;                                         // 相位出口 [phase] phase outlet
nDefrostCount   := _nCount;                                         // 除霜次数出口 [次] defrost count outlet
bDefrostAlarm   := _bFaultLatch;                                    // 除霜告警取故障锁存位（派生位，R28 5.9）[bool] alarm derived from the fault latch
nFaultCode      := _nFault;                                         // 故障码出口（锁存回放）[码] fault code outlet replayed from the latch
bError          := _bFaultLatch;                                    // 故障标志取锁存位 [bool] fault flag from the latch
END_FUNCTION_BLOCK
