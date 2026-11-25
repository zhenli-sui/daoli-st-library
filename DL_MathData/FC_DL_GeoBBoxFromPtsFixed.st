(*==============================================================================
 * 组件名称 : FC_DL_GeoBBoxFromPtsFixed ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-24
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 定长点列的轴对齐包围盒（BBox）。出参四个极值，用于视觉 ROI 自动贴合、
 *            轨迹占位评估、图形显示自适应缩放。
 * 契约     : 成功返回 TRUE 并写出 fMinX / fMaxX / fMinY / fMaxY；nCnt < 1 时返回 FALSE、
 *            bError := TRUE、四出参置 0；nCnt > 10 时钳到 10 继续（钳位为确定结论）。
 *            数组定长 ARRAY[1..10]，禁变长形参（R17）。
 * 依赖     : 无 DL_ 内部依赖（R16 自足实现），无标准库函数调用
 * 错误码   : R297 零码位范式：eErr 恒 0，仅以 bError / bValid 表达
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 点数先钳位后进循环、非有限点跳过并置标志
 *            R5 双语注释 R6 N/A（无状态机）R7 N/A（无定时器/沿实例）
 *            R10 无类型转换 R11 全声明行分号 R15 标识符零保留字冲突
 *            R17 定长数组 R18 N/A（无 bReset）
 * 遗留假设 : 极值初始化取第一个有效点而非 0，避免全正坐标集被 0 拉低下界。
 * 修订历史 : 2026-11-24 R79-A 首版（平面几何族 7/8）
 *============================================================================*)
FUNCTION FC_DL_GeoBBoxFromPtsFixed : BOOL
VAR_INPUT
    aPtsX   : ARRAY[1..10] OF LREAL;    // 点列 X 坐标，1..10 定长 [mm] / X coordinates of the points, fixed length [mm]
    aPtsY   : ARRAY[1..10] OF LREAL;    // 点列 Y 坐标，1..10 定长 [mm] / Y coordinates of the points, fixed length [mm]
    nCnt    : INT;                      // 有效点数，1~10，越界钳位 [个] / effective point count from one to ten, clamped [count]
END_VAR
VAR_OUTPUT
    eErr    : UDINT;    // 错误码，零码位范式恒 0 / error id, always zero under the zero-code rule
    bError  : BOOL;     // 有效点数为零或全为非有限点为真 / TRUE when no usable point exists
    bValid  : BOOL;     // 出参可用标志 / TRUE when the outputs are usable
    fMinX   : LREAL;    // X 下界，故障时 0 [mm] / lower X bound, zero on fault [mm]
    fMaxX   : LREAL;    // X 上界，故障时 0 [mm] / upper X bound, zero on fault [mm]
    fMinY   : LREAL;    // Y 下界，故障时 0 [mm] / lower Y bound, zero on fault [mm]
    fMaxY   : LREAL;    // Y 上界，故障时 0 [mm] / upper Y bound, zero on fault [mm]
END_VAR
VAR CONSTANT
    DL_PTS_MAX : INT := 10;         // 点列定长上限 [个] / fixed capacity of the point arrays [count]
    DL_PTS_MIN : INT := 1;          // 最少有效点数 [个] / minimum usable point count [count]
    DL_ONE     : INT := 1;          // 下标步长与 1 基起始 [个] / index step and the one based start [count]
    DL_FIN_LIM : LREAL := 1.0E308;  // 有限性上界，超过按无穷处置 [mm] / finiteness ceiling [mm]
    DL_ZERO_L  : LREAL := 0.0;      // 实数零哨兵 [mm] / real zero sentinel [mm]
END_VAR
VAR
    nUse    : INT;      // 钳位后的有效点数 [个] / effective point count after clamping [count]
    nSeen   : INT;      // 已纳入极值的有效点数 [个] / points that entered the extremes [count]
    i       : INT;      // 遍历索引，1 起 [个] / loop index starting at one [count]
    fX      : LREAL;    // 当前点 X 快照 [mm] / X snapshot of the current point [mm]
    fY      : LREAL;    // 当前点 Y 快照 [mm] / Y snapshot of the current point [mm]
END_VAR

// 段 1｜出口预置 / segment 1, preset the exit
FC_DL_GeoBBoxFromPtsFixed := FALSE;     // 缺省失败 / default failure
eErr   := 0;                            // 零码位范式 / zero-code rule
bError := FALSE;                        // 预置无故障 / preset no fault
bValid := FALSE;                        // 域闸前不认出参 / the outputs are unusable until the gates pass
fMinX  := DL_ZERO_L;                    // 下界清零 / clear the lower bound
fMaxX  := DL_ZERO_L;                    // 上界清零 / clear the upper bound
fMinY  := DL_ZERO_L;                    // 下界清零 / clear the lower bound
fMaxY  := DL_ZERO_L;                    // 上界清零 / clear the upper bound

// 段 2｜点数钳位与下越界拦截 / segment 2, clamp the count and reject an empty set
nUse := nCnt;
IF nUse > DL_PTS_MAX THEN
    nUse := DL_PTS_MAX;                 // 钳到定长上限 / clamp to the fixed capacity
END_IF
IF nUse < DL_PTS_MIN THEN
    bError := TRUE;                     // 无点可统计 / no point to scan
    RETURN;
END_IF
nSeen := 0;                             // 已纳入点计数清零 / clear the accepted counter

// 段 3｜单趟扫描：首个有效点建立初值，其后逐点更新 / segment 3, one pass with the first usable point as seed
FOR i := DL_ONE TO nUse DO
    fX := aPtsX[i];                     // X 快照 / X snapshot
    fY := aPtsY[i];                     // Y 快照 / Y snapshot
    IF NOT ((fX <> fX) OR (ABS(fX) > DL_FIN_LIM) OR (fY <> fY) OR (ABS(fY) > DL_FIN_LIM)) THEN
        IF nSeen = 0 THEN
            fMinX := fX;                // 首点种子，避免 0 被当极值 / seed from the first point instead of zero
            fMaxX := fX;
            fMinY := fY;
            fMaxY := fY;
        ELSE
            IF fX < fMinX THEN
                fMinX := fX;            // 更新 X 下界 / update the lower X bound
            END_IF
            IF fX > fMaxX THEN
                fMaxX := fX;            // 更新 X 上界 / update the upper X bound
            END_IF
            IF fY < fMinY THEN
                fMinY := fY;            // 更新 Y 下界 / update the lower Y bound
            END_IF
            IF fY > fMaxY THEN
                fMaxY := fY;            // 更新 Y 上界 / update the upper Y bound
            END_IF
        END_IF
        nSeen := nSeen + DL_ONE;        // 有效点计数 / count the accepted point
    END_IF
END_FOR

// 段 4｜出口：全为非有限点按故障处置 / segment 4, exit with the all non finite case treated as a fault
IF nSeen = 0 THEN
    bError := TRUE;                     // 全部点非有限 / every point is non finite
    fMinX  := DL_ZERO_L;                // 出参归零 / zero the outputs
    fMaxX  := DL_ZERO_L;
    fMinY  := DL_ZERO_L;
    fMaxY  := DL_ZERO_L;
    RETURN;
END_IF
bValid := TRUE;                         // 出参可用 / the outputs are usable
FC_DL_GeoBBoxFromPtsFixed := TRUE;      // 求解成功 / the request succeeded
END_FUNCTION
