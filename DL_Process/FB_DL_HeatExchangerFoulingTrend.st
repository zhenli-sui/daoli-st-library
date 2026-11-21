(*
  FB_DL_HeatExchangerFoulingTrend  —  换热器结垢趋势诊断（传热系数衰减速率） / Heat exchanger fouling trend diagnosis via UA decay rate
  分类 Category : DL_Process
  版本 Version  : 1.0.0
  来源 Source   : t1-2-oscat-building — 换热器族深化（与 HeatExchangerCtrl/HeatExchangerLmtd 分工：那两件管控制与 LMTD 计算，本件管结垢趋势诊断）
  溯源 Origin   : clean-room 实现，UA = 热负荷 / LMTD 为公开传热公式，未复制任何源码行
  功能 Function : 1) UA 估计：fUA := fHeatKw / fLmtdK（除法前域闸 fLmtdK >=
                  fLmtdMin 且 fHeatKw > 0，防除零与负商）；
                  2) 趋势窗：tTrendWin 单相独占 TON，窗内累计 UA 样本均值，
                  窗满判据 fUAavg < fUaRef × fUaTripPct / 100 → 039B 结垢
                  衰减超阈锁存（R190 归因唯一：判据无效走 039A，衰减超阈走 039B）；
                  3) 判据无效（LMTD 低于下限 / UA 非有限）→ ePause 相暂停采样
                  （双出口：判据恢复 / 撤使能，R98），判据无效为条件暂停不锁存；
                  4) 故障级：039A UA 换算非有限锁存（防御兜底）/ 039B 结垢衰减
                  超阈锁存 / 039C 组态非法 + ELSE 兜底归并；
                  5) 信息级三码：趋势窗采样完成 / 判据恢复 / 趋势复位（单拍沿）；
                  6) 解除式全当拍量（R240 落地），逐 BOOL 标注见段 4。
  边界 Boundary : ① 组态闸：fLmtdMin <= 0、fUaRef <= 0、fUaTripPct 不在
                  (0,100] 域、tTrendWin <= 0 → 039C 锁存，采样停发；
                  ② 非有限判据自反 + 差值自减双判（R79）；均值除法前判样本数
                  > 0（防除零）；
                  ③ 判据无效暂停为条件态不占故障码（R90 反证：暂停态由
                  bDtInvalid 镜像 + 相位出口可完整观测，不需加码）；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Process 段 0005，窗口 039A~039C / 04C2~04C4）:
    16#0005_039A 故障级：UA 换算非有限锁存（防御兜底），锁存至 bReset
    16#0005_039B 故障级：结垢衰减超阈锁存（窗均 UA 低于 fUaTripPct 基准），锁存至 bReset
    16#0005_039C 故障级：组态非法（LMTD 下限/基准 UA/百分比/窗域非法）或相位落 ELSE 兜底（归并声明），锁存至 bReset
    16#0005_04C2 信息级：趋势窗采样完成沿（窗满判定拍）
    16#0005_04C3 信息级：判据恢复沿（ePause 恢复出口）
    16#0005_04C4 信息级：趋势复位沿（样本累计清零拍）
  修订历史 Revision :
    2026-11-19  v1.0.0  R42 首版（批次 3 · 序号 5）
*)

TYPE E_DL_HftState :
(
    eIdle   := 0,    // 未使能：不采样 / Idle, not sampling
    eRun    := 10,   // 采样中：UA 累计 / Run, UA accumulating
    ePause  := 20,   // 暂停：判据无效 / Pause, verdict invalid
    eFault  := 90    // 故障：非有限或超阈锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_HeatExchangerFoulingTrend
VAR_INPUT
    fHeatKw      : REAL := 0.0;       // 换热负荷 [kW]，调用方注入 / Heat duty
    fLmtdK       : REAL := 0.0;       // 对数平均温差 [K]，调用方注入（LMTD 属主为 HeatExchangerLmtd）/ LMTD
    fLmtdMin     : REAL := 1.0;       // LMTD 判据下限 [K]，域 > 0 / LMTD verdict minimum
    fUaRef       : REAL := 100.0;     // 洁净基准 UA [kW/K]，域 > 0 / Clean reference UA
    fUaTripPct   : REAL := 70.0;      // 结垢衰减跳闸百分比 [%]，域 (0,100] / Fouling trip percent
    tTrendWin    : TIME := T#60S;     // 趋势采样窗 [ms]，域 > 0 / Trend sampling window
    bTrendEn     : BOOL := FALSE;     // 趋势使能（电平）[-] / Trend enable, level
    bTrendRst    : BOOL := FALSE;     // 趋势复位指令，上升沿清样本累计 [-] / Trend reset command edge
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_OUTPUT
    eState       : E_DL_HftState;     // 状态出口，段尾单点映射 / State outlet
    fUaNow       : REAL;              // 当前 UA 估计 [kW/K] / Current UA estimate
    fUaWinAvg    : REAL;              // 趋势窗 UA 均值 [kW/K]（窗满刷新）/ Window UA average
    bVerdictBad  : BOOL;              // 判据无效镜像（ePause 相电平）[-] / Verdict-invalid mirror
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonTrendWin  : TON;               // 趋势采样窗（单相独占），无条件刷新 / Trend window timer
    rtTrendRst   : R_TRIG;            // 趋势复位沿实例，无条件刷新 / Trend reset edge instance
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _fUa         : REAL;              // 逐拍 UA 估计 [kW/K]（当拍量）/ Per-scan UA estimate
    _bVerdictOk  : BOOL;              // 判据有效当拍量 [-] / Verdict-valid flag
    _bNonFin     : BOOL;              // UA 非有限当拍量 [-] / Non-finite UA flag
    _nSamples    : DINT;              // 窗内样本数 [个] / Sample count in window
    _fUaSum      : REAL;              // 窗内 UA 样本和 [kW/K] / UA sample sum in window
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_bVerdictOk := (fLmtdK >= fLmtdMin) AND (fHeatKw > 0.0);    // 判据有效（当拍量：分母域闸 + 正负荷）
IF _bVerdictOk THEN                  // 域内才做除法（防除零/防负商）
    _fUa := fHeatKw / fLmtdK;        // UA 估计（当拍量）
    _bNonFin := (_fUa <> _fUa) OR ((_fUa - _fUa) <> (_fUa - _fUa));
                                        // 非有限防御（NaN 自反 + 差值自减）
ELSE
    _fUa := 0.0;                     // 判据无效：UA 置 0（安全侧）
    _bNonFin := FALSE;               // 未做除法：非有限标志 FALSE
END_IF
rtTrendRst(CLK := bTrendRst);        // 趋势复位沿（每拍必调）
rtReset(CLK := bReset);              // 复位沿（每拍必调）
tonTrendWin(IN := (_eState = E_DL_HftState.eRun) AND _bVerdictOk, PT := tTrendWin);
                                        // 趋势窗（运行相 + 判据有效电平，暂停拍 IN 断）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 与样本累计不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
fUaNow := _fUa;                     // 当前 UA 出口（当拍量直出）
bVerdictBad := FALSE;               // 判据无效镜像缺省 FALSE
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（判据当拍量） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF
IF (fLmtdMin <= 0.0) OR (fUaRef <= 0.0) OR (fUaTripPct <= 0.0) OR (fUaTripPct > 100.0)
   OR (TIME_TO_DINT(tTrendWin) <= 0) THEN
    _uFault := 16#0005_039C;        // 故障级：组态非法
    _bFault := TRUE;                // 故障标志与码位配对（R45）
END_IF
IF rtTrendRst.Q THEN                // 趋势复位沿（当拍量）
    _nSamples := 0;                 // 样本数清零
    _fUaSum := 0.0;                 // 样本和清零
    fUaWinAvg := 0.0;               // 窗均值清零
    _uInfo := 16#0005_04C4;         // 信息级：趋势复位沿
END_IF

(* —— 段 3：非有限锁存（判据当拍量） —— *)
IF _bNonFin THEN
    _uFault := 16#0005_039A;        // 故障级：UA 非有限（防御兜底）
    _bFault := TRUE;
END_IF

(* —— 段 4：故障解除式（R240 落地，逐 BOOL 标注）：
     rtReset.Q = 当拍量；NOT bTrendEn = 当拍量；_bVerdictOk = 当拍量。
     均不含锁存量（_bFault/_uFault），解除边真实可达（判据恢复 + 撤使能 + 复位沿）。 —— *)
IF rtReset.Q AND (NOT bTrendEn) AND _bVerdictOk AND (NOT _bNonFin) THEN
    _bFault := FALSE;               // 清故障锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，仅本当拍量解除沿可清）
    IF _eState = E_DL_HftState.eFault THEN
        _eState := E_DL_HftState.eIdle;     // 故障相迁出：回未使能
    END_IF
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_HftState.eIdle:
    IF bTrendEn AND (NOT _bFault) THEN
        _nSamples := 0;                 // 样本数清零（进相预置）
        _fUaSum := 0.0;                 // 样本和清零（进相预置）
        _eState := E_DL_HftState.eRun;  // 进采样相
    END_IF

E_DL_HftState.eRun:
    IF _bVerdictOk AND (NOT _bNonFin) THEN
        _fUaSum := _fUaSum + _fUa;      // 样本累计
        _nSamples := _nSamples + 1;     // 样本数递增
    ELSE
        _eState := E_DL_HftState.ePause;    // 判据无效：进暂停相
    END_IF
    IF tonTrendWin.Q THEN               // 窗满判定（单相独占 TON）
        IF _nSamples > 0 THEN           // 均值除法前判样本数（防除零）
            fUaWinAvg := _fUaSum / UDINT_TO_REAL(UDINT(_nSamples));    // 窗均值
        END_IF
        _uInfo := 16#0005_04C2;         // 信息级：趋势窗采样完成沿
        _nSamples := 0;                 // 窗重启：样本数清零
        _fUaSum := 0.0;                 // 窗重启：样本和清零
        IF fUaWinAvg < fUaRef * fUaTripPct / 100.0 THEN
            _uFault := 16#0005_039B;    // 故障级：结垢衰减超阈
            _bFault := TRUE;
        END_IF
    END_IF
    IF NOT bTrendEn THEN
        _eState := E_DL_HftState.eIdle; // 撤使能：回未使能相
    END_IF

E_DL_HftState.ePause:
    bVerdictBad := TRUE;                // 判据无效镜像（相电平）
    IF _bVerdictOk AND (NOT _bNonFin) THEN  // 出口 1：判据恢复（事件量）
        _uInfo := 16#0005_04C3;         // 信息级：判据恢复沿
        _eState := E_DL_HftState.eRun;  // 回采样相
    ELSIF NOT bTrendEn THEN             // 出口 2：撤使能（前置条件消失，R98 双出口）
        _eState := E_DL_HftState.eIdle; // 回未使能相
    END_IF

E_DL_HftState.eFault:
    ;                                   // 故障相：采样冻结，等解除沿（段 4 承载迁出）

ELSE
    _uFault := 16#0005_039C;            // 故障级：非法相位兜底（归并组态码，码表声明）
    _bFault := TRUE;
    _eState := E_DL_HftState.eFault;    // 强制回故障相

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    bVerdictBad := FALSE;           // 故障相判据镜像强制 FALSE
    fUaNow := 0.0;                  // 故障相 UA 出口强制 0（安全侧）
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
eState := _eState;                  // 状态出口单点映射

END_FUNCTION_BLOCK
