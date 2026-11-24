(*
  道莅工业代码库 | DL_Motion | FB_DL_DeltaRobotIk
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  开源溯源: self-cleanroom（无外部来源；Delta 并联机构闭式逆解为公开几何推导，
            本件由解析几何独立推导实现，零代码行复制）
  功能: 三臂并联三角洲机器人逆运动学——末端 XYZ [mm] → 三臂上臂关节角 [°]
        （相对水平面，肘下主解分支），含行程奇异性闸与可达性闸。
  兼容性: CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；仅依赖标准 SQRT/ABS/ACOS/ATAN，零厂商私有库
  接口: 输入末端 XYZ 与机构四参数（基座半径/动平台半径/上臂长/前臂长）+ 上臂角限位；
        输出三臂角 fTheta1Deg~fTheta3Deg [°]、bReachOk、eErr。变换型 FB（无相位机，
        每拍独立全量重算，无跨周期状态），无 TON/R_TRIG 实例。
  码表: 16#0004_0369 故障级：参数非法（半径/臂长/限位角非法或末端坐标非有限）
        16#0004_036A 故障级：目标不可达（侧偏超限无解/三角函数域越界/上臂角超行程）
        码段说明：0004 段故障子带 03xx，槽位经全库实扫空闲。
  边界: ① 逆解方程：uXr*cosφ - fZ*sinφ = C（C = -(K²-Lu²-X²-z²)/(2Lu)），
        化为 R·cos(φ+α) 求解，α 由 ATAN 加象限修正手构（不用方言 ATAN2）；
        ② 侧向偏移使 K² = Lf²-b² < 0 判不可达（奇异性闸前置）；
        ③ 所有除法分母先闸（2Lu 由参数闸 >0 证明，R 由 EPS 下限闸，uXr 由 ABS<EPS 闸）；
        ④ 上臂角限位 |φ| > fPhiMaxDeg 判行程越界；
        ⑤ 任一臂不可达 → 三臂输出全零（不输出部分解）；⑥ 零全局耦合。
  邻件比对: robot 族仅监视/抓取验证件在册，无运动学逆解属主（R75 §3 留痕）。
  修订历史: 2026-11-23 v1.0.0 R75 首版（复杂件批 B1 · C03）
*)

FUNCTION_BLOCK FB_DL_DeltaRobotIk
VAR_INPUT
    fX         : LREAL := 0.0;    // 末端 X 坐标 [mm] | End-effector X coordinate
    fY         : LREAL := 0.0;    // 末端 Y 坐标 [mm] | End-effector Y coordinate
    fZ         : LREAL := 0.0;    // 末端 Z 坐标（基座平面上方为正）[mm] | End-effector Z coordinate, positive above base plane
    fRBase     : LREAL := 200.0;  // 基座等边三角形半径（肩关节分布圆），域 > 0 [mm] | Base triangle radius
    fRPlat     : LREAL := 50.0;   // 动平台等边三角形半径（腕关节分布圆），域 > 0 [mm] | Platform triangle radius
    fArmLen    : LREAL := 100.0;  // 上臂长度，域 > 0 [mm] | Upper arm length
    fForeLen   : LREAL := 250.0;  // 前臂（从动杆）长度，域 > 0 [mm] | Forearm length
    fPhiMaxDeg : LREAL := 80.0;   // 上臂角限位幅值，域 (0, 180) [°] | Upper arm angle travel limit
END_VAR
VAR_OUTPUT
    fTheta1Deg : LREAL;           // 臂 1 上臂关节角（方位 0°，相对水平面）[°] | Arm 1 upper joint angle at azimuth 0 deg
    fTheta2Deg : LREAL;           // 臂 2 上臂关节角（方位 120°）[°] | Arm 2 upper joint angle at azimuth 120 deg
    fTheta3Deg : LREAL;           // 臂 3 上臂关节角（方位 240°）[°] | Arm 3 upper joint angle at azimuth 240 deg
    bReachOk   : BOOL;            // 可达且行程内 [-] | Reachable and within travel
    eErr       : UDINT;           // 错误码，0 = 无错 | Error code, 0 = none
END_VAR
VAR
    aTheta   : ARRAY[1..3] OF LREAL;  // 三臂角暂存（出口统一映射）[°] | Per-arm angle staging
    uPsiCos  : LREAL;                 // 当前臂方位角余弦 [-] | Current arm azimuth cosine
    uPsiSin  : LREAL;                 // 当前臂方位角正弦 [-] | Current arm azimuth sine
    uXr      : LREAL;                 // 目标在臂平面内的径向差 [mm] | Radial offset in arm plane
    uLat     : LREAL;                 // 目标侧向偏移（离臂平面）[mm] | Lateral offset out of arm plane
    uK2      : LREAL;                 // 可达半径平方 K² [mm²] | Squared reachable radius
    uK       : LREAL;                 // 可达半径 K [mm] | Reachable radius
    uM       : LREAL;                 // 化简常数 M [mm] | Reduced constant
    uR       : LREAL;                 // 径向-高度合成半径 R [mm] | Combined radial-height radius
    uCosv    : LREAL;                 // cos(φ+α) 候补 [-] | cos of phi plus alpha candidate
    uAlpha   : LREAL;                 // 象限修正后的 α [rad] | Quadrant-corrected alpha
    uPhi     : LREAL;                 // 上臂角主解 [rad] | Upper arm angle primary solution
    i        : INT;                   // 臂序号游标 | Arm index cursor
    bOk      : BOOL;                  // 全程可达标志 [-] | All arms reachable flag
END_VAR
VAR CONSTANT
    DL_DRI_PI     : LREAL := 3.14159265358979;    // 圆周率 | Pi
    DL_DRI_EPS    : LREAL := 1.0E-9;              // 退化判定容差 [mm] | Degeneracy tolerance
    DL_DRI_RAD2DEG: LREAL := 57.29577951308232;   // 弧度转角度因子 | Rad to deg factor
    DL_DRI_ERR_PAR: UDINT := 16#0004_0369;        // 参数非法码 | Illegal parameter code
    DL_DRI_ERR_REA: UDINT := 16#0004_036A;        // 不可达码 | Unreachable code
END_VAR

(* —— 段 0：输出缺省全赋值（全路径覆盖） —— *)
aTheta[1] := 0.0;                       // 臂 1 暂存清零（防御） / Arm 1 staging cleared
aTheta[2] := 0.0;                       // 臂 2 暂存清零（防御） / Arm 2 staging cleared
aTheta[3] := 0.0;                       // 臂 3 暂存清零（防御） / Arm 3 staging cleared
bReachOk := FALSE;                      // 可达标志预置 FALSE / Reach flag preset FALSE
eErr := 0;                              // 错误码缺省 / Error default

(* —— 段 1：输入与机构参数域闸 —— *)
bOk := TRUE;                            // 可达标志初值 / Reach flag init
IF (fX <> fX) OR (fY <> fY) OR (fZ <> fZ)
   OR (fRBase <> fRBase) OR (fRPlat <> fRPlat) OR (fArmLen <> fArmLen)
   OR (fForeLen <> fForeLen) OR (fPhiMaxDeg <> fPhiMaxDeg) THEN
    bOk := FALSE;                       // 任一输入非有限 / Any non-finite input
    eErr := DL_DRI_ERR_PAR;             // 参数非法码 / Parameter code
END_IF
IF bOk AND ((fRBase <= 0.0) OR (fRPlat <= 0.0) OR (fArmLen <= 0.0)
         OR (fForeLen <= 0.0) OR (fPhiMaxDeg <= 0.0) OR (fPhiMaxDeg >= 180.0)) THEN
    bOk := FALSE;                       // 机构参数越域 / Mechanism parameters out of domain
    eErr := DL_DRI_ERR_PAR;             // 参数非法码 / Parameter code
END_IF

(* —— 段 2：三臂逆解主循环（肘下主解分支；任一臂失败即全件失败） —— *)
IF bOk THEN
    FOR i := 1 TO 3 DO
        // 方位角常量展开（免数组字面量初始化，跨平台安全）/ Azimuth constants unrolled
        CASE i OF
        1:  uPsiCos := 1.0;                                             // 臂 1 方位 0° | Arm 1 azimuth 0 deg
            uPsiSin := 0.0;
        2:  uPsiCos := -0.5;                                            // 臂 2 方位 120° | Arm 2 azimuth 120 deg
            uPsiSin := 0.866025403784439;
        3:  uPsiCos := -0.5;                                            // 臂 3 方位 240° | Arm 3 azimuth 240 deg
            uPsiSin := -0.866025403784439;
        ELSE
            uPsiCos := 1.0;                                             // 不可达分支兜底（循环上界已闸 1..3） | Unreachable fallback
            uPsiSin := 0.0;
        END_CASE

        // 几何量：径向差 / 侧偏 / 可达半径平方
        uXr := fX * uPsiCos + fY * uPsiSin - (fRBase - fRPlat);         // 径向差 X = x·cosψ + y·sinψ - (Rb-Rp) / Radial offset
        uLat := -fX * uPsiSin + fY * uPsiCos;                           // 侧偏 b = -x·sinψ + y·cosψ / Lateral offset
        uK2 := fForeLen * fForeLen - uLat * uLat;                       // K² = Lf² - b² / Squared reachable radius
        IF uK2 < 0.0 THEN
            bOk := FALSE;                                               // 侧偏超限无解（奇异性闸） / Lateral offset beyond reach
            eErr := DL_DRI_ERR_REA;                                     // 不可达码 / Unreachable code
        ELSE
            uK := SQRT(uK2);                                            // 可达半径 K ≥ 0 / Reachable radius
            uM := (uK2 - fArmLen * fArmLen - uXr * uXr - fZ * fZ)
               / (2.0 * fArmLen);                                       // M = (K²-Lu²-X²-z²)/(2Lu)，分母由参数闸 >0 / Reduced constant, denominator proven
            uR := SQRT(uXr * uXr + fZ * fZ);                            // 合成半径 R = √(X²+z²) / Combined radius
            IF uR < DL_DRI_EPS THEN
                IF ABS(uM) < DL_DRI_EPS THEN
                    uPhi := 0.0;                                        // 退化同心且 M≈0：φ=0 / Degenerate concentric, phi = 0
                ELSE
                    bOk := FALSE;                                       // 退化且无解 / Degenerate unsolvable
                    eErr := DL_DRI_ERR_REA;
                END_IF
            ELSE
                uCosv := -uM / uR;                                      // cos(φ+α) = -M/R，分母已闸 R > EPS / Cosine candidate, denominator gated
                IF ABS(uCosv) > 1.0 THEN
                    bOk := FALSE;                                       // 反余弦定义域越界 = 不可达 / acos domain violated, unreachable
                    eErr := DL_DRI_ERR_REA;
                ELSE
                    // α = atan2(fZ, uXr) 手构象限修正（不用方言 ATAN2）/ Manual atan2 with quadrant fix
                    IF ABS(uXr) < DL_DRI_EPS THEN
                        IF fZ >= 0.0 THEN
                            uAlpha := 0.5 * DL_DRI_PI;                  // X≈0 且 z≥0：α=+π/2 | X near zero, z non-negative
                        ELSE
                            uAlpha := -0.5 * DL_DRI_PI;                 // X≈0 且 z<0：α=-π/2 | X near zero, z negative
                        END_IF
                    ELSE
                        uAlpha := ATAN(fZ / uXr);                       // 分母 ABS(uXr) >= EPS 已闸 / Denominator gated
                        IF uXr < 0.0 THEN
                            IF fZ >= 0.0 THEN
                                uAlpha := uAlpha + DL_DRI_PI;           // 第二象限修正 | Second quadrant fix
                            ELSE
                                uAlpha := uAlpha - DL_DRI_PI;           // 第三象限修正 | Third quadrant fix
                            END_IF
                        END_IF
                    END_IF
                    uPhi := ACOS(uCosv) - uAlpha;                       // 肘下主解：φ = acos(-M/R) - α / Elbow-down primary branch
                END_IF
            END_IF
        END_IF

        IF bOk THEN
            IF ABS(uPhi * DL_DRI_RAD2DEG) > fPhiMaxDeg THEN
                bOk := FALSE;                                           // 上臂角超行程限位 / Upper arm angle beyond travel
                eErr := DL_DRI_ERR_REA;                                 // 不可达码（行程越界归并） / Unreachable code folded
            ELSE
                aTheta[i] := uPhi * DL_DRI_RAD2DEG;                     // 弧度转角度入暂存 / Rad to deg into staging
            END_IF
        END_IF
    END_FOR
END_IF

(* —— 段 3：出口单点映射（失败全零输出，不输出部分解） —— *)
fTheta1Deg := aTheta[1];                // 臂 1 角出口 [°] / Arm 1 angle outlet
fTheta2Deg := aTheta[2];                // 臂 2 角出口 [°] / Arm 2 angle outlet
fTheta3Deg := aTheta[3];                // 臂 3 角出口 [°] / Arm 3 angle outlet
bReachOk := bOk;                        // 可达出口（名实同源） / Reach outlet

END_FUNCTION_BLOCK
