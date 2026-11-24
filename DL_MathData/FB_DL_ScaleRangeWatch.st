(*
    FB_DL_ScaleRangeWatch —— 工程量标定区间越界监视（回差 + 延时确认 + 故障锁存）
    ------------------------------------------------------------------
    组件名称  : FB_DL_ScaleRangeWatch
    分类      : DL_MathData / Scaling
    前缀      : FB_DL_
    版本      : 1.0.1
    溯源      : 借鉴点 —— 过程仪表标定链的通行三段式：原始码 → 工程量线性换算
                → 带迟滞与延时确认的上下限越界判定；该「换算 + 越界监测」组合
                在开源数学/测量库族中属常见语义，本件借鉴其**判据顺序与迟滞口径**，
                不借用其任何数据结构、命名或代码组织。
                clean-room 声明 —— 零代码行复制；换算仅用标准运算符，定时与
                沿检测仅用 IEC 61131-3 标准库 TON / R_TRIG。
                许可证 —— 本件 MIT；来源标签 lgf-math 仅作语义参考，
                本件不包含、不派生其任何受版权保护的实现。
    平台      : 纯 IEC 61131-3，CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R70 构建轮 · 批 1 · N3）
    ------------------------------------------------------------------
    功能说明  : fEng = fRaw * fGain + fOffset，随后对 fEng 判上下限：
                越过 fHighLim 且持续 tConfirm 才置 bHighAlarm，跌回
                fHighLim - fHyst 才复位；下限对称（fLowLim / fLowLim + fHyst）。
                定时器无条件周期调用（规则 ⑦），IN 用显式条件表达式，
                且条件中已把「已报警自保持」并入，故复位只由回差线决定，
                不存在无回差抖振。
                故障锁存口径（R187 / R189）：组态非法或原始值非有限 → 锁存首个
                成因码至 _nCodeLatch，bReset 上升沿解除；**故障期内不按当下输入
                重新推断成因**，一律回放锁存码，避免成因漂移。
                换算除法面：本件无除法（增益为乘子），无除零面；
                但增益为 0 属**增益零域**（v1.0.1 起拦截，见边界六）：
                fGain = 0.0 时 fEng ≡ fOffset，工程量被钉死在偏置值，
                上下限报警将永久不触发（保护静默失效），故按组态非法处理。
    错误码    : 16#0002_0121 组态非法（v1.0.1 起含增益零域成因），锁存，输出清零 —— 故障级
                16#0002_0122 原始值非有限，锁存，输出保持末次良好工程值 —— 故障级
    码位总账  : 16#0002_0121 用 ｜ 16#0002_0122 用
    状态机    : N/A —— 单相监视，无顺序状态机，无 ENUM / CASE 可写；
                两路确认计时由 TON 实例自持，属定时器状态而非顺序状态
    边界与披露: 一 组态判据逐项点名（R272）：fGain / fOffset / fHighLim / fLowLim /
                   fHyst 全部纳入非有限闸；fHighLim <= fLowLim 拦截；fHyst < 0 拦截；
                   fHyst >= (fHighLim - fLowLim) 拦截（迟滞吞没整带时上下限无回差带，
                   判据恒真）；tConfirm < T#0S 不可表示，故不设该判据；
                二 输入非有限时 fEng 输出**保持末次良好值**（_bHaveGood 为真才输出，
                   否则输出 0.0），并在头注释声明该保持语义（R191 名实双出口）；
                三 失能（bEn = FALSE）语义写死（R303）：fEng 输出 0.0、bHighAlarm /
                   bLowAlarm / bInBand / bBusy 全清零、nErrCode 清零、bError 清零，
                   但 _bFault 锁存位**不被失能清除**（失能是操作态，不是复位），
                   必须 bReset 上升沿才解除 —— 两者语义分离，避免失能顺手清故障；
                四 定时器 _tonHigh / _tonLow 无论失能 / 故障 / 正常均在段 9 无条件调用，
                   IN 为段 8 计算出的显式条件，未放入任何可能被跳过的分支；
                五 量程零域拦截路径（v1.0.1 点修，缺陷 H4）：fGain = 0.0（增益零域，
                   判据 ABS(fGain) <= DL_SRW_GMIN，GMIN = 1.0E-15）时 fEng ≡ fOffset，
                   工程量被钉死在偏置值，上下限报警永久不触发且无任何故障码 ——
                   保护静默失效，比除零更隐蔽；v1.0.1 起段 4 组态闸并联该判据，
                   增益零域 → 码 0121 组态锁存、段 8 换算段结构性不可达、报警不静默；
                六 零域第二道判据（v1.0.0 既有，H2 复核确认）：fHighLim <= fLowLim
                   对 fHighLim = fLowLim 的零带宽路径同样拦截，两道判据冗余覆盖
                   零量程，不存在可进入段 8 换算段的零域反例向量（±1E30 极端
                   幅值下带宽差 <= 2E30 < LREAL 域，无溢出面）；
                七 复位解除当拍语义（H3 披露，行为不变）：段 3 清锁存与段 6 同拍
                   重判组态发生在同一扫描周期，组态仍非法则同拍重锁存 —— 与
                   R189 口径一致，非缺陷，仅声明；
                八 段 8 非有限换算分支就地锁存 0121，不含「增益 × 原始值溢出」
                   独立成因项 —— 溢出归因为组态域外（增益超域），与 R190 归因
                   唯一口径不冲突，声明即可；
                九 零全局变量、零 VAR_EXTERNAL、零物理地址、零数组下标。
    修订记录  : 2026-11-22 v1.0.0 首次入库（R70 构建轮 · 批 1 · N3）
                2026-11-22 v1.0.1 点修（R71 · 批 1 · 序号 1）：段 4 组态闸并联
                增益零域判据 ABS(fGain) <= DL_SRW_GMIN（缺陷 H4，R70 挂账复核），
                新增常量 DL_SRW_GMIN = 1.0E-15；码位沿用 16#0002_0121 不新开；
                头注释补量程零域拦截路径披露与复位当拍重锁存语义声明；
                不改引脚、不改其他段行为（H1 文档-源码口径漂移已以源码实测对账）。
*)
FUNCTION_BLOCK FB_DL_ScaleRangeWatch
VAR_INPUT
    fRaw      : LREAL;                     (* 原始值（未标定，可为 ADC 码或物理量），[原始单位] / the raw unscaled value *)
    fGain     : LREAL := 1.0;              (* 标定增益（斜率），[工程单位/原始单位] / the calibration gain, the slope *)
    fOffset   : LREAL := 0.0;              (* 标定偏置（截距），[工程单位] / the calibration offset, the intercept *)
    fHighLim  : LREAL := 100.0;            (* 上限判据值，[工程单位]，须 > fLowLim / the upper limit, must exceed fLowLim *)
    fLowLim   : LREAL := 0.0;              (* 下限判据值，[工程单位]，须 < fHighLim / the lower limit, must be under fHighLim *)
    fHyst     : LREAL := 0.0;              (* 回差带宽，[工程单位]，域 [0, fHighLim - fLowLim) / the hysteresis band *)
    tConfirm  : TIME := T#1S;              (* 越界确认延时，[ms]，须 >= T#0S / the out-of-range confirmation delay *)
    bEn       : BOOL := TRUE;              (* 使能，[标志]，FALSE 时出口清零（R303）/ the enable, FALSE clears the outlets *)
    bReset    : BOOL := FALSE;             (* 故障复位，[标志]，上升沿解除锁存 / the reset, its rising edge clears the latch *)
END_VAR
VAR_OUTPUT
    fEng      : LREAL;                     (* 换算后工程值，[工程单位] / the scaled engineering value *)
    bHighAlarm : BOOL;                     (* 上限越界报警（回差 + 延时确认后），[标志] / the high limit alarm *)
    bLowAlarm : BOOL;                      (* 下限越界报警（回差 + 延时确认后），[标志] / the low limit alarm *)
    bInBand   : BOOL;                      (* 工程值在带内（两侧报警均为假），[标志] / the value sits inside the band *)
    bBusy     : BOOL;                      (* 确认计时进行中（越界已出现但未满延时），[标志] / a confirmation timer is running *)
    bValid    : BOOL;                      (* 输出可用，故障或失能为 FALSE / the outlets are usable *)
    bError    : BOOL;                      (* 故障标志，存在锁存故障时为 TRUE / the fault flag, raised on a latched fault *)
    nErrCode  : UDINT;                     (* 错误码，0 = 正常，锁存回放 / the error id, 0 = ok, replayed from the latch *)
END_VAR
VAR
    _rtReset   : R_TRIG;                   (* 复位上升沿检测实例（无条件调用）/ the reset rising edge instance *)
    _tonHigh   : TON;                      (* 上限确认延时实例（无条件调用）/ the high limit confirmation timer *)
    _tonLow    : TON;                      (* 下限确认延时实例（无条件调用）/ the low limit confirmation timer *)
    _bFault    : BOOL;                     (* 故障锁存位，仅 bReset 上升沿解除 / the latched fault bit *)
    _nCodeLatch : UDINT;                   (* 锁存成因码，故障期回放 / the latched cause code, replayed while faulted *)
    _bCfgBad   : BOOL;                     (* 组态非法标志（逐拍重算，仅用于首次锁存）/ the configuration fault flag *)
    _bInBad    : BOOL;                     (* 原始值非有限标志（逐拍重算，仅用于首次锁存）/ the input fault flag *)
    _bRun      : BOOL;                     (* 运行许可 = 使能 且 无锁存故障 / the run permit *)
    _bHighCond : BOOL;                     (* 上限确认条件（含自保持与回差，送 TON）/ the high confirmation condition *)
    _bLowCond  : BOOL;                     (* 下限确认条件（含自保持与回差，送 TON）/ the low confirmation condition *)
    _fEngTmp   : LREAL;                    (* 换算中间量，[工程单位] / the scaling temporary *)
    _fLastGood : LREAL;                    (* 末次良好工程值，[工程单位] / the last good engineering value *)
    _bHaveGood : BOOL;                     (* 已获得过良好值，[标志] / a good value has been seen *)
END_VAR
VAR CONSTANT
    DL_SRW_FMAX : LREAL := 1.0E30;         (* 非有限筛查幅值上限，[工程单位] / the finiteness screening cap *)
    DL_SRW_GMIN : LREAL := 1.0E-15;        (* 增益零域判据阈值，|fGain| <= 此值视为零增益组态非法，[无量纲] / the zero-gain threshold, |fGain| <= this means an illegal zero-gain configuration *)
END_VAR

// 段 1｜出口预置（统一出口预置，R256）/ segment 1, preset every outlet
fEng       := 0.0;                         // 工程值预置 0.0 / preset the engineering value to zero
bHighAlarm := FALSE;                       // 上限报警预清零 / preset the high alarm false
bLowAlarm  := FALSE;                       // 下限报警预清零 / preset the low alarm false
bInBand    := FALSE;                       // 带内标志预清零 / preset the in-band flag false
bBusy      := FALSE;                       // 忙碌标志预清零 / preset the busy flag false
bValid     := FALSE;                       // 可用标志预清零 / preset the valid flag false
bError     := FALSE;                       // 故障标志预清零 / preset the error flag false
nErrCode   := 0;                           // 错误码预置无错 / preset the code to zero
_bHighCond := FALSE;                       // 上限条件预清零 / preset the high condition false
_bLowCond  := FALSE;                       // 下限条件预清零 / preset the low condition false

// 段 2｜复位沿检测（无条件调用，规则 ⑦）/ segment 2, the reset edge instance, called unconditionally
_rtReset(CLK := bReset);                   // 每周期无条件刷新 / refreshed every scan without exception

// 段 3｜锁存解除：仅 bReset 上升沿，锁存码同步清零 / segment 3, the latch release on the reset rising edge
IF _rtReset.Q THEN                         // 复位上升沿 / the reset rising edge
    _bFault     := FALSE;                  // 解除故障锁存 / release the fault latch
    _nCodeLatch := 0;                      // 清锁存码（可到达的清除边，R188）/ clear the latched code, a reachable clearing edge
END_IF

// 段 4｜组态守卫（边界一逐项点名 + 增益零域 H4，R272）/ segment 4, the configuration guard
_bCfgBad := (fHighLim <= fLowLim)                                        // 上下限反置或重合（兼拦零带宽，边界六）/ the limits reversed or coincident
         OR (fHyst < 0.0)                                                // 回差为负 / a negative hysteresis
         OR (fHyst >= (fHighLim - fLowLim))                              // 回差吞没整带 / the hysteresis swallows the band
         OR (ABS(fGain) <= DL_SRW_GMIN)                                  // 增益零域（H4，v1.0.1 起拦截）/ the zero-gain domain, intercepted since v1.0.1
         OR (fGain <> fGain) OR ((fGain - fGain) <> 0.0) OR (ABS(fGain) > DL_SRW_FMAX)        // 增益非有限 / the gain non finite
         OR (fOffset <> fOffset) OR ((fOffset - fOffset) <> 0.0) OR (ABS(fOffset) > DL_SRW_FMAX) // 偏置非有限 / the offset non finite
         OR (fHighLim <> fHighLim) OR ((fHighLim - fHighLim) <> 0.0) OR (ABS(fHighLim) > DL_SRW_FMAX) // 上限非有限 / the upper limit non finite
         OR (fLowLim <> fLowLim) OR ((fLowLim - fLowLim) <> 0.0) OR (ABS(fLowLim) > DL_SRW_FMAX)      // 下限非有限 / the lower limit non finite
         OR (fHyst <> fHyst) OR ((fHyst - fHyst) <> 0.0) OR (ABS(fHyst) > DL_SRW_FMAX);               // 回差非有限 / the hysteresis non finite

// 段 5｜输入守卫（NaN 自反判 + Inf 差值自反判 + 幅值上界）/ segment 5, the raw input guard
_bInBad := (fRaw <> fRaw) OR ((fRaw - fRaw) <> 0.0) OR (ABS(fRaw) > DL_SRW_FMAX); // 原始值非有限 / the raw value non finite

// 段 6｜首次成因锁存（故障期内不重推断，回放锁存码，R189）/ segment 6, the first-cause latch
IF NOT _bFault THEN                        // 未锁存时才有资格登记成因 / a cause is registered only while not latched
    IF _bCfgBad THEN                       // 组态非法（优先归因，组态是根因）/ an illegal configuration, the root cause first
        _bFault     := TRUE;               // 置故障锁存 / latch the fault
        _nCodeLatch := 16#0002_0121;       // 故障级：组态非法 / fault level: the configuration is illegal
    ELSIF _bInBad THEN                     // 原始值非有限 / the raw value is non finite
        _bFault     := TRUE;               // 置故障锁存 / latch the fault
        _nCodeLatch := 16#0002_0122;       // 故障级：输入非有限 / fault level: the input is non finite
    END_IF
END_IF

// 段 7｜运行许可：失能或锁存故障即退出换算 / segment 7, the run permit
_bRun := bEn AND NOT _bFault;              // 使能且无锁存故障 / enabled and not latched

// 段 8｜换算与条件计算（分支内不调用任何定时器）/ segment 8, the scaling and the conditions
IF _bRun THEN                              // 运行许可成立 / the run permit holds
    _fEngTmp := fRaw * fGain + fOffset;    // 工程量换算（委托 `*` 与 `+`）/ the engineering conversion, delegated
    IF (_fEngTmp <> _fEngTmp) OR ((_fEngTmp - _fEngTmp) <> 0.0) THEN // 换算结果非有限（增益超域导致）/ the result non finite
        _bFault     := TRUE;               // 就地锁存（增益巨大导致的溢出同属组态问题）/ latch in place
        _nCodeLatch := 16#0002_0121;       // 故障级：组态非法（增益域外）/ fault level: an illegal configuration
        fEng        := _fLastGood;         // 保持末次良好值（R191 名实双出口）/ hold the last good value
        bValid      := _bHaveGood;         // 有良好值才可用 / usable only if a good value was seen
        bError      := TRUE;               // 故障标志置位 / raise the fault flag
        nErrCode    := _nCodeLatch;        // 回放锁存码 / replay the latched code
    ELSE                                   // 换算结果有限 / the result is finite
        _fLastGood := _fEngTmp;            // 刷新末次良好值 / refresh the last good value
        _bHaveGood := TRUE;                // 标记已有良好值 / mark that a good value exists
        fEng       := _fEngTmp;            // 工程值出口 / the engineering outlet
        _bHighCond := (fEng > fHighLim) OR (_tonHigh.Q AND NOT (fEng < (fHighLim - fHyst))); // 上限条件：置位线或「已报警且未破回差线」
        _bLowCond  := (fEng < fLowLim) OR (_tonLow.Q AND NOT (fEng > (fLowLim + fHyst)));    // 下限条件：置位线或「已报警且未破回差线」
    END_IF
ELSE                                       // 失能或锁存故障 / disabled or latched
    bValid   := FALSE;                     // 输出不可用 / the outlets are unusable
    _bHighCond := FALSE;                   // 条件清零，计时器随之复位 / clear the condition, the timer resets
    _bLowCond  := FALSE;                   // 条件清零 / clear the condition
    IF NOT bEn THEN                        // 失能优先于故障归因（操作态，边界三）/ a disable takes precedence, an operator state
        fEng     := 0.0;                   // 失能相出口清零（R303）/ zero the outlet while disabled
        bError   := FALSE;                 // 失能不是故障 / a disabled block is not a fault
        nErrCode := 0;                     // 失能不发码 / no code while disabled
    ELSE                                   // 锁存故障相 / the latched fault phase
        fEng     := _fLastGood;            // 保持末次良好值（边界二，R191 名实双出口）/ hold the last good value
        bError   := _bFault;               // 故障位与锁存同源 / both outlets share the latch
        nErrCode := _nCodeLatch;           // 回放锁存码（不按当下输入重推断）/ replay the latched code
    END_IF
END_IF

// 段 9｜定时器无条件周期调用（规则 ⑦，IN 为显式条件）/ segment 9, unconditional timer calls
_tonHigh(IN := _bHighCond, PT := tConfirm);   // 上限确认计时，每周期无条件刷新 / the high confirmation timer
_tonLow(IN := _bLowCond, PT := tConfirm);     // 下限确认计时，每周期无条件刷新 / the low confirmation timer

// 段 10｜报警与忙碌出口（全部取自定时器 Q，单点写入）/ segment 10, the alarm and busy outlets
bHighAlarm := _bRun AND _tonHigh.Q;        // 上限报警：运行中且确认完成 / the high alarm, confirmed while running
bLowAlarm  := _bRun AND _tonLow.Q;         // 下限报警：运行中且确认完成 / the low alarm, confirmed while running
bInBand    := _bRun AND NOT bHighAlarm AND NOT bLowAlarm; // 带内：运行中且两侧均无报警 / inside the band
bBusy      := _bRun AND ((_bHighCond AND NOT _tonHigh.Q) OR (_bLowCond AND NOT _tonLow.Q)); // 确认计时进行中
IF _bRun AND _bHaveGood THEN               // 运行中且已有良好值 / running with a good value available
    bValid := TRUE;                        // 工程值可用 / the engineering value is usable
END_IF
END_FUNCTION_BLOCK
