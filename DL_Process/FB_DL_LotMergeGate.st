(*
  ==================================================================
  组件名 Component  : FB_DL_LotMergeGate
  分类   Category   : DL_Process
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e 类型前缀制（R265）
  版本   Version    : 1.0.1
  功能   Purpose    : 批次合批闸：按「批次数 nLotsReq / 总量 uQtyReq」双门槛
                      收集来料批次，门槛任一满足即转就绪；就绪后 bRelease
                      放行（bReleased=TRUE），放行态可经 bRecall 回迁召回态
                      再放行（合规重入）。配置非法（nLotsReq=0 或 uQtyReq=0）
                      锁存 eFault；累计器溢出钳位 + 信息码，不静默吞量。
                      bResetCmd 上升沿复位同步清账（锁存/累计/状态全清）。
  来源   Source     : t2-8-isa88（ISA-88 批次相语义：借「合批/放行/召回」相
                      命名组织方式，实现零源码复制）
  互引   Cross-ref  : FB_DL_ReworkLotGate（同族批次门禁件：返工拦截闸，本件
                      为合批闸，二者可级联——先返工门禁后合批）；FB_DL_LotGenealogyLink
                      （下游批次谱系链接件，可把本件 eState 变迁喂给它建档）
  平台   Platform   : 纯 IEC 61131-3（R_TRIG/ENUM+CASE/UDINT 四则）
  依赖   Depends    : 仅 Standard.library（R_TRIG 属标准件）
  归属   Ownership  : E_DL_MergeState 属主为本文件（全库唯一定义，R264）；
                      引用件只引用不重声明。
  红线   Redline    : R1 零全局/VAR_EXTERNAL/R2 零 %I/%Q/R3 纯 IEC 标准
                      R4 无浮点（纯整数与布尔，无除法面）/R5 全变量双语同行
                      注释/R6 ENUM+CASE 含 ELSE 兜底，eFault 分支显式出现
                      R7 四个 R_TRIG 段 0 无条件刷新/R8 溢出钳位常量化
  契约   Contract   : bEnable 未设引脚（本件无失能面，复位沿即总闸）；uLotQty
                      在 eIdle 相首个 bLotIn 沿入账、eCollecting 相后续沿逐批
                      累加；bReleased 仅在 eReleased 相为 TRUE（召回/复位即撤）。
  错误码 Codes      : 01【故障级·锁存】配置非法（nLotsReq=0 或 uQtyReq=0），
                      锁存至复位沿
                      02【信息级】累计器溢出钳位（uQtyAcc 饱和于 UDINT 上限）
                      03【故障级·锁存】非法状态拦截（ELSE 兜底）
  码位反证 Note     : 01/02/03 分立依据（R90）：01 在配置面、02 在台账面
                      （功能不受影响，bError 不置）、03 在状态面可观测；
                      02 为信息级不置 bError，与 01/03 故障级双通道可区分。
  验收   Acceptance : V1 3 批门槛收满 → eReady ｜ V2 eReady + bRelease →
                      eReleased + bReleased ｜ V3 eReleased + bRecall →
                      eRecalled + bReleased 撤 ｜ V4 eRecalled + bRelease →
                      eReleased（合规重入）｜ V5 nLotsReq=0 → 锁存 01 ｜
                      V6 溢出钳位 → 码 02（不置 bError）｜ V7 复位沿 → 全清
                      回 eIdle ｜ V8 强改非法态 → ELSE 锁存 03
  变更   Revision   : 2026-11-22  v1.0.0  R66 首版（编码阶段批 4 序 9）
                      2026-11-22  v1.0.1  R67 点修（L3）：删除 eFault 分支
                      死迁出式 IF NOT _bFaultLatch → eIdle（迁入 eFault 必伴
                      锁存，清锁存的复位沿同拍已先行置 eIdle，该式结构性不可
                      达）；eFault 相出口仅保留锁存解除路径（复位沿，段 2）。
                      按「结构性不可达防御统一记账口径」登记：eIdle 相
                      uLotQty > LMG_U_MAX 留档型防御（L2）保留不动（UDINT
                      入口域上不可达，留档备审计）。
  ==================================================================
*)
TYPE E_DL_MergeState :
(
    eIdle      := 0,   // 待机：无收集中批次 / idle, no batch being collected
    eCollecting:= 10,  // 收集中：累计未达任一门槛 / collecting, neither threshold met
    eReady     := 20,  // 就绪：门槛任一满足，待放行 / ready, a threshold met, awaiting release
    eReleased  := 30,  // 放行：bReleased=TRUE，可召回 / released, bReleased true, recallable
    eRecalled  := 40,  // 召回：放行被撤回，可再放行 / recalled, the release withdrawn, re releasable
    eFault     := 50   // 锁存故障：复位沿解除 / the latched fault, released by the reset edge
);
END_TYPE

FUNCTION_BLOCK FB_DL_LotMergeGate
VAR_INPUT
    bLotIn   : BOOL := FALSE;  // 来料批次脉冲（上升沿入账）[-] / the incoming lot pulse, counted on the rising edge
    uLotQty  : UDINT := 0;     // 当前批次数量 [件] / the current lot quantity [pc]
    nLotsReq : UDINT := 0;     // 批次数门槛 [批]，须 ≥ 1（=0 判配置非法）/ the lots threshold, at least one
    uQtyReq  : UDINT := 0;     // 总量门槛 [件]，须 ≥ 1（=0 判配置非法）/ the quantity threshold, at least one
    bRelease : BOOL := FALSE;  // 放行指令（上升沿生效）[-] / the release command, effective on the rising edge
    bRecall  : BOOL := FALSE;  // 召回指令（上升沿生效）[-] / the recall command, effective on the rising edge
    bResetCmd: BOOL := FALSE;  // 复位指令（上升沿同步清账）[-] / the reset command, clears the books on the rising edge
END_VAR
VAR_OUTPUT
    eState   : E_DL_MergeState := E_DL_MergeState.eIdle; // 状态机出口 [状态] / the state machine outlet
    uLotsAcc : UDINT := UDINT#0;   // 已收批次数 [批] / the collected lots count
    uQtyAcc  : UDINT := UDINT#0;   // 已收总量 [件]（溢出钳位于 UDINT 上限）/ the collected quantity, saturated
    bReleased: BOOL := FALSE;      // 放行态指示（仅 eReleased 相为 TRUE）[-] / the released indicator, true only in the released phase
    bError   : BOOL := FALSE;      // 故障锁存标志（复位沿清除，R45 配对）/ the latched fault flag, cleared by the reset edge
    uErrorId : UDINT := 16#0000_0000; // 错误码，0=正常；锁存回放至复位沿 [码] / the error code replayed to the reset edge
END_VAR
VAR
    _eState      : E_DL_MergeState := E_DL_MergeState.eIdle; // 内部状态寄存器 / the internal state register
    _bFaultLatch : BOOL := FALSE;   // 故障锁存副本（仅复位沿清除）/ the fault latch copy, cleared only by the reset edge
    _uLatch      : UDINT := 16#0000_0000; // 故障码锁存副本（FB33-1）/ the latched code copy
    _bQtySat     : BOOL := FALSE;   // 本拍溢出钳位信息位（单拍，段 6 映射）/ the per scan saturation info bit
    rtLotIn      : R_TRIG;          // 来料沿实例，段 0 无条件刷新 / the lot edge instance refreshed unconditionally
    rtRelease    : R_TRIG;          // 放行沿实例，段 0 无条件刷新 / the release edge instance refreshed unconditionally
    rtRecall     : R_TRIG;          // 召回沿实例，段 0 无条件刷新 / the recall edge instance refreshed unconditionally
    rtReset      : R_TRIG;          // 复位沿实例，段 0 无条件刷新（锁存解除可达边）/ the reset edge instance, the reachable release edge
END_VAR
VAR CONSTANT
    LMG_U_MAX    : UDINT := 4294967295;   // UDINT 上限哨兵 [件] / the UDINT ceiling sentinel
    LMG_ERR_NONE : UDINT := 16#0000_0000; // 无错误 [码] / no error [code]
    LMG_ERR_CFG  : UDINT := 16#0000_0001; // 码 01：配置非法（锁存）/ code 01, illegal configuration, latched
    LMG_ERR_SAT  : UDINT := 16#0000_0002; // 码 02：累计器溢出钳位（信息级）/ code 02, accumulator saturation, info level
    LMG_ERR_ILL  : UDINT := 16#0000_0003; // 码 03：非法状态（锁存）/ code 03, illegal state, latched
END_VAR

(*------------------------------------------------------------------------------
 * 段 0｜沿检测无条件刷新区（红线 R7）：严禁移入 IF / CASE
 *      The edge instances refresh unconditionally, never inside a branch
 *-----------------------------------------------------------------------------*)
rtLotIn(CLK := bLotIn);        // 来料沿 / the lot edge
rtRelease(CLK := bRelease);    // 放行沿 / the release edge
rtRecall(CLK := bRecall);      // 召回沿 / the recall edge
rtReset(CLK := bResetCmd);     // 复位沿 / the reset edge

(*------------------------------------------------------------------------------
 * 段 1｜错误码本拍预置 + 信息位复位（当前周期事实）
 *      The error code and the info bit are per scan facts
 *-----------------------------------------------------------------------------*)
uErrorId := LMG_ERR_NONE;      // 预置无错误（锁存值随后回放覆盖）/ preset none, the latch replays over it
_bQtySat := FALSE;             // 单拍信息位复位 / reset the single scan info bit

(*------------------------------------------------------------------------------
 * 段 2｜复位沿：同步清账（锁存/累计/状态/bReleased 全清回 eIdle）
 *      The reset edge clears the books synchronously
 *-----------------------------------------------------------------------------*)
IF rtReset.Q THEN
    _bFaultLatch := FALSE;     // 清锁存副本 / clear the latch copy
    _uLatch := LMG_ERR_NONE;   // 清锁存码 / clear the latched code
    uLotsAcc := UDINT#0;       // 清批次数台账 / clear the lots ledger
    uQtyAcc := UDINT#0;        // 清总量台账 / clear the quantity ledger
    _eState := E_DL_MergeState.eIdle;  // 回待机相 / back to idle
    bReleased := FALSE;        // 撤放行指示 / withdraw the release indicator
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜配置闸（锁存归因，成因独立 R190）：门槛任一为 0 即锁存 eFault
 *      The configuration gate, either threshold of zero latches the fault
 *-----------------------------------------------------------------------------*)
IF (nLotsReq = UDINT#0) OR (uQtyReq = UDINT#0) THEN
    _bFaultLatch := TRUE;      // 锁存置位 / latch on
    _uLatch := LMG_ERR_CFG;    // 配置非法码 / the configuration code
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜状态机（ENUM + CASE，含 ELSE 兜底；eFault 分支显式出现）
 *      本拍合法事件优先于故障推断（R275 同拍竞态）：复位沿已先行消化
 *      The state machine, legal events first, the reset edge already consumed above
 *-----------------------------------------------------------------------------*)
IF _bFaultLatch THEN
    _eState := E_DL_MergeState.eFault;   // 锁存强制故障相 / the latch forces the fault phase
END_IF
CASE _eState OF
E_DL_MergeState.eIdle:                   // 待机相 / the idle phase
    IF rtLotIn.Q THEN                    // 首批入账 / the first lot books in
        uLotsAcc := UDINT#1;             // 批次计数起账 / start the lots ledger
        IF uLotQty > LMG_U_MAX THEN      // 批量溢出闸（结构性不可达，留档）/ the per lot overflow gate
            uQtyAcc := LMG_U_MAX;        // 钳上限 / clamp to the ceiling
            _bQtySat := TRUE;            // 记信息位 / mark the info bit
        ELSE
            uQtyAcc := uLotQty;          // 总量入账 / book the quantity
        END_IF
        IF (uLotsAcc >= nLotsReq) OR (uQtyAcc >= uQtyReq) THEN
            _eState := E_DL_MergeState.eReady;   // 门槛即达直接就绪 / ready immediately when a threshold is met
        ELSE
            _eState := E_DL_MergeState.eCollecting;  // 否则迁入收集相 / else enter the collecting phase
        END_IF
    END_IF
E_DL_MergeState.eCollecting:             // 收集相 / the collecting phase
    IF rtLotIn.Q THEN                    // 后续批逐批入账 / each following lot books in
        IF uLotsAcc < LMG_U_MAX THEN     // 批次计数溢出钳位 / the lots count saturation clamp
            uLotsAcc := uLotsAcc + UDINT#1;
        ELSE
            _bQtySat := TRUE;            // 批次计数饱和记信息位 / mark the info bit
        END_IF
        IF uQtyAcc > LMG_U_MAX - uLotQty THEN  // 总量溢出预判（先闸后加，禁回绕）/ the quantity overflow preview, gate before adding
            uQtyAcc := LMG_U_MAX;        // 钳上限 / clamp to the ceiling
            _bQtySat := TRUE;            // 记信息位 / mark the info bit
        ELSE
            uQtyAcc := uQtyAcc + uLotQty;  // 安全累加 / the safe accumulation
        END_IF
        IF (uLotsAcc >= nLotsReq) OR (uQtyAcc >= uQtyReq) THEN
            _eState := E_DL_MergeState.eReady;   // 门槛满足迁就绪 / the threshold met, enter ready
        END_IF
    END_IF
E_DL_MergeState.eReady:                  // 就绪相 / the ready phase
    IF rtRelease.Q THEN                  // 放行沿 / the release edge
        _eState := E_DL_MergeState.eReleased;  // 迁入放行相 / enter the released phase
    END_IF
E_DL_MergeState.eReleased:               // 放行相：驻留相（可召回，非单拍回迁）/ the released phase, dwell by design
    bReleased := TRUE;                   // 放行指示与状态同源（R191 名实双出口）/ the indicator mirrors the state
    IF rtRecall.Q THEN                   // 召回沿 / the recall edge
        _eState := E_DL_MergeState.eRecalled;  // 回迁召回相 / enter the recalled phase
    END_IF
E_DL_MergeState.eRecalled:               // 召回相 / the recalled phase
    bReleased := FALSE;                  // 撤放行指示（名实双出口）/ withdraw the indicator
    IF rtRelease.Q THEN                  // 再放行沿（合规重入，头注 V4）/ the re release edge
        _eState := E_DL_MergeState.eReleased;  // 回迁放行相 / back to the released phase
    END_IF
E_DL_MergeState.eFault:                  // 故障相（显式分支）：锁存驻留，解除仅由复位沿承担
    bReleased := FALSE;                  // 故障相撤放行指示 / withdraw the indicator in the fault phase
    // 失能/故障相串清账：bReleased 已撤；台账 uLotsAcc/uQtyAcc 故意保留供审计
    // 回放（锁存回放原则：不在故障相清账，账面随复位沿统一清，R 锁存回放）
    // the ledgers are deliberately kept for audit replay, cleared by the reset edge
    // v1.0.1：本相无迁出式——锁存解除与 eIdle 回迁由复位沿（段 2）同拍承担，
    // 原 IF NOT _bFaultLatch → eIdle 为结构性不可达死代码，已删（R67 L3）
    // the latch release and the idle return are owned by the reset edge alone
ELSE                                     // 非法状态兜底（R 非法态拦截，不静默）
    _eState := E_DL_MergeState.eFault;   // 强制故障相 / force the fault phase
    _bFaultLatch := TRUE;                // 锁存置位 / latch on
    _uLatch := LMG_ERR_ILL;              // 非法状态码 / the illegal state code
END_CASE

(*------------------------------------------------------------------------------
 * 段 5｜出口映射（名实双出口 R191）：状态/锁存/信息码单点映射
 *      The outlet mapping, the state, the latch and the info code from one point
 *-----------------------------------------------------------------------------*)
IF _bFaultLatch THEN
    bError := TRUE;                      // 故障标志（R45 配对）/ the fault flag
    uErrorId := _uLatch;                 // 锁存回放 / the latched replay
ELSE
    bError := FALSE;                     // 无锁存无故障 / no latch no fault
    IF _bQtySat THEN
        uErrorId := LMG_ERR_SAT;         // 信息级码（不置 bError，功能不受影响）/ the info code, no fault flag
    END_IF
END_IF
IF _eState = E_DL_MergeState.eReleased THEN
    bReleased := TRUE;                   // 放行指示终判（唯一来源） / the release indicator final verdict
ELSE
    bReleased := FALSE;                  // 其余相一律撤 / withdrawn in every other phase
END_IF
eState := _eState;                       // 状态出口 / publish the state
END_FUNCTION_BLOCK
