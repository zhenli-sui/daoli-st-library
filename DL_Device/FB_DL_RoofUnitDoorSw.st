(*
  FB_DL_RoofUnitDoorSw  —  屋顶机检修门-风机联锁（重启抑制轻量组态） / Rooftop unit access-door fan interlock with restart inhibition
  分类 Category : DL_Device
  版本 Version  : 1.0.0
  来源 Source   : t1-2-oscat-building — 楼宇机组联锁族零检索深化
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 硬联锁：门开（bDoorOpen 当拍量）期 bFanPermit := FALSE
                  （风机许可切断，切断沿发 0425），风机命令期违约持续 tViolWin
                  → 051F 锁存；许可恢复仅在门关确认 + 复位沿承载；
                  2) 重启抑制：门关确认（0426 沿）后 tRestartInhib 内风机命令
                  有效 → 0520 抑制期违约锁存（轻量组态防骤启）；
                  抑制窗满发 0427 结束沿；
                  3) 故障级：051F 门开期风机运行违约锁存 / 0520 抑制期启动违约
                  锁存（R190 归因唯一：两违约成因独立码位）/ 0521 组态非法
                  （窗域）+ ELSE 兜底归并；
                  4) 信息级三码：联锁切断 / 门关确认 / 抑制结束（单拍沿）；
                  5) 解除式全当拍量（R240 落地），逐 BOOL 标注见段 4。
  边界 Boundary : ① 分段理由（R192）：段 0003 故障带 03A0~03FF 于 R42 用尽，
                  启用 05xx 副带续编，避开 0590~0599 判错位段；
                  ② 组态闸：tViolWin <= 0 或 tRestartInhib <= 0 → 0521 锁存；
                  ③ 安全侧：任一锁存期 bFanPermit 强制 FALSE；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Device 段 0003，窗口 051F~0521 / 0425~0427）:
    16#0003_051F 故障级：门开期风机运行违约锁存（持续 tViolWin），锁存至 bReset
    16#0003_0520 故障级：重启抑制期内启动违约锁存，锁存至 bReset
    16#0003_0521 故障级：组态非法（任一窗域非法）或相位落 ELSE 兜底（归并声明），锁存至 bReset
    16#0003_0425 信息级：联锁切断沿（门开首拍）
    16#0003_0426 信息级：门关确认沿（bDoorOpen 下降沿）
    16#0003_0427 信息级：重启抑制结束沿（抑制窗满拍）
  修订历史 Revision :
    2026-11-19  v1.0.0  R42 首版（批次 4 · 序号 2）
*)

TYPE E_DL_RudState :
(
    eIdle    := 0,   // 正常：门关许可承载 / Normal, door closed permit
    eInhibit := 10,  // 抑制：门关后重启抑制窗 / Inhibit, restart inhibition window
    eFault   := 90   // 故障：违约锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_RoofUnitDoorSw
VAR_INPUT
    bDoorOpen    : BOOL := FALSE;     // 检修门开反馈（当拍量）[-] / Access door open feedback
    bFanCmd      : BOOL := FALSE;     // 风机命令（电平）[-] / Fan command, level
    bFanRun      : BOOL := FALSE;     // 风机运行反馈（当拍量）[-] / Fan running feedback
    tViolWin     : TIME := T#1S;      // 门开期违约确认窗 [ms]，域 > 0 / Door-open violation window
    tRestartInhib: TIME := T#30S;     // 门关后重启抑制窗 [ms]，域 > 0 / Restart inhibition window
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_OUTPUT
    eState       : E_DL_RudState;     // 状态出口，段尾单点映射 / State outlet
    bFanPermit   : BOOL;              // 风机许可出口 [-] / Fan permit outlet
    bInhibitOn   : BOOL;              // 抑制窗活动镜像 [-] / Inhibition active mirror
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonViol      : TON;               // 门开期违约确认窗（电平式），无条件刷新 / Door-open violation timer
    tonInhibit   : TON;               // 重启抑制窗（R188 自复位错峰窗），无条件刷新 / Restart inhibition timer
    rtDoorClosed : F_TRIG;            // 门关沿实例（bDoorOpen 下降沿），无条件刷新 / Door-closed edge instance
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _bDoorClosed : BOOL;              // 门关当拍量 [-] / Door-closed current-scan flag
    _bInhibit    : BOOL;              // 抑制活动当拍量（tonInhibit 计时中非 Q）[-] / Inhibition active flag
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_bDoorClosed := NOT bDoorOpen;      // 门关判据（当拍量）
rtDoorClosed(CLK := bDoorOpen);      // 门关下降沿（每拍必调）
rtReset(CLK := bReset);              // 复位沿（每拍必调）
tonViol(IN := bDoorOpen AND (bFanCmd OR bFanRun), PT := tViolWin);
                                     // 门开期违约窗（电平式，违约消失自动断 IN）
tonInhibit(IN := _bDoorClosed AND (NOT tonInhibit.Q), PT := tRestartInhib);
                                     // 重启抑制窗（R188：IN 含自身 Q 取反自复位；
                                     // 门关电平启动，窗满单拍 Q 后自动重启空转）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
bFanPermit := FALSE;                // 风机许可缺省 FALSE（安全侧）
bInhibitOn := FALSE;                // 抑制镜像缺省 FALSE
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（判据当拍量） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF
IF (TIME_TO_DINT(tViolWin) <= 0) OR (TIME_TO_DINT(tRestartInhib) <= 0) THEN
    _uFault := 16#0003_0521;        // 故障级：组态非法
    _bFault := TRUE;                // 故障标志与码位配对（R45）
END_IF

(* —— 段 3：门关沿承载（抑制窗启动与门关确认沿） —— *)
IF rtDoorClosed.Q THEN              // 门关沿（当拍量）
    _uInfo := 16#0003_0426;         // 信息级：门关确认沿（抑制窗由段 0 电平承载启动）
END_IF
_bInhibit := (NOT tonInhibit.Q) AND (_bDoorClosed);          // 抑制活动（当拍量：门关且窗计时中）

(* —— 段 4：违约锁存（判据当拍量/电平式窗） —— *)
IF (NOT _bFault) AND tonViol.Q THEN
    _uFault := 16#0003_051F;        // 故障级：门开期风机运行违约
    _bFault := TRUE;
END_IF
IF (NOT _bFault) AND _bInhibit AND bFanCmd THEN
    _uFault := 16#0003_0520;        // 故障级：抑制期启动违约
    _bFault := TRUE;
END_IF

(* —— 段 5：故障解除式（R240 落地，逐 BOOL 标注）：
     rtReset.Q = 当拍量；_bDoorClosed = 当拍量；NOT bFanCmd = 当拍量；NOT bFanRun = 当拍量。
     均不含锁存量（_bFault/_uFault），解除边真实可达（门关 + 撤命令 + 复位沿）。 —— *)
IF rtReset.Q AND _bDoorClosed AND (NOT bFanCmd) AND (NOT bFanRun) THEN
    _bFault := FALSE;               // 清故障锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，仅本当拍量解除沿可清）
    IF _eState = E_DL_RudState.eFault THEN
        _eState := E_DL_RudState.eIdle;     // 故障相迁出：回正常
    END_IF
END_IF

(* —— 段 6：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_RudState.eIdle:
    IF bDoorOpen THEN
        _uInfo := 16#0003_0425;         // 信息级：联锁切断沿
        _eState := E_DL_RudState.eInhibit;      // 门开：进抑制相（许可已断）
    END_IF

E_DL_RudState.eInhibit:
    bInhibitOn := _bInhibit;            // 抑制镜像（电平）
    IF tonInhibit.Q THEN                // 抑制窗满（事件量）
        IF _bDoorClosed THEN            // 出口 1：窗满且门关
            _uInfo := 16#0003_0427;     // 信息级：抑制结束沿
            _eState := E_DL_RudState.eIdle;     // 回正常相
        END_IF
        (* 出口 2：门仍开则许可保持 FALSE，故障相违约由段 4 承载（R98 双出口：
           事件满窗 + 前置门关恢复；门未关时许可持续切断，非无报错死路） *)
    END_IF

E_DL_RudState.eFault:
    ;                                   // 故障相：许可强制断，等解除沿（段 5 承载迁出）

ELSE
    _uFault := 16#0003_0521;            // 故障级：非法相位兜底（归并组态码，码表声明）
    _bFault := TRUE;
    _eState := E_DL_RudState.eFault;    // 强制回故障相

END_CASE

(* —— 段 7：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    bFanPermit := FALSE;            // 故障相许可强制 FALSE（安全侧，③声明）
    bInhibitOn := FALSE;            // 故障相抑制镜像强制 FALSE
ELSE
    nErrId := _uInfo;               // 信息码
    bFanPermit := _bDoorClosed AND (NOT _bInhibit) AND (NOT bDoorOpen);
                                        // 许可出口（门关 + 非抑制期，当拍量承载）
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
eState := _eState;                  // 状态出口单点映射

END_FUNCTION_BLOCK
