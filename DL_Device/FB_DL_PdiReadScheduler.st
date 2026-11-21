(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PdiReadScheduler
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 设备诊断 · 无环读取调度
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅标准 TON / R_TRIG 与位运算
 * 功能描述 (Function)   : 面向参数、诊断、信息类无环读取的通用调度器。把「请求
 *                         描述域（槽、子槽、索引、子索引）加结果域（错误码、
 *                         附加信息、数据长度）」抽象成与总线无关的调度件，
 *                         硬件侧经抽象桩引脚注入就绪、完成、错误码、附加信息
 *                         与实际长度。换 RTU、换 TCP、换本地总线只换传输层，
 *                         调度层零改动。
 * 与既有件边界 (Boundary): FB_DL_ModbusPollMaster 是帧级轮询（多从站选址、
 *                         帧间静默），本件是对象字典级 PDI 调度，不触碰帧结构；
 *                         两者状态机与参数域完全不同，不得合并。
 * 工程纪律 (Discipline) : 无环通信耗时可达数十毫秒，禁止在实时任务内阻塞等待。
 *                         本块以「单拍只下发一条、忙时拒绝新启动、不排队」实现
 *                         该纪律：排队会让上层误以为指令已生效，且拖尾会累积
 *                         到下一个任务周期。
 * 设计要点 (Key notes)  : ① 请求域在启动沿一次性锁存，执行中调用方改入参不影响
 *                           在途请求；重试沿用同一锁存域，不取入参当前值；
 *                         ② 成功判据同时看错误码与数据长度：只看错误码会把
 *                           「返回长度不足」误判成功，这是无环读最常见的假成功；
 *                         ③ 失败耗尽不锁死：单次失败只记账并回待机，只有同一
 *                           请求连续三轮失败才锁故障，避免一根线缆抖动就停线；
 *                         ④ 超时用自有码（低 16 位为 5），不与总线错误码混用；
 *                         ⑤ 双层错误码打包：高 16 位附加信息、低 16 位错误码，
 *                           解包示例写在注释中，便于 HMI 直接拆。
 * 开源溯源 (Origin)     : plcnext-community。参考 PLCnext 官方公开文档所述的
 *                         无环读参数域（设备号、子设备号、对象索引、对象子索引）
 *                         与双层结果域（错误码与附加信息），以及「无环通信耗时
 *                         较长、不宜在实时任务中直接调用」的工程纪律。只借参数
 *                         域与纪律，结构体布局、状态机、码位 100% 自有
 *                         clean-room，不构成衍生作品。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 TON / R_TRIG
 * 故障码表 (Error codes):
 *   16#0003_013D【信息级】槽号或子槽号越界被钳位
 *   16#0003_013E【信息级】索引或子索引越界被钳位
 *   16#0003_013F【信息级】期望长度或单次超时越界被钳位
 *   16#0003_02F7【故障级】本次读取失败或超时且重试耗尽
 *   16#0003_02F8【故障级】非法状态兜底
 *   16#0003_02F9【故障级】同一请求连续三轮失败，锁定
 *   结果域自有码（写入 uErrCode 的低 16 位，不与总线码混用）：
 *   16#0000_0004 服务不可用（未使能或服务未就绪）
 *   16#0000_0005 超时
 * 验收向量 (Acceptance) :
 *   V1 成功链：服务就绪、域合法 → 启动一拍 → 请求激活 → 完成一拍且错误码 0、
 *      长度 4 → 完成脉冲单拍、成功为真、成功计数 1
 *   V2 忙时拒绝：等待期间再启动 → 拒绝计数 1、请求保持、不排队
 *   V3 重试：重试上限 1、连续两次错误码 16#0080 → 共 2 次下发后失败完成、
 *      失败计数 1、码 02F7
 *   V4 超时：不给完成信号、超时 1 秒 → 1 秒后失败完成、低 16 位为 5、
 *      请求撤回
 *   V5 打包解包：错误码 16#8011、附加信息 16#0002 → 打包值 16#0002_8011
 *   V6 长度不符：期望 8、实际 4、错误码 0 → 判失败（不得只看错误码）
 * 红线自检 (Redline)    : R1 零全局变量表与外部变量引用 ｜ R2 零物理地址直写
 *                         R3 纯 IEC 61131-3 ｜ R4 打包前显式类型转换、无浮点、
 *                         无除法 ｜ R5 全变量中英双语同行注释
 *                         R6 ENUM 加 CASE 加 ELSE 兜底 ｜ R7 TON 与两个 R_TRIG
 *                         全部在 CASE 之外无条件刷新
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 10 · T1-7 PLCnext 开组）
 *   2026-11-15  v1.0.1  R10 终审修复两处：
 *                       R-FIX-1【中等】单次超时直接送进定时器 PT，未做参数域
 *                       钳位（DL_TMO_MIN / DL_TMO_MAX 两个常量声明后从未使用），
 *                       PT 填 0 会让每个等待拍立即超时形成重试风暴；补钳位并
 *                       并入 013F 参数域钳位事件（本组件码位块 013D~013F 已满，
 *                       按 R30 不得跨块取 0140，故共用 013F 并在码表说明）；
 *                       R-FIX-2【注释级】码表 013F 语义同步扩为「期望长度或
 *                       单次超时越界」。
 *============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_PdiFsm（归属本功能块并同文件发布）
 *-----------------------------------------------------------------------------*)
TYPE E_DL_PdiFsm :
(
    eIdle  := 0,     // 待机：可受理启动沿 / Idle, accepts a start edge
    eSend  := 10,    // 下发：单拍锁存请求域并置请求激活 / Send, latches the request domain for one cycle
    eWait  := 20,    // 等待完成或超时 / Waiting for done or timeout
    eRetry := 30,    // 重试退避：单拍停留后重新下发 / Retry back-off, one cycle dwell then re-send
    eFault := 99     // 故障锁定：仅失能再使能可退 / Fault latched, only a disable-enable cycle leaves
);
END_TYPE

FUNCTION_BLOCK FB_DL_PdiReadScheduler
VAR_INPUT
    bEnable      : BOOL := TRUE;      // 使能 [-] / Enable
    bStart       : BOOL;              // 启动单次读取，上升沿；忙时忽略并计一次拒绝 [-] / Start a single read on a rising edge, ignored while busy
    uSlot        : UINT := 0;         // 设备号（槽），域 0 到 4095 [号] / Device slot number, 0 to 4095
    uSubslot     : UINT := 1;         // 子设备号（子槽），域 0 到 255 [号] / Sub-device subslot number, 0 to 255
    uIndex       : UINT := 0;         // 对象索引，域 0 到 65535 [索引] / Object index, 0 to 65535
    uSubindex    : USINT := 0;        // 对象子索引，域 0 到 255 [子索引] / Object subindex, 0 to 255
    nExpLen      : INT := 0;          // 期望数据长度，域 0 到 1024，0 表示不限 [字节] / Expected length, 0 means unrestricted
    tTimeout     : TIME := T#1S;      // 单次超时，域 100 毫秒到 10 秒 [毫秒] / Single-request timeout, 100 ms to 10 s
    nMaxRetry    : INT := 0;          // 重试次数，域 0 到 3，PDI 重试须保守 [次] / Retry count, 0 to 3, PDI retries must stay conservative
    bSrvReady    : BOOL;              // 传输层服务就绪 [-] / Transport service ready
    bSrvDone     : BOOL;              // 传输层服务完成，电平或单拍，内部取沿 [-] / Transport service done, edge detected internally
    uSrvError    : WORD;              // 服务错误码（低 16 位）[代码] / Service error code, low word of the packed result
    uSrvAddInfo  : WORD;              // 服务附加信息（高 16 位）[代码] / Service additional information, high word of the packed result
    uSrvLen      : UINT;              // 实际返回数据长度 [字节] / Actual returned data length
END_VAR
VAR_OUTPUT
    bReqActive   : BOOL;              // 请求已下发，送传输层的启动信号 [-] / Request asserted towards the transport layer
    bDone        : BOOL;              // 本次读取完成，单拍（成功或失败均置）[-] / Request finished, single-cycle pulse
    bSuccess     : BOOL;              // 本次读取成功，与完成同拍有效 [-] / TRUE when the request succeeded
    uErrCode     : UDINT;             // 双层错误码打包：高 16 位附加信息，低 16 位错误码 [代码] / Packed error code
    uActLen      : UINT;              // 实际数据长度 [字节] / Actual data length
    nRejectCnt   : UDINT;             // 忙时拒绝启动次数，跨班不清零 [次] / Busy rejection counter
    nOkCnt       : UDINT;             // 成功次数 [次] / Successful request counter
    nFailCnt     : UDINT;             // 失败次数（含重试耗尽）[次] / Failed request counter
    uErrorId     : UDINT;             // 事件码，0 = 无事件 / Event code, 0 = no event
    bError       : BOOL;              // 故障锁存，仅故障级码置位 [-] / Fault latch, set only by fault-level codes
END_VAR
VAR
    fbTrigStart  : R_TRIG;            // 启动沿检测，CASE 之外无条件刷新 [-] / Rising edge detector for the start input
    fbTrigDone   : R_TRIG;            // 完成沿检测，CASE 之外无条件刷新 [-] / Rising edge detector for the done input
    fbTmo        : TON;               // 超时计时，CASE 之外无条件刷新 [-] / Timeout timer refreshed outside the CASE
    bInit        : BOOL := FALSE;     // 首扫标志，初值 FALSE，判据 NOT bInit（R19 范式）[-] / First-scan flag
    bTmoIn       : BOOL;              // 超时定时器输入条件，先算后调以免条件调用实例 [-] / Timer input condition computed before the call
    eState       : E_DL_PdiFsm := E_DL_PdiFsm.eIdle;  // 状态机 / State machine
    nRetry       : INT;               // 本次请求已重试次数 [次] / Retries spent on the current request
    nRetryUse    : INT;               // 生效重试上限（已钳位）[次] / Effective retry limit
    nExpUse      : INT;               // 锁存的期望长度，重试沿用 [字节] / Latched expected length reused on retries
    uReqSlot     : UINT;              // 锁存的槽号 [号] / Latched slot number
    uReqSub      : UINT;              // 锁存的子槽号 [号] / Latched subslot number
    uReqIdx      : UINT;              // 锁存的索引 [索引] / Latched object index
    uReqSubIdx   : USINT;             // 锁存的子索引 [子索引] / Latched object subindex
    uSlotC       : UINT;              // 钳位后的槽号 [号] / Clamped slot number
    uSubC        : UINT;              // 钳位后的子槽号 [号] / Clamped subslot number
    nExpC        : INT;               // 钳位后的期望长度 [字节] / Clamped expected length
    tTmoUse      : TIME := T#1S;      // 钳位后的单次超时，供定时器实例使用 [毫秒] / Clamped timeout fed to the timer instance
    bOk          : BOOL;              // 本次完成的成功判据 [-] / Success predicate of the finished request
    nConsecFail  : INT;               // 同一请求连续失败轮数 [轮] / Consecutive failure rounds
    bEnablePrev  : BOOL := FALSE;     // 上拍使能值，用于失能再使能沿检测 [-] / Previous enable value for the re-enable edge
    bEnableRise  : BOOL;              // 失能再使能沿 [-] / Disable-then-enable edge
END_VAR
VAR CONSTANT
    DL_SLOT_MAX    : UINT := 4095;      // 槽号上限 [号] / Slot upper bound
    DL_SUBSLOT_MAX : UINT := 255;       // 子槽上限 [号] / Subslot upper bound
    DL_DATA_MAX    : INT  := 1024;      // 单次数据长度上限 [字节] / Data length upper bound
    DL_TMO_MIN     : TIME := T#100MS;   // 超时下限 [毫秒] / Timeout lower bound
    DL_TMO_MAX     : TIME := T#10S;     // 超时上限 [毫秒] / Timeout upper bound
    DL_RETRY_MAX   : INT  := 3;         // 重试上限，PDI 重试须保守 [次] / Retry upper bound
    DL_RETRY_MIN   : INT  := 0;         // 重试下限 [次] / Retry lower bound
    DL_FAIL_ROUNDS : INT  := 3;         // 连续失败轮数达到此值即锁故障 [轮] / Consecutive failure rounds before latching a fault
    DL_CODE_UNAVAIL: UDINT := 16#0000_0004;  // 自有码：服务不可用 [代码] / Own code, service unavailable
    DL_CODE_TIMEOUT: UDINT := 16#0000_0005;  // 自有码：超时 [代码] / Own code, timeout
    DL_PACK_SHIFT  : UDINT := 16;            // 打包移位量，附加信息移到高 16 位 [位] / Pack shift for the additional information
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜单拍输出预清零（R25 律①）
 *      Single-cycle output pre-clear
 *-----------------------------------------------------------------------------*)
bDone    := FALSE;
bSuccess := FALSE;

(*------------------------------------------------------------------------------
 * 段 2｜沿检测无条件刷新（R7 红线）
 *      Edge detection refreshed unconditionally
 *-----------------------------------------------------------------------------*)
fbTrigStart(CLK := bStart);
fbTrigDone(CLK := bSrvDone);

(*------------------------------------------------------------------------------
 * 段 3｜首扫初始化（R19 唯一合法范式）
 *      First-scan initialisation with the canonical R19 pattern
 *-----------------------------------------------------------------------------*)
IF NOT bInit THEN
    eState      := E_DL_PdiFsm.eIdle;
    nRetry      := 0;
    nConsecFail := 0;
    nOkCnt      := 0;
    nFailCnt    := 0;
    nRejectCnt  := 0;
    uErrCode    := 16#0000_0000;
    uActLen     := 0;
    bReqActive  := FALSE;
    bError      := FALSE;
    uErrorId    := 16#0000_0000;
    bInit       := TRUE;                 // 首扫只做一次
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜参数域钳位（每拍，信息级）：钳位结果供启动沿锁存
 *      Parameter clamping every cycle; the start edge latches the clamped values
 *      说明：索引与子索引的取值范围由 UINT 与 USINT 类型本身饱和，越界在类型
 *      层面不可达，故 013E 分支当前为防御性保留（位宽扩展后立即生效）
 *-----------------------------------------------------------------------------*)
uSlotC := uSlot;
IF uSlotC > DL_SLOT_MAX THEN
    uSlotC  := DL_SLOT_MAX;
    uErrorId := 16#0003_013D;
END_IF

uSubC := uSubslot;
IF uSubC > DL_SUBSLOT_MAX THEN
    uSubC   := DL_SUBSLOT_MAX;
    uErrorId := 16#0003_013D;
END_IF

IF uIndex > 16#FFFF THEN
    uErrorId := 16#0003_013E;            // 防御性保留分支
END_IF
IF uSubindex > 16#FF THEN
    uErrorId := 16#0003_013E;            // 防御性保留分支
END_IF

nExpC := nExpLen;
IF nExpC < 0 THEN
    nExpC   := 0;
    uErrorId := 16#0003_013F;
ELSIF nExpC > DL_DATA_MAX THEN
    nExpC   := DL_DATA_MAX;
    uErrorId := 16#0003_013F;
END_IF

nRetryUse := nMaxRetry;
IF nRetryUse < DL_RETRY_MIN THEN
    nRetryUse := DL_RETRY_MIN;
ELSIF nRetryUse > DL_RETRY_MAX THEN
    nRetryUse := DL_RETRY_MAX;
END_IF

(* 单次超时钳位：PT 直接决定重试节奏，零或负超时会让每个等待拍立即超时，
   形成无意义的重试风暴，必须在送进定时器之前夹到合法域（红线：无魔法数、
   参数域校验）。超时钳位与期望长度钳位同属「参数域钳位」事件，共用 013F。 *)
tTmoUse := tTimeout;
IF tTmoUse < DL_TMO_MIN THEN
    tTmoUse  := DL_TMO_MIN;
    uErrorId := 16#0003_013F;
ELSIF tTmoUse > DL_TMO_MAX THEN
    tTmoUse  := DL_TMO_MAX;
    uErrorId := 16#0003_013F;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜超时计时（红线：定时器在 CASE 之外无条件刷新）
 *      Timeout timer refreshed unconditionally outside the CASE
 *-----------------------------------------------------------------------------*)
IF eState = E_DL_PdiFsm.eWait THEN
    bTmoIn := TRUE;
ELSE
    bTmoIn := FALSE;
END_IF
fbTmo(IN := bTmoIn, PT := tTmoUse);

(*------------------------------------------------------------------------------
 * 段 6｜失能再使能沿（故障态唯一退出条件）
 *      Disable-then-enable edge, the only way out of the fault state
 *-----------------------------------------------------------------------------*)
IF bEnable AND (NOT bEnablePrev) THEN
    bEnableRise := TRUE;
ELSE
    bEnableRise := FALSE;
END_IF
bEnablePrev := bEnable;

(*------------------------------------------------------------------------------
 * 段 7｜忙时拒绝计数（不排队，单拍只下发一条）
 *      Busy rejection counter, one request per cycle, never queued
 *-----------------------------------------------------------------------------*)
IF fbTrigStart.Q AND (eState <> E_DL_PdiFsm.eIdle) THEN
    nRejectCnt := nRejectCnt + 1;
END_IF

(*------------------------------------------------------------------------------
 * 段 8｜主状态机（ENUM 加 CASE，含 ELSE 兜底）
 *      Main state machine with an ELSE fallback branch
 *-----------------------------------------------------------------------------*)
CASE eState OF
    E_DL_PdiFsm.eIdle:
        bReqActive := FALSE;
        IF fbTrigStart.Q THEN
            IF (NOT bEnable) OR (NOT bSrvReady) THEN
                (* 服务不可用：立即失败完成，失败也置完成脉冲，上层才能推进 *)
                bDone       := TRUE;
                uErrCode    := DL_CODE_UNAVAIL;
                nFailCnt    := nFailCnt + 1;
                nConsecFail := nConsecFail + 1;
            ELSE
                eState := E_DL_PdiFsm.eSend;
            END_IF
        END_IF

    E_DL_PdiFsm.eSend:
        (* 单拍下发：首次下发锁存入参，重试沿用原锁存域（不取入参当前值） *)
        IF nRetry = 0 THEN
            uReqSlot   := uSlotC;
            uReqSub    := uSubC;
            uReqIdx    := uIndex;
            uReqSubIdx := uSubindex;
            nExpUse    := nExpC;
        END_IF
        bReqActive := TRUE;
        uActLen    := 0;
        eState     := E_DL_PdiFsm.eWait;

    E_DL_PdiFsm.eWait:
        bReqActive := TRUE;
        IF fbTrigDone.Q THEN
            (* 打包双层错误码：高 16 位附加信息，低 16 位错误码 *)
            uErrCode := SHL(WORD_TO_UDINT(uSrvAddInfo), DL_PACK_SHIFT) OR WORD_TO_UDINT(uSrvError);
            uActLen  := uSrvLen;
            IF (uSrvError = 16#0000) AND ((nExpUse = 0) OR (uSrvLen >= INT_TO_UINT(nExpUse))) THEN
                bOk         := TRUE;
            ELSE
                bOk         := FALSE;
            END_IF
            IF bOk THEN
                bSuccess    := TRUE;
                bDone       := TRUE;
                nOkCnt      := nOkCnt + 1;
                nConsecFail := 0;
                bReqActive  := FALSE;
                nRetry      := 0;
                eState      := E_DL_PdiFsm.eIdle;
            ELSIF nRetry < nRetryUse THEN
                nRetry     := nRetry + 1;
                bReqActive := FALSE;
                eState     := E_DL_PdiFsm.eRetry;
            ELSE
                (* 重试耗尽：本块只记账不停摆，连续三轮失败才锁故障 *)
                bDone       := TRUE;
                bSuccess    := FALSE;
                nFailCnt    := nFailCnt + 1;
                nConsecFail := nConsecFail + 1;
                bReqActive  := FALSE;
                nRetry      := 0;
                uErrorId    := 16#0003_02F7;
                IF nConsecFail >= DL_FAIL_ROUNDS THEN
                    uErrorId := 16#0003_02F9;
                    bError   := TRUE;
                    eState   := E_DL_PdiFsm.eFault;
                ELSE
                    eState := E_DL_PdiFsm.eIdle;
                END_IF
            END_IF
        ELSIF fbTmo.Q THEN
            (* 超时：撤回请求，用自有码覆盖低 16 位，再走同一重试链 *)
            bReqActive := FALSE;
            uErrCode   := DL_CODE_TIMEOUT;
            IF nRetry < nRetryUse THEN
                nRetry := nRetry + 1;
                eState := E_DL_PdiFsm.eRetry;
            ELSE
                bDone       := TRUE;
                bSuccess    := FALSE;
                nFailCnt    := nFailCnt + 1;
                nConsecFail := nConsecFail + 1;
                nRetry      := 0;
                uErrorId    := 16#0003_02F7;
                IF nConsecFail >= DL_FAIL_ROUNDS THEN
                    uErrorId := 16#0003_02F9;
                    bError   := TRUE;
                    eState   := E_DL_PdiFsm.eFault;
                ELSE
                    eState := E_DL_PdiFsm.eIdle;
                END_IF
            END_IF
        END_IF

    E_DL_PdiFsm.eRetry:
        (* 退避单拍：请求电平拉低一拍，重新下发时自然形成新的上升沿 *)
        bReqActive := FALSE;
        eState     := E_DL_PdiFsm.eSend;

    E_DL_PdiFsm.eFault:
        (* 故障锁定：请求撤回，仅失能再使能可退 *)
        bReqActive := FALSE;
        bError     := TRUE;
        IF bEnableRise THEN
            bError      := FALSE;
            uErrorId    := 16#0000_0000;
            nConsecFail := 0;
            nRetry      := 0;
            eState      := E_DL_PdiFsm.eIdle;
        END_IF

    ELSE
        (* 非法枚举值兜底 *)
        eState     := E_DL_PdiFsm.eFault;
        uErrorId   := 16#0003_02F8;
        bError     := TRUE;
        bReqActive := FALSE;
END_CASE

(*------------------------------------------------------------------------------
 * 段 9｜派生输出与解包示例（注释即文档）
 *      Derived outputs plus a worked unpacking example in comments
 *      解包示例：打包值 16#0002_8011
 *        低 16 位 = UDINT_TO_WORD(打包值 AND 16#0000_FFFF) = 16#8011（错误码）
 *        高 16 位 = UDINT_TO_WORD(SHR(打包值, 16))         = 16#0002（附加信息）
 *      注意：SHR 的移位量必须是常量或已转换的无符号量，禁止直接给有符号值
 *-----------------------------------------------------------------------------*)
IF eState = E_DL_PdiFsm.eFault THEN
    bError := TRUE;
END_IF

(*------------------------------------------------------------------------------
 * 现场提示：
 *   1 请求域在启动沿锁存后，执行期间改入参不会影响在途请求，这是刻意的：
 *     否则重试会用新参数重发，现场表现为「参数被悄悄改掉」；
 *   2 若 bSrvReady 常为假，本块只会不停返回服务不可用而不锁故障，因为这是
 *     上层联锁问题而不是本块缺陷，HMI 应把失败计数与就绪位一起显示；
 *   3 超时值不要设得比总线周期还短，否则会把「还没回」误判成「失败」，
 *     进而引发无意义的重试风暴。
 *-----------------------------------------------------------------------------*)
END_FUNCTION_BLOCK
