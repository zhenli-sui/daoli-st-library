(*
  ==================================================================
  组件名 Component  : FB_DL_SoftStarterDrive
  分类   Category   : DL_Device
  复杂度 Complexity  : cx5
  版本   Version    : 1.0.1
  功能   Purpose    : 软启动器驱动封装。晶闸管斜坡启动（bCmdRun 端子）→ 斜坡
                      末投旁路接触器（bCmdBypass）→ 旁路反馈确认转运行；停
                      机双命令全断 + 旁路分断确认；斜坡窗 / 反馈确认窗 / 停
                      机确认窗三窗监视 + 启动超时保护 + 旁路提前吸合矛盾诊
                      断 + 过载锁存 + 重启抑制冷却。实现既有 I_DL_MotorDriver
                      接口，补齐 DOL / 星三角 / 软启 / 变频四启动家族。
  来源   Source     : t2-2-lbp（cmd / ind 分离范式）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；软启动器旁路投
                      切与反馈校验为行业公知工程语义，clean-room 自研实现，
                      未复制 LBP 或任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: TON / R_TRIG，无私有库）
  接口实现 Implements : I_DL_MotorDriver（属主文件 DL_Device\I_DL_MotorDriver.st）。
                      R66 收窄清单：契约属性 eState / bRunning / bFault /
                      uErrorId / bRestartInhibit 仅以 PROPERTY GET 落地（本件
                      不在 VAR_OUTPUT 重复声明同名引脚）；方法 CmdStart /
                      CmdStop / CmdReset 签名一字不减，契约语义一字不减。
  平台枚举归属 Ownership : 内部状态映射 E_DL_MotorState（归属 I_DL_MotorDriver
                      同文件发布，本件只引用不重声明）。
  码位留痕 CodeSource : 实现 I_DL_MotorDriver 契约 uErrorId（接口文件声明段位
                      16#0003_xxxx），沿用族内既有派号段（FB_DL_DolMotor 已占
                      0201..020A），本件占用 0211..0217：故障级 0003_0211 旁路
                      反馈确认超时 / 0003_0212 运行中旁路反馈断开 / 0003_0213
                      停机旁路未分断 / 0003_0214 斜坡期旁路提前吸合 / 0003_0215
                      过载锁存 / 0003_0216 非法状态；信息级 0003_0217 重启抑制
                      期拒绝（只写 uErrorId 不进 bFault，0.2 公约）。锁存解除
                      路径 = bReset 上升沿（唯一路径，R188）。
  作者   Author     : 道莅代码库 · PLC 编程专家（R58）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 三窗配比约束（R100）：tFbWindow < tRampTime（旁路反
                         馈窗必须短于斜坡窗）且 tStopConfirm < tRestartInhibit
                         （停机确认短于冷却窗）；越域由调用方组态保证，本件
                         不做二次钳制；
                      二 停机双命令全断：bCmdRun 与 bCmdBypass 在停机 / 故障
                         / 过载相安全侧全断（R191 降级显式声明）；
                      三 过载全局监视优先级最高：斜坡 / 投旁路 / 运行相过载
                         立即锁存脱扣（R190 独立成因独立码）；
                      四 方法均为非阻塞单发，跨周期动作由 _bPend* 请求标志
                         交主体状态机消化（无 METHOD 内状态驻留）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R58 首版（批 2 · 序号 7）
    2026-11-21  v1.0.1  R59 返修轻①②：复位分支前置故障相位门（故障相复位只清锁存不迁相）；删 3 处 _ePhase 自赋值死语句
  ==================================================================
*)

TYPE E_DL_SsdPhase :
(
    eSsdIdle    := 0,  // 空闲：消化停止锁存，评估启动请求 / idle, absorbing the stop latch
    eSsdRamp    := 10, // 晶闸管斜坡：运行端子得电，旁路断开 / the thyristor ramp, the run terminal on, the bypass off
    eSsdByWait  := 20, // 投旁路：旁路命令得电，等反馈吸合确认 / the bypass engage, the command on, awaiting the feedback
    eSsdRun     := 30, // 旁路运行：反馈吸合确认带载 / the bypass running, feedback confirmed
    eSsdStop    := 40, // 停机过渡：双命令全断，等旁路分断确认 / the stopping transition, both commands off, awaiting the drop out
    eSsdTrip    := 50, // 过载脱扣锁存：仅复位且过载消失可清 / the overload trip latch
    eSsdFault   := 90  // 故障锁存：仅复位可清 / the latched fault
);
END_TYPE

FUNCTION_BLOCK FB_DL_SoftStarterDrive IMPLEMENTS I_DL_MotorDriver
VAR_INPUT
    bCmdStart       : BOOL;           // 启动指令，上升沿生效 [-] / the start command, rising edge effective
    bCmdStop        : BOOL;           // 停止指令，电平生效 [-] / the stop command, level effective
    bFbBypass       : BOOL := FALSE;  // 旁路接触器反馈，TRUE = 吸合 [-] / the bypass contactor feedback, true = picked up
    bOverload       : BOOL := FALSE;  // 过载保护信号，TRUE = 过载 [-] / the overload protection signal, true = overloaded
    bPermitStart    : BOOL := TRUE;   // 启动允许联锁，TRUE = 允许 [-] / the start permit interlock, true = allowed
    tRampTime       : TIME := T#10S;  // 晶闸管斜坡时长 [毫秒] / the thyristor ramp duration [millisecond]
    tFbWindow       : TIME := T#2S;   // 旁路反馈确认窗 [毫秒] / the bypass feedback confirm window [millisecond]
    tStopConfirm    : TIME := T#5S;   // 停机旁路分断确认窗 [毫秒] / the stop drop out confirm window [millisecond]
    tRestartInhibit : TIME := T#60S;  // 重启抑制冷却时长 [毫秒] / the restart inhibit cooling duration [millisecond]
    bReset          : BOOL;           // 故障复位，上升沿生效 [-] / the fault reset, rising edge effective
END_VAR
VAR_OUTPUT
    bCmdRun    : BOOL := FALSE; // 软启器运行端子输出（斜坡 / 旁路 / 运行相保持）[-] / the softstarter run terminal outlet
    bCmdBypass : BOOL := FALSE; // 旁路接触器线圈输出（仅投旁路与运行相）[-] / the bypass contactor coil outlet
END_VAR
VAR
    _ePhase    : E_DL_SsdPhase := E_DL_SsdPhase.eSsdIdle; // 内部相位，CASE 唯一写入目标 / the internal phase, the single CASE write target
    _uErrorId  : UDINT := 0;      // 内部故障码寄存（契约属性 uErrorId 数据源）/ the internal error register, the property data source
    _bFault    : BOOL := FALSE;   // 故障锁存位（契约属性 bFault 数据源之一）/ the fault latch bit
    _bCooling  : BOOL := FALSE;   // 冷却计时进行中 [-] / the cooling timing active
    _bInhibit  : BOOL := FALSE;   // 重启抑制激活寄存（契约属性 bRestartInhibit 数据源）/ the restart inhibit register
    _bPendStart: BOOL := FALSE;   // 方法启动请求（CmdStart 置位）/ the method start request
    _bPendReset: BOOL := FALSE;   // 方法复位请求（CmdReset 置位）/ the method reset request
    _bStopLatch: BOOL := FALSE;   // 停止锁存（引脚或方法置位，主体消化）/ the stop latch
    rtStart    : R_TRIG;          // 引脚启动指令沿，段 0 无条件刷新 / the pin start edge
    rtReset    : R_TRIG;          // 引脚复位沿，段 0 无条件刷新 / the pin reset edge
    tonRamp    : TON;             // 斜坡窗，段 0 无条件刷新 / the ramp window
    tonFb      : TON;             // 旁路反馈确认窗，段 0 无条件刷新 / the bypass feedback window
    tonStop    : TON;             // 停机分断确认窗，段 0 无条件刷新 / the stop confirm window
    tonInh     : TON;             // 重启抑制冷却窗，段 0 无条件刷新 / the restart inhibit cooling window
END_VAR

METHOD CmdStart : BOOL
VAR_INPUT
END_VAR
IF (_ePhase <> E_DL_SsdPhase.eSsdIdle) OR _bFault OR _bInhibit THEN // 非空闲 / 故障 / 抑制拒绝 / refused when not idle, faulty or inhibited
    CmdStart := FALSE; // 拒绝 / refused
ELSE // 受理 / accepted
    _bPendStart := TRUE; // 登记启动请求，主体状态机消化 / register the start request for the body
    CmdStart := TRUE; // 受理 / accepted
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdStop —— 无条件安全停止（双命令全断语义，主体在载能相消化）。
 *      Method CmdStop, the unconditional safe stop, consumed by the body in the powered phases.
 *------------------------------------------------------------------------------*)
    END_METHOD

METHOD CmdStop
VAR_INPUT
END_VAR
_bStopLatch := TRUE; // 登记停止锁存，主体状态机消化 / register the stop latch for the body

(*------------------------------------------------------------------------------
 * 方法: CmdReset —— 复位过载 / 故障，返回是否可复位。
 *      Method CmdReset, resets the overload or the fault, returns the resettable verdict.
 *------------------------------------------------------------------------------*)
    END_METHOD

METHOD CmdReset : BOOL
VAR_INPUT
END_VAR
IF _bFault OR (_ePhase = E_DL_SsdPhase.eSsdTrip) OR (_ePhase = E_DL_SsdPhase.eSsdFault) THEN // 存在锁存故障 / a latch exists
    _bPendReset := TRUE; // 登记复位请求，主体状态机消化 / register the reset request for the body
    CmdReset := TRUE; // 可复位 / resettable
ELSE // 无故障可复位 / nothing to reset
    CmdReset := FALSE; // 不可复位 / not resettable
END_IF

(*------------------------------------------------------------------------------
 * 属性: eState（GET）—— 当前状态（内部相位映射契约枚举 E_DL_MotorState）。
 *      Property eState, the internal phase mapped onto the contract enum.
 *------------------------------------------------------------------------------*)
    END_METHOD

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支，FB50-1）/ segment 0, the unconditional refresh
rtStart(CLK := bCmdStart); // 启动沿 / the start edge
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonRamp(IN := (_ePhase = E_DL_SsdPhase.eSsdRamp) AND (NOT _bFault), PT := tRampTime); // 斜坡窗，IN 串斜坡相闸 / the ramp window gated by the ramp phase
tonFb(IN := (_ePhase = E_DL_SsdPhase.eSsdByWait) AND (NOT _bFault), PT := tFbWindow); // 反馈窗，IN 串投旁路相闸 / the feedback window gated by the engage phase
tonStop(IN := (_ePhase = E_DL_SsdPhase.eSsdStop) AND (NOT _bFault), PT := tStopConfirm); // 停机窗，IN 串停机相闸 / the stop window gated by the stop phase
tonInh(IN := _bCooling, PT := tRestartInhibit); // 冷却窗自复位由到期分支消化 / the cooling window absorbed by the expiry branch
IF tonInh.Q THEN // 冷却到期 / the cooling expired
    _bCooling := FALSE; // 结束冷却计时 / stop the cooling timing
    _bInhibit := FALSE; // 解除重启抑制 / release the inhibit
ELSE // 冷却中 / while cooling
    _bInhibit := _bCooling; // 抑制寄存随冷却 / the inhibit follows the cooling
END_IF

// 段 1｜公约声明（本块为纯事件型状态机，无学习 / 积分 / 滤波状态，首扫跟踪
//       范式不适用，变量零值由编译器缺省保证，无内部初始化标志——与族内
//       FB_DL_DolMotor 公约 0.1 同口径）
// segment 1, the convention note, a pure event state machine with no learning or integral state

// 段 2｜复位沿作用域：清锁存 / 清码 / 迁空闲（三项逐项声明，R59 轻①：前置故障相位门——故障相位下复位只清锁存不迁相，
//       迁相交由 CASE 故障相复位分支消化，避免绕过 eSsdFault 分支的进冷却语义）/ segment 2, the reset edge scope
IF rtReset.Q THEN // 复位沿 / the reset edge
    IF _ePhase <> E_DL_SsdPhase.eSsdFault THEN // 故障相位门：非故障相才执行迁相 / the fault phase gate, migrate only outside the fault phase
        _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
        _uErrorId := 0; // 作用域二：清故障码 / scope two, clear the code
        _ePhase := E_DL_SsdPhase.eSsdIdle; // 作用域三：迁空闲相 / scope three, back to idle
    ELSE // 故障相位：仅清锁存与码，不迁相（迁相与进冷却由段 4 eSsdFault 分支消化）/ the fault phase, latch and code only
        _bFault := FALSE; // 清故障锁存 / clear the fault latch
        _uErrorId := 0; // 清故障码 / clear the code
    END_IF
END_IF

// 段 3｜过载全局监视（优先级最高，R190 独立成因独立码，边界三）/ segment 3, the global overload monitor
IF bOverload AND ((_ePhase = E_DL_SsdPhase.eSsdRamp) OR (_ePhase = E_DL_SsdPhase.eSsdByWait) OR (_ePhase = E_DL_SsdPhase.eSsdRun)) THEN // 载能相过载 / an overload in a powered phase
    _bFault  := TRUE; // 置故障锁存 / raise the fault latch
    _uErrorId := 16#0003_0215; // 0003_0215 过载锁存【故障级】/ the overload latch, fault grade
    _ePhase  := E_DL_SsdPhase.eSsdTrip; // 迁脱扣相（锁存与迁相同分支，FB50-1）/ migrate to the trip phase
END_IF

// 段 4｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 4, the phase machine
CASE _ePhase OF

E_DL_SsdPhase.eSsdIdle: // 空闲相 / the idle phase
    IF _bStopLatch THEN // 停止锁存消化 / absorb the stop latch
        _bStopLatch := FALSE; // 锁存清零 / clear the latch
    END_IF
    IF _bPendStart OR rtStart.Q THEN // 启动请求 / a start request
        _bPendStart := FALSE; // 消费请求不自动重试 / consume the request, no retry
        IF bOverload THEN // 过载未复位静默拒绝（脱扣码已在过载相锁存，驻留不迁移）/ an overload present, silent refusal, dwell without migrate
        ELSIF NOT bPermitStart THEN // 联锁未满足静默拒绝（驻留不迁移，R59 轻②删自赋值死语句）/ the permit absent, silent refusal
        ELSIF _bInhibit THEN // 抑制期拒绝（信息级 0217，R190 独立成因，驻留不迁移）/ refused during the inhibit, info grade
            _uErrorId := 16#0003_0217; // 0003_0217 重启抑制期拒绝【信息级】/ the inhibit refusal, info grade
        ELSE // 受理启动 / accept the start
            _ePhase := E_DL_SsdPhase.eSsdRamp; // 迁斜坡相 / migrate to the ramp
        END_IF
    END_IF

E_DL_SsdPhase.eSsdRamp: // 斜坡相：运行端子得电旁路断开 / the ramp phase
    IF bFbBypass THEN // 旁路提前吸合矛盾（R190 独立成因）/ a premature bypass pick up contradiction
        _bFault  := TRUE; // 置故障锁存 / raise the fault latch
        _uErrorId := 16#0003_0214; // 0003_0214 斜坡期旁路提前吸合【故障级】/ the premature bypass, fault grade
        _ePhase  := E_DL_SsdPhase.eSsdFault; // 迁故障相 / migrate to the fault phase
    ELSIF bCmdStop OR _bStopLatch THEN // 停机中止 / a stop abort
        _bStopLatch := FALSE; // 消化停止锁存 / absorb the stop latch
        _ePhase := E_DL_SsdPhase.eSsdStop; // 迁停机相（启动中止无运行时长）/ migrate to the stop phase
    ELSIF tonRamp.Q THEN // 斜坡窗到 / the ramp done
        _ePhase := E_DL_SsdPhase.eSsdByWait; // 迁投旁路相 / migrate to the engage phase
    END_IF

E_DL_SsdPhase.eSsdByWait: // 投旁路相：等旁路反馈吸合确认 / the engage phase
    IF bFbBypass THEN // 反馈吸合确认 / the feedback confirmed
        _ePhase := E_DL_SsdPhase.eSsdRun; // 迁运行相 / migrate to the run phase
    ELSIF bCmdStop OR _bStopLatch THEN // 停机中止 / a stop abort
        _bStopLatch := FALSE; // 消化停止锁存 / absorb the stop latch
        _ePhase := E_DL_SsdPhase.eSsdStop; // 迁停机相 / migrate to the stop phase
    ELSIF tonFb.Q THEN // 反馈确认窗超时（启动超时保护）/ the feedback window timed out
        _bFault  := TRUE; // 置故障锁存 / raise the fault latch
        _uErrorId := 16#0003_0211; // 0003_0211 旁路反馈确认超时【故障级】/ the bypass feedback timeout, fault grade
        _ePhase  := E_DL_SsdPhase.eSsdFault; // 迁故障相 / migrate to the fault phase
    END_IF

E_DL_SsdPhase.eSsdRun: // 运行相：旁路反馈吸合确认带载 / the run phase
    IF NOT bFbBypass THEN // 运行中旁路反馈意外断开（R190 独立成因）/ the feedback dropped while running
        _bFault  := TRUE; // 置故障锁存 / raise the fault latch
        _uErrorId := 16#0003_0212; // 0003_0212 运行中旁路反馈断开【故障级】/ the feedback loss, fault grade
        _ePhase  := E_DL_SsdPhase.eSsdFault; // 迁故障相 / migrate to the fault phase
    ELSIF bCmdStop OR _bStopLatch THEN // 停机指令 / a stop command
        _bStopLatch := FALSE; // 消化停止锁存 / absorb the stop latch
        _ePhase := E_DL_SsdPhase.eSsdStop; // 迁停机相 / migrate to the stop phase
    END_IF

E_DL_SsdPhase.eSsdStop: // 停机过渡相：双命令全断等旁路分断确认（边界二）/ the stop transition phase
    IF NOT bFbBypass THEN // 旁路分断确认 / the drop out confirmed
        _bCooling := TRUE; // 启动重启抑制冷却 / start the cooling
        _ePhase := E_DL_SsdPhase.eSsdIdle; // 回空闲相 / back to idle
    ELSIF tonStop.Q THEN // 停机确认窗超时（触点粘连，R190 独立成因）/ the stop confirm timeout, a welded contact
        _bFault  := TRUE; // 置故障锁存 / raise the fault latch
        _uErrorId := 16#0003_0213; // 0003_0213 停机旁路未分断【故障级】/ the drop out timeout, fault grade
        _ePhase  := E_DL_SsdPhase.eSsdFault; // 迁故障相 / migrate to the fault phase
    END_IF

E_DL_SsdPhase.eSsdTrip: // 过载脱扣锁存相：仅复位且过载消失可清 / the trip latch phase
    IF (rtReset.Q OR _bPendReset) AND (NOT bOverload) THEN // 复位且过载消失 / a reset with the overload removed
        _bPendReset := FALSE; // 消费复位请求 / consume the reset request
        _bFault := FALSE; // 解除锁存（解除路径 = 复位沿，R188）/ release the latch
        _uErrorId := 0; // 清故障码 / clear the code
        _bCooling := TRUE; // 脱扣复位进冷却 / start the cooling
        _ePhase := E_DL_SsdPhase.eSsdIdle; // 回空闲相 / back to idle
    END_IF

E_DL_SsdPhase.eSsdFault: // 故障锁存相：仅复位可清 / the fault latch phase
    IF rtReset.Q OR _bPendReset THEN // 复位沿 / a reset edge
        _bPendReset := FALSE; // 消费复位请求 / consume the reset request
        _bFault := FALSE; // 解除锁存（解除路径 = 复位沿，R188）/ release the latch
        _uErrorId := 0; // 清故障码 / clear the code
        _bCooling := TRUE; // 故障复位进冷却 / start the cooling
        _ePhase := E_DL_SsdPhase.eSsdIdle; // 回空闲相 / back to idle
    END_IF

ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _bFault  := TRUE; // 置故障锁存 / raise the fault latch
    _uErrorId := 16#0003_0216; // 0003_0216 非法状态【故障级】/ the illegal state, fault grade
    _ePhase  := E_DL_SsdPhase.eSsdFault; // 迁故障相 / migrate to the fault phase
END_CASE

// 段 5｜统一出口：命令输出按相位单点映射（边界二安全侧全断）/ segment 5, the unified outlet
bCmdRun := (_ePhase = E_DL_SsdPhase.eSsdRamp) OR (_ePhase = E_DL_SsdPhase.eSsdByWait) OR (_ePhase = E_DL_SsdPhase.eSsdRun); // 运行端子仅载能相保持 / the run terminal held in the powered phases
bCmdBypass := (_ePhase = E_DL_SsdPhase.eSsdByWait) OR (_ePhase = E_DL_SsdPhase.eSsdRun); // 旁路线圈仅投旁路与运行相 / the bypass coil in the engage and run phases
IF _bFault OR (_ePhase = E_DL_SsdPhase.eSsdTrip) OR (_ePhase = E_DL_SsdPhase.eSsdFault) THEN // 故障相覆盖闸（R191 降级显式）/ the fault phase override
    bCmdRun := FALSE; // 运行端子安全侧断开 / the run terminal off on the safe side
    bCmdBypass := FALSE; // 旁路线圈安全侧断开 / the bypass coil off on the safe side
END_IF

(*------------------------------------------------------------------------------
 * 方法: CmdStart —— 启动指令（单发）。故障 / 脱扣 / 抑制 / 非空闲态返回 FALSE。
 *      Method CmdStart, a one shot start, FALSE when latched, tripped, inhibited or not idle.
 *------------------------------------------------------------------------------*)



PROPERTY eState : E_DL_MotorState
CASE _ePhase OF // 内部相位到契约枚举映射 / the internal phase to the contract enum mapping
E_DL_SsdPhase.eSsdIdle:   eState := E_DL_MotorState.eIdle;          // 空闲映射 / the idle mapping
E_DL_SsdPhase.eSsdRamp:   eState := E_DL_MotorState.eStarting;      // 斜坡归启动校验态 / the ramp mapped to starting
E_DL_SsdPhase.eSsdByWait: eState := E_DL_MotorState.eStarting;      // 投旁路归启动校验态 / the engage mapped to starting
E_DL_SsdPhase.eSsdRun:    eState := E_DL_MotorState.eRunning;       // 运行映射 / the run mapping
E_DL_SsdPhase.eSsdStop:   eState := E_DL_MotorState.eStopping;      // 停机映射 / the stop mapping
E_DL_SsdPhase.eSsdTrip:   eState := E_DL_MotorState.eTripOverload;  // 脱扣映射 / the trip mapping
E_DL_SsdPhase.eSsdFault:  eState := E_DL_MotorState.eFault;         // 故障映射 / the fault mapping
ELSE                      eState := E_DL_MotorState.eFault;         // 非法相位按故障态上报（R128）/ the illegal phase reported as the fault
END_CASE

(*------------------------------------------------------------------------------
 * 属性: bRunning（GET）—— 运行反馈（运行相且旁路反馈吸合确认）。
 *      Property bRunning, the run feedback, the run phase with the bypass confirmed.
 *------------------------------------------------------------------------------*)
PROPERTY bRunning : BOOL
bRunning := (_ePhase = E_DL_SsdPhase.eSsdRun) AND bFbBypass; // 显式确认式派生 / the explicit confirmed derived form

(*------------------------------------------------------------------------------
 * 属性: bFault（GET）—— 故障锁存指示（信息级 0217 不置本位，0.2 公约）。
 *      Property bFault, the fault latch indicator, the info code excluded.
 *------------------------------------------------------------------------------*)
PROPERTY bFault : BOOL
bFault := _bFault OR (_ePhase = E_DL_SsdPhase.eSsdTrip) OR (_ePhase = E_DL_SsdPhase.eSsdFault); // 显式排除信息级派生式 / the derived form excluding the info grade

(*------------------------------------------------------------------------------
 * 属性: uErrorId（GET）—— 末次故障码（0 = 无故障）。
 *      Property uErrorId, the last error code, zero when none.
 *------------------------------------------------------------------------------*)
PROPERTY uErrorId : UDINT
uErrorId := _uErrorId; // 返回内部故障码寄存 / return the internal error register

(*------------------------------------------------------------------------------
 * 属性: bRestartInhibit（GET）—— 重启抑制激活指示。
 *      Property bRestartInhibit, the restart inhibit active indicator.
 *------------------------------------------------------------------------------*)
PROPERTY bRestartInhibit : BOOL
bRestartInhibit := _bInhibit; // 返回抑制寄存 / return the inhibit register
END_FUNCTION_BLOCK
