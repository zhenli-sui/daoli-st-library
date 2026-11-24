(*
  ==================================================================
  组件名 Component  : FB_DL_OutlierFilter
  分类   Category   : DL_Algo
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0002_373F / 3742（故障级）｜ 16#0002_3740 / 3741（信息级）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 中
  功能   Purpose    : MAD 野点剔除滤波器：滑窗中值 + 绝对偏差中值（MAD）判野点，
                      野点丢弃并保持上次有效输出；真阶跃按连续剔除计数重基线，
                      禁「持续阶跃被永久拒绝」死锁。
  开源溯源 Origin    : 公开公式 clean-room，参考公开稳健统计教材的中值绝对偏差
                      （MAD）判据与 1.4826 正态一致性因子（分类与公式借鉴，零代码
                      复制），本件实现、闸门与码位 100% 自有。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6 算术运算符；MAD = median(|x − median|)
                      × 1.4826 公开稳健统计定义
  平台   Platform   : 纯 IEC 61131-3（FOR / 四则 / TON / 委托），三平台通用
  依赖   Depends    : FC_DL_SortIndexLReal（索引排序属主，本件双次委托，R140 /
                      R295 双承接）；Standard.library（TON）
  分工声明 Split     : FB_DL_MedianFilter（输出 = 中值，无判据）/ FB_DL_Signal
                      FrozenDetect（不变性监视）/ FB_DL_SensorDriftBaseline
                      （基线漂移）互引；本件为单点野点剔除 + 保持（R216）。
  归属 Ownership     : 本件无 TYPE 声明；全部引脚为 IEC 标准原生类型。
                      委托件码位随其属主回传（R66）。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 委托双承接（R295）：两次排序委托的返回值与 bValid 均由独立
                         变量承接后合取；委托码随属主回传（R66）；
                      二 窗长固定容量 64（禁动态分配）；nWinLen 越域钳位 + 信息级
                         3740，变更沿全窗清零（防新旧窗样本混算）；
                      三 判据 ABS(fIn − fMedian) > fNSigma × fSigmaHat + 1.0E-9 →
                         野点：不入窗、fOut 保持上次有效、bHold = TRUE、nReject + 1；
                      四 真阶跃处置（写死）：连续剔除计数 _nRejectRun ≥ nWinLen/2 →
                         判「真实阶跃」，清窗 + fIn 入窗直通 + 信息级 3741（禁死锁）；
                      五 tHoldMax 到时仍保持 → 故障级 3742 + bValid = FALSE（测点
                         疑似坏）；tonHold 段 0 无条件刷新，IN 串组态闸与保持态
                         （FB50-1 监视门控）；故障码逐拍重算不锁存（无 bReset 引脚，
                         R152 解除路径自证 = 修正组态 / 测点恢复入窗，恒可达）；
                      六 非有限 fIn → 视同野点丢弃（计数单列局部 nNonFinite，
                         不外显，不推进 _nRejectRun——测点坏与真阶跃不混淆）；
                      七 fNSigma 域闸 (0, 10] 且 tHoldMax > T#0S：非法 → 组态码
                         373F + 三件套 + RETURN 结构早退；
                      八 bEnable = FALSE 的语义写死（FB33-4 声明行）：输出冻结 +
                         窗保留（纯监视件），bHold 复位；
                      九 首拍 _bInit 全量初始化 + 首样本直通；中值 / MAD 为序不变量，
                         环形窗活样本恒为下标 0.._nFill−1（写头仅在达 _nUse 时回卷）；
                      十 无全局、无外部变量、无物理地址、无指针。
  错误码 Codes      :
    16#0002_373F【故障级】组态非法（fNSigma ≤ 0 / > 10 / 非有限，或 tHoldMax ≤ 0）
    16#0002_3740【信息级】nWinLen 越域已钳位（合法 4..64，不置 bError）
    16#0002_3741【信息级】真阶跃重基线触发（连续剔除达窗长一半，不置 bError）
    16#0002_3742【故障级】野点保持超 tHoldMax，测点疑似坏（bValid = FALSE）
  码位反证 Note     :
    373F / 3742 不可合并：373F 与窗内容无关（组态即刻判），3742 需窗已建立且持续
    保持，处置人不同（组态工程师 / 仪表工），可由 bHold 与窗状态还原（R90）；
    3740 / 3741 为信息级与故障级分属不同子带（R75 子带纪律），不可跨用。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 平稳序列 + 单点尖峰（10×σ）→ 剔除、fOut 保持、bHold 单拍
    V2 尖峰后立即回落 → 窗无污染；V3 真阶跃 → 连续剔除达窗长/2 后重基线直通 + 3741
    V4 fNSigma = 0 → 码 373F 早退；V5 保持超 tHoldMax → 3742 + bValid = FALSE
    V6 nWinLen = 3 → 钳 4 + 3740；V7 nWinLen 变更沿清窗；V8 首拍直通
  修订记录 Revision  :
    2026-11-21  v1.0.0  R63 首版（批 2 · 序号 7）
  ==================================================================
*)
FUNCTION_BLOCK FB_DL_OutlierFilter
VAR_INPUT
    bEnable  : BOOL := TRUE;   // 使能，FALSE 时输出冻结 + 窗保留（边界八）/ the enable, false freezes the output and keeps the window
    fIn      : LREAL := 0.0;   // 输入量 [工程单位]，必须有限 / the input value, must be finite
    nWinLen  : DINT := 16;     // 窗长 [个]，合法域 4..64，变更沿清窗 / the window length, legal four to sixty four, a change clears the window
    fNSigma  : LREAL := 4.0;   // MAD 倍数 [−]，域 (0, 10] / the MAD multiple inside the half open domain
    tHoldMax : TIME := T#5S;   // 野点连续保持上限 [毫秒]，超时判测点坏 / the hold ceiling before the point is declared broken
END_VAR
VAR_OUTPUT
    fOut     : LREAL := 0.0;            // 滤波输出 [工程单位] / the filtered output
    nReject  : UDINT := 0;             // 累计剔除计数 [个] / the accumulated reject count
    bHold    : BOOL := FALSE;          // 本拍处于保持态 [-] / the hold state of this scan
    bValid   : BOOL := FALSE;          // 输出可用 [-] / the output is usable
    eErr     : UDINT := 16#0000_0000;  // 错误码，0 = 正常 / the error code, zero is ok
    bError   : BOOL := FALSE;          // 故障标志（故障级码同拍置位，R45 配对）/ the fault flag raised with a fault level code
END_VAR
VAR
    _bInit     : BOOL := FALSE;               // 首拍初始化标志（R310 / FB50-2）/ the first scan flag
    _bHasSamp  : BOOL := FALSE;               // 已收首样本标志（首拍直通用）/ the first sample received flag
    _afWin     : ARRAY[0..63] OF LREAL;       // 采样环形窗 [工程单位]，固定容量 64 / the fixed capacity ring of samples
    _afSort    : ARRAY[0..255] OF LREAL;      // 中值排序工作数组 [工程单位] / the median sort work array
    _afDev     : ARRAY[0..255] OF LREAL;      // MAD 偏差序列工作数组 [工程单位] / the MAD deviation work array
    _aIdxM     : ARRAY[0..255] OF DINT;       // 中值排序索引承接 [下标] / the median sort index holder
    _aIdxD     : ARRAY[0..255] OF DINT;       // MAD 排序索引承接 [下标] / the MAD sort index holder
    _nHead     : DINT := 0;                   // 环形窗写头 [下标] / the ring write head
    _nFill     : DINT := 0;                   // 环形窗填充计数 [个] / the ring filled count
    _nUse      : DINT := 16;                  // 钳位后的窗长 [个] / the clamped window length
    _nUsePrev  : DINT := 0;                   // 上拍窗长快照 [个]，置 0 使首拍必触发清窗 / the previous length, zero forces one clear
    _nClrIdx   : DINT := 0;                   // 清窗遍历索引 [下标] / the clearing traversal index
    _nCopyIdx  : DINT := 0;                   // 拷贝遍历索引 [下标] / the copying traversal index
    _nMidIdx   : DINT := 0;                   // 中值下标 [下标] / the median index
    _nRejectRun: DINT := 0;                   // 连续剔除计数 [个]（真阶跃判据）/ the consecutive reject count for the step test
    _nNonFinite: DINT := 0;                   // 非有限丢弃计数 [个]（仅局部留档，不外显，R62-D7 口径）/ the dropped non finite count, local only and never exposed
    _fMedian   : LREAL := 0.0;                // 窗内中值 [工程单位] / the window median
    _fMad      : LREAL := 0.0;                // 绝对偏差中值 [工程单位] / the median absolute deviation
    _fSigmaHat : LREAL := 0.0;                // 稳健标准差估计 [工程单位] / the robust sigma estimate
    _fDev      : LREAL := 0.0;                // 本拍样本绝对偏差 [工程单位] / the absolute deviation of this scan
    _fOutLast  : LREAL := 0.0;                // 最近一次有效输出（保持源）[工程单位] / the last valid output used while holding
    _bHoldActive : BOOL := FALSE;             // 保持态寄存器（跨拍保持，tonHold 驱动源）/ the hold state register driving the timer
    _bCfgBad   : BOOL := FALSE;               // 组态非法标记（逐拍重算）/ the configuration fault flag
    _bWinClamp : BOOL := FALSE;               // 窗长钳位标记（逐拍重算，信息级 3740）/ the window clamp flag
    _bStepReb  : BOOL := FALSE;               // 真阶跃重基线标记（逐拍重算，信息级 3741）/ the step rebuild flag
    _bHoldOut  : BOOL := FALSE;               // 本拍保持出口位（统一出口映射）/ the hold outlet bit of this scan
    _bRejectI  : BOOL := FALSE;               // 本拍拒绝内部位 / the internal reject bit of this scan
    _bFinIn    : BOOL := FALSE;               // 输入有限闸结果（逐拍重算）/ the input finiteness gate result
    _bFinSig   : BOOL := FALSE;               // fNSigma 有限闸结果（逐拍重算）/ the sigma pin finiteness gate result
    _bSortRet  : BOOL := FALSE;               // 中值委托返回值承接量（独立承接，R295）/ the median delegate return holder
    _bSortValid: BOOL := FALSE;               // 中值委托可用位承接量 / the median delegate valid holder
    _bSortRet2 : BOOL := FALSE;               // MAD 委托返回值承接量（独立承接，R295）/ the MAD delegate return holder
    _bSortValid2: BOOL := FALSE;              // MAD 委托可用位承接量 / the MAD delegate valid holder
    _uSortErr  : UDINT := 16#0000_0000;       // 中值委托码承接量 [码] / the median delegate code holder
    _uSortErr2 : UDINT := 16#0000_0000;       // MAD 委托码承接量 [码] / the MAD delegate code holder
    _bSortErr  : BOOL := FALSE;               // 中值委托故障位承接量 / the median delegate fault holder
    _bSortErr2 : BOOL := FALSE;               // MAD 委托故障位承接量 / the MAD delegate fault holder
    tonHold    : TON;                         // 保持超时定时器，段 0 无条件刷新 / the hold timeout timer refreshed unconditionally
END_VAR  // R64 结构补齐：VAR 段缺失的 END_VAR（门禁机械修复）
VAR CONSTANT
    DL_OF_WMAX  : DINT := 64;       // 窗容量上界 [个]，与数组容量一致 / the window capacity aligned with the array
    DL_OF_WMIN  : DINT := 4;        // 窗长下界 [个] / the window floor
    DL_OF_NSIGMAX : LREAL := 10.0;  // MAD 倍数上界 [−] / the MAD multiple ceiling
    DL_OF_NSIGZERO: LREAL := 0.0;   // MAD 倍数零常量 [−] / the MAD multiple zero constant
    DL_OF_MADK    : LREAL := 1.4826; // MAD 正态一致性因子 [−] / the MAD normal consistency factor
    DL_OF_EPS     : LREAL := 1.0E-9; // 判据容差 [工程单位] / the criterion tolerance
    DL_OF_STEPDIV : LREAL := 2.0;   // 真阶跃判据除子 [−]（窗长一半）/ the step criterion divisor of one half
    DL_OF_ZERO    : LREAL := 0.0;   // 实数零常量 [工程单位] / the real zero constant
    DL_OF_ONE     : DINT := 1;      // 整型一常量 [个] / the integer one constant
    DL_OF_TWO     : DINT := 2;      // 整型二常量 [个]（中值判据最少样本）/ the integer two constant, the minimum for a median
    DL_OF_ZEROI   : DINT := 0;      // 整型零常量 [个] / the integer zero constant
    DL_OF_TIME0   : TIME := T#0S;   // 时间零常量 [毫秒] / the time zero constant
END_VAR

// 段 0｜组态闸先行 + 定时器无条件周期刷新（禁入分支，R7；监视 TON 串组态闸，FB50-1）/ segment 0, the configuration gate first and the unconditional timer refresh
_bFinSig := (fNSigma = fNSigma) AND ((fNSigma - fNSigma) = (fNSigma - fNSigma)); // fNSigma 有限 / the sigma pin is finite
_bCfgBad := (NOT _bFinSig) OR (fNSigma <= DL_OF_NSIGZERO) OR (fNSigma > DL_OF_NSIGMAX) OR (tHoldMax <= DL_OF_TIME0); // 组态非法（MAD 倍数域外或保持上限非正）/ an illegal configuration
tonHold(IN := _bHoldActive AND (NOT _bCfgBad), PT := tHoldMax); // 保持超时计时（串组态闸，防复位同拍重锁，FB50-1）/ the hold timeout with the configuration gate in series

// 段 1｜首拍初始化与窗长接管预派生（FB50-2）/ segment 1, the first scan init
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _bHasSamp := FALSE; // 首样本标志显式清零（触发直通）/ clear the first sample flag so the pass through triggers
    _nFill := DL_OF_ZEROI; // 填充计数显式清零 / clear the filled count explicitly
    _nHead := DL_OF_ZEROI; // 写头显式清零 / clear the write head explicitly
    _nUsePrev := DL_OF_ZEROI; // 窗长快照置 0，使段 2 变更沿必然触发一次清窗 / zero the snapshot so the change edge clears the window once
    _nRejectRun := DL_OF_ZEROI; // 连续剔除计数显式清零 / clear the consecutive reject count explicitly
    _nNonFinite := DL_OF_ZEROI; // 非有限计数显式清零 / clear the non finite count explicitly
    _bHoldActive := FALSE; // 保持态显式清零 / clear the hold state explicitly
    _fOutLast := DL_OF_ZERO; // 最近有效输出显式清零 / clear the last valid output explicitly
    FOR _nClrIdx := DL_OF_ZEROI TO DL_OF_WMAX - DL_OF_ONE DO // 有界遍历全容量 / the bounded traversal over the full capacity
        _afWin[_nClrIdx] := DL_OF_ZERO; // 窗元素逐项清零 / zero every window element
    END_FOR
END_IF

// 段 2｜窗长钳位与变更沿全窗清零（边界二）/ segment 2, the window length clamp and the full clear
_bWinClamp := FALSE; // 钳位标记预清零（单拍信息位，段 8 统一映射）/ preset the clamp flag false
_bStepReb := FALSE; // 重基线标记预清零（单拍信息位）/ preset the rebuild flag false
_bHoldOut := FALSE; // 保持出口位预清零（单拍信息位，R256 统一出口预置）/ preset the hold outlet bit false
_bRejectI := FALSE; // 拒绝内部位预清零（单拍位）/ preset the reject bit false
_nUse := nWinLen; // 窗长接管 [个] / take the window length
IF (_nUse < DL_OF_WMIN) OR (_nUse > DL_OF_WMAX) THEN // 窗长越域 / the length is out of the domain
    _bWinClamp := TRUE; // 置钳位标记（信息级 3740）/ raise the clamp flag
    IF _nUse < DL_OF_WMIN THEN // 下界钳位 / the floor clamp
        _nUse := DL_OF_WMIN; // 钳到下界 [个] / clamp to the floor
    ELSE // 上界钳位 / the ceiling clamp
        _nUse := DL_OF_WMAX; // 钳到容量 [个] / clamp to the capacity
    END_IF
END_IF
IF _nUse <> _nUsePrev THEN // 窗长变更沿（含首拍）/ the length change edge, the first scan included
    _nHead := DL_OF_ZEROI; // 写头回零 / reset the write head
    _nFill := DL_OF_ZEROI; // 填充计数回零 / reset the filled count
    _nRejectRun := DL_OF_ZEROI; // 连续剔除计数回零 / reset the consecutive reject count
    _bHasSamp := FALSE; // 窗已清，首样本语义复位 / the window is cleared, the first sample semantics reset
    FOR _nClrIdx := DL_OF_ZEROI TO DL_OF_WMAX - DL_OF_ONE DO // 有界遍历全容量 / the bounded traversal over the full capacity
        _afWin[_nClrIdx] := DL_OF_ZERO; // 窗元素逐项清零（禁陈旧样本混算）/ zero every window element so no stale sample mixes in
    END_FOR
    _nUsePrev := _nUse; // 快照本拍窗长 / snapshot the length
END_IF

// 段 3｜失能分支：输出冻结 + 窗保留（边界八声明行）/ segment 3, the disabled branch freezes the output
IF NOT bEnable THEN // 失能 / disabled
    fOut := _fOutLast; // 冻结最后有效输出 [工程单位] / freeze the last valid output
    bHold := FALSE; // 保持态复位 / the hold state resets
    bValid := FALSE; // 失能即不可用 / the output is not usable while disabled
    bError := FALSE; // 失能不是故障 / a disabled device is not a fault
    eErr := 16#0000_0000; // 失能不发码 / no code is emitted while disabled
    _bHoldActive := FALSE; // 保持态寄存器复位（tonHold 断输入）/ clear the hold state register
    RETURN; // 早退，窗保留；nReject 为累计量按 R187 不清零（保持语义由本注释表达，禁自赋值行）/ early return with the window kept, the accumulated reject count is kept per the pulse discipline, expressed by this comment without a dead statement
END_IF

// 段 4｜组态非法结构早退（边界七，出口三件套 + RETURN）/ segment 4, the structural early exit on an illegal configuration
IF _bCfgBad THEN // 组态非法 / an illegal configuration
    fOut := _fOutLast; // 输出保持最近有效值 [工程单位] / keep the last valid output
    bHold := FALSE; // 保持态复位 / the hold state resets
    bValid := FALSE; // 输出不可用 / the output is not usable
    eErr := 16#0002_373F; // 故障级：组态非法 / fault grade, an illegal configuration
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    _bHoldActive := FALSE; // 保持态寄存器复位 / clear the hold state register
    RETURN; // 早退，判据段不可达 / early return, the criterion segment is unreachable
END_IF

// 段 5｜输入有限闸（边界六）/ segment 5, the input finiteness gate
_bFinIn := (fIn = fIn) AND ((fIn - fIn) = (fIn - fIn)); // 输入有限 / the input is finite
IF NOT _bHasSamp THEN // 首样本直通（边界十）/ the first sample passes straight through
    _afWin[_nHead] := fIn; // 首样本入窗 [工程单位] / the first sample enters the window
    _nHead := _nHead + DL_OF_ONE; // 写头推进 / advance the head
    IF _nHead >= _nUse THEN // 回卷 / wrap
        _nHead := DL_OF_ZEROI; // 写头回零 / reset the head
    END_IF
    _nFill := _nFill + DL_OF_ONE; // 填充计数推进 [个] / advance the filled count
    fOut := fIn; // 首拍直通 [工程单位] / the first scan passes straight through
    _fOutLast := fIn; // 有效输出快照 [工程单位] / snapshot the valid output
    _bHasSamp := TRUE; // 置首样本标志 / raise the first sample flag
    bHold := FALSE; // 无保持 / no hold
    bValid := TRUE; // 输出可用 / the output is usable
    eErr := 16#0000_0000; // 正常 / ok
    bError := FALSE; // 无故障 / no fault
    RETURN; // 早退 / early return
END_IF

// 段 6｜非有限输入：视同野点丢弃（边界六，计数单列，不推进连续剔除计数）/ segment 6, a non finite input is dropped like an outlier
IF NOT _bFinIn THEN // 输入坏 / the input is broken
    _nNonFinite := _nNonFinite + DL_OF_ONE; // 非有限计数推进（仅局部留档）/ advance the non finite count, local only
    _bHoldActive := TRUE; // 置保持态（tonHold 持续计时）/ raise the hold state
    fOut := _fOutLast; // 输出保持 [工程单位] / keep the output
    bHold := TRUE; // 保持出口位 / the hold outlet
    bValid := TRUE; // 保持值本身可用（未超时前）/ the held value is still usable before the timeout
    eErr := 16#0000_0000; // 信息级不占故障位 / no fault code for a single drop
    bError := FALSE; // 无故障 / no fault
    RETURN; // 早退 / early return
END_IF

// 段 7｜中值与 MAD 计算（两次委托，双承接 R295；活样本恒为 0.._nFill−1，边界九）/ segment 7, the median and the MAD via two delegates
IF _nFill >= DL_OF_TWO THEN // 窗内至少两样本才建判据（单样本无离散度语义）/ the criterion needs at least two samples
    FOR _nCopyIdx := DL_OF_ZEROI TO _nFill - DL_OF_ONE DO // 有界遍历活样本（上界已证 ≤ 64）/ the bounded traversal over the live samples
        _afSort[_nCopyIdx] := _afWin[_nCopyIdx]; // 拷贝到排序工作数组 [工程单位] / copy into the sort work array
    END_FOR
    _bSortRet := FC_DL_SortIndexLReal(afValues := _afSort, nCount := _nFill, aIdx => _aIdxM, bValid => _bSortValid, eErr => _uSortErr, bError => _bSortErr); // 中值排序委托 / delegate the median sort
    _nMidIdx := (_nFill - DL_OF_ONE) / DL_OF_TWO; // 中值下标（偶数窗取下中值）[下标] / the median index, the lower median for an even window
    _fMedian := _afSort[_aIdxM[_nMidIdx]]; // 窗内中值 [工程单位] / the window median
    FOR _nCopyIdx := DL_OF_ZEROI TO _nFill - DL_OF_ONE DO // 有界遍历活样本 / the bounded traversal over the live samples
        _afDev[_nCopyIdx] := ABS(_afWin[_nCopyIdx] - _fMedian); // 绝对偏差序列 [工程单位] / the absolute deviation series
    END_FOR
    _bSortRet2 := FC_DL_SortIndexLReal(afValues := _afDev, nCount := _nFill, aIdx => _aIdxD, bValid => _bSortValid2, eErr => _uSortErr2, bError => _bSortErr2); // MAD 排序委托（双承接）/ delegate the MAD sort with the dual catch
    _fMad := _afDev[_aIdxD[_nMidIdx]]; // 绝对偏差中值 [工程单位] / the median absolute deviation
    _fSigmaHat := _fMad * DL_OF_MADK; // 稳健标准差估计 [工程单位] / the robust sigma estimate
    IF (NOT (_bSortRet AND _bSortValid)) OR _bSortErr OR (NOT (_bSortRet2 AND _bSortValid2)) OR _bSortErr2 THEN // 任一委托失败（双承接合取，R295）/ either delegate failed under the dual catch
        fOut := _fOutLast; // 输出保持 [工程单位] / keep the output
        bHold := FALSE; // 保持态不置（委托失败非野点）/ the hold is not raised, a delegate failure is not an outlier
        bValid := FALSE; // 输出不可用 / the output is not usable
        eErr := _uSortErr; // 委托码回传（码随属主，R66）/ replay the delegate code
        bError := _bSortErr OR _bSortErr2; // 委托故障位回传 / replay the delegate fault bits
        RETURN; // 早退 / early return
    END_IF
ELSE // 窗内样本不足：判据挂起，直接接受本拍样本 / too few samples, the criterion suspends and the sample is accepted
    _fMedian := _afWin[DL_OF_ZEROI]; // 中值占位（不参与判据）[工程单位] / a placeholder median, not used by the criterion
    _fSigmaHat := DL_OF_ZERO; // 离散度占位零 [工程单位] / a placeholder sigma of zero
END_IF

// 段 8｜野点判据与真阶跃处置（边界三四；本拍接受语义优先于超时迁移，R275）/ segment 8, the outlier criterion and the true step handling
_fDev := ABS(fIn - _fMedian); // 本拍绝对偏差 [工程单位] / the absolute deviation of this scan
IF _nFill >= DL_OF_TWO THEN // 判据已建立才比较 / the comparison runs only with a built criterion
    IF _fDev > (fNSigma * _fSigmaHat) + DL_OF_EPS THEN // 超出 MAD 带外：疑似野点 / beyond the MAD band, a suspected outlier
        _nRejectRun := _nRejectRun + DL_OF_ONE; // 连续剔除计数推进 [个] / advance the consecutive reject count
        IF DINT_TO_LREAL(_nRejectRun) >= (DINT_TO_LREAL(_nUse) / DL_OF_STEPDIV) THEN // 连续剔除达窗长一半：判真阶跃（边界四，禁死锁）/ the consecutive rejects reach half the window, a true step
            _nHead := DL_OF_ZEROI; // 清窗：写头回零 / the rebuild, the head resets
            _nFill := DL_OF_ONE; // 填充计数重置为新基线首样本 [个] / the fill resets to the first sample of the new base
            _nRejectRun := DL_OF_ZEROI; // 连续剔除计数清零 / clear the consecutive reject count
            FOR _nClrIdx := DL_OF_ZEROI TO DL_OF_WMAX - DL_OF_ONE DO // 有界遍历全容量 / the bounded traversal over the full capacity
                _afWin[_nClrIdx] := DL_OF_ZERO; // 窗元素逐项清零 / zero every window element
            END_FOR
            _afWin[DL_OF_ZEROI] := fIn; // 新基线首样本入窗 [工程单位] / the new base sample enters the window
            _nHead := DL_OF_ONE; // 写头推进一位 / advance the head by one
            fOut := fIn; // 阶跃直通 [工程单位] / the step passes straight through
            _fOutLast := fIn; // 有效输出快照 [工程单位] / snapshot the valid output
            _bStepReb := TRUE; // 置重基线标记（信息级 3741）/ raise the rebuild flag
            _bHoldActive := FALSE; // 保持态解除 / release the hold state
            bHold := FALSE; // 保持出口位复位 / the hold outlet resets
            bValid := TRUE; // 输出可用 / the output is usable
            bError := FALSE; // 信息级不置故障位 / the informational code never raises the fault bit
            IF _bWinClamp THEN // 同拍窗长钳位（信息级优先序：钳位先于重基线）/ a clamp on the same scan
                eErr := 16#0002_3740; // 信息级：窗长越域已钳位 / informational, the length was clamped
            ELSE // 无钳位 / no clamp
                eErr := 16#0002_3741; // 信息级：真阶跃重基线触发 / informational, a true step rebuilt the base
            END_IF
            RETURN; // 早退 / early return
        ELSE // 单点野点：丢弃并保持（边界三）/ a single outlier, dropped with the output held
            _bHoldActive := TRUE; // 置保持态 / raise the hold state
            _bHoldOut := TRUE; // 保持出口位置位（段 10 映射）/ raise the hold outlet bit
            _bRejectI := TRUE; // 拒绝位置位 / raise the reject bit
            fOut := _fOutLast; // 输出保持上次有效值 [工程单位] / hold the last valid output
        END_IF
    ELSE // 带内：接受样本 / inside the band, the sample is accepted
        _afWin[_nHead] := fIn; // 样本入窗 [工程单位] / the sample enters the window
        _nHead := _nHead + DL_OF_ONE; // 写头推进 / advance the head
        IF _nHead >= _nUse THEN // 回卷 / wrap
            _nHead := DL_OF_ZEROI; // 写头回零 / reset the head
        END_IF
        IF _nFill < _nUse THEN // 窗未满才累加 / count only while not full
            _nFill := _nFill + DL_OF_ONE; // 填充计数推进 [个] / advance the filled count
        END_IF
        _nRejectRun := DL_OF_ZEROI; // 连续剔除计数清零 / clear the consecutive reject count
        _bHoldActive := FALSE; // 保持态解除 / release the hold state
        fOut := fIn; // 接受直通 [工程单位] / the accepted sample passes straight through
        _fOutLast := fIn; // 有效输出快照 [工程单位] / snapshot the valid output
    END_IF
ELSE // 判据挂起拍：直接接受（窗建立期）/ the criterion suspended, the sample is accepted while the window builds
    _afWin[_nHead] := fIn; // 样本入窗 [工程单位] / the sample enters the window
    _nHead := _nHead + DL_OF_ONE; // 写头推进 / advance the head
    IF _nHead >= _nUse THEN // 回卷 / wrap
        _nHead := DL_OF_ZEROI; // 写头回零 / reset the head
    END_IF
    IF _nFill < _nUse THEN // 窗未满才累加 / count only while not full
        _nFill := _nFill + DL_OF_ONE; // 填充计数推进 [个] / advance the filled count
    END_IF
    _nRejectRun := DL_OF_ZEROI; // 连续剔除计数清零 / clear the consecutive reject count
    _bHoldActive := FALSE; // 保持态解除 / release the hold state
    fOut := fIn; // 接受直通 [工程单位] / the accepted sample passes straight through
    _fOutLast := fIn; // 有效输出快照 [工程单位] / snapshot the valid output
END_IF

// 段 9｜保持超时判据（边界五：测点疑似坏）/ segment 9, the hold timeout test
IF tonHold.Q THEN // 保持超 tonHoldMax / the hold exceeded its ceiling
    fOut := _fOutLast; // 输出保持（安全侧冻结）[工程单位] / hold the output
    bHold := TRUE; // 保持出口位 / the hold outlet
    bValid := FALSE; // 测点疑似坏，输出不可用 / the point is suspected broken, the output is unusable
    eErr := 16#0002_3742; // 故障级：保持超时 / fault grade, the hold timed out
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    RETURN; // 早退 / early return
END_IF

// 段 10｜统一出口（单拍位映射 + 累计计数单点写入，R187 / FB51-8）/ segment 10, the unified outlet
bHold := _bHoldOut; // 保持出口位（段 2 预置 + 段 8 置位映射）/ the hold outlet mapped from the preset and the raise
IF _bRejectI THEN // 本拍发生拒绝 / a reject happened on this scan
    nReject := nReject + 1; // 累计剔除计数单点写入 [个] / the accumulated reject count written at this single point
END_IF
bValid := TRUE; // 输出可用 / the output is usable
bError := FALSE; // 无故障 / no fault
IF _bWinClamp THEN // 窗长钳位（信息级，逐拍重算）/ the length clamp, informational and recomputed
    eErr := 16#0002_3740; // 信息级：窗长越域已钳位 / informational, the length was clamped
ELSE // 无事件 / no event
    eErr := 16#0000_0000; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
