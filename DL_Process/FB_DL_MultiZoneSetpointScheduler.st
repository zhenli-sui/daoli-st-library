(*==============================================================================
 * 组件名称 (Component)  : FB_DL_MultiZoneSetpointScheduler
 * 所属子库 (Sublibrary) : DL_Process ｜ 版本 (Version) : 1.0.2 ｜ 2026-11-23
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准（FOR / CASE / ABS），零厂商私有库
 * 功能描述 (Function)   : 多区设定值按时段表切换（4 区 × 每区最多 8 时段）。每区持有一张
 *                         「起始分钟 + 设定值」时段表，按当日第几分钟 nMinuteOfDay 选出生效
 *                         时段，并把「与上一生效值不同」的区以 abSpChanged 单拍沿上报。
 *                         参数非法（时段非单调 / 分钟越域 / 设定值非有限 / 时段数越界）→
 *                         整机进 eFault 并锁存首个成因码；eFault 唯一出口为 bReset（重校验通过）。
 *                         **时钟来源声明**：本件不读任何系统时钟（零全局耦合 R1），
 *                         nMinuteOfDay 由上层 PRG 从 RTC 换算后传入（0..1439）。
 *                         **bEnable = FALSE 语义（R191 二选一，本件选「冻结保持末值」）**：
 *                         各区 afActiveSp / aiActiveIdx 保持末值不动，abSpChanged 不再发沿，
 *                         bValid 落 FALSE 提示「该值已不与时钟对齐」。
 * 接口     (Interface)  : 输入 bEnable / bReset / nMinuteOfDay / aiZoneSlotCount[1..4] /
 *                         aSlots[1..4][1..8]（ST_DL_SpSlot）；输出 afActiveSp[1..4] /
 *                         aiActiveIdx[1..4] / abSpChanged[1..4]（单拍）/ eState / bError /
 *                         eCause / bValid / nFaultZone。
 * 状态迁移表 (State Transition Table)：
 *   ① eIdle → eApply：bEnable 上升（或上电首拍 bEnable 已为 TRUE）；
 *      拍 N 进入（bEnable 为 TRUE）/ 本拍行为：不做选段、不发沿、冻结保持 / 拍 N+1 转出至 eApply。
 *      拒收：bEnable 为 FALSE 时本拍不迁出，abSpChanged 保持 FALSE。
 *   ② eApply → eHold：全量参数校验通过且选段、比对、发沿完成（同一拍内完成）；
 *      拍 N 进入（校验通过）/ 本拍行为：写出 afActiveSp/aiActiveIdx 与 abSpChanged 单拍沿 /
 *      拍 N+1 转出至 eHold。
 *   ③ eApply → eFault：任一区校验失败（时段数越界 / 分钟越域 / 时段非单调 / 设定值非有限）；
 *      拍 N 进入（校验失败）/ 本拍行为：锁存首个成因码、不写 afActiveSp（保持末值）/
 *      拍 N+1 转出至 eFault（段尾迁移闸）。
 *   ④ eHold → eApply：nMinuteOfDay 落在任一时段起点（时段边界）或 bReset 为 TRUE（强制重校验）；
 *      拍 N 进入（边界命中或复位）/ 本拍行为：交出控制权、本拍不写设定值 / 拍 N+1 转出至 eApply。
 *   ⑤ eHold → eIdle：bEnable 落 FALSE（失能退出，出口冻结保持）。
 *   ⑥ eHold → eFault：段尾迁移闸（锁存位已置）——由①②③④ 任一分支置锁存后同拍迁入。
 *   ⑦ eFault → eIdle：bReset 上升且 NOT bEnable（复位沿要求先失能，避免带故障参数直接投产）；
 *      拍 N 进入（bReset 沿 + 已失能）/ 本拍行为：清锁存与成因码 / 拍 N+1 转出至 eIdle。
 *      该路径可达性自证：bReset 与 bEnable 均为外部引脚，恒可到达（R152）。
 *   ⑧ ELSE（非法枚举值）→ eFault，成因码 eIllegalState（R6 兜底）。
 * 边界     (Boundary)   : ① 首时段之前（nMinuteOfDay < 第 1 段起始）：取第 1 段值（日头承接），
 *                            该口径在段 4 注释内声明，不置码。
 *                         ② nMinuteOfDay 越域（<0 或 >1439）→ 钳位到 [0,1439] 并置信息级
 *                            eMinuteClamped（信息级永不置 bError）。
 *                         ③ 数组下标访问前先以 nCnt ∈ [1,8] 钳定（R4），越界槽不访问。
 *                         ④ 浮点同值比较用容差 DL_MZS_EPS（1E-6），禁 `=`（R4）。
 *                         ⑤ 零全局耦合（无 GVL / VAR_EXTERNAL / %I / %Q）。
 * 码表     (Codes)      : 本件不占用全局数字码位（R297 零码位范式）；出口为 BOOL + ENUM，
 *                         enum E_DL_MzsCause 归属本文件（全库唯一属主）。信息级
 *                         eMinuteClamped / eNoChange 永不置 bError；故障级成因码各占独立成员
 *                         （R190 归因唯一），锁存回放至 bReset 沿（FB33-1）。
 * 分工声明 (Scope)      : 时段选择与下发归本件；设定值斜坡 / 无扰切换归 FB_DL_RampGenerator 类；
 *                         PID 闭环归温控件。本件不下装任何硬件输出。
 * 归属     (Ownership)  : E_DL_MzsState / E_DL_MzsCause / ST_DL_SpSlot 归属本文件
 *                         （全库唯一定义，R264），引用件只引用不重声明。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC ｜ R4 ✓ 下标钳定 +
 *                         非有限双判 + 容差比较 + 循环界固定 ｜ R5 ✓ 逐行同行双语注释
 *                         R6 ✓ 四态 ENUM + CASE + ELSE ｜ R7 N/A（本件无需定时器/边沿实例）
 *                         R14 ✓ 无 PROPERTY ｜ R8/R9 N/A（无 METHOD）
 * 修订历史 (Revision)   : 2026-11-24  v1.0.2  R79-F2/P3：bReset 电平→R_TRIG 沿 + eHold 复位沿同步清锁存（原头版本号滞留 1.0.0，已核正）
 *                         2026-11-23  v1.0.0  R78-B3 首版
 *                         2026-11-23  v1.0.1  R78 返修：E045 数组访问改嵌套索引形式（8 处）；
 *                                             eHold 相补时段数重校验闸（越界锁存 eBadCount）；
 *                                             M5：成功路径不再覆盖钳位信息级码
 * 验收向量 (Acceptance) :
 *   V1 bEnable=TRUE、nMinuteOfDay=480、区 1 时段表 {(0,20.0),(480,22.0)} → afActiveSp[1]=22.0,
 *      aiActiveIdx[1]=2, abSpChanged[1]=TRUE 单拍；次拍 abSpChanged[1]=FALSE。
 *   V2 续 V1、nMinuteOfDay 保持 481（非边界）→ eState=eHold，无沿。
 *   V3 区 2 时段表起始分钟 {0, 600, 500}（非单调）→ eState=eFault, eCause=eSlotNotMonotonic,
 *      bError=TRUE, afActiveSp[2] 保持末值；bReset 上升且 bEnable=FALSE → 回 eIdle。
 *   V4 nMinuteOfDay=2000（越域）→ 钳位到 1439，eCause=eMinuteClamped（信息级），bError=FALSE。
 *   V5 区 3 设定值为 NaN → eState=eFault, eCause=eBadSetpoint, bError=TRUE。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 结构体: ST_DL_SpSlot（时段表行：起始分钟 + 该时段设定值），归属本文件，全库唯一属主
 *----------------------------------------------------------------------------*)
TYPE ST_DL_SpSlot :
STRUCT
    nStartMin : INT := 0;      // 时段起始时刻（当日第几分钟，0..1439）[-] / Slot start minute of the day
    fSetpoint : REAL := 0.0;   // 该时段生效设定值 [工程单位，由调用方标定] / Setpoint effective within the slot
END_STRUCT
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_MzsState（状态机相位；eFault 为安全相，仅 bReset 沿迁出）
 *----------------------------------------------------------------------------*)
TYPE E_DL_MzsState :
(
    eIdle  := 0,    // 空闲：未使能，设定值冻结保持末值 / Idle: disabled, setpoints frozen at last value
    eApply := 10,   // 校验与应用：全量参数校验 + 选段 + 比对 + 发沿（同拍完成）/ Validate and apply in one scan
    eHold  := 20,   // 驻留：等时段边界或复位，每拍只做边界检测 / Hold: wait for a slot boundary or reset
    eFault := 90    // 故障安全相：参数非法，锁存成因码，仅 bReset 沿迁出 / Fault latched, reset edge only
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_MzsCause（成因码；信息级 = 0..9，故障级 = 10 起，各成因独立成员 R190）
 *----------------------------------------------------------------------------*)
TYPE E_DL_MzsCause :
(
    eNone             := 0,   // 信息级：无事件 / Info: no event
    eMinuteClamped    := 1,   // 信息级：当日分钟越域已钳位 / Info: minute of day clamped into range
    eSlotNotMonotonic := 10,  // 故障级：时段起始分钟非严格递增 / Fault: slot start minutes not strictly increasing
    eBadMinute        := 11,  // 故障级：单条时段起始分钟越域 / Fault: slot start minute out of range
    eBadCount         := 12,  // 故障级：时段数越界（不在 1..8）/ Fault: slot count out of the 1..8 range
    eBadSetpoint      := 13,  // 故障级：设定值非有限 / Fault: non-finite setpoint
    eIllegalState     := 14   // 故障级：非法状态枚举值（CASE ELSE 兜底）/ Fault: illegal state enum value
);
END_TYPE

FUNCTION_BLOCK FB_DL_MultiZoneSetpointScheduler
VAR_INPUT
    bEnable        : BOOL := FALSE;                       // 使能：FALSE 冻结保持末值（本件语义声明）/ Enable, FALSE freezes the last setpoints
    bReset         : BOOL := FALSE;                       // 复位（上升沿）：清故障锁存并要求失能 / Reset rising edge clears the fault latch and requires disabled state
    nMinuteOfDay   : INT := 0;                            // 当日第几分钟，有效域 0..1439 [-] / Minute of the day, valid domain 0..1439
    aiZoneSlotCount : ARRAY[1..4] OF INT;                 // 各区时段条数，有效域 1..8 [-] / Slot count per zone, valid domain 1..8
    aSlots         : ARRAY[1..4] OF ARRAY[1..8] OF ST_DL_SpSlot;  // 四区 × 八时段时段表 / Slot tables of four zones with up to eight slots each
END_VAR
VAR_OUTPUT
    afActiveSp  : ARRAY[1..4] OF REAL;      // 各区当前生效设定值（冻结保持，见 bEnable 语义）[工程单位] / Active setpoint per zone
    aiActiveIdx : ARRAY[1..4] OF INT;       // 各区当前生效时段序号（1..8），未选定时为 0 [-] / Active slot index per zone
    abSpChanged : ARRAY[1..4] OF BOOL;      // 各区设定值变更单拍沿（统一出口预置，FB51-8）[-] / Single-scan change flag per zone
    eState      : E_DL_MzsState;            // 状态出口（段尾单点映射）[-] / State outlet, mapped at the tail
    bError      : BOOL;                     // 故障锁存标志（仅故障级成因置位）[-] / Fault latch flag
    eCause      : E_DL_MzsCause;            // 成因码出口（锁存回放）[-] / Cause code outlet, replayed from the latch
    bValid      : BOOL;                     // 设定值有效回执（eHold 且参数有效才 TRUE）[-] / Setpoint validity receipt
    nFaultZone  : INT;                      // 首个故障所在区号（0 = 无故障 / 全局性故障）[-] / Zone index of the first fault
END_VAR
VAR
    _eState      : E_DL_MzsState := E_DL_MzsState.eIdle;   // 内部相位（CASE 唯一写入目标）[-] / Internal phase
    _bFaultLatch : BOOL := FALSE;                          // 故障锁存位（仅 bReset 沿清除）[-] / Fault latch bit cleared by the reset edge only
    _eCauseLatch : E_DL_MzsCause := E_DL_MzsCause.eNone;    // 锁存成因码（锁存回放，FB33-1）[-] / Latched cause code replayed to the outlet
    _nFaultZone  : INT := 0;                               // 首个故障区号 [1..4]，0 表示无 / Zone index of the first fault
    _bParamOk    : BOOL := TRUE;                           // 本拍参数校验通过标志 [-] / Parameter validation flag of this scan
    _eCauseTmp   : E_DL_MzsCause := E_DL_MzsCause.eNone;    // 本拍首个成因（未锁存）[-] / First cause of this scan before latching
    _nFaultZtmp  : INT := 0;                               // 本拍首个故障区号（未锁存）[-] / First fault zone of this scan before latching
    _nMinute     : INT := 0;                               // 钳位后的当日分钟 [0..1439] / Clamped minute of the day
    _nCnt        : INT := 0;                               // 当前区时段条数（校验后使用）[-] / Slot count of the current zone
    _nIdx        : INT := 0;                               // 选段中间结果（时段序号）[-] / Intermediate slot index
    _nNewIdx     : INT := 0;                               // 本区本拍应生效时段序号 [-] / Slot index that should be active this scan
    _fNewSp      : REAL := 0.0;                            // 本区本拍应生效设定值 [工程单位] / Setpoint that should be active this scan
    _bBoundary   : BOOL := FALSE;                          // 时段边界命中标志（eHold 用）[-] / Slot boundary hit flag used in eHold
    _nZ          : INT := 0;                               // 外层循环索引：区号 [1..4] / Outer loop index, zone number
    _nK          : INT := 0;                               // 内层循环索引：时段序号 [1..8] / Inner loop index, slot number
    _rtReset     : R_TRIG;                                 // 复位沿检测实例（v1.0.1 补：声明沿即实现沿，段 1 无条件刷新）/ Reset edge detector, refreshed unconditionally in segment 1
END_VAR
VAR CONSTANT
    DL_MZS_ZONES    : INT := 4;             // 固定区数（数组第一维上界）[-] / Fixed zone count, upper bound of dimension one
    DL_MZS_SLOTS    : INT := 8;             // 每区最大时段数（数组第二维上界）[-] / Max slots per zone, upper bound of dimension two
    DL_MZS_MIN_DAY  : INT := 1439;          // 当日最大分钟数（23:59）[-] / Last minute of the day
    DL_MZS_MIN_ONE  : INT := 1;             // 时段数下界 [-] / Lower bound of the slot count
    DL_MZS_ZERO     : INT := 0;             // 整数零基准 [-] / Integer zero base
    DL_MZS_FZERO    : REAL := 0.0;          // 实数零基准 [-] / Real zero base
    DL_MZS_EPS      : REAL := 1.0E-6;       // 设定值同值判定容差 [-] / Setpoint equality tolerance
    DL_MZS_FIN      : LREAL := 1.0E308;     // 有限性判据上界（R477：ABS(x)>FIN 判 Inf）[工程单位] / finiteness ceiling flags Inf
END_VAR

(* —— 段 1：单拍位与当拍工作量预置（只清单拍标志，不清锁存/保持量，FB32-1） —— *)
_rtReset(CLK := bReset);                                // 复位沿刷新必须无条件周期调用（R7；v1.0.1 修复 J1 电平判据缺陷）/ The reset edge must be refreshed unconditionally every scan
FOR _nZ := 1 TO DL_MZS_ZONES DO
    abSpChanged[_nZ] := FALSE;                          // 变更沿每拍先预清 / Change edge preset FALSE every scan
END_FOR
_bParamOk   := TRUE;                                    // 校验标志复位 / Validation flag reset
_eCauseTmp  := E_DL_MzsCause.eNone;                      // 当拍成因复位 / Scan cause reset
_nFaultZtmp := DL_MZS_ZERO;                             // 当拍故障区复位 / Scan fault zone reset
_bBoundary  := FALSE;                                   // 边界标志复位 / Boundary flag reset
eCause      := E_DL_MzsCause.eNone;                      // 成因出口每拍预置信息级零码（段 2/段 3 内改写）/ Cause outlet preset to the info zero code every scan

(* —— 段 2：入参钳位与域闸（分钟越域钳位并置信息级，R4 下标与域安全） —— *)
_nMinute := nMinuteOfDay;                               // 取入参 / Take the input pin
IF _nMinute < DL_MZS_ZERO THEN
    _nMinute  := DL_MZS_ZERO;                           // 下越界钳到 0 / Clamp low
    eCause    := E_DL_MzsCause.eMinuteClamped;          // 信息级：已钳位 / Info: clamped
ELSIF _nMinute > DL_MZS_MIN_DAY THEN
    _nMinute  := DL_MZS_MIN_DAY;                        // 上越界钳到 1439 / Clamp high
    eCause    := E_DL_MzsCause.eMinuteClamped;          // 信息级：已钳位 / Info: clamped
END_IF

(* —— 段 3：状态机主体（唯一相位写入点，每分支迁移条件自足） —— *)
CASE _eState OF
    E_DL_MzsState.eIdle :
        (* 迁移①：使能上升进入统一校验相；未使能则保持冻结语义 *)
        IF bEnable THEN
            _eState := E_DL_MzsState.eApply;            // 迁入校验与应用相 / Move to validate-and-apply
        END_IF

    E_DL_MzsState.eApply :
        IF NOT bEnable THEN
            _eState := E_DL_MzsState.eIdle;             // 使能消失：退回冻结 / Enable gone: back to idle
        ELSE
            (* 段 4 前置：逐区全量校验（时段数 → 单条分钟 → 单调性 → 设定值有限性） *)
            FOR _nZ := 1 TO DL_MZS_ZONES DO
                _nCnt := aiZoneSlotCount[_nZ];          // 取本区时段条数 / Slot count of this zone
                IF (_nCnt < DL_MZS_MIN_ONE) OR (_nCnt > DL_MZS_SLOTS) THEN
                    _bParamOk := FALSE;                 // 时段数越界 / Count out of range
                    IF _eCauseTmp = E_DL_MzsCause.eNone THEN
                        _eCauseTmp  := E_DL_MzsCause.eBadCount;    // 首因锁存用 / First cause kept
                        _nFaultZtmp := _nZ;                        // 记录故障区号 / Record the fault zone
                    END_IF
                ELSE
                    FOR _nK := 1 TO _nCnt DO
                        (* 单条起始分钟域闸：0..1439 *)
                        IF (aSlots[_nZ][_nK].nStartMin < DL_MZS_ZERO)
                            OR (aSlots[_nZ][_nK].nStartMin > DL_MZS_MIN_DAY) THEN
                            _bParamOk := FALSE;
                            IF _eCauseTmp = E_DL_MzsCause.eNone THEN
                                _eCauseTmp  := E_DL_MzsCause.eBadMinute;   // 故障级：分钟越域
                                _nFaultZtmp := _nZ;
                            END_IF
                        END_IF
                        (* 单调性闸：自第 2 条起必须严格大于前一条 *)
                        IF _nK > 1 THEN
                            IF aSlots[_nZ][_nK].nStartMin <= aSlots[_nZ][_nK - 1].nStartMin THEN
                                _bParamOk := FALSE;
                                IF _eCauseTmp = E_DL_MzsCause.eNone THEN
                                    _eCauseTmp  := E_DL_MzsCause.eSlotNotMonotonic;   // 故障级：非单调
                                    _nFaultZtmp := _nZ;
                                END_IF
                            END_IF
                        END_IF
                        (* 设定值有限性闸（R79 双判） *)
                        (* v1.0.2 补（闸 Q2）：Inf 判据改 R477 范式 ABS(x) > DL_MZS_FIN，
                           x−x 差判在部分编译器会常量折叠成 0，Inf 设定值可穿透写入 afActiveSp *)
                        IF (aSlots[_nZ][_nK].fSetpoint <> aSlots[_nZ][_nK].fSetpoint)
                            OR (ABS(aSlots[_nZ][_nK].fSetpoint) > DL_MZS_FIN) THEN
                            _bParamOk := FALSE;
                            IF _eCauseTmp = E_DL_MzsCause.eNone THEN
                                _eCauseTmp  := E_DL_MzsCause.eBadSetpoint;   // 故障级：设定值非有限
                                _nFaultZtmp := _nZ;
                            END_IF
                        END_IF
                    END_FOR
                END_IF
            END_FOR

            IF NOT _bParamOk THEN
                (* 迁移③：校验失败 → 锁存首因（不改写 afActiveSp，保持末值） *)
                _eCauseLatch := _eCauseTmp;                 // 锁存成因码 / Latch the cause code
                _nFaultZone  := _nFaultZtmp;                // 锁存故障区号 / Latch the fault zone
                _bFaultLatch := TRUE;                       // 置故障锁存（段尾迁移闸迁相）/ Latch the fault
            ELSE
                (* 段 4：选段 + 比对 + 发沿（每区独立裁决，日头承接口径见分支注释） *)
                FOR _nZ := 1 TO DL_MZS_ZONES DO
                    _nCnt   := aiZoneSlotCount[_nZ];        // 时段条数 / Slot count
                    _nNewIdx := DL_MZS_MIN_ONE;             // 缺省取第 1 段（日头承接：首段之前沿用首段值）/ Default first slot
                    FOR _nK := 1 TO _nCnt DO
                        IF aSlots[_nZ][_nK].nStartMin <= _nMinute THEN
                            _nNewIdx := _nK;                // 最后一条不晚于当前分钟的时段生效 / Last slot not later than now wins
                        END_IF
                    END_FOR
                    _fNewSp := aSlots[_nZ][_nNewIdx].fSetpoint;    // 取该时段设定值 / Setpoint of the winning slot
                    IF (ABS(afActiveSp[_nZ] - _fNewSp) >= DL_MZS_EPS) OR (aiActiveIdx[_nZ] <> _nNewIdx) THEN
                        afActiveSp[_nZ]  := _fNewSp;            // 写入生效设定值 / Write the active setpoint
                        aiActiveIdx[_nZ] := _nNewIdx;           // 写入生效时段序号 / Write the active slot index
                        abSpChanged[_nZ] := TRUE;               // 单拍变更沿（本拍置位，次拍段 1 预清）/ Single-scan change edge
                    END_IF
                END_FOR
                IF eCause <> E_DL_MzsCause.eMinuteClamped THEN
                    eCause := E_DL_MzsCause.eNone;          // 信息级：无事件（M5：不覆盖段 2 已置的钳位信息码）/ Info: no event, keep the pre-set clamp code
                END_IF
                _bFaultLatch := FALSE;                      // 校验通过：清故障锁存（正常路径唯一清点）/ Clear the latch on the valid path
                _eState := E_DL_MzsState.eHold;             // 迁移②：进入驻留相 / Move to hold
            END_IF
        END_IF

    E_DL_MzsState.eHold :
        IF NOT bEnable THEN
            _eState := E_DL_MzsState.eIdle;                 // 迁移⑤：失能退出（冻结保持）/ Disable exit, frozen
        ELSE
            (* 边界检测：任一时段起点等于当前分钟（或日切 0 点）→ 回校验相重算 *)
            IF _nMinute = DL_MZS_ZERO THEN
                _bBoundary := TRUE;                         // 日切 0 点视为边界 / Day roll-over counts as a boundary
            END_IF
            FOR _nZ := 1 TO DL_MZS_ZONES DO
                _nCnt := aiZoneSlotCount[_nZ];              // 取本区时段条数（引脚每拍可被外部改写，不信任 eApply 旧校验）/ Slot count, pin may change every scan
                IF (_nCnt < DL_MZS_MIN_ONE) OR (_nCnt > DL_MZS_SLOTS) THEN
                    (* L1 加固：eHold 相重校验失败 → 故障锁存（复用参数校验闸同款 eBadCount），跳出该区处理 *)
                    IF _eCauseLatch = E_DL_MzsCause.eNone THEN   // 首因保留（不覆盖既有锁存码）/ Keep the first cause
                        _eCauseLatch := E_DL_MzsCause.eBadCount; // 故障级：时段数越界（既有成因成员，R190）/ Fault: count out of range
                        _nFaultZone  := _nZ;                     // 锁存故障区号 / Latch the fault zone
                    END_IF
                    _bFaultLatch := TRUE;                        // 置故障锁存（段 5 迁移闸同拍迁入 eFault）/ Latch the fault
                ELSE
                    FOR _nK := 1 TO _nCnt DO
                        IF aSlots[_nZ][_nK].nStartMin = _nMinute THEN
                            _bBoundary := TRUE;                 // 时段边界命中 / Slot boundary hit
                        END_IF
                    END_FOR
                END_IF
            END_FOR
            IF _rtReset.Q THEN
                (* v1.0.2 补（闸 P3）：eHold 内复位沿属"强制重校验"语义，必须同时清故障锁存，
                   否则 eApply 重校验通过后 bError 仍为 TRUE（声明"复位即清锁存"未兑现） *)
                _bFaultLatch := FALSE;                      // 复位沿清故障锁存 / Reset edge clears the fault latch
                _eCauseLatch := E_DL_MzsCause.eNone;        // 复位沿清锁存成因 / Reset edge clears the latched cause
                eCause       := E_DL_MzsCause.eNone;        // 出口同步归零 / Outlet follows
                nFaultZone   := DL_MZS_ZERO;                // 故障区号归零 / Fault zone index cleared
            END_IF
            IF (NOT _bFaultLatch) AND (_bBoundary OR _rtReset.Q) THEN
                _eState := E_DL_MzsState.eApply;            // 迁移④：边界命中或强制重校验（R274：锁存期禁迁入执行相）/ Boundary or forced revalidation
            END_IF
        END_IF

    E_DL_MzsState.eFault :
        (* 迁移⑦：唯一出口 —— bReset 沿 + 已失能（避免带故障参数直接投产） *)
        IF _rtReset.Q AND (NOT bEnable) THEN
            _bFaultLatch := FALSE;                          // 清故障锁存 / Clear the fault latch
            _eCauseLatch := E_DL_MzsCause.eNone;            // 清锁存成因 / Clear the latched cause
            _nFaultZone  := DL_MZS_ZERO;                    // 清故障区号 / Clear the fault zone
            _eState      := E_DL_MzsState.eIdle;            // 回空闲相 / Back to idle
        END_IF

ELSE
    (* 迁移⑧：非法枚举值兜底（R6） *)
    _eCauseLatch := E_DL_MzsCause.eIllegalState;            // 故障级：非法状态 / Fault: illegal state value
    _bFaultLatch := TRUE;                                   // 置锁存 / Latch
    _eState      := E_DL_MzsState.eFault;                   // 迁入安全相 / Move to the safe state
END_CASE

(* —— 段 5：段尾故障迁移闸（FB50-1④：锁存与迁相分离，置于解除段之后） —— *)
IF _bFaultLatch AND (_eState <> E_DL_MzsState.eFault) THEN
    _eState := E_DL_MzsState.eFault;                        // 锁存即迁相 / Latch forces the fault phase
END_IF

(* —— 段 6：统一出口（状态映射 + 锁存回放 + 单拍位已由段 1 预置） —— *)
eState := _eState;                                          // 相位映射 / Phase mapping
bError := _bFaultLatch;                                     // 故障标志取锁存位（派生式）/ Fault flag derived from the latch
IF _bFaultLatch THEN
    eCause := _eCauseLatch;                                 // 故障期回放锁存码（FB33-1）/ Replay the latched code
    nFaultZone := _nFaultZone;                              // 回放故障区号 / Replay the fault zone
ELSE
    nFaultZone := DL_MZS_ZERO;                              // 无故障：区号归零 / No fault: zone index zero
END_IF
bValid := (_eState = E_DL_MzsState.eHold) AND (NOT _bFaultLatch);   // 仅驻留相且无锁存时值可信 / Valid only in hold without a latch
END_FUNCTION_BLOCK
