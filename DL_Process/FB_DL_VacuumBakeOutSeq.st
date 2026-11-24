(*
  组件名 Component   : FB_DL_VacuumBakeOutSeq
  子库 Sublibrary    : DL_Process
  版本 Version       : 1.0.0
  兼容性 Platform    : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert（仅 Standard.library）
  功能 Function      : 真空烘烤顺控（锂电/半导体共性，自研行业池）：
                       1) 升温相（eRampUp）：温度需求按 fRampRateKMin 斜率逼近
                       fSoakTempC，腔压 < fSoakPressMaxPa 才视为升温有效；
                       2) 保温保压相（eSoak）：温度需求保持 fSoakTempC，腔压超上限
                       持续 tPressDevTo → 故障锁存；保温计时到 → 进压升率判漏相；
                       3) 压升率判漏相（eRorMeas）：窗始取腔压快照，窗长 tRorWin 到
                       → 压升率 = (腔压 - 快照) / 窗长，超 fRorFailPaS → 故障（判漏
                       不合格）；不超 → 终点判据达成，进降温相；
                       4) 降温放气相（eCoolVent）：需求温度按斜率降至 fEndTempC 后
                       开放气阀驻留 tVentDur → eDone。
  边界 Boundary      : ① 本件只出温度需求/阀门指令，不写物理 IO，不内嵌温控回路；
                       ② 压升率除法前置域闸：tRorWin 秒值下限 0.1 s（常量护栏）；
                       ③ 各相计时独立 TON 实例（禁跨相复用）；压升率窗始快照在
                       进相首拍写定，锁存回放不重扫；
                       ④ 故障锁存解除唯一路径 = bReset 上升沿（输入引脚，恒可达）；
                       ⑤ 无全局变量引用、无外部变量声明、无物理地址寻址。
  依赖 Depends       : Standard.library（R_TRIG / TON）
  溯源 Origin        : 道莅自研 clean-room（自研行业池：锂电/半导体真空烘烤共性
                       语义，零外部代码行复制）
  码位 Code          : 16#06_0_BF（Process 段 0006，B 子带 BF 格）
  码表 Error codes（本件格 06_0_BF，单轨子道：故障 0x02BF / 信息 0x01BF）:
    16#0006_02BF 故障级：烘烤顺控故障总码（保压越限 / 压升率判漏不合格 /
                 组态非法 / 输入非有限），锁存至复位
    16#0006_01BF 信息级：压升率判漏通过沿（进降温相迁移拍）
  修订历史 Revision  :
    2026-11-19  v1.0.0  R44 首版（批次 4 · 序号 16）
*)

TYPE E_DL_VboPhase :
(
    eIdle     := 0,   // 空闲：未使能 / Idle, not enabled
    eRampUp   := 10,  // 升温：斜坡逼近保温温度 / Ramping to soak temperature
    eSoak     := 20,  // 保温保压：保持温度与压力 / Soaking temperature and pressure
    eRorMeas  := 30,  // 判漏：压升率测量窗 / Rate-of-rise measurement window
    eCoolVent := 40,  // 降温放气：斜坡降温 + 放气 / Cooling and venting
    eDone     := 50,  // 完成：终点驻留 / Done, endpoint held
    eFault    := 90   // 故障：总码锁存 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_VacuumBakeOutSeq
VAR_INPUT
    bEnable      : BOOL;                   // 使能（电平）[-] / Enable
    bReset       : BOOL;                   // 上升沿清故障锁存 [-] / Reset edge
    fChamberTempC: REAL;                   // 腔体实测温度 [摄氏度] / Chamber temperature
    fChamberPressPa: REAL;                 // 腔体实测压力 [帕斯卡] / Chamber pressure
    fSoakTempC   : REAL := 80.0;           // 保温温度 [摄氏度] / Soak temperature
    fEndTempC    : REAL := 35.0;           // 降温终点温度 [摄氏度] / Cool-down end temperature
    fRampRateKMin: REAL := 2.0;            // 升降温斜率 [开尔文/分] / Ramp rate
    fSoakPressMaxPa: REAL := 50.0;         // 保温压力上限 [帕斯卡] / Soak pressure ceiling
    fRorFailPaS  : REAL := 5.0;            // 压升率判漏限 [帕/秒] / Rate-of-rise fail limit
    tSoakDur     : TIME := T#24H;          // 保温时长 [毫秒] / Soak duration
    tRorWin      : TIME := T#60S;          // 压升率测量窗 [毫秒] / ROR measurement window
    tPressDevTo  : TIME := T#30S;          // 保压越限确认窗 [毫秒] / Pressure deviation timeout
    tVentDur     : TIME := T#60S;          // 放气驻留 [毫秒] / Vent dwell
    tCycle       : TIME := T#1S;           // 扫描周期 [毫秒] / Scan cycle time
END_VAR
VAR_OUTPUT
    fTempDemandC : REAL;                   // 温度需求输出 [摄氏度] / Temperature demand
    bPumpCmd     : BOOL;                   // 抽真空维持指令（升温/保温/判漏相）[-] / Vacuum maintain command
    bVentCmd     : BOOL;                   // 放气阀指令（放气驻留相电平）[-] / Vent valve command
    fRorPaS      : REAL;                   // 实测压升率 [帕/秒] / Measured rate of rise
    ePhase       : E_DL_VboPhase;          // 相位出口，段尾单点映射 / Phase outlet
    bError       : BOOL;                   // 故障锁存标志 [-] / Fault latch flag
    uErrId       : UDINT;                  // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    rtReset  : R_TRIG;                     // 复位沿实例，段 0 无条件刷新 / Reset edge
    tonSoakDur: TON;                       // 保温计时（独立实例） / Soak duration timer
    tonRorWin : TON;                       // 压升率测量窗（独立实例） / ROR window timer
    tonPressDevTo: TON;                    // 保压越限确认（专用超时件命名） / Pressure timeout
    tonVentDur: TON;                       // 放气驻留计时（独立实例） / Vent dwell timer
    _ePhase : E_DL_VboPhase := E_DL_VboPhase.eIdle;    // 内部相位（CASE 唯一写入目标）/ Internal phase
    _fPressSnap: REAL;                     // 判漏窗始压力快照 [帕斯卡] / Window-start pressure snapshot
    _fPressStart: REAL;                    // 保温起点压力快照 [帕斯卡] / Soak-start pressure snapshot
    _bFault : BOOL;                        // 故障锁存位（锁存量） / Latched fault bit
    _uFault : UDINT;                       // 故障码锁存（锁存量） / Latched fault code
    _bCfgBad: BOOL;                        // 组态非法当拍量 [-] / Config illegal flag
    _bNonFin: BOOL;                        // 输入非有限当拍量 [-] / Non-finite input flag
    _bSnapDone: BOOL;                      // 判漏快照已取标志 [-] / Snapshot taken flag
END_VAR
VAR CONSTANT
    DL_WIN_MIN_S : REAL := 0.1;            // 测量窗秒值下限 [秒] / Window seconds floor
    DL_SEC_PER_MIN: REAL := 60.0;          // 秒 → 分换算系数 [秒/分] / Seconds per minute
    DL_MS_PER_S  : REAL := 1000.0;         // 毫秒 → 秒换算系数 [毫秒/秒] / Milliseconds per second
    DL_ABS_MAX   : REAL := 1.0E30;         // 有限值判定上界 [工程单位] / Finite bound
    DL_ZERO      : REAL := 0.0;            // 零常量 [工程单位] / Zero constant
END_VAR

(* —— 段 0｜沿与定时器每拍无条件刷新（禁置于 IF/CASE 内；各相独立实例禁复用） —— *)
rtReset(CLK := bReset);
tonSoakDur   (IN := (_ePhase = E_DL_VboPhase.eSoak) AND (NOT _bFault), PT := tSoakDur);
tonRorWin    (IN := (_ePhase = E_DL_VboPhase.eRorMeas) AND (NOT _bFault), PT := tRorWin);
tonPressDevTo(IN := (_ePhase = E_DL_VboPhase.eSoak) AND (fChamberPressPa > fSoakPressMaxPa)
              AND (NOT _bFault), PT := tPressDevTo);
tonVentDur   (IN := (_ePhase = E_DL_VboPhase.eCoolVent) AND (NOT _bFault), PT := tVentDur);

(* —— 段 1｜瞬时量预清零（锁存量 _bFault/_uFault/fTempDemandC/_fPressSnap 不入清单） —— *)
uErrId   := 16#0000_0000;
_bCfgBad := FALSE;
_bNonFin := FALSE;

(* —— 段 2｜复位沿：故障一次性清干净，相位回空闲，阀门指令撤销 —— *)
IF rtReset.Q THEN
    _bFault := FALSE;
    _uFault := 16#0000_0000;
    bVentCmd := FALSE;
    bPumpCmd := FALSE;
    _ePhase := E_DL_VboPhase.eIdle;
END_IF

(* —— 段 3｜组态闸与非有限判据（覆盖全部参与判据换算引脚） —— *)
IF (fRampRateKMin <= DL_ZERO) OR (fRorFailPaS <= DL_ZERO) OR (tSoakDur = T#0S)
   OR (tRorWin = T#0S) OR (tPressDevTo = T#0S) OR (tVentDur = T#0S) OR (tCycle = T#0S)
   OR (fSoakTempC <= fEndTempC) THEN
    _bCfgBad := TRUE;
END_IF
IF (fChamberTempC <> fChamberTempC) OR ((fChamberTempC - fChamberTempC) <> DL_ZERO)
   OR (fChamberPressPa <> fChamberPressPa) OR ((fChamberPressPa - fChamberPressPa) <> DL_ZERO) THEN
    _bNonFin := TRUE;
END_IF

(* —— 段 4｜主状态机：七态全覆盖 + ELSE 兜底 —— *)
CASE _ePhase OF

E_DL_VboPhase.eIdle:
    fTempDemandC := fChamberTempC;       // 空闲相：需求跟随实测（不驱动）
    bPumpCmd := FALSE;
    bVentCmd := FALSE;
    IF bEnable AND (NOT _bCfgBad) THEN
        _bSnapDone := FALSE;
        fRorPaS := DL_ZERO;
        _ePhase := E_DL_VboPhase.eRampUp;
    ELSIF bEnable AND _bCfgBad THEN
        _bFault := TRUE;
        _uFault := 16#0006_02BF;
        bError  := TRUE;
        _ePhase := E_DL_VboPhase.eFault;
    END_IF

E_DL_VboPhase.eRampUp:
    bPumpCmd := TRUE;
    bVentCmd := FALSE;
    (* 温度需求斜率逼近：每拍步长 = 斜率 × 周期（分 → 秒换算，除子域闸已过） *)
    fTempDemandC := MIN(fTempDemandC + fRampRateKMin * (TIME_TO_REAL(tCycle) / DL_MS_PER_S)
                        / DL_SEC_PER_MIN, fSoakTempC);
    IF _bNonFin THEN
        _bFault := TRUE;
        _uFault := 16#0006_02BF;
        bError  := TRUE;
        _ePhase := E_DL_VboPhase.eFault;
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_VboPhase.eIdle;  // 使能撤销回空闲
    ELSIF (fChamberTempC >= fSoakTempC) AND (fChamberPressPa <= fSoakPressMaxPa) THEN
        _fPressStart := fChamberPressPa; // 保温起点压力快照
        _ePhase := E_DL_VboPhase.eSoak;  // 迁出：温度达保温且压力已入保压域
    END_IF

E_DL_VboPhase.eSoak:
    bPumpCmd := TRUE;
    bVentCmd := FALSE;
    fTempDemandC := fSoakTempC;          // 保温相需求定值
    IF _bNonFin OR tonPressDevTo.Q THEN
        _bFault := TRUE;                 // 保压越限或输入非法：锁存
        _uFault := 16#0006_02BF;
        bError  := TRUE;
        _ePhase := E_DL_VboPhase.eFault;
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_VboPhase.eIdle;  // 使能撤销回空闲
    ELSIF tonSoakDur.Q THEN
        _bSnapDone := FALSE;             // 保温时长到：进判漏相，快照待取
        _ePhase := E_DL_VboPhase.eRorMeas;
    END_IF

E_DL_VboPhase.eRorMeas:
    bPumpCmd := TRUE;
    bVentCmd := FALSE;
    fTempDemandC := fSoakTempC;
    IF _bNonFin THEN
        _bFault := TRUE;
        _uFault := 16#0006_02BF;
        bError  := TRUE;
        _ePhase := E_DL_VboPhase.eFault;
    ELSIF NOT _bSnapDone THEN
        _fPressSnap := fChamberPressPa;  // 窗始快照：进相首拍写定（锁存回放不重扫）
        _bSnapDone := TRUE;
    ELSIF tonRorWin.Q THEN
        (* 压升率 = (腔压 - 窗始快照) / 窗长秒值（除子 = 窗长，常量护栏下限已过） *)
        fRorPaS := (fChamberPressPa - _fPressSnap)
                   / MAX(TIME_TO_REAL(tRorWin) / DL_MS_PER_S, DL_WIN_MIN_S);
        IF fRorPaS > fRorFailPaS THEN
            _bFault := TRUE;             // 判漏不合格：锁存（禁按当下输入重推断）
            _uFault := 16#0006_02BF;
            bError  := TRUE;
            _ePhase := E_DL_VboPhase.eFault;
        ELSE
            uErrId := 16#0006_01BF;      // 信息级：判漏通过沿
            _ePhase := E_DL_VboPhase.eCoolVent;   // 终点判据达成：进降温放气
        END_IF
    END_IF

E_DL_VboPhase.eCoolVent:
    bPumpCmd := FALSE;
    (* 温度需求斜率下降，降至终点温度前放气阀不开（先降温后放气） *)
    IF fTempDemandC > fEndTempC THEN
        fTempDemandC := MAX(fTempDemandC - fRampRateKMin * (TIME_TO_REAL(tCycle) / DL_MS_PER_S)
                            / DL_SEC_PER_MIN, fEndTempC);
        bVentCmd := FALSE;
    ELSE
        bVentCmd := TRUE;                // 需求到终点温度：开放气阀驻留
    END_IF
    IF _bNonFin THEN
        _bFault := TRUE;
        _uFault := 16#0006_02BF;
        bError  := TRUE;
        _ePhase := E_DL_VboPhase.eFault;
    ELSIF bVentCmd AND tonVentDur.Q THEN
        _ePhase := E_DL_VboPhase.eDone;  // 迁出：放气驻留完成
    ELSIF NOT bEnable THEN
        _ePhase := E_DL_VboPhase.eIdle;  // 使能撤销回空闲
    END_IF

E_DL_VboPhase.eDone:
    bPumpCmd := FALSE;
    bVentCmd := FALSE;                   // 完成相：阀门指令全撤（安全侧）
    IF NOT bEnable THEN
        _ePhase := E_DL_VboPhase.eIdle;  // 使能撤销回空闲（待机可返回路径）
    END_IF

E_DL_VboPhase.eFault:
    bPumpCmd := FALSE;
    bVentCmd := FALSE;
    bError := TRUE;
    ;                                    // 故障相驻留：只认复位沿（段 2 迁出）

ELSE
    _bFault := TRUE;                     // 兜底：非法相位锁存
    _uFault := 16#0006_02BF;
    bError  := TRUE;
    _ePhase := E_DL_VboPhase.eFault;
END_CASE

(* —— 段 5｜相位出口单点映射 —— *)
ePhase := _ePhase;
END_FUNCTION_BLOCK
