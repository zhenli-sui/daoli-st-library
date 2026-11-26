(*
  Component : FC_DL_CathodeSaggerLoadCalc
  Category  : DL_Process
  Function  : 匣钵装载量 = 层数 × 每层片数 × 单重，并做超重告警
  Complexity: C2
  开源溯源 : DLF 内部原创（R94 族模板派生）；参考语义来源见 SOURCE_HUNTING_MATRIX.md
  规则遵从 : R1-R16
  契约     : 输入 nLayers 层数 [层]、nPerLayer 每层片数 [片/层]、rPieceKg 单片重量 [kg]、
             rMaxLoadKg 匣钵允许装载上限 [kg]；输出 nPieceCount 总片数 [片]、rLoadKg 装载总重 [kg]、
             xOverload 超重（故障级：超重会导致匣钵破裂并损坏辊棒，按安全侧立即判故障）、
             xValid 有效标志、nFaultCode 故障码。
  边界     : 层数与每层片数须在 0~999 内（超过 999 属组态错误，防整数乘法溢出判 9802）；
             单片重量须 ≥0；上限须 >0；总片数 = 层数 × 每层片数，最大 999×999 = 998001 片，INT 可表；
             超重按方向明确判「超上限」，故为故障级（R146：与安全侧一致的异常立即终止）。
  码位     : 9801 输入非有限或为负（故障级）；9802 计数越界（故障级）；9803 超重（故障级）。
*)
FUNCTION FC_DL_CathodeSaggerLoadCalc : BOOL
VAR_INPUT
    nLayers    : INT := 8;           // 匣钵叠放层数 [层] EN: the number of stacked layers in the sagger
    nPerLayer  : INT := 6;           // 每层片数 [片/层] EN: the number of pieces per layer
    rPieceKg   : LREAL := 0.5;       // 单片重量 [kg] EN: the weight of one piece
    rMaxLoadKg : LREAL := 30.0;      // 匣钵允许装载上限 [kg] EN: the allowed load limit of the sagger
END_VAR
VAR_OUTPUT
    nPieceCount : INT;               // 总片数 [片] EN: the total piece count
    rLoadKg     : LREAL;             // 装载总重 [kg] EN: the total load weight
    xOverload   : BOOL;              // 超重（故障级） EN: the load exceeds the limit, a fault class condition
    xValid      : BOOL;              // 输出可信标志 EN: the outputs are valid
    nFaultCode  : INT;               // 0=无故障 9801=输入非法 9802=计数越界 9803=超重 EN: zero none, 9801 illegal input, 9802 count out of range, 9803 overload
END_VAR
VAR
    xFinAll  : BOOL;                 // 两个浮点入参有限 EN: both floating inputs are finite
    nCnt     : INT;                  // 总片数中间值 [片] EN: the interim piece count
    rLoad    : LREAL;                // 总重中间值 [kg] EN: the interim load weight
END_VAR
VAR CONSTANT
    DL_CSL_Z      : LREAL := 0.0;    // 浮点零常量 EN: the floating point zero constant
    DL_CSL_CNT_MAX: INT := 999;      // 层数与每层片数上限 [个] EN: the upper bound of the layer count and the per layer count
    DL_CSL_C_BAD  : INT := 9801;     // 输入非法 EN: an illegal input
    DL_CSL_C_CNT  : INT := 9802;     // 计数越界 EN: the count is out of range
    DL_CSL_C_OVER : INT := 9803;     // 超重 EN: the overload condition
END_VAR

// 段1｜出口预置
FC_DL_CathodeSaggerLoadCalc := FALSE;   // 返回值预置假 EN: preset the return value to false
nPieceCount := 0;                        // 总片数预置零 [片] EN: preset the piece count to zero
rLoadKg := DL_CSL_Z;                     // 总重预置零 [kg] EN: preset the load weight to zero
xOverload := FALSE;                      // 超重标志预置假 EN: preset the overload flag to false
xValid := FALSE;                         // 有效标志预置假 EN: preset the validity flag to false
nFaultCode := 0;                         // 故障码预置零 EN: preset the fault code to zero

// 段2｜非有限闸：两个浮点入参全列（上限参与超重判据）
xFinAll := (rPieceKg = rPieceKg) AND ((rPieceKg - rPieceKg) = DL_CSL_Z)
        AND (rMaxLoadKg = rMaxLoadKg) AND ((rMaxLoadKg - rMaxLoadKg) = DL_CSL_Z);   // 两输入有限性 EN: the finiteness of both inputs
IF NOT xFinAll THEN                                                                 // 非有限出口 EN: leave early on a non finite input
    nFaultCode := DL_CSL_C_BAD;                                                     // 输入非法码 EN: the illegal input code
    RETURN;                                                                         // 早退 EN: return early
END_IF

// 段3｜域闸：单片重量与上限为正、两计数非负且不超 999
IF (rPieceKg < DL_CSL_Z) OR (rMaxLoadKg <= DL_CSL_Z) THEN                            // 数值域闸 EN: the numeric domain gate
    nFaultCode := DL_CSL_C_BAD;                                                     // 输入非法码 EN: the illegal input code
    RETURN;                                                                         // 早退 EN: return early
END_IF
IF (nLayers < 0) OR (nLayers > DL_CSL_CNT_MAX) OR (nPerLayer < 0) OR (nPerLayer > DL_CSL_CNT_MAX) THEN
    nFaultCode := DL_CSL_C_CNT;                                                     // 计数越界码 EN: the count out of range code
    RETURN;                                                                         // 早退 EN: return early
END_IF

// 段4｜主体：片数用整数乘（取值范围已证），重量用标准转换后相乘
nCnt := nLayers * nPerLayer;                                                        // 总片数 [片] EN: the total piece count
rLoad := INT_TO_LREAL(nCnt) * rPieceKg;                                             // 总重 [kg] EN: the total load weight

// 段5｜出口：超重为故障级（安全侧一致的方向明确异常立即终止）
nPieceCount := nCnt;                                                                // 总片数出口 [片] EN: the piece count output
rLoadKg := rLoad;                                                                   // 总重出口 [kg] EN: the load weight output
IF rLoad > rMaxLoadKg THEN                                                          // 超重判据 EN: the overload test
    xOverload := TRUE;                                                              // 置超重标志 EN: raise the overload flag
    nFaultCode := DL_CSL_C_OVER;                                                    // 超重码 EN: the overload code
    xValid := FALSE;                                                                // 超重时输出不可用于投料 EN: the outputs are not usable for loading
    RETURN;                                                                         // 早退（返回假） EN: return false
END_IF
xValid := TRUE;                                                                     // 结果可信 EN: the results are valid
FC_DL_CathodeSaggerLoadCalc := TRUE;                                                // 返回真 EN: return true
END_FUNCTION
