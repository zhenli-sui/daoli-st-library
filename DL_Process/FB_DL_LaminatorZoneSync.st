(*==============================================================================
 * 组件名称 (Component)  : FB_DL_LaminatorZoneSync
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 层压机多温区联动升温。
 *                         把 1..4 个温区当作一个**联动体**（非独立温控）来推：同一设定、统一分级投切、
 *                         统一限温差，避免各区各自为政造成"局部过冲 → 材料应力"。
 *                         三段语义：
 *                           ① **分级投切**：按"设定 − 平均实测"的偏差分三级
 *                              Δ > fDevStage3 → 三级（满功率）；Δ > fDevStage2 → 二级；
 *                              Δ > fDevStage1 → 一级；否则零级（保温/停加热）。
 *                              分级门槛必须单调递减（fDevStage3 > fDevStage2 > fDevStage1 > 0），否则组态非法；
 *                           ② **最小驻留**：每次换级后 tStageMin 内不再换级（防调功器被高频投切打坏）；
 *                           ③ **区间温差联锁**：区内最大温差超 fZoneDevMax 时锁存 bZoneDevLatch，
 *                              并**强制降零级**（温差失控比缺温更危险）；温差回落到限值 − 迟滞后自动解除。
 *                         串级功率指令（比例段，无积分以免风挡饱和）：
 *                           fCmdPct = Kp · (SP − T_avg) · 级系数，钳 [0, 100]
 *                           级系数：0 级 0.0；1 级 0.4；2 级 0.7；3 级 1.0
 *                         验收向量：
 *                           ① SP=180、四区均 150（Δ=30）且 fDevStage3=20 → 三级，指令 = Kp·30 钳 100
 *                           ② 四区 = {180,181,179,182}（Δ=0）→ 零级，afCmdPct 全 0
 *                           ③ 四区 = {180,180,180,196}（温差 16 > 12）→ 锁存温差联锁 + 强制零级
 *                           ④ 换级后 tStageMin 内偏差剧变 → 级不换（驻留生效）
 * 接口     (Interface)  : 入 bEnable 使能、afTempC 各区实测温度（1..4）、nZoneCnt 有效区数、fSetpointC 设定温度、
 *                         fKpPctPerC 比例增益、fDevStage1/2/3 三级门槛、fZoneDevMaxC 允许最大区间温差、
 *                         fZoneHystC 温差联锁迟滞、tStageMin 最小驻留时长、bReset 复位沿；
 *                         出 afCmdPct 各区加热指令（1..4，钳 0..100）、fAvgTempC 平均温度、
 *                         fZoneDevC 区间最大温差、iStage 当前级（0..3）、bHeating 加热中、
 *                         bZoneDevLatch 温差联锁锁存、eState 相、eCause 成因、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做"联动分级与温差联锁"，不做单区 PID、
 *                         不驱动固态继电器/调功器**（属单区温控件与 IO 层）；本件输出的是各区统一的
 *                         功率百分比，单区微调由下层温控环叠加；
 *                         ② **分区数组边界**：afTempC / afCmdPct 以字面量上界 4 声明（R104），
 *                         nZoneCnt 作运行时二次闸（钳 1..4），越界区一律输出 0 %；
 *                         ③ **门槛单调闸**：三级门槛须严格递减且为正，温差限与迟滞须为正/非负，违反即锁存 eCfgIllegal；
 *                         ④ **驻留 TON 自复位**：tonDwell 的 IN = 封锁位 ∧ ¬Q（R188），换级即重新封锁；
 *                         ⑤ **温差联锁解除式**：温差 < fZoneDevMaxC − fZoneHystC（自动）∨ bReset 上升沿（人工），
 *                         两式均自证可满足；
 *                         ⑥ 非有限温度样本 → 该区作废（不参与均值与温差），有效区为 0 → 当拍不判、bValid=FALSE；
 *                         ⑦ 零全局耦合、零物理地址。
 * 分工声明 (Scope)      : 本件只管"多温区联动分级与温差联锁"。不接管：单区温度闭环
 *                         （属 FB_DL_DryingOvenZone 族）、层压压力曲线（属 FB_DL_LaminatorPressCtrl）、
 *                         加热器断线诊断（属加热器诊断件）。
 * 来源标签 (Source Tag) : ROADMAP 空勾真缺口 P1（层压机多温区联动，自研 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位（零码位范式 R297）；诊断由 BOOL + ENUM 出口承担。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 分区闸 + 门槛单调闸 + 输出限幅 + 非有限闸 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE 兜底 ｜ R7 ✓ TON/R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R47 首版（批次 4 · 序号 16）
 *==============================================================================*)

TYPE E_DL_LzsState :
(
    eIdle  := 0,    // 待机相（未使能，指令全 0） / Idle, all commands zero
    eHeat  := 10,   // 升温相（分级投切与温差监视） / Heating, staged switching with deviation supervision
    eFault := 90    // 故障相（组态非法，等复位） / Fault, awaiting reset
);
END_TYPE

TYPE E_DL_LzsCause :
(
    eNone          := 0,   // 无异常 / No anomaly
    eCfgIllegal    := 1,   // 组态非法（区数/门槛/限值越域） / Illegal configuration
    eZoneDevExceed := 2,   // 区间温差超限（锁存，强制零级） / Zone deviation exceeded, latched, forced zero stage
    eSampleBad     := 3,   // 全部区样本非有限（当拍不判） / All zone samples non-finite
    ePhaseBad      := 4    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_LaminatorZoneSync
VAR_INPUT
    bEnable     : BOOL := FALSE;       // 使能（FALSE 时指令全 0） [-] / Enable, commands zeroed when FALSE
    afTempC     : ARRAY[1..4] OF LREAL;   // 各区实测温度（1..4） [°C] / Zone temperatures, points 1..4
    nZoneCnt    : INT := 4;            // 有效区数，域 1..4 [区] / Active zone count, 1..4
    fSetpointC  : LREAL := 180.0;      // 设定温度 [°C] / Temperature set point [°C]
    fKpPctPerC  : LREAL := 5.0;        // 比例增益，域 > 0 [%/°C] / Proportional gain, > 0
    fDevStage1  : LREAL := 3.0;        // 一级门槛（最小正偏差） [°C] / Stage-1 threshold [°C]
    fDevStage2  : LREAL := 8.0;        // 二级门槛 [°C] / Stage-2 threshold [°C]
    fDevStage3  : LREAL := 20.0;       // 三级门槛（最大） [°C] / Stage-3 threshold [°C]
    fZoneDevMaxC: LREAL := 12.0;       // 允许最大区间温差，域 > 0 [°C] / Maximum allowed inter-zone deviation
    fZoneHystC  : LREAL := 2.0;        // 温差联锁迟滞，域 ≥ 0 [°C] / Deviation latch hysteresis
    tStageMin   : TIME := T#5S;        // 换级最小驻留，域 > T#0S [ms] / Minimum stage dwell time
    bReset      : BOOL := FALSE;       // 故障/锁存复位沿 [-] / Reset edge
END_VAR
VAR_OUTPUT
    afCmdPct    : ARRAY[1..4] OF LREAL;                  // 各区加热指令（钳 0..100） [%] / Zone heater command, 0..100
    fAvgTempC   : LREAL := 0.0;                          // 平均温度（有效区） [°C] / Mean temperature of the valid zones
    fZoneDevC   : LREAL := 0.0;                          // 区间最大温差 [°C] / Maximum inter-zone deviation
    iStage      : INT := 0;                              // 当前投切级（0..3） [级] / Present stage, 0..3
    bHeating    : BOOL := FALSE;                          // 加热中（级 ≥ 1 且未被锁存） [-] / Heating active
    bZoneDevLatch : BOOL := FALSE;                        // 温差联锁锁存 [-] / Deviation interlock, latched
    bValid      : BOOL := FALSE;                          // 判据有效（至少一区有限） [-] / Judgement valid
    eState      : E_DL_LzsState := E_DL_LzsState.eIdle;   // 相出口 [-] / Phase outlet
    eCause      : E_DL_LzsCause := E_DL_LzsCause.eNone;   // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError      : BOOL := FALSE;                          // 故障标志（仅组态级） [-] / Error flag, configuration only
END_VAR
VAR
    _eState   : E_DL_LzsState := E_DL_LzsState.eIdle;    // 内部相（CASE 唯一写入目标） / Internal phase
    _eCause   : E_DL_LzsCause := E_DL_LzsCause.eNone;    // 成因锁存量 / Latched cause
    _bFault   : BOOL := FALSE;                           // 故障锁存位 / Latched fault bit
    _bDevLat  : BOOL := FALSE;                           // 温差联锁锁存位 / Latched deviation bit
    _iStage   : INT := 0;                                // 内部级（驻留保持量） / Internal stage, dwell state
    _bDwellBlk: BOOL := FALSE;                           // 驻留封锁位（换级后置位） / Dwell blocking bit
    _fSum     : LREAL := 0.0;                            // 有效区温度累加 [°C] / Sum of valid zone temperatures
    _fMin     : LREAL := 0.0;                            // 有效区最小温度 [°C] / Minimum valid temperature
    _fMax     : LREAL := 0.0;                            // 有效区最大温度 [°C] / Maximum valid temperature
    _fAvg     : LREAL := 0.0;                            // 平均温度工作值 [°C] / Mean working value
    _fDev     : LREAL := 0.0;                            // 偏差工作值 [°C] / Deviation working value
    _fZoneDev : LREAL := 0.0;                            // 区间温差工作值 [°C] / Inter-zone deviation working value
    _fCmd     : LREAL := 0.0;                            // 指令工作值 [%] / Command working value
    _fStageK  : LREAL := 0.0;                            // 级系数 [-] / Stage gain factor
    _nValid   : INT := 0;                                // 有效区计数 [区] / Valid zone count
    _i        : INT := 0;                                // 区循环下标 / Zone loop index
    _bCfgBad  : BOOL := FALSE;                           // 组态非法当拍量 / Illegal configuration this scan
    _bInit    : BOOL := FALSE;                           // 首区初始化标志（本拍首个有效区） / First-valid-zone flag
    tonDwell  : TON;                                     // 换级驻留实例，段 0 无条件调用 / Stage dwell instance
    rtReset   : R_TRIG;                                  // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_LZS_N      : INT := 4;             // 区数上限（与数组字面量上界同源） [区] / Zone upper bound
    DL_LZS_PCT_MAX: LREAL := 100.0;       // 指令上限 [%] / Command upper bound
    DL_LZS_PCT_MIN: LREAL := 0.0;         // 指令下限 [%] / Command lower bound
    DL_LZS_K1     : LREAL := 0.4;         // 一级级系数 [-] / Stage-1 gain factor
    DL_LZS_K2     : LREAL := 0.7;         // 二级级系数 [-] / Stage-2 gain factor
    DL_LZS_K3     : LREAL := 1.0;         // 三级级系数 [-] / Stage-3 gain factor
    DL_LZS_EPS    : LREAL := 1.0E-9;      // 浮点判等容差 [°C] / Equality tolerance
END_VAR

(* —— 段 0：组态闸 + TON 与沿无条件周期刷新（R228A；驻留 TON 自复位，R188） —— *)
_bCfgBad := (nZoneCnt < 1) OR (nZoneCnt > DL_LZS_N)                                        // 区数须在 1..4 / Zone count within 1..4
         OR (NOT ((fDevStage3 > fDevStage2) AND (fDevStage2 > fDevStage1) AND (fDevStage1 > 0.0)))   // 三级门槛严格递减且为正
         OR (fZoneDevMaxC <= 0.0) OR (fZoneHystC < 0.0) OR (fZoneHystC >= fZoneDevMaxC)     // 温差限与迟滞越域 / Deviation limits
         OR (fKpPctPerC <= 0.0) OR (tStageMin <= T#0S);                                     // 增益与驻留须为正 / Gain and dwell positive
rtReset(CLK := bReset);                                                                     // 复位沿 / Reset edge
tonDwell(IN := _bDwellBlk AND (NOT tonDwell.Q), PT := tStageMin);                            // 换级驻留（自复位振荡） / Stage dwell

(* —— 段 1：单拍/输出量预置（锁存量 _eCause/_bFault/_bDevLat/_iStage/_bDwellBlk 不入清单，R107） —— *)
fAvgTempC     := 0.0;                                                                       // 平均温度预置 / Mean preset
fZoneDevC     := 0.0;                                                                       // 区间温差预置 / Deviation preset
iStage        := 0;                                                                         // 级出口预置 / Stage outlet preset
bHeating      := FALSE;                                                                     // 加热中预置 / Heating preset
bValid        := FALSE;                                                                     // 有效位预置 / Validity preset
bError        := FALSE;                                                                     // 故障标志预清（R45 配对） / Error preset
_fSum := 0.0; _fMin := 0.0; _fMax := 0.0;                                                   // 统计量预置 / Statistics preset
_fAvg := 0.0; _fDev := 0.0; _fZoneDev := 0.0; _fCmd := 0.0; _fStageK := 0.0;                // 工作值预置 / Working values preset
_nValid := 0; _bInit := FALSE;                                                              // 计数与初始化标志预置 / Count and init preset
_i := 1;                                                                                    // 区循环下标归位 / Loop index preset
afCmdPct[1] := DL_LZS_PCT_MIN; afCmdPct[2] := DL_LZS_PCT_MIN;                               // 指令逐区预清零（1/4） / Zone commands preset 1 and 2
afCmdPct[3] := DL_LZS_PCT_MIN; afCmdPct[4] := DL_LZS_PCT_MIN;                               // 指令逐区预清零（3/4） / Zone commands preset 3 and 4

(* —— 段 2：组态闸（非法即锁存） —— *)
IF _bCfgBad THEN
    _eCause := E_DL_LzsCause.eCfgIllegal;                                                   // 归因：组态非法 / Cause: illegal configuration
    _bFault := TRUE;                                                                        // 锁存 / Latch
    _eState := E_DL_LzsState.eFault;                                                        // 入故障相 / Enter fault phase
END_IF

(* —— 段 3：迁出链（bReset 上升沿：清组态故障与温差锁存，R228B） —— *)
IF rtReset.Q THEN
    _bFault  := FALSE;                                                                      // 清故障锁存 / Clear fault latch
    _bDevLat := FALSE;                                                                      // 清温差锁存 / Clear the deviation latch
    _eCause  := E_DL_LzsCause.eNone;                                                        // 清成因 / Clear cause
    _iStage  := 0;                                                                          // 级归零 / Stage cleared
    _eState  := E_DL_LzsState.eIdle;                                                        // 回待机相 / Back to idle
END_IF

(* —— 段 4：相迁移（使能驱动；故障相由段 3 迁出） —— *)
CASE _eState OF

E_DL_LzsState.eIdle:
    IF bEnable AND (NOT _bCfgBad) THEN
        _eState := E_DL_LzsState.eHeat;                                                     // 使能进升温相 / Enter heating
    END_IF

E_DL_LzsState.eHeat:
    IF NOT bEnable THEN
        _iStage := 0;                                                                        // 失能：级归零（指令全 0） / Disable clears the stage
        _eState := E_DL_LzsState.eIdle;                                                     // 回待机相（不借故障相过桥） / Back to idle
    END_IF

E_DL_LzsState.eFault:
    ;                                                                                        // 故障相：由段 3 复位沿迁出 / Exit via the reset edge

ELSE
    _eCause := E_DL_LzsCause.ePhaseBad;                                                      // 归因：非法相位 / Cause: illegal phase
    _bFault := TRUE;                                                                         // 锁存 / Latch
    _eState := E_DL_LzsState.eFault;                                                         // 强拉故障相 / Force fault phase

END_CASE

(* —— 段 5：有效区统计（非有限区作废；区内最大温差） —— *)
IF _eState = E_DL_LzsState.eHeat THEN
    FOR _i := 1 TO DL_LZS_N DO
        IF (_i <= nZoneCnt) AND NOT ((afTempC[_i] <> afTempC[_i]) OR ((afTempC[_i] - afTempC[_i]) <> (afTempC[_i] - afTempC[_i]))) THEN
            _nValid := _nValid + 1;                                                         // 有效区计数 / Valid count
            _fSum := _fSum + afTempC[_i];                                                   // 累加 / Accumulate
            IF (NOT _bInit) OR (afTempC[_i] < _fMin) THEN
                _fMin := afTempC[_i];                                                       // 最小值 / Minimum
            END_IF
            IF (NOT _bInit) OR (afTempC[_i] > _fMax) THEN
                _fMax := afTempC[_i];                                                       // 最大值 / Maximum
            END_IF
            _bInit := TRUE;                                                                 // 首个有效区已处理 / First valid zone handled
        END_IF
    END_FOR

    IF _nValid > 0 THEN
        _fAvg := _fSum / INT_TO_LREAL(_nValid);                                             // 平均（分母已证 ≥ 1） / Mean
        _fZoneDev := _fMax - _fMin;                                                         // 区间温差 / Inter-zone deviation
        _fDev := fSetpointC - _fAvg;                                                        // 偏差（正 = 欠温） / Deviation, positive means below set point
        bValid := TRUE;                                                                     // 判据有效 / Valid

        (* —— 段 6：温差联锁（超限锁存并强制零级；回落过迟滞自动解除） —— *)
        IF (_fZoneDev > fZoneDevMaxC) AND (NOT _bDevLat) THEN
            _bDevLat := TRUE;                                                               // 超限：锁存 / Beyond the limit: latch
            _eCause := E_DL_LzsCause.eZoneDevExceed;                                        // 归因：区间温差超限 / Cause: inter-zone deviation
            _iStage := 0;                                                                   // 强制零级（安全侧优先于升温） / Force stage zero
            _bDwellBlk := TRUE;                                                             // 换级后进入驻留 / Enter dwell
        ELSIF _bDevLat AND (_fZoneDev < (fZoneDevMaxC - fZoneHystC)) THEN
            _bDevLat := FALSE;                                                              // 回落过迟滞：自动解除 / Recovered: auto-release
        END_IF

        (* —— 段 7：分级投切（驻留窗内不换级） —— *)
        IF NOT _bDevLat THEN
            IF (NOT _bDwellBlk) OR tonDwell.Q THEN
                _bDwellBlk := FALSE;                                                        // 驻留窗满：允许换级 / Dwell elapsed
                IF _fDev > fDevStage3 THEN
                    IF _iStage <> 3 THEN
                        _iStage := 3; _bDwellBlk := TRUE;                                    // 升三级并重新驻留 / Stage 3
                    END_IF
                ELSIF _fDev > fDevStage2 THEN
                    IF _iStage <> 2 THEN
                        _iStage := 2; _bDwellBlk := TRUE;                                    // 二级 / Stage 2
                    END_IF
                ELSIF _fDev > fDevStage1 THEN
                    IF _iStage <> 1 THEN
                        _iStage := 1; _bDwellBlk := TRUE;                                    // 一级 / Stage 1
                    END_IF
                ELSE
                    IF _iStage <> 0 THEN
                        _iStage := 0; _bDwellBlk := TRUE;                                    // 零级（保温） / Stage 0
                    END_IF
                END_IF
            END_IF
        END_IF

        (* —— 段 8：串级功率指令（比例段，级系数缩放，逐区钳位） —— *)
        CASE _iStage OF
        1: _fStageK := DL_LZS_K1;                                                            // 一级系数 / Stage-1 factor
        2: _fStageK := DL_LZS_K2;                                                            // 二级系数 / Stage-2 factor
        3: _fStageK := DL_LZS_K3;                                                            // 三级系数 / Stage-3 factor
        ELSE
            _fStageK := 0.0;                                                                 // 零级：无功率 / Stage 0: no power
        END_CASE
        _fCmd := fKpPctPerC * _fDev * _fStageK;                                              // 比例指令 / Proportional command
        IF _fCmd > DL_LZS_PCT_MAX THEN
            _fCmd := DL_LZS_PCT_MAX;                                                         // 上钳 / Clamp high
        ELSIF _fCmd < DL_LZS_PCT_MIN THEN
            _fCmd := DL_LZS_PCT_MIN;                                                         // 下钳（负偏差不制冷） / Clamp low
        END_IF
        IF _bDevLat OR (_iStage = 0) THEN
            _fCmd := DL_LZS_PCT_MIN;                                                         // 锁存或零级：指令归零 / Zero command
        END_IF

        FOR _i := 1 TO DL_LZS_N DO
            IF _i <= nZoneCnt THEN
                afCmdPct[_i] := _fCmd;                                                       // 各区统一指令（联动语义） / Uniform command per zone
            ELSE
                afCmdPct[_i] := DL_LZS_PCT_MIN;                                              // 越界区零指令 / Out-of-range zones zeroed
            END_IF
        END_FOR
    ELSE
        _eCause := E_DL_LzsCause.eSampleBad;                                                  // 归因：全部区非有限（当拍不判） / Cause: all samples invalid
    END_IF
END_IF

(* —— 段 9：出口单点映射（名实双出口，R191） —— *)
fAvgTempC     := _fAvg;                                                                       // 平均温度出口 / Mean outlet
fZoneDevC     := _fZoneDev;                                                                   // 区间温差出口 / Deviation outlet
iStage        := _iStage;                                                                     // 级出口 / Stage outlet
bHeating      := (_iStage >= 1) AND (NOT _bDevLat) AND (_eState = E_DL_LzsState.eHeat);       // 加热中出口 / Heating outlet
bZoneDevLatch := _bDevLat;                                                                    // 温差锁存出口 / Deviation latch outlet
eState        := _eState;                                                                     // 相出口 / Phase outlet
eCause        := _eCause;                                                                     // 成因出口 / Cause outlet
bError        := _bFault;                                                                     // 故障标志 / Error flag

END_FUNCTION_BLOCK
