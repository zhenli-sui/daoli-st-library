(*
  FB_DL_PipeScannerRoute  —  管输批次扫码分输（扫码枪契约 + 阀序分道） / Pipe batch scan-and-route: scanner contract plus valve sequence routing
  分类 Category : DL_Process
  版本 Version  : 1.0.0
  来源 Source   : t2-2-lbp — 管输分输族深化
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 四相顺控：eIdle（等批次到达沿）→ eWaitScan（等扫码枪契约
                  bScanValid，tScanTo 超时判）→ eValve（按 uBatchId MOD nRoutes
                  分道，开阀等阀位反馈）→ eDone（关阀回 eIdle）；
                  2) 扫码契约：uBatchId 仅在 bScanValid 当拍采信（锁存快照），
                  分道号 nRouteIdx := UDINT_TO_DINT(uBatchId MOD nRoutes)
                  （模基数域闸 1..4，无除零）；
                  3) 故障级：0388 组态非法（分道数越域）+ ELSE 兜底归并 /
                  0389 扫码缺失超窗锁存 / 038A 开阀后阀位反馈不一致锁存；
                  4) 信息级三码：扫码成功 / 分道指令发出 / 分道完成（单拍沿）；
                  5) 解除式全当拍量（R240 落地），逐 BOOL 标注见段 4。
  边界 Boundary : ① 超时 TON 均单相独占（IN 为单相等式），跨相迁移拍 IN 必断
                  （R228-A）；阀超时与扫码超时分实例；
                  ② 阀反馈判据仅认当拍量 a_bValveFb，禁锁存反馈自指；
                  ③ 分道索引域 0..3 由 nRoutes 域闸 1..4 与 MOD 结构性限定；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Process 段 0005，窗口 0388~038A / 04B0~04B2）:
    16#0005_0388 故障级：组态非法（分道数越域 1..4）或相位落 ELSE 兜底（归并声明），锁存至 bReset
    16#0005_0389 故障级：扫码缺失超窗锁存（tScanTo 内 bScanValid 未出现），锁存至 bReset
    16#0005_038A 故障级：阀位反馈不一致锁存（开阀 tValveTo 内未到位），锁存至 bReset
    16#0005_04B0 信息级：扫码成功沿（契约有效采信拍）
    16#0005_04B1 信息级：分道指令发出沿（开阀拍）
    16#0005_04B2 信息级：分道完成沿（回 eIdle）
  修订历史 Revision :
    2026-11-19  v1.0.0  R42 首版（批次 2 · 序号 4）
*)

TYPE E_DL_PsrState :
(
    eIdle     := 0,   // 空闲：等批次到达 / Idle, waiting batch arrival
    eWaitScan := 10,  // 等扫码：契约窗计时 / Wait scan, contract window
    eValve    := 20,  // 开阀：等阀位反馈 / Valve, waiting feedback
    eDone     := 30,  // 完成：关阀确认 / Done, valve closed confirm
    eFault    := 90   // 故障：超时锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_PipeScannerRoute
VAR_INPUT
    bBatchArrive : BOOL := FALSE;     // 批次到达指令，上升沿启动分输 [-] / Batch arrival edge
    bScanValid   : BOOL := FALSE;     // 扫码枪契约有效（当拍量）[-] / Scanner contract valid, current-scan
    uBatchId     : UDINT := 0;        // 批次号（bScanValid 当拍采信）[-] / Batch ID sampled on valid
    a_bValveFb   : ARRAY[0..3] OF BOOL;  // 4 道阀位反馈，TRUE = 到位 [-] / Valve feedbacks, TRUE = in position
    nRoutes      : USINT := 4;        // 分道数 [1..4]，域闸 / Route count
    tScanTo      : TIME := T#5S;      // 扫码等待超时 [ms]，域 > 0 / Scan wait timeout
    tValveTo     : TIME := T#3S;      // 阀反馈超时 [ms]，域 > 0 / Valve feedback timeout
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_OUTPUT
    eState       : E_DL_PsrState;     // 状态出口，段尾单点映射 / State outlet
    a_bValveCmd  : ARRAY[0..3] OF BOOL;  // 4 道阀指令，TRUE = 开阀 [-] / Valve commands
    nRouteIdx    : DINT;              // 分道号 [0..3]，-1 = 未分道 / Routed index
    bDone        : BOOL;              // 分输完成标志（eDone 相电平）[-] / Routing done flag
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonScanTo    : TON;               // 扫码等待超时（单相独占），无条件刷新 / Scan wait timeout
    tonValveTo   : TON;               // 阀反馈超时（单相独占），无条件刷新 / Valve feedback timeout
    rtArrive     : R_TRIG;            // 批次到达沿实例，无条件刷新 / Arrival edge instance
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _eState      : E_DL_PsrState := E_DL_PsrState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _uBatchSnap  : UDINT;             // 批次号采信快照（锁存量）/ Batch ID trusted snapshot
    _bCmdSent    : BOOL;              // 分道指令发出沿单发标志 / Route-command one-shot flag
    _bFbOpen     : BOOL;              // 阀反馈到位当拍量（展开式聚合）[-] / Valve feedback open flag
    _bFbAllOff   : BOOL;              // 阀反馈全关当拍量（展开式聚合）[-] / All-valve-feedback-off flag
    _nIdx        : DINT;              // 阵列循环索引 [-] / Array loop index
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_bFbOpen := a_bValveFb[0] OR a_bValveFb[1] OR a_bValveFb[2] OR a_bValveFb[3];
                                        // 任一阀反馈到位（当拍量，展开式聚合）
_bFbAllOff := (NOT a_bValveFb[0]) AND (NOT a_bValveFb[1])
          AND (NOT a_bValveFb[2]) AND (NOT a_bValveFb[3]);
                                        // 全部阀反馈关位（当拍量，展开式聚合）
rtArrive(CLK := bBatchArrive);                           // 到达沿（每拍必调）
rtReset(CLK := bReset);                                  // 复位沿（每拍必调）
tonScanTo(IN := (_eState = E_DL_PsrState.eWaitScan), PT := tScanTo);  // 扫码窗（单相独占）
tonValveTo(IN := (_eState = E_DL_PsrState.eValve), PT := tValveTo);   // 阀反馈窗（单相独占）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault/_uBatchSnap 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
bDone := FALSE;                     // 完成标志缺省 FALSE
nRouteIdx := -1;                    // 分道号缺省 -1
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（当拍量判据） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF
IF (nRoutes < 1) OR (nRoutes > 4) THEN                   // 分道数域闸（1..4）
    _uFault := 16#0005_0388;        // 故障级：组态非法
    _bFault := TRUE;                // 故障标志与码位配对（R45）
END_IF

(* —— 段 3：扫码与阀反馈超时锁存（判据当拍量/单相独占 TON） —— *)
IF (NOT _bFault) AND tonScanTo.Q THEN
    _uFault := 16#0005_0389;        // 故障级：扫码缺失超窗
    _bFault := TRUE;
END_IF
IF (NOT _bFault) AND tonValveTo.Q THEN
    _uFault := 16#0005_038A;        // 故障级：阀位反馈不一致
    _bFault := TRUE;
END_IF

(* —— 段 4：故障解除式（R240 落地，逐 BOOL 标注）：
     rtReset.Q = 当拍量；NOT bBatchArrive = 当拍量；_bFbAllOff = 当拍量。
     均不含锁存量（_bFault/_uFault），解除边真实可达（指令撤销 + 全关反馈 + 复位沿）。 —— *)
IF rtReset.Q AND (NOT bBatchArrive) AND _bFbAllOff THEN
    _bFault := FALSE;               // 清故障锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，仅本当拍量解除沿可清）
    IF _eState = E_DL_PsrState.eFault THEN
        _eState := E_DL_PsrState.eIdle;     // 故障相迁出：回空闲
    END_IF
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_PsrState.eIdle:
    FOR _nIdx := 0 TO 3 DO              // 阀指令全关（空闲安全侧）
        a_bValveCmd[_nIdx] := FALSE;    // 关阀指令
    END_FOR
    IF rtArrive.Q AND (NOT _bFault) THEN
        _bCmdSent := FALSE;             // 单发标志复位（进相预置）
        _eState := E_DL_PsrState.eWaitScan;     // 进等扫码相
    END_IF

E_DL_PsrState.eWaitScan:
    IF bScanValid THEN                  // 契约有效（当拍量）：采信批次号快照
        _uBatchSnap := uBatchId;        // 采信快照（锁存量，仅此处写）
        nRouteIdx := UDINT_TO_DINT(_uBatchSnap MOD UDINT(nRoutes));
                                        // 分道号（模基数域闸 1..4，无除零；域 0..3 结构性安全）
        _uInfo := 16#0005_04B0;         // 信息级：扫码成功沿
        _eState := E_DL_PsrState.eValve;        // 进开阀相
    END_IF
    (* 扫码超时迁出在段 3 承载 *)

E_DL_PsrState.eValve:
    a_bValveCmd[nRouteIdx] := TRUE;     // 开当前分道阀（nRouteIdx 域 0..3 结构性安全）
    IF NOT _bCmdSent THEN               // 发出沿单发（进相首拍）
        _uInfo := 16#0005_04B1;         // 信息级：分道指令发出沿
        _bCmdSent := TRUE;              // 单发标志
    END_IF
    IF a_bValveFb[nRouteIdx] THEN       // 当前道阀反馈到位（当拍量判据）
        _eState := E_DL_PsrState.eDone; // 进完成相
    END_IF
    (* 阀反馈超时迁出在段 3 承载 *)

E_DL_PsrState.eDone:
    bDone := TRUE;                      // 完成标志（相电平）
    FOR _nIdx := 0 TO 3 DO              // 阀指令全关
        a_bValveCmd[_nIdx] := FALSE;    // 关阀指令
    END_FOR
    _uInfo := 16#0005_04B2;             // 信息级：分道完成沿
    _eState := E_DL_PsrState.eIdle;     // 回空闲相

E_DL_PsrState.eFault:
    FOR _nIdx := 0 TO 3 DO              // 故障相阀指令全关（安全侧）
        a_bValveCmd[_nIdx] := FALSE;    // 关阀指令
    END_FOR

ELSE
    _uFault := 16#0005_0388;            // 故障级：非法相位兜底（归并组态码，码表声明）
    _bFault := TRUE;
    _eState := E_DL_PsrState.eFault;    // 强制回故障相

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    bDone := FALSE;                 // 故障相完成出口强制 FALSE（安全侧）
    nRouteIdx := -1;                // 故障相分道号恢复未分道哨兵
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
eState := _eState;                  // 状态出口单点映射

END_FUNCTION_BLOCK
