(*
    FC_DL_InterpolateTable2D —— 二维标定表双线性插值
    ------------------------------------------------------------------
    分类      : DL_MathData / Interpolate
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : T2-1 LGF · Math（只借「标度 / 插值属 Math 组」的分类事实与参数域组织
                方式；双线性公式为公开数学，实现、码位、行主序约定 100% 自有）；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R18）
    ------------------------------------------------------------------
    功能说明  : 8x8 标定网格上做双线性插值，典型场景：温度—压力二维补偿表、
                阀门流量特性双参数表、视觉标定畸变修正；库内 MultiPointLinear 只做
                一维，二维场景现场长期靠梯形图硬编码，本件即补此缺口；
                防御链：点数闸 → 网格严格递增校验 → 坐标非有限闸 → 退化格防除零闸
                → 索引上界闸 → 结果非有限复检，每一闸都在索引或除法之前；
                定位用线性扫描（点数不超过 8，避免二分的边界 off-by-one），
                值表按行主序一维存放，不用多维数组规避平台差异。
    错误码    : 16#0001_023F 输入落网格外已钳位，或遇退化格（跨度约等于 0）按该角值直取——信息级，正常防御
                16#0001_0240 预留禁用（信息级，不得挪用）
                16#0001_0315 点数或网格非法（越界、非严格递增）——故障级，返回首值
                16#0001_0316 插值坐标或结果非有限（NaN / 正负 INF）——故障级，返回首值
                16#0001_0317 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_023F 用 / 16#0001_0240 预留 ｜ 16#0001_0315 用 / 16#0001_0316 用 / 16#0001_0317 预留
    状态机    : N/A —— 纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 纯组合函数，无定时器、无内部驻留状态；网格与值表由调用方保证
                在调用拍内不被并发改写（本库统一约定：标定表只在停机态下发）。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R18）
*)
FUNCTION FC_DL_InterpolateTable2D : REAL
VAR_INPUT
    afGridX      : ARRAY[0..7] OF REAL;        // X 轴网格，必须严格递增，有效项 0~uCountX-1 [用户单位] / X grid, strictly increasing, valid items 0~uCountX-1 [user unit]
    afGridY      : ARRAY[0..7] OF REAL;        // Y 轴网格，必须严格递增，有效项 0~uCountY-1 [用户单位] / Y grid, strictly increasing, valid items 0~uCountY-1 [user unit]
    afValue      : ARRAY[0..63] OF REAL;       // 值表，行主序：索引 = nIy * uCountX + nIx [用户单位] / value table, row major, index = nIy * uCountX + nIx [user unit]
    uCountX      : UINT := 2;                  // X 有效点数 [点]，范围 2~8 / valid X point count [pt], range 2~8
    uCountY      : UINT := 2;                  // Y 有效点数 [点]，范围 2~8 / valid Y point count [pt], range 2~8
    fX           : REAL := 0.0;                // 待插值 X [用户单位] / X to interpolate [user unit]
    fY           : REAL := 0.0;                // 待插值 Y [用户单位] / Y to interpolate [user unit]
    bExtrapolate : BOOL := FALSE;              // FALSE 边界钳位（推荐）/ TRUE 单格外延 / FALSE clamps at the border, TRUE extrapolates one cell
END_VAR
VAR_OUTPUT
    eErr       : UDINT;                        // 错误码，0=正常 / error id, 0=ok
    bError     : BOOL;                         // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid     : BOOL;                         // 结果是否可用 / result usable flag
    bOutOfGrid : BOOL;                         // 输入落在网格外（钳位或外延生效）/ input falls outside the grid (clamp or extrapolation applied)
END_VAR
VAR
    uIx      : UINT;                           // X 网格遍历游标 [点] / X grid traversal cursor [pt]
    uIy      : UINT;                           // Y 网格遍历游标 [点] / Y grid traversal cursor [pt]
    uIxSel   : UINT;                           // 命中的 X 单元下界序号 [点] / selected lower X cell index [pt]
    uIySel   : UINT;                           // 命中的 Y 单元下界序号 [点] / selected lower Y cell index [pt]
    uBase    : UINT;                           // 四角首索引（行主序）[无量纲] / first corner index in row major order [dimensionless]
    uIdx11   : UINT;                           // 对角索引 uIdx11，用于上界闸 [无量纲] / diagonal index used by the upper bound gate [dimensionless]
    fTx      : REAL;                           // X 方向归一化插值系数 0~1 / normalised interpolation factor along X, 0~1
    fTy      : REAL;                           // Y 方向归一化插值系数 0~1 / normalised interpolation factor along Y, 0~1
    fV00     : REAL;                           // 左下角值 [用户单位] / lower left corner value [user unit]
    fV10     : REAL;                           // 右下角值 [用户单位] / lower right corner value [user unit]
    fV01     : REAL;                           // 左上角值 [用户单位] / upper left corner value [user unit]
    fV11     : REAL;                           // 右上角值 [用户单位] / upper right corner value [user unit]
    fSpanX   : REAL;                           // X 单元跨度 [用户单位] / X cell span [user unit]
    fSpanY   : REAL;                           // Y 单元跨度 [用户单位] / Y cell span [user unit]
    fRes     : REAL;                           // 插值结果中间量 [用户单位] / interpolation result intermediate [user unit]
    bFoundX  : BOOL;                           // X 定位命中标志 / X location found flag
    bFoundY  : BOOL;                           // Y 定位命中标志 / Y location found flag
    bNonFin  : BOOL;                           // 非有限判定中间标志 / non-finite detection intermediate flag
END_VAR
VAR CONSTANT
    DL_2D_MAX        : UINT := 8;              // 单轴点数上限 [点] / per axis point upper bound [pt]
    DL_2D_CELLS      : UINT := 64;             // 值表容量 [个] / value table capacity [item]
    DL_2D_LAST_CELL  : UINT := 63;             // 值表末索引 [个] / last value table index [item]
    DL_FLOAT_EPS     : REAL := 1.0E-6;         // 浮点判等容差 [无量纲] / float equality tolerance [dimensionless]
    DL_2D_INF_GUARD  : REAL := 4.0E38;         // 非有限幅值判定阈值，高于 REAL 最大有限值 [用户单位] / non-finite magnitude guard above the largest finite REAL [user unit]
    DL_2D_ONE        : REAL := 1.0;            // 归一化上界与补数基数 [无量纲] / normalisation upper bound and complement base [dimensionless]
    DL_2D_ZERO       : REAL := 0.0;            // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_InterpolateTable2D := DL_2D_ZERO;        // 故障缺省返回 0 / fault default returns zero
eErr := 0;                                     // 预置无错误 / preset no error
bError := FALSE;                               // 预置无故障 / preset no fault
bValid := FALSE;                               // 预置结果不可用 / preset unusable
bOutOfGrid := FALSE;                           // 预置落在网格内 / preset inside the grid

// 段 2｜点数闸：先判界再索引，绝不越界读数组 / segment 2, point count gate before any indexing
IF (uCountX < 2) OR (uCountX > DL_2D_MAX) OR (uCountY < 2) OR (uCountY > DL_2D_MAX) THEN
    eErr := 16#0001_0315;                      // 点数非法故障码 / illegal point count fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    FC_DL_InterpolateTable2D := afValue[0];    // 返回首值，索引 0 恒存在 / return the first value, index zero always exists
    RETURN;                                    // 故障级提前返回 / early return on fault
END_IF

// 段 3｜坐标非有限闸（NaN 自不等 + 幅值判正负 INF）/ segment 3, non-finite coordinate gate
bNonFin := (fX <> fX) OR (fX > DL_2D_INF_GUARD) OR (fX < -DL_2D_INF_GUARD)
        OR (fY <> fY) OR (fY > DL_2D_INF_GUARD) OR (fY < -DL_2D_INF_GUARD); // 非有限综合判定 / combined non-finite check
IF bNonFin THEN
    eErr := 16#0001_0316;                      // 坐标非有限故障码 / non-finite coordinate fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    FC_DL_InterpolateTable2D := afValue[0];    // 返回首值 / return the first value
    RETURN;                                    // 故障级提前返回 / early return on fault
END_IF

// 段 4｜网格严格递增校验（用大于号逐点比较，禁用浮点判等）/ segment 4, strict monotonic grid check
FOR uIx := 1 TO uCountX - 1 DO
    IF NOT (afGridX[uIx] > afGridX[uIx - 1]) THEN
        eErr := 16#0001_0315;                  // 网格非严格递增故障码 / non monotonic grid fault id
        bError := TRUE;                        // 置故障标志 / raise the error flag
        FC_DL_InterpolateTable2D := afValue[0];// 返回首值 / return the first value
        RETURN;                                // 故障级提前返回 / early return on fault
    END_IF
END_FOR
FOR uIy := 1 TO uCountY - 1 DO
    IF NOT (afGridY[uIy] > afGridY[uIy - 1]) THEN
        eErr := 16#0001_0315;                  // Y 网格非严格递增故障码 / non monotonic Y grid fault id
        bError := TRUE;                        // 置故障标志 / raise the error flag
        FC_DL_InterpolateTable2D := afValue[0];// 返回首值 / return the first value
        RETURN;                                // 故障级提前返回 / early return on fault
    END_IF
END_FOR

// 段 5｜线性扫描定位单元（上界 uCountX-2，避免 off-by-one）/ segment 5, linear cell location
uIxSel := 0;                                   // 默认落最低单元 / default to the lowest cell
bFoundX := FALSE;                              // 命中标志先清 / clear the found flag
FOR uIx := 0 TO uCountX - 2 DO
    IF (NOT bFoundX) AND (fX <= afGridX[uIx + 1]) THEN
        uIxSel := uIx;                         // 命中第一个上界不小于输入的单元 / the first cell whose upper bound is not below the input
        bFoundX := TRUE;                       // 命中即锁定，后续不再覆盖 / lock the hit, later cells never overwrite it
    END_IF
END_FOR
IF NOT bFoundX THEN
    uIxSel := uCountX - 2;                     // 高于网格顶，取最高单元 / above the top, take the highest cell
    bOutOfGrid := TRUE;                        // 标记落在网格外 / flag the out-of-grid input
END_IF
IF fX < afGridX[0] THEN
    uIxSel := 0;                               // 低于网格底，取最低单元 / below the bottom, take the lowest cell
    bOutOfGrid := TRUE;                        // 标记落在网格外 / flag the out-of-grid input
END_IF
uIySel := 0;                                   // 默认落最低单元 / default to the lowest cell
bFoundY := FALSE;                              // 命中标志先清 / clear the found flag
FOR uIy := 0 TO uCountY - 2 DO
    IF (NOT bFoundY) AND (fY <= afGridY[uIy + 1]) THEN
        uIySel := uIy;                         // 命中第一个上界不小于输入的单元 / the first cell whose upper bound is not below the input
        bFoundY := TRUE;                       // 命中即锁定 / lock the hit
    END_IF
END_FOR
IF NOT bFoundY THEN
    uIySel := uCountY - 2;                     // 高于网格顶，取最高单元 / above the top, take the highest cell
    bOutOfGrid := TRUE;                        // 标记落在网格外 / flag the out-of-grid input
END_IF
IF fY < afGridY[0] THEN
    uIySel := 0;                               // 低于网格底，取最低单元 / below the bottom, take the lowest cell
    bOutOfGrid := TRUE;                        // 标记落在网格外 / flag the out-of-grid input
END_IF

// 段 6｜退化格防除零：跨度绝对值不大于容差时不除，系数取 0 按该角值直取 / segment 6, degenerate cell division guard
fSpanX := afGridX[uIxSel + 1] - afGridX[uIxSel]; // X 单元跨度 / X cell span
IF ABS(fSpanX) <= DL_FLOAT_EPS THEN
    fTx := DL_2D_ZERO;                         // 跨度近零，系数取 0，绝不除 / span near zero, factor zero, no division
    eErr := 16#0001_023F;                      // 退化格提示（信息级不置故障）/ degenerate cell hint, info level never raises a fault
ELSE
    fTx := (fX - afGridX[uIxSel]) / fSpanX;    // 除号在防零闸之后 / the division happens after the guard
END_IF
fSpanY := afGridY[uIySel + 1] - afGridY[uIySel]; // Y 单元跨度 / Y cell span
IF ABS(fSpanY) <= DL_FLOAT_EPS THEN
    fTy := DL_2D_ZERO;                         // 跨度近零，系数取 0 / span near zero, factor zero
    eErr := 16#0001_023F;                      // 退化格提示（信息级不置故障）/ degenerate cell hint, info level never raises a fault
ELSE
    fTy := (fY - afGridY[uIySel]) / fSpanY;    // 除号在防零闸之后 / the division happens after the guard
END_IF

// 段 7｜边界策略：钳位（推荐）或单格外延 / segment 7, border policy, clamp or single cell extrapolation
IF bExtrapolate THEN
    IF bOutOfGrid THEN
        eErr := 16#0001_023F;                  // 外延生效提示（信息级不置故障）/ extrapolation hint, info level never raises a fault
    END_IF
ELSE
    IF fTx < DL_2D_ZERO THEN
        fTx := DL_2D_ZERO;                     // 下侧钳位 / clamp on the low side
        bOutOfGrid := TRUE;                    // 标记落网格外 / flag the out-of-grid input
    END_IF
    IF fTx > DL_2D_ONE THEN
        fTx := DL_2D_ONE;                      // 上侧钳位 / clamp on the high side
        bOutOfGrid := TRUE;                    // 标记落网格外 / flag the out-of-grid input
    END_IF
    IF fTy < DL_2D_ZERO THEN
        fTy := DL_2D_ZERO;                     // 下侧钳位 / clamp on the low side
        bOutOfGrid := TRUE;                    // 标记落网格外 / flag the out-of-grid input
    END_IF
    IF fTy > DL_2D_ONE THEN
        fTy := DL_2D_ONE;                      // 上侧钳位 / clamp on the high side
        bOutOfGrid := TRUE;                    // 标记落网格外 / flag the out-of-grid input
    END_IF
    IF bOutOfGrid THEN
        eErr := 16#0001_023F;                  // 钳位生效提示（信息级不置故障）/ clamp hint, info level never raises a fault
    END_IF
END_IF

// 段 8｜四角索引上界闸：一切索引在取用前判界 / segment 8, corner index upper bound gate
uBase := uIySel * uCountX + uIxSel;            // 行主序首索引 / first corner index in row major order
uIdx11 := uBase + uCountX + 1;                 // 对角索引 / diagonal index
IF uIdx11 > DL_2D_LAST_CELL THEN
    eErr := 16#0001_0315;                      // 索引越界故障码 / index out of range fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    FC_DL_InterpolateTable2D := afValue[0];    // 返回首值 / return the first value
    RETURN;                                    // 故障级提前返回 / early return on fault
END_IF
fV00 := afValue[uBase];                        // 左下角值 / lower left value
fV10 := afValue[uBase + 1];                    // 右下角值 / lower right value
fV01 := afValue[uBase + uCountX];              // 左上角值 / upper left value
fV11 := afValue[uIdx11];                       // 右上角值 / upper right value

// 段 9｜双线性合成 / segment 9, bilinear composition
fRes := fV00 * (DL_2D_ONE - fTx) * (DL_2D_ONE - fTy)
      + fV10 * fTx * (DL_2D_ONE - fTy)
      + fV01 * (DL_2D_ONE - fTx) * fTy
      + fV11 * fTx * fTy;                      // 四角加权求和 / weighted sum of the four corners
bNonFin := (fRes <> fRes) OR (fRes > DL_2D_INF_GUARD) OR (fRes < -DL_2D_INF_GUARD); // 结果非有限复检 / result non-finite recheck
IF bNonFin THEN
    eErr := 16#0001_0316;                      // 结果非有限故障码 / non-finite result fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    FC_DL_InterpolateTable2D := afValue[0];    // 返回首值 / return the first value
    RETURN;                                    // 故障级提前返回 / early return on fault
END_IF

// 段 10｜出口 / segment 10, exit
FC_DL_InterpolateTable2D := fRes;              // 输出插值结果 / publish the interpolated result
bValid := TRUE;                                // 结果可用 / the result is usable
END_FUNCTION
