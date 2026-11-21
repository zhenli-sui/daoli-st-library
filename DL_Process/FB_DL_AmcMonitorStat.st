(*
  ==================================================================
  组件名 Component  : FB_DL_AmcMonitorStat
  分类   Category   : DL_Process
  版本   Version    : 1.0.0
  功能   Purpose    : AMC 污染在线统计分级。在周期采样窗内累计气态分子污染浓度
                      （单位 ppb）的样本数、均值、峰值与超阈比例，窗末按三级阈
                      （A / B / C）把均值定级为 A / B / C / D 四档，C 档及以下
                      置报警；同时给出本窗超阈样本比例与连续超阈窗计数。
  溯源   Origin     : AMC 分级统计为洁净室污染监控的通用口径；本件为 clean-room
                      实现，仅借鉴来源分类与参数域组织（来源标签 roadmap-p2-amc），
                      道莅原创设计，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（TON / REAL 运算，无私有库、无方言转换）
  作者   Author     : 道莅代码库 · PLC 编程专家（R55）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只做统计分级与报警，不控制新风阀、不驱动净化设备（属主边界）；
                      二 采样窗由自复位周期 TON 驱动，窗末结算并清零累加器；
                      三 非有限浓度样本不参与统计，只累加坏样本计数（信息级，不置故障）；
                      四 三级阈必须严格递增，否则判组态故障并锁存至复位沿；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约 Output contract:
                      eClass 四档互斥，仅在窗末结算拍更新（锁存至下一窗末）；
                      bAlarm 在 C 档及以下（含 D 档）为真，挂状态量不挂单拍标志；
                      fMeanPpb / fMaxPpb / fExceedPct 为上一完整窗的结算值；
                      eCause 故障级成因与 bError 配对（R45），信息级永不置 bError。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R55 首版（批 3 · 序号 13）
  ==================================================================
*)

TYPE E_DL_AmcClass :
(
    eA := 0,            // A 档：均值不高于 A 级阈 / class A, the mean stays at or below the A limit
    eB := 10,           // B 档：均值高于 A 级阈但不高于 B 级阈 / class B, above the A limit and at or below the B limit
    eC := 20,           // C 档：均值高于 B 级阈但不高于 C 级阈 / class C, above the B limit and at or below the C limit
    eD := 30            // D 档：均值高于 C 级阈 / class D, above the C limit
);
END_TYPE

TYPE E_DL_AmcCause :
(
    eNone       := 0,   // 无成因 / no cause
    eCfgIllegal := 1,   // 组态非法：三级阈非严格递增或比例阈越域（故障级，与 bError 配对）/ illegal config, limits not strictly increasing or the ratio threshold out of domain
    eBadSample  := 2,   // 存在非有限样本，未参与统计（信息级）/ non-finite samples excluded from the statistics, informational
    eNoSample   := 3    // 本窗无有效样本，等级保持上窗值（信息级）/ no valid sample in the window and the class holds, informational
);
END_TYPE

FUNCTION_BLOCK FB_DL_AmcMonitorStat
VAR_INPUT
    bEnable     : BOOL := TRUE;              // 使能，失能时冻结统计与等级 [-] / enable, the statistics and the class freeze when disabled
    bReset      : BOOL := FALSE;            // 复位上升沿清故障锁存与统计 [-] / reset rising edge clears the fault latch and the statistics
    fAmcPpb     : REAL := 0.0;               // AMC 浓度实测 [ppb] / measured AMC concentration [ppb]
    fClsALimit  : REAL := 10.0;              // A 级阈 [ppb]，域 大于零 / class A limit [ppb], domain above zero
    fClsBLimit  : REAL := 50.0;              // B 级阈 [ppb]，须大于 A 级阈 / class B limit [ppb], must exceed the class A limit
    fClsCLimit  : REAL := 100.0;             // C 级阈 [ppb]，须大于 B 级阈 / class C limit [ppb], must exceed the class B limit
    fExceedPctLimit : REAL := 20.0;          // 超阈样本比例报警阈 [百分比]，域 0..100 / exceed ratio alarm threshold [percent], domain 0 to 100
    tSampleWin  : TIME := T#60S;             // 采样窗时长 [毫秒]，域 大于零 / sampling window duration [millisecond], domain above zero
END_VAR
VAR_OUTPUT
    fMeanPpb    : REAL := 0.0;               // 上一窗均值 [ppb] / mean of the last complete window [ppb]
    fMaxPpb     : REAL := 0.0;               // 上一窗峰值 [ppb] / peak of the last complete window [ppb]
    fExceedPct  : REAL := 0.0;               // 上一窗超阈样本比例 [百分比] / exceed sample ratio of the last complete window [percent]
    nSampleCnt  : INT := 0;                  // 上一窗有效样本数 [个] / valid sample count of the last complete window
    nBadSampleCnt : INT := 0;                // 上一窗坏样本数 [个] / bad sample count of the last complete window
    nExceedWinCnt : INT := 0;                // 连续超比例窗计数（饱和到上限）[窗] / consecutive exceed windows, saturated [window]
    eClass      : E_DL_AmcClass := E_DL_AmcClass.eA; // 等级出口 [枚举] / class outlet [enum]
    bAlarm      : BOOL := FALSE;             // 报警（C 档及以下）[-] / alarm for class C and below
    bWinDone    : BOOL := FALSE;             // 窗结算单拍脉冲 [-] / window settle single-shot pulse
    eCause      : E_DL_AmcCause := E_DL_AmcCause.eNone; // 成因出口 [枚举] / cause outlet [enum]
    bError      : BOOL := FALSE;             // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtReset     : R_TRIG;                    // 复位沿检测，段 0 无条件刷新 / reset edge detector, refreshed unconditionally in segment zero
    tonWin      : TON;                       // 采样窗周期计时（自复位式）/ sampling window timer, self resetting
    _eCause     : E_DL_AmcCause := E_DL_AmcCause.eNone;  // 信息级成因，每拍重算 / informational cause, recomputed every scan
    _eFaultCause: E_DL_AmcCause := E_DL_AmcCause.eNone;  // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _eClass     : E_DL_AmcClass := E_DL_AmcClass.eA;     // 等级锁存量 / latched class
    _bFault     : BOOL := FALSE;             // 故障锁存位 [-] / fault latch bit
    _bInit      : BOOL := FALSE;             // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bSampleOk  : BOOL := FALSE;             // 本拍样本有限 [-] / this scan sample finite
    _bCfgBad    : BOOL := FALSE;             // 组态非法判定 [-] / illegal configuration verdict
    _bBadSeen   : BOOL := FALSE;             // 本窗出现过坏样本 [-] / a bad sample occurred in this window
    _bDoneInt   : BOOL := FALSE;             // 窗结算脉冲内部位，统一出口映射 / internal window done bit, mapped at the unified outlet
    _nCnt       : INT := 0;                  // 本窗有效样本计数 [个] / valid sample count of this window
    _nBad       : INT := 0;                  // 本窗坏样本计数 [个] / bad sample count of this window
    _nExceed    : INT := 0;                  // 本窗超阈样本计数 [个] / exceed sample count of this window
    _nExceedWin : INT := 0;                  // 连续超比例窗计数 [窗] / consecutive exceed window count [window]
    _nBadLast   : INT := 0;                  // 上一窗坏样本数锁存 [个] / last window bad sample count
    _nCntLast   : INT := 0;                  // 上一窗有效样本数锁存 [个] / last window valid sample count
    _fSum       : REAL := 0.0;               // 本窗浓度累加 [ppb] / concentration sum of this window [ppb]
    _fMax       : REAL := 0.0;               // 本窗浓度峰值 [ppb] / concentration peak of this window [ppb]
    _fMean      : REAL := 0.0;               // 本窗均值工作值 [ppb] / mean working value of this window [ppb]
    _fExceedPct : REAL := 0.0;               // 本窗超阈比例工作值 [百分比] / exceed ratio working value [percent]
    _fMeanLast  : REAL := 0.0;               // 上一窗均值锁存 [ppb] / last window mean
    _fMaxLast   : REAL := 0.0;               // 上一窗峰值锁存 [ppb] / last window peak
    _fExcLast   : REAL := 0.0;               // 上一窗超阈比例锁存 [百分比] / last window exceed ratio
END_VAR
VAR CONSTANT
    DL_AMC_WIN_MIN   : REAL := 0.0;          // 浓度下限（负浓度不可能）[ppb] / concentration floor, negatives are impossible [ppb]
    DL_AMC_WIN_MAX   : REAL := 1.0E6;        // 浓度量级上限，防量纲错配 [ppb] / concentration magnitude ceiling against a mismatch [ppb]
    DL_AMC_PCT_MAX   : REAL := 100.0;        // 比例上限 [百分比] / ratio ceiling [percent]
    DL_AMC_CNT_MAX   : INT := 30000;         // 单窗样本计数上限，防溢出 [个] / per window sample count ceiling against overflow [count]
    DL_AMC_WIN_CNT_MAX : INT := 10000;       // 连续超比例窗计数上限 [窗] / consecutive exceed window count ceiling [window]
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支）；采样窗用自复位式（IN 取自身 Q 的补）/ segment 0, unconditional refresh with a self resetting window timer
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge
tonWin(IN := (NOT tonWin.Q) AND bEnable AND (NOT _bFault), PT := tSampleWin); // 周期窗自复位：Q 到时下一拍 IN 变假即重启，符合周期脉冲发生器用法（不得用于闭锁窗）/ self resetting periodic window, never used as a latching window

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _eCause := E_DL_AmcCause.eNone; // 信息级成因清零 / clear the informational cause
    _eFaultCause := E_DL_AmcCause.eNone; // 故障级成因清零 / clear the fault cause
    _eClass := E_DL_AmcClass.eA; // 等级从 A 档起步 / the class starts at A
    _nCnt := 0; // 有效样本计数清零 / clear the valid sample count
    _nBad := 0; // 坏样本计数清零 / clear the bad sample count
    _nExceed := 0; // 超阈计数清零 / clear the exceed count
    _fSum := 0.0; // 浓度累加清零 / clear the concentration sum
    _fMax := 0.0; // 峰值清零 / clear the peak
END_IF

// 段 2｜复位沿作用域：清锁存 / 清统计 / 清等级（三项逐项声明）/ segment 2, reset edge scope
IF rtReset.Q THEN // 复位沿 / reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaultCause := E_DL_AmcCause.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _nCnt := 0; // 作用域二：清有效样本计数 / scope two, clear the valid count
    _nBad := 0; // 作用域二：清坏样本计数 / scope two, clear the bad count
    _nExceed := 0; // 作用域二：清超阈计数 / scope two, clear the exceed count
    _fSum := 0.0; // 作用域二：清浓度累加 / scope two, clear the sum
    _fMax := 0.0; // 作用域二：清峰值 / scope two, clear the peak
    _nExceedWin := 0; // 作用域二：清连续超比例窗计数 / scope two, clear the consecutive exceed window count
    _eClass := E_DL_AmcClass.eA; // 作用域三：等级回 A 档 / scope three, the class returns to A
    _bDoneInt := FALSE; // 作用域一：清窗结算脉冲内部位 / scope one, clear the internal done bit
END_IF

// 段 3｜组态域闸（R151 全覆盖）：三级阈严格递增、比例阈域、窗时长 / segment 3, configuration domain gate with strictly increasing limits
_bCfgBad := FALSE; // 组态非法预置假 / preset the illegal configuration verdict to false
IF (fClsALimit <= DL_AMC_WIN_MIN) OR (fClsALimit <> fClsALimit) OR (fClsALimit > DL_AMC_WIN_MAX) THEN // A 级阈越域 / the A limit is out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (fClsBLimit <= fClsALimit) OR (fClsBLimit <> fClsBLimit) OR (fClsBLimit > DL_AMC_WIN_MAX) THEN // B 级阈非大于 A 级阈 / the B limit is not above the A limit
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (fClsCLimit <= fClsBLimit) OR (fClsCLimit <> fClsCLimit) OR (fClsCLimit > DL_AMC_WIN_MAX) THEN // C 级阈非大于 B 级阈 / the C limit is not above the B limit
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (fExceedPctLimit < 0.0) OR (fExceedPctLimit > DL_AMC_PCT_MAX) OR (fExceedPctLimit <> fExceedPctLimit) THEN // 比例阈越域 / the ratio threshold is out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF tSampleWin <= T#0S THEN // 窗时长非正 / the window duration is not positive
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF _bCfgBad AND (NOT _bFault) THEN // 组态非法且未锁存 / illegal configuration and not yet latched
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaultCause := E_DL_AmcCause.eCfgIllegal; // 故障级成因 (R45 配对 bError) / fault grade cause paired with bError
END_IF

// 段 4｜样本接收：有限性与量级闸，坏样本不入统计 / segment 4, sample acceptance with finiteness and magnitude gates
_eCause := E_DL_AmcCause.eNone; // 信息级成因每拍重算 / the informational cause is recomputed every scan
_bSampleOk := (fAmcPpb = fAmcPpb) AND ((fAmcPpb - fAmcPpb) = (fAmcPpb - fAmcPpb)) AND (fAmcPpb >= DL_AMC_WIN_MIN) AND (fAmcPpb <= DL_AMC_WIN_MAX); // 样本有限性闸（NaN 自反、无穷差值自减）/ sample finiteness gate
IF bEnable AND (NOT _bFault) THEN // 使能且无故障才收样本 / samples are accepted only while enabled and unfaulted
    IF _bSampleOk THEN // 样本可用 / the sample is usable
        IF _nCnt < DL_AMC_CNT_MAX THEN // 未达计数上限 / below the count ceiling
            _nCnt := _nCnt + 1; // 有效样本计数递增 / increment the valid count
        END_IF
        _fSum := _fSum + fAmcPpb; // 浓度累加 / accumulate the concentration
        IF fAmcPpb > _fMax THEN // 峰值刷新 / refresh the peak
            _fMax := fAmcPpb; // 更新峰值 / update the peak
        END_IF
        IF fAmcPpb > fClsCLimit THEN // 超 C 级阈 / above the C limit
            IF _nExceed < DL_AMC_CNT_MAX THEN // 未达计数上限 / below the count ceiling
                _nExceed := _nExceed + 1; // 超阈计数递增 / increment the exceed count
            END_IF
        END_IF
    ELSE // 样本不可用 / the sample is unusable
        _bBadSeen := TRUE; // 记坏样本出现 / record the bad sample
        IF _nBad < DL_AMC_CNT_MAX THEN // 未达计数上限 / below the count ceiling
            _nBad := _nBad + 1; // 坏样本计数递增 / increment the bad count
        END_IF
    END_IF
END_IF

// 段 5｜窗末结算：算均值与超阈比例，定级并累加连续超比例窗 / segment 5, window settle with grading
IF tonWin.Q THEN // 窗末（自复位计时到时）/ window end
    _fMean := 0.0; // 均值预置零 / preset the mean to zero
    _fExceedPct := 0.0; // 超阈比例预置零 / preset the exceed ratio to zero
    IF _nCnt > 0 THEN // 有有效样本 / at least one valid sample
        _fMean := _fSum / INT_TO_REAL(_nCnt); // 均值，除子已证大于零 / mean, divisor proven positive
        _fExceedPct := INT_TO_REAL(_nExceed) / INT_TO_REAL(_nCnt) * 100.0; // 超阈比例，除子已证大于零 / exceed ratio, divisor proven positive
    END_IF
    _fMeanLast := _fMean; // 上一窗均值锁存 / latch the last window mean
    _fMaxLast := _fMax; // 上一窗峰值锁存 / latch the last window peak
    _fExcLast := _fExceedPct; // 上一窗比例锁存 / latch the last window ratio
    _nCntLast := _nCnt; // 上一窗样本数锁存 / latch the last window sample count
    _nBadLast := _nBad; // 上一窗坏样本数锁存 / latch the last window bad count
    IF _nCnt > 0 THEN // 有样本才定级 / grading needs samples
        IF _fMean <= fClsALimit THEN // 均值不高于 A 级阈 / the mean stays at or below the A limit
            _eClass := E_DL_AmcClass.eA; // A 档 / class A
        ELSIF _fMean <= fClsBLimit THEN // 高于 A 级阈且不高于 B 级阈 / above A and at or below B
            _eClass := E_DL_AmcClass.eB; // B 档 / class B
        ELSIF _fMean <= fClsCLimit THEN // 高于 B 级阈且不高于 C 级阈 / above B and at or below C
            _eClass := E_DL_AmcClass.eC; // C 档 / class C
        ELSE // 高于 C 级阈 / above the C limit
            _eClass := E_DL_AmcClass.eD; // D 档 / class D
        END_IF
        IF _fExceedPct > fExceedPctLimit THEN // 超阈比例超报警阈 / the exceed ratio passes the alarm threshold
            IF _nExceedWin < DL_AMC_WIN_CNT_MAX THEN // 未达计数上限 / below the ceiling
                _nExceedWin := _nExceedWin + 1; // 连续超比例窗计数递增 / increment the consecutive exceed window count
            END_IF
        ELSE
            _nExceedWin := 0; // 未超则清零 / cleared when the ratio is acceptable
        END_IF
    ELSE // 本窗无有效样本 / no valid sample this window
        _eCause := E_DL_AmcCause.eNoSample; // 信息级成因：等级保持上窗值 / informational cause, the class holds
    END_IF
    _bDoneInt := TRUE; // 窗结算脉冲内部位置位（统一出口映射，R187）/ raise the internal done bit, mapped at the unified outlet
    IF _bBadSeen THEN // 本窗出现过坏样本 / a bad sample occurred in this window
        _eCause := E_DL_AmcCause.eBadSample; // 信息级成因（坏样本比无样本更具体，后者不覆盖）/ informational cause, the bad sample is more specific than the empty window
    END_IF
    _bBadSeen := FALSE; // 坏样本标志按窗清零 / the bad sample flag is cleared per window
    // 累加器清零，进入下一窗 / clear the accumulators for the next window
    _nCnt := 0; // 有效样本计数清零 / clear the valid count
    _nBad := 0; // 坏样本计数清零 / clear the bad count
    _nExceed := 0; // 超阈计数清零 / clear the exceed count
    _fSum := 0.0; // 浓度累加清零 / clear the sum
    _fMax := 0.0; // 峰值清零 / clear the peak
END_IF
// 段 6｜统一出口 / segment 6, unified outlet
fMeanPpb := _fMeanLast; // 上一窗均值出口 / last window mean outlet
fMaxPpb := _fMaxLast; // 上一窗峰值出口 / last window peak outlet
fExceedPct := _fExcLast; // 上一窗比例出口 / last window ratio outlet
nSampleCnt := _nCntLast; // 上一窗样本数出口 / last window sample count outlet
nBadSampleCnt := _nBadLast; // 上一窗坏样本数出口 / last window bad count outlet
nExceedWinCnt := _nExceedWin; // 连续超比例窗计数出口 / consecutive exceed window count outlet
eClass := _eClass; // 等级出口（锁存量）/ class outlet from the latch
bAlarm := (_eClass = E_DL_AmcClass.eC) OR (_eClass = E_DL_AmcClass.eD); // 报警挂等级状态量（R99）/ the alarm follows the class state quantity
bWinDone := _bDoneInt; // 窗结算脉冲映射本拍值 / map the window done pulse for this scan
_bDoneInt := FALSE; // 映射后立即撤销，保证单拍宽度（R187 两段式）/ revoke right after mapping to keep a single-scan width
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eCause := _eFaultCause; // 故障级成因锁存回放 / the fault cause is replayed from the latch
ELSE
    eCause := _eCause; // 信息级成因直映 / the informational cause is mapped directly
END_IF
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
