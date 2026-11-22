(*==============================================================================
 * 组件名称 (Component)  : FB_DL_RampSoakProfile
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / MIN / MAX / ABS），
 *                         零厂商方言
 * 功能描述 (Function)   : 多段 Ramp/Soak 程序曲线发生器（设定源型核心件）。
 *                         段数 N 可配（1..16），每段目标值 + 斜坡时间 + 保温
 *                         时间；斜坡按"段内等步长线性插值"逐拍逼近段目标，
 *                         到达后按保温时间保温，段号递推，末段完成输出完成
 *                         标志。支持暂停/跳段/外部保持/循环运行/跟踪回投。
 *                         作为温控区设定源，烘箱/烧结炉/化成工步共用。
 * 设计要点 (Key notes)  : ① 斜坡插值逐拍复算口径：fSetpoint 每拍增量
 *                           fStep = (fTgtEff − fRampStart) × fDt / fRampTimeSec
 *                           （fRampStart=本段斜坡起点值，fDt=tSampleTime 折算
 *                           秒；量纲推导：[EU]×[s]/[s] = [EU]，R20）；到达判定
 *                           为剩余距离 ≤ |fStep| + 容差，到达拍直接贴上目标，
 *                           保证逐拍数值可复算（验收向量 V1）；
 *                         ② 保温计时自实现时间戳累积（fSoakElapsed += fDt），
 *                           不用 TON——因 bHold 需"冻结计时"语义，TON 无保持
 *                           冻结能力（头注释声明自实现理由）；时间判定带
 *                           1E-4 s 容差，防浮点累计误差卡段；
 *                         ③ 保持（bHold 电平）：冻结设定值积分与段内计时，
 *                           不改变段号，释放后从冻结点继续；
 *                         ④ 跳段（bSkipSeg 上升沿）：当前段立即结束，斜坡
 *                           起点=当前值，段号+1；末段跳段 → 直接完成并置
 *                           信息级 0002_0110；
 *                         ⑤ 跟踪（R19）：bTrack 优先级高于首扫与运行，判据
 *                           唯一合法范式 IF bTrack OR (NOT bInit)；同步
 *                           fSetpoint 与 fRampStart 为跟踪值，释放后从当前值
 *                           继续本段（中途跟踪不锁死，V4 必测）；
 *                         ⑥ 循环（bLoopProfile）：末段完成后段号回 1、斜坡
 *                           起点=当前值，不回空闲；
 *                         ⑦ 零斜坡段（aRampTime=0）：从当前值阶跃直达该段
 *                           目标并置信息级 0002_0112，保温照常执行。
 * 本文件内含       : TYPE  E_DL_RampSoakPhase（配套枚举，归属 DL_Algo）
 *                    FB    FB_DL_RampSoakProfile
 * 开源溯源 (Origin)     : 原创实现。算法思想源自通用程序曲线（Ramp/Soak）工艺
 *                         语义与 IEC 61131-3 周期安全约定，clean-room，
 *                         未参考任何厂商私有库源码行。
 * 验收向量 (Acceptance) :
 *   V1 三段逐拍复算：tSampleTime=T#100MS；段1 目标100/斜坡T#1S/保温T#2S，
 *      段2 目标50/斜坡T#500MS/保温T#0，段3 目标80/斜坡T#1S/保温T#1S，
 *      fStartValue=0 → 段1 每拍+10.0 共 10 拍到 100，保温 20 拍；段2 每拍
 *      -10.0 共 5 拍到 50，零保温直通；段3 每拍+3.0 共 10 拍到 80，保温
 *      10 拍后 bDone=TRUE；bSegChange 在段1→2、段2→3 各单发一拍；
 *   V2 保持冻结：eRamp/eSoak 中 bHold=TRUE → fSetpoint 与段内计时冻结，
 *      释放后从冻结点继续，终值不受影响；
 *   V3 跳段：段2 保温中 bSkipSeg 单脉冲 → 立即进段3（斜坡起点=当前值）；
 *      末段跳段 → bDone + 信息级 0002_0110；
 *   V4 中途跟踪：eRamp 中 bTrack 单拍（fTrackValue=60）→ fSetpoint=60 且
 *      fRampStart=60，释放后从 60 继续本段斜坡，不锁死（R19 必测）；
 *   V5 循环：bLoopProfile=TRUE → 末段完成后段号回 1 从当前值重启；
 *   V6 非有限值目标：aTarget[2] 注入 NaN → 0002_1810 锁存进故障态，该段
 *      目标取前段目标兜底，仅 bReset 清；
 *   V7 零斜坡阶跃：aRampTime[1]=T#0 → 启动拍阶跃直达段1目标 + 0002_1803。
 * 故障码表 (Error codes)【终审裁定：划独立族段 18xx（程序曲线族）——原分配
 *   0110~0113 落在 01xx PID 族段、0220 落在 02xx 串级族段，族段语义冲突，
 *   已归位重排，语义不变】:
 *   16#0002_1810【故障级】段目标非有限值（锁存进故障态，仅 bReset 清）；
 *   16#0002_1801【信息级】末段跳段完成；16#0002_1802【信息级】段数钳位；
 *   16#0002_1803【信息级】零斜坡阶跃直达；16#0002_1804【信息级】采样周期
 *   钳位；16#0002_0005【故障级】非法状态兜底（DL_Algo 公共码，与
 *   FB_DL_RampGenerator 同码同义，复用留档）。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 06 · DL_Algo 程序曲线族）
 *   2026-11-15  v1.0.1  终审故障码族段归位：0110~0113/0220 → 1801~1804/1810
 *                       （划独立族段 18xx 程序曲线族，避开 01xx PID / 02xx
 *                       串级既有族段占位；DL_Algo/VERSION.md 族段口径已同
 *                       步修正）。语义零变更，引脚契约零变更。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_RampSoakPhase（归属 DL_Algo，与 FB_DL_RampSoakProfile 同文件）
 * 含义: 程序曲线段内相位状态。编号显式、间隔 10 预留扩展位，eFault 末位。
 *----------------------------------------------------------------------------*)
{attribute 'strict'}
{attribute 'qualified_only'}
TYPE E_DL_RampSoakPhase :
(
    eIdle  := 0,    // 空闲：未启动，设定值保持 / Idle: not started, setpoint held
    eRamp  := 10,   // 斜坡：按段内等步长逼近本段目标 / Ramp: linear step-wise approach to segment target
    eSoak  := 20,   // 保温：本段目标恒温保持计时 / Soak: dwell timer at segment target
    eDone  := 30,   // 完成：全部段执行完毕 / Done: all segments completed
    eFault := 99    // 故障：非法目标/非法状态锁存，仅复位退出 / Fault: latched, only reset can leave
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_RampSoakProfile
VAR_INPUT
    tSampleTime  : TIME := T#100MS;     // 采样周期（Sample time），默认 T#100MS，<T#10MS 钳位并置码（公约 0.5 显式引脚）
    aTarget      : ARRAY[1..16] OF REAL := [16(0.0)]; // 各段目标值（Segment targets）[EU]，量纲由调用方工艺定义
    aRampTime    : ARRAY[1..16] OF TIME; // 各段斜坡时间（Segment ramp times），0=从当前值阶跃直达该段目标（信息级）
    aSoakTime    : ARRAY[1..16] OF TIME; // 各段保温时间（Segment soak times），0=该段无保温直达下段
    nSegCount    : USINT := 1;          // 有效段数（Active segment count）1..16，越界钳位至 1 并置码
    fStartValue  : REAL := 0.0;         // 启动基准值（Start value）[EU]，首段斜坡起点
    bStart       : BOOL := FALSE;       // 启动指令（Profile start），上升沿生效
    bHold        : BOOL := FALSE;       // 外部保持（External hold），电平生效：冻结当前值与段内计时（含暂停语义）
    bSkipSeg     : BOOL := FALSE;       // 跳段指令（Skip segment），上升沿生效：当前段立即结束进入下段
    bTrack       : BOOL := FALSE;       // 跟踪使能（Track enable），TRUE 时设定值跟随跟踪值（R19，运行中途插入必测）
    fTrackValue  : REAL := 0.0;         // 跟踪值（Track value）[EU]，温控区实际温度回同步（无扰重启）
    bLoopProfile : BOOL := FALSE;       // 循环运行（Loop profile），TRUE=末段完成后自动从段 1 重启（斜坡起点=当前值）
    bReset       : BOOL := FALSE;       // 复位（Reset），上升沿复位故障并回空闲
END_VAR
VAR_OUTPUT
    fSetpoint    : REAL := 0.0;         // 程序设定值输出（Profile setpoint）[EU] → 温控区设定源，量纲=EU（R20）
    nSegAct      : USINT := 0;          // 当前段号（Active segment）1..nSegCount，0=未启动
    ePhase       : E_DL_RampSoakPhase := E_DL_RampSoakPhase.eIdle; // 段内相位（Phase），HMI 显示用
    bSegChange   : BOOL := FALSE;       // 段切换沿单发（Segment change edge），TRUE 持续一拍
    bDone        : BOOL := FALSE;       // 全部段完成（Profile done），完成态保持至重启/复位
    uErrorId     : UDINT := 0;          // 末次事件码（Last error code），段位 16#0002_xxxx
END_VAR
VAR
    bInit        : BOOL := FALSE;       // 首扫标志（First-scan flag，R19 范式配套）
    nSegEff      : USINT := 1;          // 生效段数（Effective segment count）[段]，钳位 [1,16]
    fDt          : REAL := 0.1;         // 生效采样周期（Effective sample time）[s]，TIME 折算
    fRampStart   : REAL := 0.0;         // 本段斜坡起点值（Segment ramp start value）[EU]
    fTgtEff      : REAL := 0.0;         // 本段生效目标值（Effective segment target）[EU]，非有限值兜底后
    fTgtPrev     : REAL := 0.0;         // 前段目标快照（Previous segment target）[EU]，非有限目标兜底来源
    fRampSec     : REAL := 0.0;         // 本段斜坡时间（Segment ramp time）[s]，TIME 折算
    fSoakSec     : REAL := 0.0;         // 本段保温时间（Segment soak time）[s]，TIME 折算
    fSoakElapsed : REAL := 0.0;         // 保温已耗时（Soak elapsed time）[s]，自实现时间戳累积
    fStep        : REAL := 0.0;         // 本拍斜坡增量（Ramp step per scan）[EU]，= (目标−起点)×fDt/斜坡秒
    rtrigStart   : R_TRIG;              // 启动指令上升沿（Rising edge of profile start）
    rtrigSkip    : R_TRIG;              // 跳段指令上升沿（Rising edge of skip segment）
    rtrigReset   : R_TRIG;              // 复位指令上升沿（Rising edge of reset）
END_VAR
VAR CONSTANT
    DL_RS_INF_MAX : REAL := 1.0E30;     // 有限值判定幅值上限（Finite-value magnitude bound）[EU]
    DL_RS_EPS     : REAL := 1.0E-6;     // 到达判定容差（Arrival tolerance）[EU]，浮点差值比较
    DL_RS_TEPS    : REAL := 1.0E-4;     // 保温计时判定容差（Soak timer tolerance）[s]，防浮点累计卡段
    DL_RS_TMIN    : REAL := 1.0E-3;     // 有效斜坡时间下限（Effective ramp time floor）[s]，低于视为零斜坡阶跃
END_VAR

METHOD NextSegOrDone
VAR_INPUT
END_VAR
IF fSoakSec > DL_RS_TEPS THEN
    fSoakElapsed := 0.0;                 // 本段有保温：进入保温计时 [s]
    ePhase := E_DL_RampSoakPhase.eSoak;
ELSIF nSegAct < nSegEff THEN
    nSegAct := nSegAct + 1;              // 无保温直通下段 [段]
    bSegChange := TRUE;                  // 段切换沿单发
    fRampStart := fSetpoint;             // 下段斜坡起点=当前值 [EU]
    fSoakElapsed := 0.0;                 // 新段保温计时清零 [s]
    ePhase := E_DL_RampSoakPhase.eRamp;
ELSIF bLoopProfile THEN
    nSegAct := 1;                        // 循环运行：段号回 1 [段]
    bSegChange := TRUE;                  // 段切换沿单发
    fRampStart := fSetpoint;             // 循环重启斜坡起点=当前值 [EU]
    fSoakElapsed := 0.0;                 // 新段保温计时清零 [s]
    ePhase := E_DL_RampSoakPhase.eRamp;
ELSE
    ePhase := E_DL_RampSoakPhase.eDone;  // 全部段完成
    bDone := TRUE;
END_IF
    END_METHOD

// 段 1｜沿检测无条件周期刷新（R7 红线，严禁置于分支内）
rtrigStart(CLK := bStart);
rtrigSkip(CLK := bSkipSeg);
rtrigReset(CLK := bReset);

// 段 2｜瞬时码与单发沿清零（R15：瞬时码逐拍重算，锁存码随故障态驻留）
bSegChange := FALSE;                     // 段切换沿单发：本拍默认无切换
IF ePhase <> E_DL_RampSoakPhase.eFault THEN
    uErrorId := 0;                       // 瞬时信息码逐拍重算；故障态码锁存不清
END_IF

// 段 3｜公共参数处理（公约 0.5/0.6/0.8）：周期钳位、段数钳位
IF tSampleTime < T#10MS THEN
    fDt := 0.010;                        // 非法周期钳位为 10ms [s]
    uErrorId := 16#0002_1804;            // 信息级：采样周期钳位
ELSE
    fDt := TIME_TO_REAL(tSampleTime) / 1000.0;  // 合法周期换算 [s]
END_IF
IF nSegCount < 1 THEN
    nSegEff := 1;                        // 段数下限钳位 [段]
    uErrorId := 16#0002_1802;            // 信息级：段数钳位
ELSIF nSegCount > 16 THEN
    nSegEff := 16;                       // 段数上限钳位 [段]
    uErrorId := 16#0002_1802;            // 信息级：段数钳位
ELSE
    nSegEff := nSegCount;                // 合法段数直通 [段]
END_IF

// 段 4｜R19 首扫/跟踪同步：判据唯一合法范式 IF bTrack OR (NOT bInit)
IF bTrack OR (NOT bInit) THEN
    IF (fTrackValue = fTrackValue) AND (ABS(fTrackValue) <= DL_RS_INF_MAX) THEN
        fSetpoint  := fTrackValue;       // 设定值立即跟随跟踪值 [EU]（无扰回同步）
        fRampStart := fTrackValue;       // 斜坡起点同步为跟踪值，释放后从跟踪值继续本段 [EU]
    END_IF
    bInit := TRUE;
END_IF

// 段 5｜复位沿（解除路径清码，R15）与启动沿门禁
IF rtrigReset.Q THEN
    ePhase := E_DL_RampSoakPhase.eIdle;  // 回空闲
    uErrorId := 0;                       // 解除路径清码（R15）
    nSegAct := 0;
    bDone := FALSE;
END_IF
IF rtrigStart.Q AND ((ePhase = E_DL_RampSoakPhase.eIdle) OR (ePhase = E_DL_RampSoakPhase.eDone)) THEN
    nSegAct := 1;                        // 从段 1 启动 [段]
    bDone := FALSE;
    IF (fStartValue = fStartValue) AND (ABS(fStartValue) <= DL_RS_INF_MAX) THEN
        fRampStart := fStartValue;       // 首段斜坡起点=启动基准值 [EU]
    ELSE
        fRampStart := fSetpoint;         // 非有限基准防御：以当前设定值为斜坡起点 [EU]
    END_IF
    fTgtPrev := fRampStart;              // 段 1 目标兜底来源=斜坡起点 [EU]
    fSoakElapsed := 0.0;                 // 保温计时清零 [s]
    ePhase := E_DL_RampSoakPhase.eRamp;  // 进入首段斜坡
END_IF

// 段 6｜跳段沿（斜坡/保温相位均可跳；末段跳段 → 完成并置信息级 0002_0110）
IF rtrigSkip.Q AND ((ePhase = E_DL_RampSoakPhase.eRamp) OR (ePhase = E_DL_RampSoakPhase.eSoak)) THEN
    IF nSegAct < nSegEff THEN
        nSegAct := nSegAct + 1;          // 段号递推 [段]
        bSegChange := TRUE;              // 段切换沿单发
        fRampStart := fSetpoint;         // 跳段斜坡起点=当前值 [EU]
        fSoakElapsed := 0.0;             // 新段保温计时清零 [s]
        ePhase := E_DL_RampSoakPhase.eRamp;
    ELSE
        uErrorId := 16#0002_1801;        // 信息级：末段跳段，直接完成
        ePhase := E_DL_RampSoakPhase.eDone;
        bDone := TRUE;
    END_IF
END_IF

// 段 7｜主相位状态机（ENUM + CASE + ELSE 兜底）
CASE ePhase OF

    E_DL_RampSoakPhase.eIdle:            // 空闲态：未启动，输出保持
        nSegAct := 0;
        bDone := FALSE;

    E_DL_RampSoakPhase.eRamp:            // 斜坡态：段内等步长线性插值逼近本段目标
        fTgtEff := aTarget[nSegAct];     // 本段目标值 [EU]（数组下界受段数钳位保护）
        IF (fTgtEff <> fTgtEff) OR (ABS(fTgtEff) > DL_RS_INF_MAX) THEN
            fTgtEff := fTgtPrev;         // 非有限值目标兜底：取前段目标（不可达防御，公约 0.8）
            uErrorId := 16#0002_1810;    // 故障级：段目标非有限值（锁存）
            ePhase := E_DL_RampSoakPhase.eFault;
        ELSE
            fTgtPrev := fTgtEff;         // 有限目标入快照，供后续段兜底 [EU]
            fRampSec := TIME_TO_REAL(aRampTime[nSegAct]) / 1000.0;  // 本段斜坡时间 [s]
            fSoakSec := TIME_TO_REAL(aSoakTime[nSegAct]) / 1000.0;  // 本段保温时间 [s]
            IF bHold THEN
                // 外部保持：冻结设定值与计时，不积分不迁移（终端态无动作，纯注释占位）
            ELSIF fRampSec <= DL_RS_TMIN THEN
                fSetpoint := fTgtEff;    // 零斜坡：阶跃直达本段目标 [EU]（信息级）
                uErrorId := 16#0002_1803;
                NextSegOrDone();         // 阶跃后进入保温或下段
            ELSE
                fStep := (fTgtEff - fRampStart) * fDt / fRampSec;  // 本拍增量 [EU]，分母有下限防除零
                IF ABS(fTgtEff - fSetpoint) <= (ABS(fStep) + DL_RS_EPS) THEN
                    fSetpoint := fTgtEff; // 到达：剩余不足一拍，直接贴上目标 [EU]
                    NextSegOrDone();      // 进入保温或下段
                ELSE
                    fSetpoint := fSetpoint + fStep;  // 逐拍积分逼近 [EU]
                END_IF
            END_IF
        END_IF

    E_DL_RampSoakPhase.eSoak:            // 保温态：自实现时间戳累积（bHold 冻结语义，TON 不适用）
        fSoakSec := TIME_TO_REAL(aSoakTime[nSegAct]) / 1000.0;  // 本段保温时间 [s]（逐拍重算支持在线改）
        IF bHold THEN
            // 外部保持：冻结段内计时（终端态无动作，纯注释占位）
        ELSE
            fSoakElapsed := fSoakElapsed + fDt;  // 保温计时累积 [s]
            IF (fSoakElapsed + DL_RS_TEPS) >= fSoakSec THEN
                NextSegOrDone();         // 保温计满 → 下段/循环/完成
            END_IF
        END_IF

    E_DL_RampSoakPhase.eDone:            // 完成态：标志保持，等待启动沿/复位
        bDone := TRUE;

    E_DL_RampSoakPhase.eFault:           // 故障态：码锁存，仅复位沿退出（R15）
        // 保持故障码与设定值，等待 bReset（终端态无动作，纯注释占位）

    ELSE
        // 非法状态兜底（故障级，DL_Algo 公共码 0002_0005，复用留档）
        uErrorId := 16#0002_0005;
        ePhase := E_DL_RampSoakPhase.eFault;

END_CASE

(*------------------------------------------------------------------------------
 * 方法实现（METHOD）：段递推收口子过程——保温/跳转/循环/完成四路统一出口，
 * 供斜坡到达与保温计满共用，保证段切换沿与计时清零只在一处发生。
 *------------------------------------------------------------------------------*)

END_FUNCTION_BLOCK
