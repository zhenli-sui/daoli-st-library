(*
  FB_DL_ElectrolyteFillCtrl  —  注液量闭环（称重罐减量法 + 静置浸润计时）/ Electrolyte fill closed loop, mass-loss method
  分类 Category : DL_Process
  码位 Code     : 16#06_0_B7
  段位说明      : B6 格由 HjtPvdSeq 启用，本件启用相邻 B7 格（一件一码）
  版本 Version  : 1.0.0
  来源 Source   : t2-2-lbp — 注液闭环工艺待挖项
  溯源 Origin   : clean-room 实现，减量法注液公开工艺语义借鉴，未复制任何源码行
                  （与 FB_DL_ElectrolyteDosingSeq 分工：那件是定量投加顺控，本件是减量法闭环注液 + 浸润驻留）
  功能 Function : 1) 六相顺控 Idle→Tare→Fill→Trim→Dwell→Done：皮重稳定采集 → 大流量粗注 →
                  微调收口 → 静置浸润驻留 → 完成；
                  2) 减量法口径：注液量 fFilledKg = 皮重 − 实时称重（罐在秤上，质量递减）；
                  3) 粗注→微调切换：剩余量经 FC_DL_Hysteresis 迟滞判入预关带（防阀门口径切换抖动）；
                  4) 收口判定：FB_DL_ToleranceWindow 三态判定注液量入容差 → 关阀进静置；
                  5) 静置浸润：tDwellTime 驻留，质量漂移超 fDwellDriftKg 置信息级码（渗漏提示不置故障）。
  边界 Boundary : ① 称重信号 fTankMassKg 非有限保持上次有效值；注液期质量上升（反流）判故障级锁存；
                  ② 组态域闸覆盖全部参与换算引脚（R151）；容差/提前量/驻留时长域非法判组态错；
                  ③ R228-A 达标声明：tonTareTo/tonFillTo/tonTrimTo/tonDwell 各自单相独占
                  （IN 为单相等式），跨相迁移拍 IN 必断；tonDwell PT 接浸润时长（配方语义）；
                  ④ R228-B 达标声明：eFault 迁出 = rtReset.Q（输入引脚，恒可达），逐字写于此；
                  ⑤ 阀门指令为开度百分比（rValveCmdPct），不写物理 IO（由上层 PRG_IoMapping 承载）；
                  ⑥ CASE 全态覆盖 + ELSE 兜底置 Fault。
  依赖 Depends  : FB_DL_ToleranceWindow / FB_DL_SignalStatistics（实例化，引脚按 registry 实名）；
                  FC_DL_Hysteresis（函数调用，bState 由本件成员持有回传）
  码表 Error codes（本件格 06_0_B7，子码步进 +0x100）:
    16#0006_01B7 信息级：注液周期完成（Done 相）
    16#0006_02B7 故障级：组态非法（目标/容差/提前量/漂移阈/驻留/超时域非法），锁存至复位
    16#0006_03B7 故障级：相超时（Tare/Fill/Trim 独立计时），锁存至复位
    16#0006_04B7 故障级：称重信号非有限持续 / 注液期质量上升（反流），锁存至复位
    16#0006_05B7 故障级：状态机落 ELSE 兜底（非法相位 ID）
    16#0006_06B7 信息级：静置期质量漂移超阈（渗漏提示，不置故障）
    16#0006_07B7 信息级：皮重稳定判据等待中（Tare 相，不置故障）

  修订历史 Revision :
    2026-11-19  v1.0.0  R39 首版（批次 3 · 序号 15）
*)

TYPE E_DL_ElytFillState :
(
    eIdle  := 0,    // 空闲：等启动指令 / Idle, waiting for start
    eTare  := 10,   // 皮重相：称重稳定后锁皮重 / Tare, lock tare after mass stable
    eFill  := 20,   // 粗注相：阀全开大流量 / Bulk fill, valve wide open
    eTrim  := 30,   // 微调相：收口至容差带 / Trim, close into tolerance band
    eDwell := 40,   // 静置相：浸润驻留 + 漂移监视 / Dwell, soaking with drift watch
    eDone  := 50,   // 完成：周期落定 / Done
    eFault := 90    // 故障：组态/超时/称重锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_ElectrolyteFillCtrl
VAR_INPUT
    bStart        : BOOL := FALSE;      // 启动指令（上升沿）/ Start command
    fTankMassKg   : REAL := 0.0;        // 称重罐实时质量 [kg] / Live tank mass from scale
    fBatchTargetKg: REAL := 5.0;        // 目标注液量 [kg]，域 > 0 / Target fill mass
    fFillTolKg    : REAL := 0.02;       // 注液量容差半宽 [kg]，域 > 0 / Fill tolerance half band
    fPrefillKg    : REAL := 0.10;       // 粗注→微调预关提前量 [kg]，域 > 0 / Pre-close lead mass
    fHystKg       : REAL := 0.02;       // 切换迟滞带 [kg]，域 > 0 / Switch hysteresis band
    fStatTolKg    : REAL := 0.005;      // 皮重/静置稳定峰峰阈 [kg]，域 > 0 / Stability peak-to-peak threshold
    fDwellDriftKg : REAL := 0.01;       // 静置漂移报警阈 [kg]，域 > 0 / Dwell drift alarm threshold
    tTareTo       : TIME := T#10S;      // 皮重相超时 [ms]，域 > 0 / Tare timeout
    tFillTo       : TIME := T#120S;     // 粗注相超时 [ms]，域 > 0 / Bulk fill timeout
    tTrimTo       : TIME := T#60S;      // 微调相超时 [ms]，域 > 0 / Trim timeout
    tDwellTime    : TIME := T#30S;      // 静置浸润时长 [ms]，域 > 0 / Dwell soaking duration
    bReset        : BOOL := FALSE;      // 复位（eFault 迁出唯一沿）/ Reset, sole fault exit edge
END_VAR
VAR_OUTPUT
    rValveCmdPct  : REAL;               // 注液阀开度指令 [%]（上层消费）/ Fill valve command output
    fFilledKg     : REAL;               // 已注液量 [kg] = 皮重 − 实时质量 / Filled mass by mass loss
    fRemainingKg  : REAL;               // 剩余注液量 [kg] / Remaining fill mass
    fTareKg       : REAL;               // 锁定皮重 [kg] / Locked tare mass
    bFillDone     : BOOL;               // 注液完成 / Fill cycle done
    bDwellDone    : BOOL;               // 静置浸润完成 / Dwell done
    nErrId        : UDINT;              // 事件码，0 = 无事件 / Event code
    eState        : E_DL_ElytFillState; // 状态出口，段尾单点映射 / State outlet
END_VAR
VAR
    fbTol      : FB_DL_ToleranceWindow; // 容差窗判定实例（主体首部无条件刷新）/ Tolerance window instance
    fbStat     : FB_DL_SignalStatistics;// 质量稳定统计窗实例（主体首部无条件刷新）/ Mass statistics window instance
    tonTareTo  : TON;                  // 皮重相超时（单相独占）/ Tare timeout, single phase
    tonFillTo  : TON;                  // 粗注相超时（单相独占）/ Bulk fill timeout, single phase
    tonTrimTo  : TON;                  // 微调相超时（单相独占）/ Trim timeout, single phase
    tonDwell   : TON;                  // 静置浸润计时（单相独占，PT=浸润时长）/ Dwell timer, single phase
    rtStart    : R_TRIG;               // 启动上升沿 / Start rising edge
    rtReset    : R_TRIG;               // 复位上升沿 / Reset rising edge
    _eState    : E_DL_ElytFillState := E_DL_ElytFillState.eIdle;   // 内部相位（CASE 唯一写入目标）/ Internal phase
    _rMassEff  : REAL;                 // 生效质量 [kg]（非有限保持载体）/ Effective mass with hold carrier
    _rMassLast : REAL := 0.0;          // 上次有效质量 [kg] / Last valid mass
    _rMassPrv  : REAL;                 // 上拍质量 [kg]（反流判据基准）/ Previous mass for backflow test
    _rTareInt  : REAL := 0.0;          // 皮重内部量 [kg] / Internal tare register
    _rFilled   : REAL;                 // 已注液量中间量 [kg] / Filled mass working value
    _rRemain   : REAL;                 // 剩余量中间量 [kg] / Remaining mass working value
    _rDriftRef : REAL;                 // 静置起始质量参照 [kg] / Dwell-start mass reference
    _bNearTgt  : BOOL;                 // 预关带迟滞判据回传保持变量 / Hysteresis pre-close band hold member
    _bMassBad  : BOOL;                 // 质量非有限标志 / Mass non-finite flag
    _uFault    : UDINT;                // 故障码锁存 / Latched fault code
    _uInfo     : UDINT;                // 信息码，每拍重算 / Info code
    _bFault    : BOOL;                 // 故障锁存位 / Latched fault bit
    _bCfgBad   : BOOL;                 // 组态非法聚合 / Configuration invalid aggregate
END_VAR
VAR CONSTANT
    DL_EF_INF_CAP  : REAL := 1.0E15;  // 非有限值筛查幅值上限 / Non-finite screening cap
    DL_EF_VALVE_OPEN  : REAL := 100.0;  // 粗注阀开度 [%] / Bulk fill valve opening
    DL_EF_VALVE_TRIM  : REAL := 30.0;   // 微调阀开度 [%] / Trim valve opening
END_VAR

(* —— 段 0：定时器与边沿实例无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
rtStart(CLK := bStart);                                                 // 启动沿刷新，每拍必调
rtReset(CLK := bReset);                                                 // 复位沿刷新，每拍必调
tonTareTo(IN := (_eState = E_DL_ElytFillState.eTare), PT := tTareTo);       // 皮重超时（单相独占）
tonFillTo(IN := (_eState = E_DL_ElytFillState.eFill), PT := tFillTo);       // 粗注超时（单相独占）
tonTrimTo(IN := (_eState = E_DL_ElytFillState.eTrim), PT := tTrimTo);       // 微调超时（单相独占）
tonDwell(IN := (_eState = E_DL_ElytFillState.eDwell), PT := tDwellTime);    // 浸润计时（单相独占，PT=配方时长）

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault/_rTareInt/_rDriftRef 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
bFillDone := FALSE;                 // 完成出口缺省 FALSE（Done 相单点置位）
bDwellDone := FALSE;                // 静置完成出口缺省 FALSE（Done 相单点置位）
_bCfgBad := FALSE;                  // 组态非法预清零
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：组态域闸（覆盖全部参与判据换算的引脚，R151） —— *)
IF (fBatchTargetKg <> fBatchTargetKg) OR (fBatchTargetKg <= 0.0) OR (ABS(fBatchTargetKg) > DL_EF_INF_CAP)
   OR (fFillTolKg <= 0.0) OR (fPrefillKg <= 0.0) OR (fHystKg <= 0.0)
   OR (fStatTolKg <= 0.0) OR (fDwellDriftKg <= 0.0)
   OR (TIME_TO_DINT(tTareTo) <= 0) OR (TIME_TO_DINT(tFillTo) <= 0)
   OR (TIME_TO_DINT(tTrimTo) <= 0) OR (TIME_TO_DINT(tDwellTime) <= 0) THEN
    _bCfgBad := TRUE;               // 目标/容差/提前量/漂移阈/时长域非法
END_IF

(* —— 段 3：eFault 迁出沿（R228-B：rtReset.Q 为输入引脚，恒可达） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;
    IF _eState = E_DL_ElytFillState.eFault THEN
        _eState := E_DL_ElytFillState.eIdle;    // 故障相迁出：回空闲
    END_IF
END_IF

(* —— 段 4：质量采集与减量法换算（非有限保持；反流判据） —— *)
_bMassBad := (fTankMassKg <> fTankMassKg) OR (ABS(fTankMassKg) > DL_EF_INF_CAP) OR ((fTankMassKg - fTankMassKg) <> 0.0);
IF _bMassBad THEN
    _rMassEff := _rMassLast;        // 非有限：保持上次有效值
ELSE
    _rMassEff := fTankMassKg;       // 有效值入载体
    _rMassLast := fTankMassKg;
END_IF
IF (NOT _bMassBad) AND (_rMassEff - _rMassPrv > fStatTolKg) AND (_eState = E_DL_ElytFillState.eFill) THEN
    _uFault := 16#0006_04B7;        // 故障级：注液期质量上升（反流）
    _bFault := TRUE;
END_IF
_rMassPrv := _rMassEff;             // 反流判据基准更新（段尾单点）
IF NOT _bMassBad THEN
    _rFilled := _rTareInt - _rMassEff;          // 减量法：注液量 = 皮重 − 实时质量
ELSE
    _rFilled := 0.0;                // 质量无效：注液量出口置 0（防御口径）
END_IF
_rRemain := fBatchTargetKg - _rFilled;          // 剩余量
fFilledKg := _rFilled;              // 注液量出口镜像
fRemainingKg := _rRemain;           // 剩余量出口镜像
fTareKg := _rTareInt;               // 皮重出口镜像

(* —— 段 5：依赖件无条件周期刷新（容差窗 + 稳定窗 + 迟滞判据） —— *)
fbTol(bEnable := (_eState = E_DL_ElytFillState.eTrim),      // 仅微调相判定
      fTarget := fBatchTargetKg,                            // 目标注液量
      fActual := _rFilled,                                  // 实际注液量
      fTolerance := fFillTolKg,                             // 容差半宽
      fHysteresis := fHystKg);                              // 迟滞带（出窗防抖）
fbStat(fIn := _rMassEff,                                    // 质量稳定统计窗
       bSample := (_eState = E_DL_ElytFillState.eTare) OR (_eState = E_DL_ElytFillState.eDwell),
       nWindow := 32,                                       // 窗长（稳定判据标准口径）
       bClear := rtStart.Q);                                // 启动沿清窗（新批次重开）
_bNearTgt := FC_DL_Hysteresis(fIn := -_rRemain,             // 取反口径：剩余量落入预关带为 TRUE
                              fThreshold := -fPrefillKg,    // 预关阈（取反）
                              fHysteresis := fHystKg,       // 迟滞带（负值取绝对值语义由件内防御）
                              bState := _bNearTgt);         // 回传保持变量（同一成员，有状态纪律）

(* —— 段 6：相位机（只做迁移与阀指令；出口在段 8） —— *)
CASE _eState OF

E_DL_ElytFillState.eIdle:
    rValveCmdPct := 0.0;                    // 空闲：阀全关
    IF rtStart.Q AND _bCfgBad THEN
        _uFault := 16#0006_02B7;            // 故障级：组态非法
        _bFault := TRUE;
        _eState := E_DL_ElytFillState.eFault;
    ELSIF rtStart.Q AND (NOT _bCfgBad) THEN
        _rDriftRef := 0.0;                  // 静置参照预清零
        _eState := E_DL_ElytFillState.eTare;    // 进皮重相
    END_IF

E_DL_ElytFillState.eTare:
    rValveCmdPct := 0.0;                    // 皮重相：阀全关
    IF NOT _bMassBad THEN
        IF fbStat.bValid AND (fbStat.fRange <= fStatTolKg) THEN
            _rTareInt := _rMassEff;         // 锁皮重（稳定峰峰在阈内）
            _eState := E_DL_ElytFillState.eFill;    // 进粗注相
        ELSE
            _uInfo := 16#0006_07B7;         // 信息级：皮重稳定判据等待中
        END_IF
    END_IF
    IF tonTareTo.Q AND (_eState = E_DL_ElytFillState.eTare) THEN
        _uFault := 16#0006_03B7;            // 故障级：皮重相超时
        _bFault := TRUE;
        _eState := E_DL_ElytFillState.eFault;
    END_IF

E_DL_ElytFillState.eFill:
    rValveCmdPct := DL_EF_VALVE_OPEN;       // 粗注：阀全开
    IF tonFillTo.Q THEN
        _uFault := 16#0006_03B7;            // 故障级：粗注相超时
        _bFault := TRUE;
        rValveCmdPct := 0.0;                // 安全侧关阀
        _eState := E_DL_ElytFillState.eFault;
    ELSIF _bNearTgt THEN
        _eState := E_DL_ElytFillState.eTrim;    // 剩余量入预关带：进微调相
    END_IF

E_DL_ElytFillState.eTrim:
    IF _rRemain > 0.0 THEN
        rValveCmdPct := DL_EF_VALVE_TRIM;   // 微调：小开度收口
    ELSE
        rValveCmdPct := 0.0;                // 越量：关阀
    END_IF
    IF fbTol.bOk THEN
        rValveCmdPct := 0.0;                // 入容差带：关阀
        _rDriftRef := _rMassEff;            // 静置起始质量参照锁定
        _eState := E_DL_ElytFillState.eDwell;   // 进静置相
    ELSIF tonTrimTo.Q THEN
        _uFault := 16#0006_03B7;            // 故障级：微调相超时
        _bFault := TRUE;
        rValveCmdPct := 0.0;                // 安全侧关阀
        _eState := E_DL_ElytFillState.eFault;
    END_IF

E_DL_ElytFillState.eDwell:
    rValveCmdPct := 0.0;                    // 静置：阀全关
    IF ABS(_rMassEff - _rDriftRef) > fDwellDriftKg THEN
        _uInfo := 16#0006_06B7;             // 信息级：静置漂移超阈（渗漏提示，不置故障）
    END_IF
    IF tonDwell.Q THEN
        _eState := E_DL_ElytFillState.eDone;    // 浸润到点：进完成相
    END_IF

E_DL_ElytFillState.eDone:
    rValveCmdPct := 0.0;                    // 完成：阀全关
    bFillDone := TRUE;                      // 完成出口（Done 相每拍重申）
    bDwellDone := TRUE;                     // 静置完成出口（Done 相每拍重申）
    _uInfo := 16#0006_01B7;                 // 信息级：周期完成
    IF NOT bStart THEN
        _eState := E_DL_ElytFillState.eIdle;    // 指令撤销：回空闲
    END_IF

E_DL_ElytFillState.eFault:
    rValveCmdPct := 0.0;                    // 故障相：阀全关（安全侧）
    ;                                       // 等复位沿（段 3 承载迁出）

ELSE
    _uFault := 16#0006_05B7;                // 故障级：非法相位 ID 兜底
    _bFault := TRUE;
    rValveCmdPct := 0.0;                    // 安全侧关阀
    _eState := E_DL_ElytFillState.eFault;   // 强制回故障相

END_CASE

(* —— 段 7：称重非有限持续判故障（段 4 标志的锁存化，R228-B 配对） —— *)
IF _bMassBad AND (_eState <> E_DL_ElytFillState.eIdle) THEN
    _uFault := 16#0006_04B7;                // 故障级：称重信号非有效持续（活动相内）
    _bFault := TRUE;
END_IF

(* —— 段 8：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _bFault THEN
    nErrId := _uFault;                      // 故障锁存码回放（不在故障相按当下输入重推）
    bFillDone := FALSE;                     // 故障相完成出口强制 FALSE（安全侧）
    bDwellDone := FALSE;
ELSE
    nErrId := _uInfo;                       // 信息码
END_IF
eState := _eState;                          // 状态出口单点映射

END_FUNCTION_BLOCK
