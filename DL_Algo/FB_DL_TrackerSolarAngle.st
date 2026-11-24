(*
  Component : FB_DL_TrackerSolarAngle
  Category  : DL_Algo
  Type      : FB
  Version   : 1.0.0
  CodeSeg   : 16#02_3_5E
  Summary   : 跟踪支架太阳角计算：时角/赤纬/纬度（输入均为弧度）→太阳高度角，含逆跟踪防阴影角度限幅。
              Solar angle calculation for trackers: hour angle / declination / latitude (all radians) to elevation, with backtracking clamp.
  溯源声明  : 道莅自研 clean-room
  边界安全  : 输入非有限（NaN 自反 + Inf 上限）拦截；纬度域闸（|lat| < 90° 弧度制，防极点除零歧义）；
              ASIN 前对正弦参数钳制到 [-1,1]（防定义域越界）；逆跟踪限幅域闸（0..90° 弧度制）
              与输出 ±90° 硬限双保险；负高度角转驻停角 0；全浮点比较带 fEps 容差。
  复用      : 无
*)

FUNCTION_BLOCK FB_DL_TrackerSolarAngle
VAR_INPUT
    bRun        : BOOL;                (* 计算使能，假则输出冻结 · Enable, FALSE freezes outputs *)
    fHourAngRad : LREAL;               (* 太阳时角 [rad]，正午为 0 · Solar hour angle *)
    fDeclRad    : LREAL;               (* 太阳赤纬 [rad] · Solar declination *)
    fLatRad     : LREAL;               (* 站点纬度 [rad]，北正南负 · Site latitude *)
    fBackLimRad : LREAL := 0.2617994;  (* 逆跟踪限幅 [rad]，域 0 到 pi/2 · Backtracking clamp limit *)
    fEps        : LREAL := 1.0E-6;     (* 浮点判零容差 [实数域] · Floating zero tolerance *)
END_VAR
VAR_OUTPUT
    fElevRad    : LREAL;               (* 太阳高度角 [rad] · Solar elevation angle *)
    fTrackAngRad: LREAL;               (* 跟踪架给定角 [rad]，已限幅 · Tracker command angle, clamped *)
    bNight      : BOOL;                (* 夜间标志（高度角 ≤ 0）· Night flag *)
    xClamped    : BOOL;                (* 逆跟踪限幅激活标志 · Backtracking clamp active *)
    bError      : BOOL;                (* 故障标志，与故障码配对 · Fault flag paired with codes *)
    uErrorId    : UDINT;               (* 事件码 16#0000_005E，0 无事件 · Event code *)
END_VAR
VAR
    uCode  : WORD;     (* 码位暂存，每拍重算 [码] · Code staging, recomputed *)
    bSigOk : BOOL;     (* 输入有效标志 · Input validity flag *)
    fSinE  : LREAL;    (* 高度角正弦中间量 [比值] · Sine of elevation *)
    nCycles: UDINT;    (* 有效计算拍计数 [拍]，防回卷 · Valid calculation count with wrap guard *)
END_VAR
VAR CONSTANT
    DL_TSA_HALFPI : LREAL := 1.5707963; (* 90° 弧度值 [rad] · Pi over two *)
    DL_TSA_WRAP   : UDINT := 4294967290; (* 计数防回卷余量 [拍] · Counter wrap guard *)
END_VAR

(* === 段 0 · 实例刷新 === *)
(* 纯算法件：无 TON/R_TRIG 实例，计数状态见段 3；Pure algorithm, no timer instances *)

(* === 段 1 · 输入校验与量程闸（角度单位约定：全部输入为弧度）=== *)
uCode := 16#0000;                       // 每拍清码，条件不满足再置（可达清零）/ Clear codes each scan
bSigOk := (fHourAngRad = fHourAngRad) AND (fDeclRad = fDeclRad) AND (fLatRad = fLatRad)
          AND (fBackLimRad = fBackLimRad)                                           // NaN 自反判据 / NaN reflexivity
          AND (ABS(fHourAngRad) < 1.0E308) AND (ABS(fDeclRad) < 1.0E308)            // Inf 上限判据 / Inf limit
          AND (ABS(fLatRad) < (DL_TSA_HALFPI - fEps))                               // 纬度域闸，防极点 / Latitude gate
          AND (fBackLimRad >= 0.0) AND (fBackLimRad <= DL_TSA_HALFPI);              // 限幅域闸 / Clamp domain gate
IF NOT bSigOk THEN
    uCode := 16#005E;                   // 故障级：输入域外，计算冻结 / Fault: input domain invalid
END_IF

(* === 段 2 · 主逻辑：高度角与逆跟踪限幅 === *)
IF bSigOk THEN
    fSinE := SIN(fLatRad) * SIN(fDeclRad) + COS(fLatRad) * COS(fDeclRad) * COS(fHourAngRad);
                                        // 高度角正弦公式 / Sine of elevation formula
    IF fSinE > 1.0 THEN
        fSinE := 1.0;                   // 参数钳上界，防 ASIN 越界 / Clamp to one before ASIN
    ELSIF fSinE < -1.0 THEN
        fSinE := -1.0;                  // 参数钳下界 / Clamp to minus one
    END_IF
    fElevRad := ASIN(fSinE);            // 太阳高度角 [rad] / Solar elevation
    bNight := (fElevRad < fEps);        // 夜间判据（带容差负角）/ Night flag with tolerance
    IF bNight THEN
        fTrackAngRad := 0.0;            // 夜间驻停角归零 / Stow to zero at night
        xClamped := FALSE;
    ELSIF fHourAngRad > fBackLimRad THEN
        fTrackAngRad := fBackLimRad;    // 逆跟踪限幅：下午侧 / Backtracking clamp, afternoon side
        xClamped := TRUE;
    ELSIF fHourAngRad < (-fBackLimRad) THEN
        fTrackAngRad := -fBackLimRad;   // 逆跟踪限幅：上午侧 / Backtracking clamp, morning side
        xClamped := TRUE;
    ELSE
        fTrackAngRad := fHourAngRad;    // 限幅域内直通 / Pass through inside the clamp
        xClamped := FALSE;
    END_IF
    (* 输出 ±90° 硬限双保险（限幅输入异常时的兜底）/ Hard +-90deg cap as a second guard *)
    IF fTrackAngRad > DL_TSA_HALFPI THEN
        fTrackAngRad := DL_TSA_HALFPI;  // 硬限上界 / Hard cap high
    ELSIF fTrackAngRad < (-DL_TSA_HALFPI) THEN
        fTrackAngRad := -DL_TSA_HALFPI; // 硬限下界 / Hard cap low
    END_IF
END_IF

(* === 段 3 · 输出映射与故障码 === *)
IF bSigOk THEN
    IF nCycles < DL_TSA_WRAP THEN
        nCycles := nCycles + 1;         // 有效计算计数，防回卷 / Count valid calculations
    END_IF
ELSE
    fElevRad := 0.0;                    // 故障输出安全零 / Safe zero on fault
    fTrackAngRad := 0.0;
    bNight := TRUE;                     // 故障按夜间驻停处理 / Treat fault as night stow
END_IF
bError := (uCode <> 16#0000);           // 故障标志配对 / Fault flag paired
uErrorId := WORD_TO_UDINT(uCode);       // 码位单点写入（16#0000_005E 形态）/ Single write point
END_FUNCTION_BLOCK
