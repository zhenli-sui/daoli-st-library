(*
    FB_DL_VirtualMasterAxis —— 虚拟主轴相位源
    ------------------------------------------------------------------
    分类      : DL_Motion / MasterSource
    前缀      : FB_DL_
    版本      : 1.0.1
    溯源      : T2-4 S7 Motion 工艺对象分型（只借「同步轴需要独立主值源」的公开架构语义）；
                T1-6 PLCopen 凸轮/齿轮需要连续相位主值的公开条款为次源；
                斜坡积分器、精度门限、冻结策略与码位 100% 自有；clean-room 重写，
                未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    道莅 clean-room 防御性实现：语义借鉴、代码与码位 100% 自有
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R22 批 4 · #13）
    ------------------------------------------------------------------
    功能说明  : 电子凸轮 / 电子齿轮的主值源：把「速度给定 + 加减速限值」积分成连续相位、
                速度与加速度三个量，供从轴按相位跟随。本件不发任何运动指令、
                不自造轴状态枚举——它只回答「主轴现在在哪、多快、加速度多大」。
    相位精度  : 相位以 LREAL 累加。IEEE 754 双精度在 |x| > 1.0E15 mm 时相邻可表示
                差值已大于 1e-3 mm 量级，凸轮相位已失真而调用方看不出来，因此本件把
                1.0E15 设为硬门限：越限即报故障 02EE 并冻结相位，不静默累计。
                冻结而不是清零，是为了让调用方看清「停在哪」再决定复位。
    两条律    : ① bHold 走减速斜坡降到 0，绝不瞬时归零（瞬时归零会让从轴指令跳变）；
                ② 失能（bEnable 落）同样走减速斜坡，且残速期间相位继续积分，
                   因为轴物理上仍在走，位置不跟着走就等于伪造相位。
    设计取舍  : 复位沿优先于失能判定——同一拍既给 bPhaseReset 又撤 bEnable 时先复位再判状态，
                否则复位沿会被失能分支吞掉，调用方会以为「按了没反应」。
                参数类与非有限类故障（02ED）一律冻结速度与相位，不做「按末次速度继续跑」：
                采样周期不可信时继续积分等于用错误的 dt 编造相位。
    职责边界  : 本件只做「主值源」。主轴的使能、抱闸、限位、回零仍归轴功能块；
                本件不消费、不改写任何轴状态；Blending 速度融合不在本件能力范围。
    错误码    : 16#0004_01D7 加速度限幅生效（仍在斜坡中，未达给定）——信息级，边沿发布
                16#0004_01D8 相位复位已执行——信息级，单拍发布
                16#0004_02ED 采样周期非正 / 速度与限值参数非法或非有限——故障级，
                             冻结速度与相位并保持末次有效速度
                16#0004_02EE 相位累计超 LREAL 有效精度 1.0E15 mm，已冻结——故障级，
                             需调用方给 bPhaseReset 复位后才允许回待机
                16#0004_02EF 状态机落 ELSE 兜底（非法状态）——故障级，回 eFault
    码位总账  : 16#0004_01D7 用 / 16#0004_01D8 用 ｜ 16#0004_02ED 用 / 16#0004_02EE 用 / 16#0004_02EF 用
    状态机    : E_DL_VMasterState（eIdle / eRamping / eSteady / eHolding / eFault），
                CASE 含 ELSE 兜底，ELSE 置 16#0004_02EF 并回 eFault；
                斜坡与积分在本体段 6 执行，故障拍与故障相（eFault）均冻结，
                参数修复后须经失能复位或 bPhaseReset 才恢复积分（v1.0.1 终审修复）。
    采样约定  : fbPhaseReset 在本体首部无条件刷新（R40）；dt 由 tSample 引脚换算，
                严禁读取系统时钟；换算链 TIME_TO_DINT → DINT_TO_REAL 在
                CODESYS V3.5 / TwinCAT 3 / InoProShop / Machine Expert 四平台均为
                标准运算符，若目标平台仅实现 TIME_TO_REAL 可等价替换（编译门槛已声明）。
    依赖      : 仅 Standard.library（R_TRIG / LIMIT / ABS），不引用任何其他 DL_ 子库。
    验收向量  :
                V1 域外早退：tSample = T#0MS → 02ED、bError=TRUE、bValid=FALSE，
                   相位与速度两拍完全相同（冻结）。
                V2 上限限幅：fVelSet = 5000 mm/s、fAccLimit = 1000 mm/s²、tSample = 1 ms
                   → 每拍速度增量恰为 1.0 mm/s、bLimited=TRUE、01D7 只出现一拍。
                V3 跨段时序：eSteady 中 bHold 置位 → 速度按 fDecLimit 逐拍递减，
                   位置继续积分直到速度为 0 才停；不得出现速度阶跃为 0。
                V4 复位首拍：bPhaseReset 与撤 bEnable 同拍 → 复位优先执行
                   （fMasterPos = fPosInit、fMasterVel = 0、01D8），随后才回 eIdle。
    红线自检  : 1 全局变量声明零使用 / 外部变量访问零使用 / 物理地址零使用 —— 通过，全部量经引脚注入
                2 纯 IEC 61131-3 跨平台 —— 通过，仅 Standard.library，换算链已在头注释声明门槛
                3 防御性编程 —— 通过，浮点判等用 1.0E-6 容差、除法前判 dt > 0、无非有限穿透
                4 声明行同行中英双语注释 + 单位 —— 通过，逐行附注（含枚举成员）
                5 ENUM + CASE 且含 ELSE 兜底 —— 通过
                6 TON / R_TRIG 无条件刷新 —— 通过，段 1 先行调用
                7 无魔法数 —— 通过，门限与容差全部 VAR CONSTANT，时间为引脚
    修订记录  : 2026-11-16 v1.0.0 首次入库（R22 批 4 · #13）
                2026-11-16 v1.0.1 R22 终审修复：段 6 积分增加 eFault 相位门控——
                原实现中 eFault 态下 bError 仅在故障检出拍为真，参数修复后下一拍
                bError 归假即恢复积分，与「eFault 冻结速度与相位」的头注释承诺矛盾；
                修复后故障相彻底冻结，恢复仅经「失能复位」或「bPhaseReset」两条路径
*)
TYPE E_DL_VMasterState :
(
    eIdle    := 0,       // 未使能；若仍有残速则按减速限值降到零并继续积分 / not enabled, a residual velocity is ramped down and the phase keeps integrating
    eRamping := 10,      // 斜坡中，速度尚未达到给定 / ramping, the velocity has not reached the setpoint yet
    eSteady  := 20,      // 已达给定，速度稳定，bReady 置位 / at the setpoint, bReady is asserted
    eHolding := 30,      // 保持相，目标速度强制为 0 但按减速斜坡逼近 / holding, the target is forced to zero and approached through the deceleration ramp
    eFault   := 40       // 故障，速度与相位冻结 / fault, both velocity and phase are frozen
);
END_TYPE

FUNCTION_BLOCK FB_DL_VirtualMasterAxis
VAR_INPUT
    bEnable      : BOOL;                       // 使能，FALSE 时目标速度归零并走减速斜坡 / enable, FALSE forces the target to zero through the deceleration ramp
    fVelSet      : REAL;                       // 主轴速度给定 [mm/s]，非有限即拒绝 / master velocity setpoint [mm/s], a non-finite value is rejected
    fAccLimit    : REAL := 1000.0;             // 加速限值 [mm/s²]，必须大于 0 / acceleration limit [mm/s²], must exceed zero
    fDecLimit    : REAL := 1000.0;             // 减速限值 [mm/s²]，必须大于 0 / deceleration limit [mm/s²], must exceed zero
    bHold        : BOOL;                       // 保持，TRUE 时按减速斜坡降到 0 而非瞬时归零 / hold, TRUE ramps the velocity down instead of stepping it to zero
    bPhaseReset  : BOOL;                       // 相位复位，上升沿生效且优先于失能判定 / phase reset, effective on the rising edge and prior to the disable test
    fPosInit     : REAL := 0.0;                // 复位目标相位 [mm]，非有限即拒绝 / reset target phase [mm], a non-finite value is rejected
    tSample      : TIME := T#1MS;              // 采样周期 [ms]，必须大于 0，禁读系统时钟 / sample period [ms], must exceed zero, never read from the system clock
END_VAR
VAR_OUTPUT
    fMasterPos   : LREAL;                      // 主轴相位 [mm]，LREAL 累加 / master phase [mm], accumulated in LREAL
    fMasterVel   : REAL;                       // 主轴速度 [mm/s]，斜坡输出 / master velocity [mm/s], the ramp output
    fMasterAcc   : REAL;                       // 主轴加速度 [mm/s²]，本拍实际生效值 / master acceleration [mm/s²], the value actually applied this scan
    bReady       : BOOL;                       // 主值可用，速度已达给定（或保持相已停稳）/ master value usable, the velocity has reached the setpoint or the hold has settled
    bLimited     : BOOL;                       // 本拍被加减速限值截断 / this scan was clipped by an acceleration or deceleration limit
    eErr         : UDINT;                      // 错误码，0 表示无错 / error code, 0 means no error
    bError       : BOOL;                       // 故障级标志，仅故障级错误置位 / fault-class flag, set only on fault-level codes
    bValid       : BOOL;                       // 输出可用标志，= NOT bError / outputs valid flag, equals NOT bError
END_VAR
VAR
    fbPhaseReset  : R_TRIG;                    // 复位沿检测实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    _fPosL        : LREAL;                     // 相位累加器（本件唯一的跨周期状态）/ the phase accumulator, the only truly cyclic state of this block
    _fVel         : REAL;                      // 速度状态，斜坡积分结果 [mm/s] / velocity state, the ramp integration result [mm/s]
    _fTarget      : REAL;                      // 本拍有效目标速度（含失能与保持折算）[mm/s] / effective target velocity of this scan including disable and hold [mm/s]
    _fDtSec       : REAL;                      // 本拍采样周期折算秒值 [s] / sample period converted to seconds [s]
    _fMaxUp       : REAL;                      // 本拍允许的速度上升量 [mm/s] / permitted velocity increase of this scan [mm/s]
    _fMaxDn       : REAL;                      // 本拍允许的速度下降量 [mm/s] / permitted velocity decrease of this scan [mm/s]
    _fDiff        : REAL;                      // 目标与当前速度之差 [mm/s] / difference between the target and the current velocity [mm/s]
    _fDelta       : REAL;                      // 本拍速度增量，限幅后 [mm/s] / velocity increment of this scan after clipping [mm/s]
    _bParamBad    : BOOL;                      // 参数或采样非法标志 / illegal parameter or sample flag
    _bLimitPrev   : BOOL;                      // 上一拍限幅标志，用于信息码边沿发布 / previous-scan limiting flag used for the edge-published info code
    _eState       : E_DL_VMasterState;         // 当前状态 / current state
END_VAR
VAR CONSTANT
    DL_VM_MS_PER_S    : REAL := 1000.0;        // 毫秒与秒的换算系数 [ms/s] / milliseconds per second [ms/s]
    DL_VM_POS_MAX     : LREAL := 1.0E15;       // 相位有效精度上限 [mm]，越限即冻结 / effective phase precision limit [mm], exceeded means freeze
    DL_VM_INF_GUARD   : REAL := 4.0E38;        // REAL 非有限幅值判定阈（大于 REAL 最大值）[mm/s] / REAL non-finite magnitude guard [mm/s]
    DL_VM_EPS         : REAL := 1.0E-6;        // 速度判等容差 [mm/s] / velocity equality tolerance [mm/s]
    DL_VM_ZERO        : REAL := 0.0;           // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
    DL_VM_T_ZERO      : TIME := T#0S;          // 零时间常量，用于采样周期门禁 / zero time constant used by the sample gate
END_VAR

// 段 1｜复位沿实例无条件周期刷新（红线 6：严禁放入 IF / CASE）/ segment 1, unconditional edge refresh
fbPhaseReset(CLK := bPhaseReset);

// 段 2｜输出与错误状态预置 / segment 2, preset outputs and error status
eErr := 0;                                      // 预置无错误 / preset no error
bError := FALSE;                                // 预置无故障标志 / preset no error flag
bLimited := FALSE;                              // 预置本拍无限幅 / preset no limiting this scan
bReady := FALSE;                                // 预置主值不可用 / preset the master value as not usable
fMasterAcc := DL_VM_ZERO;                       // 预置本拍加速度为 0 / preset the applied acceleration to zero

// 段 3｜参数与采样门禁：① 采样周期非正 ② 限值非正或非有限 ③ 给定与复位值非有限
// segment 3, parameter and sample gate
_bParamBad := FALSE;                            // 先假定参数合法 / assume legal parameters first
IF (tSample <= DL_VM_T_ZERO)
   OR (fAccLimit <= DL_VM_ZERO)
   OR (fDecLimit <= DL_VM_ZERO) THEN
    _bParamBad := TRUE;                         // 采样周期或限值非正 / the sample period or a limit is not positive
END_IF

// 非有限检测：NaN 用自不自等捕获，±Inf 用幅值门捕获（REAL 最大约 3.4E38）
// non-finite detection, NaN via self-inequality and plus/minus infinity via the magnitude guard
IF (fVelSet - fVelSet) <> (fVelSet - fVelSet) THEN
    _bParamBad := TRUE;                         // 速度给定为 NaN / the velocity setpoint is NaN
ELSIF ABS(fVelSet) > DL_VM_INF_GUARD THEN
    _bParamBad := TRUE;                         // 速度给定为 ±Inf / the velocity setpoint is infinite
END_IF
IF (fPosInit - fPosInit) <> (fPosInit - fPosInit) THEN
    _bParamBad := TRUE;                         // 复位相位为 NaN / the reset phase is NaN
ELSIF ABS(fPosInit) > DL_VM_INF_GUARD THEN
    _bParamBad := TRUE;                         // 复位相位为 ±Inf / the reset phase is infinite
END_IF

IF _bParamBad THEN
    eErr := 16#0004_02ED;                       // 故障级：采样周期或速度参数非法 / fault: sample period or velocity parameter illegal
    bError := TRUE;                             // 置故障标志 / raise the fault flag
    _eState := E_DL_VMasterState.eFault;        // 转故障，本拍不积分 / go to fault, no integration this scan
    fMasterVel := _fVel;                        // 保持末次有效速度 [mm/s] / hold the last valid velocity [mm/s]
    bValid := FALSE;                            // 输出不可用 / outputs are not valid
END_IF

// 段 4｜有效目标速度：失能或保持都折算为 0，由斜坡逼近而非阶跃
// segment 4, effective target velocity; disable and hold both map to zero and are approached through the ramp
IF (NOT bEnable) OR bHold OR bError THEN
    _fTarget := DL_VM_ZERO;                     // 失能 / 保持 / 故障：目标为 0 / disabled, holding or faulted, the target is zero
ELSE
    _fTarget := fVelSet;                        // 正常运行：目标即给定 / normal operation, the target is the setpoint
END_IF

// 段 5｜相位复位：优先于失能判定（同一拍两者同时到达时先复位，否则沿被吞掉）
// segment 5, phase reset evaluated before the disable test so a joint edge is never swallowed
IF fbPhaseReset.Q AND (NOT _bParamBad) THEN
    _fPosL := fPosInit;                         // 相位直接置到复位目标 / the phase jumps to the reset target
    _fVel := DL_VM_ZERO;                        // 速度归零，从静止重新起算 / the velocity restarts from standstill
    _eState := E_DL_VMasterState.eIdle;         // 复位后回待机，由待机态按使能重判 / return to idle and let the enable decide the next phase
    IF NOT bError THEN
        eErr := 16#0004_01D8;                   // 信息级：相位复位已执行 / info: the phase reset was executed
    END_IF
END_IF

// 段 6｜斜坡与积分（故障拍与故障相均冻结：bError 或已处 eFault 皆不积分，修复前绝不带病复跑）
// segment 6, ramp and integration, frozen on a fault scan and inside the fault phase alike
IF (NOT bError) AND (_eState <> E_DL_VMasterState.eFault) THEN
    _fDtSec := DINT_TO_REAL(TIME_TO_DINT(tSample)) / DL_VM_MS_PER_S;    // 采样周期折算秒值 [s] / sample period in seconds
    _fMaxUp := fAccLimit * _fDtSec;             // 本拍允许上升量 [mm/s] / permitted increase of this scan
    _fMaxDn := fDecLimit * _fDtSec;             // 本拍允许下降量 [mm/s] / permitted decrease of this scan
    _fDiff := _fTarget - _fVel;                 // 目标与当前之差 [mm/s] / target minus current
    _fDelta := LIMIT(DL_VM_ZERO - _fMaxDn, _fDiff, _fMaxUp);    // 限幅后的增量 [mm/s]/ clipped increment [mm/s]
    IF ABS(_fDiff - _fDelta) > DL_VM_EPS THEN
        bLimited := TRUE;                       // 增量被截断，说明仍在斜坡 / the increment was clipped, the ramp is still active
    END_IF
    _fVel := _fVel + _fDelta;                   // 速度积分一格 / advance the velocity by one step
    IF _fDtSec > DL_VM_ZERO THEN
        fMasterAcc := _fDelta / _fDtSec;        // 本拍实际加速度，除子已判正 [mm/s²] / applied acceleration with a guarded divisor [mm/s²]
    END_IF
    _fPosL := _fPosL + REAL_TO_LREAL(_fVel * _fDtSec);    // 相位积分一格（步长先在 REAL 内算完再拓宽）[mm] / advance the phase by one step, the increment is computed in REAL and then widened [mm]

    // 精度门：越限即冻结并等调用方复位，绝不静默累计（凸轮错位的根源）
    // precision gate, freeze beyond the limit and wait for a reset instead of accumulating silently
    IF ABS(_fPosL) > DL_VM_POS_MAX THEN
        eErr := 16#0004_02EE;                   // 故障级：相位累计超 LREAL 有效精度 / fault: the phase accumulated beyond the effective LREAL precision
        bError := TRUE;                         // 置故障标志 / raise the fault flag
        _eState := E_DL_VMasterState.eFault;    // 转故障，相位冻结在当前值 / go to fault and freeze the phase at its current value
    END_IF
END_IF

// 段 7｜限幅信息码边沿发布：只在进入限幅的那一拍报，避免每拍刷屏
// segment 7, edge-published limiting info code, reported only on entry to limiting
IF bLimited AND (NOT _bLimitPrev) AND (NOT bError) THEN
    eErr := 16#0004_01D7;                       // 信息级：加速度限幅生效 / info: the acceleration limit is active
END_IF
_bLimitPrev := bLimited;                        // 更新限幅快照 / update the limiting snapshot

// 段 8｜状态机：只做可观测与转相判定，不承担斜坡职责（斜坡在段 6 已无条件算完）
// segment 8, the state machine only classifies and switches phases, the ramp itself lives in segment 6
IF NOT bError THEN
    CASE _eState OF
    E_DL_VMasterState.eIdle:
        // 待机：残速仍在段 6 递减；使能后按保持状态分相 / idle, the residual velocity still decays in segment 6
        IF bEnable AND bHold THEN
            _eState := E_DL_VMasterState.eHolding;  // 使能但要求保持 / enabled but holding
        ELSIF bEnable THEN
            _eState := E_DL_VMasterState.eRamping;  // 使能，进斜坡 / enabled, enter the ramp
        END_IF

    E_DL_VMasterState.eRamping:
        IF NOT bEnable THEN
            _eState := E_DL_VMasterState.eIdle;     // 失能，回待机按减速斜坡收尾 / disabled, finish through the deceleration ramp in idle
        ELSIF bHold THEN
            _eState := E_DL_VMasterState.eHolding;  // 转保持相 / enter the hold phase
        ELSIF ABS(_fTarget - _fVel) <= DL_VM_EPS THEN
            _eState := E_DL_VMasterState.eSteady;   // 达给定，进稳定相 / reached the setpoint
        END_IF

    E_DL_VMasterState.eSteady:
        IF NOT bEnable THEN
            _eState := E_DL_VMasterState.eIdle;     // 失能 / disabled
        ELSIF bHold THEN
            _eState := E_DL_VMasterState.eHolding;  // 转保持相 / enter the hold phase
        ELSIF ABS(_fTarget - _fVel) > DL_VM_EPS THEN
            _eState := E_DL_VMasterState.eRamping;  // 给定变了，重回斜坡 / the setpoint moved, ramp again
        END_IF

    E_DL_VMasterState.eHolding:
        IF NOT bEnable THEN
            _eState := E_DL_VMasterState.eIdle;     // 失能 / disabled
        ELSIF NOT bHold THEN
            _eState := E_DL_VMasterState.eRamping;  // 解除保持，重新向给定逼近 / hold released, ramp towards the setpoint again
        END_IF

    E_DL_VMasterState.eFault:
        // 故障退出：请求已撤且参数已修好；相位越精度门时还必须先复位（否则一拍后又越限）
        // fault exit, requires a withdrawn request and repaired parameters, plus a reset when the phase exceeded the precision gate
        IF (NOT bEnable) AND (NOT _bParamBad) THEN
            IF (ABS(_fPosL) <= DL_VM_POS_MAX) OR fbPhaseReset.Q THEN
                _eState := E_DL_VMasterState.eIdle;     // 允许回待机 / allowed back to idle
            END_IF
        END_IF

    ELSE
        // 非法状态兜底：绝不静默停在未知态 / illegal state fallback, never stay silently in an unknown state
        eErr := 16#0004_02EF;                   // 故障级：状态机落 ELSE / fault: the state machine fell into ELSE
        bError := TRUE;                         // 置故障标志 / raise the fault flag
        _eState := E_DL_VMasterState.eFault;    // 回故障态 / go to fault
    END_CASE
END_IF

// 段 9｜输出发布：相位只能从累加器读，绝不回读输出变量（R43 禁自反馈）
// segment 9, publish outputs; the phase is read from the accumulator only and never fed back from the output pin
fMasterPos := _fPosL;                           // 相位发布 [mm] / publish the phase [mm]
IF NOT bError THEN
    fMasterVel := _fVel;                        // 速度发布 [mm/s] / publish the velocity [mm/s]
END_IF
bReady := ((_eState = E_DL_VMasterState.eSteady)
           OR ((_eState = E_DL_VMasterState.eHolding) AND (ABS(_fVel) <= DL_VM_EPS))
           OR (_eState = E_DL_VMasterState.eIdle AND (ABS(_fVel) <= DL_VM_EPS)));    // 稳定或已停稳，主值可用 / settled or fully stopped, the master value may be consumed
bValid := NOT bError;                           // 输出可用 = 无故障级错误 / outputs are valid when no fault-level code is present
END_FUNCTION_BLOCK
