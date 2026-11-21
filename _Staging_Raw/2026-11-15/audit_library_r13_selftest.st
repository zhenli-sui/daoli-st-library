(*==============================================================================
 * R13 机检脚本自检样本（检测能力回归用，不属于代码库，不参与全库扫描）
 * 用途：python audit_library_r13.py --rules r37_left_clamp,r38_dual_source,r39_pre_case_override,r40_ton_cross_segment --files <本文件>
 * 期望：r37 命中 2（r37.1 一处 + r37.3 一处）、r38 命中 1（r38.a）、r39 命中 1、r40 命中 1
 *============================================================================*)
FUNCTION_BLOCK FB_AuditR13SelfTest
VAR_INPUT
    bEnable   : BOOL;                                  // 使能 / Enable
    sFrame    : STRING(255);                           // 帧 / Frame
END_VAR
VAR_OUTPUT
    bTruncated : BOOL;                                 // 截断标志（本样本故意从不置真）/ Truncated flag, never set
    eState     : E_DL_SelfTestState;                   // 状态 / State
END_VAR
VAR
    sFrameLatched : STRING(255);                       // 锁存帧 / Latched frame
    sBuf          : STRING(255);                       // 缓冲 / Buffer
    nStep         : INT;                               // 步号 / Step index
    bStepRun      : BOOL;                              // 步运行（只置真不清零）/ Step run, set true and never cleared
    fbTonWatch    : TON;                               // 监控定时器 / Watch timer
END_VAR

// [r38.a] 锁存副本与实时入参双源：同基名 LEN 并存且锁存副本被取段消费
sFrameLatched := sFrame;
IF LEN(sFrame) > 10 THEN
    nStep := LEN(sFrameLatched);
END_IF

// [r37.1] 自赋值回夹且无长度守卫、前文未置截断标志
sBuf := LEFT(sBuf, 200);

// [r39] CASE 前置停机分支无条件改写状态，条件未排除故障态
IF NOT bEnable THEN
    eState := E_DL_SelfTestState.eIdle;
END_IF

CASE nStep OF
    0:
        // [r40] 段推进写存在，IN 根变量跨段恒真
        bStepRun := TRUE;
        nStep := nStep + 1;
    1:
        fbTonWatch(IN := bStepRun, PT := T#5S);
        IF fbTonWatch.Q THEN
            nStep := nStep + 1;
        END_IF
    ELSE
        nStep := 0;
END_CASE
END_FUNCTION_BLOCK
