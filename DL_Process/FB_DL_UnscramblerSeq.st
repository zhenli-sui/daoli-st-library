(*
  ==================================================================
  组件名 Component  : FB_DL_UnscramblerSeq
  分类   Category   : DL_Process
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0006_3038（故障级：卡瓶监视窗超时）｜ 16#0006_3039
                      （故障级：组态非法）
  版本   Version    : 1.0.0
  复杂度 Complexity  : 中
  功能   Purpose    : 理瓶整理顺控：进瓶整理 → 乱瓶分拣 → 整理完成的相序推进，
                      卡瓶监视窗（卡瓶检测电平持续超窗即锁存故障）+ 料满停进
                      （满仓强制停进不 faults）；供理瓶机 / 提升料仓类工位。
  开源溯源 Origin    : OMAC PackML 状态模型（公开标准，T2-7 次源）：仅借 17 态
                      模型的相语义聚合口径（本件聚合为四相，R264 唯一声明）；
                      理瓶顺控逻辑完全自研，零代码复制。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6 状态机 / TON / R_TRIG 语义；
                      OMAC PackML 状态模型公开条款（借相语义，不抄文）
  平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / ENUM+CASE / 四则），三平台通用
  依赖   Depends    : 仅 Standard.library（TON / R_TRIG 属标准件）
  分工声明 Split     : FB_DL_CapSorterSeq（ caps 分拣专用顺控）/ FB_DL_FeederLevel
                      （料位控制）与本件互引；本件为理瓶相序 + 卡瓶保护 +
                      料满停进三合一工站级顺控，单相控制归各自属主（R216）。
  归属 Ownership     : E_DL_UnscrPhase 属主为本文件（全库唯一定义，R264）；
                      引用件只引用不重声明。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 组态闸结构早退（族② 判据，逐项点名 R272）：
                         tJamWin ≤ 0（卡瓶窗非正）或 tPhaseMin ≤ 0（相最短
                         驻留非正）→ 组态码 3039 + 三件套 + RETURN；
                      二 状态机 ENUM + CASE 必带 ELSE（非法态兜底落 eFault +
                         锁存 3039，禁静默）；本拍合法事件（停止 / 料满 /
                         相完成沿）优先于卡瓶超时迁移（R275 同拍竞态）；
                      三 卡瓶窗口径：bJamSense 电平 + tJamWin 持续超窗 →
                         锁存 3038；瞬时卡瓶抖动由窗吸收（窗时长须大于
                         检测去抖上限，交付默认 T#3S，调用方改参须维持）；
                      四 失败锁存 bJamFault + _bFaultLatch；锁存解除式
                         （可达自证，R152）：bResetCmd 上升沿清锁存回 eIdle
                         （输入引脚恒可达，无「置位即永久」路径）；
                      五 料满停进语义（不 faults）：bHopperFull 电平在
                         eFeed / eSort 相强制 bFeedOut = FALSE 停进、相保持
                         挂起（相驻留最短时限 tonPhase 在料满期同步挂起，
                         防满仓期被误判相超时——挂相不挂故障）；料满解除
                         后相序自动续推；
                      六 bEnable = FALSE 的语义写死（FB33-4 声明行）：强制
                         eIdle + 双出口复位（不 faults，使能断开 ≠ 顺控故障）；
                      七 TON / R_TRIG 段 0 无条件刷新（禁入分支，R7）；监视
                         TON IN 串故障锁存门控（FB50-1）；相驻留 TON 为
                         「最短驻留门槛」口径（IN 串相条件，到时即允许
                         迁移，不是超时故障源）；
                      八 首拍 _bInit 全量初始化；无浮点量、无除法；无全局、
                         无外部变量、无物理地址。
  错误码 Codes      :
    16#0006_3038【故障级】卡瓶持续超窗（bJamSense 持续 tJamWin，疑似卡瓶 /
                         检测回路故障）
    16#0006_3039【故障级】组态非法（tJamWin ≤ 0 / tPhaseMin ≤ 0）或非法状态
                         拦截（ELSE 兜底）
  码位反证 Note     :
    3038 与 3039 不可合并：3038 与组态无关（需运行期卡瓶电平到达，处置人 =
    现场机务），3039 组态即刻判（处置人 = 组态工程师），可由场景还原（R90），
    分立；料满停进不设码（停进不是故障，边界五语义声明）。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 启动 → eFeed（bFeedOut = TRUE）；相驻留到时 + 分拣使能 → eSort
    V2 分拣完成信号 → eReady（bFeedOut / bSortOut 复位）
    V3 bJamSense 持续超窗 → 锁存 3038、双出口切断
    V4 瞬时卡瓶 < 窗 → 不误报（窗吸收向量）
    V5 eFeed 期料满 → bFeedOut 强制 FALSE、相挂起不超时（边界五向量）
    V6 tJamWin = T#0S → 组态早退 3039；V7 失能 → eIdle 双出口复位
    V8 非法枚举态（强改 eState）→ ELSE 兜底落 eFault + 3039
  修订记录 Revision  :
    2026-11-21  v1.0.0  R64 首版（批 3 · 序号 10，PackML 相语义 + 自研顺控）
  ==================================================================
*)
TYPE E_DL_UnscrPhase :
(
    eIdle  := 0,  // 待机：等启动 / idle, waiting for the start
    eFeed  := 10, // 进瓶整理：进料出口有效，等相驻留 / the feed phase with the feed outlet
    eSort  := 20, // 乱瓶分拣：分拣出口有效，等完成信号 / the sort phase with the sort outlet
    eReady := 30, // 整理完成：双出口复位，等再启动或停止 / the ready phase with both outlets reset
    eFault := 40  // 锁存故障：卡瓶超窗或非法态，复位沿解除 / a latched fault released by the reset edge
);
END_TYPE

FUNCTION_BLOCK FB_DL_UnscramblerSeq
VAR_INPUT
    bEnable    : BOOL := TRUE;   // 使能，FALSE 时强制 eIdle + 双出口复位（边界六）/ the enable, false forces the idle and resets both outlets
    bStart     : BOOL := FALSE;  // 启动电平 [-]（eReady / eIdle 相生效）/ the start level valid in the ready and idle phases
    bSortEn    : BOOL := FALSE;  // 分拣使能电平 [-]（eFeed → eSort 的迁移前提）/ the sort enable as the transition premise
    bSortDone  : BOOL := FALSE;  // 分拣完成电平 [-]（eSort → eReady 的事件）/ the sort done event of the sort phase
    bJamSense  : BOOL := FALSE;  // 卡瓶检测电平 [-] / the jam detection level
    bHopperFull: BOOL := FALSE;  // 料满电平 [-]（满仓停进，不 faults，边界五）/ the hopper full level stopping the feed without a fault
    bResetCmd  : BOOL := FALSE;  // 故障复位电平，上升沿清锁存回 eIdle（边界四解除式）/ the fault reset level, its rising edge releases the latch
    tJamWin    : TIME := T#3S;   // 卡瓶监视窗 [毫秒]，须 > 0 / the jam window, positive
    tPhaseMin  : TIME := T#2S;   // 相最短驻留 [毫秒]，须 > 0 / the minimum phase dwell, positive
END_VAR
VAR_OUTPUT
    bFeedOut : BOOL := FALSE;           // 进料出口 [-]（料满 / 故障 / 失能强制 FALSE）/ the feed outlet forced false on full, fault or disable
    bSortOut : BOOL := FALSE;           // 分拣出口 [-]（故障 / 失能强制 FALSE）/ the sort outlet forced false on a fault or disable
    bJamFault: BOOL := FALSE;           // 卡瓶故障（锁存）[-] / the latched jam fault
    eState   : E_DL_UnscrPhase;         // 状态机出口 [状态] / the state machine outlet
    bValid   : BOOL := FALSE;           // 判据可用 [-] / the criteria are usable
    eErr     : UDINT := 16#0000_0000;   // 错误码，0 = 正常 / the error code, zero is ok
    bError   : BOOL := FALSE;           // 故障标志（故障级码同拍置位，R45 配对）/ the fault flag raised with a fault level code
END_VAR
VAR
    _bInit      : BOOL := FALSE;  // 首拍初始化标志（R310 / FB50-2）/ the first scan flag
    _eState     : E_DL_UnscrPhase := E_DL_UnscrPhase.eIdle; // 内部状态寄存器 / the internal state register
    _bFaultLatch: BOOL := FALSE;  // 故障锁存副本（仅复位沿清除）/ the fault latch copy
    _uLatch     : UDINT := 16#0000_0000; // 故障码锁存 [码]（复位沿清除，FB33-1）/ the latched fault code cleared by the reset edge
    _bCfgBad    : BOOL := FALSE;  // 组态非法标记（逐拍重算）/ the configuration fault flag
    _bHold      : BOOL := FALSE;  // 料满挂相标记（料满期相驻留计时同步挂起，边界五）/ the hold flag suspending the dwell timer on full
    rtReset     : R_TRIG;         // 复位沿实例，段 0 无条件刷新（R7）/ the reset edge instance refreshed unconditionally
    tonJam      : TON;            // 卡瓶监视窗定时器，段 0 无条件刷新 / the jam window timer refreshed unconditionally
    tonPhase    : TON;            // 相最短驻留定时器（最短驻留门槛口径，边界七）/ the phase dwell floor timer
END_VAR  // R64 结构补齐：VAR 段缺失的 END_VAR（门禁机械修复）
VAR CONSTANT
    DL_UNP_TIME0 : TIME := T#0S;          // 时间零常量 [毫秒] / the time zero constant
    DL_UNP_ZEROU : UDINT := 16#0000_0000; // 码零常量 / the code zero constant
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支，R7；监视 TON 串锁存门控，FB50-1）/ segment 0, the unconditional refresh
rtReset(CLK := bResetCmd); // 复位沿 / the reset edge
tonJam(IN := (( _eState = E_DL_UnscrPhase.eFeed) OR (_eState = E_DL_UnscrPhase.eSort))
          AND bJamSense AND (NOT _bFaultLatch), PT := tJamWin); // 卡瓶窗计时（仅进瓶 / 分拣相有效，串锁存门控防复位同拍重锁）/ the jam window only in the feed and sort phases with the latch gate
tonPhase(IN := (( _eState = E_DL_UnscrPhase.eFeed) OR (_eState = E_DL_UnscrPhase.eSort))
          AND (NOT _bHold) AND (NOT _bFaultLatch), PT := tPhaseMin); // 相驻留计时（料满挂相机同步挂起，边界五；最短驻留门槛口径，边界七）/ the dwell timer suspended on the hold, a floor not a timeout source

// 段 1｜首拍初始化与复位沿作用域（R310 / R311）/ segment 1, the first scan init and the reset edge scope
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _eState := E_DL_UnscrPhase.eIdle; // 状态显式落空闲 / place the state to idle
    _bFaultLatch := FALSE; // 故障锁存显式清零 / clear the fault latch explicitly
    _uLatch := DL_UNP_ZEROU; // 码锁存显式清零 / clear the latched code explicitly
    _bHold := FALSE; // 挂相标记显式清零 / clear the hold flag explicitly
END_IF
IF rtReset.Q THEN // 复位沿（作用域声明：清锁存 + 迁相位 + 清挂相，R311）/ the reset edge with the declared scope
    _bFaultLatch := FALSE; // 清故障锁存（唯一解除路径，边界四自证可达）/ clear the fault latch, the only release path
    _uLatch := DL_UNP_ZEROU; // 清码锁存 / clear the latched code
    _eState := E_DL_UnscrPhase.eIdle; // 迁回空闲 / back to idle
    _bHold := FALSE; // 清挂相标记 / clear the hold flag
END_IF

// 段 2｜组态域闸结构早退（边界一，族② 判据：两时限逐项点名）/ segment 2, the structural early exit on an illegal configuration
_bCfgBad := (tJamWin <= DL_UNP_TIME0) OR (tPhaseMin <= DL_UNP_TIME0); // 组态非法（任一窗非正）/ an illegal configuration
IF _bCfgBad THEN // 组态非法：结构早退（出口三件套 + RETURN）/ an illegal configuration exits structurally
    eState := _eState; // 状态照实出口（冻结）/ export the state as is
    bFeedOut := FALSE; // 进料出口切断（组态非法期禁下发）/ cut the feed outlet off
    bSortOut := FALSE; // 分拣出口切断 / cut the sort outlet off
    bJamFault := _bFaultLatch; // 故障锁存照实回放 / replay the latch
    bValid := FALSE; // 判据不可用 / the criteria are not usable
    eErr := 16#0006_3039; // 故障级：组态非法 / fault grade, an illegal configuration
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    RETURN; // 结构早退 / the structural early exit
END_IF

// 段 3｜失能分支：强制 eIdle + 双出口复位，不 faults（边界六声明行）/ segment 3, the disabled branch
IF NOT bEnable THEN // 失能 / disabled
    _eState := E_DL_UnscrPhase.eIdle; // 强制空闲 / force the idle
    _bFaultLatch := FALSE; // 锁存复位（使能断开 ≠ 顺控故障）/ clear the latch
    _uLatch := DL_UNP_ZEROU; // 码锁存复位 / clear the code
    _bHold := FALSE; // 挂相标记复位 / clear the hold flag
    eState := _eState; // 状态出口 / the state outlet
    bFeedOut := FALSE; // 进料出口复位 / the feed outlet resets
    bSortOut := FALSE; // 分拣出口复位 / the sort outlet resets
    bJamFault := FALSE; // 故障位复位 / the fault bit resets
    bValid := FALSE; // 失能即不可用 / the criteria are not usable while disabled
    bError := FALSE; // 失能不是故障 / a disabled device is not a fault
    eErr := DL_UNP_ZEROU; // 失能不发码 / no code is emitted while disabled
    RETURN; // 早退 / early return
END_IF

// 段 4｜主状态机（ENUM + CASE，ELSE 兜底；本拍合法事件优先于卡瓶超时，R275）/ segment 4, the main machine, the legal event before the jam timeout
CASE _eState OF
    E_DL_UnscrPhase.eIdle: // 空闲相 / the idle phase
        IF bStart AND (NOT _bFaultLatch) AND (NOT _bCfgBad) THEN // 启动电平 + 全量闸位复检（R274）/ the start with the full gate recheck
            _eState := E_DL_UnscrPhase.eFeed; // 迁入进瓶相 / enter the feed phase
        END_IF
    E_DL_UnscrPhase.eFeed: // 进瓶相（本拍合法事件优先：停止 / 分拣使能迁移先消化，再消化卡瓶超窗，R275）/ the feed phase, the legal event before the jam timeout
        IF bHopperFull THEN // 料满停进：相挂起不迁相（边界五，挂相不挂故障）/ the full level holds the phase without a fault
            _bHold := TRUE; // 置挂相标记（tonPhase 同步挂起，防满仓误判）/ raise the hold flag
        ELSE // 料满解除 / the full level released
            _bHold := FALSE; // 清挂相标记（相序自动续推）/ clear the hold flag
        END_IF
        IF NOT bStart THEN // 事件优先：停止电平 / the stop level, the event goes first
            _eState := E_DL_UnscrPhase.eIdle; // 回空闲 / back to idle
        ELSIF tonPhase.Q AND bSortEn THEN // 相驻留到时 + 分拣使能（迁移门槛齐备）/ the dwell floor reached with the sort enable
            _eState := E_DL_UnscrPhase.eSort; // 迁入分拣相 / enter the sort phase
        ELSIF tonJam.Q THEN // 卡瓶持续超窗（卡瓶判据，真实可达：瓶体楔死）/ the jam stayed through the window, reachable by a wedged bottle
            _bFaultLatch := TRUE; // 锁存故障 / latch the fault
            _uLatch := 16#0006_3038; // 故障级：卡瓶超窗 / fault grade, the jam through the window
            bError := TRUE; // 同拍置故障标志（R45 配对，段 6 故障分支沿用）/ raise the fault flag on the same scan
        END_IF
    E_DL_UnscrPhase.eSort: // 分拣相（同拍序与 eFeed 一致，R275）/ the sort phase with the same event order
        IF bHopperFull THEN // 料满挂相（分拣出口保持，进料出口停，边界五）/ the full level holds the phase, the sort outlet stays
            _bHold := TRUE; // 置挂相标记 / raise the hold flag
        ELSE // 料满解除 / the full level released
            _bHold := FALSE; // 清挂相标记 / clear the hold flag
        END_IF
        IF NOT bStart THEN // 事件优先：停止电平 / the stop level, the event goes first
            _eState := E_DL_UnscrPhase.eIdle; // 回空闲 / back to idle
        ELSIF bSortDone THEN // 事件优先：分拣完成 / the sort done, the event goes first
            _eState := E_DL_UnscrPhase.eReady; // 迁入完成相 / enter the ready phase
        ELSIF tonJam.Q THEN // 卡瓶持续超窗 / the jam through the window
            _bFaultLatch := TRUE; // 锁存故障 / latch the fault
            _uLatch := 16#0006_3038; // 故障级：卡瓶超窗 / fault grade, the jam through the window
            bError := TRUE; // 同拍置故障标志（R45 配对，段 6 故障分支沿用）/ raise the fault flag on the same scan
        END_IF
    E_DL_UnscrPhase.eReady: // 完成相（整理完成驻留，等再启动或停止）/ the ready phase dwelling for the next start or stop
        IF NOT bStart THEN // 停止电平 / the stop level
            _eState := E_DL_UnscrPhase.eIdle; // 回空闲 / back to idle
        ELSIF bStart AND (NOT bHopperFull) THEN // 再启动且料已不满（料满期不重进，防顶仓）/ a restart with the hopper not full
            _eState := E_DL_UnscrPhase.eFeed; // 重进进瓶相 / reenter the feed phase
        END_IF
    E_DL_UnscrPhase.eFault: // 锁存故障相（驻留，解除由段 1 复位沿承担）/ the fault phase dwelling, the release belongs to the reset edge
        ; // 驻留语义由注释表达（禁自赋值死语句，R261）/ the dwell is expressed by this comment without a dead statement
    ELSE // 非法枚举值拦截（边界二：落故障相并锁存，禁静默）/ the illegal enumeration guard
        _bFaultLatch := TRUE; // 锁存故障 / latch the fault
        _uLatch := 16#0006_3039; // 故障级：非法状态拦截（归入组态族一码，出口同形，R90）/ fault grade, the illegal state in the configuration family
        bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
        _eState := E_DL_UnscrPhase.eFault; // 落故障相 / force the fault phase
END_CASE

// 段 5｜故障锁存迁移闸（置于解除段之后防同拍抢迁，R258）/ segment 5, the latch to phase gate
IF _bFaultLatch AND (_eState <> E_DL_UnscrPhase.eFault) THEN // 已锁存但不在故障相 / latched outside the fault phase
    _eState := E_DL_UnscrPhase.eFault; // 迁入故障相 / enter the fault phase
END_IF

// 段 6｜统一出口（名实双出口同源，R191）/ segment 6, the unified outlet
eState := _eState; // 状态出口 / the state outlet
bFeedOut := (_eState = E_DL_UnscrPhase.eFeed) AND (NOT _bHold)
         AND (NOT _bFaultLatch); // 进料出口与状态 / 挂相 / 锁存同源派生（边界五料满停进）/ the feed outlet derived from the state, the hold and the latch
bSortOut := (_eState = E_DL_UnscrPhase.eSort) AND (NOT _bFaultLatch); // 分拣出口与状态 / 锁存同源派生（料满期分拣出口保持，边界五）/ the sort outlet derived from the state and the latch
bJamFault := _bFaultLatch; // 故障位与锁存同源 / the fault bit from the latch
bValid := (NOT _bFaultLatch) AND (NOT _bCfgBad); // 判据可用（无锁存且组态合法）/ usable without a latch and with a legal configuration
IF _bFaultLatch THEN // 故障锁存回放优先（不在故障相按当下输入重新推断，R152）/ the latched fault replays first
    bValid := FALSE; // 故障相不可用 / not usable in the fault phase
    bError := TRUE; // 故障位置位（R45 配对）/ raise the fault bit
    eErr := _uLatch; // 锁存码回放 / replay the latched code
ELSE // 无事件 / no event
    bError := FALSE; // 无故障 / no fault
    eErr := DL_UNP_ZEROU; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
