(*
  ==================================================================
  组件名 Component  : FB_DL_FormatMonthAudit
  分类   Category   : DL_Process
  版本   Version    : 1.0.0
  功能   Purpose    : 化成 / 分容月度窗排产审计。按日历日判月度生产窗是否开启，
                      窗内以「已完数量 / 月计划数量」与「窗内已过比例」两条进度
                      比对，给出准时 / 落后 / 超前三种审计结论，并在窗关闭那一拍
                      输出审计收口脉冲与收口结论（结论锁存至下月开窗）。
  溯源   Origin     : 月度窗进度审计为通用排产审计语义；本件为 clean-room 实现，
                      仅借鉴来源分类与参数域组织（来源标签 roadmap-p2-formation），
                      道莅原创设计，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（R_TRIG / REAL / UDINT 运算，无私有库）
  作者   Author     : 道莅代码库 · PLC 编程专家（R55）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只做审计判级与收口脉冲，不派工单、不改计划量（属主边界）；
                      二 窗内已过比例按「窗首日至当日」计，窗关闭后比例钳到 100%；
                      三 计划量为零判组态故障并锁存至复位沿，不做除法；
                      四 数量类走 UDINT 直比（禁 ABS 单侧判越界，R55 口径）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      eAudit 四态互斥（eNone 仅在窗关闭或未参与时出现）；
                      bAuditClose 为单拍脉冲（内部位置位、统一出口映射后撤销）；
                      fCompletePct / fReqDailyRate 在除子不可用时保持上拍值；
                      eCause 故障级成因与 bError 配对（R45），信息级永不置 bError。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R55 首版（批 2 · 序号 6）
  ==================================================================
*)

TYPE E_DL_FmaAudit :
(
    eNone    := 0,      // 无结论：窗未开或已收口 / no verdict, the window is closed or not yet opened
    eOnPlan  := 10,     // 准时：实际进度落在期望带内 / on plan, the actual progress sits inside the expected band
    eBehind  := 20,     // 落后：实际进度低于期望带下沿 / behind, the actual progress is below the band
    eAhead   := 30      // 超前：实际进度高于期望带上沿 / ahead, the actual progress is above the band
);
END_TYPE

TYPE E_DL_FmaCause :
(
    eNone       := 0,   // 无成因 / no cause
    eCfgIllegal := 1,   // 组态非法：年月日或窗界越域（故障级，与 bError 配对）/ illegal config, calendar or window bounds out of domain
    ePlanZero   := 2,   // 月计划量为零，进度不可算（故障级，与 bError 配对）/ monthly plan is zero, progress not computable
    eWinClosed  := 3    // 当前不在生产窗内（信息级）/ the current day is outside the production window, informational
);
END_TYPE

FUNCTION_BLOCK FB_DL_FormatMonthAudit
VAR_INPUT
    bEnable      : BOOL := TRUE;             // 使能，失能时结论冻结保持 [-] / enable, the verdict freezes and holds when disabled
    bReset       : BOOL := FALSE;           // 复位上升沿清故障锁存与收口结论 [-] / reset rising edge clears the fault latch and the closing verdict
    nYear        : INT := 2026;              // 当前年份 [年]，域 2000..2100 / current year [year], domain 2000 to 2100
    nMonth       : INT := 1;                 // 当前月份 [月]，域 1..12 / current month [month], domain 1 to 12
    nDayOfMonth  : INT := 1;                 // 当月第几日 [日]，域 1..31 / day of month [day], domain 1 to 31
    nWinStartDay : INT := 1;                 // 生产窗起始日 [日] / production window start day [day]
    nWinEndDay   : INT := 25;                // 生产窗结束日 [日]，须不早于起始日 / production window end day, not earlier than the start
    uPlanCells   : UDINT := 1000;            // 月度计划数量 [只]，域 大于零 / monthly planned quantity [pieces], domain above zero
    uDoneCells   : UDINT := 0;               // 已完数量 [只] / completed quantity [pieces]
    fBehindPct   : REAL := 5.0;              // 落后判定带宽度 [百分比]，域 大于零 / behind band width [percent], domain above zero
    fAheadPct    : REAL := 10.0;             // 超前判定带宽度 [百分比]，域 大于零 / ahead band width [percent], domain above zero
END_VAR
VAR_OUTPUT
    bWindowOpen  : BOOL := FALSE;            // 生产窗是否开启 [-] / production window open flag
    nRemainDays  : INT := 0;                 // 窗内剩余天数（窗关闭为 0）[日] / remaining window days, zero when closed
    nElapsedDays : INT := 0;                 // 窗内已过天数（含当日）[日] / elapsed window days including today
    fCompletePct : REAL := 0.0;              // 实际完成比例 [百分比] / actual completion ratio [percent]
    fExpectPct   : REAL := 0.0;              // 按时进度期望比例 [百分比] / expected on-time progress ratio [percent]
    fReqDailyRate: REAL := 0.0;              // 达产所需日均量 [只每日] / required daily rate to hit the plan [pieces per day]
    eAudit       : E_DL_FmaAudit := E_DL_FmaAudit.eNone; // 审计结论出口 [枚举] / audit verdict outlet [enum]
    eAuditClose  : E_DL_FmaAudit := E_DL_FmaAudit.eNone; // 窗关闭拍锁存的收口结论 [枚举] / verdict latched at window closing [enum]
    bAuditClose  : BOOL := FALSE;            // 审计收口单拍脉冲 [-] / audit closing single-shot pulse
    eCause       : E_DL_FmaCause := E_DL_FmaCause.eNone; // 成因出口 [枚举] / cause outlet [enum]
    bError       : BOOL := FALSE;            // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtReset      : R_TRIG;                   // 复位沿检测，段 0 无条件刷新 / reset edge detector, refreshed unconditionally in segment zero
    _eCause      : E_DL_FmaCause := E_DL_FmaCause.eNone;   // 信息级成因，每拍重算 / informational cause, recomputed every scan
    _eFaultCause : E_DL_FmaCause := E_DL_FmaCause.eNone;   // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _eAudit      : E_DL_FmaAudit := E_DL_FmaAudit.eNone;   // 内部结论 / internal verdict
    _eAuditClose : E_DL_FmaAudit := E_DL_FmaAudit.eNone;   // 收口结论锁存 / latched closing verdict
    _bFault      : BOOL := FALSE;            // 故障锁存位 [-] / fault latch bit
    _bInit       : BOOL := FALSE;            // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bWinOpenPrev: BOOL := FALSE;            // 上一拍窗开启快照，收口沿判据用 [-] / previous scan window flag for the closing edge
    _bCloseInt   : BOOL := FALSE;            // 收口脉冲内部位，统一出口映射 / internal closing pulse bit, mapped at the unified outlet
    _bWinOpen    : BOOL := FALSE;            // 本拍窗开启判定 [-] / this scan window open verdict
    _bCfgBad     : BOOL := FALSE;            // 组态非法判定 [-] / illegal configuration verdict
    _bDivOk      : BOOL := FALSE;            // 除子可用判定（计划量非零）[-] / divisor usable verdict
    _nDaysInMonth: INT := 30;                // 当月日历天数 [日] / calendar days of the current month [day]
    _nStart      : INT := 1;                 // 钳定后的窗起始日 [日] / clamped window start day [day]
    _nEnd        : INT := 1;                 // 钳定后的窗结束日 [日] / clamped window end day [day]
    _nDay        : INT := 1;                 // 钳定后的当日序号 [日] / clamped day index [day]
    _nElapsed    : INT := 0;                 // 窗内已过天数工作值 [日] / elapsed window days working value [day]
    _nRemain     : INT := 0;                 // 窗内剩余天数工作值 [日] / remaining window days working value [day]
    _nWinLen     : INT := 1;                 // 窗长（天数）[日] / window length in days [day]
    _fPlan       : REAL := 0.0;              // 计划量实数化暂存 [只] / planned quantity as a real [pieces]
    _fDone       : REAL := 0.0;              // 已完量实数化暂存 [只] / completed quantity as a real [pieces]
    _fComplete   : REAL := 0.0;              // 完成比例工作值 [百分比] / completion ratio working value [percent]
    _fExpect     : REAL := 0.0;              // 期望比例工作值 [百分比] / expected ratio working value [percent]
    _fReqRate    : REAL := 0.0;              // 所需日均量工作值 [只每日] / required daily rate working value [pieces per day]
    _fGap        : REAL := 0.0;              // 计划缺口 [只] / remaining plan gap [pieces]
    _fDivWin     : REAL := 1.0;              // 窗长除子 [日]，已证不小于 1 / window length divisor proven not below one
    _fDivDay     : REAL := 1.0;              // 剩余天数除子 [日]，已证不小于 1 / remaining day divisor proven not below one
END_VAR
VAR CONSTANT
    DL_FMA_DAY_MAX   : INT := 31;            // 月内最大天数 [日] / maximum days within a month [day]
    DL_FMA_YEAR_MIN  : INT := 2000;          // 年份下限 [年] / year floor [year]
    DL_FMA_YEAR_MAX  : INT := 2100;          // 年份上限 [年] / year ceiling [year]
    DL_FMA_BAND_MAX  : REAL := 100.0;        // 判定带宽度上限 [百分比] / band width ceiling [percent]
    DL_FMA_PCT_MAX   : REAL := 1000.0;       // 完成比例上限，防计划量过小放大 [百分比] / completion ratio ceiling against a tiny plan
    DL_FMA_RATE_MAX  : REAL := 1.0E7;        // 日均量上限，防除子过小放大 [只每日] / daily rate ceiling against a tiny divisor
END_VAR

// 段 0｜复位沿无条件周期刷新（禁入分支）/ segment 0, unconditional refresh of the reset edge, never inside a branch
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _eCause := E_DL_FmaCause.eNone; // 信息级成因清零 / clear the informational cause
    _eFaultCause := E_DL_FmaCause.eNone; // 故障级成因清零 / clear the fault cause
    _eAudit := E_DL_FmaAudit.eNone; // 结论清零 / clear the verdict
    _eAuditClose := E_DL_FmaAudit.eNone; // 收口结论清零 / clear the closing verdict
    _bWinOpenPrev := FALSE; // 窗开启快照清零 / clear the window snapshot
END_IF

// 段 2｜复位沿作用域：清故障锁存 / 清收口结论 / 清窗快照（结论不改，避免审计断档）/ segment 2, reset edge scope
IF rtReset.Q THEN // 复位沿 / reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaultCause := E_DL_FmaCause.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _eAuditClose := E_DL_FmaAudit.eNone; // 作用域二：清收口结论 / scope two, clear the closing verdict
    _bCloseInt := FALSE; // 作用域二：清收口脉冲内部位 / scope two, clear the internal closing bit
    _bWinOpenPrev := FALSE; // 作用域三：清窗开启快照 / scope three, clear the window snapshot
END_IF

// 段 3｜日历天数：闰年二月二十九日，其余按大小月 / segment 3, calendar days with a leap February
_nDaysInMonth := 31; // 默认三十一日 / default thirty one days
CASE nMonth OF
1, 3, 5, 7, 8, 10, 12: // 大月 / long months
    _nDaysInMonth := 31; // 三十一日 / thirty one days
2: // 二月 / february
    IF ((nYear MOD 4) = 0) AND (((nYear MOD 100) <> 0) OR ((nYear MOD 400) = 0)) THEN // 闰年判据 / leap year criterion
        _nDaysInMonth := 29; // 闰年二十九日 / twenty nine days in a leap year
    ELSE
        _nDaysInMonth := 28; // 平年二十八日 / twenty eight days in a common year
    END_IF
4, 6, 9, 11: // 小月 / short months
    _nDaysInMonth := 30; // 三十日 / thirty days
ELSE // 非法月份兜底（R128）/ illegal month fallback
    _nDaysInMonth := 30; // 兜底三十日，故障另由域闸锁存 / fall back to thirty days, the fault is latched by the domain gate
END_CASE

// 段 4｜组态域闸（R151 全覆盖）：年月日、窗界、计划量、判定带 / segment 4, configuration domain gate over every pin
_bCfgBad := FALSE; // 组态非法预置假 / preset the illegal configuration verdict to false
IF (nYear < DL_FMA_YEAR_MIN) OR (nYear > DL_FMA_YEAR_MAX) THEN // 年份越域 / year out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (nMonth < 1) OR (nMonth > 12) THEN // 月份越域 / month out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (nDayOfMonth < 1) OR (nDayOfMonth > DL_FMA_DAY_MAX) THEN // 当日序号越域 / day index out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (nWinStartDay < 1) OR (nWinStartDay > DL_FMA_DAY_MAX) OR (nWinEndDay < nWinStartDay) OR (nWinEndDay > DL_FMA_DAY_MAX) THEN // 窗界越域或自相矛盾 / window bounds out of domain or contradicting
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (fBehindPct <= 0.0) OR (fBehindPct > DL_FMA_BAND_MAX) OR (fBehindPct <> fBehindPct) THEN // 落后带宽越域 / behind band out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (fAheadPct <= 0.0) OR (fAheadPct > DL_FMA_BAND_MAX) OR (fAheadPct <> fAheadPct) THEN // 超前带宽越域 / ahead band out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF _bCfgBad AND (NOT _bFault) THEN // 组态非法且未锁存 / illegal configuration and not yet latched
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaultCause := E_DL_FmaCause.eCfgIllegal; // 故障级成因 (R45 配对 bError) / fault grade cause paired with bError
END_IF

// 段 5｜钳定：窗界与当日一律回钳到当月日历范围内（回钳后可安全比较）/ segment 5, clamping the window bounds and the day into the calendar range
_nStart := nWinStartDay; // 窗起始日直通 / window start passes through
IF _nStart < 1 THEN // 下越界 / below the lower bound
    _nStart := 1; // 回钳到一日 / clamp to day one
ELSIF _nStart > _nDaysInMonth THEN // 上越界 / above the upper bound
    _nStart := _nDaysInMonth; // 回钳到月末 / clamp to the last day
END_IF
_nEnd := nWinEndDay; // 窗结束日直通 / window end passes through
IF _nEnd < _nStart THEN // 结束早于起始 / end earlier than start
    _nEnd := _nStart; // 回钳到起始日，窗长退化为一日 / clamp to the start so the window degenerates to a single day
ELSIF _nEnd > _nDaysInMonth THEN // 上越界 / above the upper bound
    _nEnd := _nDaysInMonth; // 回钳到月末 / clamp to the last day
END_IF
_nDay := nDayOfMonth; // 当日序号直通 / day index passes through
IF _nDay < 1 THEN // 下越界 / below the lower bound
    _nDay := 1; // 回钳到一日 / clamp to day one
ELSIF _nDay > _nDaysInMonth THEN // 上越界 / above the upper bound
    _nDay := _nDaysInMonth; // 回钳到月末 / clamp to the last day
END_IF

// 段 6｜窗开启与窗内已过 / 剩余天数 / segment 6, window open verdict with elapsed and remaining days
_nWinLen := _nEnd - _nStart + 1; // 窗长（闭区间）[日] / window length over a closed interval [day]
IF _nWinLen < 1 THEN // 窗长为零不可能（已回钳）/ a zero length is impossible after clamping
    _nWinLen := 1; // 兜底一日，防除零 / fall back to one against division by zero
END_IF
_bWinOpen := (_nDay >= _nStart) AND (_nDay <= _nEnd); // 窗开启判据 / window open criterion
IF _bWinOpen THEN // 窗内 / inside the window
    _nElapsed := _nDay - _nStart + 1; // 已过天数含当日 / elapsed days including today
    _nRemain := _nEnd - _nDay; // 剩余天数不含当日 / remaining days excluding today
ELSE // 窗外 / outside the window
    _nElapsed := 0; // 已过天数零 / elapsed days zero
    _nRemain := 0; // 剩余天数零 / remaining days zero
END_IF
IF NOT bEnable THEN // 失能：结论与比例冻结保持末值（R191 显式声明）/ disabled, ratios and verdict freeze and hold their last value
    _bWinOpen := FALSE; // 窗开启标志撤除 / the window flag is withdrawn
END_IF

// 段 7｜比例与日均：计划量为零不计算，除子先域闸 / segment 7, ratios and daily rate with both divisors gated first
_bDivOk := uPlanCells > 0; // 计划量非零才可算比例 / the plan must be non-zero for any ratio
_eCause := E_DL_FmaCause.eNone; // 信息级成因每拍重算（R190 归因唯一）/ the informational cause is recomputed every scan
IF NOT _bDivOk THEN // 计划量为零 / the plan is zero
    IF NOT _bFault THEN // 未锁存才记故障 / record the fault only when not yet latched
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaultCause := E_DL_FmaCause.ePlanZero; // 故障级成因 (R45 配对 bError) / fault grade cause paired with bError
    END_IF
END_IF
IF _bDivOk AND _bWinOpen THEN // 计划可用且在窗内 / the plan is usable and the window is open
    _fPlan := UDINT_TO_REAL(uPlanCells); // 计划量实数化 / planned quantity as a real
    _fDone := UDINT_TO_REAL(uDoneCells); // 已完量实数化 / completed quantity as a real
    _fComplete := _fDone / _fPlan * 100.0; // 完成比例，除子已证大于零 / completion ratio, divisor proven positive
    IF _fComplete > DL_FMA_PCT_MAX THEN // 比例越上限 / ratio above the ceiling
        _fComplete := DL_FMA_PCT_MAX; // 上钳，防计划量过小放大 / clamp upward against a tiny plan
    END_IF
    _fDivWin := INT_TO_REAL(_nWinLen); // 窗长除子，已证不小于 1 / window length divisor proven not below one
    _fExpect := INT_TO_REAL(_nElapsed) / _fDivWin * 100.0; // 期望比例 / expected ratio
    _fGap := _fPlan - _fDone; // 计划缺口 / plan gap
    IF _fGap < 0.0 THEN // 已完成超出计划 / the plan is already exceeded
        _fGap := 0.0; // 缺口归零 / gap zeroed
    END_IF
    IF _nRemain > 0 THEN // 有剩余天数 / remaining days exist
        _fDivDay := INT_TO_REAL(_nRemain); // 剩余天数除子，已证大于零 / remaining day divisor proven positive
        _fReqRate := _fGap / _fDivDay; // 所需日均量 / required daily rate
        IF _fReqRate > DL_FMA_RATE_MAX THEN // 日均量越上限 / daily rate above the ceiling
            _fReqRate := DL_FMA_RATE_MAX; // 上钳，防除子过小放大 / clamp upward against a tiny divisor
        END_IF
    ELSE // 无剩余天数（窗末日或窗关闭）/ no remaining days
        _fReqRate := 0.0; // 日均需求归零 / the daily requirement is zeroed
    END_IF
    IF (_fComplete < (_fExpect - fBehindPct)) THEN // 实际低于期望带下沿 / actual below the band
        _eAudit := E_DL_FmaAudit.eBehind; // 判落后 / behind verdict
    ELSIF (_fComplete > (_fExpect + fAheadPct)) THEN // 实际高于期望带上沿 / actual above the band
        _eAudit := E_DL_FmaAudit.eAhead; // 判超前 / ahead verdict
    ELSE // 落在带内 / inside the band
        _eAudit := E_DL_FmaAudit.eOnPlan; // 判准时 / on plan verdict
    END_IF
ELSIF _bDivOk THEN // 计划可用但窗外 / the plan is usable yet outside the window
    _eAudit := E_DL_FmaAudit.eNone; // 窗外无结论 / no verdict outside the window
    _eCause := E_DL_FmaCause.eWinClosed; // 信息级成因：不在窗内 / informational cause, outside the window
END_IF

// 段 8｜收口沿：上一拍在窗内、本拍在窗外 → 锁存结论并出单拍脉冲 / segment 8, closing edge latches the verdict and raises a single-shot pulse
IF _bWinOpenPrev AND (NOT _bWinOpen) THEN // 窗关闭沿 / window closing edge
    _eAuditClose := _eAudit; // 结论锁存（窗内最后一拍的判级）/ latch the verdict from the last in-window scan
    IF _eAuditClose = E_DL_FmaAudit.eNone THEN // 收口拍无有效判级 / no valid verdict at closing
        _eAuditClose := E_DL_FmaAudit.eBehind; // 无结论按落后处理（保守侧，安全方向）/ no verdict is treated as behind on the conservative side
    END_IF
    _bCloseInt := TRUE; // 收口脉冲内部位置位（统一出口映射，R187）/ raise the internal pulse bit, mapped at the unified outlet
END_IF
_bWinOpenPrev := _bWinOpen; // 窗开启快照推进 / advance the window snapshot

// 段 9｜统一出口 / segment 9, unified outlet
bWindowOpen := _bWinOpen; // 窗开启出口 / window open outlet
nRemainDays := _nRemain; // 剩余天数出口 / remaining days outlet
nElapsedDays := _nElapsed; // 已过天数出口 / elapsed days outlet
fCompletePct := _fComplete; // 完成比例出口 / completion ratio outlet
fExpectPct := _fExpect; // 期望比例出口 / expected ratio outlet
fReqDailyRate := _fReqRate; // 所需日均量出口 / required daily rate outlet
eAudit := _eAudit; // 结论出口单点映射 / single-point verdict outlet mapping
eAuditClose := _eAuditClose; // 收口结论出口（锁存量）/ closing verdict outlet from the latch
bAuditClose := _bCloseInt; // 收口脉冲映射本拍值 / map the closing pulse for this scan
_bCloseInt := FALSE; // 映射后立即撤销，保证单拍宽度（R187 两段式）/ revoke right after mapping to keep a single-scan width
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eCause := _eFaultCause; // 故障级成因锁存回放 / the fault cause is replayed from the latch
ELSE
    eCause := _eCause; // 信息级成因直映 / the informational cause is mapped directly
END_IF
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
