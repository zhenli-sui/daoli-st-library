(*==============================================================================
 * 组件名称 (Component)  : FB_DL_StringFifoRetry
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / LEN），零厂商私有库
 * 功能描述 (Function)   : 电池串缓存队列重试出站。
 *                         上游把电池串编号压入定长缓冲，本件按 FIFO 逐条向 MES/贴标工位出站，
 *                         每条出站走"发令 → 等确认 → 成功出队 / 失败计数"的握手闭环；
 *                         同一串失败重试超上限即锁存 NG 并停线等人工复位。
 *                         三条固化纪律：
 *                           ① **丢新策略**：队满时丢弃**新到**的串、保留已在队旧串
 *                              （旧串已在产线中途，丢旧会切断履历；丢新只丢一条未开始处理的串）；
 *                           ② **重试计数上限**：nMaxRetries 提为引脚（禁魔法数），
 *                              达到上限即锁存 bRetryNg；上限域闸 nMaxRetries ≥ 1；
 *                           ③ **单拍脉冲两段式**：发令脉冲 _bTxValid 在 CASE 内用内部位
 *                              置位、段 8 统一映射出口，禁同相内置位后同相撤位（R129）。
 *                         验收向量：
 *                           ① 深度 16；压入 16 条后续压 → 丢新 + eDroppedNew（信息级，不锁存）
 *                           ② nMaxRetries = 3；同一条连续 3 次 bAckFail → 第 3 次锁存 bRetryNg
 *                           ③ 握手超时 tHandshakeTo 到 → 计一次失败（与 bAckFail 同权）
 *                           ④ bAckOk 到达 → 出队、重试计数清零、回 eIdle
 * 接口     (Interface)  : 入 bPush 入队沿、sInString 入队电池串、bStart 出站使能、bAckOk 下游确认、
 *                         bAckFail 下游失败、nMaxRetries 重试上限、tHandshakeTo 握手超时、
 *                         bReset 复位沿；
 *                         出 sTxString 当前出站串、bTxValid 发令脉冲（单拍）、bTxBusy 等确认中、
 *                         iRetryCnt 当前串已试次数、iQueueCnt 在队条数、bDropped 当拍丢新、
 *                         bRetryNg 重试超限锁存、eState 相、eCause 成因、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只管"缓冲区与重试编排"，不做报文编码/
 *                         串口收发/协议校验**（属通讯层件），也不判电池串数据内容是否合法；
 *                         ② **深度闸**：环形指针与槽位下标一律钳在 1..16（字面量上界），
 *                         同值常量 DL_SFR_DEPTH 作运行时二次闸（R104）；
 *                         ③ **超时监视冻结**：tonHandshake 的 IN 串 (NOT _bFault)，
 *                         故障期间不累计，复位同拍不会立即重锁（R252 第 2 变体）；
 *                         ④ **重试上限域闸**：nMaxRetries ≤ 0 → 锁存 eCfgIllegal（零上限会让
 *                         第 0 次即判超限，属静默失效 R179）；
 *                         ⑤ **锁存解除式**：bRetryNg / eFault 的解除仅 bReset 上升沿
 *                         （R228B 唯一迁出）；bReset 为外部引脚，不受锁存量门控，恒可达；
 *                         ⑥ 零全局耦合、零物理地址。
 * 分工声明 (Scope)      : 本件只管"电池串缓存队列的出站重试"。不接管：底层 FIFO 结构件
 *                         （FB_DL_FifoBuffer 族）、MES 报文重传的幂等去重（属通讯层）、
 *                         电池串工艺合格判定（属测试判据件）。
 * 来源标签 (Source Tag) : ROADMAP 空勾真缺口 P1（电池串重试出站，自研 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位（零码位范式 R297）；诊断由 BOOL + ENUM 出口承担。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 指针钳位 + 上限域闸 + 重试计数饱和 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE 兜底 ｜ R7 ✓ TON/四 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R47 首版（批次 2 · 序号 7）
 *==============================================================================*)

TYPE E_DL_SfrState :
(
    eIdle    := 0,    // 待机相（可取队首出站） / Idle, ready to take the head record
    eWaitAck := 10,   // 等确认相（握手窗口内） / Waiting for the downstream acknowledgement
    eFault   := 90    // 故障相（等复位） / Fault, awaiting reset
);
END_TYPE

TYPE E_DL_SfrCause :
(
    eNone        := 0,   // 无异常 / No anomaly
    eCfgIllegal  := 1,   // 组态非法（重试上限非正） / Illegal configuration, retry limit non-positive
    eDroppedNew  := 2,   // 队满丢新（信息级） / Queue full, newest dropped, info level
    eStringEmpty := 3,   // 入队空串（信息级） / Empty string rejected, info level
    eAckFail     := 4,   // 下游失败（计数未超限，信息级） / Downstream failure below the retry limit
    eHsTimeout   := 5,   // 握手超时（计数未超限，信息级） / Handshake timeout below the retry limit
    eRetryNg     := 6,   // 重试超限（锁存，故障级） / Retry limit exceeded, latched
    ePtrCorrupt  := 7,   // 环形指针损坏（故障级） / Ring pointer corruption, fault level
    ePhaseBad    := 8    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_StringFifoRetry
VAR_INPUT
    bPush        : BOOL := FALSE;       // 入队沿 [-] / Enqueue edge
    sInString    : STRING[63] := '';    // 待入队电池串编号 [-] / Cell-string identifier to enqueue
    bStart       : BOOL := FALSE;       // 出站使能（TRUE 时自动取队首出站） [-] / Outbound enable
    bAckOk       : BOOL := FALSE;       // 下游确认成功（当拍电平） [-] / Downstream acknowledgement, level
    bAckFail     : BOOL := FALSE;       // 下游失败（当拍电平） [-] / Downstream failure, level
    nMaxRetries  : INT := 3;            // 单串重试上限，域 ≥ 1 [次] / Retry limit per string, domain >= 1
    tHandshakeTo : TIME := T#3S;        // 握手超时，域 > T#0S [ms] / Handshake timeout, > T#0S [ms]
    bReset       : BOOL := FALSE;       // 复位沿（清故障锁存与重试计数） [-] / Reset edge
END_VAR
VAR_OUTPUT
    sTxString : STRING[63] := '';                        // 当前出站电池串 [-] / String currently being transmitted
    bTxValid  : BOOL := FALSE;                           // 发令脉冲（单拍） [-] / Transmit pulse, single scan
    bTxBusy   : BOOL := FALSE;                           // 等确认中 [-] / Waiting for acknowledgement
    iRetryCnt : INT := 0;                                // 当前串累计失败次数 [次] / Failure count of the current string
    iQueueCnt : INT := 0;                                // 在队条数 [条] / Records currently queued
    bDropped  : BOOL := FALSE;                           // 当拍发生丢新 [-] / Newest record dropped this scan
    bRetryNg  : BOOL := FALSE;                           // 重试超限锁存（等复位） [-] / Retry limit exceeded, latched
    eState    : E_DL_SfrState := E_DL_SfrState.eIdle;    // 相出口 [-] / Phase outlet
    eCause    : E_DL_SfrCause := E_DL_SfrCause.eNone;    // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError    : BOOL := FALSE;                           // 故障标志（仅故障级成因） [-] / Error flag, fault level only
END_VAR
VAR
    _eState    : E_DL_SfrState := E_DL_SfrState.eIdle;   // 内部相（CASE 唯一写入目标） / Internal phase
    _eCause    : E_DL_SfrCause := E_DL_SfrCause.eNone;   // 成因锁存量 / Latched cause
    _bFault    : BOOL := FALSE;                          // 故障锁存位 / Latched fault bit
    _bRetryNg  : BOOL := FALSE;                          // 重试超限锁存位 / Latched retry-NG bit
    _iHead     : INT := 1;                               // 队列头指针（1..16） / Queue head pointer
    _iTail     : INT := 1;                               // 队列尾指针（1..16） / Queue tail pointer
    _iCnt      : INT := 0;                               // 在队条数 / Queued count
    _iRetry    : INT := 0;                               // 当前串失败计数 / Failure count of the current string
    _sTx       : STRING[63] := '';                       // 当前出站串内部副本 / Internal copy of the transmitting string
    _bTxValid  : BOOL := FALSE;                          // 发令脉冲内部位（单拍） / Internal transmit pulse
    _bDropped  : BOOL := FALSE;                          // 丢新内部位（单拍） / Internal drop flag
    _bCfgBad   : BOOL := FALSE;                          // 组态非法当拍量 / Illegal configuration this scan
    _bConsume  : BOOL := FALSE;                          // 本拍应消费队首（成功出队） / Head should be consumed this scan
    _bFailArmed: BOOL := TRUE;                           // 失败条件武装位（沿消费一次，条件消失后重武装） / Failure-edge arming flag
    tonHs      : TON;                                    // 握手超时实例，段 0 无条件调用 / Handshake timeout instance
    rtPush     : R_TRIG;                                 // 入队沿实例，段 0 无条件调用 / Enqueue edge instance
    rtReset    : R_TRIG;                                 // 复位沿实例，段 0 无条件调用 / Reset edge instance
    asBuf      : ARRAY[1..16] OF STRING[63];             // 电池串环（深度字面量上界，R104） / String ring, literal depth
END_VAR
VAR CONSTANT
    DL_SFR_DEPTH : INT := 16;            // 队列深度（与数组字面量上界同源） [条] / Queue depth
    DL_SFR_RTY_MAX : INT := 100;         // 重试上限的工程上限保护 [次] / Engineering upper bound of the retry limit
END_VAR

(* —— 段 0：组态闸 + TON 与两沿无条件周期刷新（R228A；IN 串故障否决，R252） —— *)
_bCfgBad := (nMaxRetries <= 0) OR (nMaxRetries > DL_SFR_RTY_MAX) OR (tHandshakeTo <= T#0S);   // 上限须 1..100 且超时须为正
rtPush(CLK := bPush);                                    // 入队沿 / Enqueue edge
rtReset(CLK := bReset);                                  // 复位沿 / Reset edge
tonHs(IN := (_eState = E_DL_SfrState.eWaitAck) AND (NOT _bFault), PT := tHandshakeTo);   // 握手超时（等确认相派生） / Handshake timeout

(* —— 段 1：单拍量预清零（锁存量 _eCause/_bFault/_bRetryNg/_iRetry 不入清单，R107） —— *)
_bTxValid := FALSE;                                      // 发令脉冲预清 / Transmit pulse preset
_bDropped := FALSE;                                      // 丢新标志预清 / Drop flag preset
bError    := FALSE;                                      // 故障标志预清（R45 配对） / Error preset

(* —— 段 2：组态闸（非法即锁存故障级） —— *)
IF _bCfgBad THEN
    _eCause := E_DL_SfrCause.eCfgIllegal;                // 归因：组态非法 / Cause: illegal configuration
    _bFault := TRUE;                                     // 锁存 / Latch
    _eState := E_DL_SfrState.eFault;                     // 入故障相 / Enter fault phase
END_IF

(* —— 段 3：环形指针自检（越界即清队重建 + 锁存） —— *)
IF (_iHead < 1) OR (_iHead > DL_SFR_DEPTH) OR (_iTail < 1) OR (_iTail > DL_SFR_DEPTH)
   OR (_iCnt < 0) OR (_iCnt > DL_SFR_DEPTH) THEN
    _iHead := 1;                                         // 头指针重建 / Head rebuilt
    _iTail := 1;                                         // 尾指针重建 / Tail rebuilt
    _iCnt  := 0;                                         // 计数清零 / Count cleared
    _eCause := E_DL_SfrCause.ePtrCorrupt;                // 归因：指针损坏 / Cause: pointer corruption
    _bFault := TRUE;                                     // 锁存 / Latch
    _eState := E_DL_SfrState.eFault;                     // 入故障相 / Enter fault phase
END_IF

(* —— 段 4：迁出链（bReset 唯一迁出：清故障锁存 + 重试计数 + 相位；R228B） —— *)
IF rtReset.Q THEN
    _bFault   := FALSE;                                  // 清故障锁存 / Clear fault latch
    _bRetryNg := FALSE;                                  // 清重试超限锁存 / Clear retry-NG latch
    _eCause   := E_DL_SfrCause.eNone;                    // 清成因 / Clear cause
    _iRetry   := 0;                                      // 重试计数清零 / Retry counter cleared
    _iHead    := 1;                                      // 头指针回 1（队列随之作废） / Head back to 1, queue discarded
    _iTail    := 1;                                      // 尾指针回 1 / Tail back to 1
    _iCnt     := 0;                                      // 计数清零 / Count cleared
    _sTx      := '';                                     // 出站副本清空 / Transmit copy cleared
    _eState   := E_DL_SfrState.eIdle;                    // 回待机相 / Back to idle
END_IF

(* —— 段 5：入队（丢新策略：满则丢新、保旧；空串拒入） —— *)
IF (rtPush.Q) AND (NOT _bFault) THEN
    IF LEN(sInString) = 0 THEN
        _eCause := E_DL_SfrCause.eStringEmpty;           // 归因：空串拒入（信息级） / Cause: empty string, info level
    ELSIF _iCnt >= DL_SFR_DEPTH THEN
        _bDropped := TRUE;                               // 丢新锁存（当拍） / Drop the newest record
        _eCause := E_DL_SfrCause.eDroppedNew;            // 归因：队满丢新（信息级） / Cause: full, newest dropped
    ELSE
        asBuf[_iTail] := sInString;                      // 写尾槽位 / Write the tail slot
        _iCnt  := _iCnt + 1;                             // 计数递增 / Count increment
        _iTail := _iTail + 1;                            // 尾指针推进 / Tail advance
        IF _iTail > DL_SFR_DEPTH THEN
            _iTail := 1;                                 // 环形回卷 / Ring wrap
        END_IF
    END_IF
END_IF

(* —— 段 6：相迁移（出站握手闭环） —— *)
IF (NOT _bFault) AND (NOT _bCfgBad) THEN
    CASE _eState OF

    E_DL_SfrState.eIdle:
        IF bStart AND (_iCnt > 0) THEN
            _sTx      := asBuf[_iHead];                  // 取队首出站串 / Take the head string
            _bTxValid := TRUE;                           // 发令脉冲（内部位，段 8 单点映射） / Internal transmit pulse
            _iRetry   := 0;                              // 新串重试计数归零 / Reset the retry counter for the new string
            _eState   := E_DL_SfrState.eWaitAck;         // 进等确认相 / Enter the wait-ack phase
        END_IF

    E_DL_SfrState.eWaitAck:
        IF bAckOk THEN
            _bConsume := TRUE;                           // 成功：本拍消费队首 / Success: consume the head this scan
            _iRetry   := 0;                              // 重试计数归零 / Retry counter cleared
            _eState   := E_DL_SfrState.eIdle;            // 回待机相 / Back to idle
        ELSIF (bAckFail OR tonHs.Q) AND _bFailArmed THEN
            _bFailArmed := FALSE;                        // 失败条件沿消费一次（条件消失后重新武装，防每拍累加） / Consume the failure edge once
            _iRetry := _iRetry + 1;                      // 失败计数 +1（失败与超时同权） / Failure or timeout, same weight
            IF bAckFail THEN
                _eCause := E_DL_SfrCause.eAckFail;       // 归因：下游失败 / Cause: downstream failure
            ELSE
                _eCause := E_DL_SfrCause.eHsTimeout;     // 归因：握手超时 / Cause: handshake timeout
            END_IF
            IF _iRetry >= nMaxRetries THEN
                _bRetryNg := TRUE;                       // 重试超限锁存 / Latch the retry-NG state
                _bFault   := TRUE;                       // 故障锁存 / Latch the fault
                _eCause   := E_DL_SfrCause.eRetryNg;     // 归因：重试超限（覆盖为故障级首因） / Cause: retry limit, fault level
                _eState   := E_DL_SfrState.eFault;       // 入故障相（等复位） / Enter the fault phase
            ELSE
                _bTxValid := TRUE;                       // 未超限：当拍重发（内部位） / Below the limit: retransmit
                _eState   := E_DL_SfrState.eWaitAck;     // 留在等确认相 / Stay in the wait-ack phase
            END_IF
        END_IF

    E_DL_SfrState.eFault:
        ;                                            // 故障相：仅等复位沿 / Wait for the reset edge only

    ELSE
        _eCause := E_DL_SfrCause.ePhaseBad;              // 归因：非法相位 / Cause: illegal phase
        _bFault := TRUE;                                 // 锁存 / Latch
        _eState := E_DL_SfrState.eFault;                 // 强拉故障相 / Force fault phase

    END_CASE
END_IF

(* —— 段 6b：失败条件消失后重新武装（沿消费纪律；锁存量不入每拍预清零） —— *)
IF (NOT bAckFail) AND (NOT tonHs.Q) THEN
    _bFailArmed := TRUE;                                 // 条件消失：重新武装 / Condition gone: re-arm
END_IF

(* —— 段 7：出队（成功消费唯一入口；指针回卷） —— *)
IF _bConsume THEN
    asBuf[_iHead] := '';                                 // 清空已发送槽位 / Clear the sent slot
    _iCnt  := _iCnt - 1;                                 // 计数递减 / Count decrement
    _iHead := _iHead + 1;                                // 头指针推进 / Head advance
    IF _iHead > DL_SFR_DEPTH THEN
        _iHead := 1;                                     // 环形回卷 / Ring wrap
    END_IF
    _bConsume := FALSE;                                  // 消费标志自复位（防跨拍误消费） / Self-reset the consume flag
END_IF

(* —— 段 8：出口单点映射（名实双出口，R191） —— *)
sTxString := _sTx;                                       // 当前出站串出口 / Transmit string outlet
bTxValid  := _bTxValid;                                  // 发令脉冲出口 / Transmit pulse outlet
bTxBusy   := (_eState = E_DL_SfrState.eWaitAck);         // 等确认中出口 / Busy outlet
iRetryCnt := _iRetry;                                    // 失败计数出口 / Retry count outlet
iQueueCnt := _iCnt;                                      // 在队条数出口 / Queued count outlet
bDropped  := _bDropped;                                  // 丢新出口 / Drop outlet
bRetryNg  := _bRetryNg;                                  // 重试超限出口 / Retry-NG outlet
eState    := _eState;                                    // 相出口 / Phase outlet
eCause    := _eCause;                                    // 成因出口 / Cause outlet
bError    := _bFault;                                    // 故障标志 / Error flag

END_FUNCTION_BLOCK
