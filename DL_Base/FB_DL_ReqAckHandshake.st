(*
  ==================================================================
  组件名 Component  : FB_DL_ReqAckHandshake
  分类   Category   : DL_Base
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : 通用请求-应答握手原子（无工艺语义）。请求上升沿武装进入应答
                      等待相，应答窗 tAck 内收到 bAck 电平则输出确认单拍 bDone；
                      窗到期未见应答则输出重试单拍 bRetry 并进重试间隔相 tRetry，
                      重试次数达 nMaxRetry 仍不应答则锁存故障码。
  来源   Source     : self-std（IEC 61131-3 标准时序语义自研原子）
  溯源   Origin     : 请求-应答握手为公开时序语义，道莅 clean-room 自研实现，
                      未复制任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: TON / R_TRIG），
                      CODESYS / TwinCAT / InoProShop / Machine Expert 通用
  分工声明 Split     : 与 FB_DL_AgvDockingHandshake（工艺级对接握手）分工——
                      后者承载工位/库位工艺时序与就位判据；本件为无工艺语义的
                      时序原子，只做沿武装、窗超时、重试与锁存，不判任何机械条件。
  作者   Author     : 道莅代码库 · PLC 编程专家（R60）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 同拍双窗配比约束（R100/R239）：tAck 为单次应答窗、
                         tRetry 为重试间隔，约束 tAck > tRetry > 0——若
                         tRetry >= tAck，重试节拍慢于超时检测，重试上限在等效
                         时间内不可达，重试语义退化为一次性；违反即在段 2
                         组态闸锁存故障码（禁只在注释里声明）；
                      二 单拍输出 bDone / bRetry 统一出口段每拍先预置 FALSE，
                         分支只写 TRUE（R256）；
                      三 首拍零假沿自证（R257）：R_TRIG 内部存储位初值 FALSE，
                         首拍 bReq 已为真即判为一次新请求沿，语义安全（请求电平
                         已存在则握手应立即启动），而 bAck 首拍为真不会误置
                         bDone——它只在应答等待相内被消费；
                      四 应答等待相退出条件三条（R98）：bAck 成立 / 请求撤销
                         （进相前置消失，无码回空闲）/ 应答窗超时；缺一即死等；
                      五 使能 bEnable = FALSE 时语义为「冻结保持 + 弃用请求」
                         （退出活动相回空闲，不锁存、不出单拍）——R191 声明行；
                      六 故障解除路径：eFault 相由复位沿迁回空闲并清锁存与重试
                         计数（bReset 为输入引脚，恒可达，R152 自证）；
                      七 故障码一律锁存回放，不在故障相按当下输入重新推断。
  错误码   Codes    :
    16#0001_0613【故障级】组态非法（窗配比违反或重试上限为负），锁存至复位沿
    16#0001_0614【故障级】应答窗超时且重试耗尽，锁存至复位沿
    16#0001_0615【信息级】重试计数已达上限（本拍为最后一次重试，逐拍重算）
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 tAck=2s、nMaxRetry=2、第 3 个窗到期前给 bAck → bDone 单拍、计数归零
    V2 全程无 bAck、nMaxRetry=2 → 两次 bRetry 单拍后锁码 0614、相冻结
    V3 tRetry >= tAck → 首拍即锁码 0613，无单拍输出
  修订记录 Revision  :
    2026-11-21  v1.0.0  R60 首版（批 1 · 序号 4）
  ==================================================================
*)

TYPE E_DL_ReqAckPhase :
(
    eIdle     := 0,  // 空闲：等请求上升沿或复位 / idle, waiting for the request edge or a reset
    eWaitAck  := 10, // 应答等待：等 bAck / 请求撤销 / 窗超时 / waiting for the acknowledgement, an abort or the window expiry
    eRetryGap := 20, // 重试间隔：等 tRetry 到期后重开应答窗 / the retry gap, reopen the window after tRetry
    eFault    := 30  // 故障：锁存故障码，等复位沿 / fault, the code latched, waiting for the reset edge
);
END_TYPE

FUNCTION_BLOCK FB_DL_ReqAckHandshake
VAR_INPUT
    bEnable    : BOOL := TRUE;  // 使能，FALSE 时退相回空闲（边界五）/ the enable, false returns the phase to idle
    bReq       : BOOL := FALSE; // 请求电平，上升沿武装握手 / the request level, the rising edge arms the handshake
    bAck       : BOOL := FALSE; // 应答电平，仅在应答等待相内被消费 / the acknowledgement level, consumed only inside the waiting phase
    bReset     : BOOL := FALSE; // 复位沿：清故障锁存与重试计数并回空闲 / the reset edge, clears the latch and the retry count then returns to idle
    tAck       : TIME := T#2S;  // 单次应答窗时长 [毫秒] / the single attempt acknowledgement window
    tRetry     : TIME := T#500MS; // 重试间隔时长 [毫秒]，约束 tAck > tRetry / the retry gap, constrained below the window
    nMaxRetry  : DINT := 3;     // 最大重试次数 [次]，域 0..100 / the maximum retry count, from zero to one hundred
END_VAR
VAR_OUTPUT
    bBusy      : BOOL := FALSE;                 // 握手中（等待或重试间隔）[-] / the handshake in progress flag
    bDone      : BOOL := FALSE;                 // 握手成功单拍脉冲 [-] / the success one shot pulse
    bRetry     : BOOL := FALSE;                 // 发起重试单拍脉冲 [-] / the retry one shot pulse
    nRetryCnt  : DINT := 0;                     // 已发起重试次数 [次]，饱和于上限 / the issued retry count, saturated at the bound
    eState     : E_DL_ReqAckPhase;              // 主状态机当前态 [状态] / the current state of the main machine
    bError     : BOOL := FALSE;                 // 故障锁存位 [-] / the latched fault bit
    eErr       : UDINT := 16#0000_0000;         // 错误码，0 = 正常 / the error code, zero is ok
END_VAR
VAR
    _bInit     : BOOL := FALSE;                            // 首拍初始化标志（R310）/ the first scan flag
    _eState    : E_DL_ReqAckPhase := E_DL_ReqAckPhase.eIdle; // 内部状态寄存器，段 3 唯一写点 / the internal state register, single writer
    _nRetryCnt : DINT := 0;                                // 重试计数副本，段 5 单点映射 / the retry count copy, mapped once in segment five
    _bDone     : BOOL := FALSE;                            // 成功单拍内部位，段 1 预清段 5 映射 / the internal success bit, preset then mapped
    _bRetry    : BOOL := FALSE;                            // 重试单拍内部位，段 1 预清段 5 映射 / the internal retry bit, preset then mapped
    _bFault    : BOOL := FALSE;                            // 故障锁存副本（仅复位沿清除）/ the fault latch copy, cleared only on the reset edge
    _bRetrySat : BOOL := FALSE;                            // 重试计数饱和指示（逐拍重算）[-] / the retry saturation flag, recomputed every scan
    _bCfgBad   : BOOL := FALSE;                            // 组态非法指示（逐拍重算）[-] / the configuration fault flag, recomputed every scan
    rtReq      : R_TRIG;                                   // 请求沿实例，段 0 无条件刷新 / the request edge instance, refreshed unconditionally
    rtReset    : R_TRIG;                                   // 复位沿实例，段 0 无条件刷新 / the reset edge instance, refreshed unconditionally
    tonAck     : TON;                                      // 应答窗定时器，段 0 无条件刷新 / the acknowledgement window timer, refreshed unconditionally
    tonRetry   : TON;                                      // 重试间隔定时器，段 0 无条件刷新 / the retry gap timer, refreshed unconditionally
END_VAR
VAR CONSTANT
    DL_RAH_RETRYMAX : DINT := 100; // 重试次数上界 [次]，防组态越域 / the retry count bound against configuration overflow
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支，R7；IN 串故障锁存量门控，FB50-1）/ segment 0, the unconditional refresh with the latch gate
rtReq(CLK := bReq); // 请求沿 / the request edge
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonAck(IN := (_eState = E_DL_ReqAckPhase.eWaitAck) AND (NOT _bFault), PT := tAck); // 应答窗：仅在等待相且无锁存时计时 / the window timing only in the waiting phase without a latch
tonRetry(IN := (_eState = E_DL_ReqAckPhase.eRetryGap) AND (NOT _bFault), PT := tRetry); // 重试间隔计时 / the retry gap timing

// 段 1｜首拍初始化与单拍标志预清（仅单拍标志入清单，R32 FB32-1；R256）/ segment 1, the first scan init and the one shot preset
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _nRetryCnt := 0; // 重试计数显式清零 / clear the retry count explicitly
    _bFault := FALSE; // 故障锁存显式清零 / clear the fault latch explicitly
    _eState := E_DL_ReqAckPhase.eIdle; // 状态显式落空闲 / place the state to idle explicitly
END_IF
_bDone := FALSE; // 成功单拍预清零 / preset the success pulse false
_bRetry := FALSE; // 重试单拍预清零 / preset the retry pulse false
_bRetrySat := FALSE; // 饱和指示预清零 / preset the saturation flag false
_bCfgBad := FALSE; // 组态非法指示预清零 / preset the configuration fault flag false

// 段 2｜组态域闸（窗配比 + 重试上限，边界一；同拍双窗配比在此落成可观测故障）/ segment 2, the configuration gate with the window ratio landed as an observable fault
IF (tAck <= T#0S) OR (tRetry <= T#0S) OR (tRetry >= tAck) OR (nMaxRetry < 0) OR (nMaxRetry > DL_RAH_RETRYMAX) THEN // 任一越域 / any item out of domain
    _bCfgBad := TRUE; // 置组态非法 / raise the configuration fault
    _bFault := TRUE; // 锁存故障（段 4 迁移相）/ latch the fault, the segment four migrates the phase
END_IF

// 段 3｜主状态机（ENUM + CASE，ELSE 拦非法态）/ segment 3, the main machine with the illegal state guard
CASE _eState OF
    E_DL_ReqAckPhase.eIdle: // 空闲相：等请求沿 / the idle phase, waiting for the request edge
        IF bEnable AND (NOT _bFault) AND rtReq.Q THEN // 迁入判据：使能且无锁存且有请求沿（R274 全量闸位复检）/ the entry with the full gate recheck
            _nRetryCnt := 0; // 新一轮握手重试计数归零 / reset the retry count for the new round
            _eState := E_DL_ReqAckPhase.eWaitAck; // 迁入应答等待相 / enter the waiting phase
        END_IF
    E_DL_ReqAckPhase.eWaitAck: // 应答等待相：三条退出（边界四，R98）/ the waiting phase with three exits
        IF bAck THEN // 出口一：应答成立 / the first exit, the acknowledgement
            _bDone := TRUE; // 置成功单拍 / raise the success pulse
            _nRetryCnt := 0; // 成功后计数归零（复位作用域：清累计量）/ on success the count returns to zero
            _eState := E_DL_ReqAckPhase.eIdle; // 迁回空闲 / back to idle
        ELSIF (NOT bReq) THEN // 出口二：请求撤销（进相前置条件已消失，无码回空闲）/ the second exit, the request withdrawn with no code
            _nRetryCnt := 0; // 计数归零 / the count returns to zero
            _eState := E_DL_ReqAckPhase.eIdle; // 迁回空闲 / back to idle
        ELSIF tonAck.Q THEN // 出口三：应答窗到期 / the third exit, the window expired
            IF _nRetryCnt < nMaxRetry THEN // 尚有重试额度 / a retry remains available
                _nRetryCnt := _nRetryCnt + 1; // 重试计数推进 / advance the retry count
                _bRetry := TRUE; // 置重试单拍 / raise the retry pulse
                IF _nRetryCnt >= nMaxRetry THEN // 已用尽全部额度 / the whole allowance is used
                    _bRetrySat := TRUE; // 置饱和提示（最后一次重试，信息级）/ raise the informational saturation hint
                END_IF
                _eState := E_DL_ReqAckPhase.eRetryGap; // 迁入重试间隔相 / enter the retry gap phase
            ELSE // 额度已尽 / the allowance exhausted
                _bFault := TRUE; // 锁存故障（0614，段 4 迁移相）/ latch the fault, migrated in segment four
            END_IF
        END_IF
        IF (_eState = E_DL_ReqAckPhase.eWaitAck) AND (NOT bEnable) AND (NOT _bFault) THEN // 失能弃用请求（不借故障相过桥，R211；相判据防成功拍被改写）/ the disable discards the request without bridging the fault phase
            _nRetryCnt := 0; // 计数归零 / the count returns to zero
            _eState := E_DL_ReqAckPhase.eIdle; // 迁回空闲 / back to idle
        END_IF
    E_DL_ReqAckPhase.eRetryGap: // 重试间隔相：等间隔到期或请求撤销 / the retry gap phase
        IF (NOT bReq) THEN // 退出条件一：请求撤销（前置消失）/ the first exit, the request withdrawn
            _nRetryCnt := 0; // 计数归零 / the count returns to zero
            _eState := E_DL_ReqAckPhase.eIdle; // 迁回空闲 / back to idle
        ELSIF tonRetry.Q THEN // 退出条件二：间隔到期，重开应答窗 / the second exit, the gap expired, reopen the window
            _eState := E_DL_ReqAckPhase.eWaitAck; // 迁回应答等待相 / back to the waiting phase
        END_IF
        IF (NOT bEnable) AND (NOT _bFault) THEN // 失能回空闲 / the disable returns to idle
            _nRetryCnt := 0; // 计数归零 / the count returns to zero
            _eState := E_DL_ReqAckPhase.eIdle; // 迁回空闲 / back to idle
        END_IF
    E_DL_ReqAckPhase.eFault: // 故障相：锁存保持，等复位沿（解除路径可达，边界六）/ the fault phase, held until the reset edge
        IF rtReset.Q THEN // 复位沿（复位作用域：清锁存 + 清累计量 + 迁相位）/ the reset edge with the declared scope
            _bFault := FALSE; // 清故障锁存 / clear the fault latch
            _nRetryCnt := 0; // 清重试计数 / clear the retry count
            _eState := E_DL_ReqAckPhase.eIdle; // 故障相迁出边回空闲 / the exit edge back to idle
        END_IF
    ELSE // 非法枚举值拦截 / the illegal enumeration guard
        _eState := E_DL_ReqAckPhase.eIdle; // 落回空闲 / force back to idle
        _bFault := TRUE; // 置故障锁存 / latch the fault
END_CASE

// 段 4｜故障锁存迁移闸（置于解除段之后防同拍抢迁，R258）/ segment 4, the fault latch to phase gate placed after the release
IF _bFault AND (_eState <> E_DL_ReqAckPhase.eFault) THEN // 已锁存但不在故障相 / latched but not in the fault phase
    _eState := E_DL_ReqAckPhase.eFault; // 迁入故障相 / enter the fault phase
END_IF

// 段 5｜统一出口（内部副本单点映射，R180；故障码锁存回放，R187）/ segment 5, the unified outlet
bBusy := (_eState = E_DL_ReqAckPhase.eWaitAck) OR (_eState = E_DL_ReqAckPhase.eRetryGap); // 握手中指示 / the in progress flag
bDone := _bDone; // 成功单拍出口 / the success pulse outlet
bRetry := _bRetry; // 重试单拍出口 / the retry pulse outlet
nRetryCnt := _nRetryCnt; // 重试计数出口 / the retry count outlet
eState := _eState; // 状态出口 / the state outlet
bError := _bFault; // 故障位出口（与锁存同源）/ the fault bit outlet from the same latch
IF _bFault THEN // 故障锁存回放优先 / the latched fault replays first
    IF _bCfgBad THEN // 组态成因 / the configuration cause
        eErr := 16#0001_0613; // 故障级：组态非法 / fault grade, the configuration is illegal
    ELSE // 超时成因（独立码值，R190 归因唯一）/ the timeout cause with its own code value
        eErr := 16#0001_0614; // 故障级：应答窗超时且重试耗尽 / fault grade, the window expired with the retries exhausted
    END_IF
ELSIF _bRetrySat THEN // 信息级提示 / the informational hint
    eErr := 16#0001_0615; // 信息级：重试计数已达上限 / informational, the retry count reached the bound
ELSE // 无事件 / no event
    eErr := 16#0000_0000; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
