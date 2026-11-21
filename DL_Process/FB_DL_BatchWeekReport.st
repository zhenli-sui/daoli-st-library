(*
  ==================================================================
  组件名 Component  : FB_DL_BatchWeekReport
  分类   Category   : DL_Process
  版本   Version    : 1.0.0
  功能   Purpose    : 批次周报闸与周批号生成。批次结束脉冲逐条累计本周批次数与
                      本周产量；周序号变化沿锁存上周汇总并打开周报闸（等上位确认
                      或闸超时关闭）；每批结束时按「年 × 1000 + 周序号 × 10 +
                      周内批次序号模 10」生成周批号。
  溯源   Origin     : 周报闸与批号编码为通用批次管理语义；本件为 clean-room 实现，
                      仅借鉴来源分类与参数域组织（来源标签 roadmap-p2-batch），
                      道莅原创设计，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（R_TRIG / TON / UDINT / MOD，无私有库）
  作者   Author     : 道莅代码库 · PLC 编程专家（R55）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只做周汇总、周报闸与批号生成，不写报表文件、不入库（属主边界）；
                      二 周汇总只在批次结束沿增长，禁按当下累计引脚每拍重算；
                      三 周报闸关闭路径两条（上位确认沿 / 闸超时），两条均恒可达；
                      四 批号尾位为周内批次序号模 10，尾位回绕属正常编码约定并写进注释；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      uBatchNo 每批次结束沿更新一次并锁存至下一批；
                      uWeekGood / uWeekScrap / uWeekBatchCnt 为本周边界内累计（周变更清零）；
                      uLastWeekGood / uLastWeekScrap 为上周汇总（周变更沿锁存）；
                      bReportReady 为单拍脉冲（内部位置位、统一出口映射后撤销）；
                      eCause 故障级成因与 bError 配对（R45），信息级永不置 bError。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R55 首版（批 3 · 序号 11）
  ==================================================================
*)

TYPE E_DL_BwrState :
(
    eIdle  := 0,        // 空闲：等批次结束沿或周变更沿 / idle, waiting for a batch end or a week change
    eGate  := 10,       // 周报闸开：等上位确认或闸超时 / weekly report gate open, waiting for the acknowledgement or the gate timeout
    eFault := 90        // 故障：组态非法锁存 / fault, illegal configuration latched
);
END_TYPE

TYPE E_DL_BwrCause :
(
    eNone       := 0,   // 无成因 / no cause
    eCfgIllegal := 1,   // 组态非法：年份、周序号或时间引脚越域（故障级，与 bError 配对）/ illegal config, year, week index or time pin out of domain
    eWeekRoll   := 2,   // 周变更，本周累计已锁存并清零（信息级）/ week rolled over, the weekly accumulation was latched and cleared, informational
    eCntSat     := 3    // 周内批次计数饱和（信息级）/ the weekly batch counter saturated, informational
);
END_TYPE

FUNCTION_BLOCK FB_DL_BatchWeekReport
VAR_INPUT
    bEnable      : BOOL := TRUE;             // 使能，失能时关闸并冻结累计 [-] / enable, disabling closes the gate and freezes the accumulation
    bReset       : BOOL := FALSE;           // 复位上升沿清故障锁存与闸状态 [-] / reset rising edge clears the fault latch and the gate state
    nYear        : INT := 2026;              // 当前年份 [年]，域 2000..2100 / current year [year], domain 2000 to 2100
    nWeekOfYear  : INT := 1;                 // 当前周序号（年内第几周）[周]，域 1..53 / week index within the year [week], domain 1 to 53
    bBatchEnd    : BOOL := FALSE;            // 批次结束脉冲，上升沿结算 [-] / batch end pulse, settled on the rising edge
    uBatchGood   : UDINT := 0;               // 本批好品数 [只] / good pieces of this batch [pieces]
    uBatchScrap  : UDINT := 0;               // 本批废品数 [只] / scrap pieces of this batch [pieces]
    bReportAck   : BOOL := FALSE;            // 上位确认周报，上升沿关闸 [-] / weekly report acknowledgement, the rising edge closes the gate
    tGateTime    : TIME := T#60S;            // 周报闸超时 [毫秒]，域 大于零 / weekly report gate timeout [millisecond], domain above zero
END_VAR
VAR_OUTPUT
    bReportGate  : BOOL := FALSE;            // 周报闸开指示 [-] / weekly report gate open indicator
    bReportReady : BOOL := FALSE;            // 周报就绪单拍脉冲 [-] / weekly report ready single-shot pulse
    uBatchNo     : UDINT := 0;               // 周批号（年 × 1000 + 周 × 10 + 周内序号模 10）[-] / weekly batch number
    nWeekActive  : INT := 1;                 // 当前生效周序号 [周] / currently active week index [week]
    uWeekBatchCnt: UDINT := 0;               // 本周已结批次计数 [批] / settled batch count this week [batch]
    uWeekGood    : UDINT := 0;               // 本周好品累计 [只] / weekly good pieces [pieces]
    uWeekScrap   : UDINT := 0;               // 本周废品累计 [只] / weekly scrap pieces [pieces]
    uLastWeekGood: UDINT := 0;               // 上周好品汇总（锁存）[只] / last week good pieces, latched [pieces]
    uLastWeekScrap : UDINT := 0;             // 上周废品汇总（锁存）[只] / last week scrap pieces, latched [pieces]
    fWeekYield   : REAL := 0.0;              // 本周良率 [百分比] / weekly yield [percent]
    eState       : E_DL_BwrState := E_DL_BwrState.eIdle; // 相位出口 [枚举] / phase outlet [enum]
    eCause       : E_DL_BwrCause := E_DL_BwrCause.eNone; // 成因出口 [枚举] / cause outlet [enum]
    bError       : BOOL := FALSE;            // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtBatch      : R_TRIG;                   // 批次结束沿检测，段 0 无条件刷新 / batch end edge detector, refreshed unconditionally in segment zero
    rtAck        : R_TRIG;                   // 确认沿检测，段 0 无条件刷新 / acknowledgement edge detector, refreshed unconditionally in segment zero
    rtReset      : R_TRIG;                   // 复位沿检测，段 0 无条件刷新 / reset edge detector, refreshed unconditionally in segment zero
    tonGate      : TON;                      // 周报闸超时，段 0 无条件刷新 / gate timeout, refreshed unconditionally in segment zero
    _eState      : E_DL_BwrState := E_DL_BwrState.eIdle;  // 内部相位，CASE 唯一写入目标 / internal phase, the only CASE write target
    _eCause      : E_DL_BwrCause := E_DL_BwrCause.eNone;  // 信息级成因，每拍重算 / informational cause, recomputed every scan
    _eFaultCause : E_DL_BwrCause := E_DL_BwrCause.eNone;  // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault      : BOOL := FALSE;            // 故障锁存位 [-] / fault latch bit
    _bInit       : BOOL := FALSE;            // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bReadyInt   : BOOL := FALSE;            // 周报就绪脉冲内部位，统一出口映射 / internal ready bit, mapped at the unified outlet
    _bCfgBad     : BOOL := FALSE;            // 组态非法判定 [-] / illegal configuration verdict
    _bCntSat     : BOOL := FALSE;            // 周内批次计数饱和 [-] / the weekly batch counter saturated
    _nWeekPrev   : INT := -1;                // 上一拍周序号快照，初值 -1 使首拍必清 / previous week snapshot, minus one forces a clear on the first scan
    _nWeekUse    : INT := 1;                 // 钳定后的周序号 [周] / clamped week index [week]
    _uClampMax   : UDINT := 100000000;       // 周内批次计数饱和上限 [批] / weekly batch counter saturation ceiling [batch]
    _uCnt        : UDINT := 0;               // 周内批次计数工作值 [批] / weekly batch counter working value [batch]
    _uGood       : UDINT := 0;               // 本周好品累加器 [只] / weekly good accumulator [pieces]
    _uScrap      : UDINT := 0;               // 本周废品累加器 [只] / weekly scrap accumulator [pieces]
    _uLastG      : UDINT := 0;               // 上周好品锁存 [只] / last week good pieces latch [pieces]
    _uLastS      : UDINT := 0;               // 上周废品锁存 [只] / last week scrap pieces latch [pieces]
    _uBatchNo    : UDINT := 0;               // 周批号工作值 [-] / weekly batch number working value
    _uYearBase   : UDINT := 0;               // 批号中的年份基数 [-] / year base of the batch number
    _uTail       : UDINT := 0;               // 批号尾位（周内序号模 10）[-] / batch number tail, the weekly ordinal modulo ten
    _uTotLoc     : UDINT := 0;               // 良率分母（好品加废品）[只] / yield denominator [pieces]
    _fYield      : REAL := 0.0;              // 良率工作值 [百分比] / yield working value [percent]
END_VAR
VAR CONSTANT
    DL_BWR_WEEK_MIN  : INT := 1;             // 周序号下限 [周] / week index floor [week]
    DL_BWR_WEEK_MAX  : INT := 53;            // 周序号上限 [周] / week index ceiling [week]
    DL_BWR_YEAR_MIN  : INT := 2000;          // 年份下限 [年] / year floor [year]
    DL_BWR_YEAR_MAX  : INT := 2100;          // 年份上限 [年] / year ceiling [year]
    DL_BWR_YEAR_MUL  : UDINT := 1000;        // 批号年份权重 [无量纲] / year weight in the batch number
    DL_BWR_WEEK_MUL  : UDINT := 10;          // 批号周序号权重 [无量纲] / week weight in the batch number
    DL_BWR_TAIL_MOD  : UDINT := 10;          // 批号尾位取模基数（尾位回绕属正常编码约定）[无量纲] / tail modulo base, tail wrapping is a normal encoding convention
    DL_BWR_YIELD_MAX : REAL := 100.0;        // 良率上限 [百分比] / yield ceiling [percent]
    DL_BWR_CNT_CEIL  : UDINT := 2147483647;  // 数量加和上限，防相加溢出后窄化 [只] / summation ceiling against overflow before narrowing [pieces]
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支），IN 只串状态闸 / segment 0, unconditional refresh of timers and edges with state gates on IN only
rtBatch(CLK := bBatchEnd); // 批次结束沿无条件刷新 / unconditional refresh of the batch end edge
rtAck(CLK := bReportAck); // 确认沿无条件刷新 / unconditional refresh of the acknowledgement edge
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge
tonGate(IN := (_eState = E_DL_BwrState.eGate) AND (NOT _bFault), PT := tGateTime); // 周报闸超时，IN 串相位闸与故障闸 / gate timeout with the phase gate and the fault gate on IN

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _eState := E_DL_BwrState.eIdle; // 相位从空闲起步 / the phase starts from idle
    _eCause := E_DL_BwrCause.eNone; // 信息级成因清零 / clear the informational cause
    _eFaultCause := E_DL_BwrCause.eNone; // 故障级成因清零 / clear the fault cause
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _nWeekPrev := -1; // 周序号快照置非法值 / put the week snapshot at an illegal value
    _uCnt := 0; // 周内批次计数清零 / clear the weekly batch count
    _uGood := 0; // 本周好品清零 / clear the weekly good pieces
    _uScrap := 0; // 本周废品清零 / clear the weekly scrap pieces
END_IF

// 段 2｜复位沿作用域：清故障锁存 / 迁相位 / 清脉冲内部位（累计不清，避免产量丢失）/ segment 2, reset edge scope
IF rtReset.Q THEN // 复位沿 / reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaultCause := E_DL_BwrCause.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _eState := E_DL_BwrState.eIdle; // 作用域二：迁回空闲相 / scope two, migrate back to idle
    _bReadyInt := FALSE; // 作用域二：清就绪脉冲内部位 / scope two, clear the internal ready bit
END_IF

// 段 3｜组态域闸（R151 全覆盖）/ segment 3, configuration domain gate over every pin
_bCfgBad := FALSE; // 组态非法预置假 / preset the illegal configuration verdict to false
IF (nYear < DL_BWR_YEAR_MIN) OR (nYear > DL_BWR_YEAR_MAX) THEN // 年份越域 / year out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (nWeekOfYear < DL_BWR_WEEK_MIN) OR (nWeekOfYear > DL_BWR_WEEK_MAX) THEN // 周序号越域 / week index out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF tGateTime <= T#0S THEN // 闸超时非正 / gate timeout not positive
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF _bCfgBad AND (NOT _bFault) THEN // 组态非法且未锁存 / illegal configuration and not yet latched
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaultCause := E_DL_BwrCause.eCfgIllegal; // 故障级成因 (R45 配对 bError) / fault grade cause paired with bError
    _eState := E_DL_BwrState.eFault; // 迁故障相 / migrate to the fault phase
END_IF
_nWeekUse := nWeekOfYear; // 周序号直通 / week index passes through
IF _nWeekUse < DL_BWR_WEEK_MIN THEN // 下越界 / below the lower bound
    _nWeekUse := DL_BWR_WEEK_MIN; // 回钳到 1 / clamp to one
ELSIF _nWeekUse > DL_BWR_WEEK_MAX THEN // 上越界 / above the upper bound
    _nWeekUse := DL_BWR_WEEK_MAX; // 回钳到 53 / clamp to fifty three
END_IF
_uYearBase := INT_TO_UDINT(nYear) * DL_BWR_YEAR_MUL; // 批号年份基数，先落工作值 / the year base of the batch number lands in the working value

// 段 4｜周变更：锁存上周汇总、清本周累计、开周报闸 / segment 4, week rollover latches the last week summary, clears this week and opens the gate
_eCause := E_DL_BwrCause.eNone; // 信息级成因每拍重算 / the informational cause is recomputed every scan
IF _nWeekUse <> _nWeekPrev THEN // 周序号变化（首拍必命中）/ week changed, always true on the first scan
    _uLastG := _uGood; // 上周好品锁存（首拍为 0）/ latch the last week good pieces
    _uLastS := _uScrap; // 上周废品锁存（首拍为 0）/ latch the last week scrap pieces
    _nWeekPrev := _nWeekUse; // 周序号快照推进 / advance the week snapshot
    _uCnt := 0; // 本周批次计数清零 / clear the weekly batch count
    _uGood := 0; // 本周好品清零 / clear the weekly good pieces
    _uScrap := 0; // 本周废品清零 / clear the weekly scrap pieces
    _bReadyInt := TRUE; // 周报就绪脉冲内部位置位（统一出口映射，R187）/ raise the internal ready bit, mapped at the unified outlet
    _eState := E_DL_BwrState.eGate; // 开周报闸 / open the weekly report gate
    _eCause := E_DL_BwrCause.eWeekRoll; // 信息级成因：周变更已清零 / informational cause, the rollover cleared the accumulation
END_IF

// 段 5｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 5, phase machine with an ELSE fallback for illegal phases
CASE _eState OF
E_DL_BwrState.eIdle: // 空闲相：批次结束沿结算 / idle phase, settle on the batch end edge
    IF rtBatch.Q AND (NOT _bFault) THEN // 批次结束沿且无故障 / batch end edge without a fault
        _bCntSat := FALSE; // 饱和标志复位 / clear the saturation flag
        IF _uCnt < _uClampMax THEN // 未达饱和上限 / below the saturation ceiling
            _uCnt := _uCnt + 1; // 批次计数递增 / increment the batch count
        ELSE
            _bCntSat := TRUE; // 置饱和标志 / raise the saturation flag
        END_IF
        IF (_uGood + uBatchGood) < _uGood THEN // 好品累加回绕 / the good accumulation wrapped around
            _uGood := DL_BWR_CNT_CEIL; // 饱和到上限 / saturated at the ceiling
        ELSE
            _uGood := _uGood + uBatchGood; // 好品累加 / accumulate the good pieces
        END_IF
        IF (_uScrap + uBatchScrap) < _uScrap THEN // 废品累加回绕 / the scrap accumulation wrapped around
            _uScrap := DL_BWR_CNT_CEIL; // 饱和到上限 / saturated at the ceiling
        ELSE
            _uScrap := _uScrap + uBatchScrap; // 废品累加 / accumulate the scrap pieces
        END_IF
        _uTail := _uCnt MOD DL_BWR_TAIL_MOD; // 批号尾位，取模除子为常量十 / batch number tail with the constant divisor ten
        _uBatchNo := _uYearBase + INT_TO_UDINT(_nWeekUse) * DL_BWR_WEEK_MUL + _uTail; // 周批号合成 / compose the weekly batch number
    END_IF

E_DL_BwrState.eGate: // 周报闸相：确认沿或超时关闸 / report gate phase, closed by the acknowledgement edge or the timeout
    IF rtAck.Q OR tonGate.Q THEN // 确认或超时 / acknowledged or timed out
        _eState := E_DL_BwrState.eIdle; // 关闸回空闲相 / close the gate and return to idle
    END_IF
    IF rtBatch.Q AND (NOT _bFault) THEN // 闸开期间仍有批次结束 / a batch still ends while the gate is open
        IF _uCnt < _uClampMax THEN // 未达饱和上限 / below the saturation ceiling
            _uCnt := _uCnt + 1; // 批次计数照常递增 / the batch count still increments
        END_IF
        _uTail := _uCnt MOD DL_BWR_TAIL_MOD; // 批号尾位重算 / recompute the batch number tail
        _uBatchNo := _uYearBase + INT_TO_UDINT(_nWeekUse) * DL_BWR_WEEK_MUL + _uTail; // 周批号重算 / recompose the weekly batch number
    END_IF

E_DL_BwrState.eFault: // 故障相：锁存回放，等复位沿 / fault phase, the latch is replayed until the reset edge
    _bReadyInt := FALSE; // 故障拍不出就绪脉冲 / no ready pulse while faulted

ELSE // 非法相位兜底（R128）/ illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaultCause := E_DL_BwrCause.eCfgIllegal; // 故障级成因记组态非法 / record the illegal configuration cause
    _eState := E_DL_BwrState.eFault; // 迁故障相 / migrate to the fault phase
END_CASE

// 段 6｜失能与良率计算 / segment 6, disabled semantics and the yield computation
IF NOT bEnable THEN // 失能 / disabled
    _eState := E_DL_BwrState.eIdle; // 关闸回空闲相 / close the gate and return to idle
    _bReadyInt := FALSE; // 撤就绪脉冲内部位 / withdraw the internal ready bit
END_IF
_uTotLoc := _uGood + _uScrap; // 良率分母先落局部量 / the yield denominator lands in a local first
IF _uTotLoc < _uGood THEN // 相加回绕 / the sum wrapped around
    _uTotLoc := DL_BWR_CNT_CEIL; // 饱和到上限 / saturated at the ceiling
END_IF
IF _uTotLoc > 0 THEN // 分母可用 / the denominator is usable
    _fYield := UDINT_TO_REAL(_uGood) / UDINT_TO_REAL(_uTotLoc) * 100.0; // 良率，除子已证大于零 / yield, divisor proven positive
    IF _fYield > DL_BWR_YIELD_MAX THEN // 良率越上限 / yield above the ceiling
        _fYield := DL_BWR_YIELD_MAX; // 上钳 / clamp upward
    END_IF
ELSE
    _fYield := 0.0; // 无产量时良率记零 / zero yield when nothing was produced
END_IF

// 段 7｜统一出口 / segment 7, unified outlet
bReportGate := (_eState = E_DL_BwrState.eGate); // 闸开指示（挂状态量）/ gate open indicator as a state quantity
bReportReady := _bReadyInt; // 就绪脉冲映射本拍值 / map the ready pulse for this scan
_bReadyInt := FALSE; // 映射后立即撤销，保证单拍宽度（R187 两段式）/ revoke right after mapping to keep a single-scan width
uBatchNo := _uBatchNo; // 周批号出口（锁存量）/ weekly batch number outlet from the latch
nWeekActive := _nWeekUse; // 生效周序号出口 / active week index outlet
uWeekBatchCnt := _uCnt; // 本周批次计数出口 / weekly batch count outlet
uWeekGood := _uGood; // 本周好品出口 / weekly good outlet
uWeekScrap := _uScrap; // 本周废品出口 / weekly scrap outlet
uLastWeekGood := _uLastG; // 上周好品出口 / last week good outlet
uLastWeekScrap := _uLastS; // 上周废品出口 / last week scrap outlet
fWeekYield := _fYield; // 本周良率出口 / weekly yield outlet
eState := _eState; // 相位出口单点映射 / single-point phase outlet mapping
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eCause := _eFaultCause; // 故障级成因锁存回放 / the fault cause is replayed from the latch
ELSIF _bCntSat THEN // 计数饱和 / the counter saturated
    eCause := E_DL_BwrCause.eCntSat; // 信息级成因 / informational cause
ELSE
    eCause := _eCause; // 信息级成因直映 / the informational cause is mapped directly
END_IF
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
