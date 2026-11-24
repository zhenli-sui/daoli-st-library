(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AutoclaveSterilSeq
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 灭菌釜脉动真空灭菌七态顺控（GMP F0 值合规）：
 *                           ePulse     脉动置换：重复「抽真空-进蒸汽」nPulseCnt 次
 *                                      （tPulse 半周期交替，回合完成计数）；
 *                           eHeatUp    升温：温压入带（fTempSetC±fTempTolC ∧
 *                                      fPrSetKpa±fPrTolKpa）→ eSteril，tHeatTo 超时
 *                                      分码 eNoPr（压不起）/ eNoTemp（温不到）；
 *                           eSteril    保压灭菌：tSteril 到时 ∧ F0 累计达标 ∧ 温压在带内
 *                                      才过相；F0 累计 fF0Acc += fF0Rate×fCycle/60，
 *                                      **带内才累加、带外冻结不倒扣**（保守侧）；
 *                                      带外持续 tBandTmo → eFault eSterilBand；
 *                           eExhaustDry 排气干燥 tExhaust 到时 → eDone。
 *                         bStop 任一相回 eIdle 不记故障；bStop 保留 F0 累计
 *                         （_fF0Acc 不清零，同批次再启动接续累计，仅 bReset
 *                         上升沿清 F0）；bReset 上升沿清全部锁存（R311）。
 * 接口     (Interface)  : 输入 bStart/bStop/bReset、fPrKpa 釜压（kPa）、fTempC 腔温（℃）、
 *                         fPrSetKpa/fTempSetC 灭菌设定、fPrTolKpa/fTempTolC 带半宽、
 *                         tSteril 保压时长、tPulse 脉动半周期、tHeatTo/tBandTmo/tExhaust
 *                         各相窗、nPulseCnt 置换次数、fF0Min F0 目标（min）、fF0Rate
 *                         F0 速率系数（min/min）、fCycle 扫描周期（s）；输出 ePhase 七态、
 *                         fF0AccMin F0 累计（min）、四相指示 BOOL 组、bDone、eCause、
 *                         bError。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做灭菌时序编排与 F0 累计闸，不驱动
 *                         蒸汽阀/真空泵/排水阀**；执行器由 IO 映射层按相指示位驱动。
 *                         ② 七态 CASE + ELSE 兜底 eFault（R6）；段间 TON 各自专用
 *                         （tonPulse/tonHeatTo/tonSteril/tonBandTmo/tonExhaust，R228A
 *                         命名豁免式），段 0 无条件刷新，IN 由当前相与带内判据派生。
 *                         ③ eCause 分码：eNoPr（升不起压）/ eNoTemp（温不到）/ eSterilBand
 *                         （带外跌出）/ eCfgIllegal（组态非法）/ ePhaseBad（兜底），
 *                         归因唯一（R190）。
 *                         ④ 温压非有限 → eFault eCause=eNoTemp 分码（规格指定）。
 *                         ⑤ 组态闸：nPulseCnt=0、任一相时间 <= T#0S、设定值/带宽非正、
 *                         fF0Min<0、fF0Rate<0 → 锁存 eFault eCfgIllegal。
 *                         ⑥ F0 带外冻结：TON IN 派生式（带内才计时与累加），带外不倒扣
 *                         （头注释声明保守侧语义）。
 *                         ⑦ 温压带判定浮点全用 <= / >= 容差比较，禁 = 判等（R28）。
 *                         ⑧ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 温度带判定语义与 `FB_DL_ToleranceWindow` 同思想，本件自带实现
 *                         不引用（规格定为不内嵌引用，独立验收）。
 * 来源标签 (Source Tag) : T2-2 ◐（LBP 工艺分层只借灭菌工序分类事实，F0 累计口径为 GMP
 *                         公开定义，零文本复制）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 ENUM 七态 + LREAL 累计 +
 *                         BOOL 组 + ENUM 成因；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 非有限分码 + 带内累加闸 + 组态闸 + 周期缺省闸 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ 七态 CASE 含 ELSE ｜ R7 ✓ 五 TON/两 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.1  R50 返修 R2：头注释补声明
 *                         「bStop 保留 F0 累计」口径——bStop 中止只清脉动
 *                         计数与子态，_fF0Acc 不清零（同批次再启动接续累计），
 *                         仅 bReset 上升沿清 F0 累计；逻辑零改动，契约不变。
 *                         2026-11-20  v1.0.0  R48 首版（批次 4 · 序号 18）
 *                         验收向量：脉动计满进升温；温压入带 + F0 达标 + tSteril 到 →
 *                         过相；带外跌出冻结计时；tBandTmo 超时故障；bStop 中止不记故障。
 *==============================================================================*)

TYPE E_DL_AcsPhase :
(
    eIdle      := 0,    // 待机 / Idle
    ePulse     := 10,   // 脉动置换相 / Pulsing vacuum-steam phase
    eHeatUp    := 20,   // 升温相 / Heat-up phase
    eSteril    := 30,   // 保压灭菌相 / Sterilization hold phase
    eExhaustDry:= 40,   // 排气干燥相 / Exhaust and dry phase
    eDone      := 50,   // 程序完成 / Sequence done
    eFault     := 90    // 故障（等复位）/ Fault, awaiting reset
);
END_TYPE

TYPE E_DL_AcsCause :
(
    eNone       := 0,   // 无异常 / No anomaly
    eNoPr       := 1,   // 升不起压（升温相压力超时）/ Pressure fail in heat-up
    eNoTemp     := 2,   // 温不到 / 温压非有限（分码共用温度侧成因）/ Temperature fail or non-finite
    eSterilBand := 3,   // 灭菌带外跌出超时 / Sterilization band dropout timeout
    eCfgIllegal := 4,   // 组态非法 / Illegal configuration
    ePhaseBad   := 5    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_AutoclaveSterilSeq
VAR_INPUT
    bStart    : BOOL := FALSE;     // 启动沿（eIdle 入脉动相） [-] / Start edge
    bStop     : BOOL := FALSE;     // 中止（任一相回 eIdle，不记故障） [-] / Abort to idle, no fault
    bReset    : BOOL := FALSE;     // 复位，上升沿清全部锁存（R311） [-] / Reset, rising edge clears all latches
    fPrKpa    : LREAL := 0.0;      // 釜压实测 [kPa] / Chamber pressure [kPa]
    fTempC    : LREAL := 0.0;      // 腔温实测 [℃] / Chamber temperature [degC]
    fPrSetKpa : LREAL := 200.0;    // 灭菌压力设定，域 > 0 [kPa] / Sterilization pressure setpoint [kPa]
    fTempSetC : LREAL := 121.0;    // 灭菌温度设定，域 > 0 [℃] / Sterilization temperature setpoint [degC]
    fPrTolKpa : LREAL := 10.0;     // 压力带半宽，域 > 0 [kPa] / Pressure band half-width [kPa]
    fTempTolC : LREAL := 1.0;      // 温度带半宽，域 > 0 [℃] / Temperature band half-width [degC]
    tSteril   : TIME := T#30M;     // 保压灭菌时长，域 > T#0S [ms] / Sterilization hold duration [ms]
    tPulse    : TIME := T#2M;      // 脉动半周期（抽真空/进蒸汽各一段），域 > T#0S [ms] / Pulse half-period [ms]
    tHeatTo   : TIME := T#60M;     // 升温相超时，域 > T#0S [ms] / Heat-up timeout [ms]
    tBandTmo  : TIME := T#5M;      // 灭菌带外容忍窗，域 > T#0S [ms] / Band dropout tolerance [ms]
    tExhaust  : TIME := T#15M;     // 排气干燥时长，域 > T#0S [ms] / Exhaust-dry duration [ms]
    nPulseCnt : UDINT := 3;        // 脉动置换次数，域 >= 1（=0 组态闸） [次] / Pulse swap count
    fF0Min    : LREAL := 3.0;      // F0 灭菌值目标，域 >= 0 [min] / F0 target [min]
    fF0Rate   : LREAL := 1.0;      // F0 累计速率系数（带内每分钟 F0 增量），域 >= 0 [min/min] / F0 rate coefficient
    fCycle    : LREAL := 0.0;      // 扫描周期（<=0 用缺省） [s] / Scan cycle, default used when <= 0
END_VAR
VAR_OUTPUT
    ePhase    : E_DL_AcsPhase;     // 当前相出口 [-] / Present phase outlet
    fF0AccMin : LREAL;             // F0 累计输出（带内累加、带外冻结） [min] / F0 accumulated [min]
    bPulseActive   : BOOL;         // 脉动相指示 [-] / Pulse phase indicator
    bHeatUpActive  : BOOL;         // 升温相指示 [-] / Heat-up phase indicator
    bSterilActive  : BOOL;         // 灭菌相指示 [-] / Sterilization phase indicator
    bExhaustActive : BOOL;         // 排气干燥相指示 [-] / Exhaust phase indicator
    bDone     : BOOL;              // 程序完成（eDone 驻留指示） [-] / Sequence done indicator
    eCause    : E_DL_AcsCause;     // 成因出口（锁存回放，R189） / Cause outlet, latched
    bError    : BOOL;              // 故障标志 [-] / Error flag
END_VAR
VAR
    _eState    : E_DL_AcsPhase := E_DL_AcsPhase.eIdle;   // 内部相（CASE 唯一写入目标） / Internal phase
    _eCause    : E_DL_AcsCause := E_DL_AcsCause.eNone;   // 成因锁存量 / Latched cause
    _bFault    : BOOL;             // 故障锁存位（解除沿 = bReset 上升沿） / Latched fault bit
    _nPulseDone: UDINT := 0;       // 脉动回合完成计数 [次] / Completed pulse swaps
    _bPulseStm : BOOL;             // 脉动子态（FALSE=抽真空段 / TRUE=进蒸汽段） / Pulse sub-state
    _bInBand   : BOOL;             // 当拍温压带内判据 [-] / In-band this scan
    _bNonFin   : BOOL;             // 温压非有限当拍量 [-] / Non-finite measurands this scan
    _bCfgBad   : BOOL;             // 组态非法当拍量 [-] / Illegal configuration this scan
    _fCy       : LREAL;            // 当拍有效周期 [s] / Effective cycle this scan
    _fF0Acc    : LREAL := 0.0;     // F0 累计锁存 [min] / F0 accumulator latch
    _bBusyPrev : BOOL;             // 上拍运行快照（bDone 迁出用） / Busy snapshot
    tonPulse   : TON;              // 脉动半周期定时器，段 0 无条件调用 / Pulse half-period timer
    tonHeatTo  : TON;              // 升温超时定时器，段 0 无条件调用 / Heat-up timeout timer
    tonSteril  : TON;              // 保压灭菌计时定时器，段 0 无条件调用 / Sterilization hold timer
    tonBandTmo : TON;              // 带外容忍窗定时器，段 0 无条件调用 / Band dropout tolerance timer
    tonExhaust : TON;              // 排气干燥计时定时器，段 0 无条件调用 / Exhaust-dry timer
    rtStart    : R_TRIG;           // 启动沿实例，段 0 无条件调用 / Start edge instance
    rtReset    : R_TRIG;           // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_ACS_CYDEF : LREAL := 0.01;    // 缺省扫描周期 [s] / Default scan cycle
    DL_ACS_SEC   : LREAL := 60.0;    // 分秒换算基 [s/min] / Second-per-minute base
    DL_ACS_ZERO  : LREAL := 0.0;     // 非有限差值判零基准 [-] / Non-finite difference zero base
    DL_ACS_UDMAX : UDINT := 4294967295;   // UDINT 上限（脉动计数饱和点） [次] / UDINT ceiling
END_VAR

(* —— 段 0：非有限判 + 组态闸 + 周期派生 + 五 TON 两沿无条件周期刷新 —— *)
_bNonFin := (fPrKpa <> fPrKpa) OR ((fPrKpa - fPrKpa) <> DL_ACS_ZERO)
         OR (fTempC <> fTempC) OR ((fTempC - fTempC) <> DL_ACS_ZERO);   // 温压非有限（R245） / Non-finite pressure and temperature
_bCfgBad := (nPulseCnt = 0) OR (fPrSetKpa <= 0.0) OR (fTempSetC <= 0.0)
         OR (fPrTolKpa <= 0.0) OR (fTempTolC <= 0.0)
         OR (tSteril <= T#0S) OR (tPulse <= T#0S) OR (tHeatTo <= T#0S)
         OR (tBandTmo <= T#0S) OR (tExhaust <= T#0S)
         OR (fF0Min < 0.0) OR (fF0Rate < 0.0);          // 组态域闸（含 nPulseCnt=0） / Configuration gate
IF fCycle > 0.0 THEN
    _fCy := fCycle;                                     // 组态周期有效 / Configured cycle valid
ELSE
    _fCy := DL_ACS_CYDEF;                               // 周期缺省兜底 / Default cycle fallback
END_IF
rtStart(CLK := bStart);                                 // 启动沿，每拍必调 / Start edge, every scan
rtReset(CLK := bReset);                                 // 复位沿，每拍必调 / Reset edge, every scan
tonPulse(IN := (_eState = E_DL_AcsPhase.ePulse) AND (NOT tonPulse.Q), PT := tPulse);   // 脉动半周期自复位窗（R188） / Pulse self-reset window
tonHeatTo(IN := (_eState = E_DL_AcsPhase.eHeatUp), PT := tHeatTo);   // 升温超时（进相计时，出相自复位） / Heat-up timeout
tonSteril(IN := (_eState = E_DL_AcsPhase.eSteril) AND _bInBand, PT := tSteril);   // 灭菌计时（带内才计时，带外冻结） / Sterilization timer, in-band gated
tonBandTmo(IN := (_eState = E_DL_AcsPhase.eSteril) AND (NOT _bInBand), PT := tBandTmo);   // 带外容忍窗 / Band dropout tolerance
tonExhaust(IN := (_eState = E_DL_AcsPhase.eExhaustDry), PT := tExhaust);   // 排气干燥计时 / Exhaust timer

(* —— 段 1：带内判据（非有限按带外处理并分码 eNoTemp，先于 CASE 使用） —— *)
_bInBand := (NOT _bNonFin)
         AND (ABS(fTempC - fTempSetC) <= fTempTolC)     // 温度带内（容差比较，禁 =） / Temperature in band
         AND (ABS(fPrKpa - fPrSetKpa) <= fPrTolKpa);    // 压力带内 / Pressure in band

(* —— 段 2：单拍量预清零（_eState/_eCause/_bFault/_n PulseDone/_fF0Acc 锁存量不入清单，R107） —— *)
bPulseActive := FALSE;                                  // 脉动相指示预清 / Pulse indicator preset
bHeatUpActive := FALSE;                                 // 升温相指示预清 / Heat-up indicator preset
bSterilActive := FALSE;                                 // 灭菌相指示预清 / Sterilization indicator preset
bExhaustActive := FALSE;                                // 排气相指示预清 / Exhaust indicator preset
bDone := FALSE;                                         // 完成指示预清 / Done preset
bError := FALSE;                                        // 故障标志预清（R45 配对） / Error flag preset

(* —— 段 3：组态闸入故障 —— *)
IF _bCfgBad AND (NOT _bFault) THEN
    _bFault := TRUE;                                    // 锁存 / Latch
    _eCause := E_DL_AcsCause.eCfgIllegal;               // 归因：组态非法 / Cause: illegal config
    _eState := E_DL_AcsPhase.eFault;                    // 入故障相 / Enter fault
END_IF

(* —— 段 4：迁出链（bStop 优先不记故障；bReset 清全部锁存 R311） —— *)
IF bStop AND (_eState <> E_DL_AcsPhase.eIdle) THEN
    IF _eState = E_DL_AcsPhase.eFault THEN
        _bFault := FALSE;                               // 停机优先：故障相允许被停机清出 / Stop wins over fault
        _eCause := E_DL_AcsCause.eNone;                 // 清成因 / Clear cause
    END_IF
    _nPulseDone := 0;                                   // 清脉动计数 / Clear pulse count
    _bPulseStm := FALSE;                                // 清脉动子态 / Clear pulse sub-state
    _eState := E_DL_AcsPhase.eIdle;                     // 回待机（不记故障） / Back to idle, no fault
END_IF
IF rtReset.Q THEN
    _bFault := FALSE;                                   // 清故障锁存（R311） / Clear fault latch
    _eCause := E_DL_AcsCause.eNone;                     // 清成因 / Clear cause
    _nPulseDone := 0;                                   // 清脉动计数 / Clear pulse count
    _bPulseStm := FALSE;                                // 清脉动子态 / Clear pulse sub-state
    _fF0Acc := 0.0;                                     // 清 F0 累计 / Clear F0 accumulator
    _eState := E_DL_AcsPhase.eIdle;                     // 回待机 / Back to idle
END_IF

(* —— 段 5：七态顺控（只在无故障时推进；温压非有限 → 故障分码 eNoTemp） —— *)
IF (NOT _bFault) AND (NOT _bCfgBad) AND (NOT bStop) THEN
    IF _bNonFin AND (_eState <> E_DL_AcsPhase.eIdle) AND (_eState <> E_DL_AcsPhase.eDone) THEN
        _bFault := TRUE;                                // 运行相温压非有限：故障锁存（规格④） / Non-finite in running phase: fault
        _eCause := E_DL_AcsCause.eNoTemp;               // 归因分码：温度侧 / Cause: temperature side
        _eState := E_DL_AcsPhase.eFault;                // 入故障相 / Enter fault
    ELSE
        CASE _eState OF

        E_DL_AcsPhase.eIdle:
            IF rtStart.Q THEN
                _nPulseDone := 0;                       // 启动清脉动计数 / Clear pulse count on start
                _bPulseStm := FALSE;                    // 启动回抽真空子段 / Start in vacuum sub-phase
                _eState := E_DL_AcsPhase.ePulse;        // 入脉动相 / Enter pulse phase
            END_IF

        E_DL_AcsPhase.ePulse:
            IF tonPulse.Q THEN
                _bPulseStm := NOT _bPulseStm;           // 半周期到：抽真空/进蒸汽交替 / Half period: toggle sub-phase
                IF NOT _bPulseStm THEN
                    IF _nPulseDone < DL_ACS_UDMAX THEN
                        _nPulseDone := _nPulseDone + 1; // 完成一个完整回合（真空→蒸汽→真空）计数 / Count full swap round
                    END_IF
                END_IF
                IF _nPulseDone >= nPulseCnt THEN
                    _eState := E_DL_AcsPhase.eHeatUp;   // 置换次数达标：进升温相 / Swaps done: enter heat-up
                END_IF
            END_IF

        E_DL_AcsPhase.eHeatUp:
            IF _bInBand THEN
                _eState := E_DL_AcsPhase.eSteril;       // 温压入带：进保压灭菌相 / In band: enter sterilization
            ELSIF tonHeatTo.Q THEN
                IF ABS(fPrKpa - fPrSetKpa) > fPrTolKpa THEN
                    _eCause := E_DL_AcsCause.eNoPr;     // 压力超带：升不起压 / Pressure out of band: no pressure
                ELSE
                    _eCause := E_DL_AcsCause.eNoTemp;   // 压力入带而温度不达：温不到 / Temperature short
                END_IF
                _bFault := TRUE;                        // 超时故障锁存 / Latch fault
                _eState := E_DL_AcsPhase.eFault;        // 入故障相 / Enter fault
            END_IF

        E_DL_AcsPhase.eSteril:
            IF _bInBand THEN
                _fF0Acc := _fF0Acc + fF0Rate * _fCy / DL_ACS_SEC;   // 带内 F0 累计（速率×周期/60） / In-band F0 accumulation
            END_IF
            (* 带外不倒扣不累加（保守侧，头注释⑥）；带外容忍窗由 tonBandTmo 监视 *)
            IF tonBandTmo.Q THEN
                _eCause := E_DL_AcsCause.eSterilBand;   // 带外跌出超时 / Band dropout timeout
                _bFault := TRUE;                        // 锁存 / Latch
                _eState := E_DL_AcsPhase.eFault;        // 入故障相 / Enter fault
            ELSIF tonSteril.Q AND (_fF0Acc >= fF0Min) AND _bInBand THEN
                _eState := E_DL_AcsPhase.eExhaustDry;   // 计时到 ∧ F0 达标 ∧ 带内：过相（禁浮点 =，>= 判据） / Pass criteria met
            END_IF

        E_DL_AcsPhase.eExhaustDry:
            IF tonExhaust.Q THEN
                _eState := E_DL_AcsPhase.eDone;         // 排气干燥到时：进完成相 / Exhaust done: enter done
            END_IF

        E_DL_AcsPhase.eDone:
            ;                                           // 完成相驻留：由 bReset / bStop 迁出 / Held, exits via reset or stop

        E_DL_AcsPhase.eFault:
            ;                                           // 故障相驻留：由迁出链处理 / Held by exit chain

        ELSE
            _eCause := E_DL_AcsCause.ePhaseBad;         // 非法相位兜底归因 / Illegal phase cause
            _bFault := TRUE;                            // 锁存 / Latch
            _eState := E_DL_AcsPhase.eFault;            // 强拉故障相 / Force fault

        END_CASE
    END_IF
END_IF

(* —— 段 6：完成脉冲（由"运行→eDone"沿派生，单拍，R34 两段式） —— *)
IF _bBusyPrev AND (_eState = E_DL_AcsPhase.eDone) THEN
    bDone := TRUE;                                      // 程序完成单拍指示 / Done pulse
END_IF
_bBusyPrev := (_eState <> E_DL_AcsPhase.eIdle)
          AND (_eState <> E_DL_AcsPhase.eDone)
          AND (_eState <> E_DL_AcsPhase.eFault);        // 运行中快照（本拍末） / Busy snapshot at body end

(* —— 段 7：出口单点映射（相指示与相别同源，R191） —— *)
bPulseActive   := (_eState = E_DL_AcsPhase.ePulse);     // 脉动相指示 / Pulse indicator
bHeatUpActive  := (_eState = E_DL_AcsPhase.eHeatUp);    // 升温相指示 / Heat-up indicator
bSterilActive  := (_eState = E_DL_AcsPhase.eSteril);    // 灭菌相指示 / Sterilization indicator
bExhaustActive := (_eState = E_DL_AcsPhase.eExhaustDry);   // 排气相指示 / Exhaust indicator
IF _eState = E_DL_AcsPhase.eDone THEN
    bDone := TRUE;                                      // 完成相驻留期保持指示（R191 名实双出口声明） / Done held while resident
END_IF
ePhase := _eState;                                      // 当前相出口 / Present phase outlet
fF0AccMin := _fF0Acc;                                   // F0 累计出口 / F0 outlet
eCause := _eCause;                                      // 成因出口 / Cause outlet
bError := _bFault OR _bCfgBad;                          // 故障标志 = 锁存或组态非法 / Error = latch or config

END_FUNCTION_BLOCK
