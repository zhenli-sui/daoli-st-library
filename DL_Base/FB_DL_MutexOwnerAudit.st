(*
  FB_DL_MutexOwnerAudit  —  互斥锁所有权审计台账 / Mutex ownership audit ledger
  分类 Category : DL_Base
  码位 Code     : 16#01_0_02
  段位说明      : 01_0 段仅占 00/01（R38），02 起空穴，本件启用 02 格
  版本 Version  : 1.0.1
  来源 Source   : t0-8-sema — T0-8 行待挖子项「超时归还后的所有权审计」落地
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 只做「事后可追」审计出口，不改变加解锁语义：与 FB_DL_SemaMutex（互斥本体）
                  分工，本体管仲裁，本件管台账；
                  2) 记录持锁者标识 uOwnerCur、当前持有时长 fHoldCurSec、累计持有时长 uHoldTotalSec；
                  3) 计数台账：申请 / 正常释放 / 越权释放 / 超时强制归还四类，全部饱和计数不回绕；
                  4) 越权释放（无主时的释放沿）记故障级码并锁存，bReset 解除；
                  5) 超时强制归还由调用方把 FB_DL_SemaMutex.bTimedOut 单拍脉冲接入 bTimeoutForced。
  边界 Boundary : ① 本件不仲裁、不拒绝任何事件，只记录；仲裁语义全部由 FB_DL_SemaMutex 承载；
                  ② uDeltaTimeMs 为调用方注入的任务周期 [ms]，越界按上限钳位（防一次错误注入污染台账）；
                  R41 返修（R241）：饱和闸整体上移 UDINT 域——加法前预留量预检
                  （_uHoldMs / _uHoldTotMs 各自与 DL_MUA_MS_MAX - _uDtEff 比较），
                  判定值域 0..16#FFFF_F000 ms（约 49.7 天），以 10 ms 任务周期计约
                  4.29 亿拍可达，饱和分支真实可达，秒换算改纯 UDINT 整除，零降型路径；
                  ③ uOwnerIdClaim = 0 视为非法标识：照常记录持有但置信息级码 0302；
                  ④ 审计状态两相 CASE 全覆盖 + ELSE 兜底；无定时器/边沿以外的时序假设。
  依赖 Depends  : 仅 Standard.library（R_TRIG）；与 FB_DL_SemaMutex（已注册）仅状态语义对齐，不实例化
  码表 Error codes（本件格 01_0_02，子码步进 +0x100）:
    16#0001_0102 信息级：本拍记录到申请沿（持锁开始）
    16#0001_0202 故障级：越权释放（无主时的释放沿），锁存至 bReset
    16#0001_0302 信息级：申请者标识非法（uOwnerIdClaim = 0），记录照常完成
    16#0001_0402 信息级：超时强制归还事件已入账
    16#0001_0502 故障级：审计相位落 ELSE 兜底（非法相位 ID），强制回无主相并锁存

  修订历史 Revision :
    2026-11-19  v1.0.0  R39 首版（批次 1 · 序号 1）
    2026-11-19  v1.0.1  R40 5 抽终审挂账（不改逻辑）：⚠ 段 4 行 108 饱和闸「UDINT_TO_DINT(DL_MUA_SEC_MAX)」
                  对 16#FFFF_FFFE 做 DINT 降型溢出（回绕为负），乘积类型跨平台歧义；且 _uHoldTotMs
                  （UDINT ms）数学上不可能达到 SEC_MAX×1000 ms，秒级饱和分支永不按预期触发，返修轮处理。
    2026-11-19  v1.0.1  R41 P0-2 返修实施：删除「UDINT_TO_DINT(SEC_MAX) × 1000」降型比较与
                  不可达秒级闸，改为 UDINT 域加法前预留量预检（判定值域 0..16#FFFF_F000 ms，
                  可达性向量已写入边界②），秒换算改纯 UDINT 整除；新增常量 DL_MUA_MS_MAX，
                  DL_MUA_SEC_MAX 降级为文档口径不再参与比较。
*)

TYPE E_DL_MutexAuditState :
(
    eFree := 0,    // 无主：互斥空闲，等待申请沿 / Free, mutex idle, waiting for a claim edge
    eHeld := 10    // 有主：持锁审计中，累计持有时长 / Held, ownership held and hold time accumulating
);
END_TYPE

FUNCTION_BLOCK FB_DL_MutexOwnerAudit
VAR_INPUT
    bClaimEvt      : BOOL;                  // 申请事件沿（来自本体申请沿或其输入 CLK）[-] / Claim event edge from the mutex body
    bReleaseEvt    : BOOL;                  // 释放事件沿（来自本体释放沿或其输入 CLK）[-] / Release event edge from the mutex body
    bTimeoutForced : BOOL;                  // 超时强制归还脉冲，接 FB_DL_SemaMutex.bTimedOut 单拍输出 [-] / Forced timeout return pulse, wire SemaMutex.bTimedOut
    uOwnerIdClaim  : DINT := 0;             // 本次申请者标识 [ID]，0 = 非法（置信息码） / Claimer owner ID, 0 = illegal (info code)
    uDeltaTimeMs   : UDINT := 10;           // 任务周期注入 [ms]，越界按上限钳位 / Task cycle time injected by caller [ms]
    bReset         : BOOL := FALSE;         // 审计复位，上升沿清越权锁存（不清台账计数）/ Audit reset, rising edge clears the fault latch only
END_VAR
VAR_OUTPUT
    eState         : E_DL_MutexAuditState;  // 审计状态出口，段尾单点映射 / Audit state outlet
    bHeld          : BOOL;                  // 当前有主（与 eHeld 同源派生）/ Mutex currently held, derived from eHeld
    uOwnerCur      : DINT;                  // 当前持锁者标识 [ID]，无主时为 0 / Current owner ID, 0 when free
    fHoldCurSec    : REAL;                  // 当前连续持有时长 [s]，释放拍冻结到释放值 / Current continuous hold time [s], frozen at release
    uHoldTotalSec  : UDINT;                 // 累计持有时长 [s]，饱和不回绕 / Total accumulated hold time [s], saturating
    uClaimCnt      : UDINT;                 // 累计申请次数 [次]，饱和不回绕 / Total claim count [times], saturating
    uReleaseCnt    : UDINT;                 // 累计正常释放次数 [次]，饱和不回绕 / Total normal release count [times], saturating
    uUnauthRelCnt  : UDINT;                 // 累计越权释放次数 [次]，饱和不回绕 / Total unauthorized release count [times], saturating
    uTimeoutCnt    : UDINT;                 // 累计超时强制归还次数 [次]，饱和不回绕 / Total forced timeout return count [times], saturating
    uErrorId       : UDINT;                 // 事件码，0 = 无事件（故障级码锁存回放）/ Event code, 0 = none, fault codes latched and replayed
END_VAR
VAR
    rtClaim        : R_TRIG;                // 申请沿实例，主体首部无条件刷新 / Claim edge instance, refreshed unconditionally
    rtRelease      : R_TRIG;                // 释放沿实例，主体首部无条件刷新 / Release edge instance, refreshed unconditionally
    rtTimeout      : R_TRIG;                // 超时归还沿实例，主体首部无条件刷新 / Timeout edge instance, refreshed unconditionally
    rtReset        : R_TRIG;                // 复位沿实例，主体首部无条件刷新 / Reset edge instance, refreshed unconditionally
    _eState        : E_DL_MutexAuditState := E_DL_MutexAuditState.eFree;  // 内部审计相位（CASE 唯一写入目标）/ Internal audit phase, sole CASE target
    _uFault        : UDINT;                 // 故障码锁存寄存 / Latched fault code register
    _uInfo         : UDINT;                 // 本拍信息码，每拍重算 / Transient info code this cycle
    _uOwnerInt     : DINT := 0;             // 内部持锁者标识，对外经 uOwnerCur 镜像 / Internal owner register mirrored to uOwnerCur
    _uHoldMs       : UDINT := 0;            // 当前持有毫秒累加器 [ms] / Current hold millisecond accumulator
    _uHoldTotMs    : UDINT := 0;            // 累计持有毫秒累加器 [ms] / Total hold millisecond accumulator
    _uDtEff        : UDINT;                 // 钳位后的生效周期 [ms] / Clamped effective cycle time
END_VAR
VAR CONSTANT
    DL_MUA_DT_MAX     : UDINT := 60000;         // 单拍周期合理上限 [ms]，超出按上限入账 / Sane per-cycle cap [ms]
    DL_MUA_CNT_MAX    : UDINT := 16#FFFF_FFFE;  // 各计数饱和上限 [次]，加一永不回绕 / Counter saturation bound, increment never wraps
    DL_MUA_MS_PER_SEC : UDINT := 1000;          // 每秒毫秒数 [ms/s] / Milliseconds per second
    DL_MUA_SEC_MAX    : UDINT := 16#FFFF_FFFE;  // 秒级累计饱和上限 [s]，R41 起仅作文档口径，不再参与比较 / Second-level doc bound, not used in comparison since R41
    DL_MUA_MS_MAX     : UDINT := 16#FFFF_F000;  // 毫秒累加器饱和上限 [ms]，UDINT 域加法闸（约 49.7 天，10ms 周期约 4.29 亿拍可达）/ Millisecond accumulator saturation bound, UDINT-domain add gate
END_VAR

(* —— 段 0：边沿实例无条件周期刷新（R7 红线：严禁置于 IF/CASE 分支内） —— *)
rtClaim(CLK := bClaimEvt);                                        // 申请沿刷新，每拍必调
rtRelease(CLK := bReleaseEvt);                                    // 释放沿刷新，每拍必调
rtTimeout(CLK := bTimeoutForced);                                 // 超时归还沿刷新，每拍必调
rtReset(CLK := bReset);                                           // 复位沿刷新，每拍必调

(* —— 段 1：单拍量预清零（锁存量 _uFault 与台账计数不入清单，R187①） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
_uFault := _uFault;                 // 故障锁存码保持回放（禁同拍抹除，R187/R189）
uErrorId := 16#0000_0000;           // 事件码缺省无事件（段尾按锁存/信息单点回放）

(* —— 段 2：周期注入钳位（防御：一次错误注入不得污染台账） —— *)
IF uDeltaTimeMs > DL_MUA_DT_MAX THEN
    _uDtEff := DL_MUA_DT_MAX;       // 越界按上限钳位
ELSE
    _uDtEff := uDeltaTimeMs;        // 域内直通
END_IF

(* —— 段 3：复位沿（只清越权锁存，不清台账计数——台账是历史事实） —— *)
IF rtReset.Q THEN
    _uFault := 16#0000_0000;        // 清故障锁存码（唯一解除路径：bReset 上升沿）
END_IF

(* —— 段 4：持有时长累加（仅 eHeld 相累计；R41 P0-2 返修：饱和闸整体上移 UDINT 域，
     加法前预留量预检，判定值域 0..16#FFFF_F000 ms，无降型、无可达性缺口） —— *)
IF _eState = E_DL_MutexAuditState.eHeld THEN
    IF _uHoldMs <= DL_MUA_MS_MAX - _uDtEff THEN     // 加前预留量预检（当拍量判据，UDINT 域）
        _uHoldMs := _uHoldMs + _uDtEff;             // 当前持有累加 [ms]
    ELSE
        _uHoldMs := DL_MUA_MS_MAX;                  // 饱和钳位，永不回绕
    END_IF
    IF _uHoldTotMs <= DL_MUA_MS_MAX - _uDtEff THEN  // 同口径预检累计累加器（UDINT 域，零降型）
        _uHoldTotMs := _uHoldTotMs + _uDtEff;       // 累计持有累加 [ms]
    ELSE
        _uHoldTotMs := DL_MUA_MS_MAX;               // 累计饱和钳位，永不回绕
    END_IF
END_IF
fHoldCurSec := UDINT_TO_REAL(_uHoldMs) / UDINT_TO_REAL(DL_MUA_MS_PER_SEC);  // 当前持有换算秒（分母为常量恒非零）
uHoldTotalSec := _uHoldTotMs / DL_MUA_MS_PER_SEC;   // 累计秒整除换算（纯 UDINT 域，R241 零降型）

(* —— 段 5：审计相位机（只记录、不仲裁；出口在段 7） —— *)
CASE _eState OF

E_DL_MutexAuditState.eFree:
    IF rtRelease.Q THEN
        uUnauthRelCnt := uUnauthRelCnt + 1;     // 越权释放入账（无主时的释放沿）
        IF uUnauthRelCnt >= DL_MUA_CNT_MAX THEN
            uUnauthRelCnt := DL_MUA_CNT_MAX;    // 计数饱和防回绕
        END_IF
        _uFault := 16#0001_0202;                // 故障级：越权释放，锁存至 bReset
    ELSIF rtTimeout.Q THEN
        uTimeoutCnt := uTimeoutCnt + 1;         // 超时归还沿落在此相同样入账（本体已强制归还）
        IF uTimeoutCnt >= DL_MUA_CNT_MAX THEN
            uTimeoutCnt := DL_MUA_CNT_MAX;
        END_IF
        _uInfo := 16#0001_0402;                 // 信息级：超时归还已入账
    ELSIF rtClaim.Q THEN
        uClaimCnt := uClaimCnt + 1;             // 申请入账
        IF uClaimCnt >= DL_MUA_CNT_MAX THEN
            uClaimCnt := DL_MUA_CNT_MAX;
        END_IF
        IF uOwnerIdClaim = 0 THEN
            _uInfo := 16#0001_0302;             // 信息级：标识非法，记录照常
        ELSE
            _uInfo := 16#0001_0102;             // 信息级：持锁开始
        END_IF
        _uOwnerInt := uOwnerIdClaim;            // 记录持锁者标识（含非法 0，照实记录）
        _uHoldMs := 0;                          // 当前持有时长从零起算
        _eState := E_DL_MutexAuditState.eHeld;  // 进有主相
    END_IF

E_DL_MutexAuditState.eHeld:
    IF rtRelease.Q THEN
        uReleaseCnt := uReleaseCnt + 1;         // 正常释放入账
        IF uReleaseCnt >= DL_MUA_CNT_MAX THEN
            uReleaseCnt := DL_MUA_CNT_MAX;
        END_IF
        _uOwnerInt := 0;                        // 无主：标识清零
        _eState := E_DL_MutexAuditState.eFree;  // 回无主相（当前持有时长冻结在释放值）
    ELSIF rtTimeout.Q THEN
        uTimeoutCnt := uTimeoutCnt + 1;         // 超时强制归还有主相入账
        IF uTimeoutCnt >= DL_MUA_CNT_MAX THEN
            uTimeoutCnt := DL_MUA_CNT_MAX;
        END_IF
        _uInfo := 16#0001_0402;                 // 信息级：超时归还已入账
        _uOwnerInt := 0;                        // 强制归还：标识清零
        _eState := E_DL_MutexAuditState.eFree;  // 回无主相
    ELSIF rtClaim.Q THEN
        uClaimCnt := uClaimCnt + 1;             // 有主期间的申请沿照常入账（本体仲裁语义不变）
        IF uClaimCnt >= DL_MUA_CNT_MAX THEN
            uClaimCnt := DL_MUA_CNT_MAX;
        END_IF
    END_IF

ELSE
    _uFault := 16#0001_0502;                    // 故障级：非法相位 ID 兜底，锁存至 bReset
    _uOwnerInt := 0;                            // 无主侧强制清标识（安全侧）
    _eState := E_DL_MutexAuditState.eFree;      // 强制回无主相（自恢复，不锁死）

END_CASE

(* —— 段 6：派生输出每拍重写（名实同源） —— *)
bHeld := (_eState = E_DL_MutexAuditState.eHeld);            // 有主派生位
uOwnerCur := _uOwnerInt;                                     // 持锁者镜像输出

(* —— 段 7：事件码单点回放（故障锁存优先，信息码其次） —— *)
IF _uFault <> 16#0000_0000 THEN
    uErrorId := _uFault;            // 故障锁存码回放（不在故障态按当下输入重推）
ELSE
    uErrorId := _uInfo;             // 信息码
END_IF
eState := _eState;                  // 状态出口单点映射

END_FUNCTION_BLOCK
