(*==============================================================================
 * 组件名称 (Component)  : FB_DL_LineInterp2Axis
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.1
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 运动控制 · 两轴直线插补
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版）语法，
 *                         仅依赖 Standard.library（R_TRIG / SQRT / MIN / MAX / LIMIT）
 * 功能描述 (Function)   : 由起点、终点、合成速度与加速度生成两轴位置给定：单位向量分解、
 *                         单轴速度上限折算、梯形与三角速度曲线自适应、端点平滑减速、
 *                         暂停保持与故障保护。输出 X 与 Y 的位置给定、合成速度、完成度
 *                         与本次实际峰值速度。
 * 分层声明 (Layering)   : ① 本件只输出「位置给定」，不输出使能、回零与报警复位，也不直接
 *                         驱动物理轴——两轴的实际闭环由各自的单轴功能块承担，本件给出
 *                         给定值后由上层把给定接到单轴的相对或绝对运动接口；
 *                         ② 不读系统时钟、不读任务周期：插补时间增量由引脚注入，
 *                         保证结果可复现、跨平台一致；
 *                         ③ 不做圆弧与样条插补（属后续件），不做过象限与软限位判断
 *                         （软限位归运动层的软限位保护件）。
 * 周期纪律 (Cycle)      : 本件必须放在固定周期任务中调用，周期值通过标称周期引脚注入。
 *                         变周期任务（如带事件触发的任务）会直接造成速度与位置偏差，
 *                         因为时间增量按注入值推进、不按墙钟补偿。
 * 速度剖面 (Profile)    : 单侧加速度距离为合成速度平方除以两倍加速度；若两侧之和超过
 *                         路径总长则判为三角曲线，峰值速度降为「加速度乘路径长」的平方根，
 *                         加速距离取路径长的一半。临界相等（两侧之和恰等于路径长）按梯形
 *                         处理：此时峰值速度与期望合成速度相等，两种判法结果一致、不跳变。
 * 端点纪律 (Endpoint)   : 减速段出口强制把已走距离钳到路径总长，进度置 100，避免离散步长
 *                         越过终点导致给定超程；收尾速度保留峰值的若干比例，防止速度
 *                         指数衰减而出现「永远差最后一点」的爬行。
 * 开源溯源 (Origin)     : 来源标签 github-topics-motion。原创实现（参考 GitHub 运动控制与
 *                         结构化文本主题下开源运动库的共同形态：单位向量分解、合成速度
 *                         限幅、梯形与三角自适应三段结构；多份实现交叉印证其为社区共识
 *                         写法，非某一家独有）。速度剖面、临界判据、暂停策略、枚举、
 *                         状态机与全部码位 100% 本库独立设计，clean-room 实现，零代码行
 *                         复制。各上游仓库许可未逐条复核，按最严口径只借结构与参数域。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: R_TRIG / SQRT / MIN / MAX / LIMIT
 * 故障码表 (Error codes):
 *   16#0004_0109【信息级】路径长度为零，当拍直接完成，给定等于起点
 *   16#0004_010A【信息级】标称周期越界已钳到 0.1 毫秒至 1 秒
 *   16#0004_010B【信息级】单轴速度上限参与折算，合成速度已被压低
 *   16#0004_010C【信息级】路径过短，速度曲线降为三角（无匀速段）
 *   16#0004_0204【故障级】速度、加速度、单轴限速或最大路径长参数非法（锁存）
 *   16#0004_0205【故障级】路径长度超过允许上限（锁存）
 *   16#0004_0206【故障级】输入含非有限值（NaN 或无穷），前置拦截（锁存）
 *   16#0004_0207【故障级】非法状态兜底（锁存，终端安全态）
 * 码位占用 (Slot)       : 信息级 0109 / 010A / 010B / 010C；故障级 0204 / 0205 / 0206 / 0207。
 *                         全部落在 R12 本件分配块内，无跨块借用、无段外哨兵值。
 * 拍序纪律 (Cycle order) :
 *   ① ePhase    ：段 7 状态机（唯一位移点），段 8 复位分支是唯一回退点
 *   ② fS 与 fV  ：只在加速、匀速、减速三段内推进；暂停段速度归零且不推进位移
 *   ③ _bDone    ：进入准备相与进入完成相两处写，互斥不覆盖
 *   ④ uErrorId  ：段 9 单一优先级链，全拍只写一次
 * 验收向量 (Acceptance) :
 *   V1 梯形：起点 0 0、终点 300 400 → 路径 500；速度 100、加速度 200、单轴限速 1000 →
 *      合成 100 未被压低、单侧加速距离 25，两侧 50 小于 500 判梯形，峰值 100；
 *      中点给定为 150 与 200、完成度 50、合成速度 100
 *   V2 单轴限速：与 V1 同参但 X 轴限速改为 50 → 折算 83.333，合成速度被压到 83.333，
 *      X 分量 83.333 乘 0.6 等于 50，恰好不超限
 *   V3 零长度：起终点相同 → 当拍完成、给定等于起点、进度 100、码 0109
 *   V4 临界：路径 50、单侧加速距离 25 → 和为 50 恰等于路径长，判梯形，峰值 100
 *   V5 三角：路径 40 → 两侧 50 大于 40 判三角，峰值 89.44、单侧加速距离 20
 *   V6 参数非法：加速度为 0 → 故障位置位、码 0204、忙碌为假
 * 偏离留档 (Deviation)  :
 *   ① 规格未规定暂停时的时间补偿策略，本件按「不做补偿」实现：恢复后从当前速度重新加速，
 *      但时间增量仍按标称周期推进，故暂停不会造成位置瞬跳。若需要恒速衔接，应在工艺层
 *      用缓停而非暂停。
 *   ② 规格的减速段出口只要求钳位，本件额外把进度强制置 100，避免浮点除法在末拍给出
 *      99.9999 而让画面闪烁。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（R12 · 泳道 C · 两轴直线插补件）
 *   2026-11-15  v1.0.1  终审修复两处：
 *                       ① 暂停恢复时速度阶跃——加速段出口只看「位移到加速距离」，恢复后
 *                       该条件当拍即成立，再加速被整段跳过，速度由零直接跳到峰值；
 *                       改为位移与速度双条件，并在恢复时按剩余距离分流到减速段。
 *                       ② 零长度路径的完成度与头注释矛盾（注释写 100、出口被覆写为 0），
 *                       完成相下补满值分支
 *============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_LineInterpPhase（本块相位，归属本功能块并同文件发布）
 *       Phase enumeration owned by this block, one member per motion segment
 *-----------------------------------------------------------------------------*)
TYPE E_DL_LineInterpPhase :
(
    eIdle  := 0,   // 待机：等待启动沿，给定保持在起点 / Idle, waiting for the start edge
    ePrep  := 10,  // 准备：参数闸门、向量分解、速度剖面计算 / Preparation, the whole profile is computed here
    eAccel := 20,  // 加速：速度按加速度上升，位移按速度积分 / Acceleration segment
    eCruise:= 30,  // 匀速：速度保持峰值，位移按速度积分 / Constant speed segment
    eDecel := 40,  // 减速：速度按加速度下降，出口钳位到终点 / Deceleration segment
    eDone  := 50,  // 完成：完成标志保持，给定等于终点，等下一次启动 / Done, held until the next start
    eHeld  := 60,  // 暂停：速度归零、位移保持，恢复后重新加速 / Held, speed forced to zero
    eFault := 99   // 故障：参数或输入非法、路径超限、非法状态 / Fault, needs a reset to leave
);
END_TYPE

FUNCTION_BLOCK FB_DL_LineInterp2Axis
VAR_INPUT
    bEnable       : BOOL;                          // 使能，FALSE 时停止推进并回待机 [-] / Enable, stopping the move and returning to idle
    bReset        : BOOL;                          // 复位故障，上升沿有效 [-] / Rising edge clears the fault
    bStart        : BOOL;                          // 启动，上升沿有效（待机与完成态可受理）[-] / Rising edge starts the move in idle or done
    bHold         : BOOL;                          // 暂停，TRUE 时速度归零且位移保持 [-] / Pauses the interpolation while TRUE
    fStartX       : REAL;                          // 起点 X 坐标 [毫米] / Start X in millimetres
    fStartY       : REAL;                          // 起点 Y 坐标 [毫米] / Start Y in millimetres
    fEndX         : REAL;                          // 终点 X 坐标 [毫米] / End X in millimetres
    fEndY         : REAL;                          // 终点 Y 坐标 [毫米] / End Y in millimetres
    fPathSpeed    : REAL := 100.0;                 // 期望合成速度 [毫米每秒]，域大于 0 / Desired path speed, must exceed zero
    fAccel        : REAL := 500.0;                 // 加减速度 [毫米每二次方秒]，域大于 0 / Acceleration, must exceed zero
    fMaxSpeedX    : REAL := 1000.0;                // X 轴速度上限 [毫米每秒]，域大于 0 / X axis speed limit
    fMaxSpeedY    : REAL := 1000.0;                // Y 轴速度上限 [毫米每秒]，域大于 0 / Y axis speed limit
    fNominalCycle : REAL := 0.004;                 // 标称插补周期 [秒]，域 0.0001 到 1 / Nominal interpolation period
    fMaxPathLen   : REAL := 100000.0;              // 允许最大路径长度 [毫米]，域大于 0 / Maximum path length, must exceed zero
END_VAR
VAR_OUTPUT
    bBusy         : BOOL;                          // 插补进行中（含准备段）[-] / Interpolation running, preparation included
    bActive       : BOOL;                          // 位置给定有效（推进中或暂停中）[-] / Position command valid
    bDone         : BOOL;                          // 到达终点，保持到下一次启动 [-] / End reached, held until the next start
    fCmdX         : REAL;                          // X 位置给定 [毫米] / X position command
    fCmdY         : REAL;                          // Y 位置给定 [毫米] / Y position command
    fPathProgress : REAL;                          // 路径完成度 [百分之]，域 0 到 100 / Path progress in percent
    fPathVel      : REAL;                          // 当前合成速度 [毫米每秒] / Current path speed
    fPathLen      : REAL;                          // 本次路径总长 [毫米] / Total path length of this move
    fPeakVel      : REAL;                          // 本次实际峰值速度 [毫米每秒] / Effective peak speed of this move
    bError        : BOOL;                          // 故障级锁存，仅 0204 至 0207 置位 [-] / Latched fault, only fault level codes set it
    uErrorId      : UDINT;                         // 事件码，0 表示无事件 [代码] / Event code, zero means none
    eState        : E_DL_LineInterpPhase;          // 主状态机当前相位 [-] / Current phase of the main state machine
END_VAR
VAR
    fbTrigStart   : R_TRIG;                        // 启动沿检测，主周期无条件刷新 [-] / Start edge detector, refreshed unconditionally
    fbTrigReset   : R_TRIG;                        // 复位沿检测，主周期无条件刷新 [-] / Reset edge detector, refreshed unconditionally
    ePhase        : E_DL_LineInterpPhase := E_DL_LineInterpPhase.eIdle; // 内部相位，对外经 eState 输出 [-] / Internal phase exported as eState
    bInit         : BOOL := FALSE;                 // 首扫标志，初值 FALSE，判据取非 [-] / First-scan flag initialised FALSE
    bFaultLatch   : BOOL;                          // 故障锁存，仅复位分支清除 [-] / Fault latch, cleared by the reset path only
    uErrInt       : UDINT;                         // 故障级码寄存，锁存型 [代码] / Latched fault level code register
    uInfoCode     : UDINT;                         // 本拍信息级码，每拍重算 [代码] / Info level code recomputed every scan
    bDoneLatch    : BOOL;                          // 完成标志保持寄存器 [-] / Done hold register
    fDx           : REAL;                          // X 方向位移 [毫米] / X displacement
    fDy           : REAL;                          // Y 方向位移 [毫米] / Y displacement
    fLen          : REAL;                          // 路径长度 [毫米] / Path length
    fUx           : REAL;                          // X 单位向量分量 [无量纲] / X unit component
    fUy           : REAL;                          // Y 单位向量分量 [无量纲] / Y unit component
    fVEff         : REAL;                          // 生效合成速度 [毫米每秒] / Effective path speed
    fVLimit       : REAL;                          // 单轴限速折算后的合成速度上限 [毫米每秒] / Speed cap derived from axis limits
    fTmpX         : REAL;                          // X 轴限速折算中间量 [毫米每秒] / X cap temporary
    fTmpY         : REAL;                          // Y 轴限速折算中间量 [毫米每秒] / Y cap temporary
    fAccUse       : REAL;                          // 生效加速度 [毫米每二次方秒] / Effective acceleration
    fAccDist      : REAL;                          // 单侧加速距离 [毫米] / One-sided acceleration distance
    fPeak         : REAL;                          // 本次峰值速度 [毫米每秒] / Peak speed of this move
    fVDecelFloor  : REAL;                          // 收尾速度下限 [毫米每秒] / Deceleration speed floor
    fS            : REAL;                          // 当前已走路径位移 [毫米] / Travelled distance
    fV            : REAL;                          // 当前合成速度 [毫米每秒] / Current speed
    fDt           : REAL;                          // 本拍时间增量 [秒] / Time increment of this scan
    bTriangular   : BOOL;                          // 三角曲线标志（无匀速段）[-] / Triangular profile flag
    bNonFinite    : BOOL;                          // 输入含非有限值 [-] / At least one input is not finite
    bSpeedCapped  : BOOL;                          // 单轴限速参与了折算 [-] / An axis limit actually capped the speed
END_VAR
VAR CONSTANT
    DL_LEN_MIN    : REAL := 1.0E-6;                // 判零长度阈值 [毫米] / Zero length threshold
    DL_DT_MIN     : REAL := 1.0E-4;                // 最小插补周期 [秒] / Minimum interpolation period
    DL_DT_MAX     : REAL := 1.0;                   // 最大插补周期 [秒] / Maximum interpolation period
    DL_BIG        : REAL := 1.0E30;                // 非有限判定的大数阈值 [毫米] / Large value threshold for the finiteness test
    DL_DECEL_FLOOR: REAL := 0.05;                  // 收尾速度相对峰值的比例 [无量纲] / Deceleration floor as a fraction of the peak
    DL_PROGRESS_MAX : REAL := 100.0;               // 完成度满值 [百分之] / Full progress value
    DL_TWO        : REAL := 2.0;                   // 实数二，防魔数 [无量纲] / Real two used instead of a magic number
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出确定性默认值（单拍与派生标志每拍预清零，R25 第一律）
 *      Deterministic defaults first, derived flags pre-cleared every scan
 *-----------------------------------------------------------------------------*)
bBusy     := FALSE;                             // 忙碌标志预清零（Busy flag pre-cleared）
bActive   := FALSE;                             // 给定有效标志预清零（Command valid flag pre-cleared）
uInfoCode := 16#0000_0000;                      // 信息级码每拍重算（Info code recomputed every scan）
bNonFinite := FALSE;                            // 非有限标志预清零（Non-finite flag pre-cleared）
bSpeedCapped := FALSE;                          // 限速折算标志预清零（Speed cap flag pre-cleared）

(*------------------------------------------------------------------------------
 * 段 2｜沿检测无条件刷新（红线：实例在 CASE 之外每拍必刷）
 *      Edge detection refreshed unconditionally outside the CASE
 *-----------------------------------------------------------------------------*)
fbTrigStart(CLK := bStart);
fbTrigReset(CLK := bReset);

(*------------------------------------------------------------------------------
 * 段 3｜首扫初始化（唯一合法范式：初值 FALSE，判据取非）
 *      First-scan initialisation following the single legal pattern
 *-----------------------------------------------------------------------------*)
IF NOT bInit THEN
    fS           := 0.0;                        // 位移清零（Travelled distance cleared）
    fV           := 0.0;                        // 速度清零（Speed cleared）
    fUx          := 0.0;                        // X 单位向量清零（X unit component cleared）
    fUy          := 0.0;                        // Y 单位向量清零（Y unit component cleared）
    fLen         := 0.0;                        // 路径长清零（Path length cleared）
    fPeak        := 0.0;                        // 峰值速度清零（Peak speed cleared）
    fAccDist     := 0.0;                        // 加速距离清零（Acceleration distance cleared）
    fAccUse      := DL_TWO;                     // 生效加速度先给安全值（Effective acceleration pre-set to a safe value）
    fDt          := DL_DT_MIN;                  // 时间增量先给下限（Time increment pre-set to the lower bound）
    bTriangular  := FALSE;                      // 三角标志清零（Triangular flag cleared）
    bDoneLatch   := FALSE;                      // 完成保持标志清零（Done hold cleared）
    bFaultLatch  := FALSE;                      // 故障锁存清零（Fault latch cleared）
    uErrInt      := 16#0000_0000;               // 故障码清零（Fault code cleared）
    fPathLen     := 0.0;                        // 路径长出口清零（Path length outlet cleared）
    fPeakVel     := 0.0;                        // 峰值速度出口清零（Peak speed outlet cleared）
    fPathVel     := 0.0;                        // 当前速度出口清零（Current speed outlet cleared）
    fPathProgress:= 0.0;                        // 完成度出口清零（Progress outlet cleared）
    ePhase       := E_DL_LineInterpPhase.eIdle; // 相位复位为待机（Phase reset to idle）
    bInit        := TRUE;                       // 首扫只做一次（First scan runs once）
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜非有限输入前置拦截（NaN 用自身不等于自身判定，无穷用大数阈值判定）
 *      Finiteness gate, NaN by self comparison and infinity by a magnitude bound
 *-----------------------------------------------------------------------------*)
IF (fStartX <> fStartX) OR (fStartY <> fStartY) OR (fEndX <> fEndX) OR (fEndY <> fEndY) THEN
    bNonFinite := TRUE;                         // 坐标含 NaN（A coordinate is NaN）
END_IF
IF (fPathSpeed <> fPathSpeed) OR (fAccel <> fAccel) OR (fMaxSpeedX <> fMaxSpeedX) OR (fMaxSpeedY <> fMaxSpeedY) THEN
    bNonFinite := TRUE;                         // 速度或加速度含 NaN（A speed or acceleration is NaN）
END_IF
IF (ABS(fStartX) > DL_BIG) OR (ABS(fStartY) > DL_BIG) OR (ABS(fEndX) > DL_BIG) OR (ABS(fEndY) > DL_BIG) THEN
    bNonFinite := TRUE;                         // 坐标越出量级上限（A coordinate exceeds the magnitude bound）
END_IF
IF (ABS(fPathSpeed) > DL_BIG) OR (ABS(fAccel) > DL_BIG) OR (ABS(fNominalCycle) > DL_BIG) OR (ABS(fMaxPathLen) > DL_BIG) THEN
    bNonFinite := TRUE;                         // 参数越出量级上限（A parameter exceeds the magnitude bound）
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜标称周期钳位（越界只钳位并置信息级，不停机）
 *      Nominal period clamping with an informational code only
 *-----------------------------------------------------------------------------*)
IF fNominalCycle < DL_DT_MIN THEN
    fDt       := DL_DT_MIN;                     // 周期下限钳位（Clamped to the lower bound）
    uInfoCode := 16#0004_010A;                  // 010A 周期越界已钳位（Period clamped）
ELSIF fNominalCycle > DL_DT_MAX THEN
    fDt       := DL_DT_MAX;                     // 周期上限钳位（Clamped to the upper bound）
    uInfoCode := 16#0004_010A;                  // 010A 周期越界已钳位（Period clamped）
ELSE
    fDt       := fNominalCycle;                 // 合法周期直通（Valid period passed through）
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜使能撤销的最高优先级拦截（先于状态机，切断推进条件）
 *      Enable withdrawal is handled before the state machine
 *-----------------------------------------------------------------------------*)
IF NOT bEnable THEN
    fV := 0.0;                                  // 速度归零（Speed forced to zero）
    IF (ePhase = E_DL_LineInterpPhase.eAccel) OR (ePhase = E_DL_LineInterpPhase.eCruise) OR
       (ePhase = E_DL_LineInterpPhase.eDecel) OR (ePhase = E_DL_LineInterpPhase.eHeld) THEN
        ePhase := E_DL_LineInterpPhase.eIdle;   // 推进中掉使能：回待机（Disabled mid move, back to idle）
        fS     := 0.0;                          // 位移清零，避免下次启动带残留（Distance cleared）
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜主状态机（枚举每个成员均有标签，末尾 ELSE 兜底到终端安全态）
 *      Main state machine, one label per member plus a trailing ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE ePhase OF

    E_DL_LineInterpPhase.eIdle: // 待机：等启动沿，给定停在起点
        fS := 0.0;                              // 位移清零（Distance cleared）
        fV := 0.0;                              // 速度清零（Speed cleared）
        IF bFaultLatch THEN
            ePhase := E_DL_LineInterpPhase.eFault; // 参数已锁故障：进故障态（Gate failed, enter the fault state）
        ELSIF fbTrigStart.Q THEN
            bDoneLatch := FALSE;                // 新一次启动：清完成保持（A new start clears the done hold）
            ePhase     := E_DL_LineInterpPhase.ePrep; // 进准备相（Enter the preparation phase）
        END_IF

    E_DL_LineInterpPhase.ePrep: // 准备：闸门、向量分解、限幅折算、剖面判定
        IF bNonFinite THEN
            IF NOT bFaultLatch THEN
                bFaultLatch := TRUE;            // 锁故障，保留首出码（Latch the fault keeping the first code）
                uErrInt     := 16#0004_0206;    // 0206 输入非有限（Non-finite input）
            END_IF
            bDoneLatch := FALSE;                // 清完成保持（Done hold cleared）
            ePhase     := E_DL_LineInterpPhase.eFault; // 进故障态（Enter the fault state）
        ELSIF (fPathSpeed <= 0.0) OR (fAccel <= 0.0) OR (fMaxSpeedX <= 0.0) OR
              (fMaxSpeedY <= 0.0) OR (fMaxPathLen <= 0.0) THEN
            IF NOT bFaultLatch THEN
                bFaultLatch := TRUE;            // 锁故障（Latch the fault）
                uErrInt     := 16#0004_0204;    // 0204 运动参数非法（Illegal motion parameters）
            END_IF
            bDoneLatch := FALSE;                // 清完成保持（Done hold cleared）
            ePhase     := E_DL_LineInterpPhase.eFault; // 进故障态（Enter the fault state）
        ELSE
            fDx  := fEndX - fStartX;            // X 方向位移（X displacement）
            fDy  := fEndY - fStartY;            // Y 方向位移（Y displacement）
            fLen := SQRT((fDx * fDx) + (fDy * fDy)); // 路径长度（Path length）
            fPathLen := fLen;                   // 路径长出口（Path length outlet）
            IF fLen > fMaxPathLen THEN
                IF NOT bFaultLatch THEN
                    bFaultLatch := TRUE;        // 路径超限：锁故障（Path over the limit, latch a fault）
                    uErrInt     := 16#0004_0205; // 0205 路径超限（Path over the limit）
                END_IF
                bDoneLatch := FALSE;            // 清完成保持（Done hold cleared）
                ePhase     := E_DL_LineInterpPhase.eFault; // 进故障态（Enter the fault state）
            ELSIF fLen < DL_LEN_MIN THEN
                fUx        := 0.0;              // 零长度无单位向量（No unit vector for a zero length move）
                fUy        := 0.0;              // 零长度无单位向量（No unit vector for a zero length move）
                fS         := 0.0;              // 位移为零（No displacement）
                fV         := 0.0;              // 速度为零（No speed）
                fPeak      := 0.0;              // 峰值速度为零（No peak speed）
                bDoneLatch := TRUE;             // 当拍即完成（Completed within this scan）
                uInfoCode  := 16#0004_0109;     // 0109 零长度路径（Zero length path）
                ePhase     := E_DL_LineInterpPhase.eDone; // 直接进完成相（Jump to the done phase）
            ELSE
                fUx := fDx / fLen;              // X 单位向量，除数已过判零闸门（Unit vector, the divisor passed the gate）
                fUy := fDy / fLen;              // Y 单位向量，除数已过判零闸门（Unit vector, the divisor passed the gate）
                fAccUse := fAccel;              // 生效加速度（Effective acceleration）
                fVLimit := fPathSpeed;          // 先与期望合成速度取最小（Start from the desired speed）
                IF ABS(fUx) > DL_LEN_MIN THEN
                    fTmpX := fMaxSpeedX / ABS(fUx); // X 轴折算上限（X cap from the axis limit）
                    IF fTmpX < fVLimit THEN
                        fVLimit      := fTmpX;  // 取更小者（Keep the smaller cap）
                        bSpeedCapped := TRUE;   // 记录限速生效（Record that a cap applied）
                    END_IF
                END_IF
                IF ABS(fUy) > DL_LEN_MIN THEN
                    fTmpY := fMaxSpeedY / ABS(fUy); // Y 轴折算上限（Y cap from the axis limit）
                    IF fTmpY < fVLimit THEN
                        fVLimit      := fTmpY;  // 取更小者（Keep the smaller cap）
                        bSpeedCapped := TRUE;   // 记录限速生效（Record that a cap applied）
                    END_IF
                END_IF
                fVEff     := fVLimit;           // 生效合成速度（Effective path speed）
                fAccDist  := (fVEff * fVEff) / (DL_TWO * fAccUse); // 单侧加速距离（One-sided acceleration distance）
                IF (DL_TWO * fAccDist) > fLen THEN
                    bTriangular := TRUE;        // 两侧之和超过全长：三角曲线（Sum exceeds the path, triangular）
                    fPeak     := SQRT(fAccUse * fLen); // 三角峰值速度（Triangular peak speed）
                    fAccDist  := fLen * 0.5;    // 加速距离取一半（Half of the path）
                    uInfoCode := 16#0004_010C;  // 010C 三角曲线生效（Triangular profile in effect）
                ELSE
                    bTriangular := FALSE;       // 两侧之和不超过全长：梯形曲线（Trapezoidal profile）
                    fPeak       := fVEff;       // 峰值即生效合成速度（Peak equals the effective speed）
                    IF bSpeedCapped THEN
                        uInfoCode := 16#0004_010B; // 010B 单轴限速参与折算（An axis limit capped the speed）
                    END_IF
                END_IF
                fVDecelFloor := fPeak * DL_DECEL_FLOOR; // 收尾速度下限（Deceleration floor）
                fPeakVel     := fPeak;          // 峰值速度出口（Peak speed outlet）
                fS           := 0.0;            // 位移从零起算（Distance starts at zero）
                fV           := 0.0;            // 速度从零起算（Speed starts at zero）
                ePhase       := E_DL_LineInterpPhase.eAccel; // 进加速段（Enter the acceleration segment）
            END_IF
        END_IF

    E_DL_LineInterpPhase.eAccel: // 加速段：速度上升，位移积分
        IF bHold THEN
            fV     := 0.0;                      // 暂停：速度归零（Hold, speed forced to zero）
            ePhase := E_DL_LineInterpPhase.eHeld; // 进暂停相（Enter the held phase）
        ELSE
            fV := MIN(fPeak, fV + (fAccUse * fDt)); // 速度斜坡上升（Ramp the speed up）
            fS := fS + (fV * fDt);              // 位移按速度积分（Integrate the distance）
            (* 出口双条件：位移到加速距离且速度确实升到峰值——暂停恢复后必然满足前者，
               只看位移会当拍跳进匀速段、速度从零直接跳到峰值，故必须同时校验速度 *)
            (* Both conditions are required, otherwise a resume skips the ramp and steps the speed *)
            IF (fS >= fAccDist) AND (fV >= fPeak) THEN
                IF bTriangular THEN
                    ePhase := E_DL_LineInterpPhase.eDecel; // 三角曲线无匀速段（No cruise segment）
                ELSE
                    ePhase := E_DL_LineInterpPhase.eCruise; // 梯形曲线进匀速段（Enter the cruise segment）
                END_IF
            END_IF
        END_IF

    E_DL_LineInterpPhase.eCruise: // 匀速段：速度保持峰值
        IF bHold THEN
            fV     := 0.0;                      // 暂停：速度归零（Hold, speed forced to zero）
            ePhase := E_DL_LineInterpPhase.eHeld; // 进暂停相（Enter the held phase）
        ELSE
            fV := fPeak;                        // 速度保持峰值（Keep the peak speed）
            fS := fS + (fV * fDt);              // 位移按速度积分（Integrate the distance）
            IF fS >= (fLen - fAccDist) THEN
                ePhase := E_DL_LineInterpPhase.eDecel; // 到达减速点（Reach the deceleration point）
            END_IF
        END_IF

    E_DL_LineInterpPhase.eDecel: // 减速段：速度下降到收尾下限，出口钳位到终点
        IF bHold THEN
            fV     := 0.0;                      // 暂停：速度归零（Hold, speed forced to zero）
            ePhase := E_DL_LineInterpPhase.eHeld; // 进暂停相（Enter the held phase）
        ELSE
            fV := MAX(fVDecelFloor, fV - (fAccUse * fDt)); // 速度斜坡下降，保留收尾速度（Ramp down keeping the floor）
            fS := fS + (fV * fDt);              // 位移按速度积分（Integrate the distance）
            IF fS >= fLen THEN
                fS          := fLen;            // 出口钳位，防离散步长超程（Clamp at the end point）
                fV          := 0.0;             // 到位速度归零（Speed zeroed at the end）
                bDoneLatch  := TRUE;            // 完成标志保持（Done hold set）
                fPathProgress := DL_PROGRESS_MAX; // 完成度满值（Progress forced to full）
                ePhase      := E_DL_LineInterpPhase.eDone; // 进完成相（Enter the done phase）
            END_IF
        END_IF

    E_DL_LineInterpPhase.eDone: // 完成：给定等于终点，等下一次启动
        fS          := fLen;                    // 位移停在终点（Distance parked at the end）
        fV          := 0.0;                     // 速度为零（Speed zeroed）
        bDoneLatch  := TRUE;                    // 完成标志保持（Done hold kept）
        fPathProgress := DL_PROGRESS_MAX;       // 完成度满值（Progress full）
        IF fbTrigStart.Q THEN
            bDoneLatch := FALSE;                // 新一次启动：清完成保持（A new start clears the done hold）
            ePhase     := E_DL_LineInterpPhase.ePrep; // 回准备相（Back to preparation）
        END_IF

    E_DL_LineInterpPhase.eHeld: // 暂停：位移保持，恢复后从零速重新加速
        fV := 0.0;                              // 暂停期速度恒为零（Speed stays zero while held）
        IF NOT bHold THEN
            IF (fLen - fS) <= fAccDist THEN
                ePhase := E_DL_LineInterpPhase.eDecel; // 剩余距离已落在减速窗内：直接进减速段，不从零速再加速冲过终点
            ELSE
                ePhase := E_DL_LineInterpPhase.eAccel; // 恢复：从当前位移重新加速（Resume by accelerating from the current distance）
            END_IF
        END_IF

    E_DL_LineInterpPhase.eFault: // 故障：给定保持，等复位沿
        fV := 0.0;                              // 故障期速度为零（Speed zeroed during a fault）

    ELSE
        bFaultLatch := TRUE;                    // 非法状态兜底锁存（Illegal state latched）
        uErrInt     := 16#0004_0207;            // 0207 非法状态兜底（Illegal state fallback code）
        fV          := 0.0;                     // 速度归零（Speed zeroed）
        ePhase      := E_DL_LineInterpPhase.eFault; // 进终端安全态（Enter the terminal safe state）
END_CASE

(*------------------------------------------------------------------------------
 * 段 8｜复位（清故障与完成保持，位移保留供画面诊断）
 *      Reset clears the fault and the done hold, the distance is kept for diagnostics
 *-----------------------------------------------------------------------------*)
IF fbTrigReset.Q THEN
    bFaultLatch := FALSE;                       // 清故障锁存（Clear the fault latch）
    uErrInt     := 16#0000_0000;                // 清故障码（Clear the fault code）
    bDoneLatch  := FALSE;                       // 清完成保持（Clear the done hold）
    fV          := 0.0;                         // 速度归零（Speed zeroed）
    IF (ePhase = E_DL_LineInterpPhase.eFault) THEN
        ePhase := E_DL_LineInterpPhase.eIdle;   // 故障态复位回待机（Fault returns to idle）
        fS     := 0.0;                          // 回待机时位移清零（Distance cleared in idle）
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜给定与派生出口（位置给定按单位向量乘位移，完成度按位移比路径长）
 *      Command and derived outlet mapping
 *-----------------------------------------------------------------------------*)
fCmdX := fStartX + (fUx * fS);                  // X 位置给定（X position command）
fCmdY := fStartY + (fUy * fS);                  // Y 位置给定（Y position command）
IF fLen > DL_LEN_MIN THEN
    fPathProgress := LIMIT(0.0, (fS / fLen) * DL_PROGRESS_MAX, DL_PROGRESS_MAX); // 完成度钳位在 0 到 100（Clamped progress）
ELSIF ePhase = E_DL_LineInterpPhase.eDone THEN
    fPathProgress := DL_PROGRESS_MAX;           // 零长度路径已到达终点：完成度为满值，与完成相口径一致（Zero length already done, full progress）
ELSE
    fPathProgress := 0.0;                       // 其余零长度相位不给百分比，避免除零（No percentage elsewhere, avoids a division by zero）
END_IF
IF (ePhase = E_DL_LineInterpPhase.eAccel) OR (ePhase = E_DL_LineInterpPhase.eCruise) OR (ePhase = E_DL_LineInterpPhase.eDecel) THEN
    bActive   := TRUE;                          // 推进中：给定有效（Moving, the command is valid）
    bBusy     := TRUE;                          // 推进中：忙碌为真（Moving, busy is true）
    fPathVel  := fV;                            // 当前合成速度出口（Current path speed outlet）
ELSIF ePhase = E_DL_LineInterpPhase.eHeld THEN
    bActive   := TRUE;                          // 暂停中：给定仍有效（Held, the command is still valid）
    bBusy     := TRUE;                          // 暂停中：仍算任务未结束（Held, the job is not finished）
    fPathVel  := 0.0;                           // 暂停中合成速度为零（Path speed is zero while held）
ELSIF ePhase = E_DL_LineInterpPhase.ePrep THEN
    bActive   := FALSE;                         // 准备中尚无有效给定（No valid command during preparation）
    bBusy     := TRUE;                          // 准备中算忙碌（Preparation counts as busy）
    fPathVel  := 0.0;                           // 准备中速度为零（Speed is zero during preparation）
ELSE
    bActive   := FALSE;                         // 其余相位无有效给定（No valid command elsewhere）
    fPathVel  := 0.0;                           // 其余相位速度为零（Speed is zero elsewhere）
END_IF
bDone  := bDoneLatch;                           // 完成标志出口（Done outlet）
eState := ePhase;                               // 相位出口（Phase outlet）
bError := bFaultLatch;                          // 故障位只反映故障级锁存（Fault bit reflects the latch only）
IF bError THEN
    uErrorId := uErrInt;                        // 故障级码优先透出（Fault level code has priority）
ELSE
    uErrorId := uInfoCode;                      // 无故障透出本拍信息级码（Info code exposed otherwise）
END_IF
END_FUNCTION_BLOCK
