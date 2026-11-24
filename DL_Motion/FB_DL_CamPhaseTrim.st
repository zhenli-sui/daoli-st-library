(*
    FB_DL_CamPhaseTrim —— 凸轮相位在线修调
    ------------------------------------------------------------------
    分类      : DL_Motion / Cam
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 只借「凸轮相位可在线修调属运动层能力」的公开语义与运动层组织事实；
                限速率渐进、标记沿一次性受理、相位归一的禁 MOD 写法、错误分级与
                码位 100% 自有；本件不自造轴状态、不内联凸轮算法（组合调用上层凸轮件）；
                clean-room 重写，未复制任何闭源厂商源码
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R19）
    ------------------------------------------------------------------
    功能说明  : 运行中在线修调凸轮相位，输出一个相位偏移量注入凸轮件的相位输入
                （组合而非内联：可依赖低层，但不复制低层）。现场语义是飞剪/横切/贴标的
                切点对位——用色标或标记传感器测到实际相位偏差后一点点修，修的过程必须
                限速率，突变等于给机械一个冲击。
                核心防御：① 相位限幅越域（> 180°）或速率越域即故障级 02E1 并冻结修调——
                   相位限幅 0 会让修调永久卡住、太大等于允许突变；
                ② 一次性标记补偿每标记沿只受理一次，且必须在 bMarkArmed（上一拍已复位）
                   时才受理——否则高频标记会在一拍内累加成大跳变（本件最高危点）；
                ③ 相位归一用条件加减，禁浮点 MOD；
                ④ 指令或补偿量非有限即故障级并保持末次偏移——归 0 会让切点瞬间错位切出废品；
                ⑤ bReset 立即清偏移（唯一允许跳变的路径，检修专用）。
                职责边界：凸轮曲线求值归电子凸轮件，本件只出相位偏移量。
    错误码    : 16#0004_01CF 目标偏移超限已钳位 / 单次标记补偿已生效——信息级，正常防御
                16#0004_01D0 预留禁用（信息级，不得挪用）
                16#0004_02E1 限幅、速率或采样周期参数非法——故障级，修调冻结且偏移保持
                16#0004_02E2 指令或补偿量非有限——故障级，偏移保持末次有效
                16#0004_02E3 状态机落 ELSE 兜底（非法状态）——故障级，回 eIdle 并保持偏移
    码位总账  : 16#0004_01CF 用 / 16#0004_01D0 预留 ｜ 16#0004_02E1 用 / 16#0004_02E2 用 / 16#0004_02E3 用
    状态机    : E_DL_TrimState（eIdle / eRamping / eHold / eFault）四态，CASE 含 ELSE 兜底，
                ELSE 回 eIdle 并置故障级 02E3；失能时目标归 0 并按限速率回零。
    采样约定  : fbTrigReset / fbTrigMark 在本体首部无条件刷新，绝不放入 IF 或 CASE；
                速率步长由 tSampleTime 引脚换算，首拍步长按引脚值直接给出（无历史依赖）。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R19）
*)

(*
    枚举 : E_DL_TrimState —— 相位修调状态（本文件为全库唯一属主）
*)
TYPE E_DL_TrimState :
(
    eIdle    := 0,                            // 空闲：偏移按限速率回零 / idle, the offset ramps back to zero
    eRamping := 1,                            // 趋近：向目标偏移逼近 / ramping towards the target offset
    eHold    := 2,                            // 保持：已到目标，仅受标记补偿影响 / holding at the target
    eFault   := 3                             // 故障：修调冻结，偏移保持 / fault, the trim is frozen and the offset held
);
END_TYPE

FUNCTION_BLOCK FB_DL_CamPhaseTrim
VAR_INPUT
    bEnable         : BOOL;                   // 使能，FALSE 偏移按限速率归 0 / enable, FALSE ramps the offset back to zero
    bReset          : BOOL;                   // 复位，上升沿立即清偏移（检修专用，会跳变）/ reset, rising edge clears the offset at once, maintenance only
    fPhaseOffsetCmd : REAL := 0.0;            // 目标相位偏移 [deg]，范围 -180.0~180.0 / target phase offset [deg], range -180.0~180.0
    fRateMax        : REAL := 30.0;           // 偏移变化率上限 [deg/s]，范围 0.1~3600.0 / maximum offset rate [deg/s], range 0.1~3600.0
    fPhaseLimit     : REAL := 90.0;           // 偏移绝对值上限 [deg]，范围 1.0~180.0 / absolute offset limit [deg], range 1.0~180.0
    bTrimOnMark     : BOOL := FALSE;          // TRUE = 叠加标记沿的一次性补偿 / TRUE adds the one-shot mark correction
    fMarkCorrection : REAL := 0.0;            // 单次标记补偿量 [deg]，范围 -10.0~10.0 / one-shot mark correction [deg], range -10.0~10.0
    bMarkPulse      : BOOL := FALSE;          // 标记传感器脉冲（上升沿有效）/ mark sensor pulse, rising edge valid
    tSampleTime     : TIME := T#10MS;         // 采样周期 [ms]，范围 1~1000 / sample time [ms], range 1~1000
END_VAR
VAR_OUTPUT
    fPhaseOffset    : REAL;                   // 实际输出相位偏移（注入凸轮件）[deg] / actual phase offset injected into the cam block [deg]
    bTrimming       : BOOL;                   // 正在趋近目标 / ramping towards the target
    bLimited        : BOOL;                   // 受速率或幅值限制 / limited by the rate or the magnitude
    uMarkCount      : UDINT;                  // 已受理的标记补偿次数，饱和 [次] / accepted mark corrections, saturating [times]
    eErr            : UDINT;                  // 错误码，0=正常 / error id, 0=ok
    bError          : BOOL;                   // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
END_VAR
VAR
    fbTrigReset     : R_TRIG;                 // 复位上升沿实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    fbTrigMark      : R_TRIG;                 // 标记上升沿实例，本体首部无条件刷新 / mark edge instance, refreshed unconditionally
    eState          : E_DL_TrimState := eIdle; // 状态机当前态 / current state machine state
    fOffset         : REAL;                   // 内部偏移量 [deg] / internal offset [deg]
    fTarget         : REAL;                   // 限幅后的目标偏移 [deg] / clamped target offset [deg]
    fStep           : REAL;                   // 本拍允许的最大变化量 [deg] / maximum allowed change in this cycle [deg]
    fDtSec          : REAL;                   // 采样周期秒值 [s] / sample time in seconds [s]
    fLimitEff       : REAL;                   // 钳位后的相位限幅 [deg] / clamped phase limit [deg]
    fCorrEff        : REAL;                   // 钳位后的单次补偿量 [deg] / clamped one-shot correction [deg]
    bMarkArmed      : BOOL := TRUE;           // 标记受理武装位（上一拍已复位才受理）/ mark acceptance arming bit, armed only after the pulse is released
    bNonFin         : BOOL;                   // 输入非有限判定标志 / non-finite input flag
    bInit           : BOOL := FALSE;          // 首扫标志，初值 FALSE，判据 NOT bInit / first-scan flag, initial FALSE, tested with NOT
    nDtMs           : DINT;                   // 采样周期毫秒整数 [ms] / sample time in integer milliseconds [ms]
END_VAR
VAR CONSTANT
    DL_CPT_LIMIT_MAX : REAL := 180.0;         // 相位限幅上限（半周）[deg] / phase limit upper bound, half a revolution [deg]
    DL_CPT_LIMIT_MIN : REAL := 1.0;           // 相位限幅下限 [deg] / phase limit lower bound [deg]
    DL_CPT_RATE_MAX  : REAL := 3600.0;        // 速率上限 [deg/s] / rate upper bound [deg/s]
    DL_CPT_RATE_MIN  : REAL := 0.1;           // 速率下限 [deg/s] / rate lower bound [deg/s]
    DL_CPT_MARK_MAX  : REAL := 10.0;          // 单次补偿量绝对值上限 [deg] / absolute one-shot correction bound [deg]
    DL_CPT_DT_MAX    : TIME := T#1S;          // 采样周期上限 [ms] / sample time upper bound [ms]
    DL_CPT_DT_MIN    : TIME := T#1MS;         // 采样周期下限 [ms] / sample time lower bound [ms]
    DL_FLOAT_EPS     : REAL := 1.0E-6;        // 浮点判等容差 [无量纲] / float equality tolerance [dimensionless]
    DL_CPT_FULL_TURN : REAL := 360.0;         // 一整周 [deg] / one full revolution [deg]
    DL_CPT_HALF_TURN : REAL := 180.0;         // 半周 [deg] / half a revolution [deg]
    DL_CPT_MS_PER_S  : REAL := 1000.0;        // 毫秒到秒换算因子 [ms/s] / milliseconds per second [ms/s]
    DL_CPT_INF_GUARD : REAL := 1.0E38;        // 非有限幅值判定阈值 [无量纲] / non-finite magnitude guard [dimensionless]
    DL_CPT_CNT_MAX   : UDINT := 16#FFFF_FFFE; // 标记次数饱和值 [次] / mark counter saturation value [times]
    DL_CPT_ZERO      : REAL := 0.0;           // 零值常量，避免裸字面量 [deg] / zero constant, avoids a bare literal [deg]
END_VAR

// 段 1｜边沿实例无条件周期刷新（红线：严禁放入条件分支）/ segment 1, unconditional edge refresh
fbTrigReset(CLK := bReset);
fbTrigMark(CLK := bMarkPulse);

// 段 2｜输出与错误状态预置 / segment 2, preset outputs and status
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bTrimming := FALSE;                           // 预置未趋近 / preset not ramping
bLimited := FALSE;                            // 预置未受限 / preset not limited

// 段 3｜首扫初始化（唯一合法范式：初值 FALSE，判据 NOT bInit）/ segment 3, first-scan initialisation
IF NOT bInit THEN
    fOffset := DL_CPT_ZERO;                   // 首扫偏移归 0，避免未定值上电冲击 / the offset starts at zero, no undefined jump at power up
    uMarkCount := 0;                          // 标记计数清零 / clear the mark counter
    bInit := TRUE;                            // 首扫只做一次 / first scan runs once only
END_IF

// 段 4｜参数闸（限幅、速率、采样周期，任一非法即冻结修调）/ segment 4, parameter gate freezes the trim
IF (fPhaseLimit < DL_CPT_LIMIT_MIN) OR (fPhaseLimit > DL_CPT_LIMIT_MAX)
   OR (fRateMax < DL_CPT_RATE_MIN) OR (fRateMax > DL_CPT_RATE_MAX)
   OR (tSampleTime < DL_CPT_DT_MIN) OR (tSampleTime > DL_CPT_DT_MAX) THEN
    eErr := 16#0004_02E1;                     // 参数非法故障码 / illegal parameter fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    eState := eFault;                         // 落故障态，修调冻结 / enter the fault state, the trim is frozen
    fPhaseOffset := fOffset;                  // 偏移保持，绝不归 0 / hold the offset, never reset it to zero
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF

// 段 5｜输入非有限闸：偏移保持末次有效（归 0 会瞬间错位切出废品）/ segment 5, non-finite gate holds the offset
bNonFin := (fPhaseOffsetCmd <> fPhaseOffsetCmd) OR (fMarkCorrection <> fMarkCorrection)
        OR (fPhaseOffsetCmd > DL_CPT_INF_GUARD) OR (fPhaseOffsetCmd < -DL_CPT_INF_GUARD); // 非有限判定 / non-finite detection
IF bNonFin THEN
    eErr := 16#0004_02E2;                     // 指令非有限故障码 / non-finite command fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    eState := eFault;                         // 落故障态 / enter the fault state
    fPhaseOffset := fOffset;                  // 保持末次有效偏移 / hold the last valid offset
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF

// 段 5｜域钳位（限幅、补偿量各自收敛，钳位本身不置码）/ segment 5, domain clamp
fLimitEff := MIN(MAX(fPhaseLimit, DL_CPT_LIMIT_MIN), DL_CPT_LIMIT_MAX);   // 相位限幅收敛 [deg] / converge the phase limit [deg]
fCorrEff := MIN(MAX(fMarkCorrection, -DL_CPT_MARK_MAX), DL_CPT_MARK_MAX); // 单次补偿收敛到 ±10 deg / converge the one-shot correction
nDtMs := TIME_TO_DINT(tSampleTime);           // 采样周期整数毫秒 [ms] / sample time in integer milliseconds [ms]
fDtSec := DINT_TO_REAL(nDtMs) / DL_CPT_MS_PER_S; // 换算为秒，除子为常量 [s] / convert to seconds, the divisor is a constant [s]
fStep := fRateMax * fDtSec;                   // 本拍允许的最大变化量 [deg] / maximum allowed change in this cycle [deg]

// 段 6｜目标偏移 = 指令限幅 / segment 6, target offset from the clamped command
fTarget := MIN(MAX(fPhaseOffsetCmd, -fLimitEff), fLimitEff); // 目标双侧钳位 [deg] / clamp the target on both sides [deg]
IF ABS(fPhaseOffsetCmd) > fLimitEff THEN
    eErr := 16#0004_01CF;                     // 信息级：目标偏移超限已钳位 / info level, the target was clamped
END_IF

// 段 7｜标记沿一次性补偿（最高危点：每沿只受理一次，且需武装位）/ segment 7, one-shot mark correction
IF NOT bMarkPulse THEN
    bMarkArmed := TRUE;                       // 脉冲释放即重新武装 / re-arm once the pulse is released
END_IF
IF fbTrigMark.Q AND bTrimOnMark AND bMarkArmed THEN
    bMarkArmed := FALSE;                      // 受理后立即解除武装，防同拍累加 / disarm immediately so no accumulation can happen in one cycle
    fTarget := MIN(MAX(fTarget + fCorrEff, -fLimitEff), fLimitEff); // 叠加补偿并限幅 [deg] / add the correction and clamp [deg]
    IF uMarkCount < DL_CPT_CNT_MAX THEN
        uMarkCount := uMarkCount + 1;         // 饱和计数 / saturating count
    END_IF
    eErr := 16#0004_01CF;                     // 信息级：单次标记补偿已生效 / info level, the one-shot correction was applied
END_IF

// 段 8｜复位沿：立即清偏移（唯一允许跳变的路径，检修专用）/ segment 8, reset clears the offset at once
IF fbTrigReset.Q THEN
    fOffset := DL_CPT_ZERO;                   // 检修专用清偏移 / maintenance only, clear the offset
    bLimited := FALSE;                        // 清限幅标志 / clear the limited flag
END_IF

// 段 9｜失能：目标归 0，按限速率回零 / segment 9, disabling ramps the target back to zero
IF NOT bEnable THEN
    fTarget := DL_CPT_ZERO;                   // 目标归 0 / the target returns to zero
END_IF

// 段 10｜状态机（含 ELSE 兜底）/ segment 10, state machine with ELSE fallback
CASE eState OF
    eIdle:
        IF ABS(fTarget - fOffset) > fStep THEN
            eState := eRamping;               // 偏离超过一步即进入趋近态 / a deviation beyond one step enters the ramping state
        ELSE
            eState := eHold;                  // 否则直接保持 / otherwise hold at once
        END_IF

    eRamping:
        IF ABS(fTarget - fOffset) <= fStep THEN
            eState := eHold;                  // 进入一步之内即趋近完成 / inside one step the ramp is finished
        END_IF

    eHold:
        IF ABS(fTarget - fOffset) > fStep THEN
            eState := eRamping;               // 新指令或标记补偿把偏差拉大即重新趋近 / a new command or correction restarts the ramp
        END_IF

    eFault:
        fPhaseOffset := fOffset;              // 故障态偏移保持 / hold the offset in the fault state

ELSE
    eErr := 16#0004_02E3;                     // 故障级：非法状态兜底 / fault level, illegal state fallback
    bError := TRUE;                           // 置故障标志 / raise the error flag
    eState := eIdle;                          // 回空闲态 / fall back to idle
    fPhaseOffset := fOffset;                  // 保持偏移，绝不清零 / hold the offset, never clear it
END_CASE

// 段 11｜限速率推进（每拍最多变化 fStep，禁浮点 MOD 的相位归一）/ segment 11, rate limited advance
IF eState <> eFault THEN
    IF fOffset > (fTarget + fStep) THEN
        fOffset := fOffset - fStep;           // 正向逼近 / approach from above
        bLimited := TRUE;                     // 标记速率受限 / flag the rate limit
        bTrimming := TRUE;                    // 正在趋近 / ramping
    ELSIF fOffset < (fTarget - fStep) THEN
        fOffset := fOffset + fStep;           // 负向逼近 / approach from below
        bLimited := TRUE;                     // 标记速率受限 / flag the rate limit
        bTrimming := TRUE;                    // 正在趋近 / ramping
    ELSE
        fOffset := fTarget;                   // 进入一步之内即直接到位 / snap into place once inside one step
        bTrimming := FALSE;                   // 到位即不再趋近 / no longer ramping
    END_IF

    // 段 12｜幅值限幅（双侧，超限置受限标志）/ segment 12, two-sided magnitude clamp
    IF fOffset > fLimitEff THEN
        fOffset := fLimitEff;                 // 正向限幅 / clamp the positive side
        bLimited := TRUE;                     // 标记幅值受限 / flag the magnitude limit
    ELSIF fOffset < -fLimitEff THEN
        fOffset := -fLimitEff;                // 负向限幅 / clamp the negative side
        bLimited := TRUE;                     // 标记幅值受限 / flag the magnitude limit
    END_IF

    // 段 13｜相位归一（条件加减，禁浮点 MOD）/ segment 13, phase normalisation without a floating point MOD
    IF fOffset > DL_CPT_HALF_TURN THEN
        fOffset := fOffset - DL_CPT_FULL_TURN; // 超半周折回一周 / fold back one revolution
    ELSIF fOffset < -DL_CPT_HALF_TURN THEN
        fOffset := fOffset + DL_CPT_FULL_TURN; // 低于负半周折回一周 / fold forward one revolution
    END_IF
END_IF

// 段 14｜发布结果 / segment 14, publish the result
fPhaseOffset := fOffset;                      // 输出实际偏移（回零过程亦发布真实值）[deg] / publish the actual offset, including the ramp back to zero [deg]
END_FUNCTION_BLOCK
