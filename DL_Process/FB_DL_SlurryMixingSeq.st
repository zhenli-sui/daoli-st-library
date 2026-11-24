(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SlurryMixingSeq
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 浆料批次四相顺控：eIdle → eFill（加料，料位或重量达窗）→ eDisperse
 *                         （高速分散：转速达窗 + 分散时长 tDisperse）→ eDeair（真空脱泡：真空度
 *                         达窗 + 脱泡时长 tDeair）→ eDischarge（出料：料位到下限或撤启动）→ eDone。
 *                         相内监视：温升速率超 fTempRiseMax 立即故障（浆料过热会凝胶，属安全侧
 *                         异常，按 R146 立即终止）；分散相时长届满时转速仍在容差带外 → 失速故障。
 *                         每相独立超时（tFillMax / tDisperseMax / tDeairMax / tDischargeMax）。
 * 撤启动语义 (Abort)    : **bStart 落沿在任意执行相 → 直接进 eDischarge 安全收料**，不得停在
 *                         分散相（分散中滞留会让浆料在高速剪切下持续升温）。这是 R98 双出口
 *                         范式在本件的落地：执行相均有「工艺达成」与「撤启动」两条出口。
 * 分工声明 (Scope)      : 与 `FB_DL_SlurryStirrerCtrl`（Device 子库，单机搅拌器驱动与转速
 *                         闭环）分工 —— 本件是**批次相序编排**，只发相级命令位，不直接驱动
 *                         电机、不做转速闭环。
 * 接口     (Interface)  : 输入 bStart 启动电平、料位/重量/转速/真空/温升与各自目标与容差、
 *                         四个工艺时长与四个相超时、bReset 复位；输出 eState 相位、eCause 归因、
 *                         四个相级命令位、bCycleDone 完成标志、bError / nErrId。
 * 边界     (Boundary)   : ① 组态闸：任一容差 <= 0.0、任一时长 <= T#0S、fLevelHiPct <= fLevelLoPct、
 *                         fWeightTgtKg <= 0.0、fVacTgtKpa <= 0.0、fTempRiseMax <= 0.0 或任一浮点
 *                         引脚 NaN → 故障锁存（每个参与判据的引脚都在闸内，R151）；
 *                         ② **4 枚 TON（相计时）+ 1 枚 R_TRIG 全部段 0 无条件刷新**，每个实例的
 *                         IN 由对应相位派生（R228A），离开该相 IN 落假 → Q 落假、ET 归零
 *                         （R228B 跨相复位语义成立）；本件是本轮 TON 密度最高件，逐实例已核：
 *                         tonFill↔eFill、tonDisperse↔eDisperse、tonDeair↔eDeair、
 *                         tonDischarge↔eDischarge，四者对相位一一绑定，无跨相复用；
 *                         ③ 相时长的「工艺时间」与「相超时」共用同一实例：PT 绑该相超时上限，
 *                         工艺达成判据读 ET（ET >= 工艺时长），结构上不可能出现「两个计时器
 *                         各说各话」；④ 故障相迁出唯一路径 = bReset 上升沿；
 *                         ⑤ 零全局耦合（无 GVL / 无物理地址）。
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 ∧ 已撤启动（NOT bStart，当拍量，R240 范式）。
 *                         自证可满足（终审两式 1）：四枚 TON 的 IN 挂相位，故障相内 IN 恒假 →
 *                         Q 恒假；bStart 为外部电平，操作员松开即达，无恒假因子。
 * 码表     (Codes)      : 16#0005_03A6 故障级：浆料混合顺控故障总码（组态非法 / 加料超时 /
 *                         转速失速 / 真空不足 / 温升超限 / 出料超时 / 非法相位），锁存至 bReset
 *                         上升沿，归因由 eCause 承载（R190 单件单总码，每个成因均有独立赋值点）；
 *                         16#0005_04CE 信息级：批次循环完成（进 eDone 单拍）。
 *                         加码反证（R90）：完成时 bCycleDone 由相位派生且四命令位全落，而「长时间
 *                         停在 eDone」与之同值，出口组合无法区分「刚完成一个批次」与「完成态驻留」，
 *                         故立一码记录每个批次的完成沿。
 *                         码段说明：0005 段故障子带 03xx / 信息子带 04xx，本件取 03A6 / 04CE
 *                         （源码实扫该两槽为空，续接同子带已用最大值，未回填碎片孔洞）。
 * 开源溯源 (Origin)     : 道莅自研 clean-room（参考锂电前段浆料制备工艺与公开参数域，
 *                         零代码行复制；自研行业池）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R45 首版（批次 4 · 序号 18）
 *==============================================================================*)

TYPE E_DL_SmxState :
(
    eIdle      := 0,     // 待启动 / Idle, awaiting start
    eFill      := 10,    // 加料相 / Filling
    eDisperse  := 20,    // 高速分散相 / High-speed dispersion
    eDeair     := 30,    // 真空脱泡相 / Vacuum de-airing
    eDischarge := 40,    // 出料相（含撤启动安全收料） / Discharging, also the safe abort target
    eDone      := 50,    // 批次完成 / Batch done
    eFault     := 90     // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_SmxCause :
(
    eNone         := 0,  // 无故障成因 / No cause
    eCfgIllegal   := 1,  // 组态非法 / Illegal configuration
    eFillTmo      := 2,  // 加料超时 / Fill timeout
    eSpeedLoss    := 3,  // 转速失速（时长届满仍在容差带外） / Speed out of tolerance at time-up
    eVacLow       := 4,  // 真空不足 / Vacuum insufficient
    eTempRise     := 5,  // 温升速率超限 / Temperature rise rate over limit
    eDischargeTmo := 6,  // 出料超时 / Discharge timeout
    ePhaseBad     := 7   // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_SlurryMixingSeq
VAR_INPUT
    bStart        : BOOL := FALSE;        // 批次启动电平（落沿触发安全收料） [-] / Batch start level, falling edge triggers safe discharge
    fLevelPct     : REAL := 0.0;          // 料位 [%] / Tank level [%]
    fLevelLoPct   : REAL := 5.0;          // 料位下限（出料终点），域 < fLevelHiPct [%] / Level low limit [%]
    fLevelHiPct   : REAL := 80.0;         // 料位上限（加料终点），域 > fLevelLoPct [%] / Level high limit [%]
    fWeightKg     : REAL := 0.0;          // 批次重量 [kg] / Batch weight [kg]
    fWeightTgtKg  : REAL := 500.0;        // 目标重量，域 > 0.0 [kg] / Target weight, domain > 0.0 [kg]
    fSpeedRpm     : REAL := 0.0;          // 实测转速 [rpm] / Measured speed [rpm]
    fSpeedTgtRpm  : REAL := 1200.0;       // 分散目标转速 [rpm] / Dispersion target speed [rpm]
    fSpeedTol     : REAL := 50.0;         // 转速容差带，域 > 0.0 [rpm] / Speed tolerance, domain > 0.0 [rpm]
    fVacKpa       : REAL := 0.0;          // 实测真空度（幅值） [kPa] / Measured vacuum magnitude [kPa]
    fVacTgtKpa    : REAL := 80.0;         // 真空目标（幅值），域 > 0.0 [kPa] / Vacuum target magnitude, domain > 0.0 [kPa]
    fTempRiseCpm  : REAL := 0.0;          // 温升速率 [°C/min] / Temperature rise rate [degC/min]
    fTempRiseMax  : REAL := 2.0;          // 温升速率上限，域 > 0.0 [°C/min] / Rise-rate limit, domain > 0.0 [degC/min]
    tFill         : TIME := T#30S;        // 加料最短时长（防料位抖动误判），域 > T#0S [ms] / Fill minimum duration [ms]
    tFillMax      : TIME := T#10M;        // 加料相超时，域 > tFill [ms] / Fill phase timeout [ms]
    tDisperse     : TIME := T#20M;        // 分散工艺时长，域 > T#0S [ms] / Dispersion process time [ms]
    tDisperseMax  : TIME := T#25M;        // 分散相超时，域 > tDisperse [ms] / Dispersion phase timeout [ms]
    tDeair        : TIME := T#15M;        // 脱泡工艺时长，域 > T#0S [ms] / De-airing process time [ms]
    tDeairMax     : TIME := T#20M;        // 脱泡相超时，域 > tDeair [ms] / De-airing phase timeout [ms]
    tDischarge    : TIME := T#30S;        // 出料最短时长，域 > T#0S [ms] / Discharge minimum duration [ms]
    tDischargeMax : TIME := T#5M;         // 出料相超时，域 > tDischarge [ms] / Discharge phase timeout [ms]
    bReset        : BOOL := FALSE;        // 复位命令，上升沿清故障 [-] / Reset command, rising edge clears fault
END_VAR
VAR_OUTPUT
    eState            : E_DL_SmxState;    // 状态出口，段 6 单点映射 / State outlet
    eCause            : E_DL_SmxCause;    // 故障成因出口（R190 归因唯一） / Fault cause outlet
    bInletValveCmd    : BOOL;             // 进料阀命令（仅加料相） [-] / Inlet valve command, fill phase only
    bStirrerFastCmd   : BOOL;             // 高速搅拌命令（分散相） [-] / High-speed stirrer command, disperse phase
    bVacPumpCmd       : BOOL;             // 真空泵命令（脱泡相） [-] / Vacuum pump command, de-air phase
    bDischargeValveCmd: BOOL;             // 出料阀命令（出料相） [-] / Discharge valve command, discharge phase
    bCycleDone        : BOOL;             // 批次完成标志 [-] / Batch done flag
    bError            : BOOL;             // 故障锁存标志 [-] / Fault latch flag
    nErrId            : UDINT;            // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    _eState       : E_DL_SmxState := E_DL_SmxState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause       : E_DL_SmxCause := E_DL_SmxCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    tonFill       : TON;                  // 加料相计时（PT = 相超时），段 0 无条件调用 / Fill phase timer
    tonDisperse   : TON;                  // 分散相计时（PT = 相超时），段 0 无条件调用 / Dispersion phase timer
    tonDeair      : TON;                  // 脱泡相计时（PT = 相超时），段 0 无条件调用 / De-air phase timer
    tonDischarge  : TON;                  // 出料相计时（PT = 相超时），段 0 无条件调用 / Discharge phase timer
    rtReset       : R_TRIG;               // 复位沿实例，段 0 无条件调用 / Reset edge
    _bSpeedInTol  : BOOL;                 // 转速在容差带当拍量 [-] / Speed inside tolerance
    _bVacInTol    : BOOL;                 // 真空达窗当拍量 [-] / Vacuum reached
    _bFillReached : BOOL;                 // 加料达窗当拍量 [-] / Fill reached
    _bDischDone   : BOOL;                 // 出料完成当拍量 [-] / Discharge finished
    _bNonFin      : BOOL;                 // 输入非有限当拍量 [-] / Non-finite input this scan
    _bCfgBad      : BOOL;                 // 组态非法当拍量 [-] / Illegal configuration
    _bFault       : BOOL;                 // 故障锁存位（锁存量） / Latched fault bit
    _uFault       : UDINT;                // 故障码锁存（锁存量） / Latched fault code
    _uInfo        : UDINT;                // 信息码，每拍重算 / Info code, recomputed each scan
END_VAR
VAR CONSTANT
    DL_SPEED_EPS : REAL := 1.0E-3;        // 判据辅助容差（防阈值给出极小值时的边界抖动） [无量纲] / Criterion epsilon [dimensionless]
END_VAR

(* —— 段 0：当拍判据派生 + 4 枚 TON 与沿实例无条件周期刷新（逐实例绑定相位） —— *)
_bNonFin := (fLevelPct <> fLevelPct) OR (fWeightKg <> fWeightKg) OR (fSpeedRpm <> fSpeedRpm)      // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive tests
         OR (fVacKpa <> fVacKpa) OR (fTempRiseCpm <> fTempRiseCpm);                                // 真空与温升 NaN 判 / Vacuum and rise-rate NaN tests
_bSpeedInTol  := ABS(fSpeedRpm - fSpeedTgtRpm) <= (fSpeedTol + DL_SPEED_EPS);                      // 转速容差判据 / Speed tolerance verdict
_bVacInTol    := fVacKpa >= (fVacTgtKpa - DL_SPEED_EPS);                                            // 真空达窗判据 / Vacuum reached verdict
_bFillReached := (fLevelPct >= (fLevelHiPct - DL_SPEED_EPS)) OR (fWeightKg >= (fWeightTgtKg - DL_SPEED_EPS));   // 料位或重量达窗 / Level or weight reached
_bDischDone   := fLevelPct <= (fLevelLoPct + DL_SPEED_EPS);                                         // 料位到下限 / Level reached low limit
_bCfgBad := (fSpeedTol <= 0.0) OR (fTempRiseMax <= 0.0) OR (fLevelHiPct <= fLevelLoPct)             // 容差与料位几何闸 / Tolerance and level geometry gates
            OR (fWeightTgtKg <= 0.0) OR (fVacTgtKpa <= 0.0)                                         // 重量与真空目标正域闸 / Weight and vacuum gates
            OR (tFill <= T#0S) OR (tFillMax <= tFill) OR (tDisperse <= T#0S) OR (tDisperseMax <= tDisperse)   // 时间正域与配比闸 / Time gates and ratio constraints
            OR (tDeair <= T#0S) OR (tDeairMax <= tDeair)                                            // 脱泡时间配比闸 / De-air time gates
            OR (tDischarge <= T#0S) OR (tDischargeMax <= tDischarge);                               // 出料时间配比闸 / Discharge time gates
rtReset(CLK := bReset);                                                                             // 复位沿，每拍必调（R228A） / Reset edge
tonFill(IN := (_eState = E_DL_SmxState.eFill), PT := tFillMax);                                     // 加料相计时（IN 绑相位） / Fill timer, phase-bound
tonDisperse(IN := (_eState = E_DL_SmxState.eDisperse), PT := tDisperseMax);                         // 分散相计时（IN 绑相位） / Dispersion timer, phase-bound
tonDeair(IN := (_eState = E_DL_SmxState.eDeair), PT := tDeairMax);                                  // 脱泡相计时（IN 绑相位） / De-air timer, phase-bound
tonDischarge(IN := (_eState = E_DL_SmxState.eDischarge), PT := tDischargeMax);                      // 出料相计时（IN 绑相位） / Discharge timer, phase-bound

(* —— 段 1：单拍量预清零（锁存量不入清单，R107） —— *)
_uInfo   := 16#0000_0000;          // 信息码每拍重算 / Info recomputed every scan
nErrId   := 16#0000_0000;          // 事件码缺省无事件 / Event code default none
bError   := FALSE;                 // 故障标志每拍预清，故障分支同拍置位（R45 配对） / Flag preset

(* —— 段 2：复位沿 + 组态域闸 + 非有限闸 —— *)
IF rtReset.Q THEN                                                        // 当拍复位沿 / current-scan reset edge
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_SmxCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
    IF _eState = E_DL_SmxState.eFault THEN
        _eState := E_DL_SmxState.eIdle;                                  // 故障相迁出唯一路径 / Sole exit from fault phase
    END_IF
END_IF
IF _bCfgBad THEN                                                         // 组态域闸 / Configuration gate
    _uFault := 16#0005_03A6;                                             // 故障级：浆料混合顺控故障总码 / Fault-level: slurry sequence fault code
    _bFault := TRUE;
    bError  := TRUE;                                                     // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_SmxCause.eCfgIllegal;                                // 归因：组态非法 / Cause: illegal configuration
END_IF
IF (NOT _bFault) AND _bNonFin THEN                                       // 输入非有限（归入组态非法归因） / Non-finite input, mapped to config cause
    _uFault := 16#0005_03A6;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_SmxCause.eCfgIllegal;                                // 归因：组态非法（含非有限输入） / Cause: illegal configuration including non-finite
END_IF

(* —— 段 3：温升速率监视（安全侧异常，立即终止，R146） —— *)
IF (NOT _bFault) AND (fTempRiseCpm > fTempRiseMax) THEN
    _uFault := 16#0005_03A6;                                             // 故障级：温升超限 / Fault-level: rise rate over limit
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_SmxCause.eTempRise;                                  // 归因：温升超限 / Cause: temperature rise
END_IF

(* —— 段 4：相超时与相内判据（各成因独立赋值点，R190） —— *)
IF (NOT _bFault) AND tonFill.Q THEN                                      // 加料超时 / Fill timeout
    _uFault := 16#0005_03A6;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_SmxCause.eFillTmo;                                   // 归因：加料超时 / Cause: fill timeout
END_IF
IF (NOT _bFault) AND tonDisperse.Q THEN                                  // 分散相时长届满仍失速 / Dispersion time-up with speed out of tolerance
    _uFault := 16#0005_03A6;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_SmxCause.eSpeedLoss;                                 // 归因：转速失速 / Cause: speed loss
END_IF
IF (NOT _bFault) AND tonDeair.Q THEN                                     // 脱泡相时长届满真空仍不足 / De-air time-up with vacuum short
    _uFault := 16#0005_03A6;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_SmxCause.eVacLow;                                    // 归因：真空不足 / Cause: vacuum insufficient
END_IF
IF (NOT _bFault) AND tonDischarge.Q THEN                                 // 出料超时 / Discharge timeout
    _uFault := 16#0005_03A6;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_SmxCause.eDischargeTmo;                              // 归因：出料超时 / Cause: discharge timeout
END_IF

(* —— 段 5：故障解除式（R240 全当拍量） —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT _bNonFin) AND (NOT bStart) THEN
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_SmxCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
END_IF

(* —— 段 5A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_SmxState.eFault) THEN
    _eState := E_DL_SmxState.eFault;                                     // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 6：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_SmxState.eIdle:
    IF bStart AND (NOT _bFault) THEN                                     // 出口 1：启动 / Start
        _eState := E_DL_SmxState.eFill;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_SmxState.eFault;
    END_IF

E_DL_SmxState.eFill:
    IF NOT bStart THEN                                                   // 出口 1：撤启动 → 安全收料（R98 双出口） / Start released, safe discharge
        _eState := E_DL_SmxState.eDischarge;
    ELSIF _bFillReached AND (tonFill.ET >= tFill) THEN                   // 出口 2：达窗且过最短时长 / Reached after minimum duration
        _eState := E_DL_SmxState.eDisperse;
    END_IF

E_DL_SmxState.eDisperse:
    IF NOT bStart THEN                                                   // 出口 1：撤启动 → 安全收料（R98 双出口） / Start released, safe discharge
        _eState := E_DL_SmxState.eDischarge;
    ELSIF _bSpeedInTol AND (tonDisperse.ET >= tDisperse) THEN            // 出口 2：转速达窗且分散时长满 / Speed reached and dispersion time done
        _eState := E_DL_SmxState.eDeair;
    END_IF

E_DL_SmxState.eDeair:
    IF NOT bStart THEN                                                   // 出口 1：撤启动 → 安全收料（R98 双出口） / Start released, safe discharge
        _eState := E_DL_SmxState.eDischarge;
    ELSIF _bVacInTol AND (tonDeair.ET >= tDeair) THEN                    // 出口 2：真空达窗且脱泡时长满 / Vacuum reached and de-air time done
        _eState := E_DL_SmxState.eDischarge;
    END_IF

E_DL_SmxState.eDischarge:
    IF _bDischDone AND (tonDischarge.ET >= tDischarge) THEN              // 出口 1：料位到下限且过最短时长 / Level low and minimum duration done
        _uInfo := 16#0005_04CE;                                          // 信息级：批次循环完成 / Info: batch completed
        _eState := E_DL_SmxState.eDone;
    ELSIF bStart THEN                                                    // 出口 2：重新给启动（前置消失，R98） / Start re-asserted
        _eState := E_DL_SmxState.eFill;
    END_IF

E_DL_SmxState.eDone:
    bCycleDone := TRUE;                                                  // 完成相保持完成标志 / Hold done flag in done phase
    IF NOT bStart THEN                                                   // 出口 1：撤启动回空闲 / Start released returns idle
        _eState := E_DL_SmxState.eIdle;
    ELSIF bStart THEN                                                    // 出口 2：新批次请求 / New batch requested
        _eState := E_DL_SmxState.eFill;
    END_IF

E_DL_SmxState.eFault:
    ;                                                                     // 故障相：仅段 5 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _uFault := 16#0005_03A6;                                             // 故障级：非法相位兜底（归并总码） / Illegal-phase fallback
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_SmxCause.ePhaseBad;                                  // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_SmxState.eFault;

END_CASE

(* —— 段 7：出口单点映射（名实同源；锁存码回放；故障相命令全落） —— *)
IF _bFault THEN
    bInletValveCmd     := FALSE;                                         // 故障相：进料阀关 / Inlet valve closed in fault
    bStirrerFastCmd    := FALSE;                                         // 故障相：高速搅拌停 / High-speed stirrer off in fault
    bVacPumpCmd        := FALSE;                                         // 故障相：真空泵停 / Vacuum pump off in fault
    bDischargeValveCmd := FALSE;                                         // 故障相：出料阀关（安全侧不动料） / Discharge valve closed in fault
    bCycleDone         := FALSE;                                         // 故障相不宣称完成 / No completion claim in fault
ELSE
    bInletValveCmd     := (_eState = E_DL_SmxState.eFill);               // 进料阀仅加料相开 / Inlet open only while filling
    bStirrerFastCmd    := (_eState = E_DL_SmxState.eDisperse);           // 高速搅拌仅分散相开 / Fast stirrer only while dispersing
    bVacPumpCmd        := (_eState = E_DL_SmxState.eDeair);              // 真空泵仅脱泡相开 / Vacuum pump only while de-airing
    bDischargeValveCmd := (_eState = E_DL_SmxState.eDischarge);          // 出料阀仅出料相开 / Discharge valve only while discharging
END_IF
IF _bFault THEN
    nErrId := _uFault;                                                   // 故障锁存码回放 / Replay latched fault code
ELSE
    nErrId := _uInfo;                                                    // 信息码 / Info code
END_IF
bError := _bFault;                                                       // 故障标志与锁存同源（名实双出口，R191） / Flag from latch
eState := _eState;                                                       // 状态出口 / State outlet
eCause := _eCause;                                                       // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
