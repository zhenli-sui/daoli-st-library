(*
  FB_DL_SafetyDoorAuditBank  —  化成柜多安全门审计汇总（开门次数/批次锁定） / Formation cabinet multi-door audit bank: open counts and batch lock
  分类 Category : DL_Process
  版本 Version  : 1.0.0
  来源 Source   : t2-8-isa182 — 安全联锁审计族深化（与 I_DL_SafetyDoor 单门接口分工：那件管单门状态，本件管多门汇总）
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 8 门固定阵列逐门开门沿计数：每门 R_TRIG 阵列无条件周期刷新，
                  沿触发总计数 uOpenTotal 与分门计数 auOpenCnt 递增；
                  2) 批次锁定审计：bBatchLock 激活期任一门开门 → 0379 违约锁存
                  （独立记录首出违约门号 nViolDoor，R190 归因唯一）；
                  3) 审计饱和保护：uOpenTotal 逼近 UDINT 上限 → 停止递增并 037A
                  饱和锁存（防回绕伪造审计记录，还原方向不饱和原则）；
                  4) 相位机：eIdle（未使能）→ eAudit（审计中）→ eFault；
                  5) 信息级三码：开门计数沿 / 批次锁定激活 / 审计复位完成；
                  6) 解除式全当拍量（R240 落地），逐 BOOL 标注见段 4。
  边界 Boundary : ① 组态闸：bAuditEn = FALSE 相不计数不判违（审计仅使能相承载）；
                  ② 饱和反证句：饱和场景（累计达上限）不可由任何现有输出组合观测
                  （bError/nErrId 均无对应位），故独立占 037A；
                  ③ ELSE 兜底归并 037B 组态码（码表声明）；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : Standard.library（R_TRIG）
  码表 Error codes（Process 段 0005，窗口 0379~037B / 04A1~04A3）:
    16#0005_0379 故障级：批次锁定期间开门违约锁存（首出门号入 nViolDoor），锁存至 bReset
    16#0005_037A 故障级：审计总计数饱和锁存（停止递增防回绕），锁存至 bReset
    16#0005_037B 故障级：相位落 ELSE 兜底（归并声明），锁存至 bReset
    16#0005_04A1 信息级：开门计数沿（任一门开门沿触发）
    16#0005_04A2 信息级：批次锁定激活沿（进锁定审计态）
    16#0005_04A3 信息级：审计计数复位完成沿（bCountRst 生效拍）
  修订历史 Revision :
    2026-11-19  v1.0.0  R42 首版（批次 1 · 序号 4）
*)

TYPE E_DL_SdaState :
(
    eIdle   := 0,    // 未使能：不计数不判违 / Idle, not counting
    eAudit  := 10,   // 审计中：开门沿计数与批次违例监视 / Audit, counting and lock watch
    eFault  := 90    // 故障：违约或饱和锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_SafetyDoorAuditBank
VAR_INPUT
    a_bDoorOpen  : ARRAY[0..7] OF BOOL;  // 8 门开门反馈阵列，TRUE = 开 [-] / Door-open feedback array
    bAuditEn     : BOOL := FALSE;        // 审计使能（电平）[-] / Audit enable, level
    bBatchLock   : BOOL := FALSE;        // 批次锁定（电平），锁定期开门即违例 [-] / Batch lock, level
    bCountRst    : BOOL := FALSE;        // 计数复位指令，上升沿清全部计数 [-] / Count reset command edge
    bReset       : BOOL := FALSE;        // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_OUTPUT
    eState       : E_DL_SdaState;     // 状态出口，段尾单点映射 / State outlet
    uOpenTotal   : UDINT;             // 开门总计数 [次]，饱和即锁 / Total open count
    auOpenCnt    : ARRAY[0..7] OF UDINT;  // 分门开门计数 [次] / Per-door open counts
    nViolDoor    : USINT;             // 首出违约门号 [0..7]，255 = 无违约 / First violating door index
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    a_rtDoor     : ARRAY[0..7] OF R_TRIG; // 8 门开门沿实例阵列，无条件刷新 / Door edge instance array
    rtCountRst   : R_TRIG;            // 计数复位沿实例，无条件刷新 / Count reset edge instance
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _eState      : E_DL_SdaState := E_DL_SdaState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _bLockInfoSent: BOOL;             // 批次锁定信息沿单发标志 / Lock-info one-shot sent flag
    _nIdx        : DINT;              // 阵列循环索引 [-] / Array loop index
    _bAnyOpen    : BOOL;              // 任一门开当拍量 [-] / Any-door-open current-scan flag
    _bSatWarn    : BOOL;              // 饱和临近当拍量（距上限不足 8 次计数）[-] / Near-saturation flag
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_bAnyOpen := a_bDoorOpen[0] OR a_bDoorOpen[1] OR a_bDoorOpen[2] OR a_bDoorOpen[3]
          OR a_bDoorOpen[4] OR a_bDoorOpen[5] OR a_bDoorOpen[6] OR a_bDoorOpen[7];
                                        // 任一门开（当拍量，展开式判据）
FOR _nIdx := 0 TO 7 DO               // 8 门沿实例逐门刷新（每拍必调）
    a_rtDoor[_nIdx](CLK := a_bDoorOpen[_nIdx]);          // 开门沿（每拍必调）
END_FOR
_bSatWarn := (uOpenTotal >= 16#FFFFFFF8);            // 饱和临近（距上限不足 8 计数槽）
rtCountRst(CLK := bCountRst);                        // 计数复位沿（每拍必调）
rtReset(CLK := bReset);                              // 复位沿（每拍必调）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 计数复位沿（判据当拍量） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
    nViolDoor := 255;               // 违约门号恢复哨兵 255 = 无违约
END_IF
IF rtCountRst.Q AND (NOT _bAnyOpen) THEN             // 复位沿 + 全部关门（当拍量）才可清零
    uOpenTotal := 16#0000_0000;     // 总计数清零
    FOR _nIdx := 0 TO 7 DO          // 分门计数清零
        auOpenCnt[_nIdx] := 16#0000_0000;    // 逐门清零
    END_FOR
    _uInfo := 16#0005_04A3;         // 信息级：审计复位完成沿
END_IF

(* —— 段 3：开门沿计数与违约/饱和锁存（判据当拍量；每拍至多递增一次净额） —— *)
FOR _nIdx := 0 TO 7 DO              // 逐门开门沿审计（每门独立归因）
    IF a_rtDoor[_nIdx].Q AND (_eState = E_DL_SdaState.eAudit) THEN
        IF bBatchLock AND (NOT _bFault) AND (nViolDoor = 255) THEN
            _uFault := 16#0005_0379;        // 故障级：批次锁定开门违约（首出门号锁定）
            _bFault := TRUE;                // 故障标志与码位配对（R45）
            nViolDoor := USINT_TO_USINT(_nIdx);     // 首出违约门号（DINT 收窄，域 0..7 结构性安全）
        ELSIF NOT _bSatWarn THEN
            uOpenTotal := uOpenTotal + 1;   // 总计数递增（饱和临近期停止）
            auOpenCnt[_nIdx] := auOpenCnt[_nIdx] + 1;   // 分门计数递增
            _uInfo := 16#0005_04A1;         // 信息级：开门计数沿
        END_IF
    END_IF
END_FOR
IF _bSatWarn AND (_eState = E_DL_SdaState.eAudit) AND (NOT _bFault) THEN
    _uFault := 16#0005_037A;        // 故障级：审计总计数饱和锁存
    _bFault := TRUE;
END_IF

(* —— 段 4：故障解除式（R240 落地，逐 BOOL 标注）：
     rtReset.Q = 当拍量；NOT _bAnyOpen = 当拍量；NOT bBatchLock = 当拍量。
     均不含锁存量（_bFault/_uFault），解除边真实可达（关门 + 撤锁 + 复位沿）。 —— *)
IF rtReset.Q AND (NOT _bAnyOpen) AND (NOT bBatchLock) THEN
    _bFault := FALSE;               // 清故障锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，仅本当拍量解除沿可清）
    IF _eState = E_DL_SdaState.eFault THEN
        _eState := E_DL_SdaState.eIdle;     // 故障相迁出：回未使能
    END_IF
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_SdaState.eIdle:
    IF bAuditEn AND (NOT _bFault) THEN
        _eState := E_DL_SdaState.eAudit;    // 使能：进审计相
    END_IF

E_DL_SdaState.eAudit:
    IF bBatchLock AND (NOT _bLockInfoSent) THEN
        _uInfo := 16#0005_04A2;             // 信息级：批次锁定激活沿（单发）
        _bLockInfoSent := TRUE;             // 沿单发标志
    END_IF
    IF NOT bBatchLock THEN
        _bLockInfoSent := FALSE;            // 撤锁重置单发标志
    END_IF
    IF NOT bAuditEn THEN
        _eState := E_DL_SdaState.eIdle;     // 撤使能：回未使能相
    END_IF
    (* 违约/饱和迁出在段 3 承载 *)

E_DL_SdaState.eFault:
    ;                                       // 故障相：等解除沿（段 4 承载迁出）

ELSE
    _uFault := 16#0005_037B;                // 故障级：非法相位兜底
    _bFault := TRUE;
    _eState := E_DL_SdaState.eFault;        // 强制回故障相

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
