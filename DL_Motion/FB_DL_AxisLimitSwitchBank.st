(*
  ==================================================================
  组件名 Component  : FB_DL_AxisLimitSwitchBank
  分类   Category   : DL_Motion
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : 硬限位开关组分侧判 + 越限锁存 + 越限计数（硬件开关组）。
  来源   Source     : t1-6-plcopen（PLCopen 安全限位语义）
  平台   Platform   : 纯 IEC 61131-3（R_TRIG / 比较），三平台通用
  分工声明 Split     : 与 FB_DL_SoftLimitGuard（软件限幅属主）分工——后者做
                      软件限幅预测降速；本件只判硬件开关组电平（R216 双向互引）。
  作者   Author     : 道莅代码库 · PLC 编程专家（R61）
  归属 Ownership     : 本件无 TYPE 声明；引用件类型全部 IEC 标准原生。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 限位触发即锁存且方向侧独立（R190 归因唯一：正/负向各有
                         独立锁存位与独立码值）；
                      二 复位引脚解除式自证：bReset 上升沿清双侧锁存（输入引脚
                         恒可达，R152 自证）；越限计数同沿一并清零（R311 作用域
                         声明：清锁存 + 清计数，不清开关电平镜像）；
                      三 开关极性组态：bSwNC = TRUE（默认，常闭安全侧）时开关
                         断开判触发，FALSE 时闭合判触发；
                      四 无状态驻留派生量；R_TRIG 段 0 无条件刷新（禁入分支）；
                      五 无全局、无外部变量、无物理地址。
  错误码   Codes    :
    16#0004_08A3【故障级】正向硬限位触发锁存（复位沿解除）
    16#0004_08A4【故障级】负向硬限位触发锁存（复位沿解除）
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 常闭组态、正向开关断开 → bPosLimit 锁存、码 08A3、uPosTripCnt +1
    V2 复位沿 → 双侧锁存与计数清零
    V3 常开组态 bSwNC=FALSE、开关闭合 → 同 V1 判定
  修订记录 Revision  :
    2026-11-21  v1.0.0  R61 首版（批 3 · 序号 10）
  ==================================================================
*)
FUNCTION_BLOCK FB_DL_AxisLimitSwitchBank
VAR_INPUT
    bSwNC   : BOOL := TRUE;  // 开关极性组态：TRUE 常闭（断开判触发，安全侧默认）/ the switch polarity, true for the normally closed safe default
    bReset  : BOOL := FALSE; // 复位电平，上升沿清双侧锁存与计数 / the reset level clears both latches and counts
END_VAR
VAR_IN_OUT
    abPosSw : ARRAY[0..1] OF BOOL; // 正向侧限位开关电平（双开关组）[-]，只读 / the positive side switch levels, read only
    abNegSw : ARRAY[0..1] OF BOOL; // 负向侧限位开关电平（双开关组）[-]，只读 / the negative side switch levels, read only
END_VAR
VAR_OUTPUT
    bPosLimit   : BOOL := FALSE;            // 正向越限锁存指示 [-] / the positive limit latched indicator
    bNegLimit   : BOOL := FALSE;            // 负向越限锁存指示 [-] / the negative limit latched indicator
    uPosTripCnt : UDINT := 0;               // 正向越限计数 [次] / the positive trip count
    uNegTripCnt : UDINT := 0;               // 负向越限计数 [次] / the negative trip count
    bError      : BOOL := FALSE;            // 故障锁存位（双侧任一锁存即真）/ the fault bit latched by either side
    eErr        : UDINT := 16#0000_0000;    // 错误码，0 = 正常 / the error code, zero is ok
END_VAR
VAR
    _bInit     : BOOL := FALSE; // 首拍初始化标志（R310）/ the first scan flag
    _bPosLatch : BOOL := FALSE; // 正向锁存副本（仅复位沿清除）/ the positive latch copy
    _bNegLatch : BOOL := FALSE; // 负向锁存副本 / the negative latch copy
    _bPosTrig  : BOOL := FALSE; // 本拍正向触发判（极性归一后）[-] / the normalized positive trigger this scan
    _bNegTrig  : BOOL := FALSE; // 本拍负向触发判 / the normalized negative trigger this scan
    rtPos      : R_TRIG; // 正向触发沿实例，段 0 无条件刷新 / the positive trigger edge instance
    rtNeg      : R_TRIG; // 负向触发沿实例，段 0 无条件刷新 / the negative trigger edge instance
    rtReset    : R_TRIG; // 复位沿实例，段 0 无条件刷新 / the reset edge instance
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支，R7）/ segment 0, the unconditional refresh
_bPosTrig := abPosSw[0] XOR abPosSw[1]; // 双开关不一致判触发（双通道硬限位判据）/ the trigger by the two channel disagreement
IF NOT bSwNC THEN // 常开组态：闭合判触发（极性归一，边界三）/ the normally open polarity
    _bPosTrig := abPosSw[0] AND abPosSw[1]; // 双开关闭合判触发 / the trigger by the two channel agreement
END_IF
_bNegTrig := abNegSw[0] XOR abNegSw[1]; // 负向同判 / the negative side the same way
IF NOT bSwNC THEN // 常开组态 / the normally open polarity
    _bNegTrig := abNegSw[0] AND abNegSw[1]; // 双开关闭合判触发 / the trigger by the agreement
END_IF
rtPos(CLK := _bPosTrig); // 正向触发沿 / the positive trigger edge
rtNeg(CLK := _bNegTrig); // 负向触发沿 / the negative trigger edge
rtReset(CLK := bReset); // 复位沿 / the reset edge

// 段 1｜首拍初始化（R310）/ segment 1, the first scan init
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _bPosLatch := FALSE; // 正向锁存显式清零 / clear the positive latch explicitly
    _bNegLatch := FALSE; // 负向锁存显式清零 / clear the negative latch explicitly
END_IF

// 段 2｜触发沿锁存与计数（方向侧独立，R190，边界一）/ segment 2, the edge latching with the independent sides
IF rtPos.Q AND (NOT _bPosLatch) THEN // 正向触发沿且未锁存（计数每触发一次只进一）/ the positive edge not yet latched
    _bPosLatch := TRUE; // 锁存正向越限 / latch the positive trip
    uPosTripCnt := uPosTripCnt + 1; // 越限计数推进（无符号上溢由计数容量兜底声明）/ advance the trip count
END_IF
IF rtNeg.Q AND (NOT _bNegLatch) THEN // 负向触发沿且未锁存 / the negative edge not yet latched
    _bNegLatch := TRUE; // 锁存负向越限 / latch the negative trip
    uNegTripCnt := uNegTripCnt + 1; // 越限计数推进 / advance the trip count
END_IF

// 段 3｜复位沿解除（作用域：清双侧锁存 + 清双侧计数，边界二）/ segment 3, the reset edge release with the declared scope
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bPosLatch := FALSE; // 清正向锁存（解除路径：复位沿恒可达，R152 自证）/ clear the positive latch
    _bNegLatch := FALSE; // 清负向锁存 / clear the negative latch
    uPosTripCnt := 0; // 清正向计数 / clear the positive count
    uNegTripCnt := 0; // 清负向计数 / clear the negative count
END_IF

// 段 4｜统一出口（锁存同源映射，R191；故障码锁存回放，R187）/ segment 4, the unified outlet
bPosLimit := _bPosLatch; // 正向锁存出口 / the positive latch outlet
bNegLimit := _bNegLatch; // 负向锁存出口 / the negative latch outlet
bError := _bPosLatch OR _bNegLatch; // 故障位出口（双侧任一）/ the fault bit from either side
IF _bPosLatch AND _bNegLatch THEN // 双侧同锁存（先到先报前序沿码：取计数大者为成因）/ both latched, the larger count side is the first cause
    IF uPosTripCnt >= uNegTripCnt THEN // 正向先触发（计数已含本轮，等值取正向）/ the positive side first
        eErr := 16#0004_08A3; // 故障级：正向硬限位锁存回放 / fault grade, the positive trip replayed
    ELSE // 负向先触发 / the negative side first
        eErr := 16#0004_08A4; // 故障级：负向硬限位锁存回放 / fault grade, the negative trip replayed
    END_IF
ELSIF _bPosLatch THEN // 仅正向 / the positive only
    eErr := 16#0004_08A3; // 故障级：正向硬限位锁存回放 / fault grade, the positive trip replayed
ELSIF _bNegLatch THEN // 仅负向 / the negative only
    eErr := 16#0004_08A4; // 故障级：负向硬限位锁存回放 / fault grade, the negative trip replayed
ELSE // 无故障 / no fault
    eErr := 16#0000_0000; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
