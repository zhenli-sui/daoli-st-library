// =====================================================================
// FB_DL_AhuFilterDpBank.st
// 空调箱 4 段过滤器压差四级分档（迟滞 + 各段独立去抖 + 低风量冻结）
// AHU 4-stage filter dP grading with per-stage debounce and hysteresis
// 所属子库: DL_Device    版本: v1.0.0    兼容: CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 码位: 16#0003_03D9 ~ 16#0003_03DD (本件独占 5 槽, 勿复用)
// 溯源: 道莅 clean-room 防御性实现
//       来源组标签: hvac, filter-monitoring, dp-grading, hysteresis, debounce
// 枚举属主: E_DL_FilterStage —— 本文件为全库唯一属主, 其他件只引用不重声明
// 修改记录: R30 初版 (ROUND_PLAN_R30 序 1, 由 R29 隔离底稿返修入册)
//           返修要点: 共享单实例去抖定时器改为 4 温区独立实例数组 aTonDeb,
//           每扫描周期无条件刷新全部 4 个 TON 实例, 候选作废显式复位;
//           任一区间切换去抖期间其他区间计时不被复位/冻结(验收点);
//           码位由作废段 03C5~03C9 重排为实测游标新段 03D9~03DD
// =====================================================================
// ---------------------------------------------------------------------
// 枚举定义: E_DL_FilterStage (全库唯一属主, 其他件只引用不重声明)
// ---------------------------------------------------------------------
TYPE E_DL_FilterStage :
(
    eClean,         // 洁净档 / Clean stage
    eEarly,         // 初堵档 / Early clog stage
    eMid,           // 中堵档 / Mid clog stage
    eChange,        // 更换档 / Change stage
    eSensorFault    // 传感器故障档 / Sensor fault stage
);
END_TYPE

FUNCTION_BLOCK FB_DL_AhuFilterDpBank
VAR_INPUT
    bEnable        : BOOL  := FALSE;   // 使能 / Enable
    afDp_Pa        : ARRAY[1..4] OF REAL;   // 各段压差 0~2000 Pa / Stage dP [Pa]
    afDpEarly_Pa   : ARRAY[1..4] OF REAL;   // 各段初堵阈值 10~500 Pa / Early clog threshold [Pa]
    afDpChange_Pa  : ARRAY[1..4] OF REAL;   // 各段更换阈值 20~1000 Pa / Change threshold [Pa]
    fHyst_Pa       : REAL  := 10.0;    // 迟滞回差 0~100 Pa / Hysteresis band [Pa]
    fDpMax_Pa      : REAL  := 1500.0;  // 传感器量程上限 >0 Pa / Sensor range limit [Pa]
    fFanPct        : REAL  := 0.0;     // 风机输出 0~100 百分比 / Fan duty [pct]
    fFanMinPct     : REAL  := 20.0;    // 判定最低风量 0~100 百分比 / Min fan duty for judging [pct]
    tDebounce      : TIME  := T#5S;    // 去抖时长 T#100MS~T#120S / Debounce duration [s]
END_VAR
VAR_OUTPUT
    aeStage        : ARRAY[1..4] OF E_DL_FilterStage;  // 各段档位 / Stage level per section
    auMaxStage     : USINT := 0;       // 全箱最高档 0~3 / Max stage of bank 0..3
    bChangeReq     : BOOL := FALSE;    // 更换请求 / Filter change required
    bFrozen        : BOOL := FALSE;    // 低风量冻结标志 / Frozen by low airflow
    eErr           : UDINT := 16#0003_03D9;  // 错误码 / Error code
END_VAR
VAR
    aTonDeb        : ARRAY[1..4] OF TON;   // 各段独立去抖定时器, 每拍无条件刷新 / Per-stage debounce timers, refreshed every cycle
    aPendStage     : ARRAY[1..4] OF E_DL_FilterStage;  // 各段候选档位 / Pending stage per section
    aPendActive    : ARRAY[1..4] OF BOOL;  // 各段候选有效标记 / Pending active flag per section
    eAbtCode       : UDINT := 16#0003_03D9;  // 本拍守卫闸中止码 / Abort code of this cycle
    bAbort         : BOOL := FALSE;    // 守卫闸中止标记 / Gate abort flag
    bSensorFlt     : BOOL := FALSE;    // 任一段传感器故障标记 / Any-stage sensor fault flag
    uZi            : INT   := 1;       // 1..4 数组下标 / Array subscript 1..4
    eTarget        : E_DL_FilterStage := E_DL_FilterStage.eClean;  // 本拍目标档 / Target stage this cycle
    uMaxTmp        : USINT := 0;       // 最高档临时量 / Max stage temporary
    tDebS          : REAL  := 0.0;     // 去抖秒值 / Debounce seconds [s]
    xFirstScan     : BOOL  := TRUE;    // 首扫标记 / First-scan flag
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占, 勿复用）:
//   16#0003_03D9 信息 分档正常
//   16#0003_03DA 故障 去抖时长非法或任一标量/数组输入非有限（本拍冻结保持, 非锁存, 恢复合法输入即解除）
//   16#0003_03DB 故障 阈值组态非法（量程上限不大于 0 或任一段初堵阈值不低于更换阈值）
//   16#0003_03DC 信息 低风量冻结（风机输出低于判定下限, 档位保持不推进）
//   16#0003_03DD 故障 任一段压差超量程或为负, 该段落传感器故障档
// ---------------------------------------------------------------------

// ---- 去抖秒值换算 / Debounce seconds conversion ----
tDebS := TIME_TO_REAL(tDebounce) / 1000.0;  // 毫秒换算秒 / Convert ms to seconds [s]

// ---- 守卫闸 1: 标量输入非有限与去抖时长合法域 / Gate 1: scalar finite and debounce range ----
bAbort    := FALSE;                 // 中止标记复位 / Reset abort flag
eAbtCode  := 16#0003_03D9;          // 中止码复位 / Reset abort code
IF (tDebounce = T#0MS) OR (tDebS < 0.1) OR (tDebS > 120.0)
   OR (fHyst_Pa <> fHyst_Pa) OR (ABS(fHyst_Pa) >= 1.0E12)
   OR (fDpMax_Pa <> fDpMax_Pa) OR (ABS(fDpMax_Pa) >= 1.0E12)
   OR (fFanPct <> fFanPct) OR (ABS(fFanPct) >= 1.0E12)
   OR (fFanMinPct <> fFanMinPct) OR (ABS(fFanMinPct) >= 1.0E12) THEN
    bAbort  := TRUE;                // 置中止 / Set abort
    eAbtCode := 16#0003_03DA;       // 码 03DA / Code 03DA
END_IF

// ---- 守卫闸 2: 逐段压差与阈值非有限判界 / Gate 2: per-stage finite check ----
IF NOT bAbort THEN
    FOR uZi := 1 TO 4 DO
        IF (afDp_Pa[uZi] <> afDp_Pa[uZi]) OR (ABS(afDp_Pa[uZi]) >= 1.0E12)
           OR (afDpEarly_Pa[uZi] <> afDpEarly_Pa[uZi]) OR (ABS(afDpEarly_Pa[uZi]) >= 1.0E12)
           OR (afDpChange_Pa[uZi] <> afDpChange_Pa[uZi]) OR (ABS(afDpChange_Pa[uZi]) >= 1.0E12) THEN
            bAbort   := TRUE;           // 置中止 / Set abort
            eAbtCode := 16#0003_03DA;   // 码 03DA / Code 03DA
        END_IF
    END_FOR
END_IF

// ---- 守卫闸 3: 阈值组态合法性 / Gate 3: threshold configuration ----
IF NOT bAbort THEN
    IF fDpMax_Pa <= 0.0 THEN
        bAbort   := TRUE;           // 量程非法 / Illegal range
        eAbtCode := 16#0003_03DB;   // 码 03DB / Code 03DB
    END_IF
END_IF
IF NOT bAbort THEN
    FOR uZi := 1 TO 4 DO
        IF afDpEarly_Pa[uZi] >= afDpChange_Pa[uZi] THEN
            bAbort   := TRUE;           // 阈值倒置 / Inverted thresholds
            eAbtCode := 16#0003_03DB;   // 码 03DB / Code 03DB
        END_IF
    END_FOR
END_IF

// ---- 首扫初始化 / First-scan initialization ----
IF xFirstScan THEN
    FOR uZi := 1 TO 4 DO
        aeStage[uZi]     := E_DL_FilterStage.eClean;    // 初始洁净档 / Init clean stage
        aPendStage[uZi]  := E_DL_FilterStage.eClean;    // 候选初始 / Pending init
        aPendActive[uZi] := FALSE;  // 候选无效 / Pending inactive
    END_FOR
    xFirstScan := FALSE;        // 清首扫标记 / Clear first-scan flag
END_IF

// ---- 低风量冻结与中止冻结推导 / Low-airflow freeze and abort freeze ----
IF bAbort THEN
    bFrozen := TRUE;            // 守卫闸中止按安全冻结处理 / Abort treated as safe freeze
ELSIF fFanPct < fFanMinPct THEN
    bFrozen := TRUE;            // 低风量冻结 / Low airflow freeze
ELSE
    bFrozen := FALSE;           // 正常非冻结 / Normal not frozen
END_IF

// ---- 逐段目标档计算与候选登记（不在此处调定时器）/ Per-stage target and pending registration ----
IF NOT bAbort AND NOT bFrozen THEN
    bSensorFlt := FALSE;        // 传感器故障标记复位 / Reset sensor fault flag
    bChangeReq := FALSE;        // 更换请求复位 / Reset change request
    FOR uZi := 1 TO 4 DO
        // 传感器故障判: 超量程或负压差 / Sensor fault: over-range or negative dP
        IF (afDp_Pa[uZi] > fDpMax_Pa) OR (afDp_Pa[uZi] < 0.0) THEN
            aeStage[uZi]     := E_DL_FilterStage.eSensorFault;  // 落传感器故障档 / Sensor fault stage
            aPendActive[uZi] := FALSE;  // 候选作废 / Pending void
            bSensorFlt := TRUE;         // 置传感器故障 / Set sensor fault
            bChangeReq := TRUE;         // 故障档也需现场处置 / Fault stage requests action
        ELSE
            // 双阈值迟滞分档: 严格大于阈值才切档, 恰好等于阈值保持原档 / Strict-greater hysteresis grading
            CASE aeStage[uZi] OF
                E_DL_FilterStage.eClean:        // 当前洁净 / Currently clean
                    IF afDp_Pa[uZi] > (afDpEarly_Pa[uZi] + fHyst_Pa) THEN
                        eTarget := E_DL_FilterStage.eEarly;     // 越升档阈值 → 初堵 / Above rise threshold
                    ELSE
                        eTarget := E_DL_FilterStage.eClean;     // 保持 / Hold
                    END_IF
                E_DL_FilterStage.eEarly:        // 当前初堵 / Currently early
                    IF afDp_Pa[uZi] > (afDpChange_Pa[uZi] + fHyst_Pa) THEN
                        eTarget := E_DL_FilterStage.eChange;    // 越更换阈值 / Above change threshold
                    ELSIF afDp_Pa[uZi] < (afDpEarly_Pa[uZi] - fHyst_Pa) THEN
                        eTarget := E_DL_FilterStage.eClean;     // 回落洁净 / Fall back clean
                    ELSE
                        eTarget := E_DL_FilterStage.eEarly;     // 保持 / Hold
                    END_IF
                E_DL_FilterStage.eMid:          // 当前中堵 / Currently mid
                    IF afDp_Pa[uZi] > (afDpChange_Pa[uZi] + fHyst_Pa) THEN
                        eTarget := E_DL_FilterStage.eChange;    // 越更换阈值 / Above change threshold
                    ELSIF afDp_Pa[uZi] < (afDpEarly_Pa[uZi] - fHyst_Pa) THEN
                        eTarget := E_DL_FilterStage.eClean;     // 回落洁净 / Fall back clean
                    ELSE
                        eTarget := E_DL_FilterStage.eMid;       // 保持 / Hold
                    END_IF
                E_DL_FilterStage.eChange:       // 当前更换档 / Currently change
                    IF afDp_Pa[uZi] < (afDpChange_Pa[uZi] - fHyst_Pa) THEN
                        eTarget := E_DL_FilterStage.eMid;       // 回落中堵 / Fall back mid
                    ELSE
                        eTarget := E_DL_FilterStage.eChange;    // 保持 / Hold
                    END_IF
                E_DL_FilterStage.eSensorFault:  // 故障档: 压差恢复量程内后按洁净档重新进入 / Fault holds, re-enter via grading
                    eTarget := E_DL_FilterStage.eClean;     // 目标回洁净档, 去抖后切换 / Target clean, switch after debounce
                ELSE                            // 非法档位拦截 / Illegal stage interception
                    eTarget := E_DL_FilterStage.eSensorFault;   // 落故障档 / Fall to fault stage
            END_CASE

            // 候选登记: 目标与当前不同才登记 / Register pending only if target differs
            IF eTarget <> aeStage[uZi] THEN
                IF (NOT aPendActive[uZi]) OR (aPendStage[uZi] <> eTarget) THEN
                    aPendStage[uZi]  := eTarget;    // 登记新候选 / Register new candidate
                    aPendActive[uZi] := TRUE;       // 候选有效 / Pending active
                END_IF
            ELSE
                aPendActive[uZi] := FALSE;      // 目标即当前档, 候选作废 / Target equals current, void
            END_IF
        END_IF

        // 更换档请求判 / Change stage request check
        IF aeStage[uZi] = E_DL_FilterStage.eChange THEN
            bChangeReq := TRUE;     // 任一段处于更换档 / Any stage at change
        END_IF
    END_FOR
ELSE
    bSensorFlt := FALSE;            // 冻结/中止拍不重推传感器判据 / No sensor re-judge on frozen cycle
    bChangeReq := FALSE;            // 冻结拍不置更换请求 / No change request on frozen cycle
END_IF

// ---- 4 个去抖定时器无条件周期刷新（本 FOR 循环每拍必执行全部 4 个实例,
//      不放进任何 IF 分支; 候选作废分支传 IN 为假显式复位而不是跳过调用）
//      Unconditional refresh of all 4 TON instances every cycle ----
FOR uZi := 1 TO 4 DO
    IF (NOT bAbort) AND (NOT bFrozen) AND aPendActive[uZi] AND (aPendStage[uZi] <> aeStage[uZi]) THEN
        aTonDeb[uZi](IN := TRUE, PT := tDebounce);  // 本拍继续计时 / Keep timing this cycle
        IF aTonDeb[uZi].Q THEN
            aeStage[uZi] := aPendStage[uZi];        // 去抖通过, 档位切换 / Switch after debounce
            aPendActive[uZi] := FALSE;              // 候选完成 / Pending done
        END_IF
    ELSE
        aPendActive[uZi] := FALSE;                  // 候选作废 / Pending void
        aTonDeb[uZi](IN := FALSE, PT := tDebounce); // 候选作废显式复位 / Explicit reset on void
    END_IF
END_FOR

// ---- 最高档统计（只统计非传感器故障段）/ Max stage excluding sensor-fault sections ----
uMaxTmp := 0;                   // 临时量复位 / Reset temporary
FOR uZi := 1 TO 4 DO
    IF aeStage[uZi] <> E_DL_FilterStage.eSensorFault THEN
        CASE aeStage[uZi] OF
            E_DL_FilterStage.eClean:    // 档 0 / Stage 0
                uMaxTmp := uMaxTmp;     // 保持 0 / Keep 0
            E_DL_FilterStage.eEarly:    // 档 1 / Stage 1
                IF uMaxTmp < 1 THEN
                    uMaxTmp := 1;       // 升到 1 / Raise to 1
                END_IF
            E_DL_FilterStage.eMid:      // 档 2 / Stage 2
                IF uMaxTmp < 2 THEN
                    uMaxTmp := 2;       // 升到 2 / Raise to 2
                END_IF
            E_DL_FilterStage.eChange:   // 档 3 / Stage 3
                uMaxTmp := 3;           // 升到 3 / Raise to 3
            ELSE                        // 兜底: 非法档不计入 / Fallback: illegal stage not counted
                uMaxTmp := uMaxTmp;     // 保持 / Keep
        END_CASE
    END_IF
END_FOR
auMaxStage := uMaxTmp;          // 输出最高档 / Output max stage

// ---- 错误码仲裁（每拍重算, 非锁存, 恢复合法输入即解除）/ Error arbitration recomputed each cycle ----
IF bAbort THEN
    eErr := eAbtCode;           // 守卫闸中止码优先 / Gate abort code first
ELSIF bSensorFlt THEN
    eErr := 16#0003_03DD;       // 传感器故障 / Sensor fault
ELSIF bFrozen THEN
    eErr := 16#0003_03DC;       // 低风量冻结 / Low airflow freeze
ELSE
    eErr := 16#0003_03D9;       // 分档正常 / Grading normal
END_IF

END_FUNCTION_BLOCK
