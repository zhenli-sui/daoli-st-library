(*
  FB_DL_FilterSwitchLevel  —  过滤器液位/料位联锁（fail-safe LOW + 再生切换闭锁） / Filter level interlock with fail-safe LOW and regeneration interlock
  分类 Category : DL_Device
  版本 Version  : 1.0.0
  来源 Source   : t2-2-lbp — 液位联锁族零检索深化
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 传感器原始信号归一口径与 FB_DL_LevelSwitchVib 对齐（不实例化，
                  防抖上游承载）：TRUE = 介质覆盖叉体（料位高于低位）；归一取反后
                  TRUE = 低料位，防抖 tGlitch 后出 bLowLevel；
                  2) fail-safe LOW 语义：bEnable = FALSE（传感器失效/退出）→ 强制判
                  低料位（安全侧请求切换，防干转）；
                  3) 再生切换闭锁：bRegenActive 期间 + 结束后 tBlockAfter 窗内，
                  bSwReq 强制 FALSE（TOF 承载闭锁窗，闭锁沿用当拍量）；
                  4) 双表冗余可选：bRedundEn 且双表不一致持续 tDisTo → 故障级 03FE
                  独立锁存，失效安全侧强制判低。
  边界 Boundary : ① 组态闸：tGlitch/tDisTo/tBlockAfter 任一 <= 0 → 03FF 锁存；
                  ② 闭锁窗 TOF 无条件周期刷新（R7）；切换闭锁判据全当拍量；
                  ③ Device 段 0003 故障带收口：03FE/03FF 两格（分段理由见 InverterPdiPoll ②）；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : 与 FB_DL_LevelSwitchVib 归一口径语义对齐（不实例化）；Standard.library（TON / TOF / R_TRIG）
  码表 Error codes（Device 段 0003，窗口 041F~0421 / 故障 03FE~03FF）:
    16#0003_03FE 故障级：双表冗余失决（不一致持续 tDisTo），锁存至 bReset
    16#0003_03FF 故障级：组态非法（任一窗口域非法），锁存至 bReset
    16#0003_041F 信息级：低料位切换请求沿（bSwReq 首次 TRUE）
    16#0003_0420 信息级：再生闭锁激活（bRegenActive 期间请求被闭锁）
    16#0003_0421 信息级：冗余判定恢复正常沿（失决解除）
  修订历史 Revision :
    2026-11-19  v1.0.0  R41 首版（批次 4 · 序号 2）
*)

FUNCTION_BLOCK FB_DL_FilterSwitchLevel
VAR_INPUT
    bLvlRaw1     : BOOL := FALSE;     // 主表原始信号，TRUE = 介质覆盖叉体 [-] / Primary raw switch, TRUE = covered
    bLvlRaw2     : BOOL := TRUE;      // 备表原始信号（冗余可选），默认与主表一致口径 [-] / Secondary raw switch
    bRedundEn    : BOOL := FALSE;     // 双表冗余使能 [-] / Redundancy enable
    bRegenActive : BOOL := FALSE;     // 再生进行中 [-] / Regeneration active
    tGlitch      : TIME := T#500MS;   // 低料位确认防抖 [ms]，域 > 0 / Low-level debounce
    tDisTo       : TIME := T#2S;      // 冗余失决窗 [ms]，域 > 0 / Redundancy disagreement window
    tBlockAfter  : TIME := T#5S;      // 再生结束后闭锁延时 [ms]，域 > 0 / Post-regen interlock delay
    bEnable      : BOOL := TRUE;      // 传感器处理使能，FALSE = 失效安全侧 [-] / Sensor enable, FALSE = fail-safe
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_OUTPUT
    bLowLevel    : BOOL;              // 归一低料位判定（fail-safe 口径）[-] / Normalized low-level verdict
    bSwReq       : BOOL;              // 再生切换请求（闭锁窗内强制 FALSE）[-] / Switch request, forced off in interlock
    bBlock       : BOOL;              // 闭锁窗激活标志 [-] / Interlock active flag
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonLowDeb    : TON;               // 低料位防抖定时器，无条件周期刷新 / Low-level debounce timer
    tonDisTo     : TON;               // 冗余失决定时器（专用超时命名），无条件刷新 / Disagreement timer
    tofBlock     : TOF;               // 再生闭锁窗（TOF 承载再生后延时），无条件刷新 / Post-regen interlock timer
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _bLowNorm    : BOOL;              // 归一低料位当拍量（取反口径）/ Normalized low-level flag
    _bDisagree   : BOOL;              // 双表不一致当拍量 [-] / Disagreement current-scan flag
    _bDisLat     : BOOL;              // 失决锁存位（锁存量）/ Disagreement latch bit
    _bCfgBad     : BOOL;              // 组态锁存位（锁存量）/ Config-fault latch bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
    _bSwReqPrev  : BOOL;              // 上拍请求镜像（请求沿判据）/ Previous request mirror
    _bBlockPrev  : BOOL;              // 上拍闭锁镜像（闭锁沿判据）/ Previous block mirror
    _bDisOkPrev  : BOOL;              // 上拍一致镜像（恢复沿判据）/ Previous agreement mirror
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_bLowNorm := NOT bLvlRaw1;                    // 归一取反：TRUE = 低料位（当拍量）
_bDisagree := bRedundEn AND (bLvlRaw1 <> bLvlRaw2);   // 双表不一致（当拍量）
rtReset(CLK := bReset);                       // 复位沿（每拍必调）
tonLowDeb(IN := _bLowNorm AND (NOT _bDisLat), PT := tGlitch);   // 低料位防抖（每拍必调）
tonDisTo(IN := _bDisagree, PT := tDisTo);     // 失决窗（每拍必调）
tofBlock(IN := bRegenActive, PT := tBlockAfter);  // 闭锁窗（再生期间 + 再生后延时，每拍必调）

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bDisLat/_bCfgBad 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（当拍量判据） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bDisLat := FALSE;              // 清失决锁存位
    _bCfgBad := FALSE;              // 清组态锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF
IF (TIME_TO_DINT(tGlitch) <= 0) OR (TIME_TO_DINT(tDisTo) <= 0) OR (TIME_TO_DINT(tBlockAfter) <= 0) THEN
    _uFault := 16#0003_03FF;        // 故障级：组态非法
    _bCfgBad := TRUE;
END_IF

(* —— 段 3：冗余失决独立锁存与恢复（R190：失决归因唯一） —— *)
IF tonDisTo.Q AND (NOT _bDisLat) THEN
    _uFault := 16#0003_03FE;        // 故障级：双表失决锁存
    _bDisLat := TRUE;
END_IF
(* 解除式逐 BOOL 标注（R240）：rtReset.Q = 当拍量；NOT _bDisagree = 当拍量；
   均不含锁存量（_bDisLat），解除边真实可达。 *)
IF rtReset.Q AND (NOT _bDisagree) AND (NOT _bCfgBad) THEN
    _bDisLat := FALSE;              // 清失决锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，同上唯一解除路径）
END_IF
IF (NOT _bDisagree) AND _bDisOkPrev AND bRedundEn AND (NOT _bDisLat) THEN
    _uInfo := 16#0003_0421;         // 信息级：冗余判定恢复沿
END_IF

(* —— 段 4：fail-safe LOW 归一出口（失效/失决/组态坏 → 强制判低，安全侧） —— *)
IF (NOT bEnable) OR _bDisLat OR _bCfgBad THEN
    bLowLevel := TRUE;              // 安全侧强制判低（防干转，头注释②）
ELSE
    bLowLevel := tonLowDeb.Q;       // 防抖后低料位判定
END_IF

(* —— 段 5：再生切换闭锁（闭锁判据全当拍量；TOF 电平承载再生后窗） —— *)
bBlock := bRegenActive OR tofBlock.Q;   // 闭锁窗激活（再生中或再生后延时内）
bSwReq := bLowLevel AND (NOT bBlock);   // 切换请求（闭锁窗内强制 FALSE）
IF bBlock AND (NOT _bBlockPrev) THEN
    _uInfo := 16#0003_0420;         // 信息级：再生闭锁激活
END_IF
IF bSwReq AND (NOT _bSwReqPrev) THEN
    _uInfo := 16#0003_041F;         // 信息级：切换请求沿（覆盖闭锁沿，请求优先报告）
END_IF

(* —— 段 6：出口单点映射（锁存码回放，禁同拍抹除） —— *)
IF _bDisLat OR _bCfgBad THEN
    nErrId := _uFault;              // 故障锁存码回放
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bDisLat OR _bCfgBad;     // 故障标志与锁存位同源
_bSwReqPrev := bSwReq;              // 请求沿判据快照
_bBlockPrev := bBlock;              // 闭锁沿判据快照
_bDisOkPrev := NOT _bDisagree;      // 一致镜像快照

END_FUNCTION_BLOCK
