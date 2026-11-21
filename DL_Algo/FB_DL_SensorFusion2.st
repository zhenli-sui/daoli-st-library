(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SensorFusion2
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（ABS），零厂商私有库
 * 功能描述 (Function)   : 双传感器方差加权融合：对同一物理量的两路测量（如 RTD+红外温漂
 *                         互补型双测）按在线递推噪声方差倒数动态配权：
 *                           _fVarX := (1-fTauVar)×_fVarX + fTauVar×(fMeasX-_fMean)²
 *                           fWeightA = (1/_fVarA) / ((1/_fVarA)+(1/_fVarB))
 *                           fFused   = fWeightA×fMeasA + (1-fWeightA)×fMeasB
 *                         一致性判据 bAgree = |fMeasA-fMeasB| <= fDevMax；单源失效全权重
 *                         交给健康源（降级不拒算）；双源失效冻结上次 fFused 且 bValid=FALSE。
 * 接口     (Interface)  : 输入 fMeasA/fMeasB 双路测量、bFreshA/bFreshB 数据新鲜度、
 *                         fTauVar 方差递推平滑系数（域 0~1 无量纲）、fDevMax 一致性偏差闸
 *                         （工程单位）、bReset 复位；输出 fFused 融合值、fWeightA 权重
 *                         （0~1）、bAgree 一致性、bValid 有效标志、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做双源静态融合，不判传感器硬故障、
 *                         不切换通道、不接管信号健康诊断**；通道硬失效裁决归
 *                         `FB_DL_RedundantSwitch`（二选一切换），本件是"都信、按噪声配权"。
 *                         ② 方差下限钳 fVarMin（VAR CONSTANT）防除零：权重分母两项各含
 *                         1/_fVarX，钳底后分母恒正，无需额外除零判。
 *                         ③ 非有限值当拍剔除（R245）：该源当拍视同不新鲜；双源当拍均剔除
 *                         → 冻结 fFused、bValid=FALSE。
 *                         ④ 权重输出钳 [0,1]；fTauVar 组态域闸（<0 或 >1）与 fDevMax<0
 *                         → 锁存 bError，冻结输出，解除沿 = bReset 上升沿。
 *                         ⑤ 方差递推仅在双源同拍有效时进行（单源降级只直通，不污染方差）。
 *                         ⑥ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_KalmanFilter1D` 分工：单流递推滤波 ≠ 双源加权融合；
 *                         与 `FB_DL_RedundantSwitch` 分工：二选一切换 ≠ 加权融合（见①）。
 * 来源标签 (Source Tag) : 自研线（公开加权融合公式 clean-room，逆方差权重为公开统计定义）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 LREAL 组 + BOOL 组；
 *                         数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 方差下限防除零 + 非有限剔除 + 权重钳位 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（无 ENUM 状态机） ｜ R7 ✓ 一 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.1  R50 返修 R3：fTauVar=0 端点防护
 *                         （下限钳位）——fTauVar=0 时方差递推步长为零，方差
 *                         永冻结于初值 1.0、权重恒 0.5（自适应失效），现引入
 *                         DL_SF2_TAUMIN(1E-6) 下限钳位使递推保持最低活跃度；
 *                         行为变更同步更新验收向量（fTauVar=0 按 1E-6 生效）。
 *                         2026-11-20  v1.0.0  R48 首版（批次 2 · 序号 6）
 *                         验收向量：等方差双源 → 权重 0.5；A 方差骤增 → 权重移向 B；
 *                         A 不新鲜 → 权重 1.0 全信 B；双源失效 → 冻结 + bValid=FALSE。
 *==============================================================================*)

FUNCTION_BLOCK FB_DL_SensorFusion2
VAR_INPUT
    fMeasA  : LREAL := 0.0;    // A 源测量值 [工程单位] / Source A measurement
    fMeasB  : LREAL := 0.0;    // B 源测量值（与 A 同物理量） [工程单位] / Source B measurement, same quantity as A
    bFreshA : BOOL := TRUE;    // A 源数据新鲜度 [-] / Source A freshness
    bFreshB : BOOL := TRUE;    // B 源数据新鲜度 [-] / Source B freshness
    fTauVar : LREAL := 0.1;    // 方差递推平滑系数，域 [0,1] [无量纲] / Variance recursion smoothing factor
    fDevMax : LREAL := 1.0;    // 一致性偏差闸（|A-B| 超此值 bAgree=FALSE） [工程单位] / Agreement deviation gate
    bReset  : BOOL := FALSE;   // 复位，上升沿清组态故障锁存 [-] / Reset, rising edge clears config fault
END_VAR
VAR_OUTPUT
    fFused   : LREAL;          // 融合输出值 [工程单位] / Fused output value
    fWeightA : LREAL;          // A 源权重，域 [0,1] [-] / Source A weight in [0,1]
    bAgree   : BOOL;           // 双源一致性（单源降级恒 TRUE） [-] / Two-source agreement
    bValid   : BOOL;           // 融合有效标志（双源失效/组态故障为 FALSE） [-] / Fusion validity flag
    bError   : BOOL;           // 组态故障标志（锁存） [-] / Configuration fault flag, latched
END_VAR
VAR
    _fVarA    : LREAL := 1.0;  // A 源在线递推噪声方差（初值 1.0，量纲平方） / Source A recursive noise variance
    _fVarB    : LREAL := 1.0;  // B 源在线递推噪声方差（初值 1.0） / Source B recursive noise variance
    _fMean    : LREAL := 0.0;  // 上拍融合均值（方差递推参考点，冻结源） / Previous fused mean, recursion reference
    _fW       : LREAL := 0.5;  // 当拍权重中间量（冻结源，与出口同源） / Weight intermediate, frozen source
    _fTauUse  : LREAL;         // 生效递推系数（下限钳位后，v1.0.1 端点防护） [-] / Effective smoothing factor after floor clamp
    _fFused   : LREAL := 0.0;  // 融合值锁存镜像（冻结语义源） / Fused value latch mirror
    _bValid   : BOOL;          // 有效标志内部量 / Validity internal
    _bErrLatch: BOOL;          // 组态故障锁存位（解除沿 = bReset 上升沿） / Latched config fault, cleared by reset edge
    rtReset   : R_TRIG;        // 复位沿实例，段 0 无条件调用 / Reset edge instance
    _bUseA    : BOOL;          // A 源当拍可用（新鲜 ∧ 有限） / Source A usable this scan
    _bUseB    : BOOL;          // B 源当拍可用 / Source B usable this scan
    _fInvA    : LREAL;         // A 源逆方差中间量 / Inverse variance of A
    _fInvB    : LREAL;         // B 源逆方差中间量 / Inverse variance of B
    _fDevA    : LREAL;         // A 源对均值偏差 [工程单位] / Deviation of A from mean
    _fDevB    : LREAL;         // B 源对均值偏差 [工程单位] / Deviation of B from mean
END_VAR
VAR CONSTANT
    DL_SF2_VARMIN : LREAL := 1.0E-12;   // 方差下限钳（防除零） [工程单位²] / Variance floor against zero division
    DL_SF2_TAUMIN : LREAL := 1.0E-6;    // 递推系数下限钳（fTauVar=0 端点防护，v1.0.1） [-] / Smoothing factor floor, endpoint guard
    DL_SF2_EPS    : LREAL := 0.0;       // 非有限差值判零基准 [-] / Non-finite difference zero base
    DL_SF2_ONE    : LREAL := 1.0;       // 单位常量（权重钳上限） [-] / Unit constant, weight ceiling
END_VAR

(* —— 段 0：非有限判 + 组态闸 + 沿刷新 —— *)
_bUseA := bFreshA AND (fMeasA = fMeasA) AND ((fMeasA - fMeasA) = DL_SF2_EPS);   // A 源新鲜 ∧ 有限（NaN 自不等 / Inf 差非零，R245） / A fresh and finite
_bUseB := bFreshB AND (fMeasB = fMeasB) AND ((fMeasB - fMeasB) = DL_SF2_EPS);   // B 源新鲜 ∧ 有限 / B fresh and finite
IF (fTauVar < 0.0) OR (fTauVar > DL_SF2_ONE) OR (fDevMax < 0.0) THEN
    _bErrLatch := TRUE;                                    // 组态域闸：锁存（R188 解除沿 = bReset 上升沿） / Config domain gate: latch
END_IF
_fTauUse := fTauVar;                                       // 生效递推系数工作副本 / Effective factor working copy
IF _fTauUse < DL_SF2_TAUMIN THEN
    _fTauUse := DL_SF2_TAUMIN;                             // fTauVar=0 端点钳位：递推保持最低活跃度（v1.0.1） / Endpoint floor clamp
END_IF
rtReset(CLK := bReset);                                    // 复位沿，每拍必调 / Reset edge, every scan

(* —— 段 1：复位沿 —— *)
IF rtReset.Q THEN
    _bErrLatch := FALSE;                                   // 清组态故障锁存 / Clear config fault latch
END_IF

(* —— 段 2：融合主算（组态故障期冻结不重算） —— *)
bValid := FALSE;                                           // 有效标志当拍预清 / Validity preset
IF NOT _bErrLatch THEN
    IF _bUseA AND _bUseB THEN
        _fDevA := fMeasA - _fMean;                         // A 源对上拍均值偏差 / Deviation of A
        _fDevB := fMeasB - _fMean;                         // B 源对上拍均值偏差 / Deviation of B
        _fVarA := (DL_SF2_ONE - _fTauUse) * _fVarA + _fTauUse * _fDevA * _fDevA;   // A 方差递推（生效系数下限钳位后） / A variance recursion
        _fVarB := (DL_SF2_ONE - _fTauUse) * _fVarB + _fTauUse * _fDevB * _fDevB;   // B 方差递推 / B variance recursion
        IF _fVarA < DL_SF2_VARMIN THEN
            _fVarA := DL_SF2_VARMIN;                       // 方差下限钳（防除零） / Variance floor
        END_IF
        IF _fVarB < DL_SF2_VARMIN THEN
            _fVarB := DL_SF2_VARMIN;                       // 方差下限钳 / Variance floor
        END_IF
        _fInvA := DL_SF2_ONE / _fVarA;                     // A 逆方差（分母已钳底恒正） / Inverse variance of A
        _fInvB := DL_SF2_ONE / _fVarB;                     // B 逆方差 / Inverse variance of B
        _fW := _fInvA / (_fInvA + _fInvB);                 // 逆方差归一权重（分母两项恒正，无除零） / Normalized inverse-variance weight
        IF _fW < 0.0 THEN
            _fW := 0.0;                                    // 权重下钳 / Weight floor clamp
        END_IF
        IF _fW > DL_SF2_ONE THEN
            _fW := DL_SF2_ONE;                             // 权重上钳 / Weight ceiling clamp
        END_IF
        _fFused := _fW * fMeasA + (DL_SF2_ONE - _fW) * fMeasB;   // 加权融合 / Weighted fusion
        _fMean := _fFused;                                 // 更新递推参考点 / Update recursion reference
        bValid := TRUE;                                    // 双源融合有效 / Dual-source fusion valid
    ELSIF _bUseA THEN
        _fFused := fMeasA;                                 // 单源降级：全权重信 A（降级不拒算） / Degraded single source A
        _fMean := _fFused;                                 // 更新参考点 / Update reference
        _fW := DL_SF2_ONE;                                 // A 权重全一 / Full weight to A
        bValid := TRUE;                                    // 降级仍有效 / Degraded still valid
    ELSIF _bUseB THEN
        _fFused := fMeasB;                                 // 单源降级：全权重信 B / Degraded single source B
        _fMean := _fFused;                                 // 更新参考点 / Update reference
        _fW := 0.0;                                        // A 权重归零 / Zero weight to A
        bValid := TRUE;                                    // 降级仍有效 / Degraded still valid
    END_IF
    (* 双源同拍均不可用：无赋值分支 → _fFused/_fW 冻结上次值（规格②），bValid 保持 FALSE *)
END_IF

(* —— 段 3：出口单点映射（名实双出口同源，R191） —— *)
fFused   := _fFused;                                       // 融合值出口（失效期冻结） / Fused outlet, frozen on loss
fWeightA := _fW;                                           // 权重出口 / Weight outlet
bValid   := bValid AND (NOT _bErrLatch);                   // 有效标志（组态故障期强制无效） / Validity, forced invalid on fault
IF _bUseA AND _bUseB THEN
    bAgree := ABS(fMeasA - fMeasB) <= fDevMax;             // 双源一致性判据（浮点容差比较，禁 =） / Two-source agreement test
ELSE
    bAgree := TRUE;                                        // 单源降级无对可比：视为一致（诊断语义声明） / Single source: deemed consistent
END_IF
bError := _bErrLatch;                                      // 故障标志出口 / Error flag outlet

END_FUNCTION_BLOCK
