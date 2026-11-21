(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ModeArbiter
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 三源运行模式请求仲裁：手动（Manual）> 自动（Auto）> 远程（Remote）
 *                         三级优先。请求为电平输入，模式**进入**必须由对应请求的上升沿
 *                         （或 bActManual 手动激活沿）触发；高优先级请求沿出现即抢占当前
 *                         低级模式（bPreempted 记录被顶事实）；高优先级撤销后**不自动回退**
 *                         到低级模式——回退必须由低级请求重新沿触发，防模式振荡；全部请求
 *                         撤销 → eNone（不记忆最后模式，HMI 记忆语义由上层做）。
 *                         多请求同拍 → 按优先级电平取最高级裁决，同拍置 bChanged。
 * 接口     (Interface)  : 输入 bReqManual / bReqAuto / bReqRemote 三源请求电平、
 *                         bActManual 手动激活沿源（如本地选择开关）；输出 eMode 当前模式、
 *                         bChanged 模式变更单拍、bPreempted 被抢占单拍。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做模式请求仲裁与状态出口，不驱动任何
 *                         执行器、不做模式内的动作编排**；模式内行为由上层按 eMode 分发。
 *                         ② 进入 eManual 的沿条件 = rtReqManual 上升沿 ∨ (bActManual 上升沿
 *                         ∧ bReqManual 电平为真)；bActManual 单独出现而手动请求电平不成立时
 *                         不进入手动模式（防无保持电平的闪进闪出）。
 *                         ③ 在模式中保持条件 = 本模式请求电平为真；电平撤销即回 eNone，
 *                         **不**顺延到仍为真的低级请求（不自动回退铁律，回退必须重新沿触发）。
 *                         ④ 抢占定义：在非 eNone 模式中，被更高优先级的请求沿（或手动激活沿）
 *                         顶出 → bPreempted 单拍 + bChanged 单拍；平级沿（本模式自身请求沿）
 *                         不算抢占、不算变更。
 *                         ⑤ bActManual 在自动/远程模式中同样具备抢占能力（手动永远最高优先），
 *                         前提仍是 bReqManual 电平为真。
 *                         ⑥ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_MutexOwnerAudit` 分工：运行模式 ≠ 互斥锁属主，那件审计
 *                         资源占用属主，本件仲裁人机操作模式；与 `FB_DL_DeviceHealthArbiter`
 *                         分工：健康裁决域归那件，本件不读任何健康量。
 * 来源标签 (Source Tag) : 自研线（公开优先级仲裁语义 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 ENUM 模式 + BOOL 组；
 *                         数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 N/A（无浮点运算） ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE ｜ R7 ✓ 四 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R48 首版（批次 1 · 序号 4）
 *                         验收向量：手动沿抢占自动 → bPreempted；手动电平撤销 → eNone 不回
 *                         自动；自动沿重触发 → eAuto；三沿同拍 → eManual 优先。
 *==============================================================================*)

TYPE E_DL_MarMode :
(
    eNone   := 0,    // 无有效模式（全部请求撤销）/ No active mode
    eManual := 10,   // 手动模式（最高优先级）/ Manual mode, highest priority
    eAuto   := 20,   // 自动模式（中优先级）/ Auto mode, middle priority
    eRemote := 30    // 远程模式（最低优先级）/ Remote mode, lowest priority
);
END_TYPE

FUNCTION_BLOCK FB_DL_ModeArbiter
VAR_INPUT
    bReqManual : BOOL := FALSE;   // 手动模式请求电平 [-] / Manual mode request level
    bReqAuto   : BOOL := FALSE;   // 自动模式请求电平 [-] / Auto mode request level
    bReqRemote : BOOL := FALSE;   // 远程模式请求电平 [-] / Remote mode request level
    bActManual : BOOL := FALSE;   // 手动激活沿源（如本地选择开关动作；须伴随手动请求电平才生效） [-] / Manual activation edge source, needs manual request level
END_VAR
VAR_OUTPUT
    eMode      : E_DL_MarMode;    // 当前模式出口 [-] / Current mode outlet
    bChanged   : BOOL;            // 模式变更，单拍脉冲 [-] / Mode changed, single-scan pulse
    bPreempted : BOOL;            // 被高优先级抢占，单拍脉冲 [-] / Preempted by higher priority, single-scan pulse
END_VAR
VAR
    _eMode    : E_DL_MarMode := E_DL_MarMode.eNone;   // 内部模式（CASE 唯一写入目标） / Internal mode
    rtReqMan  : R_TRIG;           // 手动请求沿实例，段 0 无条件调用 / Manual request edge instance
    rtReqAuto : R_TRIG;           // 自动请求沿实例，段 0 无条件调用 / Auto request edge instance
    rtReqRem  : R_TRIG;           // 远程请求沿实例，段 0 无条件调用 / Remote request edge instance
    rtActMan  : R_TRIG;           // 手动激活沿实例，段 0 无条件调用 / Manual activation edge instance
    _bChanged : BOOL;             // 变更单拍内部量（统一出口映射，R34 两段式） / Changed pulse internal
    _bPreempt : BOOL;             // 抢占单拍内部量（统一出口映射） / Preempted pulse internal
END_VAR

(* —— 段 0：四枚沿实例无条件周期刷新 —— *)
rtReqMan(CLK := bReqManual);    // 手动请求沿，每拍必调 / Manual request edge, every scan
rtReqAuto(CLK := bReqAuto);     // 自动请求沿，每拍必调 / Auto request edge, every scan
rtReqRem(CLK := bReqRemote);    // 远程请求沿，每拍必调 / Remote request edge, every scan
rtActMan(CLK := bActManual);    // 手动激活沿，每拍必调 / Manual activation edge, every scan

(* —— 段 1：单拍量预清零（_eMode 为锁存状态量不入清单，R107） —— *)
bChanged   := FALSE;            // 变更脉冲预清 / Changed pulse preset
bPreempted := FALSE;            // 抢占脉冲预清 / Preempted pulse preset
_bChanged  := FALSE;            // 内部变更脉冲预清 / Internal changed pulse preset
_bPreempt  := FALSE;            // 内部抢占脉冲预清 / Internal preempted pulse preset

(* —— 段 2：模式状态机（进入必沿触发、保持必电平、撤销不回退） —— *)
CASE _eMode OF

E_DL_MarMode.eNone:
    IF rtReqMan.Q OR (rtActMan.Q AND bReqManual) THEN
        _eMode := E_DL_MarMode.eManual;                 // 手动沿（或激活沿∧手动电平）入手动 / Manual edge enters manual
        _bChanged := TRUE;                              // 记变更 / Mark changed
    ELSIF rtReqAuto.Q THEN
        _eMode := E_DL_MarMode.eAuto;                   // 自动沿入自动 / Auto edge enters auto
        _bChanged := TRUE;                              // 记变更 / Mark changed
    ELSIF rtReqRem.Q THEN
        _eMode := E_DL_MarMode.eRemote;                 // 远程沿入远程 / Remote edge enters remote
        _bChanged := TRUE;                              // 记变更 / Mark changed
    END_IF                                              // 同拍多沿按优先级顺序裁决（IF-ELSIF 级联即优先级）/ Same-scan multi-edge resolved by priority cascade

E_DL_MarMode.eManual:
    IF NOT bReqManual THEN
        _eMode := E_DL_MarMode.eNone;                   // 手动电平撤销 → eNone，不自动回退（铁律③）/ Manual level dropped, no auto fallback
        _bChanged := TRUE;                              // 记变更 / Mark changed
    ELSIF rtReqAuto.Q THEN
        _eMode := E_DL_MarMode.eAuto;                   // 自动沿抢占手动 / Auto edge preempts manual
        _bPreempt := TRUE;                              // 记抢占 / Mark preempted
        _bChanged := TRUE;                              // 记变更 / Mark changed
    ELSIF rtReqRem.Q THEN
        _eMode := E_DL_MarMode.eRemote;                 // 远程沿抢占手动 / Remote edge preempts manual
        _bPreempt := TRUE;                              // 记抢占 / Mark preempted
        _bChanged := TRUE;                              // 记变更 / Mark changed
    END_IF

E_DL_MarMode.eAuto:
    IF NOT bReqAuto THEN
        _eMode := E_DL_MarMode.eNone;                   // 自动电平撤销 → eNone，不自动回退 / Auto level dropped, no auto fallback
        _bChanged := TRUE;                              // 记变更 / Mark changed
    ELSIF rtReqMan.Q OR (rtActMan.Q AND bReqManual) THEN
        _eMode := E_DL_MarMode.eManual;                 // 手动沿抢占自动 / Manual edge preempts auto
        _bPreempt := TRUE;                              // 记抢占 / Mark preempted
        _bChanged := TRUE;                              // 记变更 / Mark changed
    ELSIF rtReqRem.Q THEN
        _eMode := E_DL_MarMode.eRemote;                 // 远程沿抢占自动 / Remote edge preempts auto
        _bPreempt := TRUE;                              // 记抢占 / Mark preempted
        _bChanged := TRUE;                              // 记变更 / Mark changed
    END_IF

E_DL_MarMode.eRemote:
    IF NOT bReqRemote THEN
        _eMode := E_DL_MarMode.eNone;                   // 远程电平撤销 → eNone，不自动回退 / Remote level dropped, no auto fallback
        _bChanged := TRUE;                              // 记变更 / Mark changed
    ELSIF rtReqMan.Q OR (rtActMan.Q AND bReqManual) THEN
        _eMode := E_DL_MarMode.eManual;                 // 手动沿抢占远程 / Manual edge preempts remote
        _bPreempt := TRUE;                              // 记抢占 / Mark preempted
        _bChanged := TRUE;                              // 记变更 / Mark changed
    ELSIF rtReqAuto.Q THEN
        _eMode := E_DL_MarMode.eAuto;                   // 自动沿抢占远程 / Auto edge preempts remote
        _bPreempt := TRUE;                              // 记抢占 / Mark preempted
        _bChanged := TRUE;                              // 记变更 / Mark changed
    END_IF

ELSE
    _eMode := E_DL_MarMode.eNone;                       // 非法模式兜底拉回无模式 / Illegal mode falls back to none
    _bChanged := TRUE;                                  // 兜底迁移也记变更 / Fallback marks changed

END_CASE

(* —— 段 3：出口单点映射（bChanged/bPreempted 由内部量统一映射，R34 两段式；R191 同源） —— *)
bChanged   := _bChanged;                                // 变更单拍出口 / Changed pulse outlet
bPreempted := _bPreempt;                                // 抢占单拍出口 / Preempted pulse outlet
eMode      := _eMode;                                   // 当前模式出口 / Current mode outlet

END_FUNCTION_BLOCK
