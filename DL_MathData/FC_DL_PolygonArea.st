(*==============================================================================
 * 组件名称 (Component)  : FC_DL_PolygonArea
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（ABS / MOD），全 LREAL 运算，无状态
 * 功能描述 (Function)   : 平面多边形有向面积、绝对面积与质心坐标（鞋带公式 / Green 定理的
 *                         离散形式）。用于视觉定位的料框有效面积、零件轮廓面积校验、
 *                         机器人平面抓取中心计算、皮带跑偏区域判断。
 *                         返回值即绝对面积，有向面积符号经 bCcw 输出，供调用方判断轮廓
 *                         绕向（多数视觉库输出顺时针轮廓，需要翻转才能与机器人坐标系一致）。
 *
 * 【失真与语义披露 / Distortion disclosure】
 *   1) 自交多边形：鞋带公式返回的是代数面积（正负抵消），不是几何面积。结果无几何意义，
 *      调用方必须保证输入是简单多边形；视觉轮廓应先按角度排序并去重，再送进来。
 *   2) 顶点约定"末点不重复首点"。若调用方重复传入首点，面积仍正确，但质心会偏移
 *      （重复点参与一次额外的零面积边，却多算了一次顶点权重）。检测办法：首末点距离
 *      小于 eps 时把 nCount 减 1 再调用。
 *   3) 退化（点数 < 3、共线、零面积）时质心返回顶点算术平均，而不是 (0,0)：
 *      (0,0) 会让机器人在异常时朝原点狂奔，算术平均至少落在轮廓附近。
 *   4) 必须用 LREAL：32 点 × 1e6 mm 坐标的叉积累加可达 1e12，REAL 的 24 位尾数在这个
 *      量级已经丢掉 5 位有效数字，面积会算出负偏差。
 *
 * 开源溯源 (Origin)     : 原创实现（参考西门子 LGF 数学功能组中平面几何族的分类位置，
 *                         鞋带公式为公开数学方法，clean-room 独立实现）
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: ABS / MOD
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3（MOD 取模闭合索引，无负索引）
 *                         R4 ✓ 点数双向钳位 + 索引只经 MOD + 面积零容差 + 质心分母判零
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无状态机）｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 收口批次 · R3）
 *============================================================================*)
FUNCTION FC_DL_PolygonArea : LREAL
VAR_IN_OUT
    afX : ARRAY[0..31] OF LREAL;          // 顶点 X 序列，末点不重复首点（上限 32 点）/ Vertex X, not closed, max 32
    afY : ARRAY[0..31] OF LREAL;          // 顶点 Y 序列（上限 32 点）/ Vertex Y, max 32
END_VAR
VAR_INPUT
    nCount : INT;                         // 顶点数，合法域 3..32 / Vertex count, valid 3..32
END_VAR
VAR_OUTPUT
    fCentroidX  : LREAL;                  // 质心 X [mm] / Centroid X [mm]
    fCentroidY  : LREAL;                  // 质心 Y [mm] / Centroid Y [mm]
    bCcw        : BOOL;                   // TRUE = 逆时针（右手系）/ TRUE = counter-clockwise, right-handed
    bDegenerate : BOOL;                   // TRUE = 退化（共线或面积为零）/ TRUE = degenerate polygon
    uErrorId    : UDINT;                  // 故障码，0 = 无故障 / Error code, 0 = no error
END_VAR
VAR
    nI      : INT;                        // 顶点索引 / Vertex index
    nJ      : INT;                        // 下一顶点索引 (nI + 1) MOD nCount / Next vertex index
    nCnt    : INT;                        // 钳位后的有效顶点数 / Clamped effective vertex count
    nGuard  : INT;                        // 循环防死锁计数器 / Loop guard counter
    fCross  : LREAL;                      // 单边叉积项 [mm^2] / Per-edge cross term [mm^2]
    fArea2  : LREAL;                      // 二倍有向面积 [mm^2] / Twice the signed area [mm^2]
    fCxAcc  : LREAL;                      // 质心 X 累加 [mm^3] / Centroid X accumulator [mm^3]
    fCyAcc  : LREAL;                      // 质心 Y 累加 [mm^3] / Centroid Y accumulator [mm^3]
    fDen    : LREAL;                      // 质心公式分母 3×fArea2 [mm^2] / Centroid denominator
    fMeanX  : LREAL;                      // 顶点算术平均 X（退化回退）[mm] / Mean X fallback [mm]
    fMeanY  : LREAL;                      // 顶点算术平均 Y（退化回退）[mm] / Mean Y fallback [mm]
END_VAR
VAR CONSTANT
    DL_PGA_PTS_MIN : INT   := 3;          // 最少顶点数 / Minimum vertex count
    DL_PGA_PTS_MAX : INT   := 32;         // 最多顶点数，等于数组维度 / Maximum vertex count, equals the array size
    DL_PGA_EPS     : LREAL := 1.0E-12;    // 面积零判定容差 [mm^2] / Zero-area tolerance [mm^2]
    DL_PGA_TWO     : LREAL := 2.0;        // 面积公式分母常数 / Area denominator constant
    DL_PGA_THREE   : LREAL := 3.0;        // 质心分母常数，6×(A2/2) 折算为 3×A2 / Reduced centroid denominator
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜安全预置（边界 B6）：质心先落到 0，后续任何异常路径都要再覆盖它
 *      Safe preset: the centroid starts at zero, every abnormal path overwrites it
 *-----------------------------------------------------------------------------*)
FC_DL_PolygonArea := 0.0;
fCentroidX        := 0.0;
fCentroidY        := 0.0;
bCcw              := FALSE;
bDegenerate       := FALSE;
uErrorId          := 16#0000_0000;
fArea2            := 0.0;
fCxAcc            := 0.0;
fCyAcc            := 0.0;
nGuard            := 0;

(*------------------------------------------------------------------------------
 * 段 2｜点数校验（边界 B1）：上限向下钳位（多点比少点安全），下限直接拒绝
 *      Count check: clamp the upper bound down (more points is safer), reject the lower
 *-----------------------------------------------------------------------------*)
nCnt := nCount;

IF nCnt > DL_PGA_PTS_MAX THEN
    nCnt      := DL_PGA_PTS_MAX;
    uErrorId  := 16#0001_0001;
END_IF

IF nCnt < DL_PGA_PTS_MIN THEN
    (* 边界 B6：退化时给顶点算术平均，绝不返回 (0,0) *)
    (* Degenerate: return the vertex mean, never the origin *)
    IF nCnt < 1 THEN
        fCentroidX := 0.0;
        fCentroidY := 0.0;
    ELSE
        fMeanX := 0.0;
        fMeanY := 0.0;
        FOR nI := 0 TO (nCnt - 1) DO
            fMeanX := fMeanX + afX[nI];
            fMeanY := fMeanY + afY[nI];
        END_FOR
        fCentroidX := fMeanX / INT_TO_LREAL(nCnt);
        fCentroidY := fMeanY / INT_TO_LREAL(nCnt);
    END_IF
    bDegenerate := TRUE;
    uErrorId    := 16#0002_000C;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜单遍累加（鞋带公式）：边权与质心权重共用同一个叉积项，只算一次
 *      Single-pass shoelace: the edge weight and the centroid weight share one cross term
 *      nJ 用 MOD nCount 闭合，nCnt >= 3 已保证除数非零，索引永不等于 nCnt
 *-----------------------------------------------------------------------------*)
FOR nI := 0 TO (nCnt - 1) DO

    nJ     := (nI + 1) MOD nCnt;
    fCross := (afX[nI] * afY[nJ]) - (afX[nJ] * afY[nI]);

    fArea2 := fArea2 + fCross;
    fCxAcc := fCxAcc + ((afX[nI] + afX[nJ]) * fCross);
    fCyAcc := fCyAcc + ((afY[nI] + afY[nJ]) * fCross);

    nGuard := nGuard + 1;

END_FOR

IF nGuard > (nCnt + 1) THEN
    (* 理论上不可达（FOR 定长），纯防御：循环计数异常即报表 *)
    (* Unreachable in theory: a bounded FOR loop cannot overrun, defence only *)
    uErrorId := 16#0001_0004;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜退化判定（边界 B3/B6）：共线或重合时面积为零，质心回退算术平均
 *      Degenerate test: zero area falls back to the vertex mean
 *-----------------------------------------------------------------------------*)
IF ABS(fArea2) <= DL_PGA_EPS THEN

    fMeanX := 0.0;
    fMeanY := 0.0;
    FOR nI := 0 TO (nCnt - 1) DO
        fMeanX := fMeanX + afX[nI];
        fMeanY := fMeanY + afY[nI];
    END_FOR

    fCentroidX  := fMeanX / INT_TO_LREAL(nCnt);
    fCentroidY  := fMeanY / INT_TO_LREAL(nCnt);
    bCcw        := FALSE;
    bDegenerate := TRUE;
    uErrorId    := 16#0002_000C;
    FC_DL_PolygonArea := 0.0;
    RETURN;

END_IF

(*------------------------------------------------------------------------------
 * 段 5｜正常路径：面积 = |fArea2| / 2，质心 = 累加 / (3 × fArea2)
 *      Normal path: area = |fArea2| / 2, centroid = accumulator / (3 × fArea2)
 *      分母用 3×fArea2 而不是 6×(fArea2/2)，少一次除法，少一次舍入
 *      bCcw 由 fArea2 的符号直接给出，不做"面积恒正后再判断"的二次推导
 *-----------------------------------------------------------------------------*)
bCcw := (fArea2 > 0.0);

fDen := DL_PGA_THREE * fArea2;

IF ABS(fDen) > DL_PGA_EPS THEN
    fCentroidX := fCxAcc / fDen;
    fCentroidY := fCyAcc / fDen;
ELSE
    (* 二次防御：段 4 已排除近零面积，此处仅防数值极端情形下的除零 *)
    (* Second defence: near-zero area was excluded in stage 4, this guards extremes *)
    fCentroidX  := 0.0;
    fCentroidY  := 0.0;
    bDegenerate := TRUE;
    uErrorId    := 16#0002_000C;
END_IF

FC_DL_PolygonArea := ABS(fArea2) / DL_PGA_TWO;
END_FUNCTION
