(*
  FB_DL_CaseSealTapeMonitor  —  封箱胶带缺料/断带监视 / Case sealing tape run-out and break monitor
  分类 Category : DL_Device
  码位 Code     : 16#03_2_0A
  版本 Version  : 1.0.0
  溯源 Source   : ISA-18.2 报警管理语义借鉴 · clean-room 实现，仅借分类/参数域/命名，未复制源码
  功能 Function : 1) 张力 + 光电双判据封箱胶带状态监视（复用 FB_DL_SignalDebounce 去抖）；
                  2) 节拍使能时连续 N 拍「无张力 + 光电同态」才判断带（防单拍尖峰）；
                  3) 缺料与断带独立码值（FB33-3 归因唯一），解除需补料确认 + 复位沿。
  边界 Boundary : ① 节拍使能时连续 N 拍无张力 + 光电同态才判断带（防单拍尖峰）；
                  ② 张力传感器无效冻结判定并置码；
                  ③ 缺料（低张力 + 光电无带）与断带（运动中张力突失）独立码值；
                  ④ 报警解除需补料确认 + 复位沿（双条件可达）；
                  ⑤ 输出三行同向：缺料 → 断带 → 去抖状态。
  依赖 Depends  : FB_DL_SignalDebounce × 2（张力低 / 光电无带去抖，每拍无条件调用）

  码表 Error codes（本件子码步进 16#10，避让邻件码位）:
    16#0002_030A 故障级：组态非法（确认拍数 < 1 / 去抖时长 < 0）
    16#0002_031A 故障级：断带（运动中张力突失 + 光电同态确认，锁存需补料 + 复位沿）
    16#0002_032A 信息级：缺料（低张力 + 光电无带，提示级）/ 张力无效判定冻结（不置 bError）
*)

TYPE E_DL_CstPhase :
(
    eIdle  := 0,  // 空闲 / Idle
    eWatch := 10, // 胶带状态监视 / Tape watching
    eBreak := 20, // 断带锁存 / Tape break latched
    eFault := 90  // 组态故障锁定 / Configuration fault locked
);
END_TYPE

FUNCTION_BLOCK FB_DL_CaseSealTapeMonitor
VAR_INPUT
    bEnable       : BOOL;                           // 总使能，FALSE 回空闲 / Master enable
    bCycleEn      : BOOL;                           // 封箱节拍使能（运动中判定窗口）/ Sealing cycle enable
    bReset        : BOOL;                           // 复位，上升沿清组态故障 / Reset, clears fault
    fTensionN     : REAL;                           // 胶带张力 [N] / Tape tension [N]
    bPhotoSensor  : BOOL;                           // 光电传感（TRUE = 有带）/ Photo sensor, TRUE = tape present
    fTensionLoN   : REAL := 2.0;                    // 张力下限 [N]（低于判无张力）/ Tension low limit [N]
    uBreakConfirm : UINT := 5;                      // 断带确认拍数 [拍] / Break confirm scans
    tDebounce     : TIME := T#100MS;                // 信号去抖时长 [ms] / Signal debounce time
    bTapeRefeed   : BOOL;                           // 补料确认（解除条件之一）/ Tape refeed confirmed
    fEps          : REAL := 1.0E-6;                 // 浮点判零容差 [1] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    bTapeMissing  : BOOL;                           // 缺料标志（提示级）/ Tape missing flag, info level
    bTapeBreak    : BOOL;                           // 断带标志（锁存）/ Tape break flag, latched
    bDebouncing   : BOOL;                           // 去抖进行中标志 / Debouncing flag
    bError        : BOOL;                           // 故障标志，与故障级码配对 / Fault flag
    uErrorId      : UDINT;                          // 事件码，0 = 无事件 / Event code
    eStateOut     : E_DL_CstPhase;                  // 状态机当前态，段尾单点映射 / Phase mapped at tail
END_VAR
VAR
    _eState       : E_DL_CstPhase := E_DL_CstPhase.eIdle;  // 内部状态 / Internal state
    fbDebTension  : FB_DL_SignalDebounce;           // 张力低去抖实例（无条件调用）/ Tension-low debounce
    fbDebPhoto    : FB_DL_SignalDebounce;           // 光电无带去抖实例（无条件调用）/ Photo-no-tape debounce
    rtrReset      : R_TRIG;                         // 复位沿 / Reset edge
    bCfgOk        : BOOL;                           // 组态合法标志 / Configuration valid
    bTensionOk    : BOOL;                           // 张力本拍有效 / Tension valid this scan
    bNoTension    : BOOL;                           // 无张力（去抖后）/ No tension, debounced
    bNoPhoto      : BOOL;                           // 光电无带（去抖后）/ No tape by photo, debounced
    bBreakCond    : BOOL;                           // 断带条件（无张力 + 光电同态）/ Break condition
    uBreakCnt     : UINT;                           // 断带确认计数 [拍] / Break confirm counter
    uFault        : UDINT;                          // 锁存故障码 / Latched fault code
    uInfo         : UDINT;                          // 信息级码 / Information code
END_VAR

(* === 段 0 · 实例刷新 === *)
rtrReset(CLK := bReset);                          // 每拍刷新复位沿

(* === 段 1 · 组态闸 === *)
bCfgOk := (uBreakConfirm >= UINT#1)               // 确认拍数下限
          AND (TIME_TO_REAL(tDebounce) >= 0.0)    // 去抖时长非负
          AND (fTensionLoN >= 0.0)                // 张力下限非负域
          AND (fTensionLoN = fTensionLoN);        // NaN 自反
IF NOT bCfgOk THEN
    uFault := 16#0002_030A;                       // 故障级：组态非法
END_IF
IF rtrReset.Q AND bCfgOk THEN
    uFault := 16#0000;                            // 复位沿清组态锁存（解除路径可达）
END_IF
uInfo := 16#0000;                                 // 信息码每拍清零
bTensionOk := (fTensionN = fTensionN) AND (fTensionN >= 0.0) AND (fTensionN < 1.0E30);  // 张力 NaN 自反 + 非负域

(* === 段 2 · 去抖实例（无条件调用）与双判据合成 === *)
fbDebTension(bRawInput := bTensionOk AND (fTensionN < fTensionLoN),   // 原始判据：张力低于下限
             tRiseDelay := tDebounce,             // 上升去抖
             tFallDelay := tDebounce,             // 下降去抖
             bEnable := bEnable AND bCfgOk,       // 使能透传
             bReset := rtrReset.Q);               // 复位沿透传
fbDebPhoto(bRawInput := (NOT bPhotoSensor),       // 原始判据：光电无带
           tRiseDelay := tDebounce,               // 上升去抖
           tFallDelay := tDebounce,               // 下降去抖
           bEnable := bEnable AND bCfgOk,         // 使能透传
           bReset := rtrReset.Q);                 // 复位沿透传
bNoTension := fbDebTension.bStable;               // 无张力（去抖后）
bNoPhoto := fbDebPhoto.bStable;                   // 光电无带（去抖后）
bDebouncing := fbDebTension.bFiltering OR fbDebPhoto.bFiltering;   // 去抖进行中
bBreakCond := bCycleEn AND bTensionOk AND bNoTension AND bNoPhoto;  // 节拍使能 + 无张力 + 光电同态
bTapeMissing := (NOT bCycleEn) AND bTensionOk AND bNoTension AND bNoPhoto;   // 非节拍缺料（提示级）
IF NOT bTensionOk THEN
    uInfo := 16#0002_032A;                        // 信息级：张力无效判定冻结
    uBreakCnt := UINT#0;                          // 无效拍计数归零（禁污染确认）
END_IF

(* === 段 3 · 断带确认计数（连续 N 拍防单拍尖峰）=== *)
IF bBreakCond THEN
    uBreakCnt := uBreakCnt + UINT#1;              // 断带条件确认计数
    IF uBreakCnt >= uBreakConfirm THEN
        uFault := 16#0002_031A;                   // 故障级：断带锁存（需补料 + 复位沿）
    END_IF
ELSE
    uBreakCnt := UINT#0;                          // 条件消失计数归零
END_IF
bTapeBreak := (uFault = 16#0002_031A);            // 断带出口（锁存态映射）

(* === 段 4 · 主状态机（ENUM + CASE，含 ELSE 兜底）=== *)
CASE _eState OF
E_DL_CstPhase.eIdle :
    IF uFault <> 16#0000 THEN
        _eState := E_DL_CstPhase.eFault;          // 故障优先
    ELSIF bEnable AND bCfgOk THEN
        _eState := E_DL_CstPhase.eWatch;          // 进监视相
    END_IF

E_DL_CstPhase.eWatch :
    IF uFault <> 16#0000 THEN
        _eState := E_DL_CstPhase.eBreak;          // 断带锁存转断带相
    ELSIF (NOT bEnable) OR (NOT bCfgOk) THEN
        _eState := E_DL_CstPhase.eIdle;           // 失能回空闲
    END_IF

E_DL_CstPhase.eBreak :
    (* 解除条件：补料确认 + 复位沿（双条件齐备，路径可达） *)
    IF bTapeRefeed AND rtrReset.Q THEN
        uFault := 16#0000;                        // 复位沿清断带锁存
        uBreakCnt := UINT#0;                      // 确认计数复位
        _eState := E_DL_CstPhase.eWatch;          // 回监视相
    END_IF

E_DL_CstPhase.eFault :
    IF uFault = 16#0000 THEN
        _eState := E_DL_CstPhase.eIdle;           // 解锁回空闲
    END_IF

ELSE
    _eState := E_DL_CstPhase.eFault;              // 非法状态拦截
    uFault := 16#0002_030A;                       // 故障级：相 ID 越界复用组态码段
END_CASE

(* === 段 5 · 输出映射（缺料与断带归因唯一：独立码值独立出口）=== *)
IF NOT bTapeBreak THEN
    bTapeMissing := bTapeMissing AND bTensionOk AND bCfgOk;   // 非断带时缺料提示有效
END_IF
bError := (uFault <> 16#0000);                    // 故障标志仅由故障级码置位（R45 配对）
IF bError THEN
    uErrorId := uFault;                           // 故障级优先上报
ELSE
    uErrorId := uInfo;                            // 否则上报信息级码
END_IF
eStateOut := _eState;                             // 输出枚举段尾单点映射（N2 规则）
END_FUNCTION_BLOCK
