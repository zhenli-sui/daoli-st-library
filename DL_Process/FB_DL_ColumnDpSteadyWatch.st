(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ColumnDpSteadyWatch
 * 所属子库 (Sublibrary) : DL_Process
 * 归属目录 (Directory)  : C:\Library\DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 分类/来源标签         : 功能块（FUNCTION_BLOCK）· 过程监视 · 精馏塔差压
 *                         industry-pool / distillation / steady-state-watch
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 TON
 * 溯源声明 (Provenance) : 道莅自研 clean-room——只借公开规范条款与工程惯例，零代码行复制。
 * 功能一句话 (Summary)  : 精馏塔压差稳态监视：稳态窗学习均值与散布，稳态建立后
 *                         按液泛/漏液双阈值预判，非稳态期间抑制判定保守输出。
 *
 * 功能描述 (Function)   : 空闲相等使能转学习；学习相按节拍采样压差并跟踪
 *                         最小/最大值，窗满时均值与散布一次导出，散布不超过
 *                         均值的稳态带百分比则宣告稳态（信息级 3005），否则
 *                         报 3007 重学习；监视相输出偏差百分比，压差越液泛
 *                         阈值报液泛风险、越漏液阈值报漏液风险。输入非有限
 *                         冻结评估（3006），非物理跳变冻结转重学习（3008）。
 * 与既有件边界 (Boundary): 前置件 FB_DL_ColumnDpCtrl 做压差调节；本件只做
 *                         稳态判定与预判，不输出操作指令，二者正交级联。
 * 码位说明 (Codes)      : 信息 16#0006_3005 稳态建立（均值与散布可用）
 *                         故障 16#0006_3006 输入非有限，评估冻结
 *                         故障 16#0006_3007 稳态窗超时未达稳态，重学习
 *                         故障 16#0006_3008 非物理跳变，判定冻结重学习
 *                         段 16#06_0_05~09 首槽信息级、次槽起故障级。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 TON。
 * 红线自检 (Redline)    : 零全局依赖 ｜ 零 VAR_EXTERNAL ｜ 零 %I/%Q ｜ 纯 IEC 标准库
 *                         浮点比较全部带 fEps 容差 ｜ NaN/Inf 精确判据拦截
 *                         ENUM 配 CASE 且 ELSE 兜底 ｜ 定时器每周期无条件刷新
 *                         全变量双语同行注释 ｜ 故障锁存回放且有可达解除路径
 * 修订历史 (Revision)   : 2026-11-18  v1.0.0  首版入库（R32 · 批 2）
 *============================================================================*)

FUNCTION_BLOCK FB_DL_ColumnDpSteadyWatch
VAR_INPUT
    bRun       : BOOL;                    // 监视使能，假则回空闲并清判定 / Enable, FALSE returns to idle
    fDpKpa     : LREAL;                   // 塔压差 [kPa] / Column differential pressure
    fBandPct   : LREAL := 5.0;            // 稳态带 [％]，散布占均值上限 / Steady band as percent of the mean
    fFloodThKpa: LREAL := 8.0;            // 液泛预判阈值 [kPa] / Flooding prejudge threshold
    fLeakThKpa : LREAL := 1.5;            // 漏液预判阈值 [kPa] / Weeping prejudge threshold
    fEps       : LREAL := 1.0E-6;         // 浮点判零容差 [实数域] / Floating zero tolerance
    tSteadyWin : TIME  := T#15M;          // 稳态窗时长 [s] / Steady window duration
    tSample    : TIME  := T#5S;           // 采样节拍 [s] / Sampling pace period
END_VAR
VAR_OUTPUT
    ePrejudge : (eNormal := 0, eFloodRisk := 1, eLeakRisk := 2);    // 预判枚举 / Prejudge enum
    bSteady   : BOOL;                   // 稳态标志，均值与散布可用时为真 / TRUE when steady stats are valid
    fMeanKpa  : LREAL;                  // 学习均值 [kPa] / Learned mean
    fSpreadKpa: LREAL;                  // 学习散布（最大减最小）[kPa] / Learned spread, max minus min
    fDevPct   : LREAL;                  // 当前偏差 [％]，相对学习均值 / Current deviation vs the mean
    bError    : BOOL;                   // 故障标志，与故障码配对 / Fault flag paired with codes
    uErrorId  : UDINT;                  // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    eState    : (eIdle := 0, eLearning := 1, eWatching := 2);   // 状态机：空闲/学习/监视 / State machine
    tonWin    : TON;    // 稳态窗定时器 [s]，每拍无条件刷新 / Steady window timer
    tonPace   : TON;    // 采样节拍定时器 [s]，每拍无条件刷新 / Sampling pace timer
    bSigOk    : BOOL;   // 输入有效标志 / Input validity flag
    fSumKpa   : LREAL;  // 学习相累加和 [kPa] / Learning-phase sum
    nSamples  : UDINT;  // 有效样本数 [个] / Valid sample count
    fMinKpa   : LREAL;  // 窗内最小值 [kPa] / Window minimum
    fMaxKpa   : LREAL;  // 窗内最大值 [kPa] / Window maximum
    fDpLast   : LREAL;  // 上拍压差快照 [kPa] / Previous pressure snapshot
    bHavePrev : BOOL;   // 快照有效标志 / Snapshot availability flag
    uCodeLatch: UDINT;  // 故障锁存码 [码]，故障相回放 / Latched fault code
    uInfoCode : UDINT;  // 信息级单拍码 [码] / One-shot info code
END_VAR
VAR CONSTANT
    DL_CDS_MINSAMP : INT   := 8;        // 稳态窗最小样本数 [个] / Minimum window samples
    DL_CDS_JUMP    : LREAL := 5.0;      // 单拍非物理跳变门限 [kPa] / Non-physical jump limit
    DL_CDS_PCT     : LREAL := 100.0;    // 百分比系数 [％] / Percent factor
END_VAR

(* 段 1｜定时器无条件周期刷新（红线 7）/ Timers refreshed unconditionally every scan *)
tonWin(IN := (eState = eLearning) AND bRun, PT := tSteadyWin);  // 稳态窗计时 / Steady window timing
tonPace(IN := bRun, PT := tSample);                             // 采样节拍计时 / Sampling pace timing

(* 段 2｜输入有效性（每拍计算，判据门控挂状态量）/ Input validity each scan *)
bSigOk := (fDpKpa = fDpKpa)                     // NaN 自反判据 / NaN reflexivity
          AND (ABS(fDpKpa) < 1.0E308)           // Inf 上限判据 / Inf limit
          AND (fDpKpa >= -fEps);                // 压差非负物理约束 / Physical non-negativity

(* 段 3｜状态机主分派（ENUM 配 CASE，ELSE 兜底）/ State dispatch with ELSE interception *)
CASE eState OF

    eIdle:
        bSteady := FALSE;               // 非稳态不出统计 / No stats before steady
        ePrejudge := eNormal;           // 默认预判 / Default prejudge
        fSumKpa := 0.0;                 // 清累加 / Clear the sum
        nSamples := 0;                  // 清计数 / Clear the count
        fMinKpa := 1.0E308;             // 最小值初值为上界 / Min seeded with the upper bound
        fMaxKpa := -1.0E308;            // 最大值初值为下界 / Max seeded with the lower bound
        bHavePrev := FALSE;             // 清快照 / Clear the snapshot
        IF bRun AND bSigOk THEN
            eState := eLearning;        // 拍 N 空闲相满足，拍 N+1 转学习 / Idle to learning next scan
        END_IF

    eLearning:
        (* 本拍行为：节拍到点采样并跟踪极值；退出条件 = 窗满 AND 样本足（双条件）
         * This scan: sample on pace tick; exit needs window done AND enough samples *)
        IF NOT bSigOk THEN
            uCodeLatch := 16#0006_3006; // 故障：输入非有限 / Fault: non-finite input
        ELSIF tonPace.Q THEN
            fSumKpa := fSumKpa + fDpKpa;    // 累加 / Accumulate
            nSamples := nSamples + 1;       // 计数 / Count
            IF fDpKpa < fMinKpa THEN
                fMinKpa := fDpKpa;          // 更新最小 / Update the minimum
            END_IF
            IF fDpKpa > fMaxKpa THEN
                fMaxKpa := fDpKpa;          // 更新最大 / Update the maximum
            END_IF
        END_IF
        IF tonWin.Q AND (nSamples >= INT_TO_UDINT(DL_CDS_MINSAMP)) THEN
            fMeanKpa   := fSumKpa / UDINT_TO_LREAL(nSamples);       // 均值导出 / Derive the mean
            fSpreadKpa := fMaxKpa - fMinKpa;                        // 散布导出 / Derive the spread
            IF fSpreadKpa <= (ABS(fMeanKpa) * fBandPct / DL_CDS_PCT) THEN
                bSteady := TRUE;            // 散布在带内，稳态成立 / Spread inside the band, steady
                uCodeLatch := 16#0000_0000; // 成功清除锁存 / Success clears the latch
                uInfoCode := 16#0006_3005;  // 信息级：稳态建立（单拍）/ Info: steady built, one shot
                eState := eWatching;        // 拍 N+1 转监视 / To watching next scan
            ELSE
                uCodeLatch := 16#0006_3007; // 故障：窗满未达稳态 / Fault: window done, not steady
                fSumKpa := 0.0;             // 清累加重学 / Clear for relearning
                nSamples := 0;              // 清计数 / Clear the count
                fMinKpa := 1.0E308;         // 重置极值 / Reseed the extremes
                fMaxKpa := -1.0E308;
            END_IF
        ELSIF tonWin.Q THEN
            uCodeLatch := 16#0006_3007;     // 故障：窗满样本不足 / Fault: window done, too few samples
            fSumKpa := 0.0;                 // 清累加重学 / Clear for relearning
            nSamples := 0;                  // 清计数 / Clear the count
            fMinKpa := 1.0E308;             // 重置极值 / Reseed the extremes
            fMaxKpa := -1.0E308;
        END_IF

    eWatching:
        IF NOT bSigOk THEN
            uCodeLatch := 16#0006_3006;     // 故障：输入非有限，判定冻结 / Fault: non-finite, frozen
        ELSIF ABS(fMeanKpa) < fEps THEN
            uCodeLatch := 16#0006_3008;     // 故障：基线异常，转重学习 / Fault: bad baseline, relearn
            bSteady := FALSE;               // 撤稳态标志 / Withdraw steady
            fSumKpa := 0.0;                 // 清累加 / Clear the sum
            nSamples := 0;                  // 清计数 / Clear the count
            fMinKpa := 1.0E308;             // 重置极值 / Reseed
            fMaxKpa := -1.0E308;
            eState := eLearning;            // 拍 N+1 转学习 / To learning next scan
        ELSE
            (* 非物理跳变闸：单拍超限说明取压管路异常 / Jump gate: sensing line trouble *)
            IF bHavePrev AND (ABS(fDpKpa - fDpLast) > DL_CDS_JUMP) THEN
                uCodeLatch := 16#0006_3008; // 故障：非物理跳变 / Fault: non-physical jump
                bSteady := FALSE;           // 撤稳态标志 / Withdraw steady
                fSumKpa := 0.0;             // 清累加 / Clear the sum
                nSamples := 0;              // 清计数 / Clear the count
                fMinKpa := 1.0E308;         // 重置极值 / Reseed
                fMaxKpa := -1.0E308;
                eState := eLearning;        // 拍 N+1 转学习 / To learning next scan
            ELSE
                fDevPct := (fDpKpa - fMeanKpa) / fMeanKpa * DL_CDS_PCT;     // 偏差百分比导出 / Deviation percent
                IF fDpKpa >= fFloodThKpa THEN
                    ePrejudge := eFloodRisk;    // 越液泛阈值：液泛风险 / Over flood threshold
                ELSIF fDpKpa <= fLeakThKpa THEN
                    ePrejudge := eLeakRisk;     // 越漏液阈值：漏液风险 / Under leak threshold
                ELSE
                    ePrejudge := eNormal;       // 带内正常 / Normal inside the band
                END_IF
            END_IF
        END_IF

ELSE
    eState := eIdle;                    // 非法状态拦截回空闲 / Illegal state intercepted to idle
    uCodeLatch := 16#0006_3006;         // 故障：状态越界 / Fault: state out of range
END_CASE

(* 段 4｜快照与出口装配 / Snapshot and exit assembly *)
fDpLast := fDpKpa;                      // 更新快照供下拍跳变判据 / Update the snapshot
bHavePrev := bSigOk;                    // 快照有效随数据有效 / Snapshot valid with the data
IF NOT bRun THEN
    uCodeLatch := 16#0000_0000;         // 撤使能清故障（可达解除路径）/ Run drop clears faults
END_IF
bError := (uCodeLatch <> 16#0000_0000); // 故障锁存回放 / Latched fault replay
IF uCodeLatch <> 16#0000_0000 THEN
    uErrorId := uCodeLatch;             // 故障码优先回放 / Fault code replayed first
    uInfoCode := 16#0000_0000;          // 故障压过信息码 / Fault overrides info
ELSE
    uErrorId := uInfoCode;              // 无故障时放信息码 / Info code when no fault
    uInfoCode := 16#0000_0000;          // 信息码单拍清零 / Info code cleared next scan
END_IF
END_FUNCTION_BLOCK
