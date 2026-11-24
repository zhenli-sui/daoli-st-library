(*
  FB_DL_BinderFeederSeq  —  绝缘件振动盘供料顺控（满料/缺料双光电 + 卡料窗） / Binder vibratory feeder sequence with full/empty photoeyes and jam window
  分类 Category : DL_Process
  版本 Version  : 1.0.0
  来源 Source   : t2-2-lbp — 供料/上料工艺族深化
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 三相顺控：eIdle（待机）→ eFeed（供料，bVibOn 输出驱动振动盘，
                  bFullPE 满料到达回 eIdle）→ eFault；使能撤销沿随时回 eIdle；
                  2) 卡料诊断：供料相中缺料（bEmptyPE）持续 tJamWin 未见满料
                  → 0378 卡料锁存（窗为电平式防抖窗，满料到达自动断 IN 复位）；
                  3) 双光电矛盾诊断：bFullPE 与 bEmptyPE 同 TRUE 持续 tContraWin
                  → 0377 矛盾锁存（传感器组态/遮挡异常归因唯一）；
                  4) 信息级三码：供料启动 / 卡料窗激活 / 满料到达（单拍沿）；
                  5) 解除式全当拍量（R240 落地），逐 BOOL 标注见段 4。
  边界 Boundary : ① 组态闸：tJamWin <= 0 或 tContraWin <= 0 → 0376 锁存
                  （组态与 ELSE 兜底归并声明于码表）；
                  ② 满料优先安全侧：矛盾检出期 bVibOn 强制 FALSE（停止振动）；
                  ③ 超时窗均为电平驱动，窗内判据消失自动复位（R176 周期语义合规）；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Process 段 0005，窗口 0376~0378 / 049E~04A0）:
    16#0005_0376 故障级：组态非法（任一窗 <= 0）或相位落 ELSE 兜底（归并声明），锁存至 bReset
    16#0005_0377 故障级：双光电矛盾锁存（满料与缺料同 TRUE 持续 tContraWin），锁存至 bReset
    16#0005_0378 故障级：卡料锁存（供料中缺料持续 tJamWin），锁存至 bReset
    16#0005_049E 信息级：供料启动沿（进 eFeed）
    16#0005_049F 信息级：卡料窗激活沿（供料相缺料进入）
    16#0005_04A0 信息级：满料到达沿（eFeed → eIdle）
  修订历史 Revision :
    2026-11-19  v1.0.0  R42 首版（批次 1 · 序号 3）
*)

TYPE E_DL_BfsState :
(
    eIdle   := 0,    // 待机：满料或未使能 / Idle, full or not enabled
    eFeed   := 10,   // 供料：振动输出驱动 / Feed, vibration output driving
    eFault  := 90    // 故障：卡料或矛盾锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_BinderFeederSeq
VAR_INPUT
    bFeedEn      : BOOL := FALSE;     // 供料使能（电平）[-] / Feed enable, level
    bFullPE      : BOOL := FALSE;     // 满料光电，TRUE = 料满遮挡 [-] / Full photoeye, TRUE = blocked
    bEmptyPE     : BOOL := FALSE;     // 缺料光电，TRUE = 料空遮挡 [-] / Empty photoeye, TRUE = blocked
    tJamWin      : TIME := T#10S;     // 卡料判定窗 [ms]，域 > 0 / Jam detect window
    tContraWin   : TIME := T#500MS;   // 双光电矛盾确认窗 [ms]，域 > 0 / Contradiction confirm window
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_OUTPUT
    eState       : E_DL_BfsState;     // 状态出口，段尾单点映射 / State outlet
    bVibOn       : BOOL;              // 振动盘输出驱动（供料相电平）[-] / Vibrator output drive
    bJamWarn     : BOOL;              // 卡料窗计时中镜像（未到时）[-] / Jam window arming mirror
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonJam       : TON;               // 卡料判定窗（电平式），无条件刷新 / Jam detect timer
    tonContra    : TON;               // 双光电矛盾确认窗（电平式），无条件刷新 / Contradiction timer
    rtEn         : R_TRIG;            // 使能沿实例，无条件刷新 / Enable edge instance
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _eState      : E_DL_BfsState := E_DL_BfsState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _bJamInfoSent: BOOL;              // 卡料窗信息沿单发标志（eFeed 相内保持量）/ Jam-info one-shot sent flag
    _bContra     : BOOL;              // 双光电矛盾当拍量 [-] / Contradiction current-scan flag
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_bContra := bFullPE AND bEmptyPE;                                    // 双光电矛盾（当拍量）
rtEn(CLK := bFeedEn);                                                // 使能沿（每拍必调）
rtReset(CLK := bReset);                                              // 复位沿（每拍必调）
tonJam(IN := (_eState = E_DL_BfsState.eFeed) AND bFeedEn AND bEmptyPE, PT := tJamWin);
                                                // 卡料窗（供料相缺料电平驱动，满料到达自动断 IN）
tonContra(IN := _bContra, PT := tContraWin);
                                                // 矛盾确认窗（矛盾电平驱动，矛盾消失自动断 IN）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
bVibOn := FALSE;                    // 振动输出缺省 FALSE（安全侧）
bJamWarn := FALSE;                  // 卡料窗镜像缺省 FALSE
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（当拍量判据） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF
IF (TIME_TO_DINT(tJamWin) <= 0) OR (TIME_TO_DINT(tContraWin) <= 0) THEN
    _uFault := 16#0005_0376;        // 故障级：组态非法
    _bFault := TRUE;                // 故障标志与码位配对（R45）
END_IF

(* —— 段 3：矛盾与卡料锁存（判据当拍量/电平式窗） —— *)
IF (NOT _bFault) AND tonContra.Q THEN
    _uFault := 16#0005_0377;        // 故障级：双光电矛盾锁存
    _bFault := TRUE;
END_IF
IF (NOT _bFault) AND tonJam.Q THEN
    _uFault := 16#0005_0378;        // 故障级：卡料锁存
    _bFault := TRUE;
END_IF

(* —— 段 4：故障解除式（R240 落地，逐 BOOL 标注）：
     rtReset.Q = 当拍量；bFeedEn = 当拍量；_bContra = 当拍量；NOT bEmptyPE = 当拍量。
     均不含锁存量（_bFault/_uFault），解除边真实可达：
     矛盾锁存沿「矛盾消失 + 使能撤销 + 复位沿」到达；卡料锁存沿「缺料消失 + 使能撤销 + 复位沿」到达。 —— *)
IF rtReset.Q AND (NOT bFeedEn) AND (NOT _bContra) AND (NOT bEmptyPE) THEN
    _bFault := FALSE;               // 清故障锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，仅本当拍量解除沿可清）
    IF _eState = E_DL_BfsState.eFault THEN
        _eState := E_DL_BfsState.eIdle;     // 故障相迁出：回待机
    END_IF
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_BfsState.eIdle:
    IF rtEn.Q AND (NOT _bFault) AND (NOT _bContra) THEN
        _uInfo := 16#0005_049E;             // 信息级：供料启动沿
        _eState := E_DL_BfsState.eFeed;     // 进供料相
    END_IF

E_DL_BfsState.eFeed:
    bVibOn := bFeedEn AND (NOT _bContra) AND (NOT _bFault);
                                        // 振动输出（矛盾/故障期强制 FALSE，安全侧）
    bJamWarn := bFeedEn AND bEmptyPE AND (NOT tonJam.Q);
                                        // 卡料窗计时中镜像（电平）
    IF bEmptyPE AND (NOT _bJamInfoSent) THEN
        _uInfo := 16#0005_049F;         // 信息级：卡料窗激活沿（单发）
        _bJamInfoSent := TRUE;          // 沿单发标志（eFeed 相内保持）
    END_IF
    IF bFullPE THEN
        _uInfo := 16#0005_04A0;         // 信息级：满料到达沿
        _bJamInfoSent := FALSE;         // 回待机重置单发标志
        _eState := E_DL_BfsState.eIdle; // 满料：回待机相
    ELSIF NOT bFeedEn THEN
        _bJamInfoSent := FALSE;         // 使能撤销：重置单发标志
        _eState := E_DL_BfsState.eIdle; // 回待机相
    END_IF
    (* 卡料/矛盾迁出在段 3 承载 *)

E_DL_BfsState.eFault:
    ;                                   // 故障相：等解除沿（段 4 承载迁出）

ELSE
    _uFault := 16#0005_0376;            // 故障级：非法相位兜底（归并组态码，码表声明）
    _bFault := TRUE;
    _eState := E_DL_BfsState.eFault;    // 强制回故障相

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    bVibOn := FALSE;                // 故障相振动输出强制 FALSE（安全侧）
    bJamWarn := FALSE;              // 故障相卡料镜像强制 FALSE（安全侧）
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
eState := _eState;                  // 状态出口单点映射

END_FUNCTION_BLOCK
