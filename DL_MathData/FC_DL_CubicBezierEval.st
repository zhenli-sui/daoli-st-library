(*==============================================================================
 * 组件名称 (Component)  : FC_DL_CubicBezierEval
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library 与 LREAL 四则运算，零厂商私有库
 * 功能描述 (Function)   : 一维标量三次贝塞尔曲线求值。给定四个控制点 P0~P3 与参数 t，
 *                         按 De Casteljau 递推（三级线性插值）求点值 fValue，并给出对 t 的
 *                         一阶导数 fTangent。选择 De Casteljau 而非多项式展开的理由：三次
 *                         Bernstein 展开在 t 接近 0/1 时会出现大系数相消（P0 与 P1 量级接近时
 *                         有效位丢失），De Casteljau 每级只做凸组合，数值稳定且中间量有界。
 * 分工声明 (Scope)      : 本件是**参数曲线求值**（已知控制点，求任意 t 处点与切线）；
 *                         `FC_DL_CubicSplineInterp` 是**数据点插值**（已知离散样本点，构造
 *                         分段三次样条后插值）。二者数学对象不同（Bernstein 基 vs 三次样条基），
 *                         不可互换调用：把本件当插值用会得到穿过控制包络的曲线而非过样本点曲线。
 * 接口     (Interface)  : 输入 fP0 / fP1 / fP2 / fP3 四个控制点标量值、fT 曲线参数（域 [0,1]，
 *                         越域钳制）；输出 fValue 点值、fTangent 一阶导数值、bClamped 参数
 *                         越域钳制标记、uErrorId 事件码；返回值 BOOL = TRUE 表示本次结果有效。
 * 边界     (Boundary)   : ① 参数越域（fT < 0 或 fT > 1）钳到端点并置 bClamped，不报错（钳制
 *                         是可预期的调用方行为，非故障）；
 *                         ② 任一输入非有限（NaN / ±Inf）→ 输出 0、置故障码、返回 FALSE，
 *                         绝不向下游传播 NaN（下游联锁会把 NaN 比较结果全判 FALSE 而静默失效）；
 *                         ③ 结果非有限复检兜底（防御纵深，正常域内不可能触发）；
 *                         ④ 纯函数零状态，无 TON / 边沿实例（R6 / R7 本件标注 N/A：无顺序状态机，
 *                         无实例调用，非法状态不可能出现）；
 *                         ⑤ 零全局耦合（无 GVL / 无物理地址）。
 * 判等例外 (Exception)  : 本件非有限判定使用 `x <> x`（NaN 自反）与 `(x-x) <> (x-x)`（Inf 差值
 *                         自减），此为**浮点判等禁令的唯一例外**（R79 / 机检 G6 白名单），
 *                         不得据此推断本件允许对量值使用 `=` / `<>`：量值比较在本件中不存在。
 * 码表     (Codes)      : 16#0001_03ED 故障级：贝塞尔求值故障（输入非有限 / 输出非有限复检失败），
 *                         本件单码，不细分（纯函数无归因成员，原因由入参侧唯一确定）。
 *                         16#0001_04B0 信息级：本次求值正常完成（供上层区分「未调用」与「调用成功」）。
 *                         加码反证（R90）：正常完成与「参数被钳制」在 fValue / fTangent 上不可区分
 *                         （钳制后 t 落到端点，结果与恰好传入端点值完全一致），故须以一码留痕；
 *                         钳制本身另有 bClamped 布尔出口，不再单立钳制码。
 *                         码段说明：0001 段故障子带 03xx / 信息子带 04xx，本件取 03ED / 04B0
 *                         （源码实扫该两槽为空，续接同子带已用最大值，未回填碎片孔洞）。
 * 开源溯源 (Origin)     : 道莅自研 clean-room（参考 Bernstein 基与 De Casteljau 公开算法定义，
 *                         零代码行复制；t2-1-lgf 数学子族）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R45 首版（批次 1 · 序号 4）
 *==============================================================================*)

FUNCTION FC_DL_CubicBezierEval : BOOL
VAR_INPUT
    fP0 : LREAL := 0.0;      // 控制点 P0 标量值（曲线起点），须有限 [工程单位] / Control point P0, curve start, must be finite
    fP1 : LREAL := 0.0;      // 控制点 P1 标量值（起点切线方向控制），须有限 [工程单位] / Control point P1, start tangent control
    fP2 : LREAL := 0.0;      // 控制点 P2 标量值（终点切线方向控制），须有限 [工程单位] / Control point P2, end tangent control
    fP3 : LREAL := 0.0;      // 控制点 P3 标量值（曲线终点），须有限 [工程单位] / Control point P3, curve end
    fT  : LREAL := 0.0;      // 曲线参数，有效域 0.0 ~ 1.0（越域钳制） [-] / Curve parameter, domain 0.0..1.0, out-of-range clamped
END_VAR
VAR_OUTPUT
    fValue   : LREAL;        // 曲线点值 B(t) [工程单位] / Curve point value B(t)
    fTangent : LREAL;        // 一阶导数 dB/dt（对 t 求导，非对弧长） [工程单位/参数] / First derivative dB/dt w.r.t. t
    bClamped : BOOL;         // 参数越域钳制标记 [-] / Parameter clamp flag
    uErrorId : UDINT;        // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    fTs      : LREAL;        // 钳制后的参数 t [-] / Clamped parameter t
    fOmT     : LREAL;        // 补参数 (1 - t) [-] / Complement parameter (1 - t)
    fQ0      : LREAL;        // 一级插值节点 Q0 [工程单位] / Level-1 node Q0
    fQ1      : LREAL;        // 一级插值节点 Q1 [工程单位] / Level-1 node Q1
    fQ2      : LREAL;        // 一级插值节点 Q2 [工程单位] / Level-1 node Q2
    fR0      : LREAL;        // 二级插值节点 R0 [工程单位] / Level-2 node R0
    fR1      : LREAL;        // 二级插值节点 R1 [工程单位] / Level-2 node R1
    fDiff01  : LREAL;        // 控制点差 P1 - P0 [工程单位] / Control point difference P1 - P0
    fDiff12  : LREAL;        // 控制点差 P2 - P1 [工程单位] / Control point difference P2 - P1
    fDiff23  : LREAL;        // 控制点差 P3 - P2 [工程单位] / Control point difference P3 - P2
    bNonFin  : BOOL;         // 输入非有限判定结果 [-] / Non-finite input verdict
END_VAR
VAR CONSTANT
    DL_BEZ_ORDER : LREAL := 3.0;   // 三次曲线阶数乘子（导数系数），编译期常量 [-] / Cubic order multiplier for derivative, compile-time constant
END_VAR

(* —— 段 1：返回值与输出预置（任何早退路径都不留脏值） —— *)
FC_DL_CubicBezierEval := FALSE;      // 返回值预置无效 / Preset return value invalid
fValue   := 0.0;                     // 点值预置 0，故障相即安全侧 / Point value preset 0, safe side in fault
fTangent := 0.0;                     // 切线预置 0 / Tangent preset 0
bClamped := FALSE;                   // 钳制标记预置 FALSE / Clamp flag preset FALSE
uErrorId := 16#0000_0000;            // 事件码预置无事件 / Event code preset none

(* —— 段 2：域闸（先判后算，禁算完再兜） —— *)
bNonFin := (fP0 <> fP0) OR (fP1 <> fP1) OR (fP2 <> fP2) OR (fP3 <> fP3) OR (fT <> fT)          // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive test
        OR ((fP0 - fP0) <> (fP0 - fP0)) OR ((fP1 - fP1) <> (fP1 - fP1))                        // P1 差值自减判 Inf / Inf test on P1 via self-subtraction
        OR ((fP2 - fP2) <> (fP2 - fP2)) OR ((fP3 - fP3) <> (fP3 - fP3))                        // P2 / P3 差值自减判 Inf / Inf test on P2 and P3
        OR ((fT - fT) <> (fT - fT));                                                            // 参数差值自减判 Inf / Inf test on the parameter
IF bNonFin THEN
    uErrorId := 16#0001_03ED;        // 故障级：输入非有限，输出保持 0 / Fault-level: non-finite input, outputs stay zero
    RETURN;                          // 不抛异常，直接带码返回 / Return with code, no exception
END_IF

(* —— 段 3：参数钳制（越域钳到 [0,1] 并置标记） —— *)
IF fT < 0.0 THEN
    fTs := 0.0;                      // 下界钳制 / Clamp to lower bound
    bClamped := TRUE;                // 置钳制标记 / Set clamp flag
ELSIF fT > 1.0 THEN
    fTs := 1.0;                      // 上界钳制 / Clamp to upper bound
    bClamped := TRUE;                // 置钳制标记 / Set clamp flag
ELSE
    fTs := fT;                       // 域内直通 / Pass through inside domain
END_IF
fOmT := 1.0 - fTs;                   // 补参数 (1 - t) / Complement parameter

(* —— 段 4：De Casteljau 三级递推（委托内核，凸组合有界） —— *)
fQ0 := fOmT * fP0 + fTs * fP1;       // 一级插值 Q0 / Level-1 interpolation Q0
fQ1 := fOmT * fP1 + fTs * fP2;       // 一级插值 Q1 / Level-1 interpolation Q1
fQ2 := fOmT * fP2 + fTs * fP3;       // 一级插值 Q2 / Level-1 interpolation Q2
fR0 := fOmT * fQ0 + fTs * fQ1;       // 二级插值 R0 / Level-2 interpolation R0
fR1 := fOmT * fQ1 + fTs * fQ2;       // 二级插值 R1 / Level-2 interpolation R1
fValue := fOmT * fR0 + fTs * fR1;    // 三级插值 = 曲线点值 / Level-3 interpolation = curve point value
fDiff01 := fP1 - fP0;                // 起点段差 / Start segment difference
fDiff12 := fP2 - fP1;                // 中段差 / Middle segment difference
fDiff23 := fP3 - fP2;                // 终点段差 / End segment difference
fTangent := DL_BEZ_ORDER * ( fOmT * fOmT * fDiff01
                           + 2.0 * fOmT * fTs * fDiff12
                           + fTs * fTs * fDiff23 );   // Bernstein 导数式 dB/dt / Bernstein derivative dB/dt

(* —— 段 5：结果非有限复检兜底（防御纵深） —— *)
IF (fValue <> fValue) OR ((fValue - fValue) <> (fValue - fValue))
   OR (fTangent <> fTangent) OR ((fTangent - fTangent) <> (fTangent - fTangent)) THEN
    fValue   := 0.0;                 // 复检失败：点值归 0 / Recheck failed: point value zeroed
    fTangent := 0.0;                 // 复检失败：切线归 0 / Recheck failed: tangent zeroed
    uErrorId := 16#0001_03ED;        // 故障级：输出非有限 / Fault-level: non-finite output
    RETURN;                          // 带码返回 / Return with code
END_IF

(* —— 段 6：正常出口 —— *)
uErrorId := 16#0001_04B0;            // 信息级：求值正常完成 / Info-level: evaluation completed
FC_DL_CubicBezierEval := TRUE;       // 返回值置有效 / Return value valid

END_FUNCTION
