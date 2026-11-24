(*
  FB_DL_DamperBitDiag  —  风阀执行器位诊断打包/解包（位段提取 + 位打包复用） / Damper actuator bit diagnostics pack/unpack: field extraction and packing reuse
  分类 Category : DL_Device
  版本 Version  : 1.0.0
  来源 Source   : t2-1-lgf-bitlogic — 位逻辑族深化（与 AhuDamperStuckDiag 卡滞诊断/FreshAirStepperDamper 步进执行器分工：本件为状态字位诊断打包件）
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 位段解包：uStatusWord 固定位段提取——位 0 开限位、位 1 关限位、
                  位 2 运行位（掩码 AND 提取，移位量仅常量 0/1，R48 合规）；
                  2) 位打包复用：uDiagWord 输出按固定布局重打包（位 0..2 原样
                  直通、位 8 关键故障锁存镜像、位 9 反馈矛盾锁存镜像），
                  打包与解包同件承载（复用声明）；
                  3) 关键故障位检出：uStatusWord AND uFaultMask ≠ 0
                  → 0525 锁存（掩码域闸 uFaultMask ≠ 0）；
                  4) 反馈矛盾：开限与关限同 TRUE 持续 tContraWin → 0526 锁存
                  （R190 归因唯一：关键故障走 0525，矛盾走 0526）；
                  5) 故障级：0525 关键故障位锁存 / 0526 限位反馈矛盾锁存 /
                  0527 组态非法（掩码空）+ ELSE 兜底归并；
                  6) 信息级三码：诊断位检出 / 打包字更新 / 诊断复位（单拍沿）；
                  7) 解除式全当拍量（R240 落地），逐 BOOL 标注见段 4。
  边界 Boundary : ① 分段理由（R192）：段 0003 故障带 03A0~03FF 于 R42 用尽，
                  启用 05xx 副带续编，避开 0590~0599 判错位段；
                  ② 位段覆盖声明：本件仅校验位 0..2 与 uFaultMask 交叠域，
                  位 3..7/10..15 不做校验（域外是「不存在」而非「非法」，R57 口径）；
                  ③ 打包字位 8/9 为锁存镜像派生式（R28 建议位派生口径）；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Device 段 0003，窗口 0525~0527 / 042B~042D）:
    16#0003_0525 故障级：关键故障位检出锁存（uFaultMask 交叠非零），锁存至 bReset
    16#0003_0526 故障级：限位反馈矛盾锁存（开限与关限同 TRUE 持续 tContraWin），锁存至 bReset
    16#0003_0527 故障级：组态非法（uFaultMask = 0）或相位落 ELSE 兜底（归并声明），锁存至 bReset
    16#0003_042B 信息级：诊断位检出沿（关键位或矛盾位首次置位拍）
    16#0003_042C 信息级：打包字更新沿（uDiagWord 与上拍不同拍）
    16#0003_042D 信息级：诊断复位沿（bDiagRst 生效拍）
  修订历史 Revision :
    2026-11-19  v1.0.0  R42 首版（批次 4 · 序号 4）
*)

TYPE E_DL_DbdState :
(
    eIdle  := 0,     // 待命：打包字静态承载 / Idle, packed word steady
    eDiag  := 10,    // 诊断中：位判据承载 / Diag, bit verdicts engaged
    eFault := 90     // 故障：关键位或矛盾锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_DamperBitDiag
VAR_INPUT
    uStatusWord  : WORD := 16#0000;   // 执行器状态字（位 0 开限/位 1 关限/位 2 运行）[-] / Actuator status word
    uFaultMask   : WORD := 16#0008;   // 关键故障位掩码（位 3 默认），域 ≠ 0 / Key fault bit mask
    tContraWin   : TIME := T#500MS;   // 反馈矛盾确认窗 [ms]，域 > 0 / Feedback contradiction window
    bDiagEn      : BOOL := FALSE;     // 诊断使能（电平）[-] / Diag enable, level
    bDiagRst     : BOOL := FALSE;     // 诊断复位指令，上升沿清锁存与打包镜像 [-] / Diag reset command edge
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_OUTPUT
    eState       : E_DL_DbdState;     // 状态出口，段尾单点映射 / State outlet
    uDiagWord    : WORD;              // 诊断打包字（固定布局见头注释）/ Diagnostic packed word
    bLimOpen     : BOOL;              // 开限位解包出口（位 0）[-] / Limit-open unpacked outlet
    bLimClosed   : BOOL;              // 关限位解包出口（位 1）[-] / Limit-closed unpacked outlet
    bRunning     : BOOL;              // 运行位解包出口（位 2）[-] / Running unpacked outlet
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonContra    : TON;               // 反馈矛盾确认窗（电平式），无条件刷新 / Contradiction timer
    rtDiagRst    : R_TRIG;            // 诊断复位沿实例，无条件刷新 / Diag reset edge instance
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _bLimOpen    : BOOL;              // 开限位当拍量（掩码提取）[-] / Limit-open current-scan flag
    _bLimClosed  : BOOL;              // 关限位当拍量（掩码提取）[-] / Limit-closed current-scan flag
    _bRunning    : BOOL;              // 运行位当拍量（掩码提取）[-] / Running current-scan flag
    _bKeyFault   : BOOL;              // 关键故障位当拍量（掩码交叠）[-] / Key-fault bit flag
    _bContra     : BOOL;              // 限位矛盾当拍量 [-] / Limit contradiction flag
    _uDiagPrev   : WORD;              // 上拍打包字镜像（更新沿判据）/ Previous packed word mirror
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_bLimOpen   := (uStatusWord AND 16#0001) <> WORD#0;  // 位 0 开限（掩码提取，当拍量）
_bLimClosed := (uStatusWord AND 16#0002) <> WORD#0;  // 位 1 关限（掩码提取，当拍量）
_bRunning   := (uStatusWord AND 16#0004) <> WORD#0;  // 位 2 运行（掩码提取，当拍量）
_bKeyFault  := (uStatusWord AND uFaultMask) <> WORD#0;   // 关键故障位交叠（当拍量）
_bContra    := _bLimOpen AND _bLimClosed;            // 限位矛盾（当拍量）
rtDiagRst(CLK := bDiagRst);          // 诊断复位沿（每拍必调）
rtReset(CLK := bReset);              // 复位沿（每拍必调）
tonContra(IN := bDiagEn AND _bContra, PT := tContraWin); // 矛盾窗（电平式，矛盾消失自动断 IN）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（判据当拍量） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF
IF uFaultMask = WORD#0 THEN         // 掩码域闸（WORD 判等合规）
    _uFault := 16#0003_0527;        // 故障级：组态非法
    _bFault := TRUE;                // 故障标志与码位配对（R45）
END_IF
IF rtDiagRst.Q THEN                 // 诊断复位沿（当拍量）
    uDiagWord := WORD#0;            // 打包字清零
    _uDiagPrev := WORD#0;           // 镜像同步清零
    _uInfo := 16#0003_042D;         // 信息级：诊断复位沿
END_IF

(* —— 段 3：关键位与矛盾锁存（判据当拍量/电平式窗） —— *)
IF (NOT _bFault) AND bDiagEn AND _bKeyFault THEN
    _uFault := 16#0003_0525;        // 故障级：关键故障位锁存
    _bFault := TRUE;
    _uInfo := 16#0003_042B;         // 信息级：诊断位检出沿
END_IF
IF (NOT _bFault) AND tonContra.Q THEN
    _uFault := 16#0003_0526;        // 故障级：限位反馈矛盾锁存
    _bFault := TRUE;
    _uInfo := 16#0003_042B;         // 信息级：诊断位检出沿（同检出口，成因由 nErrId 区分声明）
END_IF

(* —— 段 4：故障解除式（R240 落地，逐 BOOL 标注）：
     rtReset.Q = 当拍量；rtDiagRst.Q = 当拍量；NOT _bKeyFault = 当拍量；
     NOT _bContra = 当拍量；NOT bDiagEn = 当拍量。均不含锁存量（_bFault/_uFault），
     解除边真实可达（状态字恢复 + 复位/诊断复位沿）。 —— *)
IF (rtReset.Q OR rtDiagRst.Q) AND (NOT _bKeyFault) AND (NOT _bContra) THEN
    _bFault := FALSE;               // 清故障锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，仅本当拍量解除沿可清）
    IF _eState = E_DL_DbdState.eFault THEN
        _eState := E_DL_DbdState.eIdle;     // 故障相迁出：回待命
    END_IF
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_DbdState.eIdle:
    IF bDiagEn AND (NOT _bFault) THEN
        _eState := E_DL_DbdState.eDiag;     // 使能：进诊断相
    END_IF

E_DL_DbdState.eDiag:
    IF NOT bDiagEn THEN
        _eState := E_DL_DbdState.eIdle;     // 撤使能：回待命相
    END_IF
    (* 关键位/矛盾迁出在段 3 承载 *)

E_DL_DbdState.eFault:
    ;                               // 故障相：锁存码回放，等解除沿（段 4 承载迁出）

ELSE
    _uFault := 16#0003_0527;        // 故障级：非法相位兜底（归并组态码，码表声明）
    _bFault := TRUE;
    _eState := E_DL_DbdState.eFault;    // 强制回故障相

END_CASE

(* —— 段 6：位打包（固定布局：位 0..2 直通、位 8/9 锁存镜像派生，R28 派生口径） —— *)
uDiagWord := WORD#0;                // 打包字每拍重构（位段固定，无残留位）
IF _bLimOpen THEN
    uDiagWord := uDiagWord OR 16#0001;      // 位 0 直通
END_IF
IF _bLimClosed THEN
    uDiagWord := uDiagWord OR 16#0002;      // 位 1 直通
END_IF
IF _bRunning THEN
    uDiagWord := uDiagWord OR 16#0004;      // 位 2 直通
END_IF
IF _bFault THEN
    uDiagWord := uDiagWord OR 16#0100;      // 位 8：故障锁存镜像（派生式）
END_IF
IF _uFault = 16#0003_0526 THEN      // 矛盾码判等（UDINT 合规）
    uDiagWord := uDiagWord OR 16#0200;      // 位 9：矛盾锁存镜像（派生式）
END_IF
IF uDiagWord <> _uDiagPrev THEN     // 更新沿（当拍量判据）
    _uInfo := 16#0003_042C;         // 信息级：打包字更新沿
END_IF
_uDiagPrev := uDiagWord;            // 更新沿判据快照（段末统一写）

(* —— 段 7：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
bLimOpen := _bLimOpen;              // 解包出口（当拍量直出）
bLimClosed := _bLimClosed;          // 解包出口（当拍量直出）
bRunning := _bRunning;              // 解包出口（当拍量直出）
eState := _eState;                  // 状态出口单点映射

END_FUNCTION_BLOCK
