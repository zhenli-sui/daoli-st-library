(*==============================================================================
 * 组件名称 : FC_DL_GeoPolylineLenFixed ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 定长点列折线总长。两轴坐标以并列定长数组给出，逐段取欧氏距离累加。
 *            用于示教轨迹余量核算、皮带测绘线长、切割路径周长统计。
 * 契约     : 返回折线总长（≥ 0）；nCnt 大于 10 时钳到 10 继续计算（钳位值仍为确定结论，
 *            不置 bError）；nCnt 小于 2 时返回 0 且 bError := TRUE。
 *            数组定长 ARRAY[1..10]，禁变长形参（R17）。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现）；Standard.library: SQRT
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 点数先钳位后进循环、循环上界由钳位保证
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突
 *            R17 定长数组 R18 N/A（无 bReset）
 * 遗留假设 : 数组下标一律从 1 起，与 IEC 默认下界一致；调用方须保证实参数组同为 1..10。
 * 修订历史 : 2026-11-24 R79-A 首版（平面几何族 6/8）
 *============================================================================*)
FUNCTION FC_DL_GeoPolylineLenFixed : LREAL
VAR_INPUT
    aPtsX   : ARRAY[1..10] OF LREAL;    // 点列 X 坐标，1..10 定长 [mm] / X coordinates of the points, fixed length [mm]
    aPtsY   : ARRAY[1..10] OF LREAL;    // 点列 Y 坐标，1..10 定长 [mm] / Y coordinates of the points, fixed length [mm]
    nCnt    : INT;                      // 有效点数，2~10，越界钳位 [个] / effective point count from two to ten, clamped [count]
END_VAR
VAR_OUTPUT
    eErr    : UDINT;    // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError  : BOOL;     // 有效点数不足两点为真 / TRUE when fewer than two points remain
    bValid  : BOOL;     // 结果可用标志 / result usable flag
END_VAR
VAR CONSTANT
    DL_PTS_MAX : INT := 10;         // 点列定长上限 [个] / fixed capacity of the point arrays [count]
    DL_PTS_MIN : INT := 2;          // 构成折线的最少点数 [个] / minimum points that form a polyline [count]
    DL_ONE     : INT := 1;          // 下标步长与 1 基起始 [个] / index step and the one based start [count]
    DL_ZERO_L  : LREAL := 0.0;      // 实数零哨兵 [mm] / real zero sentinel [mm]
END_VAR
VAR
    nUse    : INT;      // 钳位后的有效点数 [个] / effective point count after clamping [count]
    i       : INT;      // 段游标，1 起 [个] / segment cursor starting at one [count]
    fDx     : LREAL;    // 单段 X 分量 [mm] / X component of one segment [mm]
    fDy     : LREAL;    // 单段 Y 分量 [mm] / Y component of one segment [mm]
    fSeg    : LREAL;    // 单段长度 [mm] / length of one segment [mm]
    fSum    : LREAL;    // 总长累加器 [mm] / accumulated total length [mm]
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_GeoPolylineLenFixed := DL_ZERO_L;     // 缺省总长 0 / default total length zero
eErr   := 0;                                // 零码位范式 / zero-code rule
bError := FALSE;                            // 预置无故障 / preset no fault
bValid := FALSE;                            // 计算完成前不认结果 / unusable until the walk ends
fSum   := DL_ZERO_L;                        // 累加器清零 / clear the accumulator

// 段 2｜点数钳位：上越界静默钳位，下越界按故障退出 / segment 2, clamp the point count
nUse := nCnt;                               // 工作副本 / working copy
IF nUse > DL_PTS_MAX THEN
    nUse := DL_PTS_MAX;                     // 钳到定长上限，超出部分不可见 / clamp to the fixed capacity
END_IF
IF nUse < DL_PTS_MIN THEN
    bError := TRUE;                         // 不足两点构不成折线 / fewer than two points form no polyline
    RETURN;                                 // 返回 0 / return zero
END_IF

// 段 3｜逐段累加：下标范围由钳位保证，不会越界 / segment 3, accumulate segment by segment
FOR i := DL_ONE TO (nUse - DL_ONE) DO
    fDx  := aPtsX[i + DL_ONE] - aPtsX[i];                   // X 分量 / X component
    fDy  := aPtsY[i + DL_ONE] - aPtsY[i];                   // Y 分量 / Y component
    fSeg := SQRT((fDx * fDx) + (fDy * fDy));                // 欧氏段长，非有限段由出口自证拦下 / Euclidean length, verified at the exit
    fSum := fSum + fSeg;                                    // 累加 / accumulate
END_FOR

// 段 4｜出口自证：总长必须有限且非负 / segment 4, the exit self proof
IF (fSum <> fSum) OR (fSum < DL_ZERO_L) THEN
    bError := TRUE;                         // 累加结果非有限或为负（坐标量级过大）/ the sum is not finite or negative
    FC_DL_GeoPolylineLenFixed := DL_ZERO_L;
    RETURN;
END_IF
FC_DL_GeoPolylineLenFixed := fSum;          // 总长 / the total length
bValid := TRUE;                             // 结果可用 / the result is usable
END_FUNCTION
