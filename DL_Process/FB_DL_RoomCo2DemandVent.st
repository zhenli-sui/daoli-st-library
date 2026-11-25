(*
  FB_DL_RoomCo2DemandVent  —  CO₂ 需量通风与新风阀联动 / Room CO2 demand-controlled ventilation
  分类 Category : DL_Process
  码位 Code     : 16#06_0_BC
  段位说明      : R38 W7 预留 B6~BF 本轮正式启用，BB 格由 WaferBreakDetect 启用，本件启用 BC 格
  版本 Version  : 1.0.0
  来源 Source   : t1-2-oscat-building — 楼控需量通风待挖项
  溯源 Origin   : clean-room 实现，DCV 公开控制语义借鉴，未复制任何源码行
                  （与 FB_DL_RoomClimateCtrl 分工：那件管温湿双回路，本件只管浓度需量回路）
  功能 Function : 1) 浓度标定：传感器原始量经 FC_DL_LinearScale 换算 ppm（零点/满量程组态）；
                  2) 需量闭环：FB_DL_PidController 浓度回路，输出新风阀开度 [%]；
                  3) 最小新风位硬下限：PID 输出域下限 = fMinDamperPct（卫生新风硬约束，非软偏好）；
                  4) 传感器失效退守：换算无效或 ppm 越合理域持续 tSensFailTo → eFailSafe 模式，
                  阀门定 fFailSafePct（故障级锁存，bReset 解除）；
                  5) 需量高峰指示：FC_DL_Hysteresis 浓度超需求阈迟滞判定（诊断随行）。
  边界 Boundary : ① 本件只出阀门开度指令 fDamperCmdPct，不写物理 IO（由上层 PRG_IoMapping 承载）；
                  ② 合理域上限 fPlausHiPpm 组态（典型 5000 ppm）：退守判据之一，防传感器漂移误控；
                  ③ R228-A 达标声明：tonSensTo 单用途计时（IN = 失效判据电平），无跨相复用问题；
                  ④ R228-B 达标声明：eFault 迁出 = rtReset.Q（输入引脚，恒可达），逐字写于此；
                  ⑤ 组态域闸覆盖全部参与换算引脚（R151）；标定量/域/阈值非法判组态错锁存；
                  ⑥ 模式 CASE 为计算型分类（eAuto/eFailSafe），含 ELSE 兜底。
  依赖 Depends  : FC_DL_LinearScale / FC_DL_Hysteresis（函数调用，引脚按 registry 实名）；
                  FB_DL_PidController（实例化，引脚按 registry 实名）
  码表 Error codes（本件格 06_0_BC，子码步进 +0x100）:
    16#0006_01BC 信息级：需量高峰（bDemandHigh 置位拍）
    16#0006_02BC 故障级：组态非法（标定量/域/阈值/退守值域非法），锁存至复位
    16#0006_03BC 故障级：传感器失效退守（eFailSafe，阀门定 fFailSafePct），锁存至复位
    16#0006_04BC 信息级：浓度换算无效（LinearScale bValid = FALSE，瞬时口径）
    16#0006_05BC 故障级：保留码，本件无 CASE 主状态机，仅作后续维护者新增分支时的防御式默认码
    16#0006_06BC 信息级：退守模式阀门指令已定值（eFailSafe 拍）
    16#0006_07BC 故障级：模式 CASE 落 ELSE 兜底（非法模式 ID，防御口径）

  修订历史 Revision :
    2026-11-19  v1.0.0  R39 首版（批次 4 · 序号 20）
*)

TYPE E_DL_Co2VentMode :
(
    eAuto     := 0,    // 自动：PID 需量闭环 / Auto, PID demand loop
    eFailSafe := 10,   // 退守：传感器失效，阀门定值 / Fail-safe, sensor failed, damper fixed
    eFault    := 90    // 组态故障锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_RoomCo2DemandVent
VAR_INPUT
    fCo2Raw      : REAL := 0.0;       // 传感器原始量 [raw]（换算源）/ Raw sensor value
    fRawZero     : REAL := 0.0;       // 标定零点原始量 [raw]（对应 0 ppm）/ Raw at zero ppm
    fRawSpan     : REAL := 4000.0;    // 标定跨度原始量 [raw]（对应 fSpanPpm）/ Raw span to full-scale ppm
    fSpanPpm     : REAL := 5000.0;    // 满量程浓度 [ppm]，域 > 0 / Full-scale ppm
    fCo2SpPpm    : REAL := 900.0;     // 浓度设定值 [ppm]，域 > 0 / CO2 setpoint
    fKp          : REAL := 0.05;      // 需量回路比例增益 [%/ppm] / Demand loop proportional gain
    tTi          : TIME := T#300S;    // 需量回路积分时间 [s] / Demand loop integral time
    fMinDamperPct: REAL := 10.0;      // 最小新风位硬下限 [%]，域 [0, fMaxDamperPct) / Minimum outdoor-air hard floor
    fMaxDamperPct: REAL := 100.0;     // 新风阀开度上限 [%]，域 <= 100 / Damper upper limit
    fFailSafePct : REAL := 30.0;      // 退守模式定值开度 [%]，域 [fMinDamperPct, fMaxDamperPct] / Fail-safe fixed opening
    fPlausHiPpm  : REAL := 5000.0;    // 合理域上限 [ppm]，域 > fCo2SpPpm / Plausibility ceiling
    fDemandThPpm : REAL := 1100.0;    // 需量高峰判定阈 [ppm] / Demand-high threshold
    fDemandHystPpm: REAL := 100.0;    // 需量高峰回差带 [ppm]，域 > 0 / Demand-high hysteresis band
    tSensFailTo  : TIME := T#10S;    // 传感器失效确认时长 [ms]，域 > 0 / Sensor failure confirm time
    bEnable      : BOOL := TRUE;      // 总使能，FALSE 时阀门指令归零 [-] / Master enable
    bReset       : BOOL := FALSE;     // 故障复位，上升沿生效 / Fault reset, rising edge
END_VAR
VAR_OUTPUT
    fCo2Ppm      : REAL;              // 换算浓度 [ppm]（失效时保持）/ Converted CO2 concentration
    fDamperCmdPct: REAL;              // 新风阀开度指令 [%]（上层消费）/ Damper command output
    bSensorFail  : BOOL;              // 传感器失效锁存 [-] / Sensor failure latch
    bDemandHigh  : BOOL;              // 需量高峰（迟滞判定）[-] / Demand-high flag
    eMode        : E_DL_Co2VentMode;  // 模式出口，段尾单点映射 / Mode outlet
    bError       : BOOL;              // 故障锁存，仅故障级码置位，bReset 清除 [-] / Fault latch
    uErrorId     : UDINT;             // 事件码，0 = 无事件（故障级锁存回放）/ Event code
END_VAR
VAR
    fbPid      : FB_DL_PidController; // 需量回路 PID 实例（主体首部无条件刷新）/ Demand loop PID instance
    tonSensTo  : TON;                 // 传感器失效确认计时（单用途，R228-A 口径）/ Sensor failure confirm timer, single purpose
    rtReset    : R_TRIG;              // 复位上升沿 / Reset rising edge
    _fPpmRaw   : REAL;                // 换算浓度中间量 [ppm] / Converted ppm working value
    _bScaleOk  : BOOL;                // 换算有效标志 / Scaling valid flag
    _bScaleClp : BOOL;                // 换算钳位标志 / Scaling clamped flag
    _fScaleErr : REAL;                // 换算百分比中间量 [%]（件出口 fPercent，未消费占位）/ Scaling percent passthrough
    _uScaleErr : UDINT;               // 换算错误码透传 / Scaling error passthrough
    _bPlausBad : BOOL;                // 本拍合理域越限标志 / Plausibility violation this cycle
    _bSensorFail : BOOL := FALSE;     // 传感器失效锁存镜像（与 bSensorFail 同源同拍）[-] / Sensor-fail latch mirror, same source as bSensorFail
    _bDemandSt : BOOL;                // 需量高峰迟滞回传保持变量 / Demand-high hysteresis hold member
    _eModeInt  : E_DL_Co2VentMode := E_DL_Co2VentMode.eAuto;   // 内部模式（CASE 唯一写入目标）/ Internal mode
    _rCmdOut   : REAL := 0.0;         // 阀门指令中间量 [%] / Damper command working value
    _uInfo     : UDINT;               // 信息码，每拍重算 / Info code
    _uFault    : UDINT;               // 故障码锁存寄存 / Latched fault code register
    _bFault    : BOOL;                // 故障锁存位 / Latched fault bit
    _bCfgBad   : BOOL;                // 组态非法聚合 / Configuration invalid aggregate
    _fHystUp   : REAL;                // 迟滞上限实阈透传（未消费占位，仅满足 FC 全参数口径）/ Hysteresis upper trip passthrough
    _fHystLo   : REAL;                // 迟滞下限实阈透传（未消费占位，仅满足 FC 全参数口径）/ Hysteresis lower trip passthrough
    _uHystErr  : UDINT;               // 迟滞件错误码透传（供诊断扩展，本拍不判级）/ Hysteresis error code passthrough
END_VAR
VAR CONSTANT
    DL_RCV_INF_CAP : REAL := 1.0E15;  // 非有限值筛查幅值上限 / Non-finite screening cap
END_VAR

(* —— 段 0：定时器与边沿实例无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
rtReset(CLK := bReset);                                 // 复位沿刷新，每拍必调
tonSensTo(IN := _bPlausBad OR (NOT _bScaleOk), PT := tSensFailTo);   // 失效确认计时（失效判据电平，单用途）

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault/_bDemandSt/_eModeInt 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
_bCfgBad := FALSE;                  // 组态非法预清零
_bPlausBad := FALSE;                // 合理域越限预清零（段 3 单点置位）
uErrorId := 16#0000_0000;           // 事件码缺省无事件

(* —— 段 2：组态域闸（覆盖全部参与判据换算的引脚，R151） —— *)
IF (fRawSpan <= 0.0) OR (ABS(fRawSpan) > DL_RCV_INF_CAP)
   OR (fSpanPpm <= 0.0) OR (fCo2SpPpm <= 0.0)
   OR (fMinDamperPct < 0.0) OR (fMinDamperPct >= fMaxDamperPct) OR (fMaxDamperPct > 100.0)
   OR (fFailSafePct < fMinDamperPct) OR (fFailSafePct > fMaxDamperPct)
   OR (fPlausHiPpm <= fCo2SpPpm) OR (fDemandThPpm <= fCo2SpPpm)
   OR (fDemandHystPpm <= 0.0) OR (TIME_TO_DINT(tSensFailTo) <= 0)
   OR (fCo2Raw <> fCo2Raw) OR (ABS(fCo2Raw) > DL_RCV_INF_CAP) OR ((fCo2Raw - fCo2Raw) <> 0.0) THEN
    _bCfgBad := TRUE;               // 标定量/域/阈值/退守值域非法
END_IF

(* —— 段 3：浓度换算（FC_DL_LinearScale 原子）与合理域判定 —— *)
_fPpmRaw := FC_DL_LinearScale(fIn := fCo2Raw,           // 传感器原始量
                              fInMin := fRawZero,       // 零点原始量
                              fInMax := fRawZero + fRawSpan,    // 满量程原始量
                              fOutMin := 0.0,           // 0 ppm
                              fOutMax := fSpanPpm,      // 满量程 ppm
                              bClamp := FALSE,          // 不钳位：越合理域由退守判据承载
                              bValid => _bScaleOk,      // 换算有效标志
                              bClamped => _bScaleClp,   // 钳位标志
                              fPercent => _fScaleErr,   // 百分比出口（未消费）
                              uErrorId => _uScaleErr);  // 错误码透传
IF (NOT _bScaleOk) OR (_uScaleErr <> 0) THEN
    _uInfo := 16#0006_04BC;         // 信息级：换算无效（瞬时口径）
END_IF
IF _bScaleOk AND ((_fPpmRaw < 0.0) OR (_fPpmRaw > fPlausHiPpm)) THEN
    _bPlausBad := TRUE;             // 合理域越限（负值或超上限：传感器漂移/失效嫌疑）
END_IF
IF _bScaleOk AND (NOT _bPlausBad) THEN
    fCo2Ppm := _fPpmRaw;            // 浓度出口更新（有效口径）
END_IF
(* 失效保持口径：bSensorFail 期间 fCo2Ppm 保持最后有效值，不在失效拍改写 *)

(* —— 段 4：故障锁存与迁出沿（R228-B：rtReset.Q 恒可达） —— *)
IF _bCfgBad AND (NOT _bFault) THEN
    _uFault := 16#0006_02BC;        // 故障级：组态非法（仅首次进入时写入）
    _bFault := TRUE;
END_IF
IF tonSensTo.Q AND (NOT _bSensorFail) THEN
    bSensorFail := TRUE;            // 传感器失效锁存（退守判据到点）
    _bSensorFail := TRUE;           // 锁存镜像同拍置位（防止重复进入失效段）
    _uFault := 16#0006_03BC;        // 故障级：传感器失效退守
    _bFault := TRUE;
END_IF
IF rtReset.Q AND (NOT _bCfgBad) AND _bScaleOk AND (NOT _bPlausBad) THEN
    IF bSensorFail THEN
        bSensorFail := FALSE;       // 失效锁存解除（信号恢复 + 组态合法为前提）
        _bSensorFail := FALSE;      // 锁存镜像同步解除（名实同源）
    END_IF
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;
END_IF

(* —— 段 5：需量高峰判定（迟滞；失效期间冻结） —— *)
IF (NOT bSensorFail) AND (NOT _bFault) THEN
    bDemandHigh := FC_DL_Hysteresis(fIn := fCo2Ppm,             // 换算浓度
                                    fThreshold := fDemandThPpm, // 高峰阈
                                    fHysteresis := fDemandHystPpm,   // 回差带
                                    bState := _bDemandSt,       // 回传保持变量（同一成员，有状态纪律）
                                    fUpperTrip => _fHystUp,     // 实阈上限透传（FC 全参数口径，R74 补齐）
                                    fLowerTrip => _fHystLo,     // 实阈下限透传（FC 全参数口径，R74 补齐）
                                    uErrorId => _uHystErr);     // 迟滞件错误码透传（FC 全参数口径，R74 补齐）
    IF bDemandHigh THEN
        _uInfo := 16#0006_01BC;     // 信息级：需量高峰
    END_IF
END_IF

(* —— 段 6：PID 无条件刷新（自动口径：失效/故障/失能时 PID 复位并闭锁） —— *)
fbPid(bEnable := bEnable AND (NOT bSensorFail) AND (NOT _bFault),   // 自动口径使能门控
      fSetpoint := fCo2SpPpm,       // 浓度设定
      fActual := fCo2Ppm,           // 换算浓度
      fKp := fKp,                   // 比例增益（正作用：浓度高 → 开度大）
      tTi := tTi,                   // 积分时间
      tTd := T#0S,                  // 微分关
      rOutMin := fMinDamperPct,     // 最小新风位硬下限（PID 输出域承载）
      rOutMax := fMaxDamperPct,     // 开度上限
      tSampleTime := T#1S,          // 采样周期（需量回路慢口径）
      bTrack := bSensorFail,        // 失效期间跟踪退守值（无扰返回）
      fTrackValue := fFailSafePct,  // 跟踪值 = 退守定值
      bReset := bSensorFail);       // 失效拍复位 PID 内部（防积分陈化）

(* —— 段 7：模式 CASE（计算型分类，含 ELSE 兜底）与阀门指令合成 —— *)
CASE _eModeInt OF

E_DL_Co2VentMode.eAuto:
    IF _bFault AND bSensorFail THEN
        _eModeInt := E_DL_Co2VentMode.eFailSafe;    // 失效锁存：进退守模式
    ELSIF _bFault AND (NOT bSensorFail) THEN
        _eModeInt := E_DL_Co2VentMode.eFault;       // 组态故障：进故障模式
    END_IF

E_DL_Co2VentMode.eFailSafe:
    _uInfo := 16#0006_06BC;         // 信息级：退守阀门定值（相内重申）
    IF (NOT bSensorFail) AND (NOT _bFault) THEN
        _eModeInt := E_DL_Co2VentMode.eAuto;        // 失效解除：回自动模式
    END_IF

E_DL_Co2VentMode.eFault:
    IF NOT _bFault THEN
        _eModeInt := E_DL_Co2VentMode.eAuto;        // 故障解除：回自动模式
    END_IF

ELSE
    _uFault := 16#0006_07BC;        // 故障级：非法模式 ID 兜底
    _bFault := TRUE;
    _eModeInt := E_DL_Co2VentMode.eFailSafe;    // 防御口径：强制退守

END_CASE

(* —— 段 8：阀门指令合成（名实同源） —— *)
IF NOT bEnable THEN
    _rCmdOut := 0.0;                // 失能：指令归零
ELSIF _eModeInt = E_DL_Co2VentMode.eFailSafe THEN
    _rCmdOut := fFailSafePct;       // 退守：定值开度（卫生新风保守侧）
ELSIF _eModeInt = E_DL_Co2VentMode.eFault THEN
    _rCmdOut := 0.0;                // 组态故障：指令归零（安全侧）
ELSE
    _rCmdOut := fbPid.fOut;         // 自动：PID 输出（域已含硬下限/上限）
END_IF
fDamperCmdPct := _rCmdOut;          // 指令出口镜像

(* —— 段 9：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
eMode := _eModeInt;                 // 模式出口单点映射
IF _bFault THEN
    uErrorId := _uFault;            // 故障锁存码回放（不在故障态按当下输入重推）
    bError := TRUE;
ELSE
    uErrorId := _uInfo;             // 信息码
    bError := FALSE;
END_IF

END_FUNCTION_BLOCK
