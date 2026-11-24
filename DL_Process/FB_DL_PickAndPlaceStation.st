(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PickAndPlaceStation
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.1
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 工站模板 · 九步序
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅 Standard.library 的 TON / R_TRIG，
 *                         轴与真空一律经既有接口引用注入，块内零硬件细节
 * 功能描述 (Function)   : 标准「取 升 移 放」上下料工站模板：注入三轴（X/Y/Z）
 *                         与真空发生器接口，按九步序执行单件搬运（确认原点、
 *                         移到取料位、下降、吸取确认、抬升、横移、下降、破真空、
 *                         抬升回原点），含真空建立超时、就位确认、节拍统计与
 *                         安灯级联出口。
 * 状态机规模 (Scope)    : 本块只做工站内工序的七态最小子集（待机、启动自检、
 *                         执行、保持中、已保持、中止收尾、故障）。完整的十七态
 *                         包装机状态机由 FB_DL_PackMlStateMachine 承载，本块
 *                         不重复实现，避免两套全状态机在同一工站内打架。
 * 接口适配说明 (Adapter) : 既有 I_DL_MotionAxis 的属性集不含「到位布尔位」，
 *                         故每步的到位判据写死为「轴处于待机态且位置落在容差
 *                         窗口内」，等价于驱动层的到位位，且不依赖任何厂商
 *                         专用属性；真空侧的吸取与破真空分别映射到既有
 *                         CmdEvacuate 与 CmdBlowOff，方法名与本块语义一一对应。
 * 时间口径 (Time base)  : 节拍以整循环超时定时器的已历时值作秒表，经
 *                         TIME_TO_DINT 转毫秒整数入滑动窗口；该转换族在三个
 *                         主流平台均提供但不属 IEC 61131-3 基础转换表，故此处
 *                         显式声明依赖，若目标平台缺失请改用显式类型转换语法，
 *                         禁止用 TIME 直接除以整数（后者跨平台必错）。
 * 设计要点 (Key notes)  : ① 单步三段式：下发（只发一次）→ 等条件 → 单拍推进，
 *                           动作指令绝不每拍重发；
 *                         ② 步超时统一由一个定时器监视，进入故障前把步号映射为
 *                           对应故障码，现场据此一步定位；
 *                         ③ 缺料与放料位占用属业务态：置安灯与信息级码，不锁
 *                           故障，产线可继续等待上料；
 *                         ④ 真空未建立属本件 NG：计数加一、置安灯、回步一，
 *                           不锁故障（吸盘老化是常态，停线代价更大）；
 *                         ⑤ 搬运中掉件属故障：立即中止并把工件当作已损坏，
 *                           转中止收尾（抬 Z、破真空），避免二次撞机；
 *                         ⑥ 保持态不重发任何运动指令，释放后从当前步继续，
 *                           已完成步不重做。
 * 开源溯源 (Origin)     : packml-omac / tcopen-component。参考 PackML 与 OMAC
 *                         公开的工站级状态语义（只在可执行子集内取七态）与
 *                         TcOpen 公开组件库的契约实现分离、状态只读属性思想。
 *                         仅借状态命名与分层思想，九步序、码位与实现 100% 自有
 *                         clean-room，不构成衍生作品。
 * 依赖     (Depends)    : I_DL_MotionAxis（DL_Motion）、I_DL_VacuumGenerator
 *                         （DL_Device），均为已入库接口，本块不依赖本轮任何新件
 * 故障码表 (Error codes):
 *   16#0005_01B0【信息级】Z 轴原点未就绪超时（保持本步重试）
 *   16#0005_01B1【信息级】真空未建立，本件判 NG
 *   16#0005_01B2【信息级】前置条件不满足（缺料或放料位占用），业务态加安灯
 *   16#0005_01B3【信息级】正常中止完成
 *   16#0005_01B4【信息级】节拍统计窗重建
 *   16#0005_02B0【故障级】X 轴取料位超时
 *   16#0005_02B1【故障级】Z 轴下降取料超时
 *   16#0005_02B2【故障级】Z 轴抬升超时
 *   16#0005_02B3【故障级】X 轴横移超时
 *   16#0005_02B4【故障级】搬运中掉件
 *   16#0005_02B5【故障级】破真空超时
 *   16#0005_02B6【故障级】回原点超时
 *   16#0005_02B7【故障级】非法状态或非法步号兜底
 * 验收向量 (Acceptance) :
 *   V1 正常单件：前置满足、启动一拍 → 步 1 到 9 推进，完成脉冲单拍、
 *      合格计数 1、节拍大于 0、回待机
 *   V2 缺料：在位信号为假即启动 → 停待机、安灯为真、码 01B2、不锁故障
 *   V3 真空失败：步 4 真空确认恒假且吸附计时到 → 不合格计数 1、安灯为真、
 *      回步 1、不锁故障
 *   V4 掉件：步 7 真空确认丢失 → 掉件标志为真、码 02B4、转中止并抬 Z
 *   V5 保持恢复：步 5 完成时给保持 → 进已保持态；释放后从步 6 继续
 *   V6 超时：步 6 长期不到位、单步超时 1 秒 → 码 02B3、进故障、轴停止被调一次
 *   V7 节拍平均：连做 9 件 → 平均节拍只反映最近 8 件
 * 红线自检 (Redline)    : R1 零全局变量表与外部变量引用 ｜ R2 零物理地址直写
 *                         R3 纯 IEC 61131-3 加既有接口 ｜ R4 到位判定用容差、
 *                         接口引用先判有效性、数组索引经模运算保证在窗内
 *                         R5 全变量中英双语同行注释 ｜ R6 ENUM 加 CASE 加 ELSE 兜底
 *                         R7 四个 TON 与两个 R_TRIG 全部在 CASE 之外无条件刷新
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 10 · ROADMAP 工站模板补齐）
 *   2026-11-15  v1.0.1  R10 终审修复三处（均为机检盲区，逐拍推演发现）：
 *                       R-FIX-1【致命】主状态机 CASE 缺 eExecute 标签，执行态
 *                       落入 ELSE 兜底被判非法状态并锁故障，工站永不执行；
 *                       R-FIX-2【严重】进故障时对四路接口一律判空后再调用，
 *                       原实现对未注入的可选 Y 轴直接调用 Stop，属空引用调用；
 *                       R-FIX-3【中等】步 1 下发分支删除 uErrorId 清零语句，
 *                       原写法把同拍刚置位的 01B0 立即覆盖，诊断不可见。
 * 规格偏离登记 (Deviations):
 *   D1 新增 fSafeZ（安全抬升位）与 fPosTol（到位容差）两个输入引脚：规格书
 *      仅以「安全位」文字描述抬升目标、以「到位」文字描述判据，未给引脚；
 *      按八、无魔法数红线提为引脚，向后兼容（有默认值），不改变既有引脚语义。
 *   D2 到位判据不引用 I_DL_MotionAxis 的到位位（该接口无此属性），改为
 *      「eState = eStandstill 且位置落在容差窗内」，等价语义，已写入头注释。
 *   D3 整循环超时沿用 02B7（非法状态兜底码）：本组件码位块 01B0~01B4 与
 *      02B0~02B7 已全部占用，按 R30「不得跨块取号」不得新增 02B8，故复用
 *      兜底码并在注释写明「循环超时同样按兜底处理」，待下一 MAJOR 拆分码位。
 *============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_SpState（唯一主状态机枚举，同名供输出对外可观测，禁止再设第二套）
 *-----------------------------------------------------------------------------*)
TYPE E_DL_SpState :
(
    eIdle     := 0,     // 待机：未启动 / Idle, not started
    eStarting := 5,     // 启动自检：轴就绪、原点就绪、放料位空闲、取料位有件 / Starting self-check
    eExecute  := 10,    // 执行：九步序推进 / Execute, running the nine-step sequence
    eHolding  := 20,    // 保持中：单拍过渡态 / Holding, a single-cycle transition state
    eHeld     := 25,    // 已保持：不重发任何运动指令 / Held, no motion command is re-issued
    eAborting := 30,    // 中止收尾：抬 Z 与破真空，逐拍推进 / Aborting, one command per cycle
    eFault    := 99     // 故障锁定：仅复位沿可退 / Fault latched, only a reset edge leaves
);
END_TYPE

FUNCTION_BLOCK FB_DL_PickAndPlaceStation
VAR_INPUT
    bEnable       : BOOL := TRUE;      // 工站使能 [-] / Station enable
    bStart        : BOOL;              // 启动单件循环，上升沿，已保持态下无效 [-] / Start one cycle on a rising edge, ignored while held
    bHold         : BOOL;              // 保持，电平：当前步完成后停在已保持态 [-] / Hold, level: park after the current step completes
    bAbort        : BOOL;              // 中止，电平：任何态转中止收尾 [-] / Abort, level: any state goes to the abort sequence
    bReset        : BOOL;              // 复位故障，上升沿 [-] / Reset the fault on a rising edge
    bPartPresent  : BOOL;              // 取料位工件在位（光电）[-] / Part present at the pick position
    bPlaceClear   : BOOL;              // 放料位空闲，允许放料 [-] / Place position clear
    bVacuumOk     : BOOL;              // 真空建立确认（真空开关）[-] / Vacuum established confirmation
    bZHomeOk      : BOOL;              // Z 轴原点或上限位就绪 [-] / Z axis home or upper limit ready
    fPickZ        : LREAL := 0.0;      // 取料位下降目标 [毫米] / Pick position Z target
    fPlaceZ       : LREAL := 0.0;      // 放料位下降目标 [毫米] / Place position Z target
    fSafeZ        : LREAL := 50.0;     // 安全抬升位，用于抬升与中止 [毫米] / Safe lift height used for lifting and aborting
    fTravelX      : LREAL := 100.0;    // 取到放的横向行程 [毫米] / Horizontal travel from pick to place
    fSpeed        : LREAL := 200.0;    // 运动速度，域不小于 1 [毫米每秒] / Motion speed, not less than 1
    fAccel        : LREAL := 1000.0;   // 加减速度，域不小于 10 [毫米每二次方秒] / Acceleration and deceleration
    fPosTol       : LREAL := 0.5;      // 到位判定容差窗口 [毫米] / In-position tolerance window
    tGripTime     : TIME := T#200MS;   // 吸盘吸附建立时间 [毫秒] / Suction build-up time
    tBlowTime     : TIME := T#150MS;   // 破真空吹气时间 [毫秒] / Blow-off time
    tStepTimeout  : TIME := T#5S;      // 单步超时 [毫秒] / Per-step timeout
    tCycleTimeout : TIME := T#30S;     // 整循环超时，同时用作节拍秒表 [毫秒] / Whole-cycle timeout, also the cycle stopwatch
END_VAR
VAR_IN_OUT
    iAxisX        : I_DL_MotionAxis;      // X 轴接口引用，横向搬运 [-] / X axis interface reference
    iAxisY        : I_DL_MotionAxis;      // Y 轴接口引用，可选，未用时传同一实例 [-] / Y axis interface reference, optional
    iAxisZ        : I_DL_MotionAxis;      // Z 轴接口引用，升降 [-] / Z axis interface reference
    iVacuum       : I_DL_VacuumGenerator; // 真空发生器接口引用 [-] / Vacuum generator interface reference
END_VAR
VAR_OUTPUT
    eState        : E_DL_SpState;   // 工站状态，对外可观测 [-] / Station state, observable from outside
    nStepNo       : INT;            // 当前步号，1 到 9，0 为无常驻步 [步] / Current step number, 1 to 9, zero when idle
    bCycleDone    : BOOL;           // 单件循环完成，单拍脉冲 [-] / Cycle finished, single-cycle pulse
    bCycleOk      : BOOL;           // 本件合格，保持到下一件开始 [-] / Part accepted, held until the next cycle starts
    bPartLost     : BOOL;           // 搬运中真空丢失，保持 [-] / Part lost during transport, holding
    bError        : BOOL;           // 故障锁存 [-] / Fault latch
    uErrorId      : UDINT;          // 事件码，0 = 无事件 / Event code, 0 = no event
    tCycleTime    : TIME;           // 上一件节拍 [毫秒] / Cycle time of the last part
    tCycleTimeAvg : TIME;           // 节拍移动平均，八件窗 [毫秒] / Moving average over an eight-part window
    nOkCnt        : UDINT;          // 合格计数 [件] / Accepted part counter
    nNgCnt        : UDINT;          // 不合格计数 [件] / Rejected part counter
    bCallAndon    : BOOL;           // 需人工介入，供安灯系统消费 [-] / Manual intervention request for the andon system
END_VAR
VAR
    fbTrigStart   : R_TRIG;         // 启动沿检测，CASE 之外无条件刷新 [-] / Rising edge detector for the start input
    fbTrigReset   : R_TRIG;         // 复位沿检测，CASE 之外无条件刷新 [-] / Rising edge detector for the reset input
    fbStepTmo     : TON;            // 单步超时，CASE 之外无条件刷新 [-] / Per-step timeout timer
    fbCycleTmo    : TON;            // 整循环超时兼节拍秒表，CASE 之外无条件刷新 [-] / Cycle timeout and stopwatch timer
    fbGrip        : TON;            // 吸附建立计时 [-] / Suction build-up timer
    fbBlow        : TON;            // 破真空计时 [-] / Blow-off timer
    bInit         : BOOL := FALSE;  // 首扫标志，初值 FALSE，判据 NOT bInit（R19 范式）[-] / First-scan flag
    _eState       : E_DL_SpState := E_DL_SpState.eIdle;  // 内部状态机 [-] / Internal state machine
    nStep         : INT := 0;       // 内部步号，0 表示无常驻步 [步] / Internal step number
    nAbortStep    : INT := 0;       // 中止收尾子步，1 抬 Z，2 破真空，3 收口 [步] / Abort sub-step
    bStepActive   : BOOL;           // 本步已下发动作，防重复下发 [-] / TRUE once the current step has issued its action
    anCycleHistMs : ARRAY[0..7] OF DINT;  // 节拍历史窗，八件毫秒整数 [毫秒] / Cycle history window in milliseconds
    nHistIdx      : INT := 0;       // 历史窗写指针 [索引] / History write index
    nHistCnt      : INT := 0;       // 历史窗有效个数 [件] / Valid entries in the history window
    bStepTmoIn    : BOOL;           // 单步超时输入条件，先算后调 [-] / Step timer input condition
    bCycleTmoIn   : BOOL;           // 整循环超时输入条件，先算后调 [-] / Cycle timer input condition
    bGripIn       : BOOL;           // 吸附计时输入条件，先算后调 [-] / Grip timer input condition
    bBlowIn       : BOOL;           // 吹气计时输入条件，先算后调 [-] / Blow timer input condition
    tStepTmoUse   : TIME := T#5S;   // 生效单步超时（已钳位）[毫秒] / Effective step timeout
    tCycleTmoUse  : TIME := T#30S;  // 生效整循环超时（已钳位）[毫秒] / Effective cycle timeout
    tGripUse      : TIME := T#200MS; // 生效吸附时间（已钳位）[毫秒] / Effective grip time
    tBlowUse      : TIME := T#150MS; // 生效吹气时间（已钳位）[毫秒] / Effective blow time
    bAxisValid    : BOOL;           // 四个接口引用全部有效 [-] / TRUE when every injected interface is valid
    bFaultStopDone: BOOL;           // 进故障时轴停止指令已发过，防每拍重发 [-] / TRUE once the axes have been stopped on fault entry
    diCycleMs     : DINT;           // 本件节拍毫秒整数 [毫秒] / Cycle time in milliseconds
    diSumMs       : DINT;           // 窗口求和中间量 [毫秒] / Window sum
    i             : INT;            // 历史窗求和循环索引 [索引] / Summation index
    fSpeedUse     : REAL;           // 生效速度（已转为接口类型）[毫米每秒] / Effective speed converted for the interface
    fAccelUse     : REAL;           // 生效加速度（已转为接口类型）[毫米每二次方秒] / Effective acceleration converted for the interface
END_VAR
VAR CONSTANT
    DL_STEP_NUM    : INT   := 9;           // 总步数 [步] / Total step count
    DL_HIST_LEN    : INT   := 8;           // 节拍历史窗长度 [件] / Cycle history window length
    DL_SPEED_MIN   : LREAL := 1.0;         // 速度下限 [毫米每秒] / Speed lower bound
    DL_ACCEL_MIN   : LREAL := 10.0;        // 加速度下限 [毫米每二次方秒] / Acceleration lower bound
    DL_TMO_MAX     : TIME  := T#60S;       // 超时上限 [毫秒] / Timeout upper bound
    DL_GRIP_MAX    : TIME  := T#10S;       // 吸附与吹气时间上限 [毫秒] / Grip and blow time upper bound
    DL_POS_DEFAULT : LREAL := 50.0;        // 安全位兜底高度 [毫米] / Safe height fallback
    DL_AXIS_TOL_MIN: LREAL := 0.01;        // 到位容差下限 [毫米] / Minimum in-position tolerance
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜单拍输出预清零（R25 律①）
 *      Single-cycle output pre-clear
 *-----------------------------------------------------------------------------*)
bCycleDone := FALSE;

(*------------------------------------------------------------------------------
 * 段 2｜超时参数钳位（先钳位再调用，杜绝分支内调用实例）
 *      Timeout parameters clamped before the unconditional timer calls
 *-----------------------------------------------------------------------------*)
tStepTmoUse := tStepTimeout;
IF tStepTmoUse > DL_TMO_MAX THEN
    tStepTmoUse := DL_TMO_MAX;
ELSIF tStepTmoUse < T#10MS THEN
    tStepTmoUse := T#10MS;
END_IF

tCycleTmoUse := tCycleTimeout;
IF tCycleTmoUse > DL_TMO_MAX THEN
    tCycleTmoUse := DL_TMO_MAX;
ELSIF tCycleTmoUse < T#10MS THEN
    tCycleTmoUse := T#10MS;
END_IF

tGripUse := tGripTime;
IF tGripUse > DL_GRIP_MAX THEN
    tGripUse := DL_GRIP_MAX;
ELSIF tGripUse < T#0S THEN
    tGripUse := T#0S;
END_IF

tBlowUse := tBlowTime;
IF tBlowUse > DL_GRIP_MAX THEN
    tBlowUse := DL_GRIP_MAX;
ELSIF tBlowUse < T#0S THEN
    tBlowUse := T#0S;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜沿与定时器无条件刷新（R7 红线）：六个实例全部在 CASE 之外
 *      All six instances refreshed outside the CASE, mandatory by the red line
 *-----------------------------------------------------------------------------*)
fbTrigStart(CLK := bStart);
fbTrigReset(CLK := bReset);

IF bStepActive AND (_eState = E_DL_SpState.eExecute) THEN
    bStepTmoIn := TRUE;
ELSE
    bStepTmoIn := FALSE;
END_IF
fbStepTmo(IN := bStepTmoIn, PT := tStepTmoUse);

IF _eState = E_DL_SpState.eExecute THEN
    bCycleTmoIn := TRUE;
ELSE
    bCycleTmoIn := FALSE;
END_IF
fbCycleTmo(IN := bCycleTmoIn, PT := tCycleTmoUse);

IF bStepActive AND (nStep = 4) THEN
    bGripIn := TRUE;
ELSE
    bGripIn := FALSE;
END_IF
fbGrip(IN := bGripIn, PT := tGripUse);

IF bStepActive AND (nStep = 8) THEN
    bBlowIn := TRUE;
ELSE
    bBlowIn := FALSE;
END_IF
fbBlow(IN := bBlowIn, PT := tBlowUse);

(*------------------------------------------------------------------------------
 * 段 4｜首扫初始化（R19 唯一合法范式）
 *      First-scan initialisation with the canonical R19 pattern
 *-----------------------------------------------------------------------------*)
IF NOT bInit THEN
    _eState        := E_DL_SpState.eIdle;
    nStep          := 0;
    nAbortStep     := 0;
    bStepActive    := FALSE;
    nOkCnt         := 0;
    nNgCnt         := 0;
    nHistIdx       := 0;
    nHistCnt       := 0;
    bCycleOk       := FALSE;
    bPartLost      := FALSE;
    bError         := FALSE;
    uErrorId       := 16#0000_0000;
    bCallAndon     := FALSE;
    tCycleTime     := T#0S;
    tCycleTimeAvg  := T#0S;
    bFaultStopDone := FALSE;
    FOR i := 0 TO (DL_HIST_LEN - 1) DO
        anCycleHistMs[i] := 0;
    END_FOR
    bInit := TRUE;                       // 首扫只做一次
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜接口有效性与运动参数兜底（接口引用未注入时不得动作）
 *      Interface validity and motion parameter fallback
 *-----------------------------------------------------------------------------*)
IF (iAxisX = 0) OR (iAxisZ = 0) OR (iVacuum = 0) THEN
    bAxisValid := FALSE;
ELSE
    bAxisValid := TRUE;
END_IF

IF fSpeed < DL_SPEED_MIN THEN
    fSpeedUse := LREAL_TO_REAL(DL_SPEED_MIN);
ELSE
    fSpeedUse := LREAL_TO_REAL(fSpeed);
END_IF

IF fAccel < DL_ACCEL_MIN THEN
    fAccelUse := LREAL_TO_REAL(DL_ACCEL_MIN);
ELSE
    fAccelUse := LREAL_TO_REAL(fAccel);
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜前置安全（每拍最先判）：中止优先，其次保持
 *      Pre-emptive safety evaluation: abort first, then hold
 *-----------------------------------------------------------------------------*)
IF bAbort THEN
    IF (_eState <> E_DL_SpState.eFault) AND (_eState <> E_DL_SpState.eAborting) THEN
        nAbortStep  := 1;
        bStepActive := FALSE;
        _eState     := E_DL_SpState.eAborting;
    END_IF
END_IF

IF bHold AND (_eState = E_DL_SpState.eExecute) AND (NOT bStepActive) THEN
    _eState := E_DL_SpState.eHolding;
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜主状态机（ENUM 加 CASE，含 ELSE 兜底）
 *      Main state machine with an ELSE fallback branch
 *-----------------------------------------------------------------------------*)
CASE _eState OF
    E_DL_SpState.eIdle:
        IF fbTrigStart.Q AND bEnable AND bAxisValid THEN
            bCycleOk := FALSE;                 // 新件开始，清上一件结论
            _eState   := E_DL_SpState.eStarting;
        END_IF

    E_DL_SpState.eStarting:
        (* 自检：Z 原点就绪、放料位空闲、取料位有件；缺一即业务态退回 *)
        IF bZHomeOk AND bPlaceClear AND bPartPresent THEN
            nStep       := 1;
            bStepActive := FALSE;
            bCallAndon  := FALSE;
            uErrorId    := 16#0000_0000;
            _eState     := E_DL_SpState.eExecute;
        ELSE
            bCallAndon := TRUE;                // 缺料或放料位占用：叫料，不锁故障
            uErrorId   := 16#0005_01B2;
            _eState    := E_DL_SpState.eIdle;
        END_IF

    E_DL_SpState.eExecute:
        (* 执行态本体在段 8 至段 11 中处理（步超时、动作下发、完成推进、循环超时）
           本分支必须显式列出：CASE 缺该标签会让 eExecute 落入 ELSE 兜底而被判为
           非法状态并锁故障，工站将永远无法执行。禁止在此分支内写任何动作。 *)

    E_DL_SpState.eHolding:
        (* 单拍过渡态：目的只是把进入动作与停留态分开，便于 HMI 看到一次跃迁 *)
        _eState := E_DL_SpState.eHeld;

    E_DL_SpState.eHeld:
        (* 已保持：不发任何运动指令，真空状态保持；释放后从当前步继续 *)
        IF NOT bHold THEN
            _eState := E_DL_SpState.eExecute;
        END_IF

    E_DL_SpState.eAborting:
        (* 中止收尾：逐拍推进，一个扫描周期只发一条指令 *)
        IF nAbortStep = 1 THEN
            iAxisZ.MoveAbsolute(fPos := LREAL_TO_REAL(fSafeZ), fVel := fSpeedUse, fAcc := fAccelUse);
            nAbortStep := 2;
        ELSIF nAbortStep = 2 THEN
            iVacuum.CmdBlowOff();
            nAbortStep := 3;
        ELSE
            nAbortStep  := 0;
            nStep       := 0;
            bStepActive := FALSE;
            uErrorId    := 16#0005_01B3;       // 信息级：正常中止完成
            _eState     := E_DL_SpState.eIdle;
        END_IF

    E_DL_SpState.eFault:
        nStep       := 0;
        bStepActive := FALSE;
        IF fbTrigReset.Q THEN
            bError         := FALSE;
            bPartLost      := FALSE;
            bCallAndon     := FALSE;
            uErrorId       := 16#0000_0000;
            bFaultStopDone := FALSE;
            _eState        := E_DL_SpState.eIdle;
        END_IF

    ELSE
        (* 非法枚举值兜底 *)
        _eState     := E_DL_SpState.eFault;
        uErrorId    := 16#0005_02B7;
        bError      := TRUE;
        nStep       := 0;
        bStepActive := FALSE;
END_CASE

(*------------------------------------------------------------------------------
 * 段 8｜执行态步序：单步超时监视
 *      Execute state, per-step timeout supervision
 *-----------------------------------------------------------------------------*)
IF (_eState = E_DL_SpState.eExecute) AND fbStepTmo.Q THEN
    IF nStep = 1 THEN
        uErrorId    := 16#0005_01B0;        // 原点未就绪：信息级，重试本步
        bStepActive := FALSE;
    ELSE
        CASE nStep OF
            2: uErrorId := 16#0005_02B0;
            3: uErrorId := 16#0005_02B1;
            5: uErrorId := 16#0005_02B2;
            6: uErrorId := 16#0005_02B3;
            7: uErrorId := 16#0005_02B4;
            8: uErrorId := 16#0005_02B5;
            9: uErrorId := 16#0005_02B6;
            ELSE
                uErrorId := 16#0005_02B7;
        END_CASE
        bError      := TRUE;
        bStepActive := FALSE;
        _eState     := E_DL_SpState.eFault;
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜执行态步序：动作下发（每步只发一次）
 *      Execute state, action dispatch once per step
 *-----------------------------------------------------------------------------*)
IF (_eState = E_DL_SpState.eExecute) AND (NOT bStepActive) THEN
    CASE nStep OF
        1:
            (* 步 1：只确认原点，无下发动作；残留信息码已在 eStarting 自检通过时
               清零（段 7），此处绝不可再写 uErrorId := 0，否则本步超时码 01B0
               会被同拍覆盖，现场看不到「原点未就绪」的直接提示 *)
        2:
            iAxisX.MoveAbsolute(fPos := 0.0, fVel := fSpeedUse, fAcc := fAccelUse);
        3:
            iAxisZ.MoveAbsolute(fPos := LREAL_TO_REAL(fPickZ), fVel := fSpeedUse, fAcc := fAccelUse);
        4:
            iVacuum.CmdEvacuate();           // 开始抽真空
        5:
            iAxisZ.MoveAbsolute(fPos := LREAL_TO_REAL(fSafeZ), fVel := fSpeedUse, fAcc := fAccelUse);
        6:
            iAxisX.MoveAbsolute(fPos := LREAL_TO_REAL(fTravelX), fVel := fSpeedUse, fAcc := fAccelUse);
        7:
            iAxisZ.MoveAbsolute(fPos := LREAL_TO_REAL(fPlaceZ), fVel := fSpeedUse, fAcc := fAccelUse);
        8:
            iVacuum.CmdBlowOff();            // 破真空
        9:
            iAxisZ.MoveAbsolute(fPos := LREAL_TO_REAL(fSafeZ), fVel := fSpeedUse, fAcc := fAccelUse);
            iAxisX.MoveAbsolute(fPos := 0.0, fVel := fSpeedUse, fAcc := fAccelUse);
        ELSE
            bError   := TRUE;
            uErrorId := 16#0005_02B7;
            _eState  := E_DL_SpState.eFault;
    END_CASE
    bStepActive := TRUE;
END_IF

(*------------------------------------------------------------------------------
 * 段 10｜执行态步序：完成条件判定与推进
 *      Execute state, completion predicates and step advance
 *-----------------------------------------------------------------------------*)
IF (_eState = E_DL_SpState.eExecute) AND bStepActive THEN
    CASE nStep OF
        1:
            IF bZHomeOk THEN
                nStep       := 2;
                bStepActive := FALSE;
            END_IF
        2:
            IF (iAxisX.eState = E_DL_AxisState.eStandstill) AND
               (ABS(REAL_TO_LREAL(iAxisX.fPosition)) <= MAX(fPosTol, DL_AXIS_TOL_MIN)) THEN
                nStep       := 3;
                bStepActive := FALSE;
            END_IF
        3:
            IF (iAxisZ.eState = E_DL_AxisState.eStandstill) AND
               (ABS(REAL_TO_LREAL(iAxisZ.fPosition) - fPickZ) <= MAX(fPosTol, DL_AXIS_TOL_MIN)) THEN
                nStep       := 4;
                bStepActive := FALSE;
            END_IF
        4:
            IF fbGrip.Q THEN
                IF bVacuumOk THEN
                    nStep       := 5;                  // 吸附建立成功
                    bStepActive := FALSE;
                ELSE
                    (* 真空未建立：本件判 NG，叫料，回步 1，不锁故障 *)
                    nNgCnt     := nNgCnt + 1;
                    bCallAndon := TRUE;
                    uErrorId   := 16#0005_01B1;
                    iVacuum.CmdStop();
                    nStep       := 1;
                    bStepActive := FALSE;
                END_IF
            END_IF
        5:
            IF (iAxisZ.eState = E_DL_AxisState.eStandstill) AND
               (ABS(REAL_TO_LREAL(iAxisZ.fPosition) - fSafeZ) <= MAX(fPosTol, DL_AXIS_TOL_MIN)) THEN
                nStep       := 6;
                bStepActive := FALSE;
            END_IF
        6:
            IF (iAxisX.eState = E_DL_AxisState.eStandstill) AND
               (ABS(REAL_TO_LREAL(iAxisX.fPosition) - fTravelX) <= MAX(fPosTol, DL_AXIS_TOL_MIN)) THEN
                nStep       := 7;
                bStepActive := FALSE;
            END_IF
        7:
            IF NOT bVacuumOk THEN
                (* 搬运中掉件：故障级，转中止收尾，避免二次撞机 *)
                bPartLost := TRUE;
                uErrorId  := 16#0005_02B4;
                bError    := TRUE;
                nAbortStep  := 1;
                bStepActive := FALSE;
                _eState     := E_DL_SpState.eAborting;
            ELSIF (iAxisZ.eState = E_DL_AxisState.eStandstill) AND
                  (ABS(REAL_TO_LREAL(iAxisZ.fPosition) - fPlaceZ) <= MAX(fPosTol, DL_AXIS_TOL_MIN)) THEN
                nStep       := 8;
                bStepActive := FALSE;
            END_IF
        8:
            IF fbBlow.Q THEN
                nStep       := 9;
                bStepActive := FALSE;
            END_IF
        9:
            IF (iAxisX.eState = E_DL_AxisState.eStandstill) AND
               (ABS(REAL_TO_LREAL(iAxisX.fPosition)) <= MAX(fPosTol, DL_AXIS_TOL_MIN)) AND
               (iAxisZ.eState = E_DL_AxisState.eStandstill) AND
               (ABS(REAL_TO_LREAL(iAxisZ.fPosition) - fSafeZ) <= MAX(fPosTol, DL_AXIS_TOL_MIN)) THEN
                (* 单件结算：完成脉冲单拍，节拍入窗并重算平均 *)
                bCycleDone := TRUE;
                nOkCnt     := nOkCnt + 1;
                bCycleOk   := TRUE;
                tCycleTime := fbCycleTmo.ET;
                diCycleMs  := TIME_TO_DINT(tCycleTime);
                anCycleHistMs[nHistIdx] := diCycleMs;
                nHistIdx   := (nHistIdx + 1) MOD DL_HIST_LEN;
                IF nHistCnt < DL_HIST_LEN THEN
                    nHistCnt := nHistCnt + 1;
                END_IF
                diSumMs := 0;
                FOR i := 0 TO (nHistCnt - 1) DO
                    diSumMs := diSumMs + anCycleHistMs[i];
                END_FOR
                IF nHistCnt > 0 THEN
                    tCycleTimeAvg := DINT_TO_TIME(diSumMs / nHistCnt);
                END_IF
                nStep       := 0;
                bStepActive := FALSE;
                _eState     := E_DL_SpState.eIdle;
            END_IF
        ELSE
            bError   := TRUE;
            uErrorId := 16#0005_02B7;
            _eState  := E_DL_SpState.eFault;
    END_CASE
END_IF

(*------------------------------------------------------------------------------
 * 段 11｜整循环超时（业务保护）：执行态超时即转中止收尾，不直接锁故障
 *      Cycle timeout protection, aborts instead of latching a fault
 *-----------------------------------------------------------------------------*)
IF (_eState = E_DL_SpState.eExecute) AND fbCycleTmo.Q THEN
    uErrorId    := 16#0005_02B7;   // 循环超时复用兜底码，理由见头注释偏离登记 D3
    nAbortStep  := 1;
    bStepActive := FALSE;
    _eState     := E_DL_SpState.eAborting;
END_IF

(*------------------------------------------------------------------------------
 * 段 12｜进故障时的轴停止（只发一次，禁止每拍重发）
 *      Stop the axes once on fault entry, never re-issued every cycle
 *-----------------------------------------------------------------------------*)
IF (_eState = E_DL_SpState.eFault) AND (NOT bFaultStopDone) THEN
    (* 逐个判空再调用：Y 轴为可选注入，未注入时接口引用为 0，直接调用会落到
       空引用上产生未定义行为。bAxisValid 只覆盖 X / Z / 真空三路，不足以
       保护 Y 轴，故此处对四路一律显式判空，绝不依赖组态纪律。 *)
    IF iAxisX <> 0 THEN
        iAxisX.Stop();
    END_IF
    IF iAxisY <> 0 THEN
        iAxisY.Stop();
    END_IF
    IF iAxisZ <> 0 THEN
        iAxisZ.Stop();
    END_IF
    IF iVacuum <> 0 THEN
        iVacuum.CmdStop();
    END_IF
    bFaultStopDone := TRUE;
END_IF

(*------------------------------------------------------------------------------
 * 段 13｜输出每拍重写（R27）
 *      Outputs rewritten every cycle
 *-----------------------------------------------------------------------------*)
eState  := _eState;
nStepNo := nStep;

IF _eState = E_DL_SpState.eFault THEN
    bError := TRUE;
END_IF

(*------------------------------------------------------------------------------
 * 现场提示：
 *   1 步 1 走的是「确认原点就绪」而不是「回原点」：回原序列由
 *     FB_DL_AxisHomingSeq 承担，工站不做回原，避免两处在同一轴上写指令；
 *   2 保持态释放后从当前步继续，若保持发生在步 3 的下降途中，释放后不会
 *     重发下降指令，轴会继续走完原指令，这是刻意的（重发会造成指令覆盖）；
 *   3 节拍秒表用整循环超时定时器的已历时值，该定时器进执行态开始计时、
 *     离开执行态清零，故单件节拍不含待机等待时间。
 *-----------------------------------------------------------------------------*)
END_FUNCTION_BLOCK
