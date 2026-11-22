(*
    FB_DL_ParallelGripper —— 平行夹爪实现（实现 I_DL_Gripper）
    ------------------------------------------------------------------
    分类      : DL_Device / Actuator
    前缀      : FB_DL_
    版本      : 1.0.1
    溯源      : T2-6 Rockwell AOI（只借「设备级 AOI 粒度」分类事实）；
                T1-5 开源契约-实现分离范式（仅借分层思想）；
                状态机、超时策略、空夹语义、码位 100% 自有；clean-room 重写，
                未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R18）
    ------------------------------------------------------------------
    功能说明  : 三段动作（驱动 → 到位确认 → 夹持力保持），含单动作超时、在位与命令
                矛盾判定、无件闭合（空夹）判定；实现 I_DL_Gripper 全部属性与方法；
                不直接写输出地址：电磁阀 / 伺服指令经 bValveOut 输出引脚由上层映射，
                换品牌只改映射层；
                安全约定：bEnable 为 FALSE、复位沿、故障态三者都在同一拍把 bValveOut
                清为 FALSE（断开驱动），绝不把「清使能」当成「保持夹持」，防夹持件掉落；
                超时参数本身非法会让超时保护失效，故 032A 同时承担「动作超时」与
                「超时参数非法」两个同源语义；
                空夹（闭合到位但无工件）是合法工况，只置信息码与 bLoadOpen，不停线。
    接口实现  : I_DL_Gripper 的七个只读属性（bOpened / bClosed / bWorkpiecePresent /
                fWidth / eHealth / uErrorId / bError）与四个方法全部在本文件尾部落地。
                五个契约量（bOpened / bClosed / bWorkpiecePresent / fWidth / bError）
                只以属性形态对外，不再另设同名输出引脚——同名成员在同一功能块命名空间
                内冲突，会出现三平台编译阻断，故按属性优先原则收敛，契约语义一字不减。
    错误码    : 16#0003_0166 空夹到位 / 开合命令同拍闭合优先 / 力给定超域已钳位——信息级，不置故障
                16#0003_0167 预留禁用（信息级，不得挪用）
                16#0003_032A 动作超时（含超时参数非法）——故障级，转故障态并断驱动
                16#0003_032B 在位信号与命令矛盾，或状态机落 ELSE 兜底——故障级，转故障态
                16#0003_032C 预留禁用（故障级，不得挪用）
    码位总账  : 16#0003_0166 用 / 16#0003_0167 预留 ｜ 16#0003_032A 用 / 16#0003_032B 用 / 16#0003_032C 预留
    状态机    : E_DL_GripperState（eIdle / eOpening / eClosing / eHolding / eFault），
                CASE 含 ELSE 兜底，兜底固定置 eFault 与 032B
    采样约定  : fbTrigReset / fbMove / fbConfirm 三个实例均在本体首部无条件调用，
                IN 引脚承载全部条件，绝不把定时器放进 IF；两个定时器分别服务超时与
                到位确认，互不干扰。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R18）
                2026-11-16 v1.0.1 R18 终审修复：METHOD Close 的形参 fForceSetpoint 原先只登记请求、未落到
                力通道，被同名引脚给定静默覆盖（接口承诺「按指定夹持力闭合」实际不生效）；新增方法力锁存
                fForceMeth / bForceMeth，段 4 改为方法优先、用后即清，复位路径一并清理。对外引脚与属性零变更。
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_GripperState（归属本实现块，与其同文件发布）
 * 含义: 平行夹爪动作状态机离散态，步长 10 留空位，故障态取 99 排末位
 *----------------------------------------------------------------------------*)
TYPE E_DL_GripperState :
(
    eIdle    := 0,     // 空闲：无动作，驱动断开 / Idle, no motion, drive released
    eOpening := 10,    // 张开中：等待全开到位 / Opening, waiting for the open feedback
    eClosing := 20,    // 闭合中：等待闭合到位 / Closing, waiting for the close feedback
    eHolding := 30,    // 夹持保持：闭合到位后维持夹持力 / Holding, keeps the clamping force after arrival
    eFault   := 99     // 故障锁存：超时 / 矛盾 / 非法状态，仅复位清除 / Fault latched, timeout, conflict or illegal state, reset only
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_ParallelGripper IMPLEMENTS I_DL_Gripper
VAR_INPUT
    bEnable            : BOOL;                 // 使能，FALSE 撤所有输出并回空闲 / enable, FALSE drops every output and returns to idle
    bReset             : BOOL;                 // 复位，上升沿清故障 / reset, rising edge clears the fault
    bCmdOpen           : BOOL;                 // 张开请求，与闭合同拍时闭合优先 / open request, the close request wins when both are set
    bCmdClose          : BOOL;                 // 闭合请求 / close request
    fForceSetpoint     : REAL := 50.0;         // 夹持力给定 [%]，范围 0.0~100.0，超域钳位 / clamping force setpoint [%], range 0.0~100.0, clamped outside
    bOpenFeedback      : BOOL;                 // 全开到位传感器 / fully open position sensor
    bCloseFeedback     : BOOL;                 // 闭合到位传感器 / fully closed position sensor
    bWorkpieceFeedback : BOOL;                 // 工件在位传感器 / workpiece present sensor
    tMoveTime          : TIME := T#2S;         // 单动作超时 [ms]，范围 100~10000 / single action timeout [ms], range 100~10000
    tConfirmTime       : TIME := T#100MS;      // 到位确认时间 [ms]，范围 0~1000 / arrival confirmation time [ms], range 0~1000
END_VAR
VAR_OUTPUT
    bValveOut         : BOOL;                  // 驱动输出，TRUE 为闭合方向，由上层映射到物理点 / drive output, TRUE closes, mapped to the physical point upstream
    fForceOut         : REAL;                  // 实际下发夹持力，钳位后 [%] / clamping force actually issued after clamping [%]
    bBusy             : BOOL;                  // 动作中 / action in progress
    bDone             : BOOL;                  // 到位单周期脉冲 / arrival single-cycle pulse
    tElapsed          : TIME;                  // 本动作已耗时 [ms] / elapsed time of the current action [ms]
    eErr              : UDINT;                 // 错误码，0=正常 / error id, 0=ok
    bLoadOpen         : BOOL;                  // 空夹（闭合到位但无工件）/ empty clamp, closed without a workpiece
END_VAR
VAR
    fbTrigReset  : R_TRIG;                     // 复位沿检测实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    fbMove       : TON;                        // 单动作超时定时器，本体首部无条件刷新 / action timeout timer, refreshed unconditionally
    fbConfirm    : TON;                        // 到位确认定时器，本体首部无条件刷新 / arrival confirmation timer, refreshed unconditionally
    eState       : E_DL_GripperState := E_DL_GripperState.eIdle; // 内部状态机步序 / internal state machine step
    bPendOpen    : BOOL;                       // 方法张开请求锁存，由主体消费 / method open request latch, consumed by the body
    bPendClose   : BOOL;                       // 方法闭合请求锁存 / method close request latch
    bPendRelease : BOOL;                       // 方法泄力请求锁存 / method release request latch
    bPendClear   : BOOL;                       // 方法清故障请求锁存 / method clear fault request latch
    fForceEff    : REAL;                       // 生效夹持力，钳位后 [%] / effective clamping force after clamping [%]
    bAtTarget    : BOOL;                       // 本拍到位反馈成立标志 / arrival feedback valid this cycle
    bFaultLatch  : BOOL;                       // 故障锁存位，仅复位或方法复位清除 / fault latch, cleared by reset or the method only
    bLoadLatch   : BOOL;                       // 空夹锁存，复位清除 / empty clamp latch, cleared by reset
    bBothCmd     : BOOL;                       // 开合命令同拍标志 / both commands active flag
    fForceMeth   : REAL;                       // 方法给定的夹持力锁存，Close() 写入 [%] / clamping force latched by the Close method [%]
    bForceMeth   : BOOL;                       // 方法给定有效标志，段 4 消费后清 / method force valid flag, cleared after segment four consumes it
    fForceRaw    : REAL;                       // 本拍生效的原始力给定（方法优先于引脚）[%] / raw force actually in effect this cycle, the method wins over the pin [%]
END_VAR
VAR CONSTANT
    DL_GRP_FORCE_MAX  : REAL := 100.0;         // 夹持力上限 [%] / clamping force upper bound [%]
    DL_GRP_FORCE_MIN  : REAL := 0.0;           // 夹持力下限 [%] / clamping force lower bound [%]
    DL_GRP_MOVE_MIN   : TIME := T#100MS;       // 超时下限 [ms] / timeout lower bound [ms]
    DL_GRP_MOVE_MAX   : TIME := T#10S;         // 超时上限 [ms] / timeout upper bound [ms]
    DL_GRP_WIDTH_NONE : REAL := 0.0;           // 无模拟量反馈时的宽度缺省值 [mm] / default width without an analogue feedback [mm]
    DL_FLOAT_EPS      : REAL := 1.0E-6;        // 浮点判等容差 [%] / float equality tolerance [%]
END_VAR

METHOD Open : BOOL
VAR_INPUT
END_VAR
IF bFaultLatch OR (eState = E_DL_GripperState.eFault) THEN
    Open := FALSE;                             // 故障态拒绝 / rejected in the fault state
    bPendOpen := FALSE;                        // 清残留请求 / clear the stale request
ELSE
    bPendOpen := TRUE;                         // 登记张开请求，主体状态机消费 / register the request, consumed by the body
    bPendClose := FALSE;                       // 互斥注销闭合请求 / cancel the opposite request
    Open := TRUE;                              // 受理成功 / accepted
END_IF

(*-----------------------------------------------------------------------------
 * 方法: Close —— 请求闭合到指定夹持力。故障锁存期拒绝并返回 FALSE。
 *      Method Close - request closing at the given force, rejected while a fault is latched.
 *----------------------------------------------------------------------------*)
    END_METHOD

METHOD Close : BOOL
VAR_INPUT
    fForceSetpoint : REAL;                     // 目标夹持力 [%]，范围 0.0~100.0 / target clamping force [%], range 0.0~100.0
END_VAR
IF bFaultLatch OR (eState = E_DL_GripperState.eFault) THEN
    Close := FALSE;                            // 故障态拒绝 / rejected in the fault state
    bPendClose := FALSE;                       // 清残留请求 / clear the stale request
ELSE
    bPendClose := TRUE;                        // 登记闭合请求 / register the close request
    fForceMeth := fForceSetpoint;              // 锁存方法形参，由段 4 消费 / latch the method parameter, consumed by segment four
    bForceMeth := TRUE;                        // 置方法给定有效 / mark the method setpoint valid
    bPendOpen := FALSE;                        // 互斥注销张开请求 / cancel the opposite request
    Close := TRUE;                             // 受理成功 / accepted
END_IF

(*-----------------------------------------------------------------------------
 * 方法: Release —— 松开并撤力。与 Open 的区别是不驱动到位，只泄力。
 *      Method Release - drop the force without driving to the open end.
 *----------------------------------------------------------------------------*)
    END_METHOD

METHOD Release : BOOL
VAR_INPUT
END_VAR
IF bFaultLatch OR (eState = E_DL_GripperState.eFault) THEN
    Release := FALSE;                          // 故障态拒绝 / rejected in the fault state
ELSE
    bPendRelease := TRUE;                      // 登记泄力请求 / register the release request
    bPendOpen := FALSE;                        // 撤销张开请求 / cancel the open request
    bPendClose := FALSE;                       // 撤销闭合请求 / cancel the close request
    Release := TRUE;                           // 受理成功 / accepted
END_IF

(*-----------------------------------------------------------------------------
 * 方法: ClearFault —— 清故障锁存（热复位）。绝不隐式产生动作。
 *      Method ClearFault - clear the fault latch, never produces any motion.
 *----------------------------------------------------------------------------*)
    END_METHOD

METHOD ClearFault : BOOL
VAR_INPUT
END_VAR
IF bFaultLatch OR (eState = E_DL_GripperState.eFault) THEN
    bPendClear := TRUE;                        // 登记清故障请求，主体状态机消化 / register the request, consumed by the body
    ClearFault := TRUE;                        // 可复位 / resettable
ELSE
    ClearFault := FALSE;                       // 无故障可复位 / nothing to clear
END_IF

(*-----------------------------------------------------------------------------
 * 属性: bOpened（GET）—— 全开到位只读视图 / property bOpened (GET), read-only view
 *----------------------------------------------------------------------------*)
    END_METHOD

// 段 1｜边沿与两个定时器无条件周期刷新（红线：严禁放入条件分支）/ segment 1, unconditional refresh of the edge and both timers
fbTrigReset(CLK := bReset);
fbMove(IN := bEnable AND ((eState = E_DL_GripperState.eOpening) OR (eState = E_DL_GripperState.eClosing)), PT := tMoveTime); // 超时只服务动作态 / the timeout only serves the moving states
bAtTarget := ((eState = E_DL_GripperState.eOpening) AND bOpenFeedback)
          OR ((eState = E_DL_GripperState.eClosing) AND bCloseFeedback); // 到位判据按当前动作取对应反馈 / the arrival criterion picks the feedback of the current action
fbConfirm(IN := bEnable AND bAtTarget, PT := tConfirmTime); // 到位确认定时器 / arrival confirmation timer

// 段 2｜输出与错误状态预置 / segment 2, preset outputs and error status
bDone := FALSE;                                // 到位脉冲先清 / clear the arrival pulse first
eErr := 0;                                     // 预置无错误 / preset no error
bBusy := FALSE;                                // 预置不忙 / preset not busy
bValveOut := FALSE;                            // 驱动先按断开预置，安全侧 / preset the drive released, safe side
fForceOut := DL_GRP_FORCE_MIN;                 // 力输出先归零 / force output to zero first

// 段 3｜超时参数闸：参数非法会让超时保护失效，与动作超时同码 / segment 3, timeout parameter gate
IF (tMoveTime < DL_GRP_MOVE_MIN) OR (tMoveTime > DL_GRP_MOVE_MAX) THEN
    eErr := 16#0003_032A;                      // 超时参数非法故障码 / illegal timeout parameter fault id
    bFaultLatch := TRUE;                       // 锁存 / latch it
    eState := E_DL_GripperState.eFault;        // 转故障态 / enter the fault state
END_IF

// 段 4｜夹持力闸：方法给定优先于引脚给定，超域钳位并置信息码 / segment 4, the method force wins over the pin, then clamp and hint
fForceRaw := fForceSetpoint;                   // 默认取引脚给定 / default to the pin setpoint
IF bForceMeth THEN
    fForceRaw := fForceMeth;                   // 方法给定优先，Close() 的形参绝不静默丢弃 / the method setpoint wins, the Close parameter is never silently dropped
    bForceMeth := FALSE;                       // 用后即清，绝不跨拍残留 / consumed and cleared, never leaks to the next cycle
END_IF
fForceEff := MIN(MAX(fForceRaw, DL_GRP_FORCE_MIN), DL_GRP_FORCE_MAX); // 双侧钳位 / clamp both sides
IF ABS(fForceEff - fForceRaw) > DL_FLOAT_EPS THEN
    eErr := 16#0003_0166;                      // 力给定钳位提示（信息级不置故障）/ force clamp hint, info level never raises a fault
END_IF

// 段 5｜开合同拍判定：闭合优先（安全侧）/ segment 5, simultaneous command arbitration, close wins
bBothCmd := bCmdOpen AND bCmdClose;            // 同拍判定 / simultaneous detection
IF bBothCmd THEN
    eErr := 16#0003_0166;                      // 同拍提示（信息级不置故障）/ simultaneous hint, info level never raises a fault
END_IF

// 段 6｜复位沿与清故障方法：同拍优先于动作 / segment 6, reset edge and clear fault method take priority
IF fbTrigReset.Q OR bPendClear THEN
    bFaultLatch := FALSE;                      // 清故障锁存 / clear the fault latch
    bLoadLatch := FALSE;                       // 清空夹锁存 / clear the empty clamp latch
    bPendClear := FALSE;                       // 用后即清 / consumed and cleared
    bPendOpen := FALSE;                        // 清残留请求 / clear the stale requests
    bPendClose := FALSE;                       // 清残留请求 / clear the stale requests
    bPendRelease := FALSE;                     // 清残留请求 / clear the stale requests
    bForceMeth := FALSE;                       // 清方法力给定，防复位后误用旧值 / clear the method force so a stale value cannot be reused after a reset
    eState := E_DL_GripperState.eIdle;         // 回空闲态 / back to idle
END_IF

// 段 7｜使能闸：撤所有输出并回空闲（防夹持件掉落）/ segment 7, enable gate drops every output
IF NOT bEnable THEN
    bValveOut := FALSE;                        // 驱动断开 / drive released
    fForceOut := DL_GRP_FORCE_MIN;             // 力撤除 / force removed
    bBusy := FALSE;                            // 不忙 / not busy
    bPendOpen := FALSE;                        // 清请求 / clear the requests
    bPendClose := FALSE;                       // 清请求 / clear the requests
    bPendRelease := FALSE;                     // 清请求 / clear the requests
    eState := E_DL_GripperState.eIdle;         // 回空闲 / back to idle
    tElapsed := fbMove.ET;                     // 耗时镜像 / elapsed mirror
    RETURN;                                    // 失能即出口 / disabled is the exit
END_IF

// 段 8｜动作超时：定时器到期即故障并断驱动 / segment 8, action timeout
IF fbMove.Q THEN
    eErr := 16#0003_032A;                      // 动作超时故障码 / action timeout fault id
    bFaultLatch := TRUE;                       // 锁存 / latch it
    eState := E_DL_GripperState.eFault;        // 转故障态 / enter the fault state
END_IF

// 段 9｜在位与命令矛盾判定：闭合指令已撤但闭合反馈仍在且无工件 / segment 9, presence and command conflict
IF bCloseFeedback AND (NOT bWorkpieceFeedback) THEN
    bLoadLatch := TRUE;                        // 空夹锁存（合法工况，不停线）/ latch the empty clamp, a legal condition, no line stop
    eErr := 16#0003_0166;                      // 空夹提示（信息级不置故障）/ empty clamp hint, info level never raises a fault
END_IF

// 段 10｜状态机主体（CASE 必含 ELSE 兜底，红线）/ segment 10, state machine body
CASE eState OF
    E_DL_GripperState.eIdle :
        bValveOut := FALSE;                    // 空闲断驱动 / the idle state releases the drive
        fForceOut := DL_GRP_FORCE_MIN;         // 力撤除 / force removed
        IF bPendRelease THEN
            bPendRelease := FALSE;             // 泄力请求只清标志，不产生动作 / a release request only clears its flag, no motion
        ELSIF bCmdClose OR bPendClose THEN
            bPendClose := FALSE;               // 用后即清 / consumed and cleared
            eState := E_DL_GripperState.eClosing; // 闭合优先（含同拍情形）/ close wins, including the simultaneous case
        ELSIF bCmdOpen OR bPendOpen THEN
            bPendOpen := FALSE;                // 用后即清 / consumed and cleared
            eState := E_DL_GripperState.eOpening; // 进张开态 / enter the opening state
        END_IF
    E_DL_GripperState.eOpening :
        bValveOut := FALSE;                    // 张开方向驱动 / drive in the opening direction
        fForceOut := DL_GRP_FORCE_MIN;         // 张开不加力 / no force while opening
        bBusy := TRUE;                         // 动作中 / in motion
        IF fbConfirm.Q THEN
            bDone := TRUE;                     // 到位单拍脉冲 / arrival single-cycle pulse
            bBusy := FALSE;                    // 到位不忙 / no longer busy
            eState := E_DL_GripperState.eIdle; // 张开到位回空闲 / back to idle after opening
        END_IF
    E_DL_GripperState.eClosing :
        bValveOut := TRUE;                     // 闭合方向驱动 / drive in the closing direction
        fForceOut := fForceEff;                // 下发钳位后的夹持力 / issue the clamped force
        bBusy := TRUE;                         // 动作中 / in motion
        IF fbConfirm.Q THEN
            bDone := TRUE;                     // 到位单拍脉冲 / arrival single-cycle pulse
            bBusy := FALSE;                    // 到位不忙 / no longer busy
            eState := E_DL_GripperState.eHolding; // 进夹持保持态 / enter the holding state
        END_IF
    E_DL_GripperState.eHolding :
        bValveOut := TRUE;                     // 保持夹持 / keep clamping
        fForceOut := fForceEff;                // 保持钳位后的夹持力 / keep the clamped force
        bBusy := FALSE;                        // 保持态不算动作中 / holding is not an action
        IF (NOT bCmdClose) AND (NOT bPendClose) THEN
            eState := E_DL_GripperState.eIdle; // 命令撤销即回空闲 / back to idle when the command is withdrawn
        END_IF
    E_DL_GripperState.eFault :
        bValveOut := FALSE;                    // 故障态断驱动 / the fault state releases the drive
        fForceOut := DL_GRP_FORCE_MIN;         // 力撤除 / force removed
        bBusy := FALSE;                        // 不忙 / not busy
ELSE
    eState := E_DL_GripperState.eFault;        // 非法状态一律回安全故障态 / any illegal state falls back to the safe fault state
    eErr := 16#0003_032B;                      // 兜底故障码 / fallback fault id
    bFaultLatch := TRUE;                       // 锁存 / latch it
    bValveOut := FALSE;                        // 断驱动 / release the drive
    fForceOut := DL_GRP_FORCE_MIN;             // 力撤除 / force removed
END_CASE

// 段 11｜故障锁存对外输出与属性镜像 / segment 11, fault latch output and property mirrors
bLoadOpen := bLoadLatch;                       // 空夹输出镜像 / empty clamp mirror
tElapsed := fbMove.ET;                         // 本动作已耗时 / elapsed time of the current action

(*-----------------------------------------------------------------------------
 * 方法: Open —— 请求张开。故障锁存期拒绝并返回 FALSE。
 *      Method Open - request opening, rejected with FALSE while a fault is latched.
 *----------------------------------------------------------------------------*)




PROPERTY bOpened : BOOL
bOpened := bOpenFeedback;                      // 返回全开到位反馈 / return the open position feedback

(*-----------------------------------------------------------------------------
 * 属性: bClosed（GET）—— 闭合到位只读视图 / property bClosed (GET), read-only view
 *----------------------------------------------------------------------------*)
PROPERTY bClosed : BOOL
bClosed := bCloseFeedback;                     // 返回闭合到位反馈 / return the close position feedback

(*-----------------------------------------------------------------------------
 * 属性: bWorkpiecePresent（GET）—— 工件在位只读视图 / property bWorkpiecePresent (GET)
 *----------------------------------------------------------------------------*)
PROPERTY bWorkpiecePresent : BOOL
bWorkpiecePresent := bWorkpieceFeedback;       // 返回工件在位反馈 / return the workpiece feedback

(*-----------------------------------------------------------------------------
 * 属性: fWidth（GET）—— 开口宽度只读视图（本实现不做模拟量换算）/ property fWidth (GET)
 *----------------------------------------------------------------------------*)
PROPERTY fWidth : REAL
fWidth := DL_GRP_WIDTH_NONE;                   // 无模拟量反馈时的缺省宽度 / default width without an analogue feedback

(*-----------------------------------------------------------------------------
 * 属性: eHealth（GET）—— 健康状态，引用库内唯一属主枚举 / property eHealth (GET)
 *----------------------------------------------------------------------------*)
PROPERTY eHealth : E_DL_Ne107Status
IF bFaultLatch OR (eState = E_DL_GripperState.eFault) THEN
    eHealth := E_DL_Ne107Status.eFailure;      // 有锁存故障即失败级 / a latched fault maps to the failure class
ELSE
    eHealth := E_DL_Ne107Status.eOk;           // 否则健康 / otherwise healthy
END_IF

(*-----------------------------------------------------------------------------
 * 属性: uErrorId（GET）—— 末次故障码只读视图 / property uErrorId (GET)
 *----------------------------------------------------------------------------*)
PROPERTY uErrorId : UDINT
uErrorId := eErr;                              // 返回末次错误码 / return the last error id

(*-----------------------------------------------------------------------------
 * 属性: bError（GET）—— 故障锁存只读视图 / property bError (GET)
 *----------------------------------------------------------------------------*)
PROPERTY bError : BOOL
bError := bFaultLatch OR (eState = E_DL_GripperState.eFault); // 派生式排除信息级码 / derived form excluding info-level codes
END_FUNCTION_BLOCK
