// =====================================================================
// FB_DL_AhuFilterDpBank.st
// 空调箱 4 段过滤器压差四级分档（迟滞 + 去抖 + 低风量冻结）
// AHU 4-stage filter dP grading FB
// 码位: 16#0003_03C5 ~ 16#0003_03C9 (本件独占 5 槽)
// 修改记录: R29 初版 (按 DISPATCH_R29 序 8)
// =====================================================================
FUNCTION_BLOCK FB_DL_AhuFilterDpBank
VAR_INPUT
    bEnable        : BOOL  := FALSE;   // 使能 / Enable
    afDp_Pa        : ARRAY[1..4] OF REAL;   // 段压差 0~2000 Pa / Stage dP [Pa]
    afDpEarly_Pa   : ARRAY[1..4] OF REAL;   // 初堵阈值 10~500 Pa / Early threshold [Pa]
    afDpChange_Pa  : ARRAY[1..4] OF REAL;   // 更换阈值 20~1000 Pa / Change threshold [Pa]
    fHyst_Pa       : REAL  := 10.0;    // 迟滞回差 0~100 Pa / Hysteresis [Pa]
    fDpMax_Pa      : REAL  := 1500.0;  // 传感器量程 >0 Pa / Sensor range [Pa]
    fFanPct        : REAL  := 0.0;     // 风机输出 0~100 % / Fan duty [%]
    fFanMinPct     : REAL  := 20.0;    // 判定最低风量 0~100 % / Min fan for judging [%]
    tDebounce      : TIME  := T#5S;    // 去抖 T#100MS~T#120S / Debounce [s]
END_VAR
VAR_OUTPUT
    aeStage        : ARRAY[1..4] OF E_DL_FilterStage;  // 各段档位 / Stage level
    auMaxStage     : USINT;            // 最高档 0~3 / Max stage
    bChangeReq     : BOOL;             // 需更换 / Change required
    bFrozen        : BOOL;             // 低风量冻结 / Frozen low airflow
    eErr           : UDINT;            // 错误码 / Error code
END_VAR
VAR
    tonDeb         : TON;              // 去抖定时器（无条件周期刷新）/ Debounce timer
    aPendStage     : ARRAY[1..4] OF E_DL_FilterStage;  // 候选档位 / Pending stage
    aPendActive    : ARRAY[1..4] OF BOOL;  // 候选有效标记 / Pending active flag
    uIdx           : UDINT;            // 循环下标 / Loop index
    uZi            : INT;              // 1..4 数组下标 / Array subscript 1..4
    eTarget        : E_DL_FilterStage; // 本拍目标档 / Target stage this cycle
    bAllSame       : BOOL;             // 候选一致标记 / Candidates all same
    uMaxTmp        : USINT;            // 最高档临时量 / Max stage temporary
    tDebS          : REAL;             // 去抖秒值 / Debounce seconds [s]
    xFirstScan     : BOOL  := TRUE;    // 首扫标记 / First-scan flag
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占，勿复用）:
//   16#0003_03C5 信息 分档正常
//   16#0003_03C6 故障 压差非有限 / tDebounce 非法
//   16#0003_03C7 故障 任一段 afDpEarly_Pa ≥ afDpChange_Pa（阈值倒置）/ fDpMax_Pa ≤ 0
//   16#0003_03C8 信息 低风量冻结（fFanPct < fFanMinPct）→ bFrozen=TRUE，档位保持
//   16#0003_03C9 故障 任一段 afDp_Pa > fDpMax_Pa 或压差为负 → 该段 eSensorFault
// ---------------------------------------------------------------------

// ---- 去抖秒值 / Debounce seconds ----
tDebS := TIME_TO_REAL(tDebounce) / 1000.0;  // 秒值 / Seconds [s]

// ---- 非有限与去抖合法性闸 / Finite and debounce validity gate ----
IF (tDebounce = T#0MS) OR (tDebS < 0.1) OR (tDebS > 120.0)
   OR (fHyst_Pa <> fHyst_Pa) OR (ABS(fHyst_Pa) >= 1.0E12)
   OR (fDpMax_Pa <> fDpMax_Pa) OR (ABS(fDpMax_Pa) >= 1.0E12)
   OR (fFanPct <> fFanPct) OR (ABS(fFanPct) >= 1.0E12) THEN
    bFrozen := TRUE;            // 安全冻结 / Safe freeze
    eErr    := 16#0003_03C6;    // 故障码 / Fault code
    RETURN;                     // 档位保持 / Stages hold
END_IF

// ---- 逐段压差与阈值非有限判界 / Per-stage finite check ----
FOR uZi := 1 TO 4 DO
    IF (afDp_Pa[uZi] <> afDp_Pa[uZi]) OR (ABS(afDp_Pa[uZi]) >= 1.0E12)
       OR (afDpEarly_Pa[uZi] <> afDpEarly_Pa[uZi]) OR (ABS(afDpEarly_Pa[uZi]) >= 1.0E12)
       OR (afDpChange_Pa[uZi] <> afDpChange_Pa[uZi]) OR (ABS(afDpChange_Pa[uZi]) >= 1.0E12) THEN
        bFrozen := TRUE;        // 安全冻结 / Safe freeze
        eErr    := 16#0003_03C6;    // 故障码 / Fault code
        RETURN;                 // 档位保持 / Stages hold
    END_IF
END_FOR

// ---- 阈值组态错闸 / Threshold configuration gate ----
IF fDpMax_Pa <= 0.0 THEN
    bFrozen := TRUE;            // 安全冻结 / Safe freeze
    eErr    := 16#0003_03C7;    // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF
FOR uZi := 1 TO 4 DO
    IF afDpEarly_Pa[uZi] >= afDpChange_Pa[uZi] THEN
        bFrozen := TRUE;        // 安全冻结 / Safe freeze
        eErr    := 16#0003_03C7;    // 故障码：阈值倒置 / Fault code: inverted thresholds
        RETURN;                 // 本拍结束 / End of cycle
    END_IF
END_FOR

// ---- 首扫初始化（R16 首扫纪律）/ First-scan initialization ----
IF xFirstScan THEN
    FOR uZi := 1 TO 4 DO
        aeStage[uZi] := E_DL_FilterStage.eClean;    // 初始洁净档 / Init clean stage
        aPendStage[uZi] := E_DL_FilterStage.eClean; // 候选初始 / Pending init
        aPendActive[uZi] := FALSE;  // 候选无效 / Pending inactive
    END_FOR
    xFirstScan := FALSE;        // 清标记 / Clear flag
END_IF

// ---- 低风量冻结：低压差会被误判洁净，必须在有风工况判定 / Low airflow freeze ----
IF fFanPct < fFanMinPct THEN
    bFrozen := TRUE;            // 冻结标志 / Frozen flag
    eErr := 16#0003_03C8;       // 信息级：低风量冻结 / Info: low airflow freeze
    // 档位保持，不做分档推进 / Stages hold, no grading advance
    RETURN;                     // 本拍结束 / End of cycle
END_IF
bFrozen := FALSE;               // 正常非冻结 / Not frozen

// ---- 逐段传感器故障判 + 目标档计算（双阈值迟滞）/ Per-stage sensor fault + hysteresis target ----
bChangeReq := FALSE;            // 更换请求复位 / Reset change request
FOR uZi := 1 TO 4 DO
    // 传感器故障判：超量程或负压差 / Sensor fault: over-range or negative
    IF (afDp_Pa[uZi] > fDpMax_Pa) OR (afDp_Pa[uZi] < 0.0) THEN
        aeStage[uZi]  := E_DL_FilterStage.eSensorFault;  // 传感器故障档 / Sensor fault stage
        aPendActive[uZi] := FALSE;   // 候选作废 / Pending void
        eErr := 16#0003_03C9;        // 故障级（故障优先于信息）/ Fault level
        bChangeReq := TRUE;          // 故障档也需现场处置 / Fault stage also requests action
    ELSE
        // 双阈值迟滞分档（当前档 + 上升/下降阈值，防抖振）/ Dual-threshold hysteresis grading
        CASE aeStage[uZi] OF
            E_DL_FilterStage.eClean:        // 当前洁净 / Currently clean
                IF afDp_Pa[uZi] > (afDpEarly_Pa[uZi] + fHyst_Pa) THEN
                    eTarget := E_DL_FilterStage.eEarly;     // 越升阈值 → 初堵 / Above rise threshold
                ELSE
                    eTarget := E_DL_FilterStage.eClean;     // 保持 / Hold
                END_IF
            E_DL_FilterStage.eEarly:        // 当前初堵 / Currently early
                IF afDp_Pa[uZi] > (afDpChange_Pa[uZi] + fHyst_Pa) THEN
                    eTarget := E_DL_FilterStage.eChange;    // 越更换阈值 / Above change threshold
                ELSIF afDp_Pa[uZi] < (afDpEarly_Pa[uZi] - fHyst_Pa) THEN
                    eTarget := E_DL_FilterStage.eClean;     // 回落至洁净 / Fall back clean
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
            E_DL_FilterStage.eSensorFault:  // 故障档保持直至压差恢复量程内 / Fault holds until back in range
                eTarget := E_DL_FilterStage.eSensorFault;   // 保持 / Hold
            ELSE                            // 非法档位拦截（R128）/ Illegal stage interception
                eTarget := E_DL_FilterStage.eSensorFault;   // 落故障档 / Fall to fault stage
        END_CASE

        // ---- 去抖：目标档持续 tDebounce 才切换 / Debounce: target must persist ----
        IF eTarget <> aeStage[uZi] THEN
            IF (NOT aPendActive[uZi]) OR (aPendStage[uZi] <> eTarget) THEN
                aPendStage[uZi]  := eTarget;    // 登记新候选 / Register new candidate
                aPendActive[uZi] := TRUE;       // 候选有效 / Pending active
                IF uZi = 1 THEN
                    tonDeb(IN := TRUE, PT := tDebounce);    // 段 1 计时 / Stage 1 timing
                ELSIF uZi = 2 THEN
                    tonDeb(IN := TRUE, PT := tDebounce);    // 段 2 计时 / Stage 2 timing
                ELSIF uZi = 3 THEN
                    tonDeb(IN := TRUE, PT := tDebounce);    // 段 3 计时 / Stage 3 timing
                ELSE
                    tonDeb(IN := TRUE, PT := tDebounce);    // 段 4 计时 / Stage 4 timing
                END_IF
                IF tonDeb.Q THEN
                    aeStage[uZi] := eTarget;    // 去抖通过切换 / Switch after debounce
                    aPendActive[uZi] := FALSE;  // 候选完成 / Pending done
                END_IF
            ELSE
                tonDeb(IN := TRUE, PT := tDebounce);    // 候选延续计时 / Continue timing
                IF tonDeb.Q THEN
                    aeStage[uZi] := eTarget;    // 切换 / Switch
                    aPendActive[uZi] := FALSE;  // 完成 / Done
                END_IF
            END_IF
        ELSE
            aPendActive[uZi] := FALSE;      // 目标即当前档，候选作废 / Target equals current, void
        END_IF
    END_IF

    // ---- 更换请求判 / Change request check ----
    IF aeStage[uZi] = E_DL_FilterStage.eChange THEN
        bChangeReq := TRUE;     // 任一段进入更换档 / Any stage at change
    END_IF
END_FOR

// ---- 最高档统计（只统计非 eSensorFault 段）/ Max stage excluding sensor faults ----
uMaxTmp := 0;                   // 临时量复位 / Reset temp
FOR uZi := 1 TO 4 DO
    IF aeStage[uZi] <> E_DL_FilterStage.eSensorFault THEN
        CASE aeStage[uZi] OF
            E_DL_FilterStage.eClean:    // 档 0 / Stage 0
                IF uMaxTmp < 0 THEN
                    uMaxTmp := 0;       // 保持 / Keep
                END_IF
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
            ELSE                        // 兜底 / Fallback
                ;                       // 无动作 / No action
        END_CASE
    END_IF
END_FOR
auMaxStage := uMaxTmp;          // 输出最高档 / Output max stage

// ---- 无更高级登记时补正常码 / Normal code if no higher code registered ----
IF eErr <> 16#0003_03C9 THEN
    eErr := 16#0003_03C5;       // 信息级：分档正常 / Info: grading normal
END_IF

END_FUNCTION_BLOCK
