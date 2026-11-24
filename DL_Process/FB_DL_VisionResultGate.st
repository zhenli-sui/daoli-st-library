(*
  ==================================================================
  组件名 Component  : FB_DL_VisionResultGate
  分类   Category   : DL_Process
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : 视觉结果门控。工件到位沿开判决窗 tJudgeWin：窗内收到
                      结果选通（rtReady）按 bVisionOk 判 OK/NG；NG 可复检
                      （nRecheckMax 次上限）；窗超时无结果降级（bDegrade 单
                      脉冲 + nDegradeCnt 计数，安全侧判 NG 拒收）。TcOpen
                      视觉契约族范式，与 FB_DL_RobotGripVerify 分工。
  来源   Source     : T1-5-tcopen（TcOpen 视觉契约族范式）
  溯源   Origin     : 视觉判决窗与复检计数为公开工程范式，clean-room 自研
                      实现，未复制 TcOpen 或任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: TON / R_TRIG，无私有库）
  分工声明 Split     : 与 FB_DL_RobotGripVerify 分工——后者做机器人抓取验
                      证，本件做视觉 OK/NG 判决门控。
  作者   Author     : 道莅代码库 · PLC 编程专家（R59）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 安全语义：降级（超时无结果）安全侧判 NG 拒收（R191
                         降级显式）；故障相输出全清；
                      二 判决窗到期即出（窗口末退出迁移，纪律④）；复检共用
                         同一窗口（迁相时窗续走不重启）；
                      三 bPass / bReject / bDegrade 均单拍脉冲，每拍前置清
                         零（纪律③防粘滞）；
                      四 组态域：nRecheckMax ∈ [0..9]，越域锁存 bError（解
                         除 = bReset 沿，R188）；
                      五 定时器与沿检测全部段 0 无条件周期刷新（R7）；
                      六 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R59 首版（批 4 · 序号 18）
  ==================================================================
*)

TYPE E_DL_VrgPhase :
(
    eVrgIdle    := 0,  // 空闲：等工件到位沿 / idle, awaiting the part edge
    eVrgJudge   := 10, // 判决窗：等结果选通 / the judge window, awaiting the result strobe
    eVrgRecheck := 20, // 复检窗：NG 后重判 / the recheck window after an NG
    eVrgFault   := 90  // 故障锁存：仅复位可清 / the latched fault
);
END_TYPE

FUNCTION_BLOCK FB_DL_VisionResultGate
VAR_INPUT
    bPartIn      : BOOL := FALSE; // 工件到位信号，上升沿开窗 [-] / the part in place signal, the rising edge opens the window
    bResultReady : BOOL := FALSE; // 视觉结果选通（结果有效单发）[-] / the result strobe, one shot valid
    bVisionOk    : BOOL := FALSE; // 视觉判决结果，TRUE = OK [-] / the vision verdict, true = ok
    tJudgeWin    : TIME := T#1S;  // 判决窗时长 [毫秒] / the judge window [millisecond]
    nRecheckMax  : INT  := 1;     // 复检次数上限 [次]，域 0..9 / the recheck bound, zero through nine
    bReset       : BOOL := FALSE; // 故障与组态复位，上升沿生效 [-] / the fault and config reset, rising edge
END_VAR
VAR_OUTPUT
    bPass        : BOOL := FALSE; // 判 OK 单脉冲（单拍）[-] / the pass one shot pulse, single scan
    bReject      : BOOL := FALSE; // 判 NG 拒收单脉冲（单拍）[-] / the reject one shot pulse, single scan
    bDegrade     : BOOL := FALSE; // 超时无结果降级单脉冲（单拍）[-] / the degrade one shot pulse, single scan
    nRecheckCnt  : INT  := 0;   // 当前件复检计数 [次] / the current part recheck count
    nDegradeCnt  : UDINT := 0;  // 累计降级计数 [次] / the accumulated degrade count
    eState       : E_DL_VrgPhase := E_DL_VrgPhase.eVrgIdle; // 流程状态输出 [-] / the process state outlet
    bFault       : BOOL := FALSE; // 故障锁存指示（解除 = bReset 沿）[-] / the fault latch indicator
    bError       : BOOL := FALSE; // 组态域闸故障锁存 [-] / the config gate fault latch
END_VAR
VAR CONSTANT
    DL_VRG_CNTMAX : UDINT := 4294967294; // 计数防回绕上界 [次] / the counter anti wrap clamp bound
END_VAR
VAR
    _ePhase    : E_DL_VrgPhase := E_DL_VrgPhase.eVrgIdle; // 内部相位，CASE 唯一写入目标 / the internal phase, the single CASE write target
    _nRecheck  : INT := 0;   // 复检计数寄存 [次] / the recheck count register
    _bInit     : BOOL := FALSE; // 首拍初始化标志（R310，真实使用：首拍安全态预置）/ the first scan flag, real use
    rtPart     : R_TRIG;     // 到位沿，段 0 无条件刷新 / the part edge
    rtReady    : R_TRIG;     // 结果选通沿，段 0 无条件刷新 / the strobe edge
    rtReset    : R_TRIG;     // 复位沿，段 0 无条件刷新 / the reset edge
    tonJudge   : TON;        // 判决窗，段 0 无条件刷新 / the judge window
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支，R7）/ segment 0, the unconditional refresh
rtPart(CLK := bPartIn); // 到位沿 / the part edge
rtReady(CLK := bResultReady); // 选通沿 / the strobe edge
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonJudge(IN := (_ePhase = E_DL_VrgPhase.eVrgJudge) OR (_ePhase = E_DL_VrgPhase.eVrgRecheck), PT := tJudgeWin); // 判决窗（复检共用不重启，边界二）/ the judge window shared by the recheck

// 段 1｜首拍初始化（R310 真实使用路径）：相位安全态显式预置 / segment 1, the first scan init
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the flag
    _ePhase := E_DL_VrgPhase.eVrgIdle; // 相位显式安全预置 / the explicit safe preset
END_IF

// 段 2｜组态域闸与复位（边界四，解除路径 = bReset 沿，R188）/ segment 2, the config gate and the reset
IF (nRecheckMax < 0) OR (nRecheckMax > 9) THEN // 复检上限越域 / the recheck bound out of domain
    bError := TRUE; // 置域闸锁存 / raise the config latch
END_IF
IF rtReset.Q THEN // 复位沿 / the reset edge
    bError := FALSE; // 清域闸锁存 / clear the config latch
    _nRecheck := 0; // 清复检计数 / clear the recheck count
    IF _ePhase = E_DL_VrgPhase.eVrgFault THEN // 仅故障相消化复位迁相 / only the fault phase consumes the reset
        _ePhase := E_DL_VrgPhase.eVrgIdle; // 回空闲（解除路径唯一，R188）/ back to idle
    END_IF
END_IF

// 段 3｜单拍脉冲前置清零（边界三，纪律③）/ segment 3, the per scan pulse preset
bPass := FALSE; // 通过脉冲预清零 / preset the pass false
bReject := FALSE; // 拒收脉冲预清零 / preset the reject false
bDegrade := FALSE; // 降级脉冲预清零 / preset the degrade false

// 段 4｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R6 / R128）/ segment 4, the phase machine
CASE _ePhase OF

E_DL_VrgPhase.eVrgIdle: // 空闲相 / the idle phase
    IF rtPart.Q AND (NOT bError) THEN // 受理到位沿开窗（组态合法）/ accept the part edge
        _nRecheck := 0; // 复检计数清零 / clear the recheck count
        _ePhase := E_DL_VrgPhase.eVrgJudge; // 迁判决窗相 / to the judge phase
    END_IF

E_DL_VrgPhase.eVrgJudge: // 判决窗相 / the judge phase
    IF rtReady.Q THEN // 结果选通 / the result strobe
        IF bVisionOk THEN // 判 OK / the ok verdict
            bPass := TRUE; // 置通过单脉冲 / raise the pass pulse
            _ePhase := E_DL_VrgPhase.eVrgIdle; // 回空闲 / back to idle
        ELSIF _nRecheck < nRecheckMax THEN // NG 且复检额度未用尽 / an NG with the recheck budget left
            _nRecheck := _nRecheck + 1; // 复检计数推进 / advance the recheck count
            _ePhase := E_DL_VrgPhase.eVrgRecheck; // 迁复检窗相（窗续走不重启）/ to the recheck phase
        ELSE // NG 且额度用尽：拒收 / the NG beyond the budget, reject
            bReject := TRUE; // 置拒收单脉冲 / raise the reject pulse
            _ePhase := E_DL_VrgPhase.eVrgIdle; // 回空闲 / back to idle
        END_IF
    ELSIF tonJudge.Q THEN // 窗超时无结果：降级安全侧判 NG（窗口末退出迁移，边界一二）/ the window expired, the safe downgrade
        bDegrade := TRUE; // 置降级单脉冲 / raise the degrade pulse
        bReject := TRUE; // 降级安全侧拒收（R191 降级显式）/ the safe reject
        IF nDegradeCnt < DL_VRG_CNTMAX THEN // 计数防回绕 / the wrap guard
            nDegradeCnt := nDegradeCnt + 1; // 降级计数推进 / advance the degrade count
        END_IF
        _ePhase := E_DL_VrgPhase.eVrgIdle; // 回空闲 / back to idle
    END_IF

E_DL_VrgPhase.eVrgRecheck: // 复检窗相 / the recheck phase
    IF rtReady.Q THEN // 复检结果选通 / the recheck strobe
        IF bVisionOk THEN // 复检判 OK / the recheck ok
            bPass := TRUE; // 置通过单脉冲 / raise the pass pulse
            _ePhase := E_DL_VrgPhase.eVrgIdle; // 回空闲 / back to idle
        ELSE // 复检仍 NG：终判拒收 / the recheck NG, the final reject
            bReject := TRUE; // 置拒收单脉冲 / raise the reject pulse
            _ePhase := E_DL_VrgPhase.eVrgIdle; // 回空闲 / back to idle
        END_IF
    ELSIF tonJudge.Q THEN // 复检窗超时：安全侧拒收（窗口末退出迁移）/ the recheck window expired, the safe reject
        bReject := TRUE; // 置拒收单脉冲 / raise the reject pulse
        _ePhase := E_DL_VrgPhase.eVrgIdle; // 回空闲 / back to idle
    END_IF

E_DL_VrgPhase.eVrgFault: // 故障锁存相：本件无迁入源，保留对称兜底位 / the fault latch phase, reserved symmetric
    // 驻留无动作：迁相由段 2 复位分支消化 / dwell, the migrate in the reset branch

ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _ePhase := E_DL_VrgPhase.eVrgIdle; // 回空闲安全相 / back to the safe idle
END_CASE

// 段 5｜统一出口（R191 名实双出口）/ segment 5, the unified outlet
nRecheckCnt := _nRecheck; // 复检计数出口 / the recheck count outlet
eState := _ePhase; // 状态出口 / the state outlet
bFault := (_ePhase = E_DL_VrgPhase.eVrgFault); // 故障指示与相位同源 / the fault indicator shares the phase
END_FUNCTION_BLOCK
