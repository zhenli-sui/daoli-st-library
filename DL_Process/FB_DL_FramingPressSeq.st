(*
  FB_DL_FramingPressSeq  —  装框机压装顺控（涂胶-组框-压合节拍） / Framing press sequence: glue, frame, press cycle
  分类 Category : DL_Process
  版本 Version  : 1.0.0
  来源 Source   : t2-2-lbp — 层压/装框工艺族深化
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 四相顺控：eGlue（涂胶，等 bGlueDone 反馈）→ eFrame（组框定位，
                  等 bFrameDone 反馈）→ ePress（压合，合力窗判据）→ eDone → 回 eIdle；
                  2) 每相独立超时 TON（单相独占，R228-A），任一相超时 → 0374 锁存
                  （相推进超时同因族归并声明于码表）；压合相合力超上限当拍检出
                  → 0375 过载锁存（R146 方向独立：超上限走 0375，未达标走 0374）；
                  3) 信息级三码：序列启动 / 合力入窗 / 序列完成（单拍沿）；
                  4) 配比约束：tPressTo > tFrameTo > tGlueTo（压合节拍最长，
                  头注释按 R100 声明同拍三窗配比）；
                  5) 解除式全当拍量（R240 落地），逐 BOOL 标注见段 4。
  边界 Boundary : ① 组态闸：fForceMax <= fForceMin、任一超时 <= 0、或配比违反
                  （tPressTo <= tFrameTo 或 tFrameTo <= tGlueTo）→ 0373 锁存，
                  顺控全部停发，ELSE 兜底归并 0373（码表声明）；
                  ② 合力非有限 → 并入 0375 防御兜底（归并声明）；
                  ③ 相迁出仅由反馈当拍量承载，无锁存量自指；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Process 段 0005，窗口 0373~0375 / 049B~049D）:
    16#0005_0373 故障级：组态非法（力窗颠倒/超时域/配比违反）或相位落 ELSE 兜底（归并声明），锁存至 bReset
    16#0005_0374 故障级：相推进超时（涂胶/组框/压合任一相独立计时到时，同因族归并声明），锁存至 bReset
    16#0005_0375 故障级：压合力过载超上限或合力非有限（防御兜底归并声明），锁存至 bReset
    16#0005_049B 信息级：压装序列启动沿（进 eGlue）
    16#0005_049C 信息级：压合力入窗沿（ePress 相）
    16#0005_049D 信息级：压装序列完成沿（进 eDone）
  修订历史 Revision :
    2026-11-19  v1.0.0  R42 首版（批次 1 · 序号 2）
*)

TYPE E_DL_FpsState :
(
    eIdle   := 0,    // 空闲：等启动沿 / Idle, waiting start edge
    eGlue   := 10,   // 涂胶：等涂胶完成反馈 / Glue, waiting glue-done feedback
    eFrame  := 20,   // 组框：等定位完成反馈 / Frame, waiting frame-done feedback
    ePress  := 30,   // 压合：合力窗判据 / Press, force band verdict
    eDone   := 40,   // 完成：序列落定 / Done
    eFault  := 90    // 故障：超时或过载锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_FramingPressSeq
VAR_INPUT
    bStart       : BOOL := FALSE;     // 启动指令，上升沿启动序列 [-] / Start command, rising edge
    bGlueDone    : BOOL := FALSE;     // 涂胶完成反馈（当拍量）[-] / Glue-done feedback
    bFrameDone   : BOOL := FALSE;     // 组框定位完成反馈（当拍量）[-] / Frame-done feedback
    fForceKgf    : REAL := 0.0;       // 压合合力反馈 [kgf]，调用方注入 / Press force feedback
    fForceMin    : REAL := 500.0;     // 合力窗下限 [kgf]，域 > 0 / Force band lower limit
    fForceMax    : REAL := 1200.0;    // 合力窗上限 [kgf]，必须 > fForceMin / Force band upper limit
    tGlueTo      : TIME := T#10S;     // 涂胶相超时 [ms]，域 > 0，配比最短 / Glue-phase timeout
    tFrameTo     : TIME := T#15S;     // 组框相超时 [ms]，域 > tGlueTo / Frame-phase timeout
    tPressTo     : TIME := T#20S;     // 压合相超时 [ms]，域 > tFrameTo / Press-phase timeout
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_OUTPUT
    eState       : E_DL_FpsState;     // 状态出口，段尾单点映射 / State outlet
    bRunning     : BOOL;              // 序列进行中标志（工艺相电平）[-] / Sequence running flag
    bDone        : BOOL;              // 序列完成标志（eDone 相电平）[-] / Sequence done flag
    bForceInBand : BOOL;              // 合力入窗实时镜像 [-] / Force-in-band mirror
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonGlueTo    : TON;               // 涂胶相超时（单相独占），无条件刷新 / Glue-phase timeout
    tonFrameTo   : TON;               // 组框相超时（单相独占），无条件刷新 / Frame-phase timeout
    tonPressTo   : TON;               // 压合相超时（单相独占），无条件刷新 / Press-phase timeout
    rtStart      : R_TRIG;            // 启动沿实例，无条件刷新 / Start edge instance
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _eState      : E_DL_FpsState := E_DL_FpsState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _bForceOk    : BOOL;              // 合力入窗当拍量 [-] / Force-in-band current-scan flag
    _bOver       : BOOL;              // 合力超上限当拍量 [-] / Force-over-limit current-scan flag
    _bNonFin     : BOOL;              // 合力非有限当拍量 [-] / Non-finite force current-scan flag
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_bForceOk := (fForceKgf >= fForceMin) AND (fForceKgf <= fForceMax);  // 合力入窗（当拍量）
_bOver   := fForceKgf > fForceMax;                                   // 过载方向独立检出（R146）
_bNonFin := (fForceKgf <> fForceKgf)
         OR ((fForceKgf - fForceKgf) <> (fForceKgf - fForceKgf));    // 非有限防御（NaN 自反 + 差值自减）
rtStart(CLK := bStart);                                              // 启动沿（每拍必调）
rtReset(CLK := bReset);                                              // 复位沿（每拍必调）
tonGlueTo(IN := (_eState = E_DL_FpsState.eGlue), PT := tGlueTo);     // 涂胶相超时（单相独占）
tonFrameTo(IN := (_eState = E_DL_FpsState.eFrame), PT := tFrameTo);  // 组框相超时（单相独占）
tonPressTo(IN := (_eState = E_DL_FpsState.ePress), PT := tPressTo);  // 压合相超时（单相独占）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
bRunning := FALSE;                  // 进行中标志缺省 FALSE
bDone := FALSE;                     // 完成标志缺省 FALSE
bForceInBand := FALSE;              // 入窗镜像缺省 FALSE
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（当拍量判据，含 R100 配比约束） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF
IF (fForceMax <= fForceMin) OR (TIME_TO_DINT(tGlueTo) <= 0)
   OR (TIME_TO_DINT(tFrameTo) <= 0) OR (TIME_TO_DINT(tPressTo) <= 0)
   OR (tPressTo <= tFrameTo) OR (tFrameTo <= tGlueTo) THEN
    _uFault := 16#0005_0373;        // 故障级：组态非法（含配比违反）
    _bFault := TRUE;                // 故障标志与码位配对（R45）
END_IF

(* —— 段 3：相超时与过载锁存（判据当拍量/单相独占 TON） —— *)
IF (NOT _bFault) AND (tonGlueTo.Q OR tonFrameTo.Q OR tonPressTo.Q) THEN
    _uFault := 16#0005_0374;        // 故障级：相推进超时（同因族归并声明）
    _bFault := TRUE;
END_IF
IF (NOT _bFault) AND (_eState = E_DL_FpsState.ePress) AND (_bOver OR _bNonFin) THEN
    _uFault := 16#0005_0375;        // 故障级：压合力过载或非有限（防御兜底归并）
    _bFault := TRUE;
END_IF

(* —— 段 4：故障解除式（R240 落地，逐 BOOL 标注）：
     rtReset.Q = 当拍量；bStart = 当拍量；均不含锁存量（_bFault/_uFault），
     解除边真实可达（启动指令撤销后复位沿可到达）。 —— *)
IF rtReset.Q AND (NOT bStart) THEN
    _bFault := FALSE;               // 清故障锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，仅本当拍量解除沿可清）
    IF _eState = E_DL_FpsState.eFault THEN
        _eState := E_DL_FpsState.eIdle;     // 故障相迁出：回空闲
    END_IF
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_FpsState.eIdle:
    IF rtStart.Q AND (NOT _bFault) THEN
        _uInfo := 16#0005_049B;             // 信息级：序列启动沿
        _eState := E_DL_FpsState.eGlue;     // 进涂胶相
    END_IF

E_DL_FpsState.eGlue:
    bRunning := TRUE;                       // 进行中标志（相电平）
    IF bGlueDone THEN
        _eState := E_DL_FpsState.eFrame;    // 涂胶完成：进组框相
    END_IF
    (* 超时迁出在段 3 承载 *)

E_DL_FpsState.eFrame:
    bRunning := TRUE;                       // 进行中标志（相电平）
    IF bFrameDone THEN
        _eState := E_DL_FpsState.ePress;    // 定位完成：进压合相
    END_IF

E_DL_FpsState.ePress:
    bRunning := TRUE;                       // 进行中标志（相电平）
    bForceInBand := _bForceOk;              // 入窗镜像（相电平）
    IF _bForceOk THEN
        _uInfo := 16#0005_049C;             // 信息级：合力入窗沿
        _eState := E_DL_FpsState.eDone;     // 判据达成：进完成相
    END_IF
    (* 过载迁出在段 3 承载 *)

E_DL_FpsState.eDone:
    bDone := TRUE;                          // 完成标志（相电平）
    _uInfo := 16#0005_049D;                 // 信息级：序列完成（相电平重发，信息级允许）
    IF NOT bStart THEN                      // 启动指令撤销：回空闲
        _eState := E_DL_FpsState.eIdle;
    END_IF

E_DL_FpsState.eFault:
    ;                                       // 故障相：等复位沿（段 4 承载迁出）

ELSE
    _uFault := 16#0005_0373;                // 故障级：非法相位兜底（归并组态码，码表声明）
    _bFault := TRUE;
    _eState := E_DL_FpsState.eFault;        // 强制回故障相

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    bRunning := FALSE;              // 故障相进行中出口强制 FALSE（安全侧）
    bDone := FALSE;                 // 故障相完成出口强制 FALSE（安全侧）
    bForceInBand := FALSE;          // 故障相入窗镜像强制 FALSE（安全侧）
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
eState := _eState;                  // 状态出口单点映射

END_FUNCTION_BLOCK
