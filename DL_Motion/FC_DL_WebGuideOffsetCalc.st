(*
  Component : FC_DL_WebGuideOffsetCalc
  Category  : DL_Motion
  Function  : 纠偏偏移量计算：边缘模式取单侧偏差，中心模式取双传感器均值差，输出带符号偏移
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 eMode 检测模式枚举、rEdgeLeftMm 左侧传感器距离 [mm]、rEdgeRightMm 右侧传感器距离 [mm]、
             rSensorSpanMm 两传感器安装跨距 [mm]、rCenterRefMm 目标中心（跨距中点为零点） [mm]；
             输出 rOffsetMm 带符号偏移（正=卷材偏右） [mm]、rCenterPosMm 卷材中心位置 [mm]、
             xValid 有效标志、nFaultCode 故障码。
  边界     : 边缘模式只用左侧传感器，中心位置 = 左侧距离；中心模式中心位置 = (左距离 + (跨距 − 右距离))/2，
             跨距须 >1.0E-6 [mm]；偏移为带符号量，不做钳位（符号即纠偏方向，钳位会反转方向）。
  码位     : 9801 输入非有限（故障级）；9802 跨距越域（故障级）；9803 模式枚举未知（故障级）。
*)
TYPE E_DL_WebGuideMode :
(
    eEdge   := 0,    // 边缘模式：单侧传感器对边 EN: the edge mode using one side sensor
    eCenter := 1     // 中心模式：双传感器对中 EN: the center mode using two sensors
);
END_TYPE

FUNCTION FC_DL_WebGuideOffsetCalc : BOOL
VAR_INPUT
    eMode        : E_DL_WebGuideMode;   // 检测模式 [-] EN: the detection mode
    rEdgeLeftMm  : LREAL := 50.0;       // 左侧传感器到卷材边距离 [mm] EN: the distance from the left sensor to the web edge
    rEdgeRightMm : LREAL := 50.0;       // 右侧传感器到卷材边距离 [mm] EN: the distance from the right sensor to the web edge
    rSensorSpanMm: LREAL := 400.0;      // 两传感器安装跨距 [mm] EN: the mounting span between the two sensors
    rCenterRefMm : LREAL := 200.0;      // 目标中心位置（相对左传感器） [mm] EN: the target center position relative to the left sensor
END_VAR
VAR_OUTPUT
    rOffsetMm    : LREAL;               // 带符号偏移，正表示卷材偏右 [mm] EN: the signed offset, positive means the web is to the right
    rCenterPosMm : LREAL;               // 卷材中心实测位置 [mm] EN: the measured web center position
    xValid       : BOOL;                // 输出可信标志 EN: the outputs are valid
    nFaultCode   : INT;                 // 0=无故障 9801=输入非有限 9802=跨距越域 9803=模式未知 EN: zero none, 9801 non finite, 9802 span out of range, 9803 unknown mode
END_VAR
VAR
    xFinAll  : BOOL;                    // 四个浮点入参有限 EN: the four floating inputs are finite
    rCenter  : LREAL;                   // 中心位置中间值 [mm] EN: the interim center position
    rOff     : LREAL;                   // 偏移中间值 [mm] EN: the interim offset
END_VAR
VAR CONSTANT
    DL_WGO_Z     : LREAL := 0.0;        // 浮点零常量 EN: the floating point zero constant
    DL_WGO_TWO   : LREAL := 2.0;        // 双侧平均系数 EN: the two sided averaging factor
    DL_WGO_MIN   : LREAL := 1.0E-6;     // 跨距下限 [mm] EN: the lower bound of the span
    DL_WGO_C_BAD : INT := 9801;         // 输入非有限 EN: a non finite input
    DL_WGO_C_SPAN: INT := 9802;         // 跨距越域 EN: the span is out of range
    DL_WGO_C_MODE: INT := 9803;         // 模式枚举未知 EN: the mode is unknown
END_VAR

// 段1｜出口预置
FC_DL_WebGuideOffsetCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
rOffsetMm := DL_WGO_Z;               // 偏移预置零 [mm] EN: preset the offset to zero
rCenterPosMm := DL_WGO_Z;            // 中心位置预置零 [mm] EN: preset the center position to zero
xValid := FALSE;                     // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                     // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：四浮点入参全列（跨距与目标中心参与换算，漏则偏移静默失效）
xFinAll := (rEdgeLeftMm = rEdgeLeftMm) AND ((rEdgeLeftMm - rEdgeLeftMm) = DL_WGO_Z)
        AND (rEdgeRightMm = rEdgeRightMm) AND ((rEdgeRightMm - rEdgeRightMm) = DL_WGO_Z)
        AND (rSensorSpanMm = rSensorSpanMm) AND ((rSensorSpanMm - rSensorSpanMm) = DL_WGO_Z)
        AND (rCenterRefMm = rCenterRefMm) AND ((rCenterRefMm - rCenterRefMm) = DL_WGO_Z);   // 四输入有限性 EN: the finiteness of all four inputs
IF NOT xFinAll THEN                                                                          // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_WGO_C_BAD;                                                              // 非有限码 EN: the non finite code
    RETURN;                                                                                  // 早退 EN: return early
END_IF

// 段3｜域闸：跨距必须足够大，否则中心模式分母退化
IF ABS(rSensorSpanMm) < DL_WGO_MIN THEN                                                      // 跨距下限 EN: the span magnitude gate
    nFaultCode := DL_WGO_C_SPAN;                                                             // 跨距越域码 EN: the span code
    RETURN;                                                                                  // 早退 EN: return early
END_IF

// 段4｜模式分派：ENUM + CASE 且 ELSE 兜底
CASE eMode OF
    E_DL_WebGuideMode.eEdge:
        rCenter := rEdgeLeftMm;                                                              // 边缘模式：左边缘即位置 [mm] EN: the edge mode uses the left edge as the position
    E_DL_WebGuideMode.eCenter:
        rCenter := (rEdgeLeftMm + (rSensorSpanMm - rEdgeRightMm)) / DL_WGO_TWO;              // 中心模式：两边中点 [mm] EN: the center mode averages both edges
ELSE
    nFaultCode := DL_WGO_C_MODE;                                                             // 未知模式码 EN: the unknown mode code
    RETURN;                                                                                  // 早退 EN: return early
END_CASE

// 段5｜偏移 = 实测中心 − 目标中心（符号保留方向）
rOff := rCenter - rCenterRefMm;                                                              // 带符号偏移 [mm] EN: the signed offset
IF (rOff <> rOff) OR (rCenter <> rCenter) THEN                                               // 结果复检 EN: recheck the result
    nFaultCode := DL_WGO_C_BAD;                                                              // 复检失败码 EN: the recheck failure code
    RETURN;                                                                                  // 早退，出口保持零哨兵 EN: return early with the zero sentinels
END_IF
rOffsetMm := rOff;                                                                           // 偏移出口 [mm] EN: the offset output
rCenterPosMm := rCenter;                                                                     // 中心位置出口 [mm] EN: the center position output
xValid := TRUE;                                                                              // 结果可信 EN: the results are valid
FC_DL_WebGuideOffsetCalc := TRUE;                                                            // 返回真 EN: return true
END_FUNCTION
