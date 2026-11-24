(*
  ==================================================================
  组件名 Component  : FB_DL_ShiftMonthReport
  分类   Category   : DL_Process
  版本   Version    : 1.0.0
  功能   Purpose    : 班次 / 月度窗口产量报表闸。班次结束脉冲到达时结算本班产量
                      （好品 / 废品 / 良率）并累加进月度窗口，同时打开报表闸
                      （等上位确认或超时自动关闸），关闸拍出报表完成脉冲。
                      月变更沿清月度累计与班次计数，实现「班次窗 + 月度窗」双窗一致。
  溯源   Origin     : 班次 / 月度报表闸为通用产量统计语义；本件为 clean-room 实现，
                      仅借鉴来源分类与参数域组织（来源标签 roadmap-p2-shift），
                      道莅原创设计，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（R_TRIG / TON / UDINT / REAL，无私有库）
  作者   Author     : 道莅代码库 · PLC 编程专家（R55）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只做结算与报表闸控，不生成报表文件、不写数据库（属主边界）；
                      二 报表闸在「确认沿」或「闸超时」任一到达时关闭，两条路径均可达；
                      三 月度累计只在班次结算拍增长，禁按当下累计引脚每拍重算；
                      四 班次号越域与月变更属信息级事件，不置故障；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      uShiftGood / uShiftScrap 为最近一次结算的班次量（锁存）；
                      uMonthGood / uMonthScrap 为当月累计（锁存，月变更清零）；
                      bReportDone 为单拍脉冲（内部位置位、统一出口映射后撤销）；
                      eCause 故障级成因与 bError 配对（R45），信息级永不置 bError。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R55 首版（批 2 · 序号 8）
  ==================================================================
*)

TYPE E_DL_SmrState :
(
    eIdle   := 0,       // 空闲：等班次结束脉冲 / idle, waiting for the shift end pulse
    eGate   := 10,      // 报表闸开：等上位确认或闸超时 / report gate open, waiting for the acknowledgement or the gate timeout
    eFault  := 90       // 故障：组态非法锁存 / fault, illegal configuration latched
);
END_TYPE

TYPE E_DL_SmrCause :
(
    eNone       := 0,   // 无成因 / no cause
    eCfgIllegal := 1,   // 组态非法：月份、班次号或时间引脚越域（故障级，与 bError 配对）/ illegal config, month, shift index or time pin out of domain
    eShiftBad   := 2,   // 班次号越域已回钳（信息级）/ the shift index was clamped, informational
    eMonthRoll  := 3    // 月变更，月度累计已清零（信息级）/ month rolled over and the monthly accumulation was cleared, informational
);
END_TYPE

FUNCTION_BLOCK FB_DL_ShiftMonthReport
VAR_INPUT
    bEnable     : BOOL := TRUE;              // 使能，失能时关闸并冻结累计 [-] / enable, disabling closes the gate and freezes the accumulation
    bReset      : BOOL := FALSE;            // 复位上升沿清故障锁存与闸状态 [-] / reset rising edge clears the fault latch and the gate state
    nMonth      : INT := 1;                  // 当前月份 [月]，域 1..12 / current month [month], domain 1 to 12
    nShiftIdx   : INT := 1;                  // 当前班次号 [班]，域 1..3 / current shift index [shift], domain 1 to 3
    bShiftEnd   : BOOL := FALSE;             // 班次结束脉冲，上升沿结算 [-] / shift end pulse, settled on the rising edge
    uGoodCnt    : UDINT := 0;                // 本班好品累计 [只] / good pieces accumulated in the shift [pieces]
    uScrapCnt   : UDINT := 0;                // 本班废品累计 [只] / scrap pieces accumulated in the shift [pieces]
    bReportAck  : BOOL := FALSE;             // 上位确认报表，上升沿关闸 [-] / report acknowledgement, the rising edge closes the gate
    tGateTime   : TIME := T#30S;             // 报表闸超时 [毫秒]，域 大于零 / report gate timeout [millisecond], domain above zero
END_VAR
VAR_OUTPUT
    bReportGate : BOOL := FALSE;             // 报表闸开指示 [-] / report gate open indicator
    uShiftGood  : UDINT := 0;                // 最近结算班次好品数 [只] / good pieces of the last settled shift [pieces]
    uShiftScrap : UDINT := 0;                // 最近结算班次废品数 [只] / scrap pieces of the last settled shift [pieces]
    fShiftYield : REAL := 0.0;               // 最近结算班次良率 [百分比] / yield of the last settled shift [percent]
    uMonthGood  : UDINT := 0;                // 当月好品累计 [只] / monthly good pieces [pieces]
    uMonthScrap : UDINT := 0;                // 当月废品累计 [只] / monthly scrap pieces [pieces]
    fMonthYield : REAL := 0.0;               // 当月良率 [百分比] / monthly yield [percent]
    nMonthShifts: INT := 0;                  // 当月已结算班次数 [班] / settled shifts within the month [shift]
    bReportDone : BOOL := FALSE;             // 报表完成单拍脉冲 [-] / report done single-shot pulse
    eState      : E_DL_SmrState := E_DL_SmrState.eIdle; // 相位出口 [枚举] / phase outlet [enum]
    eCause      : E_DL_SmrCause := E_DL_SmrCause.eNone; // 成因出口 [枚举] / cause outlet [enum]
    bError      : BOOL := FALSE;             // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtShift     : R_TRIG;                    // 班次结束沿检测，段 0 无条件刷新 / shift end edge detector, refreshed unconditionally in segment zero
    rtAck       : R_TRIG;                    // 报表确认沿检测，段 0 无条件刷新 / acknowledgement edge detector, refreshed unconditionally in segment zero
    rtReset     : R_TRIG;                    // 复位沿检测，段 0 无条件刷新 / reset edge detector, refreshed unconditionally in segment zero
    tonGate     : TON;                       // 报表闸超时，段 0 无条件刷新 / report gate timeout, refreshed unconditionally in segment zero
    _eState     : E_DL_SmrState := E_DL_SmrState.eIdle;  // 内部相位，CASE 唯一写入目标 / internal phase, the only CASE write target
    _eCause     : E_DL_SmrCause := E_DL_SmrCause.eNone;  // 信息级成因，每拍重算 / informational cause, recomputed every scan
    _eFaultCause: E_DL_SmrCause := E_DL_SmrCause.eNone;  // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault     : BOOL := FALSE;             // 故障锁存位 [-] / fault latch bit
    _bInit      : BOOL := FALSE;             // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bDoneInt   : BOOL := FALSE;             // 报表完成脉冲内部位，统一出口映射 / internal done bit, mapped at the unified outlet
    _bShiftBad  : BOOL := FALSE;             // 班次号被回钳 [-] / the shift index was clamped
    _bCfgBad    : BOOL := FALSE;             // 组态非法判定 [-] / illegal configuration verdict
    _bYieldOk   : BOOL := FALSE;             // 良率除子可用 [-] / the yield divisor is usable
    _nMonthPrev : INT := -1;                 // 上一拍月份快照，初值 -1 使首拍必清 / previous month snapshot, minus one forces a clear on the first scan
    _nShiftUse  : INT := 1;                  // 钳定后的班次号 [班] / clamped shift index [shift]
    _uGoodLoc   : UDINT := 0;                // 本拍好品暂存 [只] / good pieces held in a local [pieces]
    _uScrapLoc  : UDINT := 0;                // 本拍废品暂存 [只] / scrap pieces held in a local [pieces]
    _uMonthG    : UDINT := 0;                // 当月好品累加器 [只] / monthly good accumulator [pieces]
    _uMonthS    : UDINT := 0;                // 当月废品累加器 [只] / monthly scrap accumulator [pieces]
    _uShiftG    : UDINT := 0;                // 班次好品保持块 [只] / shift good holder [pieces]
    _uShiftS    : UDINT := 0;                // 班次废品保持块 [只] / shift scrap holder [pieces]
    _uTotLoc    : UDINT := 0;                // 良率分母（好品加废品）[只] / yield denominator, good plus scrap [pieces]
    _uMonthTot  : UDINT := 0;                // 月度良率分母（好品加废品）[只] / monthly yield denominator [pieces]
    _fYield     : REAL := 0.0;               // 良率工作值 [百分比] / yield working value [percent]
END_VAR
VAR CONSTANT
    DL_SMR_SHIFT_MIN : INT := 1;             // 班次号下限 [班] / shift index floor [shift]
    DL_SMR_SHIFT_MAX : INT := 3;             // 班次号上限 [班] / shift index ceiling [shift]
    DL_SMR_CNT_MAX   : UDINT := 2147483647;  // 计数加和上限，防 UDINT 相加溢出后窄化 [只] / summation ceiling against overflow before narrowing [pieces]
    DL_SMR_YIELD_MAX : REAL := 100.0;        // 良率上限 [百分比] / yield ceiling [percent]
    DL_SMR_DAY_SHIFT_MAX : INT := 3;         // 单日班次计数的自然上限 [班] / natural ceiling of the daily shift count [shift]
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支），IN 只串状态闸 / segment 0, unconditional refresh of timers and edges with state gates on IN only
rtShift(CLK := bShiftEnd); // 班次结束沿无条件刷新 / unconditional refresh of the shift end edge
rtAck(CLK := bReportAck); // 确认沿无条件刷新 / unconditional refresh of the acknowledgement edge
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge
tonGate(IN := (_eState = E_DL_SmrState.eGate) AND (NOT _bFault), PT := tGateTime); // 报表闸超时，IN 串相位闸与故障闸 / report gate timeout with the phase gate and the fault gate on IN

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _eState := E_DL_SmrState.eIdle; // 相位从空闲起步 / the phase starts from idle
    _eCause := E_DL_SmrCause.eNone; // 信息级成因清零 / clear the informational cause
    _eFaultCause := E_DL_SmrCause.eNone; // 故障级成因清零 / clear the fault cause
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _nMonthPrev := -1; // 月份快照置非法值 / put the month snapshot at an illegal value
    _uMonthG := 0; // 月度好品清零 / clear monthly good pieces
    _uMonthS := 0; // 月度废品清零 / clear monthly scrap pieces
    nMonthShifts := 0; // 月度班次计数清零 / clear the monthly shift count
END_IF

// 段 2｜复位沿作用域：清锁存 / 迁相位 / 清闸内部位（累计不清，避免产量丢失）/ segment 2, reset edge scope
IF rtReset.Q THEN // 复位沿 / reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaultCause := E_DL_SmrCause.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _eState := E_DL_SmrState.eIdle; // 作用域二：迁回空闲相 / scope two, migrate back to idle
    _bDoneInt := FALSE; // 作用域二：清完成脉冲内部位 / scope two, clear the internal done bit
    _eCause := E_DL_SmrCause.eNone; // 作用域一：清信息级成因 / scope one, clear the informational cause
END_IF

// 段 3｜组态域闸（R151 全覆盖）/ segment 3, configuration domain gate over every pin
_bCfgBad := FALSE; // 组态非法预置假 / preset the illegal configuration verdict to false
IF (nMonth < 1) OR (nMonth > 12) THEN // 月份越域 / month out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (nShiftIdx < DL_SMR_SHIFT_MIN) OR (nShiftIdx > DL_SMR_SHIFT_MAX) THEN // 班次号越域 / shift index out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF tGateTime <= T#0S THEN // 闸超时非正 / gate timeout not positive
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF _bCfgBad AND (NOT _bFault) THEN // 组态非法且未锁存 / illegal configuration and not yet latched
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaultCause := E_DL_SmrCause.eCfgIllegal; // 故障级成因 (R45 配对 bError) / fault grade cause paired with bError
    _eState := E_DL_SmrState.eFault; // 迁故障相 / migrate to the fault phase
END_IF
_nShiftUse := nShiftIdx; // 班次号直通 / shift index passes through
_bShiftBad := FALSE; // 回钳标志预置假 / preset the clamp flag to false
IF _nShiftUse < DL_SMR_SHIFT_MIN THEN // 下越界 / below the lower bound
    _nShiftUse := DL_SMR_SHIFT_MIN; // 回钳到 1 / clamp to one
    _bShiftBad := TRUE; // 置回钳标志 / raise the clamp flag
ELSIF _nShiftUse > DL_SMR_SHIFT_MAX THEN // 上越界 / above the upper bound
    _nShiftUse := DL_SMR_SHIFT_MAX; // 回钳到 3 / clamp to three
    _bShiftBad := TRUE; // 置回钳标志 / raise the clamp flag
END_IF

// 段 4｜月变更：清月度累计与班次计数（信息级事件，不置故障）/ segment 4, month rollover clears the monthly accumulation, an informational event
_eCause := E_DL_SmrCause.eNone; // 信息级成因每拍重算 / the informational cause is recomputed every scan
IF (nMonth <> _nMonthPrev) THEN // 月份变化（首拍必命中）/ month changed, always true on the first scan
    _nMonthPrev := nMonth; // 月份快照推进 / advance the month snapshot
    _uMonthG := 0; // 月度好品清零 / clear monthly good pieces
    _uMonthS := 0; // 月度废品清零 / clear monthly scrap pieces
    nMonthShifts := 0; // 月度班次计数清零 / clear the monthly shift count
    _uShiftG := 0; // 班次保持块清零 / clear the shift holder
    _uShiftS := 0; // 班次保持块清零 / clear the shift holder
    _eCause := E_DL_SmrCause.eMonthRoll; // 信息级成因：月变更已清零 / informational cause, the rollover cleared the accumulation
END_IF
IF _bShiftBad THEN // 班次号被回钳 / the shift index was clamped
    _eCause := E_DL_SmrCause.eShiftBad; // 信息级成因覆盖（同拍仅报更具体者）/ the informational cause overrides for the more specific event
END_IF

// 段 5｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 5, phase machine with an ELSE fallback for illegal phases
CASE _eState OF
E_DL_SmrState.eIdle: // 空闲相：等班次结束脉冲 / idle phase, waiting for the shift end pulse
    IF rtShift.Q AND (NOT _bFault) THEN // 班次结束沿且无故障 / shift end edge without a fault
        _uGoodLoc := uGoodCnt; // 好品暂存 / hold the good pieces
        _uScrapLoc := uScrapCnt; // 废品暂存 / hold the scrap pieces
        _uTotLoc := _uGoodLoc + _uScrapLoc; // 良率分母 / yield denominator
        IF (_uTotLoc < _uGoodLoc) OR (_uTotLoc < _uScrapLoc) THEN // 相加回绕 / the sum wrapped around
            _uTotLoc := DL_SMR_CNT_MAX; // 饱和到上限，防窄化负值（R316 口径）/ saturated at the ceiling against a negative narrowing
        END_IF
        _bYieldOk := _uTotLoc > 0; // 分母可用性 / denominator usability
        IF _bYieldOk THEN // 分母可用 / the denominator is usable
            _fYield := UDINT_TO_REAL(_uGoodLoc) / UDINT_TO_REAL(_uTotLoc) * 100.0; // 良率，除子已证大于零 / yield, divisor proven positive
            IF _fYield > DL_SMR_YIELD_MAX THEN // 良率越上限 / yield above the ceiling
                _fYield := DL_SMR_YIELD_MAX; // 上钳 / clamp upward
            END_IF
        ELSE
            _fYield := 0.0; // 无产量时良率记零 / zero yield when nothing was produced
        END_IF
        _uShiftG := _uGoodLoc; // 班次好品保持 / hold the shift good pieces
        _uShiftS := _uScrapLoc; // 班次废品保持 / hold the shift scrap pieces
        IF (_uMonthG + _uGoodLoc) < _uMonthG THEN // 累加回绕 / the accumulation wrapped around
            _uMonthG := DL_SMR_CNT_MAX; // 饱和到上限 / saturated at the ceiling
        ELSE
            _uMonthG := _uMonthG + _uGoodLoc; // 月度好品累加 / accumulate monthly good pieces
        END_IF
        IF (_uMonthS + _uScrapLoc) < _uMonthS THEN // 累加回绕 / the accumulation wrapped around
            _uMonthS := DL_SMR_CNT_MAX; // 饱和到上限 / saturated at the ceiling
        ELSE
            _uMonthS := _uMonthS + _uScrapLoc; // 月度废品累加 / accumulate monthly scrap pieces
        END_IF
        IF nMonthShifts < DL_SMR_DAY_SHIFT_MAX THEN // 班次计数未越自然上限 / the shift count is below its natural ceiling
            nMonthShifts := nMonthShifts + 1; // 班次计数递增 / increment the shift count
        END_IF
        _eState := E_DL_SmrState.eGate; // 迁报表闸相 / migrate to the report gate phase
    END_IF

E_DL_SmrState.eGate: // 报表闸相：确认沿或闸超时关闸 / report gate phase, closed by the acknowledgement edge or the gate timeout
    IF rtAck.Q OR tonGate.Q THEN // 确认或超时 / acknowledged or timed out
        _bDoneInt := TRUE; // 报表完成脉冲内部位置位（统一出口映射，R187）/ raise the internal done bit, mapped at the unified outlet
        _eState := E_DL_SmrState.eIdle; // 迁回空闲相 / migrate back to idle
    END_IF

E_DL_SmrState.eFault: // 故障相：锁存回放，等复位沿 / fault phase, the latch is replayed until the reset edge
    _bDoneInt := FALSE; // 故障拍不出完成脉冲 / no done pulse while faulted

ELSE // 非法相位兜底（R128）/ illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaultCause := E_DL_SmrCause.eCfgIllegal; // 故障级成因记组态非法 / record the illegal configuration cause
    _eState := E_DL_SmrState.eFault; // 迁故障相 / migrate to the fault phase
END_CASE

// 段 6｜失能语义：关闸并冻结累计（R191 显式声明）/ segment 6, disabled semantics, close the gate and freeze the accumulation
IF NOT bEnable THEN // 失能 / disabled
    _eState := E_DL_SmrState.eIdle; // 迁回空闲相 / migrate back to idle
    _bDoneInt := FALSE; // 撤完成脉冲内部位 / withdraw the internal done bit
END_IF

// 段 7｜统一出口 / segment 7, unified outlet
bReportGate := (_eState = E_DL_SmrState.eGate); // 闸开指示（挂状态量）/ gate open indicator as a state quantity
uShiftGood := _uShiftG; // 班次好品出口 / shift good outlet
uShiftScrap := _uShiftS; // 班次废品出口 / shift scrap outlet
fShiftYield := _fYield; // 班次良率出口 / shift yield outlet
uMonthGood := _uMonthG; // 月度好品出口 / monthly good outlet
uMonthScrap := _uMonthS; // 月度废品出口 / monthly scrap outlet
_uMonthTot := _uMonthG + _uMonthS; // 月度分母先落局部量，避免重复计算 / the monthly denominator lands in a local first
IF _uMonthTot < _uMonthG THEN // 相加回绕 / the sum wrapped around
    _uMonthTot := DL_SMR_CNT_MAX; // 饱和到上限 / saturated at the ceiling
END_IF
IF _uMonthTot > 0 THEN // 月度分母可用 / the monthly denominator is usable
    fMonthYield := UDINT_TO_REAL(_uMonthG) / UDINT_TO_REAL(_uMonthTot) * 100.0; // 月度良率，除子已证大于零 / monthly yield, divisor proven positive
    IF fMonthYield > DL_SMR_YIELD_MAX THEN // 良率越上限 / yield above the ceiling
        fMonthYield := DL_SMR_YIELD_MAX; // 上钳 / clamp upward
    END_IF
ELSE
    fMonthYield := 0.0; // 无产量时良率记零 / zero yield when nothing was produced
END_IF
eState := _eState; // 相位出口单点映射 / single-point phase outlet mapping
bReportDone := _bDoneInt; // 完成脉冲映射本拍值 / map the done pulse for this scan
_bDoneInt := FALSE; // 映射后立即撤销，保证单拍宽度（R187 两段式）/ revoke right after mapping to keep a single-scan width
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eCause := _eFaultCause; // 故障级成因锁存回放 / the fault cause is replayed from the latch
ELSE
    eCause := _eCause; // 信息级成因直映 / the informational cause is mapped directly
END_IF
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
