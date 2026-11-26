(* ============================================================
   DL_Algo / FB_DL_IterSolverRunner ｜ v1.0.0 ｜ 2026-11-25
   功能：多方法求根运行器（0 二分 / 1 试位 / 2 割线 / 3 Illinois / 4 Brent）
         ＋括号管理＋无解与超时出口＋迭代上限防死锁。
         纯 IEC 无函数指针，采用「求值回灌协议」：本件在 fXOut 给出待求值点，
         调用方求残差后调用方法 FeedEval(fX, fF) 回灌，主体下一拍消费并给下一点。
   边界：① 括号两端同号 → eFail、码 5（无解），不空转；② 迭代上限（0=不限，默认 100）与
         总超时（0=不限，默认 T#5S）双防死锁，各自独立码（R190 归因唯一）；超时狗武装域
         覆盖 eEvalLo / eEvalHi / eRun 三相，求值相回灌断链亦能超时退出，不永久挂死；
         ③ 回灌点与待求值点
         不匹配（|Δx|>1E-9）→ 丢弃不置错；④ 复位沿作用域：清括号/计数/回灌位/锁存/
         相位，不动 _bInit；⑤ 出口非有限即落 0（N1）；⑥ 方法内不驻留跨拍状态。
   依赖：仅 IEC 61131-3（TON/R_TRIG/ABS/MIN/MAX/LIMIT）
   溯源：DLF-B-ROOTSTEP（内部原创线）｜枚举归属：E_DL_IterRunnerPhase 唯一属主
   码位：零 16# 范式；uErrId 0 无 / 1 组态 / 2 非有限 / 3 迭代上限 / 4 超时 /
         5 括号同号 / 6 非法相位
   ============================================================ *)
TYPE E_DL_IterRunnerPhase :
(
    eIdle   := 0,    // 待机：等待启动沿 / Idle, waiting for the start edge
    eEvalLo := 10,   // 求值下界：等 f(xLo) 回灌 / Waiting for the lower bound residual
    eEvalHi := 20,   // 求值上界：等 f(xHi) 回灌 / Waiting for the upper bound residual
    eRun    := 30,   // 迭代：给试算点并消费回灌 / Iterating over trial points
    eDone   := 40,   // 完成：宽度或残差达标 / Finished within tolerance
    eFail   := 50,   // 失败：无解 / 上限 / 超时 / Failed by no root, cap or timeout
    eFault  := 90    // 故障：组态或非有限锁存 / Fault latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_IterSolverRunner
VAR_INPUT
    bStart   : BOOL;   // 启动，上升沿开始一轮 [-] / Start on the rising edge
    bReset   : BOOL;   // 复位，上升沿解除失败与故障 [-] / Reset on the rising edge
    fXLo     : LREAL;  // 初始括号下界 [-] / Initial lower bracket bound
    fXHi     : LREAL;  // 初始括号上界 [-] / Initial upper bracket bound
    fTol     : LREAL;  // 宽度收敛容差，域 > 0 [-] / Convergence tolerance on the width
    nMethod  : INT;    // 方法选择 0..4 [-] / Method selector
    nIterMax : INT := 100;         // 迭代上限，0 = 不限，默认 100 次（防死锁）[次] / Iteration cap, zero means unlimited
    tTimeout : TIME := T#5S;       // 总超时，0 = 不限，默认 5s（防死锁）[ms] / Overall timeout, zero means unlimited
END_VAR
VAR_OUTPUT
    bDone    : BOOL;   // 求根完成 [-] / Root finding finished
    bError   : BOOL;   // 失败或故障 [-] / Failed or faulted
    fXOut    : LREAL;  // 当前待求值点（完成时为根候选）[-] / Point to evaluate
    fResid   : LREAL;  // 末次回灌残差 [-] / Last residual fed back
    uErrId   : UDINT;  // 事件码，0 = 无事件 [-] / Event code
    nIterOut : INT;    // 已用迭代次数 [次] / Iterations consumed
END_VAR
VAR
    rtStart  : R_TRIG;                                           // 启动沿实例，段 0 无条件刷新 / Start edge
    rtReset  : R_TRIG;                                           // 复位沿实例，段 0 无条件刷新 / Reset edge
    tonTotal : TON;                                              // 总超时狗，段 0 无条件刷新 / Overall watchdog
    _eState  : E_DL_IterRunnerPhase := E_DL_IterRunnerPhase.eIdle; // 内部相位 / Internal phase
    _bInit   : BOOL := FALSE;                                    // 首扫初始化已执行 [-] / First scan init done
    _bFed    : BOOL := FALSE;                                    // 回灌到位（协议位，方法置位）[-] / Feedback ready
    _fFedX   : LREAL := 0.0;                                     // 回灌点横坐标 [-] / Fed back abscissa
    _fFedF   : LREAL := 0.0;                                     // 回灌残差 [-] / Fed back residual
    _fA      : LREAL := 0.0;                                     // 括号下界 [-] / Lower bracket bound
    _fB      : LREAL := 0.0;                                     // 括号上界 [-] / Upper bracket bound
    _fFa     : LREAL := 0.0;                                     // 下界残差 [-] / Residual at the lower bound
    _fFb     : LREAL := 0.0;                                     // 上界残差 [-] / Residual at the upper bound
    _fXCur   : LREAL := 0.0;                                     // 当前待求值点 [-] / Current point to evaluate
    _nIter   : INT := 0;                                         // 已用迭代次数 [次] / Iterations consumed
    _bFault  : BOOL := FALSE;                                    // 故障锁存位 [-] / Latched fault bit
    _bFail   : BOOL := FALSE;                                    // 失败锁存位 [-] / Latched failure bit
    _uFault  : UDINT := 0;                                       // 事件码锁存 [-] / Latched event code
    _bCfgBad : BOOL;                                             // 组态非法当拍量 [-] / Illegal configuration flag
    _bNonFin : BOOL;                                             // 入参非有限当拍量 [-] / Non-finite argument flag
    _bTmoArm : BOOL;                                             // 总超时狗武装量（三相驻留 TRUE）[-] / Watchdog arming flag
END_VAR
VAR CONSTANT
    DL_ISR_EPS : LREAL := 1.0E-9;  // 回灌点匹配与判零容差 [-] / Feedback match and zero tolerance
    DL_ISR_C_CFG : UDINT := 1;     // 码 1：组态非法 / Code one, illegal configuration
    DL_ISR_C_FIN : UDINT := 2;     // 码 2：非有限 / Code two, non-finite value
    DL_ISR_C_ITER : UDINT := 3;    // 码 3：迭代上限 / Code three, iteration cap reached
    DL_ISR_C_TMO : UDINT := 4;     // 码 4：总超时 / Code four, overall timeout
    DL_ISR_C_SGN : UDINT := 5;     // 码 5：括号同号 / Code five, bracket lost by equal signs
    DL_ISR_C_ILL : UDINT := 6;     // 码 6：非法相位 / Code six, illegal phase fallback
END_VAR

(* 方法 NextTrial：按方法选择给下一个试算点，回退固定为括号中点（必能推进）。
   参数全部经引脚传入，不访问 FB 成员，方法内无跨拍状态（R3 方法准则）。 *)
METHOD NextTrial : LREAL
VAR_INPUT
    nSel   : INT;    // 方法选择 0..4 [-] / Method selector
    fA     : LREAL;  // 括号下界 [-] / Lower bracket bound
    fB     : LREAL;  // 括号上界 [-] / Upper bracket bound
    fFa    : LREAL;  // 下界残差 [-] / Residual at the lower bound
    fFb    : LREAL;  // 上界残差 [-] / Residual at the upper bound
    fXPrev : LREAL;  // 上一步试算点 [-] / Previous trial point
    fFxPrev : LREAL; // 上一步残差 [-] / Residual at the previous trial point
END_VAR
VAR
    _fLo  : LREAL;  // 括号小端 [-] / Smaller bracket end
    _fHi  : LREAL;  // 括号大端 [-] / Larger bracket end
    _fMid : LREAL;  // 中点 [-] / Midpoint
    _fDen : LREAL;  // 差分分母 [-] / Slope denominator
    _fX   : LREAL;  // 试算点暂存 [-] / Staged trial point
END_VAR

_fLo := MIN(fA, fB);  _fHi := MAX(fA, fB);
_fMid := _fLo + (_fHi - _fLo) / 2.0;
_fX := _fMid;                                  // 缺省回退中点
CASE nSel OF
0:  _fX := _fMid;                              // 二分
1:  _fDen := fFb - fFa;                        // 试位
    IF ABS(_fDen) > DL_ISR_EPS THEN _fX := fA - fFa * (fB - fA) / _fDen; END_IF
2:  _fDen := fFxPrev - fFa;                    // 割线（最近两点差商）
    IF ABS(_fDen) > DL_ISR_EPS THEN _fX := fXPrev - fFxPrev * (fXPrev - fA) / _fDen; END_IF
3:  _fDen := (fFb / 2.0) - fFa;                // Illinois（停滞端折半）
    IF ABS(_fDen) > DL_ISR_EPS THEN _fX := fA - fFa * (fB - fA) / _fDen; END_IF
4:  IF (ABS(fFa - fFb) > DL_ISR_EPS) AND (ABS(fFa - fFxPrev) > DL_ISR_EPS)
       AND (ABS(fFb - fFxPrev) > DL_ISR_EPS) THEN   // Brent：逆二次插值
        _fX := fA * (fFb * fFxPrev) / ((fFa - fFb) * (fFa - fFxPrev))
             + fB * (fFa * fFxPrev) / ((fFb - fFa) * (fFb - fFxPrev))
             + fXPrev * (fFa * fFb) / ((fFxPrev - fFa) * (fFxPrev - fFb));
    END_IF
ELSE
    _fX := _fMid;                              // 非法方法号：回退二分
END_CASE
IF (_fX <> _fX) OR ((_fX - _fX) <> (_fX - _fX)) THEN
    NextTrial := _fMid;                        // 非有限：回退中点
ELSE
    NextTrial := LIMIT(_fLo, _fX, _fHi);       // 夹界即 N4 出口闸
END_IF
END_METHOD

(* 方法 FeedEval：调用方回灌残差。仅接受与本拍待求值点匹配的回灌（防陈旧值污染
   括号）；不匹配静默丢弃；本方法不推进相位（推进在主体 CASE）。 *)
METHOD FeedEval : BOOL
VAR_INPUT
    fX : LREAL;  // 求值点横坐标 [-] / Abscissa the host evaluated
    fF : LREAL;  // 该点残差 [-] / Residual at that abscissa
END_VAR

FeedEval := FALSE;
IF (fX <> fX) OR (fF <> fF) THEN RETURN; END_IF
IF ABS(fX - _fXCur) > DL_ISR_EPS THEN RETURN; END_IF
_fFedX := fX;  _fFedF := fF;  _bFed := TRUE;  FeedEval := TRUE;
END_METHOD

(* 段 0：沿实例与定时器无条件每拍刷新（R7） *)
rtStart (CLK := bStart);
rtReset (CLK := bReset);
(* 超时狗武装域 = 三相驻留（eEvalLo / eEvalHi / eRun）：只守 eRun 时求值相漏回灌即永久挂死无码 *)
_bTmoArm := (_eState = E_DL_IterRunnerPhase.eEvalLo)
            OR (_eState = E_DL_IterRunnerPhase.eEvalHi)
            OR (_eState = E_DL_IterRunnerPhase.eRun);
tonTotal (IN := _bTmoArm AND (NOT _bFault) AND (tTimeout > T#0S),
          PT := tTimeout);                     // tTimeout = 0 表示不限超时

(* 段 1：单拍量预清零（锁存量与回灌位不入清单，R107） *)
_bCfgBad := FALSE;  _bNonFin := FALSE;

(* 段 2：首扫与复位沿同款初始化（清锁存 / 清括号与计数 / 迁相位，R310/R311） *)
IF (NOT _bInit) OR rtReset.Q THEN
    _bInit := TRUE;  _bFault := FALSE;  _bFail := FALSE;  _uFault := 0;
    _bFed := FALSE;  _nIter := 0;  _fA := 0.0;  _fB := 0.0;  _fXCur := 0.0;
    _eState := E_DL_IterRunnerPhase.eIdle;
END_IF

(* 段 3：组态闸与非有限闸（覆盖全部参与判据的引脚，R272） *)
IF (fTol <= 0.0) OR (nMethod < 0) OR (nMethod > 4) OR (nIterMax < 0) THEN _bCfgBad := TRUE; END_IF
IF (fXLo <> fXLo) OR (fXHi <> fXHi) OR (fTol <> fTol) THEN _bNonFin := TRUE; END_IF
(* Inf 双判（正负无穷括号 = 组态非法，禁带入括号管理）：判据与出口同源于原始入参 *)
IF ((fXLo - fXLo) <> (fXLo - fXLo)) OR ((fXHi - fXHi) <> (fXHi - fXHi))
   OR ((fTol - fTol) <> (fTol - fTol)) THEN _bNonFin := TRUE; END_IF
IF (_bCfgBad OR _bNonFin) AND (NOT (_bFault OR _bFail)) THEN
    _bFault := TRUE;  _eState := E_DL_IterRunnerPhase.eFault;
    IF _bNonFin THEN
        _uFault := DL_ISR_C_FIN;      // 非有限优先归因（值与判据同源，N1）
    ELSE
        _uFault := DL_ISR_C_CFG;      // 组态非法：容差/方法号/迭代上限
    END_IF
END_IF

(* 段 4：主状态机（七相全覆盖 + ELSE 非法相位兜底） *)
CASE _eState OF

E_DL_IterRunnerPhase.eIdle:
    IF rtStart.Q THEN
        _fA := fXLo;  _fB := fXHi;  _nIter := 0;  _bFed := FALSE;
        _fXCur := fXLo;  _eState := E_DL_IterRunnerPhase.eEvalLo;   // 先求下界残差
    END_IF

E_DL_IterRunnerPhase.eEvalLo:
    IF _bFed THEN                              // 事件：回灌到位
        _fFa := _fFedF;  _bFed := FALSE;  _fXCur := _fB;
        _eState := E_DL_IterRunnerPhase.eEvalHi;
    ELSIF tonTotal.Q THEN                      // 事件缺失：超时接管（回灌断链不再永久挂死）
        _bFail := TRUE;  _uFault := DL_ISR_C_TMO;  _eState := E_DL_IterRunnerPhase.eFail;
    ELSIF ABS(_fB - _fA) <= DL_ISR_EPS THEN    // 前置消失：括号零宽
        _bFail := TRUE;  _uFault := DL_ISR_C_SGN;  _eState := E_DL_IterRunnerPhase.eFail;
    END_IF

E_DL_IterRunnerPhase.eEvalHi:
    IF _bFed THEN
        _fFb := _fFedF;  _bFed := FALSE;
        IF (ABS(_fFa) <= DL_ISR_EPS) OR (ABS(_fFb) <= DL_ISR_EPS) THEN
            _eState := E_DL_IterRunnerPhase.eDone;          // 端点已是根
        ELSIF ((_fFa > 0.0) AND (_fFb > 0.0)) OR ((_fFa < 0.0) AND (_fFb < 0.0)) THEN
            _bFail := TRUE;  _uFault := DL_ISR_C_SGN;       // 同号：无解归因
            _eState := E_DL_IterRunnerPhase.eFail;
        ELSE
            _fXCur := NextTrial(nSel := nMethod, fA := _fA, fB := _fB, fFa := _fFa,
                                fFb := _fFb, fXPrev := _fA, fFxPrev := _fFa);
            _eState := E_DL_IterRunnerPhase.eRun;
        END_IF
    ELSIF tonTotal.Q THEN                      // 事件缺失：超时接管（上界残差回灌断链亦不再挂死）
        _bFail := TRUE;  _uFault := DL_ISR_C_TMO;  _eState := E_DL_IterRunnerPhase.eFail;
    END_IF

E_DL_IterRunnerPhase.eRun:
    IF _bFed THEN
        _bFed := FALSE;  _nIter := _nIter + 1;              // 计数唯一写入点
        IF ((_fFa > 0.0) AND (_fFedF < 0.0)) OR ((_fFa < 0.0) AND (_fFedF > 0.0)) THEN
            _fB := _fFedX;  _fFb := _fFedF;                 // 回灌点与下界异号：替上界
        ELSE
            _fA := _fFedX;  _fFa := _fFedF;
        END_IF
        IF ABS(_fFedF) <= DL_ISR_EPS THEN
            _eState := E_DL_IterRunnerPhase.eDone;          // 残差达标
        ELSIF ABS(_fB - _fA) <= fTol THEN
            _eState := E_DL_IterRunnerPhase.eDone;          // 宽度达标
        ELSIF (nIterMax > 0) AND (_nIter >= nIterMax) THEN
            _bFail := TRUE;  _uFault := DL_ISR_C_ITER;
            _eState := E_DL_IterRunnerPhase.eFail;
        ELSE
            _fXCur := NextTrial(nSel := nMethod, fA := _fA, fB := _fB, fFa := _fFa,
                                fFb := _fFb, fXPrev := _fFedX, fFxPrev := _fFedF);
        END_IF
    ELSIF tonTotal.Q THEN                      // 事件缺失：超时接管（R275 事件优先）
        _bFail := TRUE;  _uFault := DL_ISR_C_TMO;  _eState := E_DL_IterRunnerPhase.eFail;
    END_IF

E_DL_IterRunnerPhase.eDone:
    IF rtStart.Q THEN                          // 启动沿重开一轮
        _bFed := FALSE;  _nIter := 0;  _fA := fXLo;  _fB := fXHi;  _fXCur := fXLo;
        _eState := E_DL_IterRunnerPhase.eEvalLo;
    END_IF

E_DL_IterRunnerPhase.eFail:
    _bFail := TRUE;                            // 失败相驻留：码位锁存回放

E_DL_IterRunnerPhase.eFault:
    _bFault := TRUE;                           // 故障相驻留：出口保持安全值

ELSE
    _bFault := TRUE;  _uFault := DL_ISR_C_ILL;  _eState := E_DL_IterRunnerPhase.eFault;
END_CASE

(* 段 5：故障迁相闸（置于解除段之后，R274） *)
IF _bFault AND (_eState <> E_DL_IterRunnerPhase.eFault) THEN
    _eState := E_DL_IterRunnerPhase.eFault;
END_IF

(* 段 6：统一出口段（判据位与实值单点裁决，N4） *)
bDone := (_eState = E_DL_IterRunnerPhase.eDone);
bError := _bFault OR _bFail;  uErrId := _uFault;  nIterOut := _nIter;
IF (_fXCur <> _fXCur) OR ((_fXCur - _fXCur) <> (_fXCur - _fXCur)) THEN
    fXOut := 0.0;                              // 非有限兜底（N1）
ELSE
    fXOut := _fXCur;
END_IF
IF (_fFedF <> _fFedF) OR ((_fFedF - _fFedF) <> (_fFedF - _fFedF)) THEN
    fResid := 0.0;
ELSE
    fResid := _fFedF;
END_IF
END_FUNCTION_BLOCK
