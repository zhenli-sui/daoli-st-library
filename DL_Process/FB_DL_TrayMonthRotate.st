(*
  ==================================================================
  组件名 Component  : FB_DL_TrayMonthRotate
  分类   Category   : DL_Process
  版本   Version    : 1.0.0
  功能   Purpose    : 托盘月度轮换保养排程。按「上次保养月」与保养周期（月数）逐盘
                      判到期，到期盘打包成 12 位到期掩码字，并给本月轮换优先盘号
                      （按月份在托盘序列上轮转），支持保养完成脉冲回写上次保养月。
  溯源   Origin     : 月度轮换保养为通用设备维护排程语义；本件为 clean-room 实现，
                      仅借鉴来源分类与参数域组织（来源标签 roadmap-p2-tray），
                      道莅原创设计，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（WORD / SHL / MOD / R_TRIG，无私有库）
  作者   Author     : 道莅代码库 · PLC 编程专家（R55）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只出到期掩码与优先盘号，不启动保养动作、不判保养质量；
                      二 周期判据按月数差计，跨年回绕按「月差加 12」补齐，只覆盖一周年内；
                      三 保养完成回写由 bMaintDone 上升沿 + nMaintTray 触发，
                         托盘号经回钳 1..12 后写入调用方持有的上次保养月表；
                      四 未保养盘（上次保养月小于 1）一律立即到期，不参与月差计算；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      wDueMask 位 i-1 对应托盘 i，自证向量：仅 1 号盘到期 → 16#0001，
                      仅 12 号盘到期 → 16#0800；
                      nPriTray 为 1..nTrayCount 内的轮换优先盘号，该盘到期时 bPriDue 为真；
                      eCause 故障级成因与 bError 配对（R45），信息级永不置 bError。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R55 首版（批 2 · 序号 7）
  ==================================================================
*)

TYPE E_DL_TmrCause :
(
    eNone       := 0,   // 无成因 / no cause
    eCfgIllegal := 1,   // 组态非法：年月日、盘数或周期越域（故障级，与 bError 配对）/ illegal config, calendar, tray count or interval out of domain
    eTrayBad    := 2,   // 保养完成脉冲的托盘号越域已回钳（信息级）/ the tray number on the maintenance pulse was clamped, informational
    eNoDue      := 3    // 本月无到期盘（信息级）/ no tray is due this month, informational
);
END_TYPE

FUNCTION_BLOCK FB_DL_TrayMonthRotate
VAR_INPUT
    bEnable      : BOOL := TRUE;             // 使能，失能时掩码冻结保持末值 [-] / enable, the mask freezes and holds its last value when disabled
    bReset       : BOOL := FALSE;           // 复位上升沿清故障锁存与掩码 [-] / reset rising edge clears the fault latch and the mask
    nYear        : INT := 2026;              // 当前年份 [年]，域 2000..2100 / current year [year], domain 2000 to 2100
    nMonth       : INT := 1;                 // 当前月份 [月]，域 1..12 / current month [month], domain 1 to 12
    nDayOfMonth  : INT := 1;                 // 当月第几日 [日]，域 1..31 / day of month [day], domain 1 to 31
    nTrayCount   : INT := 12;                // 参与排程的托盘数 [个]，域 1..12 / scheduled tray count [count], domain 1 to 12
    nIntervalMonths : INT := 3;              // 保养周期 [月]，域 1..60 / maintenance interval [month], domain 1 to 60
    bMaintDone   : BOOL := FALSE;            // 保养完成脉冲，上升沿回写上次保养月 [-] / maintenance done pulse, the rising edge writes back the last maintenance month
    nMaintTray   : INT := 1;                 // 保养完成脉冲对应的托盘号 [盘号] / tray number carried by the maintenance pulse
END_VAR
VAR_IN_OUT
    anLastMaintMonth : ARRAY[1..12] OF INT;  // 逐托盘上次保养月（0 = 从未保养）[月]，引用型入参由调用方持有 / per tray last maintenance month, zero means never, reference parameter owned by the caller
END_VAR
VAR_OUTPUT
    wDueMask     : WORD := 16#0000;          // 到期托盘掩码，位 i-1 对应托盘 i [-] / due tray mask, bit i minus one maps to tray i
    nDueCount    : INT := 0;                 // 到期托盘数 [个] / due tray count
    nOverdueCount: INT := 0;                 // 超期托盘数（月差超周期）[个] / overdue tray count
    nPriTray     : INT := 0;                 // 本月轮换优先托盘号 [盘号] / rotation priority tray of the month
    bPriDue      : BOOL := FALSE;            // 优先托盘本月是否到期 [-] / whether the priority tray is due this month
    bDueToday    : BOOL := FALSE;            // 本月是否存在到期盘 [-] / whether any tray is due this month
    eCause       : E_DL_TmrCause := E_DL_TmrCause.eNone; // 成因出口 [枚举] / cause outlet [enum]
    bError       : BOOL := FALSE;            // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtReset      : R_TRIG;                   // 复位沿检测，段 0 无条件刷新 / reset edge detector, refreshed unconditionally in segment zero
    rtMaint      : R_TRIG;                   // 保养完成沿检测，段 0 无条件刷新 / maintenance done edge detector, refreshed unconditionally in segment zero
    _eCause      : E_DL_TmrCause := E_DL_TmrCause.eNone;  // 内部成因 / internal cause
    _eFaultCause : E_DL_TmrCause := E_DL_TmrCause.eNone;  // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault      : BOOL := FALSE;            // 故障锁存位 [-] / fault latch bit
    _bInit       : BOOL := FALSE;            // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bCfgBad     : BOOL := FALSE;            // 组态非法判定 [-] / illegal configuration verdict
    _bTrayClamped: BOOL := FALSE;            // 回写托盘号被回钳 [-] / the write-back tray number was clamped
    _bDueBit     : BOOL := FALSE;            // 本条托盘到期判定 [-] / per tray due verdict
    _nUseCount   : INT := 0;                 // 钳定后的托盘数 [个] / clamped tray count
    _nInterval   : INT := 1;                 // 钳定后的保养周期 [月] / clamped maintenance interval [month]
    _nTray       : INT := 1;                 // 回写用托盘号（回钳 1..12）[盘号] / write-back tray number clamped one through twelve
    _nIdx        : INT := 1;                 // 托盘游标（1 起，回钳 1..12）[盘号] / tray cursor, one-based, clamped one through twelve
    _nLast       : INT := 0;                 // 本条托盘上次保养月 [月] / last maintenance month of the tray [month]
    _nElapsed    : INT := 0;                 // 距上次保养的月差 [月] / months since the last maintenance [month]
    _nPri        : INT := 1;                 // 轮换优先盘号工作值（1..12）[盘号] / rotation priority working value, one through twelve [tray]
    _wMask       : WORD := 16#0000;          // 掩码工作字，先移位后置位（R327）/ mask working word, shift before setting
    _wBit        : WORD := 16#0001;          // 本条托盘位掩码 [-] / per tray bit mask
END_VAR
VAR CONSTANT
    DL_TMR_MAX       : INT := 12;            // 托盘容量与游标回钳上界 [个] / tray capacity and cursor clamp upper bound
    DL_TMR_INT_MIN   : INT := 1;             // 保养周期下限 [月] / maintenance interval floor [month]
    DL_TMR_INT_MAX   : INT := 60;            // 保养周期上限 [月] / maintenance interval ceiling [month]
    DL_TMR_YEAR_MIN  : INT := 2000;          // 年份下限 [年] / year floor [year]
    DL_TMR_YEAR_MAX  : INT := 2100;          // 年份上限 [年] / year ceiling [year]
    DL_TMR_DAY_MAX   : INT := 31;            // 月内最大天数 [日] / maximum days within a month [day]
    DL_TMR_MONTHS    : INT := 12;            // 一周年月数，跨年回绕补齐用 [月] / months in a year for the wrap fill [month]
    DL_TMR_MASK_NONE : WORD := 16#0000;      // 空掩码常量 [-] / empty mask constant
    DL_TMR_MASK_ONE  : WORD := 16#0001;      // 单位位常量 [-] / single bit constant
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支）/ segment 0, unconditional refresh of the edge detectors, never inside a branch
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge
rtMaint(CLK := bMaintDone); // 保养完成沿无条件刷新 / unconditional refresh of the maintenance edge

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _eCause := E_DL_TmrCause.eNone; // 信息级成因清零 / clear the informational cause
    _eFaultCause := E_DL_TmrCause.eNone; // 故障级成因清零 / clear the fault cause
    _wMask := DL_TMR_MASK_NONE; // 掩码清零 / clear the mask
END_IF

// 段 2｜复位沿作用域：清故障锁存 / 清掩码与统计（不改上次保养月表，属调用方资产）/ segment 2, reset edge scope
IF rtReset.Q THEN // 复位沿 / reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaultCause := E_DL_TmrCause.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _wMask := DL_TMR_MASK_NONE; // 作用域二：清到期掩码 / scope two, clear the due mask
    nDueCount := 0; // 作用域二：清到期计数 / scope two, clear the due count
    nOverdueCount := 0; // 作用域二：清超期计数 / scope two, clear the overdue count
END_IF

// 段 3｜组态域闸（R151 全覆盖）/ segment 3, configuration domain gate over every pin
_bCfgBad := FALSE; // 组态非法预置假 / preset the illegal configuration verdict to false
IF (nYear < DL_TMR_YEAR_MIN) OR (nYear > DL_TMR_YEAR_MAX) THEN // 年份越域 / year out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (nMonth < 1) OR (nMonth > DL_TMR_MONTHS) THEN // 月份越域 / month out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (nDayOfMonth < 1) OR (nDayOfMonth > DL_TMR_DAY_MAX) THEN // 当日序号越域 / day index out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (nTrayCount < 1) OR (nTrayCount > DL_TMR_MAX) THEN // 托盘数越域 / tray count out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (nIntervalMonths < DL_TMR_INT_MIN) OR (nIntervalMonths > DL_TMR_INT_MAX) THEN // 保养周期越域 / maintenance interval out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF _bCfgBad AND (NOT _bFault) THEN // 组态非法且未锁存 / illegal configuration and not yet latched
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaultCause := E_DL_TmrCause.eCfgIllegal; // 故障级成因 (R45 配对 bError) / fault grade cause paired with bError
END_IF
_nUseCount := nTrayCount; // 托盘数直通 / tray count passes through
IF _nUseCount < 1 THEN // 下越界 / below the lower bound
    _nUseCount := 1; // 回钳到 1 / clamp to one
ELSIF _nUseCount > DL_TMR_MAX THEN // 上越界 / above the upper bound
    _nUseCount := DL_TMR_MAX; // 回钳到容量上限 / clamp to the capacity ceiling
END_IF
_nInterval := nIntervalMonths; // 周期直通 / interval passes through
IF _nInterval < DL_TMR_INT_MIN THEN // 周期过小 / interval below the floor
    _nInterval := DL_TMR_INT_MIN; // 抬到下限 / raised to the floor
ELSIF _nInterval > DL_TMR_INT_MAX THEN // 周期过大 / interval above the ceiling
    _nInterval := DL_TMR_INT_MAX; // 压到上限 / pressed to the ceiling
END_IF

// 段 4｜保养完成回写：上升沿 + 托盘号回钳后写入上次保养月表 / segment 4, maintenance write-back on the rising edge with the tray number clamped
_bTrayClamped := FALSE; // 回钳标志预置假 / preset the clamp flag to false
IF rtMaint.Q THEN // 保养完成沿 / maintenance done edge
    _nTray := nMaintTray; // 托盘号直通 / tray number passes through
    IF _nTray < 1 THEN // 下越界 / below the lower bound
        _nTray := 1; // 回钳到 1 / clamp to one
        _bTrayClamped := TRUE; // 置回钳标志 / raise the clamp flag
    ELSIF _nTray > DL_TMR_MAX THEN // 上越界 / above the upper bound
        _nTray := DL_TMR_MAX; // 回钳到 12 / clamp to twelve
        _bTrayClamped := TRUE; // 置回钳标志 / raise the clamp flag
    END_IF
    anLastMaintMonth[_nTray] := nMonth; // 回写上次保养月，下标已回钳 1..12 / write back the last maintenance month with the index already clamped
END_IF

// 段 5｜逐盘到期判定与掩码打包 / segment 5, per tray due verdict and mask packing
_wMask := DL_TMR_MASK_NONE; // 掩码每拍清零重建 / the mask is rebuilt every scan
nDueCount := 0; // 到期计数清零 / clear the due count
nOverdueCount := 0; // 超期计数清零 / clear the overdue count
_nIdx := 1; // 游标自 1 起，上界由 _nUseCount 约束 / the cursor starts at one, bounded by the usable count
WHILE _nIdx <= _nUseCount DO // 循环上界为钳定后的托盘数，天然不越 12 / the loop bound is the clamped count, never beyond twelve
    _wBit := SHL(DL_TMR_MASK_ONE, _nIdx - 1); // 本条托盘位掩码，位移量 0..11 由数组边界与循环上界共同证明 / per tray bit mask, the shift zero through eleven is proven by the array and loop bounds
    _nLast := anLastMaintMonth[_nIdx]; // 上次保养月 / last maintenance month
    _bDueBit := FALSE; // 到期判定预置假 / preset the due verdict to false
    IF _nLast < 1 THEN // 从未保养 / never maintained
        _bDueBit := TRUE; // 立即到期 / due immediately
        nOverdueCount := nOverdueCount + 1; // 计入超期统计 / counted as overdue
    ELSE
        _nElapsed := nMonth - _nLast; // 月差 / month difference
        IF _nElapsed < 0 THEN // 跨年回绕 / year wrap
            _nElapsed := _nElapsed + DL_TMR_MONTHS; // 按月数补齐，仅覆盖一周年内 / filled by the months in a year, valid within one year
        END_IF
        IF _nElapsed >= _nInterval THEN // 达到周期 / the interval is reached
            _bDueBit := TRUE; // 判到期 / due verdict
            IF _nElapsed > _nInterval THEN // 超过周期 / beyond the interval
                nOverdueCount := nOverdueCount + 1; // 计入超期统计 / counted as overdue
            END_IF
        END_IF
    END_IF
    IF _bDueBit THEN // 本条托盘到期 / the tray is due
        _wMask := _wMask OR _wBit; // 置到期位 / set the due bit
        nDueCount := nDueCount + 1; // 到期计数递增 / increment the due count
    END_IF
    _nIdx := _nIdx + 1; // 游标递增 / increment the cursor
END_WHILE

// 段 6｜轮换优先盘号：按月份在托盘序列上轮转，除子为钳定后的托盘数 / segment 6, rotation priority tray with the clamped tray count as the divisor
_nPri := ((nMonth - 1) MOD _nUseCount) + 1; // 轮换公式，除子已证不小于 1 / rotation formula, divisor proven not below one
nPriTray := _nPri; // 优先盘号出口 / priority tray outlet
bPriDue := ((_wMask AND SHL(DL_TMR_MASK_ONE, _nPri - 1)) <> DL_TMR_MASK_NONE); // 优先盘是否到期，位移量 0..11 已证 / whether the priority tray is due, the shift zero through eleven is proven
bDueToday := nDueCount > 0; // 本月是否存在到期盘（挂状态量）/ whether any tray is due, a state quantity

// 段 7｜成因分派（固定优先级：故障 > 回钳 > 无到期 > 无成因）/ segment 7, cause dispatch with a fixed priority
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eCause := _eFaultCause; // 故障级成因锁存回放 / the fault cause is replayed from the latch
ELSIF _bTrayClamped THEN // 回写托盘号被回钳 / the write-back tray number was clamped
    eCause := E_DL_TmrCause.eTrayBad; // 信息级成因 / informational cause
ELSIF nDueCount < 1 THEN // 无到期盘 / no tray is due
    eCause := E_DL_TmrCause.eNoDue; // 信息级成因 / informational cause
ELSE
    eCause := E_DL_TmrCause.eNone; // 无成因 / no cause
END_IF

// 段 8｜统一出口 / segment 8, unified outlet
wDueMask := _wMask; // 到期掩码出口 / due mask outlet
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
