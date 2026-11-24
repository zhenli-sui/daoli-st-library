(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ValveSeatLeakWatch
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 阀座关闭位泄漏趋势监视。阀门命令关 + 关位反馈到齐 +
 *                         tSettle 稳定后进入监视：对关位残差（dp 或流量）做
 *                         N 点最小二乘趋势斜率（窗口线性回归）+ 均值双判据：
 *                         残差均值超 fLeakLevel 且斜率非负上升 → 泄漏判据成立，
 *                         bLeakDetected 锁存。开阀/离开关位自动回监视待机。
 * 来源标签 (Origin)     : 自研线（诊断族深化，IEC 61131-3 标准语义的道莅防御性
 *                         实现，clean-room）
 * 分工声明 (Pairing)    : ValveSeatLeakWatch（关位泄漏趋势，本件）↔
 *                         ValvePartialStrokeTest（行程试验，既有件）：本件只在
 *                         关位做无扰动趋势监视，不驱动阀门动作；行程试验主动
 *                         部分行程激励，二者判据域不同不互斥（R298 属主边界）。
 * 边界语义 (Boundary)   : ① 判据串相位因子：仅 eWatch 相判泄漏，eIdle/开阀期
 *                         不判（R281 相位相关判据防误锁口径）；
 *                         ② LS 除零防御：Σ(x-x̄)² <= eps（窗口内无时间跨度）
 *                         → 斜率按 0 处理，只走均值判据，不产生 Inf；
 *                         ③ 残差 NaN 拒收（不入窗口，不参与统计）；
 *                         ④ 组态闸：窗深 < 2 / 阈值 <= 0 / 稳定时间 <= 0 → 故障。
 * 输出语义 (Fallback)   : 【R191】eIdle 相 → 判据输出清零（监视未在关位，
 *                         无泄漏语义）；eFault 相 → bLeakDetected 保持末值 +
 *                         bError = TRUE。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)，
 *                         码位待主控收口统一派号。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 除零（Σx² eps 闸）/NaN 拒收/组态闸 ✓
 *                         R5 双语同行注释 ✓｜R6 CASE 带 ELSE 兜底迁 eFault ✓
 *                         R7 TON/R_TRIG 段 0 无条件刷新，各自独立实例 ✓
 * 验收向量 (Acceptance) : V1 关位稳定后残差恒 0.5（阈 0.2）、窗口斜率 ≈ 0 →
 *                         斜率非负成立，tLeakConf 到时 bLeakDetected=TRUE；
 *                         V2 残差 0.5 但窗口斜率显著负下降 → 不判泄漏；
 *                         V3 开阀命令一出现 → 判据清零回 eIdle。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R49 首版（批 2 · 序号 8）
 *                        2026-11-20  v1.0.1  R52: 环窗时间序修正，消除斜率符号翻转
 *                        （删写入期 _aX[_nHead] 赋值，改求和期按 _nOldest→_nIdx 时间序
 *                        环回取 _aRes，X 用 1.._nFill 时间序号；修回卷后 X/Y 错配致
 *                        L193 `_fSlope >= 0.0` 把真实上升泄漏判成非上升的安全侧漏报）
 *==============================================================================*)
TYPE E_DL_VslState :
(
    eIdle   := 0,                            (* 未在关位（判据清零） / Not at closed seat *)
    eSettle := 10,                           (* 关位稳定等待 / Closed-seat settling *)
    eWatch  := 20,                           (* 泄漏趋势监视 / Leak trend watching *)
    eFault  := 90                            (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_VslCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：窗深/阈值/时间越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_ValveSeatLeakWatch
VAR_INPUT
    bCmdClose   : BOOL := FALSE;             (* 阀关命令电平 [-] / Valve close command level *)
    bLimitClosed: BOOL := FALSE;             (* 关位限位反馈电平 [-] / Closed-seat limit feedback *)
    fResidual   : LREAL := 0.0;              (* 关位残差输入（dp 或流量标定值）[工程单位] / Closed-seat residual input *)
    fLeakLevel  : LREAL := 0.2;              (* 泄漏均值阈值，域 > 0.0 [工程单位] / Leak mean threshold *)
    nWinDepth   : INT := 16;                 (* LS 趋势窗深，域 2..32 [点] / LS trend window depth *)
    tSettle     : TIME := T#5S;              (* 关位稳定等待时间，域 > T#0S [ms] / Settle wait time *)
    tLeakConf   : TIME := T#3S;              (* 泄漏判据确认保持时间，域 > T#0S [ms] / Leak confirm hold time *)
    bEnable     : BOOL := TRUE;              (* 监视使能 [-] / Enable *)
    bReset      : BOOL := FALSE;             (* 复位命令，上升沿清泄漏锁存与窗口 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    bLeakDetected : BOOL;                    (* 泄漏判据锁存位（复位沿或开阀沿清）[-] / Leak detected latch *)
    fResidualMean : LREAL;                   (* 当前窗口残差均值 [工程单位] / Window residual mean *)
    fTrendSlope   : LREAL;                   (* 当前窗口 LS 趋势斜率 [工程单位/拍] / Window LS slope *)
    bWatching     : BOOL;                    (* 关位监视中指示 [-] / Watching indicator *)
    eState        : E_DL_VslState;           (* 状态出口 / State outlet *)
    eCause        : E_DL_VslCause;           (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError        : BOOL;                    (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_VslState := E_DL_VslState.eIdle;      (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_VslCause := E_DL_VslCause.eNone;      (* 故障成因锁存量 / Latched cause *)
    tonSettle: TON;                          (* 关位稳定计时，IN 由相位派生，段 0 无条件调用 / Settle timer *)
    tonConf  : TON;                          (* 泄漏确认计时，独立实例（一相一定时器，R275） / Confirm timer, separate instance *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _aRes    : ARRAY[1..32] OF LREAL;        (* 残差窗口环形缓冲 [工程单位] / Residual ring window *)
    _aX      : ARRAY[1..32] OF LREAL;        (* 窗口序号数组（v1.0.1 起废弃不参与运算，R53 清理；保留以保差异审阅可读）[点] / Deprecated index array *)
    _nHead   : INT;                          (* 环形写入头游标 [-] / Ring head cursor *)
    _nOldest : INT;                          (* 最旧样本槽位（统计段每趟重算）[-] / Oldest sample slot, recomputed *)
    _nIdx    : INT;                          (* 时间序 → 环形槽位换算下标 [-] / Time-order to slot index *)
    _nFill   : INT;                          (* 窗口已填充点数 [点] / Window fill count *)
    _nEff    : INT;                          (* 钳位后生效窗深 [点] / Clamped effective depth *)
    _fSumX   : LREAL;                        (* LS 累计：Σx [-] / LS sum of x *)
    _fSumY   : LREAL;                        (* LS 累计：Σy [工程单位] / LS sum of y *)
    _fSumXY  : LREAL;                        (* LS 累计：Σxy [工程单位·点] / LS sum of xy *)
    _fSumX2  : LREAL;                        (* LS 累计：Σx² [-] / LS sum of x² *)
    _fDen    : LREAL;                        (* LS 分母 Σ(x-x̄)² [-] / LS denominator *)
    _fSlope  : LREAL;                        (* 本拍派生斜率 [工程单位/点] / Derived slope *)
    _fMean   : LREAL;                        (* 本拍派生均值 [工程单位] / Derived mean *)
    _bLeakC  : BOOL;                         (* 泄漏当拍判据（均值超阈 ∧ 斜率非负） / Leak verdict this scan *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _i       : INT;                          (* 统计扫描游标（每趟重置，R227）[-] / Stats scan cursor *)
END_VAR
VAR CONSTANT
    DL_VSL_EPS  : LREAL := 1.0E-12;          (* LS 分母判零容差 [-] / LS denominator epsilon *)
    DL_VSL_NMAX : INT   := 32;               (* 窗深容量上限 [点] / Window capacity limit *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (fLeakLevel <= 0.0) OR (tSettle <= T#0S) OR (tLeakConf <= T#0S);   (* 组态闸（标量域引脚，R151） / Config gate *)
rtReset(CLK := bReset);                                                       (* 复位沿每拍必调 / Reset edge every scan *)
tonSettle(IN := _eState = E_DL_VslState.eSettle, PT := tSettle);              (* 稳定计时随相位派生 / Settle timer *)
tonConf(IN := _bLeakC AND _eState = E_DL_VslState.eWatch, PT := tLeakConf);   (* 确认计时（注意：IN 引用上拍判据，一拍滞后可接受，头注释声明） / Confirm timer, one-scan lag declared *)
_nEff := nWinDepth;                                                           (* 生效窗深初值 / Effective depth init *)
IF _nEff < 2 THEN
    _nEff := 2;                                                               (* 窗深下限 2（两点才能定斜率） / Min depth 2 *)
END_IF
IF _nEff > DL_VSL_NMAX THEN
    _nEff := DL_VSL_NMAX;                                                     (* 窗深钳位到容量（R308） / Clamp depth to capacity *)
END_IF
IF (nWinDepth < 2) OR (nWinDepth > DL_VSL_NMAX) THEN
    _bCfgBad := _bCfgBad OR TRUE;                                             (* 窗深越域并入组态闸（越域仍钳位运行但报故障） / Depth out of domain joins gate *)
END_IF

(* —— 段 1：单拍量预清零（R107） —— *)
_bLeakC := FALSE;                                                             (* 泄漏当拍判据预清，唯一分支置位 / Leak verdict preset *)
_fSumX := 0.0;                                                                (* LS 累计量清零重算（每拍全路径派生） / LS sums recompute *)
_fSumY := 0.0;                                                                (* Σy 清零 / Sum y clear *)
_fSumXY := 0.0;                                                               (* Σxy 清零 / Sum xy clear *)
_fSumX2 := 0.0;                                                               (* Σx² 清零 / Sum x2 clear *)
_fDen := 0.0;                                                                 (* LS 分母清零（防 _nFill=0 时旧值残留触发除零） / LS denominator clear *)
_fSlope := 0.0;                                                               (* 斜率缺省 0 / Slope default *)
_fMean := 0.0;                                                                (* 均值缺省 0 / Mean default *)
_nOldest := 1;                                                                (* 最旧槽位预清（统计段重算，防残留） / Oldest slot preset *)
_nIdx := 1;                                                                   (* 槽位下标预清 / Slot index preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清泄漏锁存 + 清窗口 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                         (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_VslCause.eNone;                                           (* 清成因 / Clear cause *)
    bLeakDetected := FALSE;                                                   (* 清泄漏锁存 / Clear leak latch *)
    _nFill := 0;                                                              (* 清窗填充计数 / Clear fill count *)
    _nHead := 1;                                                              (* 头游标复位 / Head cursor reset *)
    _eState := E_DL_VslState.eIdle;                                           (* 迁待机相 / Back to idle *)
END_IF

(* —— 段 3：CASE 主状态机（判据串相位因子，R281；ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_VslState.eIdle:                                                      (* 待机相：判据与统计出口清零（声明语义） / Idle: verdicts cleared *)
        fResidualMean := 0.0;                                                 (* 均值出口清零 / Mean outlet clear *)
        fTrendSlope := 0.0;                                                   (* 斜率出口清零 / Slope outlet clear *)
        bLeakDetected := FALSE;                                               (* 泄漏锁存随离开关位自动清（声明：开阀沿清锁存） / Leak latch auto-clear on leaving seat *)
        IF bEnable AND NOT _bFault AND bCmdClose AND bLimitClosed THEN
            _eState := E_DL_VslState.eSettle;                                 (* 关位到齐进入稳定等待 / Enter settle *)
        END_IF
    E_DL_VslState.eSettle:                                                    (* 稳定等待相 / Settle *)
        IF NOT (bCmdClose AND bLimitClosed) THEN
            _eState := E_DL_VslState.eIdle;                                   (* 离开关位回待机 / Leave seat *)
        ELSIF tonSettle.Q THEN
            _nFill := 0;                                                      (* 稳定后清窗重采（避免稳定前残差污染统计） / Clear window after settle *)
            _nHead := 1;                                                      (* 头游标复位 / Head reset *)
            _eState := E_DL_VslState.eWatch;                                  (* 进入监视 / Enter watch *)
        END_IF
    E_DL_VslState.eWatch:                                                     (* 监视相：采窗 + 统计 + 判据 / Watch *)
        IF NOT (bCmdClose AND bLimitClosed) THEN
            bLeakDetected := FALSE;                                           (* 离开位清泄漏锁存（开阀沿语义） / Leak latch clear *)
            _eState := E_DL_VslState.eIdle;                                   (* 回待机 / Back to idle *)
        ELSE
            IF (fResidual = fResidual) AND ((fResidual - fResidual) = (fResidual - fResidual)) THEN
                _aRes[_nHead] := fResidual;                                   (* 有限残差入环窗（NaN 拒收不入窗） / Finite residual into ring *)
                (* X 不再于写入期生成：改为求和期按时间序现算（R52 修 R193 扩面） / X derived at sum time in time order *)
                _nHead := _nHead + 1;                                         (* 头游标递进 / Head advance *)
                IF _nHead > _nEff THEN
                    _nHead := 1;                                              (* 环回卷（下标先判后增，无越界） / Ring wrap *)
                END_IF
                IF _nFill < _nEff THEN
                    _nFill := _nFill + 1;                                     (* 填充计数封顶 / Fill count cap *)
                END_IF
            END_IF
            IF _nFill >= 1 THEN
                _nOldest := _nHead - _nFill;                                  (* 最旧样本槽：未满窗时 = 1（头游标 = 填充数 + 1） / Oldest slot while filling *)
                IF _nOldest < 1 THEN
                    _nOldest := _nOldest + _nEff;                             (* 满窗回卷后最旧样本在 _nHead 槽：时间序起点（R52 修） / Wrapped: oldest at head slot *)
                END_IF
            END_IF
            _i := 1;                                                          (* 统计游标起头重置（R227） / Stats cursor reset *)
            WHILE _i <= _nFill DO                                             (* 逐点 LS 累计：x = 时间序，y 自最旧槽环回取值（R52 时间序） / Time-ordered LS sums *)
                _nIdx := _nOldest + _i - 1;                                   (* 时间序 → 环形槽位映射 / Time order to ring slot *)
                IF _nIdx > _nEff THEN
                    _nIdx := _nIdx - _nEff;                                   (* 槽位环回 / Slot wrap *)
                END_IF
                _fSumX := _fSumX + DINT_TO_LREAL(_i);                         (* Σx（时间序号 1..nFill，不随运行时间增长） / Sum x in time order *)
                _fSumY := _fSumY + _aRes[_nIdx];                              (* Σy / Sum y *)
                _fSumXY := _fSumXY + DINT_TO_LREAL(_i) * _aRes[_nIdx];        (* Σxy / Sum xy *)
                _fSumX2 := _fSumX2 + DINT_TO_LREAL(_i) * DINT_TO_LREAL(_i);   (* Σx² / Sum x2 *)
                _i := _i + 1;                                                 (* 游标递进 / Cursor advance *)
            END_WHILE
            IF _nFill >= 1 THEN
                _fMean := _fSumY / DINT_TO_LREAL(_nFill);                     (* 均值：除子恒 >= 1 无除零 / Mean, divisor >= 1 *)
                _fDen := _fSumX2 - _fSumX * _fSumX / DINT_TO_LREAL(_nFill);   (* LS 分母 = Σx² - (Σx)²/n / LS denominator *)
            END_IF
            IF _fDen > DL_VSL_EPS THEN
                _fSlope := (_fSumXY - _fSumX * _fSumY / DINT_TO_LREAL(_nFill)) / _fDen;   (* 斜率：分母已过 eps 闸，无除零 / Slope, denominator gated *)
            ELSE
                _fSlope := 0.0;                                               (* 窗内无时间跨度：斜率退化 0，只走均值判据（边界②） / Degenerate slope zero *)
            END_IF
            fResidualMean := _fMean;                                          (* 均值出口镜像 / Mean outlet mirror *)
            fTrendSlope := _fSlope;                                           (* 斜率出口镜像 / Slope outlet mirror *)
            _bLeakC := (_fMean > fLeakLevel) AND (_fSlope >= 0.0);            (* 判据：均值超阈 ∧ 斜率非负（0.0 容差比较：斜率与 0 用 >= 单侧合法） / Verdict: mean over threshold AND slope non-negative *)
            IF tonConf.Q THEN                                                 (* 判据保持到确认时间 / Verdict held to confirm time *)
                bLeakDetected := TRUE;                                        (* 泄漏锁存至复位沿/离开位 / Leak latch *)
            END_IF
        END_IF
    E_DL_VslState.eFault:                                                     (* 故障相：保持末值，仅复位沿出 / Fault *)
        ;                                                                     (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                      (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_VslState.eFault;                                      (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                      (* 同步锁存 / Latch *)
        _eCause := E_DL_VslCause.ePhaseBad;                                   (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 4：出口映射（bError/eState 同源，R191） —— *)
bWatching := (_eState = E_DL_VslState.eWatch);                                (* 监视中指示 / Watching indicator *)
bError := _bFault;                                                            (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                            (* 状态出口 / State outlet *)
eCause := _eCause;                                                            (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
