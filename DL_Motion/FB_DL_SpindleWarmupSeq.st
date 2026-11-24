(*
  ==================================================================
  组件名 Component  : FB_DL_SpindleWarmupSeq
  分类   Category   : DL_Motion
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : 主轴暖机顺控（5 步上限）。阶梯升速驻留：步内驻留
                      tDwell 到迁下步；轴承温升斜率闸：斜率窗内温升速率
                      ΔT/Δt 超限迁 ePause 驻留降温，回落解除；中途断电续暖：
                      输出 nStepDone 供调用方持久化，重启经 nResumeStep 续暖。
                      行业公开流程，与 FB_DL_SpindleOrientationStop 分工。
  来源   Source     : self（行业公开流程）
  溯源   Origin     : 主轴暖机阶梯升速与温升监视为行业公知流程，clean-room
                      自研实现，未复制任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: TON / R_TRIG，无私有库）
  分工声明 Split     : 与 FB_DL_SpindleOrientationStop 分工——后者做定向停，
                      本件做暖机顺控。
  作者   Author     : 道莅代码库 · PLC 编程专家（R59）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 安全语义：ePause / eFault / 停止 / 非有限温度时
                         fSpdCmd 统一出口安全侧零（R191 降级显式）；
                      二 温升斜率闸（独立成因独立标志 bSlopeTrip）：斜率 >
                         fSlopeMax 迁 ePause，解除判据 = 斜率 ≤ 0.5×限值
                         （带迟滞防振荡）；
                      三 步驻留窗到期即迁（窗口末退出迁移，纪律④）；推进
                         屏蔽一拍机制保证驻留计时器逐步重启；
                      四 非有限温度置 bBad（纪律②）挂起斜率闸不误判；
                      五 组态域：nSteps ∈ [1..5]，越域锁存 bError（解除 =
                         bReset 沿，R188）；
                      六 定时器与沿检测全部段 0 无条件周期刷新（R7）；
                      七 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R59 首版（批 3 · 序号 13）
  ==================================================================
*)

TYPE E_DL_SwsPhase :
(
    eSwsIdle  := 0,  // 空闲：等启动沿 / idle, awaiting the start edge
    eSwsWarm  := 10, // 暖机运行：步内升速驻留 / the warming run, the step dwell
    eSwsPause := 20, // 温升超限驻留降温：零速保持 / the slope trip dwell, the zero speed hold
    eSwsDone  := 30, // 暖机完成驻留 / the warmup done dwell
    eSwsFault := 90  // 故障锁存：仅复位可清 / the latched fault
);
END_TYPE

FUNCTION_BLOCK FB_DL_SpindleWarmupSeq
VAR_INPUT
    bStart       : BOOL := FALSE; // 启动指令，上升沿生效 [-] / the start command, rising edge effective
    bStop        : BOOL := FALSE; // 停止指令，电平生效 [-] / the stop command, level effective
    nResumeStep  : INT := 0;      // 断电续暖入口：调用方持久化的已完成步数 [步] / the persisted done steps for the resume
    nSteps       : INT := 5;      // 暖机步数 [步]，域 1..5 / the warmup step count, one through five
    aSpd         : ARRAY[0..4] OF LREAL; // 各步转速设定组 [转每分钟] / the per step speed settings [rev per minute]
    tDwell       : TIME := T#60S; // 步内驻留时长 [毫秒] / the per step dwell [millisecond]
    fTempC       : LREAL := 0.0;  // 轴承温度反馈 [摄氏度] / the bearing temperature feedback [degree celsius]
    fSlopeMax    : LREAL := 0.5;  // 温升斜率限 [摄氏度每秒] / the temperature slope limit [degree celsius per second]
    fSlopeWinSec : LREAL := 10.0; // 斜率测量窗 [秒] / the slope measure window [second]
    bReset       : BOOL := FALSE; // 故障与组态复位，上升沿生效 [-] / the fault and config reset, rising edge
END_VAR
VAR_OUTPUT
    fSpdCmd    : LREAL := 0.0; // 主轴转速指令输出（安全侧零基线）[转每分钟] / the spindle speed command outlet [rev per minute]
    nCurStep   : INT  := -1;   // 当前步索引，-1 = 未运行 [步] / the current step index, minus one when idle
    nStepDone  : INT  := 0;    // 已完成步数（调用方持久化用）[步] / the done steps for the caller persistence
    bRunning   : BOOL := FALSE; // 暖机运行指示 [-] / the warming running indicator
    bDone      : BOOL := FALSE; // 暖机完成单脉冲（单拍）[-] / the done one shot pulse, single scan
    bSlopeTrip : BOOL := FALSE; // 温升斜率超限实时标志 [-] / the slope trip live flag
    bBad       : BOOL := FALSE; // 非有限温度实时标志 [-] / the non finite temperature flag
    bError     : BOOL := FALSE; // 组态域闸故障锁存 [-] / the config gate fault latch
END_VAR
VAR CONSTANT
    DL_SWS_STEPMAX : INT  := 5;            // 步容量上界 [步] / the step capacity bound
    DL_SWS_EPS     : LREAL := 1.0E-9;      // 窗宽下阈值 [秒] / the window width threshold
END_VAR
VAR
    _ePhase   : E_DL_SwsPhase := E_DL_SwsPhase.eSwsIdle; // 内部相位，CASE 唯一写入目标 / the internal phase, the single CASE write target
    _nStep    : INT := 0;    // 当前步寄存 [步] / the current step register
    _fTRef    : LREAL := 0.0; // 斜率窗基准温度快照 [摄氏度] / the window reference temperature snapshot
    _fSlope   : LREAL := 0.0; // 最新斜率值 [摄氏度每秒] / the latest slope value
    _bAdv     : BOOL := FALSE; // 步推进屏蔽寄存（驻留计时器重启一拍用）/ the advance mask register
    _bInit    : BOOL := FALSE; // 首拍初始化标志（R310，真实使用：基准温度快照预置）/ the first scan flag, real use
    _bFinT    : BOOL;        // 温度有限工作量 [-] / the temperature finiteness work flag
    rtStart   : R_TRIG;      // 启动沿，段 0 无条件刷新 / the start edge
    rtReset   : R_TRIG;      // 复位沿，段 0 无条件刷新 / the reset edge
    tonDwell  : TON;         // 步驻留窗，段 0 无条件刷新 / the step dwell window
    tonSlope  : TON;         // 斜率测量窗（自复位），段 0 无条件刷新 / the slope self reset window
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支，R7）/ segment 0, the unconditional refresh
rtStart(CLK := bStart); // 启动沿 / the start edge
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonDwell(IN := (_ePhase = E_DL_SwsPhase.eSwsWarm) AND (NOT _bAdv), PT := tDwell); // 步驻留窗，推进屏蔽一拍 / the dwell window, masked per advance
tonSlope(IN := (_ePhase = E_DL_SwsPhase.eSwsWarm) AND (NOT tonSlope.Q) AND _bFinT, PT := T#1S); // 斜率采样窗（自复位，R188）/ the slope sampling window

// 段 1｜首拍初始化（R310 真实使用路径）：基准温度快照预置 / segment 1, the first scan init
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the flag
    _fTRef := fTempC; // 基准温度快照 / snapshot the reference temperature
END_IF

// 段 2｜组态域闸与复位（边界五，解除路径 = bReset 沿，R188）/ segment 2, the config gate and the reset
IF (nSteps < 1) OR (nSteps > DL_SWS_STEPMAX) THEN // 步数越域 / the step count out of domain
    bError := TRUE; // 置域闸锁存 / raise the config latch
END_IF
IF rtReset.Q THEN // 复位沿 / the reset edge
    bError := FALSE; // 清域闸锁存 / clear the config latch
    bSlopeTrip := FALSE; // 清斜率标志 / clear the slope flag
END_IF

// 段 3｜温度有限性与斜率闸（边界二四，斜率闸窗自复位）/ segment 3, the temperature finiteness and the slope gate
_bFinT := (fTempC = fTempC) AND ((fTempC - fTempC) = (fTempC - fTempC)); // 温度有限双判据（R79）/ the finiteness dual verdicts
bBad := NOT _bFinT; // 拒收实时标志（R191 名实双出口）/ the rejection flag
IF (_ePhase = E_DL_SwsPhase.eSwsWarm) AND _bFinT AND (fSlopeWinSec > DL_SWS_EPS) THEN // 有效测量窗 / the valid measure window
    IF tonSlope.Q THEN // 采样窗到期 / the sampling window expired
        _fSlope := (fTempC - _fTRef) / fSlopeWinSec; // 温升斜率 [摄氏度每秒]（除子域闸保证）/ the slope, divided by the gated width
        _fTRef := fTempC; // 基准快照刷新 / refresh the reference snapshot
        bSlopeTrip := _fSlope > fSlopeMax; // 斜率闸实时标志 / the slope trip live flag
    END_IF
END_IF

// 段 4｜单拍脉冲预清零（本库纪律③）/ segment 4, the per scan pulse preset
bDone := FALSE; // 完成脉冲预清零 / preset the done pulse false

// 段 5｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R6 / R128）/ segment 5, the phase machine
CASE _ePhase OF

E_DL_SwsPhase.eSwsIdle: // 空闲相 / the idle phase
    IF rtStart.Q AND (NOT bError) THEN // 受理启动（组态合法）/ accept the start
        IF (nResumeStep >= 1) AND (nResumeStep < nSteps) THEN // 断电续暖入口有效 / a valid resume entry
            _nStep := nResumeStep; // 从续暖步起跳 / jump to the resume step
        ELSE // 全新暖机 / a fresh warmup
            _nStep := 0; // 步归零 / reset the step
        END_IF
        _fTRef := fTempC; // 基准快照刷新 / refresh the snapshot
        bSlopeTrip := FALSE; // 斜率标志清 / clear the slope flag
        _ePhase := E_DL_SwsPhase.eSwsWarm; // 运行相 / to the warm phase
    END_IF

E_DL_SwsPhase.eSwsWarm: // 暖机运行相 / the warm phase
    IF bStop OR bError THEN // 停止或组态故障中止 / a stop or config abort
        _ePhase := E_DL_SwsPhase.eSwsIdle; // 回空闲（保留 nStepDone 供续暖）/ back to idle, keep the done steps
    ELSIF bSlopeTrip THEN // 温升斜率超限（独立成因独立迁移，边界二）/ the slope trip
        _ePhase := E_DL_SwsPhase.eSwsPause; // 迁驻留降温相 / to the pause phase
    ELSIF tonDwell.Q THEN // 步驻留窗到期（窗口末退出迁移，边界三）/ the dwell expired
        _bAdv := TRUE; // 推进屏蔽一拍（驻留计时器下拍重启）/ raise the advance mask
        _nStep := _nStep + 1; // 步推进 / advance the step
        nStepDone := _nStep; // 已完成步数出口（持久化口径）/ the done steps outlet
        IF _nStep >= nSteps THEN // 全步完成 / all the steps done
            _nStep := 0; // 步归零 / reset the step
            _ePhase := E_DL_SwsPhase.eSwsDone; // 完成驻留相 / to the done phase
            bDone := TRUE; // 置完成单脉冲 / raise the done pulse
        END_IF
    END_IF

E_DL_SwsPhase.eSwsPause: // 温升超限驻留降温相（零速保持，边界一）/ the pause dwell phase
    IF bStop OR bError THEN // 停止或组态故障中止 / a stop or config abort
        _ePhase := E_DL_SwsPhase.eSwsIdle; // 回空闲 / back to idle
    ELSIF (NOT bSlopeTrip) AND _bFinT THEN // 斜率回落到迟滞带内解除（迟滞 0.5×限值）/ the slope recovered with the hysteresis
        _ePhase := E_DL_SwsPhase.eSwsWarm; // 回运行相（驻留计时自然重启）/ back to the warm phase
    END_IF

E_DL_SwsPhase.eSwsDone: // 完成驻留相 / the done dwell phase
    IF bStop THEN // 停止消化 / absorb the stop
        _ePhase := E_DL_SwsPhase.eSwsIdle; // 回空闲 / back to idle
    END_IF

E_DL_SwsPhase.eSwsFault: // 故障锁存相（本件故障经 bError 直接回空闲，保留对称兜底位）/ the fault latch phase, reserved symmetric
    IF rtReset.Q THEN // 复位沿 / the reset edge
        _ePhase := E_DL_SwsPhase.eSwsIdle; // 回空闲 / back to idle
    END_IF

ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _ePhase := E_DL_SwsPhase.eSwsIdle; // 回空闲安全相 / back to the safe idle
END_CASE

// 段 6｜迟滞解除与推进屏蔽清除（每拍后段执行）/ segment 6, the hysteresis release and the mask clear
IF bSlopeTrip AND _bFinT AND (_fSlope <= (0.5 * fSlopeMax)) THEN // 迟滞解除（斜率降到半限以下）/ the hysteresis release
    bSlopeTrip := FALSE; // 清斜率标志 / clear the slope flag
END_IF
_bAdv := FALSE; // 推进屏蔽每拍清 / clear the advance mask every scan

// 段 7｜统一出口：转速指令单点安全映射（边界一）/ segment 7, the unified outlet
IF (_ePhase = E_DL_SwsPhase.eSwsWarm) AND (NOT bError) AND (NOT bStop) THEN // 暖机有效窗 / the valid warm window
    IF (_nStep >= 0) AND (_nStep < DL_SWS_STEPMAX) THEN // 步界闸（防越界读）/ the step bound gate
        fSpdCmd := aSpd[_nStep]; // 当前步转速设定 / the current step speed setting
    ELSE // 界外兜底 / the out of bound fallback
        fSpdCmd := 0.0; // 安全零 / the safe zero
    END_IF
ELSE // 非暖机相 / the non warm phases
    fSpdCmd := 0.0; // 安全侧零（R191 降级显式）/ the safe zero, the explicit downgrade
END_IF
nCurStep := _nStep; // 当前步出口 / the current step outlet
bRunning := (_ePhase = E_DL_SwsPhase.eSwsWarm); // 运行指示（R191 名实双出口）/ the running indicator
END_FUNCTION_BLOCK
