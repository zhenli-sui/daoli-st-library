(*
    FC_DL_AffineTransformPoint —— 2D 仿射点变换
    ------------------------------------------------------------------
    分类      : DL_MathData / Transform
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : T2-1 LGF · Math（源矩阵明列「仿射变换组合族待挖」；只借该族归属
                Math 的分类事实）；旋转 / 缩放 / 平移的合成顺序为本库自有规格，
                角度归一式的工程写法、码位与错误分级 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R18）
    ------------------------------------------------------------------
    功能说明  : 单次完成「绕原点旋转 → 各轴缩放 → 平移」的合成，输出变换后坐标。
                现场语义：视觉像素坐标到机械 mm 坐标（含相机安装角偏差）、纠偏平台
                坐标映射、印刷套准偏移换算；
                角度归一用「减 360 乘整数商」单算式路径，不用循环也不用取余
                （浮点取余在三平台行为不一致）；三角函数直接调用内建 SIN / COS，
                绝不重实现（T0 判据 2）；
                缩放为 0 使变换不可逆，按故障拒绝并原值回送，绝不返回被压平的点；
                输入与中间结果双向非有限复检，1e38 量级缩放乘大坐标的溢出能被抓住。
    错误码    : 16#0001_0241 旋转角超正负 360 度已归一——信息级，正常防御
                16#0001_0242 预留禁用（信息级，不得挪用）
                16#0001_0318 缩放因子为 0（变换不可逆）——故障级，返回原点值
                16#0001_0319 输入或中间结果非有限（NaN / 正负 INF / 溢出）——故障级，输出 0
                16#0001_031A 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_0241 用 / 16#0001_0242 预留 ｜ 16#0001_0318 用 / 16#0001_0319 用 / 16#0001_031A 预留
    状态机    : N/A —— 纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 纯组合函数，无定时器、无内部驻留状态；变换参数由调用方保证在同一
                标定批次内恒定（本库统一约定：标定参数只在停机态下发）。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R18）
*)
FUNCTION FC_DL_AffineTransformPoint : BOOL
VAR_INPUT
    fX       : REAL := 0.0;                    // 源点 X [用户单位] / source point X [user unit]
    fY       : REAL := 0.0;                    // 源点 Y [用户单位] / source point Y [user unit]
    fRotDeg  : REAL := 0.0;                    // 旋转角，正为逆时针 [度]，范围 -720.0~720.0 / rotation angle, positive counter clockwise [deg], range -720.0~720.0
    fScaleX  : REAL := 1.0;                    // X 缩放比 [比值]，范围 0.001~1000.0，禁 0 / X scale ratio [ratio], range 0.001~1000.0, zero forbidden
    fScaleY  : REAL := 1.0;                    // Y 缩放比 [比值]，范围 0.001~1000.0，禁 0 / Y scale ratio [ratio], range 0.001~1000.0, zero forbidden
    fTx      : REAL := 0.0;                    // X 平移量 [用户单位] / X translation [user unit]
    fTy      : REAL := 0.0;                    // Y 平移量 [用户单位] / Y translation [user unit]
END_VAR
VAR_OUTPUT
    fOutX  : REAL;                             // 变换后 X [用户单位] / transformed X [user unit]
    fOutY  : REAL;                             // 变换后 Y [用户单位] / transformed Y [user unit]
    eErr   : UDINT;                            // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;                             // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid : BOOL;                             // 结果是否可用 / result usable flag
END_VAR
VAR
    fAngNorm : REAL;                           // 归一后角度 [度]，范围 0~360 / normalised angle [deg], range 0~360
    fRad     : REAL;                           // 归一后角度换算的弧度 [弧度] / normalised angle in radians [rad]
    fCos     : REAL;                           // 余弦值，范围 -1.0~1.0 [无量纲] / cosine value, range -1.0~1.0 [dimensionless]
    fSin     : REAL;                           // 正弦值，范围 -1.0~1.0 [无量纲] / sine value, range -1.0~1.0 [dimensionless]
    fXRot    : REAL;                           // 旋转后 X [用户单位] / X after rotation [user unit]
    fYRot    : REAL;                           // 旋转后 Y [用户单位] / Y after rotation [user unit]
    fXScaled : REAL;                           // 缩放后 X [用户单位] / X after scaling [user unit]
    fYScaled : REAL;                           // 缩放后 Y [用户单位] / Y after scaling [user unit]
    fQuot    : REAL;                           // 角度除以 360 的整数商中间量 [无量纲] / integer quotient of the angle divided by 360 [dimensionless]
    bNonFin  : BOOL;                           // 非有限判定中间标志 / non-finite detection intermediate flag
END_VAR
VAR CONSTANT
    DL_AFF_EPS        : REAL := 1.0E-6;        // 浮点判等容差 [无量纲] / float equality tolerance [dimensionless]
    DL_AFF_INF_GUARD  : REAL := 4.0E38;        // 非有限幅值判定阈值，高于 REAL 最大有限值 [用户单位] / non-finite magnitude guard above the largest finite REAL [user unit]
    DL_AFF_FULL_DEG   : REAL := 360.0;         // 一整圈角度 [度] / one full turn [deg]
    DL_AFF_DEG2RAD    : REAL := 0.017453292519943295; // 度转弧度系数 [弧度每度] / degree to radian factor [rad per deg]
    DL_AFF_ZERO       : REAL := 0.0;           // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
    DL_AFF_TWO        : REAL := 2.0;           // 除数二，用于半圆判定 [无量纲] / divisor two, used by the half turn check [dimensionless]
END_VAR

// 段 1｜返回值与输出预置 / segment 1, preset return value and outputs
FC_DL_AffineTransformPoint := FALSE;           // 故障缺省返回 FALSE / fault default returns FALSE
fOutX := DL_AFF_ZERO;                          // 输出 X 预置 0 / preset X to zero
fOutY := DL_AFF_ZERO;                          // 输出 Y 预置 0 / preset Y to zero
eErr := 0;                                     // 预置无错误 / preset no error
bError := FALSE;                               // 预置无故障 / preset no fault
bValid := FALSE;                               // 预置结果不可用 / preset unusable

// 段 2｜输入非有限闸：任一输入 NaN 或正负 INF 即拒绝 / segment 2, input non-finite gate
bNonFin := (fX <> fX) OR (fX > DL_AFF_INF_GUARD) OR (fX < -DL_AFF_INF_GUARD)
        OR (fY <> fY) OR (fY > DL_AFF_INF_GUARD) OR (fY < -DL_AFF_INF_GUARD)
        OR (fRotDeg <> fRotDeg) OR (fRotDeg > DL_AFF_INF_GUARD) OR (fRotDeg < -DL_AFF_INF_GUARD)
        OR (fTx <> fTx) OR (fTx > DL_AFF_INF_GUARD) OR (fTx < -DL_AFF_INF_GUARD)
        OR (fTy <> fTy) OR (fTy > DL_AFF_INF_GUARD) OR (fTy < -DL_AFF_INF_GUARD); // 平移与角度同样检查 / translation and angle are checked the same way
IF bNonFin THEN
    eErr := 16#0001_0319;                      // 输入非有限故障码 / non-finite input fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    RETURN;                                    // 故障级提前返回，输出保持 0 / early return on fault, outputs stay zero
END_IF

// 段 3｜缩放闸：缩放为 0 使变换不可逆，原值回送并拒绝 / segment 3, zero scale gate
IF (ABS(fScaleX) < DL_AFF_EPS) OR (ABS(fScaleY) < DL_AFF_EPS) THEN
    eErr := 16#0001_0318;                      // 缩放为零故障码 / zero scale fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    fOutX := fX;                               // 原值回送 X，便于上层诊断 / return the original X so the caller can diagnose
    fOutY := fY;                               // 原值回送 Y / return the original Y
    RETURN;                                    // 故障级提前返回 / early return on fault
END_IF

// 段 4｜角度归一：减 360 乘以整数商，单算式路径，不用循环也不用取余 / segment 4, angle normalisation
fAngNorm := fRotDeg;                           // 默认沿用输入角 / default to the input angle
IF ABS(fRotDeg) > DL_AFF_FULL_DEG THEN
    fQuot := TRUNC(fRotDeg / DL_AFF_FULL_DEG); // 整数商（向零截断，除数为常量 360 恒非零）/ integer quotient, truncated toward zero, the divisor is the constant 360
    fAngNorm := fRotDeg - DL_AFF_FULL_DEG * fQuot; // 单算式归一，残差落在正负 360 内 / single expression normalisation, the residual stays within plus or minus 360
    eErr := 16#0001_0241;                      // 归一提示（信息级不置故障）/ normalisation hint, info level never raises a fault
END_IF

// 段 5｜三角函数：直接调内建，绝不重实现 / segment 5, trigonometric functions are built-in calls only
fRad := fAngNorm * DL_AFF_DEG2RAD;             // 度转弧度 / degrees to radians
fCos := COS(fRad);                             // 余弦 [无量纲] / cosine [dimensionless]
fSin := SIN(fRad);                             // 正弦 [无量纲] / sine [dimensionless]

// 段 6｜旋转 → 缩放 → 平移 合成 / segment 6, rotation then scaling then translation
fXRot := fX * fCos - fY * fSin;                // 旋转后 X / X after rotation
fYRot := fX * fSin + fY * fCos;                // 旋转后 Y / Y after rotation
fXScaled := fXRot * fScaleX;                   // 各轴缩放 X / per axis scaling on X
fYScaled := fYRot * fScaleY;                   // 各轴缩放 Y / per axis scaling on Y
fOutX := fXScaled + fTx;                       // 叠加 X 平移 / add the X translation
fOutY := fYScaled + fTy;                       // 叠加 Y 平移 / add the Y translation

// 段 7｜结果非有限复检：大缩放乘大坐标可能溢出 / segment 7, result non-finite recheck
bNonFin := (fOutX <> fOutX) OR (fOutX > DL_AFF_INF_GUARD) OR (fOutX < -DL_AFF_INF_GUARD)
        OR (fOutY <> fOutY) OR (fOutY > DL_AFF_INF_GUARD) OR (fOutY < -DL_AFF_INF_GUARD); // 结果溢出判定 / result overflow check
IF bNonFin THEN
    fOutX := DL_AFF_ZERO;                      // 溢出即输出 0 / overflow yields zero
    fOutY := DL_AFF_ZERO;                      // 溢出即输出 0 / overflow yields zero
    eErr := 16#0001_0319;                      // 结果非有限故障码 / non-finite result fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    RETURN;                                    // 故障级提前返回 / early return on fault
END_IF

// 段 8｜出口 / segment 8, exit
bValid := TRUE;                                // 结果可用 / the result is usable
FC_DL_AffineTransformPoint := TRUE;            // 变换成功 / the transform succeeded
END_FUNCTION
