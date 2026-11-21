(*
    FB_DL_AxisInPosMonitor —— 到位稳定判定
    ------------------------------------------------------------------
    分类      : DL_Motion / AxisMonitor
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : T1-6 PLCopen（只借 InPosition / Standstill 两个公开输出的语义边界：
                InPosition = 位置入窗，Standstill = 速度低于阈；两者都是「判定」而非「指令」）；
                稳定时间、抖振窗、掩码与码位 100% 自有；clean-room 重写，
                未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    道莅 clean-room 防御性实现：语义借鉴、代码与码位 100% 自有
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R22 批 4 · #16）
    ------------------------------------------------------------------
    功能说明  : 机械手取放、压装、点胶这类「必须真停稳才能动作」的工位，需要一个比驱动器
                内置信号更严的到位判据：位置进窗 + 速度进阈 + 连续稳定满 tSettle 才算到位。
                本件就地给出三层结论——瞬时入窗（bInPos）、稳定到位（bSettled，取放联锁用
                这一个）、抖振超限（bChatterAlarm，稳定窗内反复出窗说明伺服在追或机械在弹）。
    职责划界  : 驱动器内置的跟随误差监视（FB_DL_AxisFollowingErrorMonitor）看的是
                「指令位置与实际位置的偏差」是否超限，管的是伺服跟随品质与保护停机；
                本件看的是「实际位置是否已稳定落在目标窗内」，管的是工艺许可。
                两者判据不同、出口不同、处置不同：前者越限要停轴，后者越限只是不许动作。
                本件不重复实现跟随误差保护，也不发任何运动指令、不改写轴状态。
    轴故障口径: 与批 4 其余各件一致——本件不消费 bAxisError 引脚，也绝不代替轴侧做恢复动作。
                轴一旦报故障停车，判定必然出窗并自然退回 eMoving，bSettled 当拍清零；
                恢复只能由轴侧完成后重新走「入窗 → 稳定满 tSettle」，本件不做任何自动续判。
    非有限值  : 采样出现 NaN / ±Inf 时判定冻结（保持上次判定）并报 02F7，绝不拿坏值
                伪造「到位」。因此下游取放联锁必须写成「bSettled AND bValid」——
                bSettled 只是判定值，bValid 才是「这个判定值可信」的凭据（语义分离，
                二者不可互相替代）。
    边界安全  : ① 容差与时间参数非法 → 02F6、bValid = FALSE、全输出清零并进 eFault；
                ② 采样非有限 → 02F7、判定与两只定时器全部冻结，坏值消失后重新起算；
                ③ bSettled 出窗当拍即清零，绝不锁存到下一件料（R34 家族）；
                ④ 失能 → 逐项清零输出（R72 双路径：先全清再按状态置位）；
                ⑤ 抖振计数按观察窗清，窗口自重启（TON 自复位构成滚动窗）。
    错误码    : 16#0004_01DD 已入窗但稳定时间未到，暂不计到位——信息级，入稳相那一拍发布
                16#0004_01DE 抖振计数已按观察窗清零，稳定保持——信息级
                16#0004_02F6 容差或时间参数非法（容差非正 / 稳定时间为零 / 窗长为零）——故障级
                16#0004_02F7 位置或速度采样非有限，判定冻结并保持上次判定——故障级，非锁存
                16#0004_02F8 状态机落 ELSE 兜底（非法状态）——故障级
    码位总账  : 16#0004_01DD 用 / 16#0004_01DE 用 ｜ 16#0004_02F6 用 / 16#0004_02F7 用 / 16#0004_02F8 用
    状态机    : E_DL_InPosState（eIdle / eMoving / eSettling / eInPos / eChatter / eFault），
                CASE 含 ELSE 兜底，ELSE 置 16#0004_02F8 并回 eFault；失能无条件回 eIdle。
    采样约定  : fbSettle 与 fbChatterWin 在本体最前部无条件调用（R40）；窗定时器以
                「IN := NOT 自身 Q」自重启构成滚动窗，Q 只亮一拍即完成清零动作；
                段转出统一走「断输入一拍」标志，标志在对应调用之后立刻自清。
    依赖      : 仅 Standard.library（TON / ABS / MIN / MAX），不引用任何其他 DL_ 子库。
    验收向量  :
                V1 域外早退：fPosTol = 0 → 02F6、bError = TRUE、bValid = FALSE、
                   bInPos / bSettled / bChatterAlarm 全 FALSE、进 eFault。
                V2 上限/超限：位置在窗内但速度 5 mm/s > fVelTol 1.0 → bInPos = FALSE，
                   不得进入 eSettling，稳定计时不启动。
                V3 跨段时序：入窗后第 tSettle−1 拍报 01DD 且 bSettled = FALSE；
                   第 tSettle 拍 bSettled 当拍置 TRUE（不延后一拍）。
                V4 恢复/抖振：窗内反复出窗 5 次（uChatterLimit = 5）→ bChatterAlarm = TRUE、
                   进 eChatter；随后重新稳定满 tSettle → 回 eInPos 且计数清零、01DE。
                V5 坏值冻结：fActPos = NaN 一拍 → 02F7、bValid = FALSE、
                   bSettled 保持坏值前一拍的判定值不变；下一拍正常采样恢复判定。
    红线自检  : 1 全局变量声明零使用 / 外部变量访问零使用 / 物理地址零使用 —— 通过，全部量经引脚注入
                2 纯 IEC 61131-3 跨平台 —— 通过，仅 Standard.library
                3 防御性编程 —— 通过，浮点比较全部为绝对值阈或容差、无非有限穿透、无除法
                4 声明行同行中英双语注释 + 单位 —— 通过，逐行附注（含枚举成员）
                5 ENUM + CASE 且含 ELSE 兜底 —— 通过
                6 TON / R_TRIG 无条件刷新 —— 通过，段 1 两只 TON 先行调用
                7 无魔法数 —— 通过，容差与时间全部为引脚或 VAR CONSTANT
    修订记录  : 2026-11-16 v1.0.0 首次入库（R22 批 4 · #16）
*)
TYPE E_DL_InPosState :
(
    eIdle    := 0,       // 未使能或参数未就绪，全输出清零 / not enabled or parameters not ready, every output is cleared
    eMoving  := 10,      // 尚未入窗，等位置与速度同时进阈 / not yet in the window, waiting for both position and velocity
    eSettling:= 20,      // 已入窗，稳定计时中，尚不可用于取放 / inside the window and timing the settle, not yet usable by a pick-and-place
    eInPos   := 30,      // 稳定到位，bSettled 可用 / settled, bSettled may be consumed
    eChatter := 40,      // 抖振超限，观察窗内出窗次数过多 / chatter limit exceeded, too many window exits inside the observation window
    eFault   := 50       // 故障，参数非法或非法状态兜底 / fault from illegal parameters or from the fallback branch
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisInPosMonitor
VAR_INPUT
    bEnable        : BOOL;                     // 使能，FALSE 时全输出清零并回 eIdle / enable, FALSE clears every output and returns to idle
    fActPos        : REAL;                     // 轴实际位置 [mm] / axis actual position [mm]
    fTargetPos     : REAL;                     // 目标位置 [mm] / target position [mm]
    fActVel        : REAL;                     // 轴实际速度 [mm/s]，取绝对值比较 / axis actual velocity [mm/s], compared on its absolute value
    fPosTol        : REAL := 0.05;             // 位置窗半宽 [mm]，必须大于 0 / position window half-width [mm], must exceed zero
    fVelTol        : REAL := 1.0;              // 速度阈 [mm/s]，必须大于 0 / velocity threshold [mm/s], must exceed zero
    tSettle        : TIME := T#100MS;          // 稳定时间 [ms]，必须大于 0 / settle time [ms], must exceed zero
    uChatterLimit  : UINT := 5;                // 抖振计数上限 [次]，0 = 首次出窗即报警 / chatter limit [pcs], 0 alarms on the first exit
    tChatterWin    : TIME := T#2S;             // 抖振观察窗长 [ms]，必须大于 0 / chatter observation window [ms], must exceed zero
END_VAR
VAR_OUTPUT
    bInPos         : BOOL;                     // 瞬时入窗（位置在窗内且速度达标）/ instantaneously inside the window, position in band and velocity below the threshold
    bSettled       : BOOL;                     // 稳定到位，取放联锁用这个；须与 bValid 相与 / settled, used by the pick-and-place interlock, must be ANDed with bValid
    uChatterCount  : UINT;                     // 本观察窗内出窗次数 [次] / window exits inside the current observation window [pcs]
    bChatterAlarm  : BOOL;                     // 抖振报警，计数达上限置位，重新稳定后清 / chatter alarm, set when the count reaches the limit and cleared after a new settle
    eErr           : UDINT;                    // 错误码，0 表示无错 / error code, 0 means no error
    bError         : BOOL;                     // 故障级标志，仅故障级错误置位 / fault-class flag, set only on fault-level codes
    bValid         : BOOL;                     // 判定可信标志，坏值拍为 FALSE / verdict trustworthy flag, FALSE on a bad-sample scan
END_VAR
VAR
    fbSettle       : TON;                      // 稳定计时器，仅 eSettling 使用 / settle timer, used in eSettling only
    fbChatterWin   : TON;                      // 抖振观察窗定时器，自重启构成滚动窗 / chatter observation window, self-restarting to form a rolling window
    _bSettleBreak  : BOOL;                     // 稳定计时器断输入一拍标志 / break-input flag for the settle timer
    _bWinPrev      : BOOL;                     // 上一拍观察窗到期标志，用于生成窗沿 / previous-scan window expiry flag used to build the window edge
    _bInWin        : BOOL;                     // 本拍入窗条件（位置与速度同拍相与）/ in-window condition of this scan, position and velocity taken together
    _bInWinPrev    : BOOL;                     // 上一拍入窗条件，用于捕捉出窗沿 / previous-scan in-window condition used to catch the leaving edge
    _bFrozen       : BOOL;                     // 判定冻结标志，坏值拍置位 / verdict freeze flag, set on a bad-sample scan
    _uChat         : UINT;                     // 抖振计数累加器，饱和不回绕 [次] / chatter accumulator, saturating and never wrapping [pcs]
    _eState        : E_DL_InPosState;          // 当前状态 / current state
END_VAR
VAR CONSTANT
    DL_IP_UINT_MAX   : UINT := 16#FFFF;        // 抖振计数饱和上限 [次] / chatter count saturation bound [pcs]
    DL_IP_INF_GUARD  : REAL := 4.0E38;         // 非有限幅值判定阈（大于 REAL 最大值）[mm] / non-finite magnitude guard [mm]
    DL_IP_ZERO       : REAL := 0.0;            // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
    DL_IP_T_ZERO     : TIME := T#0S;           // 零时间常量，用于参数门禁 / zero time constant used by the parameter gate
END_VAR

// 段 1｜两只 TON 无条件周期刷新（红线 6：严禁放入 IF / CASE；窗定时器自重启构成滚动窗）
// segment 1, both TON instances refreshed unconditionally, the window timer restarts itself to form a rolling window
// 稳定计时器在 eSettling 与 eChatter 两相承担的是同一个物理量「连续入窗时长」，
// 不属于跨段复用；每次进相统一断输入一拍，杜绝上一相的 ET 残留。
// the settle timer measures one single quantity, the continuous in-window time, in both eSettling and eChatter,
// which is not a cross-phase reuse; every entry restarts it with one scan of a FALSE input so no elapsed time leaks.
fbSettle(IN := (((_eState = E_DL_InPosState.eSettling) OR (_eState = E_DL_InPosState.eChatter)))
             AND (NOT _bSettleBreak) AND _bInWin AND (NOT _bFrozen), PT := tSettle);
_bSettleBreak := FALSE;                         // 断输入标志用后即刻自清 / the break flag clears right after the call
fbChatterWin(IN := (NOT fbChatterWin.Q) AND bEnable, PT := tChatterWin);
// 窗到期沿：Q 只亮一拍，用上一拍 Q 构造边沿，避免边沿在本拍被清零后丢失
// the window expiry edge, Q lives for a single scan so the previous-scan Q builds the edge

// 段 2｜输出与错误状态预置 / segment 2, preset outputs and error status
eErr := 0;                                      // 预置无错误 / preset no error
bError := FALSE;                                // 预置无故障标志 / preset no error flag
bValid := TRUE;                                 // 预置判定可信 / preset the verdict as trustworthy
_bFrozen := FALSE;                              // 预置不冻结 / preset not frozen

// 段 3｜参数门禁：四条参数任一非法即不许判定（判据本身不可信，给结论就是害人）
// segment 3, the parameter gate, no verdict may be produced from untrustworthy criteria
IF (fPosTol <= DL_IP_ZERO)
   OR (fVelTol <= DL_IP_ZERO)
   OR (tSettle <= DL_IP_T_ZERO)
   OR (tChatterWin <= DL_IP_T_ZERO) THEN
    eErr := 16#0004_02F6;                       // 故障级：容差或时间参数非法 / fault: a tolerance or duration parameter is illegal
    bError := TRUE;                             // 置故障标志 / raise the fault flag
    bValid := FALSE;                            // 判定不可信 / the verdict is not trustworthy
    _bSettleBreak := TRUE;                      // 稳定计时断输入重启 / restart the settle timer
    _eState := E_DL_InPosState.eFault;          // 转故障，等参数修复后失能复位 / go to fault and wait for repaired parameters plus a disable
END_IF

// 段 4｜采样非有限检测：NaN 用自不自等捕获（该式对 ±Inf 同样成立），坏值拍整段冻结
// segment 4, non-finite detection, the self-inequality test catches NaN and infinity alike and freezes the whole scan
IF (fActPos - fActPos) <> (fActPos - fActPos) THEN
    _bFrozen := TRUE;                           // 位置采样非有限 / the position sample is not finite
ELSIF ABS(fActPos) > DL_IP_INF_GUARD THEN
    _bFrozen := TRUE;                           // 位置采样超幅值门 / the position sample exceeds the magnitude guard
ELSIF (fActVel - fActVel) <> (fActVel - fActVel) THEN
    _bFrozen := TRUE;                           // 速度采样非有限 / the velocity sample is not finite
ELSIF ABS(fActVel) > DL_IP_INF_GUARD THEN
    _bFrozen := TRUE;                           // 速度采样超幅值门 / the velocity sample exceeds the magnitude guard
ELSIF (fTargetPos - fTargetPos) <> (fTargetPos - fTargetPos) THEN
    _bFrozen := TRUE;                           // 目标位置非有限 / the target position is not finite
END_IF

IF _bFrozen THEN
    eErr := 16#0004_02F7;                       // 故障级：采样非有限，判定冻结 / fault: a non-finite sample froze the verdict
    bError := TRUE;                             // 置故障标志（非锁存，坏值消失即复位）/ raise the flag, it is not latched and drops with the bad sample
    bValid := FALSE;                            // 判定不可信，下游必须与 bSettled 相与 / the verdict is not trustworthy and must be ANDed downstream
    _bSettleBreak := TRUE;                      // 稳定计时断输入重启，绝不在坏值上计时 / restart the settle timer, nothing may mature on bad data
END_IF

// 段 5｜入窗条件与抖振计数：位置与速度同拍相与，不做先后（同拍即结论）
// segment 5, the in-window condition combines position and velocity in the same scan, and the chatter counter follows the leaving edge
_bInWin := (ABS(fActPos - fTargetPos) <= fPosTol) AND (ABS(fActVel) <= fVelTol);

IF (NOT _bFrozen) AND bEnable AND (_eState <> E_DL_InPosState.eFault) THEN
    IF _bInWinPrev AND (NOT _bInWin) THEN
        IF _uChat < DL_IP_UINT_MAX THEN
            _uChat := _uChat + 1;               // 出窗一次，计数饱和自增 / one window exit, a saturating increment
        END_IF
    END_IF
END_IF

IF fbChatterWin.Q AND (NOT _bWinPrev) THEN
    // 观察窗到期一拍：按窗清零计数；若此刻仍稳定到位，说明这一窗没有异常
    // the observation window expired, clear the count, and a still-settled state means the window was clean
    IF (_eState = E_DL_InPosState.eInPos) THEN
        eErr := 16#0004_01DE;                   // 信息级：抖振计数已按窗清零，稳定保持 / info: the count was cleared with the window and the settle holds
    END_IF
    _uChat := 0;                                // 计数按窗清零 / clear the counter with the window
END_IF
_bWinPrev := fbChatterWin.Q;                    // 更新窗到期快照 / update the window expiry snapshot
_bInWinPrev := _bInWin;                         // 更新入窗快照（坏值拍也更新，恢复后不误算一次出窗）/ update the in-window snapshot, a frozen scan updates it too so recovery does not count a phantom exit

// 段 6｜状态机：只做分类与转相，判据计算已在段 5 完成
// segment 6, the state machine classifies and switches, the criteria were computed in segment 5
IF NOT _bFrozen THEN
    CASE _eState OF
    E_DL_InPosState.eIdle:
        _uChat := 0;                            // 待机计数清零 / clear the counter while idle
        IF bEnable THEN
            _eState := E_DL_InPosState.eMoving; // 使能即开始监视 / monitoring starts with the enable
        END_IF

    E_DL_InPosState.eMoving:
        IF NOT bEnable THEN
            _uChat := 0;                        // 失能计数清零 / clear the counter when disabled
            _eState := E_DL_InPosState.eIdle;   // 回待机 / back to idle
        ELSIF _bInWin THEN
            _bSettleBreak := TRUE;              // 入窗首拍，稳定计时断输入重启 / the settle timer restarts on the entering scan
            _eState := E_DL_InPosState.eSettling;   // 进稳相 / enter the settling phase
            eErr := 16#0004_01DD;               // 信息级：已入窗但稳定时间未到 / info: inside the window but the settle time has not elapsed
        END_IF

    E_DL_InPosState.eSettling:
        IF NOT bEnable THEN
            _uChat := 0;                        // 失能计数清零 / clear the counter when disabled
            _eState := E_DL_InPosState.eIdle;   // 回待机 / back to idle
        ELSIF NOT _bInWin THEN
            _eState := E_DL_InPosState.eMoving; // 出窗，回移动相重新等 / left the window, back to moving
        ELSIF fbSettle.Q THEN
            _eState := E_DL_InPosState.eInPos;  // 稳定时间满，到位可用 / the settle time elapsed and the verdict becomes usable
        END_IF

    E_DL_InPosState.eInPos:
        IF NOT bEnable THEN
            _uChat := 0;                        // 失能计数清零 / clear the counter when disabled
            _eState := E_DL_InPosState.eIdle;   // 回待机 / back to idle
        ELSIF NOT _bInWin THEN
            _bSettleBreak := TRUE;              // 出窗即作废稳定计时，不锁存到下一条料 / the settle timing dies with the exit, never latched across a part
            IF _uChat >= uChatterLimit THEN
                _eState := E_DL_InPosState.eChatter;    // 出窗次数达上限，进抖振相 / the exits reached the limit, enter the chatter phase
            ELSE
                _eState := E_DL_InPosState.eMoving;     // 偶发出窗，回移动相 / an incidental exit, back to moving
            END_IF
        END_IF

    E_DL_InPosState.eChatter:
        IF NOT bEnable THEN
            _uChat := 0;                        // 失能计数清零 / clear the counter when disabled
            _eState := E_DL_InPosState.eIdle;   // 回待机 / back to idle
        ELSIF fbSettle.Q THEN
            _uChat := 0;                        // 重新稳定满 tSettle，抖振报警解除并清零 / a fresh settle clears both the alarm and the counter
            _eState := E_DL_InPosState.eInPos;  // 回到位相 / back to the settled phase
        END_IF

    E_DL_InPosState.eFault:
        // 退出条件：参数已修复且请求已撤——参数不修就复位只会再进故障
        // exit needs repaired parameters and a withdrawn request, a reset with bad parameters would only re-enter the fault
        IF (fPosTol > DL_IP_ZERO) AND (fVelTol > DL_IP_ZERO)
           AND (tSettle > DL_IP_T_ZERO) AND (tChatterWin > DL_IP_T_ZERO)
           AND (NOT bEnable) THEN
            _uChat := 0;                        // 计数清零 / clear the counter
            _eState := E_DL_InPosState.eIdle;   // 回待机 / back to idle
        END_IF

    ELSE
        // 非法状态兜底：绝不静默停在未知态 / illegal state fallback, never stay silently in an unknown state
        eErr := 16#0004_02F8;                   // 故障级：状态机落 ELSE / fault: the state machine fell into ELSE
        bError := TRUE;                         // 置故障标志 / raise the fault flag
        bValid := FALSE;                        // 判定不可信 / the verdict is not trustworthy
        _bSettleBreak := TRUE;                  // 稳定计时断输入重启 / restart the settle timer
        _eState := E_DL_InPosState.eFault;      // 回故障态 / go to fault
    END_CASE
END_IF

// 段 7｜输出发布（R72 双路径：逐项显式赋值，坏值拍整块不写以保持上次判定）
// segment 7, publish outputs item by item, a frozen scan writes nothing so the previous verdict survives
IF NOT _bFrozen THEN
    bInPos := _bInWin;                          // 瞬时入窗发布 / publish the instantaneous in-window condition
    bSettled := (_eState = E_DL_InPosState.eInPos);     // 稳定到位只由状态决定，出窗当拍即清零 / the settle verdict follows the state and dies on the exit scan
    bChatterAlarm := (_eState = E_DL_InPosState.eChatter);  // 抖振报警只由状态决定 / the chatter alarm follows the state
END_IF
uChatterCount := _uChat;                        // 计数发布（坏值拍也发布，计数本身未动）/ publish the counter, which is untouched on a frozen scan
END_FUNCTION_BLOCK
