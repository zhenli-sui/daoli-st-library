(*
    FB_DL_DowntimeClassifier —— 停机原因自动分类
    ------------------------------------------------------------------
    分类      : DL_Process / Oee
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : T2-7 PackML / OMAC（只借「停机原因 / 未计划停机归因」的公开语义分类，
                不做 17 态全集——全集唯一属主是 FB_DL_PackMlStateMachine）；
                时长口径、计数口径、仲裁与码位 100% 自有；clean-room 重写，
                未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R18）
    ------------------------------------------------------------------
    功能说明  : 设备停转时自动抓取「哪个原因源先动」，给出停机原因序号与停机时长；
                同拍多源按序号最小仲裁（索引最小即优先级最高），超时未归类标未分类；
                三道防御：时间参数自相矛盾闸（最短时长大于归类等待上限即统计不可信）
                → 时长累加前先钳位（TIME 加法溢出在三平台行为不同，必须先比后加）
                → 计数饱和闸（UDINT 回绕会让台账出现天文数字）；
                结算纪律：只在停机结束那一拍累加时长与次数，停机中累加会重复计数；
                职责边界：刻意不做 OEE 三因子，该职责唯一属主是 FB_DL_OeeCalculator，
                避免两套统计口径打架。
    错误码    : 16#0005_01D2 同拍多源停机，已按源序号最小仲裁——信息级，不置故障
                16#0005_01D3 预留禁用（信息级，不得挪用）
                16#0005_02FF 停机超归类等待上限仍无原因源，判未分类（需人工补录）——故障级，需人工介入
                16#0005_0300 时间参数自相矛盾（归类上限小于最短时长或不为正）——故障级，统计冻结
                16#0005_0301 状态机落 ELSE 兜底（非法状态，回空闲）——故障级，回安全态
    码位总账  : 16#0005_01D2 用 / 16#0005_01D3 预留 ｜ 16#0005_02FF 用 / 16#0005_0300 用 / 16#0005_0301 用
    状态机    : E_DL_DowntimeState（eIdle / eStopped / eClassifying / eFault），
                CASE 含 ELSE 兜底，兜底固定置 eFault 与 0301
    采样约定  : 两个 TON 与三个 R_TRIG 在本体首部无条件调用；tMinDuration 与
                tMaxClassify 由工艺给定，改动后需一次复位使统计口径重新起算。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R18）
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_DowntimeState（归属本功能块，与其同文件发布）
 * 含义: 停机归因状态机离散态，步长 10 留空位，故障态取 99 排末位
 *----------------------------------------------------------------------------*)
TYPE E_DL_DowntimeState :
(
    eIdle        := 0,   // 空闲：设备运行中，无停机在统计 / Idle, the machine runs and no downtime is being tracked
    eStopped     := 10,  // 停机中：尚未达到最短停机时长，随时可能被过滤 / Stopped, the minimum duration is not reached yet and may still be filtered out
    eClassifying := 20,  // 归类中：已超最短时长，等待原因源或归类上限 / Classifying, past the minimum duration, waiting for a cause or the classify limit
    eFault       := 99   // 故障：参数矛盾或非法状态，统计冻结 / Fault, contradictory parameters or an illegal state, statistics frozen
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_DowntimeClassifier
VAR_INPUT
    bEnable          : BOOL;                   // 使能，FALSE 冻结统计（不清已累计值）/ enable, FALSE freezes the statistics without clearing them
    bReset           : BOOL;                   // 上升沿清累计与当前停机 / rising edge clears the totals and the current downtime
    bMachineRunning  : BOOL := FALSE;          // 设备运行信号，FALSE 且持续超最短时长即判停机 / machine running signal, FALSE beyond the minimum duration counts as downtime
    aStopCause       : ARRAY[0..7] OF BOOL;    // 8 路停机原因源，索引即优先级 0 最高 / 8 stop cause sources, the index is the priority, 0 highest
    tMinDuration     : TIME := T#5S;           // 最短停机时长，短于此不计入 [ms]，范围 100~600000 / minimum downtime filtered out below it [ms], range 100~600000
    tMaxClassify     : TIME := T#120S;         // 归类等待上限，超过仍无源即未分类 [ms] / classify wait limit, no source beyond it means unclassified [ms]
END_VAR
VAR_OUTPUT
    bDowntime     : BOOL;                      // 当前处于停机且已计时 / currently stopped and being timed
    tDownElapsed  : TIME;                      // 本次停机已持续时长 [ms] / elapsed time of the current downtime [ms]
    uActiveCause  : UINT;                      // 当前原因序号 0~7，16#FFFF = 未知 / current cause index 0~7, 16#FFFF = unknown
    uLastCause    : UINT;                      // 上次停机最终归因 / final cause of the previous downtime
    bUnclassified : BOOL;                      // 本次停机未归类（超上限或无源）/ the current downtime is unclassified
    auCauseCount  : ARRAY[0..7] OF UDINT;      // 各原因累计次数，饱和计数 [次] / accumulated count per cause, saturating [times]
    auCauseTime   : ARRAY[0..7] OF TIME;       // 各原因累计停机时长，饱和累加 [ms] / accumulated downtime per cause, saturating [ms]
    eErr          : UDINT;                     // 错误码，0=正常 / error id, 0=ok
    bError        : BOOL;                      // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
END_VAR
VAR
    fbTrigReset  : R_TRIG;                     // 复位沿检测实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    fbTrigRunOff : R_TRIG;                     // 运行信号下降沿实例 / running signal falling edge instance
    fbTrigRunOn  : R_TRIG;                     // 运行信号上升沿实例 / running signal rising edge instance
    fbMinDown    : TON;                        // 停机时长定时器，本体首部无条件刷新 / downtime duration timer, refreshed unconditionally
    fbClassify   : TON;                        // 归类等待定时器，本体首部无条件刷新 / classify wait timer, refreshed unconditionally
    eState       : E_DL_DowntimeState := E_DL_DowntimeState.eIdle; // 内部状态机步序 / internal state machine step
    uIdx         : UINT;                       // 原因源扫描游标 [路] / cause scan cursor [ch]
    uActCnt      : UINT;                       // 本拍有效原因源计数 [路] / active cause count this cycle [ch]
    bAnyCause    : BOOL;                       // 本拍存在原因源标志 / any cause active this cycle
    uFirstFound  : UINT;                       // 本拍首个为真的原因序号 / first active cause index this cycle
    uCauseCur    : UINT;                       // 本次停机已锁定的原因序号 / cause index locked for the current downtime
    tAccum       : TIME;                       // 单次停机时长累加中间量 [ms] / single downtime accumulation intermediate [ms]
    tClamped     : TIME;                       // 钳位中间量 [ms] / clamping intermediate [ms]
    bInit        : BOOL := FALSE;              // 首扫标志，初值 FALSE，判据 NOT bInit / first-scan flag, initial FALSE, tested with NOT
    bParamBad    : BOOL;                       // 时间参数矛盾标志 / contradictory time parameter flag
END_VAR
VAR CONSTANT
    DL_DTC_SRC_MAX  : UINT := 8;               // 原因源上限 [路] / cause source upper bound [ch]
    DL_DTC_NONE     : UINT := 16#FFFF;         // 未知原因哨兵 [无量纲] / unknown cause sentinel [dimensionless]
    DL_DTC_TIME_MAX : TIME := T#24H;           // 单次停机时长饱和值，防累加溢出 [ms] / single downtime saturation value against accumulation overflow [ms]
    DL_DTC_MAX_LOOP : UINT := 8;               // 循环守卫上限 [次] / loop guard upper limit [times]
    DL_DTC_MIN_DUR  : TIME := T#100MS;         // 最短停机时长下限 [ms] / minimum downtime lower bound [ms]
    DL_DTC_CNT_MAX  : UDINT := 16#FFFF_FFFE;   // 计数饱和值 [次] / count saturation value [times]
END_VAR

// 段 0｜输出与错误状态预置 / segment 0, preset outputs and error status
eErr := 0;                                     // 预置无错误 / preset no error
bError := FALSE;                               // 预置无故障 / preset no fault
bDowntime := FALSE;                            // 预置非停机 / preset not stopped
bUnclassified := FALSE;                        // 预置未判未分类 / preset not unclassified
bParamBad := FALSE;                            // 预置参数合法 / preset parameters valid
uActCnt := 0;                                  // 原因计数清零 / clear the cause count
bAnyCause := FALSE;                            // 原因标志清零 / clear the cause flag
uFirstFound := DL_DTC_NONE;                    // 首个原因先置哨兵 / the first cause starts at the sentinel

// 段 1｜时间参数闸：自相矛盾即统计不可信，冻结 / segment 1, contradictory time parameters freeze the statistics
IF (tMinDuration < DL_DTC_MIN_DUR) OR (tMaxClassify < tMinDuration) THEN
    eErr := 16#0005_0300;                      // 时间参数矛盾故障码 / contradictory time parameter fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    bParamBad := TRUE;                         // 记参数非法 / remember the illegal parameter
END_IF

// 段 2｜首扫初始化（初值 FALSE，判据 NOT bInit）/ segment 2, first-scan initialisation
IF NOT bInit THEN
    uLastCause := DL_DTC_NONE;                 // 上次归因先置哨兵 / previous cause starts at the sentinel
    uCauseCur := DL_DTC_NONE;                  // 本次原因先置哨兵 / current cause starts at the sentinel
    eState := E_DL_DowntimeState.eIdle;        // 首扫落空闲态 / start in the idle state
    bInit := TRUE;                             // 首扫只做一次 / first scan runs once only
END_IF

// 段 3｜边沿实例无条件周期刷新（红线：严禁放入条件分支）/ segment 3, unconditional edge refresh
fbTrigReset(CLK := bReset);
fbTrigRunOff(CLK := bMachineRunning);
fbTrigRunOn(CLK := bMachineRunning);

// 段 4｜原因仲裁扫描：单遍取首个为真者，索引最小即优先级最高 / segment 4, cause arbitration in a single pass
FOR uIdx := 0 TO DL_DTC_SRC_MAX - 1 DO
    IF aStopCause[uIdx] THEN
        uActCnt := uActCnt + 1;                // 有效原因计数 / count the active cause
        IF (uFirstFound = DL_DTC_NONE) THEN
            uFirstFound := uIdx;               // 只记首个，后续不覆盖 / record the first only, later ones never overwrite
        END_IF
    END_IF
END_FOR
IF uActCnt > 0 THEN
    bAnyCause := TRUE;                         // 至少一路原因动作 / at least one cause is active
END_IF
IF uActCnt > 1 THEN
    eErr := 16#0005_01D2;                      // 同拍多源提示（信息级不置故障）/ multiple sources hint, info level never raises a fault
END_IF

// 段 5｜两个定时器无条件调用，IN 引脚承载全部条件 / segment 5, both timers called unconditionally, the IN pins carry every condition
fbMinDown(IN := bEnable AND (NOT bParamBad) AND (NOT bMachineRunning), PT := tMinDuration);
fbClassify(IN := bEnable AND (NOT bParamBad) AND (NOT bMachineRunning) AND (NOT bAnyCause), PT := tMaxClassify);

// 段 6｜复位沿：清累计与当前停机 / segment 6, reset clears the totals and the current downtime
IF fbTrigReset.Q THEN
    FOR uIdx := 0 TO DL_DTC_SRC_MAX - 1 DO
        auCauseCount[uIdx] := 0;               // 次数清零 / clear the count
        auCauseTime[uIdx] := T#0MS;            // 时长清零 / clear the duration
    END_FOR
    uLastCause := DL_DTC_NONE;                 // 归因清零 / clear the last cause
    uCauseCur := DL_DTC_NONE;                  // 当前原因清零 / clear the current cause
    bUnclassified := FALSE;                    // 清未分类标志 / clear the unclassified flag
    eState := E_DL_DowntimeState.eIdle;        // 回空闲态 / back to idle
END_IF

// 段 7｜使能闸：冻结统计但不改已累计值 / segment 7, enable gate freezes without clearing
IF NOT bEnable THEN
    tDownElapsed := fbMinDown.ET;              // 时长照常回读 / the elapsed time stays readable
    RETURN;                                    // 失能即出口 / disabled is the exit
END_IF

// 段 8｜参数矛盾闸：统计冻结并转故障态 / segment 8, contradictory parameter gate
IF bParamBad THEN
    eState := E_DL_DowntimeState.eFault;       // 转故障态 / enter the fault state
    tDownElapsed := T#0MS;                     // 时长归零，不给出不可信数字 / zero the duration, never publish an untrustworthy figure
    RETURN;                                    // 故障级提前返回 / early return on fault
END_IF

// 段 9｜状态机主体（CASE 必含 ELSE 兜底，红线）/ segment 9, state machine body
CASE eState OF
    E_DL_DowntimeState.eIdle :
        bDowntime := FALSE;                    // 运行中不算停机 / running is not downtime
        tDownElapsed := T#0MS;                 // 时长归零 / clear the duration
        IF fbTrigRunOff.Q THEN
            uCauseCur := DL_DTC_NONE;          // 新一次停机，原因先清 / a new downtime clears the cause
            bUnclassified := FALSE;            // 清未分类标志 / clear the unclassified flag
            eState := E_DL_DowntimeState.eStopped; // 进停机观察态 / enter the stopped observation state
        END_IF
    E_DL_DowntimeState.eStopped :
        bDowntime := TRUE;                     // 已停机 / the machine is stopped
        tDownElapsed := fbMinDown.ET;          // 时长为未满最短时长前的实际值 / the duration below the minimum threshold
        IF bAnyCause AND (uCauseCur = DL_DTC_NONE) THEN
            uCauseCur := uFirstFound;          // 锁定首个原因 / lock the first cause
        END_IF
        IF fbMinDown.Q THEN
            eState := E_DL_DowntimeState.eClassifying; // 达最短时长，进归类态 / past the minimum duration, start classifying
        END_IF
        IF fbTrigRunOn.Q THEN
            eState := E_DL_DowntimeState.eIdle; // 短停机被过滤，不计入 / a short stop is filtered out
            uCauseCur := DL_DTC_NONE;          // 清原因 / clear the cause
        END_IF
    E_DL_DowntimeState.eClassifying :
        bDowntime := TRUE;                     // 仍在停机 / still stopped
        tDownElapsed := fbMinDown.ET;          // 实时时长 / live duration
        IF bAnyCause AND (uCauseCur = DL_DTC_NONE) THEN
            uCauseCur := uFirstFound;          // 迟到原因同样锁定 / a late cause is locked the same way
        END_IF
        IF fbClassify.Q AND (uCauseCur = DL_DTC_NONE) THEN
            bUnclassified := TRUE;             // 超归类上限仍无源 / no source beyond the classify limit
            eErr := 16#0005_02FF;              // 未分类故障码，需人工补录 / unclassified fault id, manual entry required
            bError := TRUE;                    // 置故障标志 / raise the error flag
        END_IF
        IF fbTrigRunOn.Q THEN
            uLastCause := uCauseCur;           // 停机结束拍写最终归因 / write the final cause on the closing cycle
            IF uCauseCur <> DL_DTC_NONE THEN
                uIdx := uCauseCur;             // 索引来自仲裁结果，必在 0~7 内 / the index comes from the arbitration, always inside 0~7
                IF auCauseCount[uIdx] < DL_DTC_CNT_MAX THEN
                    auCauseCount[uIdx] := auCauseCount[uIdx] + 1; // 饱和计数 / saturating count
                END_IF
                tAccum := fbMinDown.ET;        // 本次时长 / this downtime duration
                IF tAccum > DL_DTC_TIME_MAX THEN
                    tAccum := DL_DTC_TIME_MAX; // 先钳后加 / clamp before adding
                END_IF
                tClamped := auCauseTime[uIdx] + tAccum; // 加法在钳位之后 / the addition happens after the clamp
                IF tClamped > DL_DTC_TIME_MAX THEN
                    tClamped := DL_DTC_TIME_MAX; // 累计值同样钳位 / clamp the accumulated value too
                END_IF
                auCauseTime[uIdx] := tClamped; // 落盘累计时长 / commit the accumulated duration
            ELSE
                bUnclassified := TRUE;         // 无原因即未分类 / no cause means unclassified
                eErr := 16#0005_02FF;          // 未分类故障码 / unclassified fault id
                bError := TRUE;                // 置故障标志 / raise the error flag
            END_IF
            uCauseCur := DL_DTC_NONE;          // 本次归因已结算，清工作变量 / the settle finished, clear the working value
            eState := E_DL_DowntimeState.eIdle; // 回空闲态 / back to idle
        END_IF
    E_DL_DowntimeState.eFault :
        bDowntime := FALSE;                    // 故障态不统计 / no statistics in the fault state
        tDownElapsed := T#0MS;                 // 时长归零 / clear the duration
ELSE
    eState := E_DL_DowntimeState.eFault;       // 非法状态一律回安全态 / any illegal state falls back to the safe state
    eErr := 16#0005_0301;                      // 兜底故障码 / fallback fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    bDowntime := FALSE;                        // 不宣称停机 / never claim a downtime
END_CASE

// 段 10｜对外镜像 / segment 10, publish the mirrors
uActiveCause := uCauseCur;                     // 当前原因镜像 / current cause mirror
END_FUNCTION_BLOCK
