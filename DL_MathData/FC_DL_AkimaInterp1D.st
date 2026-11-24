(*
  道莅工业代码库 | DL_MathData | FC_DL_AkimaInterp1D
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  开源溯源: self-cleanroom（无外部来源；Akima 1970 抗振荡插值为公开算法，
            本件独立实现，零代码行复制）
  功能: Akima 一维插值（显式点数入参防 VLA）——5 点及以上走完整 Akima
        切线加权（端部斜率外推两支），2~4 点回落线性插值；查询点越界钳端点。
  兼容性: CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；仅依赖标准 ABS/SQRT，零厂商私有库
  接口: 输入查询点 fX、节点表 aX/aY（固定上界 ARRAY[1..100] OF REAL）、
        uPointCnt（1..200，内部钳位 [2,100]）；返回值 TRUE=已执行；
        输出 fY（越界钳端点值）、bValid、eErr。纯函数：无内部状态。
  码表: 16#0001_0500 故障级：节点表非法（含非有限值或未严格升序，或查询点 NaN）
        码段说明：0001 段 03xx 故障子带已满（03FF 已占用），启用 05xx 扩展域闸子带，
        0500 槽经全库实扫空闲。
  边界: ① uPointCnt 先钳位 [2,100]（R75 显式点数字段口径），钳位后 < 2 不可能，
        表非法仅由升序破坏/非有限/查询 NaN 触发；
        ② 段斜率除法分母由升序闸（节点差 > EPS）证明 > 0；
        ③ Akima 切线权重分母 (w1+w2) = 0 时回落两邻段斜率均值（算法标准防除零）；
        ④ 端部外推斜率 m0/m-1/mn/mn+1 需 n >= 4，本件以 n >= 5 进 Akima 路径闸住；
        ⑤ 全部输出在所有路径（含提前返回）赋值；⑥ 零全局耦合。
  邻件比对: Lagrange/Hermite/CubicSpline（多项式样条族 vs 本件 Akima 抗振荡切线族）。
  修订历史: 2026-11-23 v1.0.0 R75 首版（复杂件批 B2 · C09）
*)

FUNCTION FC_DL_AkimaInterp1D : BOOL
VAR_INPUT
    fX        : REAL;                     // 查询点横坐标 [x 单位] | Query abscissa
    aX        : ARRAY[1..100] OF REAL;    // 节点横坐标表（严格升序）[x 单位] | Node abscissae, strictly ascending
    aY        : ARRAY[1..100] OF REAL;    // 节点纵坐标表 [y 单位] | Node ordinates
    uPointCnt : UINT := 5;                // 有效点数，内部钳位 [2,100] [点] | Valid point count, clamped internally
END_VAR
VAR_OUTPUT
    fY     : REAL;                        // 插值结果（越界钳端点值）[y 单位] | Interpolated result, clamped at bounds
    bValid : BOOL;                        // 本次计算有效 [-] | Computation valid
    eErr   : UDINT;                       // 错误码，0 = 无错 | Error code, 0 = none
END_VAR
VAR
    nI      : INT;                        // 钳位后点数 [点] | Clamped point count
    i       : INT;                        // 循环游标 | Loop cursor
    iSeg    : INT;                        // 所在段左节点序号 | Segment left knot index
    bTabOk  : BOOL;                       // 表合法当拍量 [-] | Table legality this call
    bAkima  : BOOL;                       // Akima 路径标志（n >= 5）[-] | Akima path flag
    fQ      : REAL;                       // 钳界后查询点 [x 单位] | Clamped query point
    fDx     : REAL;                       // 段宽 [x 单位] | Segment width
    fTParam : REAL;                       // 段内归一化参数 t ∈ [0, 1] [-] | Normalized parameter in segment
    fT2     : REAL;                       // t 的平方 [-] | t squared
    fT3     : REAL;                       // t 的立方 [-] | t cubed
    w1      : REAL;                       // Akima 权重 |m_{i+1}-m_i| [-] | Akima weight upper
    w2      : REAL;                       // Akima 权重 |m_{i-1}-m_{i-2}| [-] | Akima weight lower
    aM      : ARRAY[1..103] OF REAL;      // 段斜率数组（含端部外拓 m_-1..m_n+1，下标偏移 +2）[y/x] | Segment slopes with two-sided extension, index offset +2
    aTang      : ARRAY[1..100] OF REAL;      // 节点切线数组 [y/x] | Knot tangents
END_VAR
VAR CONSTANT
    DL_AKI_EPS : REAL := 1.0E-6;          // 升序判据容差（节点最小间距）[x 单位] | Ascending tolerance
    DL_AKI_ERR : UDINT := 16#0001_0500;   // 节点表非法码 | Illegal table code
END_VAR

(* —— 段 0：输出缺省全赋值（全路径覆盖） —— *)
fY := 0.0;                                // 结果预置零 / Result preset zero
bValid := FALSE;                          // 有效标志预置 / Valid preset FALSE
eErr := 0;                                // 错误码缺省 / Error default
FC_DL_AkimaInterp1D := TRUE;              // 返回值：TRUE = 已执行 / Result: TRUE = executed

(* —— 段 1：点数钳位与表合法性闸（R75 显式点数字段口径） —— *)
nI := UINT_TO_INT(uPointCnt);             // 点数转整型 / Point count to INT
IF nI < 2 THEN
    nI := 2;                              // 下限钳 2（至少两点） / Clamp lower to 2
END_IF
IF nI > 100 THEN
    nI := 100;                            // 上限钳 100（数组容量） / Clamp upper to 100
END_IF
bTabOk := (fX = fX);                      // 查询点 NaN 自反判 / Query NaN self-reflex check
IF bTabOk THEN
    FOR i := 1 TO nI DO
        IF (aX[i] <> aX[i]) OR (aY[i] <> aY[i]) THEN
            bTabOk := FALSE;              // 节点值非有限 / Node value non-finite
        END_IF
    END_FOR
END_IF
IF bTabOk THEN
    FOR i := 1 TO (nI - 1) DO
        IF (aX[i + 1] - aX[i]) <= DL_AKI_EPS THEN
            bTabOk := FALSE;              // 严格升序被破坏（含重合节点） / Strict ascending violated
        END_IF
    END_FOR
END_IF
IF NOT bTabOk THEN
    eErr := DL_AKI_ERR;                   // 表非法码 / Illegal table code
    RETURN;                               // 提前返回：输出已全赋值 / Early return, outputs assigned
END_IF

(* —— 段 2：查询点钳界 —— *)
fQ := fX;                                 // 查询点暂存 / Query staging
IF fQ < aX[1] THEN
    fQ := aX[1];                          // 下界钳首节点 / Clamp to first knot
END_IF
IF fQ > aX[nI] THEN
    fQ := aX[nI];                         // 上界钳末节点 / Clamp to last knot
END_IF
bAkima := nI >= 5;                        // 5 点及以上走 Akima（端部外拓需 n >= 4） / Akima path for n >= 5

(* —— 段 3：Akima 段斜率与端部外拓 —— *)
IF bAkima THEN
    FOR i := 1 TO (nI - 1) DO
        fDx := aX[i + 1] - aX[i];         // 段宽（升序闸保证 > EPS） / Segment width, proven positive
        aM[i + 2] := (aY[i + 1] - aY[i]) / fDx;   // 段斜率 m_i 存 aM[i+2] / Segment slope, offset +2
    END_FOR
    aM[2] := 2.0 * aM[3] - aM[4];         // 端部外拓 m_0 = 2m_1 - m_2 / Extended slope m0
    aM[1] := 2.0 * aM[2] - aM[3];         // 端部外拓 m_-1 = 2m_0 - m_1 / Extended slope m-1
    aM[nI + 2] := 2.0 * aM[nI + 1] - aM[nI];       // 端部外拓 m_n = 2m_n-1 - m_n-2 / Extended slope mn
    aM[nI + 3] := 2.0 * aM[nI + 2] - aM[nI + 1];   // 端部外拓 m_n+1 = 2m_n - m_n-1 / Extended slope mn+1

    (* —— 段 4：节点切线（Akima 加权；权重和零回落均值防除零） —— *)
    FOR i := 1 TO nI DO
        w1 := ABS(aM[i + 3] - aM[i + 2]); // 权重 w1 = |m_{i+1} - m_i| / Weight from adjacent slope gap
        w2 := ABS(aM[i + 1] - aM[i]);     // 权重 w2 = |m_{i-1} - m_{i-2}| / Weight from second-adjacent gap
        IF (w1 + w2) > DL_AKI_EPS THEN
            aTang[i] := (w1 * aM[i + 1] + w2 * aM[i + 2]) / (w1 + w2);   // 加权切线（分母已闸）/ Weighted tangent, denominator gated
        ELSE
            aTang[i] := 0.5 * (aM[i + 1] + aM[i + 2]);   // 权重和零回落两邻段均值 / Fallback to mean of adjacent slopes
        END_IF
    END_FOR
END_IF

(* —— 段 5：段定位（fQ 已钳在 [aX[1], aX[nI]]，循环有界） —— *)
iSeg := 1;                                // 段定位从首段起 / Segment search from first
WHILE (iSeg < (nI - 1)) AND (fQ > aX[iSeg + 1]) DO
    iSeg := iSeg + 1;                     // 右移至目标段 / Advance to target segment
END_WHILE

(* —— 段 6：段内插值（Akima 三次 Hermite / 回落线性） —— *)
fDx := aX[iSeg + 1] - aX[iSeg];           // 段宽（升序闸保证 > EPS） / Segment width, proven positive
fTParam := (fQ - aX[iSeg]) / fDx;         // 归一化参数，分母已闸 / Normalized parameter, denominator gated
IF bAkima THEN
    fT2 := fTParam * fTParam;             // t² / t squared
    fT3 := fT2 * fTParam;                 // t³ / t cubed
    fY := aY[iSeg] * (2.0 * fT3 - 3.0 * fT2 + 1.0)
       + aY[iSeg + 1] * (3.0 * fT2 - 2.0 * fT3)
       + fDx * aTang[iSeg] * (fT3 - 2.0 * fT2 + fTParam)
       + fDx * aTang[iSeg + 1] * (fT3 - fT2);            // 三次 Hermite 基函数合成 / Cubic Hermite basis synthesis
ELSE
    fY := aY[iSeg] + fTParam * (aY[iSeg + 1] - aY[iSeg]);  // 线性回落（n < 5）/ Linear fallback
END_IF
bValid := TRUE;                           // 计算有效 / Valid

END_FUNCTION
