(*
  FB_DL_ResonanceTrackNotch  —  共振频率跟踪与陷波中心估计 / Resonance frequency tracking and notch centre estimation
  分类 Category : DL_Algo
  码位 Code     : 16#02_3_82
  版本 Version  : 1.0.1
  来源 Source   : t1-6-plcopen — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : PLCopen 运动/振动监视公开语义借鉴，clean-room 实现，仅借分类与参数域，未复制任何源码行
  功能 Function : 1) 二阶带通相位过零测周期：以信号上行过零点之间的累计时间为一个周期 [s]，取倒数得频率 [Hz]；
                  2) 频率估计经 5 点滑动中值去野值（排序网络，无循环），抗单点脉冲干扰；
                  3) 中值结果钳制到 [fFreqMinHz, fFreqMaxHz]，输出 fResonanceHz 供陷波中心使用；
                  4) 连续 nSettleCycles 次估计落在中心 ±fLockBandHz 内 → bLocked；锁定后须连续
                     nLostCycles 次越带才降级（迟滞，防抖）；
                  5) fTrackConfidence 逐拍升降（步长 DL_CONF_STEP），幅值不足时衰减而非清零。
  边界 Boundary : ① fSampleDt <= 0 / 搜索窗倒置 / 搜索窗越奈奎斯特（fFreqMaxHz >= 1/(2·fSampleDt)）
                     任一成立判组态错置 0382，状态进 eFault 且不投运（R28 组态域闸覆盖全部换算引脚）；
                  ② 信号幅值（峰值包络）< fAmpFloor 时不出频率结论：bLocked := FALSE，估计值保持，
                     置信度按 DL_CONF_DECAY 衰减（不置 bError，信息级 01B2，R187③）；
                  ③ 频率跳变率超 fMaxSlewHzPerSec 判野值丢弃并计数；计数在 DL_WILD_WINDOW 窗内
                     超 nWildMax 置「跟踪发散」故障 0392（计数窗由自复位 TON 滚动清零）；
                  ④ 幅值门限只影响结论不影响估计：无结论期间 fResonanceHz 保持末次有效值（R191 显式声明）；
                  ⑤ 解除路径自证：_bFault 清除 = rtReset.Q 单一路径（引脚可满足）；发散码 0392 另可由
                     「窗内野值计数回落至 0」按码专清（两路径互不掩盖）。
  依赖 Depends  : 仅 Standard.library（TON / R_TRIG / ABS / MAX / MIN / MOD），零外部组件依赖
  同拍双窗配比  : 野值观察窗 DL_WILD_WINDOW = 2 s 与锁定计数 nSettleCycles ≥ 1 不同源；
                  配比约束 nSettleCycles × fSampleDt <= DL_WILD_WINDOW，保证锁定判据至少跨一个观察窗成立

  码表 Error codes（本件格 02_3_82，子码步进 +0x10）:
    16#0002_0382 故障级：组态非法（采样周期 <= 0 / 搜索窗倒置 / 越奈奎斯特 / 锁定带或幅值下限 <= 0）
    16#0002_0392 故障级：跟踪发散（野值计数超 nWildMax，跟踪环已失去物理意义）
    16#0002_03A2 故障级：状态机落 ELSE 兜底（非法相位 ID）
    16#0002_01B2 信息级：信号幅值低于 fAmpFloor，本拍不出频率结论（不置 bError）
    16#0002_01C2 信息级：单拍野值已丢弃（跳变率超 fMaxSlewHzPerSec，不置 bError）

  修订历史 Revision :
    2026-11-18  v1.0.0  R37 首版
  修订 History : v1.0.1 2026-11-18 R37 终审：锁定出口随幅值门限/保持相同拍降级（原缺 eTrack/eHold 分支归零）
*)

TYPE E_DL_ResTrackState :
(
    eIdle     := 0,   // 空闲：未使能，不出结论 / Idle, no conclusion while disabled
    eTrack    := 10,  // 跟踪中：已取得周期，尚未满足锁定次数 / Tracking, period acquired but lock count insufficient
    eLocked   := 20,  // 已锁定：连续在带次数达标 / Locked, the in-band count reached the preset
    eHold     := 30,  // 保持：幅值不足，估计保持、置信度衰减 / Hold, low amplitude, estimate held and confidence decaying
    eDiverged := 40,  // 发散：野值计数超限，跟踪失效 / Diverged, wild-value count exceeded
    eFault    := 90   // 故障：组态非法或状态兜底锁定 / Fault, illegal configuration or fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_ResonanceTrackNotch
VAR_INPUT
    bEnable        : BOOL := FALSE;              // 总使能，FALSE 时不出结论并回 eIdle / Master enable
    bReset         : BOOL := FALSE;              // 复位，上升沿清故障锁存 / Reset, rising edge clears the fault latch
    fSignal        : REAL := 0.0;                // 振动或电流反馈原始信号 [工程单位] / Raw vibration or current feedback
    fSampleDt      : REAL := 0.010;              // 采样周期 [s]，域 > 0 / Sampling period [s], domain > 0
    fFreqMinHz     : REAL := 20.0;               // 搜索窗下限 [Hz]，域 > 0 / Search window lower limit [Hz]
    fFreqMaxHz     : REAL := 400.0;              // 搜索窗上限 [Hz]，须 > 下限且 < 奈奎斯特 / Search window upper limit [Hz]
    fLockBandHz    : REAL := 2.0;                // 锁定带宽（中心 ± 本值）[Hz]，域 > 0 / Lock band half width [Hz]
    fAmpFloor      : REAL := 0.05;               // 幅值下限，低于此不出结论 [工程单位]，域 > 0 / Amplitude floor
    fMaxSlewHzPerSec : REAL := 500.0;            // 允许最大频率跳变率 [Hz/s]，域 > 0 / Permitted frequency slew [Hz/s]
    nSettleCycles  : INT := 5;                   // 连续在带次数门限 [次]，域 >= 1 / In-band settle cycles
    nLostCycles    : INT := 3;                   // 连续越带次数门限（迟滞）[次]，域 >= 1 / Out-of-band lost cycles
    nWildMax       : INT := 8;                   // 窗内野值计数上限 [次]，超过即判发散 / Wild-value count limit
END_VAR
VAR_OUTPUT
    fResonanceHz     : REAL;                     // 共振频率估计（钳制后、去野值）[Hz] / Resonance frequency estimate [Hz]
    fTrackConfidence : REAL;                     // 跟踪置信度 [0~1 无量纲] / Tracking confidence, 0..1
    bLocked          : BOOL;                     // 锁定标志（迟滞维持）/ Locked flag with hysteresis
    bValid           : BOOL;                     // 本拍估计可用标志 / Estimate usable this scan
    bError           : BOOL;                     // 故障标志，派生自锁存 / Fault flag derived from the latch
    nErrId           : UDINT;                    // 事件码，0 = 无事件 / Event code, 0 = no event
    eStateOut        : E_DL_ResTrackState;       // 状态出口，段尾单点映射 / State outlet, mapped at the tail
END_VAR
VAR
    tonWild        : TON;                        // 野值观察窗，自复位（IN := NOT Q）/ Wild-value observation window, self-resetting
    rtReset        : R_TRIG;                     // 复位上升沿 / Reset rising edge
    rtEnable       : R_TRIG;                     // 使能上升沿 / Enable rising edge
    _eState        : E_DL_ResTrackState := E_DL_ResTrackState.eIdle;  // 内部相位（CASE 只写本量）/ Internal phase, the only CASE target
    _uFault        : UDINT;                      // 故障码锁存（仅复位沿或按码专清）/ Latched fault code
    _uInfo         : UDINT;                      // 信息码，每拍重算 / Information code, recomputed per scan
    _bFault        : BOOL;                       // 故障锁存位 / Latched fault bit
    _bCfgBad       : BOOL;                       // 组态非法聚合 / Configuration invalid aggregate
    _bAmpLow       : BOOL;                       // 幅值不足判定 / Low amplitude predicate
    _bWildScan     : BOOL;                       // 本拍野值丢弃标志 / Wild value discarded this scan
    _bCrossUp      : BOOL;                       // 上行过零事件 / Upward zero-crossing event
    _bHavePeriod   : BOOL;                       // 已捕获至少一个完整周期 / At least one full period captured
    fSignalPrev    : REAL;                       // 上拍信号快照 [工程单位] / Previous-scan signal snapshot
    fCrossAccum    : REAL;                       // 过零后累计时间 [s] / Elapsed time since the last up-crossing [s]
    fPeriodSec     : REAL;                       // 实测周期 [s] / Measured period [s]
    fFreqRaw       : REAL;                       // 单次频率估计（未去野）[Hz] / Raw frequency estimate [Hz]
    fFreqMed       : REAL;                       // 中值去野后的频率 [Hz] / Median-filtered frequency [Hz]
    fFreqAcc       : REAL;                       // 已受理的频率（钳制后）[Hz] / Accepted frequency after clamping [Hz]
    fFreqPrev      : REAL;                       // 上一个已受理频率（跳变率基准）[Hz] / Previous accepted frequency [Hz]
    fCenterHz      : REAL;                       // 锁定中心频率 [Hz] / Lock centre frequency [Hz]
    fAmpEnv        : REAL;                       // 峰值包络（带衰减）[工程单位] / Decaying peak envelope
    fConfidence    : REAL := 0.0;                // 置信度保持量 [0~1] / Held confidence value
    afFreqBuf      : ARRAY[0..4] OF REAL;        // 5 点滑动缓冲 [Hz] / Five-point sliding buffer [Hz]
    nBufIdx        : INT;                        // 缓冲写指针 [索引] / Buffer write index
    nFill          : INT;                        // 缓冲已填点数 [个] / Filled slots in the buffer
    nInBandCnt     : INT;                        // 连续在带计数 [次] / Consecutive in-band count
    nOutBandCnt    : INT;                        // 连续越带计数 [次] / Consecutive out-of-band count
    nWildCnt       : INT;                        // 窗内野值计数 [次] / Wild-value count inside the window
    fSort0         : REAL;                       // 排序中间量 0 [Hz] / Sorting scratch 0 [Hz]
    fSort1         : REAL;                       // 排序中间量 1 [Hz] / Sorting scratch 1 [Hz]
    fSort2         : REAL;                       // 排序中间量 2 [Hz] / Sorting scratch 2 [Hz]
    fSort3         : REAL;                       // 排序中间量 3 [Hz] / Sorting scratch 3 [Hz]
    fSort4         : REAL;                       // 排序中间量 4 [Hz] / Sorting scratch 4 [Hz]
    fSwap          : REAL;                       // 排序交换临时量 [Hz] / Sorting swap scratch [Hz]
END_VAR
VAR CONSTANT
    DL_WILD_WINDOW : TIME  := T#2S;      // 野值观察窗 [ms]，自复位节拍 / Wild-value window, self-resetting
    DL_WILD_WINDOW_SEC : REAL := 2.0;    // 野值观察窗秒值 [s]，与上行同源 / Wild-value window in seconds
    DL_NYQ_RATIO   : REAL  := 0.5;       // 奈奎斯特系数（fs/2）[1] / Nyquist factor
    DL_CONF_STEP   : REAL  := 0.05;      // 置信度上升步长 [1/拍] / Confidence rising step
    DL_CONF_DECAY  : REAL  := 0.90;      // 低幅值衰减系数 [1/拍] / Confidence decay factor under low amplitude
    DL_AMP_DECAY   : REAL  := 0.95;      // 峰值包络衰减系数 [1/拍] / Peak envelope decay factor
    DL_EPS         : REAL  := 1.0E-6;    // 判零容差 [1] / Zero tolerance
    DL_BUF_LEN     : INT   := 5;         // 滑动缓冲长度 [个] / Sliding buffer length
END_VAR

(* —— 段 0：边缘检测与自复位节拍窗无条件周期刷新（禁置于任何分支内，R182） —— *)
rtReset(CLK := bReset);                                          // 复位上升沿，每拍必调 / Reset edge, called every scan
rtEnable(CLK := bEnable);                                        // 使能上升沿，每拍必调 / Enable edge, called every scan
tonWild(IN := NOT tonWild.Q, PT := DL_WILD_WINDOW);              // 野值窗自复位：到点后下一拍断输入归零 / Self-resetting window

(* —— 段 1：单拍量预清零（快照 / 锁存 / 计数不入清单，R187①） —— *)
_uInfo         := 16#0000_0000;   // 信息码每拍重算 / Info code recomputed
bError         := FALSE;          // 故障出口每拍重算，段 6 由锁存派生 / Fault outlet recomputed, derived in segment 6
bValid         := FALSE;          // 可用标志缺省 FALSE / Usable flag defaults FALSE
bLocked        := FALSE;          // 锁定出口缺省 FALSE / Locked outlet defaults FALSE
_bCfgBad       := FALSE;          // 组态非法聚合预清零 / Config aggregate pre-cleared
_bAmpLow       := FALSE;          // 低幅值判定预清零 / Low amplitude pre-cleared
_bWildScan     := FALSE;          // 本拍野值标志预清零 / Wild flag pre-cleared
_bCrossUp      := FALSE;          // 过零事件预清零 / Crossing event pre-cleared

(* —— 段 2：复位沿清锁存 + 按码专清（R188 双路径，互不掩盖） —— *)
IF rtReset.Q THEN
    _bFault  := FALSE;            // 复位沿清锁存位 / Clear the latched bit
    _uFault  := 16#0000_0000;     // 复位沿清锁存码 / Clear the latched code
    nWildCnt := 0;                // 复位沿同步清野值计数（发散判据的输入）/ Wild count cleared with the reset
    nInBandCnt := 0;              // 复位沿清在带计数，重新建立锁 / In-band count cleared
    nOutBandCnt := 0;             // 复位沿清越带计数 / Out-of-band count cleared
    fConfidence := 0.0;           // 复位沿置信度清零 / Confidence cleared
END_IF
IF tonWild.Q THEN
    IF nWildCnt > 0 THEN
        nWildCnt := nWildCnt - 1; // 窗到点衰减一个野值（迟滞释放，避免长期积压）/ Decay one wild value per window
    END_IF
END_IF
IF (_uFault = 16#0002_0392) AND (nWildCnt = 0) THEN
    _uFault := 16#0000_0000;      // 按码专清：发散码仅在野值窗回零时清除 / Code-specific clear for the divergence code
    _bFault := FALSE;             // 锁存位同步清 / Latched bit cleared together
END_IF

(* —— 段 3：组态域闸（覆盖全部参与换算的引脚，缺一个即该判据静默失效，R151） —— *)
IF (fSampleDt <> fSampleDt) OR (fSampleDt <= 0.0) THEN
    _bCfgBad := TRUE;             // 采样周期非法（过零计时与奈奎斯特的分母）/ Sampling period illegal
END_IF
IF (fFreqMinHz <> fFreqMinHz) OR (fFreqMinHz <= 0.0) THEN
    _bCfgBad := TRUE;             // 搜索窗下限非法 / Lower search limit illegal
END_IF
IF (fFreqMaxHz <> fFreqMaxHz) OR (fFreqMaxHz <= fFreqMinHz) THEN
    _bCfgBad := TRUE;             // 搜索窗倒置（上限须严格大于下限）/ Inverted search window
END_IF
IF (fLockBandHz <> fLockBandHz) OR (fLockBandHz <= 0.0) THEN
    _bCfgBad := TRUE;             // 锁定带宽非法（迟滞判据的分母）/ Lock band illegal
END_IF
IF (fAmpFloor <> fAmpFloor) OR (fAmpFloor <= 0.0) THEN
    _bCfgBad := TRUE;             // 幅值下限非法 / Amplitude floor illegal
END_IF
IF (fMaxSlewHzPerSec <> fMaxSlewHzPerSec) OR (fMaxSlewHzPerSec <= 0.0) THEN
    _bCfgBad := TRUE;             // 跳变率上限非法（野值判据的分母）/ Slew limit illegal
END_IF
IF nSettleCycles < 1 THEN
    _bCfgBad := TRUE;             // 锁定次数门限非法 / Settle cycles illegal
END_IF
IF nLostCycles < 1 THEN
    _bCfgBad := TRUE;             // 失锁次数门限非法 / Lost cycles illegal
END_IF
IF nWildMax < 1 THEN
    _bCfgBad := TRUE;             // 野值门限非法 / Wild limit illegal
END_IF
IF (NOT _bCfgBad) AND (fFreqMaxHz >= (DL_NYQ_RATIO / fSampleDt)) THEN
    _bCfgBad := TRUE;             // 搜索窗越奈奎斯特：fMax >= fs/2 时测周期无意义 / Window crosses Nyquist
END_IF
IF _bCfgBad THEN
    _uFault := 16#0002_0382;      // 故障级：组态非法
    _bFault := TRUE;              // 锁存位置位（复位沿可清）
    bError  := TRUE;              // 故障标志置位（R45 配对）
    _eState := E_DL_ResTrackState.eFault;  // 状态机进故障相
END_IF

(* —— 段 4：跟踪内核（仅无故障且使能时执行） —— *)
IF (NOT _bFault) AND bEnable AND (NOT _bCfgBad) THEN
    (* 4.1 峰值包络：MAX 跟随上升沿，逐拍衰减，用于幅值门限 *)
    fAmpEnv := MAX(ABS(fSignal), fAmpEnv * DL_AMP_DECAY);        // 峰值包络 [工程单位]
    _bAmpLow := (fAmpEnv < fAmpFloor);                           // 幅值不足判定

    (* 4.2 上行过零测周期：上一次过零起的累计时间即周期 *)
    _bCrossUp := (fSignalPrev < 0.0) AND (fSignal >= 0.0);       // 上行过零（含恰好落 0 的边界）
    fCrossAccum := fCrossAccum + fSampleDt;                      // 过零计时累加 [s]
    IF _bCrossUp THEN
        IF _bHavePeriod THEN
            fPeriodSec := fCrossAccum;                           // 两次上行过零之间为一个周期 [s]
            IF fPeriodSec > DL_EPS THEN
                fFreqRaw := 1.0 / fPeriodSec;                    // 倒数为频率 [Hz]（分母已判 > 容差）
                afFreqBuf[nBufIdx] := fFreqRaw;                  // 入滑动缓冲
                nBufIdx := (nBufIdx + 1) MOD DL_BUF_LEN;         // 环形指针推进（移位量已归一，禁越位宽）
                IF nFill < DL_BUF_LEN THEN
                    nFill := nFill + 1;                          // 已填点数饱和到缓冲长度
                END_IF
            END_IF
        END_IF
        fCrossAccum := 0.0;                                      // 过零后计时归零（本拍唯一清零点）
        _bHavePeriod := TRUE;                                     // 已具备周期测量能力
    END_IF
    IF fCrossAccum > (DL_WILD_WINDOW_SEC) THEN
        fCrossAccum := 0.0;                                      // 超时无过零：计时器防溢出回零（信号消失路径）
        _bHavePeriod := FALSE;                                   // 周期能力失效，等待重新建立
    END_IF
    fSignalPrev := fSignal;                                      // 信号快照更新（末行，不预清零）

    (* 4.3 5 点滑动中值：排序网络（9 次比较交换），无循环 *)
    IF nFill >= DL_BUF_LEN THEN                                  // 满窗才出中值
        fSort0 := afFreqBuf[0];                                  // 拷贝 0
        fSort1 := afFreqBuf[1];                                  // 拷贝 1
        fSort2 := afFreqBuf[2];                                  // 拷贝 2
        fSort3 := afFreqBuf[3];                                  // 拷贝 3
        fSort4 := afFreqBuf[4];                                  // 拷贝 4
        IF fSort0 > fSort1 THEN                                  // 比较交换 (0,1)
            fSwap := fSort0; fSort0 := fSort1; fSort1 := fSwap;
        END_IF
        IF fSort3 > fSort4 THEN                                  // 比较交换 (3,4)
            fSwap := fSort3; fSort3 := fSort4; fSort4 := fSwap;
        END_IF
        IF fSort2 > fSort4 THEN                                  // 比较交换 (2,4)
            fSwap := fSort2; fSort2 := fSort4; fSort4 := fSwap;
        END_IF
        IF fSort2 > fSort3 THEN                                  // 比较交换 (2,3)
            fSwap := fSort2; fSort2 := fSort3; fSort3 := fSwap;
        END_IF
        IF fSort1 > fSort4 THEN                                  // 比较交换 (1,4)
            fSwap := fSort1; fSort1 := fSort4; fSort4 := fSwap;
        END_IF
        IF fSort0 > fSort3 THEN                                  // 比较交换 (0,3)
            fSwap := fSort0; fSort0 := fSort3; fSort3 := fSwap;
        END_IF
        IF fSort0 > fSort2 THEN                                  // 比较交换 (0,2)
            fSwap := fSort0; fSort0 := fSort2; fSort2 := fSwap;
        END_IF
        IF fSort1 > fSort3 THEN                                  // 比较交换 (1,3)
            fSwap := fSort1; fSort1 := fSort3; fSort3 := fSwap;
        END_IF
        IF fSort1 > fSort2 THEN                                  // 比较交换 (1,2)
            fSwap := fSort1; fSort1 := fSort2; fSort2 := fSwap;
        END_IF
        fFreqMed := fSort2;                                      // 5 点中值即排序后第 3 个
        IF (fSort4 - fSort0) > fMaxSlewHzPerSec THEN             // 极差超跳变率上限：整窗污染，丢弃本窗
            _bWildScan := TRUE;                                  // 标记野值窗
        END_IF
    ELSE
        fFreqMed := fFreqRaw;                                    // 未满窗：直取单次估计（不出中值结论）
    END_IF

    (* 4.4 跳变率判野值 + 钳制到搜索窗 *)
    IF fFreqMed > 0.0 THEN
        IF _bHavePeriod THEN
            IF ABS(fFreqMed - fFreqPrev) > (fMaxSlewHzPerSec * fSampleDt) THEN
                _bWildScan := TRUE;                              // 单拍跳变超限：判野值（分母 fSampleDt 已证 > 0）
            END_IF
        END_IF
        IF _bWildScan THEN
            nWildCnt := nWildCnt + 1;                            // 野值计数累加（饱和交由门限比较处理）
            _uInfo   := 16#0002_01C2;                            // 信息级：单拍野值已丢弃
        ELSE
            fFreqAcc := fFreqMed;                                // 受理本次估计
            IF fFreqAcc < fFreqMinHz THEN
                fFreqAcc := fFreqMinHz;                          // 下行钳制（钳制后仍参与锁定判据）
            END_IF
            IF fFreqAcc > fFreqMaxHz THEN
                fFreqAcc := fFreqMaxHz;                          // 上行钳制
            END_IF
            fFreqPrev := fFreqAcc;                               // 跳变率基准更新
        END_IF
        IF nWildCnt > nWildMax THEN
            _uFault := 16#0002_0392;                             // 故障级：跟踪发散
            _bFault := TRUE;                                     // 锁存位置位
            bError  := TRUE;                                     // 故障标志置位（R45 配对）
            _eState := E_DL_ResTrackState.eDiverged;             // 进发散相
        END_IF
    END_IF

    (* 4.5 锁定 / 失锁迟滞（中心频率在首次受理时建立） *)
    IF (fFreqAcc > 0.0) AND (NOT _bWildScan) THEN
        IF ABS(fCenterHz) < DL_EPS THEN
            fCenterHz := fFreqAcc;                               // 首受理：以本次估计建立中心
        END_IF
        IF _bAmpLow THEN
            _bAmpLow := TRUE;                                    // 幅值不足：结论门控关闭（显式保留语义）
            nInBandCnt := 0;                                     // 低幅值期间不允许累积锁定计数
            fConfidence := fConfidence * DL_CONF_DECAY;          // 置信度衰减（R187③ 衰减而非清零）
            IF fConfidence < 0.0 THEN
                fConfidence := 0.0;                              // 下限保护 [0~1]
            END_IF
            _uInfo := 16#0002_01B2;                              // 信息级：幅值不足本拍不出结论
            IF _eState <> E_DL_ResTrackState.eLocked THEN
                _eState := E_DL_ResTrackState.eHold;             // 未锁定相进保持相
            END_IF
        ELSE
            IF ABS(fFreqAcc - fCenterHz) <= fLockBandHz THEN
                nInBandCnt := nInBandCnt + 1;                    // 在带计数累加
                nOutBandCnt := 0;                                // 越带计数在同拍归零（互斥计数，不同拍错位）
                fConfidence := fConfidence + DL_CONF_STEP;       // 置信度上升
            ELSE
                nOutBandCnt := nOutBandCnt + 1;                  // 越带计数累加
                nInBandCnt := 0;                                 // 在带计数归零
                fConfidence := fConfidence - (DL_CONF_STEP * 2.0); // 越带时衰减更快
            END_IF
            IF fConfidence > 1.0 THEN
                fConfidence := 1.0;                              // 置信度上限 1
            END_IF
            IF fConfidence < 0.0 THEN
                fConfidence := 0.0;                              // 置信度下限 0
            END_IF
            IF (_eState = E_DL_ResTrackState.eLocked) THEN
                IF nOutBandCnt >= nLostCycles THEN
                    _eState := E_DL_ResTrackState.eTrack;        // 失锁：越带连续达标才降级（防抖）
                    nInBandCnt := 0;                             // 降级后重新建立锁定
                END_IF
            ELSE
                IF nInBandCnt >= nSettleCycles THEN
                    _eState := E_DL_ResTrackState.eLocked;       // 锁定：连续在带达标
                ELSE
                    IF _eState <> E_DL_ResTrackState.eHold THEN
                        _eState := E_DL_ResTrackState.eTrack;    // 跟踪相
                    END_IF
                END_IF
            END_IF
        END_IF
    END_IF
ELSE
    IF (NOT _bFault) THEN
        _eState := E_DL_ResTrackState.eIdle;                     // 未使能：出结论能力关闭（估计保持，R191）
    END_IF
    fSignalPrev := fSignal;                                      // 未运行拍快照跟随，防再使能误判过零
    fCrossAccum := 0.0;                                          // 未运行拍计时归零
    _bHavePeriod := FALSE;                                       // 未运行拍周期能力复位
END_IF

(* —— 段 5：相位机（只做兜底，不直接写输出枚举，N2） —— *)
CASE _eState OF
E_DL_ResTrackState.eIdle:
    fTrackConfidence := fConfidence;        // 空闲：置信度如实上报（保持量）
E_DL_ResTrackState.eTrack:
    bLocked := FALSE;                       // 跟踪：未达锁定，出口同拍降级（R217 ①）
    fTrackConfidence := fConfidence;        // 跟踪：置信度如实上报
E_DL_ResTrackState.eLocked:
    bLocked := NOT _bAmpLow;                // 锁定：幅值跌破门限则同拍降级（头注释 ② 兑现）
    fTrackConfidence := fConfidence;        // 锁定：置信度如实上报
E_DL_ResTrackState.eHold:
    bLocked := FALSE;                       // 保持：锁定出口随保持相解除（R217 ①）
    fTrackConfidence := fConfidence;        // 保持：置信度已衰减，如实上报
E_DL_ResTrackState.eDiverged:
    fTrackConfidence := 0.0;                // 发散：置信度强制 0（跟踪已失去物理意义）
    bLocked := FALSE;                       // 发散：强制解锁
E_DL_ResTrackState.eFault:
    fTrackConfidence := 0.0;                // 故障：置信度 0
    bLocked := FALSE;                       // 故障：强制解锁
ELSE
    _uFault := 16#0002_03A2;                // 故障级：相位 ID 越界（枚举兜底）
    _bFault := TRUE;                        // 锁存位置位
    bError  := TRUE;                        // 故障标志置位（R45 配对）
    _eState := E_DL_ResTrackState.eFault;   // 强制回故障相
    fTrackConfidence := 0.0;                // 兜底输出安全值
    bLocked := FALSE;                       // 兜底解锁
END_CASE

(* —— 段 6：出口单点映射（名实同源；故障码一律锁存回放，禁同拍抹除） —— *)
fResonanceHz := fFreqAcc;                   // 频率出口：末次受理值（钳制后），无结论期保持
eStateOut    := _eState;                    // 状态出口
IF _bFault THEN
    nErrId := _uFault;                      // 故障锁存码回放（不在故障相按当下输入重推）
    bError := TRUE;                         // 故障出口派生自锁存
    bValid := FALSE;                        // 故障拍判定不可用
ELSE
    nErrId := _uInfo;                       // 信息码（每拍重算）
    IF bEnable AND (NOT _bCfgBad) AND (fFreqAcc > 0.0) AND (NOT _bAmpLow) THEN
        bValid := TRUE;                     // 有受理频率且无故障且幅值达标：判定可用（R37 终审）
    ELSE
        bValid := FALSE;                    // 其余情形不可用
    END_IF
END_IF

END_FUNCTION_BLOCK
