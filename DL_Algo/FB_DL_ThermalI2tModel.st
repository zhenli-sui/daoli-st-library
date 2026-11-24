(*
    FB_DL_ThermalI2tModel —— I 平方 t 一阶热累积模型
    ------------------------------------------------------------------
    分类      : DL_Algo / Protection
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 自研（I 平方 t 为公开热保护工程判据，只取 IEC 60255 反时限特性的一般
                口径，不复制任何条款文本）；一阶热模型的离散化、闸门顺序、码位与
                分级 100% 自有；clean-room 重写，未复制任何闭源厂商源码，
                参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R18）
    ------------------------------------------------------------------
    功能说明  : 按 d(theta)/dt = ((I/Ir)^2 - theta) / tau 累积热容量利用率，超阈值分级
                预警与跳闸，用于电机、加热丝、线缆、制动电阻的过载热保护；
                与 VfdDrive 内部过载的分界是本件为可复用的独立热模型，不绑定任何驱动；
                四道闸：额定电流闸（除零源头）→ 电流非有限闸 → 时间参数闸 →
                离散失真硬闸（单拍 dt 超过 tau 的 10% 时欧拉积分不可信，宁可报故障
                也不出假安全值）；失能只冻结不清零，符合真实冷却慢过程的物理语义；
                冷却剩余时间用对数解析解，theta 不超过 0.5 时不取对数（定义域闸）。
    错误码    : 16#0002_2601 阈值关系倒置已自动交换 / 热容量达钳位上限已限制——信息级，不置故障
                16#0002_2602 预留禁用（信息级，不得挪用）
                16#0002_2610 额定电流非法（不大于 EPS）或电流非有限——故障级，theta 冻结
                16#0002_2611 时间常数或采样周期非法，或 dt 超 tau 的 10%（离散失真）——故障级，theta 冻结
                16#0002_2612 预留禁用（故障级，不得挪用）
    码位总账  : 16#0002_2601 用 / 16#0002_2602 预留 ｜ 16#0002_2610 用 / 16#0002_2611 用 / 16#0002_2612 预留
    状态机    : 无 CASE，热状态由 fTheta 一个实数承载，非法状态由参数闸拦截，不可能出现
    采样约定  : fbTrigReset 在本体首部无条件刷新；tSampleTime 必须等于任务周期，
                离散化误差与周期成正比，周期变动时 dl 失真闸会先行报警。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R18）
*)
FUNCTION_BLOCK FB_DL_ThermalI2tModel
VAR_INPUT
    bEnable           : BOOL;                  // 使能，FALSE 冻结热状态且不清零 / enable, FALSE freezes the thermal state without clearing it
    bReset            : BOOL;                  // 复位，上升沿把热容量清零并清跳闸（仅检修用）/ reset, rising edge clears the load and the trip, maintenance only
    fCurrent          : REAL := 0.0;           // 实测电流（RMS 或等效）[A]，范围 0.0~1.0E5 / measured current, RMS or equivalent [A], range 0.0~1.0E5
    fRatedCurrent     : REAL := 1.0;           // 额定电流 Ir [A]，范围 0.001~1.0E5 / rated current Ir [A], range 0.001~1.0E5
    tThermalTimeConst : TIME := T#60S;         // 热时间常数 tau [s]，范围 1~3600 / thermal time constant tau [s], range 1~3600
    tSampleTime       : TIME := T#10MS;        // 采样周期 [ms]，范围 1~1000，必须等于任务周期 / sample period [ms], range 1~1000, must equal the task period
    fAlarmLevel       : REAL := 0.85;          // 预警阈值（热容量利用率）[无量纲]，范围 0.1~0.99 / alarm threshold on the thermal load [dimensionless], range 0.1~0.99
    fTripLevel        : REAL := 1.00;          // 跳闸阈值 [无量纲]，必须大于预警阈值 / trip threshold [dimensionless], must exceed the alarm threshold
    bTripEnable       : BOOL := TRUE;          // 跳闸输出使能，调试期可关 / trip output enable, may be disabled during commissioning
END_VAR
VAR_OUTPUT
    fThermalLoad : REAL;                       // 热容量利用率 theta，0.0~2.0（可短暂超 1）/ thermal load theta, 0.0~2.0, may briefly exceed one
    bAlarm       : BOOL;                       // 预警（theta 不小于预警阈值）/ alarm, TRUE when theta reaches the alarm level
    bTrip        : BOOL;                       // 跳闸（已锁存，仅复位清除）/ trip, latched until reset
    tCoolRemain  : TIME;                       // 从当前 theta 冷却到 0.5 的估算剩余时间 [s] / estimated time to cool down to 0.5 [s]
    eErr         : UDINT;                      // 错误码，0=正常 / error id, 0=ok
    bError       : BOOL;                       // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
END_VAR
VAR
    fbTrigReset : R_TRIG;                      // 复位沿检测实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    fRatioSq    : REAL;                        // 电流比平方 (I/Ir)^2 [无量纲] / squared current ratio [dimensionless]
    fDtSec      : REAL;                        // 采样周期秒值 [s] / sample period in seconds [s]
    fTheta      : REAL;                        // 内部热容量利用率 [无量纲] / internal thermal load [dimensionless]
    fTauSec     : REAL;                        // 热时间常数秒值 [s] / thermal time constant in seconds [s]
    fRatio      : REAL;                        // 电流比中间量，避免重复除法 [无量纲] / current ratio intermediate, avoids a repeated division [dimensionless]
    fAlarmEff   : REAL;                        // 生效预警阈值，交换后使用 [无量纲] / effective alarm threshold after the swap [dimensionless]
    fTripEff    : REAL;                        // 生效跳闸阈值，交换后使用 [无量纲] / effective trip threshold after the swap [dimensionless]
    fSwapTmp    : REAL;                        // 阈值交换中间量 [无量纲] / threshold swap intermediate [dimensionless]
    fClamped    : REAL;                        // 钳位中间量 [无量纲] / clamping intermediate [dimensionless]
    fCoolSec    : REAL;                        // 冷却剩余时间秒值 [s] / cooling time in seconds [s]
    bInit       : BOOL := FALSE;               // 首扫标志，初值 FALSE，判据 NOT bInit / first-scan flag, initial FALSE, tested with NOT
    bTripLatch  : BOOL;                        // 跳闸锁存位，仅复位清除 / trip latch, cleared by reset only
    bFreeze     : BOOL;                        // 冻结标志，任一闸不通过即冻结 theta / freeze flag, any failed gate freezes theta
    bNonFin     : BOOL;                        // 电流非有限判定标志 / current non-finite flag
END_VAR
VAR CONSTANT
    DL_I2T_LOAD_MAX      : REAL := 2.0;        // theta 钳位上限，防离散抖动发散 [无量纲] / theta clamp against discrete chatter divergence [dimensionless]
    DL_I2T_DT_MAX_RATIO  : REAL := 0.1;        // 单拍 dt 与 tau 的比值上限，超则判离散失真 [无量纲] / per cycle dt to tau ratio cap, above it the discretisation is untrustworthy [dimensionless]
    DL_I2T_COOL_TARGET   : REAL := 0.5;        // 冷却目标利用率 [无量纲] / cooling target load [dimensionless]
    DL_I2T_TAU_MIN       : TIME := T#1S;       // 时间常数下限 [s] / time constant lower bound [s]
    DL_I2T_TS_MIN        : TIME := T#1MS;      // 采样周期下限 [ms] / sample period lower bound [ms]
    DL_I2T_MS_SEC        : REAL := 1000.0;     // 毫秒转秒的除数，恒非零 [ms/s] / milliseconds to seconds divisor, never zero [ms/s]
    DL_I2T_LEVEL_MIN     : REAL := 0.1;        // 预警阈值下限 [无量纲] / alarm threshold lower bound [dimensionless]
    DL_I2T_LEVEL_MAX     : REAL := 0.99;       // 预警阈值上限 [无量纲] / alarm threshold upper bound [dimensionless]
    DL_I2T_TRIP_MIN      : REAL := 2.0;        // 跳闸阈值上限 [无量纲] / trip threshold upper bound [dimensionless]
    DL_FLOAT_EPS         : REAL := 1.0E-6;     // 浮点判等容差 [无量纲] / float equality tolerance [dimensionless]
    DL_I2T_INF_GUARD     : REAL := 4.0E38;     // 非有限幅值判定阈值 [A] / non-finite magnitude guard [A]
    DL_I2T_ZERO          : REAL := 0.0;        // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
    DL_I2T_ONE           : REAL := 1.0;        // 一值常量，用于电流比 [无量纲] / one constant used by the current ratio [dimensionless]
END_VAR

// 段 1｜边沿实例无条件周期刷新（红线：严禁放入条件分支）/ segment 1, unconditional edge refresh
fbTrigReset(CLK := bReset);

// 段 2｜输出与错误状态预置 / segment 2, preset outputs and error status
eErr := 0;                                     // 预置无错误 / preset no error
bError := FALSE;                               // 预置无故障 / preset no fault
bAlarm := FALSE;                               // 预置无预警 / preset no alarm
bFreeze := FALSE;                              // 预置不冻结 / preset not frozen
fTauSec := DL_I2T_ZERO;                        // 时间常数秒值清零 / clear the time constant in seconds

// 段 3｜首扫初始化（初值 FALSE，判据 NOT bInit）/ segment 3, first-scan initialisation
IF NOT bInit THEN
    fTheta := DL_I2T_ZERO;                     // 冷态起步 / start from the cold state
    bTripLatch := FALSE;                       // 清跳闸锁存 / clear the trip latch
    bInit := TRUE;                             // 首扫只做一次 / first scan runs once only
END_IF

// 段 4｜阈值域校正：越域钳位，倒置自动交换（现场参数填反极常见）/ segment 4, threshold domain correction
fAlarmEff := MIN(MAX(fAlarmLevel, DL_I2T_LEVEL_MIN), DL_I2T_LEVEL_MAX); // 预警阈值双侧钳位 / clamp the alarm threshold both sides
fTripEff := MIN(MAX(fTripLevel, DL_I2T_LEVEL_MIN), DL_I2T_TRIP_MIN);    // 跳闸阈值双侧钳位 / clamp the trip threshold both sides
IF fTripEff <= (fAlarmEff + DL_FLOAT_EPS) THEN
    fSwapTmp := fAlarmEff;                     // 暂存预警阈值 / hold the alarm threshold
    fAlarmEff := fTripEff;                     // 交换下限 / swap the lower bound
    fTripEff := fSwapTmp;                      // 交换上限 / swap the upper bound
    eErr := 16#0002_2601;                      // 交换提示（信息级不置故障）/ swap hint, info level never raises a fault
END_IF

// 段 5｜复位沿：清热容量与跳闸（检修用）/ segment 5, reset clears the load and the trip
IF fbTrigReset.Q THEN
    fTheta := DL_I2T_ZERO;                     // 热容量清零 / clear the thermal load
    bTripLatch := FALSE;                       // 清跳闸锁存 / clear the trip latch
END_IF

// 段 6｜额定电流闸与电流非有限闸（除零源头先拦）/ segment 6, rated current and non-finite current gate
bNonFin := (fCurrent <> fCurrent) OR (fCurrent > DL_I2T_INF_GUARD) OR (fCurrent < -DL_I2T_INF_GUARD); // 电流非有限判定 / non-finite current check
IF (fRatedCurrent <= DL_FLOAT_EPS) OR bNonFin THEN
    eErr := 16#0002_2610;                      // 额定电流非法或电流非有限故障码 / illegal rated current or non-finite current fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    bFreeze := TRUE;                           // 冻结 theta，绝不出假安全值 / freeze theta, never publish a false safe value
END_IF

// 段 7｜时间参数闸 / segment 7, time parameter gate
IF (NOT bFreeze) AND ((tThermalTimeConst < DL_I2T_TAU_MIN) OR (tSampleTime < DL_I2T_TS_MIN)) THEN
    eErr := 16#0002_2611;                      // 时间参数非法故障码 / illegal time parameter fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    bFreeze := TRUE;                           // 冻结 theta / freeze theta
END_IF

// 段 8｜离散失真硬闸：单拍 dt 超 tau 的 10% 时欧拉积分不可信 / segment 8, discretisation distortion gate
IF NOT bFreeze THEN
    fTauSec := TIME_TO_REAL(tThermalTimeConst) / DL_I2T_MS_SEC; // 时间常数秒值 / time constant in seconds
    fDtSec := TIME_TO_REAL(tSampleTime) / DL_I2T_MS_SEC;        // 采样周期秒值 / sample period in seconds
    IF fDtSec > (DL_I2T_DT_MAX_RATIO * fTauSec) THEN
        eErr := 16#0002_2611;                  // 离散失真故障码 / discretisation distortion fault id
        bError := TRUE;                        // 置故障标志 / raise the error flag
        bFreeze := TRUE;                       // 冻结 theta / freeze theta
    END_IF
END_IF

// 段 9｜热模型更新：一阶欧拉，分母已由前闸保证非零 / segment 9, first order Euler update
IF NOT bFreeze THEN
    fRatio := fCurrent / fRatedCurrent;        // 电流比，分母已过闸 / current ratio, the divisor passed the gate
    fRatioSq := fRatio * fRatio;               // 电流比平方 / squared current ratio
    fTheta := fTheta + (fRatioSq - fTheta) * fDtSec / fTauSec; // 分母同样已过闸 / the divisor passed the same gate
    fClamped := MIN(MAX(fTheta, DL_I2T_ZERO), DL_I2T_LOAD_MAX); // 双侧钳位 / clamp both sides
    IF (fTheta > DL_I2T_LOAD_MAX) OR (fTheta < DL_I2T_ZERO) THEN
        eErr := 16#0002_2601;                  // 钳位提示（信息级不置故障）/ clamp hint, info level never raises a fault
    END_IF
    fTheta := fClamped;                        // 落盘钳位值 / commit the clamped value
END_IF

// 段 10｜分级判定与跳闸锁存 / segment 10, grading and trip latching
fThermalLoad := fTheta;                        // 对外镜像热容量 / publish the thermal load
IF fTheta >= fAlarmEff THEN
    bAlarm := TRUE;                            // 越预警阈值 / above the alarm threshold
END_IF
IF (fTheta >= fTripEff) AND bTripEnable THEN
    bTripLatch := TRUE;                        // 越跳闸阈值且允许跳闸即锁存 / latch when above the trip threshold with the trip enabled
END_IF
bTrip := bTripLatch AND bTripEnable;           // 跳闸输出受使能门控，关断时不误跳 / the trip output is gated by the enable so a disabled trip never fires

// 段 11｜冷却剩余时间：对数解析解，定义域前置 / segment 11, cooling time with the domain gate
IF (fTheta <= DL_I2T_COOL_TARGET) OR (fTauSec <= DL_FLOAT_EPS) THEN
    tCoolRemain := T#0MS;                      // 已低于目标或时间常数无效，剩余为 0，不取对数 / already below the target or an invalid time constant, no logarithm
ELSE
    fCoolSec := fTauSec * LN(fTheta / DL_I2T_COOL_TARGET); // theta 大于目标，对数定义域安全 / theta is above the target, the logarithm is safe
    IF fCoolSec > DL_I2T_ZERO THEN
        tCoolRemain := REAL_TO_TIME(fCoolSec * DL_I2T_MS_SEC); // 秒转毫秒后落 TIME / seconds to milliseconds then to TIME
    ELSE
        tCoolRemain := T#0MS;                  // 数值异常时回 0，绝不输出负时长 / fall back to zero on a numerical anomaly, never a negative duration
    END_IF
END_IF
END_FUNCTION_BLOCK
