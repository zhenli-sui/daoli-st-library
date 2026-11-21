(*
  ==================================================================
  组件名 Component  : FB_DL_EnergyMonthPreset
  分类   Category   : DL_Process
  版本   Version    : 1.0.0
  功能   Purpose    : 月度能耗预算预置计数与超限预警。月度能耗预算按 12 个月预置表
                      取值（跨月沿自动换表并清零当月累计），能耗增量按脉冲沿累加，
                      出口给出已用 / 剩余 / 占用百分比 / 日均 / 月末预测，并按
                      预警阈与临界阈分四级（正常 / 预警 / 临界 / 超限）。
  溯源   Origin     : 月度预算预置 + 分级预警为本库通用能耗管理语义；本件为
                      clean-room 实现，仅借鉴来源分类与参数域组织（来源标签
                      roadmap-p2-energy），道莅原创设计，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（R_TRIG / REAL 运算，无私有库、无方言转换）
  作者   Author     : 道莅代码库 · PLC 编程专家（R55）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只做预算计数与分级，不控制用能设备、不发停机命令；
                      二 能耗增量只在 bEnergyPulse 上升沿计入一次（防同拍重复计）；
                      三 跨月判据 = 年或月任一变化（同一月内不重复换表）；
                      四 负增量（表计回卷 / 换表）不计入并置信息级成因，不置故障；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      eLevel 四级互斥；bWarn 在预警及以上为真，bOver 仅超限为真；
                      bMonthRoll 为跨月单拍脉冲（内部位置位、出口映射后撤销）；
                      非有限能耗增量不穿透出口（已用量保持上拍值）；
                      eCause 故障级成员均与 bError 配对（R45），信息级不置故障。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R55 首版（批 1 · 序号 3）
  ==================================================================
*)

TYPE E_DL_EngLevel :
(
    eNormal := 0,       // 正常：占用低于预警阈 / normal, occupancy below the warning threshold
    eWarn   := 10,      // 预警：占用达预警阈 / warning, occupancy reached the warning threshold
    eCrit   := 20,      // 临界：占用达临界阈 / critical, occupancy reached the critical threshold
    eOver   := 30       // 超限：占用越过 100% / over, occupancy beyond one hundred percent
);
END_TYPE

TYPE E_DL_EngCause :
(
    eNone       := 0,   // 无成因 / no cause
    eCfgIllegal := 1,   // 组态非法：月/日/阈值或预算表越域（故障级）/ illegal config, month, day, threshold or budget table out of domain
    eBudgetZero := 2,   // 当月预算非正，占用率不可算（故障级）/ current month budget not positive, occupancy not computable
    eNegDelta   := 3,   // 负增量已忽略（信息级，不置故障）/ negative increment ignored, informational without a fault
    eBadDelta   := 4    // 增量非有限已忽略（信息级，不置故障）/ non-finite increment ignored, informational without a fault
);
END_TYPE

FUNCTION_BLOCK FB_DL_EnergyMonthPreset
VAR_INPUT
    bEnable          : BOOL := TRUE;         // 使能，下降沿冻结累计并按使能沿重建 / enable, falling edge freezes accumulation, the rising edge rebuilds it
    bReset           : BOOL := FALSE;         // 复位上升沿清当月累计与告警 [-] / reset rising edge clears the monthly accumulation and alarms
    nYear            : INT := 2026;           // 当前年份 [年]，域 2000..2100 / current year [year], domain 2000 to 2100
    nMonth           : INT := 1;              // 当前月份 [月]，域 1..12 / current month [month], domain 1 to 12
    nDayOfMonth      : INT := 1;              // 当月第几日 [日]，域 1..31 / day of month [day], domain 1 to 31
    bEnergyPulse     : BOOL := FALSE;         // 能耗增量脉冲，上升沿计入一次 [-] / energy increment pulse, counted once on the rising edge
    fEnergyDeltaKwh  : REAL := 0.0;           // 单次脉冲的能耗增量 [千瓦时] / energy increment per pulse [kilowatt hour]
    fBudgetOverrideKwh: REAL := 0.0;          // 预算覆盖值，大于零时取代预置表 [千瓦时] / budget override, replaces the table when positive [kilowatt hour]
    fWarnPct         : REAL := 90.0;          // 预警阈，占预算百分比 [百分比] / warning threshold as a percentage of the budget [percent]
    fCritPct         : REAL := 95.0;          // 临界阈，占预算百分比 [百分比] / critical threshold as a percentage of the budget [percent]
END_VAR
VAR_IN_OUT
    afMonthBudgetKwh : ARRAY[1..12] OF REAL;  // 12 个月预算预置表，下标即月份 [千瓦时]，引用型入参由调用方持有 / twelve month budget preset table, subscript is the month [kilowatt hour], reference parameter owned by the caller
END_VAR
VAR_OUTPUT
    fUsedKwh         : REAL := 0.0;           // 当月已用能耗 [千瓦时] / energy used in the current month [kilowatt hour]
    fBudgetKwh       : REAL := 0.0;           // 当月生效预算 [千瓦时] / effective budget of the current month [kilowatt hour]
    fRemainKwh       : REAL := 0.0;           // 当月剩余预算 [千瓦时]，可为负 / remaining budget of the current month, may be negative [kilowatt hour]
    fUsedPct         : REAL := 0.0;           // 当月预算占用百分比 [百分比] / monthly budget occupancy [percent]
    fDailyAvgKwh     : REAL := 0.0;           // 当月日均能耗 [千瓦时每日] / month to date daily average energy [kilowatt hour per day]
    fProjMonthKwh    : REAL := 0.0;           // 按日均推算的月末能耗 [千瓦时] / month end projection from the daily average [kilowatt hour]
    eLevel           : E_DL_EngLevel := E_DL_EngLevel.eNormal; // 预算级别出口 [枚举] / budget level outlet [enum]
    bWarn            : BOOL := FALSE;         // 预警及以上标志 [-] / warning and above flag
    bOver            : BOOL := FALSE;         // 超限标志 [-] / over budget flag
    bMonthRoll       : BOOL := FALSE;         // 跨月换表单拍脉冲 [-] / month rollover single-shot pulse
    nMonthActive     : INT := 0;              // 当前生效月份 [月] / currently active month [month]
    eCause           : E_DL_EngCause := E_DL_EngCause.eNone; // 成因出口 [枚举] / cause outlet [enum]
    bError           : BOOL := FALSE;         // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtEnergy         : R_TRIG;                // 能耗脉冲沿检测，段 0 无条件刷新 / energy pulse edge detector, refreshed unconditionally in segment zero
    rtReset          : R_TRIG;                // 复位沿检测，段 0 无条件刷新 / reset edge detector, refreshed unconditionally in segment zero
    _eLevel          : E_DL_EngLevel := E_DL_EngLevel.eNormal;  // 内部级别，锁存至下拍重算 / internal level, recomputed every scan
    _eCause          : E_DL_EngCause := E_DL_EngCause.eNone;   // 内部信息级成因，每拍重算 / internal informational cause, recomputed every scan
    _eFaultCause     : E_DL_EngCause := E_DL_EngCause.eNone;   // 内部故障级成因，锁存至复位沿 / internal fault cause, latched until the reset edge
    _bFault          : BOOL := FALSE;         // 故障锁存位（组态类成因）/ fault latch bit for configuration causes
    _bMonthRollInt   : BOOL := FALSE;         // 跨月脉冲内部位，统一出口映射 / internal rollover pulse bit, mapped at the unified outlet
    _bInit           : BOOL := FALSE;         // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bMonthOk        : BOOL := FALSE;         // 年/月/日域闸通过 [-] / year, month and day domain gate passed
    _bDeltaUsable    : BOOL := FALSE;         // 本拍增量可计入 [-] / this scan increment is countable
    _bNegDelta       : BOOL := FALSE;         // 本拍增量为负 [-] / this scan increment is negative
    _bBadDelta       : BOOL := FALSE;         // 本拍增量非有限 [-] / this scan increment is non-finite
    _bDayOk          : BOOL := FALSE;         // 当日序号可用于日均分母 [-] / day index usable as the daily divisor
    _nYearPrev       : INT := 0;              // 上一拍年份快照 [年] / previous scan year snapshot [year]
    _nMonthPrev      : INT := -1;             // 上一拍月份快照，初值 -1 保证首拍必换表 [月] / previous scan month snapshot, minus one forces a rollover on the first scan
    _nMonthUse       : INT := 1;              // 钳定后的月份 [月] / clamped month [month]
    _nDayUse         : INT := 1;              // 钳定后的当日序号 [日] / clamped day index [day]
    _nDaysInMonth    : INT := 30;             // 当月日历天数 [日] / calendar days of the current month [day]
    _fBudgetUse      : REAL := 0.0;           // 生效预算暂存 [千瓦时] / effective budget held in a local [kilowatt hour]
    _fDeltaUse       : REAL := 0.0;           // 本拍计入的增量 [千瓦时] / increment actually counted this scan [kilowatt hour]
    _fUsed           : REAL := 0.0;           // 累计已用量保持块 [千瓦时] / accumulated energy holder [kilowatt hour]
    _fUsedAcc        : REAL := 0.0;           // 累计已用量工作值 [千瓦时] / accumulated energy working value [kilowatt hour]
    _fPct            : REAL := 0.0;           // 占用率工作值 [百分比] / occupancy working value [percent]
    _fRemain         : REAL := 0.0;           // 剩余量工作值 [千瓦时] / remaining working value [kilowatt hour]
    _fDaily          : REAL := 0.0;           // 日均工作值 [千瓦时每日] / daily average working value [kilowatt hour per day]
    _fProj           : REAL := 0.0;           // 月末预测工作值 [千瓦时] / projection working value [kilowatt hour]
    _fDayDiv         : REAL := 1.0;           // 日均除子（当日序号）[日] / daily divisor, the day index [day]
END_VAR
VAR CONSTANT
    DL_EMP_WARNPCT_MIN : REAL := 1.0;         // 预警阈下限 [百分比] / warning threshold floor [percent]
    DL_EMP_CRITPCT_MAX : REAL := 100.0;       // 临界阈上限 [百分比] / critical threshold ceiling [percent]
    DL_EMP_USED_MAX    : REAL := 1.0E12;      // 已用量上限，防累计溢出失真 [千瓦时] / used energy ceiling against accumulation distortion [kilowatt hour]
    DL_EMP_DELTA_MAX   : REAL := 1.0E7;       // 单次增量上限，防量纲错配放大 [千瓦时] / single increment ceiling against a dimension mismatch [kilowatt hour]
    DL_EMP_DAY_MAX     : INT := 31;           // 月内最大天数 [日] / maximum days within a month [day]
    DL_EMP_YEAR_MIN    : INT := 2000;         // 年份下限 [年] / year floor [year]
    DL_EMP_YEAR_MAX    : INT := 2100;         // 年份上限 [年] / year ceiling [year]
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支）/ segment 0, unconditional refresh of the edge detectors, never inside a branch
rtEnergy(CLK := bEnergyPulse); // 能耗脉冲沿无条件刷新 / unconditional refresh of the energy pulse edge
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge

// 段 1｜首扫初始化（R310）：月份快照置 -1 使首拍必走一次换表 / segment 1, first scan initialisation, the month snapshot at minus one forces one rollover on the first scan
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _nMonthPrev := -1; // 月份快照置非法值 / put the month snapshot at an illegal value
    _nYearPrev := 0; // 年份快照清零 / clear the year snapshot
    _fUsed := 0.0; // 已用量清零 / clear the accumulated energy
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _eCause := E_DL_EngCause.eNone; // 信息级成因清零 / clear the informational cause
    _eFaultCause := E_DL_EngCause.eNone; // 故障级成因清零 / clear the fault cause
END_IF

// 段 2｜域闸：年月日、阈值对、预置表逐项（R151 全覆盖）/ segment 2, domain gate over year, month, day, the threshold pair and the preset table
_bMonthOk := TRUE; // 域闸标志预置通过 / preset the domain gate flag to passed
IF (nYear < DL_EMP_YEAR_MIN) OR (nYear > DL_EMP_YEAR_MAX) THEN // 年份越域 / year out of domain
    _bMonthOk := FALSE; // 判越域 / mark out of domain
END_IF
IF (nMonth < 1) OR (nMonth > 12) THEN // 月份越域 / month out of domain
    _bMonthOk := FALSE; // 判越域 / mark out of domain
END_IF
IF (nDayOfMonth < 1) OR (nDayOfMonth > DL_EMP_DAY_MAX) THEN // 当日序号越域 / day index out of domain
    _bMonthOk := FALSE; // 判越域 / mark out of domain
END_IF
IF (fWarnPct < DL_EMP_WARNPCT_MIN) OR (fWarnPct > DL_EMP_CRITPCT_MAX) OR (fWarnPct <> fWarnPct) THEN // 预警阈越域或非有限 / warning threshold out of domain or non-finite
    _bMonthOk := FALSE; // 判越域 / mark out of domain
END_IF
IF (fCritPct < fWarnPct) OR (fCritPct > DL_EMP_CRITPCT_MAX) OR (fCritPct <> fCritPct) THEN // 临界阈低于预警阈或越域 / critical threshold below the warning threshold or out of domain
    _bMonthOk := FALSE; // 判越域 / mark out of domain
END_IF
IF (fBudgetOverrideKwh <> fBudgetOverrideKwh) OR (fBudgetOverrideKwh < 0.0) THEN // 预算覆盖值非有限或为负 / budget override non-finite or negative
    _bMonthOk := FALSE; // 判越域 / mark out of domain
END_IF
IF _bMonthOk THEN // 域内才可安全读预置表 / the preset table is only read inside the domain
    _nMonthUse := nMonth; // 月份直通 / month passes through
    _nDayUse := nDayOfMonth; // 当日序号直通 / day index passes through
ELSE // 域外走两级回退（R117）/ out of domain uses the two stage fallback
    _nMonthUse := 1; // 一级：月份回默认一 / stage one, the month falls back to one
    _nDayUse := 1; // 一级：当日回默认一 / stage one, the day falls back to one
    IF NOT _bFault THEN // 未锁存才记故障 / record the fault only when not yet latched
        _eFaultCause := E_DL_EngCause.eCfgIllegal; // 故障级成因记组态非法 / record the illegal configuration cause
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
    END_IF
END_IF

// 段 3｜换表判据：年或月任一变化即换表，首拍必换；同年同月不重复换表 / segment 3, rollover when the year or the month changed, mandatory on the first scan
IF (_nMonthUse <> _nMonthPrev) OR (nYear <> _nYearPrev) THEN // 跨月或跨年 / month or year changed
    _nMonthPrev := _nMonthUse; // 月份快照推进 / advance the month snapshot
    _nYearPrev := nYear; // 年份快照推进 / advance the year snapshot
    _fUsed := 0.0; // 换表清零当月累计 / clear the monthly accumulation on rollover
    _bMonthRollInt := TRUE; // 跨月脉冲内部位置位（出口映射后撤销）/ raise the internal rollover bit, revoked after outlet mapping
    _eCause := E_DL_EngCause.eNone; // 换表清信息级成因（跨月是正常事件）/ clear the informational cause, a rollover is a normal event
END_IF

// 段 4｜预算取值：覆盖值优先，其次预置表；两项都非正判故障 / segment 4, effective budget, the override first and the preset table second, both non-positive is a fault
_fBudgetUse := 0.0; // 生效预算预置零 / preset the effective budget to zero
IF fBudgetOverrideKwh > 0.0 THEN // 覆盖值生效 / the override is effective
    _fBudgetUse := fBudgetOverrideKwh; // 取覆盖值 / take the override
ELSE // 覆盖值未给 / the override is absent
    _fBudgetUse := afMonthBudgetKwh[_nMonthUse]; // 按钳定月份取预置值，下标 1..12 已回钳 / read the preset by the clamped month, the index is already inside one through twelve
END_IF
IF (_fBudgetUse <> _fBudgetUse) OR ((_fBudgetUse - _fBudgetUse) <> (_fBudgetUse - _fBudgetUse)) THEN // 预算非有限 / budget non-finite
    _fBudgetUse := 0.0; // 非有限归零，绝不进除法 / zeroed so nothing non-finite enters a division
END_IF
IF _fBudgetUse <= 0.0 THEN // 预算非正 / budget not positive
    IF NOT _bFault THEN // 未锁存才记故障 / record the fault only when not yet latched
        _eFaultCause := E_DL_EngCause.eBudgetZero; // 故障级成因记预算非正 / record the non-positive budget cause
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
    END_IF
END_IF

// 段 5｜增量计入：仅上升沿、仅有限、仅非负；负与非有限各记信息级成因 / segment 5, increment only on the rising edge, only finite, only non-negative
_bDeltaUsable := FALSE; // 可计入标志预置假 / preset the countable flag to false
_bNegDelta := FALSE; // 负增量标志预置假 / preset the negative increment flag to false
_bBadDelta := FALSE; // 非有限增量标志预置假 / preset the non-finite increment flag to false
_fDeltaUse := 0.0; // 本拍计入量预置零 / preset the counted increment to zero
IF rtEnergy.Q THEN // 脉冲上升沿 / rising edge of the pulse
    IF (fEnergyDeltaKwh <> fEnergyDeltaKwh) OR ((fEnergyDeltaKwh - fEnergyDeltaKwh) <> (fEnergyDeltaKwh - fEnergyDeltaKwh)) THEN // 增量非有限 / increment non-finite
        _bBadDelta := TRUE; // 置非有限标志 / raise the non-finite flag
    ELSIF fEnergyDeltaKwh < 0.0 THEN // 增量为负（表计回卷或换表）/ increment negative, meter rollback or replacement
        _bNegDelta := TRUE; // 置负增量标志 / raise the negative flag
    ELSIF fEnergyDeltaKwh > DL_EMP_DELTA_MAX THEN // 增量越上限 / increment above the ceiling
        _fDeltaUse := DL_EMP_DELTA_MAX; // 上钳，防量纲错配放大 / clamp upward against a dimension mismatch
        _bDeltaUsable := TRUE; // 置可计入标志 / raise the countable flag
    ELSE // 正常增量 / normal increment
        _fDeltaUse := fEnergyDeltaKwh; // 直通计入 / counted as received
        _bDeltaUsable := TRUE; // 置可计入标志 / raise the countable flag
    END_IF
END_IF
_eCause := E_DL_EngCause.eNone; // 信息级成因每拍重算 / the informational cause is recomputed every scan
IF _bNegDelta THEN // 负增量拍 / negative increment scan
    _eCause := E_DL_EngCause.eNegDelta; // 信息级成因，不置故障（R45 反向：信息级不配对 bError）/ informational cause without a fault
ELSIF _bBadDelta THEN // 非有限增量拍 / non-finite increment scan
    _eCause := E_DL_EngCause.eBadDelta; // 信息级成因，不置故障 / informational cause without a fault
END_IF

// 段 6｜累计与复位：复位沿清当月累计；累计上限饱和并置信息级成因 / segment 6, accumulation and reset, with saturation at the ceiling
_fUsedAcc := _fUsed; // 工作值取保持值 / the working value takes the holder
IF rtReset.Q THEN // 复位沿 / reset edge
    _fUsedAcc := 0.0; // 当月累计清零 / clear the monthly accumulation
END_IF
IF _bDeltaUsable THEN // 本拍有可计入增量 / a countable increment exists this scan
    _fUsedAcc := _fUsedAcc + _fDeltaUse; // 累加 / accumulate
    IF _fUsedAcc > DL_EMP_USED_MAX THEN // 累计越上限 / accumulation above the ceiling
        _fUsedAcc := DL_EMP_USED_MAX; // 饱和到上限 / saturate at the ceiling
    END_IF
END_IF
IF NOT bEnable THEN // 失能：冻结保持末值（R191 显式声明）/ disabled, freeze and hold the last value as declared
    _fUsedAcc := _fUsed; // 冻结保持，不再累加 / freeze and hold without further accumulation
END_IF
_fUsed := _fUsedAcc; // 保持块更新 / refresh the holder

// 段 7｜日历天数与日均：闰年二月按 29 日；除子先域闸 / segment 7, calendar days and daily average, the divisor is gated first
_nDaysInMonth := 31; // 默认 31 日 / default thirty one days
CASE _nMonthUse OF
1, 3, 5, 7, 8, 10, 12: // 大月 / long months
    _nDaysInMonth := 31; // 三十一日 / thirty one days
2: // 二月 / february
    IF ((nYear MOD 4) = 0) AND (((nYear MOD 100) <> 0) OR ((nYear MOD 400) = 0)) THEN // 闰年判据 / leap year criterion
        _nDaysInMonth := 29; // 闰年二月二十九日 / twenty nine days in a leap year
    ELSE
        _nDaysInMonth := 28; // 平年二月二十八日 / twenty eight days in a common year
    END_IF
4, 6, 9, 11: // 小月 / short months
    _nDaysInMonth := 30; // 三十日 / thirty days
ELSE // 非法月份兜底（R128）/ illegal month fallback
    _nDaysInMonth := 30; // 兜底三十日 / fall back to thirty days
END_CASE
_bDayOk := (_nDayUse >= 1) AND (_nDayUse <= _nDaysInMonth); // 当日序号在日历域内 / the day index is inside the calendar domain
IF _bDayOk THEN // 除子可用 / the divisor is usable
    _fDayDiv := _nDayUse; // 除子取当日序号，已证 不小于 1 / the divisor takes the day index, proven not below one
ELSE
    _fDayDiv := 1.0; // 回退为 1，防除零 / fall back to one against division by zero
END_IF

// 段 8｜占用率与分级：预算非正时不计算占用率，级别保持上拍 / segment 8, occupancy and grading, skipped when the budget is not positive
IF _fBudgetUse > 0.0 THEN // 预算可用 / the budget is usable
    _fPct := _fUsed / _fBudgetUse * 100.0; // 占用率，除子已证大于零 / occupancy, divisor proven positive
    _fRemain := _fBudgetUse - _fUsed; // 剩余量（可为负）/ remaining budget, may be negative
    _fDaily := _fUsed / _fDayDiv; // 日均能耗，除子已证不小于 1 / daily average, divisor proven not below one
    _fProj := _fDaily * INT_TO_REAL(_nDaysInMonth); // 月末预测，乘数为日历天数 / month end projection over the calendar days
    IF _fPct >= 100.0 THEN // 越过全额 / beyond the full budget
        _eLevel := E_DL_EngLevel.eOver; // 超限级 / over level
    ELSIF _fPct >= fCritPct THEN // 达临界阈 / reached the critical threshold
        _eLevel := E_DL_EngLevel.eCrit; // 临界级 / critical level
    ELSIF _fPct >= fWarnPct THEN // 达预警阈 / reached the warning threshold
        _eLevel := E_DL_EngLevel.eWarn; // 预警级 / warning level
    ELSE
        _eLevel := E_DL_EngLevel.eNormal; // 正常级 / normal level
    END_IF
END_IF

// 段 9｜统一出口：脉冲映射、名实双出口、故障与级别落定 / segment 9, unified outlet for the pulse, the matched flags and the level
bMonthRoll := _bMonthRollInt; // 跨月脉冲映射本拍值 / map the rollover pulse for this scan
_bMonthRollInt := FALSE; // 映射后立即撤销，保证单拍宽度（R187 两段式）/ revoke right after mapping to keep a single-scan width
fUsedKwh := _fUsed; // 已用量出口 / used energy outlet
fBudgetKwh := _fBudgetUse; // 生效预算出口 / effective budget outlet
fRemainKwh := _fRemain; // 剩余量出口 / remaining budget outlet
fUsedPct := _fPct; // 占用率出口 / occupancy outlet
fDailyAvgKwh := _fDaily; // 日均出口 / daily average outlet
fProjMonthKwh := _fProj; // 月末预测出口 / projection outlet
eLevel := _eLevel; // 级别出口单点映射 / single-point level outlet mapping
bWarn := (_eLevel = E_DL_EngLevel.eWarn) OR (_eLevel = E_DL_EngLevel.eCrit) OR (_eLevel = E_DL_EngLevel.eOver); // 预警及以上（挂状态量）/ warning and above, a state quantity
bOver := (_eLevel = E_DL_EngLevel.eOver); // 超限（挂状态量）/ over budget, a state quantity
nMonthActive := _nMonthUse; // 生效月份出口 / active month outlet
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eCause := _eFaultCause; // 故障级成因锁存回放（禁按当下输入重推断）/ the fault cause is replayed from the latch
ELSE
    eCause := _eCause; // 信息级成因直映 / the informational cause is mapped directly
END_IF
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
