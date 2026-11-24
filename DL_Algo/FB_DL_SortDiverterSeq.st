(*
  DL Factory R83 | FB_DL_SortDiverterSeq
  功能：分拣分流器握手与故障恢复状态机，包裹到位后出分流指令并等动作确认、再等复位反馈，动作超时进重试（至多两次）后锁码，锁存可由复位沿解除恢复。
  开源溯源：无（clean-room 自研，依据公开工艺公式，来源=行业通用公式，许可证=MIT，借鉴点=公式结构）
  规则：R1-R21 全遵守
  ------------------------------------------------------------------
  分类 DL_Algo ｜ 复杂度 cx3 ｜ 版本 v1.0.0 ｜ 平台 纯 IEC 61131-3（TON、R_TRIG，无私有库）
  边界：一 本件只出分流指令与放行闸两路布尔命令，不驱动电磁阀线圈、不做包裹测速与到位判定（属主边界）；
        二 握手三段固定：到位（bParcelAt 上升沿）→ 分流指令（bDivertCmd）→ 动作确认（bAckFb 上升沿）
           → 复位反馈（bHomeFb 上升沿）→ 放行；三段证据齐全才置握手见证 _bHs；确认与复位反馈均为
           沿语义，须回零后再置位，电平自持不产生新沿（届时按超时走重试或锁码）；
        三 动作确认超时进重试：每次超时先把指令拉低（eRetry 相），重试间隔窗到再出指令；
           重试次数以 nMaxRetry 为预算（组态闸限定 0 至 2），预算耗尽仍超时即锁 402，不再重试；
        四 复位反馈超时锁 403；到位滞留超时锁 404；组态或预算越域锁 401；非法相位锁 405；
           故障锁存由 bReset 上升沿解除（唯一解除路径，R188），锁存期码位一律回放（R152）；
        五 R510 守卫（默认引脚值组合不得绕过握手直达放行）：放行闸为 _bHandshakeSeen 与相位、下游许可、
           使能与锁存位的合取式，默认引脚组合（bParcelAt、bAckFb、bHomeFb、bDownstreamClear 全假）下
           握手见证位恒假，放行闸结构上恒闭；另设「eDone 相缺握手见证即判非法相位」的防御性拦截行；
           本场景不加新码（R90 反证：默认组合下无任何输出组合能把放行闸观测为真，故无需独立码位稀释预留带）；
        六 每相一个专属定时器（到位滞留、动作确认、复位反馈、重试间隔），IN 只串本相使能与锁存闸，
           相迁移即 IN 归假并自复位（R18）；四窗分属不同相、无同拍双窗，R100 配比约束不适用；
        七 单向计数纪律（R45 ③）：重试计数 _nRetry 的自增点唯一（eCmd 超时分支），其余位置只做清零；
           零点共有三处且互斥（首扫与复位沿、eIdle 迁出、eDone 迁出），无任何递减路径；
        八 无全局变量、无外部变量声明、无物理地址寻址。
  输出契约：bDivertCmd 为分流指令电平（仅 eCmd 相，故障与失能一律归零）；bReleaseGate 为放行闸；
        bHandshakeOk 为握手见证位（三段证据齐全，新循环起点清零）；nRetryCnt 为已用重试次数；
        bDone 为保持式完成位（包裹离开时清零，R28 5.9 清零点）；iErrCode 为锁存回放。
  修订记录：2026-11-24 v1.0.0 R83 首版（批 R83 · 序号 40）
*)

TYPE E_DL_SdvPhase :
(
    eIdle  := 0,  // 空闲等使能 / idle, waiting for the enable
    eWait  := 10, // 等到位：等包裹到位沿 / waiting for the parcel arrival edge
    eCmd   := 20, // 分流指令：出指令并等动作确认 / the divert command is on and the acknowledgement is awaited
    eBack  := 30, // 等复位：等分流器复位反馈 / waiting for the diverter home feedback
    eRetry := 40, // 重试：指令拉低，等重试间隔窗 / retrying, the command is off while the gap window runs
    eDone  := 50, // 完成：握手齐全，等包裹离开后放行结束 / done, the handshake is complete and the parcel leaves
    eFault := 90  // 故障：成因锁存等复位沿 / fault, the cause is latched until the reset edge
);
END_TYPE

TYPE E_DL_SdvCause :
(
    eNone     := 0, // 无成因 / no cause
    eCfgBad   := 1, // 组态或重试预算越域（故障级，与 bError 配对）/ the configuration or the retry budget is out of domain, fault grade paired with bError
    eAckTo    := 2, // 动作确认超时且预算耗尽（故障级，与 bError 配对）/ the acknowledgement timed out with the budget exhausted, fault grade paired with bError
    eHomeTo   := 3, // 复位反馈超时（故障级，与 bError 配对）/ the home feedback timed out, fault grade paired with bError
    eWaitTo   := 4, // 包裹到位滞留超时（故障级，与 bError 配对）/ the parcel arrival lingered past its window, fault grade paired with bError
    ePhaseBad := 5  // 非法相位或缺握手见证的完成相（故障级，与 bError 配对）/ an illegal phase or a done phase without the handshake witness, fault grade paired with bError
);
END_TYPE

FUNCTION_BLOCK FB_DL_SortDiverterSeq
VAR CONSTANT
    DL_SDV_RETRY_MAX : INT := 2; // 重试次数硬上限（预算域上限）[次] / the hard upper bound of the retry budget [time]
END_VAR
VAR_INPUT
    bEnable          : BOOL := TRUE;  // 使能，失能回空闲且指令归零 [-] / enable, a disable returns to idle with the command zeroed
    bReset           : BOOL := FALSE; // 复位上升沿清故障锁存并回空闲 [-] / reset rising edge clears the latch and returns to idle
    bParcelAt        : BOOL := FALSE; // 包裹到位光电（上升沿起握手）[-]/ the parcel arrival photo sensor, its rising edge starts the handshake
    bAckFb           : BOOL := FALSE; // 分流器动作确认反馈（上升沿）[-]/ the diverter action acknowledgement, its rising edge
    bHomeFb          : BOOL := FALSE; // 分流器复位反馈（上升沿）[-]/ the diverter home feedback, its rising edge
    bDownstreamClear : BOOL := FALSE; // 下游放行许可（默认假，保守侧）[-]/ the downstream clearance, default false on the safe side
    nMaxRetry        : INT := 2;      // 允许重试次数（域 0 至 2）[次] / the allowed retry count, domain zero to two [time]
    tWaitTo          : TIME := T#10S; // 包裹到位滞留超时窗 [毫秒] / the parcel arrival lingering window [millisecond]
    tAckTo           : TIME := T#2S;  // 动作确认超时窗 [毫秒] / the acknowledgement timeout window [millisecond]
    tHomeTo          : TIME := T#5S;  // 复位反馈超时窗 [毫秒] / the home feedback timeout window [millisecond]
    tRetryGap        : TIME := T#1S;  // 重试间隔窗（指令拉低时段）[毫秒] / the retry gap window while the command is off [millisecond]
END_VAR
VAR_OUTPUT
    bBusy        : BOOL := FALSE; // 本包裹处理中 [-] / a parcel is being handled
    bDone        : BOOL := FALSE; // 本包裹握手齐全（保持式，包裹离开清零）[-] / the handshake completed for this parcel
    bFault       : BOOL := FALSE; // 故障锁存 [-] / the fault latch
    bError       : BOOL := FALSE; // 故障标志，与锁存位同源 [-] / the fault flag sharing the latch source
    iErrCode     : INT := 0;      // 错误码（锁存回放，复位沿清零）[码] / the error code replayed from the latch [code]
    ePhase       : E_DL_SdvPhase := E_DL_SdvPhase.eIdle; // 相位出口 [枚举] / the phase outlet [enum]
    bDivertCmd   : BOOL := FALSE; // 分流指令电平（仅 eCmd 相）[-] / the divert command level, eCmd only
    bReleaseGate : BOOL := FALSE; // 放行闸（握手齐全且下游许可）[-] / the release gate, handshake complete and downstream clear
    bHandshakeOk : BOOL := FALSE; // 握手见证位（三段证据齐全）[-] / the handshake witness covering all three evidences
    nRetryCnt    : INT := 0;      // 已用重试次数 [次] / the used retry count [time]
END_VAR
VAR
    rtReset    : R_TRIG; // 复位沿，段 2 无条件刷新 / the reset edge, refreshed unconditionally
    rtParcel   : R_TRIG; // 包裹到位沿，段 2 无条件刷新 / the parcel arrival edge, refreshed unconditionally
    rtAck      : R_TRIG; // 动作确认沿，段 2 无条件刷新 / the acknowledgement edge, refreshed unconditionally
    rtHome     : R_TRIG; // 复位反馈沿，段 2 无条件刷新 / the home feedback edge, refreshed unconditionally
    tonWait    : TON;    // 到位滞留超时窗，只串 eWait 相 / the arrival lingering window gated by eWait
    tonAck     : TON;    // 动作确认超时窗，只串 eCmd 相 / the acknowledgement timeout gated by eCmd
    tonHome    : TON;    // 复位反馈超时窗，只串 eBack 相 / the home feedback timeout gated by eBack
    tonRetry   : TON;    // 重试间隔窗，只串 eRetry 相 / the retry gap window gated by eRetry
    _ePhase    : E_DL_SdvPhase := E_DL_SdvPhase.eIdle; // 内部相位，CASE 唯一写入目标 / the internal phase, the only CASE target
    _eCause    : E_DL_SdvCause := E_DL_SdvCause.eNone; // 故障级成因，锁存至复位沿 / the fault cause latched until reset
    _bFault    : BOOL := FALSE; // 故障锁存位 [-] / the fault latch
    _iErrLch   : INT := 0;      // 码位锁存槽（复位沿清零）[码] / the latched code, cleared at the reset edge
    _bDone     : BOOL := FALSE; // 完成位内部锁存（清零归属：段 3 复位沿与 eDone 迁出分支）[-] / the internal done bit
    _bHs       : BOOL := FALSE; // 握手见证位内部锁存（三段证据齐全，新循环起点清零）[-] / the handshake witness, cleared at a new cycle
    _bInit     : BOOL := FALSE; // 首扫初始化完成标志（R310）[-] / the first scan initialisation flag
    _bCfgOk    : BOOL := FALSE; // 组态与重试预算域内 [-] / the configuration and the retry budget are inside their domain
    _nRetry    : INT := 0;      // 已用重试次数（单点自增，R45 ③）[次] / the used retry count, incremented at one point only [time]
END_VAR
// 段 0｜组态与重试预算域闸：参与判据换算的引脚逐项枚举（R151）
_bCfgOk := (nMaxRetry >= 0) AND (nMaxRetry <= DL_SDV_RETRY_MAX) // 重试预算落在 [0, 硬上限] / the retry budget inside its domain
    AND (tWaitTo > T#0S) AND (tAckTo > T#0S) AND (tHomeTo > T#0S) AND (tRetryGap > T#0S); // 四个时间引脚域闸 / the four time pins domain gate
// 段 1｜定时器与沿检测无条件周期刷新，IN 只串本相使能与锁存闸（R7、R18）
rtReset(CLK := bReset); // 复位沿无条件刷新 / unconditional refresh of the reset edge
rtParcel(CLK := bParcelAt); // 包裹到位沿无条件刷新 / unconditional refresh of the parcel arrival edge
rtAck(CLK := bAckFb); // 动作确认沿无条件刷新 / unconditional refresh of the acknowledgement edge
rtHome(CLK := bHomeFb); // 复位反馈沿无条件刷新 / unconditional refresh of the home feedback edge
tonWait(IN := (_ePhase = E_DL_SdvPhase.eWait) AND bParcelAt AND (NOT _bFault), PT := tWaitTo); // 到位滞留窗：只串 eWait 相且到位光电为电平（空载等待不计时）/ the arrival window gated by eWait and the live photo level
tonAck(IN := (_ePhase = E_DL_SdvPhase.eCmd) AND (NOT _bFault), PT := tAckTo); // 动作确认窗，只串 eCmd 相 / the acknowledgement window gated by eCmd only
tonHome(IN := (_ePhase = E_DL_SdvPhase.eBack) AND (NOT _bFault), PT := tHomeTo); // 复位反馈窗，只串 eBack 相 / the home window gated by eBack only
tonRetry(IN := (_ePhase = E_DL_SdvPhase.eRetry) AND (NOT _bFault), PT := tRetryGap); // 重试间隔窗，只串 eRetry 相 / the retry gap gated by eRetry only
// 段 2｜首扫初始化与复位沿同块，作用域逐项声明（R310、R311）
IF (NOT _bInit) OR rtReset.Q THEN // 首扫一拍或复位沿 / the first scan or the reset edge
    _bInit := TRUE; // 首扫完成标志（复位沿重复置位同效）/ the first scan flag, the same effect on reset
    _bFault := FALSE; _eCause := E_DL_SdvCause.eNone; _iErrLch := 0; // 作用域一：清锁存、清成因、清码位槽 / scope one, clear the latch, the cause and the code
    _bDone := FALSE; _bHs := FALSE; _ePhase := E_DL_SdvPhase.eIdle; // 作用域二：清完成位、清握手见证并迁回空闲 / scope two, clear done and the witness and migrate to idle
    _nRetry := 0; // 作用域三：清重试计数（三处清零点之一，另两处为 eIdle 与 eDone 迁出）/ scope three, clear the retry counter, one of three clear points
END_IF
// 段 3｜故障判据与锁存：未锁存才判，锁存与迁相同拍执行（R107、FB50-1④、R152）
IF NOT _bFault THEN // 未锁存才判，锁存后一律回放 / judge only while unlatched
    IF NOT _bCfgOk THEN // 组态或重试预算越域 / the configuration or the retry budget is out of domain
        _eCause := E_DL_SdvCause.eCfgBad; _iErrLch := 401; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
        _bFault := TRUE; _ePhase := E_DL_SdvPhase.eFault; // 置锁存并同拍迁故障相 / latch and migrate in the same scan
    ELSIF (_ePhase = E_DL_SdvPhase.eDone) AND (NOT _bHs) THEN // R510 守卫：完成相缺握手见证即判非法（防御性拦截，结构上不可达）
        _eCause := E_DL_SdvCause.ePhaseBad; _iErrLch := 405; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
        _bFault := TRUE; _ePhase := E_DL_SdvPhase.eFault; // 置锁存并同拍迁故障相 / latch and migrate in the same scan
    END_IF
END_IF
// 段 4｜相位状态机：ENUM ＋ CASE ＋ ELSE 非法相位兜底（R6、R128）
CASE _ePhase OF
E_DL_SdvPhase.eIdle: // 空闲相：退出条件二（使能给出、使能未给则驻留）
    IF bEnable THEN // 使能给出 / the enable is given
        _nRetry := 0; _bHs := FALSE; _ePhase := E_DL_SdvPhase.eWait; // 清重试与见证并迁等到位相 / clear the retry and the witness and migrate to wait
    END_IF
E_DL_SdvPhase.eWait: // 等到位相：退出条件三（到位沿、滞留超时、使能丢失）
    IF NOT bEnable THEN // 使能丢失 / the enable was lost
        _ePhase := E_DL_SdvPhase.eIdle; // 回空闲 / back to idle
    ELSIF rtParcel.Q THEN // 到位沿先消化（拍 N 进入：本相起点、本拍行为：拒绝出指令、拍 N+1 转出：指令相）
        _ePhase := E_DL_SdvPhase.eCmd; // 迁分流指令相 / migrate to the command phase
    ELSIF tonWait.Q THEN // 到位光电长期为真而无上升沿（包裹卡滞）/ the photo stayed true without an edge, the parcel is stuck
        _eCause := E_DL_SdvCause.eWaitTo; _iErrLch := 404; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
        _bFault := TRUE; _ePhase := E_DL_SdvPhase.eFault; // 置锁存并迁故障相 / latch and migrate to the fault phase
    END_IF
E_DL_SdvPhase.eCmd: // 分流指令相：指令保持，退出条件三（确认沿、确认超时、使能丢失），事件优先于超时（R275）
    IF NOT bEnable THEN // 使能丢失 / the enable was lost
        _ePhase := E_DL_SdvPhase.eIdle; // 回空闲（指令归零由出口执行）/ back to idle, the outlet zeroes the command
    ELSIF rtAck.Q THEN // 动作确认沿先消化 / digest the acknowledgement edge first
        _ePhase := E_DL_SdvPhase.eBack; // 迁等复位相 / migrate to the home phase
    ELSIF tonAck.Q THEN // 动作确认超时 / the acknowledgement timed out
        IF _nRetry < nMaxRetry THEN // 预算内：进重试 / inside the budget, retry
            _nRetry := _nRetry + 1; // 重试计数单点自增（R45 ③）/ the single increment point of the retry counter
            _ePhase := E_DL_SdvPhase.eRetry; // 迁重试相（指令拉低等间隔窗）/ migrate to retry with the command off
        ELSE // 预算耗尽：锁码 / the budget is exhausted, latch the code
            _eCause := E_DL_SdvCause.eAckTo; _iErrLch := 402; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
            _bFault := TRUE; _ePhase := E_DL_SdvPhase.eFault; // 置锁存并迁故障相 / latch and migrate to the fault phase
        END_IF
    END_IF
E_DL_SdvPhase.eBack: // 等复位相：退出条件三（复位沿、复位超时、使能丢失）；复位沿即三段证据齐全
    IF NOT bEnable THEN // 使能丢失 / the enable was lost
        _ePhase := E_DL_SdvPhase.eIdle; // 回空闲 / back to idle
    ELSIF rtHome.Q THEN // 复位反馈沿：置握手见证并转完成 / the home edge completes the handshake
        _bHs := TRUE; _bDone := TRUE; _ePhase := E_DL_SdvPhase.eDone; // 置见证位与完成位并迁完成相 / raise the witness and done and migrate
    ELSIF tonHome.Q THEN // 复位反馈超时 / the home feedback timed out
        _eCause := E_DL_SdvCause.eHomeTo; _iErrLch := 403; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
        _bFault := TRUE; _ePhase := E_DL_SdvPhase.eFault; // 置锁存并迁故障相 / latch and migrate to the fault phase
    END_IF
E_DL_SdvPhase.eRetry: // 重试相：指令拉低，退出条件二（间隔窗到期回指令相、使能丢失回空闲）
    IF NOT bEnable THEN // 使能丢失 / the enable was lost
        _ePhase := E_DL_SdvPhase.eIdle; // 回空闲 / back to idle
    ELSIF tonRetry.Q THEN // 重试间隔窗到期 / the retry gap expired
        _ePhase := E_DL_SdvPhase.eCmd; // 回指令相重新出指令 / back to the command phase
    END_IF
E_DL_SdvPhase.eDone: // 完成相：退出条件二（包裹离开、使能丢失），完成位与见证位在此清零（单一清零点）
    IF (NOT bParcelAt) OR (NOT bEnable) THEN // 包裹离开或失能 / the parcel left or the enable was lost
        _bDone := FALSE; _bHs := FALSE; _nRetry := 0; _ePhase := E_DL_SdvPhase.eIdle; // 清完成位、见证位与重试并回空闲 / clear done, the witness and the retry and return to idle
    END_IF
E_DL_SdvPhase.eFault: // 故障相：成因锁存回放，唯一解除路径为 bReset 上升沿（R188）
    IF NOT bEnable THEN _ePhase := E_DL_SdvPhase.eIdle; END_IF // 失能迁空闲（锁存位仍须复位沿解除）/ migrate to idle, the latch still needs the reset edge
ELSE // 非法相位兜底（R6、R128）/ the illegal phase fallback
    _eCause := E_DL_SdvCause.ePhaseBad; _iErrLch := 405; bError := TRUE; // 故障级成因、码位与标志（R45 配对）
    _bFault := TRUE; _ePhase := E_DL_SdvPhase.eFault; // 置锁存并迁故障相 / latch and migrate to the fault phase
END_CASE
IF _bFault AND (_ePhase <> E_DL_SdvPhase.eFault) THEN // 段尾迁移闸：任何锁存路径不得留在业务相（FB50-1④）
    _ePhase := E_DL_SdvPhase.eFault; // 统一迁故障相 / force the fault phase
END_IF
// 段 5｜统一出口：指令与放行闸单点映射，R510 守卫在放行闸结构上落地
bDivertCmd := (_ePhase = E_DL_SdvPhase.eCmd) AND bEnable AND (NOT _bFault); // 分流指令：仅指令相且未失能未锁存 / the divert command only in the command phase while enabled and unlatched
bReleaseGate := _bHs AND (_ePhase = E_DL_SdvPhase.eDone) AND bDownstreamClear AND bEnable AND (NOT _bFault); // 放行闸：握手见证与相位、下游许可、使能、锁存位五者合取（默认组合下恒闭，R510 守卫）
bHandshakeOk := _bHs; // 握手见证位单点映射 / single point mapping of the handshake witness
nRetryCnt := _nRetry; // 重试计数单点映射 / single point mapping of the retry counter
bBusy := bEnable AND (_ePhase <> E_DL_SdvPhase.eIdle) AND (_ePhase <> E_DL_SdvPhase.eDone) AND (_ePhase <> E_DL_SdvPhase.eFault); // 运行位排除空闲完成与故障 / the busy bit excludes idle, done and fault
bDone := _bDone; // 完成位单点映射（保持式）/ single point mapping of the held done bit
bFault := _bFault; // 故障锁存单点映射 / single point mapping of the latch
IF _bFault THEN // 故障期回放锁存码，不在故障相按当下输入重推（R152）/ replay the latched code
    iErrCode := _iErrLch; bError := TRUE; // 锁存码回放、故障标志同源 / replay the code and share the latch source
ELSE // 非故障期 / outside fault
    iErrCode := 0; bError := FALSE; // 无故障码与无故障标志 / no code and no flag
END_IF
ePhase := _ePhase; // 相位出口单点映射 / single point mapping of the phase
END_FUNCTION_BLOCK
