(*
    FB_DL_AutoTuneRelay —— 继电反馈自整定
    ------------------------------------------------------------------
    分类      : DL_Algo / ControlLaw
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 公开学术判据 —— 继电反馈法（Astrom & Hagglund 1984）描述函数
                N(a) = 4d/(pi*a)，含迟滞时 -1/N(a) = -(pi/4d)*sqrt(a^2 - h^2)；
                整定规则取 Ziegler-Nichols 与 Astrom-Hagglund 公开文本；
                只借公开公式与规则常数（属公共知识），测量闸门、状态机、引脚契约与
                码位 100% 自有；clean-room 重写，未复制任何闭源厂商源码
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R19）
    ------------------------------------------------------------------
    功能说明  : 把 ±d 继电（可带迟滞 h）接入回路，等振幅稳定后测极限振荡周期 Tu 与幅值 a，
                按公开描述函数算临界增益 Ku，再按选定规则给出 Kp / Ti / Td。
                本件不闭环控制，只输出 bRelayOut（接上层手动通道）与整定结果。
                核心防御：① 继电幅值非正/非有限即故障级 2A10（d = 0 时 Ku = 0，结果无意义）；
                ② 迟滞不小于实测幅值时拒绝出结果（描述函数分母为零/虚数，Ku 不可定义）；
                ③ 每半周期采样数不足即故障级 2A11——采样太疏时测出的「振荡」是采样网格
                   产物，不是对象特性（R67 采样密度闸先行）；
                ④ 幅值稳定判据不通过只置信息码继续测，超时才是故障级 2A12；
                ⑤ bAbort 必须撤继电（本件最高危点：不撤则回路一直振荡），且人为中止不置故障。
                说明：继电幅值相对满量程 20% 的工程上限需满量程信息，本件无满量程引脚，
                该上限由调用方在上层保证（头注释留档，不做无法判定的检查）。
    错误码    : 16#0002_2A01 振荡未收敛，继续测量 / 参数超域已钳位——信息级，正常防御
                16#0002_2A02 预留禁用（信息级，不得挪用）
                16#0002_2A10 继电参数非法（d 非正或非有限、h >= a、采样周期越域）——故障级，中止实验并撤继电
                16#0002_2A11 半周期采样密度不足，振荡不可信——故障级，中止实验并撤继电
                16#0002_2A12 超时未收敛 / Ku 不可表示 / 整定规则落 ELSE 兜底——故障级，中止实验并撤继电
    码位总账  : 16#0002_2A01 用 / 16#0002_2A02 预留 ｜ 16#0002_2A10 用 / 16#0002_2A11 用 / 16#0002_2A12 用
    状态机    : E_DL_TuneState（eIdle / eRelay / eMeasure / eDone / eFault）五态，CASE 含 ELSE 兜底，
                ELSE 回 eIdle 并置故障级 2A12；bAbort 沿无条件回 eIdle 且撤继电。
    采样约定  : fbTrigStart / fbTrigAbort / fbTimeout 在本体首部无条件刷新，绝不放入 IF 或 CASE；
                时间基准由 tSampleTime 引脚累加，累加前用比较式预判溢出（不靠回绕兜底）；
                整定规则按公开文本：ZN-P 0.5Ku；ZN-PI 0.45Ku / Tu*1.2^-1；ZN-PID 0.6Ku / Tu/2 / Tu/8；
                AH 无超调 0.2Ku / Tu/2 / Tu/3。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R19）
*)

(*
    枚举 : E_DL_TuneRule —— 整定规则（本文件为全库唯一属主）
*)
TYPE E_DL_TuneRule :
(
    eZnP           := 0,                      // Ziegler-Nichols 纯比例规则 / Ziegler-Nichols proportional rule
    eZnPi          := 1,                      // Ziegler-Nichols 比例积分规则 / Ziegler-Nichols PI rule
    eZnPid         := 2,                      // Ziegler-Nichols 比例积分微分规则 / Ziegler-Nichols PID rule
    eAhNoOvershoot := 3                       // Astrom-Hagglund 无超调规则 / Astrom-Hagglund no overshoot rule
);
END_TYPE

(*
    枚举 : E_DL_TuneState —— 自整定实验状态（本文件为全库唯一属主）
*)
TYPE E_DL_TuneState :
(
    eIdle    := 0,                            // 空闲：继电输出撤销 / idle, relay output withdrawn
    eRelay   := 1,                            // 施加继电，等待首个翻转 / relay applied, waiting for the first flip
    eMeasure := 2,                            // 收集中：测幅值与半周期 / measuring amplitude and half periods
    eDone    := 3,                            // 完成：结果有效 / done, results valid
    eFault   := 4                             // 故障：实验中止 / fault, experiment aborted
);
END_TYPE

FUNCTION_BLOCK FB_DL_AutoTuneRelay
VAR_INPUT
    bEnable           : BOOL;                 // 使能，FALSE 中止实验并撤继电 / enable, FALSE aborts the experiment and withdraws the relay
    bStart            : BOOL;                 // 启动，上升沿启动实验（运行中忽略）/ start, rising edge begins the experiment, ignored while running
    bAbort            : BOOL;                 // 中止，上升沿中止并回 eIdle（不置故障）/ abort, rising edge aborts back to idle without raising a fault
    fPv               : REAL := 0.0;          // 过程测量（被控量）[用户单位] / process measurement [user unit]
    fSp               : REAL := 0.0;          // 目标值，实验围绕此点进行 [用户单位] / setpoint the experiment oscillates around [user unit]
    fRelayAmp         : REAL := 5.0;          // 继电幅值 d [用户单位]，必须 > 0 / relay amplitude d [user unit], must be > 0
    fRelayHyst        : REAL := 0.2;          // 继电迟滞 h [用户单位]，范围 0.0~fRelayAmp（含等号即非法）/ relay hysteresis h [user unit], 0.0~fRelayAmp, equality is illegal
    uCyclesRequired   : UINT := 4;            // 需要观察的完整振荡周期数 [周期]，范围 2~20 / number of full cycles to observe [cycle], range 2~20
    uMinSamplesPerHalf : UINT := 6;           // 每半周期最少采样数 [拍]，范围 4~100 / minimum samples per half period [scan], range 4~100
    tMaxDuration      : TIME := T#300S;       // 实验总超时 [ms]，范围 10 s~2 h / experiment timeout [ms], range 10 s~2 h
    fStabTolPercent   : REAL := 2.0;          // 幅值稳定判据：前后半窗均值差百分比上限 [%]，范围 0.1~20.0 / amplitude stability tolerance [%], range 0.1~20.0
    eRule             : E_DL_TuneRule := eZnPid; // 整定规则 / tuning rule
    tSampleTime       : TIME := T#100MS;      // 采样周期 [ms]，范围 1~10000 / sample time [ms], range 1~10000
END_VAR
VAR_OUTPUT
    bRelayOut         : BOOL;                 // 继电输出（TRUE = 加 +d），接上层手动通道 / relay output, TRUE adds plus d, wired to the manual channel
    bBusy             : BOOL;                 // 实验进行中 / experiment running
    bDone             : BOOL;                 // 完成（单周期脉冲，结果有效）/ done, single-cycle pulse with valid results
    fOscAmp           : REAL;                 // 测得振荡幅值 a [用户单位] / measured oscillation amplitude a [user unit]
    tUltPeriod        : TIME;                 // 测得极限周期 Tu [ms] / measured ultimate period Tu [ms]
    fUltGain          : REAL;                 // 临界增益 Ku [无量纲] / ultimate gain Ku [dimensionless]
    fKp               : REAL;                 // 整定比例增益 [无量纲] / tuned proportional gain [dimensionless]
    fTi               : REAL;                 // 整定积分时间 [s]，0 表示纯 P / tuned integral time [s], zero means pure P
    fTd               : REAL;                 // 整定微分时间 [s]，0 表示无微分 / tuned derivative time [s], zero means no derivative
    uCycleDone        : UINT;                 // 已完成的有效振荡周期数 [周期] / completed valid cycles [cycle]
    eErr              : UDINT;                // 错误码，0=正常 / error id, 0=ok
    bError            : BOOL;                 // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid            : BOOL;                 // 结果是否可用 / results valid flag
END_VAR
VAR
    eState            : E_DL_TuneState := eIdle; // 状态机当前态 / current state machine state
    fbTrigStart       : R_TRIG;               // 启动沿实例，本体首部无条件刷新 / start edge instance, refreshed unconditionally
    fbTrigAbort       : R_TRIG;               // 中止沿实例，本体首部无条件刷新 / abort edge instance, refreshed unconditionally
    fbTimeout         : TON;                  // 实验总超时实例，本体首部无条件刷新 / total timeout instance, refreshed unconditionally
    bRelayPrev        : BOOL;                 // 上一拍继电输出，翻转检测用 / previous relay output for flip detection
    fPeakHi           : REAL;                 // 本半周期上峰值 [用户单位] / upper peak of the current half period [user unit]
    fPeakLo           : REAL;                 // 本半周期下峰值 [用户单位] / lower peak of the current half period [user unit]
    tNow              : TIME;                 // 实验内累计时间 [ms] / accumulated experiment time [ms]
    tEdgeLast         : TIME;                 // 上一次翻转的时刻 [ms] / time of the previous flip [ms]
    tHalf             : TIME;                 // 最近一个半周期长度 [ms] / most recent half period length [ms]
    tHalfPrev         : TIME;                 // 上一个半周期长度 [ms] / previous half period length [ms]
    uHalfCount        : UINT;                 // 已采集的半周期数 [个] / collected half periods [count]
    fAmpSum1          : REAL;                 // 第一窗幅值累计 [用户单位] / first window amplitude sum [user unit]
    fAmpSum2          : REAL;                 // 第二窗幅值累计 [用户单位] / second window amplitude sum [user unit]
    uAmpCnt1          : UINT;                 // 第一窗样本数 [个] / first window sample count [count]
    uAmpCnt2          : UINT;                 // 第二窗样本数 [个] / second window sample count [count]
    fHalfAmp          : REAL;                 // 单个半周期的幅值 [用户单位] / amplitude of one half period [user unit]
    fMean1            : REAL;                 // 第一窗均值 [用户单位] / first window mean [user unit]
    fMean2            : REAL;                 // 第二窗均值 [用户单位] / second window mean [user unit]
    fRelAmp           : REAL;                 // 幅值相对偏差 [无量纲] / relative amplitude deviation [dimensionless]
    fStabTolEff       : REAL;                 // 钳位后的稳定容差 [%] / clamped stability tolerance [%]
    fCyclesEff        : REAL;                 // 钳位后的周期数（REAL 形态，除法用）/ clamped cycle count in REAL form, used for division
    fHystEff          : REAL;                 // 钳位后的继电迟滞 [用户单位] / clamped relay hysteresis [user unit]
    fKuL              : LREAL;                // 临界增益中间量（LREAL 承载）/ ultimate gain intermediate carried in LREAL
    fAmpL             : LREAL;                // 幅值中间量（LREAL 承载）/ amplitude intermediate carried in LREAL
    fHystL            : LREAL;                // 迟滞中间量（LREAL 承载）/ hysteresis intermediate carried in LREAL
    fDenL             : LREAL;                // 描述函数分母（LREAL 承载）/ describing function denominator in LREAL
    fTuSec            : REAL;                 // 极限周期的秒值 [s] / ultimate period in seconds [s]
    nSampHalf         : DINT;                 // 单半周期采样数 [拍] / samples in one half period [scan]
    nDtMs             : DINT;                 // 采样周期毫秒整数 [ms] / sample time in integer milliseconds [ms]
    uNeedHalf         : UINT;                 // 需要采集的半周期总数 [个] / required half periods [count]
    bNonFin           : BOOL;                 // 输入非有限判定标志 / non-finite input flag
    bCollect          : BOOL;                 // 本拍完成一次有效半周期采集 / a valid half period was collected in this cycle
    uMinSampEff       : UINT;                 // 钳位后的每半周期最少采样数 [拍] / clamped minimum samples per half [scan]
END_VAR
VAR CONSTANT
    DL_AT_MIN_CYCLES    : UINT := 2;          // 周期数下限 [周期] / cycle count lower bound [cycle]
    DL_AT_MAX_CYCLES    : UINT := 20;         // 周期数上限 [周期] / cycle count upper bound [cycle]
    DL_AT_MIN_SAMPLES   : UINT := 4;          // 每半周期采样数下限 [拍] / samples per half lower bound [scan]
    DL_AT_MAX_SAMPLES   : UINT := 100;        // 每半周期采样数上限 [拍] / samples per half upper bound [scan]
    DL_AT_PI            : REAL := 3.14159265; // 圆周率（公开常数）[无量纲] / pi, a public constant [dimensionless]
    DL_AT_FOUR          : LREAL := 4.0;       // 描述函数分子常数 [无量纲] / describing function numerator constant [dimensionless]
    DL_AT_DT_MAX        : TIME := T#10S;      // 采样周期上限 [ms] / sample time upper bound [ms]
    DL_AT_DT_MIN        : TIME := T#1MS;      // 采样周期下限 [ms] / sample time lower bound [ms]
    DL_AT_TIME_MAX      : TIME := T#24H;      // 实验内累计时间饱和值 [ms] / accumulated time saturation [ms]
    DL_AT_TOL_MIN       : REAL := 0.1;        // 稳定容差下限 [%] / stability tolerance lower bound [%]
    DL_AT_TOL_MAX       : REAL := 20.0;       // 稳定容差上限 [%] / stability tolerance upper bound [%]
    DL_FLOAT_EPS        : REAL := 1.0E-6;     // 浮点判等容差 [无量纲] / float equality tolerance [dimensionless]
    DL_AT_PERCENT       : REAL := 100.0;      // 百分比换算因子 [%] / percent conversion factor [%]
    DL_AT_TWO           : REAL := 2.0;        // 二值常量，周期与半周期换算用 [无量纲] / two, used to convert half periods into periods
    DL_AT_ZN_P_K        : REAL := 0.5;        // ZN 纯 P 规则增益系数 [无量纲] / ZN P rule gain factor [dimensionless]
    DL_AT_ZN_PI_K       : REAL := 0.45;       // ZN PI 规则增益系数 [无量纲] / ZN PI rule gain factor [dimensionless]
    DL_AT_ZN_PI_TI      : REAL := 1.2;        // ZN PI 规则积分时间除数 [无量纲] / ZN PI integral time divisor [dimensionless]
    DL_AT_ZN_PID_K      : REAL := 0.6;        // ZN PID 规则增益系数 [无量纲] / ZN PID rule gain factor [dimensionless]
    DL_AT_ZN_PID_TI     : REAL := 2.0;        // ZN PID 规则积分时间除数 [无量纲] / ZN PID integral time divisor [dimensionless]
    DL_AT_ZN_PID_TD     : REAL := 8.0;        // ZN PID 规则微分时间除数 [无量纲] / ZN PID derivative time divisor [dimensionless]
    DL_AT_AH_K          : REAL := 0.2;        // AH 无超调规则增益系数 [无量纲] / AH no overshoot gain factor [dimensionless]
    DL_AT_AH_TI         : REAL := 2.0;        // AH 无超调规则积分时间除数 [无量纲] / AH integral time divisor [dimensionless]
    DL_AT_AH_TD         : REAL := 3.0;        // AH 无超调规则微分时间除数 [无量纲] / AH derivative time divisor [dimensionless]
    DL_AT_MS_PER_S      : REAL := 1000.0;     // 毫秒到秒换算因子 [ms/s] / milliseconds per second [ms/s]
    DL_AT_ZERO          : REAL := 0.0;        // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
    DL_AT_ZERO_L        : LREAL := 0.0;       // LREAL 零值常量 [无量纲] / LREAL zero constant [dimensionless]
    DL_AT_KU_MAX        : LREAL := 1.0E30;    // 临界增益可表示上限 [无量纲] / representable upper bound of the critical gain [dimensionless]
    DL_AT_INF_GUARD     : REAL := 1.0E38;     // 非有限幅值判定阈值 [无量纲] / non-finite magnitude guard [dimensionless]
    DL_AT_TWO_I         : INT := 2;           // 整形二值常量，半周期转周期用 [无量纲] / integer two, converts half periods into periods
    DL_AT_TWO_U         : UINT := 2;          // 无符号二值常量，半周期数折周期数用 [无量纲] / unsigned two, folds half periods into cycles
END_VAR

// 段 1｜边沿与定时器实例无条件周期刷新（红线：严禁放入条件分支）/ segment 1, unconditional refresh
fbTrigStart(CLK := bStart);
fbTrigAbort(CLK := bAbort);
fbTimeout(IN := (eState = eRelay) OR (eState = eMeasure), PT := tMaxDuration); // 只有实验期计时 / the timer runs only during the experiment

// 段 2｜输出与错误状态预置（结果量保持，bDone 为单周期脉冲）/ segment 2, preset outputs and status
bDone := FALSE;                               // 脉冲先清 / clear the pulse first
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置结果不可用 / preset results invalid
bCollect := FALSE;                            // 预置本拍无采集 / preset no collection in this cycle
bBusy := (eState = eRelay) OR (eState = eMeasure); // 忙标志由状态导出 / the busy flag derives from the state

// 段 3｜输入非有限闸：直接落故障态并撤继电 / segment 3, non-finite gate
bNonFin := (fPv <> fPv) OR (fSp <> fSp) OR (fRelayAmp <> fRelayAmp) OR (fRelayHyst <> fRelayHyst); // 非有限判定 / non-finite detection
IF bNonFin THEN
    eErr := 16#0002_2A10;                     // 继电参数非法故障码 / illegal relay parameter fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    eState := eFault;                         // 落故障态 / enter the fault state
    bRelayOut := FALSE;                       // 撤继电，绝不留在振荡状态 / withdraw the relay, never leave the loop oscillating
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF

// 段 4｜中止沿：人为中止不置故障，但必须撤继电 / segment 4, abort edge withdraws the relay without a fault
IF fbTrigAbort.Q THEN
    eState := eIdle;                          // 回空闲态 / back to idle
    bRelayOut := FALSE;                       // 撤继电（本件最高危点）/ withdraw the relay, the most critical point of this block
    bBusy := FALSE;                           // 忙标志撤销 / drop the busy flag
    RETURN;                                   // 中止即出口 / abort is the exit
END_IF

// 段 5｜失能闸：失能同样撤继电 / segment 5, enable gate
IF NOT bEnable THEN
    eState := eIdle;                          // 回空闲态 / back to idle
    bRelayOut := FALSE;                       // 撤继电 / withdraw the relay
    bBusy := FALSE;                           // 忙标志撤销 / drop the busy flag
    RETURN;                                   // 失能即出口 / disabled is the exit
END_IF

// 段 6｜参数域钳位（周期数、采样数、容差、迟滞、超时）/ segment 6, parameter domain clamp
IF (uCyclesRequired < DL_AT_MIN_CYCLES) THEN
    uNeedHalf := DL_AT_MIN_CYCLES;            // 周期数下限钳位 / clamp at the lower cycle count
    eErr := 16#0002_2A01;                     // 信息级：参数超域已钳位 / info level, the parameter was clamped
ELSIF (uCyclesRequired > DL_AT_MAX_CYCLES) THEN
    uNeedHalf := DL_AT_MAX_CYCLES;            // 周期数上限钳位 / clamp at the upper cycle count
    eErr := 16#0002_2A01;                     // 信息级：参数超域已钳位 / info level, the parameter was clamped
ELSE
    uNeedHalf := uCyclesRequired;             // 域内直接用 / in-domain value
END_IF
fCyclesEff := UINT_TO_REAL(uNeedHalf);        // 周期数 REAL 形态，除法前保证非零 / REAL form of the cycle count, nonzero by construction
fStabTolEff := MIN(MAX(fStabTolPercent, DL_AT_TOL_MIN), DL_AT_TOL_MAX); // 稳定容差收敛到 0.1~20.0 % / converge the tolerance into 0.1~20.0 %
fHystEff := MIN(MAX(fRelayHyst, DL_AT_ZERO), fRelayAmp); // 迟滞收敛到 0.0~d / converge the hysteresis into 0.0~d
IF uMinSamplesPerHalf < DL_AT_MIN_SAMPLES THEN
    uMinSampEff := DL_AT_MIN_SAMPLES;         // 采样数下限钳位 / clamp at the lower sample count
    eErr := 16#0002_2A01;                     // 信息级：参数超域已钳位 / info level, the parameter was clamped
ELSIF uMinSamplesPerHalf > DL_AT_MAX_SAMPLES THEN
    uMinSampEff := DL_AT_MAX_SAMPLES;         // 采样数上限钳位 / clamp at the upper sample count
    eErr := 16#0002_2A01;                     // 信息级：参数超域已钳位 / info level, the parameter was clamped
ELSE
    uMinSampEff := uMinSamplesPerHalf;        // 域内直接用 / in-domain value
END_IF
nDtMs := TIME_TO_DINT(tSampleTime);           // 采样周期整数毫秒 [ms] / sample time in integer milliseconds [ms]

// 段 7｜启动前提闸（幅值、采样周期、超时、采样数）/ segment 7, start preconditions
IF fbTrigStart.Q AND ((eState = eIdle) OR (eState = eDone) OR (eState = eFault)) THEN
    IF (fRelayAmp <= DL_FLOAT_EPS) OR (ABS(fRelayAmp) > DL_AT_INF_GUARD)
       OR (tSampleTime < DL_AT_DT_MIN) OR (tSampleTime > DL_AT_DT_MAX) THEN
        eErr := 16#0002_2A10;                 // 继电幅值为 0 时 Ku 恒 0，整定结果无意义 / a zero amplitude makes Ku zero and the result meaningless
        bError := TRUE;                       // 置故障标志 / raise the error flag
        eState := eFault;                     // 落故障态 / enter the fault state
        bRelayOut := FALSE;                   // 撤继电 / withdraw the relay
        RETURN;                               // 故障级提前返回 / early return on fault
    END_IF
    // 段 8｜实验现场复位并进入继电器相 / segment 8, reset the experiment context and start the relay phase
    eState := eRelay;                         // 进入继电器相 / enter the relay phase
    tNow := T#0S;                             // 累计时间清零 / clear the accumulated time
    tEdgeLast := T#0S;                        // 翻转时刻清零 / clear the flip timestamp
    tHalf := T#0S;                            // 半周期清零 / clear the half period
    tHalfPrev := T#0S;                        // 上一半周期清零 / clear the previous half period
    uHalfCount := 0;                          // 半周期计数清零 / clear the half period counter
    fAmpSum1 := DL_AT_ZERO;                   // 第一窗清零 / clear the first window
    fAmpSum2 := DL_AT_ZERO;                   // 第二窗清零 / clear the second window
    uAmpCnt1 := 0;                            // 第一窗计数清零 / clear the first window count
    uAmpCnt2 := 0;                            // 第二窗计数清零 / clear the second window count
    fPeakHi := fPv;                           // 峰值基准取当前测量 / seed the peaks from the current measurement
    fPeakLo := fPv;                           // 峰值基准取当前测量 / seed the peaks from the current measurement
    bRelayPrev := FALSE;                      // 翻转检测基准复位 / reset the flip reference
    bRelayOut := (fPv < fSp);                 // 初始继电方向：低于目标则加 +d / initial relay direction, add plus d below the setpoint
END_IF

// 段 9｜时间累加（比较式预判溢出，不靠回绕兜底）/ segment 9, accumulated time with a comparison overflow guard
IF ((eState = eRelay) OR (eState = eMeasure)) AND (tNow < (DL_AT_TIME_MAX - tSampleTime)) THEN
    tNow := tNow + tSampleTime;               // 累计实验时间 [ms] / accumulate the experiment time [ms]
END_IF

// 段 10｜状态机（含 ELSE 兜底）/ segment 10, state machine with ELSE fallback
CASE eState OF
    eIdle:
        bRelayOut := FALSE;                   // 空闲态无继电输出 / no relay output while idle
        bBusy := FALSE;                       // 空闲态不忙 / not busy while idle

    eRelay:
        // 段 11｜继电翻转（带迟滞）：低于 Sp−h 加 +d，高于 Sp+h 加 −d，带内保持 / segment 11, relay switching with hysteresis
        IF fPv < (fSp - fHystEff) THEN
            bRelayOut := TRUE;                // 低于下界，加正幅值 / below the lower band, apply plus d
        ELSIF fPv > (fSp + fHystEff) THEN
            bRelayOut := FALSE;               // 高于上界，加负幅值 / above the upper band, apply minus d
        END_IF
        fPeakHi := MAX(fPeakHi, fPv);         // 跟踪上峰值 / track the upper peak
        fPeakLo := MIN(fPeakLo, fPv);         // 跟踪下峰值 / track the lower peak
        IF bRelayOut <> bRelayPrev THEN
            bRelayPrev := bRelayOut;          // 记录新方向 / remember the new direction
            tEdgeLast := tNow;                // 记录首个翻转时刻 / remember the first flip instant
            fPeakHi := fPv;                   // 峰值重新播种 / reseed the peaks
            fPeakLo := fPv;                   // 峰值重新播种 / reseed the peaks
            eState := eMeasure;               // 首个翻转即进入测量相 / the first flip enters the measuring phase
        END_IF

    eMeasure:
        // 段 12｜同段内继续翻转判定 / segment 12, continued switching inside the measuring phase
        IF fPv < (fSp - fHystEff) THEN
            bRelayOut := TRUE;                // 低于下界，加正幅值 / below the lower band, apply plus d
        ELSIF fPv > (fSp + fHystEff) THEN
            bRelayOut := FALSE;               // 高于上界，加负幅值 / above the upper band, apply minus d
        END_IF
        fPeakHi := MAX(fPeakHi, fPv);         // 跟踪上峰值 / track the upper peak
        fPeakLo := MIN(fPeakLo, fPv);         // 跟踪下峰值 / track the lower peak

        // 段 13｜翻转沿：结算一个半周期的幅值与长度，并做采样密度闸 / segment 13, settle one half period and check the sample density
        IF bRelayOut <> bRelayPrev THEN
            tHalfPrev := tHalf;               // 保留上一个半周期 / keep the previous half period
            tHalf := tNow - tEdgeLast;        // 本半周期长度 [ms] / this half period length [ms]
            tEdgeLast := tNow;                // 更新翻转时刻 / update the flip instant
            fHalfAmp := (fPeakHi - fPeakLo) / DL_AT_TWO; // 半周期幅值 [用户单位] / half period amplitude [user unit]
            fPeakHi := fPv;                   // 峰值重新播种 / reseed the peaks
            fPeakLo := fPv;                   // 峰值重新播种 / reseed the peaks
            bRelayPrev := bRelayOut;          // 记录新方向 / remember the new direction
            IF nDtMs > 0 THEN
                nSampHalf := TIME_TO_DINT(tHalf) / nDtMs; // 半周期采样数（整数除法，除子已判非零）/ samples per half, integer division with a guarded divisor
                IF nSampHalf < UINT_TO_DINT(uMinSampEff) THEN
                    eErr := 16#0002_2A11;     // 采样过疏，测到的振荡是采样网格产物 / too sparse, the measured oscillation is a sampling artefact
                    bError := TRUE;           // 置故障标志 / raise the error flag
                    eState := eFault;         // 落故障态 / enter the fault state
                    bRelayOut := FALSE;       // 撤继电 / withdraw the relay
                    RETURN;                   // 故障级提前返回 / early return on fault
                END_IF
            END_IF
            uHalfCount := uHalfCount + 1;     // 半周期计数加一 / increment the half period counter
            bCollect := TRUE;                 // 标记本拍完成采集 / flag the collection in this cycle
            IF uAmpCnt1 < uNeedHalf THEN
                fAmpSum1 := fAmpSum1 + fHalfAmp; // 第一窗累计幅值 / accumulate into the first window
                uAmpCnt1 := uAmpCnt1 + 1;     // 第一窗计数加一 / increment the first window count
            ELSE
                fAmpSum2 := fAmpSum2 + fHalfAmp; // 第二窗累计幅值 / accumulate into the second window
                uAmpCnt2 := uAmpCnt2 + 1;     // 第二窗计数加一 / increment the second window count
            END_IF
            uCycleDone := uHalfCount / DL_AT_TWO_U; // 已完成的有效周期数由半周期数折半 / completed cycles folded from the half period count
        END_IF

        // 段 14｜两窗齐备后判稳定：不稳只置信息码继续测，超时才是故障 / segment 14, stability check
        IF bCollect AND (uAmpCnt1 >= uNeedHalf) AND (uAmpCnt2 >= uNeedHalf) THEN
            fMean1 := fAmpSum1 / fCyclesEff;  // 第一窗均值，除子为周期数（≥ 2）/ first window mean, the divisor is at least two
            fMean2 := fAmpSum2 / fCyclesEff;  // 第二窗均值 / second window mean
            IF ((fMean1 + fMean2) * DL_AT_TWO) > DL_FLOAT_EPS THEN
                fRelAmp := ABS(fMean1 - fMean2) / ((fMean1 + fMean2) / DL_AT_TWO) * DL_AT_PERCENT; // 相对偏差 [%] / relative deviation [%]
            ELSE
                fRelAmp := DL_AT_PERCENT;     // 幅值近零时视为完全不一致 / a near zero amplitude counts as fully inconsistent
            END_IF
            IF fRelAmp > fStabTolEff THEN
                eErr := 16#0002_2A01;         // 信息级：振荡未收敛，清窗继续测 / info level, not converged, clear the windows and continue
                fAmpSum1 := DL_AT_ZERO;       // 清第一窗（重新收集）/ clear the first window and collect again
                fAmpSum2 := DL_AT_ZERO;       // 清第二窗 / clear the second window
                uAmpCnt1 := 0;                // 清第一窗计数 / clear the first window count
                uAmpCnt2 := 0;                // 清第二窗计数 / clear the second window count
            ELSE
                // 段 15｜临界增益：Ku = 4d / (pi·sqrt(a^2 − h^2))，含迟滞时退化为 4d/(pi·a) / segment 15, critical gain
                fOscAmp := (fMean1 + fMean2) / DL_AT_TWO; // 振荡幅值取两窗均值 [用户单位] / amplitude as the mean of both windows [user unit]
                tUltPeriod := tHalfPrev * DL_AT_TWO_I;  // 极限周期取最近半周期×2 [ms] / ultimate period as twice the latest half period [ms]
                fTuSec := DINT_TO_REAL(TIME_TO_DINT(tUltPeriod)) / DL_AT_MS_PER_S; // 极限周期秒值 [s] / ultimate period in seconds [s]
                IF fHystEff >= fOscAmp THEN
                    eErr := 16#0002_2A10;     // 迟滞不小于实测幅值，描述函数分母为零/虚数 / hysteresis not narrower than the amplitude makes the denominator zero or imaginary
                    bError := TRUE;           // 置故障标志 / raise the error flag
                    eState := eFault;         // 落故障态 / enter the fault state
                    bRelayOut := FALSE;       // 撤继电 / withdraw the relay
                    RETURN;                   // 故障级提前返回 / early return on fault
                END_IF
                fAmpL := REAL_TO_LREAL(fOscAmp);   // 幅值升位到 LREAL / widen the amplitude to LREAL
                fHystL := REAL_TO_LREAL(fHystEff); // 迟滞升位到 LREAL / widen the hysteresis to LREAL
                fDenL := fAmpL * fAmpL - fHystL * fHystL; // a^2 − h^2（含迟滞描述函数分母）/ squared amplitude minus squared hysteresis
                IF fDenL <= DL_AT_ZERO_L THEN
                    eErr := 16#0002_2A12;     // 分母非正，Ku 不可表示 / the denominator is not positive, Ku is not representable
                    bError := TRUE;           // 置故障标志 / raise the error flag
                    eState := eFault;         // 落故障态 / enter the fault state
                    bRelayOut := FALSE;       // 撤继电 / withdraw the relay
                    RETURN;                   // 故障级提前返回 / early return on fault
                END_IF
                fKuL := DL_AT_FOUR * REAL_TO_LREAL(fRelayAmp) / (REAL_TO_LREAL(DL_AT_PI) * SQRT(fDenL)); // 临界增益（LREAL 中间量）/ critical gain carried in LREAL
                IF (fKuL <> fKuL) OR (fKuL <= DL_AT_ZERO_L) OR (fKuL > DL_AT_KU_MAX) THEN
                    eErr := 16#0002_2A12;     // Ku 不可表示 / Ku is not representable
                    bError := TRUE;           // 置故障标志 / raise the error flag
                    eState := eFault;         // 落故障态 / enter the fault state
                    bRelayOut := FALSE;       // 撤继电 / withdraw the relay
                    RETURN;                   // 故障级提前返回 / early return on fault
                END_IF
                fUltGain := LREAL_TO_REAL(fKuL);   // 回落到 REAL 输出 / narrow back to REAL for the output
                // 段 16｜整定规则（公开文本常数，CASE 含 ELSE 兜底）/ segment 16, tuning rules with ELSE fallback
                CASE eRule OF
                    eZnP:
                        fKp := DL_AT_ZN_P_K * fUltGain;              // 纯比例：Kp = 0.5·Ku / proportional only
                        fTi := DL_AT_ZERO;                           // 纯 P 无积分 / pure P has no integral
                        fTd := DL_AT_ZERO;                           // 纯 P 无微分 / pure P has no derivative
                    eZnPi:
                        fKp := DL_AT_ZN_PI_K * fUltGain;             // PI：Kp = 0.45·Ku / PI gain
                        fTi := fTuSec / DL_AT_ZN_PI_TI;              // PI：Ti = Tu / 1.2 [s] / PI integral time
                        fTd := DL_AT_ZERO;                           // PI 无微分 / PI has no derivative
                    eZnPid:
                        fKp := DL_AT_ZN_PID_K * fUltGain;            // PID：Kp = 0.6·Ku / PID gain
                        fTi := fTuSec / DL_AT_ZN_PID_TI;             // PID：Ti = Tu / 2 [s] / PID integral time
                        fTd := fTuSec / DL_AT_ZN_PID_TD;             // PID：Td = Tu / 8 [s] / PID derivative time
                    eAhNoOvershoot:
                        fKp := DL_AT_AH_K * fUltGain;                // 无超调：Kp = 0.2·Ku / no overshoot gain
                        fTi := fTuSec / DL_AT_AH_TI;                 // 无超调：Ti = Tu / 2 [s] / no overshoot integral time
                        fTd := fTuSec / DL_AT_AH_TD;                 // 无超调：Td = Tu / 3 [s] / no overshoot derivative time
                ELSE
                    eErr := 16#0002_2A12;                            // 故障级：非法规则兜底 / fault level, illegal rule fallback
                    bError := TRUE;                                  // 置故障标志 / raise the error flag
                    eState := eFault;                                // 落故障态 / enter the fault state
                    bRelayOut := FALSE;                              // 撤继电 / withdraw the relay
                    RETURN;                                          // 故障级提前返回 / early return on fault
                END_CASE
                eState := eDone;              // 结果产出，进入完成态 / results produced, enter the done state
                bDone := TRUE;                // 单周期完成脉冲 / single-cycle done pulse
                bRelayOut := FALSE;           // 完成后必须撤继电 / withdraw the relay once finished
                bValid := TRUE;               // 结果可用 / results are valid
                bBusy := FALSE;               // 实验结束 / the experiment is finished
            END_IF
        END_IF

    eDone:
        bRelayOut := FALSE;                   // 完成态保持无继电输出 / no relay output in the done state
        bValid := TRUE;                       // 结果保持可用 / results stay valid
        bBusy := FALSE;                       // 不忙 / not busy

    eFault:
        bRelayOut := FALSE;                   // 故障态撤继电 / withdraw the relay in the fault state
        bBusy := FALSE;                       // 不忙 / not busy

ELSE
    eErr := 16#0002_2A12;                     // 故障级：非法状态兜底 / fault level, illegal state fallback
    bError := TRUE;                           // 置故障标志 / raise the error flag
    eState := eIdle;                          // 回空闲态 / fall back to idle
    bRelayOut := FALSE;                       // 撤继电，绝不留振荡 / withdraw the relay, never leave the loop oscillating
END_CASE

// 段 17｜超时闸：只有实验期有效，超时即故障并撤继电 / segment 17, timeout gate
IF fbTimeout.Q AND ((eState = eRelay) OR (eState = eMeasure)) THEN
    eErr := 16#0002_2A12;                     // 超时未收敛故障码 / timeout without convergence fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    eState := eFault;                         // 落故障态 / enter the fault state
    bRelayOut := FALSE;                       // 撤继电 / withdraw the relay
END_IF
END_FUNCTION_BLOCK
