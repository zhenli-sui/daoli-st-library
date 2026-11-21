(*
  FB_DL_GlassFeederAccum  —  玻璃上料输送积放（多区级联积放协调） / Glass feeder multi-zone accumulation and cascade release coordinator
  分类 Category : DL_Process
  版本 Version  : 1.0.0
  来源 Source   : t2-2-lbp — 玻璃输送/积放族深化
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 四区级联积放：eIdle（积放保持，挡板全抬起）→ eRel（放行序列：
                  自下游区 0 起逐区落挡板放行、等区光电放空、抬板进下一区）
                  → 全区放空回 eIdle；
                  2) 释放相单区超时 tZoneTo → 037D 锁存（R233 单相独占分实例）；
                  3) 积放相背压监视：非释放相全部区占满且输送运行持续 tAccumTo
                  → 037E 满载滞留锁存（归因独立于释放超时）；
                  4) 信息级三码：积放激活 / 区释放沿 / 全区放行完成；
                  5) 解除式全当拍量（R240 落地），逐 BOOL 标注见段 4。
  边界 Boundary : ① 组态闸：任一时间 <= 0 → 037C 锁存，ELSE 兜底归并 037C（码表声明）；
                  ② 区索引域 0..3 由常量数组界结构性限定，无越界路径（头注释自证）；
                  ③ 故障相挡板输出全保持抬起（安全侧：不拦料）；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Process 段 0005，窗口 037C~037E / 04A4~04A6）:
    16#0005_037C 故障级：组态非法（任一时间域非法）或相位落 ELSE 兜底（归并声明），锁存至 bReset
    16#0005_037D 故障级：释放相单区放行超时（tZoneTo），锁存至 bReset
    16#0005_037E 故障级：积放相满载滞留超时（tAccumTo），锁存至 bReset
    16#0005_04A4 信息级：放行序列启动沿（进 eRel）
    16#0005_04A5 信息级：单区放行完成沿（区光电放空拍）
    16#0005_04A6 信息级：全区放行完成沿（回 eIdle）
  修订历史 Revision :
    2026-11-19  v1.0.0  R42 首版（批次 1 · 序号 5）
*)

TYPE E_DL_GfaState :
(
    eIdle   := 0,    // 积放保持：挡板抬起拦料 / Accum hold, stoppers up
    eRel    := 10,   // 放行：逐区落板放空 / Release, zone-by-zone pass
    eFault  := 90    // 故障：超时锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_GlassFeederAccum
VAR_INPUT
    a_bZonePE    : ARRAY[0..3] OF BOOL;  // 4 区光电，TRUE = 区内有料 [-] / Zone photoeyes, TRUE = occupied
    bConvRun     : BOOL := FALSE;        // 输送运行反馈（当拍量）[-] / Conveyor running feedback
    bRelCmd      : BOOL := FALSE;        // 放行指令，上升沿启动释放序列 [-] / Release command edge
    tZoneTo      : TIME := T#8S;         // 单区放行超时 [ms]，域 > 0 / Per-zone release timeout
    tAccumTo     : TIME := T#60S;        // 满载滞留超时 [ms]，域 > 0 / Full-load dwell timeout
    bReset       : BOOL := FALSE;        // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_OUTPUT
    eState       : E_DL_GfaState;     // 状态出口，段尾单点映射 / State outlet
    a_bStopperUp : ARRAY[0..3] OF BOOL;   // 4 区挡板抬起指令，TRUE = 拦料 [-] / Stopper-up commands
    nRelZone     : DINT;              // 当前放行区号 [0..3]，-1 = 非放行相 / Current releasing zone
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonZoneTo    : TON;               // 单区放行超时（单相独占），无条件刷新 / Zone release timeout
    tonAccumTo   : TON;               // 满载滞留超时（电平式），无条件刷新 / Full-load dwell timeout
    rtRelCmd     : R_TRIG;            // 放行指令沿实例，无条件刷新 / Release edge instance
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _eState      : E_DL_GfaState := E_DL_GfaState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _nRelZoneIdx : DINT := 0;         // 放行序列区号游标 [0..3] / Release sequence zone cursor
    _nIdx        : DINT;              // 阵列循环索引 [-] / Array loop index
    _bAllFull    : BOOL;              // 全区占满当拍量 [-] / All-zones-full current-scan flag
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_bAllFull := a_bZonePE[0] AND a_bZonePE[1] AND a_bZonePE[2] AND a_bZonePE[3];
                                        // 全区占满（当拍量，展开式判据）
rtRelCmd(CLK := bRelCmd);               // 放行沿（每拍必调）
rtReset(CLK := bReset);                 // 复位沿（每拍必调）
tonZoneTo(IN := (_eState = E_DL_GfaState.eRel), PT := tZoneTo);
                                        // 单区放行超时（释放相独占，跨相 IN 必断）
tonAccumTo(IN := (_eState = E_DL_GfaState.eIdle) AND bConvRun AND _bAllFull, PT := tAccumTo);
                                        // 满载滞留超时（电平式，任一条件消失自动断 IN）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
nRelZone := -1;                     // 放行区号缺省 -1 = 非放行相
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（当拍量判据） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF
IF (TIME_TO_DINT(tZoneTo) <= 0) OR (TIME_TO_DINT(tAccumTo) <= 0) THEN
    _uFault := 16#0005_037C;        // 故障级：组态非法
    _bFault := TRUE;                // 故障标志与码位配对（R45）
END_IF

(* —— 段 3：释放相超时与满载滞留锁存（判据当拍量/单相独占 TON） —— *)
IF (NOT _bFault) AND tonZoneTo.Q THEN
    _uFault := 16#0005_037D;        // 故障级：单区放行超时
    _bFault := TRUE;
END_IF
IF (NOT _bFault) AND tonAccumTo.Q THEN
    _uFault := 16#0005_037E;        // 故障级：满载滞留超时
    _bFault := TRUE;
END_IF

(* —— 段 4：故障解除式（R240 落地，逐 BOOL 标注）：
     rtReset.Q = 当拍量；NOT bRelCmd = 当拍量；a_bZonePE 各元素 = 当拍量。
     均不含锁存量（_bFault/_uFault），解除边真实可达（料清空 + 指令撤销 + 复位沿）。 —— *)
IF rtReset.Q AND (NOT bRelCmd)
   AND (NOT a_bZonePE[0]) AND (NOT a_bZonePE[1])
   AND (NOT a_bZonePE[2]) AND (NOT a_bZonePE[3]) THEN
    _bFault := FALSE;               // 清故障锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，仅本当拍量解除沿可清）
    IF _eState = E_DL_GfaState.eFault THEN
        _eState := E_DL_GfaState.eIdle;     // 故障相迁出：回积放保持
    END_IF
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_GfaState.eIdle:
    FOR _nIdx := 0 TO 3 DO              // 挡板全抬起（拦料保持）
        a_bStopperUp[_nIdx] := TRUE;    // 抬板指令
    END_FOR
    IF rtRelCmd.Q AND (NOT _bFault) THEN
        _nRelZoneIdx := 0;              // 放行游标自下游区 0 起
        _uInfo := 16#0005_04A4;         // 信息级：放行序列启动沿
        _eState := E_DL_GfaState.eRel;  // 进放行相（自区 0 起）
    END_IF

E_DL_GfaState.eRel:
    nRelZone := _nRelZoneIdx;           // 当前放行区号镜像
    a_bStopperUp[_nRelZoneIdx] := FALSE;    // 落板放行当前区
    IF NOT a_bZonePE[_nRelZoneIdx] THEN // 当前区光电放空（当拍量）
        a_bStopperUp[_nRelZoneIdx] := TRUE;     // 抬板恢复拦截
        _uInfo := 16#0005_04A5;         // 信息级：单区放行完成沿
        _nRelZoneIdx := _nRelZoneIdx + 1;       // 进下一区
        IF _nRelZoneIdx > 3 THEN        // 全区放空（索引域 0..3 上界结构性安全）
            _uInfo := 16#0005_04A6;     // 信息级：全区放行完成沿
            _eState := E_DL_GfaState.eIdle;     // 回积放保持相
        END_IF
    END_IF
    (* 超时迁出在段 3 承载 *)

E_DL_GfaState.eFault:
    FOR _nIdx := 0 TO 3 DO              // 故障相挡板全抬起（安全侧：不拦料）
        a_bStopperUp[_nIdx] := TRUE;    // 抬板指令
    END_FOR

ELSE
    _uFault := 16#0005_037C;            // 故障级：非法相位兜底（归并组态码，码表声明）
    _bFault := TRUE;
    _eState := E_DL_GfaState.eFault;    // 强制回故障相

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    nRelZone := -1;                 // 故障相放行区号恢复非放行哨兵
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
eState := _eState;                  // 状态出口单点映射

END_FUNCTION_BLOCK
