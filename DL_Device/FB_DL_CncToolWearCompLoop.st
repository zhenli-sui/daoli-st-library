(*
  DL Factory R84 | FB_DL_CncToolWearCompLoop
  功能：CNC 刀具后刀面磨损量 VB 在线估计与刀补闭环：按切削路程三段线性磨损曲线出 VB 原值，按切削比能调制滤波增益做一阶指数平滑得 VB 估计，超补偿门限按增量限幅出刀补，超寿命锁存换刀请求。
  开源溯源：无（clean-room 自研，依据公开工艺公式与安全设计惯例，来源=行业通用公式+工程实践，许可证=MIT，借鉴点=公式结构与联锁分层）
  规则：R1-R16 全遵守
  ------------------------------------------------------------------
  分类 DL_Device ｜ 复杂度 cx4 ｜ 版本 v1.0.0 ｜ 平台 纯 IEC 61131-3（LREAL、ENUM、CASE）
  边界一：只出刀补增量与换刀请求，不驱动伺服轴、不写 CNC 刀补表（落表由上层 PRG 执行，属主边界）。
  边界二：磨损曲线为三段线性——初期占额定寿命路程 0.15 段、占磨损余量 0.30 份；稳态占 0.70 段、占 0.55 份；
          急剧占余下 0.15 段、占余下 0.15 份；三段积分在路程等于额定寿命处恰等于 VB 限值（量纲自检见下）。
  边界三：切削路程按「进给率 × 切削时长增量」积分，时长增量取 fCutTimeS 的上拍快照差分（R45 ②）；
          负增量判零、超大跳变钳到 1 秒，防掉电恢复的时钟跳变伪造路程。
  边界四：工艺代理常量——DL_CNC_AP_MM 与 DL_CNC_AE_MM 为名义切深与切宽代理值（本件无切深切宽引脚）；
          代理值是名义切深切宽、覆盖常规铣削 0.2~3 mm 切深与 4~20 mm 切宽区间、区间外的重型切槽工况由上层
          按实际切深切宽折算 fKcNmm2 后下发（R95 三句齐备，代理假设挂编译验证债）。
  边界五：无效拍语义——功率或转速为零、或任一浮点入参非有限 → xValid 出假、相位保持、刀补增量出零；
          不推进滤波、不累加路程（不除零、不外推）。
  边界六：换刀请求 xChangeReq 为锁存式，唯一解除路径为 bReset 上升沿（R188）；xAlarm 为电平式跟随相位。
  量纲自检：VB [mm]＝斜率 [mm/m] × 路程 [m]；斜率一 ＝ VB限值 × 0.30 ÷（额定寿命 × 0.15）[mm/m]；
          路程增量 [m]＝进给 [mm/min] × 时长增量 [s] ÷ 60 [s/min] × 0.001 [m/mm]；
          切削功率 [kW]＝Kc [N/mm²] × 切除率 [mm³/s] ÷ 1000 [W/kW]；
          切除率 [mm³/s]＝进给 [mm/s] × 切深 [mm] × 切宽 [mm]；刀补 [µm]＝VB [mm] × 1000 [µm/mm]。
  码表：本件全部码位为信息级（2601 非法相位、2602 组态越域、2603 入参非有限、2604 转速或功率为零）；
        信息级码每拍重算且不置 bError；故障级语义由 xChangeReq 锁存位承担，故本件无 bError 出口（R187）。
  输出契约：fCompUm 为本次刀补增量 [µm]（限幅 ±50，非补偿相出 0 不保持）；fCompAccUm 为累计刀补 [µm]（0~200 单向）；
          fVbEst 为滤波后估计 [mm]；fVbRaw 为曲线原值 [mm]；iErrCode 信息级，非零时 xValid 恒假。
  修订记录：2026-11-24 v1.0.0 R84 首版（批 R84 · 序号 41）
*)

TYPE E_DL_CncWearState :
(
    eIdle       := 0,  // 空闲：等使能与切削条件 / idle, waiting for the enable and the cutting condition
    eLearn      := 10, // 学习：累加路程并收敛 VB 滤波 / learning, accumulate the path and settle the filter
    eCompensate := 20, // 补偿：VB 超补偿门限，按增量出刀补 / compensating, the wear passed the trigger threshold
    eAlarm      := 30, // 报警：VB 超报警门限，继续补偿并报警 / alarm, the wear passed the alarm threshold
    eChangeReq  := 40  // 换刀请求：VB 超寿命，锁存至复位沿 / change request, the wear passed the life limit and is latched
);
END_TYPE

TYPE E_DL_CncWearCause :
(
    eNone      := 0, // 无成因 / no cause
    ePhaseBad  := 1, // 非法相位（信息级 2601）/ illegal phase, info grade 2601
    eCfgBad    := 2, // 组态越域（信息级 2602）/ the configuration is out of its domain, info grade 2602
    eNotFinite := 3, // 入参非有限（信息级 2603）/ a non-finite input, info grade 2603
    eSpeedZero := 4  // 转速或功率为零（信息级 2604）/ the speed or the power is zero, info grade 2604
);
END_TYPE

FUNCTION_BLOCK FB_DL_CncToolWearCompLoop
VAR CONSTANT
    DL_CNC_PH1_FRAC   : LREAL := 0.15;    // 初期磨损段占额定寿命的路程分数 [-] / the initial wear path fraction of the rated life [-]
    DL_CNC_PH1_WEAR   : LREAL := 0.30;    // 初期磨损段占磨损余量的份额 [-] / the initial wear share of the allowance [-]
    DL_CNC_PH2_FRAC   : LREAL := 0.70;    // 稳态磨损段占额定寿命的路程分数 [-] / the steady wear path fraction of the rated life [-]
    DL_CNC_PH2_WEAR   : LREAL := 0.55;    // 稳态磨损段占磨损余量的份额 [-] / the steady wear share of the allowance [-]
    DL_CNC_ALARM_FRAC : LREAL := 0.85;    // 报警门限回退系数（组态越域时用）[-] / the alarm threshold fallback factor [-]
    DL_CNC_HYST_BAND  : LREAL := 0.02;    // 报警相回补偿相的回差带（VB 限值倍数）[-] / the hysteresis band for the alarm exit [-]
    DL_CNC_ALPHA_MIN  : LREAL := 0.02;    // 滤波增益下限（防迟钝）[-] / the filter gain lower bound [-]
    DL_CNC_ALPHA_MAX  : LREAL := 0.50;    // 滤波增益上限（防抖动）[-] / the filter gain upper bound [-]
    DL_CNC_ALPHA_SPAN : LREAL := 0.50;    // 比能超出量归一跨度（比能比 - 1 的满量程）[-] / the normalised span of the specific energy excess [-]
    DL_CNC_PWR_GAIN   : LREAL := 0.80;    // 比能超基准对磨损的加速增益 [-] / the specific energy excess gain on the wear [-]
    DL_CNC_ACCEL_MAX  : LREAL := 3.00;    // 加速因子上限 [-] / the acceleration factor upper bound [-]
    DL_CNC_RATIO_BAND : LREAL := 0.02;    // 比能比值的容差带（浮点比较）[-] / the specific energy ratio tolerance band [-]
    DL_CNC_VB_HEAD    : LREAL := 2.00;    // VB 估计上限（VB 限值倍数，防过冲）[-] / the VB estimate headroom over the limit [-]
    DL_CNC_STEP_UM    : LREAL := 50.0;    // 单次刀补增量限幅 [µm] / the per-scan compensation step limit [um]
    DL_CNC_ACC_UM     : LREAL := 200.0;   // 累计刀补上限 [µm] / the accumulated compensation upper limit [um]
    DL_CNC_UM_PER_MM  : LREAL := 1000.0;  // 毫米到微米折算系数 [µm/mm] / the millimetre to micrometre factor [um/mm]
    DL_CNC_M_PER_MM   : LREAL := 0.001;   // 毫米到米折算系数 [m/mm] / the millimetre to metre factor [m/mm]
    DL_CNC_SEC_MIN    : LREAL := 60.0;    // 秒到分钟折算系数 [s/min] / the second to minute factor [s/min]
    DL_CNC_W_PER_KW   : LREAL := 1000.0;  // 瓦到千瓦折算系数 [W/kW] / the watt to kilowatt factor [W/kW]
    DL_CNC_DTJUMP_S   : LREAL := 1.0;     // 切削时长增量上限（时钟跳变钳位）[s] / the cutting time increment upper clamp [s]
    DL_CNC_AP_MM       : LREAL := 1.0;    // 名义轴向切深代理值 [mm] / the nominal axial depth of cut proxy [mm]
    DL_CNC_AE_MM       : LREAL := 10.0;   // 名义径向切宽代理值 [mm] / the nominal radial width of cut proxy [mm]
    DL_CNC_EPS         : LREAL := 1.0E-9; // 除法零闸与零判定门限 [-] / the division guard and zero test threshold [-]
END_VAR
VAR_INPUT
    bEnable        : BOOL := TRUE;    // 使能，失能回空闲且刀补增量归零 [-] / enable, a disable returns to idle with the step zeroed
    bReset         : BOOL := FALSE;   // 复位上升沿清换刀请求锁存 [-] / reset rising edge clears the change request latch
    bCutting       : BOOL := FALSE;   // 切削中，为真才累加切削路程 [-] / cutting active, the path accumulates only while true
    fSpindleKw     : LREAL := 0.0;    // 主轴有功功率 [kW] / the spindle active power [kW]
    fFeedMmMin     : LREAL := 0.0;    // 进给率 [mm/min] / the feed rate [mm/min]
    fRpm           : LREAL := 0.0;    // 主轴转速 [r/min] / the spindle speed [r/min]
    fCutTimeS      : LREAL := 0.0;    // 本刀具累计切削时长（由上层保持）[s] / the accumulated cutting time of the tool [s]
    fKcNmm2        : LREAL := 2000.0; // 材料单位切削力系数 [N/mm²] / the specific cutting force coefficient [N/mm^2]
    fVbLimitMm     : LREAL := 0.30;   // 后刀面磨损量限值（换刀门限）[mm] / the flank wear limit, the change threshold [mm]
    fLifePathM     : LREAL := 8000.0; // 刀具额定寿命切削路程 [m] / the rated cutting path of the tool life [m]
    fIdleKw        : LREAL := 0.5;    // 主轴空载功率（扣除项）[kW] / the spindle idle power to be deducted [kW]
    fVbCompTrigMm  : LREAL := 0.15;   // 补偿启动门限 [mm] / the compensation trigger threshold [mm]
    fVbAlarmMm     : LREAL := 0.25;   // 报警门限 [mm] / the alarm threshold [mm]
END_VAR
VAR_OUTPUT
    fVbEst      : LREAL := 0.0;   // 滤波后磨损量估计 [mm] / the filtered wear estimate [mm]
    fVbRaw      : LREAL := 0.0;   // 磨损曲线原值（未滤波）[mm] / the raw wear from the piecewise curve [mm]
    fCompUm     : LREAL := 0.0;   // 本次刀补增量 [µm] / the compensation increment of this scan [um]
    fCompAccUm  : LREAL := 0.0;   // 累计刀补量 [µm] / the accumulated compensation [um]
    fPathM      : LREAL := 0.0;   // 累计切削路程 [m] / the accumulated cutting path [m]
    fKcRatio    : LREAL := 1.0;   // 实测比能比（切削功率 ÷ 名义切削功率）[-] / the measured specific energy ratio [-]
    xChangeReq  : BOOL := FALSE;  // 换刀请求（锁存式，复位沿清除）[-] / the change request, latched until the reset edge
    xAlarm      : BOOL := FALSE;  // 磨损报警（电平式）[-] / the wear alarm, level type
    eState      : E_DL_CncWearState := E_DL_CncWearState.eIdle; // 相位出口 [枚举] / the phase outlet [enum]
    iErrCode    : INT := 0;       // 信息级码（每拍重算，非锁存）[码] / the info grade code, recomputed every scan [code]
    xValid      : BOOL := FALSE;  // 本拍估计可信（判据全通过）[-] / the estimate is trustworthy this scan [-]
END_VAR
VAR
    rtReset : R_TRIG; // 复位上升沿实例（R188：电平复位会导致按住即反复清零） [-] / reset rising edge instance [-]
    _eState     : E_DL_CncWearState := E_DL_CncWearState.eIdle; // 内部相位（枚举，无量纲）[-] / the internal phase, the only CASE target
    _bInit      : BOOL := FALSE;  // 首扫初始化完成标志（R310）[-] / the first scan initialisation flag [-]
    _bFinOk     : BOOL := FALSE;  // 全部浮点入参有限 [-] / every floating input is finite
    _bCfgOk     : BOOL := FALSE;  // 组态参数域内 [-] / the configuration is inside its domain
    _bSpeedOk   : BOOL := FALSE;  // 转速与功率非零（防除零）[-] / the speed and the power are non zero
    _bValid     : BOOL := FALSE;  // 三个闸的合取 [-] / the conjunction of the three gates
    _bChangeLch : BOOL := FALSE;  // 换刀请求锁存位（唯一清除：复位沿）[-] / the change request latch, cleared by the reset edge only
    _iErrTmp    : INT := 0;       // 本拍信息级码暂存 [码] / the scan info code scratch [code]
    _fCutPrevS  : LREAL := 0.0;   // 上拍切削时长快照（差分用）[s] / the previous scan cutting time snapshot [s]
    _fDtCutS    : LREAL := 0.0;   // 切削时长增量（钳定后）[s] / the clamped cutting time increment [s]
    _fPathM     : LREAL := 0.0;   // 累计切削路程（跨批保持）[m] / the accumulated cutting path across batches [m]
    _fPnomKw    : LREAL := 0.0;   // 名义切削功率 [kW] / the nominal cutting power [kW]
    _fPcKw      : LREAL := 0.0;   // 实测净切削功率（扣除空载）[kW] / the measured net cutting power [kW]
    _fRatio     : LREAL := 1.0;   // 比能比（含域夹取）[-] / the specific energy ratio with clamping [-]
    _fExcess    : LREAL := 0.0;   // 比能超出量归一值 [0,1] [-] / the normalised specific energy excess [-]
    _fAlpha     : LREAL := 0.0;   // 本拍滤波增益（随比能自适应）[-] / the adaptive filter gain of this scan [-]
    _fSlope1    : LREAL := 0.0;   // 初期磨损段斜率 [mm/m] / the initial wear slope [mm/m]
    _fSlope2    : LREAL := 0.0;   // 稳态磨损段斜率 [mm/m] / the steady wear slope [mm/m]
    _fSlope3    : LREAL := 0.0;   // 急剧磨损段斜率 [mm/m] / the severe wear slope [mm/m]
    _fL1        : LREAL := 0.0;   // 初期磨损段终点路程 [m] / the initial wear segment end path [m]
    _fL2        : LREAL := 0.0;   // 稳态磨损段终点路程 [m] / the steady wear segment end path [m]
    _fAccel     : LREAL := 1.0;   // 比能加速因子 [-] / the specific energy acceleration factor [-]
    _fVbRaw     : LREAL := 0.0;   // 磨损曲线原值 [-] / the raw wear value [-]
    _fVbFilt    : LREAL := 0.0;   // 滤波后磨损量（保持槽，写入前过非有限闸）[mm] / the filtered wear, guarded before the write [mm]
    _fVbEst     : LREAL := 0.0;   // 本拍磨损估计 [mm] / the wear estimate of this scan [mm]
    _fAlarmMm   : LREAL := 0.0;   // 报警门限（两级回退后）[mm] / the alarm threshold after the two level fallback [mm]
    _fCompAcc   : LREAL := 0.0;   // 累计刀补量 [µm] / the accumulated compensation [um]
    _fCompTgt   : LREAL := 0.0;   // 目标累计刀补量 [µm] / the target accumulated compensation [um]
    _fStep      : LREAL := 0.0;   // 本拍刀补增量（限幅后）[µm] / the limited compensation step of this scan [um]
END_VAR
// 段 0｜出口预置：所有出口先赋安全侧值，任何早退路径不留未初始化输出
xValid := FALSE; // 有效性预置假（判据未完成前一律无效，安全侧）/ validity preset false on the safe side
xAlarm := FALSE; // 报警预置假 / the alarm preset false
xChangeReq := _bChangeLch; // 换刀请求回放锁存位 / replay the change request latch
fCompUm := 0.0; // 刀补增量预置零（非补偿相不出量）/ the step preset zero while not compensating
fVbEst := 0.0; // 估计预置零 / the estimate preset zero
fVbRaw := 0.0; // 原值预置零 / the raw value preset zero
fCompAccUm := _fCompAcc; // 累计刀补回放 / replay the accumulated compensation
fPathM := _fPathM; // 路程回放 / replay the path
fKcRatio := _fRatio; // 比能比回放 / replay the specific energy ratio
eState := _eState; // 相位回放 / replay the phase
iErrCode := 0; // 信息级码预置零（本拍重算）/ the info code preset zero, recomputed this scan
_iErrTmp := 0; // 单拍码暂存预清零（FB32-1：仅单拍标志可预清）/ preclear the scan code scratch only
// 段 1｜非有限闸：NaN 用自反比较、Inf 用差值自减双判，逐项枚举全部浮点入参（R79、R272）
_bFinOk := (fSpindleKw = fSpindleKw) AND ((fSpindleKw - fSpindleKw) = (fSpindleKw - fSpindleKw)) // 主轴功率有限 [-] / the spindle power is finite
    AND (fFeedMmMin = fFeedMmMin) AND ((fFeedMmMin - fFeedMmMin) = (fFeedMmMin - fFeedMmMin)) // 进给率有限 [-] / the feed rate is finite
    AND (fRpm = fRpm) AND ((fRpm - fRpm) = (fRpm - fRpm)) // 转速有限 [-] / the speed is finite
    AND (fCutTimeS = fCutTimeS) AND ((fCutTimeS - fCutTimeS) = (fCutTimeS - fCutTimeS)) // 切削时长有限 [-] / the cutting time is finite
    AND (fKcNmm2 = fKcNmm2) AND ((fKcNmm2 - fKcNmm2) = (fKcNmm2 - fKcNmm2)) // 切削力系数有限 [-] / the cutting force coefficient is finite
    AND (fVbLimitMm = fVbLimitMm) AND ((fVbLimitMm - fVbLimitMm) = (fVbLimitMm - fVbLimitMm)) // 磨损限值有限 [-] / the wear limit is finite
    AND (fLifePathM = fLifePathM) AND ((fLifePathM - fLifePathM) = (fLifePathM - fLifePathM)) // 额定寿命路程有限 [-] / the rated life path is finite
    AND (fIdleKw = fIdleKw) AND ((fIdleKw - fIdleKw) = (fIdleKw - fIdleKw)) // 空载功率有限 [-] / the idle power is finite
    AND (fVbCompTrigMm = fVbCompTrigMm) AND ((fVbCompTrigMm - fVbCompTrigMm) = (fVbCompTrigMm - fVbCompTrigMm)) // 补偿门限有限 [-] / the trigger threshold is finite
    AND (fVbAlarmMm = fVbAlarmMm) AND ((fVbAlarmMm - fVbAlarmMm) = (fVbAlarmMm - fVbAlarmMm)); // 报警门限有限 [-] / the alarm threshold is finite
// 段 2｜组态域闸：门限次序与正定性，参与判据换算的每个引脚都在闸内（R151）
_bCfgOk := (fVbLimitMm > 0.0) AND (fLifePathM > 0.0) AND (fKcNmm2 > 0.0) AND (fIdleKw >= 0.0) // 限值、寿命、系数、空载功率四项域闸 [-] / the four base domains
    AND (fVbCompTrigMm > 0.0) AND (fVbCompTrigMm < fVbLimitMm) // 补偿门限介于零与限值之间 [-] / the trigger sits between zero and the limit
    AND (fVbAlarmMm > fVbCompTrigMm) AND (fVbAlarmMm <= fVbLimitMm); // 报警门限高于补偿门限且不超限值 [-] / the alarm sits above the trigger and never above the limit
_bSpeedOk := (ABS(fRpm) > DL_CNC_EPS) AND (ABS(fSpindleKw) > DL_CNC_EPS); // 转速与功率非零闸（防除零，R4）/ the non zero gate against the division by zero
_bValid := _bFinOk AND _bCfgOk AND _bSpeedOk; // 三个闸合取 / the conjunction of the three gates
IF NOT _bFinOk THEN _iErrTmp := 2603; ELSIF NOT _bCfgOk THEN _iErrTmp := 2602; ELSIF NOT _bSpeedOk THEN _iErrTmp := 2604; END_IF // 信息级码分派（有限 → 组态 → 零速）/ the info code dispatch
// 段 3｜首扫初始化与复位沿同块，作用域逐项声明（R310、R311）
rtReset(CLK := bReset); // 复位沿无条件周期刷新（R7） [-] / the reset edge refreshed every scan [-]

IF (NOT _bInit) OR rtReset.Q THEN // 首扫一拍或复位上升沿（R188，禁电平复位） / the first scan or the reset edge
    _bInit := TRUE; // 首扫完成标志（复位沿重复置位同效）/ the first scan flag, the same effect on reset
    _bChangeLch := FALSE; // 作用域一：清换刀请求锁存（唯一清除边，R188）/ scope one, clear the change request latch
    _fVbFilt := 0.0; // 作用域二：清滤波保持槽 / scope two, clear the filter hold slot
    _fCompAcc := 0.0; // 作用域二：清累计刀补 / scope two, clear the accumulated compensation
    _fPathM := 0.0; // 作用域三：清切削路程（换刀后按新刀重计）/ scope three, clear the path for the new tool
    _fCutPrevS := fCutTimeS; // 作用域三：时长快照重取（防跨批假路程）/ scope three, re-take the snapshot
    _eState := E_DL_CncWearState.eIdle; // 作用域二：迁回空闲相 / scope two, migrate to idle
END_IF
// 段 4｜切削路程积分：时长增量差分 + 双向钳定，仅有效拍且切削中累加（R45 ②）
_fDtCutS := fCutTimeS - _fCutPrevS; // 切削时长增量 [s] / the cutting time increment [s]
IF _fDtCutS < 0.0 THEN _fDtCutS := 0.0; END_IF // 负增量判零（时钟回退不伪造路程）/ a negative increment is zeroed
IF _fDtCutS > DL_CNC_DTJUMP_S THEN _fDtCutS := DL_CNC_DTJUMP_S; END_IF // 超大跳变钳位（掉电恢复不伪造路程）/ a huge jump is clamped
IF _bValid AND bCutting THEN // 仅有效拍且切削中 / only on a valid scan while cutting
    _fPathM := _fPathM + fFeedMmMin * (_fDtCutS / DL_CNC_SEC_MIN) * DL_CNC_M_PER_MM; // 路程增量 [m] / the path increment [m]
END_IF
_fCutPrevS := fCutTimeS; // 上拍时长快照（用完立即赋值，防重复累计）/ the snapshot taken right after the integration
// 段 5｜切削比能：名义功率由 Kc 与名义切除率折算（切深切宽取边界四之代理常量），分母显式零闸（R4）
IF _bValid THEN // 仅在有效拍计算比能 / compute the ratio on a valid scan only
    _fPnomKw := fKcNmm2 * (fFeedMmMin / DL_CNC_SEC_MIN) * DL_CNC_AP_MM * DL_CNC_AE_MM / (DL_CNC_W_PER_KW * 1000.0); // N/mm2·mm3/s = mW，再除以 1e6 得 kW（量纲校正，R583） / [N/mm2]*[mm3/s] = [mW], divided by 1e6 for [kW]
    _fPcKw := fSpindleKw - fIdleKw; // 净切削功率 [kW] / the net cutting power [kW]
    IF _fPcKw < 0.0 THEN _fPcKw := 0.0; END_IF // 负净功率夹取（空载波动）/ clamp the negative net power
    _fRatio := 1.0; // 比能比默认一（无切除按名义）/ the ratio defaults to one without stock removal
    IF (_fPnomKw > DL_CNC_EPS) AND (fFeedMmMin > DL_CNC_EPS) THEN // 双分母零闸 / both denominators guarded
        _fRatio := _fPcKw / _fPnomKw; // 比能比 [-] / the specific energy ratio [-]
    END_IF
    IF _fRatio < 0.2 THEN _fRatio := 0.2; ELSIF _fRatio > 3.0 THEN _fRatio := 3.0; END_IF // 比值域夹取，防加速因子发散 / clamp the ratio domain
END_IF
// 段 6｜三段线性磨损曲线：三段斜率由额定寿命与 VB 限值反算，积分在寿命终点恰为限值
IF _bCfgOk THEN // 组态域内才反算斜率（分母中含 fLifePathM，越域即除零）/ compute the slopes only inside the domain
    _fSlope1 := (fVbLimitMm * DL_CNC_PH1_WEAR) / (fLifePathM * DL_CNC_PH1_FRAC); // 初期段斜率 [mm/m] / the initial slope [mm/m]
    _fSlope2 := (fVbLimitMm * DL_CNC_PH2_WEAR) / (fLifePathM * DL_CNC_PH2_FRAC); // 稳态段斜率 [mm/m] / the steady slope [mm/m]
    _fSlope3 := (fVbLimitMm * (1.0 - DL_CNC_PH1_WEAR - DL_CNC_PH2_WEAR)) / (fLifePathM * (1.0 - DL_CNC_PH1_FRAC - DL_CNC_PH2_FRAC)); // 急剧段斜率 [mm/m] / the severe slope [mm/m]
    _fL1 := fLifePathM * DL_CNC_PH1_FRAC; // 初期段终点 [m] / the initial segment end [m]
    _fL2 := _fL1 + fLifePathM * DL_CNC_PH2_FRAC; // 稳态段终点 [m] / the steady segment end [m]
    IF _fPathM <= _fL1 THEN // 阶段一：初期磨损 / stage one, the initial wear
        _fVbRaw := _fSlope1 * _fPathM; // 初期段磨损 [mm] / the initial wear [mm]
    ELSIF _fPathM <= _fL2 THEN // 阶段二：稳态磨损（含初期段积分）/ stage two, the steady wear including the initial integral
        _fVbRaw := _fSlope1 * _fL1 + _fSlope2 * (_fPathM - _fL1); // 稳态段磨损 [mm] / the steady wear [mm]
    ELSE // 阶段三：急剧磨损 / stage three, the severe wear
        _fVbRaw := _fSlope1 * _fL1 + _fSlope2 * (_fL2 - _fL1) + _fSlope3 * (_fPathM - _fL2); // 急剧段磨损 [mm] / the severe wear [mm]
    END_IF
    IF _fRatio > (1.0 + DL_CNC_RATIO_BAND) THEN // 比能高于基准才加速 / accelerate only above the base
        _fAccel := 1.0 + DL_CNC_PWR_GAIN * (_fRatio - 1.0); // 加速因子 [-] / the acceleration factor [-]
    ELSE // 比能未超基准：不加速也不抑制 / no acceleration below the base
        _fAccel := 1.0; // 加速因子归一 / the factor is unity
    END_IF
    IF _fAccel > DL_CNC_ACCEL_MAX THEN _fAccel := DL_CNC_ACCEL_MAX; END_IF // 加速因子上限 / the factor upper bound
    _fVbRaw := _fVbRaw * _fAccel; // 比能修正后磨损 [mm] / the wear corrected by the specific energy
    IF _fVbRaw > (fVbLimitMm * DL_CNC_VB_HEAD) THEN _fVbRaw := fVbLimitMm * DL_CNC_VB_HEAD; END_IF // 上限兜底防过冲 / the upper bound against overshoot
END_IF
// 段 7｜一阶指数滤波：增益随比能超出量自适应（钝化加剧时跟随更快），写入前过非有限闸（R133）
_fExcess := (_fRatio - 1.0) / DL_CNC_ALPHA_SPAN; // 超出量归一 [-] / the normalised excess [-]
IF _fExcess < 0.0 THEN _fExcess := 0.0; ELSIF _fExcess > 1.0 THEN _fExcess := 1.0; END_IF // 归一值夹取到 [0,1] / clamp the excess into [0,1]
_fAlpha := DL_CNC_ALPHA_MIN + (DL_CNC_ALPHA_MAX - DL_CNC_ALPHA_MIN) * _fExcess; // 本拍增益 [-] / the gain of this scan [-]
IF _bValid THEN // 仅有效拍推进滤波（无效拍不污染保持槽）/ advance only on a valid scan
    _fVbFilt := _fVbFilt + _fAlpha * (_fVbRaw - _fVbFilt); // 一阶指数平滑 [mm] / the first order exponential smoothing [mm]
END_IF
IF NOT (_fVbFilt = _fVbFilt) THEN _fVbFilt := _fVbRaw; END_IF // 滤波结果 NaN 兜底（回退原值）/ the NaN fallback to the raw value
IF (_fVbFilt - _fVbFilt) <> (_fVbFilt - _fVbFilt) THEN _fVbFilt := _fVbRaw; END_IF // 滤波结果 Inf 兜底（同回退）/ the Inf fallback to the raw value
_fVbEst := _fVbFilt; // 本拍估计 [mm] / the estimate of this scan [mm]
IF _fVbEst < 0.0 THEN _fVbEst := 0.0; END_IF // 估计下限夹取（磨损不可为负）/ the wear can never be negative
// 段 8｜报警门限两级回退：一级回默认系数、二级按有效域钳定（R117）
_fAlarmMm := fVbAlarmMm; // 一级：取引脚值 / level one, take the pin value
IF NOT _bCfgOk THEN // 组态越域：一级回退到限值系数 / out of domain, fall back to the limit factor
    _fAlarmMm := fVbLimitMm * DL_CNC_ALARM_FRAC; // 回退值 [mm] / the fallback threshold [mm]
    IF _fAlarmMm <= fVbCompTrigMm THEN _fAlarmMm := fVbCompTrigMm + (fVbLimitMm * DL_CNC_RATIO_BAND); END_IF // 二级：按有效域钳定 / level two, clamp into the valid domain
END_IF
// 段 9｜相位状态机：ENUM ＋ CASE ＋ ELSE 非法相位兜底（R6、R128）
CASE _eState OF
E_DL_CncWearState.eIdle: // 空闲相：退出条件三（使能、切削中、有效拍、无换刀锁存）
    IF _bChangeLch THEN // 换刀请求未解除：禁止回到生产 / the change request blocks production
        _eState := E_DL_CncWearState.eChangeReq; // 驻留换刀请求相 / stay in the change request phase
    ELSIF bEnable AND bCutting AND _bValid THEN // 三个条件齐备才进学习 / all three conditions enter learning
        _eState := E_DL_CncWearState.eLearn; // 迁学习相 / migrate to learning
    END_IF
E_DL_CncWearState.eLearn: // 学习相：按门限升相，无门限命中则驻留（驻留由注释表达，禁自赋值 R261）
    IF NOT bEnable THEN // 使能丢失 / the enable was lost
        _eState := E_DL_CncWearState.eIdle; // 回空闲 / back to idle
    ELSIF _fVbEst >= fVbLimitMm THEN // 越过寿命限值 / the life limit was passed
        _eState := E_DL_CncWearState.eChangeReq; // 迁换刀请求相 / migrate to the change request
    ELSIF _fVbEst >= _fAlarmMm THEN // 越过报警门限 / the alarm threshold was passed
        _eState := E_DL_CncWearState.eAlarm; // 迁报警相 / migrate to alarm
    ELSIF _fVbEst >= fVbCompTrigMm THEN // 越过补偿门限 / the trigger threshold was passed
        _eState := E_DL_CncWearState.eCompensate; // 迁补偿相 / migrate to compensating
    END_IF
E_DL_CncWearState.eCompensate: // 补偿相：按门限升相，回落到补偿门限以下不降相（已补量不回退）
    IF NOT bEnable THEN // 使能丢失 / the enable was lost
        _eState := E_DL_CncWearState.eIdle; // 回空闲 / back to idle
    ELSIF _fVbEst >= fVbLimitMm THEN // 越过寿命限值 / the life limit was passed
        _eState := E_DL_CncWearState.eChangeReq; // 迁换刀请求相 / migrate to the change request
    ELSIF _fVbEst >= _fAlarmMm THEN // 越过报警门限 / the alarm threshold was passed
        _eState := E_DL_CncWearState.eAlarm; // 迁报警相 / migrate to alarm
    END_IF
E_DL_CncWearState.eAlarm: // 报警相：退出条件三（使能丢失、升换刀、带回差降回补偿）
    IF NOT bEnable THEN // 使能丢失 / the enable was lost
        _eState := E_DL_CncWearState.eIdle; // 回空闲 / back to idle
    ELSIF _fVbEst >= fVbLimitMm THEN // 越过寿命限值 / the life limit was passed
        _eState := E_DL_CncWearState.eChangeReq; // 迁换刀请求相 / migrate to the change request
    ELSIF _fVbEst < (_fAlarmMm - (fVbLimitMm * DL_CNC_HYST_BAND)) THEN // 回差带以下才降相（防抖）/ drop only below the hysteresis band
        IF _fVbEst >= fVbCompTrigMm THEN // 仍在补偿门限之上 / still above the trigger
            _eState := E_DL_CncWearState.eCompensate; // 降回补偿相 / drop back to compensating
        ELSE // 已回落到补偿门限之下 / fell below the trigger
            _eState := E_DL_CncWearState.eLearn; // 降回学习相 / drop back to learning
        END_IF
    END_IF
E_DL_CncWearState.eChangeReq: // 换刀请求相：锁存驻留，唯一解除为复位沿（段 3 已迁回空闲）
    IF NOT _bChangeLch THEN // 锁存已被复位沿清除 / the latch was cleared by the reset edge
        _eState := E_DL_CncWearState.eIdle; // 回空闲 / back to idle
    END_IF
ELSE // 非法相位兜底（R6、R128）/ the illegal phase fallback
    _eState := E_DL_CncWearState.eIdle; // 回安全态空闲 / back to the safe idle phase
    _iErrTmp := 2601; // 信息级非法相位码 / the info grade illegal phase code
END_CASE
IF _eState = E_DL_CncWearState.eChangeReq THEN _bChangeLch := TRUE; END_IF // 锁存单点置位（R187 两段式之一）/ single point latch set
// 段 10｜刀补增量闭环：状态量门控（R99），增量限幅 ±50 µm 每拍，累计上限 200 µm 单向
IF (_eState = E_DL_CncWearState.eCompensate) OR (_eState = E_DL_CncWearState.eAlarm) THEN // 仅补偿相与报警相出增量
    _fCompTgt := (_fVbEst - fVbCompTrigMm) * DL_CNC_UM_PER_MM; // 目标累计补偿量 [µm]，以补偿门限为零点 / the target accumulated compensation [um]
    IF _fCompTgt < 0.0 THEN _fCompTgt := 0.0; END_IF // 目标下限夹取（不回退已补量）/ the lower clamp, no retraction
    IF _fCompTgt > DL_CNC_ACC_UM THEN _fCompTgt := DL_CNC_ACC_UM; END_IF // 目标上限夹取 / the upper clamp
    _fStep := _fCompTgt - _fCompAcc; // 本拍应补增量 [µm] / the step required this scan [um]
    IF _fStep > DL_CNC_STEP_UM THEN _fStep := DL_CNC_STEP_UM; ELSIF _fStep < (0.0 - DL_CNC_STEP_UM) THEN _fStep := (0.0 - DL_CNC_STEP_UM); END_IF // 单拍双向限幅 / the two sided step limit
    _fCompAcc := _fCompAcc + _fStep; // 累计量单点写入（全库唯一写入点）/ the only write point of the accumulator
    IF _fCompAcc > DL_CNC_ACC_UM THEN _fCompAcc := DL_CNC_ACC_UM; END_IF // 累计上限硬钳 / the hard clamp of the accumulator
    IF _fCompAcc < 0.0 THEN _fCompAcc := 0.0; END_IF // 累计下限硬钳 / the hard clamp of the lower side
    fCompUm := _fStep; // 增量单点映射 / the single point mapping of the step
END_IF
// 段 11｜统一出口：输出单点映射，信息级码与有效性同源（R191 名实相符）
eState := _eState; // 相位单点映射 / the single point mapping of the phase
fVbEst := _fVbEst; // 估计单点映射 [mm] / the single point mapping of the estimate
fVbRaw := _fVbRaw; // 原值单点映射 [mm] / the single point mapping of the raw value
fCompAccUm := _fCompAcc; // 累计刀补单点映射 [µm] / the single point mapping of the accumulator
fPathM := _fPathM; // 路程单点映射 [m] / the single point mapping of the path
fKcRatio := _fRatio; // 比能比单点映射 [-] / the single point mapping of the ratio
xChangeReq := _bChangeLch; // 换刀请求回放锁存位 / replay the change request latch
xAlarm := (_eState = E_DL_CncWearState.eAlarm) OR (_eState = E_DL_CncWearState.eChangeReq); // 报警电平（含换刀请求相）/ the alarm level including the change request
iErrCode := _iErrTmp; // 信息级码单点映射（每拍重算，不锁存，R187）/ the info code mapping, recomputed every scan
xValid := _bValid AND (_iErrTmp = 0); // 有效性：判据全通过且无信息级异常 / valid when every gate passed and no info code is set
END_FUNCTION_BLOCK
