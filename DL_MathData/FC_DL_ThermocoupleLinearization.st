(*
  ==================================================================
  组件名 Component  : FC_DL_ThermocoupleLinearization
  分类   Category   : DL_MathData
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : 热电偶 mV↔温度双向线性化（K / N / S 三型）。内部按公开
                      ITS-90 参考分度表特征点（100 摄氏度步距锚点）做折线
                      插值，正向（温度→mV）与反向（mV→温度）共用同一单调
                      锚点表，域外钳位并置信息级，未知型别 / 非法方向 / 表
                      单调破坏判故障级。与 RtdLinearization / TempUnitConvert
                      / NtcTempScan 三分工边界按 ROADMAP 1083 行写死。
  来源   Source     : roadmap-p1（R56 评估项落地）
  溯源   Origin     : 锚点数值取自公开 ITS-90 热电偶参考分度表（clean-room
                      整理），插值算法为自研折线实现，未复制 NIST 数据库
                      程序或任何厂商私有库源码。
  精度声明 Precision : 100 摄氏度步距折线插值，K / N 型 0..1000 摄氏度段典型
                      误差 ±1.5 K 量级（S 型低温段略宽）；非 NIST 全阶多项式
                      ——全阶系数升级挂编译验证债（入库后另行立项复核）。
  平台   Platform   : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
  分工声明 Split     : 与 FC_DL_RtdLinearization 分工——Rtd 为铂电阻 Callendar-
                      Van Dusen 方程口径；与 FC_DL_TempUnitConvert 分工——
                      后者只做摄氏 / 华氏 / 开尔文单位换算；与 FB_DL_NtcTempScan
                      分工——Ntc 为 NTC 热敏电阻扫描查表；本件只做热电偶
                      mV↔温度双向线性化。
  作者   Author     : 道莅代码库 · PLC 编程专家（R58）
  ------------------------------------------------------------------
  功能说明  : 输入 fIn 按方向解释：eTempToMv 时 fIn 为摄氏度 [摄氏度]，返回
              毫伏 [毫伏]；eMvToTemp 时 fIn 为毫伏 [毫伏]，返回摄氏度 [摄氏度]。
              域闸门四段式（R45）：预置 → 非有限 / 型别 / 方向 / 单调性闸 →
              域内插值 → 结果非有限复检兜底。
  输出约定  : bError = TRUE 仅故障级（非有限 / 型别非法 / 方向非法 / 表单调
              破坏）；bClamped = TRUE 为信息级域外钳位（不置 bError），此时
              返回值为钳位端点值。
  修订记录  : 2026-11-21 v1.0.0 首次入库（R58 批 1 · 序号 3）
*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_TcKind（唯一属主 = 本文件，R67 全库唯一断言）
 * 含义: 支持的热电偶型别。
 *----------------------------------------------------------------------------*)
TYPE E_DL_TcKind :
(
    eTcK := 0, // K 型热电偶（镍铬 - 镍硅）/ the type K thermocouple
    eTcN := 1, // N 型热电偶（镍铬硅 - 镍硅）/ the type N thermocouple
    eTcS := 2  // S 型热电偶（铂铑 10 - 铂）/ the type S thermocouple
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_TcDir（唯一属主 = 本文件，R67 全库唯一断言）
 * 含义: 线性化方向。
 *----------------------------------------------------------------------------*)
TYPE E_DL_TcDir :
(
    eTempToMv := 0, // 正向：温度 → 毫伏 / the forward direction, temperature to millivolt
    eMvToTemp := 1  // 反向：毫伏 → 温度 / the reverse direction, millivolt to temperature
);
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_TlcCause（唯一属主 = 本文件，R67 全库唯一断言；零码位范式，
 *       收口派号前不写 16# 事件码，故障出口 = BOOL + ENUM）
 * 含义: 线性化结果成因（1..3 故障级 / 4 信息级）。
 *----------------------------------------------------------------------------*)
TYPE E_DL_TlcCause :
(
    eTlcNone         := 0, // 无成因 / no cause
    eTlcNonFinite    := 1, // 输入或结果非有限（故障级，与 bError 配对）/ a non finite input or result
    eTlcKindBad      := 2, // 型别非法或锚点表单调破坏（故障级，与 bError 配对）/ an unknown kind or a monotony break
    eTlcDirBad       := 3, // 方向非法（故障级，与 bError 配对）/ an illegal direction
    eTlcRangeClamped := 4  // 域外钳位（信息级，不置 bError）/ an out of range clamp, informational
);
END_TYPE

FUNCTION FC_DL_ThermocoupleLinearization : LREAL
VAR_INPUT
    fIn  : LREAL; // 输入量：正向为摄氏度 [摄氏度]，反向为毫伏 [毫伏] / the input, temperature in celsius forward or millivolt reverse
    eKind: E_DL_TcKind; // 热电偶型别选择 [枚举] / the thermocouple kind selector
    eDir : E_DL_TcDir;  // 线性化方向选择 [枚举] / the linearization direction selector
END_VAR
VAR_OUTPUT
    bError   : BOOL; // 故障标志，仅故障级置位 / the fault flag, fault grade only
    bClamped : BOOL; // 域外钳位发生（信息级，不置 bError）[-] / an out of range clamp happened, informational
    eCause   : E_DL_TlcCause; // 成因出口 [枚举] / the cause outlet
END_VAR
VAR
    afT    : ARRAY[0..17] OF LREAL; // 工作锚点温度表 [摄氏度] / the working anchor temperature table [degree celsius]
    afM    : ARRAY[0..17] OF LREAL; // 工作锚点热电势表 [毫伏] / the working anchor millivolt table [millivolt]
    nAnch  : DINT;  // 工作表有效锚点数 [个] / the valid anchor count of the working table
    nI     : DINT;  // 锚点遍历索引 [个] / the anchor loop index
    nSeg   : DINT;  // 命中段索引 [段] / the hit segment index
    lrX    : LREAL; // 工作量（已判向后的输入）[混合] / the working value after the direction verdict
    lrDen  : LREAL; // 命中段分母（锚点差）[混合] / the hit segment denominator
    lrRes  : LREAL; // 结果工作量 [混合] / the result working value
    bBad   : BOOL;  // 故障级闸命中工作量 [-] / the fault gate hit work flag
END_VAR
VAR CONSTANT
    aTkT : ARRAY[0..14] OF LREAL := [-100.0, 0.0, 100.0, 200.0, 300.0, 400.0, 500.0, 600.0, 700.0, 800.0, 900.0, 1000.0, 1100.0, 1200.0, 1300.0]; // K 型锚点温度表 [摄氏度]，严格递增 / the type K anchor temperatures, strictly increasing
    aTkM : ARRAY[0..14] OF LREAL := [-3.554, 0.0, 4.096, 8.138, 12.209, 16.397, 20.644, 24.905, 29.129, 33.275, 37.326, 41.276, 45.119, 48.838, 52.398]; // K 型锚点热电势表 [毫伏]，严格递增 / the type K anchor millivolts, strictly increasing
    aTnT : ARRAY[0..14] OF LREAL := [-100.0, 0.0, 100.0, 200.0, 300.0, 400.0, 500.0, 600.0, 700.0, 800.0, 900.0, 1000.0, 1100.0, 1200.0, 1300.0]; // N 型锚点温度表 [摄氏度]，严格递增 / the type N anchor temperatures, strictly increasing
    aTnM : ARRAY[0..14] OF LREAL := [-2.655, 0.0, 2.774, 5.913, 9.341, 12.974, 16.748, 20.644, 24.639, 28.608, 32.542, 36.382, 40.103, 43.770, 47.348]; // N 型锚点热电势表 [毫伏]，严格递增 / the type N anchor millivolts, strictly increasing
    aTsT : ARRAY[0..17] OF LREAL := [0.0, 100.0, 200.0, 300.0, 400.0, 500.0, 600.0, 700.0, 800.0, 900.0, 1000.0, 1100.0, 1200.0, 1300.0, 1400.0, 1500.0, 1600.0, 1700.0]; // S 型锚点温度表 [摄氏度]，严格递增 / the type S anchor temperatures, strictly increasing
    aTsM : ARRAY[0..17] OF LREAL := [0.0, 0.646, 1.441, 2.323, 3.259, 4.233, 5.239, 6.274, 7.345, 8.448, 9.587, 10.754, 11.947, 13.159, 14.373, 15.582, 16.777, 17.942]; // S 型锚点热电势表 [毫伏]，严格递增 / the type S anchor millivolts, strictly increasing
END_VAR

// 段 1｜返回值与错误状态预置安全值（四段式第一段，R45）/ segment 1, preset the return and error states
FC_DL_ThermocoupleLinearization := 0.0; // 返回值预置 0.0 / preset the return to the safe zero
bError   := FALSE; // 故障标志预置假 / preset the fault flag false
bClamped := FALSE; // 钳位标志预置假 / preset the clamp flag false
eCause   := E_DL_TlcCause.eTlcNone; // 成因预置无 / preset the cause none
bBad     := FALSE; // 故障闸工作量预置假 / preset the fault work flag false

// 段 2｜非有限拦截（自反双判据，R79）/ segment 2, the non finite interception
IF (fIn <> fIn) OR ((fIn - fIn) <> (fIn - fIn)) THEN // 输入非有限 / a non finite input
    bBad   := TRUE; // 置故障闸 / raise the fault gate
    eCause := E_DL_TlcCause.eTlcNonFinite; // 故障级成因（R45 配对）/ the fault cause
END_IF

// 段 3｜型别装表 + 方向闸 + 表单调自检 / segment 3, the table loading, the direction gate and the monotony self check
IF NOT bBad THEN // 非有限未命中才装表 / load the table only when finite
    CASE eKind OF // 按型别装工作表（其余锚点槽保持缺省零，不在有效域内使用）/ load the working table by kind
    E_DL_TcKind.eTcK: // K 型 / the type K
        nAnch := 15; // 有效锚点数 / the valid anchor count
        FOR nI := 0 TO 14 DO // 固定界复制 / the fixed bound copy
            afT[nI] := aTkT[nI]; // 装温度锚点 / load the temperature anchor
            afM[nI] := aTkM[nI]; // 装热电势锚点 / load the millivolt anchor
        END_FOR
    E_DL_TcKind.eTcN: // N 型 / the type N
        nAnch := 15; // 有效锚点数 / the valid anchor count
        FOR nI := 0 TO 14 DO // 固定界复制 / the fixed bound copy
            afT[nI] := aTnT[nI]; // 装温度锚点 / load the temperature anchor
            afM[nI] := aTnM[nI]; // 装热电势锚点 / load the millivolt anchor
        END_FOR
    E_DL_TcKind.eTcS: // S 型 / the type S
        nAnch := 18; // 有效锚点数 / the valid anchor count
        FOR nI := 0 TO 17 DO // 固定界复制 / the fixed bound copy
            afT[nI] := aTsT[nI]; // 装温度锚点 / load the temperature anchor
            afM[nI] := aTsM[nI]; // 装热电势锚点 / load the millivolt anchor
        END_FOR
    ELSE // 未知型别兜底（R128）/ the unknown kind fallback
        nAnch  := 0; // 不装表 / no table
        bBad   := TRUE; // 置故障闸 / raise the fault gate
        eCause := E_DL_TlcCause.eTlcKindBad; // 故障级成因 / the fault cause
    END_CASE
    IF (NOT bBad) AND (nAnch >= 2) THEN // 表已装且至少两锚点才自检 / self check with a loaded table
        FOR nI := 0 TO nAnch - 2 DO // 逐段单调自检（防御深，常量表本应单调）/ the per segment monotony self check, defense in depth
            IF (afT[nI + 1] <= afT[nI]) OR (afM[nI + 1] <= afM[nI]) THEN // 单调破坏 / a monotony break
                bBad   := TRUE; // 置故障闸 / raise the fault gate
                eCause := E_DL_TlcCause.eTlcKindBad; // 故障级成因（表损坏归型别成因）/ the fault cause, a broken table maps to the kind cause
            END_IF
        END_FOR
    END_IF
END_IF

// 段 4｜方向闸与双向插值（域外钳位信息级，除子单调已证大于零）/ segment 4, the direction gate and the bidirectional interpolation
IF NOT bBad THEN // 无故障才插值 / interpolate only without a fault
    CASE eDir OF // 方向闸（含非法方向兜底 R128）/ the direction gate with the illegal fallback
    E_DL_TcDir.eTempToMv: // 正向：温度→毫伏 / the forward direction
        lrX := fIn; // 工作量为摄氏度 / the working value in celsius
        IF lrX < afT[0] THEN // 低于域下界 / below the floor
            lrX := afT[0]; // 钳到下端点 / clamp to the lower anchor
            bClamped := TRUE; // 信息级钳位 / the informational clamp
        ELSIF lrX > afT[nAnch - 1] THEN // 高于域上界 / above the bound
            lrX := afT[nAnch - 1]; // 钳到上端点 / clamp to the upper anchor
            bClamped := TRUE; // 信息级钳位 / the informational clamp
        END_IF
        nSeg := nAnch - 2; // 段索引预置末段（上端点命中）/ preset the last segment
        FOR nI := 0 TO nAnch - 2 DO // 有界段搜索（命中即出，无死循环）/ the bounded segment search
            IF lrX <= afT[nI + 1] THEN // 命中段 / a hit segment
                nSeg := nI; // 记段索引 / record the segment
                EXIT; // 提前出循环 / leave early
            END_IF
        END_FOR
        lrDen := afT[nSeg + 1] - afT[nSeg]; // 温差分母 [摄氏度] / the temperature denominator
        IF lrDen > 1.0E-12 THEN // 除子护栏（单调自检已证，防御深）/ the divisor guard
            lrRes := afM[nSeg] + (lrX - afT[nSeg]) * (afM[nSeg + 1] - afM[nSeg]) / lrDen; // 折线插值 / the linear interpolation
        ELSE // 分母退化（不可达路径兜底）/ the degenerate divisor, unreachable
            bBad   := TRUE; // 置故障闸 / raise the fault gate
            eCause := E_DL_TlcCause.eTlcKindBad; // 故障级成因 / the fault cause
        END_IF
    E_DL_TcDir.eMvToTemp: // 反向：毫伏→温度 / the reverse direction
        lrX := fIn; // 工作量为毫伏 / the working value in millivolt
        IF lrX < afM[0] THEN // 低于域下界 / below the floor
            lrX := afM[0]; // 钳到下端点 / clamp to the lower anchor
            bClamped := TRUE; // 信息级钳位 / the informational clamp
        ELSIF lrX > afM[nAnch - 1] THEN // 高于域上界 / above the bound
            lrX := afM[nAnch - 1]; // 钳到上端点 / clamp to the upper anchor
            bClamped := TRUE; // 信息级钳位 / the informational clamp
        END_IF
        nSeg := nAnch - 2; // 段索引预置末段 / preset the last segment
        FOR nI := 0 TO nAnch - 2 DO // 有界段搜索 / the bounded segment search
            IF lrX <= afM[nI + 1] THEN // 命中段 / a hit segment
                nSeg := nI; // 记段索引 / record the segment
                EXIT; // 提前出循环 / leave early
            END_IF
        END_FOR
        lrDen := afM[nSeg + 1] - afM[nSeg]; // 热电势差分母 [毫伏] / the millivolt denominator
        IF lrDen > 1.0E-12 THEN // 除子护栏（单调自检已证，防御深）/ the divisor guard
            lrRes := afT[nSeg] + (lrX - afM[nSeg]) * (afT[nSeg + 1] - afT[nSeg]) / lrDen; // 反向折线插值 / the reverse interpolation
        ELSE // 分母退化（不可达路径兜底）/ the degenerate divisor, unreachable
            bBad   := TRUE; // 置故障闸 / raise the fault gate
            eCause := E_DL_TlcCause.eTlcKindBad; // 故障级成因 / the fault cause
        END_IF
    ELSE // 非法方向兜底（R128）/ the illegal direction fallback
        bBad   := TRUE; // 置故障闸 / raise the fault gate
        eCause := E_DL_TlcCause.eTlcDirBad; // 故障级成因 / the fault cause
    END_CASE
END_IF

// 段 5｜结果非有限复检兜底（防御纵深，正常路径不可达）/ segment 5, the result recheck as defense in depth
IF (NOT bBad) AND ((lrRes <> lrRes) OR ((lrRes - lrRes) <> (lrRes - lrRes))) THEN // 结果非有限 / a non finite result
    bBad   := TRUE; // 置故障闸 / raise the fault gate
    eCause := E_DL_TlcCause.eTlcNonFinite; // 故障级成因 / the fault cause
END_IF
IF bBad THEN // 故障出口 / the fault outlet
    FC_DL_ThermocoupleLinearization := 0.0; // 返回预置安全值 / return the safe zero
    bError := TRUE; // 置故障标志（R45 配对）/ raise the fault flag
ELSE // 正常出口 / the normal outlet
    FC_DL_ThermocoupleLinearization := lrRes; // 返回插值结果 / return the interpolation result
END_IF
END_FUNCTION
