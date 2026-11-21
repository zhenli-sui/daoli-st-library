(*
  ==================================================================
  组件名 Component  : FC_DL_QuatSlerp
  分类   Category   : DL_MathData
  复杂度 Complexity  : cx3
  版本   Version    : 1.0.0
  功能   Purpose    : 单位四元数球面线性插值 SLERP。输入两个四元数（x / y / z / w）
                      与插值参数 t，输出最短路径中间四元数并归一化；dot < 0 取反
                      qB 走最短路径，dot > 0.9995 或 SIN(theta) 过小退化为线性插值
                      后归一化，任一输入零范数或非有限置 bInvalid 并给安全侧输出。
  来源   Source     : t2-1-lgf-math
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；SLERP 为公开四元数插值
                      方法（球面几何公开结果），clean-room 自研实现，未复制任何闭源
                      代码行。
  平台   Platform   : 纯 IEC 61131-3（LREAL / ACOS / SIN / SQRT，无私有库、无幂运算符）
  作者   Author     : 道莅代码库 · PLC 编程专家（R56）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 本件只做两姿态间中间四元数插值，不做旋转向量作用、不做角度
                         归一（属主边界，反证句见 R56 台账第 2 行）；
                      二 dot 一律先钳到 [-1, 1] 再取 ACOS，防浮点越域（ACOS 定义域闸）；
                      三 插值参数 t 越出 [0, 1] 先回钳再使用，不判故障；
                      四 非有限或零范数输入不穿透出口：一者范数无效则取另一者归一化，
                         两者均无效取单位四元数（w = 1）并置 bInvalid（R127 安全侧常量）；
                      五 无全局变量、无外部变量声明、无物理地址寻址、无定时器（纯函数）。
  输出契约 Output contract:
                      qX / qY / qZ / qW 出口恒为单位范数（除 bInvalid 安全侧出口外）；
                      bLinPath = 本拍走了退化线性插值路径；标志优先级 bInvalid > bLinPath；
                      本件为纯函数，无跨扫描周期状态驻留。
  修订记录 Revision  :
    2026-11-20  v1.0.0  R56 首版（批 1 · 序号 2）
  ==================================================================
*)

FUNCTION FC_DL_QuatSlerp : BOOL
VAR_INPUT
    qaX : LREAL; // 四元数 A 的 x 分量 [无量纲] / x component of quaternion A
    qaY : LREAL; // 四元数 A 的 y 分量 [无量纲] / y component of quaternion A
    qaZ : LREAL; // 四元数 A 的 z 分量 [无量纲] / z component of quaternion A
    qaW : LREAL; // 四元数 A 的 w 分量 [无量纲] / w component of quaternion A
    qbX : LREAL; // 四元数 B 的 x 分量 [无量纲] / x component of quaternion B
    qbY : LREAL; // 四元数 B 的 y 分量 [无量纲] / y component of quaternion B
    qbZ : LREAL; // 四元数 B 的 z 分量 [无量纲] / z component of quaternion B
    qbW : LREAL; // 四元数 B 的 w 分量 [无量纲] / w component of quaternion B
    t   : LREAL; // 插值参数，越域回钳 [无量纲] / interpolation parameter, clamped into the unit range
END_VAR
VAR_OUTPUT
    qX       : LREAL; // 插值四元数 x 分量（单位范数）[无量纲] / x component of the interpolated quaternion
    qY       : LREAL; // 插值四元数 y 分量（单位范数）[无量纲] / y component of the interpolated quaternion
    qZ       : LREAL; // 插值四元数 z 分量（单位范数）[无量纲] / z component of the interpolated quaternion
    qW       : LREAL; // 插值四元数 w 分量（单位范数）[无量纲] / w component of the interpolated quaternion
    bInvalid : BOOL;  // 输入非有限或双零范数，出口取安全侧 [-] / input non finite or both norms void, the outlet takes the safe side
    bLinPath : BOOL;  // 本拍走了退化线性插值路径 [-] / the degenerate linear path was taken this call
END_VAR
VAR
    _fT      : LREAL := 0.0; // 钳位后的插值参数 [无量纲] / clamped interpolation parameter
    _fNa     : LREAL := 0.0; // 四元数 A 范数平方 [无量纲] / squared norm of quaternion A
    _fNb     : LREAL := 0.0; // 四元数 B 范数平方 [无量纲] / squared norm of quaternion B
    _fDot    : LREAL := 0.0; // 四元数点积 [无量纲] / quaternion dot product
    _fTheta  : LREAL := 0.0; // 两四元数夹角 [弧度] / angle between the quaternions [radian]
    _fSinT   : LREAL := 0.0; // 夹角正弦 [无量纲] / sine of the angle
    _fWa     : LREAL := 0.0; // A 端权重 [无量纲] / weight of the A end
    _fWb     : LREAL := 0.0; // B 端权重 [无量纲] / weight of the B end
    _fX      : LREAL := 0.0; // 插值结果 x 分量暂存 [无量纲] / interpolation result x component
    _fY      : LREAL := 0.0; // 插值结果 y 分量暂存 [无量纲] / interpolation result y component
    _fZ      : LREAL := 0.0; // 插值结果 z 分量暂存 [无量纲] / interpolation result z component
    _fW      : LREAL := 0.0; // 插值结果 w 分量暂存 [无量纲] / interpolation result w component
    _fNorm   : LREAL := 0.0; // 结果范数平方 [无量纲] / squared norm of the result
    _fInvN   : LREAL := 0.0; // 结果范数倒数 [无量纲] / reciprocal of the result norm
    _bFinA   : BOOL := FALSE; // A 分量全部有限 [-] / all components of A are finite
    _bFinB   : BOOL := FALSE; // B 分量全部有限 [-] / all components of B are finite
    _bFinT   : BOOL := FALSE; // 插值参数有限 [-] / the parameter is finite
END_VAR

// 段 1｜非有限闸（R151 全覆盖）：九个输入逐项判，NaN 自反、Inf 差值自减 / segment 1, finiteness gate over every input
_bFinA := (qaX = qaX) AND ((qaX - qaX) = (qaX - qaX)) AND (qaY = qaY) AND ((qaY - qaY) = (qaY - qaY)) AND (qaZ = qaZ) AND ((qaZ - qaZ) = (qaZ - qaZ)) AND (qaW = qaW) AND ((qaW - qaW) = (qaW - qaW)); // A 分量有限性 / finiteness of A
_bFinB := (qbX = qbX) AND ((qbX - qbX) = (qbX - qbX)) AND (qbY = qbY) AND ((qbY - qbY) = (qbY - qbY)) AND (qbZ = qbZ) AND ((qbZ - qbZ) = (qbZ - qbZ)) AND (qbW = qbW) AND ((qbW - qbW) = (qbW - qbW)); // B 分量有限性 / finiteness of B
_bFinT := (t = t) AND ((t - t) = (t - t)); // 参数有限性 / finiteness of the parameter
IF (NOT _bFinA) OR (NOT _bFinB) OR (NOT _bFinT) THEN // 非有限输入 / non finite input
    qX := 0.0; // 安全侧取单位四元数（R127 常量）/ the safe side takes the identity quaternion
    qY := 0.0; // 安全侧 / the safe side
    qZ := 0.0; // 安全侧 / the safe side
    qW := 1.0; // 安全侧 / the safe side
    bInvalid := TRUE; // 置无效标志 / raise the invalid flag
    bLinPath := FALSE; // 路径标志不成立 / the path flag is false
    FC_DL_QuatSlerp := FALSE; // 函数返回失败 / the function returns failure
    RETURN; // 早退 / early return
END_IF

// 段 2｜参数回钳与范数判据 / segment 2, parameter clamp and norm verdict
_fT := t; // 参数直通 / the parameter passes through
IF _fT < 0.0 THEN // 下越域 / below the unit range
    _fT := 0.0; // 回钳到零 / clamp to zero
ELSIF _fT > 1.0 THEN // 上越域 / above the unit range
    _fT := 1.0; // 回钳到一 / clamp to one
END_IF
_fNa := qaX * qaX + qaY * qaY + qaZ * qaZ + qaW * qaW; // A 范数平方 / squared norm of A
_fNb := qbX * qbX + qbY * qbY + qbZ * qbZ + qbW * qbW; // B 范数平方 / squared norm of B
bInvalid := FALSE; // 无效标志预置假 / preset the invalid flag to false
bLinPath := FALSE; // 路径标志预置假 / preset the path flag to false
IF (_fNa < 1.0E-12) AND (_fNb < 1.0E-12) THEN // 双零范数兜底 / both norms void
    qX := 0.0; // 安全侧取单位四元数 / the safe side takes the identity quaternion
    qY := 0.0; // 安全侧 / the safe side
    qZ := 0.0; // 安全侧 / the safe side
    qW := 1.0; // 安全侧 / the safe side
    bInvalid := TRUE; // 置无效标志 / raise the invalid flag
    FC_DL_QuatSlerp := FALSE; // 函数返回失败 / the function returns failure
    RETURN; // 早退 / early return
ELSIF _fNa < 1.0E-12 THEN // A 零范数，取 B 归一化 / A void, take the normalised B
    _fInvN := 1.0 / SQRT(_fNb); // B 范数倒数，除子为范数已证超阈 / reciprocal of the proven norm of B
    qX := qbX * _fInvN; // B 归一化 x / normalised x of B
    qY := qbY * _fInvN; // B 归一化 y / normalised y of B
    qZ := qbZ * _fInvN; // B 归一化 z / normalised z of B
    qW := qbW * _fInvN; // B 归一化 w / normalised w of B
    bInvalid := TRUE; // 置无效标志（输入侧缺陷留痕）/ raise the invalid flag for the input defect
    FC_DL_QuatSlerp := TRUE; // 函数返回成功（出口有效）/ the function returns success
    RETURN; // 早退 / early return
ELSIF _fNb < 1.0E-12 THEN // B 零范数，取 A 归一化 / B void, take the normalised A
    _fInvN := 1.0 / SQRT(_fNa); // A 范数倒数，除子为范数已证超阈 / reciprocal of the proven norm of A
    qX := qaX * _fInvN; // A 归一化 x / normalised x of A
    qY := qaY * _fInvN; // A 归一化 y / normalised y of A
    qZ := qaZ * _fInvN; // A 归一化 z / normalised z of A
    qW := qaW * _fInvN; // A 归一化 w / normalised w of A
    bInvalid := TRUE; // 置无效标志（输入侧缺陷留痕）/ raise the invalid flag for the input defect
    FC_DL_QuatSlerp := TRUE; // 函数返回成功 / the function returns success
    RETURN; // 早退 / early return
END_IF

// 段 3｜点积与最短路径取反 / segment 3, dot product and the shortest path negation
_fDot := qaX * qbX + qaY * qbY + qaZ * qbZ + qaW * qbW; // 四元数点积 / the dot product
IF _fDot < 0.0 THEN // 点积为负，反取 B 走最短路径 / a negative dot product negates B for the shortest path
    qbX := -qbX; // B 取反 x / negate the x of B
    qbY := -qbY; // B 取反 y / negate the y of B
    qbZ := -qbZ; // B 取反 z / negate the z of B
    qbW := -qbW; // B 取反 w / negate the w of B
    _fDot := -_fDot; // 点积同步取反 / the dot product is negated the same way
END_IF
IF _fDot > 1.0 THEN // 点积上越域钳位，防 ACOS 定义域越界 / the dot product is clamped against the ACOS domain
    _fDot := 1.0; // 钳到一 / clamp to one
END_IF

// 段 4｜退化判据与 SLERP 权重 / segment 4, degeneracy verdict and the SLERP weights
IF _fDot > 0.9995 THEN // 近平行，退化走线性插值 / nearly parallel, the linear path is taken
    bLinPath := TRUE; // 置线性路径标志 / raise the linear path flag
    _fX := qaX + _fT * (qbX - qaX); // 线性插值 x / linear interpolation of x
    _fY := qaY + _fT * (qbY - qaY); // 线性插值 y / linear interpolation of y
    _fZ := qaZ + _fT * (qbZ - qaZ); // 线性插值 z / linear interpolation of z
    _fW := qaW + _fT * (qbW - qaW); // 线性插值 w / linear interpolation of w
ELSE // 一般路径 / the general path
    _fTheta := ACOS(_fDot); // 两四元数夹角，定义域已钳 [0, 1] / the angle, the domain is proven clamped
    _fSinT := SIN(_fTheta); // 夹角正弦 / the sine of the angle
    IF _fSinT < 1.0E-9 THEN // 正弦过小，退化走线性插值 / the sine is too small, the linear path is taken
        bLinPath := TRUE; // 置线性路径标志 / raise the linear path flag
        _fX := qaX + _fT * (qbX - qaX); // 线性插值 x / linear interpolation of x
        _fY := qaY + _fT * (qbY - qaY); // 线性插值 y / linear interpolation of y
        _fZ := qaZ + _fT * (qbZ - qaZ); // 线性插值 z / linear interpolation of z
        _fW := qaW + _fT * (qbW - qaW); // 线性插值 w / linear interpolation of w
    ELSE // 球面插值权重 / the spherical weights
        _fWa := SIN((1.0 - _fT) * _fTheta) / _fSinT; // A 端权重，除子为正弦已证超阈 / the weight of A, the divisor is the proven sine
        _fWb := SIN(_fT * _fTheta) / _fSinT; // B 端权重，除子为同一已证正弦 / the weight of B, the same proven sine divisor
        _fX := _fWa * qaX + _fWb * qbX; // 球面插值 x / spherical interpolation of x
        _fY := _fWa * qaY + _fWb * qbY; // 球面插值 y / spherical interpolation of y
        _fZ := _fWa * qaZ + _fWb * qbZ; // 球面插值 z / spherical interpolation of z
        _fW := _fWa * qaW + _fWb * qbW; // 球面插值 w / spherical interpolation of w
    END_IF
END_IF

// 段 5｜出口归一化 / segment 5, normalise the outlet
_fNorm := _fX * _fX + _fY * _fY + _fZ * _fZ + _fW * _fW; // 结果范数平方 / the squared norm of the result
IF _fNorm < 1.0E-12 THEN // 结果范数无效兜底（双端单位范数下不可达，防御性保留）/ the void norm fallback, unreachable for unit inputs, kept as a defence
    qX := 0.0; // 安全侧取单位四元数 / the safe side takes the identity quaternion
    qY := 0.0; // 安全侧 / the safe side
    qZ := 0.0; // 安全侧 / the safe side
    qW := 1.0; // 安全侧 / the safe side
    bInvalid := TRUE; // 置无效标志 / raise the invalid flag
    FC_DL_QuatSlerp := FALSE; // 函数返回失败 / the function returns failure
    RETURN; // 早退 / early return
END_IF
_fInvN := 1.0 / SQRT(_fNorm); // 范数倒数，除子已证超阈 / the reciprocal of the proven norm
qX := _fX * _fInvN; // 归一化出口 x / the normalised outlet x
qY := _fY * _fInvN; // 归一化出口 y / the normalised outlet y
qZ := _fZ * _fInvN; // 归一化出口 z / the normalised outlet z
qW := _fW * _fInvN; // 归一化出口 w / the normalised outlet w
FC_DL_QuatSlerp := TRUE; // 函数返回成功 / the function returns success
END_FUNCTION
