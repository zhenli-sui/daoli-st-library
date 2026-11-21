(*
  FC_DL_OscillationIndex  —  回路振荡指数（过零率 x 幅值离散度归一合成）/ Loop oscillation index
  分类 Category : DL_MathData
  码位 Code     : 16#05_0_03
  版本 Version  : 1.0.0
  来源 Source   : t2-4-s7-motion — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : clean-room 实现，过零率与幅值离散度公开统计语义，未复制任何源码行
                  （与 FC_DL_CpkIndex 严格分工：本件判「在抖」— 振荡行为；FC_DL_CpkIndex 判「偏离」— 规格符合度）
  功能 Function : 1) 等间隔采样窗去均值后统计越过 ±fDeadband 的过零次数，得过零频率 fZeroCrossRateHz；
                  2) 幅值离散度 = 去均值绝对偏差均值 / 去均值幅值均值（fAmpDispersion）；
                  3) 两判据各自归一化后取几何平均合成 fOscIndex（0~1 无量纲），越 fOscNormLimit 判 bOscillating。
  边界 Boundary : ① nWindowSize < 8 或超数组上界判码（防越界）；② fSampleDt <= 0 防除零判码；
                  ③ 幅值均值 < fAmpFloor 判静止段：fOscIndex := 0 且 bOscillating := FALSE（不判抖）；
                  ④ fDeadband < 0 取 ABS 并置信息码（不拒算）；
                  ⑤ 非有限样本（NaN/Inf）按非法处理：本窗口无效置码，不输出指数；
                  ⑥ 解除式自证：bOscillating 每调用重算，下一窗指数回落即自动解除（无锁存）。
  依赖 Depends  : 仅 Standard.library（ABS/SQRT/MIN/MAX）；参考对齐 FB_DL_SignalStatistics（已注册，仅命名体例）；
                  分工件 FC_DL_CpkIndex（已注册，判偏离，与本件互不替代）
  码表 Error codes（本件格 05_0_03，子码步进 +0x100）:
    16#0005_0103 信息级：fDeadband 为负，已取 ABS 继续计算
    16#0005_0203 故障级：组态非法（窗长 < 8 / 超数组上界 / fSampleDt <= 0 / 归一化满量程 <= 0）
    16#0005_0303 故障级：采样窗含非有限值（NaN/Inf），本窗无效

  修订历史 Revision :
    2026-11-18  v1.0.0  R38 首版
*)

FUNCTION FC_DL_OscillationIndex : BOOL
VAR_INPUT
    afSampleBuffer : ARRAY[0..255] OF REAL;   // 等间隔采样窗 [工程量] / Equally spaced sample window
    nWindowSize    : INT;                     // 有效窗长 [点]，域 8..256 / Valid window length
    fSampleDt      : REAL;                    // 采样间隔 [s]，域 > 0 / Sample interval
    fDeadband      : REAL;                    // 判抖死区 [工程量单位] / Jitter deadband in engineering units
    fAmpFloor      : REAL := 0.01;            // 幅值均值下限 [工程量单位]，低于判静止 / Amplitude mean floor
    fNormRateHz    : REAL := 5.0;             // 过零率归一化满量程 [Hz]，域 > 0 / Zero-cross rate full-scale for normalization
    fOscNormLimit  : REAL := 0.3;             // 振荡判定阈值 [无量纲 0..1] / Oscillation verdict threshold
END_VAR
VAR_OUTPUT
    fOscIndex      : REAL;                    // 振荡指数 [无量纲 0..1] / Oscillation index
    fZeroCrossRateHz : REAL;                  // 过零频率 [Hz] / Zero-cross rate
    fAmpDispersion : REAL;                    // 幅值离散度 [无量纲] / Amplitude dispersion
    bOscillating   : BOOL;                    // 振荡判定 / Oscillation verdict
    nErrId         : UDINT;                   // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    rMean, rAbsDev, rAmpMean : LREAL;         // 均值/绝对偏差和/幅值均值 / Mean, abs-deviation sum, amplitude mean
    rCross, rWinTime         : LREAL;         // 过零计数/窗时长 / Crossing count, window duration
    rRateN, rDispN, rIdx     : LREAL;         // 归一化过零率/归一化离散度/合成指数 / Normalized rate, dispersion, composite
    rD                       : LREAL;         // 单样本临时量 / Per-sample scratch
    rDb                      : LREAL;         // 死区生效值（负值取 ABS）/ Effective deadband
    k                        : INT;           // 循环计数器 / Loop counter
END_VAR
VAR CONSTANT
    nMinWin   : INT   := 8;       // 最小窗长 [点] / Minimum window length
    nMaxWin   : INT   := 256;     // 数组上界 [点] / Array upper bound
    rFinLim   : LREAL := 1.0E30;  // 非有限值筛查幅值上限 / Non-finite screening cap
    rDispNorm : LREAL := 1.0;     // 离散度归一化满量程（std/mean 量纲） / Dispersion full-scale
END_VAR

(* —— 段 1：输出缺省与组态闸（纯函数，每调用重算） —— *)
fOscIndex := 0.0;  fZeroCrossRateHz := 0.0;  fAmpDispersion := 0.0;   // 输出缺省
bOscillating := FALSE;                                                // 缺省不判抖（安全侧）
nErrId := 16#0000_0000;                                               // 事件码缺省无事件
FC_DL_OscillationIndex := FALSE;                                      // 返回值缺省失败

rDb := LREAL(fDeadband);                                              // 死区暂存
IF rDb < 0.0 THEN
    rDb := -rDb;                                                      // 负死区取 ABS 继续算（规格强制）
    nErrId := 16#0005_0103;                                           // 信息级：死区为负已取 ABS
END_IF

IF (nWindowSize < nMinWin) OR (nWindowSize > nMaxWin)
   OR (LREAL(fSampleDt) <= 0.0) OR (LREAL(fNormRateHz) <= 0.0) THEN
    nErrId := 16#0005_0203;                                           // 故障级：组态非法（覆盖防除零两项）
    RETURN;                                                           // 不进入计算
END_IF

(* —— 段 2：去均值 + 非有限值筛查（NaN 用 x<>x 自反判定，Inf 用幅值上限兜） —— *)
FOR k := 0 TO (nWindowSize - 1) DO
    rD := LREAL(afSampleBuffer[k]);
    IF (rD <> rD) OR (ABS(rD) > rFinLim) THEN
        nErrId := 16#0005_0303;                                       // 故障级：本窗含非有限值
        RETURN;                                                       // 整窗无效，不输出指数
    END_IF
    rMean := rMean + rD;                                              // 均值累加
END_FOR
rMean := rMean / LREAL(nWindowSize);                                  // 窗均值（窗长已闸 >= 8）

(* —— 段 3：幅值均值与过零计数（越过 ±死区计一次完整摆动） —— *)
FOR k := 0 TO (nWindowSize - 1) DO
    rD := LREAL(afSampleBuffer[k]) - rMean;                           // 去均值
    rAbsDev := rAbsDev + ABS(rD);                                     // 绝对偏差累加
END_FOR
rAmpMean := rAbsDev / LREAL(nWindowSize);                             // 幅值均值（平均绝对偏差）

FOR k := 1 TO (nWindowSize - 1) DO
    IF ((afSampleBuffer[k - 1] - REAL(rMean) < -REAL(rDb)) AND (afSampleBuffer[k] - REAL(rMean) >= REAL(rDb)))
       OR ((afSampleBuffer[k - 1] - REAL(rMean) > REAL(rDb)) AND (afSampleBuffer[k] - REAL(rMean) <= REAL(rDb))) THEN
        rCross := rCross + 1.0;                                       // 由 -侧 越到 +侧（或反向）：计 1 次过零
    END_IF
END_FOR

(* —— 段 4：静止段短路（幅值均值低于下限不判抖） —— *)
IF rAmpMean < LREAL(fAmpFloor) THEN
    fOscIndex := 0.0;                                                 // 静止段：指数 0
    bOscillating := FALSE;                                            // 不判抖（规格强制）
    FC_DL_OscillationIndex := TRUE;                                   // 计算已有效执行
    RETURN;                                                           // 过零率/离散度维持 0 缺省
END_IF

(* —— 段 5：频率与离散度归一化合成（分母均已闸） —— *)
rWinTime := LREAL(nWindowSize - 1) * LREAL(fSampleDt);                // 窗时长 [s]（fSampleDt 已闸 > 0）
IF rWinTime > 0.0 THEN
    fZeroCrossRateHz := REAL(rCross / (2.0 * rWinTime));              // 每次完整摆动含 2 次过零 [Hz]
END_IF
fAmpDispersion := REAL(MIN(rAmpMean / rDispNorm, 1.0));               // 离散度归一化并钳 0..1
rRateN := MIN(fZeroCrossRateHz / fNormRateHz, 1.0);                   // 过零率归一化并钳 0..1
rIdx := SQRT(rRateN * LREAL(fAmpDispersion));                         // 几何平均合成
fOscIndex := REAL(MIN(MAX(rIdx, 0.0), 1.0));                          // 钳 0..1

(* —— 段 6：判定出口 —— *)
bOscillating := fOscIndex > fOscNormLimit;                            // 越阈值判抖（每调用重算，解除式自证）
FC_DL_OscillationIndex := TRUE;                                       // 计算有效

END_FUNCTION
