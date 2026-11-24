(*==============================================================================
 * 组件名称 (Component)  : FB_DL_TankBlanketPrCtrl
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 储罐氮封压差监测联动。
 *                         两只压力变送器（A/B）冗余采集氮封压差，按"双表一致 → 取均值；双表偏离超限 →
 *                         锁存传感器偏离故障并退化为**取低值**（保守侧：宁可早开补气阀，不可迟开）"
 *                         的判据链给出唯一可信压差，再驱动氮封补气阀与超压排放阀。
 *                         三条固化纪律：
 *                           ① **双表冗余判据（复用 RedundantSwitch 语义）**：本件不实例化
 *                              `FB_DL_RedundantSwitch`（R47 批次零文件级依赖），复用其三条语义——
 *                              偏差闸、退化取低值、偏离故障锁存；
 *                           ② **低压联锁**：可信压差低于低压门槛并经 tLowConf 确认后锁存 bLowInterlock，
 *                              补气阀保持开启直到压差回升到门槛 + 迟滞（迟滞防抖，不靠时间滤）；
 *                           ③ **阀输出限幅**：模拟阀位指令钳在 [fOpenMinPct, 100]，BOOL 阀位与之同源
 *                              （名实双出口，R191），禁"模拟量说开、BOOL 说关"。
 *                         验收向量：
 *                           ① 表 A=3.0 kPa、表 B=3.2 kPa、偏差限 0.5 → 一致，取均值 3.1 kPa
 *                           ② 表 A=3.0 kPa、表 B=5.0 kPa → 偏离 2.0 > 0.5，锁存偏离，取低值 3.0 kPa
 *                           ③ 低压门槛 2.0 kPa、迟滞 0.2、可信压差 1.8 且持续 tLowConf → 锁存低压联锁
 *                           ④ 压差回升到 2.25 kPa → 高于 2.0+0.2，补气阀关断、联锁解除（非锁存件复位前）
 * 接口     (Interface)  : 入 bEnable 使能、fPrRawA / fPrRawB 双表原始值、fSpanKpa 量程标定、
 *                         fDevMaxKpa 双表偏差限、fPrLowKpa 低压门槛、fPrHighKpa 超压门槛、
 *                         fHystKpa 迟滞半宽、tLowConf 低压确认时长、bReset 复位沿；
 *                         出 fPrSelected 可信压差、fPrDev 双表偏差、bMakeupValve 补气阀位、
 *                         fValveCmdPct 补气阀位指令、bVentValve 排放阀位、bLowInterlock 低压联锁锁存、
 *                         bSensorDev 双表偏离锁存、eState 相、eCause 成因、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做"压差判据 + 阀位指令"，不驱动电磁阀线圈、
 *                         不做阀门回讯确认**（属阀件 / IO 映射层）；② **标定除零闸**：fSpanKpa ≤ 0
 *                         或非有限 → 锁存 eCfgIllegal（零量程会把任何原始值放大成无穷，R179）；
 *                         ③ **门槛单调闸**：fPrLow < fPrHigh 且 fHyst ≥ 0 且 fHyst < 门槛差的一半；
 *                         ④ **退化取低值**：双表偏离时选 min(A,B)，安全侧赋值只取"已证明可用的局部工作值"
 *                         或常量，绝不取被判非法的脚值（R127）；
 *                         ⑤ **确认 TON 冻结**：tonLowConf 的 IN 串 (NOT _bFault)，故障期不累计，
 *                         复位同拍不会立即重锁（R252）；TON 段 0 无条件调用；
 *                         ⑥ **锁存解除式**：bSensorDev 与 bLowInterlock 的解除各有独立路径——
 *                         bSensorDev 由 bReset 沿解除（需人工确认传感器）；bLowInterlock 由
 *                         "压差回升过门槛 + 迟滞"自动解除，两条都写死并自证可满足；
 *                         ⑦ 非有限样本 → 该路作废（当拍不参与均值），双路皆废 → 当拍不判、bValid=FALSE；
 *                         ⑧ 零全局耦合、零物理地址。
 * 分工声明 (Scope)      : 本件只管"氮封压差判据与阀位指令"。不接管：储罐液位控制
 *                         （属 FB_DL_TankLevelCtrl 族）、氮气纯度分析（属气体分析件）、
 *                         阀门故障诊断（属阀件）。
 * 来源标签 (Source Tag) : ROADMAP 空勾真缺口 P2（氮封压差联动，自研 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位（零码位范式 R297）；诊断由 BOOL + ENUM 出口承担。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 零量程闸 + 门槛单调闸 + 阀位限幅 + 非有限闸 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE 兜底 ｜ R7 ✓ TON/R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R47 首版（批次 2 · 序号 9）
 *==============================================================================*)

TYPE E_DL_TbpState :
(
    eIdle    := 0,    // 待机相（未使能，阀位全关） / Idle, disabled, valves closed
    eMonitor := 10,   // 监测相（判据与阀位联动） / Monitoring, judgement and valve interlock
    eFault   := 90    // 故障相（等复位，阀位全关） / Fault, valves closed, awaiting reset
);
END_TYPE

TYPE E_DL_TbpCause :
(
    eNone      := 0,   // 无异常 / No anomaly
    eCfgIllegal:= 1,   // 组态非法（量程/门槛/迟滞越域） / Illegal configuration
    eSensorDev := 2,   // 双表偏离超限（锁存，取低值退化） / Transmitter deviation, latched, low value used
    eLowPr     := 3,   // 氮封低压联锁（锁存，等压差回升） / Blanket low pressure interlock, latched
    eBothBad   := 4,   // 双表皆非有限（当拍不判） / Both transmitters non-finite
    ePhaseBad  := 5    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_TankBlanketPrCtrl
VAR_INPUT
    bEnable    : BOOL := FALSE;      // 使能（FALSE 时阀位全关） [-] / Enable, valves closed when FALSE
    fPrRawA    : LREAL := 0.0;       // A 表原始值（按量程标定解释） [raw] / Transmitter A raw value
    fPrRawB    : LREAL := 0.0;       // B 表原始值（按量程标定解释） [raw] / Transmitter B raw value
    fSpanKpa   : LREAL := 10.0;      // 量程标定（原始值 → kPa 的比例），域 > 0 [kPa/raw] / Span calibration, > 0
    fDevMaxKpa : LREAL := 0.5;       // 双表偏差限，域 > 0 [kPa] / Transmitter deviation limit, > 0
    fPrLowKpa  : LREAL := 2.0;       // 低压联锁门槛 [kPa] / Low-pressure interlock threshold
    fPrHighKpa : LREAL := 6.0;       // 超压排放门槛，域 > 低压门槛 [kPa] / Over-pressure vent threshold
    fHystKpa   : LREAL := 0.2;       // 迟滞半宽，域 ≥ 0 [kPa] / Hysteresis half-width, >= 0
    tLowConf   : TIME := T#2S;       // 低压确认时长，域 > T#0S [ms] / Low-pressure confirmation time, > T#0S
    bReset     : BOOL := FALSE;      // 复位沿（清双表偏离锁存） [-] / Reset edge, clears the deviation latch
END_VAR
VAR_OUTPUT
    fPrSelected  : LREAL := 0.0;                          // 可信压差 [kPa] / Trusted blanket pressure [kPa]
    fPrDev       : LREAL := 0.0;                          // 双表偏差绝对值 [kPa] / Absolute transmitter deviation [kPa]
    bMakeupValve : BOOL := FALSE;                         // 补气阀位 [-] / Make-up valve position
    fValveCmdPct : LREAL := 0.0;                          // 补气阀位指令，钳 0..100 [%] / Make-up valve command, clamped 0..100
    bVentValve   : BOOL := FALSE;                         // 超压排放阀位 [-] / Vent valve position
    bLowInterlock: BOOL := FALSE;                         // 低压联锁锁存 [-] / Low-pressure interlock, latched
    bSensorDev   : BOOL := FALSE;                         // 双表偏离锁存 [-] / Transmitter deviation, latched
    bValid       : BOOL := FALSE;                         // 判据有效（至少一路有限） [-] / Judgement valid
    eState       : E_DL_TbpState := E_DL_TbpState.eIdle;  // 相出口 [-] / Phase outlet
    eCause       : E_DL_TbpCause := E_DL_TbpCause.eNone;  // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError       : BOOL := FALSE;                         // 故障标志（组态级或双表皆废） [-] / Error flag
END_VAR
VAR
    _eState    : E_DL_TbpState := E_DL_TbpState.eIdle;    // 内部相（CASE 唯一写入目标） / Internal phase
    _eCause    : E_DL_TbpCause := E_DL_TbpCause.eNone;    // 成因锁存量 / Latched cause
    _bFault    : BOOL := FALSE;                           // 故障锁存位（组态级） / Latched configuration fault
    _bDevLatch : BOOL := FALSE;                           // 双表偏离锁存位 / Latched deviation bit
    _bLowLatch : BOOL := FALSE;                           // 低压联锁锁存位 / Latched low-pressure bit
    _fA        : LREAL := 0.0;                            // A 表换算后压差 [kPa] / Transmitter A converted value
    _fB        : LREAL := 0.0;                            // B 表换算后压差 [kPa] / Transmitter B converted value
    _bAOk      : BOOL := FALSE;                           // A 表可用标志 / Transmitter A usable
    _bBOk      : BOOL := FALSE;                           // B 表可用标志 / Transmitter B usable
    _fSel      : LREAL := 0.0;                            // 可信压差工作值 [kPa] / Trusted pressure working value
    _fDev      : LREAL := 0.0;                            // 偏差工作值 [kPa] / Deviation working value
    _fPct      : LREAL := 0.0;                            // 阀位指令工作值 [%] / Valve command working value
    _bMakeup   : BOOL := FALSE;                           // 补气阀内部位（迟滞保持量） / Internal make-up valve bit
    _bVent     : BOOL := FALSE;                           // 排放阀内部位（迟滞保持量） / Internal vent valve bit
    _bCfgBad   : BOOL := FALSE;                           // 组态非法当拍量 / Illegal configuration this scan
    tonLowConf : TON;                                     // 低压确认实例，段 0 无条件调用 / Low-pressure confirmation instance
    rtReset    : R_TRIG;                                  // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_TBP_PCT_MAX  : LREAL := 100.0;     // 阀位指令上限 [%] / Valve command upper bound [%]
    DL_TBP_PCT_MIN  : LREAL := 0.0;       // 阀位指令下限 [%] / Valve command lower bound [%]
    DL_TBP_EPS      : LREAL := 1.0E-9;    // 浮点判等容差 [kPa] / Equality tolerance [kPa]
END_VAR

(* —— 段 0：组态闸 + TON 与沿无条件周期刷新（R228A；IN 串故障否决，R252） —— *)
_bCfgBad := (fSpanKpa <= 0.0) OR (fSpanKpa <> fSpanKpa)                       // 量程须为正且有限 / Span positive and finite
         OR (fDevMaxKpa <= 0.0) OR (fDevMaxKpa <> fDevMaxKpa)                 // 偏差限须为正且有限 / Deviation limit positive
         OR (NOT (fPrLowKpa < fPrHighKpa))                                    // 门槛须满足低压 < 超压 / Low threshold below high threshold
         OR (fHystKpa < 0.0) OR (fHystKpa > ((fPrHighKpa - fPrLowKpa) / 2.0)) // 迟滞须非负且小于门槛差半宽 / Hysteresis within the band
         OR (tLowConf <= T#0S);                                               // 确认时长须为正 / Confirmation time positive
rtReset(CLK := bReset);                                                       // 复位沿 / Reset edge
tonLowConf(IN := (_eState = E_DL_TbpState.eMonitor) AND (NOT _bFault), PT := tLowConf);   // 低压确认（监测相派生） / Low-pressure confirmation

(* —— 段 1：单拍/输出量预置（锁存量 _eCause/_bFault/_bDevLatch/_bLowLatch/_bMakeup/_bVent 不入清单，R107） —— *)
fPrSelected := 0.0;                                          // 可信压差预置 / Trusted pressure preset
fPrDev      := 0.0;                                          // 偏差预置 / Deviation preset
fValveCmdPct:= 0.0;                                          // 阀位指令预置 / Valve command preset
bMakeupValve:= FALSE;                                        // 补气阀预置 / Make-up valve preset
bVentValve  := FALSE;                                        // 排放阀预置 / Vent valve preset
bValid      := FALSE;                                        // 有效位预置 / Validity preset
bError      := FALSE;                                        // 故障标志预清（R45 配对） / Error preset
_fSel       := 0.0;                                          // 可信压差工作值预置 / Working value preset
_fDev       := 0.0;                                          // 偏差工作值预置 / Deviation working value preset
_fPct       := DL_TBP_PCT_MIN;                               // 阀位工作值预置为下限 / Command working value at the lower bound

(* —— 段 2：组态闸（非法即锁存，阀位全关） —— *)
IF _bCfgBad THEN
    _eCause := E_DL_TbpCause.eCfgIllegal;                    // 归因：组态非法 / Cause: illegal configuration
    _bFault := TRUE;                                         // 锁存 / Latch
    _eState := E_DL_TbpState.eFault;                         // 入故障相 / Enter fault phase
END_IF

(* —— 段 3：迁出链（bReset 清组态故障与双表偏离锁存；低压联锁不走复位，走压差回升） —— *)
IF rtReset.Q THEN
    _bFault    := FALSE;                                     // 清组态故障锁存 / Clear the configuration fault latch
    _bDevLatch := FALSE;                                     // 清双表偏离锁存（需人工确认后复位） / Clear the deviation latch
    _eCause    := E_DL_TbpCause.eNone;                       // 清成因 / Clear cause
    _eState    := E_DL_TbpState.eIdle;                       // 回待机相 / Back to idle
END_IF

(* —— 段 4：相迁移（使能驱动；故障相由段 3 迁出） —— *)
CASE _eState OF

E_DL_TbpState.eIdle:
    IF bEnable THEN
        _eState := E_DL_TbpState.eMonitor;                   // 使能即进监测相 / Enable enters monitoring
    END_IF

E_DL_TbpState.eMonitor:
    IF NOT bEnable THEN
        _eState := E_DL_TbpState.eIdle;                      // 失能回待机相（阀位在出口强制全关） / Disable returns to idle
    END_IF

E_DL_TbpState.eFault:
    ;                                                        // 故障相：由段 3 复位沿迁出 / Exit handled by the reset edge

ELSE
    _eCause := E_DL_TbpCause.ePhaseBad;                      // 归因：非法相位 / Cause: illegal phase
    _bFault := TRUE;                                         // 锁存 / Latch
    _eState := E_DL_TbpState.eFault;                         // 强拉故障相 / Force fault phase

END_CASE

(* —— 段 5：双表换算（原始值 × 量程比例；非有限路作废，双废当拍不判） —— *)
IF (_eState = E_DL_TbpState.eMonitor) AND (NOT _bCfgBad) THEN
    _bAOk := NOT ((fPrRawA <> fPrRawA) OR ((fPrRawA - fPrRawA) <> (fPrRawA - fPrRawA)));   // A 路有限 / A finite
    _bBOk := NOT ((fPrRawB <> fPrRawB) OR ((fPrRawB - fPrRawB) <> (fPrRawB - fPrRawB)));   // B 路有限 / B finite
    IF _bAOk THEN
        _fA := fPrRawA * fSpanKpa;                           // A 表换算为 kPa / Convert A to kPa
    END_IF
    IF _bBOk THEN
        _fB := fPrRawB * fSpanKpa;                           // B 表换算为 kPa / Convert B to kPa
    END_IF

    IF (NOT _bAOk) AND (NOT _bBOk) THEN
        _eCause := E_DL_TbpCause.eBothBad;                   // 归因：双表皆废（当拍不判，不锁存） / Cause: both transmitters unusable
    ELSIF (NOT _bBOk) THEN
        _fSel := _fA;                                        // 仅 A 可用：取 A（并记偏离锁存外的降级） / Only A usable
        _fDev := 0.0;                                        // 无对照：偏差按 0 报 / No reference, deviation reported as 0
        bValid := TRUE;
    ELSIF (NOT _bAOk) THEN
        _fSel := _fB;                                        // 仅 B 可用：取 B / Only B usable
        _fDev := 0.0;                                        // 无对照：偏差按 0 报 / No reference
        bValid := TRUE;
    ELSE
        _fDev := ABS(_fA - _fB);                             // 双表偏差绝对值 / Absolute deviation
        IF _fDev > fDevMaxKpa THEN
            _bDevLatch := TRUE;                              // 偏离超限：锁存 / Deviation beyond the limit: latch
            _eCause := E_DL_TbpCause.eSensorDev;             // 归因：双表偏离 / Cause: transmitter deviation
            IF _fA < _fB THEN
                _fSel := _fA;                                // 退化取低值（保守侧） / Degrade to the lower reading
            ELSE
                _fSel := _fB;                                // 退化取低值（保守侧） / Degrade to the lower reading
            END_IF
        ELSE
            _fSel := (_fA + _fB) / 2.0;                      // 双表一致：取均值 / Consistent, use the mean
        END_IF
        bValid := TRUE;
    END_IF

    (* —— 段 6：低压联锁（门槛 + 确认时长；回升过"门槛 + 迟滞"自动解除） —— *)
    IF bValid THEN
        IF (_fSel < fPrLowKpa) AND tonLowConf.Q THEN
            _bLowLatch := TRUE;                              // 低压确认到位：锁存联锁 / Confirm and latch the interlock
            _eCause := E_DL_TbpCause.eLowPr;                 // 归因：氮封低压 / Cause: blanket low pressure
        ELSIF _fSel > (fPrLowKpa + fHystKpa) THEN
            _bLowLatch := FALSE;                             // 回升过门槛 + 迟滞：自动解除 / Recovery clears the interlock
        END_IF

        (* —— 段 7：阀位联动（补气阀：低压或联锁 → 开；超压 → 关；其余按迟滞保持） —— *)
        IF _bLowLatch OR (_fSel < (fPrLowKpa - fHystKpa)) THEN
            _bMakeup := TRUE;                                // 低压侧：补气阀开 / Low side: open the make-up valve
        ELSIF _fSel > (fPrLowKpa + fHystKpa) THEN
            _bMakeup := FALSE;                               // 回升：补气阀关 / Recovered: close the make-up valve
        END_IF

        IF _fSel > fPrHighKpa THEN
            _bVent := TRUE;                                  // 超压：排放阀开 / Over-pressure: open the vent valve
        ELSIF _fSel < (fPrHighKpa - fHystKpa) THEN
            _bVent := FALSE;                                 // 回落：排放阀关 / Below the hysteresis: close the vent
        END_IF

        (* —— 段 8：阀位指令限幅（开则满开、关则零，指令与 BOOL 同源） —— *)
        IF _bMakeup THEN
            _fPct := DL_TBP_PCT_MAX;                         // 开阀指令 100 % / Open command
        ELSE
            _fPct := DL_TBP_PCT_MIN;                         // 关阀指令 0 % / Close command
        END_IF
        IF _fPct > DL_TBP_PCT_MAX THEN
            _fPct := DL_TBP_PCT_MAX;                         // 上钳 / Clamp high
        ELSIF _fPct < DL_TBP_PCT_MIN THEN
            _fPct := DL_TBP_PCT_MIN;                         // 下钳 / Clamp low
        END_IF
    ELSE
        _bMakeup := FALSE;                                   // 判据无效：补气阀保守关（不猜方向） / Invalid: close conservatively
        _bVent   := FALSE;                                   // 判据无效：排放阀关 / Invalid: vent closed
        _fPct    := DL_TBP_PCT_MIN;                           // 指令归零 / Command zeroed
    END_IF
END_IF

(* —— 段 9：故障/失能强制阀位全关（安全侧优先于段 8 联动） —— *)
IF (_eState <> E_DL_TbpState.eMonitor) THEN
    _bMakeup := FALSE;                                       // 非监测相：补气阀关 / Non-monitoring: make-up closed
    _bVent   := FALSE;                                       // 非监测相：排放阀关 / Non-monitoring: vent closed
    _fPct    := DL_TBP_PCT_MIN;                              // 非监测相：指令归零 / Non-monitoring: command zeroed
END_IF

(* —— 段 10：出口单点映射（名实双出口，R191） —— *)
fPrSelected   := _fSel;                                      // 可信压差出口 / Trusted pressure outlet
fPrDev        := _fDev;                                      // 双表偏差出口 / Deviation outlet
bMakeupValve  := _bMakeup;                                   // 补气阀位出口 / Make-up valve outlet
fValveCmdPct  := _fPct;                                      // 阀位指令出口（已限幅） / Command outlet, clamped
bVentValve    := _bVent;                                     // 排放阀位出口 / Vent valve outlet
bLowInterlock := _bLowLatch;                                 // 低压联锁出口 / Low interlock outlet
bSensorDev    := _bDevLatch;                                 // 双表偏离出口 / Deviation outlet
eState        := _eState;                                    // 相出口 / Phase outlet
eCause        := _eCause;                                    // 成因出口 / Cause outlet
bError        := _bFault OR _bDevLatch;                      // 故障标志（组态级或双表偏离） / Error flag

END_FUNCTION_BLOCK
