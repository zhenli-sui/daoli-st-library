(*
    FB_DL_VacCupRingCtrl —— 多吸盘组分档拾放
    ------------------------------------------------------------------
    分类      : DL_Process / Handling
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 多吸盘拾放为公开搬运工程结构（成组吸附 → 确认 → 分组释放）；
                逐通道确认、少吸失败判据、分组释放相、降级放行、错误分级与码位 100% 自有；
                单个真空发生器仍归设备层（本件不内联真空发生器控制）；
                clean-room 重写，未复制任何闭源厂商源码
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R19）
    ------------------------------------------------------------------
    功能说明  : 一组（1~8 个）真空吸盘的拾放控制：逐通道吸附确认、吸盘数不足时判拾取
                失败（安全侧：少吸的料上轴会在加速时掉落）、可选降级放行（少吸但达最低
                要求）、分组释放（先外圈后内圈，防料被甩）。
                核心防御：① 吸盘数越界、最少需吸附数大于总数、真空门限非负或超物理可达——
                   三类参数错即故障级 0308 并撤销全部阀输出，绝不索引数组；
                ② 逐通道判据 = 到位开关闭合 **且** 真空度低于门限，两者同时成立才算到位
                   （只看开关会漏掉管路微漏，只看数值会被单点噪声骗过）；
                ③ 真空值非有限按「未到位」处理并置故障级 0309，绝不当成到位；
                ④ 确认时间到而到位数不足即锁存拾取失败，保持吸附（掉料比保持更危险）；
                ⑤ 降级放行必须显式允许（bAllowDegrade）且达到最低吸盘数；
                ⑥ 分组释放两相，相内不改吸附判据；⑦ CASE 含 ELSE 兜底回 eIdle 并撤阀。
                职责边界：真空发生器/喷射器的单机控制归设备层件，本件只做组级工艺编排。
    错误码    : 16#0005_01D8 降级放行（少吸但达最低要求）/ 拾取计数饱和——信息级，正常防御
                16#0005_01D9 预留禁用（信息级，不得挪用）
                16#0005_0308 吸盘数或真空门限参数非法——故障级，阀输出全部撤销
                16#0005_0309 吸附确认失败（到位数不足 / 真空值非有限 / 确认超时）——故障级，锁存并保持吸附
                16#0005_030A 状态机落 ELSE 兜底（非法状态）——故障级，回 eIdle 并撤销阀输出（用途固定，不得改作他用）
    码位总账  : 16#0005_01D8 用 / 16#0005_01D9 预留 ｜ 16#0005_0308 用 / 16#0005_0309 用 / 16#0005_030A 用
    状态机    : E_DL_VacRingState（eIdle / ePicking / eHolding / eReleasing / eDegraded / eFault）六态，
                CASE 含 ELSE 兜底，ELSE 回 eIdle 并撤销全部阀输出。
    采样约定  : fbTrigReset / fbTrigPick / fbTrigRelease 与 fbConfirm / fbSettle 五个实例在本体首部
                无条件刷新，绝不放入 IF 或 CASE（按段断输入是本族高危点）；
                释放两相各自计时：fbConfirm 覆盖「外圈已释放」，fbSettle 覆盖「内圈已释放」。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R19）
*)

(*
    枚举 : E_DL_VacRingState —— 吸盘组拾放状态（本文件为全库唯一属主）
*)
TYPE E_DL_VacRingState :
(
    eIdle      := 0,                          // 空闲：无吸附无动作 / idle, nothing held and no action
    ePicking   := 1,                          // 拾取中：等待吸附确认 / picking, waiting for the vacuum confirmation
    eHolding   := 2,                          // 保持中：全部吸盘确认到位 / holding, every cup confirmed
    eReleasing := 3,                          // 释放中：两相分组释放 / releasing, two phase grouped release
    eDegraded  := 4,                          // 降级保持：少吸但达最低要求 / degraded hold, fewer cups but above the minimum
    eFault     := 5                           // 故障：参数错或拾取失败 / fault, parameter error or pick failure
);
END_TYPE

FUNCTION_BLOCK FB_DL_VacCupRingCtrl
VAR_INPUT
    bEnable            : BOOL;                // 使能，FALSE 撤销所有阀输出 / enable, FALSE withdraws every valve output
    bReset             : BOOL;                // 复位，上升沿清故障与降级锁存 / reset, rising edge clears the faults and the degraded latch
    bCmdPick           : BOOL;                // 拾取命令（上升沿启动）/ pick command, rising edge starts it
    bCmdRelease        : BOOL;                // 释放命令（上升沿启动）/ release command, rising edge starts it
    auVacuumOk         : ARRAY[0..7] OF BOOL; // 各吸盘真空到位开关 / vacuum reached switch per cup
    afVacuum           : ARRAY[0..7] OF REAL; // 各吸盘真空度（负值）[kPa]，范围 -101.3~0.0 / vacuum level per cup, negative [kPa], range -101.3~0.0
    uCupCount          : UINT := 4;           // 有效吸盘数 [个]，范围 1~8 / valid cup count [cup], range 1~8
    uMinCupsRequired   : UINT := 4;           // 最少需吸附的吸盘数 [个]，范围 1~uCupCount / minimum cups to confirm [cup], range 1~uCupCount
    fVacMin            : REAL := -40.0;       // 真空度合格门限（负值，绝对值越大越紧）[kPa] / vacuum acceptance threshold, negative [kPa]
    tConfirmTime       : TIME := T#500MS;     // 吸附确认时间（亦作释放相时间）[ms]，范围 0~10000 / confirmation and release phase time [ms], range 0~10000
    bAllowDegrade      : BOOL := FALSE;       // TRUE = 允许少吸降级放行（须达最低要求）/ TRUE allows a degraded release above the minimum
    bReleaseOuterFirst : BOOL := TRUE;        // TRUE = 先释放偶数通道（视为外圈）/ TRUE releases the even channels first, treated as the outer ring
END_VAR
VAR_OUTPUT
    auValveOut         : ARRAY[0..7] OF BOOL; // 各吸盘真空阀输出（由上层映射到物理点）/ vacuum valve output per cup, mapped to physical points above
    bPicked            : BOOL;                // 已拾取（吸附确认通过）/ picked, the vacuum confirmation passed
    bReleased          : BOOL;                // 已释放完成 / released, the release finished
    uOkCups            : UINT;                // 当前确认到位的吸盘数 [个] / cups currently confirmed [cup]
    bDegraded          : BOOL;                // 降级运行中（少吸放行）/ running degraded with fewer cups
    bPickFailed        : BOOL;                // 拾取失败（锁存，需 bReset）/ pick failure, latched until reset
    uPickCount         : UDINT;               // 累计成功拾取次数，饱和 [次] / accumulated successful picks, saturating [times]
    eErr               : UDINT;               // 错误码，0=正常 / error id, 0=ok
    bError             : BOOL;               // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
END_VAR
VAR
    eState             : E_DL_VacRingState := eIdle; // 状态机当前态 / current state machine state
    fbTrigReset        : R_TRIG;              // 复位上升沿实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    fbTrigPick         : R_TRIG;              // 拾取命令沿实例，本体首部无条件刷新 / pick edge instance, refreshed unconditionally
    fbTrigRelease      : R_TRIG;              // 释放命令沿实例，本体首部无条件刷新 / release edge instance, refreshed unconditionally
    fbConfirm          : TON;                 // 吸附确认与释放第一相定时器，本体首部无条件刷新 / confirmation and first release phase timer, refreshed unconditionally
    fbSettle           : TON;                 // 释放第二相定时器，本体首部无条件刷新 / second release phase timer, refreshed unconditionally
    uIdx               : UINT;                // 通道扫描游标 [通道]，范围 0~7 / channel scan cursor [channel], range 0~7
    uOk                : UINT;                // 本拍到位的吸盘数 [个] / confirmed cups in this cycle [cup]
    uPhase             : UINT;                // 释放分组相号 [相]，0 = 外圈，1 = 内圈 / release phase index [phase], zero outer, one inner
    fVacMinEff         : REAL;                // 钳位后的真空门限 [kPa] / clamped vacuum threshold [kPa]
    bNonFinVac         : BOOL;                // 存在非有限真空值 / a non-finite vacuum value exists
    bGroupA            : BOOL;                // 本通道属于当前相要释放的分组 / this channel belongs to the group released in the current phase
    bInit              : BOOL := FALSE;       // 首扫标志，初值 FALSE，判据 NOT bInit / first-scan flag, initial FALSE, tested with NOT
    tConfirmEff        : TIME;                // 钳位后的确认时间（定时器 PT 前置收敛）[ms] / clamped confirmation time feeding the timers [ms]
END_VAR
VAR CONSTANT
    DL_VRC_CUP_MAX      : UINT := 8;          // 吸盘数上限 [个] / cup count upper bound [cup]
    DL_VRC_VAC_ABS_MAX  : REAL := 101.3;      // 真空物理上限（绝对值）[kPa] / absolute physical vacuum bound [kPa]
    DL_VRC_CNT_MAX      : UDINT := 16#FFFF_FFFE; // 拾取计数饱和值 [次] / pick counter saturation value [times]
    DL_VRC_DT_MAX       : TIME := T#10S;      // 确认时间上限 [ms] / confirmation time upper bound [ms]
    DL_FLOAT_EPS        : REAL := 1.0E-6;     // 浮点判等容差 [无量纲] / float equality tolerance [dimensionless]
    DL_VRC_INF_GUARD    : REAL := 1.0E38;     // 非有限幅值判定阈值 [无量纲] / non-finite magnitude guard [dimensionless]
    DL_VRC_TWO          : UINT := 2;          // 二值常量，内外圈分组用 [无量纲] / two constant used by the ring grouping
    DL_VRC_PHASE_ONE    : UINT := 1;          // 第二相相号 [相] / phase index of the second release
    DL_VRC_ZERO         : REAL := 0.0;        // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
    DL_VRC_CNT_ZERO     : UINT := 0;          // 无符号零常量 [无量纲] / unsigned zero constant [dimensionless]
END_VAR

// 段 1｜确认时间前置收敛（定时器 PT 的入参必须先合法）/ segment 1, clamp the confirmation time before the timers
tConfirmEff := tConfirmTime;                   // 取入参副本 / copy the input
IF tConfirmEff > DL_VRC_DT_MAX THEN
    tConfirmEff := DL_VRC_DT_MAX;              // 超上限钳到 10 s / clamp to ten seconds
END_IF
IF tConfirmEff < T#0S THEN
    tConfirmEff := T#0S;                       // 负时间无物理意义 / a negative time has no physical meaning
END_IF

// 段 2｜边沿与定时器实例无条件周期刷新（红线：严禁放入条件分支）/ segment 2, unconditional refresh
fbTrigReset(CLK := bReset);
fbTrigPick(CLK := bCmdPick);
fbTrigRelease(CLK := bCmdRelease);
fbConfirm(IN := (eState = ePicking) OR ((eState = eReleasing) AND (uPhase = DL_VRC_CNT_ZERO)), PT := tConfirmEff); // 拾取确认与释放第一相共用 / shared by the pick confirmation and the first release phase
fbSettle(IN := (eState = eReleasing) AND (uPhase >= DL_VRC_PHASE_ONE), PT := tConfirmEff);                          // 释放第二相计时 / times the second release phase

// 段 2｜输出与错误状态预置（bPicked / bPickFailed / uPickCount 为保持量）/ segment 2, preset outputs
eErr := 0;                                     // 预置无错误 / preset no error
bError := FALSE;                               // 预置无故障 / preset no fault
bReleased := FALSE;                            // 脉冲类标志先清 / clear the pulse style flags
uOkCups := DL_VRC_CNT_ZERO;                    // 到位数清零 / clear the confirmed cup count
uOk := DL_VRC_CNT_ZERO;                        // 到位数中间量清零 / clear the intermediate count
bNonFinVac := FALSE;                           // 预置无非有限真空值 / preset no non-finite vacuum
uPhase := DL_VRC_CNT_ZERO;                     // 相号复位 / reset the phase index
FOR uIdx := 0 TO DL_VRC_CUP_MAX - 1 DO
    auValveOut[uIdx] := FALSE;                 // 全部阀输出先撤销，再由状态逻辑按需置位 / clear every valve output, the state logic sets them again
END_FOR

// 段 3｜首扫初始化（唯一合法范式：初值 FALSE，判据 NOT bInit）/ segment 3, first-scan initialisation
IF NOT bInit THEN
    bPicked := FALSE;                          // 首扫未拾取 / not picked on the first scan
    bPickFailed := FALSE;                      // 首扫无拾取失败 / no pick failure on the first scan
    bDegraded := FALSE;                        // 首扫无降级 / not degraded on the first scan
    uPickCount := 0;                           // 拾取统计清零 / clear the pick statistics
    bInit := TRUE;                             // 首扫只做一次 / first scan runs once only
END_IF

// 段 4｜参数闸（三类参数错一律撤销阀输出，且绝不索引数组）/ segment 4, parameter gate
IF (uCupCount < 1) OR (uCupCount > DL_VRC_CUP_MAX) THEN
    eErr := 16#0005_0308;                      // 吸盘数越界故障码 / cup count out of range fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    eState := eFault;                          // 落故障态 / enter the fault state
    RETURN;                                   // 故障级提前返回，阀输出已全撤 / early return, the valve outputs are already cleared
END_IF
IF (uMinCupsRequired < 1) OR (uMinCupsRequired > uCupCount) THEN
    eErr := 16#0005_0308;                      // 最少吸附数矛盾故障码 / contradictory minimum cup count fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    eState := eFault;                          // 落故障态 / enter the fault state
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF
IF (fVacMin <> fVacMin) OR (fVacMin >= DL_VRC_ZERO) OR (ABS(fVacMin) > DL_VRC_VAC_ABS_MAX) THEN
    eErr := 16#0005_0308;                      // 真空门限非负或不可达故障码 / the vacuum threshold is non-negative or unreachable
    bError := TRUE;                            // 置故障标志 / raise the error flag
    eState := eFault;                          // 落故障态 / enter the fault state
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF

// 段 5｜真空门限域钳位（确认时间已在段 1 收敛）/ segment 5, threshold clamp, the confirmation time was clamped in segment 1
fVacMinEff := MAX(fVacMin, -DL_VRC_VAC_ABS_MAX); // 门限绝对值收敛到物理可达 [kPa] / converge the threshold into the physical range [kPa]

// 段 6｜使能闸：失能撤销所有阀输出 / segment 6, enable gate
IF NOT bEnable THEN
    eState := eIdle;                           // 回空闲态 / back to idle
    bPicked := FALSE;                          // 不计已拾取 / not picked
    bDegraded := FALSE;                        // 撤降级 / drop the degraded flag
    RETURN;                                   // 失能即出口，阀输出已全撤 / disabled is the exit, the outputs are already cleared
END_IF

// 段 7｜复位沿：清故障与降级锁存（不改变吸附状态）/ segment 7, reset clears the latches
IF fbTrigReset.Q THEN
    bPickFailed := FALSE;                      // 清拾取失败锁存 / clear the pick failure latch
    bDegraded := FALSE;                        // 清降级锁存 / clear the degraded latch
    bPicked := FALSE;                          // 清已拾取标志 / clear the picked flag
    IF eState = eFault THEN
        eState := eIdle;                       // 故障态由复位退出 / a reset leaves the fault state
    END_IF
END_IF

// 段 8｜逐通道吸附确认（到位开关与真空度必须同时成立）/ segment 8, per channel confirmation
FOR uIdx := 0 TO uCupCount - 1 DO
    IF (afVacuum[uIdx] <> afVacuum[uIdx]) OR (afVacuum[uIdx] > DL_VRC_INF_GUARD) OR (afVacuum[uIdx] < -DL_VRC_INF_GUARD) THEN
        bNonFinVac := TRUE;                    // 非有限真空值：按未到位处理，绝不当成到位 / a non-finite value counts as not confirmed, never as confirmed
    ELSIF auVacuumOk[uIdx] AND (afVacuum[uIdx] <= fVacMinEff) THEN
        uOk := uOk + 1;                        // 开关与数值同时成立才计入 / both the switch and the level must agree
    END_IF
END_FOR
uOkCups := uOk;                                // 发布到位吸盘数 [个] / publish the confirmed cup count [cup]

// 段 9｜状态机（含 ELSE 兜底）/ segment 9, state machine with ELSE fallback
CASE eState OF
    eIdle:
        bPicked := FALSE;                      // 空闲不计已拾取 / idle is not picked
        IF fbTrigPick.Q THEN
            eState := ePicking;                // 拾取沿进入拾取中 / a pick edge enters the picking state
        ELSIF fbTrigRelease.Q THEN
            uPhase := DL_VRC_CNT_ZERO;         // 释放从第一相开始 / the release starts in the first phase
            eState := eReleasing;              // 直接进入释放（空手释放用于清管）/ entering release with nothing held is allowed to purge
        END_IF

    ePicking:
        FOR uIdx := 0 TO uCupCount - 1 DO
            auValveOut[uIdx] := TRUE;          // 拾取相全部吸盘抽真空 / every cup is evacuated in the picking phase
        END_FOR
        IF bNonFinVac THEN
            eErr := 16#0005_0309;              // 真空值非有限故障码 / non-finite vacuum fault id
            bError := TRUE;                    // 置故障标志 / raise the error flag
            bPickFailed := TRUE;               // 锁存拾取失败 / latch the pick failure
            eState := eFault;                  // 落故障态（保持吸附，掉料更危险）/ the fault state keeps the vacuum, dropping the load is worse
        ELSIF uOk >= uCupCount THEN
            bPicked := TRUE;                   // 全部到位即拾取成功 / every cup confirmed means a successful pick
            IF uPickCount < DL_VRC_CNT_MAX THEN
                uPickCount := uPickCount + 1;  // 饱和累计拾取次数 / saturating pick counter
            END_IF
            eState := eHolding;                // 进入保持态 / enter the holding state
        ELSIF (uOk >= uMinCupsRequired) AND bAllowDegrade THEN
            bDegraded := TRUE;                  // 少吸但达最低要求且显式允许：降级放行 / fewer cups but above the minimum and explicitly allowed
            bPicked := TRUE;                    // 降级也算拾取（工艺已允许）/ a degraded pick still counts, the process allowed it
            eErr := 16#0005_01D8;               // 信息级：降级放行 / info level, released in a degraded mode
            eState := eDegraded;                // 进入降级保持态 / enter the degraded holding state
        ELSIF fbConfirm.Q THEN
            eErr := 16#0005_0309;               // 确认超时仍未到位故障码 / the confirmation timed out short of the minimum
            bError := TRUE;                     // 置故障标志 / raise the error flag
            bPickFailed := TRUE;                // 锁存拾取失败（安全侧：少吸的料上轴会掉落）/ latch the failure, carrying a partial load would drop it during acceleration
            eState := eFault;                   // 落故障态并保持吸附 / enter the fault state and keep the vacuum
        END_IF

    eHolding:
        FOR uIdx := 0 TO uCupCount - 1 DO
            auValveOut[uIdx] := TRUE;          // 保持相持续抽真空 / the holding phase keeps the vacuum
        END_FOR
        IF fbTrigRelease.Q THEN
            uPhase := DL_VRC_CNT_ZERO;         // 释放从第一相开始 / start with the first phase
            eState := eReleasing;              // 进入释放相 / enter the release phase
        END_IF

    eDegraded:
        FOR uIdx := 0 TO uCupCount - 1 DO
            auValveOut[uIdx] := TRUE;          // 降级保持同样保持真空 / the degraded hold keeps the vacuum as well
        END_FOR
        bDegraded := TRUE;                      // 持续发布降级标志 / keep publishing the degraded flag
        IF fbTrigRelease.Q THEN
            uPhase := DL_VRC_CNT_ZERO;         // 释放从第一相开始 / start with the first phase
            eState := eReleasing;              // 进入释放相 / enter the release phase
        END_IF

    eReleasing:
        // 段 10｜分组释放：第一相放外圈（偶数通道），第二相放内圈 / segment 10, two phase grouped release
        FOR uIdx := 0 TO uCupCount - 1 DO
            IF uPhase = DL_VRC_CNT_ZERO THEN
                IF bReleaseOuterFirst THEN
                    bGroupA := (uIdx MOD DL_VRC_TWO) = DL_VRC_CNT_ZERO; // 偶数通道为外圈 / the even channels form the outer ring
                ELSE
                    bGroupA := (uIdx MOD DL_VRC_TWO) <> DL_VRC_CNT_ZERO; // 奇数通道为外圈 / the odd channels form the outer ring
                END_IF
                auValveOut[uIdx] := NOT bGroupA; // 第一相只放外圈，其余继续抽真空 / only the outer ring is released in the first phase
            ELSE
                auValveOut[uIdx] := FALSE;      // 第二相全部释放 / everything is released in the second phase
            END_IF
        END_FOR
        IF (uPhase = DL_VRC_CNT_ZERO) AND fbConfirm.Q THEN
            uPhase := DL_VRC_PHASE_ONE;         // 第一相到时进入第二相 / the first phase elapses into the second
        ELSIF (uPhase >= DL_VRC_PHASE_ONE) AND fbSettle.Q THEN
            bReleased := TRUE;                  // 释放完成单周期脉冲 / the release completed, a single-cycle pulse
            bPicked := FALSE;                   // 清已拾取 / clear the picked flag
            bDegraded := FALSE;                 // 清降级 / clear the degraded flag
            uPhase := DL_VRC_CNT_ZERO;          // 相号复位 / reset the phase index
            eState := eIdle;                    // 回空闲态 / back to idle
        END_IF

    eFault:
        // 段 11｜故障态：参数错时阀已全撤；拾取失败时保持吸附 / segment 11, the fault state keeps the vacuum after a pick failure
        IF bPickFailed THEN
            FOR uIdx := 0 TO uCupCount - 1 DO
                auValveOut[uIdx] := auVacuumOk[uIdx]; // 保持已确认的通道，未确认的不再抽（避免持续漏气补压）/ keep the confirmed cups, stop evacuating those that never confirm
            END_FOR
        END_IF

ELSE
    eErr := 16#0005_030A;                       // 故障级：非法状态兜底（用途固定）/ fault level, illegal state fallback, the purpose is fixed
    bError := TRUE;                             // 置故障标志 / raise the error flag
    eState := eIdle;                            // 回空闲态 / fall back to idle
    FOR uIdx := 0 TO DL_VRC_CUP_MAX - 1 DO
        auValveOut[uIdx] := FALSE;              // 兜底时撤销全部阀输出 / withdraw every valve output on the fallback path
    END_FOR
END_CASE
END_FUNCTION_BLOCK
