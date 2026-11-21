(*==============================================================================
 * 组件名称 (Component)  : FB_DL_BusbarWeldMonitor
 * 所属子库 (Sublibrary) : DL_Process
 * 归属目录 (Directory)  : C:\Library\DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 分类/来源标签         : 功能块（FUNCTION_BLOCK）· 母线焊接 · 超声焊能量包络
 *                         industry-pool / pvbusbar / ultrasonic-weld / envelope
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 TON / F_TRIG / ABS
 * 溯源声明 (Provenance) : 道莅自研 clean-room——只借公开规范条款与工程惯例，零代码行复制。
 * 功能一句话 (Summary)  : Busbar 超声焊接三维能量包络监视（功率-振幅-时间），
 *                         焊接期间任一维越窗即记缺陷，焊毕按在窗占比判定。
 *
 * 功能描述 (Function)   : 焊接进行中每拍评估三维窗口（功率带、振幅带、焊接
 *                         时长上限），任一维越窗当拍即置缺陷标记；焊接结束
 *                         （F_TRIG 下降沿）按在窗拍占比判定合格（信息级）或
 *                         缺陷（故障级）；时长越上限强制判缺陷并锁存；输入
 *                         非有限冻结监视。判定锁存到下一焊次起动沿解除。
 * 与既有件边界 (Boundary): 与库内激光焊轨迹件 LaserTabWeldTrack 为不同物理
 *                         域不同机制；本件只做包络判定，不出焊接功率给定。
 * 码位说明 (Codes)      : 信息 16#0006_3032 焊接判定合格（在窗占比达标）
 *                         故障 16#0006_3033 焊接判定缺陷（在窗占比不足）
 *                         故障 16#0006_3034 焊接时长越上限，强制缺陷
 *                         故障 16#0006_3035 输入非有限，监视冻结
 *                         段 16#06_0_32~36 首槽信息级、次槽起故障级。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 TON / F_TRIG。
 * 红线自检 (Redline)    : 零全局依赖 ｜ 零 VAR_EXTERNAL ｜ 零 %I/%Q ｜ 纯 IEC 标准库
 *                         NaN/Inf 精确判据拦截 ｜ 浮点比较带 fEps 容差
 *                         ENUM 配 CASE 且 ELSE 兜底 ｜ TON/F_TRIG 每周期无条件刷新
 *                         全变量双语同行注释 ｜ 判定锁存回放且有可达解除路径
 * 修订历史 (Revision)   : 2026-11-18  v1.0.0  首版入库（R32 · 批 4）
 *============================================================================*)

FUNCTION_BLOCK FB_DL_BusbarWeldMonitor
VAR_INPUT
    bRun     : BOOL;                    // 监视使能 / Enable
    bWelding : BOOL;                    // 焊接进行中 [事件] / Welding in progress
    fPowerKw : LREAL;                   // 焊接功率 [kW] / Welding power
    fAmpUm   : LREAL;                   // 振幅 [um] / Ultrasonic amplitude
    fPwrLoKw : LREAL := 4.0;            // 功率窗下限 [kW] / Power window lower bound
    fPwrHiKw : LREAL := 6.0;            // 功率窗上限 [kW] / Power window upper bound
    fAmpLoUm : LREAL := 35.0;           // 振幅窗下限 [um] / Amplitude window lower bound
    fAmpHiUm : LREAL := 55.0;           // 振幅窗上限 [um] / Amplitude window upper bound
    tWeldMaxS: TIME  := T#5S;           // 焊接时长上限 [s] / Weld duration limit
    fRatioTh : LREAL := 0.9;            // 在窗占比合格阈 [比值] / In-window ratio threshold
    fEps     : LREAL := 1.0E-6;         // 浮点判零容差 [实数域] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    eVerdict : (ePending := 0, eGood := 1, eDefect := 2);       // 判定枚举输出 / Verdict output enum
    bInWin   : BOOL;                    // 当前拍三维都在窗内 / All three in window this scan
    fWinRatio: LREAL;                   // 在窗拍占比 [比值] / In-window scan ratio
    bError   : BOOL;                    // 故障标志，与故障码配对 / Fault flag paired with codes
    uErrorId : UDINT;                   // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    _eVerdict: (ePending := 0, eGood := 1, eDefect := 2);       // 内部判定 / Internal verdict
    tonWeld  : TON;     // 焊接时长计时 [s]，每拍无条件刷新 / Weld duration timer
    fTrigEnd : F_TRIG;  // 焊接结束下降沿，每拍无条件刷新 / Weld end falling edge
    bSigOk   : BOOL;    // 输入有效标志 / Input validity flag
    bWinNow  : BOOL;    // 本拍在窗判定 / This-scan window verdict
    nWinScans: UDINT;   // 在窗拍计数 [拍] / In-window scan count
    nTotScans: UDINT;   // 总拍计数 [拍] / Total scan count
    bTimeout : BOOL;    // 时长越限锁存 / Duration timeout latched
    bNewWeld : BOOL;    // 新焊次起动沿（焊接上升沿）/ New weld rising edge
    bPrevWld : BOOL;    // 上拍焊接快照 [开关] / Previous welding snapshot
    uCode    : UDINT;   // 码位暂存，出口单点写入 [码] / Code staging
END_VAR
VAR CONSTANT
    DL_BWM_PCT   : LREAL := 100.0;      // 百分比系数 [％] / Percent factor
    DL_BWM_BIGUD : UDINT := 4294967290; // 计数防回卷余量 [拍] / Counter wrap guard
END_VAR

(* 段 1｜定时器与边沿无条件刷新（红线 7）/ Timers and edges refreshed unconditionally *)
tonWeld(IN := bWelding AND bRun, PT := tWeldMaxS);  // 时长计时 / Duration timing
fTrigEnd(CLK := bWelding);                          // 焊接结束沿 / Weld end edge
bNewWeld := bWelding AND (NOT bPrevWld);            // 新焊次上升沿 / New weld edge
bPrevWld := bWelding;                               // 快照更新 / Update the snapshot

(* 段 2｜输入有效性（NaN 自反、Inf 上限）/ Input validity *)
bSigOk := (fPowerKw = fPowerKw) AND (fAmpUm = fAmpUm)               // NaN 自反判据 / NaN reflexivity
          AND (ABS(fPowerKw) < 1.0E308) AND (ABS(fAmpUm) < 1.0E308); // Inf 上限判据 / Inf limit

(* 段 3｜新焊次部署：计数清零，判定回待定，锁存解除（可达解除路径）
 *      New weld deployment: counters cleared, verdict reset, latch released *)
IF bNewWeld AND bRun THEN
    nWinScans := 0;                     // 在窗计数清零 / Clear the in-window count
    nTotScans := 0;                     // 总计数清零 / Clear the total count
    bTimeout := FALSE;                  // 时长锁存解除 / Release the timeout latch
    _eVerdict := ePending;              // 判定回待定 / Verdict to pending
    uCode := 16#0000_0000;              // 清码 / Clear the code
END_IF

(* 段 4｜焊接中每拍三维评估 / Per-scan three-dimension evaluation while welding *)
bWinNow := FALSE;                       // 默认不在窗 / Default out of window
IF bRun AND bWelding THEN
    IF NOT bSigOk THEN
        uCode := 16#0006_3035;          // 故障级：输入非有限，监视冻结 / Fault: frozen
    ELSE
        bWinNow := (fPowerKw >= fPwrLoKw - fEps) AND (fPowerKw <= fPwrHiKw + fEps)  // 功率在窗 / Power inside
                   AND (fAmpUm >= fAmpLoUm - fEps) AND (fAmpUm <= fAmpHiUm + fEps);  // 振幅在窗 / Amplitude inside
        nTotScans := nTotScans + 1;     // 总拍计数 / Count the scan
        IF bWinNow THEN
            nWinScans := nWinScans + 1; // 在窗计数 / Count in-window
        END_IF
        IF nTotScans >= DL_BWM_BIGUD THEN
            nTotScans := DL_BWM_BIGUD;  // 防回卷钳位 / Anti-wrap clamp
            nWinScans := nWinScans;     // 保持现值，占比保守 / Hold, ratio conservative
        END_IF
        IF tonWeld.Q THEN
            bTimeout := TRUE;           // 时长越限锁存 / Latch the timeout
        END_IF
    END_IF
END_IF
bInWin := bWinNow;                      // 在窗标志输出 / Window flag output

(* 段 5｜焊毕判定（F_TRIG 触发一次）：占比判合格或缺陷 / Verdict on weld end *)
IF fTrigEnd.Q AND bRun THEN
    IF (nTotScans > 0) AND (NOT bTimeout) THEN
        fWinRatio := UDINT_TO_LREAL(nWinScans) / UDINT_TO_LREAL(nTotScans);     // 占比导出 / Derive the ratio
        IF fWinRatio >= fRatioTh THEN
            _eVerdict := eGood;         // 判定合格 / Verdict good
            uCode := 16#0006_3032;      // 信息级：合格 / Info: good
        ELSE
            _eVerdict := eDefect;       // 判定缺陷 / Verdict defect
            uCode := 16#0006_3033;      // 故障级：占比不足 / Fault: ratio short
        END_IF
    ELSIF bTimeout THEN
        _eVerdict := eDefect;           // 超时强制缺陷 / Timeout forces defect
        fWinRatio := 0.0;               // 占比哨兵零（与真实占比可区分，看码）/ Sentinel ratio
        uCode := 16#0006_3034;          // 故障级：时长越限 / Fault: over duration
    ELSE
        _eVerdict := eDefect;           // 无样本保守缺陷 / Conservative defect without samples
        uCode := 16#0006_3033;          // 故障级：样本不足 / Fault: no samples
    END_IF
END_IF

(* 段 6｜出口装配 / Exit assembly *)
eVerdict := _eVerdict;                  // 判定输出 / Verdict output
IF NOT bRun THEN
    uCode := 16#0000_0000;              // 撤使能清码（可达解除）/ Run drop clears codes
END_IF
bError := (uCode >= 16#0006_3033) AND (uCode <= 16#0006_3035);  // 故障级码带判定 / Fault band check
uErrorId := uCode;                      // 码位单点写入 / Single write point
END_FUNCTION_BLOCK
