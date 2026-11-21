(*
  FB_DL_RobotArmVibrationWatch  —  晶圆传送机械手振动特征监视（高通分量 + 特征窗分级） / Wafer-handling robot arm vibration watch: high-pass component with feature-window grading
  分类 Category : DL_Device
  版本 Version  : 1.0.0
  来源 Source   : t2-6-rockwell-aoi — 设备监视族深化
  溯源 Origin   : clean-room 实现，一阶高通/指数特征功率为公开信号处理惯例，未复制任何源码行
  功能 Function : 1) 高通分量：一阶低通 _fLpf 递推后取差 fHighPass :=
                  fAccRaw - _fLpf（高通近似，滤波系数域 [0,1)）；
                  2) 特征功率（平方量纲）：指数滑动 _fFeatSq 递推，判据全部用
                  平方域比较（阈值平方以乘法承载，不调用 SQRT/EXPT 内建，
                  R140 委托优先——本件非内核属主）；
                  3) 特征窗分级：特征功率 > fThrWarnSq（当拍）→ 信息级 0422
                  警告级沿；> fThrFaultSq 持续 tFeatWin → 051C 故障级锁存
                  （R190 归因唯一：警告不锁存、故障持续窗锁存）；
                  4) 故障级：051C 振动超故障阈持续锁存 / 051D 组态非法（阈值
                  颠倒、系数域、时间域）+ ELSE 兜底归并 / 051E 输入非有限锁存；
                  5) 信息级三码：警告级沿 / 恢复沿 / 特征窗激活沿；
                  6) 解除式全当拍量（R240 落地），逐 BOOL 标注见段 4。
  边界 Boundary : ① 分段理由（R192）：段 0003 故障带 03A0~03FF 于 R42 用尽，
                  启用 05xx 副带续编，避开 0590~0599 判错位段；
                  ② 组态闸：fThrFaultSq <= fThrWarnSq、fAlphaLpf 越域 [0,1)、
                  tFeatWin <= 0 → 051D 锁存，监视停发；
                  ③ 非有限判据自反 + 差值自减双判（R79）；滤波递推故障期冻结；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Device 段 0003，窗口 051C~051E / 0422~0424）:
    16#0003_051C 故障级：振动特征功率超故障阈持续锁存（tFeatWin），锁存至 bReset
    16#0003_051D 故障级：组态非法（阈值颠倒/系数越域/窗域非法）或相位落 ELSE 兜底（归并声明），锁存至 bReset
    16#0003_051E 故障级：加速度输入非有限锁存（滤波冻结），锁存至 bReset
    16#0003_0422 信息级：警告级沿（特征功率越警告阈首拍）
    16#0003_0423 信息级：恢复沿（警告级退回正常拍）
    16#0003_0424 信息级：特征窗激活沿（监视使能进 eWatch）
  修订历史 Revision :
    2026-11-19  v1.0.0  R42 首版（批次 4 · 序号 1，Device 05xx 副带首启用件）
*)

TYPE E_DL_RvwState :
(
    eIdle  := 0,     // 未使能：滤波冻结 / Idle, filter frozen
    eWatch := 10,    // 监视中：特征递推 / Watch, feature recursion
    eFault := 90     // 故障：超阈或组态锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_RobotArmVibrationWatch
VAR_INPUT
    fAccRaw      : REAL := 0.0;       // 加速度原始输入 [g]，调用方注入 / Raw acceleration input
    fAlphaLpf    : REAL := 0.05;      // 低通系数 [-]，域 [0,1) / Low-pass alpha coefficient
    fThrWarnSq   : REAL := 0.01;      // 警告阈（功率平方量纲）[g²]，域 > 0 / Warning threshold squared
    fThrFaultSq  : REAL := 0.04;      // 故障阈（功率平方量纲）[g²]，必须 > 警告阈 / Fault threshold squared
    tFeatWin     : TIME := T#1S;      // 故障阈持续确认窗 [ms]，域 > 0 / Fault threshold sustain window
    bWatchEn     : BOOL := FALSE;     // 监视使能（电平）[-] / Watch enable, level
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_OUTPUT
    eState       : E_DL_RvwState;     // 状态出口，段尾单点映射 / State outlet
    fHighPass    : REAL;              // 高通分量输出 [g] / High-pass component output
    fFeatSq      : REAL;              // 特征功率输出（平方量纲）[g²] / Feature power output squared
    bWarn        : BOOL;              // 警告级标志（越警告阈电平）[-] / Warning-level flag
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonFeatTo    : TON;               // 故障阈持续确认窗（电平式），无条件刷新 / Fault sustain timer
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _fLpf        : REAL;              // 一阶低通状态 [g]（保持量）/ First-order LPF state
    _fHigh       : REAL;              // 高通分量（当拍量）[g] / High-pass component
    _fFeatSq     : REAL;              // 特征功率（指数递推，保持量）[g²] / Feature power recursion
    _bNonFin     : BOOL;              // 输入非有限当拍量 [-] / Non-finite input flag
    _bWarnPrev   : BOOL;              // 上拍警告镜像（警告/恢复沿判据）/ Previous warning mirror
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_bNonFin := (fAccRaw <> fAccRaw)
         OR ((fAccRaw - fAccRaw) <> (fAccRaw - fAccRaw));        // 非有限防御（NaN 自反 + 差值自减）
_fHigh := fAccRaw - _fLpf;                              // 高通分量（当拍量，低通状态差）
_fLpf := _fLpf + fAlphaLpf * (fAccRaw - _fLpf);         // 一阶低通递推（滤波系数域闸后承载）
_fFeatSq := _fFeatSq + (1.0 - fAlphaLpf) * (_fHigh * _fHigh - _fFeatSq);
                                        // 特征功率指数递推（平方量纲，乘法承载）
rtReset(CLK := bReset);                 // 复位沿（每拍必调）
tonFeatTo(IN := (_eState = E_DL_RvwState.eWatch) AND (_fFeatSq > fThrFaultSq), PT := tFeatWin);
                                        // 故障阈持续窗（电平式，越阈消失自动断 IN）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 与滤波状态不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
fHighPass := _fHigh;                // 高通出口（当拍量直出）
fFeatSq := _fFeatSq;                // 特征功率出口（保持量直出）
bWarn := FALSE;                     // 警告标志缺省 FALSE
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（判据当拍量） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF
IF (fThrFaultSq <= fThrWarnSq) OR (fThrWarnSq <= 0.0) OR (fAlphaLpf < 0.0)
   OR (fAlphaLpf >= 1.0) OR (TIME_TO_DINT(tFeatWin) <= 0) THEN
    _uFault := 16#0003_051D;        // 故障级：组态非法
    _bFault := TRUE;                // 故障标志与码位配对（R45）
END_IF
IF _bNonFin THEN
    _fLpf := 0.0;                   // 低通状态清零（安全侧常量，FB32-4）
    _fFeatSq := 0.0;                // 特征功率清零（安全侧常量）
    _uFault := 16#0003_051E;        // 故障级：输入非有限锁存
    _bFault := TRUE;
END_IF

(* —— 段 3：故障阈持续锁存（判据当拍量/电平式窗） —— *)
IF (NOT _bFault) AND tonFeatTo.Q THEN
    _uFault := 16#0003_051C;        // 故障级：振动超故障阈持续
    _bFault := TRUE;
END_IF

(* —— 段 4：故障解除式（R240 落地，逐 BOOL 标注）：
     rtReset.Q = 当拍量；NOT bWatchEn = 当拍量；_fFeatSq <= fThrFaultSq 为保持量，
     解除路径为特征功率自然回落（监视保持承载）+ 撤使能 + 复位沿当拍量组合，可达。 —— *)
IF rtReset.Q AND (NOT bWatchEn) AND (_fFeatSq <= fThrFaultSq) THEN
    _bFault := FALSE;               // 清故障锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，仅本当拍量解除沿可清）
    IF _eState = E_DL_RvwState.eFault THEN
        _eState := E_DL_RvwState.eIdle;     // 故障相迁出：回未使能
    END_IF
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_RvwState.eIdle:
    _fLpf := fAccRaw;               // 未使能：低通状态随输入直通（进相无跳变）
    _fFeatSq := 0.0;                // 特征功率清零
    IF bWatchEn AND (NOT _bFault) THEN
        _uInfo := 16#0003_0424;     // 信息级：特征窗激活沿
        _eState := E_DL_RvwState.eWatch;    // 进监视相
    END_IF

E_DL_RvwState.eWatch:
    bWarn := _fFeatSq > fThrWarnSq;     // 警告级标志（当拍量电平）
    IF bWarn AND (NOT _bWarnPrev) THEN
        _uInfo := 16#0003_0422;     // 信息级：警告级沿
    END_IF
    IF (NOT bWarn) AND _bWarnPrev THEN
        _uInfo := 16#0003_0423;     // 信息级：恢复沿
    END_IF
    IF NOT bWatchEn THEN
        _eState := E_DL_RvwState.eIdle;     // 撤使能：回未使能相
    END_IF
    (* 超阈持续迁出在段 3 承载 *)

E_DL_RvwState.eFault:
    bWarn := FALSE;                 // 故障相警告标志强制 FALSE（安全侧）

ELSE
    _uFault := 16#0003_051D;        // 故障级：非法相位兜底（归并组态码，码表声明）
    _bFault := TRUE;
    _eState := E_DL_RvwState.eFault;    // 强制回故障相

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    bWarn := FALSE;                 // 故障相警告出口强制 FALSE（安全侧）
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
eState := _eState;                  // 状态出口单点映射
_bWarnPrev := bWarn;                // 警告沿判据快照（段末统一写）

END_FUNCTION_BLOCK
