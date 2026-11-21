(*
  ==================================================================
  组件名 Component  : FB_DL_TimerFailSafe
  分类   Category   : DL_Base
  复杂度 Complexity  : 轻
  版本   Version    : 1.0.0
  功能   Purpose    : 安全侧定时器。接通延时输出 bOut；当输出持续时长超过
                      tMaxHold 看门狗窗时自动回安全态 FALSE 并锁存 bTimedOut，
                      解除路径 = bIn 断电或 bReset 上升沿。安全侧赋值单点完成
                      （bOut := tonDelay.Q AND NOT _bLatch），不受本闸判定量
                      污染；与 FB_DL_ExtendedTimer 通用四模式分工互引。
  来源   Source     : T0-iec-std-wrapper（T0-2 定时器安全语义扩展）
  溯源   Origin     : IEC 61131-3 TON 标准语义的安全包装，clean-room 自研实现，
                      未复制任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: TON / R_TRIG，无私有库）
  分工声明 Split     : 与 FB_DL_ExtendedTimer 分工——后者做通用四模式定时，
                      本件只做安全侧超时自动回退封装。
  作者   Author     : 道莅代码库 · PLC 编程专家（R59）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 安全语义：bOut 唯一赋值点为统一出口，锁存期强制 FALSE
                         （安全态），锁存解除后须 bIn 重新接通才重新计时；
                      二 组态域：tOnDelay / tMaxHold 由调用方保证为正时长，
                         本件不做二次钳制；
                      三 定时器与沿检测全部段 0 无条件周期刷新（R7）；
                      四 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R59 首版（批 1 · 序号 1）
  ==================================================================
*)

FUNCTION_BLOCK FB_DL_TimerFailSafe
VAR_INPUT
    bIn       : BOOL := FALSE;  // 定时条件输入，TRUE = 请求延时接通 [-] / the timing condition input, true = the on delay requested
    tOnDelay  : TIME := T#2S;   // 接通延时整定 [毫秒] / the on delay setting [millisecond]
    tMaxHold  : TIME := T#60S;  // 输出最大允许持续时长，超过自动安全态 [毫秒] / the max allowed hold duration, safe state beyond [millisecond]
    bReset    : BOOL := FALSE;  // 超时锁存复位，上升沿生效 [-] / the timeout latch reset, rising edge effective
END_VAR
VAR_OUTPUT
    bOut      : BOOL := FALSE;  // 安全侧定时输出，超时自动回 FALSE [-] / the safety side timed output, safe false on timeout
    bRun      : BOOL := FALSE;  // 延时计时进行指示 [-] / the delay timing in progress indicator
    bTimedOut : BOOL := FALSE;  // 超时锁存指示，解除 = bIn 断电或复位沿 [-] / the timeout latch indicator, released by input drop or reset edge
    bError    : BOOL := FALSE;  // 预留故障位（本件无浮点运算，恒常假）[-] / the reserved fault bit, constant false in this block
END_VAR
VAR
    _bInit   : BOOL := FALSE; // 首拍初始化标志（R310，真实使用：首拍强制安全态预置）/ the first scan flag, real use, the safe preset on first scan
    _bLatch  : BOOL := FALSE; // 超时锁存位（安全态保持源，区分于实时镜像 bTimedOut）/ the timeout latch bit, the safe state source
    rtReset  : R_TRIG;        // 复位沿检测，段 0 无条件刷新 / the reset edge, refreshed unconditionally at segment 0
    tonDelay : TON;           // 接通延时器，段 0 无条件刷新 / the on delay timer, refreshed unconditionally
    tonHold  : TON;           // 持续时长看门狗，段 0 无条件刷新 / the hold watchdog timer, refreshed unconditionally
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支，R7）/ segment 0, the unconditional refresh
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonDelay(IN := bIn AND (NOT _bLatch), PT := tOnDelay); // 接通延时，锁存期不计时 / the on delay, not timing while latched
tonHold(IN := tonDelay.Q AND (NOT _bLatch), PT := tMaxHold); // 持续看门狗，仅在输出成立期计时 / the hold watchdog, timing only while the output stands

// 段 1｜首拍初始化（R310 真实使用路径）：强制安全态预置 / segment 1, the first scan init, the safe preset
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _bLatch := FALSE; // 锁存清零（编译缺省之上的显式安全预置）/ clear the latch explicitly
    bOut := FALSE; // 输出强制安全态 / force the output safe
END_IF

// 段 2｜超时锁存与解除（锁存解除路径 = bIn 断电沿或 bReset 上升沿，双路径可达，R188）/ segment 2, the timeout latch and release
IF tonHold.Q THEN // 看门狗窗到期：超时锁存 / the watchdog expired, latch the timeout
    _bLatch := TRUE; // 置超时锁存 / raise the timeout latch
END_IF
IF (NOT bIn) OR rtReset.Q THEN // 条件断电或复位沿 / the condition dropped or the reset edge
    _bLatch := FALSE; // 解除锁存（解除后再接通需重新计时）/ release the latch
END_IF

// 段 3｜统一出口：安全侧赋值单点完成（判定量 bIn 只经 tonDelay.Q 进入，不被闸判定量污染，边界一）/ segment 3, the unified outlet
bOut := tonDelay.Q AND (NOT _bLatch); // 输出 = 延时到 且 未超时锁存 / the output, delayed and not latched
bRun := tonDelay.IN; // 计时进行镜像 / the timing in progress mirror
bTimedOut := _bLatch; // 超时指示与锁存位同源（R191 名实双出口）/ the timeout indicator shares the latch
END_FUNCTION_BLOCK
