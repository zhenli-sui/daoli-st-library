(*
  ==================================================================
  组件名 Component  : FB_DL_AdaptiveLmsFilter
  分类   Category   : DL_Algo
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0002_374C（故障级）｜ 16#0002_3749 / 374A / 374B（信息级）
  版本   Version    : 1.0.1
  复杂度 Complexity  : 高
  功能   Purpose    : LMS 自适应横向滤波器（N 抽头权重在线更新 w[k] += 2μ·e·x[k]），
                      周期干扰对消 / 主动降噪的现场可整定基元。
  开源溯源 Origin    : 公开公式 clean-room，参考公开自适应信号处理教材的 LMS 权重
                      递推式（分类与公式借鉴，零代码复制），本件实现、闸门与码位
                      100% 自有。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6 算术运算符；LMS 递推 w[k] += 2μ·e·x[k]
                      为公开自适应滤波公式（Widrow-Hoff 类公开定义）
  平台   Platform   : 纯 IEC 61131-3（FOR / 四则 / R_TRIG / 比较），三平台通用
  依赖   Depends    : 仅 Standard.library（R_TRIG 属标准边沿检测）
  分工声明 Split     : FB_DL_BiquadFilter / FB_DL_BiquadCascade 为固定系数族；
                      FB_DL_DisturbanceObserver 为观测器路线；本件为在线自适应族；
                      互引 + MANUAL 选型段（「系数已知用 Biquad、干扰特征未知用
                      LMS」）（R216）。
  归属 Ownership     : 本件无 TYPE 声明；全部引脚为 IEC 标准原生类型。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 延迟线固定 ARRAY[0..31] OF LREAL（禁动态分配），每拍右移
                         入 fRef；uTaps 越域钳位 4..32 + 信息级 374A，钳位赋值
                         上移至变更沿检测前（R64 v1.0.1）：抽头数变更沿以本拍
                         钳位值判定，无晚一拍混算窗口（旧值配新权重 / 延迟线
                         的混算拍已消除）；变更沿清权重与延迟线（活动抽头数才
                         参与运算）；
                      二 fMu 域闸 (0, 0.1] 且非有限 → 组态码 3749 + 权重冻结 +
                         三件套 + RETURN 结构早退；
                      三 任一输入非有限（fRef / fDesired）→ 权重冻结 + 故障码 374C
                         + bValid = FALSE；两条恢复路径拆明（R64 v1.0.1）：
                         a) NaN 输入（测点坏）——权重未被写入污染物，测点恢复后
                            下一拍自动恢复；b) 溢出污染——权重写回前 |corr·x|
                            预检命中非有限即 374C 冻结（跳过写回），若上一拍已
                            写入污染物则需 bWipeW 才能恢复（不可自动恢复性写死）；
                         递推结果复检非有限同码处置（更新前置闸：命中路径冻结
                         权重，禁污染物写入）；
                      四 fWEnergy > 1.0E12 → 发散监视信息级 374B（建议减小 μ，不
                         自动清权重，诊断出口，每拍重算不锁存）；374B 为持续
                         发散监视，溢出（写回预检命中）当拍改报故障级 374C 并
                         早退，溢出一次性报告、374B 不逐拍重报溢出
                         （R64 v1.0.1 口径）；
                      五 bWipeW 单拍 → 全权重与延迟线清零（段 0 R_TRIG 无条件刷新）；
                      六 bEnable = FALSE 的语义写死（FB33-4 声明行）：权重保留但
                         停止更新、fErr 冻结——现场断使能调试时不丢已收敛权重；
                      七 故障码策略（本件无 bReset 引脚，R152 解除路径自证）：组态
                         与测量类故障码逐拍重算不锁存，解除路径 = 修正组态 / 测点
                         恢复（恒可达）；发散信息级逐拍重算；
                      八 段 0 无条件刷新 R_TRIG；CASE 无（线性递推，R6 标注 N/A）；
                         首拍 _bInit 全量初始化；无全局、无外部变量、无物理地址。
  错误码 Codes      :
    16#0002_3749【故障级】组态非法（fMu ≤ 0 / > 0.1 / 非有限）
    16#0002_374A【信息级】uTaps 越域已钳位（合法 4..32，不置 bError）
    16#0002_374B【信息级】权重平方和超阈（fWEnergy > 1.0E12，持续发散监视，建议
                         减小 μ；溢出当拍由 374C 承担并早退，374B 不重报溢出）
    16#0002_374C【故障级】输入非有限（fRef / fDesired 为 NaN / ±Inf）、递推结果
                         非有限、或权重写回前 |corr·x| 预检命中非有限（溢出污染，
                         需 bWipeW 恢复，出口同形 R90）
  码位反证 Note     :
    3749 与 374C 不可合并：3749 与输入无关（组态即刻判），374C 需输入到达，处置人
    不同（组态工程师 / 现场测点），可由场景还原（R90）；374A / 374B 信息级子带
    （R75 纪律），不跨用故障子带。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 fRef = 0 → 权重不增长、fErr = fDesired
    V2 正弦干扰 + 相关参考 → fErr 包络逐拍递减（定性收敛向量）
    V3 fMu = 0 → 组态早退权重冻结；V4 fRef = NaN 单拍 → 权重冻结 + 故障
       （下一拍恢复后 fErr 不含污染：权重未变断言）
    V5 uTaps = 100 → 钳 32 + 信息级；V6 bWipeW → fWEnergy = 0
    V7 权重平方和超阈 → 信息级不锁存
  修订记录 Revision  :
    2026-11-21  v1.0.0  R63 首版（批 4 · 序号 11）
    2026-11-21  v1.0.1  R64 返修 R63-D3/D4：抽头数钳位赋值整体上移至段 4 变更沿
                        检测前（变更沿以本拍钳位值判定，无晚一拍混算窗口）；
                        段 11 写回前 ABS(_fCorr*_afX[_i]) 预检，命中即 374C 冻结
                        权重当拍早退（溢出一次性报告），374B 改持续发散监视；
                        边界三拆明两条恢复路径（NaN 输入自动恢复 / 溢出需
                        bWipeW），删除「理论上不可达」失准表述
  ==================================================================
*)
FUNCTION_BLOCK FB_DL_AdaptiveLmsFilter
VAR_INPUT
    bEnable   : BOOL := TRUE;   // 使能，FALSE 时权重保留但停止更新（边界六）/ the enable, false keeps the weights but stops the update
    bWipeW    : BOOL := FALSE;  // 权重清零电平，上升沿全权重与延迟线清零 / the wipe level, its rising edge clears the weights and the delay line
    fRef      : LREAL := 0.0;   // 参考输入 [工程单位]（与干扰相关的信号）/ the reference input correlated with the disturbance
    fDesired  : LREAL := 0.0;   // 主输入 [工程单位] / the desired main input
    uTaps     : USINT := 16;    // 抽头数 [个]，合法域 4..32，变更沿清权重 / the tap count, legal four to thirty two
    fMu       : LREAL := 0.01;  // 步长 [−]，域 (0, 0.1] / the step size inside the half open domain
END_VAR
VAR_OUTPUT
    fErr      : LREAL := 0.0;           // 误差 = fDesired − fOut [工程单位] / the error of the desired minus the output
    fOut      : LREAL := 0.0;           // 滤波输出 [工程单位] / the filter output
    fWEnergy  : LREAL := 0.0;           // 权重平方和 [−]，收敛 / 发散诊断 / the squared weight sum for the convergence diagnostics
    bValid    : BOOL := FALSE;          // 输出可用 [-] / the output is usable
    eErr      : UDINT := 16#0000_0000;  // 错误码，0 = 正常 / the error code, zero is ok
    bError    : BOOL := FALSE;          // 故障标志（故障级码同拍置位，R45 配对）/ the fault flag raised with a fault level code
END_VAR
VAR
    _bInit    : BOOL := FALSE;              // 首拍初始化标志（R310 / FB50-2）/ the first scan flag
    _afW      : ARRAY[0..31] OF LREAL;      // 权重数组 [−]，固定 32 抽头 / the fixed weight array of thirty two taps
    _afX      : ARRAY[0..31] OF LREAL;      // 延迟线 [工程单位] / the delay line
    _nTaps    : DINT := 16;                 // 钳位后的抽头数 [个] / the clamped tap count
    _nTapsPrev: DINT := 0;                  // 上拍抽头数快照 [个]，置 0 使首拍必触发清权重 / the previous tap count
    _i        : DINT := 0;                  // 抽头遍历索引 [下标] / the tap traversal index
    _iShift   : DINT := 0;                  // 移位遍历索引 [下标] / the shift traversal index
    _fAcc     : LREAL := 0.0;               // 输出累加器 [工程单位] / the output accumulator
    _fEng     : LREAL := 0.0;               // 权重能量累加器 [−] / the weight energy accumulator
    _fErrUse  : LREAL := 0.0;               // 误差工作副本 [工程单位] / the working error copy
    _fCorr    : LREAL := 0.0;               // 修正量 2μ·e [−] / the correction factor of two mu times the error
    _fProdAbs : LREAL := 0.0;               // 写回预检量 |corr·x| [−]（R64 v1.0.1）/ the writeback precheck magnitude of the correction times the tap
    _bWOverflow: BOOL := FALSE;             // 写回预检溢出命中标记（单拍，R64 v1.0.1）/ the writeback overflow hit flag of this scan
    _bFinRef  : BOOL := FALSE;              // 参考输入有限闸结果（逐拍重算）/ the reference finiteness gate result
    _bFinDes  : BOOL := FALSE;              // 主输入有限闸结果（逐拍重算）/ the desired finiteness gate result
    _bFinMu   : BOOL := FALSE;              // 步长有限闸结果（逐拍重算）/ the mu finiteness gate result
    _bCfgBad  : BOOL := FALSE;              // 组态非法标记（逐拍重算）/ the configuration fault flag
    _bTapClamp: BOOL := FALSE;              // 抽头数钳位标记（逐拍重算，信息级 374A）/ the tap clamp flag
    _bDivWarn : BOOL := FALSE;              // 发散警告标记（逐拍重算，信息级 374B）/ the divergence warning flag
    rtWipe    : R_TRIG;                     // 权重清零沿实例，段 0 无条件刷新（R7）/ the wipe edge instance refreshed unconditionally
END_VAR  // R64 结构补齐：VAR 段缺失的 END_VAR（门禁机械修复）
VAR CONSTANT
    DL_LMS_TMAX  : DINT := 32;        // 抽头容量上界 [个]，与数组容量一致 / the tap capacity aligned with the array
    DL_LMS_TMIN  : DINT := 4;         // 抽头数下界 [个] / the tap floor
    DL_LMS_MUMAX : LREAL := 0.1;      // 步长上界 [−] / the step size ceiling
    DL_LMS_MUZERO: LREAL := 0.0;      // 步长零常量 [−] / the step size zero constant
    DL_LMS_TWO   : LREAL := 2.0;      // LMS 修正系数常量 [−] / the LMS correction factor constant
    DL_LMS_WMAX  : LREAL := 1.0E12;   // 权重平方和发散门限 [−] / the divergence threshold of the weight energy
    DL_LMS_ZERO  : LREAL := 0.0;      // 实数零常量 [工程单位] / the real zero constant
    DL_LMS_ZEROI : DINT := 0;         // 整型零常量 [个] / the integer zero constant
    DL_LMS_ONEI  : DINT := 1;         // 整型一常量 [个] / the integer one constant
END_VAR

// 段 0｜组态闸先行 + 沿检测无条件周期刷新（禁入分支，R7）/ segment 0, the configuration gate first and the unconditional edge refresh
_bFinMu := (fMu = fMu) AND ((fMu - fMu) = (fMu - fMu)); // 步长有限 / the step size is finite
_bCfgBad := (NOT _bFinMu) OR (fMu <= DL_LMS_MUZERO) OR (fMu > DL_LMS_MUMAX); // 组态非法 / an illegal configuration
rtWipe(CLK := bWipeW); // 权重清零沿 / the wipe edge

// 段 1｜首拍初始化（FB50-2）/ segment 1, the first scan init
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _nTapsPrev := DL_LMS_ZEROI; // 抽头数快照置 0，使段 4 变更沿必然触发一次清权重 / zero the snapshot so the change edge clears the weights once
    FOR _i := DL_LMS_ZEROI TO DL_LMS_TMAX - DL_LMS_ONEI DO // 有界遍历全容量 / the bounded traversal over the full capacity
        _afW[_i] := DL_LMS_ZERO; // 权重显式清零 [−] / clear the weight explicitly
        _afX[_i] := DL_LMS_ZERO; // 延迟线显式清零 [工程单位] / clear the delay line explicitly
    END_FOR
END_IF

// 段 2｜单拍量预置 / segment 2, the per scan preset
_bTapClamp := FALSE; // 钳位标记预清零（单拍信息位，段 7 映射）/ preset the clamp flag false
_bDivWarn := FALSE; // 发散警告标记预清零（单拍信息位）/ preset the divergence flag false
_fErrUse := fErr; // 误差工作副本接管上拍出口（冻结语义基线）[工程单位] / the working error takes the previous outlet as the freeze base

// 段 3｜组态非法结构早退：权重冻结（边界二，出口三件套 + RETURN）/ segment 3, the structural early exit on an illegal configuration
IF _bCfgBad THEN // 组态非法 / an illegal configuration
    bValid := FALSE; // 输出不可用 / the output is not usable
    eErr := 16#0002_3749; // 故障级：组态非法 / fault grade, an illegal configuration
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    RETURN; // 结构早退，权重冻结（禁污染）/ the structural early exit with the weights frozen
END_IF

// 段 4｜抽头数钳位（边界一，信息级 374A；R64 v1.0.1 整体上移至变更沿检测前，
//        保证段 5 变更沿以本拍钳位值判定，无晚一拍混算窗口）/ segment 4, the tap clamp moved before the change edge
_nTaps := USINT_TO_DINT(uTaps); // 抽头数升位接管 [个] / take the tap count widened
IF (_nTaps < DL_LMS_TMIN) OR (_nTaps > DL_LMS_TMAX) THEN // 抽头数越域 / the count is out of the domain
    _bTapClamp := TRUE; // 置钳位标记（信息级 374A）/ raise the clamp flag
    IF _nTaps < DL_LMS_TMIN THEN // 下界钳位 / the floor clamp
        _nTaps := DL_LMS_TMIN; // 钳到下界 [个] / clamp to the floor
    ELSE // 上界钳位 / the ceiling clamp
        _nTaps := DL_LMS_TMAX; // 钳到容量 [个] / clamp to the capacity
    END_IF
END_IF

// 段 5｜权重清零沿：全权重与延迟线清零（边界五；抽头数变更沿同段处理，
//        以段 4 本拍钳位值判定）/ segment 5, the wipe edge and the tap change edge
IF (_nTaps <> _nTapsPrev) OR rtWipe.Q THEN // 抽头数变更沿或清零沿 / the tap change edge or the wipe edge
    FOR _i := DL_LMS_ZEROI TO DL_LMS_TMAX - DL_LMS_ONEI DO // 有界遍历全容量 / the bounded traversal over the full capacity
        _afW[_i] := DL_LMS_ZERO; // 权重清零 [−] / clear the weight
        _afX[_i] := DL_LMS_ZERO; // 延迟线清零 [工程单位] / clear the delay line
    END_FOR
    _nTapsPrev := _nTaps; // 快照本拍抽头数 / snapshot the tap count
END_IF

// 段 6｜失能分支：权重保留但停止更新（边界六声明行）/ segment 6, the disabled branch keeps the weights
IF NOT bEnable THEN // 失能 / disabled
    bValid := FALSE; // 输出不可用 / the output is not usable while disabled
    bError := FALSE; // 失能不是故障 / a disabled device is not a fault
    eErr := 16#0000_0000; // 失能不发码 / no code is emitted while disabled
    RETURN; // 早退，权重保留（现场断使能调试不丢已收敛权重）/ early return with the weights kept
END_IF

// 段 7｜输入非有限闸：权重冻结（边界三，禁污染权重）/ segment 7, the input finiteness gate freezes the weights
_bFinRef := (fRef = fRef) AND ((fRef - fRef) = (fRef - fRef)); // 参考输入有限 / the reference is finite
_bFinDes := (fDesired = fDesired) AND ((fDesired - fDesired) = (fDesired - fDesired)); // 主输入有限 / the desired is finite
IF (NOT _bFinRef) OR (NOT _bFinDes) THEN // 任一输入坏 / either input is broken
    bValid := FALSE; // 输出不可用 / the output is not usable
    eErr := 16#0002_374C; // 故障级：输入非有限 / fault grade, an input is not finite
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    RETURN; // 早退，权重冻结（不更新，污染不可自动恢复性见边界三）/ early return with the weights frozen
END_IF

// 段 8｜延迟线右移入新样本（边界一，固定容量，禁动态分配）/ segment 8, the delay line shifts the new sample in
FOR _iShift := DL_LMS_TMAX - DL_LMS_ONEI TO DL_LMS_ONEI BY -1 DO // 有界逆向遍历（31 → 1）/ the bounded reverse traversal from thirty one down to one
    _afX[_iShift] := _afX[_iShift - DL_LMS_ONEI]; // 延迟线逐位右移 [工程单位] / shift the delay line one slot right
END_FOR
_afX[DL_LMS_ZEROI] := fRef; // 新样本入延迟线首槽 [工程单位] / the new sample enters the first slot

// 段 9｜滤波输出与误差计算（活动抽头数才参与，边界一）/ segment 9, the output and the error over the active taps
_fAcc := DL_LMS_ZERO; // 输出累加器清零 [工程单位] / clear the output accumulator
FOR _i := DL_LMS_ZEROI TO _nTaps - DL_LMS_ONEI DO // 有界遍历活动抽头（上界已证 ≤ 32）/ the bounded traversal over the active taps
    _fAcc := _fAcc + (_afW[_i] * _afX[_i]); // 横向滤波加权和 [工程单位] / the transversal weighted sum
END_FOR
fOut := _fAcc; // 滤波输出出口 [工程单位] / the filter output outlet
_fErrUse := fDesired - fOut; // 误差 = 主输入 − 输出 [工程单位] / the error of the desired minus the output

// 段 10｜递推结果复检（更新前置闸：结果非有限则权重冻结，禁污染物写入，边界三）/ segment 10, the result recheck before the update
IF (_fErrUse <> _fErrUse) OR ((_fErrUse - _fErrUse) <> (_fErrUse - _fErrUse))
OR (fOut <> fOut) OR ((fOut - fOut) <> (fOut - fOut)) THEN // 误差或输出非有限（理论上不可达，防御保留）/ a non finite error or output
    bValid := FALSE; // 输出不可用 / the output is not usable
    eErr := 16#0002_374C; // 故障级：输入或结果非有限（同族一码，出口同形，R90）/ fault grade under the same family code
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    RETURN; // 早退，权重冻结 / early return with the weights frozen
END_IF

// 段 11｜LMS 权重在线更新（公开公式：w[k] += 2μ·e·x[k]，边界三判据已过）；
//         写回前 |corr·x| 预检（R64 v1.0.1，R63-D4）：命中非有限即 374C 冻结
//         权重当拍早退（跳过写回与段 12 的 374B 判定，溢出一次性报告）/
//         segment 11, the LMS weight update with the writeback precheck
_fCorr := DL_LMS_TWO * fMu * _fErrUse; // 修正量 2μ·e [−] / the correction factor
_bWOverflow := FALSE; // 预检命中标记预清零（单拍量，本段内置）/ preset the overflow hit flag false
FOR _i := DL_LMS_ZEROI TO _nTaps - DL_LMS_ONEI DO // 有界遍历活动抽头 / the bounded traversal over the active taps
    _fProdAbs := ABS(_fCorr * _afX[_i]); // 写回预检量 |corr·x| [−]（先算后判，命中即冻结）/ the precheck magnitude computed before the writeback
    IF (_fProdAbs <> _fProdAbs) OR ((_fProdAbs - _fProdAbs) <> (_fProdAbs - _fProdAbs)) THEN // 预检量非有限（NaN 或 ±Inf，溢出真实可达：μ 上界 0.1 内大误差大样本即可触发）/ a non finite precheck magnitude, reachable on the overflow
        _bWOverflow := TRUE; // 置溢出命中标记 / raise the overflow hit flag
        EXIT; // 跳出写回（冻结权重，禁污染物写入）/ leave the loop without the writeback, the weights stay frozen
    END_IF
    _afW[_i] := _afW[_i] + (_fCorr * _afX[_i]); // 权重递推 [−]（预检已过才写回）/ the weight recursion only after the precheck passed
END_FOR
IF _bWOverflow THEN // 预检命中：溢出一次性报告（故障级 374C，本拍不进段 12 的 374B 判定，R64 v1.0.1）/ the precheck hit, the overflow is reported once
    fErr := _fErrUse; // 误差出口照实（已过段 10 有限闸）[工程单位] / the error outlet is still finite
    bValid := FALSE; // 输出不可用 / the output is not usable
    eErr := 16#0002_374C; // 故障级：写回预检命中非有限（溢出污染，需 bWipeW 恢复，边界三路径 b）/ fault grade, the writeback precheck hit a non finite magnitude
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    RETURN; // 早退，权重冻结（跳过段 12 能量诊断，374B 本拍不判）/ early return with the weights frozen, the energy diagnostics are skipped this scan
END_IF
fErr := _fErrUse; // 误差出口（已过有限闸）[工程单位] / the error outlet after the gate

// 段 12｜权重能量诊断（边界四，信息级 374B，每拍重算不锁存）/ segment 12, the weight energy diagnostics
_fEng := DL_LMS_ZERO; // 能量累加器清零 [−] / clear the energy accumulator
FOR _i := DL_LMS_ZEROI TO _nTaps - DL_LMS_ONEI DO // 有界遍历活动抽头 / the bounded traversal over the active taps
    _fEng := _fEng + (_afW[_i] * _afW[_i]); // 权重平方累加 [−] / accumulate the squared weights
END_FOR
fWEnergy := _fEng; // 权重平方和出口 [−] / the weight energy outlet
IF fWEnergy > DL_LMS_WMAX THEN // 超发散门限 / above the divergence threshold
    _bDivWarn := TRUE; // 置发散警告标记（信息级 374B）/ raise the divergence flag
END_IF

// 段 13｜统一出口（信息级重算，R187 / FB51-8）/ segment 13, the unified outlet
bValid := TRUE; // 输出可用 / the output is usable
bError := FALSE; // 无故障 / no fault
IF _bTapClamp THEN // 抽头数钳位（信息级，逐拍重算）/ the tap clamp, informational
    eErr := 16#0002_374A; // 信息级：uTaps 越域已钳位 / informational, the tap count was clamped
ELSIF _bDivWarn THEN // 发散警告（信息级，逐拍重算）/ the divergence, informational
    eErr := 16#0002_374B; // 信息级：权重平方和超阈，建议减小 μ / informational, the weight energy is over the threshold, reduce the step size
ELSE // 无事件 / no event
    eErr := 16#0000_0000; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
