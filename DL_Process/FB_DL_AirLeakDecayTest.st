(*
  组件名 Component   : FB_DL_AirLeakDecayTest
  子库 Sublibrary    : DL_Process
  版本 Version       : 1.0.0
  兼容性 Platform    : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert（仅 Standard.library）
  功能 Function      : 气密压降法泄漏测试（与 FC 氦检分工：空气压降 vs 氦质谱）：
                       1) 三段顺控：充压（eCharge，出充压指令至测试压力确认）→
                       稳压（eStabilize，驻留 tStabDur 待温度平衡）→ 测量（eMeasure，
                       驻留 tMeasDur，窗始/窗末压力双快照）；
                       2) 温度补偿：绝对温标折算，压降补偿值 =
                       p1 - p2 × (T1/T2)，T 为绝对温度（摄氏度 + 开尔文偏置）；
                       3) 泄漏率换算判级：泄漏率 = 补偿压降 × 容积 / 测量时长，
                       <= fLeakLim 判合格，否则不合格；
                       4) 测量段压力跌破 fPressMinPa → 充压丢失故障锁存。
  边界 Boundary      : ① 本件只出充压指令与测试结论，不写物理 IO；
                       ② 除法前置域闸：测量时长秒值下限 1.0 s、绝对温度下限
                       1.0 K、容积 > 0（组态闸承载）；
                       ③ 各相计时独立 TON 实例（禁跨相复用）；窗始快照进相首拍
                       写定，锁存回放不重扫；
                       ④ 故障锁存解除唯一路径 = bReset 上升沿（输入引脚，恒可达）；
                       ⑤ 无全局变量引用、无外部变量声明、无物理地址寻址。
  依赖 Depends       : Standard.library（R_TRIG / TON）
  溯源 Origin        : 道莅自研 clean-room（自研行业池：通用质量工装气密检测
                       共性语义，零外部代码行复制）
  码位 Code          : 16#06_0_C2（Process 段 0006，C 子带 C2 格）
  码表 Error codes（本件格 06_0_C2，单轨子道：故障 0x02C2 / 信息 0x01C2）:
    16#0006_02C2 故障级：气密测试故障总码（充压超时 / 测量段压力跌破下限 /
                 组态非法 / 输入非有限），锁存至复位
    16#0006_01C2 信息级：测试结论写定沿（合格或不合格判定拍）
  修订历史 Revision  :
    2026-11-19  v1.0.0  R44 首版（批次 4 · 序号 19）
*)

TYPE E_DL_AltPhase :
(
    eIdle      := 0,   // 空闲：等测试沿 / Idle, waiting test edge
    eCharge    := 10,  // 充压：至测试压力确认 / Charging to test pressure
    eStabilize := 20,  // 稳压：温度平衡驻留 / Stabilizing dwell
    eMeasure   := 30,  // 测量：双快照驻留 / Measuring dwell
    eDone      := 40,  // 完成：结论驻留 / Done, verdict held
    eFault     := 90   // 故障：总码锁存 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_AirLeakDecayTest
VAR_INPUT
    bEnable      : BOOL;                   // 使能（电平）[-] / Enable
    bReset       : BOOL;                   // 上升沿清故障锁存 [-] / Reset edge
    bTestCmd     : BOOL;                   // 测试指令（上升沿承载）[-] / Test command edge
    fPressPa     : REAL;                   // 腔体实测压力 [帕斯卡] / Measured pressure
    fTempC       : REAL;                   // 腔体实测温度 [摄氏度] / Measured temperature
    fTestPressPa : REAL := 500000.0;       // 测试压力 [帕斯卡] / Test pressure
    fPressMinPa  : REAL := 400000.0;       // 测量段压力下限 [帕斯卡] / Measurement pressure floor
    fVolumeL     : REAL := 10.0;           // 腔体容积 [升] / Cavity volume
    fLeakLimPaLs : REAL := 1.0;            // 泄漏率合格限 [帕·升/秒] / Leak rate pass limit
    tStabDur     : TIME := T#60S;          // 稳压驻留 [毫秒] / Stabilization dwell
    tMeasDur     : TIME := T#120S;         // 测量驻留 [毫秒] / Measurement dwell
    tChargeTo    : TIME := T#120S;         // 充压超时 [毫秒] / Charge timeout
END_VAR
VAR_OUTPUT
    bChargeCmd   : BOOL;                   // 充压指令输出 [-] / Charge command output
    bTestPass    : BOOL;                   // 结论：合格 [-] / Verdict pass flag
    fLeakRatePaLs: REAL;                   // 实测泄漏率 [帕·升/秒] / Measured leak rate
    fDpCompPa    : REAL;                   // 温度补偿压降 [帕斯卡] / Compensated pressure drop
    ePhase       : E_DL_AltPhase;          // 相位出口，段尾单点映射 / Phase outlet
    bError       : BOOL;                   // 故障锁存标志 [-] / Fault latch flag
    uErrId       : UDINT;                  // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    rtReset: R_TRIG;                       // 复位沿实例，段 0 无条件刷新 / Reset edge
    rtTest : R_TRIG;                       // 测试沿实例，段 0 无条件刷新 / Test edge
    tonStabDur: TON;                       // 稳压驻留计时（独立实例） / Stabilization timer
    tonMeasDur: TON;                       // 测量驻留计时（独立实例） / Measurement timer
    tonChargeTo: TON;                      // 充压超时（专用超时件命名） / Charge timeout
    _ePhase: E_DL_AltPhase := E_DL_AltPhase.eIdle;     // 内部相位（CASE 唯一写入目标）/ Internal phase
    _fP1Pa : REAL;                         // 窗始压力快照 [帕斯卡] / Window-start pressure snapshot
    _fT1C  : REAL;                         // 窗始温度快照 [摄氏度] / Window-start temperature snapshot
    _bSnapDone: BOOL;                      // 窗始快照已取标志 [-] / Snapshot taken flag
    _fT1K  : REAL;                         // 窗始绝对温度 [开尔文] / Window-start absolute temperature
    _fT2K  : REAL;                         // 窗末绝对温度 [开尔文] / Window-end absolute temperature
    _bFault: BOOL;                         // 故障锁存位（锁存量） / Latched fault bit
    _uFault: UDINT;                        // 故障码锁存（锁存量） / Latched fault code
    _bCfgBad: BOOL;                        // 组态非法当拍量 [-] / Config illegal flag
    _bNonFin: BOOL;                        // 输入非有限当拍量 [-] / Non-finite input flag
END_VAR
VAR CONSTANT
    DL_KELVIN_OFF : REAL := 273.15;        // 开尔文偏置 [开尔文] / Kelvin offset
    DL_T_ABS_MIN  : REAL := 1.0;           // 绝对温度下限 [开尔文] / Absolute temperature floor
    DL_MEAS_MIN_S : REAL := 1.0;           // 测量时长秒值下限 [秒] / Measurement seconds floor
    DL_MS_PER_S   : REAL := 1000.0;        // 毫秒 → 秒换算系数 [毫秒/秒] / Milliseconds per second
    DL_ABS_MAX    : REAL := 1.0E30;        // 有限值判定上界 [工程单位] / Finite bound
    DL_ZERO       : REAL := 0.0;           // 零常量 [工程单位] / Zero constant
END_VAR

(* —— 段 0｜沿与定时器每拍无条件刷新（禁置于 IF/CASE 内；各相独立实例禁复用） —— *)
rtReset(CLK := bReset);
rtTest (CLK := bTestCmd);
tonStabDur (IN := (_ePhase = E_DL_AltPhase.eStabilize) AND (NOT _bFault), PT := tStabDur);
tonMeasDur (IN := (_ePhase = E_DL_AltPhase.eMeasure) AND (NOT _bFault), PT := tMeasDur);
tonChargeTo(IN := (_ePhase = E_DL_AltPhase.eCharge) AND (NOT _bFault), PT := tChargeTo);

(* —— 段 1｜瞬时量预清零（锁存量 _bFault/_uFault/bTestPass/_fP1Pa 不入清单） —— *)
uErrId   := 16#0000_0000;
_bCfgBad := FALSE;
_bNonFin := FALSE;

(* —— 段 2｜复位沿：故障一次性清干净，相位回空闲，充压指令撤销 —— *)
IF rtReset.Q THEN
    _bFault := FALSE;
    _uFault := 16#0000_0000;
    bChargeCmd := FALSE;
    _ePhase := E_DL_AltPhase.eIdle;
END_IF

(* —— 段 3｜组态闸与非有限判据（覆盖全部参与判据换算引脚） —— *)
IF (fTestPressPa <= fPressMinPa) OR (fPressMinPa <= DL_ZERO) OR (fVolumeL <= DL_ZERO)
   OR (fLeakLimPaLs <= DL_ZERO) OR (tStabDur = T#0S) OR (tMeasDur = T#0S)
   OR (tChargeTo = T#0S) THEN
    _bCfgBad := TRUE;
END_IF
IF (fPressPa <> fPressPa) OR ((fPressPa - fPressPa) <> DL_ZERO)
   OR (fTempC <> fTempC) OR ((fTempC - fTempC) <> DL_ZERO) THEN
    _bNonFin := TRUE;
END_IF

(* —— 段 4｜主状态机：六态全覆盖 + ELSE 兜底 —— *)
CASE _ePhase OF

E_DL_AltPhase.eIdle:
    bChargeCmd := FALSE;
    IF rtTest.Q AND bEnable AND (NOT _bFault) AND (NOT _bCfgBad) AND (NOT _bNonFin) THEN
        bTestPass := FALSE;
        fLeakRatePaLs := DL_ZERO;
        fDpCompPa := DL_ZERO;
        _bSnapDone := FALSE;
        _ePhase := E_DL_AltPhase.eCharge;
    ELSIF rtTest.Q AND (_bFault OR _bCfgBad OR _bNonFin) THEN
        _bFault := TRUE;                 // 带病启动拒绝
        _uFault := 16#0006_02C2;
        bError  := TRUE;
        _ePhase := E_DL_AltPhase.eFault;
    END_IF

E_DL_AltPhase.eCharge:
    bChargeCmd := TRUE;
    IF _bNonFin THEN
        _bFault := TRUE;
        _uFault := 16#0006_02C2;
        bError  := TRUE;
        _ePhase := E_DL_AltPhase.eFault;
    ELSIF fPressPa >= fTestPressPa THEN
        bChargeCmd := FALSE;
        _ePhase := E_DL_AltPhase.eStabilize;     // 迁出条件 1：测试压力达成
    ELSIF tonChargeTo.Q THEN
        _bFault := TRUE;                 // 迁出条件 2（故障路）：充压超时
        _uFault := 16#0006_02C2;
        bError  := TRUE;
        bChargeCmd := FALSE;
        _ePhase := E_DL_AltPhase.eFault;
    END_IF

E_DL_AltPhase.eStabilize:
    bChargeCmd := FALSE;
    IF _bNonFin THEN
        _bFault := TRUE;
        _uFault := 16#0006_02C2;
        bError  := TRUE;
        _ePhase := E_DL_AltPhase.eFault;
    ELSIF tonStabDur.Q THEN
        _bSnapDone := FALSE;
        _ePhase := E_DL_AltPhase.eMeasure;   // 稳压驻留完成：进测量相
    END_IF

E_DL_AltPhase.eMeasure:
    bChargeCmd := FALSE;
    IF _bNonFin THEN
        _bFault := TRUE;
        _uFault := 16#0006_02C2;
        bError  := TRUE;
        _ePhase := E_DL_AltPhase.eFault;
    ELSIF fPressPa < fPressMinPa THEN
        _bFault := TRUE;                 // 测量段压力跌破下限：充压丢失
        _uFault := 16#0006_02C2;
        bError  := TRUE;
        _ePhase := E_DL_AltPhase.eFault;
    ELSIF NOT _bSnapDone THEN
        _fP1Pa := fPressPa;              // 窗始双快照：进相首拍写定（锁存回放不重扫）
        _fT1C  := fTempC;
        _bSnapDone := TRUE;
    ELSIF tonMeasDur.Q THEN
        (* 温度补偿判级：绝对温标折算，除子 = 绝对温度/测量时长，域闸均已过 *)
        _fT1K := _fT1C + DL_KELVIN_OFF;
        _fT2K := fTempC + DL_KELVIN_OFF;
        IF (_fT1K >= DL_T_ABS_MIN) AND (_fT2K >= DL_T_ABS_MIN) THEN
            fDpCompPa := _fP1Pa - (fPressPa * _fT1K / _fT2K);   // 补偿压降
            fLeakRatePaLs := MAX(fDpCompPa, DL_ZERO) * fVolumeL
                             / MAX(TIME_TO_REAL(tMeasDur) / DL_MS_PER_S, DL_MEAS_MIN_S);
            bTestPass := fLeakRatePaLs <= fLeakLimPaLs;
            uErrId := 16#0006_01C2;      // 信息级：结论写定沿
            _ePhase := E_DL_AltPhase.eDone;
        ELSE
            _bFault := TRUE;             // 绝对温度越下限：判据不可信
            _uFault := 16#0006_02C2;
            bError  := TRUE;
            _ePhase := E_DL_AltPhase.eFault;
        END_IF
    END_IF

E_DL_AltPhase.eDone:
    bChargeCmd := FALSE;
    IF NOT bTestCmd THEN
        _ePhase := E_DL_AltPhase.eIdle;  // 测试指令撤销：回空闲（结论锁存保留）
    END_IF

E_DL_AltPhase.eFault:
    bChargeCmd := FALSE;                 // 故障相：充压指令安全侧撤销
    bError := TRUE;
    ;                                    // 故障相驻留：只认复位沿（段 2 迁出）

ELSE
    _bFault := TRUE;                     // 兜底：非法相位锁存
    _uFault := 16#0006_02C2;
    bError  := TRUE;
    _ePhase := E_DL_AltPhase.eFault;
END_CASE

(* —— 段 5｜相位出口单点映射 —— *)
ePhase := _ePhase;
END_FUNCTION_BLOCK
