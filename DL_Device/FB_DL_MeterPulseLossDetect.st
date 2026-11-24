(*
  Name        : FB_DL_MeterPulseLossDetect
  Category    : DL_Device
  Version     : 1.0.0
  Purpose     : 脉冲式流量计丢脉冲检测：按指令流量与 K 系数推算采样窗内应有脉冲数，与实际累计脉冲增量比对，超容差即判丢脉冲；/ Detect pulse loss on a pulse-output flow meter by comparing expected pulses (command flow x K-factor) against the actual count increment within a sampling window
  溯源        : 借 t1-3-oscat-network·计量 的分类/参数域组织，clean-room 实现
  Boundary    : ① 组态闸：K 系数/采样周期/流量下限/容差任一越域 → 锁存故障；
                ② 流量闸：指令流量 <= 最小有效流量时不判（低流量下脉冲稀疏，比对无意义）；
                ③ 推算除子闸：应有脉冲数 <= eps → 不判（避免小分母放大误差）；
                ④ 累计脉冲负增量（清零/溢出回卷）按 0 处理并计入 bCountReset，不判丢脉冲；
                ⑤ 全部比值判据用容差比较，禁 `=`/`<>`。
*)
TYPE E_DL_MplState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    eMon   := 10,                            (* 比对运行 / Comparing *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_MplCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：K 系数/周期/流量闸越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_MeterPulseLossDetect
VAR_INPUT
    diPulseCount : DINT := 0;                (* 流量计累计脉冲数（表侧原始累计）[脉冲] / Meter cumulative pulse count *)
    fFlowCmd     : REAL := 0.0;              (* 指令/参考流量（工艺给定），域 >= 0 [L/min] / Command (reference) flow, >= 0 *)
    fKFactor     : REAL := 100.0;            (* 仪表 K 系数（脉冲/升），域 > 0 [脉冲/L] / Meter K factor, > 0 *)
    tSample      : TIME := T#1S;             (* 采样窗长，域 > T#0S [ms] / Sampling window, > 0 *)
    fFlowMin     : REAL := 0.5;              (* 最小有效流量（判据闸），域 > 0 [L/min] / Minimum valid flow, > 0 *)
    fLossTolPct  : REAL := 10.0;             (* 丢脉冲容差，域 0 < x < 100 [%] / Loss tolerance, 0..100 *)
    bEnable      : BOOL := TRUE;             (* 检测使能 [-] / Enable *)
    bReset       : BOOL := FALSE;            (* 复位命令，上升沿清比对结果与故障 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    diPulseDelta : DINT;                     (* 本窗实际脉冲增量 [脉冲] / Actual pulse increment this window *)
    fPulseExpect : REAL;                     (* 本窗应有脉冲数（推算值）[脉冲] / Expected pulses this window *)
    fLossPct     : REAL;                     (* 丢脉冲百分比（0 = 不丢，> 0 为丢失比例）[%] / Pulse loss percentage *)
    bPulseLoss   : BOOL;                     (* 丢脉冲判据（超容差）[-] / Pulse loss verdict *)
    bFlowGate    : BOOL;                     (* 流量闸开放（本窗参与判据）[-] / Flow gate open this window *)
    bCountReset  : BOOL;                     (* 累计计数回卷/清零检测位 [-] / Count reset or wrap detected *)
    eState       : E_DL_MplState;            (* 状态出口 / State outlet *)
    eCause       : E_DL_MplCause;            (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError       : BOOL;                     (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_MplState := E_DL_MplState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_MplCause := E_DL_MplCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonWin   : TON;                          (* 采样窗自复位计时器（R188） / Self-resetting window timer *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
    _bFinite : BOOL;                         (* 输入有限性当拍量 / Input finiteness *)
    _diPrev  : DINT;                         (* 上窗脉冲数快照 [脉冲] / Previous window pulse snapshot *)
    _diDelta : DINT;                         (* 本窗增量（负值按 0）[脉冲] / Delta, negative treated as zero *)
    _fDtSec  : REAL;                         (* 窗长秒值 [s] / Window length in seconds *)
    _fExpect : REAL;                         (* 应有脉冲数推算中间量 [脉冲] / Expected pulses intermediate *)
    _fLoss   : REAL;                         (* 丢脉冲百分比中间量 [%] / Loss intermediate *)
END_VAR
VAR CONSTANT
    DL_MPL_EPS     : REAL := 1.0E-6;         (* 判零容差 [-] / Epsilon *)
    DL_MPL_SECMIN  : REAL := 60.0;           (* 每分秒数（L/min → L/s 换算常量）[s] / Seconds per minute *)
    DL_MPL_PCTMAX  : REAL := 100.0;          (* 百分比满量程 [%] / Percentage full scale *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_fDtSec := TIME_TO_LREAL(tSample) / 1000.0;                                    (* 窗长秒化（除子常量 1000） / Window to seconds *)
_bCfgBad := NOT (tSample > T#0S)                                               (* 窗长正域闸 / Window gate *)
            OR (fKFactor <= DL_MPL_EPS)                                        (* K 系数正域闸（乘性因子，零则无脉冲语义） / K factor gate *)
            OR (fFlowMin <= DL_MPL_EPS)                                        (* 流量闸正域 / Flow gate positive *)
            OR (fLossTolPct <= 0.0) OR (fLossTolPct >= DL_MPL_PCTMAX);         (* 容差域闸 (0,100) / Tolerance gate *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
tonWin(IN := NOT tonWin.Q, PT := tSample);                                     (* 采样窗自复位（R188） / Self-resetting window *)
_bFinite := (fFlowCmd = fFlowCmd) AND ((fFlowCmd - fFlowCmd) = (fFlowCmd - fFlowCmd));   (* NaN/Inf 联合闸 / NaN and Inf gate *)

(* —— 段 1：单拍量预清零（R107） —— *)
bPulseLoss := FALSE;                                                           (* 丢脉冲判据预清 / Verdict preset *)
bFlowGate := FALSE;                                                            (* 流量闸预清 / Gate preset *)
bCountReset := FALSE;                                                          (* 计数回卷位预清 / Reset flag preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清比对 + 清快照 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_MplCause.eNone;                                            (* 清成因 / Clear cause *)
    _diPrev := diPulseCount;                                                   (* 快照对齐当前值（复位后不产生虚假增量） / Align snapshot *)
    diPulseDelta := 0;                                                         (* 清增量出口 / Clear delta *)
    fPulseExpect := 0.0;                                                       (* 清推算出口 / Clear expected *)
    fLossPct := 0.0;                                                           (* 清丢包出口 / Clear loss *)
    _eState := E_DL_MplState.eIdle;                                            (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_MplCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_MplState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_MplState.eIdle:                                                       (* 未使能：快照持续跟随，不判 / Disabled *)
        _diPrev := diPulseCount;                                               (* 失能期间跟随（重使能无虚假增量） / Track while disabled *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_MplState.eMon;                                     (* 使能进入比对 / Enter comparing *)
        END_IF
    E_DL_MplState.eMon:                                                        (* 比对相：窗到点结算一次 / Comparing *)
        IF NOT bEnable THEN
            _eState := E_DL_MplState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        ELSIF tonWin.Q THEN                                                    (* 窗到点：单点结算 / Window elapsed: settle once *)
            _diDelta := diPulseCount - _diPrev;                                (* 增量 = 当前 - 上窗快照 / Delta *)
            IF _diDelta < 0 THEN
                _diDelta := 0;                                                 (* 负增量（清零/回卷）：按 0 处理 / Negative: zero *)
                bCountReset := TRUE;                                           (* 标记计数回卷，不判丢脉冲（边界④） / Mark wrap, skip verdict *)
            END_IF
            diPulseDelta := _diDelta;                                          (* 增量出口 / Delta outlet *)
            _diPrev := diPulseCount;                                           (* 快照推进（单点写入，无双向双计） / Advance snapshot *)
            IF _bFinite AND (fFlowCmd > fFlowMin) THEN                         (* 流量闸：低流量不判 / Flow gate *)
                bFlowGate := TRUE;                                             (* 闸开放 / Gate open *)
                _fExpect := fFlowCmd / DL_MPL_SECMIN * _fDtSec * fKFactor;     (* 应有脉冲 = (L/min→L/s)·s·K（除子为常量）[脉冲] / Expected pulses *)
                fPulseExpect := _fExpect;                                      (* 推算出口 / Expected outlet *)
                IF _fExpect > DL_MPL_EPS THEN                                  (* 除子闸（边界③） / Divisor gate *)
                    _fLoss := (1.0 - DINT_TO_REAL(_diDelta) / _fExpect) * DL_MPL_PCTMAX;   (* 丢脉冲百分比（除子已过闸）[%] / Loss percentage *)
                    IF _fLoss < 0.0 THEN
                        _fLoss := 0.0;                                         (* 多计数（负丢包）按 0 饱和 / Clamp to zero *)
                    ELSIF _fLoss > DL_MPL_PCTMAX THEN
                        _fLoss := DL_MPL_PCTMAX;                               (* 上限饱和 100% / Upper saturation *)
                    END_IF
                    fLossPct := _fLoss;                                        (* 丢包出口 / Loss outlet *)
                    IF _fLoss > fLossTolPct THEN
                        bPulseLoss := TRUE;                                    (* 超容差：判丢脉冲 / Exceeds tolerance: loss *)
                    END_IF
                ELSE
                    fLossPct := 0.0;                                           (* 推算量过小：不判，出口清 0 / Too small: no verdict *)
                END_IF
            ELSE
                bFlowGate := FALSE;                                            (* 闸关闭：本窗不判 / Gate closed *)
                fPulseExpect := 0.0;                                           (* 推算出口清 0（无判据语义） / Expected cleared *)
                fLossPct := 0.0;                                               (* 丢包出口清 0 / Loss cleared *)
            END_IF
        END_IF
    E_DL_MplState.eFault:                                                      (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_MplState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_MplCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
