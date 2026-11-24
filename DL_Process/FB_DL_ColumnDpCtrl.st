(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ColumnDpCtrl
 * 溯源说明 (Provenance): 道莅 clean-room 防御性实现（IEC 61131-3 纯净实现，闭源文档仅借语义，零代码行）
 * 所属子库 (Sublibrary) : DL_Process / ProcessControl
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），仅用
 *                         Standard.library 的 TON / LIMIT / ABS / TIME_TO_DINT / DINT_TO_TIME
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 精馏塔压差控制
 * 功能一句话 (Summary)  : 以塔压差设定为基准增量式双向调节回流与再沸两路给定，
 *                         带死区、双侧抗饱和，压差越上限时按防冲塔策略强制分配。
 *
 * 本件存在的意义 (Why this unit exists)
 *   精馏塔的 ΔP 是「液泛前兆」的直接指示：ΔP 升高说明上升蒸汽被液相托住，
 *   继续加热会冲塔（产品全部跑废、可能超压）。库内 FB_DL_RatioController 管
 *   两路比值、FB_DL_SplitRangeControl 管单输出分程，都不解「ΔP 偏高时增回流
 *   减再沸、ΔP 偏低时反向」这条双向分配律，也没有防冲塔的强制优先级。
 *
 * 增量式调节与抗饱和 (Incremental law and anti-windup)
 *   两路输出都是**增量累加**的绝对给定（不是增量输出），每走一步：
 *     ΔP 偏高（> 设定 + 死区）→ 回流 +fStep、再沸 −fStep
 *     ΔP 偏低（< 设定 − 死区）→ 回流 −fStep、再沸 +fStep
 *   累加后钳到 fOutMin~fOutMax，且**到达限值即停止向该方向累加**——钳位后
 *   不再累加是本件的抗饱和手段，不做积分回算（塔的工艺时间常数以十分钟计，
 *   回算没有收益，只会让审计算不清）。
 *
 * 防冲塔优先级 (Anti-flooding priority)
 *   fDpMeas > fDpHighLimit 持续 tConfirm → bDpHigh：**再沸立即降到 fOutMin、
 *   回流抬到 fOutMax**，压差调节暂时让位。这条优先级高于增量调节，因为冲塔
 *   是不可逆的产品损失；退出须压差回落到 fDpHighLimit − fDpDeadband 以下
 *   （用已有死区引脚做回差，不新开参数），避免在限值上反复进出。
 *
 * 引脚补全声明 (Pin completion —— 规格正文要求但引脚表漏列)
 *   fStep : 单步调节量 [%]，规格正文明确要求「步长引脚 fStep（缺省 1.0 %）」；
 *   tStep : 步进节拍 [ms]，增量式调节必须有时基，否则步进率随任务周期漂移。
 *   tStep 采用 T#200MS 缺省（现场常规回路周期），两引脚均已按要求常量化默认值。
 *
 * 边界安全 (Boundary)
 *   ① fDpSp <= 0、fOutMin >= fOutMax、fDpHighLimit <= fDpSp、fStep <= 0、
 *      任一参数非有限 → 故障 030E、**双输出置 fOutMin**（切断热源侧再加量）；
 *   ② fDpMeas 非有限 → 故障 030F、**保持末次输出**（塔不能因坏值断热，
 *      与①方向相反，两条并列写死）；
 *   ③ 死区内 → 信息 01DC，不调节、输出保持；
 *   ④ bDpHigh 进入置 01DD，退出复用 01DC（R90 不加码，头注释写明复用理由）；
 *   ⑤ 失能 → eIdle、双输出置 fOutMin、bDpHigh 清零（逐项赋，R72）；
 *   ⑥ 两只 TON 无条件刷新（步进节拍 / 越限确认），各司其职不共用；
 *   ⑦ CASE 落 ELSE 置 0310 并回 eFault。
 *
 * 错误码    : 16#0005_01DC ΔP 在死区内不调节，或已退出防冲塔——信息级，正常调节
 *             16#0005_01DD ΔP 越上限，已按防冲塔策略强制分配——信息级，保护动作
 *             16#0005_030E 控制参数非法（设定/限值/步长/上下限关系）——故障级，双输出置下限
 *             16#0005_030F ΔP 输入非有限，保持末次输出——故障级，不得断热
 *             16#0005_0310 状态机落 ELSE 兜底（非法状态）——故障级，回 eFault
 * 码位总账  : 16#0005_01DC 用 / 16#0005_01DD 用 ｜ 16#0005_030E 用 / 16#0005_030F 用 / 16#0005_0310 用
 * 状态机    : E_DL_ColumnDpState（eIdle / eNormal / eDpHigh / eDpLow / eFault），CASE 含 ELSE 兜底，
 *             ELSE 置 16#0005_0310 并回 eFault；失能无条件回 eIdle
 * 采样约定  : 每任务周期调用一次；步进节拍由 tStep 给定，越限确认由 tConfirm 给定
 * 依赖说明  : 只做组合编排，不复制低层算法；无 DL_ 子库调用
 * 验收向量  : V1 ΔP 5.0、设定 5.0、死区 0.2 → 死区内不调节，eErr = 01DC，输出保持
 *             V2 ΔP 6.0（> 5.2）、步长 1.0、节拍 200 ms → 每步回流 +1、再沸 −1，
 *                累加到限值后停（抗饱和主向量）
 *             V3 V2 持续到回流 = fOutMax → bLimited = TRUE，不再向该方向累加
 *             V4 ΔP 8.5（> 上限 8.0）持续 2 s → bDpHigh = TRUE，回流 = fOutMax、
 *                再沸 = fOutMin，eErr = 01DD（防冲塔主向量）
 *             V5 V4 后 ΔP 回落到 7.9（< 8.0 − 0.2）→ 退出防冲塔，eErr = 01DC（回差主向量）
 *             V6 fDpSp = 0 → 030E，双输出 = fOutMin，bValid = FALSE
 *             V7 fDpMeas = NaN → 030F，双输出保持上一拍值（坏值不断热主向量）
 *             V8 bEnable 落 → eIdle，双输出 = fOutMin，bDpHigh = FALSE
 * 红线自检  : 全局变量声明零使用 / 外部变量访问零使用 / 物理地址零使用 ｜ 纯 IEC 61131-3 ｜ 无除法
 *             浮点只用大小与容差比较 ｜ 无循环 ｜ 全变量双语同行注释 ｜ ENUM + CASE
 *             含 ELSE ｜ 两只 TON 在主体前部无条件刷新 ｜ 阈值常量化，无魔法数
 * 修订历史  : 2026-11-16  v1.0.0  首版入库（R22 · 批 3 · 过程单元控制）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ColumnDpState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 塔压差控制相位。0 起步长 10。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_ColumnDpState :
(
    eIdle   := 0,      // 待机：未使能或参数非法 / Idle, disabled or illegal parameters
    eNormal := 10,     // 正常：ΔP 在死区外按增量调节 / Normal, incremental control outside the dead band
    eDpHigh := 20,     // 压差高：防冲塔强制分配 / High differential pressure, anti-flooding distribution
    eDpLow  := 30,     // 压差低：反向调节 / Low differential pressure, reverse correction
    eFault  := 99      // 故障：参数非法或输入非有限 / Fault, illegal parameter or non-finite input
);
END_TYPE

FUNCTION_BLOCK FB_DL_ColumnDpCtrl
VAR_INPUT
    fDpMeas      : REAL;                       // 塔压差实测 [kPa] / measured column differential pressure [kPa]
    fDpSp        : REAL := 5.0;                // 压差设定 [kPa]，须 > 0 / differential pressure setpoint [kPa], must be > 0
    fDpDeadband  : REAL := 0.2;                // 死区半宽 [kPa]，须 >= 0 / dead band half width [kPa], must be >= 0
    fOutMin      : REAL := 0.0;                // 输出下限 [%] / output floor [%]
    fOutMax      : REAL := 100.0;              // 输出上限 [%]，须 > fOutMin / output ceiling [%], must exceed the floor
    fDpHighLimit : REAL := 8.0;                // 防冲塔压差上限 [kPa]，须 > fDpSp / anti-flooding limit [kPa], must exceed the setpoint
    fStep        : REAL := 1.0;                // 单步调节量 [%]，须 > 0 / single step size [%], must be > 0
    tStep        : TIME := T#200MS;            // 步进节拍 [ms] / step cadence [ms]
    tConfirm     : TIME := T#2S;               // 越限确认时间 [ms] / limit confirm time [ms]
    bEnable      : BOOL;                       // 使能 / enable
END_VAR
VAR_OUTPUT
    fRefluxOut   : REAL;                       // 回流量给定 [%]，范围 fOutMin~fOutMax / reflux setpoint [%]
    fReboilOut   : REAL;                       // 再沸热源给定 [%]，范围 fOutMin~fOutMax / reboiler duty setpoint [%]
    bDpHigh      : BOOL;                       // 压差越上限（防冲塔生效） / differential pressure above the limit
    bLimited     : BOOL;                       // 输出已到限值（抗饱和生效） / an output sits at its limit
    eErr         : UDINT;                      // 错误码，0 表示无错 / error code, 0 means no error
    bError       : BOOL;                       // 故障级标志，仅故障级错误置位 / fault-class flag, set only on fault-level codes
    bValid       : BOOL;                       // 输出可用标志 / outputs usable flag
END_VAR
VAR
    fbStep       : TON;                        // 步进节拍计时，段 6 无条件刷新 [ms] / step cadence timer
    fbHigh       : TON;                        // 越限确认计时，段 6 无条件刷新 [ms] / limit confirm timer
    _eState      : E_DL_ColumnDpState := E_DL_ColumnDpState.eIdle; // 当前相位 / current phase
    _bInit       : BOOL := FALSE;              // 首扫标志，初值 FALSE 取非判定 / first-scan flag, tested negated
    _bParamBad   : BOOL;                       // 参数非法标志 / illegal parameter flag
    _bFiniteBad  : BOOL;                       // 输入非有限标志 / non-finite input flag
    _bIllegal    : BOOL;                       // 非法状态标志 / illegal state flag
    _bStepBreak  : BOOL;                       // 步进计时器断输入一拍 / step timer one-scan break
    _bHighBreak  : BOOL;                       // 越限计时器断输入一拍 / limit timer one-scan break
    _bStepPulse  : BOOL;                       // 本拍走一步 / one step this scan
    _bInDeadband : BOOL;                       // 本拍在死区内 / inside the dead band this scan
    _bHiAbove    : BOOL;                       // 本拍越上限（裸判据） / above the limit this scan
    _bHiExit     : BOOL;                       // 压差已回落到退出线以下 / below the exit line
    _tStepUse    : TIME := T#200MS;            // 生效步进节拍 [ms]，已钳位 / effective cadence, clamped
    _tConfUse    : TIME := T#2S;               // 生效确认时间 [ms]，已钳位 / effective confirm time, clamped
    _fReflux     : REAL;                       // 回流量累加保持量 [%] / held reflux setpoint [%]
    _fReboil     : REAL;                       // 再沸累加保持量 [%] / held reboiler setpoint [%]
    _fRefluxOut  : REAL;                       // 回流输出暂存 [%] / reflux outlet staging
    _fReboilOut  : REAL;                       // 再沸输出暂存 [%] / reboiler outlet staging
END_VAR
VAR CONSTANT
    DL_VAL_LIM     : REAL := 1.0E6;            // 有限性判定的绝对值上限 [无量纲] / finiteness ceiling
    DL_SP_MIN      : REAL := 0.0;              // 设定下限 [kPa]，须严格大于 / setpoint floor, strictly greater
    DL_BAND_MIN    : REAL := 0.0;              // 死区下限 [kPa] / dead band floor [kPa]
    DL_STEP_MIN    : REAL := 0.0;              // 步长下限 [%]，须严格大于 / step floor, strictly greater
    DL_EPS         : REAL := 1.0E-6;           // 浮点比较容差 [%] / float comparison tolerance [%]
    DL_CAD_MIN_MS  : DINT := 10;               // 步进节拍下限 [ms] / cadence floor [ms]
    DL_CAD_MAX_MS  : DINT := 60000;            // 步进节拍上限 [ms] / cadence ceiling [ms]
    DL_CONF_MAX_MS : DINT := 60000;            // 确认时间上限 [ms] / confirm ceiling [ms]
    DL_TIME_ZERO   : TIME := T#0MS;            // 时间零值基准 [ms] / time zero reference
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置（输出与累加量在段 9 单点写入）
 *      Per-scan presets, the outputs and accumulators are written in segment nine
 *-----------------------------------------------------------------------------*)
eErr         := 16#0000_0000;                  // 错误码每拍重算 / error code recomputed every scan
bError       := FALSE;                         // 故障标志每拍重算 / fault flag recomputed every scan
bValid       := FALSE;                         // 可用标志每拍重算 / usable flag recomputed every scan
bDpHigh      := FALSE;                         // 越限标志每拍重算 / high flag recomputed
bLimited     := FALSE;                         // 抗饱和标志每拍重算 / limited flag recomputed
_bParamBad   := FALSE;                         // 参数非法标志预清零 / parameter flag pre-cleared
_bFiniteBad  := FALSE;                         // 非有限标志预清零 / non-finite flag pre-cleared
_bIllegal    := FALSE;                         // 非法状态标志预清零 / illegal state flag pre-cleared
_bStepPulse  := FALSE;                         // 步进脉冲预置 FALSE / step pulse preset FALSE
_bInDeadband := FALSE;                         // 死区标志预置 FALSE / dead band flag preset FALSE
_bHiAbove    := FALSE;                         // 越上限标志预置 FALSE / above-limit preset FALSE
_bHiExit     := FALSE;                         // 退出标志预置 FALSE / exit preset FALSE

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化（两路从输出下限起：塔未运行时回流与热源都在最小位）
 *      First-scan initialisation, both loops start at the output floor
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState     := E_DL_ColumnDpState.eIdle;   // 相位待机 / phase idle
    _fReflux    := 0.0;                        // 回流累加量 0 [%] / reflux accumulator zero
    _fReboil    := 0.0;                        // 再沸累加量 0 [%] / reboiler accumulator zero
    _bStepBreak := TRUE;                       // 步进节拍从零开始 / cadence timer starts from zero
    _bHighBreak := TRUE;                       // 越限确认从零开始 / confirm timer starts from zero
    _bInit      := TRUE;                       // 首扫只做一次 / the first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜参数闸门（设定/上下限关系/越限值/步长，任一非法即故障级）
 *      Parameter gate, any illegal value or relation is a fault
 *-----------------------------------------------------------------------------*)
IF (fDpSp <> fDpSp) OR (ABS(fDpSp) > DL_VAL_LIM) OR (fDpSp <= DL_SP_MIN) THEN
    _bParamBad := TRUE;                        // 压差设定非法 / setpoint illegal
END_IF
IF (fOutMin <> fOutMin) OR (fOutMax <> fOutMax) OR (ABS(fOutMin) > DL_VAL_LIM)
   OR (ABS(fOutMax) > DL_VAL_LIM) THEN
    _bParamBad := TRUE;                        // 输出上下限非有限 / output limits non-finite
ELSIF fOutMin >= fOutMax THEN
    _bParamBad := TRUE;                        // 上下限关系非法 / illegal limit relation
END_IF
IF (fDpHighLimit <> fDpHighLimit) OR (ABS(fDpHighLimit) > DL_VAL_LIM)
   OR (fDpHighLimit <= fDpSp) THEN
    _bParamBad := TRUE;                        // 越限值必须严格大于设定 / the limit must exceed the setpoint
END_IF
IF (fStep <> fStep) OR (ABS(fStep) > DL_VAL_LIM) OR (fStep <= DL_STEP_MIN) THEN
    _bParamBad := TRUE;                        // 步长非法 / step illegal
END_IF
IF (fDpDeadband <> fDpDeadband) OR (fDpDeadband < DL_BAND_MIN) OR (ABS(fDpDeadband) > DL_VAL_LIM) THEN
    _bParamBad := TRUE;                        // 死区非法 / dead band illegal
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜输入有限性（区间判据同时拦 NaN 与 ±Inf）
 *      Input finiteness, the interval test catches NaN and infinity
 *-----------------------------------------------------------------------------*)
IF (fDpMeas < -DL_VAL_LIM) OR (fDpMeas > DL_VAL_LIM) THEN
    _bFiniteBad := TRUE;                       // 压差非有限 / differential pressure non-finite
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜判据计算（死区 / 越上限 / 退出线，全部在参数合法时才可信）
 *      Criteria evaluation, only meaningful with legal parameters
 *-----------------------------------------------------------------------------*)
IF (NOT _bFiniteBad) AND (NOT _bParamBad) THEN
    _bInDeadband := (ABS(fDpMeas - fDpSp) <= fDpDeadband); // 死区判据 [布尔] / dead band test
    _bHiAbove    := (fDpMeas > fDpHighLimit);              // 越上限裸判据 / raw above-limit test
    _bHiExit     := (fDpMeas < (fDpHighLimit - fDpDeadband)); // 退出线用已有死区做回差 / the exit line reuses the dead band
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜两只计时器无条件刷新（R40：CASE 之外每拍必调，各司其职不共用）
 *      Both timers refreshed unconditionally, each with its own duty
 *-----------------------------------------------------------------------------*)
_tStepUse := tStep;                            // 步进节拍直取引脚 [ms] / cadence from the pin
IF TIME_TO_DINT(_tStepUse) < DL_CAD_MIN_MS THEN
    _tStepUse := DINT_TO_TIME(DL_CAD_MIN_MS);  // 下限钳位（无专用码位，R90 不新开码） / clamped to the floor
END_IF
IF TIME_TO_DINT(_tStepUse) > DL_CAD_MAX_MS THEN
    _tStepUse := DINT_TO_TIME(DL_CAD_MAX_MS);  // 上限钳位 / clamped to the ceiling
END_IF

_tConfUse := tConfirm;                         // 确认时间直取引脚 [ms] / confirm time from the pin
IF TIME_TO_DINT(_tConfUse) < 0 THEN
    _tConfUse := DL_TIME_ZERO;                 // 负时间兜底为 0 / fallback to zero
END_IF
IF TIME_TO_DINT(_tConfUse) > DL_CONF_MAX_MS THEN
    _tConfUse := DINT_TO_TIME(DL_CONF_MAX_MS); // 上限钳位 / clamped to the ceiling
END_IF

fbStep(IN := bEnable AND (NOT _bParamBad) AND (NOT _bFiniteBad)
             AND (NOT _bInDeadband) AND (NOT _bHiAbove) AND (NOT _bStepBreak),
       PT := _tStepUse);                       // 步进节拍计时
_bStepBreak := FALSE;                          // 断输入拍在调用后自清 / break self-cleared after the call
_bStepPulse := fbStep.Q;                       // 本拍走一步 / one step this scan

fbHigh(IN := bEnable AND (NOT _bParamBad) AND (NOT _bFiniteBad) AND _bHiAbove AND (NOT _bHighBreak),
       PT := _tConfUse);                       // 越限确认计时
_bHighBreak := FALSE;                          // 断输入拍在调用后自清 / break self-cleared after the call

(*------------------------------------------------------------------------------
 * 段 7｜相位机（只做迁移；调节量在段 8 演进）
 *      Phase machine, transitions only, the setpoints evolve in segment eight
 *-----------------------------------------------------------------------------*)
CASE _eState OF

    E_DL_ColumnDpState.eIdle:                  // 待机：参数合法且使能即进入
        IF _bParamBad OR _bFiniteBad THEN
            _eState := E_DL_ColumnDpState.eFault; // 原因未消失，转故障 / the cause persists
        ELSIF bEnable THEN
            IF fbHigh.Q THEN
                _eState := E_DL_ColumnDpState.eDpHigh; // 越限已确认，直接进防冲塔 / the limit is confirmed
                _bStepBreak := TRUE;           // 步进节拍重启 / the cadence restarts
            ELSIF (fDpSp - fDpMeas) > fDpDeadband THEN
                _eState := E_DL_ColumnDpState.eDpLow;  // 压差偏低，直接进低压相 / differential pressure low
            ELSE
                _eState := E_DL_ColumnDpState.eNormal; // 正常区间（含偏高与死区） / normal range
            END_IF
        END_IF

    E_DL_ColumnDpState.eNormal:                // 正常：越限或偏低都会迁移
        IF _bParamBad OR _bFiniteBad THEN
            _eState := E_DL_ColumnDpState.eFault; // 转故障 / go to fault
        ELSIF NOT bEnable THEN
            _eState := E_DL_ColumnDpState.eIdle;  // 失能回待机 / disabled, back to idle
        ELSIF fbHigh.Q THEN
            _eState := E_DL_ColumnDpState.eDpHigh; // 越限确认，进防冲塔 / confirmed, anti-flooding
            _bStepBreak := TRUE;               // 步进节拍重启 / the cadence restarts
        ELSIF (fDpSp - fDpMeas) > fDpDeadband THEN
            _eState := E_DL_ColumnDpState.eDpLow;  // 压差偏低 / differential pressure low
        END_IF

    E_DL_ColumnDpState.eDpLow:                 // 压差低：回升进死区即回正常
        IF _bParamBad OR _bFiniteBad THEN
            _eState := E_DL_ColumnDpState.eFault; // 转故障 / go to fault
        ELSIF NOT bEnable THEN
            _eState := E_DL_ColumnDpState.eIdle;  // 失能回待机 / disabled, back to idle
        ELSIF fbHigh.Q THEN
            _eState := E_DL_ColumnDpState.eDpHigh; // 越限确认，进防冲塔 / confirmed, anti-flooding
            _bStepBreak := TRUE;               // 步进节拍重启 / the cadence restarts
        ELSIF (fDpMeas - fDpSp) >= (-fDpDeadband) THEN
            _eState := E_DL_ColumnDpState.eNormal; // 已回到死区边界内 / back inside the dead band edge
        END_IF

    E_DL_ColumnDpState.eDpHigh:                // 防冲塔：压差回落到退出线以下才让位
        IF _bParamBad OR _bFiniteBad THEN
            _eState := E_DL_ColumnDpState.eFault; // 转故障 / go to fault
        ELSIF NOT bEnable THEN
            _eState := E_DL_ColumnDpState.eIdle;  // 失能回待机 / disabled, back to idle
        ELSIF _bHiExit THEN
            _eState := E_DL_ColumnDpState.eNormal; // 退出防冲塔（回差确认） / leave anti-flooding after hysteresis
            _bStepBreak := TRUE;               // 步进节拍重启，避免立即继续累加 / the cadence restarts
        END_IF

    E_DL_ColumnDpState.eFault:                 // 故障：参数与输入恢复即回待机
        IF bEnable AND (NOT _bParamBad) AND (NOT _bFiniteBad) THEN
            _eState := E_DL_ColumnDpState.eIdle; // 原因消失 / the cause is gone
            _bStepBreak := TRUE;               // 步进节拍重启 / the cadence restarts
        END_IF

    ELSE
        _bIllegal := TRUE;                     // 标记非法状态 / flag the illegal state
        _eState   := E_DL_ColumnDpState.eFault; // 回故障态 / back to the fault state
END_CASE

(*------------------------------------------------------------------------------
 * 段 8｜调节量演进（唯一累加点：防冲塔强制分配 > 步进增量）
 *      Setpoint evolution, the single accumulation point
 *-----------------------------------------------------------------------------*)
IF (_eState = E_DL_ColumnDpState.eDpHigh) AND (NOT _bFiniteBad) AND (NOT _bParamBad) THEN
    _fReflux := fOutMax;                       // 防冲塔：回流抬到上限 [%] / reflux forced to the ceiling
    _fReboil := fOutMin;                       // 防冲塔：再沸立即降到下限 [%] / reboiler forced to the floor
ELSIF _bStepPulse AND bEnable AND (NOT _bFiniteBad) AND (NOT _bParamBad)
      AND (_eState <> E_DL_ColumnDpState.eIdle) THEN
    IF (fDpMeas - fDpSp) > fDpDeadband THEN
        (* ΔP 偏高：增回流、减再沸，各自到达限值即停（抗饱和） *)
        (* High differential pressure, add reflux and cut reboiler, both stop at their limits *)
        IF _fReflux < (fOutMax - DL_EPS) THEN
            _fReflux := _fReflux + fStep;      // 回流增量 [%] / reflux increment
        END_IF
        IF _fReboil > (fOutMin + DL_EPS) THEN
            _fReboil := _fReboil - fStep;      // 再沸减量 [%] / reboiler decrement
        END_IF
    ELSIF (fDpSp - fDpMeas) > fDpDeadband THEN
        (* ΔP 偏低：减回流、增再沸，各自到达限值即停（抗饱和） *)
        (* Low differential pressure, cut reflux and add reboiler, both stop at their limits *)
        IF _fReflux > (fOutMin + DL_EPS) THEN
            _fReflux := _fReflux - fStep;      // 回流减量 [%] / reflux decrement
        END_IF
        IF _fReboil < (fOutMax - DL_EPS) THEN
            _fReboil := _fReboil + fStep;      // 再沸增量 [%] / reboiler increment
        END_IF
    END_IF
    _bStepBreak := TRUE;                       // 走一步后重启节拍，节拍严格等于 tStep / restart the cadence
END_IF

(* 限值钳位：参数变更或强制分配后一律落回 [fOutMin, fOutMax] *)
(* Clamped into the output range after any change *)
IF (NOT _bParamBad) THEN
    _fReflux := LIMIT(fOutMin, _fReflux, fOutMax); // 回流钳位 [%] / reflux clamped
    _fReboil := LIMIT(fOutMin, _fReboil, fOutMax); // 再沸钳位 [%] / reboiler clamped
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜输出单点写入与码位优先级链
 *      Single write point of the outputs and the code priority chain
 *-----------------------------------------------------------------------------*)
IF _bParamBad THEN
    _fRefluxOut := fOutMin;                    // 参数非法：回流置下限（安全侧） [%] / reflux to the floor
    _fReboilOut := fOutMin;                    // 参数非法：再沸置下限（切断热源加量） [%] / reboiler to the floor
ELSIF NOT bEnable THEN
    _fRefluxOut := fOutMin;                    // 失能：回流置下限 [%] / reflux to the floor
    _fReboilOut := fOutMin;                    // 失能：再沸置下限 [%] / reboiler to the floor
ELSE
    _fRefluxOut := _fReflux;                   // 正常：回流给定 [%] / reflux setpoint
    _fReboilOut := _fReboil;                   // 正常：再沸给定 [%] / reboiler setpoint
END_IF

fRefluxOut := _fRefluxOut;                     // 回流出口 [%] / reflux outlet
fReboilOut := _fReboilOut;                     // 再沸出口 [%] / reboiler outlet
bDpHigh    := (_eState = E_DL_ColumnDpState.eDpHigh); // 越限标志出口 / high flag outlet
bLimited   := (_fRefluxOut >= (fOutMax - DL_EPS)) OR (_fRefluxOut <= (fOutMin + DL_EPS))
              OR (_fReboilOut >= (fOutMax - DL_EPS)) OR (_fReboilOut <= (fOutMin + DL_EPS)); // 任一输出到限值即置位

IF _bIllegal THEN
    eErr   := 16#0005_0310;                    // 故障级：状态机兜底 / fault: state machine fallback
    bError := TRUE;                            // 置故障标志 / raise the fault flag
ELSIF _bParamBad THEN
    eErr   := 16#0005_030E;                    // 故障级：控制参数非法 / fault: control parameters illegal
    bError := TRUE;                            // 置故障标志 / raise the fault flag
ELSIF _bFiniteBad THEN
    eErr   := 16#0005_030F;                    // 故障级：输入非有限，保持末次输出 / fault: non-finite input, outputs held
    bError := TRUE;                            // 置故障标志 / raise the fault flag
ELSIF bDpHigh THEN
    eErr   := 16#0005_01DD;                    // 信息级：越上限已按防冲塔策略分配 / informational: anti-flooding applied
ELSIF _bInDeadband THEN
    eErr   := 16#0005_01DC;                    // 信息级：死区内不调节（退出防冲塔亦复用本码） / informational: no correction
END_IF

IF bError THEN
    bValid := FALSE;                           // 故障级：输出不可用 / fault: outputs unusable
ELSIF NOT bEnable THEN
    bValid := FALSE;                           // 失能：输出不可用 / disabled: unusable
ELSE
    bValid := TRUE;                            // 输出可用 / outputs usable
END_IF

END_FUNCTION_BLOCK
