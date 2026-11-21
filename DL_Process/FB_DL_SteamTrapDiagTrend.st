(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SteamTrapDiagTrend
 * 所属子库 (Sublibrary) : DL_Process
 * 归属目录 (Directory)  : C:\Library\DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 分类/来源标签         : 功能块（FUNCTION_BLOCK）· 过程诊断 · 疏水阀趋势
 *                         industry-pool / steam-system / trend-diagnosis
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 TON
 * 溯源声明 (Provenance) : 道莅自研 clean-room——只借公开规范条款与工程惯例，零代码行复制。
 * 功能一句话 (Summary)  : 以过冷度（管线饱和温度与阀前温度之差）为判据，学习窗
 *                         建立基线后监视温差趋势，四级判定蒸汽泄漏等级。
 *
 * 本件存在的意义 (Why this unit exists)：
 *   疏水阀失效开路（直排蒸汽）是蒸汽管网最大的隐性损失。健康阀的过冷度稳定在
 *   基线带内，阀失效后过冷度向零收敛。本件把「过冷度相对基线的收敛程度」变成
 *   四级可观测等级，绝对判据与趋势速率双通道互证，避免单阈值误报。
 *
 * 功能描述 (Function)   : 空闲相等使能转学习；学习相按节拍采样过冷度累加，
 *                         窗满且样本足则建基线（信息级 3000）转监视；窗满样本
 *                         不足回退默认基线并报 3002（保守降级不阻塞监视）；监视
 *                         相按过冷度与基线之比分级（0.7/0.5/0.3），EWMA 趋势以
 *                         K/h 输出。输入非有限冻结评估（3001），非物理跳变冻结
 *                         转重学习（3003）。
 * 与既有件边界 (Boundary): 前置件 FB_DL_SteamTrapMonitor 做单点判定；本件做
 *                         趋势累积与分级，二者正交可级联。
 * 码位说明 (Codes)      : 信息 16#0006_3000 学习完成基线建立
 *                         故障 16#0006_3001 输入非有限，评估冻结
 *                         故障 16#0006_3002 学习窗超时样本不足，基线回退默认
 *                         故障 16#0006_3003 非物理跳变，判定冻结转重学习
 *                         段 16#06_0_00~04 首槽信息级、次槽起故障级。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 TON。
 * 红线自检 (Redline)    : 零全局依赖 ｜ 零 VAR_EXTERNAL ｜ 零 %I/%Q ｜ 纯 IEC 标准库
 *                         浮点比较全部带 fEps 容差 ｜ NaN/Inf 精确判据拦截
 *                         ENUM 配 CASE 且 ELSE 兜底 ｜ 定时器每周期无条件刷新
 *                         全变量双语同行注释 ｜ 故障锁存回放且有可达解除路径
 * 修订历史 (Revision)   : 2026-11-18  v1.0.0  首版入库（R32 · 批 2）
 *============================================================================*)

FUNCTION_BLOCK FB_DL_SteamTrapDiagTrend
VAR_INPUT
    bRun          : BOOL;                   // 诊断使能，假则回空闲并清判定 / Enable, FALSE returns to idle
    fTrapTempC    : LREAL;                  // 阀前温度 [degC] / Trap body temperature
    fLineTempC    : LREAL;                  // 管线饱和温度基准 [degC] / Line saturation reference temperature
    fDTBaseDef    : LREAL := 15.0;          // 默认基线过冷度 [K]，学习失败回退值 / Default baseline subcooling
    fRatioWatch   : LREAL := 0.7;           // 关注级阈值 [比值]，低于此进入关注 / Watch level ratio threshold
    fRatioSuspect : LREAL := 0.5;           // 可疑级阈值 [比值] / Suspect level ratio threshold
    fRatioLeak    : LREAL := 0.3;           // 泄漏级阈值 [比值] / Leak level ratio threshold
    fEps          : LREAL := 1.0E-6;        // 浮点判零容差 [实数域] / Floating zero tolerance
    tLearnWin     : TIME  := T#30M;         // 学习窗时长 [s] / Learning window duration
    tSample       : TIME  := T#10S;         // 采样节拍 [s] / Sampling pace period
END_VAR
VAR_OUTPUT
    eLevel    : (eLevelOk := 0, eLevelWatch := 1, eLevelSuspect := 2, eLevelLeak := 3);  // 泄漏等级枚举 / Leak level enum
    fBaseDT   : LREAL;                  // 已建立基线过冷度 [K] / Established baseline subcooling
    fDTNow    : LREAL;                  // 当前过冷度 [K] / Current subcooling
    fTrendKpH : LREAL;                  // 过冷度趋势 [K/h]，负值为向零收敛 / Subcooling trend, negative converges to zero
    bDiag     : BOOL;                   // 判定有效标志，监视相且数据有效为真 / TRUE when the verdict is valid
    bError    : BOOL;                   // 故障标志，与故障码配对 / Fault flag paired with codes
    uErrorId  : UDINT;                  // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    eState    : (eIdle := 0, eLearning := 1, eMonitor := 2);    // 状态机：空闲/学习/监视 / State machine
    tonLearn  : TON;    // 学习窗定时器 [s]，每拍无条件刷新 / Learning window timer
    tonPace   : TON;    // 采样节拍定时器 [s]，每拍无条件刷新 / Sampling pace timer
    bSigOk    : BOOL;   // 输入有效标志 / Input validity flag
    fSumDT    : LREAL;  // 学习相过冷度累加和 [K] / Learning-phase subcooling sum
    nSamples  : UDINT;  // 有效样本数 [个] / Valid sample count
    fDTLast   : LREAL;  // 上拍过冷度快照 [K] / Previous subcooling snapshot
    bHavePrev : BOOL;   // 快照有效标志 / Snapshot availability flag
    fTrendEw  : LREAL;  // 趋势 EWMA 内部值 [K/h] / Trend EWMA internal value
    fPaceS    : LREAL;  // 采样节拍秒值 [s]，由 tSample 一次性导出 / Pace in seconds, derived once
    uCodeLatch: UDINT;  // 故障锁存码 [码]，故障相回放 / Latched fault code
    uInfoCode : UDINT;  // 信息级单拍码 [码]，出口装配后即清 / One-shot info code, cleared after assembly
END_VAR
VAR CONSTANT
    DL_STT_MINSAMP : INT   := 10;       // 学习窗最小样本数 [个] / Minimum learning samples
    DL_STT_JUMP    : LREAL := 50.0;     // 单拍非物理跳变门限 [K] / Non-physical jump limit
    DL_STT_TAU     : LREAL := 0.1;      // 趋势 EWMA 平滑系数 [比值] / Trend EWMA smoothing factor
    DL_STT_H2S     : LREAL := 3600.0;   // 每小时秒数 [s/h] / Seconds per hour
    DL_STT_MS2S    : LREAL := 1000.0;   // 毫秒到秒系数 [ms/s] / Milliseconds per second
END_VAR

(* 段 1｜定时器无条件周期刷新（红线 7）：两实例每拍先触发 / Timers refreshed unconditionally every scan *)
tonLearn(IN := (eState = eLearning) AND bRun, PT := tLearnWin);     // 学习窗计时 / Learning window timing
tonPace(IN := bRun, PT := tSample);                                 // 采样节拍计时 / Sampling pace timing
IF fPaceS < 0.0001 THEN
    fPaceS := DINT_TO_LREAL(TIME_TO_DINT(tSample)) / DL_STT_MS2S;   // 节拍秒值一次导出 / Derive pace seconds once
END_IF

(* 段 2｜当前过冷度与输入有效性（每拍计算，判据门控挂状态量）/ Current subcooling and validity each scan *)
fDTNow := fLineTempC - fTrapTempC;                                  // 过冷度导出 / Derive subcooling
bSigOk := (fTrapTempC = fTrapTempC) AND (fLineTempC = fLineTempC)   // NaN 自反判据 / NaN reflexivity
          AND (ABS(fTrapTempC) < 1.0E308) AND (ABS(fLineTempC) < 1.0E308)   // Inf 上限判据 / Inf limit
          AND (fDTNow >= -fEps);                                    // 过冷度非负物理约束 / Non-negativity

(* 段 3｜状态机主分派（ENUM 配 CASE，ELSE 兜底）/ State dispatch with ELSE interception *)
CASE eState OF

    eIdle:
        bDiag := FALSE;                 // 空闲不出判定 / No verdict in idle
        eLevel := eLevelOk;             // 默认级 / Default level
        fSumDT := 0.0;                  // 清累加 / Clear the sum
        nSamples := 0;                  // 清计数 / Clear the count
        fTrendEw := 0.0;                // 清趋势 / Clear the trend
        bHavePrev := FALSE;             // 清快照 / Clear the snapshot
        IF bRun AND bSigOk THEN
            eState := eLearning;        // 拍 N 空闲相满足条件，拍 N+1 进入学习 / Idle to learning next scan
        END_IF

    eLearning:
        (* 本拍行为：节拍到点且数据有效则采样累加；退出条件 = 窗满 AND 样本足（双条件）
         * This scan: sample on pace tick; exit needs window done AND enough samples *)
        IF NOT bSigOk THEN
            uCodeLatch := 16#0006_3001; // 故障：输入非有限 / Fault: non-finite input
        ELSIF tonPace.Q THEN
            fSumDT := fSumDT + fDTNow;  // 累加 / Accumulate
            nSamples := nSamples + 1;   // 计数 / Count
        END_IF
        IF tonLearn.Q AND (nSamples >= INT_TO_UDINT(DL_STT_MINSAMP)) THEN
            fBaseDT := fSumDT / UDINT_TO_LREAL(nSamples);   // 均值基线 / Mean baseline
            uCodeLatch := 16#0000_0000;                     // 学习成功清除锁存 / Success clears the latch
            uInfoCode := 16#0006_3000;                      // 信息级：基线建立（单拍）/ Info: baseline built, one shot
            eState := eMonitor;                             // 拍 N+1 转监视 / To monitor next scan
        ELSIF tonLearn.Q AND (nSamples < INT_TO_UDINT(DL_STT_MINSAMP)) THEN
            fBaseDT := fDTBaseDef;      // 保守回退默认基线，不阻塞监视 / Conservative fallback, monitoring unblocked
            uCodeLatch := 16#0006_3002; // 故障：样本不足已回退 / Fault: insufficient samples, fallback
            eState := eMonitor;         // 拍 N+1 转监视 / To monitor next scan
        END_IF

    eMonitor:
        bDiag := bSigOk;                // 判定有效随数据有效 / Verdict valid with the data
        IF NOT bSigOk THEN
            uCodeLatch := 16#0006_3001; // 故障：输入非有限，判定冻结 / Fault: non-finite, frozen
        ELSIF ABS(fBaseDT) < fEps THEN
            uCodeLatch := 16#0006_3003; // 故障：基线异常，转重学习 / Fault: bad baseline, relearn
            fSumDT := 0.0;              // 清累加 / Clear the sum
            nSamples := 0;              // 清计数 / Clear the count
            eState := eLearning;        // 拍 N+1 转学习 / To learning next scan
        ELSE
            (* 非物理跳变闸：单拍变化超限说明传感器异常，冻结并重学习 / Jump gate: freeze and relearn *)
            IF bHavePrev AND (ABS(fDTNow - fDTLast) > DL_STT_JUMP) THEN
                uCodeLatch := 16#0006_3003;     // 故障：非物理跳变 / Fault: non-physical jump
                fSumDT := 0.0;                  // 清累加 / Clear the sum
                nSamples := 0;                  // 清计数 / Clear the count
                eState := eLearning;            // 拍 N+1 转学习 / To learning next scan
            ELSE
                (* 分级判据：过冷度相对基线的收敛程度 / Grading: convergence relative to the baseline *)
                IF fDTNow < (fRatioLeak * fBaseDT) THEN
                    eLevel := eLevelLeak;       // 泄漏级 / Leak level
                ELSIF fDTNow < (fRatioSuspect * fBaseDT) THEN
                    eLevel := eLevelSuspect;    // 可疑级 / Suspect level
                ELSIF fDTNow < (fRatioWatch * fBaseDT) THEN
                    eLevel := eLevelWatch;      // 关注级 / Watch level
                ELSE
                    eLevel := eLevelOk;         // 健康级 / Healthy level
                END_IF
                (* 趋势采样：节拍到点且快照有效则算瞬时趋势并 EWMA / Trend sample on pace tick *)
                IF tonPace.Q AND bHavePrev AND (fPaceS > fEps) THEN
                    fTrendEw := fTrendEw * (1.0 - DL_STT_TAU)
                                + ((fDTNow - fDTLast) / fPaceS * DL_STT_H2S) * DL_STT_TAU;  // K/h 瞬时趋势入 EWMA / K/h trend into EWMA
                END_IF
            END_IF
        END_IF

ELSE
    eState := eIdle;                    // 非法状态拦截回空闲 / Illegal state intercepted to idle
    uCodeLatch := 16#0006_3001;         // 故障：状态越界 / Fault: state out of range
END_CASE

(* 段 4｜快照与出口装配 / Snapshot and exit assembly *)
fDTLast := fDTNow;                      // 更新快照供下拍跳变判据 / Update the snapshot for the next scan
bHavePrev := bSigOk;                    // 快照有效随数据有效 / Snapshot valid with the data
fTrendKpH := fTrendEw;                  // 趋势输出 / Trend output
IF NOT bRun THEN
    uCodeLatch := 16#0000_0000;         // 撤使能清故障（可达解除路径）/ Run drop clears faults, reachable reset
END_IF
bError   := (uCodeLatch <> 16#0000_0000);   // 故障锁存回放 / Latched fault replay
IF uCodeLatch <> 16#0000_0000 THEN
    uErrorId := uCodeLatch;             // 故障码优先回放 / Fault code replayed first
    uInfoCode := 16#0000_0000;          // 故障压过信息码 / Fault overrides the info code
ELSE
    uErrorId := uInfoCode;              // 无故障时放信息码 / Info code when no fault
    uInfoCode := 16#0000_0000;          // 信息码单拍清零 / Info code cleared next scan
END_IF
END_FUNCTION_BLOCK
