(*
    FB_DL_LaneDivertCtrl —— 输送线道岔分流控制器（到件 → 岔口动作 → 尾件确认 → 恢复直行）
    ------------------------------------------------------------------
    组件名称  : FB_DL_LaneDivertCtrl
    分类      : DL_Process / Conveyor
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 借鉴点 —— S-9 输送线工程惯例（R7 先例）的「命令 - 反馈 -
                确认」三段分层骨架，以及 PackML（ISA-TR88.00.02）最小子集
                态命名语义（只借「最小子集 + 明确终止态」的态组织）。
                本件只借**骨架与态组织**，岔口三段判据 / 码位 100% 自有。
                clean-room 声明 —— 零代码行复制；定时与沿检测仅用 IEC 61131-3
                标准库 TON / R_TRIG / F_TRIG。
                许可证 —— 本件 MIT；来源标签 s9-conv 为内部自研线，
                t2-7-packml 仅指公开标准条款，无版权文本继承。
    平台      : 纯 IEC 61131-3，CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R71 构建轮 · 批 2 · 序号 6）
    ------------------------------------------------------------------
    功能说明  : 分流道岔「命令 - 反馈 - 确认」三段顺控：
                eIdle 待机 →（到件上升沿 ∧ 岔口回位 ∧ 分流道空闲）eActuate
                岔口动作（发 bDivertCmd，等 bActDone 反馈）→（bActDone 确认，
                uDivertCount 计数）ePassing 通过（bRelease 放行，等尾件越过 =
                到件信号下降沿，F_TRIG 承载）→ eRestore 回位（撤 bDivertCmd /
                bRelease，等 bActHome）→ eIdle。
                拒放不排队（计划口径）：到件时岔口未回位或分流道占用 →
                拒收计数（信息级 37A4），不缓存到件沿 —— 防积压误分；
                周期内（ePassing）后续到件沿忽略，连续来件最小间隔由到件
                传感器信号本身承载，本件不造额外节拍参数（无魔法数）。
                动作反馈超时归因唯一（R190）：eActuate 等 bActDone 超时 →
                37A1；eRestore 等 bActHome 超时 → 37A2，绝不共用码值；
                超时即故障锁存 + 放行撤销（放行撤销必能在码表找到对应码，
                R45 口径）。
                定时器设计：单实例 _tonPhase，PT 由当前相在段 8 以 IF/ELSIF
                链逐相选择（eActuate / eRestore 两相均用 tActTimeout），**每
                周期无条件调用**（规则 ⑦），相切换时 IN 随条件清零复位，
                **不跨相累计**（定时器纪律：单定时器逐相 PT，已声明选型）。
                起立判据「先判后信」（R42）：eActuate 的 bActDone 为本拍
                复验的实时反馈，不在沿上锁存旧反馈。
    错误码    : 16#0002_37A0 组态非法（tActTimeout 非正，延时不可表示），锁存
                            —— 故障级
                16#0002_37A1 岔口动作反馈超时（eActuate 等 bActDone），锁存 +
                            放行撤销 —— 故障级
                16#0002_37A2 岔口回位反馈超时（eRestore 等 bActHome），锁存
                            —— 故障级
                16#0002_37A3 非法相枚举（CASE ELSE 兜底），锁存 —— 故障级
                16#0002_37A4 到件被拒（岔口未回位或分流道占用），拒放不排队
                            —— 信息级，不置 bError
    码位总账  : 37A0 / 37A1 / 37A2 / 37A3 用（均故障级）
                37A4 用（信息级，bError 恒 FALSE）
    状态机    : ENUM E_DL_LdcPhase 五态，CASE 全覆盖 + ELSE 兜底（锁存 37A3
                回 eFault）。迁移表见功能说明；bReset 上升沿：解锁存 →
                eIdle（唯一可到达的解除边，R188）。
    边界与披露: 一 组态判据：tActTimeout <= T#0S 拦截（TIME 非负语义下的
                   防御性复检，37A0）；布尔输入无非有限面，不设数值闸；
                二 失能 / 故障相输出回夹（R57）：bDivertCmd / bRelease 全清零
                   —— 失能（bEn = FALSE）为操作态不发码、状态回 eIdle、
                   **锁存保留**（R303）；故障相 bError 置位并回放锁存码，
                   两者语义分离；
                三 计数器 uDivertCount / uRejectCount 饱和不回绕（增量前预判，
                   R28-3 口径）；uDivertCount 在 bActDone 确认拍计数（岔口
                   动作完成即视为一次分流成立），uRejectCount 在拒收拍计数；
                四 到件沿 / 尾件沿（R_TRIG / F_TRIG）与复位沿均在段 2 无条件
                   周期刷新（规则 ⑦），不在任何 IF 分支内实例化；
                五 ePassing 中 bRelease 与 bDivertCmd 同拍保持（岔口须保持
                   分流位直至尾件越过），eRestore 首拍即双清零（放行撤销
                   与回位命令同步，不留悬空放行）；
                六 零全局变量、零 VAR_EXTERNAL、零物理地址、零数组下标、无除法。
    分工声明  : FB_DL_PalletZoneMerge（DL_Process，合流汇入）、
                FB_DL_ConveyorJamDetect（DL_Device，堵塞判级诊断）——本件只管
                「分流道岔命令-反馈-确认」三段，不做合流汇入与堵塞判级，
                三者互引分工不互代。
    修订记录  : 2026-11-22 v1.0.0 首次入库（R71 构建轮 · 批 2 · 序号 6）
*)
TYPE E_DL_LdcPhase :
(
    eIdle     := 0,   (* 待机，等下一个到件沿 / idle, waiting for the next arrival edge *)
    eActuate  := 10,  (* 岔口动作相（发分流命令，等到位反馈）/ the actuate phase, the divert command out, waiting for the in-position feedback *)
    ePassing  := 20,  (* 通过相（放行，等尾件越过 = 到件下降沿）/ the passing phase, released, waiting for the tail to pass *)
    eRestore  := 30,  (* 回位相（撤命令，等回位反馈）/ the restore phase, the command withdrawn, waiting for the home feedback *)
    eFault    := 40   (* 故障相（锁存待复位）/ the fault phase, latched for a reset *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_LaneDivertCtrl
VAR_INPUT
    bEn         : BOOL := TRUE;            (* 使能，[标志]，FALSE 时出口清零且状态回待机（R303）/ the enable, FALSE clears the outlets and returns to idle *)
    bReset      : BOOL := FALSE;           (* 故障复位（上升沿有效），[标志] / the fault reset, rising edge effective *)
    bPartArrive : BOOL := FALSE;           (* 到件传感，[标志]，上升沿 = 头件到 / 下沿 = 尾件越过 / the part arrival sensor, rising = head arrived, falling = tail passed *)
    bLaneFree   : BOOL := TRUE;            (* 分流道空闲（上位注入），[标志] / the divert lane free flag, injected by the upper level *)
    bActDone    : BOOL := FALSE;           (* 岔口动作器到位反馈，[标志] / the diverter in-position feedback *)
    bActHome    : BOOL := TRUE;            (* 岔口动作器回位反馈，[标志] / the diverter home feedback *)
    tActTimeout : TIME := T#3S;            (* 动作 / 回位反馈超时，[ms]，须 > T#0S / the actuation and home feedback timeout *)
END_VAR
VAR_OUTPUT
    eState      : E_DL_LdcPhase := E_DL_LdcPhase.eIdle; (* 相状态出口，[相] / the phase outlet *)
    bDivertCmd  : BOOL;                    (* 岔口动作命令，[标志] / the diverter actuation command *)
    bRelease    : BOOL;                    (* 放行，[标志] / the release flag *)
    uDivertCount: UDINT;                   (* 分流完成计数（饱和不回绕）/ the divert counter, saturating *)
    uRejectCount: UDINT;                   (* 到件拒收计数（饱和不回绕）/ the reject counter, saturating *)
    bError      : BOOL;                    (* 故障标志，锁存故障时为 TRUE / the fault flag, raised while latched *)
    nErrCode    : UDINT;                   (* 错误码，0 = 正常，锁存回放 / the error id, 0 = ok, replayed from the latch *)
END_VAR
VAR
    _rtArrive   : R_TRIG;                  (* 到件上升沿实例（无条件调用）/ the arrival rising edge instance *)
    _ftArrive   : F_TRIG;                  (* 尾件越过下降沿实例（无条件调用）/ the tail passed falling edge instance *)
    _rtReset    : R_TRIG;                  (* 复位上升沿实例（无条件调用）/ the reset rising edge instance *)
    _tonPhase   : TON;                     (* 相反馈超时实例（单定时器逐相 PT，无条件调用）/ the phase feedback timeout timer *)
    _ePhase     : E_DL_LdcPhase := E_DL_LdcPhase.eIdle; (* 相状态寄存器 / the internal phase register *)
    _bFault     : BOOL;                    (* 故障锁存位，仅 bReset 上升沿解除 / the latched fault bit *)
    _nCodeLatch : UDINT;                   (* 锁存成因码，故障期回放 / the latched cause code, replayed *)
    _bCfgBad    : BOOL;                    (* 组态非法标志（逐拍重算）/ the configuration fault flag *)
    _bTimerIn   : BOOL;                    (* 相计时器 IN 条件（显式条件）/ the timer IN condition *)
    _tPhasePt   : TIME;                    (* 相计时器 PT 当前值（逐相选择）/ the timer PT for the current phase *)
END_VAR
VAR CONSTANT
    DL_LDC_CMAX : UDINT := 16#FFFF_FFFE;   (* 计数器饱和上限（增量前预判）/ the counter saturation cap, pre-increment check *)
END_VAR

// 段 1｜出口预置（R256 统一出口预置）/ segment 1, preset every outlet
eState       := _ePhase;                   // 相出口先镜像寄存器 / mirror the phase register first
bDivertCmd   := FALSE;                     // 分流命令预清零（活动相内再置位）/ preset the divert command false
bRelease     := FALSE;                     // 放行预清零（通过相内再置位）/ preset the release false
bError       := FALSE;                     // 故障标志预清零 / preset the error flag false
nErrCode     := 0;                         // 错误码预置无错 / preset the code to zero
_bTimerIn    := FALSE;                     // 计时条件预清零 / preset the timer condition false
_tPhasePt    := tActTimeout;               // 计时 PT 预置缺省值 / preset the timer PT to the default

// 段 2｜沿检测实例无条件调用（规则 ⑦）/ segment 2, the edge instances, called unconditionally
_rtArrive(CLK := bPartArrive);             // 到件上升沿，每周期无条件刷新 / the arrival edge, refreshed every scan
_ftArrive(CLK := bPartArrive);             // 尾件下降沿，每周期无条件刷新 / the tail edge, refreshed every scan
_rtReset(CLK := bReset);                   // 复位沿，每周期无条件刷新 / the reset edge, refreshed every scan

// 段 3｜复位解除：唯一可到达的锁存解除边（R188）/ segment 3, the only latch release edge
IF _rtReset.Q THEN                         // 复位上升沿 / the reset rising edge
    _bFault     := FALSE;                  // 解除故障锁存 / release the fault latch
    _nCodeLatch := 0;                      // 清锁存码 / clear the latched code
    _ePhase     := E_DL_LdcPhase.eIdle;    // 回待机相（安全相）/ back to the safe idle phase
END_IF

// 段 4｜组态守卫（边界一）/ segment 4, the configuration guard
_bCfgBad := (tActTimeout <= T#0S);         // 超时非正（TIME 非负语义下的防御复检）/ a non positive timeout

// 段 5｜首次成因锁存（故障期不重推断，回放锁存码，R189）/ segment 5, the first-cause latch
IF NOT _bFault THEN                        // 未锁存才登记成因 / a cause is registered only while not latched
    IF _bCfgBad THEN                       // 组态非法（根因）/ the configuration, the root cause
        _bFault     := TRUE;               // 置锁存 / latch it
        _nCodeLatch := 16#0002_37A0;       // 故障级：组态非法 / fault level: an illegal configuration
        _ePhase     := E_DL_LdcPhase.eFault; // 迁入故障相 / enter the fault phase
    END_IF
END_IF

// 段 6｜相反馈超时 PT 选择与无条件调用（规则 ⑦，选相不依赖可跳过分支）/ segment 6, the timer PT selection and the unconditional call
IF _ePhase = E_DL_LdcPhase.eActuate THEN   // 岔口动作相 / the actuate phase
    _tPhasePt := tActTimeout;              // 到位反馈超时 / the in-position feedback timeout
    _bTimerIn := TRUE;                     // 相内计时有效 / the timer runs
ELSIF _ePhase = E_DL_LdcPhase.eRestore THEN // 回位相 / the restore phase
    _tPhasePt := tActTimeout;              // 回位反馈超时 / the home feedback timeout
    _bTimerIn := TRUE;                     // 相内计时有效 / the timer runs
ELSE                                       // 其余相不参与计时（缺省分支，非状态机 ELSE）/ the other phases do not time
    _tPhasePt := tActTimeout;              // 缺省 PT，保证 PT 恒有定义 / a default PT, always defined
    _bTimerIn := FALSE;                    // 计时条件清零 / the timer condition cleared
END_IF
_tonPhase(IN := _bTimerIn, PT := _tPhasePt); // 每周期无条件调用 / called every scan without exception

// 段 7｜失能相输出回夹（R57 + R303，先于状态机执行）/ segment 7, the disable phase output clamping
IF (NOT bEn) AND (NOT _bFault) THEN        // 失能且无锁存故障（操作态不发码）/ disabled without a latched fault
    _ePhase := E_DL_LdcPhase.eIdle;        // 状态回待机 / back to idle
END_IF                                     // 输出清零由段 1 预置 + 状态机仅在运行许可时执行共同保证

// 段 8｜相状态机（ENUM + CASE + ELSE 兜底，仅运行许可时执行）/ segment 8, the phase machine, run permit only
IF bEn AND NOT _bFault THEN                // 运行许可成立 / the run permit holds
CASE _ePhase OF
    E_DL_LdcPhase.eIdle:                   // 待机相 / the idle phase
        IF _rtArrive.Q THEN                // 到件上升沿 / an arrival rising edge
            IF bActHome AND bLaneFree THEN // 岔口已回位且分流道空闲 / homed and the lane free
                _ePhase := E_DL_LdcPhase.eActuate; // 进入岔口动作相 / enter the actuate phase
            ELSE                           // 未回位或分流道占用 → 拒放不排队 / not homed or occupied, refused, no queue
                IF uRejectCount < DL_LDC_CMAX THEN // 饱和不回绕（增量前预判）/ saturating
                    uRejectCount := uRejectCount + 1; // 拒收计数递增 / increment the reject counter
                END_IF
                nErrCode := 16#0002_37A4;  // 信息级：到件被拒（不置 bError，R45）/ info level: the arrival refused
            END_IF
        END_IF
    E_DL_LdcPhase.eActuate:                // 岔口动作相 / the actuate phase
        bDivertCmd := TRUE;                // 发分流命令 / raise the divert command
        IF bActDone THEN                   // 到位反馈本拍复验成立（R42 先判后信）/ the in-position feedback verified this scan
            IF uDivertCount < DL_LDC_CMAX THEN // 饱和不回绕 / saturating
                uDivertCount := uDivertCount + 1; // 分流计数递增（动作完成即成立）/ increment the divert counter
            END_IF
            _ePhase := E_DL_LdcPhase.ePassing; // 进入通过相 / enter the passing phase
        ELSIF _tonPhase.Q THEN             // 动作反馈超时（归因唯一 37A1）/ the actuation feedback timed out
            _bFault     := TRUE;           // 锁存故障 / latch the fault
            _nCodeLatch := 16#0002_37A1;   // 故障级：动作反馈超时 / fault level: the actuation feedback timed out
            _ePhase     := E_DL_LdcPhase.eFault; // 迁入故障相（命令随预置清零，回夹）/ enter the fault phase
        END_IF
    E_DL_LdcPhase.ePassing:                // 通过相 / the passing phase
        bDivertCmd := TRUE;                // 岔口保持分流位直至尾件越过（边界五）/ hold the diverter until the tail passes
        bRelease   := TRUE;                // 放行 / release
        IF _ftArrive.Q THEN                // 尾件越过（到件信号下降沿承载）/ the tail passed, carried by the falling edge
            _ePhase := E_DL_LdcPhase.eRestore; // 进入回位相 / enter the restore phase
        END_IF                             // 放行撤销在 eRestore 首拍由预置完成（不留悬空放行）
    E_DL_LdcPhase.eRestore:                // 回位相 / the restore phase
        IF bActHome THEN                   // 回位反馈本拍复验成立 / the home feedback verified this scan
            _ePhase := E_DL_LdcPhase.eIdle; // 回待机 / back to idle
        ELSIF _tonPhase.Q THEN             // 回位反馈超时（归因唯一 37A2）/ the home feedback timed out
            _bFault     := TRUE;           // 锁存故障 / latch the fault
            _nCodeLatch := 16#0002_37A2;   // 故障级：回位反馈超时 / fault level: the home feedback timed out
            _ePhase     := E_DL_LdcPhase.eFault; // 迁入故障相 / enter the fault phase
        END_IF
    E_DL_LdcPhase.eFault:                  // 故障相（锁存保持）/ the fault phase, latched
        bError   := TRUE;                  // 故障标志置位 / raise the fault flag
        nErrCode := _nCodeLatch;           // 回放锁存码（不按当下输入重推断）/ replay the latched code
    ELSE                                   // 非法枚举兜底（回安全相 + 置码，规则 ⑥）/ the illegal enumeration guard
        _bFault     := TRUE;               // 置锁存 / latch it
        _nCodeLatch := 16#0002_37A3;       // 故障级：非法相枚举 / fault level: an illegal phase value
        _ePhase     := E_DL_LdcPhase.eFault; // 回安全相（故障相）/ force the safe fault phase
        bError      := TRUE;               // 故障标志置位（禁静默）/ raise the flag
        nErrCode    := _nCodeLatch;        // 回放锁存码 / replay the latched code
END_CASE
END_IF

// 段 9｜出口映射（名实双出口同源，单点写入，R191）/ segment 9, the outlet mapping
eState := _ePhase;                         // 相出口 = 寄存器（段 8 之后不再触碰）/ the phase outlet, not touched after segment 8
IF _bFault THEN                            // 锁存故障相出口补充（含故障入口拍，回夹不留残拍）/ the latched fault supplement, including the entry scan
    bDivertCmd := FALSE;                   // 分流命令清零（回夹执行输出）/ zero the divert command outlet
    bRelease   := FALSE;                   // 放行清零（回夹）/ zero the release outlet
    bError   := TRUE;                      // 故障标志 / the fault flag
    nErrCode := _nCodeLatch;               // 回放锁存码 / replay the latched code
END_IF
END_FUNCTION_BLOCK
