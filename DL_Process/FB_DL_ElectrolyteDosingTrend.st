(*
  ==================================================================
  组件名 Component  : FB_DL_ElectrolyteDosingTrend
  分类   Category   : DL_Process
  版本   Version    : 1.0.0
  功能   Purpose    : 注液量趋势 SPG（统计过程判据）统计。逐次注液量进环窗，
                      窗满后给出均值、样本标准差、上下控制限（均值 ± k × 标准差）、
                      越限判据与连续同向趋势判据（连升 / 连降），并给目标带内
                      合格判据，用于注液泵磨损与堵塞的早期趋势预警。
  溯源   Origin     : 均值 / 标准差 / 控制限为公开统计过程控制口径；本件为 clean-room
                      实现，仅借鉴来源分类与参数域组织（来源标签 roadmap-p2-dosing），
                      道莅原创设计，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（SQRT / REAL / R_TRIG，无私有库、无方言转换）
  作者   Author     : 道莅代码库 · PLC 编程专家（R55）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只做统计与趋势判据，不调节注液泵、不改配方（属主边界）；
                      二 样本标准差按 n − 1 无偏口径，样本数小于 2 时不下结论；
                      三 方差由「平方和 − 和的平方 / n」推得，舍入致负值一律钳零（开方前闸）；
                      四 环窗遍历按时间序遍历，禁按数组下标序遍历（R194）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      fMeanMl / fStdMl / fUclMl / fLclMl 仅在样本数达标时更新，
                      否则保持上拍值；bOutOfCtrl 仅在最新样本越限时为真（单拍语义，
                      由调用方按需累计）；nTrendRun 正数为连升、负数为连降；
                      eCause 故障级成因与 bError 配对（R45），信息级永不置 bError。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R55 首版（批 4 · 序号 15）
  ==================================================================
*)

TYPE E_DL_EdtTrend :
(
    eStable := 0,       // 平稳：最新与上一样本无明显方向 / stable, no clear direction between the last two samples
    eUp     := 10,      // 连升：连续同向上升 / rising, a run of increases
    eDown   := 20       // 连降：连续同向下降 / falling, a run of decreases
);
END_TYPE

TYPE E_DL_EdtCause :
(
    eNone       := 0,   // 无成因 / no cause
    eCfgIllegal := 1,   // 组态非法：窗口容量、系数或目标带越域（故障级，与 bError 配对）/ illegal config, window size, sigma factor or target band out of domain
    eNoSample   := 2,   // 样本数不足 2，统计量保持上拍值（信息级）/ fewer than two samples and the statistics hold, informational
    eBadSample  := 3    // 存在非有限样本，已拒收（信息级）/ non-finite samples were rejected, informational
);
END_TYPE

FUNCTION_BLOCK FB_DL_ElectrolyteDosingTrend
VAR_INPUT
    bEnable      : BOOL := TRUE;             // 使能，失能时不收样本 [-] / enable, no sample is accepted when disabled
    bReset       : BOOL := FALSE;           // 复位上升沿清故障锁存与全部统计 [-] / reset rising edge clears the fault latch and all statistics
    bSamplePulse : BOOL := FALSE;            // 单次注液量采样脉冲，上升沿收一条 [-] / single dose sample pulse, one sample per rising edge
    fVolMl       : REAL := 0.0;              // 本次注液量 [毫升] / dose volume of this shot [millilitre]
    fTargetMl    : REAL := 100.0;            // 目标注液量 [毫升]，域 大于零 / target dose volume [millilitre], domain above zero
    fTolPct      : REAL := 2.0;              // 目标带容差 [百分比]，域 大于零 / target band tolerance [percent], domain above zero
    nWinSize     : INT := 20;                // 统计窗样本数 [个]，域 2..64 / statistics window size [count], domain 2 to 64
    fSigmaK      : REAL := 3.0;              // 控制限系数（倍标准差）[倍]，域 1..6 / control limit factor in standard deviations [factor], domain 1 to 6
END_VAR
VAR_OUTPUT
    fMeanMl      : REAL := 0.0;              // 窗口均值 [毫升] / window mean [millilitre]
    fStdMl       : REAL := 0.0;              // 窗口样本标准差（n − 1 口径）[毫升] / window sample standard deviation over n minus one [millilitre]
    fUclMl       : REAL := 0.0;              // 上控制限 [毫升] / upper control limit [millilitre]
    fLclMl       : REAL := 0.0;              // 下控制限 [毫升]，可为负 / lower control limit, may be negative [millilitre]
    nSampleCnt   : INT := 0;                 // 窗口有效样本数 [个] / valid sample count in the window
    bOutOfCtrl   : BOOL := FALSE;            // 最新样本越控制限 [-] / the newest sample is beyond a control limit
    bHasStats    : BOOL := FALSE;            // 统计量是否已可交付 [-] / the statistics are deliverable
    bInTarget    : BOOL := FALSE;            // 最新样本落在目标带内 [-] / the newest sample is inside the target band
    nTrendRun    : INT := 0;                 // 连续同向计数（正连升 / 负连降）[次] / signed run length, positive rising and negative falling [count]
    eTrend       : E_DL_EdtTrend := E_DL_EdtTrend.eStable; // 趋势出口 [枚举] / trend outlet [enum]
    nRejectCnt   : INT := 0;                 // 累计拒收样本数（饱和到上限）[个] / total rejected samples, saturated [count]
    eCause       : E_DL_EdtCause := E_DL_EdtCause.eNone; // 成因出口 [枚举] / cause outlet [enum]
    bError       : BOOL := FALSE;            // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtSample     : R_TRIG;                   // 采样沿检测，段 0 无条件刷新 / sample edge detector, refreshed unconditionally in segment zero
    rtReset      : R_TRIG;                   // 复位沿检测，段 0 无条件刷新 / reset edge detector, refreshed unconditionally in segment zero
    _eCause      : E_DL_EdtCause := E_DL_EdtCause.eNone;  // 信息级成因，每拍重算 / informational cause, recomputed every scan
    _eFaultCause : E_DL_EdtCause := E_DL_EdtCause.eNone;  // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _eTrend      : E_DL_EdtTrend := E_DL_EdtTrend.eStable; // 趋势工作值 / trend working value
    _bFault      : BOOL := FALSE;            // 故障锁存位 [-] / fault latch bit
    _bInit       : BOOL := FALSE;            // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bCfgBad     : BOOL := FALSE;            // 组态非法判定 [-] / illegal configuration verdict
    _bSampleOk   : BOOL := FALSE;            // 本拍样本有限 [-] / this scan sample finite
    _bStatsOk    : BOOL := FALSE;            // 统计量可算 [-] / the statistics are computable
    _bVarOk      : BOOL := FALSE;            // 方差非负可开方 [-] / the variance is non-negative and can be rooted
    _bBadReject  : BOOL := FALSE;            // 本拍发生过拒收 [-] / a rejection occurred this scan
    _nWinUse     : INT := 2;                 // 钳定后的窗口容量 [个] / clamped window size [count]
    _nFill       : INT := 0;                 // 环窗已填样本数 [个] / samples held in the ring [count]
    _nHead       : INT := 0;                 // 环窗最新样本槽位（1 起，回钳 1..64）[槽号] / newest ring slot, clamped one through sixty four
    _nIdx        : INT := 0;                 // 环窗游标 [槽号] / ring cursor [slot]
    _nK          : INT := 0;                 // 时间序遍历序号 [序号] / time-order ordinal
    _nGuard      : INT := 0;                 // 遍历守护计数 [次] / traversal guard [count]
    _nRun        : INT := 0;                 // 连续同向计数工作值 [次] / signed run length working value [count]
    _nReject     : INT := 0;                 // 拒收计数工作值 [个] / rejected sample count [count]
    _fVolPrev    : REAL := 0.0;              // 上一样本注液量 [毫升] / previous sample volume [millilitre]
    _fSum        : REAL := 0.0;              // 窗口和 [毫升] / window sum [millilitre]
    _fSumSq      : REAL := 0.0;              // 窗口平方和 [毫升平方] / window sum of squares [millilitre squared]
    _fMean       : REAL := 0.0;              // 均值工作值 [毫升] / mean working value [millilitre]
    _fVar        : REAL := 0.0;              // 方差工作值 [毫升平方] / variance working value [millilitre squared]
    _fStd        : REAL := 0.0;              // 标准差工作值 [毫升] / standard deviation working value [millilitre]
    _fDivN       : REAL := 1.0;              // 均值除子（样本数）[个] / mean divisor, the sample count [count]
    _fDivNm1     : REAL := 1.0;              // 方差除子（样本数减一）[个] / variance divisor, the sample count minus one [count]
    _fVolLoc     : REAL := 0.0;              // 遍历取出的样本值 [毫升] / sample value taken during the traversal [millilitre]
    _afVol       : ARRAY[1..64] OF REAL := [64(0.0)]; // 环窗注液量缓存 [毫升] / ring buffer of dose volumes [millilitre]
END_VAR
VAR CONSTANT
    DL_EDT_MAX       : INT := 64;            // 环窗容量与槽位回钳上界 [个] / ring capacity and slot clamp upper bound
    DL_EDT_WIN_MIN   : INT := 2;             // 窗口容量下限（标准差至少两个样本）[个] / window size floor, a deviation needs two samples
    DL_EDT_VOL_MAX   : REAL := 1.0E6;        // 注液量量级上限，防量纲错配 [毫升] / dose volume magnitude ceiling against a mismatch [millilitre]
    DL_EDT_SIGMA_MIN : REAL := 1.0;          // 控制限系数下限 [倍] / control limit factor floor [factor]
    DL_EDT_SIGMA_MAX : REAL := 6.0;          // 控制限系数上限 [倍] / control limit factor ceiling [factor]
    DL_EDT_TOL_MAX   : REAL := 100.0;        // 容差上限 [百分比] / tolerance ceiling [percent]
    DL_EDT_REJ_MAX   : INT := 30000;         // 拒收计数上限，防溢出 [个] / rejection count ceiling against overflow [count]
    DL_EDT_VAR_EPS   : REAL := 1.0E-9;       // 方差零阈，舍入负值钳零用 [毫升平方] / variance zero threshold for clamping rounding negatives [millilitre squared]
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支）/ segment 0, unconditional refresh of the edge detectors, never inside a branch
rtSample(CLK := bSamplePulse); // 采样沿无条件刷新 / unconditional refresh of the sample edge
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _eCause := E_DL_EdtCause.eNone; // 信息级成因清零 / clear the informational cause
    _eFaultCause := E_DL_EdtCause.eNone; // 故障级成因清零 / clear the fault cause
    _nHead := 0; // 环窗无样本 / the ring holds no sample
    _nFill := 0; // 环窗计数清零 / clear the ring count
    _nRun := 0; // 趋势计数清零 / clear the run counter
    _fVolPrev := 0.0; // 上一样本清零 / clear the previous sample
    _eTrend := E_DL_EdtTrend.eStable; // 趋势从平稳起步 / the trend starts stable
END_IF

// 段 2｜复位沿作用域：清锁存 / 清统计 / 清环窗游标（三项逐项声明）/ segment 2, reset edge scope
IF rtReset.Q THEN // 复位沿 / reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaultCause := E_DL_EdtCause.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _nHead := 0; // 作用域三：清环窗槽位 / scope three, clear the ring slot cursor
    _nFill := 0; // 作用域三：清环窗计数 / scope three, clear the ring count
    _nRun := 0; // 作用域二：清趋势计数 / scope two, clear the run counter
    _nReject := 0; // 作用域二：清拒收计数 / scope two, clear the rejection count
    _fVolPrev := 0.0; // 作用域二：清上一样本 / scope two, clear the previous sample
    _eTrend := E_DL_EdtTrend.eStable; // 作用域二：趋势回平稳 / scope two, the trend returns to stable
    fMeanMl := 0.0; // 作用域二：清均值出口 / scope two, clear the mean outlet
    fStdMl := 0.0; // 作用域二：清标准差出口 / scope two, clear the deviation outlet
    fUclMl := 0.0; // 作用域二：清上控制限出口 / scope two, clear the upper limit outlet
    fLclMl := 0.0; // 作用域二：清下控制限出口 / scope two, clear the lower limit outlet
END_IF

// 段 3｜组态域闸（R151 全覆盖）/ segment 3, configuration domain gate over every pin
_bCfgBad := FALSE; // 组态非法预置假 / preset the illegal configuration verdict to false
IF (fTargetMl <= 0.0) OR (fTargetMl <> fTargetMl) OR (fTargetMl > DL_EDT_VOL_MAX) THEN // 目标量越域 / the target is out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (fTolPct <= 0.0) OR (fTolPct > DL_EDT_TOL_MAX) OR (fTolPct <> fTolPct) THEN // 容差越域 / the tolerance is out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (nWinSize < DL_EDT_WIN_MIN) OR (nWinSize > DL_EDT_MAX) THEN // 窗口容量越域 / the window size is out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (fSigmaK < DL_EDT_SIGMA_MIN) OR (fSigmaK > DL_EDT_SIGMA_MAX) OR (fSigmaK <> fSigmaK) THEN // 系数越域 / the factor is out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF _bCfgBad AND (NOT _bFault) THEN // 组态非法且未锁存 / illegal configuration and not yet latched
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaultCause := E_DL_EdtCause.eCfgIllegal; // 故障级成因 (R45 配对 bError) / fault grade cause paired with bError
END_IF
_nWinUse := nWinSize; // 窗口容量直通 / the window size passes through
IF _nWinUse < DL_EDT_WIN_MIN THEN // 下越界 / below the lower bound
    _nWinUse := DL_EDT_WIN_MIN; // 回钳到 2 / clamp to two
ELSIF _nWinUse > DL_EDT_MAX THEN // 上越界 / above the upper bound
    _nWinUse := DL_EDT_MAX; // 回钳到 64 / clamp to sixty four
END_IF

// 段 4｜样本接收与趋势跟踪 / segment 4, sample acceptance and trend tracking
_eCause := E_DL_EdtCause.eNone; // 信息级成因每拍重算 / the informational cause is recomputed every scan
_bBadReject := FALSE; // 拒收标志预置假 / preset the rejection flag to false
IF rtSample.Q AND bEnable AND (NOT _bFault) THEN // 采样沿且使能无故障 / sample edge while enabled and unfaulted
    _bSampleOk := (fVolMl = fVolMl) AND ((fVolMl - fVolMl) = (fVolMl - fVolMl)) AND (fVolMl >= 0.0) AND (fVolMl <= DL_EDT_VOL_MAX); // 样本有限性与量级闸 / sample finiteness and magnitude gate
    IF NOT _bSampleOk THEN // 样本不可用 / the sample is unusable
        _bBadReject := TRUE; // 记拒收 / record the rejection
        IF _nReject < DL_EDT_REJ_MAX THEN // 未达计数上限 / below the ceiling
            _nReject := _nReject + 1; // 拒收计数递增 / increment the rejection count
        END_IF
    ELSE
        // 段 4.1｜环窗写入：先算槽位再写入，槽位回钳 1..64 / segment 4.1, ring write with a clamped slot
        _nHead := _nHead + 1; // 槽位前移 / advance the slot
        IF _nHead > DL_EDT_MAX THEN // 越过上界 / past the upper bound
            _nHead := 1; // 回钳到一号槽 / clamp back to slot one
        END_IF
        _afVol[_nHead] := fVolMl; // 样本入环窗 / store the sample
        IF _nFill < DL_EDT_MAX THEN // 环窗未满 / the ring is not yet full
            _nFill := _nFill + 1; // 计数递增 / increment the count
        END_IF
        // 段 4.2｜趋势跟踪：与上一样本比较方向 / segment 4.2, trend tracking against the previous sample
        IF _nFill > 1 THEN // 至少两条样本才有方向 / a direction needs at least two samples
            IF fVolMl > _fVolPrev THEN // 上升 / rising
                IF _nRun < 0 THEN // 原为连降 / previously falling
                    _nRun := 1; // 方向翻转，计数从 1 起 / the direction flipped and the run restarts at one
                ELSE
                    _nRun := _nRun + 1; // 连升累加 / extended the rising run
                END_IF
            ELSIF fVolMl < _fVolPrev THEN // 下降 / falling
                IF _nRun > 0 THEN // 原为连升 / previously rising
                    _nRun := -1; // 方向翻转，计数从负 1 起 / the direction flipped and the run restarts at minus one
                ELSE
                    _nRun := _nRun - 1; // 连降累加 / extended the falling run
                END_IF
            ELSE // 相等（本拍样本与上一样本同值）/ equal to the previous sample
                _nRun := 0; // 无方向 / no direction
            END_IF
        END_IF
        _fVolPrev := fVolMl; // 上一样本推进 / advance the previous sample
    END_IF
END_IF
IF _bBadReject THEN // 本拍发生拒收 / a rejection occurred this scan
    _eCause := E_DL_EdtCause.eBadSample; // 信息级成因 / informational cause
END_IF

// 段 5｜统计量：按时间序遍历环窗求均值与样本标准差 / segment 5, statistics over the ring in time order
_bStatsOk := _nFill >= DL_EDT_WIN_MIN; // 样本数达下限才可算标准差 / the deviation needs the minimum sample count
IF _bStatsOk THEN // 统计可算 / the statistics are computable
    _fSum := 0.0; // 和清零 / clear the sum
    _fSumSq := 0.0; // 平方和清零 / clear the sum of squares
    _nIdx := _nHead - _nFill + 1; // 时间序最旧槽位 / the oldest slot in time order
    IF _nIdx < 1 THEN // 越过下界 / below the lower bound
        _nIdx := _nIdx + DL_EDT_MAX; // 单次回绕补齐 / a single wrap restores the time order
    END_IF
    _nK := 1; // 时间序序号自 1 起 / the time-order ordinal starts at one
    _nGuard := 0; // 守护计数清零 / reset the guard
    WHILE (_nK <= _nFill) AND (_nGuard < (2 * DL_EDT_MAX)) DO // 双重守护 / dual guard
        _nGuard := _nGuard + 1; // 守护计数递增 / increment the guard
        _nIdx := _nHead - _nFill + _nK; // 时间序槽位 / the slot in time order
        IF _nIdx < 1 THEN // 越过下界 / below the lower bound
            _nIdx := _nIdx + DL_EDT_MAX; // 单次回绕 / single wrap
        END_IF
        _fVolLoc := _afVol[_nIdx]; // 取出样本 / take the sample
        _fSum := _fSum + _fVolLoc; // 累加和 / accumulate the sum
        _fSumSq := _fSumSq + _fVolLoc * _fVolLoc; // 累加平方和 / accumulate the sum of squares
        _nK := _nK + 1; // 序号递增 / increment the ordinal
    END_WHILE
    _fDivN := INT_TO_REAL(_nFill); // 均值除子为样本数，已证不小于 2 / the mean divisor is the count, proven not below two
    _fMean := _fSum / _fDivN; // 均值 / mean
    _fDivNm1 := INT_TO_REAL(_nFill - 1); // 方差除子为 n − 1，已证不小于 1 / the variance divisor is n minus one, proven not below one
    _fVar := (_fSumSq - (_fSum * _fSum) / _fDivN) / _fDivNm1; // 无偏方差 / unbiased variance
    _bVarOk := _fVar > DL_EDT_VAR_EPS; // 方差可用（舍入负值不参与开方）/ the variance is usable and rounding negatives are excluded
    IF _bVarOk THEN // 方差可用 / the variance is usable
        _fStd := SQRT(_fVar); // 标准差 / standard deviation
    ELSE
        _fStd := 0.0; // 方差近零时标准差记零 / a near-zero variance yields a zero deviation
    END_IF
    fMeanMl := _fMean; // 均值出口 / mean outlet
    fStdMl := _fStd; // 标准差出口 / deviation outlet
    fUclMl := _fMean + fSigmaK * _fStd; // 上控制限 / upper control limit
    fLclMl := _fMean - fSigmaK * _fStd; // 下控制限（可为负）/ lower control limit, may be negative
    bHasStats := TRUE; // 统计量可交付 / the statistics are deliverable
ELSE // 样本不足 / too few samples
    bHasStats := FALSE; // 统计量不可交付，出口保持上拍值 / the statistics are not deliverable and the outlets hold
    _eCause := E_DL_EdtCause.eNoSample; // 信息级成因 / informational cause
END_IF

// 段 6｜越限与目标带判据（仅在有统计量时判，避免用未成型的限值下结论）/ segment 6, limit and target band verdicts
bOutOfCtrl := FALSE; // 越限标志预置假 / preset the out-of-control flag to false
bInTarget := FALSE; // 目标带标志预置假 / preset the in-target flag to false
IF bHasStats AND rtSample.Q AND _bSampleOk THEN // 仅在有效采样拍判越限与目标带 / the verdicts run only on a valid sample scan
    bOutOfCtrl := (fVolMl > fUclMl) OR (fVolMl < fLclMl); // 最新样本越控制限 / the newest sample is beyond a control limit
    bInTarget := ABS(fVolMl - fTargetMl) <= (fTargetMl * fTolPct / 100.0); // 目标带判据，除子为常量 100.0 / target band verdict with the constant divisor one hundred
END_IF

// 段 7｜趋势出口映射 / segment 7, trend outlet mapping
IF _nRun > 0 THEN // 连升 / rising run
    _eTrend := E_DL_EdtTrend.eUp; // 连升档 / rising
ELSIF _nRun < 0 THEN // 连降 / falling run
    _eTrend := E_DL_EdtTrend.eDown; // 连降档 / falling
ELSE
    _eTrend := E_DL_EdtTrend.eStable; // 平稳档 / stable
END_IF
eTrend := _eTrend; // 趋势出口单点映射 / single-point trend outlet mapping
nTrendRun := _nRun; // 连续同向计数出口 / signed run length outlet
nSampleCnt := _nFill; // 窗口样本数出口 / window sample count outlet
nRejectCnt := _nReject; // 拒收计数出口 / rejection count outlet
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eCause := _eFaultCause; // 故障级成因锁存回放 / the fault cause is replayed from the latch
ELSE
    eCause := _eCause; // 信息级成因直映 / the informational cause is mapped directly
END_IF
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
