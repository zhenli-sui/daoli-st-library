(*
  FB_DL_TrapezoidProfilePlanner —— 梯形/三角速度规划：起止速度不等，距离不足自动降级三角曲线，逐周期输出设定值与完成/超差标志
  分类：DL_Motion | 复杂度：4 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT

  职责：按「目标位移 + 最大速度 + 最大加速度 + 起止速度 + 周期」做解析式梯形速度规划；
        当 fDa + fDd 超过目标位移时自动降级为三角曲线（峰值速度解含开方，负根 / 低于起止速度判规划失败）。
  输入契约：fDist 目标位移 [mm]（可为负，负号即反向）；fVelMax > 0；fAccMax > 0；
            fVelStart / fVelEnd 与 fDist 同号（按幅值参与规划）；fDt > 0 扫描周期 [s]。
  输出契约：fPosCmd / fVelCmd 为「相对起点的位移指令 / 速度指令」，符号随 fDist；
            xBusy 运动三相为 TRUE；xDone 到达终点的保持位；xOverrun 规划不可行或参数非法（锁存至下次启动沿）。
  边界：① 除零防护：fDt / fAccMax / fVelMax / fVp 全部前置判零；② 浮点比较一律用 DL_EPS 容差；
        ③ 起点段 eIdle 一次性解算全段时长，运动三相只做解析求值，无累积积分漂移；
        ④ 末拍精确落点（fPosCmd := fDist、fVelCmd := fVelEnd），消除解析式尾差；
        ⑤ 零全局耦合、零物理地址、零库件依赖（仅 SQRT / ABS 标准函数）。
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_TrapSeg（梯形规划段 / 状态，归属本文件，全库唯一定义）
 *----------------------------------------------------------------------------*)
TYPE E_DL_TrapSeg :
(
    eIdle   := 0,   // 空闲待启动 [—] / Idle, waiting for the start edge
    eAccel  := 1,   // 加速段（含三角曲线前半） [—] / Acceleration phase
    eCruise := 2,   // 匀速段（三角曲线时长为 0） [—] / Constant velocity phase
    eDecel  := 3,   // 减速段（含三角曲线后半） [—] / Deceleration phase
    eDone   := 4,   // 已到达终点（保持末值） [—] / Finished, outputs held
    eFault  := 5    // 规划失败 / 参数非法（锁存） [—] / Planning failed or invalid parameters
);
END_TYPE

FUNCTION_BLOCK FB_DL_TrapezoidProfilePlanner
VAR_INPUT
    xEnable   : BOOL  := TRUE;    // 使能，FALSE 时运动三相立即停机回空闲 [—] / Enable, false aborts motion to idle
    xStart    : BOOL  := FALSE;   // 启动（上升沿触发一次规划） [—] / Start, a rising edge triggers one plan
    fDist     : LREAL := 100.0;   // 目标位移，负值即反向 [mm] / Target displacement, negative means reverse
    fVelMax   : LREAL := 50.0;    // 最大允许速度（幅值） [mm/s] / Maximum allowed velocity magnitude
    fAccMax   : LREAL := 100.0;   // 最大允许加速度（幅值） [mm/s2] / Maximum allowed acceleration magnitude
    fVelStart : LREAL := 0.0;     // 起始速度（与 fDist 同号） [mm/s] / Start velocity, same sign as fDist
    fVelEnd   : LREAL := 0.0;     // 终止速度（与 fDist 同号） [mm/s] / End velocity, same sign as fDist
    fDt       : LREAL := 0.01;    // 扫描周期，必须 > 0 [s] / Scan period, must be positive
END_VAR
VAR_OUTPUT
    fPosCmd   : LREAL;                          // 位移指令（相对起点，带符号） [mm] / Position command relative to start
    fVelCmd   : LREAL;                          // 速度指令（带符号） [mm/s] / Velocity command with sign
    xBusy     : BOOL;                           // 运动进行中 [—] / Motion in progress
    xDone     : BOOL;                           // 已到达终点（保持位） [—] / Target reached, held
    xOverrun  : BOOL;                           // 规划不可行 / 参数非法（锁存） [—] / Planning overrun or invalid parameters
    xValid    : BOOL;                           // 本次规划有效 [—] / The current plan is valid
    eSeg      : E_DL_TrapSeg;                   // 当前段枚举 [—] / The active profile segment
END_VAR
VAR
    eState      : E_DL_TrapSeg;                 // 内部状态（与 eSeg 同步发布） [—] / Internal state mirrored to eSeg
    xStartPrev  : BOOL;                         // 启动信号上拍快照 [—] / Previous scan snapshot of xStart
    xEdgeStart  : BOOL;                         // 本拍启动上升沿 [—] / The start rising edge this scan
    xParamBad   : BOOL;                         // 参数 / 规划非法标志 [—] / Parameter or planning invalid flag
    xTriangle   : BOOL;                         // 三角曲线降级标志 [—] / Triangular profile degraded flag
    fSgn        : LREAL;                        // 位移方向符号（+1 / -1） [—] / Displacement direction sign
    fDistAbs    : LREAL;                        // 目标位移幅值 [mm] / Absolute target displacement
    fVStartAbs  : LREAL;                        // 起始速度幅值 [mm/s] / Absolute start velocity
    fVEndAbs    : LREAL;                        // 终止速度幅值 [mm/s] / Absolute end velocity
    fVp         : LREAL;                        // 实际峰值速度 [mm/s] / The effective peak velocity
    fVp2        : LREAL;                        // 峰值速度平方（开方前中间量） [mm2/s2] / Peak velocity squared
    fTa         : LREAL;                        // 加速段时长 [s] / Acceleration phase duration
    fTc         : LREAL;                        // 匀速段时长（三角曲线为 0） [s] / Cruise phase duration
    fTd         : LREAL;                        // 减速段时长 [s] / Deceleration phase duration
    fTtot       : LREAL;                        // 全段总时长 [s] / Total profile duration
    fDa         : LREAL;                        // 加速段位移 [mm] / Acceleration phase distance
    fDc         : LREAL;                        // 匀速段位移 [mm] / Cruise phase distance
    fDd         : LREAL;                        // 减速段位移 [mm] / Deceleration phase distance
    fTElapsed   : LREAL;                        // 已用时间 [s] / Elapsed time since the start edge
    fTd2        : LREAL;                        // 减速段内相对时间 [s] / Relative time inside the deceleration phase
    fS          : LREAL;                        // 位移幅值中间量 [mm] / Displacement magnitude intermediate
    fV          : LREAL;                        // 速度幅值中间量 [mm/s] / Velocity magnitude intermediate
END_VAR
VAR CONSTANT
    DL_EPS : LREAL := 1.0E-9;                   // 浮点比较容差 [—] / The floating point comparison tolerance
    DL_ZERO : LREAL := 0.0;                     // 浮点零常量 [—] / The floating point zero constant
    DL_TWO : LREAL := 2.0;                      // 浮点二常量 [—] / The floating point two constant
    DL_BIG : LREAL := 1.0E30;                   // 非有限值判据上界 [—] / The upper bound used to detect an infinite input
END_VAR

// 段 1｜周期无条件刷新：输出预置 + 启动沿提取（R7 无实例定时器，手工沿快照）
xEdgeStart := xStart AND NOT xStartPrev;        // 上升沿提取（上拍快照比对） / extract the rising edge
xDone := FALSE;                                 // 完成位预置假，CASE 内命中终点才置真 / preset done false
xBusy := FALSE;                                 // 忙碌位预置假，CASE 内运动三相置真 / preset busy false
xOverrun := FALSE;                              // 超差位预置假，CASE 内故障相置真 / preset overrun false
xValid := FALSE;                                // 规划有效位预置假，规划通过才置真 / preset valid false

// 段 2｜主状态机（ENUM + CASE，ELSE 拦截非法状态）
CASE eState OF

    E_DL_TrapSeg.eIdle:
        fPosCmd := DL_ZERO;                     // 空闲相位移指令归零 [mm] / idle position command zero
        fVelCmd := DL_ZERO;                     // 空闲相速度指令归零 [mm/s] / idle velocity command zero
        eSeg := E_DL_TrapSeg.eIdle;             // 段枚举发布空闲 / publish the idle segment
        IF xEdgeStart THEN                      // 收到启动沿 / a start edge arrived
            xParamBad := FALSE;                 // 参数闸标志复位 / reset the parameter gate flag
            fSgn := 1.0;                        // 方向符号预置正 / preset the sign positive
            IF fDist < DL_ZERO THEN             // 目标位移为负 / the target displacement is negative
                fSgn := -1.0;                   // 方向符号取负 / take the negative sign
            END_IF
            fDistAbs := ABS(fDist);             // 位移幅值 [mm] / the displacement magnitude
            fVStartAbs := ABS(fVelStart);       // 起始速度幅值 [mm/s] / the start velocity magnitude
            fVEndAbs := ABS(fVelEnd);           // 终止速度幅值 [mm/s] / the end velocity magnitude
            IF NOT xEnable THEN                 // 未使能启动 / started while disabled
                xParamBad := TRUE;              // 判参数非法 / mark the parameters invalid
            END_IF
            IF (fDist <> fDist) OR (fVelMax <> fVelMax) OR (fAccMax <> fAccMax)
               OR (fVelStart <> fVelStart) OR (fVelEnd <> fVelEnd) OR (fDt <> fDt)
               OR (ABS(fDist) > DL_BIG) OR (ABS(fVelMax) > DL_BIG) OR (ABS(fAccMax) > DL_BIG) THEN
                xParamBad := TRUE;              // 非有限值闸：NaN 或 Inf 一律判参数非法 / non-finite gate, NaN or Inf marks the parameters invalid
            END_IF
            IF fDt <= DL_ZERO THEN              // 周期非正（除零防护一） / the period is non positive
                xParamBad := TRUE;              // 判参数非法 / mark the parameters invalid
            END_IF
            IF fVelMax <= DL_ZERO THEN          // 最大速度非正（除零防护二） / the max velocity is non positive
                xParamBad := TRUE;              // 判参数非法 / mark the parameters invalid
            END_IF
            IF fAccMax <= DL_ZERO THEN          // 最大加速度非正（除零防护三） / the max acceleration is non positive
                xParamBad := TRUE;              // 判参数非法 / mark the parameters invalid
            END_IF
            IF fDistAbs <= DL_EPS THEN          // 目标位移近似为零 / the target displacement is near zero
                xParamBad := TRUE;              // 判参数非法 / mark the parameters invalid
            END_IF
            IF fVStartAbs > fVelMax + DL_EPS THEN // 起始速度越最大速度 / the start velocity above the maximum
                xParamBad := TRUE;              // 判参数非法 / mark the parameters invalid
            END_IF
            IF fVEndAbs > fVelMax + DL_EPS THEN // 终止速度越最大速度 / the end velocity above the maximum
                xParamBad := TRUE;              // 判参数非法 / mark the parameters invalid
            END_IF
            IF (fVelStart * fVelEnd) < -DL_EPS THEN // 起止速度异号，需过零，本件不支持 / opposite signs unsupported
                xParamBad := TRUE;              // 判参数非法 / mark the parameters invalid
            END_IF
            IF NOT xParamBad THEN               // 参数全通过才做规划 / plan only when all parameters pass
                fDa := (fVelMax * fVelMax - fVStartAbs * fVStartAbs) / (DL_TWO * fAccMax); // 满速加速段位移 [mm]
                fDd := (fVelMax * fVelMax - fVEndAbs * fVEndAbs) / (DL_TWO * fAccMax);     // 满速减速段位移 [mm]
                IF (fDa + fDd) <= fDistAbs THEN // 位移足够走梯形 / enough distance for a trapezoid
                    xTriangle := FALSE;         // 梯形标志 / trapezoidal profile
                    fVp := fVelMax;             // 峰值速度取最大速度 [mm/s] / the peak equals the maximum
                    fDc := fDistAbs - fDa - fDd;// 匀速段位移 [mm] / the cruise distance
                ELSE                            // 位移不足，降级三角曲线 / degrade to a triangle
                    xTriangle := TRUE;          // 三角标志 / triangular profile
                    fVp2 := (DL_TWO * fAccMax * fDistAbs + fVStartAbs * fVStartAbs + fVEndAbs * fVEndAbs) / DL_TWO; // 峰值速度平方 [mm2/s2]
                    IF fVp2 <= DL_ZERO THEN // 负根或零根，距离不足以起停 / negative root, distance too short
                        xParamBad := TRUE;  // 判规划失败 / mark the planning failure
                    ELSE
                        fVp := SQRT(fVp2);  // 峰值速度取正根 [mm/s] / take the positive root
                        IF (fVp < fVStartAbs - DL_EPS) OR (fVp < fVEndAbs - DL_EPS) THEN // 峰值低于起止速度，距离连加速都装不下
                            xParamBad := TRUE;  // 判规划失败 / mark the planning failure
                        END_IF
                    END_IF
                    IF NOT xParamBad THEN       // 三角曲线重算各段位移 / recompute the triangle distances
                        fDa := (fVp * fVp - fVStartAbs * fVStartAbs) / (DL_TWO * fAccMax); // 加速段位移 [mm]
                        fDd := (fVp * fVp - fVEndAbs * fVEndAbs) / (DL_TWO * fAccMax);     // 减速段位移 [mm]
                        fDc := DL_ZERO;     // 三角曲线无匀速段 [mm] / no cruise distance in a triangle
                    END_IF
                END_IF
            END_IF
            IF NOT xParamBad THEN               // 位移段解算通过后解时长 / solve the phase durations
                fTa := (fVp - fVStartAbs) / fAccMax; // 加速段时长 [s] / the acceleration duration
                fTd := (fVp - fVEndAbs) / fAccMax;   // 减速段时长 [s] / the deceleration duration
                IF fVp > DL_EPS THEN            // 峰值速度非零（除零防护四） / the peak velocity is positive
                    fTc := fDc / fVp;           // 匀速段时长 [s] / the cruise duration
                ELSE
                    fTc := DL_ZERO;             // 零速退化，匀速段记零 [s] / degenerate, cruise duration zero
                END_IF
                fTtot := fTa + fTc + fTd;       // 全段总时长 [s] / the total duration
                IF fTtot <= DL_EPS THEN         // 总时长为零，规划不可行 / the total duration is zero
                    xParamBad := TRUE;          // 判规划失败 / mark the planning failure
                END_IF
            END_IF
            IF xParamBad THEN                   // 任一闸判失败 / any gate failed
                eState := E_DL_TrapSeg.eFault;  // 迁入故障相（锁存） / enter the fault state, latched
                eSeg := E_DL_TrapSeg.eFault;    // 段枚举发布故障 / publish the fault segment
                fPosCmd := DL_ZERO;             // 位移指令归零 [mm] / position command zero
                fVelCmd := DL_ZERO;             // 速度指令归零 [mm/s] / velocity command zero
                xOverrun := TRUE;               // 置超差位 [—] / raise the overrun flag
            ELSE                                // 规划通过 / the plan passes
                fTElapsed := DL_ZERO;           // 已用时间清零 [s] / clear the elapsed time
                xValid := TRUE;                 // 置规划有效 [—] / raise the valid flag
                xBusy := TRUE;                  // 置忙碌位 [—] / raise the busy flag
                fPosCmd := DL_ZERO;             // 起点位移指令为零 [mm] / the start position command
                fVelCmd := fVelStart;           // 起点速度指令为起始速度 [mm/s] / the start velocity command
                eSeg := E_DL_TrapSeg.eAccel;    // 段枚举发布加速段 / publish the acceleration segment
                eState := E_DL_TrapSeg.eAccel;  // 迁入加速段 / enter the acceleration phase
            END_IF
        END_IF

    E_DL_TrapSeg.eAccel, E_DL_TrapSeg.eCruise, E_DL_TrapSeg.eDecel:
        IF NOT xEnable THEN                     // 使能撤销，立即停机 / the enable dropped, stop at once
            eState := E_DL_TrapSeg.eIdle;       // 回空闲相 / back to idle
            eSeg := E_DL_TrapSeg.eIdle;         // 段枚举发布空闲 / publish the idle segment
            fVelCmd := DL_ZERO;                 // 速度指令归零 [mm/s] / velocity command zero
            fPosCmd := DL_ZERO;                 // 位移指令归零 [mm] / position command zero
        ELSE
            fTElapsed := fTElapsed + fDt;       // 累加已用时间 [s]（fDt > 0 已在规划闸证明）
            IF fTElapsed <= fTa THEN            // 落在加速段时间窗内 / inside the acceleration window
                fS := fVStartAbs * fTElapsed + 0.5 * fAccMax * fTElapsed * fTElapsed; // 位移幅值 [mm]
                fV := fVStartAbs + fAccMax * fTElapsed;                              // 速度幅值 [mm/s]
                eSeg := E_DL_TrapSeg.eAccel;    // 段枚举发布加速段 / publish the acceleration segment
            ELSIF fTElapsed <= (fTa + fTc) THEN // 落在匀速段时间窗内 / inside the cruise window
                fS := fDa + fVp * (fTElapsed - fTa); // 位移幅值 [mm] / the displacement magnitude
                fV := fVp;                      // 速度幅值取峰值 [mm/s] / the velocity magnitude equals the peak
                eSeg := E_DL_TrapSeg.eCruise;   // 段枚举发布匀速段 / publish the cruise segment
            ELSE                                // 落在减速段时间窗内 / inside the deceleration window
                fTd2 := fTElapsed - fTa - fTc;  // 减速段内相对时间 [s] / the relative time inside deceleration
                fS := fDa + fDc + fVp * fTd2 - 0.5 * fAccMax * fTd2 * fTd2; // 位移幅值 [mm]
                fV := fVp - fAccMax * fTd2;     // 速度幅值 [mm/s] / the velocity magnitude
                eSeg := E_DL_TrapSeg.eDecel;    // 段枚举发布减速段 / publish the deceleration segment
            END_IF
            IF fS > fDistAbs THEN               // 位移幅值上越界钳位 / clamp the displacement magnitude
                fS := fDistAbs;                 // 钳到目标位移 [mm] / clamp to the target
            END_IF
            IF fS < DL_ZERO THEN                // 位移幅值下越界钳位 / clamp the lower side
                fS := DL_ZERO;                  // 钳到零 [mm] / clamp to zero
            END_IF
            IF fV < DL_ZERO THEN                // 速度幅值下越界钳位 / clamp the velocity magnitude
                fV := DL_ZERO;                  // 钳到零 [mm/s] / clamp to zero
            END_IF
            fPosCmd := fSgn * fS;               // 带符号位移指令出口 [mm] / the signed position command
            fVelCmd := fSgn * fV;               // 带符号速度指令出口 [mm/s] / the signed velocity command
            xBusy := TRUE;                      // 运动三相置忙碌 [—] / raise busy during the motion phases
            xValid := TRUE;                     // 运动三相规划仍有效 [—] / the plan stays valid while moving
            IF fTElapsed >= (fTtot - DL_EPS) THEN // 到达总时长 / the total duration is reached
                fPosCmd := fDist;               // 末拍精确落点 [mm] / the exact final position
                fVelCmd := fVelEnd;             // 末拍精确末速 [mm/s] / the exact final velocity
                xDone := TRUE;                  // 置完成位 [—] / raise the done flag
                xBusy := FALSE;                 // 撤忙碌位 [—] / drop the busy flag
                eSeg := E_DL_TrapSeg.eDone;     // 段枚举发布完成 / publish the done segment
                eState := E_DL_TrapSeg.eDone;   // 迁入完成相（锁存末值） / enter the done state, outputs held
            END_IF
        END_IF

    E_DL_TrapSeg.eDone:
        fPosCmd := fDist;                       // 保持精确终点 [mm] / hold the exact final position
        fVelCmd := fVelEnd;                     // 保持精确末速 [mm/s] / hold the exact final velocity
        xDone := TRUE;                          // 保持完成位 [—] / hold the done flag
        xValid := TRUE;                         // 保持规划有效 [—] / hold the valid flag
        eSeg := E_DL_TrapSeg.eDone;             // 保持段枚举完成 / hold the done segment
        IF xEdgeStart THEN                      // 完成后再启动一次 / restarted from the done state
            eState := E_DL_TrapSeg.eIdle;       // 回空闲相，下一拍重新规划 / back to idle for a fresh plan
        END_IF

    E_DL_TrapSeg.eFault:
        fPosCmd := DL_ZERO;                     // 故障相位移指令归零 [mm] / fault state position zero
        fVelCmd := DL_ZERO;                     // 故障相速度指令归零 [mm/s] / fault state velocity zero
        xOverrun := TRUE;                       // 故障锁存回放超差位 [—] / replay the latched overrun flag
        eSeg := E_DL_TrapSeg.eFault;            // 段枚举发布故障 / publish the fault segment
        IF (NOT xStart) AND NOT xEnable THEN    // 撤启动信号且使能撤销 / start released and enable dropped
            eState := E_DL_TrapSeg.eIdle;       // 唯一解除路径：该条件沿回空闲 / the only clear edge back to idle
        END_IF

ELSE
    eState := E_DL_TrapSeg.eFault;              // 非法枚举值一律拦入故障相 / trap any illegal state value
    eSeg := E_DL_TrapSeg.eFault;                // 段枚举发布故障 / publish the fault segment
    fPosCmd := DL_ZERO;                         // 位移指令归零 [mm] / position command zero
    fVelCmd := DL_ZERO;                         // 速度指令归零 [mm/s] / velocity command zero
    xOverrun := TRUE;                           // 置超差位 [—] / raise the overrun flag
END_CASE

// 段 3｜启动信号上拍快照（位于主体末尾，保证本拍沿检测用的是上拍值）
xStartPrev := xStart;                           // 末尾刷新上拍快照 / refresh the previous snapshot at the end
END_FUNCTION_BLOCK
