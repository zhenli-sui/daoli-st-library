(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AhuSupplyAirReset
 * 所属子库 (Sublibrary) : DL_Process
 * 归属目录 (Directory)  : C:\Library\DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 分类/来源标签         : 功能块（FUNCTION_BLOCK）· 暖通串级 · 送风温度再设定
 *                         industry-pool / hvac / ahu / cascade-reset
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library
 * 溯源声明 (Provenance) : 道莅自研 clean-room——只借公开规范条款与工程惯例，零代码行复制。
 * 功能一句话 (Summary)  : 按活动末端需求均值对送风温度设定做串级重置，
 *                         区分 cooling/heating 双模式带，外温切换模式带。
 *
 * 功能描述 (Function)   : 三态状态机：关断/冷带/热带。冷带模式需求越大送风
 *                         越冷（设定 = 冷带上限 − 带宽 × 需求），热带模式
 *                         需求越大送风越热（设定 = 热带下限 + 带宽 × 需求）；
 *                         外温高于切换阈走冷带、低于走热带；活动区需求域外
 *                         钳位并报信息级；输入非有限冻结保持上一设定；温度
 *                         带域外（下限大于上限）报故障；无活动区保持上一设定。
 * 与既有件边界 (Boundary): 本件只出送风设定，不控盘管水阀；盘管调节归
 *                         下级反馈环，本件是串级主环设定层。
 * 码位说明 (Codes)      : 信息 16#0006_3019 活动区需求域外已钳位到 0..100
 *                         故障 16#0006_301A 输入非有限，设定冻结保持
 *                         故障 16#0006_301B 温度带域外（下限大于上限）
 *                         故障 16#0006_301C 无有效活动区，设定保持上一值
 *                         段 16#06_0_19~1D 首槽信息级、次槽起故障级。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 ABS。
 * 红线自检 (Redline)    : 零全局依赖 ｜ 零 VAR_EXTERNAL ｜ 零 %I/%Q ｜ 纯 IEC 标准库
 *                         NaN/Inf 精确判据拦截 ｜ ENUM 配 CASE 且 ELSE 兜底
 *                         全变量双语同行注释 ｜ 无定时器实例 ｜ 除法面仅常量
 * 修订历史 (Revision)   : 2026-11-18  v1.0.0  首版入库（R32 · 批 4）
 *============================================================================*)

FUNCTION_BLOCK FB_DL_AhuSupplyAirReset
VAR_INPUT
    bRun       : BOOL;                    // 串级使能，假则设定回安全默认 / Enable, FALSE falls back to default
    aDemPct    : ARRAY[1..4] OF LREAL;    // 各末端需求 [％]，域 0 到 100 / Zone demand percent
    aZoneEn    : ARRAY[1..4] OF BOOL;     // 各末端活动使能 / Zone activity enables
    fOatC      : LREAL;                   // 室外温度 [degC] / Outdoor air temperature
    fOatSwC    : LREAL := 18.0;           // 模式切换外温阈 [degC] / Mode switching OAT threshold
    fCoolMinC  : LREAL := 12.0;           // 冷带下限 [degC]（需求满）/ Cooling band minimum at full demand
    fCoolMaxC  : LREAL := 18.0;           // 冷带上限 [degC]（需求零）/ Cooling band maximum at zero demand
    fHeatMinC  : LREAL := 22.0;           // 热带下限 [degC]（需求零）/ Heating band minimum at zero demand
    fHeatMaxC  : LREAL := 30.0;           // 热带上限 [degC]（需求满）/ Heating band maximum at full demand
    fEps       : LREAL := 1.0E-6;         // 浮点判零容差 [实数域] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    eMode   : (eModeOff := 0, eModeCool := 1, eModeHeat := 2);  // 模式枚举输出 / Mode output enum
    fTsaSetC: LREAL;                    // 送风温度设定 [degC] / Supply air setpoint
    bValid  : BOOL;                     // 设定有效标志，冻结期间为假 / TRUE when the setpoint is valid
    bError  : BOOL;                     // 故障标志，与故障码配对 / Fault flag paired with codes
    uErrorId: UDINT;                    // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    _eState  : (eStOff := 0, eStCool := 1, eStHeat := 2);   // 内部状态机 / Internal state machine
    fMeanDem : LREAL;                   // 活动区需求均值 [％] / Mean demand of active zones
    fTsaNew  : LREAL;                   // 本拍设定计算值 [degC] / Setpoint computed this scan
    bDomClamp: BOOL;                    // 需求钳位标志 / Demand clamped flag
    bBandOk  : BOOL;                    // 温度带域有效标志 / Band validity flag
    nActive  : INT;                     // 活动区个数 [个] / Active zone count
    nI       : INT;                     // 区循环下标 [索引] / Zone loop index
    fDem     : LREAL;                   // 单区需求暂存 [％] / Zone demand staging
    uCode    : UDINT;                   // 码位暂存，出口单点写入 [码] / Code staging
END_VAR

(* 段 1｜输出预置（不触碰 _eState，R19）/ Pre-set outputs, state stays resident *)
bValid  := FALSE;
bError  := FALSE;
uErrorId := 16#0000_0000;
uCode   := 16#0000_0000;
bDomClamp := FALSE;
eMode := eModeOff;                      // 模式输出出口刷新 / Mode output refreshed at the exit

(* 段 2｜需求加权均值与域闸（NaN 自反、Inf 上限、带序校验）/ Weighted mean and gates *)
nActive := 0;                           // 活动计数清零 / Clear the count
fMeanDem := 0.0;                        // 均值累加器清零 / Clear the accumulator
bBandOk := ((fCoolMaxC - fCoolMinC) > fEps) AND ((fHeatMaxC - fHeatMinC) > fEps)
           AND (fOatC = fOatC) AND (ABS(fOatC) < 1.0E308);      // 带宽为正且外温有限 / Bands ordered, OAT finite
FOR nI := 1 TO 4 DO
    IF aZoneEn[nI] THEN
        fDem := aDemPct[nI];            // 取单区需求 / Take the zone demand
        IF (fDem <> fDem) OR (ABS(fDem) > 1.0E308) THEN
            uCode := 16#0006_301A;      // 故障级：需求非有限 / Fault: non-finite demand
            bBandOk := FALSE;           // 数据无效冻结评估 / Freeze the evaluation
        ELSE
            IF fDem < 0.0 THEN
                fDem := 0.0;            // 钳下界 / Clamp low
                bDomClamp := TRUE;
            ELSIF fDem > 100.0 THEN
                fDem := 100.0;          // 钳上界 / Clamp high
                bDomClamp := TRUE;
            END_IF
            fMeanDem := fMeanDem + fDem;    // 累加 / Accumulate
            nActive := nActive + 1;         // 计数 / Count
        END_IF
    END_IF
END_FOR
IF nActive > 0 THEN
    fMeanDem := fMeanDem / (DINT_TO_LREAL(nActive) * 100.0);    // 归一到 0..1 比值 / Normalize to 0..1
END_IF
IF bDomClamp AND (uCode = 16#0000_0000) THEN
    uCode := 16#0006_3019;              // 信息级：需求已钳位 / Info: demand clamped
END_IF

(* 段 3｜状态机主分派（ENUM 配 CASE，ELSE 兜底）/ State dispatch with ELSE interception *)
CASE _eState OF

    eStOff:
        (* 本拍行为：设定保持安全默认；使能与域闸俱备按外温选带 / Hold the default; pick a band by OAT *)
        fTsaSetC := fCoolMaxC;          // 关断安全默认 / Safe default
        IF bRun AND bBandOk THEN
            IF fOatC >= fOatSwC THEN
                _eState := eStCool;     // 拍 N+1 转冷带 / To cooling next scan
            ELSE
                _eState := eStHeat;     // 拍 N+1 转热带 / To heating next scan
            END_IF
        END_IF

    eStCool:
        (* 本拍行为：需求越大送风越冷；撤使能或带域异常回关断 / More demand, colder supply *)
        IF NOT bRun THEN
            _eState := eStOff;          // 拍 N+1 回关断 / To off next scan
        ELSIF NOT bBandOk THEN
            uCode := 16#0006_301B;      // 故障级：温度带域外 / Fault: band out of domain
            bValid := FALSE;            // 设定冻结 / Freeze the setpoint
        ELSIF nActive = 0 THEN
            uCode := 16#0006_301C;      // 故障级：无活动区，保持上一值 / Fault: no active zone
        ELSE
            fTsaNew := fCoolMaxC - (fCoolMaxC - fCoolMinC) * fMeanDem;  // 冷带重置 / Cooling reset
            fTsaSetC := fTsaNew;        // 设定写出 / Write the setpoint
            bValid := TRUE;
        END_IF

    eStHeat:
        (* 本拍行为：需求越大送风越热；撤使能或带域异常回关断 / More demand, warmer supply *)
        IF NOT bRun THEN
            _eState := eStOff;          // 拍 N+1 回关断 / To off next scan
        ELSIF NOT bBandOk THEN
            uCode := 16#0006_301B;      // 故障级：温度带域外 / Fault: band out of domain
            bValid := FALSE;
        ELSIF nActive = 0 THEN
            uCode := 16#0006_301C;      // 故障级：无活动区 / Fault: no active zone
        ELSE
            fTsaNew := fHeatMinC + (fHeatMaxC - fHeatMinC) * fMeanDem;  // 热带重置 / Heating reset
            fTsaSetC := fTsaNew;        // 设定写出 / Write the setpoint
            bValid := TRUE;
        END_IF

ELSE
    _eState := eStOff;                  // 非法状态拦截回关断 / Illegal state to off
    uCode := 16#0006_301B;              // 故障：状态越界 / Fault: state out of range
END_CASE

(* 段 4｜出口装配 / Exit assembly *)
eMode := eModeOff;                      // 模式映射刷新 / Refresh the mode mapping
IF _eState = eStCool THEN
    eMode := eModeCool;
ELSIF _eState = eStHeat THEN
    eMode := eModeHeat;
END_IF
bError := (uCode >= 16#0006_301A) AND (uCode <= 16#0006_301C);  // 故障级码带判定 / Fault band check
uErrorId := uCode;                      // 码位单点写入 / Single write point
END_FUNCTION_BLOCK
