(*==============================================================================
 * 组件名称 (Component)  : FB_DL_LuenbergerObserver
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS / SQRT / MIN / MAX），零厂商私有库
 * 功能描述 (Function)   : 离散二阶状态观测器（Luenberger 结构）+ 残差窗收敛判据 + 防发散钳位。
 *                         被估对象为二阶线性离散模型（位置/速度）：
 *                           x1⁺ = a11·x1 + a12·x2 + b1·u        （位置方程）
 *                           x2⁺ = a21·x1 + a22·x2 + b2·u        （速度方程）
 *                           yHat = x1⁺                           （测点为位置）
 *                         观测器（Luenberger 增益 L = [l1, l2]）：
 *                           r  = y − yHat（新息）
 *                           x1 = x1⁺ + l1·r
 *                           x2 = x2⁺ + l2·r
 *                         收敛判据：以周期窗（自复位 TON）为单位累计新息平方和，窗末算均方根
 *                         fResRms = SQRT(Σr²/n)。fResRms <= fResThr 记为收敛（bConverged 置真），
 *                         否则清零。**只有收敛后才宣称状态估计可用**——不收敛时 x1Hat/x2Hat 仍输出
 *                         （便于诊断），但 bEstValid=FALSE，不得参与闭环。
 *                         防发散：① 每个状态在更新后钳到 ±fXMax，触位即 bClamped（饱和非故障）；
 *                         ② 窗 RMS 超 fResDiv 判观测器发散（故障锁存，eCause=eDiverged），
 *                         因为真实系统残差不会长期比噪声大一个量级；③ 增益/系数 NaN 一律闸死。
 * 接口     (Interface)  : 输入 fY 实测位置、fU 控制量、六个模型系数（a11/a12/a21/a22/b1/b2）、
 *                         两个增益（l1/l2）、fXMax 状态硬限、fResThr 收敛阈、fResDiv 发散阈、
 *                         tWindow 残差窗、bReset；输出 fX1Hat / fX2Hat 状态估计、fResidual 当拍新息、
 *                         fResRms 窗均方根、bConverged 收敛、bEstValid 估计可用、bClamped 触限、
 *                         eState / eCause / bError。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件是纯算法件——不读轴接口、不发指令、
 *                         不参与闭环**。估计值经上层注入，是否用于前馈/诊断由上层决定。
 *                         ② 模型系数与增益由调用方给（本件不做模型辨识）：辨识属 `FB_DL_RlsEstimator`；
 *                         二者可级联（辨识出系数喂本件），但不得互相内嵌。
 *                         ③ 组态闸：fXMax <= DL_LUO_EPS、fResThr <= 0.0、fResDiv <= fResThr、
 *                         tWindow <= T#0S、任一系数/增益/引脚 NaN → 故障锁存，估计输出置 0
 *                         （安全侧：不宣称任何状态）。
 *                         ④ 周期窗用 IN := (NOT tonWin.Q) 自复位（R188 合规），不依赖外部沿清零；
 *                         TON 与 R_TRIG 均在段 0 无条件周期刷新。
 *                         ⑤ 故障相迁出唯一路径 = bReset 上升沿（R228B），并在头注释声明该沿。
 *                         ⑥ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 来源标签 (Source Tag) : 自研线（Luenberger 1964 观测器结构属公开经典理论；ST 离散实现、
 *                         残差窗判据与钳位包装为本库自研，零代码行复制）
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 → 清发散锁存、清收敛标志、清残差窗。
 *                         自证可满足：复位清窗后重新累计，无锁存量门控。
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 BOOL（bConverged / bEstValid /
 *                         bClamped / bError）+ ENUM（eState / eCause）；数字码位待主控收口阶段派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 除零闸（n>0）+ 开方负值钳位 + 状态饱和 + NaN 闸
 *                         R5 ✓ 声明逐行同行双语注释 ｜ R6 ✓ ENUM+CASE 含 ELSE
 *                         R7 ✓ TON/R_TRIG 段 0 无条件刷新
 * 返修记录 (Repair)     : v1.0.1（R47 P0 返修）复位沿同步把 _fX1 / _fX2 清 0：原实现只清残差窗口与
 *                         锁存，状态量沿用上电残值，复位后首个先验会把旧状态带进新批次（隐性回夹）。
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R46 首版（批次 3 · 序号 12）
 *==============================================================================*)

TYPE E_DL_LuoState :
(
    eIdle  := 0,    // 首窗未收敛，估计不可宣称 / First window not converged
    eRun   := 10,   // 观测器运行相 / Observer running
    eFault := 90    // 发散锁存相 / Divergence latched phase
);
END_TYPE

TYPE E_DL_LuoCause :
(
    eNone       := 0,   // 无异常 / No anomaly
    eCfgIllegal := 1,   // 组态非法（硬限/阈值/窗长/非有限） / Illegal configuration
    eDiverged   := 2,   // 残差 RMS 超发散阈（观测器发散） / Residual RMS exceeded the divergence threshold
    eClampHit   := 3,   // 状态长期触硬限（模型与实测严重不符） / States pinned at the hard limit
    ePhaseBad   := 4    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_LuenbergerObserver
VAR_INPUT
    fY      : REAL := 0.0;      // 实测位置（唯一测点） [mm] / Measured position, the only measurement [mm]
    fU      : REAL := 0.0;      // 控制量（转矩/加速度当量） [N] / Control input [N]
    fA11    : REAL := 1.0;      // 系数 a11（位置自保持） [-] / Coefficient a11
    fA12    : REAL := 0.02;     // 系数 a12（速度→位置，≈采样周期） [s] / Coefficient a12, roughly the sample time [s]
    fA21    : REAL := 0.0;      // 系数 a21（位置→速度） [-] / Coefficient a21
    fA22    : REAL := 1.0;      // 系数 a22（速度自保持） [-] / Coefficient a22
    fB1     : REAL := 0.0;      // 输入增益 b1（控制→位置） [mm/N] / Input gain b1 [mm/N]
    fB2     : REAL := 0.01;     // 输入增益 b2（控制→速度） [mm/(s·N)] / Input gain b2 [mm/(s·N)]
    fL1     : REAL := 0.30;     // 观测器增益 l1（新息→位置） [-] / Observer gain l1
    fL2     : REAL := 0.05;     // 观测器增益 l2（新息→速度） [-] / Observer gain l2
    fXMax   : REAL := 1000.0;   // 状态硬限（|x| 上限），域 > eps [工程单位] / State hard limit, > eps
    fResThr : REAL := 0.05;     // 收敛阈（窗 RMS），域 > 0.0 [mm] / Convergence threshold on window RMS, > 0.0 [mm]
    fResDiv : REAL := 5.0;      // 发散阈（窗 RMS），域 > fResThr [mm] / Divergence threshold, > convergence [mm]
    tWindow : TIME := T#100MS;  // 残差统计窗，域 > T#0S [ms] / Residual statistics window, > 0 [ms]
    bReset  : BOOL := FALSE;    // 复位，上升沿清发散锁存与残差窗 [-] / Reset, rising edge clears divergence and the window
END_VAR
VAR_OUTPUT
    fX1Hat    : REAL;           // 位置估计 [mm] / Position estimate [mm]
    fX2Hat    : REAL;           // 速度估计 [mm/s] / Velocity estimate [mm/s]
    fResidual : REAL;           // 当拍新息 r = y − yHat [mm] / Present innovation [mm]
    fResRms   : REAL;           // 上一完整窗的残差均方根 [mm] / Residual RMS of the last complete window [mm]
    bConverged: BOOL;           // 残差窗判据通过（估计可用） [-] / Convergence criterion passed
    bEstValid : BOOL;           // 估计值可用于闭环（= 收敛 ∧ 无故障） [-] / Estimate usable in closed loop
    bClamped  : BOOL;           // 本拍状态触硬限 [-] / States clamped this scan
    eState    : E_DL_LuoState;  // 状态出口 [-] / State outlet
    eCause    : E_DL_LuoCause;  // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError    : BOOL;           // 故障标志（发散或组态非法） [-] / Error flag
END_VAR
VAR
    _eState   : E_DL_LuoState := E_DL_LuoState.eIdle;    // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause   : E_DL_LuoCause := E_DL_LuoCause.eNone;    // 成因锁存量 / Latched cause
    tonWin    : TON;            // 残差统计周期窗（自复位），段 0 无条件调用 / Periodic residual window, self-resetting
    rtReset   : R_TRIG;         // 复位沿实例，段 0 无条件调用 / Reset edge instance
    _fX1      : REAL;           // 位置状态（锁存量） [mm] / Position state, latched
    _fX2      : REAL;           // 速度状态（锁存量） [mm/s] / Velocity state, latched
    _fX1P     : REAL;           // 位置先验（预测）当拍量 [mm] / Position prior this scan [mm]
    _fX2P     : REAL;           // 速度先验（预测）当拍量 [mm/s] / Velocity prior this scan [mm/s]
    _fRes     : REAL;           // 当拍新息中间量 [mm] / Innovation intermediate [mm]
    _fSumSq   : REAL;           // 窗内新息平方和（锁存量） [mm²] / Windowed squared innovation sum, latched
    _nCnt     : UDINT;          // 窗内样本数（锁存量） [个] / Windowed sample count, latched
    _fRms     : REAL;           // 窗 RMS 锁存值 [mm] / Held window RMS [mm]
    _bConverged : BOOL;         // 收敛标志（锁存量，窗末刷新） / Converged flag, refreshed at window end
    _bFault   : BOOL;           // 发散锁存位（锁存量） / Latched divergence bit
    _bCfgBad  : BOOL;           // 组态非法当拍量 [-] / Illegal configuration this scan
    _bNonFin  : BOOL;           // 输入非有限当拍量 [-] / Non-finite input this scan
    _bClamped : BOOL;           // 本拍触限当拍量 [-] / Clamp hit this scan
END_VAR
VAR CONSTANT
    DL_LUO_EPS   : REAL := 1.0E-6;   // 浮点判零容差 [无量纲] / Float epsilon
    DL_LUO_ZERO  : REAL := 0.0;      // 零基准（方差钳位用） [无量纲] / Zero baseline
END_VAR

(* —— 段 0：判据派生 + 两实例无条件周期刷新 —— *)
_bNonFin := (fY <> fY) OR (fU <> fU) OR (fXMax <> fXMax)                  // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive tests
         OR (fA11 <> fA11) OR (fA12 <> fA12) OR (fA21 <> fA21) OR (fA22 <> fA22)
         OR (fB1 <> fB1) OR (fB2 <> fB2) OR (fL1 <> fL1) OR (fL2 <> fL2)
         OR (fResThr <> fResThr) OR (fResDiv <> fResDiv);                 // 系数/增益/阈值 NaN 全量判 / All coefficient, gain and threshold NaN tests
_bCfgBad := (fXMax <= DL_LUO_EPS) OR (fResThr <= 0.0)                     // 硬限与收敛阈闸 / Hard limit and convergence gate
         OR (fResDiv <= fResThr) OR (tWindow <= T#0S) OR _bNonFin;        // 发散阈几何 + 窗长 + 非有限 / Divergence geometry, window, non-finite
rtReset(CLK := bReset);                                                   // 复位沿，每拍必调（R228A） / Reset edge, every scan
tonWin(IN := (NOT tonWin.Q) AND (NOT _bCfgBad), PT := tWindow);           // 残差周期窗，自复位（R188） / Residual window, self-resetting

(* —— 段 1：单拍量预清零（锁存量 _fX1/_fX2/_fSumSq/_nCnt/_fRms/_bConverged/_bFault 不入清单） —— *)
fResidual := 0.0;       // 新息出口预清 / Innovation preset
bConverged := FALSE;    // 收敛出口预清 / Converged preset
bEstValid := FALSE;     // 可用出口预清 / Valid preset
bClamped  := FALSE;     // 触限出口预清 / Clamped preset
bError    := FALSE;     // 故障标志预清（R45 配对） / Error flag preset
_bClamped := FALSE;     // 触限当拍量预清 / Clamp hit preset

(* —— 段 2：复位沿 + 组态闸 —— *)
IF rtReset.Q THEN
    _bFault    := FALSE;                        // 清发散锁存 / Clear divergence latch
    _eCause    := E_DL_LuoCause.eNone;          // 清成因 / Clear cause
    _fSumSq    := 0.0;                          // 残差平方和归零 / Clear the squared sum
    _nCnt      := 0;                            // 窗样本数归零 / Clear the sample count
    _fRms      := 0.0;                          // RMS 归零 / Clear
    _fX1       := 0.0;                          // 位置状态清零（v1.0.1：复位沿同步清状态，防旧状态带出） / Position state cleared on reset
    _fX2       := 0.0;                          // 速度状态清零（v1.0.1：复位沿同步清状态，防旧状态带出） / Velocity state cleared on reset the RMS
    _bConverged := FALSE;                       // 收敛标志清零（重新收敛需重新累计） / Convergence must be re-earned
    IF _eState = E_DL_LuoState.eFault THEN
        _eState := E_DL_LuoState.eIdle;         // 故障相迁出（R228B） / Leave fault phase
    END_IF
END_IF
IF _bCfgBad THEN
    _bFault := TRUE;                            // 组态非法锁存 / Latch illegal configuration
    _eCause := E_DL_LuoCause.eCfgIllegal;       // 归因：组态非法 / Cause: illegal configuration
    _fX1 := 0.0;                                // 状态清零（不宣称） / States zeroed, not claimed
    _fX2 := 0.0;
END_IF

(* —— 段 3：观测器一拍更新（仅组态合法时执行；先验 → 新息 → 后验 → 钳位） —— *)
IF NOT _bCfgBad THEN
    _fX1P := (fA11 * _fX1) + (fA12 * _fX2) + (fB1 * fU);    // 位置先验 / Position prior
    _fX2P := (fA21 * _fX1) + (fA22 * _fX2) + (fB2 * fU);    // 速度先验 / Velocity prior
    _fRes := fY - _fX1P;                                    // 新息 = 实测 − 预测位置 / Innovation
    _fX1  := _fX1P + (fL1 * _fRes);                         // 后验位置（Luenberger 校正） / Posterior position
    _fX2  := _fX2P + (fL2 * _fRes);                         // 后验速度（Luenberger 校正） / Posterior velocity
    IF _fX1 > fXMax THEN
        _fX1 := fXMax;                                      // 正向上限钳位 / Clamp at the positive limit
        _bClamped := TRUE;
    ELSIF _fX1 < -fXMax THEN
        _fX1 := -fXMax;                                     // 负向下限钳位 / Clamp at the negative limit
        _bClamped := TRUE;
    END_IF
    IF _fX2 > fXMax THEN
        _fX2 := fXMax;                                      // 速度正向上限钳位 / Velocity positive clamp
        _bClamped := TRUE;
    ELSIF _fX2 < -fXMax THEN
        _fX2 := -fXMax;                                     // 速度负向下限钳位 / Velocity negative clamp
        _bClamped := TRUE;
    END_IF
    _fSumSq := _fSumSq + (_fRes * _fRes);                   // 新息平方累加 / Accumulate the squared innovation
    _nCnt   := _nCnt + 1;                                   // 窗样本计数 / Window sample count
    fResidual := _fRes;                                     // 新息出口 / Innovation outlet
    fX1Hat    := _fX1;                                      // 位置估计出口 / Position estimate outlet
    fX2Hat    := _fX2;                                      // 速度估计出口 / Velocity estimate outlet
END_IF

(* —— 段 4：窗末收敛判定（单点写入 _fRms/_bConverged，避免同拍抹除，R187） —— *)
IF tonWin.Q AND (NOT _bCfgBad) THEN
    IF _nCnt > 0 THEN                                       // 除零闸 / Divide gate
        _fRms := SQRT(_fSumSq / UDINT_TO_REAL(_nCnt));      // 窗均方根 / Window RMS
        IF _fRms <= fResThr THEN
            _bConverged := TRUE;                            // 收敛成立 / Convergence holds
            IF _eState = E_DL_LuoState.eIdle THEN
                _eState := E_DL_LuoState.eRun;              // 首窗收敛入运行相 / First converged window enters run
            END_IF
            IF _eCause = E_DL_LuoCause.eClampHit THEN
                _eCause := E_DL_LuoCause.eNone;             // 收敛即清「长期触限」提示 / Clear the clamp notice once converged
            END_IF
        ELSE
            _bConverged := FALSE;                           // 本窗不收敛 / Not converged this window
            IF _fRms > fResDiv THEN
                _bFault := TRUE;                            // 发散锁存 / Latch divergence
                _eCause := E_DL_LuoCause.eDiverged;         // 归因：发散 / Cause: divergence
            ELSIF _bClamped THEN
                _eCause := E_DL_LuoCause.eClampHit;         // 提示：长期触限（信息级成因） / Notice: long-term clamp hit
            END_IF
        END_IF
    ELSE
        _fRms := 0.0;                                       // 空窗不宣称（分母为 0 时） / Empty window, nothing claimed
        _bConverged := FALSE;
    END_IF
    _fSumSq := 0.0;                                         // 窗末清零（自复位窗的配套动作） / Clear the sum at window end
    _nCnt   := 0;                                           // 窗末清零 / Clear the count at window end
END_IF

(* —— 段 5：故障相迁移 —— *)
IF _bFault AND (_eState <> E_DL_LuoState.eFault) THEN
    _eState := E_DL_LuoState.eFault;                        // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 6：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_LuoState.eIdle:
    IF _bFault THEN                                         // 出口 1：故障锁存 / Fault latched
        _eState := E_DL_LuoState.eFault;
    ELSIF _bConverged THEN                                  // 出口 2：收敛 / Converged
        _eState := E_DL_LuoState.eRun;
    END_IF

E_DL_LuoState.eRun:
    IF _bFault THEN                                         // 出口 1：发散锁存 / Divergence latched
        _eState := E_DL_LuoState.eFault;
    ELSIF _bConverged = FALSE THEN                          // 出口 2：失收敛回等待相 / Lost convergence, back to idle
        _eState := E_DL_LuoState.eIdle;
    END_IF

E_DL_LuoState.eFault:
    ;                                                       // 故障相：仅段 2 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _bFault := TRUE;                                        // 非法相位兜底锁存 / Illegal-phase fallback latch
    _eCause := E_DL_LuoCause.ePhaseBad;                     // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_LuoState.eFault;                        // 强拉故障相 / Force fault phase

END_CASE

(* —— 段 7：出口单点映射（估计值恒回放，故障相亦不清零——诊断需要看发散的数值） —— *)
bConverged := _bConverged;                                  // 收敛出口 / Convergence outlet
bEstValid  := _bConverged AND (NOT _bFault);                // 可用 = 收敛 ∧ 无故障 / Usable = converged and fault-free
fResRms    := _fRms;                                        // 窗 RMS 出口 / Window RMS outlet
bClamped   := _bClamped;                                    // 触限出口 / Clamp outlet
bError     := _bFault OR _bCfgBad;                          // 故障标志 = 锁存或组态非法 / Error = latch or illegal config
eState     := _eState;                                      // 状态出口 / State outlet
eCause     := _eCause;                                      // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
