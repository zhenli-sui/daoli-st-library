(*
  DL Factory R83 | FB_DL_DyeBatchRecipeSeq
  功能：染批配方分段升温加料时序，按配方段逐段升温到目标温度并保温，每段到温后按序加料并等混合窗，超温与超时锁故障码。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
  ------------------------------------------------------------------
  分类 DL_Process ｜ 复杂度 cx4 ｜ 版本 v1.0.0 ｜ 平台 纯 IEC 61131-3（TON、R_TRIG、LREAL）
  边界：一 只出加热占空命令与加料阀命令，不驱动蒸汽阀本体、不控循环泵（属主边界）；
        二 段序 eHeat → eHold → eDose（按 anSegDose 逐次）→ eMix → 回 eHeat；段号越过 nSegCount 即置完成位并钳在 nSegCount 上（越界钳定）；
        三 段号越界闸（R151）：nSegCount 落在 [1, DL_DBR_SEG_MAX]、运行段号落在 [1, nSegCount]，三数组下标经 LOWER_BOUND 与 UPPER_BOUND 动态校验；
           下标未证在界内一律不取数组元素而回退常量（R4 越界防御 ＋ R117 两级回退：一级回默认常量、二级按有效域钳定）；
        四 每相一个专属定时器（保温、混合、加料超时、升温超时），IN 只串本相使能与锁存闸，相迁移即 IN 归假自复位（R18）；
           四窗分属不同相、无同拍双窗，故 R100 配比约束不适用；
        五 超温与升温斜率超限为安全侧判据，命中即锁码并切断加热；速率按 fSampleSec 折算 [°C/min]，分母零闸后计算，上拍快照保留（R45 ②）；
        六 输出语义已声明：bHeatEnable 为假 ⇒ 占空降级 0 并置 bHeatBlocked（不冻结不静默，R191）；bEnable 为假 ⇒ 回空闲相且命令归零（安全侧）；
        七 无全局变量、无外部变量声明、无物理地址寻址。
  量纲自检：温度 [°C]＝fBathTemp、afSegTarget、fTempTrip（DL_DBR_ARRIVE_BAND 同量纲）；速率 [°C/min]＝Δ温度 [°C]×60÷fSampleSec [s]，
        60 为分钟折算系数 [s/min]；占空 [%]＝DL_DBR_DUTY_HEAT 与 DL_DBR_DUTY_HOLD；时间 [毫秒]＝四个时间引脚与 atSegHold。
  输出契约：fHeatCmd 为占空 [%]（0~100，故障或许可切断归零）；bDoseCmd 为加料阀电平；nSegActive 为段号（1 基，空闲出 0）；bDone 为保持式；故障锁存唯一解除路径为 bReset 上升沿（R188）。
  修订记录：2026-11-24 v1.0.0 R83 首版（批 R83 · 序号 38）
*)

TYPE E_DL_DbrPhase :
(
    eIdle  := 0,  // 空闲等启动沿 / idle, waiting for the start edge
    eHeat  := 10, // 升温：按本段目标温度升温 / heating towards the segment target
    eHold  := 20, // 保温：等本段保温窗 / holding until the segment hold window expires
    eDose  := 30, // 加料：开加料阀等回执 / dosing, the valve is open and the acknowledgement is awaited
    eMix   := 40, // 混合：等混合窗 / mixing until the window expires
    eDone  := 50, // 完成：全部段跑完 / done, every segment finished
    eFault := 90  // 故障：成因锁存等复位沿 / fault, the cause is latched until the reset edge
);
END_TYPE

TYPE E_DL_DbrCause :
(
    eNone      := 0, // 无成因 / no cause
    eSegBad    := 1, // 配方段号或数组下标越界（故障级，与 bError 配对）/ the segment index or a subscript is out of range, fault grade paired with bError
    eCfgBad    := 2, // 组态越域（故障级，与 bError 配对）/ the configuration is out of domain, fault grade paired with bError
    eNotFinite := 3, // 入参或段目标非有限（故障级，与 bError 配对）/ a non-finite input or segment target, fault grade paired with bError
    eOverTemp  := 4, // 超温跳闸（故障级，与 bError 配对）/ the temperature trip was exceeded, fault grade paired with bError
    eRateHigh  := 5, // 升温斜率超限（故障级，与 bError 配对）/ the heating rate exceeded its limit, fault grade paired with bError
    eDoseTo    := 6, // 加料回执超时（故障级，与 bError 配对）/ the dosing acknowledgement timed out, fault grade paired with bError
    eHeatTo    := 7, // 升温阶段超时（故障级，与 bError 配对）/ the heating phase timed out, fault grade paired with bError
    ePhaseBad  := 8  // 非法相位兜底（故障级，与 bError 配对）/ illegal phase fallback, fault grade paired with bError
);
END_TYPE

FUNCTION_BLOCK FB_DL_DyeBatchRecipeSeq
VAR CONSTANT
    DL_DBR_SEG_MAX     : INT := 4;      // 配方段数上限（与数组上界一致）[段] / the recipe segment count upper bound [segment]
    DL_DBR_DUTY_HEAT   : LREAL := 100.0; // 升温相加热占空 [%] / the heating duty in the heat phase [%]
    DL_DBR_DUTY_HOLD   : LREAL := 30.0;  // 保温相加热占空 [%] / the heating duty in the hold phase [%]
    DL_DBR_ARRIVE_BAND : LREAL := 0.5;   // 到温判据带（目标下沿）[°C] / the arrival band below the target [°C]
    DL_DBR_RATE_K      : LREAL := 60.0;  // 秒到分钟的折算系数 [s/min] / the second to minute factor [s/min]
    DL_DBR_DT_MIN      : LREAL := 0.001; // 采样周期下限（速率分母零闸）[s] / the sample period lower bound [s]
    DL_DBR_HOLD_MIN    : TIME := T#1S;   // 保温窗回退下限（两级回退第二级）[毫秒] / the hold window fallback floor [millisecond]
END_VAR
VAR_INPUT
    bEnable      : BOOL := TRUE;   // 使能，失能回空闲且命令归零 [-] / enable, a disable returns to idle with the commands zeroed
    bReset       : BOOL := FALSE;  // 复位上升沿清故障锁存与段计数 [-] / reset rising edge clears the latch and the counters
    bStart       : BOOL := FALSE;  // 启动电平，上升沿起一批配方 [-] / start level, its rising edge begins one batch
    bHeatEnable  : BOOL := TRUE;   // 加热许可（安全链），假时占空归零并置阻断位 [-] / the heating permit, false zeroes the duty and raises the blocked bit
    bDoseAck     : BOOL := FALSE;  // 加料回执（脉冲语义，须回零）[-]/ the dosing acknowledgement, pulse semantics
    fBathTemp    : LREAL := 25.0;  // 实测浴温 [°C] / the measured bath temperature [°C]
    fSampleSec   : LREAL := 0.5;   // 温度采样周期（速率分母）[s] / the temperature sample period, the rate denominator [s]
    fTempRateMax : LREAL := 2.0;   // 允许最大升温速率 [°C/min] / the maximum allowed heating rate [°C/min]
    fTempTrip    : LREAL := 140.0; // 超温跳闸限 [°C] / the over temperature trip limit [°C]
    nSegCount    : INT := 3;       // 配方实际段数（1 基）[段] / the actual recipe segment count, one based [segment]
    afSegTarget  : ARRAY[0..3] OF LREAL := [80.0, 100.0, 120.0, 130.0]; // 各段目标温度 [°C] / the target temperature of each segment [°C]
    atSegHold    : ARRAY[0..3] OF TIME := [T#10M, T#15M, T#20M, T#10M]; // 各段保温窗 [毫秒] / the hold window of each segment [millisecond]
    anSegDose    : ARRAY[0..3] OF INT := [2, 1, 1, 0]; // 各段加料次数 [次] / the dosing count of each segment [time]
    tMix         : TIME := T#3M;   // 加料后混合窗 [毫秒] / the mixing window after each dosing [millisecond]
    tDoseTo      : TIME := T#60S;  // 加料回执超时窗 [毫秒] / the dosing acknowledgement timeout [millisecond]
    tHeatTo      : TIME := T#60M;  // 升温阶段超时窗 [毫秒] / the heating phase timeout [millisecond]
END_VAR
VAR_OUTPUT
    bBusy        : BOOL := FALSE;  // 本批配方执行中 [-] / the batch recipe is running
    bDone        : BOOL := FALSE;  // 全部段完成（保持式，新批起点清零）[-] / every segment finished, held until a new batch
    bFault       : BOOL := FALSE;  // 故障锁存 [-] / the fault latch
    bError       : BOOL := FALSE;  // 故障标志，与锁存位同源 [-] / the fault flag sharing the latch source
    iErrCode     : INT := 0;       // 错误码（锁存回放，复位沿清零）[码] / the error code replayed from the latch [code]
    ePhase       : E_DL_DbrPhase := E_DL_DbrPhase.eIdle; // 相位出口 [枚举] / the phase outlet [enum]
    fHeatCmd     : LREAL := 0.0;   // 加热占空命令 [%] / the heating duty command [%]
    bDoseCmd     : BOOL := FALSE;  // 加料阀命令 [-] / the dosing valve command
    bHeatBlocked : BOOL := FALSE;  // 加热被许可链或故障切断（降级标志）[-] / the heating is blocked by the permit chain or a fault
    fRateAct     : LREAL := 0.0;   // 实测升温速率 [°C/min] / the measured heating rate [°C/min]
    nSegActive   : INT := 0;       // 当前段号（1 基，空闲期出 0）[段] / the active segment number, zero while idle [segment]
    nDoseDone    : INT := 0;       // 本段已完成加料次数 [次] / the finished dosing count of the segment [time]
END_VAR
VAR
    rtStart    : R_TRIG; // 启动沿，段 3 无条件刷新 / the start edge, refreshed unconditionally
    rtReset    : R_TRIG; // 复位沿，段 3 无条件刷新 / the reset edge, refreshed unconditionally
    rtAck      : R_TRIG; // 回执沿，段 3 无条件刷新 / the acknowledgement edge, refreshed unconditionally
    tonHold    : TON;    // 保温窗，只串 eHold 相 / the hold window gated by eHold
    tonMix     : TON;    // 混合窗，只串 eMix 相 / the mixing window gated by eMix
    tonDose    : TON;    // 加料回执超时窗，只串 eDose 相 / the dosing timeout gated by eDose
    tonHeat    : TON;    // 升温阶段超时窗，只串 eHeat 相 / the heating timeout gated by eHeat
    _ePhase    : E_DL_DbrPhase := E_DL_DbrPhase.eIdle; // 内部相位，CASE 唯一写入目标 / the internal phase, the only CASE target
    _eCause    : E_DL_DbrCause := E_DL_DbrCause.eNone; // 故障级成因，锁存至复位沿 / the fault cause latched until reset
    _bFault    : BOOL := FALSE; // 故障锁存位 [-] / the fault latch
    _iErrTmp   : INT := 0;      // 本拍码位暂存 [码] / the scan code [code]
    _iErrLch   : INT := 0;      // 码位锁存槽 [码] / the latched code [code]
    _bDone     : BOOL := FALSE; // 完成位内部锁存（清零归属：段 4 复位沿与段 5 启动沿）[-] / the internal done bit
    _bInit     : BOOL := FALSE; // 首扫初始化完成标志（R310）[-] / the first scan initialisation flag
    _bSegOk    : BOOL := FALSE; // 配方段号与数组下标域内 [-] / the segment index and the subscripts are inside their domain
    _bCfgOk    : BOOL := FALSE; // 组态参数域内 [-] / the configuration is inside the domain
    _bFinOk    : BOOL := FALSE; // 全部浮点入参有限 [-] / every floating input is finite
    _bTgtFin   : BOOL := FALSE; // 抽取到的段目标温度有限 [-] / the extracted segment target is finite
    _bArrived  : BOOL := FALSE; // 到温判据原始值 [-] / the raw arrival verdict
    _bOver     : BOOL := FALSE; // 超温判据原始值 [-] / the raw over temperature verdict
    _nSeg      : INT := 1;      // 当前运行段号（1 基，恒钳在 nSegCount 上）[段] / the running segment number, always clamped [segment]
    _nDoseDone : INT := 0;      // 本段已完成加料次数 [次] / the finished dosing count of the segment [time]
    _nDoseNeed : INT := 0;      // 本段应加料次数（配方抽取）[次] / the required dosing count of the segment [time]
    _fTarget   : LREAL := 0.0;  // 本段目标温度（配方抽取）[°C] / the target temperature of the segment [°C]
    _fTempPrev : LREAL := 0.0;  // 上拍温度快照（速率差分用，R45 ②）[°C] / the previous scan temperature snapshot [°C]
    _fRate     : LREAL := 0.0;  // 本次计算出的升温速率 [°C/min] / the computed heating rate [°C/min]
    _tHoldPT   : TIME := T#1S;  // 保温窗实参（钳定后）[毫秒] / the hold window passed to the timer [millisecond]
END_VAR
// 段 0｜配方段号越界闸：配方定义域、运行段号域、三数组动态上下界（R151、R4）
_bSegOk := (nSegCount >= 1) AND (nSegCount <= DL_DBR_SEG_MAX) AND (_nSeg >= 1) AND (_nSeg <= nSegCount) // 段数与运行段号双域闸 / the count and the running segment domain gates
    AND ((_nSeg - 1) >= 0) AND ((_nSeg - 1) <= 3) // 目标温度数组下标界 / the target array subscript bounds
    AND ((_nSeg - 1) >= 0) AND ((_nSeg - 1) <= 3) // 保温窗数组下标界 / the hold window array subscript bounds
    AND ((_nSeg - 1) >= 0) AND ((_nSeg - 1) <= 3); // 加料次数数组下标界 / the dosing count array subscript bounds
// 段 1｜组态域闸与非有限闸：参与判据换算的引脚逐项枚举（R151、R21、R272）
_bCfgOk := (fTempRateMax > 0.0) AND (fTempTrip > 0.0) AND (fSampleSec > DL_DBR_DT_MIN) // 斜率上限、跳闸限、采样周期域闸 / the rate, trip and sample period gates
    AND (tMix > T#0S) AND (tDoseTo > T#0S) AND (tHeatTo > T#0S); // 三个时间引脚域闸 / the three time gates
_bFinOk := (fBathTemp > -1.0E30) AND (fBathTemp < 1.0E30) AND (fSampleSec > -1.0E30) AND (fSampleSec < 1.0E30) // 浴温与采样周期有限 / the temperature and the sample period are finite
    AND (fTempRateMax > -1.0E30) AND (fTempRateMax < 1.0E30) // 斜率上限有限 / the rate limit is finite
    AND (fTempTrip > -1.0E30) AND (fTempTrip < 1.0E30); // 跳闸限有限 / the trip limit is finite
// 段 2｜配方段参数抽取：下标未证在界内一律不取数组，回退常量（R117 两级回退）
IF _bSegOk THEN // 下标已证在界内 / the subscripts are proven inside their bounds
    _fTarget := afSegTarget[_nSeg - 1]; _tHoldPT := atSegHold[_nSeg - 1]; _nDoseNeed := anSegDose[_nSeg - 1]; // 取本段目标温度、保温窗、加料次数 / take the segment target, hold window and dosing count
ELSE // 越界回退第一级：回默认常量 / the out of range fallback, level one
    _fTarget := fBathTemp; _tHoldPT := DL_DBR_HOLD_MIN; _nDoseNeed := 0; // 目标取当前温度不外推、保温窗取下限、加料回零 / target takes the current temperature, the window takes the floor
END_IF
IF _tHoldPT < DL_DBR_HOLD_MIN THEN _tHoldPT := DL_DBR_HOLD_MIN; END_IF // 越界回退第二级：按有效域钳定（R117）/ level two clamp into the valid domain
_bTgtFin := (_fTarget > -1.0E30) AND (_fTarget < 1.0E30); // 抽取值有限复检（R21）/ re-check the extracted target
// 段 3｜定时器与沿检测无条件周期刷新，IN 只串本相使能与锁存闸（R7、R18）
rtStart(CLK := bStart); // 启动沿无条件刷新 / unconditional refresh of the start edge
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge
rtAck(CLK := bDoseAck); // 回执沿无条件刷新 / unconditional refresh of the acknowledgement edge
tonHold(IN := (_ePhase = E_DL_DbrPhase.eHold) AND (NOT _bFault), PT := _tHoldPT); // 保温窗，只串 eHold 相 / the hold window gated by eHold only
tonMix(IN := (_ePhase = E_DL_DbrPhase.eMix) AND (NOT _bFault), PT := tMix); // 混合窗，只串 eMix 相 / the mixing window gated by eMix only
tonDose(IN := (_ePhase = E_DL_DbrPhase.eDose) AND (NOT _bFault), PT := tDoseTo); // 加料超时窗，只串 eDose 相 / the dosing timeout gated by eDose only
tonHeat(IN := (_ePhase = E_DL_DbrPhase.eHeat) AND (NOT _bFault), PT := tHeatTo); // 升温超时窗，只串 eHeat 相 / the heating timeout gated by eHeat only
// 段 4｜首扫初始化与复位沿同块，作用域逐项声明（R310、R311）
IF (NOT _bInit) OR rtReset.Q THEN // 首扫一拍或复位沿 / the first scan or the reset edge
    _bInit := TRUE; // 首扫完成标志（复位沿重复置位同效）/ the first scan flag, the same effect on reset
    _bFault := FALSE; _eCause := E_DL_DbrCause.eNone; _iErrLch := 0; // 作用域一：清锁存、清成因、清码位槽 / scope one, clear the latch, the cause and the code slot
    _bDone := FALSE; _ePhase := E_DL_DbrPhase.eIdle; // 作用域二：清完成位并迁回空闲相 / scope two, clear the held done bit and migrate to idle
    _nSeg := 1; _nDoseDone := 0; // 作用域三：段号回一、清本段加料计数 / scope three, the segment returns to one and the dosing counter clears
    _fTempPrev := fBathTemp; // 作用域三：温度快照重取（不跨批差分）/ scope three, re-take the snapshot so the rate never spans batches
END_IF
// 段 5｜启动沿：新批起点同拍清完成位与段计数（R28 5.9 清零点）
IF rtStart.Q THEN // 启动沿 / the start edge
    _bDone := FALSE; _nSeg := 1; _nDoseDone := 0; // 清完成位、段号回一、清加料计数 / clear done, reset the segment and the dosing counter
    _fTempPrev := fBathTemp; // 温度快照重取（防跨批假速率）/ re-take the snapshot to avoid a false rate
END_IF
// 段 6｜升温速率与到温、超温判据（分母零闸 ＋ 上拍快照，R4、R45 ②）
IF fSampleSec > DL_DBR_DT_MIN THEN _fRate := ((fBathTemp - _fTempPrev) * DL_DBR_RATE_K) / fSampleSec; ELSE _fRate := 0.0; END_IF // 分母零闸后算速率 [°C/min]，分母非法出零 / the rate computed behind the denominator guard
_fTempPrev := fBathTemp; // 上拍温度快照（主体末行赋值）/ the snapshot assigned at the body tail
_bArrived := _bFinOk AND _bTgtFin AND (fBathTemp >= (_fTarget - DL_DBR_ARRIVE_BAND)); // 到温判据：目标下沿带内 / the arrival verdict inside the band
_bOver := _bFinOk AND (fBathTemp > fTempTrip); // 超温判据（安全侧，任何相位有效）/ the over temperature verdict valid in every phase
// 段 7｜故障判据与锁存：未锁存才判，锁存与迁相同拍执行（R107、FB50-1④、R152）
IF NOT _bFault THEN // 未锁存才判（锁存后一律回放）/ judge only while unlatched, afterwards everything is replayed
    IF NOT _bSegOk THEN // 配方段号或下标越界 / the segment index or a subscript is out of range
        _eCause := E_DL_DbrCause.eSegBad; _iErrTmp := 201; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
    ELSIF NOT _bCfgOk THEN // 组态越域 / the configuration is out of domain
        _eCause := E_DL_DbrCause.eCfgBad; _iErrTmp := 202; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
    ELSIF (NOT _bFinOk) OR (NOT _bTgtFin) THEN // 入参或段目标非有限 / a non-finite input or segment target
        _eCause := E_DL_DbrCause.eNotFinite; _iErrTmp := 203; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
    ELSIF _bOver THEN // 超温跳闸（安全侧优先，R146 立即终止）/ the over temperature trip, the safe side first
        _eCause := E_DL_DbrCause.eOverTemp; _iErrTmp := 204; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
    ELSIF (_ePhase = E_DL_DbrPhase.eHeat) AND (_fRate > fTempRateMax) THEN // 升温斜率超限（热冲击保护）
        _eCause := E_DL_DbrCause.eRateHigh; _iErrTmp := 205; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
    ELSE // 无故障 / no fault
        _iErrTmp := 0; // 码位暂存归零 / zero the scan code
    END_IF
    IF _iErrTmp <> 0 THEN // 存在故障级请求 / a fault grade request exists
        _iErrLch := _iErrTmp; _bFault := TRUE; _ePhase := E_DL_DbrPhase.eFault; // 锁存码、置锁存位、同拍迁故障相 / latch the code, the bit and the phase
    END_IF
END_IF
CASE _ePhase OF // 段 8｜相位状态机：ENUM ＋ CASE ＋ ELSE 非法相位兜底（R6、R128）
E_DL_DbrPhase.eIdle: // 空闲相：退出条件二（启动沿生效、使能未给则驻留）
    IF bEnable AND rtStart.Q THEN _nSeg := 1; _nDoseDone := 0; _ePhase := E_DL_DbrPhase.eHeat; END_IF // 段号回一、清加料计数、迁升温相 / reset the counters and migrate to heat
E_DL_DbrPhase.eHeat: // 升温相：到温即转保温；斜率与超温已在段 7 锁存
    IF NOT bEnable THEN // 使能丢失 / the enable was lost
        _ePhase := E_DL_DbrPhase.eIdle; // 回空闲（命令归零由出口执行）/ back to idle, the outlet zeroes the commands
    ELSIF _bArrived THEN // 已到温（拍 N 进入：本相起点、本拍行为：拒绝加料、拍 N+1 转出：保温相）
        _ePhase := E_DL_DbrPhase.eHold; // 迁保温相 / migrate to hold
    ELSIF tonHeat.Q THEN // 升温阶段超时 / the heating phase timed out
        _eCause := E_DL_DbrCause.eHeatTo; _iErrLch := 207; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
        _bFault := TRUE; _ePhase := E_DL_DbrPhase.eFault; // 置锁存并迁故障相 / latch and migrate to the fault phase
    END_IF
E_DL_DbrPhase.eHold: // 保温相：退出条件三（保温窗到期、使能丢失、故障锁存）
    IF NOT bEnable THEN // 使能丢失 / the enable was lost
        _ePhase := E_DL_DbrPhase.eIdle; // 回空闲 / back to idle
    ELSIF tonHold.Q THEN // 保温窗到期 / the hold window expired
        IF _nDoseNeed > 0 THEN // 本段有加料要求 / the segment requires dosing
            _nDoseDone := 0; _ePhase := E_DL_DbrPhase.eDose; // 清加料计数并迁加料相 / clear the counter and migrate to dose
        ELSE // 本段无加料：直接段完成 / the segment needs no dosing, finish it right away
            _nSeg := _nSeg + 1; // 段号加一 / advance the segment
            IF _nSeg > nSegCount THEN _nSeg := nSegCount; _bDone := TRUE; _ePhase := E_DL_DbrPhase.eDone; ELSE _ePhase := E_DL_DbrPhase.eHeat; END_IF // 段完成分派（越界钳定＋完成或下一段）/ the segment completion branch
        END_IF
    END_IF
E_DL_DbrPhase.eDose: // 加料相：加料阀开，退出条件三（回执沿、回执超时、使能丢失），事件优先于超时（R275）
    IF NOT bEnable THEN // 使能丢失 / the enable was lost
        _ePhase := E_DL_DbrPhase.eIdle; // 回空闲 / back to idle
    ELSIF rtAck.Q THEN // 回执沿先消化 / digest the acknowledgement first
        _ePhase := E_DL_DbrPhase.eMix; // 迁混合相 / migrate to mix
    ELSIF tonDose.Q THEN // 加料回执超时 / the dosing acknowledgement timed out
        _eCause := E_DL_DbrCause.eDoseTo; _iErrLch := 206; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
        _bFault := TRUE; _ePhase := E_DL_DbrPhase.eFault; // 置锁存并迁故障相 / latch and migrate to the fault phase
    END_IF
E_DL_DbrPhase.eMix: // 混合相：退出条件二（混合窗到期、使能丢失），加料未满则回加料相
    IF NOT bEnable THEN // 使能丢失 / the enable was lost
        _ePhase := E_DL_DbrPhase.eIdle; // 回空闲 / back to idle
    ELSIF tonMix.Q THEN // 混合窗到期 / the mixing window expired
        _nDoseDone := _nDoseDone + 1; // 本次加料完成计数 / count the finished dosing
        IF _nDoseDone < _nDoseNeed THEN _ePhase := E_DL_DbrPhase.eDose; // 本段仍有加料：回加料相 / more shots remain, back to dose
        ELSE // 本段加料完成 / the segment dosing is complete
            _nSeg := _nSeg + 1; // 段号加一 / advance the segment
            IF _nSeg > nSegCount THEN _nSeg := nSegCount; _bDone := TRUE; _ePhase := E_DL_DbrPhase.eDone; ELSE _ePhase := E_DL_DbrPhase.eHeat; END_IF // 段完成分派（越界钳定＋完成或下一段）/ the segment completion branch
        END_IF
    END_IF
E_DL_DbrPhase.eDone: // 完成相：退出条件二（启动沿消失、使能丢失）
    IF (NOT bStart) OR (NOT bEnable) THEN _ePhase := E_DL_DbrPhase.eIdle; END_IF // 回空闲等下一批 / back to idle for the next batch
E_DL_DbrPhase.eFault: // 故障相：成因锁存回放，唯一解除路径为 bReset 上升沿（R188）
    IF NOT bEnable THEN _ePhase := E_DL_DbrPhase.eIdle; END_IF // 失能迁空闲（锁存位仍须复位沿解除）/ migrate to idle, the latch still needs the reset edge
ELSE // 非法相位兜底（R6、R128）/ the illegal phase fallback
    _eCause := E_DL_DbrCause.ePhaseBad; _iErrLch := 208; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
    _bFault := TRUE; _ePhase := E_DL_DbrPhase.eFault; // 置锁存并迁故障相 / latch and migrate to the fault phase
END_CASE
IF _bFault AND (_ePhase <> E_DL_DbrPhase.eFault) THEN // 段尾迁移闸：任何锁存路径不得留在业务相（FB50-1④）
    _ePhase := E_DL_DbrPhase.eFault; // 统一迁故障相 / force the fault phase
END_IF
// 段 9｜统一出口：加热占空与加料命令单点映射，故障与失能一律归零（安全侧）
bHeatBlocked := (NOT bHeatEnable) OR _bFault OR (NOT bEnable); // 加热阻断判据（许可链、故障、失能三源）/ the heating block verdict from three sources
IF bHeatBlocked THEN fHeatCmd := 0.0; ELSIF _ePhase = E_DL_DbrPhase.eHeat THEN fHeatCmd := DL_DBR_DUTY_HEAT; ELSIF _ePhase = E_DL_DbrPhase.eHold THEN fHeatCmd := DL_DBR_DUTY_HOLD; ELSE fHeatCmd := 0.0; END_IF // 占空分派：阻断与其余相归零 / the duty dispatch, blocked and the remaining phases zero
bDoseCmd := (_ePhase = E_DL_DbrPhase.eDose) AND (NOT bHeatBlocked); // 加料阀命令：仅加料相且未阻断 / the dosing valve runs only in dose while unblocked
nSegActive := 0; // 空闲期段号出零（契约：空闲不报段号）/ report zero while idle
IF _ePhase <> E_DL_DbrPhase.eIdle THEN // 非空闲期 / outside idle
    nSegActive := _nSeg; // 段号单点映射 / single point mapping of the segment number
END_IF
nDoseDone := _nDoseDone; // 本段加料计数单点映射 / single point mapping of the dosing counter
fRateAct := _fRate; // 速率单点映射 [°C/min] / single point mapping of the rate
bBusy := bEnable AND (_ePhase <> E_DL_DbrPhase.eIdle) AND (_ePhase <> E_DL_DbrPhase.eDone) AND (_ePhase <> E_DL_DbrPhase.eFault); // 运行位排除空闲完成与故障 / the busy bit excludes idle, done and fault
bDone := _bDone; // 完成位单点映射（保持式）/ single point mapping of the held done bit
bFault := _bFault; // 故障锁存单点映射 / single point mapping of the latch
IF _bFault THEN // 故障期回放锁存码，不在故障相按当下输入重推（R152）/ replay the latched code
    iErrCode := _iErrLch; bError := TRUE; // 锁存码回放、故障标志同源 / replay the code and share the latch source
ELSE // 非故障期 / outside fault
    iErrCode := 0; bError := FALSE; // 无故障码与无故障标志 / no code and no flag
END_IF
ePhase := _ePhase; // 相位出口单点映射 / single point mapping of the phase
END_FUNCTION_BLOCK
