(*
  FB_DL_BmsPdiGateway  —  楼宇侧 PDI 对象网关轮询（调度 + 异常上报） / Building-side PDI object gateway polling: scheduling plus exception report
  分类 Category : DL_Device
  版本 Version  : 1.0.0
  来源 Source   : t1-4-codesys-forge — 网关轮询族零检索深化（与 PdiReadScheduler 调度底座分工：那件为底层调度，本件为楼宇网关应用件）
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 轮询调度：bPollTick 调用方节拍沿驱动，对象索引 0..uObjCnt-1
                  轮转（uObjCnt 域闸 1..8），每拍采信当前对象 bPollOk / fObjVal
                  契约快照，逐对象连续失败计数 auFailCnt；
                  2) 异常上报：连续失败达 uFailTo → 0528 首出对象锁存
                  （nFirstFailObj 记首出号，R190 归因唯一）；对象值非有限
                  → 0529 防御锁存（NaN 自反判）；
                  3) 成功承载：失败计数清零 + 值快照写入 afObjVal + 信息级
                  042E；首出锁存拍发 042F；
                  4) 故障级：0528 对象连续失败超阈 / 0529 对象值非有限 /
                  052A 组态非法（对象数越域）+ ELSE 兜底归并；
                  5) 信息级三码：轮询成功 / 超时上报 / 网关复位（单拍沿）；
                  6) 解除式全当拍量（R240 落地），逐 BOOL 标注见段 4。
  边界 Boundary : ① 分段理由（R192）：段 0003 故障带 03A0~03FF 于 R42 用尽，
                  启用 05xx 副带续编，避开 0590~0599 判错位段；
                  ② 组态闸：uObjCnt = 0 或 > 8 或 uFailTo = 0 → 052A 锁存，
                  轮询停发；对象索引域 0..7 由 uObjCnt 域闸与常量 8 结构性限定；
                  ③ 失败计数 USINT 饱和前置判（防回绕）；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : Standard.library（R_TRIG）
  码表 Error codes（Device 段 0003，窗口 0528~052A / 042E~0430）:
    16#0003_0528 故障级：对象连续失败超阈锁存（首出对象号入 nFirstFailObj），锁存至 bReset
    16#0003_0529 故障级：对象值非有限锁存（防御兜底），锁存至 bReset
    16#0003_052A 故障级：组态非法（对象数/失败阈域非法）或相位落 ELSE 兜底（归并声明），锁存至 bReset
    16#0003_042E 信息级：轮询成功沿（对象值快照写入拍）
    16#0003_042F 信息级：超时上报沿（首出锁存拍）
    16#0003_0430 信息级：网关复位沿（台账清零拍）
  修订历史 Revision :
    2026-11-19  v1.0.0  R42 首版（批次 4 · 序号 5）
*)

TYPE E_DL_BpgState :
(
    eIdle  := 0,     // 未使能：不轮询 / Idle, not polling
    ePoll  := 10,    // 轮询中：逐对象承载 / Poll, per-object engaged
    eFault := 90     // 故障：首出或非有限锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_BmsPdiGateway
VAR_INPUT
    bPollTick    : BOOL := FALSE;     // 轮询节拍沿（调用方驱动）[-] / Poll tick edge from caller
    bPollOk      : BOOL := FALSE;     // 当前对象轮询成功（当拍量契约）[-] / Current-object poll success
    fObjVal      : REAL := 0.0;       // 当前对象值 [工程单位]，bPollOk 当拍采信 / Current-object value
    uObjCnt      : USINT := 8;        // 对象总数 [1..8]，域闸 / Object count
    uFailTo      : USINT := 3;        // 连续失败阈 [次]，域 > 0 / Consecutive-fail threshold
    bGwEn        : BOOL := FALSE;     // 网关使能（电平）[-] / Gateway enable, level
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存与台账 / Reset edge
END_VAR
VAR_OUTPUT
    eState       : E_DL_BpgState;     // 状态出口，段尾单点映射 / State outlet
    nObjIdx      : DINT;              // 当前轮询对象号 [0..7]，-1 = 未轮询 / Current polling object index
    afObjVal     : ARRAY[0..7] OF REAL;   // 逐对象值快照 [工程单位] / Per-object value snapshots
    auFailCnt    : ARRAY[0..7] OF USINT;  // 逐对象连续失败计数 [次] / Per-object fail counts
    nFirstFailObj: DINT;              // 首出失败对象号 [0..7]，-1 = 无首出 / First failed object index
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    rtPollTick   : R_TRIG;            // 轮询节拍沿实例，无条件刷新 / Poll tick edge instance
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _eState      : E_DL_BpgState := E_DL_BpgState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _nObjCursor  : UDINT := 0;        // 轮转游标 [0..uObjCnt-1] / Round-robin cursor
    _nIdx        : DINT;              // 阵列循环索引 [-] / Array loop index
    _bValNonFin  : BOOL;              // 对象值非有限当拍量 [-] / Object-value non-finite flag
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_bValNonFin := (fObjVal <> fObjVal)
            OR ((fObjVal - fObjVal) <> (fObjVal - fObjVal));    // 值非有限防御（NaN 自反 + 差值自减）
rtPollTick(CLK := bPollTick);       // 轮询节拍沿（每拍必调）
rtReset(CLK := bReset);             // 复位沿（每拍必调）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 与计数阵列不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
nObjIdx := -1;                      // 对象号缺省 -1
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（判据当拍量） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
    nFirstFailObj := -1;            // 首出对象号恢复哨兵
    FOR _nIdx := 0 TO 7 DO          // 台账逐对象清零
        auFailCnt[_nIdx] := 0;      // 失败计数清零
        afObjVal[_nIdx] := 0.0;     // 值快照清零
    END_FOR
    _uInfo := 16#0003_0430;         // 信息级：网关复位沿
END_IF
IF (uObjCnt < 1) OR (uObjCnt > 8) OR (uFailTo = 0) THEN      // 域闸（1..8 与失败阈）
    _uFault := 16#0003_052A;        // 故障级：组态非法
    _bFault := TRUE;                // 故障标志与码位配对（R45）
END_IF

(* —— 段 3：轮询沿承载（判据当拍量；对象索引由域闸 1..8 结构性限域） —— *)
IF rtPollTick.Q AND (_eState = E_DL_BpgState.ePoll) AND (NOT _bFault) THEN
    _nObjCursor := (_nObjCursor + 1) MOD UDINT(uObjCnt);    // 轮转游标（模基数域闸 > 0，无除零）
    nObjIdx := UDINT_TO_DINT(_nObjCursor);          // 当前对象号（域 0..uObjCnt-1 ⊆ 0..7）
    IF bPollOk THEN                 // 成功承载（当拍量契约）
        auFailCnt[nObjIdx] := 0;    // 失败计数清零
        IF NOT _bValNonFin THEN     // 值快照仅非有限闸通过后写入（FB32-7 保持槽闸）
            afObjVal[nObjIdx] := fObjVal;       // 值快照写入
        END_IF
        _uInfo := 16#0003_042E;     // 信息级：轮询成功沿
    ELSE                            // 失败承载
        IF auFailCnt[nObjIdx] < 255 THEN
            auFailCnt[nObjIdx] := auFailCnt[nObjIdx] + 1;   // 计数递增（饱和前置判防回绕）
        END_IF
        IF (auFailCnt[nObjIdx] >= uFailTo) AND (nFirstFailObj = -1) THEN
            nFirstFailObj := nObjIdx;   // 首出对象号锁定（仅首个写入）
            _uFault := 16#0003_0528;    // 故障级：连续失败超阈
            _bFault := TRUE;
            _uInfo := 16#0003_042F;     // 信息级：超时上报沿
        END_IF
    END_IF
    IF _bValNonFin AND bPollOk THEN // 成功契约但值非有限：防御锁存（0529 独立归因）
        _uFault := 16#0003_0529;    // 故障级：对象值非有限
        _bFault := TRUE;
    END_IF
END_IF

(* —— 段 4：故障解除式（R240 落地，逐 BOOL 标注）：
     rtReset.Q = 当拍量；bPollOk = 当拍量；NOT bGwEn = 当拍量。
     均不含锁存量（_bFault/_uFault），解除边真实可达（轮询恢复 + 撤使能 + 复位沿）。 —— *)
IF rtReset.Q AND bPollOk AND (NOT bGwEn) THEN
    _bFault := FALSE;               // 清故障锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，仅本当拍量解除沿可清）
    IF _eState = E_DL_BpgState.eFault THEN
        _eState := E_DL_BpgState.eIdle;     // 故障相迁出：回未使能
    END_IF
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_BpgState.eIdle:
    IF bGwEn AND (NOT _bFault) THEN
        _eState := E_DL_BpgState.ePoll;     // 使能：进轮询相
    END_IF

E_DL_BpgState.ePoll:
    IF (NOT _bFault) AND (NOT bGwEn) THEN
        _eState := E_DL_BpgState.eIdle;     // 撤使能：回未使能相
    END_IF
    (* 首出/非有限迁出在段 3 承载（置 _bFault 后次拍迁故障相） *)

E_DL_BpgState.eFault:
    ;                               // 故障相：轮询冻结，等解除沿（段 4 承载迁出）

ELSE
    _uFault := 16#0003_052A;        // 故障级：非法相位兜底（归并组态码，码表声明）
    _bFault := TRUE;
    _eState := E_DL_BpgState.eFault;    // 强制回故障相

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    nObjIdx := -1;                  // 故障相对象号恢复未轮询哨兵
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
eState := _eState;                  // 状态出口单点映射

END_FUNCTION_BLOCK
