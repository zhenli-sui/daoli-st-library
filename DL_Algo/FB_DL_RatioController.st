(*
    FB_DL_RatioController —— 比值控制站
    ------------------------------------------------------------------
    分类      : DL_Algo / ProcessControl
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 比值控制为公开过程控制通用结构（从动给定 = 主动流量 × 比率 + 偏置）；
                本件只借「参数域约束」的组织方式，低限切安全给定、迟滞式的状态迁移、
                斜率限制、兜底纪律与码位 100% 自有；clean-room 重写，未复制任何
                闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R19）
    ------------------------------------------------------------------
    功能说明  : 从动流量给定 = 主动流量 × 比率 + 偏置。核心防御是「主动流量低限保护」：
                主动流量接近 0 时按比例算出的从动给定也趋 0，操作工看到「两个流量都归零」，
                真正的故障源（主动侧断料）被掩盖——本件在低限以下直接切到安全给定并置
                bMasterLow。其余防御：① 比率域与输出域自相矛盾即故障级 2811（区间不存在）；
                ② 比率越窗只钳位并置信息码（超窗是「待调整」而非故障）；
                ③ 斜率限制首拍 fStep = 0，绝不用 0 除；④ 输出双侧钳位（只做单侧是常见缺陷）；
                ⑤ 输入非有限时给定保持末次有效值——切 0 会直接停料；
                ⑥ 状态机 CASE 含 ELSE 兜底，非法状态回 eIdle 并保持末值。
                职责边界：本件不算 PID（环路闭合归 FB_DL_PidController），只出给定。
    错误码    : 16#0002_2801 比率被限幅 / 主动流量低于低限已切安全给定——信息级，正常防御
                16#0002_2802 预留禁用（信息级，不得挪用）
                16#0002_2810 输入非有限或斜率/采样参数非法——故障级，给定保持末次有效
                16#0002_2811 限值区间自相矛盾（比率域或输出域非法）——故障级，给定保持末次有效
                16#0002_2812 状态机落 ELSE 兜底（非法状态）——故障级，回 eIdle 并保持末值
    码位总账  : 16#0002_2801 用 / 16#0002_2802 预留 ｜ 16#0002_2810 用 / 16#0002_2811 用 / 16#0002_2812 用
    状态机    : E_DL_RatioState（eIdle / eRunning / eMasterLow / eFault）四态，CASE 含 ELSE 兜底，
                ELSE 分支回 eIdle 并置故障级 2812；失能无条件回 eIdle。
    采样约定  : fbTrigReset 在本体首部无条件刷新；斜率步长由 tSampleTime 引脚换算，
                首拍 fLastSp 未建立时 fStep 取 0（不做除零），故给定不会突变。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R19）
*)

(*
    枚举 : E_DL_RatioState —— 比值站状态（本文件为全库唯一属主）
*)
TYPE E_DL_RatioState :
(
    eIdle      := 0,                          // 空闲：未使能，输出停在限幅下限 / idle, disabled, output parked at the lower bound
    eRunning   := 1,                          // 运行：按比率跟踪主动流量 / running, tracking the master flow by ratio
    eMasterLow := 2,                          // 主动低限：给定已切安全值 / master low, setpoint switched to the safe value
    eFault     := 3                           // 故障：给定保持末次有效值 / fault, setpoint holds the last valid value
);
END_TYPE

FUNCTION_BLOCK FB_DL_RatioController
VAR_INPUT
    bEnable         : BOOL;                   // 使能，FALSE 回 eIdle 并输出限幅下限 / enable, FALSE returns to eIdle and outputs the lower bound
    bReset          : BOOL;                   // 复位，上升沿清限幅锁存与斜率状态 / reset, rising edge clears the clamp latches and the ramp state
    fMasterFlow     : REAL := 0.0;            // 主动流量测量值 [m3/h]，范围 0.0~1.0E6 / measured master flow [m3/h], range 0.0~1.0E6
    fRatio          : REAL := 1.0;            // 比率 [无量纲]，范围 fRatioMin~fRatioMax / ratio [dimensionless], range fRatioMin~fRatioMax
    fRatioMin       : REAL := 0.01;           // 比率下限 [无量纲]，必须 > 0 / ratio lower bound [dimensionless], must be > 0
    fRatioMax       : REAL := 10.0;           // 比率上限 [无量纲]，必须 > fRatioMin / ratio upper bound [dimensionless], must be > fRatioMin
    fBias           : REAL := 0.0;            // 偏置量 [m3/h]，范围 -1.0E4~1.0E4 / bias [m3/h], range -1.0E4~1.0E4
    fMasterLowLimit : REAL := 1.0;            // 主动流量低限 [m3/h]，范围 0.0~1.0E6 / master flow low limit [m3/h], range 0.0~1.0E6
    fMasterLowSp    : REAL := 0.0;            // 低限以下的安全给定 [m3/h]，范围 fOutMin~fOutMax / safe setpoint below the low limit [m3/h], range fOutMin~fOutMax
    fOutMin         : REAL := 0.0;            // 输出下限 [m3/h] / output lower bound [m3/h]
    fOutMax         : REAL := 100.0;          // 输出上限 [m3/h]，必须 > fOutMin / output upper bound [m3/h], must be > fOutMin
    fRateMax        : REAL := 50.0;           // 输出最大变化率 [m3/h/s]，范围 0.001~1.0E6 / maximum output rate [m3/h/s], range 0.001~1.0E6
    tSampleTime     : TIME := T#100MS;        // 采样周期 [ms]，范围 1~10000 / sample time [ms], range 1~10000
END_VAR
VAR_OUTPUT
    fSlaveSp        : REAL;                   // 从动侧给定 [m3/h] / slave setpoint [m3/h]
    bMasterLow      : BOOL;                   // 主动流量低于低限，给定已切安全值 / master flow below the low limit, setpoint switched
    bRatioClamped   : BOOL;                   // 比率被限幅 / ratio clamped
    bOutClamped     : BOOL;                   // 输出被上下限或斜率限制 / output limited by the bounds or the ramp
    fEffectiveRatio : REAL;                   // 实际生效比率（含限幅）[无量纲] / effective ratio including the clamp [dimensionless]
    eErr            : UDINT;                  // 错误码，0=正常 / error id, 0=ok
    bError          : BOOL;                   // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid          : BOOL;                   // 给定是否可用 / setpoint valid flag
END_VAR
VAR
    eState          : E_DL_RatioState := eIdle; // 状态机当前态 / current state machine state
    fbTrigReset     : R_TRIG;                 // 复位上升沿实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    fLastSp         : REAL;                   // 上一拍给定（斜率限制基准）[m3/h] / previous setpoint used by the ramp [m3/h]
    fStep           : REAL;                   // 本拍允许的最大变化量 [m3/h] / maximum allowed change in this cycle [m3/h]
    fDtSec          : REAL;                   // 采样周期换算的秒数 [s] / sample time converted to seconds [s]
    fRatioEff       : REAL;                   // 限幅后的生效比率 [无量纲] / effective ratio after clamping [dimensionless]
    fTarget         : REAL;                   // 钳位与限速率前的目标给定 [m3/h] / target setpoint before clamping and ramping [m3/h]
    bNonFin         : BOOL;                   // 输入非有限判定标志 / non-finite input flag
    nDtMs           : DINT;                   // 采样周期毫秒整数 [ms] / sample time in integer milliseconds [ms]
END_VAR
VAR CONSTANT
    DL_RTO_RATIO_EPS : REAL := 1.0E-6;        // 比率判零容差 [无量纲] / ratio zero tolerance [dimensionless]
    DL_RTO_RATE_MIN  : REAL := 0.001;         // 变化率下限 [m3/h/s] / rate lower bound [m3/h/s]
    DL_RTO_RATE_MAX  : REAL := 1.0E6;         // 变化率上限 [m3/h/s] / rate upper bound [m3/h/s]
    DL_RTO_DT_MAX    : TIME := T#10S;         // 采样周期上限 [ms] / sample time upper bound [ms]
    DL_RTO_DT_MIN    : TIME := T#1MS;         // 采样周期下限 [ms] / sample time lower bound [ms]
    DL_FLOAT_EPS     : REAL := 1.0E-6;        // 浮点判等容差 [无量纲] / float equality tolerance [dimensionless]
    DL_RTO_MS_PER_S  : REAL := 1000.0;        // 毫秒到秒的换算因子 [ms/s] / milliseconds per second [ms/s]
    DL_RTO_INF_GUARD : REAL := 1.0E38;        // 非有限幅值判定阈值 [无量纲] / non-finite magnitude guard [dimensionless]
    DL_RTO_ZERO      : REAL := 0.0;           // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
END_VAR

// 段 1｜边沿实例无条件周期刷新（红线：严禁放入条件分支）/ segment 1, unconditional edge refresh
fbTrigReset(CLK := bReset);

// 段 2｜输出与错误状态预置（fSlaveSp 不预置，故障时须保持末次有效值）/ segment 2, preset outputs except the held setpoint
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置不可用 / preset invalid
bMasterLow := FALSE;                          // 预置非低限态 / preset not in the master-low state
bRatioClamped := FALSE;                       // 预置比率未限幅 / preset ratio not clamped
bOutClamped := FALSE;                         // 预置输出未限幅 / preset output not clamped

// 段 3｜输入非有限闸：给定保持末次有效（切 0 会直接停料）/ segment 3, non-finite gate
bNonFin := (fMasterFlow <> fMasterFlow) OR (fMasterFlow > DL_RTO_INF_GUARD) OR (fMasterFlow < -DL_RTO_INF_GUARD)
        OR (fRatio <> fRatio) OR (fBias <> fBias)
        OR (fRatioMin <> fRatioMin) OR (fRatioMax <> fRatioMax)
        OR (fOutMin <> fOutMin) OR (fOutMax <> fOutMax)
        OR (fMasterLowLimit <> fMasterLowLimit) OR (fMasterLowSp <> fMasterLowSp); // 非有限判定 / non-finite detection
IF bNonFin THEN
    eErr := 16#0002_2810;                     // 输入非有限故障码 / non-finite input fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    eState := eFault;         // 落故障态 / enter the fault state
    fSlaveSp := fLastSp;                      // 给定保持末次有效值 / hold the last valid setpoint
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF

// 段 4｜限值区间自洽闸（区间不存在即故障，比参数越界更危险）/ segment 4, interval consistency gate
IF (fRatioMin <= DL_RTO_RATIO_EPS) OR (fRatioMax <= fRatioMin) THEN
    eErr := 16#0002_2811;                     // 比率域自相矛盾故障码 / ratio domain contradiction fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    eState := eFault;         // 落故障态 / enter the fault state
    fSlaveSp := fLastSp;                      // 保持末值 / hold the last value
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF
IF fOutMax <= fOutMin THEN
    eErr := 16#0002_2811;                     // 输出域自相矛盾，同一语义复用同一故障码 / output domain contradiction, same fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    eState := eFault;         // 落故障态 / enter the fault state
    fSlaveSp := fLastSp;                      // 保持末值 / hold the last value
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF

// 段 5｜斜率与采样参数闸（参数非法则斜率律不可信）/ segment 5, rate and sample gate
IF (fRateMax < DL_RTO_RATE_MIN) OR (fRateMax > DL_RTO_RATE_MAX)
   OR (tSampleTime < DL_RTO_DT_MIN) OR (tSampleTime > DL_RTO_DT_MAX) THEN
    eErr := 16#0002_2810;                     // 斜率或采样参数非法故障码 / rate or sample parameter fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    eState := eFault;         // 落故障态 / enter the fault state
    fSlaveSp := fLastSp;                      // 给定保持末次有效值 / hold the last valid setpoint
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF

// 段 6｜斜率步长（首拍 fLastSp 未建立时 fStep = 0，绝不用 0 除）/ segment 6, ramp step
nDtMs := TIME_TO_DINT(tSampleTime);           // 采样周期显式取整数毫秒 / take the sample time in integer milliseconds
fDtSec := DINT_TO_REAL(nDtMs) / DL_RTO_MS_PER_S; // 换算为秒，除子为常量非零 [s] / convert to seconds, the divisor is a nonzero constant [s]
IF fDtSec <= DL_RTO_ZERO THEN
    fStep := DL_RTO_ZERO;                     // 首拍或非法周期：不突变 / first scan or illegal period, no step at all
ELSE
    fStep := fRateMax * fDtSec;               // 本拍允许的最大变化量 [m3/h] / maximum allowed change in this cycle [m3/h]
END_IF

// 段 7｜复位沿清限幅锁存与斜率状态（不改变状态机态）/ segment 7, reset edge clears the latches
IF fbTrigReset.Q THEN
    fLastSp := MIN(MAX(fLastSp, fOutMin), fOutMax); // 复位把基准拉回合法域 / pull the ramp reference back into the legal domain
    bRatioClamped := FALSE;                   // 清比率限幅锁存 / clear the ratio clamp latch
    bOutClamped := FALSE;                     // 清输出限幅锁存 / clear the output clamp latch
END_IF

// 段 8｜失能无条件回 eIdle / segment 8, disabled forces eIdle
IF NOT bEnable THEN
    eState := eIdle;          // 失能回空闲态 / return to idle when disabled
END_IF

// 段 9｜比率限幅（越窗是待调整，只置信息码）/ segment 9, ratio clamp
fRatioEff := fRatio;                          // 取入参副本 / copy the input
IF fRatioEff > fRatioMax THEN
    fRatioEff := fRatioMax;                   // 越上限钳位 / clamp at the upper bound
    bRatioClamped := TRUE;                    // 标记比率限幅 / flag the ratio clamp
    eErr := 16#0002_2801;                     // 信息级：比率被限幅 / info level, the ratio was clamped
ELSIF fRatioEff < fRatioMin THEN
    fRatioEff := fRatioMin;                   // 越下限钳位 / clamp at the lower bound
    bRatioClamped := TRUE;                    // 标记比率限幅 / flag the ratio clamp
    eErr := 16#0002_2801;                     // 同一业务语义复用同一信息码 / the same semantics reuses the same info id
END_IF
fEffectiveRatio := fRatioEff;                 // 发布生效比率 / publish the effective ratio

// 段 10｜状态机（含 ELSE 兜底）/ segment 10, state machine with ELSE fallback
CASE eState OF
    eIdle:
        fSlaveSp := fOutMin;                  // 空闲态输出限幅下限，不按比例算 / idle outputs the lower bound, no ratio computation
        fLastSp := fOutMin;                   // 斜率基准同步，避免使能首拍跳变 / sync the ramp reference to avoid a jump on enable
        IF bEnable THEN
            eState := eRunning; // 使能即进入运行态 / enabling enters the running state
        END_IF

    eRunning:
        IF fMasterFlow < fMasterLowLimit THEN
            fTarget := fMasterLowSp;          // 低限以下切安全给定，不按比例算 / below the low limit switch to the safe setpoint
            bMasterLow := TRUE;               // 发布低限标志 / publish the master-low flag
            eErr := 16#0002_2801;             // 信息级：主动流量低于低限已切安全给定 / info level, the safe setpoint was applied
            eState := eMasterLow; // 迁移到低限态 / move to the master-low state
        ELSE
            fTarget := fMasterFlow * fRatioEff + fBias; // 比值律：从动给定 = 主动 × 比率 + 偏置 / ratio law
        END_IF

    eMasterLow:
        fTarget := fMasterLowSp;              // 低限态保持安全给定 / hold the safe setpoint in the master-low state
        bMasterLow := TRUE;                   // 持续发布低限标志 / keep publishing the master-low flag
        IF fMasterFlow >= fMasterLowLimit THEN
            eState := eRunning; // 主动流量恢复即回运行态 / return to running once the master recovers
        END_IF

    eFault:
        fTarget := fLastSp;                   // 故障态目标即末次值，不再跟踪 / the fault state targets the last value, no tracking
        bValid := FALSE;                      // 故障态给定不可用 / the setpoint is not usable in the fault state

ELSE
    eErr := 16#0002_2812;                     // 故障级：非法状态兜底 / fault level, illegal state fallback
    bError := TRUE;                           // 置故障标志 / raise the error flag
    eState := eIdle;          // 回空闲态 / fall back to idle
    fTarget := fLastSp;                       // 保持末值，不产生跳变 / hold the last value, no jump
END_CASE

// 段 11｜输出双侧钳位（只做单侧是常见缺陷）/ segment 11, two-sided output clamp
IF fTarget > fOutMax THEN
    fTarget := fOutMax;                       // 上限钳位 / clamp at the upper bound
    bOutClamped := TRUE;                      // 标记输出限幅 / flag the output clamp
ELSIF fTarget < fOutMin THEN
    fTarget := fOutMin;                       // 下限钳位 / clamp at the lower bound
    bOutClamped := TRUE;                      // 标记输出限幅 / flag the output clamp
END_IF

// 段 12｜斜率限制（每拍最多变化 fStep）/ segment 12, ramp limiting
IF fStep > DL_RTO_ZERO THEN
    IF fTarget > (fLastSp + fStep) THEN
        fTarget := fLastSp + fStep;           // 正向每拍限幅 / limit the positive step per cycle
        bOutClamped := TRUE;                  // 标记斜率限制 / flag the ramp limit
    ELSIF fTarget < (fLastSp - fStep) THEN
        fTarget := fLastSp - fStep;           // 负向每拍限幅 / limit the negative step per cycle
        bOutClamped := TRUE;                  // 标记斜率限制 / flag the ramp limit
    END_IF
END_IF

// 段 13｜发布给定与状态（无故障时给定可用）/ segment 13, publish the setpoint and the status
fSlaveSp := fTarget;                          // 输出本拍给定 [m3/h] / publish this cycle setpoint [m3/h]
fLastSp := fTarget;                           // 记录为下一拍斜率基准 / remember it as the next ramp reference
IF NOT bError THEN
    bValid := TRUE;                           // 无故障则给定可用 / usable when no fault is present
END_IF
END_FUNCTION_BLOCK
