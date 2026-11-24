(*
  FB_DL_InverterPdiPoll  —  逆变器 PDI 参数周期读取（单拍单发 + 站表台账） / Inverter PDI parameter cyclic poll with a station ledger
  分类 Category : DL_Device
  版本 Version  : 1.0.0
  来源 Source   : t1-7-plcnext — PDI 应用族零检索深化（基于 PdiReadScheduler 底座）
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 站表 aSlot 逐站轮询：eIdle（间隔到）→ eReq（单发 bStart）→ eWait
                  （等 bDone）→ eJudge（读-比-判：bSuccess 且 uActLen = 期望长度）；
                  2) 单拍单发纪律：全轮询任意时刻仅一个在途请求（状态机单相承载）；
                  3) 台账：uOkTotal / uFailTotal / 站内连续失败计数，达 nFailLatch 阈
                  → 故障级 03FD 锁存；
                  4) 站间推进沿 041C；全站巡检一周完成沿 041D；连续失败未达阈提示 041E。
  边界 Boundary : ① 组态闸：uStationCnt < 1 或 > 8 → 03FC 锁存（站表容量下限 >= 1）；
                  ② Device 段 0003 故障带仅余 03FC~03FF，本件启用 03FC/03FD 两格，
                  分段理由：03xx 带收口分配，不足溢出走 05xx 副带（本轮未占用）；
                  ③ fbPdi 输入引脚在 eIdle 相整定、eReq 相单发，禁批量并发；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : FB_DL_PdiReadScheduler（注入，不实例化，引脚按 registry 实名）；Standard.library（TON / R_TRIG）
  码表 Error codes（Device 段 0003，窗口 041C~041E / 故障 03FC~03FD）:
    16#0003_03FC 故障级：组态非法（站数界外），锁存至 bReset
    16#0003_03FD 故障级：站点连续失败达阈锁存（台账口径），锁存至 bReset
    16#0003_041C 信息级：站间推进沿（切换下一站）
    16#0003_041D 信息级：全站巡检一周完成沿
    16#0003_041E 信息级：连续失败未达阈提示（伴随态）
  修订历史 Revision :
    2026-11-19  v1.0.0  R41 首版（批次 4 · 序号 1）
*)

TYPE E_DL_InvPollState :
(
    eIdle  := 0,    // 空闲：等站间间隔 / Idle, waiting the inter-station gap
    eReq   := 10,   // 请求：单发启动 / Request, one-shot start
    eWait  := 20,   // 等待：等传输层完成 / Wait, transport completion
    eJudge := 30,   // 判定：读-比-判三段 / Judge, read-compare-verdict
    eFault := 90    // 故障：连续失败锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_InverterPdiPoll
VAR_INPUT
    aSlot        : ARRAY[1..8] OF UINT;   // 站表（设备号）[号] / Station slot table
    uStationCnt  : UINT := 1;         // 站数 [站]，域 1..8 / Station count
    uIndex       : UINT := 16#2035;   // PDI 对象索引（逆变器参数例）/ Object index
    uSubindex    : USINT := 0;        // 对象子索引 / Object subindex
    nExpLen      : INT := 2;          // 期望数据长度 [字节] / Expected data length
    tPollGap     : TIME := T#100MS;   // 站间间隔 [ms]，域 > 0 / Inter-station gap
    tWaitTo      : TIME := T#2S;      // 在途等待超时 [ms]，域 > 0 / In-flight wait timeout
    nFailLatch   : INT := 3;          // 连续失败锁存阈 [次]，域 >= 1 / Consecutive-fail latch threshold
    bEnable      : BOOL := FALSE;     // 轮询使能 [-] / Poll enable
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_IN_OUT
    fbPdi        : FB_DL_PdiReadScheduler;  // PDI 调度底座（注入，不实例化）/ PDI scheduler base
END_VAR
VAR_OUTPUT
    eState       : E_DL_InvPollState; // 状态出口，段尾单点映射 / State outlet
    uCurSlot     : UINT;              // 当前站号出口 [号] / Current slot outlet
    uIdx         : UINT;              // 当前站序号（1 基）[站] / Current station index
    uOkTotal     : UDINT;             // 累计成功数 [次]，饱和不回绕 / Total success count
    uFailTotal   : UDINT;             // 累计失败数 [次]，饱和不回绕 / Total failure count
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonGap       : TON;               // 站间间隔定时器（自复位口径），无条件刷新 / Inter-station gap timer
    tonWaitTo    : TON;               // 在途等待定时器（专用超时命名），无条件刷新 / In-flight wait timer
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _eState      : E_DL_InvPollState := E_DL_InvPollState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _uIdx        : UINT := 1;         // 内部站序号（1 基）/ Internal station index
    _nFailRun    : INT;               // 站内连续失败计数 [次] / Consecutive-fail streak
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR
VAR CONSTANT
    DL_IPP_CNT_MAX : UDINT := 16#FFFF_FFFE;  // 台账计数饱和上限 [次] / Ledger saturation bound
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
rtReset(CLK := bReset);                                   // 复位沿（每拍必调）
tonGap(IN := (_eState = E_DL_InvPollState.eIdle) AND bEnable AND (NOT _bFault), PT := tPollGap);
                                                          // 站间间隔（每拍必调，TON 自复位口径 IN 断即清）
tonWaitTo(IN := (_eState = E_DL_InvPollState.eWait), PT := tWaitTo);   // 在途等待（单相独占）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault/台账计数不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（当拍量判据） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF
IF (UINT_TO_INT(uStationCnt) < 1) OR (UINT_TO_INT(uStationCnt) > 8)
   OR (TIME_TO_DINT(tPollGap) <= 0) OR (TIME_TO_DINT(tWaitTo) <= 0) OR (nFailLatch < 1) THEN
    _uFault := 16#0003_03FC;        // 故障级：组态非法
    _bFault := TRUE;
END_IF

(* —— 段 3：底座输入整定（每拍写入；bStart 仅 eReq 相电平置位构成单发沿） —— *)
fbPdi.bEnable := bEnable AND (NOT _bFault);   // 底座使能随本件
IF (UINT_TO_INT(_uIdx) >= 1) AND (UINT_TO_INT(_uIdx) <= 8) THEN
    fbPdi.uSlot := aSlot[UINT_TO_INT(_uIdx)]; // 当前站号下装（界内守卫）
END_IF
fbPdi.uIndex := uIndex;             // 对象索引下装
fbPdi.uSubindex := uSubindex;       // 子索引下装
fbPdi.nExpLen := nExpLen;           // 期望长度下装（比较段判据）
fbPdi.bStart := (_eState = E_DL_InvPollState.eReq);   // 单发沿（eReq 单相电平，下一相即断）

(* —— 段 4：相位机（CASE 全覆盖 + ELSE 兜底；单拍单发由状态机单相承载） —— *)
CASE _eState OF

E_DL_InvPollState.eIdle:
    IF _bFault THEN
        _eState := E_DL_InvPollState.eFault;    // 故障相
    ELSIF bEnable AND tonGap.Q THEN
        fbPdi.bEnable := TRUE;                  // 底座使能确认
        _eState := E_DL_InvPollState.eReq;      // 进请求相（bStart 下一拍电平置位成沿）
    END_IF

E_DL_InvPollState.eReq:
    IF _bFault THEN
        _eState := E_DL_InvPollState.eFault;    // 故障相（bStart 已断）
    ELSE
        _eState := E_DL_InvPollState.eWait;     // bStart 单发即进等待相（下一拍电平断）
    END_IF

E_DL_InvPollState.eWait:
    IF _bFault THEN
        _eState := E_DL_InvPollState.eFault;    // 故障相
    ELSIF tonWaitTo.Q THEN
        _nFailRun := _nFailRun + 1;             // 超时按失败入账
        uFailTotal := uFailTotal + 1;           // 台账累加
        IF uFailTotal >= DL_IPP_CNT_MAX THEN
            uFailTotal := DL_IPP_CNT_MAX;       // 台账饱和防回绕
        END_IF
        _eState := E_DL_InvPollState.eIdle;     // 回空闲（下一站间隔后重试）
    ELSIF fbPdi.bDone THEN
        _eState := E_DL_InvPollState.eJudge;    // 完成沿：进判定相
    END_IF

E_DL_InvPollState.eJudge:
    IF _bFault THEN
        _eState := E_DL_InvPollState.eFault;    // 故障相
    ELSIF fbPdi.bSuccess AND (fbPdi.uActLen = INT_TO_UINT(nExpLen)) THEN
        uOkTotal := uOkTotal + 1;               // 台账成功累加
        IF uOkTotal >= DL_IPP_CNT_MAX THEN
            uOkTotal := DL_IPP_CNT_MAX;         // 台账饱和防回绕
        END_IF
        _nFailRun := 0;                         // 连败计数清零
        _uInfo := 16#0003_041C;                 // 信息级：站间推进沿（成功随行）
        _uIdx := _uIdx + 1;                     // 下一站
        IF UINT_TO_INT(_uIdx) > UINT_TO_INT(uStationCnt) THEN
            _uIdx := 1;                         // 站表回卷
            _uInfo := 16#0003_041D;             // 信息级：全站巡检一周完成
        END_IF
        _eState := E_DL_InvPollState.eIdle;     // 回空闲
    ELSE
        _nFailRun := _nFailRun + 1;             // 失败或长度不匹配：连败入账
        uFailTotal := uFailTotal + 1;           // 台账累加
        IF uFailTotal >= DL_IPP_CNT_MAX THEN
            uFailTotal := DL_IPP_CNT_MAX;       // 台账饱和防回绕
        END_IF
        IF _nFailRun >= nFailLatch THEN
            _uFault := 16#0003_03FD;            // 故障级：连续失败达阈锁存
            _bFault := TRUE;
            _eState := E_DL_InvPollState.eFault;
        ELSE
            _uInfo := 16#0003_041E;             // 信息级：连败未达阈提示
            _eState := E_DL_InvPollState.eIdle; // 回空闲重试
        END_IF
    END_IF

E_DL_InvPollState.eFault:
    ;                                   // 故障相：等复位沿（段 2 承载迁出）

ELSE
    _uFault := 16#0003_03FC;            // 故障级：非法相位兜底（归并组态码，头注释②）
    _bFault := TRUE;
    _eState := E_DL_InvPollState.eFault;    // 强制回故障相

END_CASE

(* —— 段 5：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
uCurSlot := aSlot[UINT_TO_INT(_uIdx)];      // 当前站号出口（站表 1..8 静态界内）
IF UINT_TO_INT(_uIdx) < 1 THEN
    uIdx := 1;                      // 序号下界防御
ELSIF UINT_TO_INT(_uIdx) > 8 THEN
    uIdx := 8;                      // 序号上界防御
ELSE
    uIdx := _uIdx;                  // 序号直通
END_IF
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
eState := _eState;                  // 状态出口单点映射

END_FUNCTION_BLOCK
