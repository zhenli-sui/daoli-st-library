(*
  FB_DL_MultiClickDetect  —  按钮短按/长按/双击三形态判定 / Button short, long and double-click detection
  分类 Category : DL_Base
  版本 Version  : 1.0.0
  来源 Source   : t1-5-tcopen — 调试盘人机交互族零检索深化
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 对 bBtn 判定三种按压形态：短按（释放早于 tLong 且无双击窗内第二沿）、
                  长按（按压持续达 tLong）、双击（释放后 tDouble 窗内出现第二按压沿）；
                  2) bShortPulse / bDouble 单拍脉冲在判定拍发出；bLong 在达窗拍发出单拍脉冲；
                  3) 双击窗内第二沿判据使用当拍量（rtPrs.Q），无锁存量自指；
                  4) bReset 上升沿清组态故障锁存。
  边界 Boundary : ① 组态闸：tLong > tDouble > T#0S 必须成立，违例置故障级 03DE，三脉冲出口强制 FALSE；
                  ② 长按期间释放不产生短按脉冲（长按优先归因，防同拍双归因）；
                  ③ 状态机 ENUM+CASE 全覆盖 + ELSE 兜底落 03DF 故障锁存；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : 仅 Standard.library（TON / R_TRIG）
  码表 Error codes（段 0001，窗口 03DE~03DF / 04A1~04A2）:
    16#0001_03DE 故障级：组态非法（tLong <= tDouble 或任一窗 <= T#0S），锁存至 bReset
    16#0001_03DF 故障级：状态机落 ELSE 兜底（非法相位 ID），锁存至 bReset
    16#0001_04A1 信息级：短按事件（与 bShortPulse 同拍）
    16#0001_04A2 信息级：双击事件（与 bDouble 同拍）
  修订历史 Revision :
    2026-11-19  v1.0.0  R41 首版（批次 1 · 序号 2）
*)

TYPE E_DL_McdState :
(
    eIdle   := 0,    // 空闲：按钮未按压 / Idle, button released
    eHeld   := 10,   // 按压中：等释放或达长按窗 / Held, waiting release or long window
    eWait2  := 20,   // 双击等待：释放早于长按窗，等第二沿 / Wait second press inside the double window
    eFault  := 90    // 故障：组态非法或兜底锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_MultiClickDetect
VAR_INPUT
    bBtn         : BOOL := FALSE;     // 按钮输入，TRUE = 按压 [-] / Button input, TRUE = pressed
    tLong        : TIME := T#1000MS;  // 长按窗 [ms]，必须 > tDouble / Long-press window
    tDouble      : TIME := T#300MS;   // 双击窗 [ms]，必须 > T#0S 且 < tLong / Double-click window
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_OUTPUT
    bShortPulse  : BOOL;              // 短按单拍脉冲 [-] / Short-press one-scan pulse
    bLong        : BOOL;              // 长按单拍脉冲 [-] / Long-press one-scan pulse
    bDouble      : BOOL;              // 双击单拍脉冲 [-] / Double-click one-scan pulse
    eState       : E_DL_McdState;     // 状态出口，段尾单点映射 / State outlet
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonLongTo    : TON;               // 长按窗定时器（按压电平驱动），无条件刷新 / Long window timer
    tonDblTo     : TON;               // 双击窗定时器（等待相独占），无条件刷新 / Double window timer
    rtPrs        : R_TRIG;            // 按压沿实例，无条件刷新 / Press edge instance
    rtRel        : R_TRIG;            // 释放沿实例，无条件刷新 / Release edge instance
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _eState      : E_DL_McdState := E_DL_McdState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
    _bLongSent   : BOOL;              // 本按压已发长按脉冲标志（防重复）/ Long pulse sent flag
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
rtPrs(CLK := bBtn);                       // 按压沿（每拍必调）
rtRel(CLK := NOT bBtn);                   // 释放沿（每拍必调）
rtReset(CLK := bReset);                   // 复位沿（每拍必调）
tonLongTo(IN := bBtn, PT := tLong);       // 长按窗（电平驱动，每拍必调）
tonDblTo(IN := (_eState = E_DL_McdState.eWait2), PT := tDouble);  // 双击窗（等待相独占，每拍必调）

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault 不入清单；完成脉冲两段式出口） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
bShortPulse := FALSE;               // 短按脉冲缺省 FALSE
bLong := FALSE;                     // 长按脉冲缺省 FALSE
bDouble := FALSE;                   // 双击脉冲缺省 FALSE
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿与组态域闸（全当拍量判据） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF
IF (TIME_TO_DINT(tLong) <= TIME_TO_DINT(tDouble)) OR (TIME_TO_DINT(tDouble) <= 0) THEN
    _uFault := 16#0001_03DE;        // 故障级：组态非法
    _bFault := TRUE;
    _eState := E_DL_McdState.eIdle; // 故障期间回空闲
END_IF

(* —— 段 3：相位机（只判形态与发标志；脉冲在段 5 统一出口映射） —— *)
CASE _eState OF

E_DL_McdState.eIdle:
    IF rtPrs.Q AND (NOT _bFault) THEN
        _bLongSent := FALSE;            // 本按压长按脉冲未发
        _eState := E_DL_McdState.eHeld; // 进按压相
    END_IF

E_DL_McdState.eHeld:
    IF _bFault THEN
        _eState := E_DL_McdState.eIdle; // 故障相回空闲（脉冲出口已被强制 FALSE）
    ELSIF tonLongTo.Q AND (NOT _bLongSent) THEN
        bLong := TRUE;                  // 长按脉冲（本拍置位，段 5 出口同拍映射）
        _bLongSent := TRUE;             // 单发标志
    ELSIF rtRel.Q THEN
        IF (NOT _bLongSent) AND (TIME_TO_DINT(tDouble) > 0) THEN
            _eState := E_DL_McdState.eWait2;    // 早于长按窗释放：进双击等待相
        ELSE
            _eState := E_DL_McdState.eIdle;     // 长按后释放或组态异常：回空闲
        END_IF
    END_IF

E_DL_McdState.eWait2:
    IF _bFault THEN
        _eState := E_DL_McdState.eIdle;     // 故障相回空闲
    ELSIF rtPrs.Q THEN
        bDouble := TRUE;                    // 双击命中（窗内第二沿，当拍量判据）
        _uInfo := 16#0001_04A2;             // 信息级：双击事件
        _eState := E_DL_McdState.eHeld;     // 第二次按压继续按普通按压相处理
        _bLongSent := FALSE;                // 新按压重新计时长按
    ELSIF tonDblTo.Q THEN
        bShortPulse := TRUE;                // 双击窗超时：第一次按压判短按
        _uInfo := 16#0001_04A1;             // 信息级：短按事件
        _eState := E_DL_McdState.eIdle;     // 回空闲
    END_IF

E_DL_McdState.eFault:
    IF NOT _bFault THEN
        _eState := E_DL_McdState.eIdle;     // 故障解除（复位沿）回空闲，迁出边可达
    END_IF

ELSE
    _uFault := 16#0001_03DF;            // 故障级：非法相位 ID 兜底
    _bFault := TRUE;
    _eState := E_DL_McdState.eFault;    // 强制回故障相

END_CASE

(* —— 段 4：故障相脉冲出口强制 FALSE（安全侧，防故障期误发脉冲） —— *)
IF _bFault THEN
    bShortPulse := FALSE;           // 安全侧清脉冲
    bLong := FALSE;                 // 安全侧清脉冲
    bDouble := FALSE;               // 安全侧清脉冲
END_IF

(* —— 段 5：出口单点映射（锁存码回放，禁同拍抹除） —— *)
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
eState := _eState;                  // 状态出口单点映射

END_FUNCTION_BLOCK
