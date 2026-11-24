(*
  FB_DL_PalletGripperSafe  —  码垛夹手区域安全互锁（夹爪压力 + 区域扫描双条件） / Palletizer gripper area safety interlock: grip pressure plus zone scan dual condition
  分类 Category : DL_Process
  版本 Version  : 1.0.0
  来源 Source   : t2-7-packml — 包装码垛安全族深化
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 夹持许可双条件：bGripAllow := bZoneClear（区域扫描无人，
                  当拍量）AND (fGripPressBar >= fPressMin)（夹爪压力达下限）；
                  许可沿发 04BD；互锁通过沿（双条件同时成立）发 04BC；
                  2) 区域违约诊断：bGripCmd 有效而区域非清空持续 tZoneWin
                  → 0395 违约锁存（互锁失效归因唯一，安全级立即切断 bClampOn）；
                  3) 失压诊断：夹紧输出 ON 期压力跌破下限 → 0394 失压锁存
                  （R146 方向独立：只判低压方向，超压不判）；
                  4) 故障级：0394 失压 / 0395 区域违约 / 0396 组态非法 + ELSE
                  兜底归并；信息级三码：互锁通过 / 夹持许可 / 互锁切断；
                  5) 解除式全当拍量（R240 落地），逐 BOOL 标注见段 4。
  边界 Boundary : ① 组态闸：fPressMin <= 0 或 tZoneWin <= 0 → 0396 锁存；
                  ② 安全侧原则：任一故障锁存期 bClampOn 强制 FALSE（松开）；
                  ③ 互锁切断沿在故障锁存拍单发（信息级 04BE）；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Process 段 0005，窗口 0394~0396 / 04BC~04BE）:
    16#0005_0394 故障级：夹持失压锁存（夹紧期压力跌破 fPressMin），锁存至 bReset
    16#0005_0395 故障级：区域违约锁存（夹持命令期区域非清空持续 tZoneWin），锁存至 bReset
    16#0005_0396 故障级：组态非法（压力下限/区域窗域非法）或相位落 ELSE 兜底（归并声明），锁存至 bReset
    16#0005_04BC 信息级：互锁通过沿（双条件同时成立首拍）
    16#0005_04BD 信息级：夹持许可沿（bGripAllow 首次 TRUE）
    16#0005_04BE 信息级：互锁切断沿（故障锁存拍单发）
  修订历史 Revision :
    2026-11-19  v1.0.0  R42 首版（批次 3 · 序号 3）
*)

TYPE E_DL_PgsState :
(
    eIdle   := 0,    // 待命：无夹持命令 / Idle, no grip command
    eGrip   := 10,   // 夹持：双条件承载夹紧 / Grip, dual-condition clamping
    eFault  := 90    // 故障：失压或违约锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_PalletGripperSafe
VAR_INPUT
    fGripPressBar: REAL := 0.0;       // 夹爪压力反馈 [bar]，调用方注入 / Grip pressure feedback
    fPressMin    : REAL := 4.0;       // 夹持压力下限 [bar]，域 > 0 / Grip pressure lower limit
    bZoneClear   : BOOL := FALSE;     // 区域扫描清空（当拍量，TRUE = 无人）[-] / Zone scan clear flag
    bGripCmd     : BOOL := FALSE;     // 夹持命令（电平）[-] / Grip command, level
    tZoneWin     : TIME := T#500MS;   // 区域违约确认窗 [ms]，域 > 0 / Zone violation window
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_OUTPUT
    eState       : E_DL_PgsState;     // 状态出口，段尾单点映射 / State outlet
    bGripAllow   : BOOL;              // 夹持许可出口（双条件）[-] / Grip allow outlet
    bClampOn     : BOOL;              // 夹紧输出（许可相电平）[-] / Clamp output
    bTripMirror  : BOOL;              // 互锁切断镜像 [-] / Interlock trip mirror
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonZoneViol  : TON;               // 区域违约确认窗（电平式），无条件刷新 / Zone violation timer
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _eState      : E_DL_PgsState := E_DL_PgsState.eIdle;   // 内部相位，CASE 唯一写入目标 / Internal phase, the only CASE write target
    _bPressOk    : BOOL;              // 压力达下限当拍量 [-] / Pressure-ok current-scan flag
    _bNonFin     : BOOL;              // 压力非有限当拍量 [-] / Non-finite pressure flag
    _bDualOk     : BOOL;              // 双条件成立当拍量 [-] / Dual-condition ok flag
    _bAllowPrev  : BOOL;              // 上拍许可镜像（许可/切断沿判据）/ Previous allow mirror
    _bClampPrev  : BOOL;              // 上拍夹紧输出镜像（失压判据承载量）/ Previous clamp output mirror
    _bTripSent   : BOOL;              // 互锁切断沿单发标志 / Trip one-shot sent flag
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_bPressOk := fGripPressBar >= fPressMin;             // 压力达下限（当拍量，单向低压判）
_bNonFin := (fGripPressBar <> fGripPressBar)
         OR ((fGripPressBar - fGripPressBar) <> (fGripPressBar - fGripPressBar));
                                        // 非有限防御（NaN 自反 + 差值自减）
_bDualOk := _bPressOk AND bZoneClear AND (NOT _bNonFin);     // 双条件（当拍量）
rtReset(CLK := bReset);                 // 复位沿（每拍必调）
tonZoneViol(IN := bGripCmd AND (NOT bZoneClear), PT := tZoneWin);
                                        // 区域违约窗（电平式，区域恢复自动断 IN）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
bGripAllow := FALSE;                // 许可出口缺省 FALSE（安全侧）
bClampOn := FALSE;                  // 夹紧输出缺省 FALSE（安全侧）
bTripMirror := FALSE;               // 切断镜像缺省 FALSE
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（判据当拍量） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF
IF (fPressMin <= 0.0) OR (TIME_TO_DINT(tZoneWin) <= 0) THEN
    _uFault := 16#0005_0396;        // 故障级：组态非法
    _bFault := TRUE;                // 故障标志与码位配对（R45）
END_IF

(* —— 段 3：失压与区域违约锁存（判据当拍量/电平式窗） —— *)
IF (NOT _bFault) AND (_eState = E_DL_PgsState.eGrip) AND _bClampPrev THEN
    IF (NOT _bPressOk) OR _bNonFin THEN
        _uFault := 16#0005_0394;    // 故障级：夹持失压（含非有限并入防御）
        _bFault := TRUE;
    END_IF
END_IF
IF (NOT _bFault) AND tonZoneViol.Q THEN
    _uFault := 16#0005_0395;        // 故障级：区域违约锁存
    _bFault := TRUE;
END_IF

(* —— 段 4：故障解除式（R240 落地，逐 BOOL 标注）：
     rtReset.Q = 当拍量；NOT bGripCmd = 当拍量；bZoneClear = 当拍量；_bPressOk = 当拍量。
     均不含锁存量（_bFault/_uFault），解除边真实可达（撤命令 + 区域清空 + 压力恢复 + 复位沿）。 —— *)
IF rtReset.Q AND (NOT bGripCmd) AND bZoneClear AND _bPressOk AND (NOT _bNonFin) THEN
    _bFault := FALSE;               // 清故障锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，仅本当拍量解除沿可清）
    IF _eState = E_DL_PgsState.eFault THEN
        _eState := E_DL_PgsState.eIdle;     // 故障相迁出：回待命
    END_IF
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_PgsState.eIdle:
    IF bGripCmd AND _bDualOk AND (NOT _bFault) THEN
        _eState := E_DL_PgsState.eGrip;     // 双条件成立：进夹持相
    END_IF

E_DL_PgsState.eGrip:
    bGripAllow := _bDualOk;         // 许可出口（当拍量直出）
    bClampOn := _bDualOk;           // 夹紧输出（许可承载，失压拍自动断）
    IF bGripAllow THEN
        _uInfo := 16#0005_04BD;     // 信息级：夹持许可沿（电平重发，信息级允许）
    END_IF
    IF _bDualOk AND (NOT _bAllowPrev) THEN
        _uInfo := 16#0005_04BC;     // 信息级：互锁通过沿（覆盖许可沿，后到优先声明）
    END_IF
    IF (NOT bGripCmd) OR (NOT _bDualOk) THEN
        _eState := E_DL_PgsState.eIdle;     // 命令撤销或条件失：回待命相
    END_IF
    (* 失压/违约迁出在段 3 承载 *)

E_DL_PgsState.eFault:
    ;                               // 故障相：夹紧强制断，等解除沿（段 4 承载迁出）

ELSE
    _uFault := 16#0005_0396;        // 故障级：非法相位兜底（归并组态码，码表声明）
    _bFault := TRUE;
    _eState := E_DL_PgsState.eFault;    // 强制回故障相

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    bClampOn := FALSE;              // 故障相夹紧强制 FALSE（安全侧，②声明）
    bGripAllow := FALSE;            // 故障相许可强制 FALSE（安全侧）
    bTripMirror := TRUE;            // 切断镜像（故障期电平）
    IF NOT _bTripSent THEN
        _uInfo := 16#0005_04BE;     // 信息级：互锁切断沿（锁存拍单发）
        _bTripSent := TRUE;         // 单发标志
    END_IF
ELSE
    nErrId := _uInfo;               // 信息码
    bTripMirror := FALSE;           // 非故障期切断镜像 FALSE
    _bTripSent := FALSE;            // 单发标志复位
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
eState := _eState;                  // 状态出口单点映射
_bAllowPrev := bGripAllow;          // 许可沿判据快照（段末统一写）
_bClampPrev := bClampOn;            // 夹紧输出快照（下拍失压判据承载，段末统一写）

END_FUNCTION_BLOCK
