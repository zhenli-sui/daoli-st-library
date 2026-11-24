(*
  ==================================================================
  组件名 Component  : FB_DL_BacdHvacPoll
  分类   Category   : DL_Process
  版本   Version    : 1.0.1
  功能   Purpose    : BA 顺控 BACnet / Modbus 轮询行。按固定轮询间隔对 1..16 台现场
                      设备做轮询：发出轮询触发后等响应超时窗，收到响应即置在线位并
                      清重试计数；超时即重试，重试次数用尽置离线位。每轮完成后索引
                      前进并跳过离线设备（全部离线时仍逐台尝试以探测恢复），并输出
                      在线 / 离线掩码字、轮询计数与超时计数。
  溯源   Origin     : BACnet / Modbus 轮询调度为公开现场总线通信语义；本件为 clean-room
                      实现，仅借鉴来源分类与参数域组织（来源标签 roadmap-p2-bacd），
                      道莅原创设计，未复制任何闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / WORD / SHL，无私有库）
  作者   Author     : 道莅代码库 · PLC 编程专家（R55）
  ------------------------------------------------------------------
  同拍双窗配比约束（R100）：tRespTo 必须小于 tPollInt —— 响应超时窗短于轮询间隔窗，
                      两窗职责分离：tPollInt 定节拍，tRespTo 判单台失败；超时窗覆盖整个
                      间隔会使下一拍无法发出轮询，配比反置在组态域闸内直接判故障。
  边界 Boundary     :
                      一 本件只出轮询触发与在线掩码，不做协议编解码、不写设备（属主边界）；
                      二 轮询间隔用自复位周期 TON（周期脉冲发生器用法，R328 适用方向）；
                      三 响应超时件 IN 串「等待响应相」闸与「响应已到」补集，不跨相累计；
                      四 设备索引一律回钳 1..16，跳过离线设备的循环有守护上限防死循环；
                      五 无全局变量、无外部变量声明、无物理地址寻址；
                      六 eNoDevice 为预留恒空成员：设备数为零已由组态域闸判
                         eCfgIllegal（故障级），信息级 eNoDevice 不可达，保留成员
                         以稳定接口（R56 返修留痕）。
  输出契约 Output contract:
                      nPollIdx 为当前轮询设备号（1..nDevCount），无设备时保持 1；
                      wOnlineMask / wOfflineMask 位 i-1 对应设备 i，
                      自证向量：仅 1 号设备离线 → 16#0001，仅 16 号设备离线 → 16#8000；
                      bPollTrig 与 bRespTimeout 各为单拍脉冲（内部位置位、出口映射后撤销）；
                      eCause 故障级成因与 bError 配对（R45），信息级永不置 bError。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R55 首版（批 4 · 序号 20）
    2026-11-20  v1.0.1  R56 返修（7.1）：段 7 删除恒假死分支（判量 _nUseCount 经段 3
                        回钳恒 ≥1，信息级 eNoDevice 不可达），「设备数为零」语义改由
                        组态域闸 eCfgIllegal（故障级）承载；_nCurRetry 声明经核验
                        已在 VAR 区在位（7 处引用合法）。
  ==================================================================
*)

TYPE E_DL_BhdPhase :
(
    eIdle  := 0,        // 空闲：未使能或已停轮询 / idle, disabled or polling stopped
    ePoll  := 10,       // 发出：本拍发出轮询触发 / issuing, the poll trigger is raised this scan
    eWait  := 20,       // 等响应：等响应或超时 / waiting, for the response or the timeout
    eFault := 90        // 故障：组态非法锁存 / fault, illegal configuration latched
);
END_TYPE

TYPE E_DL_BhdCause :
(
    eNone       := 0,   // 无成因 / no cause
    eCfgIllegal := 1,   // 组态非法：设备数、重试上限或时间引脚越域（故障级，与 bError 配对）/ illegal config, device count, retry cap or time pin out of domain
    eDevOffline := 2,   // 有设备重试用尽转离线（信息级）/ a device exhausted its retries and went offline, informational
    eAllOffline := 3,   // 全部设备离线，仍逐台尝试探测恢复（信息级）/ every device is offline and the scan still probes for recovery
    eNoDevice   := 4    // 设备数为零（预留恒空，语义由 eCfgIllegal 承载，R56 留痕）/ no device configured, reserved always empty, carried by eCfgIllegal
);
END_TYPE

FUNCTION_BLOCK FB_DL_BacdHvacPoll
VAR_INPUT
    bEnable     : BOOL := TRUE;              // 使能，失能时停轮询并保持掩码 [-] / enable, polling stops and the masks hold when disabled
    bReset      : BOOL := FALSE;            // 复位上升沿清故障锁存、掩码与重试 [-] / reset rising edge clears the fault latch, the masks and the retries
    nDevCount   : INT := 8;                  // 轮询设备数 [台]，域 1..16 / polled device count [unit], domain 1 to 16
    nRetryMax   : INT := 2;                  // 单设备重试上限 [次]，域 0..9 / per device retry ceiling [count], domain 0 to 9
    tPollInt    : TIME := T#1S;              // 轮询间隔 [毫秒]，域 大于零 / poll interval [millisecond], domain above zero
    tRespTo     : TIME := T#500MS;           // 响应超时 [毫秒]，域 大于零 / response timeout [millisecond], domain above zero
    bRespPulse  : BOOL := FALSE;             // 响应到达脉冲（对应当前轮询设备）[-] / response arrival pulse for the currently polled device
END_VAR
VAR_OUTPUT
    nPollIdx    : INT := 1;                  // 当前轮询设备号 [设备号] / currently polled device number
    bPollTrig   : BOOL := FALSE;             // 轮询触发单拍脉冲 [-] / poll trigger single-shot pulse
    bRespTimeout: BOOL := FALSE;             // 响应超时单拍脉冲 [-] / response timeout single-shot pulse
    wOnlineMask : WORD := 16#0000;           // 在线设备掩码，位 i-1 对应设备 i [-] / online device mask, bit i minus one maps to device i
    wOfflineMask: WORD := 16#0000;           // 离线设备掩码，位 i-1 对应设备 i [-] / offline device mask, bit i minus one maps to device i
    uPollCnt    : UDINT := 0;                // 累计轮询次数（饱和到上限）[次] / total poll count, saturated [count]
    uTimeoutCnt : UDINT := 0;                // 累计响应超时次数（饱和到上限）[次] / total response timeout count, saturated [count]
    nOfflineCnt : INT := 0;                  // 当前离线设备数 [台] / current offline device count [unit]
    nCurRetry   : INT := 0;                  // 当前设备已重试次数 [次] / retries already spent on the current device [count]
    ePhase      : E_DL_BhdPhase := E_DL_BhdPhase.eIdle; // 相位出口 [枚举] / phase outlet [enum]
    eCause      : E_DL_BhdCause := E_DL_BhdCause.eNone; // 成因出口 [枚举] / cause outlet [enum]
    bError      : BOOL := FALSE;             // 故障锁存标志 [-] / fault latch flag
END_VAR
VAR
    rtResp      : R_TRIG;                    // 响应沿检测，段 0 无条件刷新 / response edge detector, refreshed unconditionally in segment zero
    rtReset     : R_TRIG;                    // 复位沿检测，段 0 无条件刷新 / reset edge detector, refreshed unconditionally in segment zero
    tonPollInt  : TON;                       // 轮询间隔周期计时（自复位式）/ poll interval timer, self resetting
    tonResp     : TON;                       // 响应超时计时，段 0 无条件刷新 / response timeout timer, refreshed unconditionally in segment zero
    _ePhase     : E_DL_BhdPhase := E_DL_BhdPhase.eIdle;   // 内部相位，CASE 唯一写入目标 / internal phase, the only CASE write target
    _eCause     : E_DL_BhdCause := E_DL_BhdCause.eNone;   // 信息级成因，每拍重算 / informational cause, recomputed every scan
    _eFaultCause: E_DL_BhdCause := E_DL_BhdCause.eNone;   // 故障级成因，锁存至复位沿 / fault cause, latched until the reset edge
    _bFault     : BOOL := FALSE;             // 故障锁存位 [-] / fault latch bit
    _bInit      : BOOL := FALSE;             // 首扫初始化完成标志（R310）/ first scan initialisation flag
    _bCfgBad    : BOOL := FALSE;             // 组态非法判定 [-] / illegal configuration verdict
    _bPollInt   : BOOL := FALSE;             // 轮询触发内部位，统一出口映射 / internal poll trigger bit, mapped at the unified outlet
    _bToInt     : BOOL := FALSE;             // 超时脉冲内部位，统一出口映射 / internal timeout bit, mapped at the unified outlet
    _bOfflineNew: BOOL := FALSE;             // 本拍有新设备转离线 [-] / a device went offline this scan
    _bAllOff    : BOOL := FALSE;             // 全部设备离线 [-] / every device is offline
    _bFound     : BOOL := FALSE;             // 跳过循环命中标志 [-] / hit flag of the skip loop
    _bIsOffline : BOOL := FALSE;             // 被检设备是否离线 [-] / whether the checked device is offline
    _nUseCount  : INT := 1;                  // 钳定后的设备数 [台] / clamped device count [unit]
    _nRetryUse  : INT := 1;                  // 钳定后的重试上限 [次] / clamped retry ceiling [count]
    _nIdx       : INT := 1;                  // 设备索引（回钳 1..16）[设备号] / device index clamped one through sixteen
    _nGuard     : INT := 0;                  // 跳过循环守护计数 [次] / skip loop guard [count]
    _nIdxProbe  : INT := 1;                  // 离线统计探测索引 [设备号] / probe index for the offline statistics
    _nCurRetry  : INT := 0;                  // 当前设备重试计数（声明补齐，R55 终审）/ current device retry counter, declaration completed at R55 review
    _nOfflineCnt: INT := 0;                  // 本轮统计离线设备数工作值（出口映射源）[台] / offline device count working value, source of the outlet [unit]
    _wOff       : WORD := 16#0000;           // 离线掩码工作字 / offline mask working word
    _wOn        : WORD := 16#0000;           // 在线掩码工作字（按位或累计）/ online mask working word
    _wBit       : WORD := 16#0001;           // 本设备位掩码，先移位后置位（R327）/ device bit mask, shift before setting
    _uPoll      : UDINT := 0;                // 轮询计数工作值 [次] / poll count working value [count]
    _uTo        : UDINT := 0;                // 超时计数工作值 [次] / timeout count working value [count]
END_VAR
VAR CONSTANT
    DL_BHD_MAX      : INT := 16;             // 设备容量与索引回钳上界 [台] / device capacity and index clamp upper bound
    DL_BHD_RETRY_MAX: INT := 9;              // 重试上限的钳定上限 [次] / clamp ceiling of the retry cap [count]
    DL_BHD_CNT_MAX  : UDINT := 2000000000;   // 计数饱和上限（常量在 DINT 可表范围内）[次] / count saturation ceiling, the constant fits in DINT
    DL_BHD_MASK_NONE: WORD := 16#0000;       // 空掩码常量 [-] / empty mask constant
    DL_BHD_MASK_ONE : WORD := 16#0001;       // 单位位常量 [-] / single bit constant
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支）；轮询间隔用自复位式周期发生器 / segment 0, unconditional refresh with a self resetting periodic generator
rtResp(CLK := bRespPulse); // 响应沿无条件刷新 / unconditional refresh of the response edge
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge
tonPollInt(IN := (NOT tonPollInt.Q) AND bEnable AND (NOT _bFault), PT := tPollInt); // 轮询间隔周期发生器，Q 到时下一拍即重启（R328 周期脉冲方向）/ periodic poll generator that restarts right after its own pulse
tonResp(IN := (_ePhase = E_DL_BhdPhase.eWait) AND (NOT rtResp.Q) AND (NOT _bFault), PT := tRespTo); // 响应超时，IN 串等待相闸与响应到达补集 / response timeout with the waiting gate and the response complement on IN

// 段 1｜首扫初始化（R310）/ segment 1, first scan initialisation
IF NOT _bInit THEN // 首扫一拍 / the very first scan
    _bInit := TRUE; // 置首扫完成标志 / raise the first scan flag
    _ePhase := E_DL_BhdPhase.eIdle; // 相位从空闲起步 / the phase starts from idle
    _eCause := E_DL_BhdCause.eNone; // 信息级成因清零 / clear the informational cause
    _eFaultCause := E_DL_BhdCause.eNone; // 故障级成因清零 / clear the fault cause
    _bFault := FALSE; // 故障锁存清零 / clear the fault latch
    _wOff := DL_BHD_MASK_NONE; // 离线掩码清零 / clear the offline mask
    _wOn := DL_BHD_MASK_NONE; // 在线掩码清零 / clear the online mask
    _nIdx := 1; // 索引归位 / park the index at one
    _uPoll := 0; // 轮询计数清零 / clear the poll count
    _uTo := 0; // 超时计数清零 / clear the timeout count
END_IF

// 段 2｜复位沿作用域：清锁存 / 清掩码 / 清计数与索引（四项逐项声明）/ segment 2, reset edge scope declared item by item
IF rtReset.Q THEN // 复位沿 / reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaultCause := E_DL_BhdCause.eNone; // 作用域一：清故障级成因 / scope one, clear the fault cause
    _wOff := DL_BHD_MASK_NONE; // 作用域二：清离线掩码 / scope two, clear the offline mask
    _wOn := DL_BHD_MASK_NONE; // 作用域二：清在线掩码 / scope two, clear the online mask
    _nIdx := 1; // 作用域三：索引归位 / scope three, park the index
    _nCurRetry := 0; // 作用域三：清重试计数 / scope three, clear the retry count
    _ePhase := E_DL_BhdPhase.eIdle; // 作用域四：迁回空闲相 / scope four, migrate back to idle
    _bPollInt := FALSE; // 作用域四：清轮询脉冲内部位 / scope four, clear the internal poll bit
    _bToInt := FALSE; // 作用域四：清超时脉冲内部位 / scope four, clear the internal timeout bit
END_IF

// 段 3｜组态域闸（R151 全覆盖）/ segment 3, configuration domain gate over every pin
_bCfgBad := FALSE; // 组态非法预置假 / preset the illegal configuration verdict to false
IF (nDevCount < 1) OR (nDevCount > DL_BHD_MAX) THEN // 设备数越域 / the device count is out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (nRetryMax < 0) OR (nRetryMax > DL_BHD_RETRY_MAX) THEN // 重试上限越域 / the retry cap is out of domain
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF (tPollInt <= T#0S) OR (tRespTo <= T#0S) THEN // 时间引脚非正 / a time pin is not positive
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF tRespTo >= tPollInt THEN // 响应超时窗不得覆盖整个轮询间隔（配比约束，R100）/ the response window must not swallow the whole poll interval
    _bCfgBad := TRUE; // 判非法 / mark illegal
END_IF
IF _bCfgBad AND (NOT _bFault) THEN // 组态非法且未锁存 / illegal configuration and not yet latched
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaultCause := E_DL_BhdCause.eCfgIllegal; // 故障级成因 (R45 配对 bError) / fault grade cause paired with bError
    _ePhase := E_DL_BhdPhase.eFault; // 迁故障相 / migrate to the fault phase
END_IF
_nUseCount := nDevCount; // 设备数直通 / the device count passes through
IF _nUseCount < 1 THEN // 下越界 / below the lower bound
    _nUseCount := 1; // 回钳到 1 / clamp to one
ELSIF _nUseCount > DL_BHD_MAX THEN // 上越界 / above the upper bound
    _nUseCount := DL_BHD_MAX; // 回钳到 16 / clamp to sixteen
END_IF
_nRetryUse := nRetryMax; // 重试上限直通 / the retry cap passes through
IF _nRetryUse < 0 THEN // 下越界（防御）/ below the lower bound as a defence
    _nRetryUse := 0; // 回钳到 0 / clamp to zero
ELSIF _nRetryUse > DL_BHD_RETRY_MAX THEN // 上越界 / above the upper bound
    _nRetryUse := DL_BHD_RETRY_MAX; // 回钳到 9 / clamp to nine
END_IF
IF _nIdx < 1 THEN // 索引下越界 / the index is below the lower bound
    _nIdx := 1; // 回钳到 1 / clamp to one
ELSIF _nIdx > _nUseCount THEN // 索引上越界 / the index is above the upper bound
    _nIdx := _nUseCount; // 回钳到末台 / clamp to the last unit
END_IF

// 段 4｜失效使能与设备位更新 / segment 4, enable handling and device bit updates
_eCause := E_DL_BhdCause.eNone; // 信息级成因每拍重算 / the informational cause is recomputed every scan
_bOfflineNew := FALSE; // 新转离线标志预置假 / preset the new offline flag to false
_bAllOff := FALSE; // 全离线标志每拍重算 / the all offline flag is recomputed every scan
IF NOT bEnable THEN // 失能：停轮询并保持掩码（R191 显式声明）/ disabled, polling stops and the masks hold
    _ePhase := E_DL_BhdPhase.eIdle; // 回空闲相 / return to idle
    _bPollInt := FALSE; // 撤轮询脉冲内部位 / withdraw the internal poll bit
    _bToInt := FALSE; // 撤超时脉冲内部位 / withdraw the internal timeout bit
END_IF
_wBit := SHL(DL_BHD_MASK_ONE, _nIdx - 1); // 当前设备位掩码，位移量 0..15 由索引回钳与容量常量证明 / the current device bit mask, the shift zero through fifteen is proven by the index clamp and the capacity constant
IF rtResp.Q AND (_ePhase = E_DL_BhdPhase.eWait) THEN // 等待相收到响应 / a response arrived while waiting
    _wOff := _wOff AND NOT _wBit; // 清离线位 / clear the offline bit
    _wOn := _wOn OR _wBit; // 置在线位 / set the online bit
    _nCurRetry := 0; // 清重试计数 / clear the retry count
    _ePhase := E_DL_BhdPhase.ePoll; // 本轮结束，转下一轮发出相 / the round is finished and the next issuing phase follows
    _bFound := FALSE; // 跳过命中标志预置假 / preset the skip hit flag to false
    _nGuard := 0; // 守护计数清零 / reset the guard
    WHILE (_nGuard < DL_BHD_MAX) AND (NOT _bFound) DO // 跳过离线设备，守护上限为容量 / skip offline devices with the capacity as the guard
        _nGuard := _nGuard + 1; // 守护计数递增 / increment the guard
        _nIdx := _nIdx + 1; // 索引前进 / advance the index
        IF _nIdx > _nUseCount THEN // 越过末台 / past the last unit
            _nIdx := 1; // 回卷到首台 / wrap back to the first unit
        END_IF
        _wBit := SHL(DL_BHD_MASK_ONE, _nIdx - 1); // 候选设备位掩码 / the candidate device bit mask
        _bIsOffline := ((_wOff AND _wBit) <> DL_BHD_MASK_NONE); // 候选设备是否离线 / whether the candidate is offline
        IF NOT _bIsOffline THEN // 候选在线 / the candidate is online
            _bFound := TRUE; // 命中 / hit
        END_IF
    END_WHILE
    IF NOT _bFound THEN // 全部离线，仍逐台尝试（探测恢复）/ every device is offline and probing continues
        _nIdx := _nIdx + 1; // 索引照常前进 / the index advances anyway
        IF _nIdx > _nUseCount THEN // 越过末台 / past the last unit
            _nIdx := 1; // 回卷到首台 / wrap back to the first unit
        END_IF
        _bAllOff := TRUE; // 置全离线标志 / raise the all offline flag
    END_IF
END_IF
IF tonResp.Q AND (_ePhase = E_DL_BhdPhase.eWait) THEN // 等待相超时 / the waiting phase timed out
    _bToInt := TRUE; // 超时脉冲内部位置位（统一出口映射，R187）/ raise the internal timeout bit, mapped at the unified outlet
    IF _uTo < DL_BHD_CNT_MAX THEN // 未达饱和上限 / below the ceiling
        _uTo := _uTo + 1; // 超时计数递增 / increment the timeout count
    END_IF
    IF _nCurRetry < _nRetryUse THEN // 重试未用尽 / retries remain
        _nCurRetry := _nCurRetry + 1; // 重试计数递增并立即重发 / increment the retry count and re-issue at once
        _ePhase := E_DL_BhdPhase.ePoll; // 回发出相重试同一台 / back to the issuing phase for the same unit
    ELSE // 重试用尽 / retries exhausted
        _wOff := _wOff OR _wBit; // 置离线位 / set the offline bit
        _wOn := _wOn AND NOT _wBit; // 清在线位 / clear the online bit
        _bOfflineNew := TRUE; // 记新转离线 / record the new offline event
        _nCurRetry := 0; // 重试计数清零 / clear the retry count
        _ePhase := E_DL_BhdPhase.ePoll; // 回发出相转下一台 / back to the issuing phase for the next unit
        _bFound := FALSE; // 跳过命中标志预置假 / preset the skip hit flag to false
        _nGuard := 0; // 守护计数清零 / reset the guard
        WHILE (_nGuard < DL_BHD_MAX) AND (NOT _bFound) DO // 跳过离线设备 / skip offline devices
            _nGuard := _nGuard + 1; // 守护计数递增 / increment the guard
            _nIdx := _nIdx + 1; // 索引前进 / advance the index
            IF _nIdx > _nUseCount THEN // 越过末台 / past the last unit
                _nIdx := 1; // 回卷到首台 / wrap back to the first unit
            END_IF
            _wBit := SHL(DL_BHD_MASK_ONE, _nIdx - 1); // 候选设备位掩码 / the candidate device bit mask
            _bIsOffline := ((_wOff AND _wBit) <> DL_BHD_MASK_NONE); // 候选设备是否离线 / whether the candidate is offline
            IF NOT _bIsOffline THEN // 候选在线 / the candidate is online
                _bFound := TRUE; // 命中 / hit
            END_IF
        END_WHILE
        IF NOT _bFound THEN // 全部离线 / every device is offline
            _bAllOff := TRUE; // 置全离线标志 / raise the all offline flag
        END_IF
    END_IF
END_IF

// 段 5｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 5, phase machine with an ELSE fallback for illegal phases
CASE _ePhase OF
E_DL_BhdPhase.eIdle: // 空闲相：使能且无故障才起轮询 / idle, polling starts when enabled and unfaulted
    IF bEnable AND (NOT _bFault) THEN // 使能且无故障 / enabled and unfaulted
        _ePhase := E_DL_BhdPhase.ePoll; // 迁发出相 / migrate to the issuing phase
    END_IF

E_DL_BhdPhase.ePoll: // 发出相：本拍发轮询触发并转等待相 / issuing phase, the trigger is raised and the waiting phase follows
    IF bEnable AND (NOT _bFault) AND tonPollInt.Q THEN // 轮询间隔到 / the poll interval elapsed
        _bPollInt := TRUE; // 轮询触发内部位置位（统一出口映射，R187）/ raise the internal poll bit, mapped at the unified outlet
        IF _uPoll < DL_BHD_CNT_MAX THEN // 未达饱和上限 / below the ceiling
            _uPoll := _uPoll + 1; // 轮询计数递增 / increment the poll count
        END_IF
        _ePhase := E_DL_BhdPhase.eWait; // 迁等待相 / migrate to the waiting phase
    END_IF

E_DL_BhdPhase.eWait: // 等待相：等响应或超时（两出口均在段 4 处理）/ waiting phase, the response and the timeout are handled in segment four
    IF (NOT bEnable) OR _bFault THEN // 失能或故障 / disabled or faulted
        _ePhase := E_DL_BhdPhase.eIdle; // 回空闲相 / return to idle
    END_IF

E_DL_BhdPhase.eFault: // 故障相：停轮询，等复位沿 / fault phase, polling stopped until the reset edge
    _bPollInt := FALSE; // 撤轮询脉冲内部位 / withdraw the internal poll bit
    _bToInt := FALSE; // 撤超时脉冲内部位 / withdraw the internal timeout bit
    _nCurRetry := 0; // 清重试计数 / clear the retry count

ELSE // 非法相位兜底（R128）/ illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaultCause := E_DL_BhdCause.eCfgIllegal; // 故障级成因记组态非法 / record the illegal configuration cause
    _ePhase := E_DL_BhdPhase.eFault; // 迁故障相 / migrate to the fault phase
END_CASE

// 段 6｜离线统计：逐台扫全容量统计，未参与设备按零位计 / segment 6, offline statistics over the full capacity
_nOfflineCnt := 0; // 离线计数清零 / clear the offline count
_nIdxProbe := 1; // 探测索引自 1 起 / the probe index starts at one
WHILE _nIdxProbe <= DL_BHD_MAX DO // 全容量扫查，未参与设备恒为零位 / sweep the full capacity because unused devices stay cleared
    _wBit := SHL(DL_BHD_MASK_ONE, _nIdxProbe - 1); // 本设备位掩码 / this device bit mask
    IF ((_wOff AND _wBit) <> DL_BHD_MASK_NONE) THEN // 本设备离线 / this device is offline
        _nOfflineCnt := _nOfflineCnt + 1; // 离线计数递增 / increment the offline count
    END_IF
    _nIdxProbe := _nIdxProbe + 1; // 索引递增 / increment the index
END_WHILE

// 段 7｜成因分派（固定优先级：故障 > 新转离线 > 全离线 > 无设备 > 无成因）/ segment 7, cause dispatch with a fixed priority
IF _bFault THEN // 故障锁存优先 / the fault latch takes priority
    eCause := _eFaultCause; // 故障级成因锁存回放 / the fault cause is replayed from the latch
ELSIF _bOfflineNew THEN // 本拍有新设备转离线 / a device went offline this scan
    eCause := E_DL_BhdCause.eDevOffline; // 信息级成因 / informational cause
ELSIF _bAllOff THEN // 全部离线 / every device is offline
    eCause := E_DL_BhdCause.eAllOffline; // 信息级成因 / informational cause
ELSE // 设备数为零的情形已由组态域闸 eCfgIllegal 承载（R56 死分支删除留痕）/ the no device case is carried by the configuration gate
    eCause := _eCause; // 信息级成因直映 / the informational cause is mapped directly
END_IF

// 段 8｜统一出口 / segment 8, unified outlet
nPollIdx := _nIdx; // 当前轮询设备号出口 / currently polled device outlet
bPollTrig := _bPollInt; // 轮询触发映射本拍值 / map the poll trigger for this scan
_bPollInt := FALSE; // 映射后立即撤销，保证单拍宽度（R187 两段式）/ revoke right after mapping to keep a single-scan width
bRespTimeout := _bToInt; // 超时脉冲映射本拍值 / map the timeout pulse for this scan
_bToInt := FALSE; // 映射后立即撤销，保证单拍宽度（R187 两段式）/ revoke right after mapping to keep a single-scan width
wOnlineMask := _wOn; // 在线掩码出口 / online mask outlet
wOfflineMask := _wOff; // 离线掩码出口 / offline mask outlet
uPollCnt := _uPoll; // 轮询计数出口 / poll count outlet
uTimeoutCnt := _uTo; // 超时计数出口 / timeout count outlet
nOfflineCnt := _nOfflineCnt; // 离线设备数出口 / offline device count outlet
nCurRetry := _nCurRetry; // 当前重试次数出口 / current retry count outlet
ePhase := _ePhase; // 相位出口单点映射 / single-point phase outlet mapping
bError := _bFault; // 故障标志与锁存位同源 / the fault flag shares the latch source
END_FUNCTION_BLOCK
