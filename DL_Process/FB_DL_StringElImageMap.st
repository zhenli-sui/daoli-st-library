(*
  ==================================================================
  组件名 Component  : FB_DL_StringElImageMap
  分类   Category   : DL_Process
  版本   Version    : 1.0.1
  功能   Purpose    : EL 图像缺陷坐标归档与批次比对。逐条接收缺陷报告（坐标、面积、
                      类型），回钳后写入环窗归档（最新 64 条），并按批号累计本批
                      缺陷数、面积和 / 最大值 / 类型掩码；批号变化沿把当前批统计
                      转入「上批」快照并清零当前批，随后给出与上批的比对结论
                      （缺陷数与最大面积双向带容差比较）。
  溯源   Origin     : 缺陷坐标归档与批次间对比为通用视觉质量统计语义；本件为
                      clean-room 实现，仅借鉴来源分类与参数域组织（来源标签
                      roadmap-p2-elimage），道莅原创设计，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（ARRAY / WORD / SHL / R_TRIG，无私有库）
  作者   Author     : 道莅代码库 · PLC 编程专家（R55）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只做归档与统计比对，不做缺陷判定、不存图像（属主边界）；
                      二 坐标越出视野范围不归档，但计入越界计数并置信息级成因；
                      三 非有限坐标或面积不归档、不计数，出口数值保持上拍值；
                      四 环窗游标一律经回钳 1..64，写入顺序为「先算槽位、后写入」；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      wTypeMask 位 i-1 对应缺陷类型 i（类型 1 得 bit0，类型 8 得 bit7）；
                      bComparePass 仅在无参照批（上批缺陷数为零）时恒为真，
                      有参照批时按「缺陷数」与「最大面积」双向带容差比较；
                      eCause 故障级成因与 bError 配对（R45），信息级永不置 bError。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R55 首版（批 3 · 序号 12）
    2026-11-20  v1.0.1  R56 返修（7.4）：段 2 复位作用域补清 fLastXmm / fLastYmm /
                        fLastSizeMm2 / nLastType 四个最近缺陷出口，并补
                        _stCur.uBatchId 批号重同步，防复位后首条新批报告误判入旧批窗口。
  ==================================================================
*)

TYPE ST_DL_ElBatchStat :
STRUCT
    uBatchId  : UDINT := 0;      // 批号 [-] / batch identifier
    nCount    : INT := 0;        // 缺陷条数 [条] / defect count [piece]
    fSumSize  : REAL := 0.0;     // 面积累计 [平方毫米] / accumulated area [square millimetre]
    fMaxSize  : REAL := 0.0;     // 面积最大值 [平方毫米] / maximum area [square millimetre]
    wTypeMask : WORD := 16#0000; // 类型掩码 [-] / type mask
END_STRUCT
END_TYPE

TYPE E_DL_SeiCause :
(
    eNone       := 0,   // 无成因 / no cause
    eCfgIllegal := 1,   // 组态非法：视野范围或容差越域（故障级，与 bError 配对）/ illegal config, field bounds or tolerance out of domain
    eOutField   := 2,   // 缺陷坐标越出视野，未归档（信息级）/ the defect coordinate is outside the field and was not archived, informational
    eInputBad   := 3,   // 坐标或面积非有限，未归档（信息级）/ non-finite coordinate or area, not archived, informational
    eTypeBad    := 4    // 缺陷类型越域已回钳（信息级）/ the defect type was clamped, informational
);
END_TYPE

FUNCTION_BLOCK FB_DL_StringElImageMap
VAR_INPUT
    bEnable       : BOOL := TRUE;            // 使能，失能时不接收缺陷报告 [-] / enable, defect reports are not accepted when disabled
    bReset        : BOOL := FALSE;          // 复位上升沿清故障锁存与全部统计 [-] / reset rising edge clears the fault latch and all statistics
    bDefectValid  : BOOL := FALSE;           // 缺陷报告脉冲，上升沿归档一次 [-] / defect report pulse, archived once on the rising edge
    fPosXmm       : REAL := 0.0;             // 缺陷中心横坐标 [毫米] / defect centre abscissa [millimetre]
    fPosYmm       : REAL := 0.0;             // 缺陷中心纵坐标 [毫米] / defect centre ordinate [millimetre]
    fSizeMm2      : REAL := 0.0;             // 缺陷面积 [平方毫米] / defect area [square millimetre]
    nDefectType   : INT := 1;                // 缺陷类型 [类型号]，域 1..8 / defect type [type number], domain 1 to 8
    uBatchId      : UDINT := 0;              // 当前批号 [-] / current batch identifier
    fFieldXmm     : REAL := 1000.0;          // 视野横向范围 [毫米]，域 大于零 / field width [millimetre], domain above zero
    fFieldYmm     : REAL := 1000.0;          // 视野纵向范围 [毫米]，域 大于零 / field height [millimetre], domain above zero
    fTolPct       : REAL := 10.0;            // 批次比对容差 [百分比]，域 大于零 / batch comparison tolerance [percent], domain above zero
END_VAR
VAR_OUTPUT
    fLastXmm      : REAL := 0.0;             // 最近归档缺陷横坐标 [毫米] / abscissa of the last archived defect [millimetre]
    fLastYmm      : REAL := 0.0;             // 最近归档缺陷纵坐标 [毫米] / ordinate of the last archived defect [millimetre]
    fLastSizeMm2  : REAL := 0.0;             // 最近归档缺陷面积 [平方毫米] / area of the last archived defect [square millimetre]
    nLastType     : INT := 0;                // 最近归档缺陷类型 [类型号] / type of the last archived defect [type number]
    uArchiveCnt   : UDINT := 0;              // 累计归档缺陷数 [条] / total archived defects [piece]
    nBufCount     : INT := 0;                // 环窗当前条数 [条] / ring buffer occupancy [piece]
    nCurCount     : INT := 0;                // 当前批缺陷条数 [条] / current batch defect count [piece]
    fCurMaxMm2    : REAL := 0.0;             // 当前批最大缺陷面积 [平方毫米] / current batch maximum area [square millimetre]
    fCurMeanMm2   : REAL := 0.0;             // 当前批平均缺陷面积 [平方毫米] / current batch mean area [square millimetre]
    nPrevCount    : INT := 0;                // 上批缺陷条数 [条] / previous batch defect count [piece]
    fPrevMaxMm2   : REAL := 0.0;             // 上批最大缺陷面积 [平方毫米] / previous batch maximum area [square millimetre]
    fDeltaMaxPct  : REAL := 0.0;             // 最大面积相对变化 [百分比] / relative change of the maximum area [percent]
    bComparePass  : BOOL := FALSE;           // 批次比对通过 [-] / batch comparison passed
    wTypeMask     : WORD := 16#0000;         // 当前批缺陷类型掩码 [-] / current batch defect type mask
    nOutFieldCnt  : INT := 0;                // 越界缺陷计数（饱和到上限）[条] / out of field defect count, saturated [piece]
    eCause        : E_DL_SeiCause := E_DL_SeiCause.eNone; // 成因出口 [枚举] / cause outlet [enum]
    bError        : BOOL := FALSE;           // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtDefect      : R_TRIG;                  // 缺陷报告沿检测，段 0 无条件刷新 / defect report edge detector, refreshed unconditionally in segment zero
    rtReset       : R_TRIG;                  // 复位沿检测，段 0 无条件刷新 / reset edge detector, refreshed unconditionally in segment zero
    _stCur        : ST_DL_ElBatchStat;       // 当前批统计 / current batch statistics
    _stPrev       : ST_DL_ElBatchStat;       // 上批统计快照 / previous batch statistics snapshot
    _eCause       : E_DL_SeiCause := E_DL_SeiCause.eNone;  // 信息级成因，每拍重算 / informational cause, recomputed every scan
    _eFaultCause  : E_DL_SeiCause := E_DL_SeiCause.eNone;  // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault       : BOOL := FALSE;           // 故障锁存位 [-] / fault latch bit
    _bInit        : BOOL := FALSE;           // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bCfgBad      : BOOL := FALSE;           // 组态非法判定 [-] / illegal configuration verdict
    _bInOk        : BOOL := FALSE;           // 本拍缺陷数据有限 [-] / this scan defect data finite
    _bInField     : BOOL := FALSE;           // 坐标在视野内 [-] / the coordinate is inside the field
    _bTypeClamped : BOOL := FALSE;           // 类型号被回钳 [-] / the type number was clamped
    _bBatchRoll   : BOOL := FALSE;           // 本拍发生批号变化 [-] / the batch identifier changed this scan
    _nTypeUse     : INT := 1;                // 钳定后的缺陷类型号 [类型号] / clamped defect type number
    _nIdx         : INT := 1;                // 环窗写入槽位（1 起，回钳 1..64）[槽号] / ring write slot, one-based, clamped one through sixty four
    _wTypeBit     : WORD := 16#0001;         // 类型位掩码，先移位后置位（R327）/ type bit mask, shift before setting
    _wMask        : WORD := 16#0000;         // 类型掩码工作字 / type mask working word
    _fMean        : REAL := 0.0;             // 均值工作值 [平方毫米] / mean working value [square millimetre]
    _fDeltaPct    : REAL := 0.0;             // 相对变化工作值 [百分比] / relative change working value [percent]
    _fPrevMaxB    : REAL := 0.0;             // 上批最大面积基线，用于除零闸 [平方毫米] / previous maximum baseline against division by zero [square millimetre]
    _fPrevCntB    : REAL := 0.0;             // 上批条数基线，用于除零闸 [条] / previous count baseline against division by zero [piece]
    _fCurMaxB     : REAL := 0.0;             // 当前批最大面积暂存 [平方毫米] / current maximum area held in a local [square millimetre]
    _fCurCntB     : REAL := 0.0;             // 当前批条数暂存 [条] / current count held in a local [piece]
    _afX          : ARRAY[1..64] OF REAL := [64(0.0)]; // 环窗横坐标归档 [毫米] / ring archive of abscissae [millimetre]
    _afY          : ARRAY[1..64] OF REAL := [64(0.0)]; // 环窗纵坐标归档 [毫米] / ring archive of ordinates [millimetre]
    _afSz         : ARRAY[1..64] OF REAL := [64(0.0)]; // 环窗面积归档 [平方毫米] / ring archive of areas [square millimetre]
    _anType       : ARRAY[1..64] OF INT := [64(0)];    // 环窗类型归档 [类型号] / ring archive of type numbers [type number]
END_VAR
VAR CONSTANT
    DL_SEI_BUF_MAX   : INT := 64;            // 环窗容量与槽位回钳上界 [条] / ring capacity and slot clamp upper bound
    DL_SEI_TYPE_MIN  : INT := 1;             // 缺陷类型下限 [类型号] / defect type floor [type number]
    DL_SEI_TYPE_MAX  : INT := 8;             // 缺陷类型上限（与掩码位宽一致）[类型号] / defect type ceiling matching the mask width [type number]
    DL_SEI_COUNT_MAX : INT := 30000;         // 单批缺陷条数上限，防溢出 [条] / per batch defect count ceiling against overflow [piece]
    DL_SEI_AREA_MAX  : REAL := 1.0E6;        // 缺陷面积量级上限 [平方毫米] / defect area magnitude ceiling [square millimetre]
    DL_SEI_TOL_MAX   : REAL := 500.0;        // 比对容差上限 [百分比] / comparison tolerance ceiling [percent]
    DL_SEI_MASK_NONE : WORD := 16#0000;      // 空掩码常量 [-] / empty mask constant
    DL_SEI_MASK_ONE  : WORD := 16#0001;      // 单位位常量 [-] / single bit constant
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支）/ segment 0, unconditional refresh of the edge detectors, never inside a branch
rtDefect(CLK := bDefectValid); // 缺陷报告沿无条件刷新 / unconditional refresh of the defect edge
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge

// 段 1｜首扫初始化（R310）：统计与环窗从确定起点开始 / segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _eCause := E_DL_SeiCause.eNone; // 信息级成因清零 / clear the informational cause
    _eFaultCause := E_DL_SeiCause.eNone; // 故障级成因清零 / clear the fault cause
    _stCur.uBatchId := uBatchId; // 当前批号初始化 / initialise the current batch identifier
    _stPrev.uBatchId := 0; // 上批号清零 / clear the previous batch identifier
    _nIdx := 1; // 环窗槽位归位 / park the ring slot at one
END_IF

// 段 2｜复位沿作用域：清锁存 / 清统计 / 清环窗游标（归档数组保留，不作判据）/ segment 2, reset edge scope
IF rtReset.Q THEN // 复位沿 / reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaultCause := E_DL_SeiCause.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _stCur.nCount := 0; // 作用域二：清当前批条数 / scope two, clear the current batch count
    _stCur.fSumSize := 0.0; // 作用域二：清面积累计 / scope two, clear the accumulated area
    _stCur.fMaxSize := 0.0; // 作用域二：清面积最大值 / scope two, clear the maximum area
    _stCur.wTypeMask := DL_SEI_MASK_NONE; // 作用域二：清类型掩码 / scope two, clear the type mask
    _stPrev.nCount := 0; // 作用域二：清上批条数 / scope two, clear the previous count
    _stPrev.fSumSize := 0.0; // 作用域二：清上批面积累计 / scope two, clear the previous accumulated area
    _stPrev.fMaxSize := 0.0; // 作用域二：清上批最大面积 / scope two, clear the previous maximum area
    _stPrev.wTypeMask := DL_SEI_MASK_NONE; // 作用域二：清上批类型掩码 / scope two, clear the previous type mask
    fLastXmm := 0.0; // 作用域二：清最近横坐标出口（R56 返修补齐）/ scope two, clear the last abscissa outlet
    fLastYmm := 0.0; // 作用域二：清最近纵坐标出口（R56 返修补齐）/ scope two, clear the last ordinate outlet
    fLastSizeMm2 := 0.0; // 作用域二：清最近面积出口（R56 返修补齐）/ scope two, clear the last area outlet
    nLastType := 0; // 作用域二：清最近类型出口（R56 返修补齐）/ scope two, clear the last type outlet
    _stCur.uBatchId := uBatchId; // 作用域二：当前批号重同步，防复位后首条新批报告误判入旧批窗口（R56 返修补齐）/ scope two, resync the current batch identifier so the first report after a reset is not judged against a stale batch window
    _nIdx := 1; // 作用域三：清环窗槽位 / scope three, clear the ring slot cursor
    nBufCount := 0; // 作用域三：清环窗占用 / scope three, clear the ring occupancy
    uArchiveCnt := 0; // 作用域三：清累计归档数 / scope three, clear the total archived count
    nOutFieldCnt := 0; // 作用域三：清越界计数 / scope three, clear the out of field count
END_IF

// 段 3｜组态域闸（R151 全覆盖）：视野范围与比对容差 / segment 3, configuration domain gate over the field bounds and the tolerance
_bCfgBad := FALSE; // 组态非法预置假 / preset the illegal configuration verdict to false
IF (fFieldXmm <= 0.0) OR (fFieldXmm <> fFieldXmm) OR (fFieldXmm > DL_SEI_AREA_MAX) THEN // 横向视野越域 / field width out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (fFieldYmm <= 0.0) OR (fFieldYmm <> fFieldYmm) OR (fFieldYmm > DL_SEI_AREA_MAX) THEN // 纵向视野越域 / field height out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (fTolPct <= 0.0) OR (fTolPct > DL_SEI_TOL_MAX) OR (fTolPct <> fTolPct) THEN // 容量越域 / tolerance out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF _bCfgBad AND (NOT _bFault) THEN // 组态非法且未锁存 / illegal configuration and not yet latched
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaultCause := E_DL_SeiCause.eCfgIllegal; // 故障级成因 (R45 配对 bError) / fault grade cause paired with bError
END_IF

// 段 4｜批号变化：当前批统计转入上批快照，当前批清零 / segment 4, batch change moves the current statistics into the previous snapshot
_bBatchRoll := (uBatchId <> _stCur.uBatchId); // 批号变化判据 / batch change criterion
IF _bBatchRoll THEN // 批号变化 / the batch identifier changed
    _stPrev.uBatchId := _stCur.uBatchId; // 上批号继承 / the previous identifier inherits
    _stPrev.nCount := _stCur.nCount; // 上批条数快照 / snapshot the previous count
    _stPrev.fSumSize := _stCur.fSumSize; // 上批面积累计快照 / snapshot the previous accumulated area
    _stPrev.fMaxSize := _stCur.fMaxSize; // 上批最大面积快照 / snapshot the previous maximum area
    _stPrev.wTypeMask := _stCur.wTypeMask; // 上批类型掩码快照 / snapshot the previous type mask
    _stCur.uBatchId := uBatchId; // 当前批号推进 / advance the current identifier
    _stCur.nCount := 0; // 当前批条数清零 / clear the current count
    _stCur.fSumSize := 0.0; // 当前批面积累计清零 / clear the current accumulated area
    _stCur.fMaxSize := 0.0; // 当前批最大面积清零 / clear the current maximum area
    _stCur.wTypeMask := DL_SEI_MASK_NONE; // 当前批类型掩码清零 / clear the current type mask
END_IF

// 段 5｜缺陷归档：有限性闸 → 视野闸 → 类型回钳 → 环窗写入 → 统计累加 / segment 5, defect archiving chain
_eCause := E_DL_SeiCause.eNone; // 信息级成因每拍重算 / the informational cause is recomputed every scan
_bTypeClamped := FALSE; // 类型回钳标志预置假 / preset the type clamp flag to false
IF rtDefect.Q AND bEnable AND (NOT _bFault) THEN // 缺陷报告沿且使能无故障 / defect edge while enabled and unfaulted
    _bInOk := (fPosXmm = fPosXmm) AND ((fPosXmm - fPosXmm) = (fPosXmm - fPosXmm)) AND (fPosYmm = fPosYmm) AND ((fPosYmm - fPosYmm) = (fPosYmm - fPosYmm)) AND (fSizeMm2 = fSizeMm2) AND ((fSizeMm2 - fSizeMm2) = (fSizeMm2 - fSizeMm2)); // 坐标与面积有限性闸 / finiteness gate on coordinates and area
    _bInField := _bInOk AND (fPosXmm >= 0.0) AND (fPosXmm <= fFieldXmm) AND (fPosYmm >= 0.0) AND (fPosYmm <= fFieldYmm) AND (fSizeMm2 >= 0.0) AND (fSizeMm2 <= DL_SEI_AREA_MAX); // 视野与面积域闸 / field and area domain gate
    _nTypeUse := nDefectType; // 类型号直通 / the type number passes through
    IF _nTypeUse < DL_SEI_TYPE_MIN THEN // 下越界 / below the lower bound
        _nTypeUse := DL_SEI_TYPE_MIN; // 回钳到 1 / clamp to one
        _bTypeClamped := TRUE; // 置回钳标志 / raise the clamp flag
    ELSIF _nTypeUse > DL_SEI_TYPE_MAX THEN // 上越界 / above the upper bound
        _nTypeUse := DL_SEI_TYPE_MAX; // 回钳到 8 / clamp to eight
        _bTypeClamped := TRUE; // 置回钳标志 / raise the clamp flag
    END_IF
    IF NOT _bInOk THEN // 数据非有限 / data non-finite
        _eCause := E_DL_SeiCause.eInputBad; // 信息级成因：未归档 / informational cause, not archived
    ELSIF NOT _bInField THEN // 坐标或面积越域 / coordinate or area out of domain
        _eCause := E_DL_SeiCause.eOutField; // 信息级成因：越界未归档 / informational cause, out of field
        IF nOutFieldCnt < DL_SEI_COUNT_MAX THEN // 未达计数上限 / below the count ceiling
            nOutFieldCnt := nOutFieldCnt + 1; // 越界计数递增 / increment the out of field count
        END_IF
    ELSE
        // 段 5.1｜环窗写入：先算槽位再写入，槽位经回钳 1..64 / segment 5.1, ring write with the slot clamped one through sixty four
        _nIdx := _nIdx + 1; // 槽位前移 / advance the slot
        IF _nIdx > DL_SEI_BUF_MAX THEN // 越过上界 / past the upper bound
            _nIdx := 1; // 回钳到一号槽 / clamp back to slot one
        END_IF
        _afX[_nIdx] := fPosXmm; // 横坐标归档 / archive the abscissa
        _afY[_nIdx] := fPosYmm; // 纵坐标归档 / archive the ordinate
        _afSz[_nIdx] := fSizeMm2; // 面积归档 / archive the area
        _anType[_nIdx] := _nTypeUse; // 类型归档 / archive the type
        IF nBufCount < DL_SEI_BUF_MAX THEN // 环窗未满 / the ring is not yet full
            nBufCount := nBufCount + 1; // 占用递增 / increment the occupancy
        END_IF
        IF uArchiveCnt < 2000000000 THEN // 累计计数未达保护上限（常量在 DINT 可表范围内）/ the total count is below the guard ceiling, the constant fits in DINT
            uArchiveCnt := uArchiveCnt + 1; // 累计归档数递增 / increment the total archived count
        END_IF
        fLastXmm := fPosXmm; // 最近横坐标出口 / last abscissa outlet
        fLastYmm := fPosYmm; // 最近纵坐标出口 / last ordinate outlet
        fLastSizeMm2 := fSizeMm2; // 最近面积出口 / last area outlet
        nLastType := _nTypeUse; // 最近类型出口 / last type outlet
        // 段 5.2｜当前批统计累加 / segment 5.2, accumulate the current batch statistics
        IF _stCur.nCount < DL_SEI_COUNT_MAX THEN // 未达条数上限 / below the count ceiling
            _stCur.nCount := _stCur.nCount + 1; // 条数递增 / increment the count
        END_IF
        _stCur.fSumSize := _stCur.fSumSize + fSizeMm2; // 面积累计 / accumulate the area
        IF fSizeMm2 > _stCur.fMaxSize THEN // 面积最大值刷新 / refresh the maximum area
            _stCur.fMaxSize := fSizeMm2; // 更新最大值 / update the maximum
        END_IF
        _wTypeBit := SHL(DL_SEI_MASK_ONE, _nTypeUse - 1); // 类型位掩码，位移量 0..7 由类型回钳证明 / type bit mask, the shift zero through seven is proven by the type clamp
        _stCur.wTypeMask := _stCur.wTypeMask OR _wTypeBit; // 类型掩码置位 / set the type bit
        IF _bTypeClamped THEN // 类型被回钳 / the type was clamped
            _eCause := E_DL_SeiCause.eTypeBad; // 信息级成因 / informational cause
        END_IF
    END_IF
END_IF

// 段 6｜批次比对：双向带容差比较，参照批缺陷数为零时判通过 / segment 6, batch comparison with a two sided tolerance
_fCurMaxB := _stCur.fMaxSize; // 当前批最大面积 / the current maximum area
_fCurCntB := INT_TO_REAL(_stCur.nCount); // 当前批条数实数化 / the current count as a real
_fPrevMaxB := _stPrev.fMaxSize; // 上批最大面积 / the previous maximum area
_fPrevCntB := INT_TO_REAL(_stPrev.nCount); // 上批条数实数化 / the previous count as a real
IF (_fPrevMaxB > 0.0) THEN // 有参照批 / a reference batch exists
    _fDeltaPct := (_fCurMaxB - _fPrevMaxB) / _fPrevMaxB * 100.0; // 最大面积相对变化，除子已证大于零 / relative change of the maximum area, divisor proven positive
    bComparePass := (_fCurMaxB <= _fPrevMaxB * (1.0 + fTolPct / 100.0)) AND (_fPrevCntB <= 0.0 OR (_fCurCntB <= _fPrevCntB * (1.0 + fTolPct / 100.0))); // 数与面积双向比较，条数基线为零时只比面积 / the count and area are both compared, with a zero count baseline only the area is compared
ELSE // 无参照批 / no reference batch
    _fDeltaPct := 0.0; // 相对变化记零 / the relative change is zeroed
    bComparePass := TRUE; // 无参照按通过处理（不误判不合格）/ no reference passes so nothing is falsely rejected
END_IF

// 段 7｜统一出口 / segment 7, unified outlet
nCurCount := _stCur.nCount; // 当前批条数出口 / current count outlet
fCurMaxMm2 := _stCur.fMaxSize; // 当前批最大面积出口 / current maximum area outlet
_fMean := 0.0; // 均值预置零 / preset the mean to zero
IF _stCur.nCount > 0 THEN // 有条数才可算均值 / the mean needs at least one piece
    _fMean := _stCur.fSumSize / INT_TO_REAL(_stCur.nCount); // 均值，除子已证大于零 / mean, divisor proven positive
END_IF
fCurMeanMm2 := _fMean; // 当前批均值出口 / current mean outlet
nPrevCount := _stPrev.nCount; // 上批条数出口 / previous count outlet
fPrevMaxMm2 := _stPrev.fMaxSize; // 上批最大面积出口 / previous maximum area outlet
fDeltaMaxPct := _fDeltaPct; // 相对变化出口 / relative change outlet
wTypeMask := _stCur.wTypeMask; // 类型掩码出口 / type mask outlet
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eCause := _eFaultCause; // 故障级成因锁存回放 / the fault cause is replayed from the latch
ELSE
    eCause := _eCause; // 信息级成因直映 / the informational cause is mapped directly
END_IF
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
