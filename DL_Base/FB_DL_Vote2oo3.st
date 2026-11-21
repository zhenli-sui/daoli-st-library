(*==============================================================================
 * 组件名称 (Component)  : FB_DL_Vote2oo3
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 三通道二取二表决（2oo3）。逐拍统计健康通道数 nHealthy 与
 *                         健康通道中为真的个数 nTrue：
 *                         ① nHealthy >= 3 → 三取二多数表决（2/3 即通过）；
 *                         ② nHealthy = 2 → 降级 1oo2，两健康通道一致才通过，不一致判失配；
 *                         ③ nHealthy <= 1 → 健康数不足，输出保守 FALSE 并置故障；
 *                         ④ 失配须连续维持 tMismatchTime（默认 T#300MS）才判故障，
 *                            消除单拍抖动造成的误判（确认窗消除法）。
 *                         输出同意数 nAgreeCount = 多数派票数 = MAX(nTrue, nHealthy - nTrue)。
 * 接口     (Interface)  : 输入 bCh1/bCh2/bCh3 三通道原始值、bHealthy1/bHealthy2/bHealthy3
 *                         通道健康位、tMismatchTime 失配确认时间、tConfirmTime 健康数不足
 *                         确认时间、bReset 复位电平；输出 bOut 表决结果、nAgreeCount 同意数、
 *                         eState 相位、eCause 成因、bError 故障标志、nErrId 事件码。
 * 边界     (Boundary)   : ① 组态闸：tMismatchTime <= T#0S 或 tConfirmTime <= T#0S → 故障锁存；
 *                         ② 安全侧：任何故障相 bOut 强制 FALSE（保守关断侧），nAgreeCount 置 0；
 *                         ③ TON 两枚 + R_TRIG 一枚在段 0 无条件周期刷新，IN 由当拍判据派生；
 *                         ④ 故障相迁出唯一路径 = bReset 上升沿；⑤ 零全局耦合（无 GVL / 无物理地址）。
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 ∧ tonMismatch.Q = FALSE ∧
 *                         tonInsuff.Q = FALSE ∧ nHealthy >= 2（全为当拍量，R240 范式）。
 *                         自证可满足（终审两式 1）：故障相下两枚 TON 的 IN 仍由当拍判据
 *                         派生，三通道恢复一致且健康数恢复 >= 2 时两 Q 必落假，解除式必可达。
 * 码表     (Codes)      : 16#0001_03EA 故障级：表决故障总码（组态非法 / 通道失配 / 健康数不足），
 *                         锁存至 bReset 上升沿，归因由 eCause 独立成员承载（R190 单件单总码）；
 *                         16#0001_04AD 信息级：降级 1oo2 表决中（健康数恰为 2，无故障）。
 *                         加码反证（R90）：降级 1oo2 与「三通道全健康」在 bOut/nAgreeCount 上
 *                         可同值（nHealthy=2 且一致时 nAgreeCount=2），但二者故障处置不同，
 *                         现有输出组合无法唯一还原「当前仅两通道可信」，故立此信息码。
 *                         码段说明：0001 段故障子带 03xx / 信息子带 04xx，本件取 03EA / 04AD
 *                         （源码实扫该两槽为空，续接同子带已用最大值，未回填碎片孔洞）。
 * 开源溯源 (Origin)     : 道莅自研 clean-room（参考 2oo3 表决结构惯例与参数域，零代码行复制）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R45 首版（批次 1 · 序号 1）
 *==============================================================================*)

TYPE E_DL_V23State :
(
    eIdle  := 0,     // 未使能待运行（健康通道数不足前不输出） / Idle, not enough healthy channels
    eRun   := 10,    // 表决运行 / Voting in progress
    eFault := 90     // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_V23Cause :
(
    eNone       := 0,   // 无故障成因 / No cause
    eCfgIllegal := 1,   // 组态非法 / Illegal configuration
    eMismatch   := 2,   // 健康通道表决失配（确认时间到） / Healthy channels mismatch confirmed
    eInsuff     := 3    // 健康通道数不足（<= 1） / Insufficient healthy channels
);
END_TYPE

FUNCTION_BLOCK FB_DL_Vote2oo3
VAR_INPUT
    bCh1          : BOOL := FALSE;            // 通道 1 原始值 [-] / Channel 1 raw value
    bCh2          : BOOL := FALSE;            // 通道 2 原始值 [-] / Channel 2 raw value
    bCh3          : BOOL := FALSE;            // 通道 3 原始值 [-] / Channel 3 raw value
    bHealthy1     : BOOL := TRUE;             // 通道 1 健康位，FALSE 表示该通道不参与表决 [-] / Channel 1 health, FALSE excludes it
    bHealthy2     : BOOL := TRUE;             // 通道 2 健康位，FALSE 表示该通道不参与表决 [-] / Channel 2 health, FALSE excludes it
    bHealthy3     : BOOL := TRUE;             // 通道 3 健康位，FALSE 表示该通道不参与表决 [-] / Channel 3 health, FALSE excludes it
    tMismatchTime : TIME := T#300MS;          // 失配确认时间，域 > T#0S [ms] / Mismatch confirm time, domain > T#0S
    tConfirmTime  : TIME := T#500MS;          // 健康数不足确认时间，域 > T#0S [ms] / Insufficient-health confirm time
    bReset        : BOOL := FALSE;            // 复位命令，上升沿清故障 [-] / Reset command, rising edge clears fault
END_VAR
VAR_OUTPUT
    bOut          : BOOL;                     // 表决结果，故障相强制 FALSE（安全侧） [-] / Voting result, forced FALSE in fault
    nAgreeCount   : INT;                      // 多数派同意票数 [票] / Majority agreement count [votes]
    eState        : E_DL_V23State;            // 状态出口，段 6 单点映射 / State outlet, single mapping point
    eCause        : E_DL_V23Cause;            // 故障成因出口（R190 归因唯一） / Fault cause outlet
    bError        : BOOL;                     // 故障锁存标志 [-] / Fault latch flag
    nErrId        : UDINT;                    // 事件码，0 = 无事件 / Event code, 0 = no event
END_VAR
VAR
    _eState       : E_DL_V23State := E_DL_V23State.eIdle;      // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause       : E_DL_V23Cause := E_DL_V23Cause.eNone;      // 故障成因锁存（锁存量） / Latched cause
    tonMismatch   : TON;                      // 失配确认计时，段 0 无条件调用 / Mismatch confirm timer
    tonInsuff     : TON;                      // 健康数不足确认计时，段 0 无条件调用 / Insufficient-health timer
    rtReset       : R_TRIG;                   // 复位沿实例，段 0 无条件调用 / Reset edge instance
    _nHealthy     : INT;                      // 健康通道数当拍量 [路] / Healthy channel count this scan
    _nTrue        : INT;                      // 健康通道中为真的个数当拍量 [路] / TRUE count among healthy channels
    _bDisagree    : BOOL;                     // 健康通道失配当拍量 [-] / Healthy channels disagree
    _bInsuff      : BOOL;                     // 健康数不足当拍量 [-] / Insufficient healthy channels
    _bCfgBad      : BOOL;                     // 组态非法当拍量 [-] / Illegal configuration
    _bFault       : BOOL;                     // 故障锁存位（锁存量） / Latched fault bit
    _uFault       : UDINT;                    // 故障码锁存（锁存量） / Latched fault code
    _uInfo        : UDINT;                    // 信息码，每拍重算 / Info code, recomputed each scan
END_VAR

(* —— 段 0：当拍判据派生 + 定时器与沿实例无条件周期刷新 —— *)
_nHealthy := 0;                                                              // 健康计数起点 0 / Healthy count start
_nTrue    := 0;                                                              // 真票计数起点 0 / TRUE vote count start
IF bHealthy1 THEN                                                            // 通道 1 健康则纳入 / Channel 1 counted if healthy
    _nHealthy := _nHealthy + 1;                                              // 健康数累加 / Accumulate healthy count
    IF bCh1 THEN
        _nTrue := _nTrue + 1;                                                // 真票累加 / Accumulate TRUE vote
    END_IF
END_IF
IF bHealthy2 THEN                                                            // 通道 2 健康则纳入 / Channel 2 counted if healthy
    _nHealthy := _nHealthy + 1;
    IF bCh2 THEN
        _nTrue := _nTrue + 1;
    END_IF
END_IF
IF bHealthy3 THEN                                                            // 通道 3 健康则纳入 / Channel 3 counted if healthy
    _nHealthy := _nHealthy + 1;
    IF bCh3 THEN
        _nTrue := _nTrue + 1;
    END_IF
END_IF
_bDisagree := (_nHealthy >= 2) AND (_nTrue > 0) AND (_nTrue < _nHealthy);     // 健康通道内既有真也有假即失配 / Disagreement inside healthy set
_bInsuff   := (_nHealthy <= 1);                                               // 健康数 <= 1 即不足 / Less than two healthy channels
_bCfgBad   := (tMismatchTime <= T#0S) OR (tConfirmTime <= T#0S);              // 组态非法当拍量 / Illegal configuration this scan
rtReset(CLK := bReset);                                                      // 复位沿，每拍必调（R228A） / Reset edge, called every scan
tonMismatch(IN := _bDisagree, PT := tMismatchTime);                          // 失配确认计时 / Mismatch confirm timer
tonInsuff(IN := _bInsuff, PT := tConfirmTime);                               // 健康数不足确认计时 / Insufficient-health timer

(* —— 段 1：单拍量预清零（锁存量与 TON/R_TRIG 实例不入清单，R107） —— *)
_uInfo      := 16#0000_0000;          // 信息码每拍重算 / Info recomputed every scan
bOut        := FALSE;                 // 表决结果缺省 FALSE（安全侧） / Result default FALSE, safe side
nAgreeCount := 0;                     // 同意数缺省 0 / Agreement count default 0
nErrId      := 16#0000_0000;          // 事件码缺省无事件 / Event code default none
bError      := FALSE;                 // 故障标志每拍预清，由故障分支同拍置位（R45 配对） / Flag preset, set by fault branch

(* —— 段 2：复位沿 + 组态域闸 —— *)
IF rtReset.Q THEN                                                    // rtReset.Q 为当拍量 / current-scan edge
    _bFault := FALSE;                                                // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                         // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_V23Cause.eNone;                                  // 清成因（锁存量） / Clear latched cause
    IF _eState = E_DL_V23State.eFault THEN
        _eState := E_DL_V23State.eIdle;                              // 故障相迁出唯一路径 / Sole exit from fault phase
    END_IF
END_IF
IF _bCfgBad THEN                                                     // 组态域闸 / Configuration gate
    _uFault := 16#0001_03EA;                                         // 故障级：表决故障总码 / Fault-level: voting fault code
    _bFault := TRUE;                                                 // 锁存置位 / Latch set
    bError  := TRUE;                                                 // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_V23Cause.eCfgIllegal;                            // 归因：组态非法 / Cause: illegal configuration
END_IF

(* —— 段 3：失配与健康数不足（确认窗到时才判，消除单拍抖动） —— *)
IF (NOT _bFault) AND tonMismatch.Q THEN                              // 失配确认窗到 / Mismatch confirm elapsed
    _uFault := 16#0001_03EA;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_V23Cause.eMismatch;                              // 归因：通道失配 / Cause: channel mismatch
END_IF
IF (NOT _bFault) AND tonInsuff.Q THEN                                // 健康数不足确认窗到 / Insufficient-health elapsed
    _uFault := 16#0001_03EA;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_V23Cause.eInsuff;                                // 归因：健康数不足 / Cause: insufficient health
END_IF

(* —— 段 4：故障解除式（R240 全当拍量） —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT tonMismatch.Q) AND (NOT tonInsuff.Q) AND (_nHealthy >= 2) THEN
    _bFault := FALSE;                                                // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                                         // 清故障锁存码（锁存量） / Clear latched code
    _eCause := E_DL_V23Cause.eNone;                                  // 清成因（锁存量） / Clear latched cause
END_IF

(* —— 段 4A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_V23State.eFault) THEN                // 锁存即入故障相 / Latch enters fault phase
    _eState := E_DL_V23State.eFault;
END_IF

(* —— 段 5：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_V23State.eIdle:
    IF (_nHealthy >= 2) AND (NOT _bFault) THEN                        // 出口 1：健康通道恢复 / Enough healthy channels
        _eState := E_DL_V23State.eRun;                                // 进表决运行 / Enter voting run
    ELSIF _bFault THEN                                                // 出口 2：已锁故障（前置被破坏） / Fault latched
        _eState := E_DL_V23State.eFault;
    END_IF

E_DL_V23State.eRun:
    IF _nHealthy < 2 THEN                                             // 出口 1：健康数跌破 2 / Healthy count drops below two
        _eState := E_DL_V23State.eIdle;                               // 退回未使能待恢复 / Back to idle awaiting recovery
    ELSIF _bFault THEN                                                // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_V23State.eFault;
    END_IF

E_DL_V23State.eFault:
    ;                                                                 // 故障相：仅段 4 复位沿可迁出 / Only the reset edge leaves this phase

ELSE
    _uFault := 16#0001_03EA;                                          // 故障级：非法相位兜底（归并总码） / Illegal-phase fallback
    _bFault := TRUE;                                                  // 锁存置位 / Latch set
    bError  := TRUE;                                                  // 故障标志同拍置位（R45 配对） / Error flag set same scan
    _eCause := E_DL_V23Cause.eCfgIllegal;                             // 归因：相位非法归并组态 / Cause: phase illegal mapped to config
    _eState := E_DL_V23State.eFault;                                  // 强制回故障相 / Force fault phase

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放） —— *)
IF _bFault THEN
    bOut        := FALSE;                                             // 故障相保守关断侧 / Conservative OFF in fault
    nAgreeCount := 0;                                                 // 故障相同意数置 0 / Agreement count zeroed in fault
ELSE
    IF (_nTrue * 2) > _nHealthy THEN                                  // 多数派为真（严格过半） / Strict majority TRUE
        bOut := TRUE;
    ELSE
        bOut := FALSE;                                                // 无过半多数（含 1oo2 不一致）保守 FALSE / No majority, conservative FALSE
    END_IF
    IF _nTrue >= (_nHealthy - _nTrue) THEN                            // 多数派票数 = MAX(真, 假) / Majority votes
        nAgreeCount := _nTrue;
    ELSE
        nAgreeCount := _nHealthy - _nTrue;
    END_IF
    IF _nHealthy = 2 THEN                                             // 降级 1oo2 运行（信息级） / Degraded 1oo2 operation
        _uInfo := 16#0001_04AD;
    END_IF
END_IF
IF _bFault THEN
    nErrId := _uFault;                                                // 故障锁存码回放 / Replay latched fault code
ELSE
    nErrId := _uInfo;                                                 // 信息码 / Info code
END_IF
bError := _bFault;                                                    // 故障标志与锁存同源（名实双出口，R191） / Flag from latch
eState := _eState;                                                    // 状态出口 / State outlet
eCause := _eCause;                                                    // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
