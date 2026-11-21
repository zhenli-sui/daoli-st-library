(*
    FB_DL_FilmWebCenter —— 膜卷纠偏（EPC）
    ------------------------------------------------------------------
    分类      : DL_Motion / Guide
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 纠偏为公开卷材处理工程结构（EPC / CPC：边缘或中心偏差 → 纠偏辊位置给定）；
                死区保持、断料保持、限速率、双侧行程钳位、错误分级与码位 100% 自有；
                与排线往复件、背隙修正件的职责严格分离（一个管横向对中、一个管往复排布、
                一个管传动链间隙）；clean-room 重写，未复制任何闭源厂商源码
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R19）
    ------------------------------------------------------------------
    功能说明  : 把边缘/中心偏差换算成纠偏辊位置给定。核心防御三条：
                ① 死区内保持——偏差在死区内给定不动，防辊子随噪声来回磨（不是把给定设成 0）；
                ② 限速率——纠偏动作过快会造成膜起皱甚至跑偏振荡；
                ③ 断料保持——膜断了还继续纠偏，辊子会一路顶到机械极限，复产后第一次穿膜
                   直接撞限位，故断料时给定保持末值、绝不追 0。
                其余防御：④ 行程域矛盾、增益或速率越域即故障级 02E4 并冻结在中心位
                   （增益过大是纠偏振荡的头号原因，硬限比「相信现场」更安全）；
                ⑤ 偏差非有限即故障级 02E5 并保持末次给定；
                ⑥ 给定双侧行程钳位，超限置 bLimited；⑦ 斜率限制首拍 fStep 由引脚换算，
                   不做除法；⑧ 状态机 CASE 含 ELSE 兜底，非法状态回 eIdle 并保持给定。
                职责边界：纠偏执行器的伺服闭环归驱动层，本件只出位置给定。
    错误码    : 16#0004_01D1 断料保持中 / 偏差在死区内给定保持——信息级，正常防御
                16#0004_01D2 预留禁用（信息级，不得挪用）
                16#0004_02E4 增益/速率/行程/采样参数非法——故障级，纠偏冻结在中心位
                16#0004_02E5 偏差输入非有限——故障级，给定保持末次有效
                16#0004_02E6 状态机落 ELSE 兜底（非法状态）——故障级，回 eIdle 并保持给定
    码位总账  : 16#0004_01D1 用 / 16#0004_01D2 预留 ｜ 16#0004_02E4 用 / 16#0004_02E5 用 / 16#0004_02E6 用
    状态机    : E_DL_WebState（eIdle / eManual / eAuto / eWebLost / eFault）五态，CASE 含 ELSE 兜底，
                ELSE 回 eIdle 并置故障级 02E6；失能不归零，只保持末值。
    采样约定  : fbTrigReset 在本体首部无条件刷新；速率步长由 tSampleTime 引脚换算；
                bInDeadband / bLimited / bWebLost 均为当拍组合量，不锁存。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R19）
*)

(*
    枚举 : E_DL_WebState —— 纠偏工作状态（本文件为全库唯一属主）
*)
TYPE E_DL_WebState :
(
    eIdle    := 0,                            // 空闲：未使能，给定保持 / idle, disabled, the setpoint is held
    eManual  := 1,                            // 手动：走手动偏置给定 / manual, the setpoint follows the manual offset
    eAuto    := 2,                            // 自动：按偏差纠偏 / automatic, correcting by the measured deviation
    eWebLost := 3,                            // 断料：给定保持末值 / web lost, the setpoint holds its last value
    eFault   := 4                             // 故障：冻结在中心位 / fault, frozen at the centre
);
END_TYPE

FUNCTION_BLOCK FB_DL_FilmWebCenter
VAR_INPUT
    bEnable         : BOOL;                   // 使能，FALSE 输出保持末值（不归零）/ enable, FALSE holds the last setpoint without zeroing it
    bReset          : BOOL;                   // 复位，上升沿回中位并清状态 / reset, rising edge returns to the centre and clears the state
    bAuto           : BOOL := FALSE;          // TRUE = 自动纠偏，FALSE = 手动（走 fManualOffset）/ TRUE automatic, FALSE manual via the manual offset
    fDeviation      : REAL := 0.0;            // 边缘/中心偏差（正 = 偏向驱动侧）[mm] / edge or centre deviation, positive towards the drive side [mm]
    fGain           : REAL := 1.0;            // 偏差到位置给定增益 [mm/mm]，范围 0.1~20.0 / deviation to position gain [mm/mm], range 0.1~20.0
    fManualOffset   : REAL := 0.0;            // 手动偏置 [mm]，范围 fTravelMin~fTravelMax / manual offset [mm], range fTravelMin~fTravelMax
    fDeadband       : REAL := 0.3;            // 死区半宽 [mm]，范围 0.0~10.0 / deadband half width [mm], range 0.0~10.0
    fRateMax        : REAL := 5.0;            // 给定最大变化率 [mm/s]，范围 0.01~100.0 / maximum setpoint rate [mm/s], range 0.01~100.0
    fTravelMin      : REAL := -50.0;          // 行程下限 [mm] / travel lower bound [mm]
    fTravelMax      : REAL := 50.0;           // 行程上限 [mm]，必须 > fTravelMin / travel upper bound [mm], must be > fTravelMin
    bWebPresent     : BOOL := TRUE;           // 膜在位信号，FALSE = 断料 / web present signal, FALSE means the web is lost
    tSampleTime     : TIME := T#20MS;         // 采样周期 [ms]，范围 1~1000 / sample time [ms], range 1~1000
END_VAR
VAR_OUTPUT
    fPositionSp     : REAL;                   // 纠偏辊位置给定 [mm] / guide roller position setpoint [mm]
    bInDeadband     : BOOL;                   // 偏差在死区内（给定保持）/ the deviation is inside the deadband, the setpoint holds
    bLimited        : BOOL;                   // 受行程或速率限制 / limited by the travel or the rate
    bWebLost        : BOOL;                   // 断料保持中 / holding because the web is lost
    eErr            : UDINT;                  // 错误码，0=正常 / error id, 0=ok
    bError          : BOOL;                   // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid          : BOOL;                   // 给定是否可用 / setpoint valid flag
END_VAR
VAR
    fbTrigReset     : R_TRIG;                 // 复位上升沿实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    eState          : E_DL_WebState := eIdle; // 状态机当前态 / current state machine state
    fLastSp         : REAL;                   // 上一拍给定（斜率基准）[mm] / previous setpoint used by the ramp [mm]
    fTarget         : REAL;                   // 钳位与限速率前的目标给定 [mm] / target setpoint before clamping and ramping [mm]
    fStep           : REAL;                   // 本拍允许的最大变化量 [mm] / maximum allowed change in this cycle [mm]
    fDtSec          : REAL;                   // 采样周期秒值 [s] / sample time in seconds [s]
    fGainEff        : REAL;                   // 钳位后的增益 [mm/mm] / clamped gain [mm/mm]
    fDeadEff        : REAL;                   // 钳位后的死区半宽 [mm] / clamped deadband half width [mm]
    fManualEff      : REAL;                   // 钳位后的手动偏置 [mm] / clamped manual offset [mm]
    nDtMs           : DINT;                   // 采样周期毫秒整数 [ms] / sample time in integer milliseconds [ms]
    bInit           : BOOL := FALSE;          // 首扫标志，初值 FALSE，判据 NOT bInit / first-scan flag, initial FALSE, tested with NOT
END_VAR
VAR CONSTANT
    DL_EPC_GAIN_MIN  : REAL := 0.1;           // 增益下限 [mm/mm] / gain lower bound [mm/mm]
    DL_EPC_GAIN_MAX  : REAL := 20.0;          // 增益上限 [mm/mm] / gain upper bound [mm/mm]
    DL_EPC_RATE_MIN  : REAL := 0.01;          // 速率下限 [mm/s] / rate lower bound [mm/s]
    DL_EPC_RATE_MAX  : REAL := 100.0;         // 速率上限 [mm/s] / rate upper bound [mm/s]
    DL_EPC_DB_MAX    : REAL := 10.0;          // 死区半宽上限 [mm] / deadband half width upper bound [mm]
    DL_EPC_DT_MAX    : TIME := T#1S;          // 采样周期上限 [ms] / sample time upper bound [ms]
    DL_EPC_DT_MIN    : TIME := T#1MS;         // 采样周期下限 [ms] / sample time lower bound [ms]
    DL_FLOAT_EPS     : REAL := 1.0E-6;        // 浮点判等容差 [无量纲] / float equality tolerance [dimensionless]
    DL_EPC_MS_PER_S  : REAL := 1000.0;        // 毫秒到秒换算因子 [ms/s] / milliseconds per second [ms/s]
    DL_EPC_INF_GUARD : REAL := 1.0E38;        // 非有限幅值判定阈值 [无量纲] / non-finite magnitude guard [dimensionless]
    DL_EPC_ZERO      : REAL := 0.0;           // 零值常量，避免裸字面量 [mm] / zero constant, avoids a bare literal [mm]
END_VAR

// 段 1｜边沿实例无条件周期刷新（红线：严禁放入条件分支）/ segment 1, unconditional edge refresh
fbTrigReset(CLK := bReset);

// 段 2｜输出与错误状态预置（fPositionSp 为保持量，故障与断料时均保持）/ segment 2, preset outputs, the setpoint is held
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bInDeadband := FALSE;                         // 预置非死区 / preset outside the deadband
bLimited := FALSE;                            // 预置未受限 / preset not limited
bWebLost := NOT bWebPresent;                  // 断料标志由在位信号导出 / the web lost flag derives from the present signal

// 段 3｜首扫初始化（唯一合法范式：初值 FALSE，判据 NOT bInit）/ segment 3, first-scan initialisation
IF NOT bInit THEN
    fLastSp := DL_EPC_ZERO;                   // 首扫给定基准取中心位 / the setpoint reference starts at the centre
    bInit := TRUE;                            // 首扫只做一次 / first scan runs once only
END_IF

// 段 4｜参数闸：行程域、增益、速率、采样周期（任一非法即冻结在中心位）/ segment 4, parameter gate
IF (fTravelMax <= fTravelMin)
   OR (fGain < DL_EPC_GAIN_MIN) OR (fGain > DL_EPC_GAIN_MAX)
   OR (fRateMax < DL_EPC_RATE_MIN) OR (fRateMax > DL_EPC_RATE_MAX)
   OR (tSampleTime < DL_EPC_DT_MIN) OR (tSampleTime > DL_EPC_DT_MAX) THEN
    eErr := 16#0004_02E4;                     // 参数非法故障码 / illegal parameter fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    eState := eFault;                         // 落故障态 / enter the fault state
    fPositionSp := DL_EPC_ZERO;               // 冻结在中心位（唯一安全的固定点）/ freeze at the centre, the only safe fixed point
    bValid := FALSE;                          // 给定不可用 / the setpoint is not usable
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF

// 段 5｜偏差非有限闸：给定保持末次有效（绝不追 0）/ segment 5, non-finite gate holds the setpoint
IF (fDeviation <> fDeviation) OR (fDeviation > DL_EPC_INF_GUARD) OR (fDeviation < -DL_EPC_INF_GUARD) THEN
    eErr := 16#0004_02E5;                     // 偏差非有限故障码 / non-finite deviation fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    eState := eFault;                         // 落故障态 / enter the fault state
    fPositionSp := fLastSp;                   // 保持末次给定 / hold the last setpoint
    bValid := FALSE;                          // 给定不可用 / the setpoint is not usable
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF

// 段 6｜域钳位与速率步长（无历史依赖，不做除法）/ segment 6, domain clamp and rate step
fGainEff := fGain;                            // 增益已由段 4 保证在域内 / the gain is already in range by segment 4
fDeadEff := MIN(MAX(fDeadband, DL_EPC_ZERO), DL_EPC_DB_MAX); // 死区半宽收敛到 0.0~10.0 mm / converge the deadband into 0.0~10.0 mm
fManualEff := MIN(MAX(fManualOffset, fTravelMin), fTravelMax); // 手动偏置收敛到行程域 / converge the manual offset into the travel range
nDtMs := TIME_TO_DINT(tSampleTime);           // 采样周期整数毫秒 [ms] / sample time in integer milliseconds [ms]
fDtSec := DINT_TO_REAL(nDtMs) / DL_EPC_MS_PER_S; // 换算为秒，除子为常量 [s] / convert to seconds, the divisor is a constant [s]
fStep := fRateMax * fDtSec;                   // 本拍允许的最大变化量 [mm] / maximum allowed change in this cycle [mm]

// 段 7｜复位沿：回中位并清状态 / segment 7, reset returns to the centre
IF fbTrigReset.Q THEN
    fLastSp := DL_EPC_ZERO;                   // 给定基准回中心位 / the setpoint reference returns to the centre
    fPositionSp := DL_EPC_ZERO;               // 给定回中位 / the setpoint returns to the centre
    IF eState = eFault THEN
        eState := eIdle;                      // 故障态允许由复位退出 / a reset leaves the fault state
    END_IF
END_IF

// 段 8｜状态选择（断料优先级最高，其次使能与手自动）/ segment 8, state selection
IF NOT bWebPresent THEN
    eState := eWebLost;                       // 断料优先，给定保持 / web loss has the highest priority, the setpoint holds
    bWebLost := TRUE;                         // 发布断料标志 / publish the web lost flag
ELSE
    bWebLost := FALSE;                        // 在位则清断料标志 / clear the flag when the web is present
    IF eState = eWebLost THEN
        eState := eIdle;                      // 断料解除回空闲，由使能重新决定手自动 / leaving the web lost state returns to idle
    END_IF
END_IF
IF (eState <> eWebLost) AND (eState <> eFault) THEN
    IF NOT bEnable THEN
        eState := eIdle;                      // 失能回空闲（保持不归零）/ disabled returns to idle without zeroing the setpoint
    ELSIF bAuto THEN
        eState := eAuto;                      // 自动纠偏 / automatic correction
    ELSE
        eState := eManual;                    // 手动偏置 / manual offset
    END_IF
END_IF

// 段 9｜目标给定（含死区保持与断料保持）/ segment 9, target setpoint with deadband and web loss holding
CASE eState OF
    eIdle:
        fTarget := fLastSp;                   // 空闲保持末值，不归零 / idle holds the last value without zeroing it

    eManual:
        fTarget := fManualEff;                // 手动走偏置给定 / manual follows the offset

    eAuto:
        IF ABS(fDeviation) <= fDeadEff THEN
            fTarget := fLastSp;               // 死区内保持，绝不设成 0 / hold inside the deadband, never set it to zero
            bInDeadband := TRUE;              // 发布死区标志 / publish the deadband flag
            eErr := 16#0004_01D1;             // 信息级：偏差在死区内给定保持 / info level, the setpoint holds inside the deadband
        ELSE
            fTarget := fLastSp + fGainEff * fDeviation; // 增量式纠偏：在上一拍给定上叠加 / incremental correction on top of the previous setpoint
        END_IF

    eWebLost:
        fTarget := fLastSp;                   // 断料保持末值 / web lost holds the last value
        eErr := 16#0004_01D1;                 // 信息级：断料保持中 / info level, holding because the web is lost

    eFault:
        fTarget := fLastSp;                   // 故障态保持末值 / the fault state holds the last value

ELSE
    eErr := 16#0004_02E6;                     // 故障级：非法状态兜底 / fault level, illegal state fallback
    bError := TRUE;                           // 置故障标志 / raise the error flag
    eState := eIdle;                          // 回空闲态 / fall back to idle
    fTarget := fLastSp;                       // 保持末值，不产生跳变 / hold the last value, no jump
END_CASE

// 段 10｜行程双侧钳位（只做单侧是常见缺陷）/ segment 10, two-sided travel clamp
IF fTarget > fTravelMax THEN
    fTarget := fTravelMax;                    // 上限钳位 / clamp at the upper bound
    bLimited := TRUE;                         // 标记行程受限 / flag the travel limit
ELSIF fTarget < fTravelMin THEN
    fTarget := fTravelMin;                    // 下限钳位 / clamp at the lower bound
    bLimited := TRUE;                         // 标记行程受限 / flag the travel limit
END_IF

// 段 11｜限速率（每拍最多变化 fStep，防膜起皱与跑偏振荡）/ segment 11, rate limiting
IF fStep > DL_EPC_ZERO THEN
    IF fTarget > (fLastSp + fStep) THEN
        fTarget := fLastSp + fStep;           // 正向每拍限幅 / limit the positive step per cycle
        bLimited := TRUE;                     // 标记速率受限 / flag the rate limit
    ELSIF fTarget < (fLastSp - fStep) THEN
        fTarget := fLastSp - fStep;           // 负向每拍限幅 / limit the negative step per cycle
        bLimited := TRUE;                     // 标记速率受限 / flag the rate limit
    END_IF
END_IF

// 段 12｜发布给定 / segment 12, publish the setpoint
fPositionSp := fTarget;                       // 输出纠偏辊位置给定 [mm] / publish the guide roller setpoint [mm]
fLastSp := fTarget;                           // 记录为下一拍斜率基准 / remember it as the next ramp reference
IF NOT bError THEN
    bValid := TRUE;                           // 无故障则给定可用 / usable when no fault is present
END_IF
END_FUNCTION_BLOCK
