(*
  FB_DL_OcvProbeDock  —  OCV 探针台对接下压与接触校验（压力窗 + 接触电阻判据） / OCV prober docking press & contact check
  分类 Category : DL_Process
  版本 Version  : 1.0.0
  来源 Source   : roadmap-li-p1 — 行业池锂电/半导体探针台缺口件
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 四相顺控：eDock（下压，等压力入窗，tDockTo 超时判）
                  → ePress（保压窗 tonHold，超压当拍检出即锁）
                  → eJudge（接触电阻判据 fContOhm <= fContMax）
                  → eDone → 回 eIdle；
                  2) 故障级三码独立锁存：0370 组态非法 / 0371 压力窗判据失效
                  （入窗超时与保压超压归并声明于码表，两向均立即终止安全侧）/
                  0372 接触电阻超限；
                  3) 信息级三码：对接开始 / 压力入窗 / 校验通过（单拍沿）；
                  4) 浮点比较全部容差式或单向阈值，禁 = 判等；
                  5) 解除式全当拍量（R240 落地），逐 BOOL 标注见段 4。
  边界 Boundary : ① 组态闸：fPressMax <= fPressMin、fContMax <= 0、任一时间 <= 0
                  → 0370 锁存，顺控全部停发；
                  ② 非有限输入（压力/电阻 NaN 自反判）→ 并入 0372 防御兜底（归并声明）；
                  ③ 超时 TON 单相独占（IN 为单相等式），跨相迁移拍 IN 必断（R228-A）；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Process 段 0005，窗口 0370~0372 / 0498~049A）:
    16#0005_0370 故障级：组态非法（压力窗颠倒/电阻阈/时间域非法）或相位落 ELSE 兜底（归并声明），锁存至 bReset
    16#0005_0371 故障级：压力窗判据失效（入窗超时 tDockTo 或保压超压，归并声明），锁存至 bReset
    16#0005_0372 故障级：接触电阻超限或输入非有限（防御兜底归并声明），锁存至 bReset
    16#0005_0498 信息级：对接开始沿（进 eDock）
    16#0005_0499 信息级：压力入窗沿（进 ePress）
    16#0005_049A 信息级：接触校验通过沿（进 eDone）
  修订历史 Revision :
    2026-11-19  v1.0.0  R42 首版（批次 1 · 序号 1）
*)

TYPE E_DL_OpdState :
(
    eIdle   := 0,    // 空闲：等启动沿 / Idle, waiting start edge
    eDock   := 10,   // 对接：下压等压力入窗 / Dock, press until pressure in band
    ePress  := 20,   // 保压：保压窗计时 / Press, hold window timing
    eJudge  := 30,   // 判定：接触电阻判据 / Judge, contact resistance verdict
    eDone   := 40,   // 完成：校验通过 / Done
    eFault  := 90    // 故障：任一判据锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_OcvProbeDock
VAR_INPUT
    bStart       : BOOL := FALSE;     // 启动指令，上升沿进入对接 [-] / Start command, rising edge
    fPressKgf    : REAL := 0.0;       // 探针压力反馈 [kgf]，调用方注入 / Probe pressure feedback
    fContOhm     : REAL := 1.0E9;     // 接触电阻反馈 [ohm]，调用方注入 / Contact resistance feedback
    fPressMin    : REAL := 0.5;       // 压力窗下限 [kgf]，域 > 0 / Pressure band lower limit
    fPressMax    : REAL := 2.0;       // 压力窗上限 [kgf]，必须 > fPressMin / Pressure band upper limit
    fContMax     : REAL := 50.0;      // 接触电阻上限 [ohm]，域 > 0 / Contact resistance limit
    tDockTo      : TIME := T#3S;      // 入窗超时 [ms]，域 > 0 / In-band timeout
    tPressHold   : TIME := T#500MS;   // 保压窗 [ms]，域 > 0 / Pressure hold window
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_OUTPUT
    eState       : E_DL_OpdState;     // 状态出口，段尾单点映射 / State outlet
    bDocking     : BOOL;              // 对接进行中标志（eDock/ePress 相电平）[-] / Docking active flag
    bDone        : BOOL;              // 校验完成标志（eDone 相电平）[-] / Check done flag
    bFault       : BOOL;              // 故障锁存标志 / Fault latch flag
    bError       : BOOL;              // 故障级标志（与锁存同源）/ Fault flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonDockTo    : TON;               // 入窗超时定时器（单相独占），无条件刷新 / Dock in-band timeout timer
    tonHold      : TON;               // 保压窗定时器（单相独占），无条件刷新 / Hold window timer
    rtStart      : R_TRIG;            // 启动沿实例，无条件刷新 / Start edge instance
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _eState      : E_DL_OpdState := E_DL_OpdState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _bInBand     : BOOL;              // 压力入窗当拍量 [-] / Pressure-in-band current-scan flag
    _bOver       : BOOL;              // 超压当拍量 [-] / Over-pressure current-scan flag
    _bNonFin     : BOOL;              // 输入非有限当拍量 [-] / Non-finite input current-scan flag
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_bInBand := (fPressKgf >= fPressMin) AND (fPressKgf <= fPressMax);   // 压力入窗（当拍量）
_bOver  := fPressKgf > fPressMax;                                    // 超压（当拍量，R146 方向独立检出）
_bNonFin := (fPressKgf <> fPressKgf) OR (fContOhm <> fContOhm)
         OR ((fPressKgf - fPressKgf) <> (fPressKgf - fPressKgf))
         OR ((fContOhm - fContOhm) <> (fContOhm - fContOhm));        // 非有限防御（NaN 自反 + 差值自减）
rtStart(CLK := bStart);                                              // 启动沿（每拍必调）
rtReset(CLK := bReset);                                              // 复位沿（每拍必调）
tonDockTo(IN := (_eState = E_DL_OpdState.eDock), PT := tDockTo);     // 入窗超时（单相独占）
tonHold(IN := (_eState = E_DL_OpdState.ePress), PT := tPressHold);   // 保压窗（单相独占）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
bDocking := FALSE;                  // 对接标志缺省 FALSE
bDone := FALSE;                     // 完成标志缺省 FALSE
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（当拍量判据） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF
IF (fPressMax <= fPressMin) OR (fContMax <= 0.0)
   OR (TIME_TO_DINT(tDockTo) <= 0) OR (TIME_TO_DINT(tPressHold) <= 0) THEN
    _uFault := 16#0005_0370;        // 故障级：组态非法
    _bFault := TRUE;                // 故障标志与码位配对（R45）
END_IF

(* —— 段 3：压力窗判据锁存（判据当拍量；超时/超压归并声明见码表） —— *)
IF (NOT _bFault) AND tonDockTo.Q THEN
    _uFault := 16#0005_0371;        // 故障级：入窗超时
    _bFault := TRUE;
END_IF
IF (NOT _bFault) AND (_eState = E_DL_OpdState.ePress) AND _bOver THEN
    _uFault := 16#0005_0371;        // 故障级：保压超压（归并 0371，同域声明）
    _bFault := TRUE;
END_IF

(* —— 段 4：电阻超限 / 非有限锁存（判据当拍量） —— *)
IF (NOT _bFault) AND (_eState = E_DL_OpdState.eJudge) AND (fContOhm > fContMax) THEN
    _uFault := 16#0005_0372;        // 故障级：接触电阻超限
    _bFault := TRUE;
END_IF
IF _bNonFin THEN
    _uFault := 16#0005_0372;        // 故障级：输入非有限（防御兜底归并 0372）
    _bFault := TRUE;
END_IF

(* —— 段 5：故障解除式（R240 落地，逐 BOOL 标注）：
     rtReset.Q = 当拍量；_bInBand = 当拍量；均不含锁存量（_bFault/_uFault），
     解除边真实可达（对接完成回空闲后复位沿可到达）。 —— *)
IF rtReset.Q AND (NOT _bNonFin) THEN
    _bFault := FALSE;               // 清故障锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，仅本当拍量解除沿可清）
    IF _eState = E_DL_OpdState.eFault THEN
        _eState := E_DL_OpdState.eIdle;     // 故障相迁出：回空闲
    END_IF
END_IF

(* —— 段 6：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_OpdState.eIdle:
    IF rtStart.Q AND (NOT _bFault) THEN
        _uInfo := 16#0005_0498;             // 信息级：对接开始沿
        _eState := E_DL_OpdState.eDock;     // 进对接相
    END_IF

E_DL_OpdState.eDock:
    bDocking := TRUE;                       // 对接标志（相电平）
    IF _bInBand THEN
        _uInfo := 16#0005_0499;             // 信息级：压力入窗沿
        _eState := E_DL_OpdState.ePress;    // 进保压相
    END_IF
    (* 超时迁出在段 3 承载 *)

E_DL_OpdState.ePress:
    bDocking := TRUE;                       // 对接标志（相电平）
    IF tonHold.Q THEN
        _eState := E_DL_OpdState.eJudge;    // 保压完成：进判定相
    END_IF
    (* 超压迁出在段 3 承载 *)

E_DL_OpdState.eJudge:
    IF fContOhm <= fContMax THEN
        _uInfo := 16#0005_049A;             // 信息级：校验通过沿
        _eState := E_DL_OpdState.eDone;     // 进完成相
    END_IF
    (* 电阻超限迁出在段 4 承载 *)

E_DL_OpdState.eDone:
    bDone := TRUE;                          // 完成标志（相电平）
    IF NOT bStart THEN                      // 启动指令撤销：完成标志随相清除
        _eState := E_DL_OpdState.eIdle;     // 回空闲
    END_IF

E_DL_OpdState.eFault:
    ;                                       // 故障相：等复位沿（段 5 承载迁出）

ELSE
    _uFault := 16#0005_0370;                // 故障级：非法相位兜底（归并组态码，码表声明）
    _bFault := TRUE;
    _eState := E_DL_OpdState.eFault;        // 强制回故障相

END_CASE

(* —— 段 7：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    bDocking := FALSE;              // 故障相对接出口强制 FALSE（安全侧）
    bDone := FALSE;                 // 故障相完成出口强制 FALSE（安全侧）
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bFault := _bFault;                  // 锁存位出口
bError := _bFault;                  // 故障标志与锁存位同源
eState := _eState;                  // 状态出口单点映射

END_FUNCTION_BLOCK
