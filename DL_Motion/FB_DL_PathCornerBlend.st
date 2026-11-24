(*
  ==================================================================
  组件名 Component  : FB_DL_PathCornerBlend
  分类   Category   : DL_Motion
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : 路径拐角圆滑过渡解算。给定方向改变角 fCornerAngDeg 与
                      拐角半径 fBlendR：切点距 fTanLen = R / tan(θ/2)（θ 为
                      方向改变角）；弦高误差 fChordErr = R·(1−cos(θ/2))；误
                      差带超限时按 Rmax = TolErr/(1−cos(θ/2)) 自动回夹半径并
                      置 bClamped；单调性自检：切点距不得超过两相邻段长一半
                      （与 FC_DL_LookaheadVelPlanner 速度前瞻分工互引）。
  来源   Source     : T1-6-plcopen（PLCopen 运动公开语义）
  溯源   Origin     : 圆弧过渡切点/弦高为公开几何语义，clean-room 自研实现，
                      未复制 PLCopen 或任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
  分工声明 Split     : 与 FC_DL_LookaheadVelPlanner 分工——后者做段间速度前
                      瞻，本件做拐角几何过渡解算。
  作者   Author     : 道莅代码库 · PLC 编程专家（R59）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 非有限入参闸（自反双判据，五参数全覆盖）：命中置
                         bError，输出安全侧零（四段式 R45）；
                      二 角度域闸：方向改变角钳入 [1, 179] 度（信息级
                         bClamped），防 tan/cos 小角爆炸与退化；
                      三 除零闸：tan(θ/2) ≤ eps 判退化置 bError；半径自动
                         回夹除式 (1−cos(θ/2)) > eps 由角度域闸保证并显式
                         再闸一层；
                      四 单调性自检：fTanLen > 0.5·min(段A, 段B) 置 bTooLong
                         （交接约束，信息级非故障）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R59 首版（批 2 · 序号 10）
  ==================================================================
*)

FUNCTION_BLOCK FB_DL_PathCornerBlend
VAR_INPUT
    fCornerAngDeg : LREAL := 90.0;  // 方向改变角 [度]，域 [1,179] / the direction change angle [degree]
    fBlendR       : LREAL := 10.0;  // 拐角半径 [毫米] / the corner radius [millimeter]
    fTolErr       : LREAL := 0.1;   // 弦高误差带 [毫米] / the chord error band [millimeter]
    fSegLenA      : LREAL := 100.0; // 前段长 [毫米] / the former segment length [millimeter]
    fSegLenB      : LREAL := 100.0; // 后段长 [毫米] / the latter segment length [millimeter]
    bCalc         : BOOL := TRUE;   // 解算使能，失能输出安全侧零 [-] / the calc enable, disabling zeroes the outlets
END_VAR
VAR_OUTPUT
    fTanLen   : LREAL := 0.0; // 切点距拐角距离（两腿对称）[毫米] / the tangent distance from the corner [millimeter]
    fChordErr : LREAL := 0.0; // 弦高误差 [毫米] / the chord sagitta error [millimeter]
    bValid    : BOOL := FALSE; // 解算受理且可用 [-] / the solved and usable flag
    bErrBand  : BOOL := FALSE; // 弦高超误差带（信息级）[-] / the chord beyond the band, informational
    bTooLong  : BOOL := FALSE; // 切点距超段长一半（单调性自检，信息级）[-] / the tangent beyond the half segment, informational
    bClamped  : BOOL := FALSE; // 半径自动回夹发生（信息级）[-] / the radius auto clamp happened, informational
    bError    : BOOL := FALSE; // 故障标志（非有限或退化角）[-] / the fault flag
END_VAR
VAR CONSTANT
    DL_PCB_EPS     : LREAL := 1.0E-9;             // 退化阈值 [无量纲] / the degenerate threshold
    DL_PCB_ANGMIN  : LREAL := 1.0;                // 角度域下界 [度] / the angle floor
    DL_PCB_ANGMAX  : LREAL := 179.0;              // 角度域上界 [度] / the angle ceiling
    DL_PCB_DEG2RAD : LREAL := 0.0174532925199433; // 度到弧度系数 [弧度每度] / the degree to radian factor
END_VAR
VAR
    lrAng   : LREAL; // 角度工作量（钳后）[度] / the clamped angle work value
    lrHalf  : LREAL; // 半角工作量 [弧度] / the half angle in radian
    lrTanH  : LREAL; // 半角正切工作量 [无量纲] / the half angle tangent
    lrCosH  : LREAL; // 半角余弦工作量 [无量纲] / the half angle cosine
    lrR     : LREAL; // 半径工作量（可回夹）[毫米] / the radius work value, clampable
    lrRmax  : LREAL; // 误差带反算半径上界 [毫米] / the radius bound from the error band
    lrSegMin: LREAL; // 两段较短者 [毫米] / the shorter of the two segments
    bFin    : BOOL;  // 入参有限工作量 [-] / the input finiteness work flag
END_VAR

// 段 1｜输出预置与失能安全侧（四段式，R45）/ segment 1, the preset and the disabled safe side
fTanLen := 0.0; // 切点距预置零 / preset the tangent zero
fChordErr := 0.0; // 弦高预置零 / preset the chord zero
bValid := FALSE; // 有效预置假 / preset the valid false
bErrBand := FALSE; // 超带预置假 / preset the band flag false
bTooLong := FALSE; // 超长预置假 / preset the too long false
bClamped := FALSE; // 回夹预置假 / preset the clamp false
bError := FALSE; // 故障预置假 / preset the fault false
IF NOT bCalc THEN // 失能：输出保持安全侧零 / disabled, keep the safe zero
    RETURN; // 早退 / return early
END_IF

// 段 2｜非有限入参闸（五参数自反双判据全覆盖，R79）/ segment 2, the non finite gate
bFin := (fCornerAngDeg = fCornerAngDeg) AND ((fCornerAngDeg - fCornerAngDeg) = (fCornerAngDeg - fCornerAngDeg)) // 角度有限 / the angle finite
    AND (fBlendR = fBlendR) AND ((fBlendR - fBlendR) = (fBlendR - fBlendR)) // 半径有限 / the radius finite
    AND (fTolErr = fTolErr) AND ((fTolErr - fTolErr) = (fTolErr - fTolErr)) // 误差带有限 / the band finite
    AND (fSegLenA = fSegLenA) AND ((fSegLenA - fSegLenA) = (fSegLenA - fSegLenA)) // 前段有限 / the former finite
    AND (fSegLenB = fSegLenB) AND ((fSegLenB - fSegLenB) = (fSegLenB - fSegLenB)); // 后段有限 / the latter finite
IF NOT bFin THEN // 非有限命中 / a non finite hit
    bError := TRUE; // 置故障（本库纪律②不静默吞）/ raise the fault
    RETURN; // 早退 / return early
END_IF

// 段 3｜角度域钳制与三角量解算（除零前置闸，边界二三）/ segment 3, the angle clamp and the trigonometry
lrAng := fCornerAngDeg; // 装角度 / load the angle
IF lrAng < DL_PCB_ANGMIN THEN // 小角下钳（防 tan 爆炸）/ clamp the small angle
    lrAng := DL_PCB_ANGMIN; // 夹到下界 / clamp to the floor
    bClamped := TRUE; // 信息级 / informational
ELSIF lrAng > DL_PCB_ANGMAX THEN // 大角上钳（防退化）/ clamp the large angle
    lrAng := DL_PCB_ANGMAX; // 夹到上界 / clamp to the ceiling
    bClamped := TRUE; // 信息级 / informational
END_IF
lrHalf := lrAng * 0.5 * DL_PCB_DEG2RAD; // 半角弧度 / the half angle radian
lrTanH := TAN(lrHalf); // 半角正切 / the tangent
lrCosH := COS(lrHalf); // 半角余弦 / the cosine
IF ABS(lrTanH) < DL_PCB_EPS THEN // 退化角闸（切点距无界）/ the degenerate angle gate
    bError := TRUE; // 置故障 / raise the fault
    RETURN; // 早退 / return early
END_IF
lrR := ABS(fBlendR); // 半径取绝对值 / the radius absolute
fTanLen := lrR / lrTanH; // 切点距（除子已闸）/ the tangent distance, divided by the gated tan
fChordErr := lrR * (1.0 - lrCosH); // 弦高误差 / the chord error

// 段 4｜误差带回夹与单调性自检（单点回夹防互相覆盖，边界三四）/ segment 4, the band clamp and the monotonic check
bErrBand := fChordErr > fTolErr; // 超带判定 / the band verdict
IF bErrBand THEN // 超带：反算半径上界回夹 / beyond the band, recompute the radius bound
    IF (1.0 - lrCosH) > DL_PCB_EPS THEN // 除零再闸（角度域已保证，纵深）/ the divide gate, defense in depth
        lrRmax := fTolErr / (1.0 - lrCosH); // 半径上界 [毫米] / the radius bound
        fTanLen := lrRmax / lrTanH; // 回夹后切点距（除子已闸）/ the clamped tangent
        fChordErr := fTolErr; // 弦高回到带上（单点回夹口径）/ the chord to the band
        bClamped := TRUE; // 信息级回夹 / the informational clamp
    ELSE // 反算除子退化（不可达分支兜底）/ the unreachable fallback
        bError := TRUE; // 置故障 / raise the fault
        RETURN; // 早退 / return early
    END_IF
END_IF
lrSegMin := fSegLenA; // 取较短段 / take the shorter segment
IF fSegLenB < lrSegMin THEN // 后段更短 / the latter shorter
    lrSegMin := fSegLenB; // 换取 / take it
END_IF
bTooLong := fTanLen > (0.5 * lrSegMin); // 单调性自检（切点距 ≤ 半段长）/ the monotonic check
bValid := TRUE; // 解算可用 / the solve usable
END_FUNCTION_BLOCK
