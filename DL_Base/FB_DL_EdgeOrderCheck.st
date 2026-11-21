(*==============================================================================
 * 组件名称 (Component)  : FB_DL_EdgeOrderCheck
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 两信号 A→B 时序联锁监视：A 必须先于 B 到达，且 A 领先量
 *                         不少于 tMinGap。逐拍判定四类事件：
 *                         ① 正常顺序：B 上升沿时 A 已在位且领先量 >= tMinGap → bOrderOk TRUE；
 *                         ② 间隔不足：B 上升沿时 A 在位但领先量 < tMinGap → 故障级归因 eGapShort；
 *                         ③ 越序：B 上升沿时 A 不在位（B 无 A 前导）→ 故障级归因 eOrder；
 *                         ④ 逆序：B 先到且仍高，A 随后到来 → nReverseCount 递增并锁存故障 eReverse；
 *                         ⑤ 缺回应：A 单独在位超过 tAloneMax 仍未等到 B → 信息级（不锁故障）。
 * 接口     (Interface)  : 输入 bSigA / bSigB 两信号、tMinGap 最小领先间隔、tAloneMax A 单独
 *                         在位上限、bReset 复位电平；输出 bOrderOk 顺序合规镜像、nReverseCount
 *                         逆序累计计数、eState 相位、eCause 成因、bError、nErrId。
 * 边界     (Boundary)   : ① 组态闸：tMinGap <= T#0S 或 tAloneMax <= tMinGap → 故障锁存；
 *                         ② 计数器饱和于 DL_COUNT_MAX 常量（2147483000，留加 1 裕度，不裸数），
 *                            饱和后不再递增（不回绕，避免台账出现负数）并置信息级留痕；
 *                         ③ R_TRIG 两枚 + TON 两枚在段 0 无条件周期刷新，IN 由当拍电平派生；
 *                         ④ 领先量判据读「前拍快照」_bGapMet：B 上升沿当拍 tonGap.IN 已落假，
 *                            Q 会同拍复位，直接读 Q 会结构性漏判（R45 规则 1 ② 同源教训）；
 *                         ⑤ 故障相迁出唯一路径 = bReset 上升沿；⑥ 零全局耦合（无 GVL / 无物理地址）。
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 ∧ bSigA = FALSE ∧ bSigB = FALSE
 *                         （两信号均已回落，全为当拍量，R240 范式）。自证可满足（终审两式 1）：
 *                         解除式不含任何计时器输出，两信号回落即可达，无恒假因子。
 * 码表     (Codes)      : 16#0001_03EB 故障级：时序联锁故障总码（组态非法 / 间隔不足 / 越序 /
 *                         逆序 / 非法相位），锁存至 bReset 上升沿，归因由 eCause 承载；
 *                         16#0001_04AE 信息级：非故障台账事件（A 缺回应 或 逆序计数饱和）。
 *                         加码反证（R90）：缺回应与计数饱和均不改变 bOrderOk / bError / eCause，
 *                         也无专属状态位可观测，故须立一码留痕；二者共用一码的处置依据是
 *                         「都只要求留痕不要求区分动作」，需要区分时由上层比较
 *                         nReverseCount 是否已达饱和常量反推，无需第二码位。
 *                         码段说明：0001 段故障子带 03xx / 信息子带 04xx，本件取 03EB / 04AE
 *                         （源码实扫该两槽为空，续接同子带已用最大值，未回填碎片孔洞）。
 * 开源溯源 (Origin)     : 道莅自研 clean-room（参考现场联锁惯例与参数域，零代码行复制）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R45 首版（批次 1 · 序号 2）
 *==============================================================================*)

TYPE E_DL_EocState :
(
    eIdle  := 0,     // 双信号均低，等待首个事件 / Idle, both signals low
    eRun   := 10,    // 监视运行（至少一路信号在位） / Running, at least one signal active
    eFault := 90     // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_EocCause :
(
    eNone       := 0,   // 无故障成因 / No cause
    eCfgIllegal := 1,   // 组态非法 / Illegal configuration
    eGapShort   := 2,   // 领先间隔不足 / Lead gap too short
    eOrder      := 3,   // 越序（B 无 A 前导） / Out of order, B without preceding A
    eReverse    := 4    // 逆序（B 先到后 A 到达） / Reverse order, B first then A
);
END_TYPE

FUNCTION_BLOCK FB_DL_EdgeOrderCheck
VAR_INPUT
    bSigA     : BOOL := FALSE;          // 领先信号 A（应先到） [-] / Leading signal A, must arrive first
    bSigB     : BOOL := FALSE;          // 跟随信号 B（应后到） [-] / Following signal B, must arrive later
    tMinGap   : TIME := T#50MS;         // A 领先 B 的最小间隔，域 > T#0S [ms] / Minimum A-to-B lead gap
    tAloneMax : TIME := T#2S;           // A 单独在位上限（缺回应判据），域 > tMinGap [ms] / Max A-alone duration
    bReset    : BOOL := FALSE;          // 复位命令，上升沿清故障 [-] / Reset command, rising edge clears fault
END_VAR
VAR_OUTPUT
    bOrderOk      : BOOL;               // 顺序合规镜像（最近一次 B 沿判定结果） [-] / Order compliance mirror
    nReverseCount : DINT;               // 逆序累计计数（锁存量，复位不清零） [次] / Reverse count, latched, not cleared by reset
    eState        : E_DL_EocState;      // 状态出口，段 6 单点映射 / State outlet
    eCause        : E_DL_EocCause;      // 故障成因出口（R190 归因唯一） / Fault cause outlet
    bError        : BOOL;               // 故障锁存标志 [-] / Fault latch flag
    nErrId        : UDINT;              // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    _eState       : E_DL_EocState := E_DL_EocState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause       : E_DL_EocCause := E_DL_EocCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    tonGap        : TON;                // A 领先量计时，段 0 无条件调用 / A lead-gap timer
    tonAlone      : TON;                // A 单独在位计时，段 0 无条件调用 / A-alone duration timer
    rtA           : R_TRIG;             // A 上升沿实例，段 0 无条件调用 / A rising edge
    rtB           : R_TRIG;             // B 上升沿实例，段 0 无条件调用 / B rising edge
    rtReset       : R_TRIG;             // 复位沿实例，段 0 无条件调用 / Reset edge
    _bAlone       : BOOL;               // A 在位且 B 不在位当拍量 [-] / A active while B inactive
    _bGapMet      : BOOL;               // 领先量已满足的前拍快照 [-] / Previous-scan lead-gap satisfied snapshot
    _bCfgBad      : BOOL;               // 组态非法当拍量 [-] / Illegal configuration
    _bFault       : BOOL;               // 故障锁存位（锁存量） / Latched fault bit
    _bOrderOk     : BOOL;               // 顺序合规内部判定（锁存量，供出口映射） / Internal order verdict
    _nReverseCount : DINT;              // 逆序计数内部累计（锁存量，唯一写入点） [次] / Internal reverse counter, single write point [count]
    _uFault       : UDINT;              // 故障码锁存（锁存量） / Latched fault code
    _uInfo        : UDINT;              // 信息码，每拍重算 / Info code, recomputed each scan
END_VAR
VAR CONSTANT
    DL_COUNT_MAX  : DINT := 2147483000; // 逆序计数饱和上限，留安全裕度防加 1 溢出 [次] / Reverse count saturation limit with overflow margin [count]
END_VAR

(* —— 段 0：前拍快照 + 当拍量派生 + 定时器与沿实例无条件周期刷新 —— *)
_bGapMet := tonGap.Q;                                                    // 领先量满足态的前拍快照（B 沿当拍 IN 已落假） / Previous-scan gap-met snapshot
_bAlone  := bSigA AND (NOT bSigB);                                       // A 单独在位当拍量 / A alone this scan
_bCfgBad := (tMinGap <= T#0S) OR (tAloneMax <= tMinGap);                 // 组态非法当拍量 / Illegal configuration
rtA(CLK := bSigA);                                                       // A 上升沿，每拍必调（R228A） / A rising edge, called every scan
rtB(CLK := bSigB);                                                       // B 上升沿，每拍必调 / B rising edge, called every scan
rtReset(CLK := bReset);                                                  // 复位沿，每拍必调 / Reset edge, called every scan
tonGap(IN := _bAlone, PT := tMinGap);                                    // 领先量计时 / Lead-gap timer
tonAlone(IN := _bAlone, PT := tAloneMax);                                // A 单独在位计时 / A-alone timer

(* —— 段 1：单拍量预清零（锁存量与快照量不入清单，R107） —— *)
_uInfo    := 16#0000_0000;         // 信息码每拍重算 / Info recomputed every scan
nErrId    := 16#0000_0000;         // 事件码缺省无事件 / Event code default none
bError    := FALSE;                // 故障标志每拍预清，由故障分支同拍置位（R45 配对） / Flag preset
bOrderOk  := _bOrderOk;            // 顺序镜像由锁存判定派生（名实同源，R191） / Order mirror from latched verdict

(* —— 段 2：复位沿 + 组态域闸 —— *)
IF rtReset.Q THEN                                                        // 当拍复位沿 / current-scan reset edge
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_EocCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
    IF _eState = E_DL_EocState.eFault THEN
        _eState := E_DL_EocState.eIdle;                                  // 故障相迁出唯一路径 / Sole exit from fault phase
    END_IF
END_IF
IF _bCfgBad THEN                                                         // 组态域闸 / Configuration gate
    _uFault := 16#0001_03EB;                                             // 故障级：时序联锁故障总码 / Fault-level: order-check fault code
    _bFault := TRUE;                                                     // 锁存置位 / Latch set
    bError  := TRUE;                                                     // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_EocCause.eCfgIllegal;                                // 归因：组态非法 / Cause: illegal configuration
END_IF

(* —— 段 3：顺序判据（B 沿受理 / A 沿逆序判定 / 缺回应信息级） —— *)
IF (NOT _bFault) AND rtB.Q THEN                                          // B 上升沿受理 / B rising edge accepted
    IF bSigA THEN                                                        // A 仍在位：检查领先量 / A is active, check lead gap
        IF _bGapMet THEN
            _bOrderOk := TRUE;                                           // 顺序合规（锁存量） / Order OK, latched verdict
        ELSE
            _uFault := 16#0001_03EB;
            _bFault := TRUE;
            bError  := TRUE;
            _eCause := E_DL_EocCause.eGapShort;                          // 归因：领先间隔不足 / Cause: lead gap too short
            _bOrderOk := FALSE;                                          // 锁存量置违规 / Latched verdict violation
        END_IF
    ELSE
        _uFault := 16#0001_03EB;
        _bFault := TRUE;
        bError  := TRUE;
        _eCause := E_DL_EocCause.eOrder;                                 // 归因：越序（B 无 A 前导） / Cause: out of order
        _bOrderOk := FALSE;                                              // 锁存量置违规 / Latched verdict violation
    END_IF
END_IF
IF (NOT _bFault) AND rtA.Q AND bSigB THEN                                // A 在 B 仍高时到来 = 逆序 / A arrives while B still high
    IF _nReverseCount < DL_COUNT_MAX THEN
        _nReverseCount := _nReverseCount + 1;                            // 逆序计数递增（单点写入） / Reverse count increment, single write point
    ELSE
        _uInfo := 16#0001_04AE;                                          // 信息级：计数饱和留痕，不回绕 / Info: saturation recorded, no wrap
    END_IF
    _uFault := 16#0001_03EB;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_EocCause.eReverse;                                   // 归因：逆序 / Cause: reverse order
    _bOrderOk := FALSE;                                                  // 锁存量置违规 / Latched verdict violation
END_IF
IF (NOT _bFault) AND tonAlone.Q THEN                                     // A 单独在位超上限 → 缺回应（信息级，不锁故障） / A alone too long, info level
    _uInfo := 16#0001_04AE;
END_IF

(* —— 段 4：故障解除式（R240 全当拍量） —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT bSigA) AND (NOT bSigB) THEN
    _bFault := FALSE;                                                    // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                             // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_EocCause.eNone;                                      // 清成因（锁存量） / Clear latched cause
END_IF

(* —— 段 4A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_EocState.eFault) THEN
    _eState := E_DL_EocState.eFault;                                     // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 5：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_EocState.eIdle:
    IF bSigA OR bSigB THEN                                               // 出口 1：任一信号动作 / Any signal active
        _eState := E_DL_EocState.eRun;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_EocState.eFault;
    END_IF

E_DL_EocState.eRun:
    IF (NOT bSigA) AND (NOT bSigB) THEN                                  // 出口 1：两信号均回落 / Both signals released
        _eState := E_DL_EocState.eIdle;
    ELSIF _bFault THEN                                                   // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_EocState.eFault;
    END_IF

E_DL_EocState.eFault:
    ;                                                                     // 故障相：仅段 4 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _uFault := 16#0001_03EB;                                             // 故障级：非法相位兜底（归并总码） / Illegal-phase fallback
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_EocCause.eCfgIllegal;                                // 归因：相位非法归并组态 / Cause: phase illegal
    _eState := E_DL_EocState.eFault;

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放） —— *)
nReverseCount := _nReverseCount;                                         // 逆序计数出口（锁存量回放） / Reverse count outlet
IF _bFault THEN
    bOrderOk := FALSE;                                                   // 故障相强制违规镜像 / Fault forces violation mirror
    nErrId   := _uFault;                                                 // 故障锁存码回放 / Replay latched fault code
ELSE
    nErrId   := _uInfo;                                                  // 信息码 / Info code
END_IF
bError := _bFault;                                                       // 故障标志与锁存同源（名实双出口，R191） / Flag from latch
eState := _eState;                                                       // 状态出口 / State outlet
eCause := _eCause;                                                       // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
