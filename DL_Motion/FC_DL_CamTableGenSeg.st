(*
  ==================================================================
  组件名 Component  : FC_DL_CamTableGenSeg
  分类   Category   : DL_Motion
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : 凸轮表段型自动生成。按边界点（起点 / 终点）与点数生成
                      点列，段型三选一：线性 / 五次多项式（6u⁵-15u⁴+10u³）/
                      摆线（正弦修正单段位移式 u - sin(2πu)/(2π)）；生成后
                      做逐点单调性自检。供 CamTableValidate 前置使用。
  来源   Source     : t1-6-plcopen（凸轮族补口）
  溯源   Origin     : 段型位移表达式为公开凸轮设计教材内容（clean-room 整
                      理），生成与自检为自研实现，未复制 PLCopen 或任何厂商
                      私有库源码。
  平台   Platform   : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
  分工声明 Split     : 与 DL_Motion 存量 FC_DL_CamTableValidate 分工——后者
                      验证既有凸轮表合法性，本件按段型生成点列供其前置；
                      本件不做电子凸轮耦合与主轴同步。
  作者   Author     : 道莅代码库 · PLC 编程专家（R58）
  ------------------------------------------------------------------
  功能说明  : 四段式防御（R45）：预置 → 非有限 / 点数域闸（钳位 2..64，信
              息级）→ 域内逐点生成（除子 nPoints-1 ≥ 1 已证）→ 单调性自检
              与结果非有限复检兜底。afTable 仅写 0..nPoints-1 槽位，其余槽
              位由调用方自行清理（本件不触碰，契约声明）。
  输出约定  : bOk = 生成受理；bClamped = 点数越域已钳位（信息级）；bMonoBad
              = 单调性自检失败（故障级，此时 bOk = FALSE）。
  修订记录  : 2026-11-21 v1.0.0 首次入库（R58 批 3 · 序号 12）
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_CamSegType（唯一属主 = 本文件，R67 全库唯一断言）
 * 含义: 凸轮表段型。
 *----------------------------------------------------------------------------*)
TYPE E_DL_CamSegType :
(
    eLinear  := 0, // 线性段 / the linear segment
    eQuintic := 1, // 五次多项式段 / the quintic segment
    eCycloid := 2  // 摆线段（正弦修正单段位移式）/ the cycloid segment, the sinusoid modified single segment form
);
END_TYPE

FUNCTION FC_DL_CamTableGenSeg : BOOL
VAR_INPUT
    eSegType  : E_DL_CamSegType; // 段型选择 [枚举] / the segment type selector
    fStartPos : LREAL; // 段起点位置 [工程单位] / the segment start position [engineering unit]
    fEndPos   : LREAL; // 段终点位置 [工程单位] / the segment end position [engineering unit]
    nPoints   : DINT;  // 生成点数 [个]，钳位 2..64 / the generated point count, clamped two through sixty four
END_VAR
VAR_IN_OUT
    afTable : ARRAY[0..63] OF LREAL; // 生成点列表 [工程单位]，仅写 0..nPoints-1 / the generated point list, only the first nPoints slots written
END_VAR
VAR_OUTPUT
    bOk      : BOOL; // 生成受理标志 [-] / the accepted flag
    bClamped : BOOL; // 点数越域钳位发生（信息级）[-] / a point count clamp happened, informational
    bMonoBad : BOOL; // 单调性自检失败（故障级）[-] / the monotony self check failed, fault grade
END_VAR
VAR
    lrSpan  : LREAL; // 段行程 [工程单位] / the segment span
    lrU     : LREAL; // 归一化进度 [无量纲] / the normalized progress
    lrS     : LREAL; // 段型形状因子 [无量纲] / the segment shape factor
    lrPos   : LREAL; // 点位置工作量 [工程单位] / the point position work value
    lrPrev  : LREAL; // 前点形状因子快照 [无量纲] / the previous shape factor snapshot
    lrSgn   : LREAL; // 方向号（+1 上行、-1 下行、0 平段）[无量纲] / the direction sign
    nPts    : DINT;  // 点数工作副本 [个] / the point count work copy
    nI      : DINT;  // 点遍历索引 [个] / the point loop index
    bBad    : BOOL;  // 故障级闸命中工作量 [-] / the fault gate work flag
END_VAR
VAR CONSTANT
    DL_CTS_NMAX   : DINT  := 64;                  // 点数上界 [个]，与数组容量一致 / the point bound, aligned with the array capacity
    DL_CTS_TWOPI  : LREAL := 6.283185307179586;   // 圆周率二倍（LREAL 精度字面量，R51）/ two pi at LREAL precision
END_VAR

// 段 1｜返回值与错误状态预置安全值（四段式第一段，R45）/ segment 1, preset the return and error states
FC_DL_CamTableGenSeg := FALSE; // 受理标志预置假 / preset the accepted flag false
bOk := FALSE; // 受理标志预置假 / preset the accepted flag false
bClamped := FALSE; // 钳位标志预置假 / preset the clamp flag false
bMonoBad := FALSE; // 单调标志预置假 / preset the mono flag false
bBad := FALSE; // 故障闸工作量预置假 / preset the fault work flag false

// 段 2｜非有限入参闸（起点终点双判据，R79）/ segment 2, the non finite input gate
IF (fStartPos <> fStartPos) OR ((fStartPos - fStartPos) <> (fStartPos - fStartPos)) THEN // 起点非有限 / a non finite start
    bBad := TRUE; // 置故障闸 / raise the fault gate
END_IF
IF (fEndPos <> fEndPos) OR ((fEndPos - fEndPos) <> (fEndPos - fEndPos)) THEN // 终点非有限 / a non finite end
    bBad := TRUE; // 置故障闸 / raise the fault gate
END_IF

// 段 3｜点数钳位（信息级，边界与数组容量一致，索引结构性安全）/ segment 3, the point count clamp
nPts := nPoints; // 装工作副本 / load the work copy
IF nPts < 2 THEN // 低于下界（单点无法构成段）/ below the floor
    nPts := 2; // 钳到 2 / clamp to two
    bClamped := TRUE; // 信息级钳位 / the informational clamp
ELSIF nPts > DL_CTS_NMAX THEN // 高于上界 / above the bound
    nPts := DL_CTS_NMAX; // 钳到容量 / clamp to the capacity
    bClamped := TRUE; // 信息级钳位 / the informational clamp
END_IF

// 段 4｜段型生成（除子 nPts-1 ≥ 1 已证；两极限自检见边界段）/ segment 4, the generation by the segment type
lrSpan := fEndPos - fStartPos; // 段行程 / the span
IF NOT bBad THEN // 无故障才生成 / generate only without a fault
    lrSgn := 0.0; // 方向号预置平段 / preset the sign zero
    IF lrSpan > 1.0E-12 THEN // 上行段 / an up segment
        lrSgn := 1.0; // 方向号置正 / the sign positive
    ELSIF lrSpan < -1.0E-12 THEN // 下行段 / a down segment
        lrSgn := -1.0; // 方向号置负 / the sign negative
    END_IF
    lrPrev := 0.0; // 前点因子快照预置零（首点因子恒 0）/ preset the previous snapshot
    FOR nI := 0 TO nPts - 1 DO // 逐点生成（固定界）/ the per point generation
        lrU := DINT_TO_LREAL(nI) / DINT_TO_LREAL(nPts - 1); // 归一化进度（除子已证 ≥1）/ the normalized progress
        CASE eSegType OF // 段型形状因子（边界点 s(0)=0 / s(1)=1 两极限自检成立）/ the shape factor, the both ends verified
        E_DL_CamSegType.eLinear: // 线性段 / the linear segment
            lrS := lrU; // 线性形状 / the linear shape
        E_DL_CamSegType.eQuintic: // 五次多项式段 / the quintic segment
            lrS := 10.0 * lrU * lrU * lrU - 15.0 * lrU * lrU * lrU * lrU + 6.0 * lrU * lrU * lrU * lrU * lrU; // 6u⁵-15u⁴+10u³ / the quintic form
        E_DL_CamSegType.eCycloid: // 摆线段（正弦修正单段位移式）/ the cycloid segment
            lrS := lrU - SIN(DL_CTS_TWOPI * lrU) / DL_CTS_TWOPI; // u - sin(2πu)/(2π) / the cycloidal form
        ELSE // 未知段型兜底（R128）/ the unknown segment fallback
            bBad := TRUE; // 置故障闸 / raise the fault gate
            lrS := 0.0; // 因子安全值 / the safe factor
        END_CASE
        lrPos := fStartPos + lrS * lrSpan; // 点位置 / the point position
        IF (lrPos <> lrPos) OR ((lrPos - lrPos) <> (lrPos - lrPos)) THEN // 点位置非有限（累乘溢出防御）/ a non finite point
            bBad := TRUE; // 置故障闸 / raise the fault gate
        END_IF
        IF NOT bBad THEN // 无故障才写表 / write the table only without a fault
            afTable[nI] := lrPos; // 写点（索引已证 < nPts ≤ 64）/ write the point
            IF nI > 0 THEN // 非首点做单调预检（逐点，最终判定在段 5）/ the per point mono pre check
                IF lrSgn > 0.0 THEN // 上行预检 / the up pre check
                    IF lrS < (lrPrev - 1.0E-12) THEN // 形状因子回落 / a shape dip
                        bMonoBad := TRUE; // 置单调失败 / raise the mono failure
                    END_IF
                ELSIF lrSgn < 0.0 THEN // 下行预检 / the down pre check
                    IF lrS > (lrPrev + 1.0E-12) THEN // 形状因子反弹 / a shape bounce
                        bMonoBad := TRUE; // 置单调失败 / raise the mono failure
                    END_IF
                END_IF // 平段（lrSgn = 0）无单调判据（两端点相等，逐点值恒等）
            END_IF
            lrPrev := lrS; // 快照推进 / advance the snapshot
        END_IF
    END_FOR
END_IF

// 段 5｜受理出口（单调失败为故障级，受理拒绝）/ segment 5, the acceptance outlet
IF bBad OR bMonoBad THEN // 故障或单调失败 / a fault or a mono failure
    FC_DL_CamTableGenSeg := FALSE; // 拒绝受理 / refuse the acceptance
ELSE // 正常受理 / the normal acceptance
    FC_DL_CamTableGenSeg := TRUE; // 受理 / accept
    bOk := TRUE; // 受理标志 / the accepted flag
END_IF
END_FUNCTION
