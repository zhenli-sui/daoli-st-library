(*
    FB_DL_StrainThermalCreepAdaptive —— 应变桥温漂与蠕变自适应补偿（含空载窗口自动重学零点）
    ------------------------------------------------------------------
    组件名    : FB_DL_StrainThermalCreepAdaptive
    分类      : DL_Device / Weighing Compensation（称重与测力补偿）
    一句话功能: 在线扣除应变桥的温漂与载荷蠕变，并在空载窗口自动重学零点，
                同时用「载荷是否真为空」判据防止把真实载荷学成漂移。
    复杂度    : C3
    版本      : v1.0.0
    开源溯源  : 无（clean-room 自研，未借鉴任何开源实现）
    平台      : 纯 IEC 61131-3（TON / R_TRIG / ABS / TIME_TO_REAL 标准转换），目标编译器
                RuSTy 1.0.8，兼容 CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert；
                无 PROPERTY、无 VLA、无 FOR..DOWNTO、无 AS 类方言
    ------------------------------------------------------------------
    功能说明  : ① 温漂：fTempCorrMv = fTempCoefMvPerC × (fTempC − fRefTempC)，从原始桥压减掉；
                ② 零点：fCorrected = fRawMv − fTempCorrMv − fZeroMv，零点由空载学习维护；
                ③ 蠕变：fCreepCorrMv = fCorrected × fCreepCoefPctPerMin × 0.01 × tHoldMin，
                   方向随 fCorrected 的符号自动跟随载荷方向（负载荷得到负补偿量）；
                ④ 空载学习：bNoLoadWindow = TRUE 且持续 ≥ tLearnMinMs（TON 无条件刷新）→ 进
                   eLearn，用一阶低通（系数固定 0.05，见代理假设）把「温漂修正后、零点修正前」
                   的值学成新零点；窗口消失立即退出并冻结零点；
                ⑤ 防误学：学习期间若 |温漂修正后值| 超 fNoLoadMaxMv（载荷比 > 1）→ 判「并非空载」，
                   退出 eLearn 回 eRun 并置 bLearnRejected 单拍位；同一空载窗口内不再重试
                   （_bRejLatch 在窗口消失时清除），避免窗口内反复进出打摆；
                ⑥ 温度或原始值非有限 → eFault，且 fOutMv 保持上一次有效值（保持而非清零）。
    量纲链    : fTempCoefMvPerC [mV/°C] × (fTempC − fRefTempC) [°C] → fTempCorrMv [mV]（°C 约去）；
                fRawMv [mV] − fTempCorrMv [mV] → _fRawTemp [mV]（零点修正前）；
                _fRawTemp [mV] − fZeroMv [mV] → fCorrected [mV]（零点修正后）；
                fCorrected [mV] × fCreepCoefPctPerMin [%/min] × 0.01 [1/%] × tHoldMin [min]
                    → fCreepCorrMv [mV]（%/min × min = %，× 0.01 无因次，只剩 mV）；
                fOutMv = fCorrected [mV] − fCreepCorrMv [mV] → [mV]；
                _fLoadRatio = |_fRawTemp| [mV] ÷ _fNoLoadGuard [mV] → [-]（判载荷比与 1.0 直比）。
                全程无「温度与毫伏相加」「时间与毫伏相加」，量纲链逐段闭合。
    代理假设  : （R95 三句声明）① 代理值 = 低通系数固定 0.05，隐含标称扫描周期 10 ms，
                对应零点学习时间常数 τ ≈ 0.2 s；② 覆盖范围 = 5 ms ~ 20 ms 的周期任务
                （时间常数随之在 0.1 s ~ 0.4 s 间变化，只影响学习快慢，不影响零点收敛方向）；
                ③ 覆盖不到的区间（< 2 ms 或 > 50 ms 的任务）由现场加长 tLearnMinMs 与空载窗口
                驻留时长补偿，本件不提供自适应系数。
    交付门槛  : 本件使用 TIME_TO_REAL 标准转换做承载时长换算，须在 CODESYS / TwinCAT /
                InoProShop 三平台各编译验证一次（R64）。
    状态机    : eInit(0) --使能且输入有限且组态合法--> eRun(10)
                eRun --空载窗口持续到（tonLearn.Q）且本窗口未拒学过--> eLearn(20)
                eLearn --窗口消失--> eRun（零点冻结）；--载荷比 > 1--> eRun（拒学 + 单拍位）
                eRun/eLearn --失能--> eHold(30)（冻结保持末次有效输出与累计）
                eHold --重新使能--> eRun
                任意相 --输入非有限或组态非法--> eFault(90)
                eFault 的唯一解除路径 = bReset 上升沿（见段 8 与复位作用域声明）
    失能语义  : bEnable = FALSE → eHold，fOutMv 冻结保持末次有效值，蠕变累计与零点学习全部冻结
                （取「冻结保持」而非「降级清零」：称重输出清零会被上位当作零载荷，属伪造计量事实）。
    复位作用域: bReset 上升沿①清 _bFaultLatch / _bBadIn / _bCfgBad；②清 _fZero 与
                _fHoldBaseMin（零点与承载累计一并归零，须重新学习）；③清 _bRejLatch；
                ④迁相回 eInit；⑤不清 _fOutHold（补偿输出不因复位跳变），_bHoldValid 保留。
    防御口径  : NaN 用自反 f<>f；±Inf 用 (f−f)<>(f−f)；另设幅值域闸 ABS(f) > 1.0E30。
                除子三类：DL_ST_MS_PER_MIN = 60000.0 与 DL_ST_PCT_TO_RATIO = 0.01 为具名常量，
                结构上不可能为零；载荷比除子 _fNoLoadGuard 由 fNoLoadMaxMv 经两级下限兜底后
                才参与除法（R117 两级回退）。
                计算结果写入保持槽 _fOutHold 之前必须过非有限闸（R133），污染数据不进保持槽。
    规格偏离  : 派单把学习最短时长写作 fLearnMinMs，其实际类型为 TIME；本库规范 1.2 规定
                时间量前缀为 t，故落为 tLearnMinMs，语义不变。按 R190 归因唯一补充
                bCfgErr / bDataErr 两个诊断位，使两条故障成因各自可观测。
    码位说明  : 本件按零码位范式交付，不分配 16# 事件码；学习结果与故障一律经
                eState / bLearnRejected / bFaultOut / bCfgErr / bDataErr 组合观测。
    修订记录  : 2026-11-24 v1.0.0 首次入库（R87 批 · #3）
*)
TYPE E_DL_StrainCompState :
(
    eInit   := 0,     // 初始化：首扫或复位后，尚无可信输出 | init, no trustworthy output yet
    eRun    := 10,    // 运行：温漂 + 零点 + 蠕变三项全补偿 | running, thermal, zero and creep all compensated
    eLearn  := 20,    // 学习：空载窗口内低通重学零点，蠕变累计冻结 | learning the zero in a no-load window
    eHold   := 30,    // 保持：失能冻结末次有效输出与累计 | hold, disabled, last valid output frozen
    eFault  := 90     // 故障：输入非有限或组态非法，锁存至复位沿 | fault latched until the reset edge
);
END_TYPE

FUNCTION_BLOCK FB_DL_StrainThermalCreepAdaptive
VAR_INPUT
    bEnable             : BOOL;                   // 使能电平，TRUE = 允许补偿与学习 | enable level, TRUE = compensation and learning
    bReset              : BOOL;                   // 复位请求，上升沿生效 | reset request, rising-edge active
    fRawMv              : REAL;                   // 应变桥原始输出 [mV] | raw bridge output [mV]
    fTempC              : REAL;                   // 桥体温度 [°C] | bridge temperature [degC]
    fRefTempC           : REAL := 20.0;           // 参考温度（补偿零点温度）[°C] | reference temperature [degC]
    fTempCoefMvPerC     : REAL := 0.0;            // 温度系数 [mV/°C]，正负均合法 | temperature coefficient [mV/degC]
    fCreepCoefPctPerMin : REAL := 0.0;            // 蠕变系数 [%/min]，须非负 | creep coefficient [%/min], non-negative
    bNoLoadWindow       : BOOL;                   // 空载窗口（上位给出：工位确认为空载）| no-load window from the supervisor
    tLearnMinMs         : TIME := T#2S;           // 空载最短驻留时长，达到才允许学习 [ms] | minimum no-load dwell [ms]
    fNoLoadMaxMv        : REAL := 0.5;            // 空载带半宽，超出即判非空载 [mV] | no-load band half width [mV]
END_VAR
VAR_OUTPUT
    eState              : E_DL_StrainCompState;          // 主状态，供 HMI 使用 | main state for HMI
    fOutMv              : REAL;                   // 补偿后输出（去皮净载荷）[mV] | compensated output [mV]
    fTempCorrMv         : REAL;                   // 本拍温漂补偿量 [mV] | thermal correction this scan [mV]
    fCreepCorrMv        : REAL;                   // 本拍蠕变补偿量 [mV] | creep correction this scan [mV]
    fZeroMv             : REAL;                   // 当前生效零点 [mV] | active zero offset [mV]
    bLearnRejected      : BOOL;                   // 学习被拒事件位，单拍 | learning rejection event, single scan
    bFaultOut           : BOOL;                   // 故障汇总位 | fault aggregate
    bCfgErr             : BOOL;                   // 组态非法诊断位（归因唯一，R190）| bad-configuration flag
    bDataErr            : BOOL;                   // 数据非有限诊断位（归因唯一，R190）| non-finite data flag
END_VAR
VAR
    rtReset             : R_TRIG;                 // 复位上升沿实例，每拍无条件刷新 | reset rising-edge instance
    tonHold             : TON;                    // 承载时长分片计时，自复位，每拍无条件刷新 | load-hold slice timer, self-resetting
    tonLearn            : TON;                    // 空载窗口驻留计时，每拍无条件刷新 | no-load dwell timer
    _eState             : E_DL_StrainCompState := E_DL_StrainCompState.eInit; // 状态机内部当前态 | internal current state
    _bInit              : BOOL := TRUE;           // 首扫初始化标志，含零点与累计状态 | first-scan init flag
    _bResetLatch        : BOOL := FALSE;          // 复位沿锁存量，本拍末清除 | reset-edge latch, cleared at scan end
    _bFaultLatch        : BOOL := FALSE;          // 故障锁存位 | fault latch
    _bBadIn             : BOOL := FALSE;          // 输入非有限成因位 | non-finite input cause
    _bCfgBad            : BOOL := FALSE;          // 组态非法成因位 | bad configuration cause
    _bRejLatch          : BOOL := FALSE;          // 拒学锁存，空载窗口消失时清除 | rejection latch, cleared when the window drops
    _bHoldValid         : BOOL := FALSE;          // 保持槽已有有效值标志 | holder contains a valid value
    _bLoadNow           : BOOL := FALSE;          // 本拍存在载荷（超空载带）| load present this scan
    _fZero              : REAL := 0.0;            // 学习得到的零点 [mV] | learned zero offset [mV]
    _fTempCorr          : REAL := 0.0;            // 温漂补偿量 [mV] | thermal correction [mV]
    _fRawTemp           : REAL := 0.0;            // 温漂修正后、零点修正前的值 [mV] | thermally corrected, pre-zero [mV]
    _fCorrected         : REAL := 0.0;            // 温漂与零点均修正后的值 [mV] | fully corrected value [mV]
    _fCreepCorr         : REAL := 0.0;            // 蠕变补偿量 [mV] | creep correction [mV]
    _fOut               : REAL := 0.0;            // 本拍补偿输出 [mV] | compensated output this scan [mV]
    _fOutHold           : REAL := 0.0;            // 输出保持槽，只写已过非有限闸的值 [mV] | output holder, gated before writing [mV]
    _fNoLoadGuard       : REAL := 0.0;            // 空载带半宽的兜底值 [mV]，作除法除子 | no-load band with floor, used as divisor [mV]
    _fLoadRatio         : REAL := 0.0;            // 载荷比 [-] = |值| ÷ 空载带半宽 | load ratio, dimensionless
    _fHoldBaseMin       : REAL := 0.0;            // 已满片承载时长基值 [min] | accumulated whole-slice hold time [min]
    _fHoldMin           : REAL := 0.0;            // 参与蠕变计算的承载时长 [min] | hold time used by the creep model [min]
END_VAR
VAR CONSTANT
    DL_ST_EPS           : REAL := 1.0E-6;         // 浮点判零容差 [mV] | float zero tolerance [mV]
    DL_ST_MAG_MAX       : REAL := 1.0E30;         // 有限幅值域闸上限 [mV] | magnitude domain bound [mV]
    DL_ST_BAND_FLOOR    : REAL := 1.0E-3;         // 空载带半宽下限兜底 [mV] | no-load band floor [mV]
    DL_ST_LPF_ALPHA     : REAL := 0.05;           // 零点学习低通系数 [-]，见代理假设三句 | zero-learning low-pass coefficient
    DL_ST_MS_PER_MIN    : REAL := 60000.0;        // 毫秒与分钟换算常量 [ms/min] | milliseconds per minute
    DL_ST_PCT_TO_RATIO  : REAL := 0.01;           // 百分数转无因次常量 [1/%] | percent to ratio constant
    DL_ST_SLICE_MIN     : REAL := 60.0;           // 承载时长分片宽度 [min]（对应 TON 的 1 h 量程）| hold slice width [min]
    DL_ST_HOLD_MAX_MIN  : REAL := 1000000.0;      // 承载时长基值饱和上限 [min]，防浮点溢出 | hold-time saturation bound [min]
END_VAR

METHOD ClampToBand : REAL
(*
    把补偿量钳到 ±带宽，防止系数误配时补偿量把输出打穿。纯函数，无跨拍状态。
    Clamp a correction to a symmetric band so a mis-parameterised coefficient cannot saturate the output.
*)
VAR_INPUT
    fIn   : REAL;                                 // 待钳补偿量 [mV] | correction to clamp [mV]
    fBand : REAL;                                 // 对称带宽（已兜底为正）[mV] | symmetric band, floored positive [mV]
END_VAR
ClampToBand := fIn;                               // 直通后按两侧硬界饱和 | straight-through, saturated below
IF ClampToBand > fBand THEN
    ClampToBand := fBand;                         // 正向钳到 +带宽 [mV] | clamp to the positive band
END_IF
IF ClampToBand < (0.0 - fBand) THEN
    ClampToBand := 0.0 - fBand;                   // 负向钳到 −带宽 [mV] | clamp to the negative band
END_IF
END_METHOD

// 段 1｜输出预置与首扫初始化（含零点与累计状态，故必须有 _bInit，R310）
// segment 1, output presets and first-scan initialisation; the zero and accumulators require _bInit
fTempCorrMv := 0.0;                                // 预置温漂补偿 0 [mV] | preset zero thermal correction [mV]
fCreepCorrMv := 0.0;                               // 预置蠕变补偿 0 [mV] | preset zero creep correction [mV]
bLearnRejected := FALSE;                           // 预置无拒学事件（清零归属本段，R256）| preset no rejection event
_bBadIn := FALSE;                                  // 预置输入有限 | preset finite input
_bCfgBad := FALSE;                                 // 预置组态合法 | preset legal configuration
_bLoadNow := FALSE;                                // 预置无载荷 | preset no load
IF _bInit THEN
    _bInit := FALSE;                               // 首扫只执行一次 | runs once on the first scan
    _eState := E_DL_StrainCompState.eInit;                // 首扫状态回初相 | initialise the state
    _fZero := 0.0;                                 // 首扫零点归零 [mV]，由空载学习建立 | initial zero [mV]
    _fHoldBaseMin := 0.0;                          // 首扫承载时长归零 [min] | initial hold time [min]
    _fHoldMin := 0.0;                              // 首扫参与量归零 [min] | initial hold time for the model [min]
    _bRejLatch := FALSE;                           // 首扫清拒学锁存 | clear the rejection latch
    _bHoldValid := FALSE;                          // 首扫无有效保持值 | no valid holder value yet
END_IF

// 段 2｜非有限闸：NaN 自反 + Inf 自减 + 幅值域，逐个浮点入参枚举（R4 / R151 / R272）
// segment 2, non-finite gate over every REAL input: NaN self-reflexive, Inf by self-subtraction, magnitude bound
IF (fRawMv <> fRawMv) OR ((fRawMv - fRawMv) <> (fRawMv - fRawMv)) THEN
    _bBadIn := TRUE;                               // 原始桥压 NaN 或 ±Inf | raw bridge output NaN or infinity
END_IF
IF ABS(fRawMv) > DL_ST_MAG_MAX THEN
    _bBadIn := TRUE;                               // 原始桥压超幅值域 | raw bridge output beyond the magnitude domain
END_IF
IF (fTempC <> fTempC) OR ((fTempC - fTempC) <> (fTempC - fTempC)) THEN
    _bBadIn := TRUE;                               // 温度 NaN 或 ±Inf | temperature NaN or infinity
END_IF
IF ABS(fTempC) > DL_ST_MAG_MAX THEN
    _bBadIn := TRUE;                               // 温度超幅值域 | temperature beyond the magnitude domain
END_IF
IF (fRefTempC <> fRefTempC) OR ((fRefTempC - fRefTempC) <> (fRefTempC - fRefTempC)) THEN
    _bBadIn := TRUE;                               // 参考温度 NaN 或 ±Inf | reference temperature NaN or infinity
END_IF
IF ABS(fRefTempC) > DL_ST_MAG_MAX THEN
    _bBadIn := TRUE;                               // 参考温度超幅值域 | reference temperature beyond the magnitude domain
END_IF
IF (fTempCoefMvPerC <> fTempCoefMvPerC) OR ((fTempCoefMvPerC - fTempCoefMvPerC) <> (fTempCoefMvPerC - fTempCoefMvPerC)) THEN
    _bBadIn := TRUE;                               // 温度系数 NaN 或 ±Inf | temperature coefficient NaN or infinity
END_IF
IF ABS(fTempCoefMvPerC) > DL_ST_MAG_MAX THEN
    _bBadIn := TRUE;                               // 温度系数超幅值域 | temperature coefficient beyond the magnitude domain
END_IF
IF (fCreepCoefPctPerMin <> fCreepCoefPctPerMin) OR ((fCreepCoefPctPerMin - fCreepCoefPctPerMin) <> (fCreepCoefPctPerMin - fCreepCoefPctPerMin)) THEN
    _bBadIn := TRUE;                               // 蠕变系数 NaN 或 ±Inf | creep coefficient NaN or infinity
END_IF
IF ABS(fCreepCoefPctPerMin) > DL_ST_MAG_MAX THEN
    _bBadIn := TRUE;                               // 蠕变系数超幅值域 | creep coefficient beyond the magnitude domain
END_IF
IF (fNoLoadMaxMv <> fNoLoadMaxMv) OR ((fNoLoadMaxMv - fNoLoadMaxMv) <> (fNoLoadMaxMv - fNoLoadMaxMv)) THEN
    _bBadIn := TRUE;                               // 空载带半宽 NaN 或 ±Inf | no-load band NaN or infinity
END_IF
IF ABS(fNoLoadMaxMv) > DL_ST_MAG_MAX THEN
    _bBadIn := TRUE;                               // 空载带半宽超幅值域 | no-load band beyond the magnitude domain
END_IF

// 段 3｜组态闸与两级兜底：空载带半宽作除法除子，先兜底；蠕变系数须非负；学习时长须非负
// segment 3, configuration gate and two-stage fallback; the band is a divisor and the creep coefficient must be non-negative
_fNoLoadGuard := fNoLoadMaxMv;                     // 取配置空载带半宽 [mV] | take the configured band [mV]
IF _fNoLoadGuard < DL_ST_BAND_FLOOR THEN
    _fNoLoadGuard := DL_ST_BAND_FLOOR;             // 一级兜底：钳到定义域下限 [mV] | stage-one clamp to the floor [mV]
END_IF
IF fCreepCoefPctPerMin < 0.0 THEN
    _bCfgBad := TRUE;                              // 蠕变系数为负：方向无物理意义，判组态非法 | negative creep coefficient is illegal
END_IF
IF tLearnMinMs < T#0S THEN
    _bCfgBad := TRUE;                              // 学习时长非法（TIME 负值）：判组态非法 | negative learning time is illegal
END_IF
IF fNoLoadMaxMv <= DL_ST_EPS THEN
    _bCfgBad := TRUE;                              // 空载带为零或负：空载判据无法成立，判组态非法 | degenerate band is illegal
END_IF

// 段 4｜温漂修正与零点修正（双闸均通过才计算，避免污染下游全部判据）
// segment 4, thermal and zero correction; computed only when both gates pass, so no polluted value flows downstream
IF (NOT _bBadIn) AND (NOT _bCfgBad) THEN
    _fTempCorr := fTempCoefMvPerC * (fTempC - fRefTempC); // 温漂补偿量 [mV] = [mV/°C] × [°C] | thermal correction [mV]
    _fRawTemp := fRawMv - _fTempCorr;              // 温漂修正后、零点修正前 [mV] | thermally corrected, pre-zero [mV]
    _fCorrected := _fRawTemp - _fZero;             // 零点修正后 [mV] | zero-corrected [mV]
    _fLoadRatio := ABS(_fRawTemp) / _fNoLoadGuard; // 载荷比 [-] = [mV] ÷ [mV]，除子已兜底非零 | guarded division
    IF _fLoadRatio > 1.0 THEN
        _bLoadNow := TRUE;                         // 超空载带：判定存在载荷 | beyond the band, load present
    END_IF
ELSE
    _fTempCorr := 0.0;                             // 闸门未过：本拍补偿量置 0，输出走保持 | gates failed, correction zeroed
    _fCorrected := 0.0;                            // 闸门未过：修正值为 0 且不写入保持槽 | corrected value zeroed, not stored
    _fLoadRatio := 0.0;                            // 闸门未过：载荷比置 0 | load ratio zeroed
END_IF

// 段 5｜定时器与沿实例无条件周期刷新（R7）；承载计时自复位（R188）
// segment 5, timers and edge instances refreshed unconditionally; the hold-slice timer is self-resetting
rtReset(CLK := bReset);
tonHold(IN := (NOT tonHold.Q) AND bEnable AND (NOT _bFaultLatch) AND _bLoadNow AND (_eState <> E_DL_StrainCompState.eLearn), PT := T#1H);
tonLearn(IN := bEnable AND bNoLoadWindow AND (NOT _bFaultLatch) AND (NOT _bRejLatch), PT := tLearnMinMs);
IF rtReset.Q THEN
    _bResetLatch := TRUE;                          // 复位沿存锁存量，段 8 统一消费 | store the reset edge, consumed in segment 8
END_IF

// 段 6｜承载时长累计：分片到时分片基值 +1，未满片的零头按 ET 折分钟（边界拍去重，R45②）
// segment 6, hold-time accumulation; whole slices are added to the base, the remainder comes from ET without double counting
IF tonHold.Q THEN
    _fHoldBaseMin := _fHoldBaseMin + DL_ST_SLICE_MIN; // 满一个分片：基值加 60 [min] | one slice completed, add 60 min
    IF _fHoldBaseMin > DL_ST_HOLD_MAX_MIN THEN
        _fHoldBaseMin := DL_ST_HOLD_MAX_MIN;        // 饱和，防浮点溢出 | saturate to avoid float overflow
    END_IF
    _fHoldMin := _fHoldBaseMin;                    // 到时分片已计入基值，ET 不再重复折算 | the slice is already in the base
ELSE
    _fHoldMin := _fHoldBaseMin + TIME_TO_REAL(tonHold.ET) / DL_ST_MS_PER_MIN; // 基值 + 零头 [min]，除子为常量 | base plus remainder [min]
END_IF

// 段 7｜空载窗口消失即解除拒学锁存（唯一清除边；否则同一窗口内永久拒学）
// segment 7, dropping the no-load window clears the rejection latch, the only release edge for that latch
IF NOT bNoLoadWindow THEN
    _bRejLatch := FALSE;                           // 窗口消失 → 下一窗口可重试学习 | window dropped, the next window may retry
END_IF

// 段 8｜复位沿与故障锁存（复位先执行，保证本拍新故障不被抹除，R275）
// segment 8, reset edge and fault latches; reset runs first so a same-scan fault survives
IF _bResetLatch THEN
    _bFaultLatch := FALSE;                         // 清故障锁存 | clear the fault latch
    _bBadIn := FALSE;                              // 清数据非有限成因位 | clear the non-finite cause
    _bCfgBad := FALSE;                             // 清组态非法成因位（下一拍按新参数重判）| clear the configuration cause
    _fZero := 0.0;                                 // 零点归零 [mV]，须重新学习 | zero cleared, must be re-learned
    _fHoldBaseMin := 0.0;                          // 承载累计归零 [min] | hold-time base cleared
    _fHoldMin := 0.0;                              // 参与量归零 [min] | hold time for the model cleared
    _bRejLatch := FALSE;                           // 清拒学锁存 | clear the rejection latch
    _eState := E_DL_StrainCompState.eInit;                // 迁相回初相 | return to the init phase
END_IF
IF _bBadIn AND (NOT _bFaultLatch) THEN
    _bFaultLatch := TRUE;                          // 锁存数据非有限（独立成因）| latch the non-finite cause
    _eState := E_DL_StrainCompState.eFault;               // 与锁存同拍迁相（R258）| migrate in the same scan
END_IF
IF _bCfgBad AND (NOT _bFaultLatch) THEN
    _bFaultLatch := TRUE;                          // 锁存组态非法（独立成因）| latch the configuration cause
    _eState := E_DL_StrainCompState.eFault;               // 与锁存同拍迁相（R258）| migrate in the same scan
END_IF

// 段 9｜主状态机：ENUM + CASE + ELSE 兜底（R6）
// segment 9, main state machine with ENUM + CASE + ELSE fallback
CASE _eState OF
E_DL_StrainCompState.eInit:
    // 拍 N 进入：首扫或复位沿；本拍行为：不做补偿写入，保持槽尚未建立；
    // 拍 N+1 转出：使能且输入有限且组态合法 → eRun
    // entered on the first scan or the reset edge; no compensation is written yet because the holder is empty;
    // exits to eRun once enabled with finite inputs and a legal configuration
    IF bEnable AND (NOT _bBadIn) AND (NOT _bCfgBad) THEN
        _eState := E_DL_StrainCompState.eRun;
    END_IF

E_DL_StrainCompState.eRun:
    IF NOT bEnable THEN
        _eState := E_DL_StrainCompState.eHold;            // 失能 → 保持相 | disable falls into hold
    ELSIF bNoLoadWindow AND tonLearn.Q THEN
        _eState := E_DL_StrainCompState.eLearn;           // 空载窗口驻留到且本窗口未拒学 → 进学习 | dwell elapsed, enter learning
    END_IF

E_DL_StrainCompState.eLearn:
    // 学习：低通把「温漂修正后、零点修正前」的值学成零点；该值不含零点自身，故不会自激
    // learning: the low-pass tracks the thermally corrected pre-zero value, which excludes the zero itself
    IF NOT bEnable THEN
        _eState := E_DL_StrainCompState.eHold;            // 失能 → 保持相（零点冻结）| disable falls into hold, the zero is frozen
    ELSIF NOT bNoLoadWindow THEN
        _eState := E_DL_StrainCompState.eRun;             // 窗口消失 → 退出并冻结零点 | the window dropped, freeze the zero
    ELSIF _fLoadRatio > 1.0 THEN
        bLearnRejected := TRUE;                    // 拒学事件，单拍（清零归属段 1）| rejection event, single scan
        _bRejLatch := TRUE;                        // 本窗口内不再重试 | no retry inside this window
        _eState := E_DL_StrainCompState.eRun;             // 回运行相，零点保持旧值 | back to run with the previous zero
    ELSE
        _fZero := _fZero + DL_ST_LPF_ALPHA * (_fRawTemp - _fZero); // 零点一阶低通 [mV] | first-order zero tracking [mV]
    END_IF

E_DL_StrainCompState.eHold:
    // 保持：不学习、不累计、不更新保持槽；fOutMv 由 _fOutHold 回放（冻结保持，见头注释失能语义）
    // hold: no learning, no accumulation and no holder update; the output replays the frozen holder
    IF bEnable AND (NOT _bFaultLatch) THEN
        _eState := E_DL_StrainCompState.eRun;             // 重新使能 → 回运行相 | re-enabled, back to run
    END_IF

E_DL_StrainCompState.eFault:
    // 驻留语义：本相只能由段 8 的复位沿迁出（唯一解除路径）；输出保持末次有效值
    // dwell semantics: left only through the reset edge in segment 8; the output keeps the last valid value

ELSE
    // 非法枚举值（越界或未定义成员）：不猜，置故障并回故障相
    // illegal enumerator: no guessing, latch a fault and return to the fault phase
    _bFaultLatch := TRUE;
    _eState := E_DL_StrainCompState.eFault;
END_CASE;

// 段 10｜蠕变补偿与保持槽写入（写入前过非有限闸，R133；组态闸与数据闸均通过才写）
// segment 10, creep correction and holder write; the value is gated before it enters the holder
IF (NOT _bBadIn) AND (NOT _bCfgBad) AND (NOT _bFaultLatch) THEN
    _fCreepCorr := _fCorrected * fCreepCoefPctPerMin * DL_ST_PCT_TO_RATIO * _fHoldMin; // 蠕变补偿 [mV]，符号随载荷 | creep correction [mV]
    _fCreepCorr := ClampToBand(_fCreepCorr, ABS(_fCorrected)); // 钳到 ±|当前载荷|，系数误配时不得把输出打穿 | clamp to the load magnitude
    _fOut := _fCorrected - _fCreepCorr;            // 补偿输出 [mV] = [mV] − [mV] | compensated output [mV]
    IF (_fOut <> _fOut) OR ((_fOut - _fOut) <> (_fOut - _fOut)) THEN
        _bBadIn := TRUE;                           // 输出侧兜底：结果非有限则拒收并置数据成因位 | result non-finite, reject and flag
        _bFaultLatch := TRUE;                      // 同拍锁存故障，保证 bFaultOut 与 eFault 语义一致（R256 三件套）| latch in the same scan
        _eState := E_DL_StrainCompState.eFault;           // 同拍迁相（R256 三件套之一）| migrate in the same scan
    ELSE
        IF (_eState = E_DL_StrainCompState.eRun) OR (_eState = E_DL_StrainCompState.eLearn) THEN
            _fOutHold := _fOut;                    // 只有已证明有限的值才进保持槽 | only a proven finite value enters the holder
            _bHoldValid := TRUE;                   // 保持槽已建立 | holder established
        END_IF
        // 保持相、初相与故障相不更新保持槽：失能即冻结末次有效值（头注释已声明「冻结保持」，R191）
        // the hold, init and fault phases never update the holder, which implements the declared freeze semantics
    END_IF
ELSE
    _fCreepCorr := 0.0;                            // 闸门未过：本拍蠕变补偿置 0，输出走保持 | gates failed, correction zeroed
END_IF

// 段 11｜出口单点映射（保持槽回放，非有限污染不会外泄）
// segment 11, single-point output mapping; the holder is replayed so no polluted value leaks out
eState := _eState;                                 // 状态映射 | state mapping
fTempCorrMv := _fTempCorr;                         // 温漂补偿量映射 [mV] | thermal correction mapping [mV]
fCreepCorrMv := _fCreepCorr;                       // 蠕变补偿量映射 [mV] | creep correction mapping [mV]
fZeroMv := _fZero;                                 // 生效零点映射 [mV] | active zero mapping [mV]
IF _bHoldValid THEN
    fOutMv := _fOutHold;                           // 有有效历史值：冻结保持末次有效输出 [mV] | replay the last valid output [mV]
ELSE
    fOutMv := 0.0;                                 // 从未建立有效值：输出哨兵零点，不伪造读数 [mV] | sentinel zero, never a fake reading
END_IF
bFaultOut := _bFaultLatch;                         // 故障锁存回放 | replay the fault latch
bCfgErr := _bCfgBad;                               // 组态非法诊断位 | bad-configuration diagnostic
bDataErr := _bBadIn;                               // 数据非有限诊断位 | non-finite data diagnostic

// 段 12｜本拍消费量收尾（仅清沿锁存；不触碰任何锁存位与 CASE 内写入量）
// segment 12, end-of-scan cleanup; only the edge latch is cleared
_bResetLatch := FALSE;
END_FUNCTION_BLOCK
