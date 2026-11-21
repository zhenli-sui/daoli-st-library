(*
  ==================================================================
  组件名 Component  : FB_DL_RollPressBitWord
  分类   Category   : DL_Process
  版本   Version    : 1.0.0
  功能   Purpose    : 辊压压力报警字位段打包。逐区（1..8）比较实测压力与逐区
                      高压阈 / 低压阈，带回差防抖，把报警状态打包为一个 16 位字：
                      低 8 位段 = 低压报警（位 i-1 对应区 i），
                      高 8 位段 = 高压报警（位 8+i-1 对应区 i），
                      另出无效区掩码字（该区不可判：阈值非法或压力非有限）。
  溯源   Origin     : 逐区位段打包与回差防抖为通用报警字组织方式；本件为 clean-room
                      实现，仅借鉴来源分类与参数域组织（来源标签 roadmap-p2-rollpress），
                      道莅原创设计，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（WORD / SHL / NOT / AND / OR，无私有库）
  作者   Author     : 道莅代码库 · PLC 编程专家（R55）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只做压力报警字打包，不驱动辊缝、不做停机决策（属主边界）；
                      二 回差判据挂在报警字自身状态上（已置位者按 阈 - 回差 复位）；
                      三 非有限压力不判高低压，只置无效位，出口报警位保持上拍；
                      四 阈值非法（高阈不高于低阈或非有限）→ 该区无效 + 故障锁存；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      wAlarmWord 低字节为低压段、高字节为高压段，两段互不跨用；
                      自证向量：仅 1 区低压 → 16#0001，仅 1 区高压 → 16#0100，
                      1 区低压且 8 区高压 → 16#0180；
                      nFirstAlarmZone 为 1..8，无报警为 0；uAlarmCount 为本拍置位数；
                      eCause 故障级成因与 bError 配对（R45），信息级永不置 bError。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R55 首版（批 1 · 序号 5）
  ==================================================================
*)

TYPE E_DL_RpbCause :
(
    eNone       := 0,   // 无成因 / no cause
    eThrBad     := 1,   // 阈值非法：高阈不高于低阈或非有限（故障级，与 bError 配对）/ illegal threshold, high not above low or non-finite, a fault paired with bError
    eCountBad   := 2,   // 区数越域已回钳（信息级）/ zone count out of domain and clamped, informational
    ePressBad   := 3    // 压力非有限，该区不可判（信息级）/ non-finite pressure, the zone is undecidable, informational
);
END_TYPE

FUNCTION_BLOCK FB_DL_RollPressBitWord
VAR_INPUT
    bEnable      : BOOL := TRUE;             // 使能，失能时报警字冻结保持末值 [-] / enable, the alarm word freezes and holds its last value when disabled
    bReset       : BOOL := FALSE;           // 复位上升沿清报警位与故障锁存 [-] / reset rising edge clears the alarm bits and the fault latch
    nZoneCount   : INT := 8;                 // 参与判定的区数 [个]，域 1..8 / participating zones [count], domain 1 to 8
    fHystBar     : REAL := 0.5;              // 回差带 [巴]，域 大于等于零 / hysteresis band [bar], domain zero and above
END_VAR
VAR_IN_OUT
    afPressBar   : ARRAY[1..8] OF REAL;      // 逐区压力实测 [巴]，引用型入参由调用方持有 / per zone measured pressure [bar], reference parameter owned by the caller
    afPressHiBar : ARRAY[1..8] OF REAL;      // 逐区高压报警阈 [巴]，引用型入参由调用方持有 / per zone high alarm threshold [bar], reference parameter owned by the caller
    afPressLoBar : ARRAY[1..8] OF REAL;      // 逐区低压报警阈 [巴]，引用型入参由调用方持有 / per zone low alarm threshold [bar], reference parameter owned by the caller
END_VAR
VAR_OUTPUT
    wAlarmWord   : WORD := 16#0000;          // 打包报警字：低字节低压段 / 高字节高压段 [-] / packed alarm word, low byte for the low segment and high byte for the high segment
    wLowWord     : WORD := 16#0000;          // 低压报警段（位 i-1 对应区 i）[-] / low pressure alarm segment, bit i minus one maps to zone i
    wHighWord    : WORD := 16#0000;          // 高压报警段（位 i-1 对应区 i）[-] / high pressure alarm segment, bit i minus one maps to zone i
    wInvalidWord : WORD := 16#0000;          // 无效区掩码（不可判的区）[-] / invalid zone mask for undecidable zones
    bAnyAlarm    : BOOL := FALSE;            // 任一报警置位 [-] / any alarm bit set
    nFirstAlarmZone : INT := 0;              // 首个报警区号 [区号]，无报警为 0 / first alarming zone number, zero when none
    uAlarmCount  : UINT := 0;                // 本拍报警位数 [位] / number of alarm bits this scan
    eCause       : E_DL_RpbCause := E_DL_RpbCause.eNone; // 成因出口 [枚举] / cause outlet [enum]
    bError       : BOOL := FALSE;            // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtReset      : R_TRIG;                   // 复位沿检测，段 0 无条件刷新 / reset edge detector, refreshed unconditionally in segment zero
    _eCause      : E_DL_RpbCause := E_DL_RpbCause.eNone; // 内部成因，故障级锁存、信息级每拍重算 / internal cause, latched for faults and recomputed for information
    _bFault      : BOOL := FALSE;            // 故障锁存位（阈值非法）/ fault latch bit for an illegal threshold
    _bInit       : BOOL := FALSE;            // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bZoneBad    : BOOL := FALSE;            // 本区不可判（阈值非法或压力非有限）[-] / the zone is undecidable
    _bPressOk    : BOOL := FALSE;            // 本区压力有限 [-] / the zone pressure is finite
    _bThrOk      : BOOL := FALSE;            // 本区阈值合法 [-] / the zone thresholds are legal
    _bPressNonFin: BOOL := FALSE;            // 本拍出现非有限压力 [-] / a non-finite pressure occurred this scan
    _bCountClamped : BOOL := FALSE;          // 区数被回钳 [-] / the zone count was clamped
    _bHiBit      : BOOL := FALSE;            // 本区高压报警位当前值 [-] / current high alarm bit of the zone
    _bLoBit      : BOOL := FALSE;            // 本区低压报警位当前值 [-] / current low alarm bit of the zone
    _nUseCount   : INT := 0;                 // 钳定后的区数 [个] / clamped zone count
    _nIdx        : INT := 0;                 // 区游标（1 起，回钳 1..8）[区号] / zone cursor, one-based, clamped one through eight
    _fPress      : REAL := 0.0;              // 本区压力暂存 [巴] / zone pressure held in a local [bar]
    _fHi         : REAL := 0.0;              // 本区高压阈暂存 [巴] / zone high threshold held in a local [bar]
    _fLo         : REAL := 0.0;              // 本区低压阈暂存 [巴] / zone low threshold held in a local [bar]
    _fHiReset    : REAL := 0.0;              // 高压回差复位点 [巴] / high hysteresis reset point [bar]
    _fLoReset    : REAL := 0.0;              // 低压回差复位点 [巴] / low hysteresis reset point [bar]
    _fHyst       : REAL := 0.0;              // 钳定后的回差 [巴] / clamped hysteresis [bar]
    _wLo         : WORD := 16#0000;          // 低压段工作字，兼作回差状态 / low segment working word, also the hysteresis state
    _wHi         : WORD := 16#0000;          // 高压段工作字，兼作回差状态 / high segment working word, also the hysteresis state
    _wInv        : WORD := 16#0000;          // 无效区工作字 / invalid zone working word
    _wBit        : WORD := 16#0001;          // 本区位掩码，先移位后置位（R327）/ zone bit mask, shift before setting
END_VAR
VAR CONSTANT
    DL_RPB_MAX      : INT := 8;              // 区容量与游标回钳上界 [个] / zone capacity and cursor clamp upper bound
    DL_RPB_SEG_SHIFT: INT := 8;              // 高压段移入高字节的位移量 [位]，常量 8 小于字宽 16 / shift moving the high segment into the high byte, the constant eight is below the word width sixteen
    DL_RPB_MASK_NONE: WORD := 16#0000;       // 空掩码常量 [-] / empty mask constant
    DL_RPB_MASK_ONE : WORD := 16#0001;       // 单位位常量 [-] / single bit constant
    DL_RPB_HYST_MAX : REAL := 100.0;         // 回差上限 [巴]，防回差吞掉整个量程 / hysteresis ceiling against swallowing the whole range [bar]
    DL_RPB_PRESS_MAX: REAL := 1.0E6;         // 压力量级上限，防量纲错配 [巴] / pressure magnitude ceiling against a dimension mismatch [bar]
END_VAR

// 段 0｜复位沿无条件周期刷新（禁入分支）/ segment 0, unconditional refresh of the reset edge, never inside a branch
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _eCause := E_DL_RpbCause.eNone; // 成因清零 / clear the cause
    _wLo := DL_RPB_MASK_NONE; // 低压段清零 / clear the low segment
    _wHi := DL_RPB_MASK_NONE; // 高压段清零 / clear the high segment
    _wInv := DL_RPB_MASK_NONE; // 无效字清零 / clear the invalid word
END_IF

// 段 2｜复位沿作用域：清报警位 / 清无效字 / 清故障锁存（三项逐项声明）/ segment 2, reset edge scope declared item by item
IF rtReset.Q THEN // 复位沿 / reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eCause := E_DL_RpbCause.eNone; // 作用域一：清成因 / scope one, clear the cause
    _wLo := DL_RPB_MASK_NONE; // 作用域二：清低压报警位 / scope two, clear the low alarm bits
    _wHi := DL_RPB_MASK_NONE; // 作用域二：清高压报警位 / scope two, clear the high alarm bits
    _wInv := DL_RPB_MASK_NONE; // 作用域三：清无效字 / scope three, clear the invalid word
END_IF

// 段 3｜区数回钳与回差域闸 / segment 3, zone count clamping and hysteresis domain gate
_bCountClamped := FALSE; // 回钳标志预置假 / preset the clamp flag to false
_nUseCount := nZoneCount; // 区数直通 / zone count passes through
IF _nUseCount < 1 THEN // 下越界 / below the lower bound
    _nUseCount := 1; // 回钳到 1 / clamp to one
    _bCountClamped := TRUE; // 置回钳标志 / raise the clamp flag
ELSIF _nUseCount > DL_RPB_MAX THEN // 上越界 / above the upper bound
    _nUseCount := DL_RPB_MAX; // 回钳到容量上限 / clamp to the capacity ceiling
    _bCountClamped := TRUE; // 置回钳标志 / raise the clamp flag
END_IF
_fHyst := fHystBar; // 回差直通 / hysteresis passes through
IF (_fHyst <> _fHyst) OR ((_fHyst - _fHyst) <> (_fHyst - _fHyst)) THEN // 回差非有限 / hysteresis non-finite
    _fHyst := 0.0; // 非有限归零（等价无回差）/ zeroed, equivalent to no hysteresis
END_IF
IF _fHyst < 0.0 THEN // 回差为负 / hysteresis negative
    _fHyst := 0.0; // 钳零 / clamped to zero
ELSIF _fHyst > DL_RPB_HYST_MAX THEN // 回差过大 / hysteresis too large
    _fHyst := DL_RPB_HYST_MAX; // 钳到上限 / clamped to the ceiling
END_IF
IF NOT bEnable THEN // 失能：报警字冻结保持末值（R191 显式声明）/ disabled, the alarm word freezes and holds its last value
    _nUseCount := 0; // 区数置零使主循环不执行 / the zone count is zeroed so the main loop does not run
END_IF

// 段 4｜逐区判定主循环：阈值闸 → 压力闸 → 回差判据 → 位打包（先移位后置位）/ segment 4, per zone loop with threshold gate, pressure gate, hysteresis criterion and bit packing
_bPressNonFin := FALSE; // 非有限压力标志清零 / clear the non-finite pressure flag
_nIdx := 1; // 游标自 1 起，上界由 _nUseCount 约束 / the cursor starts at one, bounded by the usable count
WHILE _nIdx <= _nUseCount DO // 循环上界为钳定后的区数，天然不越 8 / the loop bound is the clamped count, never beyond eight
    _wBit := SHL(DL_RPB_MASK_ONE, _nIdx - 1); // 本区位掩码，位移量 0..7 由数组边界与循环上界共同证明 / zone bit mask, the shift zero through seven is proven by the array and loop bounds
    _fPress := afPressBar[_nIdx]; // 压力暂存 / pressure held in a local
    _fHi := afPressHiBar[_nIdx]; // 高压阈暂存 / high threshold held in a local
    _fLo := afPressLoBar[_nIdx]; // 低压阈暂存 / low threshold held in a local
    _bThrOk := (_fHi = _fHi) AND ((_fHi - _fHi) = (_fHi - _fHi)) AND (_fLo = _fLo) AND ((_fLo - _fLo) = (_fLo - _fLo)) AND (_fHi > _fLo); // 阈值有限且高阈高于低阈 / thresholds finite with the high above the low
    _bPressOk := (_fPress = _fPress) AND ((_fPress - _fPress) = (_fPress - _fPress)) AND (ABS(_fPress) <= DL_RPB_PRESS_MAX); // 压力有限且量级可信 / pressure finite with a credible magnitude
    _bZoneBad := FALSE; // 本区不可判标志预置假 / preset the undecidable flag to false
    IF NOT _bThrOk THEN // 阈值非法 / illegal threshold
        _bZoneBad := TRUE; // 本区不可判 / the zone is undecidable
        IF NOT _bFault THEN // 未锁存才记故障 / record the fault only when not yet latched
            _bFault := TRUE; // 置故障锁存 / raise the fault latch
            _eCause := E_DL_RpbCause.eThrBad; // 故障级成因 (R45 配对 bError) / fault grade cause paired with bError
        END_IF
    ELSIF NOT _bPressOk THEN // 压力非有限 / pressure non-finite
        _bZoneBad := TRUE; // 本区不可判 / the zone is undecidable
        _bPressNonFin := TRUE; // 记非有限压力成因 / record the non-finite pressure cause
    END_IF
    _wInv := _wInv AND NOT _wBit; // 先假定本区可判，清无效位 / assume the zone is decidable and clear the invalid bit
    IF _bZoneBad THEN // 本区不可判 / the zone is undecidable
        _wInv := _wInv OR _wBit; // 置无效位 / set the invalid bit
        _wLo := _wLo AND NOT _wBit; // 低压位保持清零（不可判不报警）/ the low bit stays cleared, nothing is decided
        _wHi := _wHi AND NOT _wBit; // 高压位保持清零（不可判不报警）/ the high bit stays cleared, nothing is decided
    ELSE
        _bLoBit := ((_wLo AND _wBit) <> DL_RPB_MASK_NONE); // 低压位当前值 / current low bit
        _bHiBit := ((_wHi AND _wBit) <> DL_RPB_MASK_NONE); // 高压位当前值 / current high bit
        _fLoReset := _fLo + _fHyst; // 低压回差复位点（已报警者高于此值才复位）/ low hysteresis reset point
        _fHiReset := _fHi - _fHyst; // 高压回差复位点（已报警者低于此值才复位）/ high hysteresis reset point
        IF _bLoBit THEN // 低压已报警 / the low alarm is active
            IF _fPress > _fLoReset THEN // 回升越过回差复位点 / recovered above the reset point
                _wLo := _wLo AND NOT _wBit; // 复位低压位 / clear the low bit
            END_IF
        ELSE // 低压未报警 / the low alarm is inactive
            IF _fPress < _fLo THEN // 低于低压阈 / below the low threshold
                _wLo := _wLo OR _wBit; // 置低压位 / set the low bit
            END_IF
        END_IF
        IF _bHiBit THEN // 高压已报警 / the high alarm is active
            IF _fPress < _fHiReset THEN // 回落越过回差复位点 / recovered below the reset point
                _wHi := _wHi AND NOT _wBit; // 复位高压位 / clear the high bit
            END_IF
        ELSE // 高压未报警 / the high alarm is inactive
            IF _fPress > _fHi THEN // 高于高压阈 / above the high threshold
                _wHi := _wHi OR _wBit; // 置高压位 / set the high bit
            END_IF
        END_IF
    END_IF
    _nIdx := _nIdx + 1; // 游标递增 / increment the cursor
END_WHILE

// 段 5｜字位段打包：低字节放低压段、高字节放高压段，两段互不跨用 / segment 5, segment packing with the low byte for the low segment and the high byte for the high segment
wLowWord := _wLo; // 低压段出口 / low segment outlet
wHighWord := _wHi; // 高压段出口 / high segment outlet
wInvalidWord := _wInv; // 无效区掩码出口 / invalid zone mask outlet
wAlarmWord := _wLo OR SHL(_wHi, DL_RPB_SEG_SHIFT); // 两段合成，位移量为常量八 / both segments combined with the constant shift of eight

// 段 6｜统计：报警位数与首个报警区号（自 1 区起顺序扫，命中即止）/ segment 6, statistics for the alarm count and the first alarming zone
_bAnyAlarm := FALSE; // 任一报警标志预置假 / preset the any alarm flag to false
uAlarmCount := 0; // 报警位数清零 / clear the alarm bit count
nFirstAlarmZone := 0; // 首个报警区号清零 / clear the first alarming zone
_nIdx := 1; // 游标自 1 起 / the cursor starts at one
WHILE _nIdx <= DL_RPB_MAX DO // 全容量扫查，未参与区恒为零位 / sweep the full capacity because unused zones stay cleared
    _wBit := SHL(DL_RPB_MASK_ONE, _nIdx - 1); // 本区位掩码 / zone bit mask
    IF ((_wLo AND _wBit) <> DL_RPB_MASK_NONE) OR ((_wHi AND _wBit) <> DL_RPB_MASK_NONE) THEN // 本区任一报警位 / any alarm bit of this zone
        _bAnyAlarm := TRUE; // 置任一报警标志 / raise the any alarm flag
        uAlarmCount := uAlarmCount + 1; // 报警位数递增 / increment the alarm count
        IF nFirstAlarmZone = 0 THEN // 尚未记录首个 / nothing recorded yet
            nFirstAlarmZone := _nIdx; // 记录首个报警区号 / record the first alarming zone
        END_IF
    END_IF
    _nIdx := _nIdx + 1; // 游标递增 / increment the cursor
END_WHILE
bAnyAlarm := _bAnyAlarm; // 任一报警出口（挂状态量，非单拍标志）/ any alarm outlet, a state quantity

// 段 7｜成因分派（固定优先级：故障 > 回钳 > 非有限压力 > 无成因）/ segment 7, cause dispatch with a fixed priority
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    _eCause := E_DL_RpbCause.eThrBad; // 故障级成因锁存回放 / the fault cause is replayed from the latch
ELSIF _bCountClamped THEN // 区数被回钳 / the zone count was clamped
    _eCause := E_DL_RpbCause.eCountBad; // 信息级成因 / informational cause
ELSIF _bPressNonFin THEN // 存在非有限压力 / a non-finite pressure occurred
    _eCause := E_DL_RpbCause.ePressBad; // 信息级成因 / informational cause
ELSE
    _eCause := E_DL_RpbCause.eNone; // 无成因 / no cause
END_IF

// 段 8｜统一出口 / segment 8, unified outlet
eCause := _eCause; // 成因出口单点映射 / single-point cause outlet mapping
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
