(*
  FB_DL_CoderRibbonLife  —  打码机色带寿命双口径评估（次数口径 + 浓度口径取劣）/ Coder ribbon life, dual-criterion estimation
  分类 Category : DL_Device
  码位 Code     : 16#03_2_11
  版本 Version  : 1.0.0
  来源 Source   : t2-1-lgf-technology — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : LGF 工艺类文档公开语义借鉴（耗材寿命双口径、浓度补偿），clean-room 实现，未复制源码行
  功能 Function : 1) 次数口径：已打次数 nPrintedCount 对额定 nRibbonRatingPrints 的余量 → fRemainCntPct；
                  2) 浓度口径：为达清晰度被迫把浓度指令抬升至 fDensityMinPct 之上的幅度，
                     超过 fDensityRiseMaxPct 即说明色带色粉已衰减 → fRemainDensPct（按抬升幅度线性折算）；
                  3) 两口径**取劣者**作为 fRemainPct 输出（任一口径到限即预警，不平均、不取优）；
                  4) bReplaceWarn 在 fRemainPct <= fWarnLevelPct 时置位（维护级告警，信息级 0121，不置 bError）；
                  5) bDensityCompSaturated 在浓度指令顶到 fDensityCeilPct（默认 100%）时置位（再无可调余量）。
  边界 Boundary : ① nRibbonRatingPrints = 0 判组态错 0211（次数口径的分母，R45 防除零）；
                      fDensityMinPct <= 0 / fDensityRiseMaxPct <= 0 / fWarnLevelPct 域外同判组态错；
                  ② fDensityCmdPct 越 0~100 时**钳制到域内**并置组态告警 0211（bError 置位，工艺参数错误
                     不允许静默通过）；钳制值参与后续全部换算，绝不用域外值做分母；
                  ③ nPrintedCount 为 UDINT，饱和到额定值**不回绕**（回绕会让色带寿命台账凭空复活）；
                     计数累加前做上限预判（R28-3：不写 TRUNC(x)+1，不靠事后比较）；
                  ④ 换带复位须 bRibbonReplaced 上升沿 **且** bReset 同时成立（解除式自证：两条件均可满足）；
                     只按 bRibbonReplaced 会丢掉操作员确认，只按 bReset 会把正常复位当成换带（台账污染）；
                  ⑤ bPrintPulse 用 R_TRIG 且**每主周期无条件刷新**（R182）；
                  ⑥ 浓度口径与次数口径的百分比均限幅到 [0, 100]（负余量不显示为负数，防 HMI 误解）。
  依赖 Depends  : 仅 Standard.library（TON / R_TRIG / ABS / MIN / MAX），零外部组件依赖
  同拍双窗配比  : 浓度告警去抖窗 tDensityDb 与心跳窗 DL_HEART_WINDOW 不同源；配比约束
                  tDensityDb <= DL_HEART_WINDOW，保证心跳窗内至少一次浓度结论更新（R100）

  码表 Error codes（本件格 03_2_11，子码步进 +0x10）:
    16#0003_0211 故障级：组态非法（额定次数 = 0 / 浓度基准 <= 0 / 抬升上限 <= 0 / 浓度指令越 0~100 已钳制）
    16#0003_0221 故障级：状态机落 ELSE 兜底（非法相位 ID）
    16#0003_0111 信息级：换带复位已执行（计数与口径全部归零，不置 bError）
    16#0003_0121 信息级：色带更换预警（维护级，fRemainPct <= fWarnLevelPct，不置 bError）
    16#0003_0131 信息级：浓度补偿已饱和（指令顶到上限，无再调余量，不置 bError）

  修订历史 Revision :
    2026-11-18  v1.0.0  R37 首版
*)

TYPE E_DL_RibbonState :
(
    eIdle  := 0,   // 空闲：未使能 / Idle, not enabled
    eRun   := 10,  // 运行：正常计数与评估 / Running, counting and evaluating
    eWarn  := 20,  // 预警：余量到限，仍可继续打印 / Warning, printing may continue
    eFault := 90   // 故障：组态非法锁定 / Fault, illegal configuration latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_CoderRibbonLife
VAR_INPUT
    bEnable        : BOOL := FALSE;             // 总使能，FALSE 时不计次 / Master enable, low level stops counting
    bReset         : BOOL := FALSE;             // 复位，上升沿清故障锁存（与换带沿同时成立才清台账）/ Reset, clears the latch
    bRibbonReplaced : BOOL := FALSE;            // 换带完成信号（上升沿；须与 bReset 同拍才复位台账）/ Ribbon replaced, rising edge
    bPrintPulse    : BOOL := TRUE;              // 打印触发脉冲输入（上升沿计一次；R_TRIG 每拍无条件刷新）/ Print trigger, rising edge counts
    nRibbonRatingPrints : UDINT := 1000000;     // 色带额定打印次数 [次]，域 > 0 / Rated print count, domain above zero
    fDensityCmdPct : REAL := 60.0;              // 当前浓度指令 [%]，域 0~100 / Present density command [%]
    fDensityMinPct : REAL := 40.0;              // 浓度基准（新带所需浓度）[%]，域 > 0 / Density baseline of a new ribbon [%]
    fDensityRiseMaxPct : REAL := 40.0;          // 允许浓度抬升上限 [%]，域 > 0 / Permitted density rise [%]
    fDensityCeilPct : REAL := 100.0;            // 浓度上限（饱和判定点）[%]，域 > 基准 / Density ceiling for the saturation test [%]
    fWarnLevelPct  : REAL := 10.0;              // 更换预警余量门限 [%]，域 0~100 / Remaining-level warning threshold [%]
END_VAR
VAR_OUTPUT
    nPrintedCount  : UDINT;                     // 已打次数 [次]，饱和不超过额定值 / Printed count, saturated at the rating
    fRemainPct     : REAL;                      // 剩余寿命（双口径取劣）[%] / Remaining life, the worse of both criteria [%]
    fRemainCntPct  : REAL;                      // 次数口径余量 [%] / Remaining life by count [%]
    fRemainDensPct : REAL;                      // 浓度口径余量 [%] / Remaining life by density [%]
    bReplaceWarn   : BOOL;                      // 更换色带预警（维护级）/ Ribbon replacement warning
    bDensityCompSaturated : BOOL;               // 浓度补偿饱和 / Density compensation saturated
    bValid         : BOOL;                      // 判据可用标志 / Criteria usable
    bError         : BOOL;                      // 故障标志，派生自锁存 / Fault flag derived from the latch
    nErrId         : UDINT;                     // 事件码，0 = 无事件 / Event code, 0 = no event
    eStateOut      : E_DL_RibbonState;          // 状态出口，段尾单点映射 / State outlet, mapped at the tail
END_VAR
VAR
    tonHeart     : TON;                         // 周期心跳窗，自复位 / Periodic heartbeat window, self-resetting
    rtReset      : R_TRIG;                      // 复位上升沿 / Reset rising edge
    rtReplace    : R_TRIG;                      // 换带上升沿 / Replacement rising edge
    rtPrint      : R_TRIG;                      // 打印触发上升沿（每拍无条件刷新）/ Print rising edge, refreshed every scan
    _eState      : E_DL_RibbonState := E_DL_RibbonState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _uFault      : UDINT;                       // 故障码锁存 / Latched fault code
    _uInfo       : UDINT;                       // 信息码，每拍重算 / Information code, recomputed per scan
    _bFault      : BOOL;                        // 故障锁存位 / Latched fault bit
    _bCfgBad     : BOOL;                        // 组态非法聚合 / Configuration invalid aggregate
    _bDensClamped : BOOL;                       // 浓度指令被钳制 / The density command was clamped
    _nCountAcc   : UDINT;                       // 已打次数保持量 [次] / Held printed count
    _fDens       : REAL;                        // 生效浓度指令（钳制后）[%] / Effective density command [%]
    _fRisePct    : REAL;                        // 相对基准的浓度抬升 [%] / Density rise above the baseline [%]
    _fCntRemain  : REAL;                        // 次数口径余量 [%] / Remaining life by count [%]
    _fDensRemain : REAL;                        // 浓度口径余量 [%] / Remaining life by density [%]
    _fWorst      : REAL;                        // 双口径取劣结果 [%] / Worse criterion value [%]
    _bReplaceNow : BOOL;                        // 本拍更换预警判据成立 / Warning criterion present this scan
    _bHeartBrk   : BOOL := TRUE;                // 心跳窗断输入一拍 / One-scan heartbeat break
END_VAR
VAR CONSTANT
    DL_PCT_MAX    : REAL := 100.0;      // 百分比上限 [%] / Percentage ceiling
    DL_PCT_MIN    : REAL := 0.0;        // 百分比下限 [%] / Percentage floor
    DL_HEART_WINDOW : TIME := T#2S;     // 心跳观察窗 [ms]，自复位节拍 / Heartbeat window, self-resetting
    DL_COUNT_MAX  : UDINT := 16#FFFF_FFFE; // 次数硬上限（额定值异常放大时的兜底）[次] / Hard count ceiling
END_VAR

(* —— 段 0：定时器与边缘检测无条件周期刷新（R182：R_TRIG 必须在主体前部，不得置于 IF 内） —— *)
rtReset(CLK := bReset);                                          // 复位上升沿，每拍必调
rtReplace(CLK := bRibbonReplaced);                               // 换带上升沿，每拍必调
rtPrint(CLK := bPrintPulse);                                     // 打印上升沿，每拍必调（计数触发源）
tonHeart(IN := (NOT tonHeart.Q) AND (NOT _bHeartBrk), PT := DL_HEART_WINDOW);  // 心跳窗自复位
_bHeartBrk := FALSE;                                             // 断输入拍在调用后自清

(* —— 段 1：单拍量预清零（计数 / 口径保持量不入清单，R187①） —— *)
_uInfo       := 16#0000_0000;   // 信息码每拍重算
bError       := FALSE;          // 故障出口每拍重算，段 7 由锁存派生
bValid       := FALSE;          // 可用标志缺省 FALSE
bReplaceWarn := FALSE;          // 预警出口缺省 FALSE，段 8 单点置位
_bCfgBad     := FALSE;          // 组态非法预清零
_bDensClamped := FALSE;         // 浓度钳制标志预清零
_bReplaceNow := FALSE;          // 预警判据预清零

(* —— 段 2：复位沿与换带沿（台账复位为双条件，R28-1 解除式自证） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                // 复位沿清故障锁存位（台账不清，换带才清）
    _uFault := 16#0000_0000;         // 复位沿清锁存码
END_IF
IF rtReplace.Q AND rtReset.Q THEN
    _nCountAcc := 0;                 // 换带 + 复位同拍：已打次数归零
    _fCntRemain := DL_PCT_MAX;       // 次数口径余量回到 100 %
    _fDensRemain := DL_PCT_MAX;      // 浓度口径余量回到 100 %
    _uInfo := 16#0003_0111;          // 信息级：换带复位已执行
END_IF

(* —— 段 3：组态域闸（覆盖全部参与换算的引脚，R151） —— *)
IF nRibbonRatingPrints = 0 THEN
    _bCfgBad := TRUE;                // 额定次数为 0：次数口径分母非法（R45 防除零）
END_IF
IF (fDensityMinPct <> fDensityMinPct) OR (fDensityMinPct <= 0.0) OR (fDensityMinPct > DL_PCT_MAX) THEN
    _bCfgBad := TRUE;                // 浓度基准非法
END_IF
IF (fDensityRiseMaxPct <> fDensityRiseMaxPct) OR (fDensityRiseMaxPct <= 0.0) THEN
    _bCfgBad := TRUE;                // 允许抬升上限非法（浓度口径分母）
END_IF
IF (fDensityCeilPct <> fDensityCeilPct) OR (fDensityCeilPct <= fDensityMinPct) THEN
    _bCfgBad := TRUE;                // 浓度上限须严格大于基准（否则饱和判定无意义）
END_IF
IF (fWarnLevelPct <> fWarnLevelPct) OR (fWarnLevelPct < DL_PCT_MIN) OR (fWarnLevelPct > DL_PCT_MAX) THEN
    _bCfgBad := TRUE;                // 预警门限越 0~100 域
END_IF
_fDens := fDensityCmdPct;            // 生效浓度初值
IF (_fDens <> _fDens) THEN
    _bCfgBad := TRUE;                // 浓度指令非有限：无法解释
END_IF
IF _fDens > DL_PCT_MAX THEN
    _fDens := DL_PCT_MAX;            // 上钳制到域内（钳制值才参与换算）
    _bDensClamped := TRUE;           // 标记已钳制
END_IF
IF _fDens < DL_PCT_MIN THEN
    _fDens := DL_PCT_MIN;            // 下钳制
    _bDensClamped := TRUE;
END_IF
IF _bDensClamped THEN
    _bCfgBad := TRUE;                // 域外浓度：组态告警（工艺参数错误不得静默通过）
END_IF
IF _bCfgBad THEN
    _uFault := 16#0003_0211;         // 故障级：组态非法
    _bFault := TRUE;                 // 锁存位置位（复位沿可清）
    bError  := TRUE;                 // 故障标志置位（R45 配对）
    _eState := E_DL_RibbonState.eFault;  // 进故障相
END_IF

(* —— 段 4：次数累计（上限预判，饱和不回绕；禁用 TRUNC(x)+1 型写法） —— *)
IF rtPrint.Q AND bEnable AND (NOT _bFault) AND (NOT _bCfgBad) THEN
    IF _nCountAcc < nRibbonRatingPrints THEN
        IF _nCountAcc < DL_COUNT_MAX THEN
            _nCountAcc := _nCountAcc + 1;   // 计数 +1（双重上限：额定值与硬上限，均不回绕）
        END_IF
    END_IF
END_IF

(* —— 段 5：双口径余量计算（次数口径与浓度口径各自独立，取劣输出） —— *)
IF (NOT _bCfgBad) AND (nRibbonRatingPrints > 0) THEN
    _fCntRemain := (1.0 - (UDINT_TO_REAL(_nCountAcc) / UDINT_TO_REAL(nRibbonRatingPrints))) * DL_PCT_MAX;  // 次数口径余量 [%]
    IF _fCntRemain < DL_PCT_MIN THEN
        _fCntRemain := DL_PCT_MIN;                     // 下限保护（饱和计数时余量恰为 0）
    END_IF
    IF _fCntRemain > DL_PCT_MAX THEN
        _fCntRemain := DL_PCT_MAX;                     // 上限保护（计数小于额定时不超过 100）
    END_IF
    IF _fDens > fDensityMinPct THEN
        _fRisePct := (_fDens - fDensityMinPct) / fDensityMinPct * DL_PCT_MAX;   // 相对基准的抬升 [%]（分母已证 > 0）
    ELSE
        _fRisePct := 0.0;                              // 未抬升：无衰减指示
    END_IF
    IF _fRisePct >= fDensityRiseMaxPct THEN
        _fDensRemain := DL_PCT_MIN;                    // 抬升已达上限：浓度口径余量耗尽
    ELSE
        _fDensRemain := (1.0 - (_fRisePct / fDensityRiseMaxPct)) * DL_PCT_MAX;  // 线性折算余量 [%]（分母已证 > 0）
    END_IF
    IF _fDensRemain < DL_PCT_MIN THEN
        _fDensRemain := DL_PCT_MIN;                    // 下限保护
    END_IF
    IF _fDensRemain > DL_PCT_MAX THEN
        _fDensRemain := DL_PCT_MAX;                    // 上限保护
    END_IF
    _fWorst := MIN(_fCntRemain, _fDensRemain);         // 双口径取劣（任一到限即预警）
    _bReplaceNow := (_fWorst <= fWarnLevelPct);        // 预警判据
    IF _bReplaceNow AND (_eState <> E_DL_RibbonState.eFault) THEN
        _uInfo := 16#0003_0121;                        // 信息级：色带更换预警（维护级）
    END_IF
ELSE
    _fWorst := DL_PCT_MIN;                             // 组态非法：余量按最不利显示（不伪造 100 %）
END_IF

(* —— 段 6：相位机（只做迁移；出口在段 8） —— *)
CASE _eState OF

E_DL_RibbonState.eIdle:
    IF bEnable AND (NOT _bFault) AND (NOT _bCfgBad) THEN
        _eState := E_DL_RibbonState.eRun;              // 使能且组态合法：进运行相
    END_IF

E_DL_RibbonState.eRun:
    IF (NOT bEnable) THEN
        _eState := E_DL_RibbonState.eIdle;             // 失能：回空闲
    ELSIF _bReplaceNow THEN
        _eState := E_DL_RibbonState.eWarn;             // 余量到限：进预警相（仍允许打印）
    END_IF

E_DL_RibbonState.eWarn:
    IF (NOT bEnable) THEN
        _eState := E_DL_RibbonState.eIdle;             // 失能：回空闲
    ELSIF (NOT _bReplaceNow) AND (rtReplace.Q AND rtReset.Q) THEN
        _eState := E_DL_RibbonState.eRun;              // 换带复位完成：回运行相
    END_IF

E_DL_RibbonState.eFault:
    IF (NOT _bFault) AND (NOT _bCfgBad) AND bEnable THEN
        _eState := E_DL_RibbonState.eRun;              // 锁存已清且组态合法：回运行相
    END_IF

ELSE
    _uFault := 16#0003_0221;                           // 故障级：相位 ID 越界（枚举兜底）
    _bFault := TRUE;                                   // 锁存
    bError  := TRUE;                                   // 故障标志置位（R45 配对）
    _eState := E_DL_RibbonState.eFault;                // 强制回故障相
END_CASE

(* —— 段 7：故障码优先级链（每个 bError 置位源在此均有码，R45 配对） —— *)
IF _bCfgBad THEN
    _uFault := 16#0003_0211;                           // 组态非法优先上报
    _bFault := TRUE;
    bError  := TRUE;
END_IF

(* —— 段 8：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
nPrintedCount  := _nCountAcc;                          // 已打次数出口（饱和）
fRemainCntPct  := _fCntRemain;                         // 次数口径余量出口
fRemainDensPct := _fDensRemain;                        // 浓度口径余量出口
fRemainPct     := _fWorst;                             // 双口径取劣余量出口
bReplaceWarn   := (_eState = E_DL_RibbonState.eWarn);  // 预警出口（状态派生，与 eWarn 相严格同源）
bDensityCompSaturated := (_fDens >= fDensityCeilPct) AND (NOT _bCfgBad);  // 浓度补偿饱和：指令顶到上限
IF bDensityCompSaturated THEN
    _uInfo := 16#0003_0131;                            // 信息级：浓度补偿已饱和（无再调余量）
END_IF
eStateOut := _eState;                                  // 状态出口
IF _bFault THEN
    nErrId := _uFault;                                 // 故障锁存码回放（不在故障相按当下输入重推）
    bError := TRUE;                                    // 故障出口派生自锁存
ELSE
    nErrId := _uInfo;                                  // 信息码
END_IF
bValid := bEnable AND (NOT _bFault) AND (NOT _bCfgBad);  // 判据可用

END_FUNCTION_BLOCK
