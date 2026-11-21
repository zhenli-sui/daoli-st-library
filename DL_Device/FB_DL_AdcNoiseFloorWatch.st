(*
  ==================================================================
  组件名 Component  : FB_DL_AdcNoiseFloorWatch
  分类   Category   : DL_Device
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0003_071D / 071E（故障级）｜ 16#0003_071F / 0720（信息级）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 中
  功能   Purpose    : ADC 测点底噪监视：静态期窗内标准差与上限比较（接地 / 屏蔽
                      劣化、前端供电噪声的早期征兆）。
  开源溯源 Origin    : 公开公式 clean-room，参考公开测量工程口径的底噪标准差判据
                      （分类与公式借鉴，零代码复制），本件实现、闸门与码位 100% 自有。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6 算术运算符；样本标准差（n−1 分母）
                      公开统计定义
  平台   Platform   : 纯 IEC 61131-3（FOR / 四则 / SQRT / TON 无），三平台通用
  依赖   Depends    : 仅 Standard.library（SQRT 属标准内建）
  分工声明 Split     : FB_DL_SignalFrozenDetect / FB_DL_SignalStuckWatch 监视
                      不变性；FB_DL_SignalStatistics 为通用统计出口；本件为静态期
                      噪声幅度监视（动静时序由 bStatic 外部给定），四件互引（R216）。
                      SQRT 原语经派单规格授权（窗内标准差属主口径）；统计内核委托
                      不适用（流式窗口件非整段数组口径，环窗驻留数据自算）。
  归属 Ownership     : 本件无 TYPE 声明；全部引脚为 IEC 标准原生类型。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 环形窗固定容量 256（禁动态分配）；活样本恒为下标
                         0.._nFill−1（写头仅在达 _nUse 时回卷，序不变量证明同族件）；
                         标准差与均值均为序不变量，回卷不影响结果；
                      二 bStatic 变更沿全窗清零（防静 / 动混合窗污染标准差口径）；
                         nWinLen 变更沿同样清窗；
                      三 标准差两遍法（均值先行、离差平方累加在后），禁「平方和减
                         均值平方」单遍式（灾难性抵消会产生负方差或 0，SPC 经典
                         事故，写死）；除子 DINT_TO_LREAL(_nFill − 1)：_nFill < 2 →
                         不计算（判据挂起，bValid = FALSE，除零防护，R61-D4 固化）；
                      四 fNoiseLim ≤ 0 或非有限 → 组态码 071D + 三件套 + RETURN
                         结构早退（族② 判据固化，R1 教训出厂即正确）；
                      五 fMeas 非有限 → 丢弃不入窗，nNonFinite 局部计数（不外显，
                         R62-D7 口径）超窗长一半 → 故障 071E + bValid = FALSE；
                      六 判据迟滞：fNoiseStd > fNoiseLim 触发，回落
                         < fNoiseLim×(1−fHystPct/100) 复原（两方向分别定义，R146）；
                      七 bEnable = FALSE 的语义写死（FB33-4 声明行）：判据复位 +
                         fNoiseStd 冻结（纯监视件，保留读数供 HMI）；
                      八 首拍 _bInit 全量初始化；无状态机（CASE N/A，R6 标注）；
                         无定时器 / 无边沿实例（段 0 无刷新对象）；无全局、无外部
                         变量、无物理地址。
  错误码 Codes      :
    16#0003_071D【故障级】组态非法（fNoiseLim ≤ 0 / 非有限；fHystPct < 0 / 非有限）
    16#0003_071E【故障级】测量失效（非有限样本累计超过窗长一半）
    16#0003_071F【信息级】底噪超上限（bNoiseHigh = TRUE）
    16#0003_0720【信息级】窗长越域已钳位（合法 16..256）
  码位反证 Note     :
    071D 与 071E 不可合并：071D 组态即刻判（与窗内容无关），071E 需窗已建立且坏点
    累计超半窗，处置人不同（组态工程师 / 仪表工），可由 nFill 与窗状态还原（R90）；
    071F / 0720 信息级与故障级分属不同子带（R75 子带纪律），不可跨用。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 恒定值 → std = 0、bNoiseHigh = FALSE
    V2 注入 ±0.5 方波抖动 → std ≈ 0.5，超限触发
    V3 限值上下 5% 波动（迟滞 10%）→ 不反复跳
    V4 fNoiseLim = 0 → 组态早退；V5 _nFill = 1 → 判据挂起 bValid = FALSE
    V6 bStatic 翻转 → 清窗 nFill = 0；V7 全 NaN → 故障 071E
  修订记录 Revision  :
    2026-11-21  v1.0.0  R63 首版（批 3 · 序号 9）
  ==================================================================
*)
FUNCTION_BLOCK FB_DL_AdcNoiseFloorWatch
VAR_INPUT
    bEnable   : BOOL := TRUE;  // 使能，FALSE 时判据复位 + 标准差冻结（边界七）/ the enable, false resets the criterion and freezes the std
    fMeas     : LREAL := 0.0;  // 测点实测值 [工程单位]，必须有限 / the measured value, must be finite
    bStatic   : BOOL := FALSE; // 静态期标志（过程稳态且无操作，由调用方给）[-] / the static period flag given by the caller
    nWinLen   : DINT := 64;    // 窗长 [个]，合法域 16..256，变更沿清窗 / the window length, legal sixteen to two hundred fifty six
    fNoiseLim : LREAL := 1.0;  // 底噪上限 [工程单位]，须 > 0 / the noise ceiling, must be positive
    fHystPct  : LREAL := 10.0; // 判据迟滞 [%]，须 ≥ 0 / the criterion hysteresis in percent, non negative
END_VAR
VAR_OUTPUT
    fNoiseStd  : LREAL := 0.0;           // 窗内标准差 [工程单位] / the window standard deviation
    bNoiseHigh : BOOL := FALSE;          // 底噪超限判据（带迟滞）[-] / the noise high criterion with hysteresis
    nFill      : DINT := 0;              // 窗填充数 [个] / the filled count
    bValid     : BOOL := FALSE;          // 判据可用 [-] / the criterion is usable
    eErr       : UDINT := 16#0000_0000;  // 错误码，0 = 正常 / the error code, zero is ok
    bError     : BOOL := FALSE;          // 故障标志（故障级码同拍置位，R45 配对）/ the fault flag raised with a fault level code
END_VAR
VAR
    _bInit     : BOOL := FALSE;              // 首拍初始化标志（R310 / FB50-2）/ the first scan flag
    _afWin     : ARRAY[0..255] OF LREAL;     // 采样环形窗 [工程单位]，固定容量 256 / the fixed capacity ring of samples
    _nHead     : DINT := 0;                  // 环形窗写头 [下标] / the ring write head
    _nFill     : DINT := 0;                  // 环形窗填充计数 [个] / the ring filled count
    _nUse      : DINT := 64;                 // 钳位后的窗长 [个] / the clamped window length
    _nUsePrev  : DINT := 0;                  // 上拍窗长快照 [个]，置 0 使首拍必触发清窗 / the previous length
    _bStaticPrev : BOOL := FALSE;            // 上拍静态期快照 [-] / the previous static flag
    _nClrIdx   : DINT := 0;                  // 清窗遍历索引 [下标] / the clearing traversal index
    _nSumIdx   : DINT := 0;                  // 统计遍历索引 [下标] / the statistics traversal index
    _nNonFinite: DINT := 0;                  // 非有限丢弃计数 [个]（仅局部留档，不外显，R62-D7 口径）/ the dropped non finite count, local only and never exposed
    _fSum      : LREAL := 0.0;               // 窗内样本和 [工程单位] / the window sample sum
    _fMean     : LREAL := 0.0;               // 窗内均值（两遍法第一遍）[工程单位] / the window mean of the first pass
    _fSqSum    : LREAL := 0.0;               // 离差平方和（两遍法第二遍）[工程单位²] / the squared deviation sum of the second pass
    _fStdUse   : LREAL := 0.0;               // 标准差工作副本 [工程单位] / the working standard deviation
    _fVar      : LREAL := 0.0;               // 样本方差（n−1 分母）[工程单位²] / the sample variance
    _bNoiseL   : BOOL := FALSE;              // 底噪超限迟滞状态（跨拍保持）/ the noise high hysteresis state
    _bCfgBad   : BOOL := FALSE;              // 组态非法标记（逐拍重算）/ the configuration fault flag
    _bWinClamp : BOOL := FALSE;              // 窗长钳位标记（逐拍重算，信息级 0720）/ the window clamp flag
    _bMeasBad  : BOOL := FALSE;              // 测量失效标记（逐拍重算）/ the measurement failure flag
    _bFinLim   : BOOL := FALSE;              // 上限有限闸结果（逐拍重算）/ the limit finiteness gate result
    _bFinHyst  : BOOL := FALSE;              // 迟滞有限闸结果（逐拍重算）/ the hysteresis finiteness gate result
    _bFinMeas  : BOOL := FALSE;              // 样本有限闸结果（逐拍重算）/ the sample finiteness gate result
VAR CONSTANT
    DL_ANF_WMAX  : DINT := 256;      // 窗容量上界 [个]，与数组容量一致 / the capacity aligned with the array
    DL_ANF_WMIN  : DINT := 16;       // 窗长下界 [个] / the window floor
    DL_ANF_ZERO  : LREAL := 0.0;     // 实数零常量 [工程单位] / the real zero constant
    DL_ANF_PCT   : LREAL := 100.0;  // 百分比换算系数 [%] / the percentage scaling factor
    DL_ANF_ONE   : DINT := 1;        // 整型一常量 [个] / the integer one constant
    DL_ANF_TWO   : DINT := 2;        // 整型二常量 [个]（方差最少样本）/ the integer two constant, the minimum for a variance
    DL_ANF_ZEROI : DINT := 0;        // 整型零常量 [个] / the integer zero constant
    DL_ANF_HALF  : LREAL := 2.0;     // 半窗判据除子 [−] / the half window criterion divisor
END_VAR

// 段 0｜本件无定时器与边沿实例（纯统计监视器，R6 标注 N/A），无刷新对象 / segment 0, no timers and no edge instances exist here

// 段 1｜首拍初始化（FB50-2）/ segment 1, the first scan init
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _nFill := DL_ANF_ZEROI; // 填充计数显式清零 / clear the filled count explicitly
    _nHead := DL_ANF_ZEROI; // 写头显式清零 / clear the write head explicitly
    _fSum := DL_ANF_ZERO; // 窗和显式清零 / clear the sum explicitly
    _nUsePrev := DL_ANF_ZEROI; // 窗长快照置 0，使段 3 变更沿必然触发一次清窗 / zero the snapshot so the change edge clears once
    _bStaticPrev := bStatic; // 静态期快照对齐首拍值（防首拍误清窗）/ align the static snapshot to avoid a spurious clear
    _bNoiseL := FALSE; // 迟滞状态显式清零 / clear the hysteresis state explicitly
    _nNonFinite := DL_ANF_ZEROI; // 非有限计数显式清零 / clear the non finite count explicitly
    FOR _nClrIdx := DL_ANF_ZEROI TO DL_ANF_WMAX - DL_ANF_ONE DO // 有界遍历全容量 / the bounded traversal over the full capacity
        _afWin[_nClrIdx] := DL_ANF_ZERO; // 窗元素逐项清零 / zero every window element
    END_FOR
END_IF

// 段 2｜组态域闸（边界四，族② 判据：全部限值逐个点名，R272）/ segment 2, the configuration gates
_bFinLim := (fNoiseLim = fNoiseLim) AND ((fNoiseLim - fNoiseLim) = (fNoiseLim - fNoiseLim)); // 上限有限 / the ceiling is finite
_bFinHyst := (fHystPct = fHystPct) AND ((fHystPct - fHystPct) = (fHystPct - fHystPct)); // 迟滞有限 / the hysteresis is finite
_bCfgBad := (NOT _bFinLim) OR (fNoiseLim <= DL_ANF_ZERO) OR (NOT _bFinHyst) OR (fHystPct < DL_ANF_ZERO); // 组态非法 / an illegal configuration
IF _bCfgBad THEN // 组态非法：结构早退（出口三件套 + RETURN，除法段不可达）/ an illegal configuration exits structurally
    fNoiseStd := _fStdUse; // 标准差取最近有效值 [工程单位]（禁自赋值出口，R261）/ the std takes the last valid value instead of a self assignment
    bNoiseHigh := FALSE; // 判据复位 / the criterion resets
    nFill := _nFill; // 填充计数照实出口 [个] / the fill count as is
    bValid := FALSE; // 判据不可用 / the criterion is not usable
    eErr := 16#0003_071D; // 故障级：组态非法 / fault grade, an illegal configuration
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    RETURN; // 结构早退 / the structural early exit
END_IF

// 段 3｜窗长钳位与变更沿 / 静态期变更沿全窗清零（边界二）/ segment 3, the window clamp and the change edge clears
_bWinClamp := FALSE; // 钳位标记预清零（单拍信息位，段 8 映射）/ preset the clamp flag false
_bMeasBad := FALSE; // 测量失效标记预清零 / preset the failure flag false
_nUse := nWinLen; // 窗长接管 [个] / take the window length
IF (_nUse < DL_ANF_WMIN) OR (_nUse > DL_ANF_WMAX) THEN // 窗长越域 / the length is out of the domain
    _bWinClamp := TRUE; // 置钳位标记（信息级 0720）/ raise the clamp flag
    IF _nUse < DL_ANF_WMIN THEN // 下界钳位 / the floor clamp
        _nUse := DL_ANF_WMIN; // 钳到下界 [个] / clamp to the floor
    ELSE // 上界钳位 / the ceiling clamp
        _nUse := DL_ANF_WMAX; // 钳到容量 [个] / clamp to the capacity
    END_IF
END_IF
IF (_nUse <> _nUsePrev) OR (bStatic <> _bStaticPrev) THEN // 窗长或静态期变更沿（含首拍）/ the length or the static flag changed
    _nHead := DL_ANF_ZEROI; // 写头回零 / reset the write head
    _nFill := DL_ANF_ZEROI; // 填充计数回零 / reset the filled count
    _fSum := DL_ANF_ZERO; // 窗和回零 / reset the sum
    _nNonFinite := DL_ANF_ZEROI; // 非有限计数回零 / reset the non finite count
    FOR _nClrIdx := DL_ANF_ZEROI TO DL_ANF_WMAX - DL_ANF_ONE DO // 有界遍历全容量 / the bounded traversal over the full capacity
        _afWin[_nClrIdx] := DL_ANF_ZERO; // 窗元素逐项清零（禁静动混合窗） / zero every element so no mixed window remains
    END_FOR
    _nUsePrev := _nUse; // 快照本拍窗长 / snapshot the length
    _bStaticPrev := bStatic; // 快照本拍静态期 / snapshot the static flag
END_IF

// 段 4｜失能分支：判据复位 + 标准差冻结（边界七声明行）/ segment 4, the disabled branch
IF NOT bEnable THEN // 失能 / disabled
    fNoiseStd := _fStdUse; // 标准差冻结最近有效值 [工程单位] / freeze the last valid std
    bNoiseHigh := FALSE; // 判据复位 / the criterion resets
    nFill := _nFill; // 填充计数照实出口 [个] / the fill count as is
    bValid := FALSE; // 失能即不可用 / the criterion is not usable while disabled
    bError := FALSE; // 失能不是故障 / a disabled device is not a fault
    eErr := 16#0000_0000; // 失能不发码 / no code is emitted while disabled
    RETURN; // 早退，窗保留 / early return with the window kept
END_IF

// 段 5｜样本入窗（非有限丢弃并计数，边界五）/ segment 5, push the sample or count the drop
_bFinMeas := (fMeas = fMeas) AND ((fMeas - fMeas) = (fMeas - fMeas)); // 样本有限 / the sample is finite
IF bStatic AND _bFinMeas THEN // 静态期且样本有限才入窗（动态期样本不进底噪窗）/ only a finite sample of a static period enters the noise window
    _fSum := _fSum - _afWin[_nHead] + fMeas; // 滑窗和更新 [工程单位] / update the sliding sum
    _afWin[_nHead] := fMeas; // 本拍样本入环 [工程单位] / push the sample
    _nHead := _nHead + DL_ANF_ONE; // 写头推进 / advance the head
    IF _nHead >= _nUse THEN // 回卷（按钳位窗长）/ wrap by the clamped length
        _nHead := DL_ANF_ZEROI; // 写头回零 / reset the head
    END_IF
    IF _nFill < _nUse THEN // 窗未满才累加 / count only while not full
        _nFill := _nFill + DL_ANF_ONE; // 填充计数推进 [个] / advance the filled count
    END_IF
ELSIF bStatic THEN // 静态期但样本非有限：丢弃计数 / a static period sample is broken, dropped and counted
    _nNonFinite := _nNonFinite + DL_ANF_ONE; // 非有限计数推进 [个] / advance the non finite count
END_IF
IF DINT_TO_LREAL(_nNonFinite) > (DINT_TO_LREAL(_nUse) / DL_ANF_HALF) THEN // 非有限累计超窗长一半（边界五）/ the non finite count exceeds half the window
    _bMeasBad := TRUE; // 置测量失效标记（码 071E）/ raise the failure flag
END_IF
nFill := _nFill; // 填充计数出口 [个] / the fill count outlet

// 段 6｜均值与标准差两遍法（边界三：除子 _nFill−1，_nFill < 2 判据挂起）/ segment 6, the two pass mean and standard deviation
IF _nFill >= DL_ANF_TWO THEN // 除子已证 ≥ 1（禁裸除子）/ the divisor is proven at least one
    _fMean := _fSum / DINT_TO_LREAL(_nFill); // 第一遍：窗均值 [工程单位] / the first pass mean
    _fSqSum := DL_ANF_ZERO; // 离差平方和清零 [工程单位²] / clear the squared deviation sum
    FOR _nSumIdx := DL_ANF_ZEROI TO _nFill - DL_ANF_ONE DO // 有界遍历活样本（上界已证 ≤ 256）/ the bounded traversal over the live samples
        _fSqSum := _fSqSum + ((_afWin[_nSumIdx] - _fMean) * (_afWin[_nSumIdx] - _fMean)); // 第二遍：离差平方累加 [工程单位²] / the second pass accumulates the squared deviations
    END_FOR
    _fVar := _fSqSum / DINT_TO_LREAL(_nFill - DL_ANF_ONE); // 样本方差（n−1 分母）[工程单位²] / the sample variance with the n minus one divisor
    IF _fVar < DL_ANF_ZERO THEN // 负方差兜底（两遍法下理论上不可达，防御保留）/ a negative variance, unreachable by theory, kept as a defence
        _fVar := DL_ANF_ZERO; // 方差钳零 [工程单位²] / clamp the variance to zero
    END_IF
    _fStdUse := SQRT(_fVar); // 标准差 [工程单位]，SQRT 属主口径见分工声明 / the standard deviation
ELSE // 样本不足：判据挂起 / too few samples, the criterion suspends
    fNoiseStd := _fStdUse; // 标准差保持最近有效值 [工程单位] / keep the last valid std
    bNoiseHigh := FALSE; // 判据复位 / the criterion resets
    bValid := FALSE; // 判据不可用（_nFill < 2，边界三）/ the criterion is not usable
    eErr := 16#0000_0000; // 挂起不是故障 / a suspension is not a fault
    bError := FALSE; // 无故障 / no fault
    RETURN; // 早退，禁除零 / early return, no division is reached
END_IF

// 段 7｜底噪判据迟滞（边界六，两方向分别定义，R146）/ segment 7, the noise criterion hysteresis
IF NOT _bNoiseL THEN // 未报警态 / the released state
    IF _fStdUse > fNoiseLim THEN // 超过上限 / above the ceiling
        _bNoiseL := TRUE; // 置迟滞状态 / set the hysteresis state
    END_IF
ELSE // 已报警态 / the tripped state
    IF _fStdUse < (fNoiseLim * (DL_ANF_PCT - fHystPct) / DL_ANF_PCT) THEN // 回落低于上限减迟滞 / below the ceiling minus the hysteresis
        _bNoiseL := FALSE; // 复原 / release
    END_IF
END_IF

// 段 8｜统一出口（单拍位映射 + 信息级重算，R187 / FB51-8）/ segment 8, the unified outlet
fNoiseStd := _fStdUse; // 标准差出口 [工程单位] / the std outlet
bNoiseHigh := _bNoiseL; // 判据出口（迟滞状态派生）/ the criterion outlet
bValid := (NOT _bMeasBad); // 判据可用（无测量失效）/ usable without a measurement failure
IF _bMeasBad THEN // 测量失效（故障级优先）/ the measurement failed
    bValid := FALSE; // 判据不可用 / the criterion is not usable
    bError := TRUE; // 故障位置位 / raise the fault bit
    eErr := 16#0003_071E; // 故障级：测量失效 / fault grade, the measurement failed
ELSIF _bNoiseL THEN // 底噪超限（信息级）/ the noise is high, informational
    bError := FALSE; // 信息级不置故障位 / the informational code never raises the fault bit
    eErr := 16#0003_071F; // 信息级：底噪超上限 / informational, the noise is over the ceiling
ELSIF _bWinClamp THEN // 窗长钳位（信息级）/ the length clamp, informational
    bError := FALSE; // 信息级不置故障位 / no fault bit
    eErr := 16#0003_0720; // 信息级：窗长越域已钳位 / informational, the length was clamped
ELSE // 无事件 / no event
    bError := FALSE; // 无故障 / no fault
    eErr := 16#0000_0000; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
