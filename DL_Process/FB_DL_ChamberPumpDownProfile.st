//==============================================================================
// 功能块：FB_DL_ChamberPumpDownProfile ｜ 中文名称：腔体抽气曲线包络监视
// 所属子库：DL_Process ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：真空腔体抽气过程包络监视——启动时锁定基线压力，以指数衰减
//           包络为参照：包络上界 p_env(t) = fBasePa x EXP(-t/tau 包络)，
//           实测压力高于上界（衰减慢于包络）持续 tSlopeTimeout → 抽速
//           异常早停（bPumpAbortReq 锁存）；滚动窗内压力样本统计（窗口
//           极差）用于判「压力停滞」（极差 < 停滞阈且未达目标真空，同
//           样归入抽速异常）。达目标真空 → 抽气完成放行（信息级）。
//           斜率判据与窗统计互为冗余：一条失效另一条仍可兜住（如压力
//           缓慢泄漏时斜率判据先报，压力卡死时停滞判据先报）。
// 遗留假设（R95 代理阈值三句）：① 代理值 = fCycleTimeS 组态扫描周期
//           [秒]（包络时间基量）；② 覆盖 0.001~0.1 秒任务周期范围；
//           ③ 覆盖不到的区间由调用方按实际任务周期重设该引脚负责，
//           该假设挂编译验证债。
// 开源溯源 (Origin)：道莅原创实现（参考真空系统抽气曲线与抽速异常判定工程惯例 分类与参数域）
// 单位表：压力[帕] / 目标真空[帕] / 包络时间常数[秒] / 时间[ms] /
//         停滞阈[帕] / 极差[帕] / 扫描周期[秒] / 样本计数[次]
// 错误码表：16#0005_01F2 信息级（抽气完成：达目标真空放行，不置
//           bError）/ 16#0005_01F3 信息级（包络逼近预警：实测压力进入
//           包络上界 1.2 倍预警带，不置 bError）/ 16#0005_0330 故障级
//           （组态非法：目标/包络/阈值域、时间窗 <= 0 或任一输入非
//           有限，置 bError）/ 16#0005_0331 故障级（抽速异常早停：斜率
//           判据或停滞判据确认，bPumpAbortReq 锁存，置 bError——该场景
//           不可由 0330 的组态类判据观测，属工艺过程独立域）/
//           16#0005_0332 故障级兜底（状态机落 ELSE，置 bError）
// 状态机：E_DL_PumpDownState（五态：eIdle=0 / ePumping=10 / eDone=20 /
//           eAbort=30 / eFault=99），CASE 含 ELSE 兜底，ELSE 置 0332 并
//           撤早停请求外的全部输出
// 边界行为：① 组态非法 → 故障态锁存，bReset 复位；② 启动拍锁定基线
//           （基线取当拍实测，非魔法数）；③ 压力非有限 → 归入抽速异常
//           域早停（0331 复用，R90：传感器数据不可信时早停为安全侧）；
//           ④ 早停锁存至 bReset；⑤ 未启动/故障态早停请求撤零并
//           bValid := FALSE（空闲态不挂请求，防误触发停泵）；⑥ 窗口
//           样本环形缓存 8 点，满窗前停滞判据不生效（样本不足不判）。
// 修订历史：v1.0.0 2026-11-17 首版（R24 派单 · ROADMAP P1 §708）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_PumpDownState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 抽气监视相位，每个成员在 CASE 中有且仅有一个标签。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_PumpDownState :
(
    eIdle    := 0,   // 空闲：等启动沿 / Idle, awaiting start edge
    ePumping := 10,  // 抽气：包络与停滞双判据监视 / Pumping, envelope and stagnation dual monitoring
    eDone    := 20,  // 完成：达目标真空放行 / Done, target vacuum reached
    eAbort   := 30,  // 早停：抽速异常锁存 / Abort, pumping anomaly latched
    eFault   := 99   // 故障：组态非法/非法状态 / Fault, config or illegal state
);
END_TYPE

FUNCTION_BLOCK FB_DL_ChamberPumpDownProfile
VAR_INPUT
    bStart       : BOOL;                    // 启动请求 [—]，上升沿生效 / Start request, rising edge
    bReset       : BOOL;                    // 故障复位 [—]，上升沿清锁存 / Fault reset, rising edge clears latches
    fPressPa     : LREAL;                   // 腔压实测 [帕]（绝对压力） / Chamber pressure [Pa], absolute
    fTargetPa    : LREAL := 10.0;           // 目标真空 [帕]，须 > 0 / Target vacuum [Pa], must be > 0
    fTauEnvS     : LREAL := 60.0;           // 包络时间常数 [秒]，须 > 0 / Envelope time constant [s]
    fStagThreshPa: LREAL := 0.5;            // 停滞阈 [帕]（窗极差低于此判停滞） / Stagnation threshold [Pa]
    fSlopeMargin : LREAL := 1.2;            // 包络预警带倍数 [倍]（须 >= 1） / Envelope warning margin [ratio]
    tSlopeTimeout: TIME  := T#30S;          // 抽速异常确认窗 [ms]，须 > 0 / Anomaly confirm window [ms]
    fCycleTimeS  : LREAL := 0.01;           // 任务扫描周期 [秒]，须 > 0（R95 代理阈值） / Task scan cycle [s], must be > 0, R95 proxy
END_VAR
VAR_OUTPUT
    bPumpAbortReq : BOOL;                   // 抽速异常早停请求 [—]（锁存保持） / Pump-abort request, latched
    bPumpDownDone : BOOL;                   // 抽气完成 [—]（完成态电平） / Pump-down done, completion level
    fEnvPressPa   : LREAL;                  // 包络上界 [帕]（诊断出口） / Envelope ceiling [Pa], diagnostics outlet
    eState        : E_DL_PumpDownState;     // 相位出口 [—] / Phase outlet
    eErr          : UDINT;                  // 错误码，0 = 无错，码位 16#0005_01F2 起信息级、16#0005_0330 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError        : BOOL;                   // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid        : BOOL;                   // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbSlope  : TON;                         // 抽速异常确认计时（每拍无条件刷新）[ms] / Anomaly confirm timer, refreshed unconditionally
    _eState  : E_DL_PumpDownState := E_DL_PumpDownState.eIdle; // 当前相位 / Current phase
    _bCfgBad : BOOL;                        // 组态非法锁存 / Illegal config latch
    _bAbortL : BOOL;                        // 早停锁存 / Abort latch
    _bInfoDone: BOOL;                       // 完成信息当拍标志 / Done info flag of this scan
    _bInfoWarn: BOOL;                       // 预警信息当拍标志 / Warning info flag of this scan
    _fBasePa : LREAL;                       // 启动基线压力 [帕] / Startup baseline pressure [Pa]
    _fElapsedS: LREAL;                      // 抽气累计时间 [秒] / Elapsed pumping time [s]
    _afWin   : ARRAY[0..7] OF LREAL;        // 滚动窗样本环形缓存 [帕] / Rolling-window sample ring [Pa]
    _nWinIdx : INT;                         // 环形缓存写指针 [次] / Ring write index [count]
    _nWinFill: INT;                         // 环形缓存已填数 [次] / Ring fill count [count]
    _bSlopeBad: BOOL;                       // 斜率判据电平（确认窗条件） / Slope-criterion level
    _bStagBad : BOOL;                       // 停滞判据电平（确认窗条件） / Stagnation-criterion level
    _bIllegal : BOOL;                       // 非法状态标志 / Illegal state flag
    _bInit    : BOOL := FALSE;              // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
END_VAR
VAR CONSTANT
    DL_CPD_INF    : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_CPD_EPS    : LREAL := 1.0E-6;        // 浮点判零容差 [帕] / Float zero tolerance [Pa]
    DL_CPD_WIN    : INT    := 8;            // 滚动窗容量 [次] / Rolling-window capacity [count]
    DL_CPD_ZERO   : LREAL := 0.0;           // 零值常量，避免裸字面量 [混合] / Zero constant, avoids a bare literal
END_VAR
VAR
    nI       : INT;                         // 极差统计循环索引 [次] / Range-statistics loop index
    fWinHi   : LREAL;                       // 窗内最大值 [帕] / Window maximum [Pa]
    fWinLo   : LREAL;                       // 窗内最小值 [帕] / Window minimum [Pa]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：早停请求先撤（安全侧；锁存态在段 6 重置），标志预清零
 *      Abort request cleared first, flags pre-cleared
 *-----------------------------------------------------------------------------*)
bPumpAbortReq := FALSE;                  // 早停请求先撤（锁存态在段 6 重置） / Abort request cleared first
bPumpDownDone := FALSE;                  // 完成电平先清 / Done level cleared first
fEnvPressPa   := DL_CPD_ZERO;            // 包络出口每拍重算 / Envelope outlet recomputed
eErr   := 16#0000_0000;                  // 错误码每拍重算 / Error code recomputed
bError := FALSE;                         // 故障标志每拍重算 / Fault flag recomputed
bValid := FALSE;                         // 可用标志每拍重算 / Usable flag recomputed
_bInfoDone := FALSE;                     // 完成信息预清零 / Done info pre-cleared
_bInfoWarn := FALSE;                     // 预警信息预清零 / Warn info pre-cleared
_bIllegal  := FALSE;                     // 非法状态预清零 / Illegal flag pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState  := E_DL_PumpDownState.eIdle; // 相位空闲起步 / Phase starts idle
    _bCfgBad := FALSE;                   // 组态锁存清零 / Config latch cleared
    _bAbortL := FALSE;                   // 早停锁存清零 / Abort latch cleared
    _fElapsedS := DL_CPD_ZERO;           // 累计时间清零 / Elapsed time cleared
    _nWinIdx := 0;                       // 写指针归零 / Write index reset
    _nWinFill := 0;                      // 已填数归零 / Fill count reset
    _bInit   := TRUE;                    // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜组态防御闸：非有限（R79）+ 目标/包络/阈值/时间窗域
 *      Configuration defense gates
 *-----------------------------------------------------------------------------*)
IF (fTargetPa <> fTargetPa) OR (ABS(fTargetPa) > DL_CPD_INF)
   OR (fTauEnvS <> fTauEnvS) OR (ABS(fTauEnvS) > DL_CPD_INF)
   OR (fStagThreshPa <> fStagThreshPa) OR (ABS(fStagThreshPa) > DL_CPD_INF)
   OR (fSlopeMargin <> fSlopeMargin) OR (ABS(fSlopeMargin) > DL_CPD_INF)
   OR (fCycleTimeS <> fCycleTimeS) OR (ABS(fCycleTimeS) > DL_CPD_INF) THEN
    _bCfgBad := TRUE;                    // 非有限归组态非法锁存 / Non-finite folded into the config latch
END_IF
IF (NOT _bCfgBad) AND ((fTargetPa <= DL_CPD_EPS) OR (fTauEnvS <= DL_CPD_EPS)
   OR (fStagThreshPa <= DL_CPD_EPS) OR (fSlopeMargin < 1.0)
   OR (tSlopeTimeout <= T#0MS) OR (fCycleTimeS <= DL_CPD_EPS)) THEN
    _bCfgBad := TRUE;                    // 目标/包络/阈值/时间窗域非法锁存 / Target, envelope, threshold and window domains latched
END_IF
IF bReset THEN
    _bCfgBad := FALSE;                   // 复位清组态锁存 / Reset clears the config latch
    _bAbortL := FALSE;                   // 复位清早停锁存 / Reset clears the abort latch
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜确认窗无条件刷新（R40：CASE 之外每拍必调）
 *      Confirm timer refreshed unconditionally per R40
 *-----------------------------------------------------------------------------*)
fbSlope(IN := (_eState = E_DL_PumpDownState.ePumping)
             AND (_bSlopeBad OR _bStagBad), PT := tSlopeTimeout); // 抽速异常确认窗 / Anomaly confirm window

(*------------------------------------------------------------------------------
 * 段 5｜相位机与双判据链（CASE 含 ELSE 兜底；状态改写只出现在分支判据内，R39）
 *      Phase machine and the dual-criteria chain
 *-----------------------------------------------------------------------------*)
CASE _eState OF

    E_DL_PumpDownState.eIdle:              // 空闲：启动沿且组态合法进抽气
        IF bStart AND (NOT _bCfgBad) THEN
            _fBasePa := fPressPa;          // 基线锁定（启动拍实测，非魔法数） / Baseline locked at start
            _fElapsedS := DL_CPD_ZERO;     // 累计时间归零 / Elapsed time reset
            _nWinIdx := 0;                 // 写指针归零 / Write index reset
            _nWinFill := 0;                // 已填数归零（满窗前停滞判据不生效） / Fill reset, stagnation inert before the full window
            _eState := E_DL_PumpDownState.ePumping; // 进抽气 / To pumping
        ELSIF bStart AND _bCfgBad THEN
            _eState := E_DL_PumpDownState.eFault; // 组态非法进故障 / Illegal config to fault
        END_IF

    E_DL_PumpDownState.ePumping:           // 抽气：包络/停滞双判据 + 目标判定
        IF _bCfgBad THEN
            _eState := E_DL_PumpDownState.eFault; // 组态漂移转故障 / Config drift, fault
        ELSIF fPressPa <= fTargetPa THEN
            _bInfoDone := TRUE;            // 达目标真空（信息级，拍 N 进入） / Target vacuum reached, info
            _eState := E_DL_PumpDownState.eDone; // 本拍转出：进完成 / To done
        ELSE
            _fElapsedS := _fElapsedS + fCycleTimeS; // 累计时间推进 [秒] / Elapsed time advanced
            IF (fPressPa <> fPressPa) OR (ABS(fPressPa) > DL_CPD_INF) THEN
                _bSlopeBad := TRUE;        // 腔压非有限归抽速异常域（传感器数据不可信，早停安全侧，0331 复用 R90） / Non-finite pressure folded into the anomaly domain
            ELSE
                fEnvPressPa := _fBasePa * EXP(-_fElapsedS / fTauEnvS); // 包络上界 [帕]，分母已闸 / Envelope ceiling, denominator gated
                _bSlopeBad := fPressPa > (fSlopeMargin * fEnvPressPa); // 斜率判据：衰减慢于包络 / Slope criterion: slower than the envelope
            END_IF
            _afWin[_nWinIdx] := fPressPa;  // 样本入环 / Sample into the ring
            _nWinIdx := (_nWinIdx + 1) MOD DL_CPD_WIN; // 写指针环形推进（模 8，归一安全） / Ring index advance, modulo-normalised
            IF _nWinFill < DL_CPD_WIN THEN
                _nWinFill := _nWinFill + 1; // 已填数推进 / Fill count advanced
            END_IF
            IF _nWinFill >= DL_CPD_WIN THEN
                fWinHi := _afWin[0];       // 窗极差统计起步 / Range statistics start
                fWinLo := _afWin[0];       // 窗极差统计起步 / Range statistics start
                FOR nI := 1 TO (DL_CPD_WIN - 1) DO
                    IF _afWin[nI] > fWinHi THEN
                        fWinHi := _afWin[nI]; // 窗内最大值 / Window maximum
                    END_IF
                    IF _afWin[nI] < fWinLo THEN
                        fWinLo := _afWin[nI]; // 窗内最小值 / Window minimum
                    END_IF
                END_FOR
                _bStagBad := (fWinHi - fWinLo) < fStagThreshPa; // 停滞判据：窗极差低于阈 / Stagnation: range below the threshold
            ELSE
                _bStagBad := FALSE;        // 样本不足不判停滞（边界行为⑥） / Sample insufficient, no stagnation verdict
            END_IF
            IF fbSlope.Q THEN
                _bAbortL := TRUE;          // 抽速异常确认，早停锁存（拍 N 进入） / Anomaly confirmed, abort latched
                _eState := E_DL_PumpDownState.eAbort; // 本拍转出：进早停 / To abort
            END_IF
        END_IF

    E_DL_PumpDownState.eDone:              // 完成：等启动撤销回空闲（同拍重启防抖）
        IF NOT bStart THEN
            _eState := E_DL_PumpDownState.eIdle; // 回空闲 / Back to idle
        END_IF

    E_DL_PumpDownState.eAbort:             // 早停：请求锁存保持，bReset 才解除
        IF bReset AND (NOT _bCfgBad) THEN
            _bAbortL := FALSE;             // 复位清早停锁存 / Reset clears the abort latch
            _eState := E_DL_PumpDownState.eIdle; // 回空闲 / Back to idle
        END_IF

    E_DL_PumpDownState.eFault:             // 故障：复位沿且组态恢复回空闲
        IF bReset AND (NOT _bCfgBad) THEN
            _eState := E_DL_PumpDownState.eIdle; // 回空闲 / Back to idle
        END_IF

    ELSE                                   // 非法状态兜底（R21：CASE 必带 ELSE）
        _bIllegal := TRUE;                 // 标记非法状态 / Flag the illegal state
        _eState := E_DL_PumpDownState.eFault; // 回故障态 / Back to fault
END_CASE

IF (_eState = E_DL_PumpDownState.ePumping) AND (_fElapsedS > DL_CPD_EPS)
   AND (fPressPa > (fSlopeMargin * fEnvPressPa)) THEN
    _bInfoWarn := TRUE;                    // 包络逼近预警带（信息级） / Envelope approach warning, info
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜码位出口与放行（故障级码 3 行内置 bError，R45/R101 配对）
 *      Code outlet and release, fault codes paired with bError
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN
    eErr   := 16#0005_0332;                // 故障级：状态机兜底 / Fault: state machine fallback
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bCfgBad THEN
    eErr   := 16#0005_0330;                // 故障级：组态非法 / Fault: illegal configuration
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bAbortL THEN
    eErr   := 16#0005_0331;                // 故障级：抽速异常早停锁存 / Fault: pumping anomaly, abort latched
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bInfoWarn THEN
    eErr := 16#0005_01F3;                  // 信息级：包络逼近预警 / Info: envelope approach warning
ELSIF _bInfoDone THEN
    eErr := 16#0005_01F2;                  // 信息级：抽气完成放行 / Info: pump-down done
END_IF

bPumpAbortReq := _bAbortL;               // 早停请求出口 = 锁存量（R99，空闲态不挂请求） / Abort outlet equals the latch
bPumpDownDone := (_eState = E_DL_PumpDownState.eDone); // 完成电平挂状态量 / Done level bound to the state
bValid := (NOT bError) AND (_eState <> E_DL_PumpDownState.eIdle); // 空闲/故障输出不可用 / Outputs unusable in idle or fault
eState := _eState;                       // 相位出口 / Phase outlet
END_FUNCTION_BLOCK
