(*
  FB_DL_AxisProbeTouchOffSeq —— 探针触测状态机：快进-慢进-触发记录-回退，超程与未触发超时双兜底
  分类：DL_Motion | 复杂度：3 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT

  职责：正向（+方向）接近工件的两段式触测序列——快进到 fFastSpan 后转慢进，探针上升沿记录当前实际位置，
        随后反向回退到 fRetractDist 之外并驻留，最后给出 xDone。
  输入契约：fPosAct 为轴实际位置 [mm]（由调用方从轴接口取，本件不引用任何物理地址）；
            fFastVel / fSlowVel > 0；fSoftMax > fSoftMin；fRetractDist > 0；tTimeout / tDwell 为标准 TIME。
  输出契约：fVelCmd 速度指令 [mm/s]（快进为正、回退为负）；fProbePos 记录的触发位置 [mm]；
            xDone / xFault 均为锁存位，只在启动沿清除；eStateOut 为当前相枚举。
  边界：① 双兜底——超程（fPosAct 越 fSoftMax / fSoftMin）与未触发超时（tonTimeout.Q）均迁 FAULT；
        ② FAULT 保持最后有效 fProbePos 并置 xFault，不按当下输入重新推断；
        ③ 两个 TON 实例一律在 CASE 之外无条件每周期调用（R7）；超时定时器用锁存位单稳态自复位（R188）；
        ④ 除零防护：无除法；浮点比较一律容差 DL_EPS；⑤ 零全局耦合、零物理地址、零库件依赖。
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ProbState（探针触测相，归属本文件，全库唯一定义）
 *----------------------------------------------------------------------------*)
TYPE E_DL_ProbState :
(
    eIdle       := 0,   // 空闲待启动 [—] / Idle, waiting for the start edge
    eFastApproach := 1, // 快进相（正向快速接近） [—] / Fast approach phase, positive direction
    eSlowApproach := 2, // 慢进相（正向精细接近） [—] / Slow approach phase, positive direction
    eRecord     := 3,   // 触发记录相（单拍锁存探针位置） [—] / Record phase, latches the probe position
    eRetract    := 4,   // 回退相（反向离开工件） [—] / Retract phase, negative direction
    eDwell      := 5,   // 驻留相（零速等待稳定） [—] / Dwell phase at zero velocity
    eFault      := 6    // 故障相（超程 / 超时 / 参数非法，锁存） [—] / Fault phase, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisProbeTouchOffSeq
VAR_INPUT
    xEnable      : BOOL  := TRUE;   // 使能，FALSE 时任意相立即回空闲 [—] / Enable, false resets to idle from any phase
    xStart       : BOOL  := FALSE;  // 启动（上升沿开始一次触测） [—] / Start, a rising edge begins one probing cycle
    fPosAct      : LREAL := 0.0;    // 轴实际位置（由调用方传入） [mm] / The actual axis position fed by the caller
    xProbeTrig   : BOOL  := FALSE;  // 探针触发原始信号 [—] / The raw probe trigger signal
    fFastVel     : LREAL := 20.0;   // 快进速度（正值，正向） [mm/s] / Fast approach velocity, positive
    fSlowVel     : LREAL := 2.0;    // 慢进速度（正值，正向） [mm/s] / Slow approach velocity, positive
    fFastSpan    : LREAL := 50.0;   // 快进段行程（自启动位置起算） [mm] / The fast approach span from the start position
    fSoftMax     : LREAL := 200.0;  // 软限位上界 [mm] / The soft limit upper bound
    fSoftMin     : LREAL := -10.0;  // 软限位下界 [mm] / The soft limit lower bound
    fRetractDist : LREAL := 5.0;    // 回退距离（自记录位置起算） [mm] / The retract distance from the recorded position
    tTimeout     : TIME  := T#5S;   // 未触发超时门限 [s] / The not triggered timeout threshold
    tDwell       : TIME  := T#200MS;// 回退后驻留时间 [s] / The dwell time after retracting
END_VAR
VAR_OUTPUT
    fVelCmd    : LREAL;                     // 速度指令（带方向） [mm/s] / The velocity command with direction
    fProbePos  : LREAL;                     // 记录的探针触发位置 [mm] / The recorded probe trigger position
    xBusy      : BOOL;                      // 触测进行中 [—] / Probing in progress
    xDone      : BOOL;                      // 序列完成（锁存，启动沿清除） [—] / Sequence done, latched and cleared by the start edge
    xFault     : BOOL;                      // 故障（锁存，启动沿清除） [—] / Fault, latched and cleared by the start edge
    eStateOut  : E_DL_ProbState;            // 当前相枚举 [—] / The current phase enumeration
END_VAR
VAR
    eState        : E_DL_ProbState;         // 内部相（与 eStateOut 同步发布） [—] / Internal phase mirrored to eStateOut
    xStartPrev    : BOOL;                   // 启动信号上拍快照 [—] / Previous scan snapshot of xStart
    xProbePrev    : BOOL;                   // 探针信号上拍快照 [—] / Previous scan snapshot of xProbeTrig
    xStartEdge    : BOOL;                   // 本拍启动上升沿 [—] / The start rising edge this scan
    xProbeEdge    : BOOL;                   // 本拍探针上升沿 [—] / The probe rising edge this scan
    xTimeoutLatch : BOOL;                   // 超时锁存位（单稳态自复位用） [—] / The timeout latch used for the monostable reset
    xApproaching  : BOOL;                   // 处于接近两相（超时定时器使能条件） [—] / In an approach phase, the timer enable
    xParamBad     : BOOL;                   // 参数非法标志 [—] / Parameter invalid flag
    fPosRef       : LREAL;                  // 启动时的位置基准 [mm] / The position reference captured at the start edge
    fProbeLast    : LREAL;                  // 最后有效触发位置 [mm] / The last valid trigger position
    tonTimeout    : TON;                    // 未触发超时定时器（CASE 外无条件调用） [—] / The not triggered timeout timer
    tonDwell      : TON;                    // 回退后驻留定时器（CASE 外无条件调用） [—] / The dwell timer after retracting
END_VAR
VAR CONSTANT
    DL_EPS  : LREAL := 1.0E-9;              // 浮点比较容差 [—] / The floating point comparison tolerance
    DL_ZERO : LREAL := 0.0;                 // 浮点零常量 [—] / The floating point zero constant
END_VAR

// 段 1｜周期无条件刷新：沿提取、使能判定、出口指令预置
xStartEdge := xStart AND NOT xStartPrev;                  // 启动上升沿提取 / extract the start rising edge
xProbeEdge := xProbeTrig AND NOT xProbePrev;              // 探针上升沿提取 / extract the probe rising edge
xApproaching := (eState = E_DL_ProbState.eFastApproach) OR (eState = E_DL_ProbState.eSlowApproach); // 接近两相判定
xBusy := FALSE;                                           // 忙碌位预置假，接近 / 回退 / 驻留相置真 / preset busy false
fVelCmd := DL_ZERO;                                       // 速度指令预置零，各相按需置值 / preset the velocity command zero

// 段 2｜两个定时器无条件调用（R7：不在 IF / CASE 内调用）
tonTimeout(IN := xApproaching AND NOT xTimeoutLatch, PT := tTimeout); // 未触发超时：接近相且未锁存时计时
tonDwell(IN := (eState = E_DL_ProbState.eDwell) AND NOT tonDwell.Q, PT := tDwell); // 驻留：驻留相计时，Q 到后自复位
IF tonTimeout.Q THEN                                      // 超时到（首次到达即锁存） / the timeout elapsed
    xTimeoutLatch := TRUE;                                // 锁存超时位，复位定时器 IN / latch so the timer resets
END_IF

// 段 2.5｜使能总闸（R86 审校 BLOCK 修复）：撤使能须从任意运动相立即停机，不能只在空闲相判
IF (NOT xEnable) AND (eState <> E_DL_ProbState.eFault) THEN   // 撤使能且当前非故障相 / enable dropped while not faulted
    eState := E_DL_ProbState.eIdle;                           // 强制回空闲相 / force the state back to idle
    fVelCmd := DL_ZERO;                                       // 速度指令立即清零，禁止带着速度指令穿越 / zero the velocity command at once
    xBusy := FALSE;                                           // 清忙碌位 / clear the busy flag
END_IF

// 段 3｜主状态机（ENUM + CASE，ELSE 拦截非法相）
CASE eState OF

    E_DL_ProbState.eIdle:
        IF NOT xEnable THEN                               // 未使能时保持空闲并清锁存 / stay idle and clear the latches
            xDone := FALSE;                               // 清完成锁存 [—] / clear the done latch
            xFault := FALSE;                              // 清故障锁存 [—] / clear the fault latch
            xTimeoutLatch := FALSE;                       // 清超时锁存 [—] / clear the timeout latch
        END_IF
        IF xStartEdge AND xEnable THEN                    // 使能下的启动沿 / a start edge while enabled
            xDone := FALSE;                               // 启动沿清完成锁存 [—] / clear the done latch on the start edge
            xFault := FALSE;                              // 启动沿清故障锁存 [—] / clear the fault latch on the start edge
            xTimeoutLatch := FALSE;                       // 启动沿清超时锁存 [—] / clear the timeout latch on the start edge
            xParamBad := FALSE;                           // 参数闸标志复位 / reset the parameter gate flag
            IF fFastVel <= DL_ZERO THEN                   // 快进速度非正 / the fast velocity is non positive
                xParamBad := TRUE;                        // 判参数非法 / mark the parameters invalid
            END_IF
            IF fSlowVel <= DL_ZERO THEN                   // 慢进速度非正 / the slow velocity is non positive
                xParamBad := TRUE;                        // 判参数非法 / mark the parameters invalid
            END_IF
            IF fFastSpan < DL_ZERO THEN                   // 快进行程为负 / the fast span is negative
                xParamBad := TRUE;                        // 判参数非法 / mark the parameters invalid
            END_IF
            IF fRetractDist <= DL_ZERO THEN               // 回退距离非正 / the retract distance is non positive
                xParamBad := TRUE;                        // 判参数非法 / mark the parameters invalid
            END_IF
            IF fSoftMax <= fSoftMin THEN                  // 软限位上下界倒置 / the soft limits are inverted
                xParamBad := TRUE;                        // 判参数非法 / mark the parameters invalid
            END_IF
            IF (fPosAct > fSoftMax) OR (fPosAct < fSoftMin) THEN // 起始位置已在限位外 / already outside the soft limits
                xParamBad := TRUE;                        // 判参数非法 / mark the parameters invalid
            END_IF
            IF xParamBad THEN                             // 任一闸判失败 / any gate failed
                eState := E_DL_ProbState.eFault;          // 迁入故障相 / enter the fault phase
                xFault := TRUE;                           // 置故障锁存 [—] / raise the fault latch
            ELSE
                fPosRef := fPosAct;                       // 捕获启动位置基准 [mm] / capture the start position reference
                fProbeLast := fPosAct;                    // 触发位置初值取启动位置 [mm] / the initial trigger position
                fProbePos := fProbeLast;                  // 出口同步初值 [mm] / mirror the outlet value
                eState := E_DL_ProbState.eFastApproach;   // 迁入快进相 / enter the fast approach phase
            END_IF
        END_IF

    E_DL_ProbState.eFastApproach:
        fVelCmd := fFastVel;                              // 快进速度指令 [mm/s] / the fast approach velocity command
        xBusy := TRUE;                                    // 置忙碌位 [—] / raise the busy flag
        IF xProbeEdge THEN                                // 探针已触发 / the probe already triggered
            eState := E_DL_ProbState.eRecord;             // 直接进入记录相（本拍合法事件优先） / go straight to record
        ELSIF (fPosAct > fSoftMax) OR (fPosAct < fSoftMin) THEN // 软限位超程（兜底一） / the soft limit is exceeded
            eState := E_DL_ProbState.eFault;              // 迁入故障相 / enter the fault phase
            xFault := TRUE;                               // 置故障锁存 [—] / raise the fault latch
            fVelCmd := DL_ZERO;                           // 故障即切零速 [mm/s] / cut the velocity to zero
        ELSIF (fPosAct - fPosRef) >= fFastSpan THEN       // 快进行程走满 / the fast span is used up
            eState := E_DL_ProbState.eSlowApproach;       // 转入慢进相 / switch to the slow approach phase
        ELSIF xTimeoutLatch THEN                          // 未触发超时（兜底二） / the not triggered timeout fired
            eState := E_DL_ProbState.eFault;              // 迁入故障相 / enter the fault phase
            xFault := TRUE;                               // 置故障锁存 [—] / raise the fault latch
            fVelCmd := DL_ZERO;                           // 故障即切零速 [mm/s] / cut the velocity to zero
        END_IF

    E_DL_ProbState.eSlowApproach:
        fVelCmd := fSlowVel;                              // 慢进速度指令 [mm/s] / the slow approach velocity command
        xBusy := TRUE;                                    // 置忙碌位 [—] / raise the busy flag
        IF xProbeEdge THEN                                // 探针触发 / the probe triggered
            eState := E_DL_ProbState.eRecord;             // 进入记录相（本拍合法事件优先） / enter the record phase first
        ELSIF (fPosAct > fSoftMax) OR (fPosAct < fSoftMin) THEN // 软限位超程（兜底一） / the soft limit is exceeded
            eState := E_DL_ProbState.eFault;              // 迁入故障相 / enter the fault phase
            xFault := TRUE;                               // 置故障锁存 [—] / raise the fault latch
            fVelCmd := DL_ZERO;                           // 故障即切零速 [mm/s] / cut the velocity to zero
        ELSIF xTimeoutLatch THEN                          // 未触发超时（兜底二） / the not triggered timeout fired
            eState := E_DL_ProbState.eFault;              // 迁入故障相 / enter the fault phase
            xFault := TRUE;                               // 置故障锁存 [—] / raise the fault latch
            fVelCmd := DL_ZERO;                           // 故障即切零速 [mm/s] / cut the velocity to zero
        END_IF

    E_DL_ProbState.eRecord:
        fProbeLast := fPosAct;                            // 锁存本次触发位置 [mm] / latch the trigger position of this cycle
        fProbePos := fProbeLast;                          // 发布到出口 [mm] / publish it to the outlet
        xBusy := TRUE;                                    // 记录拍仍算忙碌 [—] / the record scan still counts as busy
        eState := E_DL_ProbState.eRetract;                // 下一拍进入回退相 / move to the retract phase next scan
        IF fProbeLast > fSoftMax THEN                     // 记录位置越上限的不可能态兜底 / a defensive check on the record
            eState := E_DL_ProbState.eFault;              // 迁入故障相 / enter the fault phase
            xFault := TRUE;                               // 置故障锁存 [—] / raise the fault latch
        END_IF

    E_DL_ProbState.eRetract:
        fVelCmd := -fSlowVel;                             // 反向回退速度指令 [mm/s] / the negative retract velocity command
        xBusy := TRUE;                                    // 置忙碌位 [—] / raise the busy flag
        IF (fProbeLast - fPosAct) >= fRetractDist THEN    // 回退距离走满 / the retract distance is covered
            eState := E_DL_ProbState.eDwell;              // 转入驻留相 / switch to the dwell phase
            fVelCmd := DL_ZERO;                           // 驻留相速度归零 [mm/s] / zero velocity in the dwell phase
        ELSIF fPosAct < fSoftMin THEN                     // 回退越下软限位 / the lower soft limit is exceeded while retracting
            eState := E_DL_ProbState.eFault;              // 迁入故障相 / enter the fault phase
            xFault := TRUE;                               // 置故障锁存 [—] / raise the fault latch
            fVelCmd := DL_ZERO;                           // 故障即切零速 [mm/s] / cut the velocity to zero
        END_IF

    E_DL_ProbState.eDwell:
        fVelCmd := DL_ZERO;                               // 驻留相零速保持 [mm/s] / hold zero velocity during the dwell
        xBusy := TRUE;                                    // 置忙碌位 [—] / raise the busy flag
        IF tonDwell.Q THEN                                // 驻留计时到 / the dwell elapsed
            eState := E_DL_ProbState.eIdle;               // 回空闲相 / back to idle
            xDone := TRUE;                                // 置完成锁存 [—] / raise the done latch
        END_IF

    E_DL_ProbState.eFault:
        fVelCmd := DL_ZERO;                               // 故障相速度指令归零 [mm/s] / the fault phase velocity is zero
        fProbePos := fProbeLast;                          // 故障相保持最后有效触发位置 [mm] / hold the last valid trigger position
        xFault := TRUE;                                   // 故障锁存回放 [—] / replay the latched fault flag
        IF (NOT xStart) AND NOT xEnable THEN              // 撤启动且撤使能 / start released and enable dropped
            eState := E_DL_ProbState.eIdle;               // 唯一解除路径：该条件沿回空闲 / the only clear edge back to idle
            xTimeoutLatch := FALSE;                       // 同时清超时锁存 [—] / clear the timeout latch as well
        END_IF

ELSE
    eState := E_DL_ProbState.eFault;                      // 非法枚举值一律拦入故障相 / trap any illegal phase value
    xFault := TRUE;                                       // 置故障锁存 [—] / raise the fault latch
    fVelCmd := DL_ZERO;                                   // 速度指令归零 [mm/s] / the velocity command is zero
    fProbePos := fProbeLast;                              // 保持最后有效触发位置 [mm] / hold the last valid trigger position
END_CASE

// 段 4｜相枚举出口发布 + 输入上拍快照（主体末尾，保证本拍沿检测用上拍值）
eStateOut := eState;                                      // 相枚举统一出口（单点发布） / the single point phase outlet
xStartPrev := xStart;                                     // 刷新启动上拍快照 / refresh the start snapshot
xProbePrev := xProbeTrig;                                 // 刷新探针上拍快照 / refresh the probe snapshot
END_FUNCTION_BLOCK
