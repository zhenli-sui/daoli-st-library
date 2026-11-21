(*
  ==================================================================
  组件名 Component  : FC_DL_Kalman2DSmoother
  分类   Category   : DL_MathData
  复杂度 Complexity  : cx5
  版本   Version    : 1.0.0
  功能   Purpose    : 2D 常速模型稳态卡尔曼平滑（纯函数形态，状态由外部持有）。
                      输入本拍测量 (zX, zY) 与上拍状态 (x, y, vx, vy)、采样周期 dt、
                      过程噪声 q、量测噪声 r，按标量序贯近似输出更新后状态与位置
                      估计。协方差用标量稳态近似：位置增益 alpha = q·dt / (q·dt + r)，
                      速度增益 beta = alpha² / (2 - alpha)（alpha-beta 滤波器即稳态
                      二态卡尔曼，公开结果）；速度修正经 beta/dt 施加。
  来源   Source     : ROADMAP R56 池（与 FB_DL_KalmanFilter1D 分工：1D 标量 vs 2D 常速）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；稳态卡尔曼与 alpha-beta
                      滤波等价性为公开控制理论结果，clean-room 自研实现，未复制任何
                      闭源代码行。
  平台   Platform   : 纯 IEC 61131-3（LREAL 运算，无私有库、无幂运算符）
  作者   Author     : 道莅代码库 · PLC 编程专家（R56）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件为纯函数，无跨扫描周期状态驻留，协方差不外显（标量稳态
                         近似内嵌于增益解析式，属主边界）；
                      二 失败语义（R191 显式声明）：r <= 0 / dt <= 0 / q < 0 / 任一输入
                         非有限时，出口原样返回上拍状态并置 bInvalid（冻结保持）；
                      三 dt 下界 1.0E-6 防速度修正除零（beta/dt）；
                      四 无全局变量、无外部变量声明、无物理地址寻址、无定时器（纯函数）。
  输出契约 Output contract:
                      xN / yN / vxN / vyN 仅在 bInvalid = FALSE 时为更新后状态；
                      本件为纯函数，无跨扫描周期状态驻留。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R56 首版（批 2 · 序号 6）
  ==================================================================
*)

FUNCTION FC_DL_Kalman2DSmoother : BOOL
VAR_INPUT
    zX : LREAL; // X 轴测量值 [长度单位] / X axis measurement [length unit]
    zY : LREAL; // Y 轴测量值 [长度单位] / Y axis measurement [length unit]
    x  : LREAL; // 上拍 X 位置估计 [长度单位] / previous X position estimate [length unit]
    y  : LREAL; // 上拍 Y 位置估计 [长度单位] / previous Y position estimate [length unit]
    vx : LREAL; // 上拍 X 速度估计 [长度每秒] / previous X velocity estimate [length per second]
    vy : LREAL; // 上拍 Y 速度估计 [长度每秒] / previous Y velocity estimate [length per second]
    dt : LREAL; // 采样周期 [秒]，域 大于零 / sample period [second], domain above zero
    q  : LREAL; // 过程噪声强度（每秒）[平方长度每秒] / process noise intensity per second [square length per second]
    r  : LREAL; // 量测噪声方差 [平方长度] / measurement noise variance [square length]
END_VAR
VAR_OUTPUT
    xN      : LREAL; // 更新后 X 位置估计 [长度单位] / updated X position estimate [length unit]
    yN      : LREAL; // 更新后 Y 位置估计 [长度单位] / updated Y position estimate [length unit]
    vxN     : LREAL; // 更新后 X 速度估计 [长度每秒] / updated X velocity estimate [length per second]
    vyN     : LREAL; // 更新后 Y 速度估计 [长度每秒] / updated Y velocity estimate [length per second]
    bInvalid: BOOL;  // 输入无效，出口原样返回上拍状态 [-] / the input is void, the outlet returns the previous state unchanged
END_VAR
VAR
    _bFin  : BOOL := FALSE;  // 九个输入全部有限 [-] / all nine inputs are finite
    _fDt   : LREAL := 0.0;   // 钳定后的采样周期 [秒] / the clamped sample period [second]
    _fQdt  : LREAL := 0.0;   // 过程噪声强度乘周期 [平方长度] / process noise times the period
    _fAlp  : LREAL := 0.0;   // 位置增益 alpha [无量纲] / the position gain alpha
    _fBta  : LREAL := 0.0;   // 速度增益 beta [无量纲] / the velocity gain beta
    _fPx   : LREAL := 0.0;   // X 轴位置预测 [长度单位] / the X position prediction
    _fPy   : LREAL := 0.0;   // Y 轴位置预测 [长度单位] / the Y position prediction
    _fIx   : LREAL := 0.0;   // X 轴新息 [长度单位] / the X innovation
    _fIy   : LREAL := 0.0;   // Y 轴新息 [长度单位] / the Y innovation
END_VAR

// 段 1｜非有限闸（R151 全覆盖）与参数域闸 / segment 1, finiteness gate over every input and the parameter domain gate
_bFin := (zX = zX) AND ((zX - zX) = (zX - zX)) AND (zY = zY) AND ((zY - zY) = (zY - zY)) AND (x = x) AND ((x - x) = (x - x)) AND (y = y) AND ((y - y) = (y - y)) AND (vx = vx) AND ((vx - vx) = (vx - vx)) AND (vy = vy) AND ((vy - vy) = (vy - vy)) AND (dt = dt) AND ((dt - dt) = (dt - dt)) AND (q = q) AND ((q - q) = (q - q)) AND (r = r) AND ((r - r) = (r - r)); // 九输入有限性 / finiteness of all nine inputs
IF (NOT _bFin) OR (dt <= 0.0) OR (r <= 0.0) OR (q < 0.0) THEN // 输入无效或参数越域 / the input is void or a parameter is out of domain
    xN := x;   // 冻结保持：原样返回上拍状态（R191 显式声明）/ frozen hold, the previous state passes through unchanged
    yN := y;   // 冻结保持 / frozen hold
    vxN := vx; // 冻结保持 / frozen hold
    vyN := vy; // 冻结保持 / frozen hold
    bInvalid := TRUE; // 置无效标志 / raise the invalid flag
    FC_DL_Kalman2DSmoother := FALSE; // 函数返回失败 / the function returns failure
    RETURN; // 早退 / early return
END_IF

// 段 2｜稳态增益计算（标量近似） / segment 2, the steady state gains by the scalar approximation
_fDt := dt; // 周期直通 / the period passes through
IF _fDt < 1.0E-6 THEN // 周期过小 / the period is too small
    _fDt := 1.0E-6; // 抬到下限，防速度修正除零 / raised against the velocity divisor
END_IF
_fQdt := q * _fDt; // 过程噪声强度乘周期 / the process noise times the period
_fAlp := _fQdt / (_fQdt + r); // 位置增益，除子为 q·dt + r 已证 > 0 / the position gain, the divisor is proven positive
_fBta := _fAlp * _fAlp / (2.0 - _fAlp); // 速度增益，除子 2 - alpha 已证 > 1（alpha < 1 结构性成立）/ the velocity gain, the divisor is proven above one since alpha is structurally below one

// 段 3｜X 轴预测与更新 / segment 3, the X axis prediction and update
_fPx := x + vx * _fDt; // 常速位置预测 / the constant velocity position prediction
_fIx := zX - _fPx; // 新息 / the innovation
xN := _fPx + _fAlp * _fIx; // 位置更新 / the position update
vxN := vx + (_fBta / _fDt) * _fIx; // 速度更新（除子已钳下限）/ the velocity update with the proven divisor

// 段 4｜Y 轴预测与更新 / segment 4, the Y axis prediction and update
_fPy := y + vy * _fDt; // 常速位置预测 / the constant velocity position prediction
_fIy := zY - _fPy; // 新息 / the innovation
yN := _fPy + _fAlp * _fIy; // 位置更新 / the position update
vyN := vy + (_fBta / _fDt) * _fIy; // 速度更新（除子已钳下限）/ the velocity update with the proven divisor

bInvalid := FALSE; // 有效标志 / the valid flag
FC_DL_Kalman2DSmoother := TRUE; // 函数返回成功 / the function returns success
END_FUNCTION
