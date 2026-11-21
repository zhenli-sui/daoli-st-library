(*
  FB_DL_CrossCorrelationDelay  —  互相关时延估计（滑动窗 + 抛物线插值）/ Cross-correlation delay estimator
  分类 Category : DL_Algo
  码位 Code     : 16#02_3_85
  版本 Version  : 1.0.0
  来源 Source   : t2-4-s7-motion — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : clean-room 实现，滑动互相关与三点抛物线亚采样插值公开语义，未复制任何源码行
                  （依赖语义对齐 FB_DL_MedianFilter / FB_DL_LowPassFilter：前端滤波由调用方承载，本件不做滤波）
  功能 Function : 1) 输入缓冲以 [0] 为最新采样点，FB 内部维护 nWindowSize 深双路滑动窗（去均值后互相关）；
                  2) 在 |lag| <= nMaxLagSamples 内取互相关峰值，三点抛物线插值得亚采样滞后 fDelayS（s，负 = 超前）；
                  3) fPeakCorr < fConfidenceMin 判不可信不出时延结论；eState: Fill/Search/Locked/Fault。
  边界 Boundary : ① fSampleDt <= 0 / nWindowSize < 16 / 2·nMaxLagSamples >= nWindowSize / 窗超数组上界 判组态错进 Fault；
                  ② 缓冲未填满时 bWindowFull := FALSE 且不出时延结论（fDelayS 维持 0）；
                  ③ 参考信号方差 < 1E-12 判「激励不足」置码且 bValid := FALSE（不输出随机滞后）；
                  ④ 峰值落窗边界（|lag| = nMaxLagSamples）判「滞后超窗」置码而非当有效值；
                  ⑤ 解除式自证：Fault 退出 = bReset 上升沿 AND 组态三参数合法（引脚均可满足，R28-1）；
                  ⑥ 未知状态由 CASE ELSE 拦截进 Fault（兜底置码）。
  依赖 Depends  : 仅 Standard.library（ABS）；前端滤波语义对齐 FB_DL_MedianFilter / FB_DL_LowPassFilter（已注册，不实例化）
  码表 Error codes（本件格 02_3_85，子码步进 +0x100）:
    16#0002_0185 信息级：参考激励不足（方差 < 1E-12），不出时延结论
    16#0002_0285 故障级：组态非法（dt <= 0 / 窗 < 16 / 2·maxLag >= 窗 / 窗超数组上界），锁存至复位
    16#0002_0385 信息级：峰值落窗边界（|lag| = maxLag），判滞后超窗
    16#0002_0485 信息级：置信度不足（fPeakCorr < fConfidenceMin），bValid = FALSE
    16#0002_0585 故障级：状态机落 ELSE 兜底（非法相位 ID）

  修订历史 Revision :
    2026-11-18  v1.0.0  R38 首版
*)

TYPE E_DL_XCorrState :
(
    eFill   := 0,   // 填窗：滑动窗未满，不出结论 / Filling, window not yet full
    eSearch := 10,  // 搜索：逐拍互相关寻峰 / Searching, per-scan peak search
    eLocked := 20,  // 锁定：峰值过置信门限，时延有效 / Locked, peak above confidence
    eFault  := 90   // 故障：组态错锁存，等复位 / Fault, latched until reset
);
END_TYPE

FUNCTION_BLOCK FB_DL_CrossCorrelationDelay
VAR_INPUT
    afSignalRef    : ARRAY[0..127] OF REAL;   // 参考信号缓冲，[0] = 本拍最新采样 / Reference buffer, index 0 is newest
    afSignalFb     : ARRAY[0..127] OF REAL;   // 反馈信号缓冲，[0] = 本拍最新采样 / Feedback buffer, index 0 is newest
    nWindowSize    : INT;                     // 相关窗长 [点]，域 16..128 / Correlation window length
    fSampleDt      : REAL;                    // 采样间隔 [s]，域 > 0 / Sample interval
    nMaxLagSamples : INT;                     // 最大滞后 [点]，域 0..63 且 2 倍 < 窗长 / Maximum lag in samples
    fConfidenceMin : REAL;                    // 置信度门限 [无量纲 0..1] / Minimum peak correlation
    bReset         : BOOL := FALSE;           // 复位（Fault 退出唯一路径）/ Reset, sole fault exit
END_VAR
VAR_OUTPUT
    fDelayS        : REAL;                    // 时延 [s]，负 = 超前 / Estimated delay, negative means lead
    fPeakCorr      : REAL;                    // 归一化峰值相关 [-1..1] / Normalized peak correlation
    bValid         : BOOL;                    // 时延结论有效 / Delay verdict valid
    bWindowFull    : BOOL;                    // 滑动窗已填满 / Window full flag
    nErrId         : UDINT;                   // 事件码，0 = 无事件 / Event code, 0 = none
    eState         : E_DL_XCorrState;         // 状态出口，段尾单点映射 / State outlet, mapped at the tail
END_VAR
VAR
    tonFaultWatch : TON;                       // 故障态驻留观察窗，自复位（段 0 无条件刷新）/ Fault dwell observer, self-resetting
    rtReset       : R_TRIG;                    // 复位上升沿 / Reset rising edge
    _eState       : E_DL_XCorrState := E_DL_XCorrState.eFill;   // 内部相位（CASE 唯一写入目标）/ Internal phase
    _arRefWin     : ARRAY[0..127] OF REAL;     // 参考滑动窗 / Reference sliding window
    _arFbWin      : ARRAY[0..127] OF REAL;     // 反馈滑动窗 / Feedback sliding window
    _arCorr       : ARRAY[0..127] OF REAL;     // 各 lag 相关系数（下标 = lag + 64）/ Correlation per lag, index = lag + 64
    _nFill        : INT;                       // 已填点数 [点] / Filled sample count
    _nPeakLag     : INT;                       // 峰值 lag [点] / Peak lag
    _nLag         : INT;                       // lag 循环计数 / Lag loop counter
    _nK           : INT;                       // 窗内循环计数 / Window loop counter
    _uFault       : UDINT;                     // 故障码锁存 / Latched fault code
    _uInfo        : UDINT;                     // 信息码，每拍重算 / Info code, recomputed per scan
    _bFault       : BOOL;                      // 故障锁存位 / Latched fault bit
    _bCfgBad      : BOOL;                      // 组态非法聚合 / Configuration invalid aggregate
    _rRefMean     : LREAL;                     // 参考窗均值 / Reference window mean
    _rFbMean      : LREAL;                     // 反馈窗均值 / Feedback window mean
    _rRefVar      : LREAL;                     // 参考窗方差 / Reference window variance
    _rFbVar       : LREAL;                     // 反馈窗方差 / Feedback window variance
    _rCross       : LREAL;                     // 交叉累加暂存 / Cross accumulation scratch
    _rPeak        : LREAL;                     // 峰值相关 / Peak correlation
    _rCm1, _rC0, _rCp1 : LREAL;                // 抛物线三点 / Parabola three points
    _rShift       : LREAL;                     // 亚采样偏移 [点] / Sub-sample shift
END_VAR
VAR CONSTANT
    nWinMin  : INT   := 16;       // 最小窗长 [点] / Minimum window length
    nWinMax  : INT   := 128;      // 数组上界 [点] / Array upper bound
    nLagBase : INT   := 64;       // lag 下标基准（数组下标 = lag + 64）/ Lag index base
    rVarFloor: LREAL := 1.0E-12;  // 激励方差下限 / Excitation variance floor
    rWatchPt : TIME  := T#2S;     // 故障观察窗 [ms]，自复位节拍 / Fault watch window, self-resetting
END_VAR

(* —— 段 0：定时器与边沿无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
rtReset(CLK := bReset);                                     // 复位上升沿，每拍必调
tonFaultWatch(IN := (NOT tonFaultWatch.Q), PT := rWatchPt); // 观察窗自复位节拍（表达式入参，非 IF 内）

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault/_nFill/_arWin 不入清单，R187①） —— *)
_uInfo    := 16#0000_0000;     // 信息码每拍重算
bValid    := FALSE;            // 结论缺省无效
nErrId    := 16#0000_0000;     // 事件码缺省无事件

(* —— 段 2：组态域闸（覆盖全部参与判据换算的引脚，R151） —— *)
_bCfgBad := FALSE;             // 组态非法预清零（每拍重算，Fault 锁存不受影响）
IF LREAL(fSampleDt) <= 0.0 THEN
    _bCfgBad := TRUE;          // 采样间隔非法
END_IF
IF (nWindowSize < nWinMin) OR (nWindowSize > nWinMax) THEN
    _bCfgBad := TRUE;          // 窗长越域
END_IF
IF (nMaxLagSamples < 0) OR ((2 * nMaxLagSamples) >= nWindowSize) THEN
    _bCfgBad := TRUE;          // 滞后窗不得吃掉相关样本（规格强制）
END_IF
IF _bCfgBad THEN
    _uFault  := 16#0002_0285;  // 故障级：组态非法
    _bFault  := TRUE;          // 锁存（解除式自证：bReset AND 组态合法）
    _eState  := E_DL_XCorrState.eFault;
END_IF

(* —— 段 3：复位沿（Fault 解除唯一路径：bReset AND 组态合法） —— *)
IF rtReset.Q THEN
    IF (NOT _bCfgBad) THEN
        _bFault  := FALSE;                 // 清故障锁存位
        _uFault  := 16#0000_0000;          // 清锁存码
        _eState  := E_DL_XCorrState.eFill; // 回填窗相重新开始
        _nFill   := 0;                     // 填充计数清零
        fDelayS  := 0.0;                   // 时延结论清零
        fPeakCorr := 0.0;                  // 峰值清零
    END_IF
END_IF

(* —— 段 4：滑动窗移位入队（每拍执行，Fault 相冻结不采集） —— *)
IF _eState <> E_DL_XCorrState.eFault THEN
    FOR _nK := (nWinMax - 1) TO 1 BY -1 DO
        _arRefWin[_nK] := _arRefWin[_nK - 1];   // 参考窗右移
        _arFbWin[_nK]  := _arFbWin[_nK - 1];    // 反馈窗右移
    END_FOR
    _arRefWin[0] := afSignalRef[0];             // 最新采样入队（[0] = 本拍最新）
    _arFbWin[0]  := afSignalFb[0];
    IF _nFill < nWinMax THEN
        _nFill := _nFill + 1;                   // 填充计数（上限守卫，不回绕）
    END_IF
END_IF
bWindowFull := _nFill >= nWindowSize;           // 窗满标志（窗长已闸 <= 128）

(* —— 段 5：相位机（只做迁移与计算；出口在段 8） —— *)
CASE _eState OF

E_DL_XCorrState.eFill:
    IF bWindowFull THEN
        _eState := E_DL_XCorrState.eSearch;     // 窗满：进搜索相
    END_IF

E_DL_XCorrState.eSearch:
    IF NOT bWindowFull THEN
        _eState := E_DL_XCorrState.eFill;       // 组态变更窗长变大：回填窗相
    ELSE
        (* —— 去均值与方差（分母 nWindowSize 已闸 >= 16） —— *)
        _rRefMean := 0.0;  _rFbMean := 0.0;
        FOR _nK := 0 TO (nWindowSize - 1) DO
            _rRefMean := _rRefMean + LREAL(_arRefWin[_nK]);
            _rFbMean  := _rFbMean  + LREAL(_arFbWin[_nK]);
        END_FOR
        _rRefMean := _rRefMean / LREAL(nWindowSize);
        _rFbMean  := _rFbMean  / LREAL(nWindowSize);
        _rRefVar  := 0.0;  _rFbVar := 0.0;
        FOR _nK := 0 TO (nWindowSize - 1) DO
            _rRefVar := _rRefVar + (LREAL(_arRefWin[_nK]) - _rRefMean) * (LREAL(_arRefWin[_nK]) - _rRefMean);
            _rFbVar  := _rFbVar  + (LREAL(_arFbWin[_nK])  - _rFbMean)  * (LREAL(_arFbWin[_nK])  - _rFbMean);
        END_FOR
        _rRefVar := _rRefVar / LREAL(nWindowSize);
        _rFbVar  := _rFbVar  / LREAL(nWindowSize);
        IF _rRefVar < rVarFloor THEN
            _uInfo := 16#0002_0185;             // 信息级：参考激励不足
            fPeakCorr := 0.0;                   // 不输出随机滞后
        ELSE
            (* —— 滑动互相关（lag ∈ [−maxLag, +maxLag]，重叠区去均值归一化） —— *)
            _rPeak := -2.0;                     // 峰值暂存（相关系数域 [-1,1]，取超域初值）
            _nPeakLag := 0;
            FOR _nLag := -nMaxLagSamples TO nMaxLagSamples DO
                _rCross := 0.0;
                FOR _nK := 0 TO (nWindowSize - 1 - ABS(_nLag)) DO
                    _rCross := _rCross
                        + (LREAL(_arRefWin[_nK]) - _rRefMean)
                        * (LREAL(_arFbWin[_nK + _nLag]) - _rFbMean);   // 参考滞后 _nLag 拍的交叉积
                END_FOR
                _arCorr[_nLag + nLagBase] := REAL(_rCross
                    / MAX(SQRT(_rRefVar * _rFbVar) * LREAL(nWindowSize - ABS(_nLag)), rVarFloor));  // 归一化（分母已闸）
                IF LREAL(_arCorr[_nLag + nLagBase]) > _rPeak THEN
                    _rPeak := LREAL(_arCorr[_nLag + nLagBase]);        // 峰值刷新
                    _nPeakLag := _nLag;                                 // 峰值 lag 记录
                END_IF
            END_FOR
            fPeakCorr := REAL(_rPeak);
            (* —— 边界峰值 = 滞后超窗：判码不出有效值（规格强制） —— *)
            IF ABS(_nPeakLag) >= nMaxLagSamples THEN
                _uInfo := 16#0002_0385;         // 信息级：峰值落窗边界
            ELSIF _rPeak < LREAL(fConfidenceMin) THEN
                _uInfo := 16#0002_0485;         // 信息级：置信度不足
            ELSE
                (* —— 三点抛物线亚采样插值（峰值在开区间内，三点必在 lag 表内） —— *)
                _rCm1 := LREAL(_arCorr[_nPeakLag - 1 + nLagBase]);   // lag−1 相关系数
                _rC0  := LREAL(_arCorr[_nPeakLag     + nLagBase]);   // lag   相关系数
                _rCp1 := LREAL(_arCorr[_nPeakLag + 1 + nLagBase]);   // lag+1 相关系数
                IF ABS(_rCm1 - 2.0 * _rC0 + _rCp1) > rVarFloor THEN
                    _rShift := 0.5 * (_rCm1 - _rCp1) / (_rCm1 - 2.0 * _rC0 + _rCp1);   // 抛物线顶点偏移（分母已闸）
                ELSE
                    _rShift := 0.0;             // 三点共线：退化为整数 lag
                END_IF
                fDelayS := REAL((LREAL(_nPeakLag) + _rShift) * LREAL(fSampleDt));   // 亚采样时延 [s]
                bValid  := TRUE;                // 结论有效
                _eState := E_DL_XCorrState.eLocked;   // 过门限：进锁定相
            END_IF
        END_IF
    END_IF

E_DL_XCorrState.eLocked:
    IF NOT bWindowFull THEN
        _eState := E_DL_XCorrState.eFill;       // 组态变更：回填窗相
        bValid  := FALSE;                       // 锁定值作废
    ELSE
        (* —— 锁定相维持结论并继续逐拍复算（复算逻辑与搜索相同，保持时延新鲜度） —— *)
        _rRefMean := 0.0;  _rFbMean := 0.0;
        FOR _nK := 0 TO (nWindowSize - 1) DO
            _rRefMean := _rRefMean + LREAL(_arRefWin[_nK]);
            _rFbMean  := _rFbMean  + LREAL(_arFbWin[_nK]);
        END_FOR
        _rRefMean := _rRefMean / LREAL(nWindowSize);
        _rFbMean  := _rFbMean  / LREAL(nWindowSize);
        _rRefVar  := 0.0;  _rFbVar := 0.0;
        FOR _nK := 0 TO (nWindowSize - 1) DO
            _rRefVar := _rRefVar + (LREAL(_arRefWin[_nK]) - _rRefMean) * (LREAL(_arRefWin[_nK]) - _rRefMean);
            _rFbVar  := _rFbVar  + (LREAL(_arFbWin[_nK])  - _rFbMean)  * (LREAL(_arFbWin[_nK])  - _rFbMean);
        END_FOR
        _rRefVar := _rRefVar / LREAL(nWindowSize);
        _rFbVar  := _rFbVar  / LREAL(nWindowSize);
        IF _rRefVar < rVarFloor THEN
            _uInfo := 16#0002_0185;             // 信息级：激励不足（锁定值维持，bValid 置 FALSE）
            bValid := FALSE;
        ELSE
            _rPeak := -2.0;
            _nPeakLag := 0;
            FOR _nLag := -nMaxLagSamples TO nMaxLagSamples DO
                _rCross := 0.0;
                FOR _nK := 0 TO (nWindowSize - 1 - ABS(_nLag)) DO
                    _rCross := _rCross
                        + (LREAL(_arRefWin[_nK]) - _rRefMean)
                        * (LREAL(_arFbWin[_nK + _nLag]) - _rFbMean);
                END_FOR
                _arCorr[_nLag + nLagBase] := REAL(_rCross
                    / MAX(SQRT(_rRefVar * _rFbVar) * LREAL(nWindowSize - ABS(_nLag)), rVarFloor));
                IF LREAL(_arCorr[_nLag + nLagBase]) > _rPeak THEN
                    _rPeak := LREAL(_arCorr[_nLag + nLagBase]);
                    _nPeakLag := _nLag;
                END_IF
            END_FOR
            fPeakCorr := REAL(_rPeak);
            IF ABS(_nPeakLag) >= nMaxLagSamples THEN
                _uInfo := 16#0002_0385;         // 信息级：滞后超窗（锁定值维持，bValid 置 FALSE）
                bValid := FALSE;
            ELSIF _rPeak < LREAL(fConfidenceMin) THEN
                _uInfo := 16#0002_0485;         // 信息级：置信度不足
                bValid := FALSE;
            ELSE
                _rCm1 := LREAL(_arCorr[_nPeakLag - 1 + nLagBase]);
                _rC0  := LREAL(_arCorr[_nPeakLag     + nLagBase]);
                _rCp1 := LREAL(_arCorr[_nPeakLag + 1 + nLagBase]);
                IF ABS(_rCm1 - 2.0 * _rC0 + _rCp1) > rVarFloor THEN
                    _rShift := 0.5 * (_rCm1 - _rCp1) / (_rCm1 - 2.0 * _rC0 + _rCp1);
                ELSE
                    _rShift := 0.0;
                END_IF
                fDelayS := REAL((LREAL(_nPeakLag) + _rShift) * LREAL(fSampleDt));   // 时延逐拍刷新
                bValid  := TRUE;                // 结论维持有效
            END_IF
        END_IF
    END_IF

E_DL_XCorrState.eFault:
    ;                                           // 故障相：等复位沿（段 3 承载解除，无动作）

ELSE
    _uFault := 16#0002_0585;                    // 故障级：非法相位 ID 兜底
    _bFault := TRUE;                            // 锁存
    _eState := E_DL_XCorrState.eFault;          // 强制回故障相

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
eState := _eState;                              // 状态出口单点映射
IF _bFault THEN
    nErrId := _uFault;                          // 故障锁存码回放（不在故障相按当下输入重推）
    bValid := FALSE;                            // 故障相结论无效（安全侧）
ELSE
    nErrId := _uInfo;                           // 信息码
END_IF

END_FUNCTION_BLOCK
