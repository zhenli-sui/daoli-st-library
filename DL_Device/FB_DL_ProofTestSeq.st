(*
  ==================================================================
  组件名 Component  : FB_DL_ProofTestSeq
  分类   Category   : DL_Device
  复杂度 Complexity  : cx4
  版本   Version    : 1.0.0
  功能   Purpose    : 联锁功能证明试验顺控。按 tTestPeriod 周期发起激励-反馈
                      回路验证：激励输出后 tFeedbackTo 内收到反馈沿进评估段，
                      保持激励 tTestDur 后按反馈在位判通过；试验失败挂
                      NE107 eCheckFunction / eMaintenanceReq 健康语言。
  来源   Source     : t2-isa-ne107（借鉴 ISA-18.2 / NE107 证明试验与健康语言
                      纪律，clean-room 自研实现，未复制任何文档代码行）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；证明试验周期激励
                      为公开功能安全维护语义。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: TON / R_TRIG，无私有库）
  分工声明 Split     : 与 FB_DL_PassboxInterlockSeq（工艺顺控）分工——本件是
                      联锁回路自证试验顺控，不驱动工艺介质、不参与生产联锁。
  作者   Author     : 道莅代码库 · PLC 编程专家（R57）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 组态配比约束（R100）：tTestPeriod > tTestDur 且
                         tFeedbackTo < tTestDur，越域判故障级；
                      二 试验中真实故障（bDeviceFault）与试验失败（eTestFail）
                         分段独立成因（R190 归因唯一），真实故障优先；
                      三 试验请求仅在设备空闲相（bDevIdle）受理，运行相拒
                         并置信息级 bReqRejected 单拍；
                      四 锁存解除路径 = bReset 上升沿（唯一路径，R188）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R57 首版（批 4 · 序号 18）
  ==================================================================
*)

TYPE E_DL_PtsPhase :
(
    eIdle   := 0,  // 空闲：周期窗计时 / idle, the period window counting
    eExcite := 10, // 激励：等反馈沿 / exciting, waiting for the feedback edge
    eEval   := 20, // 评估：保持激励到持续窗满 / evaluating, the drive held until the duration expiry
    eFault  := 90  // 故障：成因锁存 / fault, the cause latched
);
END_TYPE

TYPE E_DL_PtsFault :
(
    eNone        := 0, // 无成因 / no cause
    eCfgBad      := 1, // 组态非法：三窗配比越域（故障级，与 bError 配对）/ an illegal config
    eDeviceFault := 2, // 试验中真实设备故障（故障级，与 bError 配对）/ a real device fault during the test
    eTestFail    := 3, // 试验失败：反馈超时或评估失在（故障级，与 bError 配对）/ a test failure
    ePhaseBad    := 4  // 非法相位兜底（故障级，与 bError 配对）/ an illegal phase fallback
);
END_TYPE

TYPE E_DL_PtsHealth :
(
    eGood           := 0, // NE107 正常（最近试验通过）/ the NE107 good state, the latest test passed
    eCheckFunction  := 1, // NE107 功能受影响（试验失败待复测）/ the NE107 check function state
    eMaintenanceReq := 2  // NE107 维护要求（试验失败或真实故障）/ the NE107 maintenance state
);
END_TYPE

FUNCTION_BLOCK FB_DL_ProofTestSeq
VAR_INPUT
    bEnable      : BOOL := TRUE;   // 使能，失能即停试验回空闲 [-] / enable, disabling stops the test to idle
    bReset       : BOOL := FALSE;  // 复位上升沿清锁存 [-] / reset rising edge clears the latch
    bTestReq     : BOOL := FALSE;  // 试验请求电平（仅在空闲相受理）[-] / the test request level, accepted only in idle
    bDevIdle     : BOOL := TRUE;   // 设备空闲相指示 [-] / the device idle indicator
    bDeviceFault : BOOL := FALSE;  // 设备真实故障电平 [-] / the real device fault level
    bFeedback    : BOOL := FALSE;  // 联锁反馈（激励后应动作）[-] / the interlock feedback, expected active under the drive
    tTestPeriod  : TIME := T#3600S; // 试验周期窗 [毫秒]，域 大于 tTestDur / the test period window, above the duration
    tTestDur     : TIME := T#10S;   // 试验持续窗 [毫秒]，域 大于 tFeedbackTo / the test duration window, above the feedback timeout
    tFeedbackTo  : TIME := T#5S;    // 反馈超时窗 [毫秒] / the feedback timeout window [millisecond]
END_VAR
VAR_OUTPUT
    bTestDrive   : BOOL := FALSE; // 激励输出（试验中为真）[-] / the test drive outlet
    bTestActive  : BOOL := FALSE; // 试验进行中电平 [-] / the test active level
    bTestOk      : BOOL := FALSE; // 试验通过单拍脉冲 [-] / the test pass one-scan pulse
    bReqRejected : BOOL := FALSE; // 请求被拒信息级单拍（非空闲相受理）[-] / the request rejected informational pulse
    eHealth      : E_DL_PtsHealth := E_DL_PtsHealth.eGood; // NE107 健康语言出口 [枚举] / the health outlet [enum]
    ePhase       : E_DL_PtsPhase := E_DL_PtsPhase.eIdle; // 相位出口 [枚举] / the phase outlet [enum]
    eFault       : E_DL_PtsFault := E_DL_PtsFault.eNone; // 成因出口，锁存回放 [枚举] / the cause outlet replayed
    bError       : BOOL := FALSE; // 故障锁存标志 [-] / the fault latch flag
END_VAR
VAR
    rtReset  : R_TRIG; // 复位沿检测，段 0 无条件刷新 / the reset edge
    rtReq    : R_TRIG; // 试验请求沿检测，段 0 无条件刷新 / the request edge
    rtFb     : R_TRIG; // 反馈沿检测，段 0 无条件刷新 / the feedback edge
    rtOk     : R_TRIG; // 通过电平沿检测，段 0 无条件刷新 / the pass level edge
    tonPeriod: TON;    // 试验周期窗（自复位 R188），段 0 无条件刷新 / the period window, self resetting
    tonFbTo  : TON;    // 反馈超时窗，段 0 无条件刷新 / the feedback timeout
    tonDur   : TON;    // 试验持续窗，段 0 无条件刷新 / the duration window
    _ePhase  : E_DL_PtsPhase := E_DL_PtsPhase.eIdle; // 内部相位，CASE 唯一写入目标 / the internal phase
    _eFaulC  : E_DL_PtsFault := E_DL_PtsFault.eNone; // 故障级成因，锁存至复位沿 / the fault cause, latched
    _bFault  : BOOL := FALSE; // 故障锁存位 [-] / the fault latch bit
    _bInit   : BOOL := FALSE; // 首扫初始化完成标志（R310）/ the first scan flag
    _bCfgOk  : BOOL := FALSE; // 组态域内 [-] / the config inside the domain
    _bPassed : BOOL := FALSE; // 最近试验通过保持位（复位沿清，R243 最近量）[-] / the latest pass holder, cleared by reset
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支）/ segment 0, the unconditional refresh
rtReset(CLK := bReset); // 复位沿 / the reset edge
rtReq(CLK := bTestReq); // 请求沿 / the request edge
rtFb(CLK := bFeedback); // 反馈沿 / the feedback edge
rtOk(CLK := _bPassed); // 通过电平沿 / the pass level edge
tonPeriod(IN := bEnable AND (_ePhase = E_DL_PtsPhase.eIdle) AND (NOT tonPeriod.Q), PT := tTestPeriod); // 周期窗自复位循环（R188）/ the self resetting period loop
tonFbTo(IN := (_ePhase = E_DL_PtsPhase.eExcite) AND (NOT _bFault), PT := tFeedbackTo); // 反馈超时窗，IN 串激励相闸 / the feedback timeout gated by the excite phase
tonDur(IN := (_ePhase = E_DL_PtsPhase.eEval) AND (NOT _bFault), PT := tTestDur); // 持续窗，IN 串评估相闸 / the duration gated by the eval phase

// 段 1｜首扫初始化（R310）/ segment 1, the first scan
IF NOT _bInit THEN // 首扫一拍 / the first scan
    _bInit := TRUE; // 置首扫标志 / raise the flag
END_IF

// 段 2｜复位沿作用域：清锁存 / 清最近通过量 / 迁空闲（三项逐项声明）/ segment 2, the reset edge scope
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bFault  := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaulC  := E_DL_PtsFault.eNone; // 作用域一：清成因 / scope one, clear the cause
    _bPassed := FALSE; // 作用域二：清最近通过保持量（R243）/ scope two, clear the latest pass holder
    _ePhase  := E_DL_PtsPhase.eIdle; // 作用域三：迁空闲相 / scope three, back to idle
END_IF

// 段 3｜组态域闸：三窗配比（R100，边界一）/ segment 3, the config gate, the window pairing
_bCfgOk := (tTestPeriod > tTestDur) AND (tTestDur > tFeedbackTo) AND (tFeedbackTo > T#0S); // 周期 > 持续 > 反馈超时配比 / the period above duration above timeout pairing
IF NOT _bCfgOk THEN // 配比越域 / a pairing violation
    IF NOT _bFault THEN // 未锁存才迁移 / migrate only while unlatched
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_PtsFault.eCfgBad; // 故障级成因（R45 配对 bError）/ the fault cause
        _ePhase := E_DL_PtsPhase.eFault; // 迁故障相 / migrate to fault
    END_IF
END_IF

// 段 4｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 4, the phase machine
CASE _ePhase OF

E_DL_PtsPhase.eIdle: // 空闲相：请求受理与周期触发 / the idle phase, the request acceptance and the period trigger
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_PtsPhase.eIdle; // 停摆驻留 / dwell
    ELSIF rtReq.Q AND (NOT bDevIdle) THEN // 非空闲相受理请求（边界三）/ a request while not idle
        bReqRejected := TRUE; // 信息级拒绝单拍 / the informational reject pulse
    ELSIF (tonPeriod.Q OR rtReq.Q) AND bDevIdle AND (NOT _bFault) THEN // 周期到或请求沿且空闲 / the period expiry or an accepted request
        _ePhase := E_DL_PtsPhase.eExcite; // 迁激励相 / migrate to excite
    END_IF

E_DL_PtsPhase.eExcite: // 激励相：等反馈沿 / the excite phase, waiting for the feedback edge
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_PtsPhase.eIdle; // 回空闲相 / back to idle
    ELSIF bDeviceFault THEN // 真实故障优先（边界二）/ the real fault first
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_PtsFault.eDeviceFault; // 故障级成因（R45 配对 bError）/ the fault cause
        _ePhase := E_DL_PtsPhase.eFault; // 迁故障相 / migrate to fault
    ELSIF rtFb.Q THEN // 反馈沿到达 / a feedback edge arrived
        _ePhase := E_DL_PtsPhase.eEval; // 迁评估相 / migrate to eval
    ELSIF tonFbTo.Q THEN // 反馈超时 / the feedback timed out
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_PtsFault.eTestFail; // 故障级成因（R45 配对 bError）/ the fault cause
        _ePhase := E_DL_PtsPhase.eFault; // 迁故障相 / migrate to fault
    END_IF

E_DL_PtsPhase.eEval: // 评估相：保持激励到持续窗满再判反馈在位 / the eval phase, the drive held then the verdict
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_PtsPhase.eIdle; // 回空闲相 / back to idle
    ELSIF bDeviceFault THEN // 真实故障优先（边界二）/ the real fault first
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        _eFaulC := E_DL_PtsFault.eDeviceFault; // 故障级成因（R45 配对 bError）/ the fault cause
        _ePhase := E_DL_PtsPhase.eFault; // 迁故障相 / migrate to fault
    ELSIF tonDur.Q THEN // 持续窗满 / the duration expired
        IF bFeedback THEN // 反馈在位判通过 / the feedback held, a pass
            _bPassed := TRUE; // 置最近通过保持量 / raise the pass holder
        ELSE // 反馈脱落判失败 / the feedback dropped, a failure
            _bFault := TRUE; // 置故障锁存 / raise the fault latch
            _eFaulC := E_DL_PtsFault.eTestFail; // 故障级成因（R45 配对 bError）/ the fault cause
            _ePhase := E_DL_PtsPhase.eFault; // 迁故障相 / migrate to fault
        END_IF
        IF NOT _bFault THEN // 通过路径回空闲 / the pass path back to idle
            _ePhase := E_DL_PtsPhase.eIdle; // 回空闲相 / back to idle
        END_IF
    END_IF

E_DL_PtsPhase.eFault: // 故障相：成因锁存，等复位沿；失能也回空闲（解锁路径，R188）/ the fault phase, latched until the reset edge
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_PtsPhase.eIdle; // 回空闲相（锁存仍保持至复位沿）/ back to idle, the latch held until reset
    END_IF

ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_PtsFault.ePhaseBad; // 故障级成因（R45 配对 bError）/ the fault cause
    _ePhase := E_DL_PtsPhase.eFault; // 迁故障相 / migrate to fault
END_CASE

// 段 5｜统一出口 / segment 5, the unified outlet
bTestDrive := (_ePhase = E_DL_PtsPhase.eExcite) OR (_ePhase = E_DL_PtsPhase.eEval); // 激励输出（激励与评估相保持）/ the drive held in excite and eval
bTestActive := bTestDrive; // 试验进行中电平 / the active level
bTestOk := rtOk.Q; // 通过单拍脉冲（沿检测已无条件刷新）/ the pass pulse
IF _bFault THEN // 故障锁存优先 / the fault latch first
    eFault := _eFaulC; // 成因锁存回放（R152）/ the cause replayed
    IF _eFaulC = E_DL_PtsFault.eTestFail THEN // 试验失败映射功能受影响（NE107）/ a test failure maps to check function
        eHealth := E_DL_PtsHealth.eCheckFunction; // 功能受影响 / the check function state
    ELSE // 其余故障映射维护要求 / the other causes to maintenance
        eHealth := E_DL_PtsHealth.eMaintenanceReq; // 维护要求 / the maintenance state
    END_IF
ELSE // 无锁存 / no latch
    eFault := E_DL_PtsFault.eNone; // 无成因 / no cause
    eHealth := E_DL_PtsHealth.eGood; // 健康态 / the good state
END_IF
ePhase := _ePhase; // 相位出口单点映射 / the phase outlet
bError := _bFault; // 故障标志与锁存位同源 / the flag shares the latch
END_FUNCTION_BLOCK
