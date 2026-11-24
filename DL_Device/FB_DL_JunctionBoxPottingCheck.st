(*
  FB_DL_JunctionBoxPottingCheck  —  接线盒灌胶量与固化判定 / Junction box potting quantity and cure check
  分类 Category : DL_Device
  码位 Code     : 16#03_2_14
  段位说明      : 03_2 段低半字节 00~0F 已满（05 为历史空穴留存），进位 14 段续号（R192）
  版本 Version  : 1.0.0
  来源 Source   : t2-1-lgf-technology — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : clean-room 实现，灌胶积分与固化当量公开工艺语义，未复制任何源码行
                  （积分用内部等价实现承载 FB_DL_Integrator 语义；温度域契约对齐 I_DL_TemperatureZone）
  功能 Function : 1) 灌胶量 = 流量对时间积分（DL_TICK 节拍窗离散积分）得 mL，与 fGlueTargetMl ± fGlueTolPct 比较；
                  2) 固化当量 = Σ(max(T − fCureTempMinC, 0) × Δt) 累积 [°C·min]，达 fCureDoseMinCmin 判固化完成；
                  3) 灌胶判据与固化判据独立记账：bGlueOk / bCureOk 不互相覆盖，bCycleOk 仅在两者皆真时为真。
  边界 Boundary : ① fGlueFlowLpm < 0（负流量 = 倒吸）判传感器故障置码进 Fault；
                  ② fGlueTargetMl <= 0 / fCureDoseMinCmin <= 0 / fCureTempMaxC <= fCureTempMinC / 容差 <= 0 判组态错
                     （fCureTempMinC 高于环境上限将永不固化，规格强制）；
                  ③ 超 tCureMax 置 bCureOk := FALSE 并进 Fault（固化超时升级）；
                  ④ 积分节拍窗 DL_TICK 内恒定流量近似（离散积分语义，头注释声明）；
                  ⑤ 解除式自证：Fault 解除 = bReset AND bCycleStart 新上升沿（eState 回 Dose，引脚可满足）；
                  ⑥ CASE 全态覆盖 + ELSE 兜底置故障相。
  依赖 Depends  : I_DL_TemperatureZone（注入，只读属性，不实例化）；积分语义对齐 FB_DL_Integrator（已注册，不实例化）
  码表 Error codes（本件格 03_2_14，子码步进 +0x100）:
    16#0003_0114 信息级：灌胶量达标，Dose 相切换至 Cure 相
    16#0003_0214 故障级：组态非法（目标量/当量下限 <= 0 / 温域倒置 / 容差 <= 0），锁存至复位
    16#0003_0314 故障级：负流量（倒吸）传感器故障，锁存至复位
    16#0003_0414 故障级：固化超时 tCureMax（bCureOk = FALSE）
    16#0003_0514 故障级：状态机落 ELSE 兜底（非法相位 ID）

  修订历史 Revision :
    2026-11-18  v1.0.0  R38 首版
*)

TYPE E_DL_PottingState :
(
    eDose  := 0,    // 灌胶相：流量积分进行中 / Dose, flow integrating
    eCure  := 10,   // 固化相：当量累积进行中 / Cure, equivalent accumulating
    eDone  := 20,   // 完成相：双判据落定 / Done, both verdicts settled
    eFault := 90    // 故障相：组态/倒吸/超时锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_JunctionBoxPottingCheck
VAR_INPUT
    bCycleStart    : BOOL := FALSE;       // 周期启动（上升沿）/ Cycle start
    fGlueFlowLpm   : REAL := 0.0;         // 灌胶流量 [L/min] / Glue flow rate
    fGlueTargetMl  : REAL := 50.0;        // 灌胶目标量 [mL]，域 > 0 / Target dosed volume
    fGlueTolPct    : REAL := 5.0;         // 灌胶容差 [%]，域 > 0 / Dose tolerance
    fCureTempMinC  : REAL := 25.0;        // 固化有效温度下限 [°C] / Cure effective temperature floor
    fCureTempMaxC  : REAL := 80.0;        // 环境/工艺温度上限 [°C]，须 > 下限 / Ambient ceiling, must exceed floor
    fCureDoseMinCmin : REAL := 500.0;     // 固化当量下限 [°C·min]，域 > 0 / Cure equivalent floor
    tCureMax       : TIME := T#3600S;     // 固化最长时限 [ms]，域 > 0 / Cure maximum duration
    bReset         : BOOL := FALSE;       // 复位（Fault 解除路径之一）/ Reset
END_VAR
VAR_OUTPUT
    fGlueDosedMl   : REAL;                // 灌胶量 [mL] / Dosed volume
    fCureDoseCmin  : REAL;                // 固化当量 [°C·min] / Cure equivalent
    bGlueOk        : BOOL;                // 灌胶判据（独立记账）/ Glue verdict, independent bookkeeping
    bCureOk        : BOOL;                // 固化判据（独立记账）/ Cure verdict, independent bookkeeping
    bCycleOk       : BOOL;                // 周期合格（两者皆真）/ Cycle ok, both true
    nErrId         : UDINT;               // 事件码，0 = 无事件 / Event code
    eState         : E_DL_PottingState;   // 状态出口，段尾单点映射 / State outlet
END_VAR
VAR_IN_OUT
    iTempZone : I_DL_TemperatureZone;     // 温区引用（注入，只读属性）/ Temperature zone reference
END_VAR
VAR
    tonTick    : TON;                     // 积分节拍窗，自复位（段 0 无条件刷新）/ Integration tick window, self-resetting
    tonCure    : TON;                     // 固化超时计时，段 0 无条件刷新 / Cure timeout timer
    tonFaultWch: TON;                     // 故障观察窗，自复位 / Fault watch window, self-resetting
    rtStart    : R_TRIG;                  // 周期启动上升沿 / Cycle start rising edge
    rtReset    : R_TRIG;                  // 复位上升沿 / Reset rising edge
    _bTickBrk  : BOOL;                    // 节拍窗断输入请求（自复位范式，R182 同族）/ Tick break request
    _eState    : E_DL_PottingState := E_DL_PottingState.eDose;   // 内部相位（CASE 唯一写入目标）/ Internal phase
    _rTempC    : REAL;                    // 温区实测温度 [°C] / Zone actual temperature
    _rVolRate  : REAL;                    // 流量换算暂存 [mL/s] / Volume rate scratch
    _rTolMl    : REAL;                    // 容差换算暂存 [mL] / Tolerance scratch
    _uFault    : UDINT;                   // 故障码锁存 / Latched fault code
    _uInfo     : UDINT;                   // 信息码，每拍重算 / Info code
    _bFault    : BOOL;                    // 故障锁存位 / Latched fault bit
    _bCfgBad   : BOOL;                    // 组态非法聚合 / Configuration invalid aggregate
    _bGlueHold : BOOL;                    // 灌胶判据保持量（独立记账）/ Glue verdict held quantity
    _bCureHold : BOOL;                    // 固化判据保持量（独立记账）/ Cure verdict held quantity
    _bCureMax  : BOOL;                    // 固化超时保持量 / Cure timeout held quantity
END_VAR
VAR CONSTANT
    DL_TICK    : TIME := T#100MS;   // 积分节拍窗 [ms]（离散积分步长）/ Integration tick window
    DL_LPM2MLS : REAL := 16.6667;   // L/min → mL/s 换算系数 / Litres-per-minute to mL-per-second factor
    rFinLim    : REAL := 1.0E15;    // 非有限值筛查幅值上限 / Non-finite screening cap
    DL_WatchPt : TIME := T#2S;      // 故障观察窗 [ms]，自复位 / Fault watch window
END_VAR

(* —— 段 0：定时器与边沿无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
rtStart(CLK := bCycleStart);                                    // 周期启动上升沿，每拍必调
rtReset(CLK := bReset);                                         // 复位上升沿，每拍必调
tonFaultWch(IN := (NOT tonFaultWch.Q), PT := DL_WatchPt);       // 观察窗自复位（表达式入参）
tonTick(IN := (NOT tonTick.Q) AND (NOT _bTickBrk), PT := DL_TICK);   // 节拍窗自复位（表达式入参，禁外部沿清零）
_bTickBrk := FALSE;                                             // 断输入拍在调用后自清（R188 范式）
tonCure(IN := (_eState = E_DL_PottingState.eCure), PT := tCureMax);  // 固化超时（表达式入参，相位条件不写进 IF）

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault/_bGlueHold/_bCureHold/_bCureMax/_rVolRate 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;         // 信息码每拍重算
_bCfgBad := FALSE;              // 组态非法预清零
nErrId := 16#0000_0000;         // 事件码缺省无事件

(* —— 段 2：组态域闸（覆盖全部参与判据换算的引脚，R151） —— *)
IF (fGlueTargetMl <> fGlueTargetMl) OR (fGlueTargetMl <= 0.0) OR (ABS(fGlueTargetMl) > rFinLim) THEN
    _bCfgBad := TRUE;           // 目标量非法
END_IF
IF (fGlueTolPct <= 0.0) OR (fCureDoseMinCmin <= 0.0) THEN
    _bCfgBad := TRUE;           // 容差/当量下限非法（防除零）
END_IF
IF fCureTempMaxC <= fCureTempMinC THEN
    _bCfgBad := TRUE;           // 温域倒置：固化下限高于环境上限将永不固化（规格强制）
END_IF
IF TIME_TO_DINT(tCureMax) <= 0 THEN
    _bCfgBad := TRUE;           // 超时非法
END_IF

(* —— 段 3：复位沿（Fault 解除式：bReset，eState 回 Dose 等新上升沿） —— *)
IF rtReset.Q THEN
    IF (NOT _bCfgBad) THEN
        _bFault := FALSE;       // 清故障锁存位
        _uFault := 16#0000_0000;
        _eState := E_DL_PottingState.eDose;   // 回灌胶相（等 bCycleStart 新上升沿）
    END_IF
END_IF

(* —— 段 4：温区只读采集 + 节拍窗离散积分（窗内恒定近似，头注释声明） —— *)
_rTempC := iTempZone.fTempActual;       // 实测温度 [°C]（只读属性）
IF tonTick.Q THEN
    _bTickBrk := TRUE;                  // 断输入请求：下一拍窗重开（自复位范式）
    _rVolRate := fGlueFlowLpm * DL_LPM2MLS;                  // [mL/s]（负值即倒吸，段 5 判）
    fGlueDosedMl := fGlueDosedMl + _rVolRate * (TIME_TO_REAL(DL_TICK) / 1000.0);   // 流量积分 [mL]
    fCureDoseCmin := fCureDoseCmin + MAX(_rTempC - fCureTempMinC, 0.0)
                     * (TIME_TO_REAL(DL_TICK) / 60000.0);                     // 当量积分 [°C·min]
END_IF

(* —— 段 5：相位机（只做迁移与判据记账；出口在段 8） —— *)
CASE _eState OF

E_DL_PottingState.eDose:
    IF _bCfgBad THEN
        _uFault := 16#0003_0214;        // 故障级：组态非法
        _bFault := TRUE;                // 锁存（复位沿可清）
        _eState := E_DL_PottingState.eFault;
    ELSIF fGlueFlowLpm < 0.0 THEN
        _uFault := 16#0003_0314;        // 故障级：负流量倒吸（传感器故障）
        _bFault := TRUE;
        _eState := E_DL_PottingState.eFault;
    ELSE
        _rTolMl := fGlueTargetMl * fGlueTolPct / 100.0;     // 容差 [mL]
        IF fGlueDosedMl >= (fGlueTargetMl - _rTolMl) THEN
            IF fGlueDosedMl <= (fGlueTargetMl + _rTolMl) THEN
                _bGlueHold := TRUE;     // 灌胶判据记账：达标（独立，不覆盖固化）
                _uInfo := 16#0003_0114; // 信息级：灌胶量达标
            ELSE
                _bGlueHold := FALSE;    // 过量超容差：判不合格
            END_IF
            _eState := E_DL_PottingState.eCure;   // 切固化相（量已定，不再积分判定）
        END_IF
    END_IF

E_DL_PottingState.eCure:
    IF fCureDoseCmin >= fCureDoseMinCmin THEN
        _bCureHold := TRUE;             // 固化判据记账：达标（独立，不覆盖灌胶）
        _eState := E_DL_PottingState.eDone;   // 进完成相
    ELSIF tonCure.Q THEN
        _uFault := 16#0003_0414;        // 故障级：固化超时（bCureOk = FALSE，规格强制）
        _bFault := TRUE;
        _bCureHold := FALSE;            // 固化判据显式记账为不合格
        _eState := E_DL_PottingState.eFault;
    END_IF

E_DL_PottingState.eDone:
    ;                                   // 完成相：判据已落定，等新周期（bCycleOk 段 8 出口）

E_DL_PottingState.eFault:
    ;                                   // 故障相：等复位沿（段 3 承载解除）

ELSE
    _uFault := 16#0003_0514;            // 故障级：非法相位 ID 兜底
    _bFault := TRUE;                    // 锁存
    _eState := E_DL_PottingState.eFault;// 强制回故障相

END_CASE

(* —— 段 7：出口单点映射（名实同源；独立记账，禁互相覆盖） —— *)
bGlueOk  := _bGlueHold AND (NOT _bCfgBad);      // 灌胶判据出口（独立）
bCureOk  := _bCureHold AND (NOT _bCfgBad);      // 固化判据出口（独立）
bCycleOk := bGlueOk AND bCureOk;                // 周期合格：两者皆真
IF _bCfgBad THEN
    nErrId := 16#0003_0214;         // 故障级：组态非法（每拍重申，复位沿清）
    _bFault := TRUE;
ELSIF fGlueFlowLpm < 0.0 THEN
    nErrId := 16#0003_0314;         // 故障级：负流量（锁存语义由 Fault 相承载）
    _bFault := TRUE;
END_IF
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放（不在故障相按当下输入重推）
    bGlueOk  := FALSE;              // 故障相判据出口撤销（安全侧）
    bCureOk  := FALSE;
    bCycleOk := FALSE;
END_IF
eState := _eState;                  // 状态出口单点映射

END_FUNCTION_BLOCK
