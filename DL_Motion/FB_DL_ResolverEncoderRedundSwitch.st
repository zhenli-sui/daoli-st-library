(*
    FB_DL_ResolverEncoderRedundSwitch —— 旋变 + 增量编码器双通道角反馈冗余判定与无扰切换
    ------------------------------------------------------------------
    组件名    : FB_DL_ResolverEncoderRedundSwitch
    分类      : DL_Motion / Feedback Redundancy（反馈冗余切换）
    一句话功能: 双通道角反馈偏差超限时判定哪一路可信并无扰切到单通道运行，
                切换过程中输出角度受变率限制，绝不产生位置跳变。
    复杂度    : C4
    版本      : v1.0.0
    开源溯源  : 无（clean-room 自研，未借鉴任何开源实现）
    平台      : 纯 IEC 61131-3（TON / R_TRIG / ABS / REAL_TO_INT / INT_TO_REAL 标准转换），
                目标编译器 RuSTy 1.0.8，兼容 CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop /
                Machine Expert；无 PROPERTY、无 VLA、无 FOR..DOWNTO、无 AS 类方言
    ------------------------------------------------------------------
    功能说明  : ① 角差按 360° 环形折算：先各自折到 [0,360)，再
                   d := ABS(fAngleA − fAngleB)；IF d > 180 THEN d := 360 − d（结果域 [0,180]）；
                ② 双通道都有效且角差在容差内 → 融合输出（两路短弧中点），并每拍刷新
                   「融合参照角」_fRefDeg，供后续判定「哪一路可信」时作参照；
                ③ 角差超容差且持续 tFaultPersistMs（TON 无条件刷新）→ 判 SUSPECT；
                   任一路 bXValid = FALSE（或该路角度非有限）→ 直接判该路失效并切单通道；
                ④ 判定「哪一路可信」：以「最近一次双通道合格时的融合参照角」为准，
                   取与参照偏离较小者（相等时稳定优先取旋变 A）；无参照 → LOST，不猜；
                ⑤ 切换时 fAngleOut 按 fMaxSlewDegPerSec 限变率跟随目标角：环形带符号差值
                   先钳到 ±每拍步长再累加，故任何切换都不产生跳变；
                ⑥ 输出通道码 nActiveChannel：0 = 融合、1 = 旋变 A、2 = 编码器 B、-1 = 无。
    量纲链    : fAngleADeg [°] − fAngleBDeg [°] → 角差 [°]（经 360° 折算，域 [0,180]）；
                _fDevRatio = _fDevDeg [°] ÷ _fTolGuard [°] → 无因次 [-]（故与 1.0 直比判超限）；
                fMaxSlewDegPerSec [°/s] × DL_RE_SAMPLE_S [s] → 每拍最大角增量 [°]；
                _fDelta [°] 钳到 ±步长 [°] 后加到 _fOut [°] 再折回 [0,360) → fAngleOut [°]。
                全程无「角度与时间相加」「比例与角度相加」，量纲链逐段闭合。
    代理假设  : （R95 三句声明）① 代理值 = 常量 DL_RE_SAMPLE_S = 0.004 s，代表本 FB 所在
                任务的标称扫描周期；② 覆盖范围 = 2 ms ~ 10 ms 的周期任务（最坏 ±60% 误差只
                影响切换变率的平滑度，不改变安全判据的判定结果）；③ 覆盖不到的区间
                （< 1 ms 高速任务、事件任务、扫描周期抖动超 10 ms）由驱动层位置环限幅与伺服
                自身加速度限制负责，本件限变率只作二级防线。
    交付门槛  : 本件使用 REAL_TO_INT / INT_TO_REAL 标准转换做角度折圈，须在 CODESYS /
                TwinCAT / InoProShop 三平台各编译验证一次（R64）。
    状态机    : eInit(0) --双路有效且角差在容差内--> eDualOk(10)
                eInit --双路有效但角差超限--> eSuspect(20)；--仅一路有效--> eSingleA(30)/eSingleB(40)
                eDualOk --角差超容差持续 tFaultPersistMs 到（tonDev.Q）--> eSuspect
                eDualOk/eSuspect --A 失效--> eSingleB；--B 失效--> eSingleA
                eSuspect --有参照且可判--> eSingleA/eSingleB；--无参照或双路皆失效--> eLost(90)
                eSingleA/eSingleB --对侧恢复且一致计时到（tonAgree.Q）--> eDualOk
                eSingleA --A 失效--> eLost；eSingleB --B 失效--> eLost
                eLost --双路恢复且一致计时到（tonAgree.Q）--> eDualOk；
                eLost --单路恢复且确认计时到（tonSingle.Q）--> eSingleA/eSingleB（先进单通道，不直接回双通道）
                解除路径自证：tonSingle 的 IN 为「恰好一路可用」，故 eLost 的单路恢复边恒可达；
                若两路长期不一致且从未建立参照，eLost 按设计保持（不猜），bReset 重建参照后再裁决
    失能语义  : bEnable = FALSE 时 eState := eInit、nActiveChannel := -1、bLost := FALSE，
                fAngleOut 冻结保持末值（不跳变、不清零）；恢复使能后按变率追随新目标角。
                取「冻结保持」而非「降级清零」：角度是位置事实量，清零等于伪造位置（R191）。
    复位作用域: bReset 上升沿①清 _fRefDeg 与 _bRefValid（参照作废，须重建双通道合格）；
                ②清 _bCfgBad 与各成因位；③迁相回 eInit；④不清 _fOut（角度不得因复位跳变）。
    防御口径  : NaN 用自反 f<>f；±Inf 用 (f−f)<>(f−f)；另设幅值域闸 ABS(f) > 1.0E30。
                折圈除法的除子为常量 360.0（无零风险），但实数转整数前先做幅值域钳制，防
                REAL_TO_INT 溢出翻转（R151）；容差比值除法先以 DL_RE_TOL_FLOOR 两级兜底除子。
    规格补充  : 派单引脚表未含变率限制引脚，但设计要求「输出必须限变率」，故补充输入
                fMaxSlewDegPerSec（默认 3600 °/s，即 10 圈每秒）。派单写作 iActiveChannel（INT）；
                本库命名规范 1.2 规定有符号整数前缀为 n、i 专用于接口引用，故落为
                nActiveChannel，语义与码值一字不减。另按 R190 归因唯一补充 bCfgErr / bDataErr
                两个诊断位，使「组态非法」与「通道数据非有限」两条成因各自可观测。
    码位说明  : 本件按零码位范式交付，不分配 16# 事件码；失效成因（A 失效 / B 失效 /
                双路同时失效 / 无参照 / 当前通道失效 / 组态非法）各有独立内部成员，
                经 eState 与 bLost 观测，不共用同一枚举成员归因（R190）。
    修订记录  : 2026-11-24 v1.0.0 首次入库（R87 批 · #2）
*)
TYPE E_DL_ResEncState :
(
    eInit    := 0,    // 初始化或未投运：输出冻结，不判角差 | init or disabled, output frozen, no judging
    eDualOk  := 10,   // 双通道合格：融合输出，刷新融合参照角 | dual channels healthy, fused output, reference refreshed
    eSuspect := 20,   // 疑似：角差持续超容差，正在判定可信通道 | suspect, deviation persisted, arbitrating the trusted channel
    eSingleA := 30,   // 单通道 A：仅旋变通道参与输出 | single channel A, resolver only
    eSingleB := 40,   // 单通道 B：仅编码器通道参与输出 | single channel B, encoder only
    eLost    := 90    // 失效：无可信通道或无参照可判，输出冻结 | lost, no trusted channel or no reference
);
END_TYPE

FUNCTION_BLOCK FB_DL_ResolverEncoderRedundSwitch
VAR_INPUT
    bEnable            : BOOL;                    // 使能电平，TRUE = 允许切换判定 | enable level, TRUE = arbitration active
    bReset             : BOOL;                    // 复位请求，上升沿生效 | reset request, rising-edge active
    fAngleADeg         : REAL;                    // 旋变通道角度 [°]，任意圈数，内部折到 0..360 | resolver angle [deg]
    fAngleBDeg         : REAL;                    // 增量编码器角度 [°]，任意圈数，内部折到 0..360 | encoder angle [deg]
    fTolDeg            : REAL := 0.5;             // 双通道允许角差 [°]，须为正 | allowed channel deviation [deg]
    tFaultPersistMs    : TIME := T#100MS;         // 超限与恢复一致的持续确认时长 [ms] | persistence time [ms]
    bAValid            : BOOL;                    // 旋变通道有效位，驱动侧给出 | resolver channel validity from the drive
    bBValid            : BOOL;                    // 编码器通道有效位，驱动侧给出 | encoder channel validity from the drive
    fMaxSlewDegPerSec  : REAL := 3600.0;          // 输出角度最大变率 [°/s]，须为正 | max output slew rate [deg/s]
END_VAR
VAR_OUTPUT
    eState             : E_DL_ResEncState;        // 主状态，供 HMI 与联锁使用 | main state for HMI and interlocks
    fAngleOut          : REAL;                    // 参与位置环的输出角度 [°]，域 [0,360) 且限变率 | output angle [deg]
    fDeviationDeg      : REAL;                    // 本拍环形角差 [°]，域 [0,180] | circular deviation this scan [deg]
    nActiveChannel     : INT;                     // 通道码：0 融合 / 1 旋变 A / 2 编码器 B / -1 无 | channel code
    bSwitchEvent       : BOOL;                    // 通道切换事件位，单拍 | channel switch event, single scan
    bLost              : BOOL;                    // 失效汇总位，eLost 相为 TRUE | lost aggregate, TRUE in the eLost phase
    bCfgErr            : BOOL;                    // 组态非法诊断位（归因唯一，R190）| bad-configuration flag, unique attribution
    bDataErr           : BOOL;                    // 数据非有限诊断位（归因唯一，R190）| non-finite data flag, unique attribution
END_VAR
VAR
    rtReset            : R_TRIG;                  // 复位上升沿实例，每拍无条件刷新 | reset rising-edge instance
    tonDev             : TON;                     // 角差超限持续确认计时，每拍无条件刷新 | deviation persistence timer
    tonAgree           : TON;                     // 双通道一致确认计时，每拍无条件刷新 | agreement persistence timer
    tonSingle          : TON;                     // 单通道恢复确认计时，每拍无条件刷新 | single-channel recovery timer
    _eState            : E_DL_ResEncState := E_DL_ResEncState.eInit; // 状态机内部当前态 | internal current state
    _bInit             : BOOL := TRUE;            // 首扫初始化标志，含参照与输出保持槽状态 | first-scan init flag
    _bResetLatch       : BOOL := FALSE;           // 复位沿锁存量，本拍末清除 | reset-edge latch, cleared at scan end
    _bCfgBad           : BOOL := FALSE;           // 组态非法标志 | bad configuration flag
    _bAOk              : BOOL := FALSE;           // 旋变通道可用（有效位且角度有限）| resolver channel usable
    _bBOk              : BOOL := FALSE;           // 编码器通道可用（有效位且角度有限）| encoder channel usable
    _bLostBoth         : BOOL := FALSE;           // 双路同时失效成因位（归因唯一）| both channels lost
    _bNoRef            : BOOL := FALSE;           // 无融合参照成因位（归因唯一）| no reference available
    _bChLost           : BOOL := FALSE;           // 当前单通道失效成因位（归因唯一）| the active single channel was lost
    _fOut              : REAL := 0.0;             // 输出角度保持槽 [°]，域 [0,360) | output angle holder [deg]
    _fRefDeg           : REAL := 0.0;             // 融合参照角 [°]，仅在双通道合格时刷新 | fused reference angle [deg]
    _bRefValid         : BOOL := FALSE;           // 融合参照角可用标志 | fused reference valid flag
    _fDevDeg           : REAL := 0.0;             // 本拍环形角差 [°] | circular deviation this scan [deg]
    _fDevRatio         : REAL := 0.0;             // 角差与容差之比 [-]，判超限用 | deviation to tolerance ratio
    _fTolGuard         : REAL := 0.0;             // 带下限兜底的容差 [°]，作除法除子 | tolerance with floor, used as divisor
    _fSlewStep         : REAL := 0.0;             // 每拍最大角增量 [°] | max angle increment per scan [deg]
    _fDelta            : REAL := 0.0;             // 本拍待施加带符号角增量 [°]（已钳位）| clamped angle increment [deg]
    _fTarget           : REAL := 0.0;             // 本拍目标角 [°] | target angle this scan [deg]
    _fFuse             : REAL := 0.0;             // 本拍融合角 [°] | fused angle this scan [deg]
    _fDevA             : REAL := 0.0;             // A 相对参照的偏离 [°] | A deviation from the reference [deg]
    _fDevB             : REAL := 0.0;             // B 相对参照的偏离 [°] | B deviation from the reference [deg]
    _nCh               : INT := -1;               // 本拍通道码 | channel code this scan
    _nChPrev           : INT := -1;               // 上一拍通道码，供切换事件差分 | previous channel code for the switch event
    nFoldIdx           : INT := 0;                // 折圈方法内残余修正循环下标 | residue loop index inside the folding method
END_VAR
VAR CONSTANT
    DL_RE_EPS          : REAL := 1.0E-6;          // 浮点判零容差 [°] | float zero tolerance [deg]
    DL_RE_TOL_FLOOR    : REAL := 1.0E-4;          // 容差参数下限兜底 [°] | tolerance floor [deg]
    DL_RE_MAG_MAX      : REAL := 1.0E30;          // 有限幅值域闸上限（角度与变率）[°] | magnitude domain bound [deg]
    DL_RE_FOLD_MAX     : REAL := 1.0E6;           // 折圈前的角度幅值域上限 [°]，实数转整数前钳制 | fold domain bound [deg]
    DL_RE_SAMPLE_S     : REAL := 0.004;           // 代理扫描周期 [s]，见头注释代理假设三句 | proxy sample period [s]
    DL_RE_DEG_FULL     : REAL := 360.0;           // 整圈角度 [°] | full turn [deg]
    DL_RE_DEG_HALF     : REAL := 180.0;           // 半圈角度 [°] | half turn [deg]
    DL_RE_FUSE_W       : REAL := 0.5;             // 融合权重，两路等权且权值和为 1 [-] | fusion weight, sums to one
    DL_RE_CH_FUSE      : INT := 0;                // 通道码：融合 | channel code, fused
    DL_RE_CH_A         : INT := 1;                // 通道码：旋变 A | channel code, resolver A
    DL_RE_CH_B         : INT := 2;                // 通道码：编码器 B | channel code, encoder B
    DL_RE_CH_NONE      : INT := -1;               // 通道码：无 | channel code, none
    DL_RE_FOLD_ITER    : INT := 8;                // 折圈残余修正最大迭代次数（防死循环计数器）| fold iteration guard
END_VAR

METHOD FoldAngleDeg : REAL
(*
    角度折圈：把任意圈数角度折到 [0,360)。先按幅值域钳制再转整数，防 REAL_TO_INT 溢出翻转。
    Angle folding into [0,360): the magnitude is bounded before the real-to-integer conversion.
*)
VAR_INPUT
    fIn : REAL;                                   // 待折圈角度 [°] | angle to fold [deg]
END_VAR
VAR
    nTurn : INT;                                  // 整圈数，截断取整后按符号修正 [-] | whole turns after truncation
END_VAR
IF (fIn <> fIn) OR ((fIn - fIn) <> (fIn - fIn)) THEN
    FoldAngleDeg := 0.0;                          // NaN 或 ±Inf：返回哨兵零点，由调用方闸门拦截 | non-finite input returns the sentinel zero
    RETURN;
END_IF
IF (fIn > DL_RE_FOLD_MAX) OR (fIn < (0.0 - DL_RE_FOLD_MAX)) THEN
    FoldAngleDeg := 0.0;                          // 超折圈域：返回哨兵零点不猜，域外由上游闸门负责 | out of fold domain, return the sentinel
    RETURN;
END_IF
nTurn := REAL_TO_INT(fIn / DL_RE_DEG_FULL);       // 圈数 [-] = [°] ÷ 常量 360.0（除子为常量，无除零风险）| turns, constant divisor
FoldAngleDeg := fIn - INT_TO_REAL(nTurn) * DL_RE_DEG_FULL; // 折圈结果 [°] = [°] − [-] × [°] | folded angle [deg]
FOR nFoldIdx := 1 TO DL_RE_FOLD_ITER DO
    IF FoldAngleDeg < 0.0 THEN
        FoldAngleDeg := FoldAngleDeg + DL_RE_DEG_FULL; // 负角补整圈 [°] | add one turn for negative angles
    END_IF
END_FOR
IF FoldAngleDeg >= DL_RE_DEG_FULL THEN
    FoldAngleDeg := 0.0;                          // 折圈后仍越上界（数值极值退化）：返回哨兵零点 | degenerate result returns the sentinel
END_IF
END_METHOD

METHOD FoldDeviationDeg : REAL
(*
    环形角差幅值：d := ABS(A − B)；IF d > 180 THEN d := 360 − d，结果域 [0,180]（派单指定口径）。
    Circular deviation magnitude, exactly the formula requested by the dispatch.
*)
VAR_INPUT
    fAngleA : REAL;                               // A 通道角度 [°] | channel A angle [deg]
    fAngleB : REAL;                               // B 通道角度 [°] | channel B angle [deg]
END_VAR
VAR
    fD : REAL;                                    // 角差中间量 [°] | deviation intermediate [deg]
END_VAR
fD := ABS(FoldAngleDeg(fAngleA) - FoldAngleDeg(fAngleB)); // 折圈后作差取绝对值 [°] | absolute difference of folded angles
IF fD > DL_RE_DEG_HALF THEN
    fD := DL_RE_DEG_FULL - fD;                    // 折到短弧侧 [°]，与派单口径一致 | fold onto the short arc [deg]
END_IF
FoldDeviationDeg := fD;
END_METHOD

METHOD FoldSignedDiff : REAL
(*
    环形带符号差：返回 A − B 折到 (-180, 180]，用于融合与限变率增量计算。
    Signed circular difference folded into (-180, 180], used by fusion and by the slew limiter.
*)
VAR_INPUT
    fAngleA : REAL;                               // 被减角度 [°] | minuend angle [deg]
    fAngleB : REAL;                               // 减数角度 [°] | subtrahend angle [deg]
END_VAR
VAR
    fD : REAL;                                    // 带符号角差中间量 [°] | signed difference intermediate [deg]
END_VAR
fD := FoldAngleDeg(fAngleA) - FoldAngleDeg(fAngleB); // 折圈后作差 [°] | difference of folded angles [deg]
IF fD > DL_RE_DEG_HALF THEN
    fD := fD - DL_RE_DEG_FULL;                    // 折到负侧 [°] | fold into the negative side [deg]
END_IF
IF fD <= (0.0 - DL_RE_DEG_HALF) THEN
    fD := fD + DL_RE_DEG_FULL;                    // 折到正侧 [°] | fold into the positive side [deg]
END_IF
FoldSignedDiff := fD;
END_METHOD

// 段 1｜输出安全侧预置与首扫初始化（含参照与保持槽状态，故必须有 _bInit，R310）
// segment 1, safe-value presets and first-scan initialisation; the reference holder requires _bInit
nActiveChannel := DL_RE_CH_NONE;                   // 预置通道码「无」| preset channel code to none
bLost := FALSE;                                    // 预置未失效 | preset not lost
bSwitchEvent := FALSE;                             // 预置无切换事件 | preset no switch event
_fDevDeg := 0.0;                                   // 预置角差 0 [°] | preset zero deviation [deg]
_fDevRatio := 0.0;                                 // 预置角差比 0 [-] | preset zero ratio
_bCfgBad := FALSE;                                 // 预置组态合法 | preset legal configuration
_bLostBoth := FALSE;                               // 预置双路未同时失效 | preset both channels not lost
_bNoRef := FALSE;                                  // 预置参照缺失未置位 | preset reference-missing flag clear
_bChLost := FALSE;                                 // 预置当前通道未失效 | preset active-channel-lost flag clear
_nCh := DL_RE_CH_NONE;                             // 预置本拍通道码「无」| preset the channel code to none
IF _bInit THEN
    _bInit := FALSE;                               // 首扫只执行一次 | runs once on the first scan
    _eState := E_DL_ResEncState.eInit;             // 首扫状态回初相 | initialise the state
    _bRefValid := FALSE;                           // 参照角作废，须重建 | invalidate the reference
    IF (fAngleADeg <> fAngleADeg) OR ((fAngleADeg - fAngleADeg) <> (fAngleADeg - fAngleADeg)) THEN
        _fOut := 0.0;                              // 首扫角度非有限：保持槽取哨兵零点，等闸门置失效 | non-finite first angle
    ELSE
        _fOut := FoldAngleDeg(fAngleADeg);         // 首扫以旋变角为输出起点 [°]，避免首拍从 0 跳变 | start from the resolver angle
    END_IF
    _nChPrev := DL_RE_CH_NONE;                     // 首扫通道快照为「无」| first-scan channel snapshot
END_IF

// 段 2｜通道可用性判定：有效位 + NaN 自反 + Inf 自减 + 幅值域，逐个浮点入参枚举（R4 / R151 / R272）
// segment 2, channel usability: validity bit plus NaN self-reflexive, Inf self-subtraction and the magnitude bound
_bAOk := bAValid;
IF (fAngleADeg <> fAngleADeg) OR ((fAngleADeg - fAngleADeg) <> (fAngleADeg - fAngleADeg)) THEN
    _bAOk := FALSE;                                // 旋变角 NaN 或 ±Inf：判该路失效 | NaN or infinity, the channel is unusable
END_IF
IF ABS(fAngleADeg) > DL_RE_MAG_MAX THEN
    _bAOk := FALSE;                                // 旋变角超幅值域：判该路失效 | beyond the magnitude domain, unusable
END_IF
_bBOk := bBValid;
IF (fAngleBDeg <> fAngleBDeg) OR ((fAngleBDeg - fAngleBDeg) <> (fAngleBDeg - fAngleBDeg)) THEN
    _bBOk := FALSE;                                // 编码器角 NaN 或 ±Inf：判该路失效 | NaN or infinity, the channel is unusable
END_IF
IF ABS(fAngleBDeg) > DL_RE_MAG_MAX THEN
    _bBOk := FALSE;                                // 编码器角超幅值域：判该路失效 | beyond the magnitude domain, unusable
END_IF

// 段 3｜容差两级兜底与组态闸（容差作除子，必须先兜底再除；变率须为正且有限）
// segment 3, two-stage tolerance fallback and configuration gate; the tolerance is a divisor, floor it first
_fTolGuard := fTolDeg;                             // 取配置容差 [°] | take the configured tolerance [deg]
IF (fTolDeg <> fTolDeg) OR ((fTolDeg - fTolDeg) <> (fTolDeg - fTolDeg)) THEN
    _fTolGuard := DL_RE_TOL_FLOOR;                 // 容差非有限：一级回默认下限 [°] | non-finite tolerance falls back to the floor
END_IF
IF _fTolGuard < DL_RE_TOL_FLOOR THEN
    _fTolGuard := DL_RE_TOL_FLOOR;                 // 容差过小或为负：二级按有效域钳定 [°] | too small or negative, clamp to the floor
END_IF
IF (fMaxSlewDegPerSec <> fMaxSlewDegPerSec) OR ((fMaxSlewDegPerSec - fMaxSlewDegPerSec) <> (fMaxSlewDegPerSec - fMaxSlewDegPerSec)) THEN
    _bCfgBad := TRUE;                              // 变率非有限：组态非法 | non-finite slew rate, illegal configuration
END_IF
IF fMaxSlewDegPerSec <= DL_RE_EPS THEN
    _bCfgBad := TRUE;                              // 变率非正：组态非法（无变率限制即失去无扰切换保障）| non-positive slew rate
END_IF
IF ABS(fMaxSlewDegPerSec) > DL_RE_MAG_MAX THEN
    _bCfgBad := TRUE;                              // 变率超幅值域：组态非法 | slew rate beyond the magnitude domain
END_IF
IF tFaultPersistMs < T#0S THEN
    _bCfgBad := TRUE;                              // 持续确认时长为负：组态非法 | negative persistence time, illegal configuration
END_IF

// 段 4｜本拍角差与角差比（双路都可用才计算，否则记 0 且不参与判据）
// segment 4, deviation and deviation ratio this scan; computed only when both channels are usable
IF _bAOk AND _bBOk THEN
    _fDevDeg := FoldDeviationDeg(fAngleADeg, fAngleBDeg); // 环形角差 [°] | circular deviation [deg]
    _fDevRatio := _fDevDeg / _fTolGuard;           // 角差比 [-] = [°] ÷ [°]，_fTolGuard 已两级兜底非零 | guarded division
ELSE
    _fDevDeg := 0.0;                               // 单路或双路失效：角差无意义记 0 [°] | deviation meaningless here
    _fDevRatio := 0.0;                             // 单路或双路失效：角差比记 0 [-] | ratio meaningless here
END_IF

// 段 5｜定时器与沿实例无条件周期刷新（R7：严禁放入 IF / CASE 分支内部），入参为本拍已算量
// segment 5, timers and edge instances refreshed unconditionally, fed with values already computed this scan
rtReset(CLK := bReset);
tonDev(IN := bEnable AND _bAOk AND _bBOk AND (_fDevRatio > 1.0), PT := tFaultPersistMs);
tonAgree(IN := bEnable AND _bAOk AND _bBOk AND (_fDevRatio <= 1.0), PT := tFaultPersistMs);
tonSingle(IN := bEnable AND (_bAOk OR _bBOk) AND (NOT (_bAOk AND _bBOk)), PT := tFaultPersistMs);
IF rtReset.Q THEN
    _bResetLatch := TRUE;                          // 复位沿存锁存量，段 6 统一消费 | store the reset edge, consumed in segment 6
END_IF

// 段 6｜复位沿处理（先复位后判据，保证本拍新事件不被抹除，R275）
// segment 6, reset edge handling; reset runs before the criteria so same-scan events survive
IF _bResetLatch THEN
    _bRefValid := FALSE;                           // 参照作废，须重新建立双通道合格 | invalidate the reference
    _fRefDeg := 0.0;                               // 参照角清零 [°] | clear the reference angle [deg]
    _bCfgBad := FALSE;                             // 清组态非法标志（下一拍按新参数重判）| clear the configuration flag
    _eState := E_DL_ResEncState.eInit;             // 迁回初相 | return to the init phase
    _nCh := DL_RE_CH_NONE;                         // 复位拍通道码置无 | channel code set to none on the reset scan
END_IF

// 段 7｜组态非法：无变率限制即无法保证无扰切换，组态闸优先于一切判定
// segment 7, illegal configuration: without a slew limit the bumpless switch cannot be guaranteed
IF _bCfgBad THEN
    _eState := E_DL_ResEncState.eLost;
END_IF

// 段 8｜主状态机：ENUM + CASE + ELSE 兜底（R6）
// segment 8, main state machine with ENUM + CASE + ELSE fallback
CASE _eState OF
E_DL_ResEncState.eInit:
    _fTarget := _fOut;                             // 初相不追随目标，输出冻结 [°] | the init phase does not chase a target
    // 拍 N 进入：首扫、复位沿或使能撤除；本拍行为：只做有效性分类，不改输出角；
    // 拍 N+1 转出：双路有效且角差在容差内 → eDualOk；双路有效但超容差 → eSuspect；
    //              仅一路有效 → eSingleA / eSingleB；两路皆失效 → eLost
    // entered on the first scan, the reset edge or on disable; only classifies validity and never moves the output;
    // exits to eDualOk, eSuspect, eSingleA, eSingleB or eLost according to the validation result
    IF bEnable THEN
        IF _bAOk AND _bBOk THEN
            IF _fDevRatio <= 1.0 THEN
                _eState := E_DL_ResEncState.eDualOk;
            ELSE
                _eState := E_DL_ResEncState.eSuspect;
            END_IF
        ELSIF _bAOk THEN
            _eState := E_DL_ResEncState.eSingleA;
        ELSIF _bBOk THEN
            _eState := E_DL_ResEncState.eSingleB;
        ELSE
            _bLostBoth := TRUE;                    // 双路同时失效（独立成因）| both channels lost, unique attribution
            _eState := E_DL_ResEncState.eLost;
        END_IF
    END_IF

E_DL_ResEncState.eDualOk:
    // 融合：以 A 为基准加半幅带符号差，权重和为 1，故结果恒落在两路短弧中点
    // fusion: start from A and add half of the signed difference, giving the short-arc midpoint
    _fFuse := FoldAngleDeg(fAngleADeg + FoldSignedDiff(fAngleBDeg, fAngleADeg) * DL_RE_FUSE_W); // 融合角 [°] | fused angle [deg]
    _fTarget := _fFuse;                            // 双通道相目标为融合角 [°] | target is the fused angle
    _nCh := DL_RE_CH_FUSE;                         // 通道码：融合 | channel code fused
    _fRefDeg := _fFuse;                            // 刷新融合参照角 [°]，供后续判可信通道 | refresh the fused reference [deg]
    _bRefValid := TRUE;                            // 参照角已建立 | reference established
    IF NOT bEnable THEN
        _eState := E_DL_ResEncState.eInit;          // 失能回初相（输出冻结）| disable returns to init
    ELSIF (NOT _bAOk) AND (NOT _bBOk) THEN
        _bLostBoth := TRUE;                        // 双路同时失效 | both channels lost
        _eState := E_DL_ResEncState.eLost;
    ELSIF NOT _bAOk THEN
        _eState := E_DL_ResEncState.eSingleB;       // 旋变失效 → 切编码器 | resolver lost, switch to the encoder
    ELSIF NOT _bBOk THEN
        _eState := E_DL_ResEncState.eSingleA;       // 编码器失效 → 切旋变 | encoder lost, switch to the resolver
    ELSIF tonDev.Q THEN
        _eState := E_DL_ResEncState.eSuspect;       // 角差超容差持续确认到 → 进疑似相 | persisted deviation, enter suspect
    END_IF

E_DL_ResEncState.eSuspect:
    _fTarget := _fOut;                             // 疑似相不追随任何通道，输出冻结等裁决 [°] | no channel is chased here
    _nCh := DL_RE_CH_NONE;                         // 疑似相无有效通道码 | no valid channel code in suspect
    IF NOT bEnable THEN
        _eState := E_DL_ResEncState.eInit;          // 失能回初相 | disable returns to init
    ELSIF _bAOk AND _bBOk THEN
        IF _fDevRatio <= 1.0 THEN
            _eState := E_DL_ResEncState.eDualOk;   // 角差已回到容差内：撤销疑似，无需切换 | deviation back inside, cancel the suspect
        ELSIF _bRefValid THEN
            _fDevA := FoldDeviationDeg(fAngleADeg, _fRefDeg); // A 相对参照偏离 [°] | A deviation from the reference [deg]
            _fDevB := FoldDeviationDeg(fAngleBDeg, _fRefDeg); // B 相对参照偏离 [°] | B deviation from the reference [deg]
            IF (_fDevA < _fDevB) OR (_fDevA = _fDevB) THEN
                _eState := E_DL_ResEncState.eSingleA; // 取偏离小者；相等时稳定优先保留旋变 A | closer channel wins, ties keep the resolver
            ELSE
                _eState := E_DL_ResEncState.eSingleB;
            END_IF
        ELSE
            _bNoRef := TRUE;                       // 无参照可判：不猜（独立成因）| no reference, refuse to guess
            _eState := E_DL_ResEncState.eLost;
        END_IF
    ELSIF _bAOk THEN
        _eState := E_DL_ResEncState.eSingleA;       // 仅旋变可用 | only the resolver is usable
    ELSIF _bBOk THEN
        _eState := E_DL_ResEncState.eSingleB;       // 仅编码器可用 | only the encoder is usable
    ELSE
        _bLostBoth := TRUE;                        // 双路同时失效 | both channels lost
        _eState := E_DL_ResEncState.eLost;
    END_IF

E_DL_ResEncState.eSingleA:
    _fTarget := FoldAngleDeg(fAngleADeg);          // 单通道 A：目标为旋变角 [°] | single A, target is the resolver angle
    _nCh := DL_RE_CH_A;                            // 通道码：旋变 A | channel code A
    IF NOT bEnable THEN
        _eState := E_DL_ResEncState.eInit;          // 失能回初相 | disable returns to init
    ELSIF NOT _bAOk THEN
        _bChLost := TRUE;                          // 当前通道失效（独立成因）：不切换、直接失效 | the active channel is lost
        _eState := E_DL_ResEncState.eLost;
    ELSIF _bBOk AND tonAgree.Q THEN
        _eState := E_DL_ResEncState.eDualOk;        // 对侧恢复且一致计时到 → 回双通道 | peer recovered and agreed, back to dual
    END_IF

E_DL_ResEncState.eSingleB:
    _fTarget := FoldAngleDeg(fAngleBDeg);          // 单通道 B：目标为编码器角 [°] | single B, target is the encoder angle
    _nCh := DL_RE_CH_B;                            // 通道码：编码器 B | channel code B
    IF NOT bEnable THEN
        _eState := E_DL_ResEncState.eInit;          // 失能回初相 | disable returns to init
    ELSIF NOT _bBOk THEN
        _bChLost := TRUE;                          // 当前通道失效（独立成因）：不切换、直接失效 | the active channel is lost
        _eState := E_DL_ResEncState.eLost;
    ELSIF _bAOk AND tonAgree.Q THEN
        _eState := E_DL_ResEncState.eDualOk;        // 对侧恢复且一致计时到 → 回双通道 | peer recovered and agreed, back to dual
    END_IF

E_DL_ResEncState.eLost:
    _fTarget := _fOut;                             // 失效相冻结输出，宁可保持也不跳变 [°] | frozen output, never jump
    _nCh := DL_RE_CH_NONE;                         // 无有效通道码 | no valid channel code
    IF NOT bEnable THEN
        _eState := E_DL_ResEncState.eInit;          // 失能回初相 | disable returns to init
    ELSIF _bAOk AND _bBOk AND tonAgree.Q THEN
        _eState := E_DL_ResEncState.eDualOk;        // 双路恢复且一致计时到 → 回双通道 | both recovered and agreed
    ELSIF _bAOk AND tonSingle.Q THEN
        _eState := E_DL_ResEncState.eSingleA;       // 单路 A 恢复且确认到 → 先切单通道（不直接回双通道）| single A confirmed
    ELSIF _bBOk AND tonSingle.Q THEN
        _eState := E_DL_ResEncState.eSingleB;       // 单路 B 恢复且确认到 → 先切单通道 | single B confirmed
    END_IF
    // 解除路径自证：tonSingle 的 IN = 恰好一路可用，故上式在「单路恢复」场景恒可达；
    // 若两路长期不一致且无参照，本相按设计保持（不猜），bReset 可重建参照后重新裁决。

ELSE
    // 非法枚举值（越界或未定义成员）：不猜，冻结输出并置失效相
    // illegal enumerator: no guessing, freeze the output and fall into the lost phase
    _fTarget := _fOut;
    _nCh := DL_RE_CH_NONE;
    _eState := E_DL_ResEncState.eLost;
END_CASE;

// 段 9｜限变率追随：环形带符号差先钳到 ±每拍步长再累加，故任何切换都不产生跳变
// segment 9, slew-limited tracking; the circular difference is clamped to the per-scan step before integration
IF bEnable AND (NOT _bCfgBad) THEN
    _fSlewStep := fMaxSlewDegPerSec * DL_RE_SAMPLE_S; // 每拍最大角增量 [°] = [°/s] × [s] | per-scan step [deg]
    _fDelta := FoldSignedDiff(_fTarget, _fOut);    // 待施加带符号角增量 [°] | signed increment to apply [deg]
    IF _fDelta > _fSlewStep THEN
        _fDelta := _fSlewStep;                     // 正向钳到步长上限 [°] | clamp to the positive step
    END_IF
    IF _fDelta < (0.0 - _fSlewStep) THEN
        _fDelta := 0.0 - _fSlewStep;               // 负向钳到步长下限 [°] | clamp to the negative step
    END_IF
    _fOut := FoldAngleDeg(_fOut + _fDelta);        // 累加并折圈 [°] | integrate and fold [deg]
END_IF
// 失能或组态非法时 _fOut 冻结保持末值（头注释已声明「冻结保持」语义，R191）

// 段 10｜出口单点映射（切换事件由通道码差分派生，单拍；快照在本段末更新）
// segment 10, single-point output mapping; the switch event is derived from the channel code difference
eState := _eState;                                 // 状态映射 | state mapping
fAngleOut := _fOut;                                // 输出角度映射 [°] | output angle mapping [deg]
fDeviationDeg := _fDevDeg;                         // 角差映射 [°] | deviation mapping [deg]
nActiveChannel := _nCh;                            // 通道码映射 | channel code mapping
bSwitchEvent := (_nCh <> _nChPrev);                // 切换单拍位 = 本拍码与上拍码不同 | one-scan switch pulse
_nChPrev := _nCh;                                  // 更新通道码快照（非清零，仅供下一拍差分）| update the snapshot
bLost := (_eState = E_DL_ResEncState.eLost);       // 失效汇总由状态派生 | lost aggregate derived from the state
bCfgErr := _bCfgBad;                               // 组态非法诊断位 | bad-configuration diagnostic
bDataErr := (NOT _bAOk) OR (NOT _bBOk);            // 数据非有限诊断位（通道可用性直接派生）| non-finite data diagnostic

// 段 11｜本拍消费量收尾（仅清沿锁存；不触碰任何锁存位与 CASE 内写入量）
// segment 11, end-of-scan cleanup; only the edge latch is cleared
_bResetLatch := FALSE;
END_FUNCTION_BLOCK
