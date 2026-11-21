(*
  Name        : FB_DL_ValveCycleLifeCounter
  Category    : DL_Device
  Version     : 1.0.0
  Purpose     : 阀门动作循环寿命计数：行程到位 + 扭角峰值双源同证并经去抖确认才计一个循环，累计数达保养阈值即预警；/ Valve cycle-life counter: one cycle is counted only when both stroke-limit and torque sources agree and the agreement is debounce-confirmed; a maintenance warning is raised at the threshold
  溯源        : 借 t2-8-isa182·回路一致性 的分类/参数域组织，clean-room 实现
  Boundary    : ① 组态闸：保养阈值 < 1 / 去抖时间 <= 0 → 锁存故障（阈值 0 会使预警无意义）；
                ② 双源判据：行程与扭角须同拍同真（AND），单源漂移不会虚计（去抖再拦短时毛刺）；
                ③ 计数用净额单点写入 + 饱和上限（R28 防回绕），不使用 CTU 双向端；
                ④ 循环脉冲 _bCycC 内部置位 → 段 5 统一出口映射单拍（R187），CASE 内不直写出口；
                ⑤ 本件仅计数与预警，不执行保养联锁（属主边界）。
*)
TYPE E_DL_VclState :
(
    eIdle  := 0,                             (* 未使能 / Disabled *)
    eCount := 10,                            (* 寿命计数运行 / Counting *)
    eFault := 90                             (* 故障锁存相 / Fault latched *)
);
END_TYPE

TYPE E_DL_VclCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：阈值/去抖越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_ValveCycleLifeCounter
VAR_INPUT
    bStrokeOk   : BOOL := FALSE;             (* 行程到位信号（限位开关/位控回读）[-] / Stroke limit reached *)
    bTorqueOk   : BOOL := FALSE;             (* 扭角峰值信号（扭矩/扭角判据回读）[-] / Torque-angle criterion met *)
    tDebounce   : TIME := T#200MS;           (* 双源同证去抖时长，域 > T#0S [ms] / Dual-source debounce time, > 0 *)
    nMaintLimit : UDINT := 100000;           (* 保养阈值（累计循环数），域 >= 1 [次] / Maintenance cycle threshold, >= 1 *)
    bEnable     : BOOL := TRUE;              (* 计数使能 [-] / Enable *)
    bReset      : BOOL := FALSE;             (* 复位命令，上升沿清计数与故障（保养完成侧清零亦可用）[-] / Reset command *)
END_VAR
VAR_OUTPUT
    nCycles     : UDINT;                     (* 累计动作循环数（净额，饱和）[次] / Accumulated cycles, saturated *)
    fCycPct     : REAL;                      (* 寿命消耗百分比 = 计数/阈值（饱和 0..100）[%] / Life consumed percentage *)
    bCycPulse   : BOOL;                      (* 本拍新增一个循环（单拍脉冲）[-] / One new cycle this scan *)
    bMaintWarn  : BOOL;                      (* 保养预警：累计数 >= 阈值（电平，复位沿清）[-] / Maintenance warning level *)
    eState      : E_DL_VclState;             (* 状态出口 / State outlet *)
    eCause      : E_DL_VclCause;             (* 故障成因出口（R190 归因唯一） / Fault cause outlet *)
    bError      : BOOL;                      (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState   : E_DL_VclState := E_DL_VclState.eIdle;    (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause   : E_DL_VclCause := E_DL_VclCause.eNone;    (* 故障成因锁存量 / Latched cause *)
    rtReset   : R_TRIG;                      (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    rtCyc     : R_TRIG;                      (* 去抖确认输出沿实例，段 0 无条件调用 / Debounced-cycle edge *)
    tonDeb    : TON;                         (* 双源同证去抖计时器（IN 由双源派生） / Dual-source debounce timer *)
    _bFault   : BOOL;                        (* 故障锁存位 / Latched fault bit *)
    _bCfgBad  : BOOL;                        (* 组态非法当拍量 / Illegal config this scan *)
    _bDual    : BOOL;                        (* 双源同证当拍量（行程 AND 扭角） / Dual-source agreement this scan *)
    _bCycC    : BOOL;                        (* 循环确认内部单拍量（出口统一映射，R187） / Cycle-confirmed internal pulse *)
END_VAR
VAR CONSTANT
    DL_VCL_EPS    : REAL  := 1.0E-6;         (* 判零容差 [-] / Epsilon *)
    DL_VCL_CNTMAX : UDINT := 4294967295;     (* 计数饱和上限（R28）[-] / Count saturation cap *)
    DL_VCL_PCTMAX : REAL  := 100.0;         (* 百分比满量程 [%] / Percentage full scale *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A；R_TRIG/TON 全在段 0，无 IF 包裹） —— *)
_bCfgBad := (nMaintLimit < 1) OR NOT (tDebounce > T#0S);                       (* 阈值下限闸 + 去抖正域闸 / Threshold and debounce gates *)
rtReset(CLK := bReset);                                                        (* 复位沿每拍必调 / Reset edge every scan *)
rtCyc(CLK := tonDeb.Q);                                                        (* 去抖确认输出沿每拍必调 / Debounced edge every scan *)
_bDual := bStrokeOk AND bTorqueOk;                                             (* 双源同证：行程 AND 扭角（单源漂移不虚计） / Dual-source agreement *)
tonDeb(IN := (_eState = E_DL_VclState.eCount) AND _bDual, PT := tDebounce);    (* 去抖计时（eCount 相位闸：eIdle/eFault 不计时，上拍相位 1 拍延迟可接受） / Debounce with phase gate *)

(* —— 段 1：单拍量预清零（R107） —— *)
_bCycC := FALSE;                                                               (* 循环脉冲内部量预清 / Cycle pulse preset *)
bCycPulse := FALSE;                                                            (* 循环脉冲出口预清 / Cycle pulse outlet preset *)
bMaintWarn := FALSE;                                                           (* 预警位预清（仅计数分支按阈值置位） / Warn preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清计数 + 清出口 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                          (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_VclCause.eNone;                                            (* 清成因 / Clear cause *)
    nCycles := 0;                                                              (* 清累计循环数出口 / Clear cycle count *)
    fCycPct := 0.0;                                                            (* 清寿命百分比出口 / Clear life percentage *)
    bMaintWarn := FALSE;                                                       (* 清保养预警出口 / Clear warn outlet *)
    _eState := E_DL_VclState.eIdle;                                            (* 迁未使能相 / Back to idle *)
END_IF

(* —— 段 3：组态故障锁存（锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                                                           (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_VclCause.eCfgIllegal;                                      (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_VclState.eFault;                                           (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_VclState.eIdle:                                                       (* 未使能：不计数，出口保持 0 语义 / Disabled *)
        nCycles := 0;                                                          (* 失能清计数出口（防隐性回夹） / Clear count outlet *)
        fCycPct := 0.0;                                                        (* 失能清百分比出口 / Clear percentage outlet *)
        bMaintWarn := FALSE;                                                   (* 失能清预警出口 / Clear warn outlet *)
        IF bEnable AND NOT _bFault THEN
            _eState := E_DL_VclState.eCount;                                   (* 使能进入计数 / Enter counting *)
        END_IF
    E_DL_VclState.eCount:                                                      (* 计数相：去抖确认后入账 / Counting *)
        IF NOT bEnable THEN
            _eState := E_DL_VclState.eIdle;                                    (* 失能回未使能 / Back to idle *)
        END_IF
        IF rtCyc.Q THEN                                                        (* 双源同证保持满去抖时长：确认一个循环 / Debounce elapsed: one cycle confirmed *)
            _bCycC := TRUE;                                                    (* 循环脉冲内部置位（出口统一映射，R187） / Cycle pulse internal *)
            IF nCycles < DL_VCL_CNTMAX THEN
                nCycles := nCycles + 1;                                        (* 计数净额 +1（饱和防回绕，R28） / Net +1, saturated *)
            END_IF
            IF nCycles >= nMaintLimit THEN
                bMaintWarn := TRUE;                                            (* 累计数达保养阈值：预警锁存（复位沿清） / Maintenance threshold reached *)
            END_IF
            fCycPct := UDINT_TO_REAL(nCycles) / UDINT_TO_REAL(nMaintLimit) * DL_VCL_PCTMAX;   (* 寿命消耗比：除子阈值 >= 1 由组态闸保证 [%] / Life ratio, divisor gated *)
            IF fCycPct > DL_VCL_PCTMAX THEN
                fCycPct := DL_VCL_PCTMAX;                                      (* 百分比上限饱和（该变量最后一次写，钳位不被覆盖） / Upper saturation, last write *)
            END_IF
        END_IF
        IF bMaintWarn = FALSE THEN
            IF nCycles >= nMaintLimit THEN                                     (* 达阈值后维持预警电平（阈值随组态下调亦能覆盖） / Hold warn level *)
                bMaintWarn := TRUE;                                            (* 预警电平保持 / Warn level held *)
            END_IF
        END_IF
    E_DL_VclState.eFault:                                                      (* 故障相：冻结保持末值，仅复位沿出 / Fault *)
        ;                                                                      (* 锁存回放（R28） / Replay from latch *)
    ELSE                                                                       (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_VclState.eFault;                                       (* 迁故障相 / To fault *)
        _bFault := TRUE;                                                       (* 同步锁存 / Latch *)
        _eCause := E_DL_VclCause.ePhaseBad;                                    (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（内部 _b* → 输出单拍，R187；名实双出口，R191） —— *)
bCycPulse := _bCycC;                                                           (* 循环脉冲单拍出口 / Cycle pulse single-scan outlet *)
bError := _bFault;                                                             (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                                                             (* 状态出口 / State outlet *)
eCause := _eCause;                                                             (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
