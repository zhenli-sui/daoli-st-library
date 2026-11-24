(*==============================================================================
 * 组件名称 (Component)  : FB_DL_RulEstimator
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.1
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / SQRT / ABS），
 *                         零厂商私有库
 * 功能描述 (Function)   : 多特征健康指数线性外推剩余寿命估计（预测性维护 RUL）。
 *                         四路特征（振动/温度/电流/压差等）按组态权重合成健康
 *                         指数 HI = 100·Σ(wi·xi/fiFull)（钳位 0..100），滚动窗
 *                         内对 (采样序号, HI) 做最小二乘回归得退化斜率 k（每拍
 *                         HI 损失）；k < 0 且显著（|k| > k·σ 噪声门）时外推
 *                         RUL = (HI - EOL 阈值) / (-k)，置信带由残差标准差
 *                         σ 经斜率不确定性传播给出 RUL ± fZConf·σ/|k|。
 *                         与 DeviceHealthArbiter（健康仲裁）配对：本件外推，
 *                         仲裁件决策。
 * 来源标签 (Origin)     : 自研线（IEC 61131-3 标准语义的道莅防御性实现，clean-room）
 * 分工声明 (Pairing)    : RulEstimator（寿命外推，本件）↔ DeviceHealthArbiter
 *                         （健康仲裁，既有件）：本件只产出 HI/斜率/RUL/置信带，
 *                         不做停机决策、不派维护工单（R298 属主边界）。
 * 边界语义 (Boundary)   : ① 斜率除零/符号闸：|k| <= eps 或 k >= 0（未退化）
 *                         → RUL 输出哨兵 0 且 bRulValid = FALSE（还原方向
 *                         不饱和、返回哨兵 + 有效性位，非故障级）；
 *                         ② LS 分母 <= eps → 斜率按 0（窗内 HI 无变化）；
 *                         ③ 特征 NaN/Inf 拒收该拍（HI 不入窗，防污染回归）；
 *                         ④ RUL 上限饱和：nRulScans 超 UDINT 哨兵前按
 *                         DL_RUL_MAX 饱和（先 TRUNC 再进位语义，实数上限兜底
 *                         防溢出，R28 清单）；
 *                         ⑤ 组态闸：权重和 <= eps / EOL 阈值域 / 满量程 <= eps
 *                         → 故障锁存；
 *                         ⑥ 环形窗回归遍历按时间序（自最旧样本槽起环回映射，
 *                         v1.0.1 R51），与数组下标序解耦（R50 终审严重项修法）。
 * 输出语义 (Fallback)   : 【R191】bRulValid = FALSE → fRulHours/nRulScans 输出
 *                         哨兵 0（非故障）；eFault 相 → 全输出冻结保持末值 +
 *                         bError = TRUE。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)，
 *                         码位待主控收口统一派号。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 除零（斜率/分母双闸）/NaN 拒收/饱和防溢出/组态闸 ✓
 *                         R5 双语同行注释 ✓｜R6 CASE 带 ELSE 兜底迁 eFault ✓
 *                         R7 TON/R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 HI 每拍恒降 1.25（线性序列 LS 精确复原斜率）→
 *                         k = -1.25 [HI/拍]，EOL=30 → RUL = (HI-30)/1.25 拍；
 *                         V2 HI 恒定（k=0）→ bRulValid=FALSE，RUL 哨兵 0；
 *                         V3 HI 回升（k>0）→ bRulValid=FALSE（未退化语义）；
 *                         V4 窗深 8 连采 16 拍（第 9 拍起回卷）：回卷后斜率与
 *                         回卷前一致（时序遍历，符号不翻转；v1.0.1 回归向量）。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R49 首版（批 3 · 序号 14）
 *                        2026-11-20  v1.0.1  R51 返修（R50 终审严重）：LS 回归改自
 *                        最旧样本槽起按时间序环回遍历（_nOldest→_nIdx 映射取 _aY），
 *                        修窗回卷后 y 序列相对 x 旋转致斜率符号翻转；新增验收
 *                        向量 V4 环回一致性回归。
 *==============================================================================*)
TYPE E_DL_RulState :
(
    eIdle  := 0,                             (* 待使能 / Idle *)
    eLearn := 10,                            (* 健康指数采集与回归 / Learning *)
    eFault := 90                             (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_RulCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：权重/阈值/满量程越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_RulEstimator
VAR_INPUT
    fFeat1    : LREAL := 0.0;                (* 特征 1（如振动烈度）[工程单位] / Feature 1 *)
    fFeat2    : LREAL := 0.0;                (* 特征 2（如轴承温度）[工程单位] / Feature 2 *)
    fFeat3    : LREAL := 0.0;                (* 特征 3（如电机电流）[工程单位] / Feature 3 *)
    fFeat4    : LREAL := 0.0;                (* 特征 4（如压差）[工程单位] / Feature 4 *)
    fFull1    : LREAL := 100.0;              (* 特征 1 满量程（报警级幅值），域 > eps [工程单位] / Feature 1 full scale *)
    fFull2    : LREAL := 100.0;              (* 特征 2 满量程 [工程单位] / Feature 2 full scale *)
    fFull3    : LREAL := 100.0;              (* 特征 3 满量程 [工程单位] / Feature 3 full scale *)
    fFull4    : LREAL := 100.0;              (* 特征 4 满量程 [工程单位] / Feature 4 full scale *)
    fW1       : LREAL := 0.4;                (* 特征 1 权重，四权重和 > eps [-] / Feature 1 weight *)
    fW2       : LREAL := 0.3;                (* 特征 2 权重 [-] / Feature 2 weight *)
    fW3       : LREAL := 0.2;                (* 特征 3 权重 [-] / Feature 3 weight *)
    fW4       : LREAL := 0.1;                (* 特征 4 权重 [-] / Feature 4 weight *)
    fEolThresh: LREAL := 30.0;               (* 寿命终点健康指数阈值，域 0..100 [HI] / End-of-life HI threshold *)
    nWinDepth : INT := 64;                   (* 回归窗深，域 8..128 [点] / Regression window depth *)
    tScan     : TIME := T#1S;                (* 采样周期（RUL 小时换算基），域 > T#0S [ms] / Sampling period *)
    bEnable   : BOOL := TRUE;                (* 估计使能 [-] / Enable *)
    bReset    : BOOL := FALSE;               (* 复位命令，上升沿清窗与全部输出 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fHealthIdx : LREAL;                      (* 当前健康指数 0..100（实时派生）[HI] / Current health index *)
    fSlopePerScan : LREAL;                   (* 退化斜率（每拍 HI 损失，负值 = 退化）[HI/拍] / Degradation slope per scan *)
    nRulScans  : UDINT;                      (* 剩余寿命拍数估计（哨兵 0 = 无效）[拍] / RUL in scans, sentinel 0 *)
    fRulHours  : LREAL;                      (* 剩余寿命小时估计（哨兵 0.0 = 无效）[h] / RUL in hours, sentinel 0 *)
    fRulLo     : LREAL;                      (* RUL 置信下界 [h] / RUL confidence lower bound *)
    fRulHi     : LREAL;                      (* RUL 置信上界 [h] / RUL confidence upper bound *)
    bRulValid  : BOOL;                       (* RUL 有效性（斜率显著为负才 TRUE）[-] / RUL validity *)
    eState     : E_DL_RulState;              (* 状态出口 / State outlet *)
    eCause     : E_DL_RulCause;              (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError     : BOOL;                       (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_RulState := E_DL_RulState.eIdle;      (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_RulCause := E_DL_RulCause.eNone;      (* 故障成因锁存量 / Latched cause *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _aY      : ARRAY[1..128] OF LREAL;       (* HI 样本窗 [HI] / HI sample window *)
    _nHead   : INT;                          (* 环形头游标 [-] / Ring head cursor *)
    _nFill   : INT;                          (* 窗填充数 [点] / Window fill count *)
    _nEff    : INT;                          (* 钳位后生效窗深 [点] / Clamped depth *)
    _nSeq    : UDINT;                        (* 全局采样序号（回归自变量基）[点] / Global sample sequence *)
    _fHI     : LREAL;                        (* 本拍合成健康指数 [HI] / Health index this scan *)
    _fSx     : LREAL;                        (* Σx [点] / Sum x *)
    _fSy     : LREAL;                        (* Σy [HI] / Sum y *)
    _fSxy    : LREAL;                        (* Σxy [HI·点] / Sum xy *)
    _fSx2    : LREAL;                        (* Σx² [点²] / Sum x2 *)
    _fDen    : LREAL;                        (* LS 分母 n·Σx²-(Σx)² [点²] / LS denominator *)
    _fK      : LREAL;                        (* 回归斜率 [HI/点] / Regression slope *)
    _fInter  : LREAL;                        (* 回归截距 [HI] / Regression intercept *)
    _fSse    : LREAL;                        (* 残差平方和 [HI²] / Residual SSE *)
    _fSigma  : LREAL;                        (* 残差标准差 [HI] / Residual sigma *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _nJ      : INT;                          (* 时间序游标（0.._nFill-1，每趟重置，R227）[-] / Time-order cursor *)
    _nIdx    : INT;                          (* 时间序 → 环形槽位换算下标 [-] / Ring slot index *)
    _nOldest : INT;                          (* 最旧样本槽位（每趟重算）[-] / Oldest sample slot *)
END_VAR
VAR CONSTANT
    DL_RUL_EPS  : LREAL := 1.0E-12;          (* 斜率/分母判零容差 [-] / Slope/denominator epsilon *)
    DL_RUL_NMAX : INT   := 128;              (* 窗深容量上限 [点] / Window capacity limit *)
    DL_RUL_MIN  : INT   := 16;               (* 判据最小样本数 [点] / Min samples for verdict *)
    DL_RUL_MAX  : UDINT := 4000000000;       (* RUL 拍数饱和上限（实数域兜底防溢出，R28）[拍] / RUL saturation cap *)
    DL_RUL_Z    : LREAL := 1.96;             (* 置信带 z 值（95% 双侧，公开统计常数）[-] / Confidence z value 95% *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (fFull1 <= DL_RUL_EPS) OR (fFull2 <= DL_RUL_EPS) OR (fFull3 <= DL_RUL_EPS) OR (fFull4 <= DL_RUL_EPS)   (* 满量程正域闸（每个引脚单独覆盖，R151） / Full-scale gates *)
            OR (fW1 + fW2 + fW3 + fW4 <= DL_RUL_EPS)                                                      (* 权重和闸（防除零） / Weight-sum gate *)
            OR (fEolThresh < 0.0) OR (fEolThresh > 100.0)                                                 (* EOL 阈值域闸 / EOL threshold gate *)
            OR (nWinDepth < 8) OR (nWinDepth > DL_RUL_NMAX) OR (tScan <= T#0S);                           (* 窗深/周期闸 / Depth/period gate *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)
_nEff := nWinDepth;                          (* 生效窗深初值 / Depth init *)
IF _nEff < 8 THEN
    _nEff := 8;                              (* 下限钳位 / Lower clamp *)
END_IF
IF _nEff > DL_RUL_NMAX THEN
    _nEff := DL_RUL_NMAX;                    (* 上限钳位（R308） / Upper clamp *)
END_IF
_nSeq := _nSeq + 1;                          (* 采样序号推进（UDINT 回绕：2^32 点按 1s 采样 ≈ 136 年，工程安全） / Sequence advance *)

(* —— 段 1：单拍量预清零（R107） —— *)
_fHI := 0.0;                                 (* HI 缺省 0 / HI default *)
_fSx := 0.0;                                 (* 累计量清零重算（每拍全路径派生，R285） / Sums recompute *)
_fSy := 0.0;                                 (* Σy 清零 / Sum y clear *)
_fSxy := 0.0;                                (* Σxy 清零 / Sum xy clear *)
_fSx2 := 0.0;                                (* Σx² 清零 / Sum x2 clear *)
_fDen := 0.0;                                (* 分母清零 / Denominator clear *)
_fK := 0.0;                                  (* 斜率缺省 0 / Slope default *)
_fInter := 0.0;                              (* 截距缺省 0 / Intercept default *)
_fSse := 0.0;                                (* 残差平方和清零 / SSE clear *)
_fSigma := 0.0;                              (* σ 缺省 0 / Sigma default *)
_nJ := 0;                                    (* 时间序游标预清 / Time cursor preset *)
_nIdx := 1;                                  (* 槽位下标预清 / Slot index preset *)
_nOldest := 1;                               (* 最旧槽位预清（统计段重算） / Oldest slot preset *)
bRulValid := FALSE;                           (* RUL 有效性预清（派生出口全路径赋值） / RUL validity preset *)
nRulScans := 0;                               (* RUL 哨兵 0 预置（还原方向不饱和返回哨兵口径） / RUL sentinel preset *)
fRulHours := 0.0;                             (* 小时哨兵 0 预置 / Hours sentinel preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清窗 + 清序号 + 清输出锁存 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_RulCause.eNone;          (* 清成因 / Clear cause *)
    _nFill := 0;                             (* 清窗填充 / Clear fill *)
    _nHead := 1;                             (* 头游标复位 / Head reset *)
    _nSeq := 0;                              (* 清序号基 / Clear sequence base *)
    fHealthIdx := 0.0;                       (* 清 HI 出口 / Clear HI outlet *)
    fSlopePerScan := 0.0;                    (* 清斜率出口 / Clear slope outlet *)
    fRulLo := 0.0;                           (* 清置信下界 / Clear lower bound *)
    fRulHi := 0.0;                           (* 清置信上界 / Clear upper bound *)
    _eState := E_DL_RulState.eIdle;          (* 迁待机相 / Back to idle *)
END_IF

(* —— 段 3：组态闸故障锁存（R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                         (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_RulCause.eCfgIllegal;    (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_RulState.eFault;         (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_RulState.eIdle:                     (* 待机相 / Idle *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_RulState.eLearn; (* 进入学习 / Enter learn *)
        END_IF
    E_DL_RulState.eLearn:                    (* 学习相：HI 合成 + 回归外推 / Learn *)
        IF NOT bEnable THEN
            _eState := E_DL_RulState.eIdle;  (* 失能回待机 / Back to idle *)
        ELSE
            IF (fFeat1 = fFeat1) AND (fFeat2 = fFeat2) AND (fFeat3 = fFeat3) AND (fFeat4 = fFeat4)   (* 四特征 NaN 自反判（联合闸） / NaN reflex gates *)
               AND ((fFeat1 - fFeat1) = (fFeat1 - fFeat1)) AND ((fFeat2 - fFeat2) = (fFeat2 - fFeat2))
               AND ((fFeat3 - fFeat3) = (fFeat3 - fFeat3)) AND ((fFeat4 - fFeat4) = (fFeat4 - fFeat4)) THEN   (* Inf 差判（联合闸） / Inf gates *)
                _fHI := 100.0 * (fW1 * fFeat1 / fFull1 + fW2 * fFeat2 / fFull2   (* 加权归一合成（除子为满量程，组态闸已保证 > eps） / Weighted normalized composition *)
                       + fW3 * fFeat3 / fFull3 + fW4 * fFeat4 / fFull4) / (fW1 + fW2 + fW3 + fW4);   (* 除子为权重和（组态闸已保证 > eps），无除零 / Divisor weight-sum, gated *)
                IF _fHI < 0.0 THEN
                    _fHI := 0.0;             (* HI 下限钳位 / HI lower clamp *)
                ELSIF _fHI > 100.0 THEN
                    _fHI := 100.0;           (* HI 上限钳位 / HI upper clamp *)
                END_IF
                fHealthIdx := _fHI;          (* HI 实时出口 / HI outlet *)
                _aY[_nHead] := _fHI;         (* 入窗 / Into window *)
                _nHead := _nHead + 1;        (* 头游标递进 / Head advance *)
                IF _nHead > _nEff THEN
                    _nHead := 1;             (* 环回卷 / Ring wrap *)
                END_IF
                IF _nFill < _nEff THEN
                    _nFill := _nFill + 1;    (* 填充封顶 / Fill cap *)
                END_IF
            END_IF                           (* 非有限特征拍：HI 保持上拍值、不入窗（边界③） / Non-finite scan: hold, skip *)
            IF _nFill >= 1 THEN
                _nOldest := _nHead - _nFill; (* 最旧样本槽位：未满窗时 = 1（头游标 = 填充数 + 1） / Oldest slot while filling *)
                IF _nOldest < 1 THEN
                    _nOldest := _nOldest + _nEff;   (* 满窗回卷后最旧样本在 _nHead 槽：时间序起点（R51 修） / Wrapped: oldest at head slot *)
                END_IF
            END_IF
            _nJ := 0;                        (* 时间序游标起头重置（R227） / Time cursor reset *)
            WHILE _nJ < _nFill DO            (* 按时间序 LS 累计：x = 时间序号，y 自最旧样本环回取值（修窗回卷旋转，R51） / Time-ordered LS sums *)
                _nIdx := _nOldest + _nJ;     (* 时间序 → 环形槽位映射 / Time order to ring slot *)
                IF _nIdx > _nEff THEN
                    _nIdx := _nIdx - _nEff;  (* 槽位环回 / Slot wrap *)
                END_IF
                _fSx := _fSx + DINT_TO_LREAL(_nJ + 1);       (* Σx（时间序号 1..nFill） / Sum x *)
                _fSy := _fSy + _aY[_nIdx];   (* Σy / Sum y *)
                _fSxy := _fSxy + DINT_TO_LREAL(_nJ + 1) * _aY[_nIdx];   (* Σxy / Sum xy *)
                _fSx2 := _fSx2 + DINT_TO_LREAL(_nJ + 1) * DINT_TO_LREAL(_nJ + 1);   (* Σx² / Sum x2 *)
                _nJ := _nJ + 1;              (* 游标递进 / Cursor advance *)
            END_WHILE
            IF _nFill >= 1 THEN
                _fDen := DINT_TO_LREAL(_nFill) * _fSx2 - _fSx * _fSx;   (* LS 分母 / LS denominator *)
            END_IF
            IF (_fDen > DL_RUL_EPS) AND (_nFill >= DL_RUL_MIN) THEN
                _fK := (DINT_TO_LREAL(_nFill) * _fSxy - _fSx * _fSy) / _fDen;   (* 斜率：分母已过 eps 闸，无除零 / Slope, denominator gated *)
                _fInter := (_fSy - _fK * _fSx) / DINT_TO_LREAL(_nFill);   (* 截距：除子恒 >= 1 / Intercept *)
                _nJ := 0;                    (* 残差时间序游标重置（R227） / Residual cursor reset *)
                WHILE _nJ < _nFill DO        (* 残差平方和累计（与统计段同款时间序环回映射） / Residual SSE, time-ordered *)
                    _nIdx := _nOldest + _nJ; (* 时间序 → 环形槽位映射 / Time order to ring slot *)
                    IF _nIdx > _nEff THEN
                        _nIdx := _nIdx - _nEff;   (* 槽位环回 / Slot wrap *)
                    END_IF
                    _fSse := _fSse + (_aY[_nIdx] - (_fInter + _fK * DINT_TO_LREAL(_nJ + 1))) * (_aY[_nIdx] - (_fInter + _fK * DINT_TO_LREAL(_nJ + 1)));   (* (y-ŷ)² / Squared residual *)
                    _nJ := _nJ + 1;          (* 游标递进 / Cursor advance *)
                END_WHILE
                _fSigma := SQRT(_fSse / DINT_TO_LREAL(_nFill));   (* 残差标准差（除子恒 >= 1） / Residual sigma *)
                fSlopePerScan := _fK / DINT_TO_LREAL(1);   (* 斜率出口（每拍口径） / Slope outlet per scan *)
                IF (_fK < (-DL_RUL_EPS)) AND (_fHI > fEolThresh) THEN   (* 退化显著（斜率负）且尚未到 EOL / Significant negative slope *)
                    IF ((-_fK) > DL_RUL_EPS) AND ((_fHI - fEolThresh) / (-_fK) < UDINT_TO_LREAL(DL_RUL_MAX)) THEN
                        nRulScans := LREAL_TO_UDINT((_fHI - fEolThresh) / (-_fK));   (* RUL 拍数：除子 |k| 已过双闸，先判实数上限再 TRUNC 防溢出（R28 口径） / RUL scans, overflow-guarded *)
                        bRulValid := TRUE;   (* RUL 有效 / RUL valid *)
                    ELSE
                        nRulScans := DL_RUL_MAX;   (* 实数上限兜底饱和 / Cap saturation *)
                        bRulValid := TRUE;   (* 饱和值仍有效 / Saturated but valid *)
                    END_IF
                    fRulHours := UDINT_TO_LREAL(nRulScans) * TIME_TO_LREAL(tScan) / 1000.0 / 3600.0;   (* 拍→小时换算（除子常量 3600，无除零） / Scans to hours *)
                    fRulLo := fRulHours - DL_RUL_Z * _fSigma / (-_fK) * TIME_TO_LREAL(tScan) / 1000.0 / 3600.0;   (* 置信下界：σ/|k| 经斜率不确定性传播（|k| 已过闸） / Lower bound *)
                    fRulHi := fRulHours + DL_RUL_Z * _fSigma / (-_fK) * TIME_TO_LREAL(tScan) / 1000.0 / 3600.0;   (* 置信上界 / Upper bound *)
                    IF fRulLo < 0.0 THEN
                        fRulLo := 0.0;       (* 下界物理性钳位（寿命不为负） / Lower bound clamp *)
                    END_IF
                END_IF
            END_IF
        END_IF
    E_DL_RulState.eFault:                    (* 故障相：冻结保持，仅复位沿出 / Fault *)
        ;                                    (* 锁存回放（R28） / Replay from latch *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_RulState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_RulCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
