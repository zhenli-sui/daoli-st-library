(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AxisDroopComp
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商方言
 * 功能描述 (Function)   : 轴跟随误差前馈补偿：按速度段从补偿表取增益，折算位置前置量
 *                         fCompOut [mm] = 速度段增益 [mm per mm/s] × 速度给定 [mm/s]，
 *                         并钳在 ±fCompMax；用于抵消伺服刚度不足造成的跟随下垂。
 * 分工互引 (Boundary)   : FB_DL_AxisFollowErrGuard 是**保护件**（跟随误差超限即停），
 *                         本件是**补偿件**（前置量注入位置环，不产生任何停止动作）；
 *                         两者互不替代，禁把保护判据写进本件。
 *                         FB_DL_AxisFrictionFf 补偿摩擦力方向项，本件只补偿速度相关下垂。
 * 边界与语义披露 (Boundary disclosure) :
 *   1) 补偿表 8 段定长（DL_AC_SEG），段边界按 |fVelCmd| 等分 fVelSegMax，
 *      符号由速度给定方向携带（段内取绝对值查表，输出乘回方向），故负速也有补偿。
 *   2) 组态域闸（R151 全枚举）：fVelSegMax <= 0、fCompMax < 0、表内任一元素非有限或
 *      为负（负增益会让补偿反向加剧下垂）均判组态非法，锁存至复位沿 + 组态改对。
 *   3) 速度给定非有限属运行时信号失效：本拍不输出补偿（fCompOut := 0，安全侧不注入
 *      错误前置量），置信息级码，**不锁存**（不因一扫 NaN 让补偿永久失效）。
 *   4) 输出饱和（|补偿| 被 fCompMax 钳住）为信息级：饱和本身不改变补偿符号。
 * 故障码表 (Error codes) :
 *   16#0004_03F0 [故障级] 组态非法（段宽 / 补偿上限 / 表元素），补偿置 0
 *                 反证：补偿置 0 与「速度恰好为 0」输出组合相同，无码不可区分。
 *   16#0004_03F2 [信息级] 速度给定非有限，本拍不注入补偿（保持 0）
 *                 反证：补偿 0 与「低速段增益为 0」输出相同，需码位区分信号失效。
 *   16#0004_03F3 [信息级] 补偿量被上限钳位（bSaturated 同源可查）
 *                 反证：钳位后补偿与前一段恰好相同，无码不可观测。
 * 码位总账 (Code ledger) : 16#0004_03F0 用 ｜ 16#0004_03F2 / 03F3 用
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量 ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 段索引钳位无越界 / 非有限三判 / 除子由域闸保证 > 0
 *                         R5 ✓ 全变量双语同行注释 ｜ R6 ✓ 三态 ENUM + ELSE 兜底
 *                         R7 ✓ 一沿实例主体最前部无条件刷新
 * 修订历史 (Revision)   : 2026-11-22  v1.0.0  首版入库（R69 构建轮 · 批 3 · N8）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_DroopState（归属 DL_Motion，与 FB_DL_AxisDroopComp 同文件）
 *----------------------------------------------------------------------------*)
TYPE E_DL_DroopState :
(
    eOff   := 0,      // 未使能：补偿恒 0 / Disabled, compensation is zero
    eRun   := 10,     // 补偿中：按速度段查表 / Compensating by speed segment
    eFault := 99      // 组态锁存：补偿恒 0 / Config latched, compensation forced to zero
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_AxisDroopComp
 * 调用约定: 每个扫描周期无条件调用一次。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_AxisDroopComp
VAR_INPUT
    fVelCmd    : REAL;                          // 速度给定 [mm/s] / velocity setpoint [mm/s]
    afSegGain  : ARRAY[0..7] OF REAL;           // 8 段补偿增益 [mm per mm/s]，必须 >= 0 / per-segment droop gain
    fVelSegMax : REAL := 1000.0;                // 补偿表覆盖的最高速度 [mm/s]，<= 0 组态非法 / table velocity span
    fCompMax   : REAL := 2.0;                   // 补偿量上限 [mm]，< 0 组态非法 / compensation magnitude ceiling [mm]
    bEnable    : BOOL := TRUE;                  // 使能 / enable
    bReset     : BOOL;                          // 上升沿：清组态锁存 / rising edge clears the config latch
END_VAR
VAR_OUTPUT
    fCompOut   : REAL;                          // 位置前置补偿量 [mm]（含速度方向符号）/ position feed-forward [mm]
    nSegIdx    : INT;                           // 命中补偿段号 [段]，0..7 / hit segment index
    bSaturated : BOOL;                          // 补偿量被上限钳位 / compensation clamped at the ceiling
    bVelValid  : BOOL;                          // 本拍速度给定有限 / velocity setpoint finite this scan
    bError     : BOOL;                          // 故障标志（组态锁存）/ fault flag
    uErrorId   : UDINT;                         // 故障码，0 = 无故障 / error code, 0 = none
    eState     : E_DL_DroopState;               // 当前状态（供 HMI 诊断）/ current state
END_VAR
VAR
    fbTrigReset : R_TRIG;                       // 复位沿检测实例 / reset edge detector
    eStateInt   : E_DL_DroopState;              // 主状态机内部当前态 / internal state
    fVelAbs     : REAL;                         // 速度绝对值 [mm/s]（查表用）/ absolute velocity for the lookup
    fSegSpan    : REAL;                         // 单段速度宽度 [mm/s]（除子，域闸保证 > 0）/ segment width, the divisor
    fGainEff    : REAL;                         // 命中段增益 [mm per mm/s] / hit segment gain
    fCompRaw    : REAL;                         // 未钳补偿量 [mm] / unclamped compensation
    nIdx        : INT;                          // 表遍历游标 [段] / table cursor
    bVelBad     : BOOL;                         // 速度给定非有限 / velocity non-finite
    bCfgBad     : BOOL;                         // 本拍组态非法 / config illegal this scan
    bCfgLatch   : BOOL;                         // 组态锁存（复位沿 + 组态改对解除）/ config latch
    bErrorInt   : BOOL;                         // 本拍故障置位累加 / fault set accumulator
    bFirstScan  : BOOL := TRUE;                 // 上电首扫标志 / first-scan flag
END_VAR
VAR CONSTANT
    DL_AC_SEG     : INT := 8;                   // 补偿表段数 [段]，与数组维度一致 / segment count
    DL_AC_FIN_LIM : REAL := 1.0E30;             // REAL 幅值兜底判界 / REAL magnitude bound
    DL_AC_NEG_EPS : REAL := 0.0;                // 增益负值判界（0 为合法端点）/ gain negativity bound, zero is legal
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：一沿实例位于主体最前部
 *      Unconditional refresh: the edge instance at the very top
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);

(* 段 2｜上电首扫：状态与输出落安全侧 / first-scan init *)
IF bFirstScan THEN
    eStateInt  := E_DL_DroopState.eOff;
    fCompOut   := 0.0;
    bFirstScan := FALSE;
END_IF

(* 段 3｜每拍预清（FB32-1）：单拍标志与派生量 / per-scan preset *)
bErrorInt  := FALSE;
bSaturated := FALSE;

(*------------------------------------------------------------------------------
 * 段 4｜组态域闸（R151 全枚举）：段宽 / 上限 / 表内 8 个元素逐一非有限与负值判
 *      Config gate over the span, the ceiling and every table element
 *      解除路径（R152 自证可达）：复位沿 AND 组态非法条件全部消失
 *-----------------------------------------------------------------------------*)
bCfgBad := (fVelSegMax <= 0.0) OR (fVelSegMax <> fVelSegMax)
           OR (fCompMax < 0.0) OR (fCompMax <> fCompMax);
FOR nIdx := 0 TO (DL_AC_SEG - 1) DO
    IF (afSegGain[nIdx] <> afSegGain[nIdx])
       OR ((afSegGain[nIdx] - afSegGain[nIdx]) <> (afSegGain[nIdx] - afSegGain[nIdx]))
       OR (ABS(afSegGain[nIdx]) >= DL_AC_FIN_LIM)
       OR (afSegGain[nIdx] < DL_AC_NEG_EPS) THEN
        bCfgBad := TRUE;                        // 表元素非法：任一项即整表不可信 / any bad element invalidates the table
    END_IF
END_FOR

IF bCfgBad THEN
    bCfgLatch := TRUE;
END_IF
IF fbTrigReset.Q AND (NOT bCfgBad) THEN
    bCfgLatch := FALSE;                         // 组态锁存解除 / config latch cleared
    uErrorId  := 16#0000_0000;                  // 码位随解除归零 / code cleared with the latch
END_IF
IF bCfgLatch THEN
    uErrorId  := 16#0004_03F0;                  // 故障级：组态非法 / fault: illegal configuration
    bErrorInt := TRUE;                          // R45 配对 / paired with the code
    eStateInt := E_DL_DroopState.eFault;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *-----------------------------------------------------------------------------*)
CASE eStateInt OF

    E_DL_DroopState.eOff:
        IF bEnable AND (NOT bCfgLatch) THEN
            eStateInt := E_DL_DroopState.eRun;
        END_IF

    E_DL_DroopState.eRun:
        IF (NOT bEnable) OR bCfgLatch THEN
            eStateInt := E_DL_DroopState.eOff;
        END_IF

    E_DL_DroopState.eFault:
        IF fbTrigReset.Q AND (NOT bCfgBad) THEN
            bCfgLatch := FALSE;
            uErrorId  := 16#0000_0000;
            eStateInt := E_DL_DroopState.eOff;
        END_IF

    ELSE
        (* 非法状态拦截 / illegal state interception *)
        eStateInt := E_DL_DroopState.eFault;
        uErrorId  := 16#0004_03F0;
        bErrorInt := TRUE;

END_CASE;

(*------------------------------------------------------------------------------
 * 段 6｜速度段查表与补偿折算
 *      Segment lookup and the compensation folding
 *-----------------------------------------------------------------------------*)
bVelBad  := (fVelCmd <> fVelCmd)
            OR ((fVelCmd - fVelCmd) <> (fVelCmd - fVelCmd))
            OR (ABS(fVelCmd) >= DL_AC_FIN_LIM);
bVelValid := (NOT bVelBad) AND (NOT bCfgLatch);
fCompOut  := 0.0;                               // 缺省不注入（安全侧）/ default no injection
nSegIdx   := 0;
fGainEff  := 0.0;

IF bVelValid AND bEnable AND (eStateInt = E_DL_DroopState.eRun) THEN
    IF fVelCmd >= 0.0 THEN
        fVelAbs := fVelCmd;                     // 正方向 [mm/s] / positive direction
    ELSE
        fVelAbs := -fVelCmd;                    // 取绝对值查表（符号在出口乘回）[mm/s] / absolute value for the lookup
    END_IF
    fSegSpan := fVelSegMax / INT_TO_REAL(DL_AC_SEG);                 // 单段宽（除子为常数 8 > 0）[mm/s] / segment width
    IF fVelAbs > fVelSegMax THEN
        fVelAbs := fVelSegMax;                  // 实数域先钳制再转整型（R151 防方向翻转）/ clamp in the real domain before the cast
    END_IF
    nSegIdx  := REAL_TO_INT(fVelAbs / fSegSpan);                     // 段号（除子 > 0 且已钳制）/ segment index after clamping
    IF nSegIdx >= DL_AC_SEG THEN
        nSegIdx := DL_AC_SEG - 1;               // 超表按末段钳位（禁越界访问）/ clamp to the last segment
    ELSIF nSegIdx < 0 THEN
        nSegIdx := 0;                           // 负段号防御，结构性不可达 / negative guard, unreachable
    END_IF
    fGainEff := afSegGain[nSegIdx];             // 命中段增益 [mm per mm/s] / hit gain
    fCompRaw := fGainEff * fVelCmd;             // 未钳补偿（含方向符号）[mm] / raw compensation with direction
    IF fCompRaw > fCompMax THEN
        fCompOut   := fCompMax;                 // 正向饱和 [mm] / saturated high
        bSaturated := TRUE;
        uErrorId   := 16#0004_03F3;             // 信息级：补偿被钳位 / info: compensation clamped
    ELSIF fCompRaw < -fCompMax THEN
        fCompOut   := -fCompMax;                // 负向饱和 [mm] / saturated low
        bSaturated := TRUE;
        uErrorId   := 16#0004_03F3;             // 信息级：补偿被钳位 / info: compensation clamped
    ELSE
        fCompOut   := fCompRaw;                 // 域内直通 [mm] / in-domain pass-through
    END_IF
ELSIF bVelBad THEN
    uErrorId := 16#0004_03F2;                   // 信息级：速度非有限，不注入（不锁存）/ info: non-finite velocity
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜输出单一出口（范式 P-05）
 *      Single output exit
 *-----------------------------------------------------------------------------*)
bError := bErrorInt OR bCfgLatch;
eState := eStateInt;
END_FUNCTION_BLOCK
