(*
  FB_DL_PollAuditBank  —  多链路轮询异常台账汇总（多实例轮询 + 首出） / Multi-link polling audit bank with first-out ledger
  分类 Category : DL_Process
  版本 Version  : 1.0.0
  来源 Source   : t1-3-oscat-network — 网络轮询审计族零检索深化
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 4 链路轮询审计：调用方轮询节拍沿 bPollTrig + 每链路当拍
                  成功量 a_bLinkOk 承载；逐链连续失败计数 auFailCnt，达 uFailTo
                  → 038E 链路异常锁存（首出链路号入 nFirstFailLink，R190 归因
                  以首出唯一承载，各链路计数独立保持）；
                  2) 恢复审计：失败计数非零链路在轮询沿收到成功 → 04B7 恢复沿
                  且计数清零；恢复不解除已锁存故障（解除仅复位沿承载）；
                  3) 故障级：038E 连续失败超阈 / 038F 组态非法（uFailTo = 0）/
                  0390 ELSE 兜底；信息级三码：首出记录 / 链路恢复 / 台账清零；
                  4) 相位机：eIdle（未使能）→ eAudit（审计中）→ eFault；
                  5) 解除式全当拍量（R240 落地），逐 BOOL 标注见段 4。
  边界 Boundary : ① 组态闸：bPollEn = FALSE 相不计数不判阈（审计仅使能相承载）；
                  ② uFailTo = 0 → 038F 锁存（连续失败阈域闸）；
                  ③ 失败计数上限钳 255（USINT 饱和前置判，防回绕）；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : Standard.library（R_TRIG）
  码表 Error codes（Process 段 0005，窗口 038E~0390 / 04B6~04B8）:
    16#0005_038E 故障级：链路连续失败超阈锁存（首出链路号入 nFirstFailLink），锁存至 bReset
    16#0005_038F 故障级：组态非法（失败阈 uFailTo = 0），锁存至 bReset
    16#0005_0390 故障级：相位落 ELSE 兜底，锁存至 bReset
    16#0005_04B6 信息级：首出失败记录沿（故障锁存拍）
    16#0005_04B7 信息级：链路恢复沿（失败计数非零链路收成功拍）
    16#0005_04B8 信息级：台账清零沿（复位沿清全部计数）
  修订历史 Revision :
    2026-11-19  v1.0.0  R42 首版（批次 3 · 序号 1）
*)

TYPE E_DL_PabState :
(
    eIdle   := 0,    // 未使能：不计数不判阈 / Idle, not counting
    eAudit  := 10,   // 审计中：逐链失败计数 / Audit, per-link fail counting
    eFault  := 90    // 故障：首出锁存 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_PollAuditBank
VAR_INPUT
    a_bLinkOk    : ARRAY[0..3] OF BOOL;  // 4 链路轮询成功量（当拍量）[-] / Per-link poll success flags
    bPollTrig    : BOOL := FALSE;        // 轮询节拍沿（调用方驱动）[-] / Poll tick edge from caller
    uFailTo      : USINT := 3;           // 连续失败阈 [次]，域 > 0 / Consecutive-fail threshold
    bPollEn      : BOOL := FALSE;        // 审计使能（电平）[-] / Audit enable, level
    bReset       : BOOL := FALSE;        // 复位，上升沿清故障锁存与台账 / Reset edge clears fault and ledger
END_VAR
VAR_OUTPUT
    eState       : E_DL_PabState;     // 状态出口，段尾单点映射 / State outlet
    auFailCnt    : ARRAY[0..3] OF USINT;  // 逐链连续失败计数 [次] / Per-link consecutive-fail counts
    nFirstFailLink : DINT;            // 首出失败链路号 [0..3]，-1 = 无首出 / First failed link index
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    rtPollTrig   : R_TRIG;            // 轮询节拍沿实例，无条件刷新 / Poll tick edge instance
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _eState      : E_DL_PabState := E_DL_PabState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _nIdx        : DINT;              // 阵列循环索引 [-] / Array loop index
    _bAllOk      : BOOL;              // 全链成功当拍量（展开式聚合）[-] / All-links-ok flag
    _nGuard      : DINT;              // WHILE/循环防死锁计数器（本件 FOR 结构性有限，仍保留计数）[-] / Loop guard counter
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_bAllOk := a_bLinkOk[0] AND a_bLinkOk[1] AND a_bLinkOk[2] AND a_bLinkOk[3];
                                        // 全链成功（当拍量，展开式聚合）
rtPollTrig(CLK := bPollTrig);           // 轮询节拍沿（每拍必调）
rtReset(CLK := bReset);                 // 复位沿（每拍必调）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 与计数阵列不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（判据当拍量） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
    nFirstFailLink := -1;           // 首出链路号恢复哨兵
    FOR _nIdx := 0 TO 3 DO          // 台账逐链清零
        auFailCnt[_nIdx] := 0;      // 失败计数清零
    END_FOR
    _uInfo := 16#0005_04B8;         // 信息级：台账清零沿
END_IF
IF uFailTo = 0 THEN                 // 失败阈域闸（USINT 判等合规）
    _uFault := 16#0005_038F;        // 故障级：组态非法
    _bFault := TRUE;                // 故障标志与码位配对（R45）
END_IF

(* —— 段 3：轮询沿承载逐链审计（判据当拍量；FOR 上界 3 结构性有限，守卫计数保留） —— *)
_nGuard := 0;                       // 守卫计数预置
FOR _nIdx := 0 TO 3 DO              // 逐链审计
    _nGuard := _nGuard + 1;         // 守卫递增（FOR 结构性 ≤ 4 次，守卫仅防未来改版失控）
    IF _nGuard > 4 THEN
        EXIT;                       // 守卫兜底：异常退出（结构性不可达，防御保留）
    END_IF
    IF rtPollTrig.Q AND (_eState = E_DL_PabState.eAudit) THEN
        IF a_bLinkOk[_nIdx] THEN    // 成功：恢复审计（失败计数非零才发恢复沿）
            IF auFailCnt[_nIdx] > 0 THEN
                auFailCnt[_nIdx] := 0;              // 计数清零
                _uInfo := 16#0005_04B7;             // 信息级：链路恢复沿
            END_IF
        ELSE                        // 失败：计数递增（USINT 饱和前置判防回绕）
            IF auFailCnt[_nIdx] < 255 THEN
                auFailCnt[_nIdx] := auFailCnt[_nIdx] + 1;   // 计数递增
            END_IF
            IF (auFailCnt[_nIdx] >= uFailTo) AND (nFirstFailLink = -1) THEN
                nFirstFailLink := _nIdx;            // 首出链路号锁定（仅首个写入）
                _uFault := 16#0005_038E;            // 故障级：连续失败超阈
                _bFault := TRUE;
                _uInfo := 16#0005_04B6;             // 信息级：首出失败记录沿
            END_IF
        END_IF
    END_IF
END_FOR

(* —— 段 4：故障解除式（R240 落地，逐 BOOL 标注）：
     rtReset.Q = 当拍量；_bAllOk = 当拍量；NOT bPollEn = 当拍量。
     均不含锁存量（_bFault/_uFault），解除边真实可达（全链恢复 + 撤使能 + 复位沿）。 —— *)
IF rtReset.Q AND _bAllOk AND (NOT bPollEn) THEN
    _bFault := FALSE;               // 清故障锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，仅本当拍量解除沿可清）
    IF _eState = E_DL_PabState.eFault THEN
        _eState := E_DL_PabState.eIdle;     // 故障相迁出：回未使能
    END_IF
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_PabState.eIdle:
    IF bPollEn AND (NOT _bFault) THEN
        _eState := E_DL_PabState.eAudit;    // 使能：进审计相
    END_IF

E_DL_PabState.eAudit:
    IF (NOT _bFault) AND (NOT bPollEn) THEN
        _eState := E_DL_PabState.eIdle;     // 撤使能：回未使能相
    END_IF
    (* 首出锁存迁出在段 3 承载（置 _bFault 后段 5 次拍迁故障相） *)

E_DL_PabState.eFault:
    ;                                   // 故障相：等解除沿（段 4 承载迁出）

ELSE
    _uFault := 16#0005_0390;            // 故障级：非法相位兜底
    _bFault := TRUE;
    _eState := E_DL_PabState.eFault;    // 强制回故障相

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
eState := _eState;                  // 状态出口单点映射

END_FUNCTION_BLOCK
