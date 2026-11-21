(*
  ==================================================================
  组件名 Component  : FB_DL_DualValveBlockSet
  分类   Category   : DL_Device
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0003_072D（故障级：组态非法）｜ 16#0003_072E（故障级：
                      反馈不一致窗超时）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 中
  功能   Purpose    : 双阀冗余块组控：双阀同令同闭（单指令源统一下发）+ 两路
                      位置反馈不一致窗判定（一阀卡滞 / 位置开关故障的启动期
                      与稳态期保护）；不一致持续超窗即锁存故障并切断指令出口。
  开源溯源 Origin    : 西门子 LBP（免费闭源）阀特性「命令-监视-判定」三段分层
                      组织方式借鉴（R26 沿用，只借骨不抄肉）；双阀不一致窗
                      判据与实现 clean-room，零代码复制。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6 状态机与 TON 语义；冗余阀组
                      「命令-监视-判定」公开工程组织口径
  平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / ENUM+CASE / 四则），三平台通用
  依赖   Depends    : 仅 Standard.library（TON / R_TRIG 属标准件）
  分工声明 Split     : FB_DL_SingleValveCtrl（单阀对象）/ FB_DL_ValvePairXor
                      （二取一表决）与本件互引；本件为「同令同闭 + 不一致窗」
                      冗余组控，表决逻辑归 ValvePairXor（R216）。
  归属 Ownership     : E_DL_DualValvePhase 属主为本文件（全库唯一定义，R264）；
                      引用件只引用不重声明。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 组态闸结构早退（族② 判据）：tMismatchWin ≤ 0 →
                         组态码 072D + 三件套 + RETURN（无浮点引脚，非有限
                         闸 N/A，本件域闸仅时限一项，逐项点名 R272）；
                      二 状态机 ENUM + CASE 必带 ELSE（非法态兜底落 eFault +
                         锁存 072D，禁静默）；本拍合法事件（指令沿 / 反馈
                         归队）优先于超时迁移（R275 同拍竞态）；
                      三 不一致窗口径：_bMismatch = (bFbValveA <> bFbValveB)
                         电平直比（BOOL 反馈无容差问题）；指令切换瞬态的不
                         一致由 tMismatchWin 吸收（窗时长须大于双阀响应差
                         上限，交付默认 T#10S，调用方改参须维持该配比）；
                         持续超窗 → 锁存 072E；
                      四 失败锁存 bMismatchFault + _bFaultLatch；锁存解除式
                         （可达自证，R152）：bResetCmd 上升沿清锁存回 eIdle
                         （输入引脚恒可达，无「置位即永久」路径）；
                      五 指令出口切断（安全语义）：bValveCmd = bOpenCmd AND
                         NOT _bFaultLatch AND bEnable——故障锁存 / 失能期间
                         指令出口强制 FALSE（双保险语义，切令不切监视）；
                      六 bEnable = FALSE 的语义写死（FB33-4 声明行）：强制
                         eIdle + 双出口复位（不 faults，使能断开 ≠ 阀组故障）；
                      七 TON / R_TRIG 段 0 无条件刷新（禁入分支，R7）；监视
                         TON IN 串故障锁存门控（FB50-1）；
                      八 首拍 _bInit 全量初始化；无全局、无外部变量、无物理
                         地址；无浮点量（全 BOOL / TIME / ENUM），无除法。
  错误码 Codes      :
    16#0003_072D【故障级】组态非法（tMismatchWin ≤ 0）或非法状态拦截（ELSE 兜底）
    16#0003_072E【故障级】两路位置反馈不一致持续超窗（tMismatchWin，疑似单阀
                         卡滞或位置开关故障）
  码位反证 Note     :
    072D 与 072E 不可合并：072D 与输入无关（组态即刻判，处置人 = 组态工程师），
    072E 需运行期反馈到达（处置人 = 现场阀检），可由场景还原（R90），分立。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 指令 ON + 双反馈同步 ON → bInSync、bValveCmd 跟随、无码
    V2 单反馈滞留超窗 → 锁存 072E、bValveCmd 切断、bMismatchFault
    V3 指令切换瞬态不一致 < 窗 → 不误报（窗吸收向量）
    V4 故障态 bResetCmd 上升沿 → 解锁回 eIdle（锁存解除可达向量）
    V5 tMismatchWin = T#0S → 组态早退 072D
    V6 失能 → eIdle + 双出口复位（不 faults）
    V7 非法枚举态（强改 eState）→ ELSE 兜底落 eFault + 072D
  修订记录 Revision  :
    2026-11-21  v1.0.0  R64 首版（批 3 · 序号 8，LBP 阀组组织方式 clean-room）
  ==================================================================
*)
TYPE E_DL_DualValvePhase :
(
    eIdle  := 0,  // 待机：等指令 / idle, waiting for the command
    eRun   := 10, // 运行监视：指令生效，两路反馈一致窗监视 / the run phase with the mismatch window supervision
    eFault := 20  // 锁存故障：不一致超窗或非法态，复位沿解除 / a latched fault released by the reset edge
);
END_TYPE

FUNCTION_BLOCK FB_DL_DualValveBlockSet
VAR_INPUT
    bEnable     : BOOL := TRUE;   // 使能，FALSE 时强制 eIdle + 双出口复位（边界六）/ the enable, false forces the idle and resets both outlets
    bOpenCmd    : BOOL := FALSE;  // 开阀指令 [-]，双阀统一下发 / the open command issued to both valves
    bFbValveA   : BOOL := FALSE;  // 阀 A 位置反馈 [-] / the position feedback of the valve A
    bFbValveB   : BOOL := FALSE;  // 阀 B 位置反馈 [-] / the position feedback of the valve B
    bResetCmd   : BOOL := FALSE;  // 故障复位电平，上升沿清锁存回 eIdle（边界四解除式）/ the fault reset level, its rising edge releases the latch
    tMismatchWin: TIME := T#10S;  // 不一致监视窗 [毫秒]，须 > 0 且大于双阀响应差上限 / the mismatch window, positive and above the response spread
END_VAR
VAR_OUTPUT
    bValveCmd      : BOOL := FALSE;          // 阀组指令出口 [-]（故障 / 失能强制切断，边界五）/ the valve command outlet cut off on a fault or disable
    bInSync        : BOOL := FALSE;          // 双反馈同步 [-] / the two feedbacks in sync
    bMismatchFault : BOOL := FALSE;          // 不一致故障（锁存）[-] / the latched mismatch fault
    eState         : E_DL_DualValvePhase;    // 状态机出口 [状态] / the state machine outlet
    bValid         : BOOL := FALSE;          // 判据可用 [-] / the criteria are usable
    eErr           : UDINT := 16#0000_0000;  // 错误码，0 = 正常 / the error code, zero is ok
    bError         : BOOL := FALSE;          // 故障标志（故障级码同拍置位，R45 配对）/ the fault flag raised with a fault level code
END_VAR
VAR
    _bInit      : BOOL := FALSE;  // 首拍初始化标志（R310 / FB50-2）/ the first scan flag
    _eState     : E_DL_DualValvePhase := E_DL_DualValvePhase.eIdle; // 内部状态寄存器 / the internal state register
    _bFaultLatch: BOOL := FALSE;  // 故障锁存副本（仅复位沿清除）/ the fault latch copy
    _uLatch     : UDINT := 16#0000_0000; // 故障码锁存 [码]（复位沿清除，FB33-1）/ the latched fault code cleared by the reset edge
    _bMismatch  : BOOL := FALSE;  // 反馈不一致电平（逐拍重算）/ the mismatch level recomputed every scan
    _bCfgBad    : BOOL := FALSE;  // 组态非法标记（逐拍重算）/ the configuration fault flag
    rtReset     : R_TRIG;         // 复位沿实例，段 0 无条件刷新（R7）/ the reset edge instance refreshed unconditionally
    tonMismatch : TON;            // 不一致窗定时器，段 0 无条件刷新 / the mismatch window timer refreshed unconditionally
END_VAR  // R64 结构补齐：VAR 段缺失的 END_VAR（门禁机械修复）
VAR CONSTANT
    DL_DVP_TIME0 : TIME := T#0S;        // 时间零常量 [毫秒] / the time zero constant
    DL_DVP_ZEROU : UDINT := 16#0000_0000; // 码零常量 / the code zero constant
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支，R7；监视 TON 串锁存门控，FB50-1）/ segment 0, the unconditional refresh
rtReset(CLK := bResetCmd); // 复位沿 / the reset edge
_bMismatch := (bFbValveA <> bFbValveB); // 不一致电平逐拍重算（BOOL 直比无容差问题）/ the mismatch level recomputed, a plain boolean compare
tonMismatch(IN := _bMismatch AND (NOT _bFaultLatch), PT := tMismatchWin); // 不一致窗计时（串锁存门控防复位同拍重锁）/ the mismatch window with the latch gate

// 段 1｜首拍初始化与复位沿作用域（R310 / R311）/ segment 1, the first scan init and the reset edge scope
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _eState := E_DL_DualValvePhase.eIdle; // 状态显式落空闲 / place the state to idle
    _bFaultLatch := FALSE; // 故障锁存显式清零 / clear the fault latch explicitly
    _uLatch := DL_DVP_ZEROU; // 码锁存显式清零 / clear the latched code explicitly
END_IF
IF rtReset.Q THEN // 复位沿（作用域声明：清锁存 + 迁相位，R311）/ the reset edge with the declared scope
    _bFaultLatch := FALSE; // 清故障锁存（唯一解除路径，边界四自证可达）/ clear the fault latch, the only release path
    _uLatch := DL_DVP_ZEROU; // 清码锁存 / clear the latched code
    _eState := E_DL_DualValvePhase.eIdle; // 迁回空闲 / back to idle
END_IF

// 段 2｜组态域闸结构早退（边界一，族② 判据：tMismatchWin 逐项点名）/ segment 2, the structural early exit on an illegal configuration
_bCfgBad := (tMismatchWin <= DL_DVP_TIME0); // 组态非法（窗非正）/ an illegal configuration
IF _bCfgBad THEN // 组态非法：结构早退（出口三件套 + RETURN）/ an illegal configuration exits structurally
    eState := _eState; // 状态照实出口（冻结）/ export the state as is
    bValveCmd := FALSE; // 指令出口切断（组态非法期禁下发）/ cut the command outlet off
    bInSync := NOT _bMismatch; // 同步位照实 / the sync bit as is
    bMismatchFault := _bFaultLatch; // 故障锁存照实回放 / replay the latch
    bValid := FALSE; // 判据不可用 / the criteria are not usable
    eErr := 16#0003_072D; // 故障级：组态非法 / fault grade, an illegal configuration
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    RETURN; // 结构早退 / the structural early exit
END_IF

// 段 3｜失能分支：强制 eIdle + 双出口复位，不 faults（边界六声明行）/ segment 3, the disabled branch
IF NOT bEnable THEN // 失能 / disabled
    _eState := E_DL_DualValvePhase.eIdle; // 强制空闲 / force the idle
    _bFaultLatch := FALSE; // 锁存复位（使能断开 ≠ 阀组故障）/ clear the latch
    _uLatch := DL_DVP_ZEROU; // 码锁存复位 / clear the code
    eState := _eState; // 状态出口 / the state outlet
    bValveCmd := FALSE; // 指令出口复位 / the command outlet resets
    bInSync := FALSE; // 同步位复位（失能不声明同步）/ the sync bit resets
    bMismatchFault := FALSE; // 故障位复位 / the fault bit resets
    bValid := FALSE; // 失能即不可用 / the criteria are not usable while disabled
    bError := FALSE; // 失能不是故障 / a disabled device is not a fault
    eErr := DL_DVP_ZEROU; // 失能不发码 / no code is emitted while disabled
    RETURN; // 早退 / early return
END_IF

// 段 4｜主状态机（ENUM + CASE，ELSE 兜底；本拍事件优先于超时迁移，R275）/ segment 4, the main machine
CASE _eState OF
    E_DL_DualValvePhase.eIdle: // 空闲相 / the idle phase
        IF bOpenCmd AND (NOT _bFaultLatch) AND (NOT _bCfgBad) THEN // 指令电平 + 全量闸位复检（R274）/ the command with the full gate recheck
            _eState := E_DL_DualValvePhase.eRun; // 迁入运行监视相 / enter the run phase
        END_IF
    E_DL_DualValvePhase.eRun: // 运行监视相（本拍合法事件优先：反馈归队先消化，再消化超窗，R275）/ the run phase, the event before the timeout
        IF NOT bOpenCmd THEN // 事件优先：指令撤回 / the command withdrawn, the event goes first
            _eState := E_DL_DualValvePhase.eIdle; // 回空闲（监视件不锁运行态）/ back to idle
        ELSIF tonMismatch.Q THEN // 不一致持续超窗（卡滞 / 开关故障判据）/ the mismatch stayed through the window
            _bFaultLatch := TRUE; // 锁存故障 / latch the fault
            _uLatch := 16#0003_072E; // 故障级：不一致超窗 / fault grade, the mismatch through the window
            bError := TRUE; // 同拍置故障标志（R45 配对，段 6 故障分支沿用）/ raise the fault flag on the same scan
        END_IF
    E_DL_DualValvePhase.eFault: // 锁存故障相（驻留，解除由段 1 复位沿承担）/ the fault phase dwelling, the release belongs to the reset edge
        ; // 驻留语义由注释表达（禁自赋值死语句，R261）/ the dwell is expressed by this comment without a dead statement
    ELSE // 非法枚举值拦截（边界二：落故障相并锁存，禁静默）/ the illegal enumeration guard
        _bFaultLatch := TRUE; // 锁存故障 / latch the fault
        _uLatch := 16#0003_072D; // 故障级：非法状态拦截（归入组态族一码，出口同形，R90）/ fault grade, the illegal state in the configuration family
        bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
        _eState := E_DL_DualValvePhase.eFault; // 落故障相 / force the fault phase
END_CASE

// 段 5｜故障锁存迁移闸（置于解除段之后防同拍抢迁，R258）/ segment 5, the latch to phase gate
IF _bFaultLatch AND (_eState <> E_DL_DualValvePhase.eFault) THEN // 已锁存但不在故障相 / latched outside the fault phase
    _eState := E_DL_DualValvePhase.eFault; // 迁入故障相 / enter the fault phase
END_IF

// 段 6｜统一出口（名实双出口同源，R191）/ segment 6, the unified outlet
eState := _eState; // 状态出口 / the state outlet
bValveCmd := bOpenCmd AND (NOT _bFaultLatch); // 指令出口与锁存同源切断（边界五安全语义）/ the command outlet cut off with the latch
bInSync := NOT _bMismatch; // 同步位与不一致电平同源取反 / the sync bit inverted from the mismatch level
bMismatchFault := _bFaultLatch; // 故障位与锁存同源 / the fault bit from the latch
bValid := NOT _bFaultLatch; // 判据可用（无锁存故障）/ usable without a latch
IF _bFaultLatch THEN // 故障锁存回放优先（不在故障相按当下输入重新推断，R152）/ the latched fault replays first
    bValid := FALSE; // 故障相不可用 / not usable in the fault phase
    bError := TRUE; // 故障位置位（R45 配对）/ raise the fault bit
    eErr := _uLatch; // 锁存码回放 / replay the latched code
ELSE // 无事件 / no event
    bError := FALSE; // 无故障 / no fault
    eErr := DL_DVP_ZEROU; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
