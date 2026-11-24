(*
    FB_DL_GainScheduler —— 分段增益调度
    ------------------------------------------------------------------
    分类      : DL_Algo / Control
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : T2-5 Mod_PID（只借「参数域约束」的组织方式；源矩阵判定其参数域已取尽，
                仅剩「分段 / 手自动」这类手册细节，本件即分段这一侧的收口件）；
                迟滞判据、状态化输出、码位与分级 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R18）
    ------------------------------------------------------------------
    功能说明  : 按调度变量（温度 / 流量 / 负载率）落在哪个断点区间，输出该段的一组
                Kp / Ki / Kd，解决「升温段要大 P、保温段要强 I」的分段整定需求；
                核心防御是边界迟滞：升段要越过「断点 + 迟滞半宽」，降段要跌破
                「断点 - 迟滞半宽」，杜绝边界抖动导致增益每拍来回跳；
                复位沿优先于定位，断点表严格递增在校验层一次性拦截；
                职责边界：本件只输出增益，不实现积分，也不做无扰切换——无扰由
                FB_DL_BumplessTransfer 与 PID 侧承担，避免与级联 PID 抢职责。
    错误码    : 16#0002_2301 调度变量非有限或变化被迟滞带抑制（保持当前段）——信息级，不置故障
                16#0002_2302 预留禁用（信息级，不得挪用）
                16#0002_2310 断点表非严格递增（非法组态）——故障级，输出保持末次并置故障
                16#0002_2311 段数越界（不在 2~4）——故障级，输出全 0 且不索引数组
                16#0002_2312 预留禁用（故障级，不得挪用）
    码位总账  : 16#0002_2301 用 / 16#0002_2302 预留 ｜ 16#0002_2310 用 / 16#0002_2311 用 / 16#0002_2312 预留
    状态机    : 无 CASE，段号由 uSeg 一个整数承载，非法状态由段数闸拦截，不可能出现
    采样约定  : fbTrigReset 在本体首部无条件刷新；本件无时间量，切换判定与任务周期无关，
                bSwitched 为单周期脉冲（每拍先清后置）。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R18）
*)
FUNCTION_BLOCK FB_DL_GainScheduler
VAR_INPUT
    bEnable       : BOOL;                      // 使能，FALSE 输出保持末次并冻结段号 / enable, FALSE holds the last gains and freezes the segment
    bReset        : BOOL;                      // 复位，上升沿强制回到段 0 并清切换沿 / reset, rising edge forces segment zero and clears the switch pulse
    fScheduleVar  : REAL := 0.0;               // 调度变量（如温度）[用户单位] / scheduling variable such as temperature [user unit]
    afBreakpoint  : ARRAY[0..3] OF REAL;       // 分段上界断点，有效项 0~uSegCount-2，必须严格递增 [用户单位] / segment upper breakpoints, valid items 0~uSegCount-2, strictly increasing [user unit]
    afKp          : ARRAY[0..3] OF REAL;       // 各段比例增益 [无量纲] / proportional gain per segment [dimensionless]
    afKi          : ARRAY[0..3] OF REAL;       // 各段积分增益 [1/s] / integral gain per segment [1/s]
    afKd          : ARRAY[0..3] OF REAL;       // 各段微分增益 [s] / derivative gain per segment [s]
    uSegCount     : UINT := 2;                 // 段数 [段]，范围 2~4 / segment count [seg], range 2~4
    fHysteresis   : REAL := 0.5;               // 段边界迟滞带半宽 [用户单位]，范围 0.0~100.0，0 = 无迟滞 / half width of the boundary hysteresis band [user unit], range 0.0~100.0, 0 = none
END_VAR
VAR_OUTPUT
    fKp         : REAL;                        // 当前段比例增益 [无量纲] / proportional gain of the active segment [dimensionless]
    fKi         : REAL;                        // 当前段积分增益 [1/s] / integral gain of the active segment [1/s]
    fKd         : REAL;                        // 当前段微分增益 [s] / derivative gain of the active segment [s]
    uActiveSeg  : UINT;                        // 当前段号 0~3 [段] / active segment index 0~3 [seg]
    bSwitched   : BOOL;                        // 段切换单周期脉冲 / single-cycle segment switch pulse
    uSwitchCnt  : UDINT;                       // 累计切换次数，抖动监视用，饱和计数 [次] / accumulated switch count for chatter monitoring, saturating [times]
    eErr        : UDINT;                       // 错误码，0=正常 / error id, 0=ok
    bError      : BOOL;                        // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
END_VAR
VAR
    fbTrigReset : R_TRIG;                      // 复位沿检测实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    bInit       : BOOL := FALSE;               // 首扫标志，初值 FALSE，判据 NOT bInit / first-scan flag, initial FALSE, tested with NOT
    uSeg        : UINT;                        // 内部当前段号 [段] / internal active segment index [seg]
    uIdx        : UINT;                        // 断点遍历游标 [段] / breakpoint traversal cursor [seg]
    fHystEff    : REAL;                        // 生效迟滞半宽，钳位后使用 [用户单位] / effective hysteresis half width after clamping [user unit]
    bNonFin     : BOOL;                        // 调度变量非有限判定标志 / scheduling variable non-finite flag
    uSegLast    : UINT;                        // 上一拍段号，用于切换沿判定 [段] / previous cycle segment index for the switch edge [seg]
END_VAR
VAR CONSTANT
    DL_GS_SEG_MAX     : UINT := 4;             // 段数上限 [段] / segment count upper bound [seg]
    DL_GS_SEG_MIN     : UINT := 2;             // 段数下限 [段] / segment count lower bound [seg]
    DL_GS_LAST_IDX    : UINT := 3;             // 增益数组末索引 [段] / last gain array index [seg]
    DL_GS_HYST_MAX    : REAL := 100.0;         // 迟滞半宽上限 [用户单位] / hysteresis half width upper bound [user unit]
    DL_FLOAT_EPS      : REAL := 1.0E-6;        // 浮点判等容差 [用户单位] / float equality tolerance [user unit]
    DL_GS_INF_GUARD   : REAL := 4.0E38;        // 非有限幅值判定阈值 [用户单位] / non-finite magnitude guard [user unit]
    DL_GS_CNT_MAX     : UDINT := 16#FFFF_FFFE; // 切换计数饱和值 [次] / switch counter saturation value [times]
    DL_GS_ZERO        : REAL := 0.0;           // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
END_VAR

// 段 1｜边沿实例无条件周期刷新（红线：严禁放入条件分支）/ segment 1, unconditional edge refresh
fbTrigReset(CLK := bReset);

// 段 2｜输出与错误状态预置：bSwitched 每拍先清后置 / segment 2, preset outputs and error status
bSwitched := FALSE;                            // 单拍脉冲先清 / clear the single-cycle pulse first
eErr := 0;                                     // 预置无错误 / preset no error
bError := FALSE;                               // 预置无故障 / preset no fault

// 段 3｜首扫初始化（初值 FALSE，判据 NOT bInit）/ segment 3, first-scan initialisation
IF NOT bInit THEN
    uSeg := 0;                                 // 首扫落段 0 / start in segment zero
    uSegLast := 0;                             // 切换沿比较基准清零 / clear the switch edge reference
    uSwitchCnt := 0;                           // 切换计数清零 / clear the switch counter
    bInit := TRUE;                             // 首扫只做一次 / first scan runs once only
END_IF

// 段 4｜使能闸：失能保持末次增益并冻结段号 / segment 4, enable gate holds the last gains
IF NOT bEnable THEN
    uActiveSeg := uSeg;                        // 段号镜像保持 / keep the mirrored segment index
    RETURN;                                    // 失能即出口 / disabled is the exit
END_IF

// 段 5｜段数闸：越界即输出全 0 且不索引数组 / segment 5, segment count gate
IF (uSegCount < DL_GS_SEG_MIN) OR (uSegCount > DL_GS_SEG_MAX) THEN
    eErr := 16#0002_2311;                      // 段数越界故障码 / segment count out of range fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    fKp := DL_GS_ZERO;                         // 输出全 0 / zero all gains
    fKi := DL_GS_ZERO;                         // 输出全 0 / zero the integral gain
    fKd := DL_GS_ZERO;                         // 输出全 0 / zero the derivative gain
    uActiveSeg := 0;                           // 段号回 0 / segment index back to zero
    RETURN;                                    // 故障级提前返回 / early return on fault
END_IF

// 段 6｜断点严格递增校验（浮点用大于号，禁用判等）/ segment 6, strict monotonic breakpoint check
FOR uIdx := 1 TO uSegCount - 2 DO
    IF NOT (afBreakpoint[uIdx] > afBreakpoint[uIdx - 1]) THEN
        eErr := 16#0002_2310;                  // 断点非法故障码 / illegal breakpoint fault id
        bError := TRUE;                        // 置故障标志 / raise the error flag
        uActiveSeg := uSeg;                    // 段号保持，输出保持末次 / keep the segment and the last gains
        RETURN;                                // 故障级提前返回 / early return on fault
    END_IF
END_FOR

// 段 7｜迟滞半宽双向钳位（负值视为无迟滞，超上限钳位）/ segment 7, hysteresis half width clamp
fHystEff := MIN(MAX(fHysteresis, DL_GS_ZERO), DL_GS_HYST_MAX); // 双侧钳位 / clamp both sides

// 段 8｜段号上界保护：段表缩短后旧段号可能越界 / segment 8, segment index upper bound protection
IF uSeg > (uSegCount - 1) THEN
    uSeg := uSegCount - 1;                     // 钳到最高段 / clamp to the highest segment
END_IF

// 段 9｜复位沿优先于定位 / segment 9, reset edge has priority over locating
IF fbTrigReset.Q THEN
    uSeg := 0;                                 // 强制回段 0 / force back to segment zero
END_IF

// 段 10｜迟滞定位：一次调用最多跨一段，跨多段交给后续拍 / segment 10, hysteresis locating, one step per cycle
bNonFin := (fScheduleVar <> fScheduleVar)
        OR (fScheduleVar > DL_GS_INF_GUARD)
        OR (fScheduleVar < -DL_GS_INF_GUARD);   // 非有限判定 / non-finite check
IF bNonFin THEN
    eErr := 16#0002_2301;                      // 非有限保持当前段（信息级不置故障）/ non-finite keeps the current segment, info level never raises a fault
ELSIF (NOT fbTrigReset.Q) THEN
    IF (uSeg < (uSegCount - 1)) AND (fScheduleVar > (afBreakpoint[uSeg] + fHystEff)) THEN
        uSeg := uSeg + 1;                      // 升段：必须越过断点加迟滞 / step up only beyond the breakpoint plus hysteresis
    ELSIF (uSeg > 0) AND (fScheduleVar < (afBreakpoint[uSeg - 1] - fHystEff)) THEN
        uSeg := uSeg - 1;                      // 降段：必须跌破断点减迟滞 / step down only below the breakpoint minus hysteresis
    END_IF
END_IF

// 段 11｜切换沿与抖动计数：段号变化才产生单拍脉冲 / segment 11, switch edge and chatter counting
IF uSeg <> uSegLast THEN
    bSwitched := TRUE;                         // 段号变化即置单拍脉冲 / raise the single-cycle pulse on any change
    IF uSwitchCnt < DL_GS_CNT_MAX THEN
        uSwitchCnt := uSwitchCnt + 1;          // 饱和加一，绝不回绕 / saturating increment, never wraps
    END_IF
END_IF
uSegLast := uSeg;                              // 记录本拍段号供下一拍比较 / remember this cycle segment for the next comparison

// 段 12｜增益输出：段号已由段 8 与段 5 双重保证在合法区间 / segment 12, publish the gains
fKp := afKp[uSeg];                             // 段号不超过 3，索引安全 / the segment index never exceeds three, indexing is safe
fKi := afKi[uSeg];                             // 积分增益取本段表值 / integral gain from the active segment row
fKd := afKd[uSeg];                             // 微分增益取本段表值 / derivative gain from the active segment row
uActiveSeg := uSeg;                            // 对外镜像段号 / publish the segment index
END_FUNCTION_BLOCK
