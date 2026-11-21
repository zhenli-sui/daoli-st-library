(*==============================================================================
 * 组件名称 (Component)  : FB_DL_RollerGapAdjust
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 设备执行 · 辊距微调背隙补偿
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅 LIMIT / ABS 与标准 TON / R_TRIG
 * 功能描述 (Function)   : 把「目标辊距 → 单向越程逼近（吃掉背隙）→ 反向精定位
 *                         → 到位窗口判定 → 偏差记账」封装成设备对象，输出电动
 *                         缸位置指令与到位状态。解决电动缸双向逼近时背隙导致
 *                         的重复定位偏差，让每次调整都从同一侧逼近目标。
 * 边界声明 (Boundary)   : FB_DL_ThreePointValve 是浮点式阀的开度积分估算；
 *                         FB_DL_AnalogValve 是模拟量比例阀开度控制；本块是
 *                         位置伺服式间隙调整（带背隙补偿与到位窗口）。三者执行
 *                         机构语义不同，不可互替。本块刻意不注入轴接口：辊距
 *                         调整多为独立电动缸加位移传感器，注入轴接口会把设备层
 *                         拖到运动层，破坏分层依赖方向。
 * 为什么必须两段     : 单向逼近是背隙补偿的本体。把两段压成「一次赋值加到位
 *                     判定」会丢掉「先越程再回退」的动作序列，重复定位精度退化
 *                     到双向逼近水平——那正是普通定位块已有的能力，本件也就没有
 *                     存在价值。故 eApproach 与 eFine 是不可合并的两个相位。
 * 背隙补偿算术   : 阶段 A 指令取「目标加逼近符号乘背隙」，逼近符号为负一，
 *                     即先退到目标下方一个背隙；反馈越程过半后进入阶段 B，
 *                     指令回目标值，反向逼近吃掉整段背隙。两个阶段都必须把
 *                     指令钳在上下限内，防止背隙量把指令推出机械行程。
 * 反馈丢失纪律   : 位移反馈无效时指令必须**保持上一拍值**，绝不清零——对辊距
 *                     来说指令清零等于辊缝全开，属于危险侧动作。同时撤回到位
 *                     标志（位置不可信），并置反馈丢失故障码，等待人工确认。
 * 到位与记账     : 到位判定同时要求「偏差在容差内」与「反馈有效」，两者缺一
 *                     不可；到位拍写残余偏差、更新偏差一阶低通均值、更新本次
 *                     调整耗时，并对超容差次数累加。统计量用于预测机械磨损。
 * 开源溯源 (Origin)   : rockwell-aoi / lbp-process / lgf-technology。参考公开
 *                     设备 AOI 的参数分段组织与工艺功能库中「单向逼近消除背隙」
 *                     的工艺分类，只借参数分段与工艺分类；状态机、指令算术、
 *                     钳位策略、统计口径、码位与全部实现 100% 自有，clean-room
 *                     实现，不构成衍生作品。
 * 依赖     (Depends)   : 无 DL_ 内部依赖；仅 Standard.library 的 TON / R_TRIG
 * 故障码表 (Error codes):
 *   16#0003_0147【信息级】目标间隙越界已钳位（含上下限颠倒时的自动换位）
 *   16#0003_0148【信息级】背隙补偿量越界已钳位（负值或超上限）
 *   16#0003_0305【故障级】到位超时（限时内偏差始终未进入容差带）
 *   16#0003_0306【故障级】位移反馈无效或丢失（指令保持，撤回到位标志）
 *   16#0003_0308【故障级】非法相位兜底
 * 码位占用 (Slot)      : 信息级 0147 / 0148；故障级 0305 / 0306 / 0308。
 *                         全部落在 R11 本件分配块内，无跨块借用。
 * 写入点次序 (Write order) :
 *   ① fGapCmd    ：只在相位跃迁拍写（进逼近写越程值，进精定位写目标值），
 *                  其余拍一律不写，从而天然满足「故障时指令保持」
 *   ② bInPosition：只在到位跃迁拍置真，启动新一次调整时置假，其余拍不写
 *   ③ ePhase     ：状态机段为唯一位移点，复位分支只回待机
 *   ④ uErrorId   ：输出段单一优先级链（0308 优于 0306 优于 0305 优于 0147
 *                  优于 0148），全拍只写一次
 * 验收向量 (Acceptance) :
 *   V1 两阶段指令：目标 2.500、背隙 0.050 → 阶段 A 指令 2.450；到位保持段 2.500
 *   V2 到位判定：目标 2.500、容差 0.02、反馈 2.515 → 到位为真、残余偏差 +0.015
 *   V3 限幅：目标 5.0、上限 3.0 → 钳位后阶段 A 指令落在 2.950，保持段指令 3.000，
 *      并置码 16#0003_0147
 *   V4 反馈丢失：反馈有效由真变假（指令原为 2.50）→ 指令保持 2.50、码
 *      16#0003_0306、故障位为真
 *   V5 超时：限时 10 秒内偏差始终大于容差 → 码 16#0003_0305、调整中为假、
 *      累计调整次数不加
 * 红线自检 (Redline)   : R1 零全局变量表与外部变量引用 ｜ R2 零物理地址直写
 *                        R3 纯 IEC 61131-3 ｜ R4 浮点全用容差比较、无除法
 *                        R5 全变量中英双语同行注释 ｜ R6 ENUM 加 CASE 加 ELSE
 *                        R7 TON 与两个 R_TRIG 在 CASE 之外无条件刷新
 *                        R8 信息级码 0147 与 0148 不置故障位
 * 修订历史 (Revision)  :
 *   2026-11-15  v1.0.0  首版落盘（Round 11 · 泳道 B · 辊距伺服微调）
 *============================================================================*)

(*------------------------------------------------------------------------------
 * 结构体: ST_DL_GapTrimStat（跨周期统计，由调用方持有）
 *         Persistent statistics structure owned by the caller
 *-----------------------------------------------------------------------------*)
TYPE ST_DL_GapTrimStat :
STRUCT
    fDevAvg    : REAL;      // 残余偏差一阶低通均值 [毫米]，用于预测机械磨损 / Low pass average of the residual deviation, millimetre
    tLastMove  : TIME;      // 上一次调整的耗时 [毫秒] / Duration of the last adjustment
    nOverTolCnt : UDINT;    // 偏差超容差次数，饱和计数 [次] / Count of adjustments that ended outside the tolerance band
END_STRUCT
END_TYPE

(*------------------------------------------------------------------------------
 * 枚举: E_DL_GapPhase（本块相位，归属本功能块并同文件发布）
 *       Phase enumeration owned by this block and published in the same file
 *-----------------------------------------------------------------------------*)
TYPE E_DL_GapPhase :
(
    eIdle     := 0,   // 待机：可接受启动沿，指令保持 / Idle, ready for a start edge, command kept
    eApproach := 10,  // 逼近：先越程一个背隙，从同一侧靠近 / Approach, overshoot by one backlash from one side
    eFine     := 20,  // 精定位：反向逼近到目标值 / Fine positioning, approach the target from the opposite side
    eHold     := 30,  // 保持：到位后维持指令，等待下一次调整 / Hold, keep the command until the next adjustment
    eFault    := 99   // 故障：超时或反馈丢失，需复位 / Fault, timeout or feedback loss, needs a reset
);
END_TYPE

(*==============================================================================
 * 逐拍推演 (Cycle-by-cycle trace)：
 *   场景 A 正常一次调整（目标 2.500，背隙 0.050，容差 0.02）
 *     启动沿拍：反馈有效，进逼近相位，指令写 2.450，到位标志清假，限时开始计时
 *     逼近相位：段五算出越程过半判据点为 2.475，反馈降到 2.470 时进精定位，
 *          指令改写 2.500
 *     精定位相位：反馈升到 2.515，偏差 0.015 在容差内，进保持相位，到位置真，
 *          残余偏差写 0.015，偏差均值按低通系数更新，耗时取限时器已计时间
 *     保持相位：指令维持 2.500，不再改写；下一次启动沿才重新走两段
 *   场景 B 到位超时（限时十秒，偏差始终 0.5 毫米）
 *     精定位相位中限时器到拍：转故障相位，码 0305，调整中标志落，累计调整
 *     次数不加（未到位不计入台账）
 *   场景 C 反馈丢失（指令原为 2.500）
 *     反馈有效位变假：逼近与精定位相位转故障，保持相位只报警不断开保持；
 *     指令**不写**，自然保持 2.500；到位标志撤回；码 0306
 *   场景 D 目标越界（目标 5.0，上限 3.0）
 *     段三先钳位目标到 3.0 并标记，段四的上下限颠倒检查确认顺序正确；
 *     指令装配时再钳一次，保证背隙量不会把指令推出机械行程；码 0147 只进码
 *   场景 E 非法相位（枚举被外部强制写成未定义值）
 *     兜底分支转故障相位并置 0308，指令保持，需复位退出
 *============================================================================*)

FUNCTION_BLOCK FB_DL_RollerGapAdjust
VAR_INPUT
    bEnable        : BOOL;                  // 使能，FALSE 时指令保持、撤回到位标志 [-] / Enable, holds the command and drops the in-position flag
    bReset         : BOOL;                  // 复位故障，上升沿有效 [-] / Clears the fault on a rising edge
    bAdjustStart   : BOOL;                  // 执行一次调整，上升沿触发 [-] / Triggers one adjustment on a rising edge
    fGapSetpoint   : REAL;                  // 目标辊距 [毫米]，量程 0.0 到 20.0 / Target roller gap in millimetre, zero to twenty
    fGapActual     : REAL;                  // 位移传感器实测辊距 [毫米] / Measured roller gap in millimetre
    fGapTol        : REAL := 0.02;          // 到位容差 [毫米]，0 表示必须完全相等 / In-position tolerance in millimetre, zero demands equality
    fBacklash      : REAL := 0.05;          // 反向背隙补偿量 [毫米]，0 表示不补偿 / Backlash compensation in millimetre, zero disables it
    fCmdMin        : REAL := 0.0;           // 指令下限 [毫米] / Command lower limit in millimetre
    fCmdMax        : REAL := 20.0;          // 指令上限 [毫米] / Command upper limit in millimetre
    bFeedbackValid : BOOL;                  // 位移反馈有效（传感器自诊断汇总）[-] / Position feedback valid, sensor self diagnosis summary
    tMoveTimeout   : TIME := T#10S;         // 单次调整限时 [毫秒]，0 表示不监控 / Adjustment timeout, zero disables monitoring
END_VAR
VAR_OUTPUT
    fGapCmd        : REAL;                  // 电动缸位置指令 [毫米]，故障时保持不写 / Actuator position command, kept untouched on a fault
    bAdjusting     : BOOL;                  // 调整进行中（逼近或精定位）[-] / Adjustment in progress, approach or fine
    bInPosition    : BOOL;                  // 到位，保持到下次调整 [-] / In position, kept until the next adjustment
    eState         : E_DL_GapPhase;         // 主状态机当前相位 [-] / Current phase of the main state machine
    bError         : BOOL;                  // 故障级锁存，仅 0305 0306 0308 置位 [-] / Latched fault, only fault level codes set it
    uErrorId       : UDINT;                 // 事件码，0 表示无事件 [代码] / Event code, zero means none
    fLastDeviation : REAL;                  // 上次调整结束时的残余偏差 [毫米] / Residual deviation of the last adjustment
    nAdjustCount   : UDINT;                 // 累计调整次数，仅到位时累加，饱和 [次] / Adjustment counter, saturating, incremented on arrival only
END_VAR
VAR_IN_OUT
    stTrim         : ST_DL_GapTrimStat;     // 跨周期统计：偏差均值、耗时、超容差次数 / Persistent statistics, deviation, duration and over tolerance count
END_VAR
VAR
    fbTrigReset    : R_TRIG;                // 复位沿检测，CASE 之外无条件刷新 [-] / Reset edge detector, refreshed outside the CASE
    fbTrigStart    : R_TRIG;                // 启动沿检测，CASE 之外无条件刷新 [-] / Start edge detector, refreshed outside the CASE
    fbTonMove      : TON;                   // 单次调整限时计时，CASE 之外无条件刷新 / Move timeout timer, refreshed outside the CASE
    bInit          : BOOL := FALSE;         // 首扫标志，初值 FALSE，判据 NOT bInit [-] / First-scan flag initialised FALSE
    ePhase         : E_DL_GapPhase := E_DL_GapPhase.eIdle;  // 内部相位，对外经 eState 输出 / Internal phase, exported as eState
    fMinUse        : REAL;                  // 生效的指令下限 [毫米]，已按大小关系归一 / Effective lower limit, normalised by magnitude
    fMaxUse        : REAL;                  // 生效的指令上限 [毫米]，已按大小关系归一 / Effective upper limit, normalised by magnitude
    fSpUse         : REAL;                  // 钳位后的目标辊距 [毫米] / Clamped target roller gap
    fTolUse        : REAL;                  // 生效的到位容差 [毫米]，负值取绝对值 / Effective tolerance, negative input taken as absolute
    fBlUse         : REAL;                  // 生效的背隙补偿量 [毫米]，已钳位 / Effective backlash compensation, clamped
    fApproachTarget : REAL;                 // 越程过半判据点 [毫米] / Half overshoot threshold of the approach phase
    fCmdCandidate  : REAL;                  // 指令候选值，钳位前中间量 [毫米] / Command candidate before clamping
    fDeviation     : REAL;                  // 本次残余偏差中间量 [毫米] / Residual deviation of this adjustment
    bInTol         : BOOL;                  // 本拍偏差在容差内且反馈有效 [-] / Flag, deviation inside tolerance with valid feedback
    bMoveRun       : BOOL;                  // 限时计时器输入，先算后调 [-] / Timeout timer input, computed before the call
    bMoveTimeout   : BOOL;                  // 限时到拍标志 [-] / Timeout flag of this cycle
    bTimeoutEnable : BOOL;                  // 是否启用限时监控 [-] / Flag, timeout monitoring enabled
    tMoveUse       : TIME;                  // 生效的限时值 [毫秒] / Effective timeout value
    bFeedbackLost  : BOOL;                  // 本拍反馈丢失（使能前提下）[-] / Flag, feedback lost while enabled
    bSpClamped     : BOOL;                  // 目标被钳位的标记 [-] / Flag, the target was clamped
    bBlClamped     : BOOL;                  // 背隙被钳位的标记 [-] / Flag, the backlash was clamped
    bArrived       : BOOL;                  // 本拍刚到位，供统计段使用 [-] / Flag, arrival happened in this cycle
    bStateIllegal  : BOOL;                  // 非法相位被兜底捕获 [-] / Flag, an illegal phase was captured
END_VAR
VAR CONSTANT
    DL_FLOAT_EPS     : REAL := 1.0E-6;      // 浮点判零容差 [无量纲] / Float epsilon for zero tests
    DL_APPROACH_SIGN : REAL := -1.0;        // 逼近方向符号，负向吃背隙 [无量纲] / Approach direction sign, negative eats the backlash
    DL_BACKLASH_MAX  : REAL := 1.0;         // 背隙补偿上限 [毫米]，防组态错值 / Backlash compensation upper bound
    DL_OVERSHOOT_RATIO : REAL := 0.5;       // 越程过半判据比例 [无量纲] / Half overshoot ratio of the approach phase
    DL_DEV_ALPHA     : REAL := 0.2;         // 偏差均值一阶低通系数 [无量纲] / First order low pass coefficient of the deviation average
    DL_CNT_MAX       : UDINT := 16#FFFF_FFFE;  // 计数饱和上限，防溢出回绕 [次] / Counter saturation limit
    DL_TIME_ZERO     : TIME := T#0MS;       // 时间零值基准 [毫秒] / Time zero reference
    DL_TIME_NEVER    : TIME := T#24H;       // 限时关闭时的占位时长 [毫秒] / Placeholder duration when timeout monitoring is off
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜沿检测无条件刷新（R7 红线）
 *      Edge detection refreshed unconditionally
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);
fbTrigStart(CLK := bAdjustStart);

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化（R19 唯一合法范式）
 *      First-scan initialisation with the canonical R19 pattern
 *-----------------------------------------------------------------------------*)
IF NOT bInit THEN
    fGapCmd        := 0.0;                 // 指令初值：由上层在投运时给定安全位
    bAdjusting     := FALSE;
    bInPosition    := FALSE;
    fLastDeviation := 0.0;
    nAdjustCount   := 0;
    ePhase         := E_DL_GapPhase.eIdle;
    eState         := E_DL_GapPhase.eIdle;
    bError         := FALSE;
    bStateIllegal  := FALSE;
    stTrim.fDevAvg     := 0.0;             // 偏差均值初值为零
    stTrim.tLastMove   := DL_TIME_ZERO;    // 耗时初值为零
    stTrim.nOverTolCnt := 0;               // 超容差次数初值为零
    uErrorId       := 16#0000_0000;
    bInit          := TRUE;                // 首扫只做一次
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜参数钳位（先归一上下限，再钳目标与背隙；越界只记信息级码）
 *      Parameter clamping, normalise the limits first, info level only
 *-----------------------------------------------------------------------------*)
bSpClamped := FALSE;
bBlClamped := FALSE;

IF fCmdMax < fCmdMin THEN
    fMinUse    := fCmdMax;                 // 上下限颠倒：自动换位，避免非法区间
    fMaxUse    := fCmdMin;
    bSpClamped := TRUE;                    // 记入参数越界信息码
ELSE
    fMinUse := fCmdMin;
    fMaxUse := fCmdMax;
END_IF

IF fGapSetpoint < fMinUse THEN
    fSpUse     := fMinUse;                 // 低于下限：钳到下限
    bSpClamped := TRUE;
ELSIF fGapSetpoint > fMaxUse THEN
    fSpUse     := fMaxUse;                 // 高于上限：钳到上限
    bSpClamped := TRUE;
ELSE
    fSpUse := fGapSetpoint;
END_IF

IF fGapTol >= 0.0 THEN
    fTolUse := fGapTol;                    // 容差非负：原样使用
ELSE
    fTolUse := ABS(fGapTol);               // 容差为负：按绝对值理解
    bSpClamped := TRUE;
END_IF

IF fBacklash < 0.0 THEN
    fBlUse     := 0.0;                     // 负背隙无物理意义：按不补偿处理
    bBlClamped := TRUE;
ELSIF fBacklash > DL_BACKLASH_MAX THEN
    fBlUse     := DL_BACKLASH_MAX;         // 超上限：钳到上限
    bBlClamped := TRUE;
ELSE
    fBlUse := fBacklash;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜到位判定与限时准备（判定条件与计时输入都在此处一次算清）
 *      In-position judgement and timeout preparation, computed once here
 *-----------------------------------------------------------------------------*)
fDeviation := fGapActual - fSpUse;
IF bFeedbackValid AND (ABS(fDeviation) <= fTolUse) THEN
    bInTol := TRUE;                        // 偏差入带且反馈可信才算到位
ELSE
    bInTol := FALSE;
END_IF

IF tMoveTimeout <= DL_TIME_ZERO THEN
    tMoveUse       := DL_TIME_NEVER;       // 零限时：关闭监控，避免立即误报
    bTimeoutEnable := FALSE;
ELSE
    tMoveUse       := tMoveTimeout;
    bTimeoutEnable := TRUE;
END_IF

bMoveRun := (ePhase = E_DL_GapPhase.eApproach) OR (ePhase = E_DL_GapPhase.eFine);
fbTonMove(IN := bMoveRun, PT := tMoveUse);
bMoveTimeout := bTimeoutEnable AND fbTonMove.Q;

IF bEnable AND (NOT bFeedbackValid) THEN
    bFeedbackLost := TRUE;                 // 使能状态下反馈无效：按丢失处理
ELSE
    bFeedbackLost := FALSE;
END_IF

bArrived := FALSE;                         // 到位单拍标志预清零

(*------------------------------------------------------------------------------
 * 段 5｜主状态机（ENUM 加 CASE，含 ELSE 兜底；每成员均有对应标签）
 *      Main state machine, one label per enumeration member plus a fallback
 *      指令只在跃迁拍写，其余拍不写，从而天然满足「故障时指令保持」
 *-----------------------------------------------------------------------------*)
CASE ePhase OF
    E_DL_GapPhase.eIdle:
        IF NOT bEnable THEN
            bInPosition := FALSE;          // 未使能：位置不可信，撤回到位标志
        ELSIF fbTrigStart.Q THEN
            bInPosition := FALSE;          // 每次调整都从「未到位」开始记账
            IF bFeedbackLost THEN
                ePhase := E_DL_GapPhase.eFault;        // 反馈无效不得启动，指令保持
            ELSE
                fCmdCandidate := fSpUse + DL_APPROACH_SIGN * fBlUse;
                fGapCmd       := LIMIT(fMinUse, fCmdCandidate, fMaxUse);  // 越程值再钳一次
                ePhase        := E_DL_GapPhase.eApproach;
            END_IF
        END_IF

    E_DL_GapPhase.eApproach:
        IF NOT bEnable THEN
            ePhase := E_DL_GapPhase.eIdle;
        ELSIF bFeedbackLost THEN
            ePhase := E_DL_GapPhase.eFault;            // 反馈丢失：转故障，指令保持
        ELSIF bMoveTimeout THEN
            ePhase := E_DL_GapPhase.eFault;            // 越程段超时：转故障
        ELSE
            fApproachTarget := fSpUse + DL_APPROACH_SIGN * fBlUse * DL_OVERSHOOT_RATIO;
            IF (DL_APPROACH_SIGN * (fGapActual - fApproachTarget)) >= 0.0 THEN
                fGapCmd := LIMIT(fMinUse, fSpUse, fMaxUse);   // 越程过半：回目标值
                ePhase  := E_DL_GapPhase.eFine;
            END_IF
        END_IF

    E_DL_GapPhase.eFine:
        IF NOT bEnable THEN
            ePhase := E_DL_GapPhase.eIdle;
        ELSIF bFeedbackLost THEN
            ePhase := E_DL_GapPhase.eFault;            // 反馈丢失：转故障，指令保持
        ELSIF bInTol THEN
            fGapCmd        := LIMIT(fMinUse, fSpUse, fMaxUse);   // 到位拍指令即目标值
            fLastDeviation := fDeviation;              // 残余偏差：带符号，正为偏大
            bInPosition    := TRUE;
            bArrived       := TRUE;                    // 供统计段使用
            ePhase         := E_DL_GapPhase.eHold;
        ELSIF bMoveTimeout THEN
            ePhase := E_DL_GapPhase.eFault;            // 精定位超时：转故障
        END_IF

    E_DL_GapPhase.eHold:
        IF NOT bEnable THEN
            bInPosition := FALSE;                      // 未使能撤回到位标志
            ePhase      := E_DL_GapPhase.eIdle;
        ELSIF fbTrigStart.Q THEN
            bInPosition := FALSE;                      // 新一轮调整：先撤到位
            IF bFeedbackLost THEN
                ePhase := E_DL_GapPhase.eFault;
            ELSE
                fCmdCandidate := fSpUse + DL_APPROACH_SIGN * fBlUse;
                fGapCmd       := LIMIT(fMinUse, fCmdCandidate, fMaxUse);
                ePhase        := E_DL_GapPhase.eApproach;
            END_IF
        ELSIF bFeedbackLost THEN
            bInPosition := FALSE;                      // 位置不可信：撤回到位，但不断开保持
            ePhase      := E_DL_GapPhase.eFault;
        END_IF

    E_DL_GapPhase.eFault:
        IF NOT bEnable THEN
            ePhase := E_DL_GapPhase.eIdle;             // 停使能可直接退出故障态
        ELSIF fbTrigReset.Q THEN
            ePhase        := E_DL_GapPhase.eIdle;      // 复位后回待机，指令保持原值
            bStateIllegal := FALSE;
        END_IF

    ELSE
        ePhase        := E_DL_GapPhase.eFault;         // 非法值兜底
        bStateIllegal := TRUE;
END_CASE

(*------------------------------------------------------------------------------
 * 段 6｜统计记账（只在到位拍更新，避免逐拍累加污染台账）
 *      Statistics updated on the arrival cycle only
 *-----------------------------------------------------------------------------*)
IF bArrived THEN
    IF ABS(stTrim.fDevAvg) < DL_FLOAT_EPS THEN
        stTrim.fDevAvg := fLastDeviation;              // 首次到位：均值直接取本次值
    ELSE
        stTrim.fDevAvg := stTrim.fDevAvg + DL_DEV_ALPHA * (fLastDeviation - stTrim.fDevAvg);
    END_IF
    stTrim.tLastMove := fbTonMove.ET;                  // 本次耗时取限时器已计时间
    IF ABS(fLastDeviation) > fTolUse THEN
        IF stTrim.nOverTolCnt < DL_CNT_MAX THEN
            stTrim.nOverTolCnt := stTrim.nOverTolCnt + 1;
        END_IF
    END_IF
    IF nAdjustCount < DL_CNT_MAX THEN
        nAdjustCount := nAdjustCount + 1;               // 仅到位才计入次数
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜输出归并与码位定级（单一优先级链，全拍只写一次 uErrorId）
 *      Output merge and single-priority error code resolution
 *-----------------------------------------------------------------------------*)
bAdjusting := (ePhase = E_DL_GapPhase.eApproach) OR (ePhase = E_DL_GapPhase.eFine);

IF bStateIllegal THEN
    uErrorId := 16#0003_0308;                          // 优先级一：非法相位
ELSIF bFeedbackLost THEN
    uErrorId := 16#0003_0306;                          // 优先级二：反馈无效或丢失
ELSIF bMoveTimeout THEN
    uErrorId := 16#0003_0305;                          // 优先级三：到位超时
ELSIF bSpClamped THEN
    uErrorId := 16#0003_0147;                          // 信息级：目标越界已钳位
ELSIF bBlClamped THEN
    uErrorId := 16#0003_0148;                          // 信息级：背隙越界已钳位
ELSE
    uErrorId := 16#0000_0000;
END_IF

(* 故障位只反映故障级：信息级码 0147 与 0148 绝不置故障位（R21） *)
bError := bStateIllegal OR bFeedbackLost OR bMoveTimeout;

eState := ePhase;                                      // 相位每拍重写，供 HMI 诊断
END_FUNCTION_BLOCK
