(*
  FB_DL_TankLevelStrapping  —  储罐液位-容积分层标定与体积折算 / Tank level-volume strapping table conversion
  分类 Category : DL_Process
  码位 Code     : 16#06_0_BA
  段位说明      : R38 W7 预留 B6~BF 本轮正式启用，B9 格由 RadiatorZoneValve 启用，本件启用 BA 格
  版本 Version  : 1.0.0
  来源 Source   : 自研线（t2-1-lgf-math 次源）— 容积表标定核对待挖项
  溯源 Origin   : clean-room 实现，分层容积表折算为计量公开语义，未复制任何源码行
                  （与 FC_DL_MultiPointLinear 分工：那件是通用折算原子，本件带标定核对与罐型组态语义）
  功能 Function : 1) 分层容积表折算：液位 [m] → 体积 [m³]，走 FC_DL_MultiPointLinear 分段线性原子；
                  2) 越表插值拒绝：实测液位越出表界（外推被拒）时体积出口置 0 并置信息级码；
                  3) 标定核对：核对点（参考液位/参考体积）入容差窗（FB_DL_ToleranceWindow）判定，
                  核对失败锁故障（防表错继续计量），bReset 解除；
                  4) 液位百分比出口：FC_DL_LinearScale 表界归一。
  边界 Boundary : ① 表合法性（折点 >= 2 且液位严格递增）由折算原子校验，本件透传其错误码并锁存；
                  ② fTankMaxVolM3 为组态罐容上限：折算结果越上限钳制 + 信息级码（防表末段误配）；
                  ③ 组态域闸覆盖全部参与换算引脚（R151）；核对容差/参考体积域非法判组态错；
                  ④ 无状态机相（折算型 FB）：核对失败经锁存位承载，无跨相 TON 复用问题；
                  ⑤ R228-B 达标声明：eFault 迁出 = rtReset.Q（输入引脚，恒可达），逐字写于此；
                  ⑥ 折算原子为 LREAL 口径：入参/返回显式 REAL_TO_LREAL / LREAL_TO_REAL 转换。
  依赖 Depends  : FC_DL_MultiPointLinear / FC_DL_LinearScale（函数调用，引脚按 registry 实名）；
                  FB_DL_ToleranceWindow（实例化，引脚按 registry 实名）
  码表 Error codes（本件格 06_0_BA，子码步进 +0x100）:
    16#0006_01BA 信息级：标定核对通过（bCalCheck 拍）
    16#0006_02BA 故障级：标定核对失败（核对点越容差窗），锁存至复位
    16#0006_03BA 故障级：容积表非法（折点不足或非严格递增），锁存至复位
    16#0006_04BA 信息级：实测液位越表界，体积拒绝输出（置 0）
    16#0006_05BA 故障级：组态非法（点数/参考量/罐容上限域非法），锁存至复位
    16#0006_06BA 信息级：折算体积越组态罐容上限，已钳制
    16#0006_07BA 故障级：状态机落 ELSE 兜底（非法状态 ID）

  修订历史 Revision :
    2026-11-19  v1.0.0  R39 首版（批次 4 · 序号 18）
*)

TYPE E_DL_StrapState :
(
    eReady      := 0,    // 就绪：表合法且液位在表界内 / Ready, table valid and level in range
    eTableBad   := 10,   // 表非法：折算原子校验失败 / Table invalid, interpolator check failed
    eOutOfRange := 20,   // 越表：实测液位越表界 / Out of table range
    eCalFail    := 30,   // 核对失败：标定核对越容差 / Calibration check failed
    eFault      := 90    // 组态/核对故障锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_TankLevelStrapping
VAR_INPUT
    fLevelMeasM   : REAL := 0.0;         // 实测液位 [m] / Measured liquid level
    nTablePts     : INT := 0;            // 容积表有效折点数 [个]，2..16 / Strapping table point count
    fTankMaxVolM3 : REAL := 1000.0;      // 组态罐容上限 [m³]，域 > 0 / Tank volume configuration ceiling
    fRefLevelM    : REAL := 0.0;         // 核对点参考液位 [m] / Reference level for calibration check
    fRefVolM3     : REAL := 0.0;         // 核对点参考体积 [m³]，域 > 0 / Reference volume for check
    fRefTolPct    : REAL := 1.0;         // 核对容差 [%]（相对参考体积），域 (0, 100] / Check tolerance in percent
    bCalCheck     : BOOL := FALSE;       // 标定核对指令（上升沿）/ Calibration check command
    bReset        : BOOL := FALSE;       // 故障复位，上升沿生效 / Fault reset, rising edge
END_VAR
VAR_OUTPUT
    fVolumeM3    : REAL;                 // 折算体积 [m³]（越表/故障置 0）/ Converted volume output
    fLevelPct    : REAL;                 // 液位百分比 [%]（表界归一）/ Level percent of table span
    bOutOfRange  : BOOL;                 // 越表拒绝标志（瞬时，每拍重算）[-] / Out-of-range rejection flag
    bTableValid  : BOOL;                 // 容积表合法性 [-] / Table validity flag
    bCalOk       : BOOL;                 // 最近一次核对通过锁存 [-] / Last check passed latch
    eState       : E_DL_StrapState;      // 状态出口，段尾单点映射 / State outlet
    bError       : BOOL;                 // 故障锁存，仅故障级码置位，bReset 清除 [-] / Fault latch
    uErrorId     : UDINT;                // 事件码，0 = 无事件（故障级锁存回放）/ Event code
END_VAR
VAR_IN_OUT
    afLevelM : ARRAY[0..15] OF LREAL;    // 容积表液位折点 [m]，须严格递增 / Table level breakpoints, strictly increasing
    afVolM3  : ARRAY[0..15] OF LREAL;    // 容积表体积折点 [m³] / Table volume breakpoints
END_VAR
VAR
    fbTol      : FB_DL_ToleranceWindow;  // 核对容差窗实例（主体首部无条件刷新）/ Check tolerance window instance
    rtCalCheck : R_TRIG;                 // 核对指令上升沿 / Check command rising edge
    rtReset    : R_TRIG;                 // 复位上升沿 / Reset rising edge
    _lrVolCalc : LREAL;                  // 主折算体积中间量 [m³]（LREAL 口径）/ Main volume working value
    _lrVolAtRef: LREAL;                  // 核对点折算体积 [m³] / Volume at reference level
    _nSegMain  : INT;                    // 主折算命中段号 / Main conversion segment index
    _bExtrap   : BOOL;                   // 主折算外推标志 / Main conversion extrapolation flag
    _bClamp    : BOOL;                   // 主折算钳位标志 / Main conversion clamp flag
    _uMplErr   : UDINT;                  // 折算原子错误码透传 / Interpolator error passthrough
    _nSegRef   : INT;                    // 核对折算命中段号 / Check conversion segment index
    _bExtRef   : BOOL;                   // 核对折算外推标志 / Check conversion extrapolation flag
    _bClpRef   : BOOL;                   // 核对折算钳位标志 / Check conversion clamp flag
    _uErrRef   : UDINT;                  // 核对折算错误码透传 / Check conversion error passthrough
    _fScalePct : REAL;                   // 百分比中间量 [%] / Percent working value
    _bScaleOk  : BOOL;                   // 百分比换算有效 / Percent scaling valid
    _bTolSt    : BOOL;                   // 容差窗状态回传保持变量（有状态纪律）/ Tolerance window state hold member
    _bCalRun   : BOOL;                   // 本拍执行核对标志 / Check executed this cycle
    _eStateInt : E_DL_StrapState := E_DL_StrapState.eReady;   // 内部状态（CASE 唯一写入目标）/ Internal state
    _uInfo     : UDINT;                  // 信息码，每拍重算 / Info code
    _uFault    : UDINT;                  // 故障码锁存寄存 / Latched fault code register
    _bFault    : BOOL;                   // 故障锁存位 / Latched fault bit
    _bCfgBad   : BOOL;                   // 组态非法聚合 / Configuration invalid aggregate
END_VAR
VAR CONSTANT
    DL_TLS_INF_CAP  : REAL := 1.0E15;    // 非有限值筛查幅值上限 / Non-finite screening cap
    DL_TLS_PTS_MAX  : INT   := 16;       // 折点数上限（= 数组维度）/ Point count upper bound
    DL_TLS_VOL_EPS  : LREAL := 1.0E-9;   // 容差半宽下限兜底 [m³] / Tolerance half-width floor
END_VAR

(* —— 段 0：边沿实例无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
(* 容差窗 fbTol 在段 8 调用（数据流：核对折算先于判定），仍为顶层无条件调用 *)
rtCalCheck(CLK := bCalCheck);                            // 核对沿刷新，每拍必调
rtReset(CLK := bReset);                                  // 复位沿刷新，每拍必调

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault/bCalOk 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
_bCfgBad := FALSE;                  // 组态非法预清零
bOutOfRange := FALSE;               // 越表标志缺省 FALSE（段 4 单点置位）
uErrorId := 16#0000_0000;           // 事件码缺省无事件

(* —— 段 2：组态域闸（覆盖全部参与判据换算的引脚，R151） —— *)
IF (nTablePts < 2) OR (nTablePts > DL_TLS_PTS_MAX) THEN
    _bCfgBad := TRUE;               // 折点数域非法
END_IF
IF (fTankMaxVolM3 <= 0.0) OR (ABS(fTankMaxVolM3) > DL_TLS_INF_CAP)
   OR (fRefVolM3 <= 0.0) OR (ABS(fRefVolM3) > DL_TLS_INF_CAP)
   OR (fRefTolPct <= 0.0) OR (fRefTolPct > 100.0)
   OR (fLevelMeasM <> fLevelMeasM) OR (ABS(fLevelMeasM) > DL_TLS_INF_CAP) OR ((fLevelMeasM - fLevelMeasM) <> 0.0) THEN
    _bCfgBad := TRUE;               // 罐容/参考量/容差/液位域非法
END_IF

(* —— 段 3：故障锁存与迁出沿（R228-B：rtReset.Q 恒可达） —— *)
IF _bCfgBad AND (NOT _bFault) THEN
    _uFault := 16#0006_05BA;        // 故障级：组态非法（仅首次进入时写入）
    _bFault := TRUE;
END_IF
IF rtReset.Q AND (NOT _bCfgBad) THEN
    _bFault := FALSE;               // 清故障锁存位（组态恢复合法为前提）
    _uFault := 16#0000_0000;
    bCalOk := FALSE;                // 核对通过锁存随复位清除
END_IF

(* —— 段 4：主折算（FC_DL_MultiPointLinear 原子；bClamp = FALSE，越表由外推标志承载拒绝语义） —— *)
_lrVolCalc := FC_DL_MultiPointLinear(afX := afLevelM,        // 液位折点表
                                     afY := afVolM3,         // 体积折点表
                                     fIn := REAL_TO_LREAL(fLevelMeasM),   // 实测液位（显式升型）
                                     nCount := nTablePts,    // 有效折点数
                                     bClamp := FALSE,        // 不钳位：越表拒绝语义自管
                                     nSegment => _nSegMain,  // 命中段号
                                     bExtrapolated => _bExtrap,   // 外推标志
                                     bClamped => _bClamp,    // 钳位标志
                                     uErrorId => _uMplErr);  // 错误码透传
bTableValid := (_uMplErr = 0) AND (_nSegMain >= 0);          // 表合法 = 无错误码且命中段有效

(* —— 段 5：液位百分比出口（FC_DL_LinearScale 原子，表界归一；表非法时出口 0） —— *)
IF bTableValid THEN
    _fScalePct := FC_DL_LinearScale(fIn := fLevelMeasM,      // 实测液位
                                    fInMin := LREAL_TO_REAL(afLevelM[0]),       // 表界下端
                                    fInMax := LREAL_TO_REAL(afLevelM[nTablePts - 1]),   // 表界上端（下标已由点数闸钳位）
                                    fOutMin := 0.0,          // 归一 0%
                                    fOutMax := 100.0,        // 归一 100%
                                    bClamp := TRUE,          // 表界内归一，越界钳位
                                    bValid => _bScaleOk,     // 换算有效标志
                                    uErrorId => _uInfo);     // 换算错误码（瞬时，并入信息码）
ELSE
    _fScalePct := 0.0;               // 表非法：百分比出口置 0（防御口径）
END_IF
fLevelPct := _fScalePct;            // 百分比出口镜像

(* —— 段 6：状态分类 CASE（计算型分类，含 ELSE 兜底） —— *)
CASE _eStateInt OF

E_DL_StrapState.eReady:
    IF _bFault THEN
        _eStateInt := E_DL_StrapState.eFault;           // 故障锁存：进故障态
    ELSIF NOT bTableValid THEN
        _eStateInt := E_DL_StrapState.eTableBad;        // 表非法：进表错态
    ELSIF _bExtrap THEN
        _eStateInt := E_DL_StrapState.eOutOfRange;      // 越表：进拒绝态
    END_IF

E_DL_StrapState.eTableBad:
    IF bTableValid THEN
        _eStateInt := E_DL_StrapState.eReady;           // 表恢复合法：回就绪态
    END_IF

E_DL_StrapState.eOutOfRange:
    IF (NOT _bExtrap) AND bTableValid THEN
        _eStateInt := E_DL_StrapState.eReady;           // 回表界内：回就绪态
    END_IF

E_DL_StrapState.eCalFail:
    IF (NOT _bFault) AND bTableValid THEN
        _eStateInt := E_DL_StrapState.eReady;           // 核对故障解除：回就绪态
    END_IF

E_DL_StrapState.eFault:
    IF NOT _bFault THEN
        _eStateInt := E_DL_StrapState.eReady;           // 故障解除：回就绪态
    END_IF

ELSE
    _uFault := 16#0006_07BA;        // 故障级：非法状态 ID 兜底
    _bFault := TRUE;
    _eStateInt := E_DL_StrapState.eFault;   // 强制回故障态

END_CASE

(* —— 段 7：体积出口合成（越表拒绝 / 表非法 / 故障三路置 0；越罐容上限钳制） —— *)
IF _bFault OR (NOT bTableValid) OR _bExtrap THEN
    IF _bExtrap AND (NOT _bFault) AND bTableValid THEN
        bOutOfRange := TRUE;        // 越表拒绝标志（瞬时）
        _uInfo := 16#0006_04BA;     // 信息级：越表拒绝输出
    END_IF
    IF (NOT bTableValid) AND (NOT _bFault) THEN
        _uFault := 16#0006_03BA;    // 故障级：容积表非法（锁存）
        _bFault := TRUE;
    END_IF
    fVolumeM3 := 0.0;               // 拒绝/非法/故障：体积出口置 0
ELSE
    IF _lrVolCalc > REAL_TO_LREAL(fTankMaxVolM3) THEN
        fVolumeM3 := fTankMaxVolM3; // 越罐容上限钳制
        _uInfo := 16#0006_06BA;     // 信息级：已钳制
    ELSE
        fVolumeM3 := LREAL_TO_REAL(_lrVolCalc);     // 正常折算出口（显式降型）
    END_IF
END_IF

(* —— 段 8：标定核对（沿触发核对折算 → fbTol 顶层判定 → 自消费判定标志） —— *)
IF rtCalCheck.Q AND (NOT _bFault) AND bTableValid THEN
    _lrVolAtRef := FC_DL_MultiPointLinear(afX := afLevelM,      // 液位折点表
                                          afY := afVolM3,       // 体积折点表
                                          fIn := REAL_TO_LREAL(fRefLevelM),     // 核对点参考液位
                                          nCount := nTablePts,  // 有效折点数
                                          bClamp := FALSE,      // 不钳位
                                          nSegment => _nSegRef, // 命中段号
                                          bExtrapolated => _bExtRef,    // 外推标志
                                          bClamped => _bClpRef, // 钳位标志
                                          uErrorId => _uErrRef);    // 错误码透传
    IF (_uErrRef = 0) AND (_nSegRef >= 0) AND (NOT _bExtRef) THEN
        _bCalRun := TRUE;           // 核对折算有效：判定标志置位（本段末尾自消费）
        _eStateInt := E_DL_StrapState.eCalFail;     // 判定期间暂入核对态（按结果迁出）
    ELSE
        _uFault := 16#0006_02BA;    // 故障级：核对点越表（核对失败口径之一）
        _bFault := TRUE;
    END_IF
END_IF
fbTol(bEnable := _bCalRun,                               // 仅核对拍判定
      fTarget := REAL_TO_LREAL(fRefVolM3),               // 核对目标体积
      fActual := _lrVolAtRef,                            // 核对点折算体积
      fTolerance := MAX(REAL_TO_LREAL(fRefVolM3) * REAL_TO_LREAL(fRefTolPct) / 100.0, DL_TLS_VOL_EPS),   // 容差半宽（相对口径，下限防零窗死判）
      fHysteresis := 0.0);                               // 无回差（单次判定口径）
IF _bCalRun THEN
    IF fbTol.bOk THEN
        bCalOk := TRUE;             // 核对通过锁存
        _uInfo := 16#0006_01BA;     // 信息级：核对通过
        _eStateInt := E_DL_StrapState.eReady;   // 回就绪态
    ELSE
        _uFault := 16#0006_02BA;    // 故障级：标定核对失败（锁存至复位）
        _bFault := TRUE;
    END_IF
    _bCalRun := FALSE;              // 判定标志自消费（单拍口径）
END_IF

(* —— 段 9：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _bFault THEN
    uErrorId := _uFault;            // 故障锁存码回放（不在故障态按当下输入重推）
    bError := TRUE;
    bOutOfRange := FALSE;           // 故障态越表标志强制 FALSE（口径归一）
ELSE
    uErrorId := _uInfo;             // 信息码
    bError := FALSE;
END_IF
eState := _eStateInt;               // 状态出口单点映射

END_FUNCTION_BLOCK
