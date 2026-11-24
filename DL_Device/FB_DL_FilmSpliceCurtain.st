(*
  FB_DL_FilmSpliceCurtain  —  接膜工位光幕屏蔽序列（2 传感器模式屏蔽时序） / Film-splice station light-curtain muting sequence with two-sensor pattern
  分类 Category : DL_Device
  版本 Version  : 1.0.0
  来源 Source   : t2-8-isa182 — 安全屏蔽族深化（与 I_DL_SafetyDoor 单门接口分工：本件为光幕屏蔽时序件）
  溯源 Origin   : clean-room 实现，双传感器屏蔽模式为 ISA182 惯例公开借鉴，未复制任何源码行
  功能 Function : 1) 三相屏蔽时序：eIdle → eSeq（首传感器沿后等第二传感器沿，
                  tSeqTo 超时判）→ eMute（双传感器齐备，屏蔽承载 bMuteEn，
                  物料通过双传感器回落回 eIdle）；
                  2) 屏蔽期内光幕遮断被容忍（不置故障，屏蔽语义承载）；
                  屏蔽相滞留超 tMuteMax → 0523 锁存并退出屏蔽（安全侧）；
                  3) 非法模式：eSeq 相单传感器悬置 tSeqTo → 0522 锁存
                  （R190 归因唯一：非法模式走 0522，滞留超窗走 0523）；
                  4) 故障级：0522 屏蔽序列非法模式锁存 / 0523 屏蔽相滞留超窗
                  锁存 / 0524 组态非法（窗域）+ ELSE 兜底归并；
                  5) 信息级三码：屏蔽激活 / 屏蔽解除 / 非法模式检出（单拍沿）；
                  6) 解除式全当拍量（R240 落地），逐 BOOL 标注见段 4。
  边界 Boundary : ① 分段理由（R192）：段 0003 故障带 03A0~03FF 于 R42 用尽，
                  启用 05xx 副带续编，避开 0590~0599 判错位段；
                  ② 组态闸：tSeqTo <= 0 或 tMuteMax <= 0 → 0524 锁存；
                  ③ 安全侧：故障锁存期 bMuteEn 强制 FALSE（光幕恢复全防护）；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Device 段 0003，窗口 0522~0524 / 0428~042A）:
    16#0003_0522 故障级：屏蔽序列非法模式锁存（单传感器悬置 tSeqTo），锁存至 bReset
    16#0003_0523 故障级：屏蔽相滞留超窗锁存（tMuteMax），锁存至 bReset
    16#0003_0524 故障级：组态非法（任一窗域非法）或相位落 ELSE 兜底（归并声明），锁存至 bReset
    16#0003_0428 信息级：屏蔽激活沿（进 eMute）
    16#0003_0429 信息级：屏蔽解除沿（回 eIdle）
    16#0003_042A 信息级：非法模式检出沿（0522 锁存拍）
  修订历史 Revision :
    2026-11-19  v1.0.0  R42 首版（批次 4 · 序号 3）
*)

TYPE E_DL_FscState :
(
    eIdle  := 0,     // 全防护：屏蔽未承载 / Full protection, muting off
    eSeq   := 10,    // 序列：等第二传感器沿 / Sequence, waiting second sensor
    eMute  := 20,    // 屏蔽：双传感器承载 / Muting, dual-sensor engaged
    eFault := 90     // 故障：非法模式或滞留锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_FilmSpliceCurtain
VAR_INPUT
    bMuteA       : BOOL := FALSE;     // 屏蔽传感器 A（当拍量）[-] / Muting sensor A, current-scan
    bMuteB       : BOOL := FALSE;     // 屏蔽传感器 B（当拍量）[-] / Muting sensor B, current-scan
    bCurtainBrk  : BOOL := FALSE;     // 光幕遮断（当拍量，TRUE = 遮断）[-] / Light curtain broken flag
    tSeqTo       : TIME := T#2S;      // 序列第二传感器等待窗 [ms]，域 > 0 / Sequence second-sensor window
    tMuteMax     : TIME := T#10S;     // 屏蔽最大承载窗 [ms]，域 > 0 / Maximum muting window
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_OUTPUT
    eState       : E_DL_FscState;     // 状态出口，段尾单点映射 / State outlet
    bMuteEn      : BOOL;              // 屏蔽承载输出（eMute 相电平）[-] / Muting engage output
    bCurtainSafe : BOOL;              // 光幕安全出口（遮断且非屏蔽 → FALSE）[-] / Curtain safety outlet
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonSeqTo     : TON;               // 序列等待窗（单相独占），无条件刷新 / Sequence window timer
    tonMuteMax   : TON;               // 屏蔽承载窗（单相独占），无条件刷新 / Muting window timer
    rtMuteA      : R_TRIG;            // 传感器 A 沿实例，无条件刷新 / Sensor A edge instance
    rtMuteB      : R_TRIG;            // 传感器 B 沿实例，无条件刷新 / Sensor B edge instance
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _eState      : E_DL_FscState := E_DL_FscState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
rtMuteA(CLK := bMuteA);              // 传感器 A 沿（每拍必调）
rtMuteB(CLK := bMuteB);              // 传感器 B 沿（每拍必调）
rtReset(CLK := bReset);              // 复位沿（每拍必调）
tonSeqTo(IN := (_eState = E_DL_FscState.eSeq), PT := tSeqTo);        // 序列窗（单相独占）
tonMuteMax(IN := (_eState = E_DL_FscState.eMute), PT := tMuteMax);   // 屏蔽窗（单相独占）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
bMuteEn := FALSE;                   // 屏蔽输出缺省 FALSE（安全侧）
bCurtainSafe := FALSE;              // 光幕安全出口缺省 FALSE（安全侧）
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（判据当拍量） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF
IF (TIME_TO_DINT(tSeqTo) <= 0) OR (TIME_TO_DINT(tMuteMax) <= 0) THEN
    _uFault := 16#0003_0524;        // 故障级：组态非法
    _bFault := TRUE;                // 故障标志与码位配对（R45）
END_IF

(* —— 段 3：非法模式与滞留超窗锁存（判据当拍量/单相独占 TON） —— *)
IF (NOT _bFault) AND tonSeqTo.Q THEN
    _uFault := 16#0003_0522;        // 故障级：非法模式（单传感器悬置）
    _bFault := TRUE;
    _uInfo := 16#0003_042A;         // 信息级：非法模式检出沿
END_IF
IF (NOT _bFault) AND tonMuteMax.Q THEN
    _uFault := 16#0003_0523;        // 故障级：屏蔽相滞留超窗
    _bFault := TRUE;
END_IF

(* —— 段 4：故障解除式（R240 落地，逐 BOOL 标注）：
     rtReset.Q = 当拍量；NOT bMuteA = 当拍量；NOT bMuteB = 当拍量；
     NOT bCurtainBrk = 当拍量。均不含锁存量（_bFault/_uFault），
     解除边真实可达（双传感器回落 + 光幕恢复 + 复位沿）。 —— *)
IF rtReset.Q AND (NOT bMuteA) AND (NOT bMuteB) AND (NOT bCurtainBrk) THEN
    _bFault := FALSE;               // 清故障锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，仅本当拍量解除沿可清）
    IF _eState = E_DL_FscState.eFault THEN
        _eState := E_DL_FscState.eIdle;     // 故障相迁出：回全防护
    END_IF
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_FscState.eIdle:
    IF rtMuteA.Q OR rtMuteB.Q THEN  // 任一传感器沿：进序列相
        _eState := E_DL_FscState.eSeq;
    END_IF

E_DL_FscState.eSeq:
    IF (rtMuteA.Q AND bMuteB) OR (rtMuteB.Q AND bMuteA) THEN
        _uInfo := 16#0003_0428;     // 信息级：屏蔽激活沿（第二传感器齐备拍）
        _eState := E_DL_FscState.eMute;     // 进屏蔽相
    END_IF
    (* 非法模式迁出在段 3 承载 *)

E_DL_FscState.eMute:
    IF (NOT bMuteA) AND (NOT bMuteB) THEN   // 双传感器回落：物料通过
        _uInfo := 16#0003_0429;     // 信息级：屏蔽解除沿
        _eState := E_DL_FscState.eIdle;     // 回全防护相
    END_IF
    (* 滞留超窗迁出在段 3 承载 *)

E_DL_FscState.eFault:
    ;                               // 故障相：屏蔽强制断，等解除沿（段 4 承载迁出）

ELSE
    _uFault := 16#0003_0524;        // 故障级：非法相位兜底（归并组态码，码表声明）
    _bFault := TRUE;
    _eState := E_DL_FscState.eFault;    // 强制回故障相

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _eState = E_DL_FscState.eMute THEN
    bMuteEn := TRUE;                // 屏蔽承载（相电平）
    bCurtainSafe := TRUE;           // 屏蔽期光幕遮断被容忍（安全出口保持 TRUE）
ELSIF bCurtainBrk THEN
    bCurtainSafe := FALSE;          // 非屏蔽期遮断：安全出口 FALSE（全防护语义）
ELSE
    bCurtainSafe := TRUE;           // 非屏蔽期未遮断：安全出口 TRUE
END_IF
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    bMuteEn := FALSE;               // 故障相屏蔽强制 FALSE（安全侧，③声明）
    bCurtainSafe := NOT bCurtainBrk;    // 故障相光幕语义保持全防护（遮断即 FALSE）
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
eState := _eState;                  // 状态出口单点映射

END_FUNCTION_BLOCK
