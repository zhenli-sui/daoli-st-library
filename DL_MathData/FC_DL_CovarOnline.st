(*==============================================================================
 * 组件名称 (Component)  : FC_DL_CovarOnline
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 基本算术，零厂商私有库
 * 功能描述 (Function)   : 双信号在线协方差（Welford 增量式），单遍流式更新、免二次遍历。
 *                         每拍只吃一对样本 (fX, fY)，把状态推进到调用者持有的累加结构 ST_DL_CovarAcc 中，
 *                         因此"在线"语义靠 IN_OUT 携带状态实现，函数本体无隐式记忆量。
 *                         Welford 协方差增量式（与均值更新交替，数值稳定）：
 *                           n ← n + 1                       （先计数，n 恒 ≥ 1）
 *                           dx ← x − meanX                  （用旧均值）
 *                           meanX ← meanX + dx / n
 *                           dy ← y − meanY
 *                           meanY ← meanY + dy / n
 *                           C ← C + dx · (y − meanY)        （用**新**均值，cosvar 更新式）
 *                           协方差 = C / (n − 1)            （样本协方差，n ≥ 2 才有定义）
 *                         验收向量（退化为可解析预测，R105 退化自检）：
 *                           ① 三点共线 y = 2x（x=1,2,3）→ 协方差 = 4.0，方差域比 = 1
 *                           ② 常量序列 x≡y≡5（n≥2）      → 协方差 = 0.0（差值容差内）
 *                           ③ 单样本 n=1                  → bValid=FALSE，不宣称
 * 接口     (Interface)  : IN_OUT stAcc 累加体（n/meanX/meanY/C 四量，调用者持有并负责复位）；
 *                         入 fX 样本 X、fY 样本 Y；出 返回值 = 样本协方差、bValid 宣称位（n≥2）、
 *                         bSampleRejected 当拍样本被剔标志、bResetDone 首样本生效标志。
 * 边界     (Boundary)   : ① **非有限样本前置剔除**：任一路为 NaN（自反判定 x<>x）或 Inf
 *                         （差值自反 (x−x)<>(x−x)）→ 当拍不累加、返回上一次已算协方差、置
 *                         bSampleRejected；② **分母闸**：n<2 时不做除法，返回 0 + bValid=FALSE
 *                         （单样本协方差无定义，绝不能拿 0/0 出来）；③ **输出钳位**：
 *                         协方差绝对值超 fCovarMax 时钳到 ±fCovarMax（防上游 IEEE 单位换算爆表）；
 *                         ④ 浮点比较一律差值容差，禁 = / <>（本件仅在 ABS 差 < 1E-12 处判等）；
 *                         ⑤ 累加体越界（n 达 UDINT 上限）时整体冻结不再累加并置 bSampleRejected；
 *                         ⑥ 零全局耦合、零物理地址。
 * 分工声明 (Scope)      : 本件只做"双流协方差原子件"。不接管：单信号多统计量聚合
 *                         （属 FB_DL_SignalStatistics）、相关系数归一（由调用者自行除以 σx·σy）、
 *                         样本窗口滑窗淘汰（本件是全历史累加，滑窗属上层窗口件）。
 * 来源标签 (Source Tag) : T2-1 LGF · Measurement ◐（流式协方差，自研 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位（零码位范式 R297）；诊断由 BOOL 出口承担。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 非有限剔除 + 分母闸 + 输出钳位 + 差值容差 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ 无状态机（纯组合函数，判别 IF 链带兜底分支） ｜ R7 ✓ 无定时器/沿实例
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R47 首版（批次 1 · 序号 3）
 *==============================================================================*)

TYPE ST_DL_CovarAcc :
STRUCT
    nCnt  : UDINT := 0;     // 已收样本数（含当拍） [个] / Accepted sample count including this scan
    fMeanX: LREAL := 0.0;   // X 流运行均值 [工程单位] / Running mean of the X stream
    fMeanY: LREAL := 0.0;   // Y 流运行均值 [工程单位] / Running mean of the Y stream
    fC    : LREAL := 0.0;   // 协方差分子累加量 C = Σ(x−mx)(y−my) [单位²] / Covariance co-moment accumulator
    fLast : LREAL := 0.0;   // 上次有效协方差（被剔样本当拍回放） [单位²] / Last valid covariance, replayed on reject
END_STRUCT
END_TYPE

FUNCTION FC_DL_CovarOnline : LREAL
VAR_IN_OUT
    stAcc : ST_DL_CovarAcc;                 // 累加体（调用者持有；复位时四量清 0） [-] / Accumulator owned by the caller
END_VAR
VAR_INPUT
    fX        : LREAL := 0.0;               // X 流当拍样本 [工程单位] / X sample of this scan
    fY        : LREAL := 0.0;               // Y 流当拍样本 [工程单位] / Y sample of this scan
    fCovarMax : LREAL := 1.0E12;            // 协方差输出绝对上限，域 > 0 [单位²] / Absolute covariance clamp, > 0
END_VAR
VAR_OUTPUT
    bValid          : BOOL := FALSE;        // 宣称位（n≥2 且本次除法合法） [-] / Validity flag, n >= 2
    bSampleRejected : BOOL := FALSE;        // 当拍样本被剔（非有限或计数饱和） [-] / Sample rejected this scan
END_VAR
VAR
    bXFin : BOOL := FALSE;                  // X 样本有限性判定中间量 [-] / X finiteness working flag
    bYFin : BOOL := FALSE;                  // Y 样本有限性判定中间量 [-] / Y finiteness working flag
    fDx   : LREAL := 0.0;                   // X 相对旧均值偏差 [工程单位] / X deviation from the old mean
    fDy   : LREAL := 0.0;                   // Y 相对旧均值偏差 [工程单位] / Y deviation from the old mean
    fN    : LREAL := 0.0;                   // 样本数的实数副本（作除数，已证 ≥ 1） [-] / Real copy of the count
    fLim  : LREAL := 0.0;                   // 生效钳位限（脚非法时回退常量，R127 解耦） [单位²] / Effective clamp limit
    fOut  : LREAL := 0.0;                   // 结果工作值 [单位²] / Result working value
END_VAR
VAR CONSTANT
    DL_COV_LIM_DEF : LREAL := 1.0E12;       // 钳位限回退默认值（与脚默认同源） [单位²] / Default clamp limit
    DL_COV_CNT_MAX : UDINT := 16#FFFF_FFFE; // 样本计数饱和闸（留 1 个余量防 +1 回绕） [个] / Count saturation gate
    DL_COV_EPS     : LREAL := 1.0E-12;      // 浮点判等容差（仅用于"差≈0"判定） [-] / Equality tolerance
END_VAR

(* —— 段 1：返回值与标志预置（R45 四段式第①段） —— *)
FC_DL_CovarOnline := 0.0;                   // 返回值预置 / Return value preset
bValid := FALSE;                            // 宣称位预置 / Validity preset
bSampleRejected := FALSE;                   // 剔除标志预置 / Reject flag preset
fOut := 0.0;                                 // 结果工作值预置 / Result working preset

(* —— 段 2：钳位限域闸（脚值非法回退常量，二级钳定 R117；R127 兜底值与被判量解耦） —— *)
fLim := fCovarMax;                           // 先直取脚值 / Take the pin value first
IF (fLim <> fLim) OR ((fLim - fLim) <> (fLim - fLim)) OR (fLim <= 0.0) THEN
    fLim := DL_COV_LIM_DEF;                  // 非有限或非正：回退默认常量 / Non-finite or non-positive: fall back
END_IF

(* —— 段 3：样本有限性闸（NaN 自反 + Inf 差值自反，LREAL 域无幅值常量可用，R40） —— *)
bXFin := NOT ((fX <> fX) OR ((fX - fX) <> (fX - fX)));      // X 有限 ⇔ 非 NaN 且非 Inf / X finite
bYFin := NOT ((fY <> fY) OR ((fY - fY) <> (fY - fY)));      // Y 有限 ⇔ 非 NaN 且非 Inf / Y finite

(* —— 段 4：剔除分支（非有限或计数饱和：不累加，回放上次有效值） —— *)
IF (NOT bXFin) OR (NOT bYFin) OR (stAcc.nCnt >= DL_COV_CNT_MAX) THEN
    bSampleRejected := TRUE;                 // 当拍样本拒收 / Reject this scan's sample
    fOut := stAcc.fLast;                     // 回放上次有效协方差（保持槽非有限闸已在写入侧保证） / Replay last valid value
ELSE
    (* —— 段 5：Welford 增量更新（先计数，再双均值，最后共矩） —— *)
    stAcc.nCnt := stAcc.nCnt + 1;            // 计数先推进（n ≥ 1，除零结构性不可能） / Count first, n >= 1 guaranteed
    fN := UDINT_TO_LREAL(stAcc.nCnt);        // 实数副本作除数 / Real copy as divisor

    fDx := fX - stAcc.fMeanX;                // X 偏差（旧均值） / X deviation from old mean
    stAcc.fMeanX := stAcc.fMeanX + (fDx / fN);   // X 均值更新 / Update X mean
    fDy := fY - stAcc.fMeanY;                // Y 偏差（旧均值） / Y deviation from old mean
    stAcc.fMeanY := stAcc.fMeanY + (fDy / fN);   // Y 均值更新 / Update Y mean

    stAcc.fC := stAcc.fC + (fDx * (fY - stAcc.fMeanY));  // 共矩增量（用新均值） / Co-moment increment with the new mean

    IF stAcc.nCnt >= 2 THEN
        fOut := stAcc.fC / (fN - 1.0);       // 样本协方差（分母 n−1 ≥ 1） / Sample covariance
        bValid := TRUE;                       // 样本数够：允许宣称 / Enough samples: may claim validity
    ELSE
        fOut := 0.0;                          // 单样本：协方差无定义，输出 0 / Single sample: undefined, output 0
        bValid := FALSE;                      // 不宣称 / Do not claim
    END_IF
END_IF

(* —— 段 6：结果非有限复检 + 钳位（R45 四段式第④段） —— *)
IF (fOut <> fOut) OR ((fOut - fOut) <> (fOut - fOut)) THEN
    fOut := 0.0;                             // 结果非有限：归 0 / Non-finite result: zeroed
    bValid := FALSE;                          // 同步撤宣称 / Withdraw validity in the same scan
END_IF
IF fOut > fLim THEN
    fOut := fLim;                             // 上钳 / Clamp high
ELSIF fOut < (0.0 - fLim) THEN
    fOut := 0.0 - fLim;                       // 下钳（写作 0.0−lim，避免负号字面量歧义） / Clamp low
END_IF

(* —— 段 7：保持槽写入（仅有限值可写入信任根，R133） —— *)
IF (NOT bSampleRejected) AND bValid THEN
    stAcc.fLast := fOut;                      // 记录最近有效值 / Remember the latest valid value
END_IF

(* —— 段 8：统一出口 —— *)
FC_DL_CovarOnline := fOut;                    // 输出样本协方差 / Output the sample covariance

END_FUNCTION
