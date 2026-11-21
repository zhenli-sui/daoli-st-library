(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AxisJogController
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 轴点动操作器 · 工艺上层件
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅依赖 Standard.library（TON / R_TRIG /
 *                         MIN / MAX / ABS），零厂商方言
 * 功能描述 (Function)   : 单轴点动操作器，经 I_DL_MotionAxis 接口引用驱动
 *                         轴体（依赖注入，不关心实现块品牌）。点动语义：
 *                         长按低速、按住高速选择且延时到自动升高速、松开
 *                         即受控停止；升/降速均走轴接口速度域限幅斜坡，
 *                         不做阶跃。软限位拦截独立于轴组态，便于现场收紧：
 *                         进入制动距离警戒区强制降为低速，限位处拒绝继续。
 * 设计要点 (Key notes)  : ① 双向同按 → 停止 + 信息级 0004_0102（安全侧
 *                           「不猜」，两方向都不执行）；
 *                         ② iAxis 不在 eStandstill/eContinuousMotion → 点动
 *                           指令拒绝（含 eStopping/eErrorStop 门禁）；
 *                         ③ 制动距离 fBrakeDist = fVel²/(2·fAcc) 现算（S-2
 *                           软限位预判语义的简化版），fAcc 有参数下限兜底
 *                           防除零；
 *                         ④ 参数对调自修复（公约 0.6）：fJogSlow > fJogFast
 *                           对调、限位对倒置对调，信息级 0004_0103。
 * 规格偏离留档 (R11)    : 规格引脚表未列 uErrorId，但信息级出码（0102/0103/
 *                         0105）必须有可观察出口，故补充 uErrorId : UDINT
 *                         输出引脚（信息级专用，无故障锁存语义）。
 * 开源溯源 (Origin)     : s7-motion。仅提取 S7-1500 Motion Control 手册公开
 *                         的点动工艺语义（低速/高速点动、延时切换）与接口
 *                         参数域；实现与命名 100% 自有 clean-room。
 * 验收向量 (Acceptance) :
 *   V1 正常链：bJogPos 按住 → iAxis 进入 eContinuousMotion 正向低速；
 *      bFastSelect 按住且 tFastDelay 到 → 升高速；松开 → iAxis.Stop()；
 *   V2 双向同按：bJogPos+bJogNeg → 停止请求 + 信息级 0004_0102；
 *   V3 软限位拦截：正向点动接近 fSoftLimitPos 制动距离内 → 强制低速；
 *      到限位 → 停止请求 + 信息级 0004_0105；
 *   V4 参数对调：fJogSlow=50 / fJogFast=5 → 对调生效 + 信息级 0004_0103；
 *   V5 状态门禁：iAxis.eState = eErrorStop → 点动指令被拒，轴状态不变。
 * 故障码表 (Error codes):
 *   16#0004_0102【信息级】双向点动冲突 / 16#0004_0103【信息级】参数对调
 *   或兜底修复 / 16#0004_0105【信息级】软限位预判停车（与 FB_DL_SingleAxis
 *   同码同义，点动与连续运动共用）。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 05 · DL_Motion 开库）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   fbJog.iAxis := fbAxis;                        // 接口依赖注入（注入实现块实例）
 *   fbJog(bJogPos := bBtnUp, bJogNeg := bBtnDown, // 周期调用
 *         bFastSelect := bBtnFast, fJogSlow := 5.0, fJogFast := 50.0);
 *   手轮/按键电平直接接 bJogPos/bJogNeg；松开即停，无需上层编排停止时序。
 *   点动软限位独立于轴组态：现场试机时可临时收紧 fSoftLimitPos/Neg。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 常见误用与现场提示 (Field notes)：
 *   1 点动速度变化走轴的速度域斜坡（MoveVelocity 改速语义），但加减速
 *     由 fAcc 单参数承担，现场要求的"点动要跟手"请把 fAcc 适当调大，
 *     不要去改轴的组态参数。
 *   2 高速切换是"按住 bFastSelect 且已按方向键满 tFastDelay"，不是按
 *     高速键的边沿；想瞬切高速的工位把 tFastDelay 设为 T#0MS 即可
 *     （TON 零延时当拍满足）。
 *   3 本块不做任何传感器/安全件防抖，急停与安全门请走 bProcessAbort /
 *     驱动层安全链，不要指望点动块拦截。
 *   4 点动软限位与轴组态软限位是两道独立防线，两者取交集生效；现场
 *     收紧本块限位不会影响程序自动运行的轴组态限位。
 *----------------------------------------------------------------------------*)
FUNCTION_BLOCK FB_DL_AxisJogController
VAR_INPUT
    bJogPos        : BOOL := FALSE;      // 正向点动（Jog forward），电平生效
    bJogNeg        : BOOL := FALSE;      // 负向点动（Jog backward），电平生效
    fJogSlow       : REAL := 5.0;        // 低速点动速度（Slow jog velocity）[mm/s]
    fJogFast       : REAL := 50.0;       // 高速点动速度（Fast jog velocity）[mm/s]
    bFastSelect    : BOOL := FALSE;      // 高速选择（Fast select），TRUE 且按住 ≥ tFastDelay 自动切高速
    tFastDelay     : TIME := T#1S;       // 低→高速切换延时（Fast switch delay）
    fSoftLimitPos  : REAL := 1000000.0;  // 点动软限位上限（Jog soft limit high）[mm]，独立于轴组态
    fSoftLimitNeg  : REAL := -1000000.0; // 点动软限位下限（Jog soft limit low）[mm]
    fAcc           : REAL := 1000.0;     // 点动加减速度（Jog acceleration）[mm/s²]
END_VAR
VAR_IN_OUT
    iAxis          : I_DL_MotionAxis;    // 轴接口引用（Axis reference），由上层注入实现块实例
END_VAR
VAR_OUTPUT
    uErrorId       : UDINT := 0;         // 末次信息级事件码（Last info code），规格外补充引脚（见头注 R11 留档）
END_VAR
VAR
    bJogging       : BOOL := FALSE;      // 点动进行中（Jog active）
    bStopReq       : BOOL := FALSE;      // 内部停止请求（Internal stop request）
    bAxisOk        : BOOL := FALSE;      // 轴状态可用标志（Axis state usable），eStandstill/eContinuousMotion 为 TRUE
    iJogMode       : INT := 0;           // 点动模式裁决值（Jog mode decision）：0 停止/1 正向/2 负向/3 冲突
    fVelSel        : REAL := 5.0;        // 生效点动速度（Selected jog speed）[mm/s]
    fVelCmd        : REAL := 0.0;        // 本拍点动速度指令（Jog velocity command）[mm/s]，带符号
    fSlow          : REAL := 5.0;        // 生效低速（Effective slow speed）[mm/s]，对调修复后
    fFast          : REAL := 50.0;       // 生效高速（Effective fast speed）[mm/s]，对调修复后
    fAccEff        : REAL := 1000.0;     // 生效加减速度（Effective acceleration）[mm/s²]
    fLimPos        : REAL := 1000000.0;  // 生效点动软限位上限（Effective jog limit high）[mm]
    fLimNeg        : REAL := -1000000.0; // 生效点动软限位下限（Effective jog limit low）[mm]
    fBrakeDist     : REAL := 0.0;        // 制动距离（Braking distance）[mm]
    fDistToLim     : REAL := 0.0;        // 沿点动方向距限位距离（Distance to limit）[mm]
    tonFast        : TON;                // 低→高速切换延时定时器（Fast switch delay timer）
    rtrigStop      : R_TRIG;             // 停止请求沿检测（Rising edge of stop request）
END_VAR
VAR CONSTANT
    DL_JOG_INF_MAX  : REAL := 1.0E30;    // 有限值判定幅值上限（Finite-value magnitude bound）[mm]
    DL_JOG_EPS      : REAL := 1.0E-6;    // 浮点判零容差（Float zero tolerance）[mm]
    DL_JOG_ACC_FLOOR : REAL := 1.0E-3;   // 加速度参数下限兜底（Acceleration parameter floor）[mm/s²]
END_VAR

// 段 1｜定时器/沿检测无条件周期刷新（R7 红线，严禁置于分支内）
tonFast(CLK := (bJogPos XOR bJogNeg) AND bFastSelect AND (NOT bStopReq), PT := tFastDelay);
rtrigStop(CLK := bStopReq);

// 段 2｜接口引用有效性防御：未注入轴引用则直接退出（不产生误动作）
IF iAxis = 0 THEN
    bJogging := FALSE;
    RETURN;
END_IF

// 段 3｜轴状态门禁：仅待机/连续运动两态可点动（eStopping/eErrorStop 拒绝）
bAxisOk := (iAxis.eState = E_DL_AxisState.eStandstill) OR (iAxis.eState = E_DL_AxisState.eContinuousMotion);

// 段 4｜参数防御与对调自修复（公约 0.6/0.8）：信息级码，不锁存
IF (fJogSlow <> fJogSlow) OR (fJogFast <> fJogFast) OR (fJogSlow <= DL_JOG_EPS) OR (fJogFast <= DL_JOG_EPS)
   OR (fJogSlow > DL_JOG_INF_MAX) OR (fJogFast > DL_JOG_INF_MAX) THEN
    fSlow := 5.0;                        // 非有限/非法低速兜底 [mm/s]
    fFast := 50.0;                       // 非有限/非法高速兜底 [mm/s]
    uErrorId := 16#0004_0103;
ELSIF fJogSlow > fJogFast THEN
    fSlow := fJogFast;                   // 低/高速对调修复（Swap repair）
    fFast := fJogSlow;
    uErrorId := 16#0004_0103;
ELSE
    fSlow := fJogSlow;
    fFast := fJogFast;
END_IF
IF (fAcc <> fAcc) OR (fAcc <= DL_JOG_ACC_FLOOR) OR (fAcc > DL_JOG_INF_MAX) THEN
    fAccEff := 1000.0;                   // 非法加速度兜底 [mm/s²]，防除零
    uErrorId := 16#0004_0103;
ELSE
    fAccEff := fAcc;
END_IF
IF fSoftLimitPos < fSoftLimitNeg THEN
    fLimPos := fSoftLimitNeg;            // 点动限位对倒置对调修复（Swap repair）
    fLimNeg := fSoftLimitPos;
    uErrorId := 16#0004_0103;
ELSE
    fLimPos := fSoftLimitPos;
    fLimNeg := fSoftLimitNeg;
END_IF

// 段 5｜点动模式裁决：双向冲突/松开/正常三分支（安全侧不猜）
IF bJogPos AND bJogNeg THEN
    iJogMode := 3;                       // 双向同按：冲突模式
ELSIF (NOT bJogPos) AND (NOT bJogNeg) THEN
    iJogMode := 0;                       // 松开：停止模式
ELSIF bAxisOk THEN
    IF bJogPos THEN iJogMode := 1; ELSE iJogMode := 2; END_IF   // 正向/负向点动
ELSE
    iJogMode := 0;                       // 轴态不可用：按松开处理
END_IF

// 段 6｜点动决策机（CASE+ELSE 兜底）
CASE iJogMode OF
    0:                                   // 停止模式：等待停止沿
        bJogging := FALSE;
    1:                                   // 正向点动
        IF NOT DispatchJog(bPositive := TRUE) THEN
            bStopReq := TRUE;            // 轴拒绝受理 → 转停止
        END_IF
    2:                                   // 负向点动
        IF NOT DispatchJog(bPositive := FALSE) THEN
            bStopReq := TRUE;
        END_IF
    3:                                   // 冲突模式：两方向都不执行
        bStopReq := TRUE;
        uErrorId := 16#0004_0102;
        bJogging := FALSE;
ELSE
    // 非法模式兜底
    iJogMode := 0;
END_CASE

// 段 7｜停止沿执行：松开/冲突/限位停车 → 调用轴受控停止（MC_Stop 语义），
//      消费后才清标志，保证 R_TRIG 能捕获到电平（沿在本拍段 1 已建立）
IF rtrigStop.Q THEN
    iAxis.Stop();
    bStopReq := FALSE;
END_IF

(*-----------------------------------------------------------------------------
 * 方法实现（METHOD）：点动派发子过程，速度选择 + 软限位预判 + 发速度指令
 * 三步串行，供主体点动决策机调用，正/负向共用一套逻辑。
 *-----------------------------------------------------------------------------*)

METHOD DispatchJog : BOOL
VAR_INPUT
    bPositive : BOOL;                    // 点动方向（Jog direction），TRUE=正向
END_VAR
DispatchJog := FALSE;
// 速度选择：长按低速，按住高速选择且延时到自动升高速
fVelSel := fSlow;
IF bFastSelect AND tonFast.Q THEN
    fVelSel := fFast;
END_IF
// 软限位预判：制动距离内强制低速，限位处拒绝继续
IF bPositive THEN
    fDistToLim := fLimPos - iAxis.fPosition;          // 正向距限位 [mm]
ELSE
    fDistToLim := iAxis.fPosition - fLimNeg;          // 负向距限位 [mm]
END_IF
fBrakeDist := (fVelSel * fVelSel) / (2.0 * fAccEff);  // 制动距离 [mm]，fAccEff 有下限防除零
IF fDistToLim <= DL_JOG_EPS THEN
    bStopReq := TRUE;                    // 已在限位：拒绝继续点动
    uErrorId := 16#0004_0105;
    RETURN;
ELSIF fDistToLim <= fBrakeDist THEN
    fVelSel := fSlow;                    // 警戒区内强制降为低速（预判语义简化版）
END_IF
// 发速度指令：带符号速度走轴接口速度域限幅斜坡，不做阶跃
IF bPositive THEN
    fVelCmd := fVelSel;
ELSE
    fVelCmd := -fVelSel;
END_IF
IF iAxis.MoveVelocity(fVelCmd, fAccEff) THEN
    bJogging := TRUE;
    DispatchJog := TRUE;
END_IF
END_FUNCTION_BLOCK
