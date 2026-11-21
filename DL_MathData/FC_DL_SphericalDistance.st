(*
  FC_DL_SphericalDistance  —  球面大圆距离（haversine，纯函数）/ Great-circle distance via haversine, pure function
  分类 Category : DL_MathData
  码位 Code     : 16#05_0_05
  段位说明      : 05_0 段 04 格由 FC_DL_TrendSlopeCalc 启用，本件启用相邻 05 格（一件一码）
  版本 Version  : 1.0.0
  来源 Source   : t2-1-lgf-math — Math 分类「三角方向」待挖项落地
  溯源 Origin   : clean-room 实现，haversine 公式为公开领域数学方法，未复制任何源码行
  功能 Function : 1) 两经纬度（度）→ 球面大圆距离 [km]，haversine 公式 + ASIN 半角域钳制；
                  2) 同点分支：经纬差绝对值在容差内直接返回 0 距离（信息级码），不做三角运算；
                  3) 经纬度域钳制：纬度钳到 [-90, 90]、经度钳到 [-180, 180]，越界置信息级码并照常计算；
                  4) 服务 AGV 航点里程 / 光伏阵列地理排布 / 天文钟族等地理量场景。
  边界 Boundary : ① 角度入口（度）而非弧度，与上位地图口径一致，内部换算弧度；
                  ② 非有限输入（x <> x 判 NaN、差值自反判 Inf）直接故障码返回 0 距离；
                  ③ ASIN 域钳制：sqrt(h) 先钳到 [0,1] 再取 ASIN，杜绝浮点抖动越域；
                  ④ 反余弦域钳制声明：本实现走 ASIN 半角路径，天然域 [0,1]，无 ACOS 越域风险；
                  ⑤ 纯函数无内部状态，每拍重算；地球半径取公开常用值 6371.0088 km。
  依赖 Depends  : 无 DL_ 内部依赖，纯 IEC 61131-3（SIN/COS/ASIN/SQRT 均为标准函数）
  码表 Error codes（本件格 05_0_05，子码步进 +0x100）:
    16#0005_0105 信息级：经纬度越域已钳制，计算照常完成
    16#0005_0205 故障级：输入非有限（NaN/Inf），返回 0 距离
    16#0005_0305 信息级：同点分支（经纬差在容差内），返回 0 距离

  修订历史 Revision :
    2026-11-19  v1.0.0  R39 首版（批次 1 · 序号 3）
*)

FUNCTION FC_DL_SphericalDistance : LREAL    // 返回两点大圆距离 [km]，异常路径返回 0 / Returns distance [km], 0 on error paths
VAR_INPUT
    fLat1Deg : LREAL;                   // 点 1 纬度 [deg]，域 [-90, 90]，越界钳制 / Latitude of point 1 [deg]
    fLon1Deg : LREAL;                   // 点 1 经度 [deg]，域 [-180, 180]，越界钳制 / Longitude of point 1 [deg]
    fLat2Deg : LREAL;                   // 点 2 纬度 [deg] / Latitude of point 2 [deg]
    fLon2Deg : LREAL;                   // 点 2 经度 [deg] / Longitude of point 2 [deg]
END_VAR
VAR_OUTPUT
    bClamped : BOOL;                    // 本次输入发生越域钳位 / Inputs were clamped this call
    bSamePt  : BOOL;                    // 同点分支命中 / Same-point branch hit
    uErrorId : UDINT;                   // 事件码，0 = 无事件（本件码均为单次调用瞬时，无锁存）/ Event code, transient per call
END_VAR
VAR
    fLat1    : LREAL;                   // 点 1 纬度钳制后 [deg] / Clamped latitude 1
    fLon1    : LREAL;                   // 点 1 经度钳制后 [deg] / Clamped longitude 1
    fLat2    : LREAL;                   // 点 2 纬度钳制后 [deg] / Clamped latitude 2
    fLon2    : LREAL;                   // 点 2 经度钳制后 [deg] / Clamped longitude 2
    fPhi1    : LREAL;                   // 点 1 纬度弧度 [rad] / Latitude 1 in radians
    fPhi2    : LREAL;                   // 点 2 纬度弧度 [rad] / Latitude 2 in radians
    fDPhi    : LREAL;                   // 纬差弧度 [rad] / Latitude delta in radians
    fDLam    : LREAL;                   // 经差弧度 [rad] / Longitude delta in radians
    fSinDPhi : LREAL;                   // sin(纬差/2) 工作量 / sin of half latitude delta
    fSinDLam : LREAL;                   // sin(经差/2) 工作量 / sin of half longitude delta
    fH       : LREAL;                   // haversine 半角量 h = a，域 [0,1] 钳制后 / Haversine half-chord term, clamped to [0,1]
    fDLat    : LREAL;                   // 纬差 [deg]（同点判据用）/ Latitude delta [deg] for the same-point test
    fDLon    : LREAL;                   // 经差 [deg]（同点判据用）/ Longitude delta [deg] for the same-point test
END_VAR
VAR CONSTANT
    DL_SPH_LAT_MAX  : LREAL := 90.0;        // 纬度域上限 [deg] / Latitude domain bound
    DL_SPH_LON_MAX  : LREAL := 180.0;       // 经度域上限 [deg] / Longitude domain bound
    DL_SPH_INF_CAP  : LREAL := 1.0E30;      // 非有限值筛查幅值上限 / Non-finite magnitude screening cap
    DL_SPH_DEG2RAD  : LREAL := 0.017453292519943295;   // 度转弧度系数 π/180 [rad/deg] / Degrees to radians factor
    DL_SPH_R_EARTH  : LREAL := 6371.0088;   // 地球平均半径 [km]，公开常用值 / Mean Earth radius [km]
    DL_SPH_SAME_EPS : LREAL := 1.0E-9;      // 同点判据容差 [deg] / Same-point tolerance [deg]
    DL_SPH_ZERO     : LREAL := 0.0;         // 零距离常量 [km] / Zero distance constant
END_VAR

(* —— 段 1｜输出安全预置：任何异常路径返回 0 距离 —— *)
(* Stage 1, safe preset: every error path returns zero *)
FC_DL_SphericalDistance := 0.0;
bClamped := FALSE;
bSamePt  := FALSE;
uErrorId := 16#0005_0205;               // 缺省非有限故障码，通过路径末尾改写 / Default non-finite code, rewritten on success

(* —— 段 2｜非有限筛查（x<>x 判 NaN、差值自反判 Inf、幅值兜底） —— *)
(* Stage 2, non-finite screening *)
IF (fLat1Deg <> fLat1Deg) OR (ABS(fLat1Deg) > DL_SPH_INF_CAP) OR ((fLat1Deg - fLat1Deg) <> 0.0)
   OR (fLon1Deg <> fLon1Deg) OR (ABS(fLon1Deg) > DL_SPH_INF_CAP) OR ((fLon1Deg - fLon1Deg) <> 0.0)
   OR (fLat2Deg <> fLat2Deg) OR (ABS(fLat2Deg) > DL_SPH_INF_CAP) OR ((fLat2Deg - fLat2Deg) <> 0.0)
   OR (fLon2Deg <> fLon2Deg) OR (ABS(fLon2Deg) > DL_SPH_INF_CAP) OR ((fLon2Deg - fLon2Deg) <> 0.0) THEN
    RETURN;                             // 非有限输入：0 距离返回（预置码 0205 已在） / Non-finite input, return zero
END_IF

(* —— 段 3｜同点分支（容差内直接零距离，不做三角运算） —— *)
(* Stage 3, same-point branch *)
fDLat := fLat2Deg - fLat1Deg;
fDLon := fLon2Deg - fLon1Deg;
IF (ABS(fDLat) < DL_SPH_SAME_EPS) AND (ABS(fDLon) < DL_SPH_SAME_EPS) THEN
    bSamePt  := TRUE;
    uErrorId := 16#0005_0305;           // 信息级：同点零距
    RETURN;                             // 返回 0 距离（预置值）/ Return zero distance
END_IF

(* —— 段 4｜经纬度域钳制（越界置信息码并照常计算） —— *)
(* Stage 4, domain clamping *)
fLat1 := MIN(DL_SPH_LAT_MAX, MAX(-DL_SPH_LAT_MAX, fLat1Deg));
fLon1 := MIN(DL_SPH_LON_MAX, MAX(-DL_SPH_LON_MAX, fLon1Deg));
fLat2 := MIN(DL_SPH_LAT_MAX, MAX(-DL_SPH_LAT_MAX, fLat2Deg));
fLon2 := MIN(DL_SPH_LON_MAX, MAX(-DL_SPH_LON_MAX, fLon2Deg));
IF (fLat1 <> fLat1Deg) OR (fLon1 <> fLon1Deg) OR (fLat2 <> fLat2Deg) OR (fLon2 <> fLon2Deg) THEN
    bClamped := TRUE;
    uErrorId := 16#0005_0105;           // 信息级：越域钳制，计算照常
END_IF

(* —— 段 5｜haversine 主体（度转弧度，半角正弦构造） —— *)
(* Stage 5, haversine core *)
fPhi1    := fLat1 * DL_SPH_DEG2RAD;
fPhi2    := fLat2 * DL_SPH_DEG2RAD;
fDPhi    := (fLat2 - fLat1) * DL_SPH_DEG2RAD;
fDLam    := (fLon2 - fLon1) * DL_SPH_DEG2RAD;
fSinDPhi := SIN(fDPhi * 0.5);
fSinDLam := SIN(fDLam * 0.5);
fH := fSinDPhi * fSinDPhi + COS(fPhi1) * COS(fPhi2) * fSinDLam * fSinDLam;   // h = sin²(Δφ/2) + cosφ1·cosφ2·sin²(Δλ/2)
IF fH < 0.0 THEN
    fH := 0.0;                          // 浮点抖动下限钳位 / Clamp numerical noise below zero
END_IF
IF fH > 1.0 THEN
    fH := 1.0;                          // ASIN 域钳制（上限）：杜绝越域 / ASIN domain clamp upper
END_IF

(* —— 段 6｜距离合成：d = 2R·asin(sqrt(h))（h 已钳 [0,1]，无越域） —— *)
(* Stage 6, distance assembly *)
FC_DL_SphericalDistance := 2.0 * DL_SPH_R_EARTH * ASIN(SQRT(fH));
uErrorId := 16#0000_0000;               // 正常路径无事件 / No event on the normal path
IF bClamped THEN
    uErrorId := 16#0005_0105;           // 钳制信息码还原（正常距离照常返回）/ Restore clamp info code
END_IF

END_FUNCTION
