(*
  DL Factory R83 | FB_DL_ToteGapReleaseCtrl
  功能：按实测间距与下游就绪状态做料箱最小间隔放行，含压料超时三态机。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
*)
TYPE E_DL_GapSt : ( eGapHold := 0, eGapGo := 1, eGapFault := 2 ); END_TYPE // 间隔放行三态枚举
FUNCTION_BLOCK FB_DL_ToteGapReleaseCtrl
VAR_INPUT
    fToteLenM        : REAL; // 料箱沿输送方向长度 [m] / Tote length [m]
    fMinGapM         : REAL; // 工艺允许最小净间距 [m] / Allowed minimum clear gap [m]
    fGapActM         : REAL; // 实测与前箱净间距 [m] / Measured clear gap [m]
    fConvSpeedMps    : REAL; // 输送线速度 [m/s] / Conveyor speed [m/s]
    bDownstreamReady : BOOL; // 下游就绪（允许接箱）/ Downstream ready to accept
    bReset           : BOOL; // 复位：清锁存故障码并回保压相 / Reset: clear code, back to hold
END_VAR
VAR_OUTPUT
    fGapNeedM   : REAL; // 需保持中心距（箱长+净间距）[m] / Required centre distance [m]
    fGapMarginM : REAL; // 间距裕量（实测-最小净距）[m] / Gap margin, negative = insufficient [m]
    xRelease    : BOOL; // 放行许可输出 / Release permit output
    iErrCode    : INT;  // 错误码，0=无错 / Error code, 0 = no error
END_VAR
VAR
    _eState : E_DL_GapSt := eGapHold; // 当前状态，枚举初值一律 := / Current state, enum init with :=
    _iLatch : INT;        // 故障码锁存，仅 bReset 沿清除 / Latched fault code, reset edge only
    tonHold : TON;        // 压料计时（无条件周期刷新）/ Hold timer, refreshed unconditionally
END_VAR
xRelease := FALSE; fGapNeedM := fToteLenM + fMinGapM; fGapMarginM := fGapActM - fMinGapM; // 出口预置
IF bReset THEN _iLatch := 0; iErrCode := 0; _eState := eGapHold; END_IF // 唯一清除边（R188）
// 定时器无条件周期刷新：置于所有早退之前，保证每周期都刷新（R7/R18），超时窗 10 s
tonHold(IN := (_eState = eGapHold), PT := T#10S);
IF NOT (fToteLenM > -1.0E30 AND fToteLenM < 1.0E30) OR NOT (fMinGapM > -1.0E30 AND fMinGapM < 1.0E30) OR NOT (fGapActM > -1.0E30 AND fGapActM < 1.0E30) OR NOT (fConvSpeedMps > -1.0E30 AND fConvSpeedMps < 1.0E30) OR fToteLenM <= 0.0 OR fMinGapM < 0.0 OR fGapActM < 0.0 OR fConvSpeedMps <= 0.0 THEN  // 非有限拦截 + 量纲自检（R20/R21）
    _eState := eGapFault; _iLatch := 9301; iErrCode := _iLatch; RETURN; // 故障拍不放行 / Fault never releases
END_IF
CASE _eState OF  // 三态机：本拍合法沿优先于超时迁移（R275）
eGapHold:
    IF fGapActM >= fGapNeedM AND bDownstreamReady THEN
        _eState := eGapGo;          // 间距足够且下游就绪，进放行相 / Gap and downstream OK
    ELSIF tonHold.Q THEN
        _eState := eGapFault; _iLatch := 9302;   // 压料超时：下游阻塞 / Hold timeout, downstream blocked
    END_IF
eGapGo:
    xRelease := TRUE;               // 放行相输出许可 / Release permit in go state
    IF fGapActM < fMinGapM OR NOT bDownstreamReady THEN _eState := eGapHold; END_IF // 退出两条合并
eGapFault:
    xRelease := FALSE; iErrCode := _iLatch;  // 故障相不放行，故障码锁存回放 / Latched replay
ELSE
    _eState := eGapFault; _iLatch := 9303;   // 非法状态兜底拦截（R6）/ Illegal state fallback
END_CASE
END_FUNCTION_BLOCK
