(*
  Name: FB_DL_CrusherLubeInterlockSeq
  Category: DL_Process
  Version: 1.0.0
  Round: R89 / 2026-11-25
  开源溯源：clean-room 自研（族 矿山破碎筛分，ST 开源生态实测 0 命中，无外部代码引入）
  功能：破碎机润滑站启动联锁顺控：油压→流量→回油温度三重确认（各自独立确认窗）后才放行主电机。
  边界条件：① 七入参全部过非有限闸；配置越域即故障（101），主电机永不放行；
            ② 三重确认各用独立 TON，PT 均取 tConfirmS，禁跨相共用（R100：三相不同拍激活，无双窗配比）；
               确认口径 = 判据持续成立累计 tConfirmS（判据掉落则 ET 自清零，重新确认）；
            ③ 硬失效（油压低于下限 30 % / 流量为 0 / 回油超上限 +15 ℃）任一相内立即锁存故障；
            ④ 放行相内任一判据失守即锁存 105 联锁跌落并撤放行（安全侧立即生效，不驻留等待）；
            ⑤ 故障解除唯一路径：故障相内 xStartCmd 释放（R152 可达性自证），清锁存后回 eIdle。
  状态机：eIdle / ePress / eFlow / eTemp / ePermit / eFault（CASE 含 ELSE 兜底）。
*)
TYPE E_DL_LisPhase :
(
    eIdle   := 0,       (* 待机：等启动沿 / Idle, waiting for start edge *)
    ePress  := 10,      (* 油压确认相 / Oil pressure confirmation *)
    eFlow   := 20,      (* 流量确认相 / Flow confirmation *)
    eTemp   := 30,      (* 回油温度确认相 / Return oil temperature confirmation *)
    ePermit := 40,      (* 放行相：主电机允许启动 / Permit phase, motor allowed *)
    eFault  := 90       (* 故障相：锁存待释放 / Fault latched, awaiting release *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_CrusherLubeInterlockSeq
VAR_INPUT
    xStartCmd : BOOL;           (* 润滑站启动命令 [-] Lube station start command *)
    fOilPressBar : REAL;        (* 润滑油压实测 [bar] Oil pressure actual [bar] *)
    fOilPressMinBar : REAL;     (* 油压联锁下限 [bar] Oil pressure interlock minimum [bar] *)
    fFlowLpm : REAL;            (* 润滑油流量实测 [L/min] Oil flow actual [L/min] *)
    fFlowMinLpm : REAL;         (* 流量联锁下限 [L/min] Flow interlock minimum [L/min] *)
    fRetTempC : REAL;           (* 回油温度实测 [℃] Return oil temperature [degC] *)
    fRetTempMaxC : REAL;        (* 回油温度联锁上限 [℃] Return oil temperature limit [degC] *)
    tConfirmS : TIME;           (* 单重确认窗 [ms] Per-channel confirmation window [ms] *)
END_VAR
VAR_OUTPUT
    eState : E_DL_LisPhase;     (* 当前相 [-] Present phase *)
    xMotorPermit : BOOL;        (* 主电机放行 [-] Main motor permit *)
    xFault : BOOL;              (* 故障锁存标志 [-] Fault latched *)
    nErrCode : INT;             (* 故障码 0/101 组态/102 油压硬失效/103 流量硬失效/104 回油超温/105 联锁跌落/106 非法相 [-] Error code *)
END_VAR
VAR
    _ePhase : E_DL_LisPhase := E_DL_LisPhase.eIdle;  (* 内部相（CASE 唯一写入目标） [-] Internal phase *)
    _bFaultLatch : BOOL := FALSE;   (* 故障锁存位 [-] Fault latch *)
    _bReqFault : BOOL := FALSE;     (* 单拍故障请求（段 1 预清） [-] Fault request *)
    _bCfgBad : BOOL := FALSE;       (* 组态非法当拍量 [-] Configuration bad *)
    _bPressOk : BOOL := FALSE;      (* 油压判据成立 [-] Pressure criterion met *)
    _bFlowOk : BOOL := FALSE;       (* 流量判据成立 [-] Flow criterion met *)
    _bTempOk : BOOL := FALSE;       (* 回油温度判据成立 [-] Temperature criterion met *)
    _nErr : INT := 0;               (* 故障码锁存 [-] Latched error code *)
    _nReqErr : INT := 0;            (* 当拍请求码 [-] Requested error code *)
    tonPress : TON;                 (* 油压确认窗（段 0 无条件调用） / Pressure window *)
    tonFlow : TON;                  (* 流量确认窗（段 0 无条件调用） / Flow window *)
    tonTemp : TON;                  (* 温度确认窗（段 0 无条件调用） / Temperature window *)
    rtStart : R_TRIG;               (* 启动沿（段 0 无条件调用） / Start edge *)
END_VAR
VAR CONSTANT
    DL_LIS_EPS : REAL := 1.0E-9;        (* 判据容差 [-] Criterion tolerance *)
    DL_LIS_HARD : REAL := 0.3;          (* 硬失效系数（下限的 30 %） [-] Hard-fail coefficient *)
    DL_LIS_TMARG : REAL := 15.0;        (* 回油超温裕度 [℃] Over-temperature margin [degC] *)
END_VAR
(* —— 段 0：沿与三确认 TON 无条件周期刷新（R7），IN 由相位与判据共同派生 —— *)
rtStart(CLK := xStartCmd);                                                        (* 启动沿 / Start edge *)
(* 判据本体：油压/流量/回油温度阈值比较（阈值均先过非有限闸） *)
_bPressOk := (fOilPressBar >= fOilPressMinBar) AND (fOilPressMinBar > 0.0);
_bFlowOk := (fFlowLpm >= fFlowMinLpm) AND (fFlowMinLpm > 0.0);
_bTempOk := (fRetTempC <= fRetTempMaxC) AND (fRetTempMaxC > 0.0);
tonPress(IN := (_ePhase = E_DL_LisPhase.ePress) AND _bPressOk, PT := tConfirmS);  (* 油压确认 / Pressure *)
tonFlow(IN := (_ePhase = E_DL_LisPhase.eFlow) AND _bFlowOk, PT := tConfirmS);     (* 流量确认 / Flow *)
tonTemp(IN := (_ePhase = E_DL_LisPhase.eTemp) AND _bTempOk, PT := tConfirmS);     (* 温度确认 / Temperature *)
(* 非有限闸（NaN 自反 + Inf 差值自减）+ 静态组态域闸：六浮点入参全枚举（R272） *)
_bCfgBad := (fOilPressBar <> fOilPressBar) OR ((fOilPressBar - fOilPressBar) <> 0.0)
         OR (fOilPressMinBar <> fOilPressMinBar) OR ((fOilPressMinBar - fOilPressMinBar) <> 0.0)
         OR (fFlowLpm <> fFlowLpm) OR ((fFlowLpm - fFlowLpm) <> 0.0)
         OR (fFlowMinLpm <> fFlowMinLpm) OR ((fFlowMinLpm - fFlowMinLpm) <> 0.0)
         OR (fRetTempC <> fRetTempC) OR ((fRetTempC - fRetTempC) <> 0.0)
         OR (fRetTempMaxC <> fRetTempMaxC) OR ((fRetTempMaxC - fRetTempMaxC) <> 0.0)
         OR (fOilPressMinBar <= 0.0) OR (fOilPressMinBar > 20.0)
         OR (fFlowMinLpm <= 0.0) OR (fFlowMinLpm > 500.0)
         OR (fRetTempMaxC <= 20.0) OR (fRetTempMaxC > 120.0)
         OR (tConfirmS <= T#0S);
(* —— 段 1：单拍量预清零 —— *)
_bReqFault := FALSE;
_nReqErr := 0;
(* —— 段 2：故障锁存解除（唯一路径 = 故障相内启动命令释放，R152） —— *)
IF _bFaultLatch AND (NOT xStartCmd) THEN
    _bFaultLatch := FALSE;                      (* 清锁存 / Clear latch *)
    _nErr := 0;                                 (* 清码 / Clear code *)
    _ePhase := E_DL_LisPhase.eIdle;             (* 迁回待机 / Back to idle *)
END_IF
(* —— 段 3：故障请求汇集（组态 + 硬失效 + 放行相跌落，归因唯一 R190） —— *)
IF _bCfgBad THEN
    _bReqFault := TRUE; _nReqErr := 101;        (* 组态非法 / Configuration bad *)
ELSIF (_ePhase <> E_DL_LisPhase.eIdle) AND (fOilPressBar < (fOilPressMinBar * DL_LIS_HARD)) THEN
    _bReqFault := TRUE; _nReqErr := 102;        (* 油压硬失效 / Pressure hard fail *)
ELSIF (_ePhase <> E_DL_LisPhase.eIdle) AND (fFlowLpm <= DL_LIS_EPS) THEN
    _bReqFault := TRUE; _nReqErr := 103;        (* 流量硬失效 / Flow hard fail *)
ELSIF (_ePhase <> E_DL_LisPhase.eIdle) AND (fRetTempC > (fRetTempMaxC + DL_LIS_TMARG)) THEN
    _bReqFault := TRUE; _nReqErr := 104;        (* 回油超温 / Return over-temperature *)
ELSIF (_ePhase = E_DL_LisPhase.ePermit) AND ((NOT _bPressOk) OR (NOT _bFlowOk) OR (NOT _bTempOk)) THEN
    _bReqFault := TRUE; _nReqErr := 105;        (* 放行相联锁跌落 / Interlock loss while permitted *)
END_IF
(* —— 段 4：主状态机（ENUM + CASE，ELSE 兜底） —— *)
CASE _ePhase OF
E_DL_LisPhase.eIdle:
    IF rtStart.Q AND (NOT _bFaultLatch) THEN
        _ePhase := E_DL_LisPhase.ePress;        (* 起序 → 油压确认 / Start to pressure confirm *)
    END_IF
E_DL_LisPhase.ePress:
    IF tonPress.Q THEN
        _ePhase := E_DL_LisPhase.eFlow;         (* 油压确认通过 → 流量 / Pressure ok, flow *)
    END_IF
E_DL_LisPhase.eFlow:
    IF tonFlow.Q THEN
        _ePhase := E_DL_LisPhase.eTemp;         (* 流量确认通过 → 温度 / Flow ok, temperature *)
    END_IF
E_DL_LisPhase.eTemp:
    IF tonTemp.Q THEN
        _ePhase := E_DL_LisPhase.ePermit;       (* 温度确认通过 → 放行 / Temperature ok, permit *)
    END_IF
E_DL_LisPhase.ePermit:
    IF NOT xStartCmd THEN
        _ePhase := E_DL_LisPhase.eIdle;         (* 启动释放 → 待机（撤放行） / Start released *)
    END_IF
E_DL_LisPhase.eFault:
    _bPressOk := (fOilPressBar >= fOilPressMinBar) AND (fOilPressMinBar > 0.0);   (* 故障相驻留：判据每拍照算供追溯，不迁相 *)
ELSE
    _bReqFault := TRUE;                         (* 非法相兜底 / Illegal phase fallback *)
    _nReqErr := 106;
END_CASE
(* —— 段 5：故障请求统一落地（唯一锁存点 + 同步迁相，R187/R252） —— *)
IF _bReqFault AND (NOT _bFaultLatch) THEN
    _bFaultLatch := TRUE;                       (* 锁存 / Latch *)
    _nErr := _nReqErr;                          (* 码锁存回放 / Latched code *)
    _ePhase := E_DL_LisPhase.eFault;            (* 同步迁相 / Migrate to fault *)
END_IF
(* —— 段 6：统一出口（放行 = 相 + 无锁存，安全侧立即撤） —— *)
eState := _ePhase;
xMotorPermit := (_ePhase = E_DL_LisPhase.ePermit) AND (NOT _bFaultLatch)
                AND _bPressOk AND _bFlowOk AND _bTempOk;
xFault := _bFaultLatch;
nErrCode := _nErr;
END_FUNCTION_BLOCK
