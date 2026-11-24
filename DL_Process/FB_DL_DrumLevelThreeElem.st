(*
    FB_DL_DrumLevelThreeElem —— 汽包水位三冲量（单泵轻量版）
    ------------------------------------------------------------------
    分类      : DL_Process / Boiler
    前缀      : FB_DL_
    版本      : 1.0.1
    溯源      : 三冲量为公开锅炉控制工程结构（水位偏差 + 蒸汽流量前馈 − 给水流量反馈）；
                增量式给定、限值矛盾闸、越限锁存、错误分级与码位 100% 自有；
                PID 只作下游组合（本件不内联 PID）；clean-room 重写，
                未复制任何闭源厂商源码
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R19）
    ------------------------------------------------------------------
    功能说明  : 单冲量在负荷突变时水位会「假水位」反向摆动，三冲量能压住：水位负反馈（主，
                水位低于目标则增大给水）+ 蒸汽流量前馈（负荷扰动前馈）− 给水流量反馈（内
                回路快速抑制）。v1.0.0 水位项误用 + 号构成正反馈（水位越低越不补水），
                v1.0.1 修正为负反馈符号（R19 终审，安全级缺陷）。
                本件不出 PID 输出，只出「给水流量给定」，由上层 PID 闭合流量小回路。
                核心防御：① 水位限值矛盾（fLevelLow >= fLevelHigh）即故障级 0306——
                   联锁彻底失效比水位本身更危险，此时给定保持末值；
                ② 水位或流量非有限即故障级 0305 并保持末次给定——切 0 等于停给水泵，
                   汽包会在十几秒内烧干；
                ③ 给定用增量式（累加）而非绝对式：三冲量在工程上带积分性质，绝对式会让
                   水位缓慢收敛到偏置点（本件算法要点）；
                ④ 输出双侧钳位；⑤ 越限锁存：汽包低水位是安全事件，不随水位恢复自动解除，
                   必须 bReset；⑥ 状态机 CASE 含 ELSE 兜底，非法状态回 eIdle 并保持给定。
                职责边界：流量小回路闭合归 PID 件，级联归级联件，本件只出给定。
    错误码    : 16#0005_01D6 给定被上下限限制 / 水位接近报警门限——信息级，正常防御
                16#0005_01D7 预留禁用（信息级，不得挪用）
                16#0005_0305 水位或流量输入非有限——故障级，给定保持末次有效
                16#0005_0306 水位限值或输出限值区间矛盾（联锁失效）——故障级，给定保持末次有效
                16#0005_0307 状态机落 ELSE 兜底（非法状态）——故障级，回 eIdle 并保持给定
    码位总账  : 16#0005_01D6 用 / 16#0005_01D7 预留 ｜ 16#0005_0305 用 / 16#0005_0306 用 / 16#0005_0307 用
    状态机    : E_DL_DrumState（eIdle / eRunning / eLowTrip / eHighTrip / eFault）五态，CASE 含 ELSE 兜底，
                ELSE 回 eIdle 并置故障级 0307；越限态锁存，仅 bReset 可解除。
    采样约定  : fbTrigReset 在本体首部无条件刷新；本件无时间量，增量式给定按调用节拍累加，
                调用节拍变化会改变积分速度，故上层的节拍必须稳定（已在功能说明留档）。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R19）
                2026-11-16 v1.0.1 终审修正：水位项符号由 + 改为 −（负反馈），v1.0.0 的
                正反馈会使低水位时给定进一步减小，属安全级缺陷（R19 终审）
*)

(*
    枚举 : E_DL_DrumState —— 汽包水位控制站状态（本文件为全库唯一属主）
*)
TYPE E_DL_DrumState :
(
    eIdle     := 0,                           // 空闲：未使能，给定保持 / idle, disabled, the setpoint holds
    eRunning  := 1,                           // 运行：三冲量增量计算 / running, three element incremental computation
    eLowTrip  := 2,                           // 低水位锁存：安全事件，需复位 / low level trip, latched until reset
    eHighTrip := 3,                           // 高水位锁存：安全事件，需复位 / high level trip, latched until reset
    eFault    := 4                            // 故障：给定保持末值 / fault, the setpoint holds its last value
);
END_TYPE

FUNCTION_BLOCK FB_DL_DrumLevelThreeElem
VAR_INPUT
    bEnable         : BOOL;                   // 使能，FALSE 给定保持末值 / enable, FALSE holds the last setpoint
    bReset          : BOOL;                   // 复位，上升沿清限幅锁存与联锁 / reset, rising edge clears the limits and the interlock latch
    fLevel          : REAL := 0.0;            // 汽包水位（相对正常水位线）[mm]，范围 -300.0~300.0 / drum level relative to normal [mm], range -300.0~300.0
    fLevelSp        : REAL := 0.0;            // 水位目标 [mm]，范围 -100.0~100.0 / level setpoint [mm], range -100.0~100.0
    fSteamFlow      : REAL := 0.0;            // 蒸汽流量 [t/h]，范围 0.0~1.0E4 / steam flow [t/h], range 0.0~1.0E4
    fFeedFlow       : REAL := 0.0;            // 给水流量 [t/h]，范围 0.0~1.0E4 / feed water flow [t/h], range 0.0~1.0E4
    fLevelGain      : REAL := 0.05;           // 水位偏差增益 [t/h/mm]，范围 0.001~10.0 / level deviation gain [t/h/mm], range 0.001~10.0
    fSteamGain      : REAL := 1.0;            // 蒸汽前馈系数 [t/h per t/h]，范围 0.0~3.0 / steam feedforward factor [t/h per t/h], range 0.0~3.0
    fFeedGain       : REAL := 0.5;            // 给水反馈系数 [t/h per t/h]，范围 0.0~2.0 / feed water feedback factor [t/h per t/h], range 0.0~2.0
    fLevelLow       : REAL := -150.0;         // 低水位报警/联锁门限 [mm] / low level alarm and interlock threshold [mm]
    fLevelHigh      : REAL := 150.0;          // 高水位报警/联锁门限 [mm]，必须 > fLevelLow / high level threshold [mm], must be > fLevelLow
    fOutMin         : REAL := 0.0;            // 给定下限 [t/h] / setpoint lower bound [t/h]
    fOutMax         : REAL := 500.0;          // 给定上限 [t/h]，必须 > fOutMin / setpoint upper bound [t/h], must be > fOutMin
END_VAR
VAR_OUTPUT
    fFeedSp         : REAL;                   // 给水流量给定（送 PID 作设定值）[t/h] / feed water setpoint for the downstream PID [t/h]
    bLevelLow       : BOOL;                   // 低水位（fLevel <= fLevelLow）/ low level active
    bLevelHigh      : BOOL;                   // 高水位（fLevel >= fLevelHigh）/ high level active
    bInterlockTrip  : BOOL;                   // 联锁触发建议（越限锁存，需 bReset）/ interlock recommendation, latched until reset
    bLimited        : BOOL;                   // 给定被上下限限制 / the setpoint was limited
    eErr            : UDINT;                  // 错误码，0=正常 / error id, 0=ok
    bError          : BOOL;                   // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid          : BOOL;                   // 给定是否可用 / setpoint valid flag
END_VAR
VAR
    fbTrigReset     : R_TRIG;                 // 复位上升沿实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    eState          : E_DL_DrumState := eIdle; // 状态机当前态 / current state machine state
    fLastSp         : REAL;                   // 上一拍给定（增量式累加基准）[t/h] / previous setpoint used by the incremental form [t/h]
    fSp             : REAL;                   // 本拍计算出的给定中间量 [t/h] / computed setpoint intermediate [t/h]
    fLevelDev       : REAL;                   // 水位偏差（水位 − 目标）[mm] / level deviation, level minus setpoint [mm]
    fLevelGainEff   : REAL;                   // 钳位后的水位增益 [t/h/mm] / clamped level gain [t/h/mm]
    fSteamGainEff   : REAL;                   // 钳位后的蒸汽前馈系数 [t/h per t/h] / clamped steam feedforward factor [t/h per t/h]
    fFeedGainEff    : REAL;                   // 钳位后的给水反馈系数 [t/h per t/h] / clamped feed water feedback factor [t/h per t/h]
    bNonFin         : BOOL;                   // 输入非有限判定标志 / non-finite input flag
    bInit           : BOOL := FALSE;          // 首扫标志，初值 FALSE，判据 NOT bInit / first-scan flag, initial FALSE, tested with NOT
END_VAR
VAR CONSTANT
    DL_DL3_LEVEL_ABS_MAX : REAL := 1000.0;    // 水位量程绝对值上限 [mm] / absolute level range bound [mm]
    DL_DL3_GAIN_MAX      : REAL := 10.0;      // 水位增益上限 [t/h/mm] / level gain upper bound [t/h/mm]
    DL_DL3_STEAM_MAX     : REAL := 3.0;       // 蒸汽前馈系数上限 [t/h per t/h] / steam factor upper bound [t/h per t/h]
    DL_DL3_FEED_MAX      : REAL := 2.0;       // 给水反馈系数上限 [t/h per t/h] / feed water factor upper bound [t/h per t/h]
    DL_FLOAT_EPS         : REAL := 1.0E-6;    // 浮点判等容差 [无量纲] / float equality tolerance [dimensionless]
    DL_DL3_INF_GUARD     : REAL := 1.0E38;    // 非有限幅值判定阈值 [无量纲] / non-finite magnitude guard [dimensionless]
    DL_DL3_ZERO          : REAL := 0.0;       // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
END_VAR

// 段 1｜边沿实例无条件周期刷新（红线：严禁放入条件分支）/ segment 1, unconditional edge refresh
fbTrigReset(CLK := bReset);

// 段 2｜输出与错误状态预置（fFeedSp 为保持量）/ segment 2, preset outputs, the setpoint is held
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bLevelLow := FALSE;                           // 预置无低水位 / preset no low level
bLevelHigh := FALSE;                          // 预置无高水位 / preset no high level
bLimited := FALSE;                            // 预置未限幅 / preset not limited
bValid := FALSE;                              // 预置给定不可用 / preset invalid

// 段 3｜首扫初始化（唯一合法范式：初值 FALSE，判据 NOT bInit）/ segment 3, first-scan initialisation
IF NOT bInit THEN
    fLastSp := fOutMin;                       // 首扫累加基准取给定下限 / the accumulation reference starts at the lower bound
    fFeedSp := fOutMin;                       // 首扫给定即下限 / the first setpoint equals the lower bound
    bInterlockTrip := FALSE;                  // 首扫无联锁 / no interlock on the first scan
    bInit := TRUE;                            // 首扫只做一次 / first scan runs once only
END_IF

// 段 4｜水位限值一致性闸（联锁失效比水位本身危险）/ segment 4, level limit consistency gate
IF (fLevelLow >= fLevelHigh) OR (fOutMax <= fOutMin) THEN
    eErr := 16#0005_0306;                     // 限值区间矛盾故障码 / contradictory limit fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    eState := eFault;                         // 落故障态 / enter the fault state
    fFeedSp := fLastSp;                       // 给定保持末值 / hold the last setpoint
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF

// 段 5｜输入非有限闸：给定保持末次有效（切 0 等于停泵烧干汽包）/ segment 5, non-finite gate
bNonFin := (fLevel <> fLevel) OR (fSteamFlow <> fSteamFlow) OR (fFeedFlow <> fFeedFlow)
        OR (fLevelSp <> fLevelSp)
        OR (fLevel > DL_DL3_INF_GUARD) OR (fLevel < -DL_DL3_INF_GUARD)
        OR (fSteamFlow > DL_DL3_INF_GUARD) OR (fFeedFlow > DL_DL3_INF_GUARD); // 非有限判定 / non-finite detection
IF bNonFin THEN
    eErr := 16#0005_0305;                     // 输入非有限故障码 / non-finite input fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    eState := eFault;                         // 落故障态 / enter the fault state
    fFeedSp := fLastSp;                       // 保持末次有效给定 / hold the last valid setpoint
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF

// 段 6｜增益域钳位（负增益会让水位反向调节，绝不允许）/ segment 6, gain domain clamp
fLevelGainEff := MIN(MAX(fLevelGain, DL_DL3_ZERO), DL_DL3_GAIN_MAX);  // 水位增益收敛到 0.0~10.0 / converge the level gain
fSteamGainEff := MIN(MAX(fSteamGain, DL_DL3_ZERO), DL_DL3_STEAM_MAX); // 蒸汽前馈收敛到 0.0~3.0 / converge the steam factor
fFeedGainEff := MIN(MAX(fFeedGain, DL_DL3_ZERO), DL_DL3_FEED_MAX);    // 给水反馈收敛到 0.0~2.0 / converge the feed water factor

// 段 7｜复位沿：清限幅与联锁锁存（唯一的解锁路径）/ segment 7, reset clears the interlock latch
IF fbTrigReset.Q THEN
    bInterlockTrip := FALSE;                  // 清联锁锁存 / clear the interlock latch
    bLimited := FALSE;                        // 清限幅标志 / clear the limited flag
    IF (eState = eLowTrip) OR (eState = eHighTrip) THEN
        eState := eIdle;                      // 锁存态由复位退出 / the trip states are left by a reset
    END_IF
END_IF

// 段 8｜水位门限判定与锁存（低水位是安全事件，不自恢复）/ segment 8, level threshold and latching
bLevelLow := fLevel <= fLevelLow;             // 低水位判定 / low level test
bLevelHigh := fLevel >= fLevelHigh;           // 高水位判定 / high level test
IF bLevelLow THEN
    eState := eLowTrip;                       // 低水位锁存 / latch the low level trip
    bInterlockTrip := TRUE;                   // 置联锁建议 / raise the interlock recommendation
    eErr := 16#0005_01D6;                     // 信息级：水位接近报警门限 / info level, the level reached the alarm threshold
ELSIF bLevelHigh THEN
    eState := eHighTrip;                      // 高水位锁存 / latch the high level trip
    bInterlockTrip := TRUE;                   // 置联锁建议 / raise the interlock recommendation
    eErr := 16#0005_01D6;                     // 同一业务语义复用同一信息码 / the same semantics reuses the same info id
END_IF

// 段 9｜失能判定（锁存态优先保留）/ segment 9, disable handling with the trip latched
IF NOT bEnable THEN
    IF (eState <> eLowTrip) AND (eState <> eHighTrip) AND (eState <> eFault) THEN
        eState := eIdle;                      // 非锁存态失能回空闲 / a non latched state returns to idle
    END_IF
    fFeedSp := fLastSp;                       // 失能保持末值，不归零 / hold the last setpoint while disabled
    RETURN;                                   // 出口 / exit
END_IF

// 段 10｜状态机（含 ELSE 兜底）：只有运行态做三冲量增量计算 / segment 10, state machine with ELSE fallback
CASE eState OF
    eIdle:
        eState := eRunning;                   // 使能且无锁存即进入运行态 / enabling without a latch enters the running state
        fSp := fLastSp;                       // 本拍给定保持，下一拍开始增量 / hold this cycle, accumulation starts next cycle

    eRunning:
        fLevelDev := fLevel - fLevelSp;       // 水位偏差 [mm] / level deviation [mm]
        fSp := fLastSp
             - fLevelGainEff * fLevelDev
             + fSteamGainEff * fSteamFlow
             - fFeedGainEff * fFeedFlow;      // 增量式三冲量：水位负反馈（低于目标则加水）+ 蒸汽前馈 − 给水反馈 [t/h] / incremental three element form with negative level feedback [t/h]

    eLowTrip:
        fSp := fLastSp;                       // 低水位锁存期保持给定，不随水位恢复自解除 / hold while latched
        bInterlockTrip := TRUE;               // 锁存保持联锁建议 / keep the interlock recommendation

    eHighTrip:
        fSp := fLastSp;                       // 高水位锁存期保持给定 / hold while latched
        bInterlockTrip := TRUE;               // 锁存保持联锁建议 / keep the interlock recommendation

    eFault:
        fSp := fLastSp;                       // 故障态保持末值 / hold the last value in the fault state

ELSE
    eErr := 16#0005_0307;                     // 故障级：非法状态兜底 / fault level, illegal state fallback
    bError := TRUE;                           // 置故障标志 / raise the error flag
    eState := eIdle;                          // 回空闲态 / fall back to idle
    fSp := fLastSp;                           // 保持末值，不产生跳变 / hold the last value, no jump
END_CASE

// 段 11｜输出双侧钳位（只做单侧是常见缺陷）/ segment 11, two-sided output clamp
IF fSp > fOutMax THEN
    fSp := fOutMax;                           // 上限钳位 / clamp at the upper bound
    bLimited := TRUE;                         // 标记限幅 / flag the limit
    IF eErr = 0 THEN
        eErr := 16#0005_01D6;                 // 信息级：给定被上下限限制 / info level, the setpoint was limited
    END_IF
ELSIF fSp < fOutMin THEN
    fSp := fOutMin;                           // 下限钳位 / clamp at the lower bound
    bLimited := TRUE;                         // 标记限幅 / flag the limit
    IF eErr = 0 THEN
        eErr := 16#0005_01D6;                 // 同一业务语义复用同一信息码 / the same semantics reuses the same info id
    END_IF
END_IF

// 段 12｜防积分饱和：锁存与故障态下不推进累加基准 / segment 12, anti windup on the accumulation reference
IF (eState = eRunning) THEN
    fLastSp := fSp;                           // 仅运行态推进累加基准 / the reference advances only while running
END_IF
fFeedSp := fSp;                               // 输出给水给定 [t/h] / publish the feed water setpoint [t/h]
IF NOT bError THEN
    bValid := TRUE;                           // 无故障则给定可用 / usable when no fault is present
END_IF
END_FUNCTION_BLOCK
