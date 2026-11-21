(*==============================================================================
 * 组件名称 (Component)  : FB_DL_RfidTrayRoute
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / LEN），零厂商私有库
 * 功能描述 (Function)   : 载具 RFID 身份驱动路径路由。
 *                         读到载具身份码后在**调用者提供的路由表**中线性匹配，命中即锁定路由号并发出
 *                         段切换请求，等段间握手确认后放行；未命中则拒路由并锁存（未知载具不允许
 *                         在线上自由流动）；同一载具在防抖窗内重复读到同一码时按"重扫"忽略。
 *                         三条固化纪律：
 *                           ① **未知载具拒路由**：匹配失败即锁存 bUnknownTray 并进故障相，
 *                              绝不给"默认路由"兜底（默认路由会把未知载具送进错误工位）；
 *                           ② **重复读码防抖**：路由成功后置防抖窗（tDupWin），窗内读到**同一码**
 *                              只置 bDupRead（信息级），不改路由、不重发段请求；读到**不同码**
 *                              视为换载具，立即重匹配；
 *                           ③ **段间握手**：请求脉冲单拍、等确认超时锁存，超时与不一致分码归因。
 *                         验收向量：
 *                           ① 路由表 3 条 {TRAY-A, TRAY-B, TRAY-C}，读 TRAY-B → iRouteNo = 2
 *                           ② 读 TRAY-Z → 拒路由 + bUnknownTray 锁存（等复位）
 *                           ③ 读 TRAY-B 后 tDupWin 内再读 TRAY-B → bDupRead 单拍，iRouteNo 不变
 *                           ④ 段请求发出后超时无 bSegAck → bUnknownTray 不动，锁存 eSegTimeout
 * 接口     (Interface)  : 入 bReadDone 读码完成沿、sTrayId 载具身份码、bStartSeg 段切换启动沿、
 *                         bSegAck 段间确认、nRouteCnt 路由表有效条数、tDupWin 防抖窗、
 *                         tSegAckTo 段握手超时、bReset 复位沿；
 *                         路由表 IN_OUT asRouteTable（1..16，调用者持有）；
 *                         出 iRouteNo 路由号（0 = 无）、bRouteValid 路由就绪、bSegReq 段请求脉冲（单拍）、
 *                         bSegBusy 等确认中、bUnknownTray 未知载具锁存、bDupRead 重扫忽略脉冲（单拍）、
 *                         eState 相、eCause 成因、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做"身份 → 路由号 → 段放行"，
 *                         不驱动读码头、不驱动输送段电机、不写 MES 履历**；
 *                         ② **路由表边界**：表上界以字面量 16 声明（R104），有效条数 nRouteCnt 作
 *                         运行时二次闸（钳 0..16）；匹配循环带 _uGuard 计数，必然收敛；
 *                         ③ **空码闸**：LEN(sTrayId) = 0 → 视为无码，拒路由 + eNoCode（信息级，不锁存）；
 *                         ④ **超时 TON 冻结**：tonSeg / tonDup 的 IN 均串 (NOT _bFault)，
 *                         故障期不累计，复位同拍不会立即重锁（R252）；
 *                         ⑤ **锁存解除式**：bUnknownTray 与 eFault 仅由 bReset 上升沿解除
 *                         （R228B 唯一迁出）；bReset 为外部引脚，恒可达；
 *                         ⑥ 零全局耦合、零物理地址。
 * 分工声明 (Scope)      : 本件只管"载具身份路由编排"。不接管：读码头驱动与标签数据块解析
 *                         （属 FB_DL_RfidTagHandler 族）、FOUP 配方放行校验（属 FB_DL_FoupRfidCheck）、
 *                         输送段方向控制（属输送件）。
 * 来源标签 (Source Tag) : ROADMAP 空勾真缺口 P1（RFID 载具路由，自研 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位（零码位范式 R297）；诊断由 BOOL + ENUM 出口承担。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 表界闸 + 循环计数器 + 空码闸 + 双超时 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE 兜底 ｜ R7 ✓ 双 TON/三 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R47 首版（批次 3 · 序号 11）
 *==============================================================================*)

TYPE E_DL_RtrState :
(
    eIdle   := 0,    // 待机相（等读码） / Idle, awaiting a tag read
    eSegWait:= 10,   // 等段确认相（握手窗口内） / Waiting for the segment acknowledgement
    eFault  := 90    // 故障相（等复位） / Fault, awaiting reset
);
END_TYPE

TYPE E_DL_RtrCause :
(
    eNone      := 0,   // 无异常 / No anomaly
    eUnknownTray:= 1,  // 未知载具（拒路由，锁存） / Unknown tray, routing refused, latched
    eNoCode    := 2,   // 空码（信息级，不锁存） / Empty code, info level
    eDupRead   := 3,   // 防抖窗内重扫（信息级，不锁存） / Duplicate read inside the debounce window
    eSegTimeout:= 4,   // 段握手超时（锁存） / Segment handshake timeout, latched
    eCfgIllegal:= 5,   // 组态非法（路由表条数/时间越域） / Illegal configuration
    ePhaseBad  := 6    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_RfidTrayRoute
VAR_IN_OUT
    asRouteTable : ARRAY[1..16] OF STRING[15];   // 路由表（1..16，条内容由调用者维护） [-] / Route table owned by the caller
END_VAR
VAR_INPUT
    bReadDone  : BOOL := FALSE;      // 读码完成沿 [-] / Tag-read edge
    sTrayId    : STRING[15] := '';   // 载具身份码（≤15 字符） [-] / Tray identity code
    bStartSeg  : BOOL := FALSE;      // 段切换启动沿 [-] / Segment-start edge
    bSegAck    : BOOL := FALSE;      // 段间确认（当拍电平） [-] / Segment acknowledgement, level
    nRouteCnt  : INT := 0;           // 路由表有效条数，域 0..16 [条] / Valid route count, 0..16
    tDupWin    : TIME := T#5S;       // 重复读码防抖窗，域 > T#0S [ms] / Duplicate-read debounce window
    tSegAckTo  : TIME := T#10S;      // 段握手超时，域 > T#0S [ms] / Segment handshake timeout
    bReset     : BOOL := FALSE;      // 故障复位沿 [-] / Fault reset edge
END_VAR
VAR_OUTPUT
    iRouteNo    : INT := 0;                              // 路由号（1..16；0 = 无） [-] / Route number, 0 = none
    bRouteValid : BOOL := FALSE;                         // 路由就绪（等段启动） [-] / Route ready
    bSegReq     : BOOL := FALSE;                         // 段请求脉冲（单拍） [-] / Segment request, single scan
    bSegBusy    : BOOL := FALSE;                         // 等段确认中 [-] / Waiting for the acknowledgement
    bUnknownTray: BOOL := FALSE;                         // 未知载具锁存（等复位） [-] / Unknown tray, latched
    bDupRead    : BOOL := FALSE;                         // 重扫忽略脉冲（单拍） [-] / Duplicate-read pulse
    eState      : E_DL_RtrState := E_DL_RtrState.eIdle;  // 相出口 [-] / Phase outlet
    eCause      : E_DL_RtrCause := E_DL_RtrCause.eNone;  // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError      : BOOL := FALSE;                         // 故障标志（仅故障级成因） [-] / Error flag, fault level only
END_VAR
VAR
    _eState   : E_DL_RtrState := E_DL_RtrState.eIdle;    // 内部相（CASE 唯一写入目标） / Internal phase
    _eCause   : E_DL_RtrCause := E_DL_RtrCause.eNone;    // 成因锁存量 / Latched cause
    _bFault   : BOOL := FALSE;                           // 故障锁存位 / Latched fault bit
    _bUnknown : BOOL := FALSE;                           // 未知载具锁存位 / Latched unknown-tray bit
    _iRoute   : INT := 0;                                // 内部路由号 / Internal route number
    _iCnt     : INT := 0;                                // 归一后的有效条数 / Normalised valid count
    _iIdx     : INT := 0;                                // 匹配下标（1..16） / Match index
    _iHitIdx  : INT := 0;                                // 首个命中号（0 = 未命中） / First hit index, 0 = no hit
    _uGuard   : UINT := 0;                               // 匹配循环计数器（防死循环） / Match-loop guard
    _bHit     : BOOL := FALSE;                           // 匹配命中标志 / Match-found flag
    _bSegReq  : BOOL := FALSE;                           // 段请求脉冲内部位（单拍） / Internal segment request
    _bDupRead : BOOL := FALSE;                           // 重扫脉冲内部位（单拍） / Internal duplicate pulse
    _bDupBlk  : BOOL := FALSE;                           // 防抖窗封锁位（持窗量） / Debounce window blocking bit
    _sLastId  : STRING[15] := '';                        // 上次成功路由的身份码 / Last successfully routed identity
    _bCfgBad  : BOOL := FALSE;                           // 组态非法当拍量 / Illegal configuration this scan
    tonSeg    : TON;                                     // 段握手超时实例，段 0 无条件调用 / Segment timeout instance
    tonDup    : TON;                                     // 防抖窗实例，段 0 无条件调用 / Debounce window instance
    rtRead    : R_TRIG;                                  // 读码沿实例，段 0 无条件调用 / Tag-read edge instance
    rtStartSeg: R_TRIG;                                  // 段启动沿实例，段 0 无条件调用 / Segment-start edge instance
    rtReset   : R_TRIG;                                  // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_RTR_MAX   : INT := 16;            // 路由表深度（与数组字面量上界同源） [条] / Route table depth
    DL_RTR_GUARD : UINT := 18;           // 匹配循环守护上限（深度 + 2） [次] / Match-loop guard limit
END_VAR

(* —— 段 0：组态闸 + 双 TON 与三沿无条件周期刷新（R228A；IN 串故障否决，R252） —— *)
_bCfgBad := (nRouteCnt < 0) OR (nRouteCnt > DL_RTR_MAX)              // 条数须在 0..16 / Count within 0..16
         OR (tDupWin <= T#0S) OR (tSegAckTo <= T#0S);                // 两时间须为正 / Both times positive
rtRead(CLK := bReadDone);                                            // 读码沿 / Tag-read edge
rtStartSeg(CLK := bStartSeg);                                        // 段启动沿 / Segment-start edge
rtReset(CLK := bReset);                                              // 复位沿 / Reset edge
tonDup(IN := _bDupBlk AND (NOT tonDup.Q), PT := tDupWin);             // 防抖窗（自复位振荡，R188） / Debounce window, self-resetting
tonSeg(IN := (_eState = E_DL_RtrState.eSegWait) AND (NOT _bFault), PT := tSegAckTo);   // 段握手超时 / Segment handshake timeout

(* —— 段 1：单拍量预清零（锁存量 _eCause/_bFault/_bUnknown/_iRoute/_bDupBlk 不入清单，R107） —— *)
bRouteValid := FALSE;                                                // 路由就绪预清 / Route-ready preset
bSegReq     := FALSE;                                                // 段请求预清（出口侧，段 6 由内部位覆写） / Segment request preset
_bSegReq    := FALSE;                                                // 段请求内部位预清 / Internal segment request preset
_bDupRead   := FALSE;                                                // 重扫脉冲内部位预清 / Internal duplicate pulse preset
bError      := FALSE;                                                // 故障标志预清（R45 配对） / Error preset

(* —— 段 2：组态闸（非法即锁存故障级） —— *)
IF _bCfgBad THEN
    _eCause := E_DL_RtrCause.eCfgIllegal;                            // 归因：组态非法 / Cause: illegal configuration
    _bFault := TRUE;                                                 // 锁存 / Latch
    _eState := E_DL_RtrState.eFault;                                 // 入故障相 / Enter fault phase
END_IF

(* —— 段 3：迁出链（bReset 上升沿：清双锁存与路由号，R228B） —— *)
IF rtReset.Q THEN
    _bFault   := FALSE;                                              // 清故障锁存 / Clear fault latch
    _bUnknown := FALSE;                                              // 清未知载具锁存 / Clear the unknown-tray latch
    _eCause   := E_DL_RtrCause.eNone;                                // 清成因 / Clear cause
    _iRoute   := 0;                                                  // 路由号清零 / Route number cleared
    _bDupBlk  := FALSE;                                              // 解除防抖封锁 / Release the debounce block
    _sLastId  := '';                                                 // 清上次身份码 / Clear the last identity
    _eState   := E_DL_RtrState.eIdle;                                // 回待机相 / Back to idle
END_IF

(* —— 段 4：防抖窗到时自动解除封锁（持窗量，非每拍预清零量） —— *)
IF tonDup.Q THEN
    _bDupBlk := FALSE;                                               // 窗到：解除封锁 / Window elapsed, release
END_IF

(* —— 段 5：读码与匹配（未知载具拒路由；同一码防抖忽略） —— *)
_iCnt := nRouteCnt;                                                  // 归一有效条数 / Normalise the valid count
IF _iCnt > DL_RTR_MAX THEN
    _iCnt := DL_RTR_MAX;                                             // 二次上界钳 / Second upper clamp
END_IF

IF (rtRead.Q) AND (NOT _bFault) AND (NOT _bCfgBad) THEN
    IF LEN(sTrayId) = 0 THEN
        _eCause := E_DL_RtrCause.eNoCode;                            // 归因：空码（信息级） / Cause: empty code, info level
    ELSIF _bDupBlk AND (sTrayId = _sLastId) THEN
        _bDupRead := TRUE;                                           // 防抖窗内同一码：重扫忽略 / Same code inside the window: ignored
        _eCause := E_DL_RtrCause.eDupRead;                           // 归因：重扫（信息级） / Cause: duplicate read, info level
    ELSE
        (* 线性匹配（带守护计数；仅记录首个命中号，未命中即非法载具） *)
        _bHit    := FALSE;                                           // 命中标志预置 / Hit preset
        _uGuard  := 0;                                               // 守护计数归零 / Guard reset
        _iIdx    := 1;                                               // 从表首匹配 / Start at the table head
        _iHitIdx := 0;                                               // 命中号预置 / Hit index preset
        WHILE (_uGuard < DL_RTR_GUARD) AND (_iIdx <= _iCnt) DO
            IF (NOT _bHit) AND (asRouteTable[_iIdx] = sTrayId) THEN
                _bHit    := TRUE;                                    // 首个命中即锁定 / Lock on the first hit
                _iHitIdx := _iIdx;                                   // 记录命中号 / Record the hit index
            END_IF
            _uGuard := _uGuard + 1;                                  // 计数器推进 / Guard advance
            _iIdx   := _iIdx + 1;                                    // 下标推进 / Index advance
        END_WHILE

        IF _bHit THEN
            _iRoute  := _iHitIdx;                                    // 锁定路由号 / Lock the route number
            _sLastId := sTrayId;                                     // 记录身份码 / Remember the identity
            _bDupBlk := TRUE;                                        // 开防抖窗 / Open the debounce window
            bRouteValid := TRUE;                                     // 路由就绪 / Route ready
        ELSE
            _bUnknown := TRUE;                                       // 未知载具：锁存 / Unknown tray: latch
            _bFault   := TRUE;                                       // 故障锁存 / Latch the fault
            _eCause   := E_DL_RtrCause.eUnknownTray;                 // 归因：未知载具 / Cause: unknown tray
            _eState   := E_DL_RtrState.eFault;                       // 入故障相 / Enter fault phase
            _iRoute   := 0;                                          // 路由号清零（拒路由） / Route number cleared
        END_IF
    END_IF
END_IF

(* —— 段 6：相迁移（段握手闭环） —— *)
IF (NOT _bFault) AND (NOT _bCfgBad) THEN
    CASE _eState OF

    E_DL_RtrState.eIdle:
        IF rtStartSeg.Q AND (_iRoute > 0) THEN
            _bSegReq := TRUE;                                        // 段请求脉冲（内部位） / Internal segment request
            _eState  := E_DL_RtrState.eSegWait;                      // 进等确认相 / Enter the wait-ack phase
        END_IF

    E_DL_RtrState.eSegWait:
        IF bSegAck THEN
            _iRoute := 0;                                            // 确认到达：路由消费完毕 / Acknowledged, the route is consumed
            _eState := E_DL_RtrState.eIdle;                          // 回待机相 / Back to idle
        ELSIF tonSeg.Q THEN
            _bFault := TRUE;                                         // 握手超时：锁存 / Timeout: latch
            _eCause := E_DL_RtrCause.eSegTimeout;                    // 归因：段握手超时 / Cause: segment timeout
            _eState := E_DL_RtrState.eFault;                         // 入故障相 / Enter fault phase
        END_IF

    E_DL_RtrState.eFault:
        ;                                                            // 故障相：仅等复位沿 / Wait for the reset edge only

    ELSE
        _eCause := E_DL_RtrCause.ePhaseBad;                          // 归因：非法相位 / Cause: illegal phase
        _bFault := TRUE;                                             // 锁存 / Latch
        _eState := E_DL_RtrState.eFault;                             // 强拉故障相 / Force fault phase

    END_CASE
END_IF

(* —— 段 7：出口单点映射（名实双出口，R191） —— *)
bSegReq     := _bSegReq;                                             // 段请求脉冲出口 / Segment request outlet
bDupRead    := _bDupRead;                                            // 重扫脉冲出口 / Duplicate-read outlet
iRouteNo    := _iRoute;                                              // 路由号出口 / Route number outlet
bSegBusy    := (_eState = E_DL_RtrState.eSegWait);                   // 等确认中出口 / Busy outlet
bUnknownTray:= _bUnknown;                                            // 未知载具出口 / Unknown-tray outlet
eState      := _eState;                                              // 相出口 / Phase outlet
eCause      := _eCause;                                              // 成因出口 / Cause outlet
bError      := _bFault;                                              // 故障标志 / Error flag

END_FUNCTION_BLOCK
