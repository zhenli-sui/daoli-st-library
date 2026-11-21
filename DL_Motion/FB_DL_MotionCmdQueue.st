(*
    FB_DL_MotionCmdQueue —— 运动指令排队器（仅 Buffered 语义）
    ------------------------------------------------------------------
    分类      : DL_Motion / CommandMgmt
    前缀      : FB_DL_
    版本      : 1.0.1
    溯源      : T1-6 PLCopen MC_BUFFERMODE 公开条款（Aborting / Buffered / BlendingLow /
                BlendingHigh / BlendingPrevious / BlendingNext 六种，其中 Buffered
                = 「新指令等前一条 Done 之后才影响轴」）；本件只实现 Buffered 一种；
                环形缓冲、满队策略、去重、自愈规则与码位 100% 自有；clean-room 重写，
                未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    道莅 clean-room 防御性实现：语义借鉴、代码与码位 100% 自有
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R22 批 4 · #14）
    ------------------------------------------------------------------
    功能说明  : 把上位连发的定位指令排成先入先出队列，按 Buffered 语义一条一条放给轴：
                前一条轴的 Done 未回就不发下一条。本件不消费轴状态、不发 MC_ 功能块、
                不判断运动是否成功——轴的 Done / Error 由调用方以引脚注入。
    职责边界  : ① 只做 Buffered。Blending 系列不立：BlendingLow / BlendingHigh /
                   BlendingPrevious / BlendingNext 都要求「两段速度在过渡点融合」，
                   而本库的轴侧接口没有速度融合通道，硬做只能做出假混合，
                   比不做更危险——故明确不立项，调用方需融合时请用轴厂家的原生接口。
                ② 不做指令合法性（软限位、速度上限）判定，那是 FB_DL_SoftLimitGuard 的职责。
                ③ bAxisError 到达后只挂起不自动续发：必须先让轴故障消失、再给 bClear，
                   否则队列会在轴仍故障时继续往下砸指令，那是二次伤害。
    队列实现  : 环形缓冲，深度固定 DL_MQ_DEPTH = 8（不参数化：动态内存违反零厂商依赖）。
                头指针指向待发条目，尾指针指向下一个空位，计数 _uCount 为权威值。
    自愈规则  : 每拍前置一致性检查，规则写在此处即此件的契约：
                ① 头指针、尾指针任一 >= DL_MQ_DEPTH，或计数 > DL_MQ_DEPTH
                   → 指针与内容均不可信，整队重建（计数与双指针全部归零）；
                ② 指针均合法时，用 (尾 − 头 + 深度) MOD 深度 反算应有计数，
                   满队时该值为 0，按满队解释为 DL_MQ_DEPTH；
                   反算值与 _uCount 不符 → 以指针为准重建计数（双指针是同拍维护的，
                   计数可能被外部复位或掉电字节残留破坏，指针更可信）。
                自愈是静默的，不占码位（不影响工艺判定），但会在头注释留档供现场排查。
    偏离留档  : 派单写「bAxisDone 上升沿出队」，若按字面在 Done 那一拍才移出队首，
                bClear 期间的槽位归属会与新入队条目混叠（新条目可能被下一次 Done 误当成
                在飞条目弹出，等于吞掉一条指令）。本件把「出队」放在发令那一拍完成，
                Done 只负责把状态机送回 eIdle——语义等价，且消除了混叠路径。
    错误码    : 16#0004_01D9 队列满：bOverwriteOldest=TRUE 丢最旧 / FALSE 拒绝新入队
                              （两策略共用本码，靠 uDropped 是否自增区分）——信息级
                16#0004_01DA 连续同目标同速度的指令已合并去重——信息级，正常防御
                16#0004_02F0 指令参数非有限（NaN / ±Inf），拒绝入队且不占槽——故障级，
                             只拒这一条，不打断整队，也不改变状态机（非锁存）
                16#0004_02F1 轴故障应答（bAxisError），已清队并挂起，禁止自动续发——故障级
                16#0004_02F2 状态机落 ELSE 兜底（非法状态）——故障级，回 eIdle 并清队
    码位总账  : 16#0004_01D9 用 / 16#0004_01DA 用 ｜ 16#0004_02F0 用 / 16#0004_02F1 用 / 16#0004_02F2 用
    状态机    : E_DL_CmdQueueState（eIdle / eSending / eWaitDone / eFault），
                CASE 含 ELSE 兜底，ELSE 置 16#0004_02F2 并回 eIdle 同时清队；
                eSending 是单拍相（发令拍），进相即出相，bExec 因此天然只亮一拍。
    采样约定  : 三个 R_TRIG（入队 / 轴 Done / 轴 Error）在本体最前部无条件刷新（R40）；
                bExec 由段 2 的预置清零保证单拍（R25 三律：置位后本拍即被预置覆盖，
                下一拍必为 FALSE，不存在只置不清）。
    依赖      : 仅 Standard.library（R_TRIG / ABS / MIN / MAX），不引用任何其他 DL_ 子库。
    验收向量  :
                V1 域外早退：fTargetPos = NaN 入队 → 02F0、bError=TRUE、uCount 不变、
                   不占槽，整队继续可用。
                V2 上限截断：连发 9 条 → 第 9 条时 bFull=TRUE；bOverwriteOldest=TRUE
                   → uDropped=1、uCount 仍 8、01D9；置 FALSE → uDropped 不变、01D9、
                   新条目被拒。
                V3 跨段时序：eWaitDone 中 bAxisDone 与下一次 bEnq 同拍 → 本拍先入队
                   （uCount+1）再出相；下一拍才发令，bExec 不连拍。
                V4 恢复首拍：bAxisError 上升沿 → 02F1、清队、eFault；轴故障消失后
                   单独给 bClear → 回 eIdle，队列为空且不发任何残留指令。
    红线自检  : 1 全局变量声明零使用 / 外部变量访问零使用 / 物理地址零使用 —— 通过，全部量经引脚注入
                2 纯 IEC 61131-3 跨平台 —— 通过，仅 Standard.library，无动态内存
                3 防御性编程 —— 通过，数组索引全部前置界检、计数递减前判零、
                   浮点判等用 1.0E-6 容差、非有限值拒绝入队
                4 声明行同行中英双语注释 + 单位 —— 通过，逐行附注（含枚举与数组）
                5 ENUM + CASE 且含 ELSE 兜底 —— 通过
                6 TON / R_TRIG 无条件刷新 —— 通过，段 1 三个沿实例先行调用
                7 无魔法数 —— 通过，深度、容差、计数上限全部 VAR CONSTANT
    修订记录  : 2026-11-16 v1.0.0 首次入库（R22 批 4 · #14）
                2026-11-16 v1.0.1 R22 终审修复：eSending 进相后队列若被 bClear /
                轴故障清空，发令被跳过时改回 eIdle，不再空等永不到来的轴 Done
                （消除「清队竞态 → eWaitDone 挂死」路径，新增 V5 验收向量：
                eIdle 转 eSending 的下一拍给 bClear → 本拍不发令、回 eIdle、bExec 不出现）
*)
TYPE E_DL_CmdQueueState :
(
    eIdle     := 0,      // 空闲，队列非空即进发令相 / idle, a non-empty queue enters the sending phase
    eSending  := 10,     // 单拍发令相，本拍出队并把指令放到执行引脚 / one-scan sending phase, dequeues and publishes the command
    eWaitDone := 20,     // 等轴 Done，未回不发下一条（Buffered 契约）/ waiting for the axis Done, nothing else is issued before it
    eFault    := 30      // 故障，队列已清，需轴故障消失后再给 bClear / fault, the queue is cleared and a bClear is required after the axis fault disappears
);
END_TYPE

FUNCTION_BLOCK FB_DL_MotionCmdQueue
VAR_INPUT
    bEnq             : BOOL;                   // 入队请求，上升沿生效 / enqueue request, effective on the rising edge
    fTargetPos       : REAL;                   // 目标位置 [mm]，非有限即拒收 / target position [mm], a non-finite value is rejected
    fVelocity        : REAL;                   // 运行速度 [mm/s]，非有限即拒收 / travel velocity [mm/s], a non-finite value is rejected
    bAxisDone        : BOOL;                   // 轴 Done 输入，由调用方注入，本件不消费轴状态 / axis Done injected by the caller, no axis state is consumed here
    bAxisError       : BOOL;                   // 轴故障输入，上升沿清队挂起 / axis error input, a rising edge clears the queue and suspends
    bOverwriteOldest : BOOL := TRUE;           // 满队策略：TRUE 丢最旧 / FALSE 拒绝新入队 / full-queue policy, TRUE drops the oldest, FALSE rejects the newcomer
    bClear           : BOOL;                   // 清队电平，为真期间队列保持空且不发令 / clear level, the queue stays empty and nothing is issued while TRUE
END_VAR
VAR_OUTPUT
    bExec            : BOOL;                   // 发令单拍脉冲，只亮一拍 / issue pulse, asserted for exactly one scan
    fExecPos         : REAL;                   // 本拍发出的目标位置 [mm]，保持到下一次发令 / target position issued this scan [mm], held until the next issue
    fExecVel         : REAL;                   // 本拍发出的运行速度 [mm/s]，保持到下一次发令 / travel velocity issued this scan [mm/s], held until the next issue
    uCount           : UINT;                   // 队列内条目数 [条]，0~DL_MQ_DEPTH / number of queued items [pcs], 0~DL_MQ_DEPTH
    bFull            : BOOL;                   // 队列已满 / the queue is full
    uDropped         : UDINT;                  // 累计丢弃条数 [条]，饱和不回绕 / accumulated dropped items [pcs], saturating and never wrapping
    eErr             : UDINT;                  // 错误码，0 表示无错 / error code, 0 means no error
    bError           : BOOL;                   // 故障级标志，仅故障级错误置位 / fault-class flag, set only on fault-level codes
    bValid           : BOOL;                   // 输出可用标志，= NOT bError / outputs valid flag, equals NOT bError
END_VAR
VAR
    fbEnq            : R_TRIG;                 // 入队沿检测实例，无条件刷新 / enqueue edge instance, refreshed unconditionally
    fbDone           : R_TRIG;                 // 轴 Done 沿检测实例，无条件刷新 / axis Done edge instance, refreshed unconditionally
    fbAxisErr        : R_TRIG;                 // 轴故障沿检测实例，无条件刷新 / axis error edge instance, refreshed unconditionally
    _afPos           : ARRAY[0..DL_MQ_DEPTH - 1] OF REAL;   // 队列位置缓存 [mm]，深度与 DL_MQ_DEPTH 同源 / queued positions [mm], depth tied to DL_MQ_DEPTH
    _afVel           : ARRAY[0..DL_MQ_DEPTH - 1] OF REAL;   // 队列速度缓存 [mm/s] / queued velocities [mm/s]
    _uHead           : UINT;                   // 头指针，指向待发条目 / head pointer, points at the next item to issue
    _uTail           : UINT;                   // 尾指针，指向下一个空位 / tail pointer, points at the next free slot
    _uCount          : UINT;                   // 队列条目数（权威值）[条] / item count, the authoritative value [pcs]
    _uExp            : UINT;                   // 由双指针反算的应有计数，自愈用 [条] / count derived from the pointers, used by the self-healing path [pcs]
    _uDroppedAcc     : UDINT;                  // 丢弃计数累加器，饱和不回绕 [条] / dropped accumulator, saturating and never wrapping [pcs]
    _fLastPos        : REAL;                   // 最近一次入队或发令的目标位置，去重用 [mm] / last queued or issued target, used for de-duplication [mm]
    _fLastVel        : REAL;                   // 最近一次入队或发令的速度，去重用 [mm/s] / last queued or issued velocity, used for de-duplication [mm/s]
    _bHaveLast       : BOOL;                   // 去重基准是否已建立 / whether the de-duplication reference exists
    _bParamBad       : BOOL;                   // 本条指令参数非有限标志 / the incoming command carries a non-finite value
    _eState          : E_DL_CmdQueueState;     // 当前状态 / current state
END_VAR
VAR CONSTANT
    DL_MQ_DEPTH      : UINT := 8;              // 队列深度 [条]，固定不参数化 / queue depth [pcs], fixed and never parameterised
    DL_MQ_UDINT_MAX  : UDINT := 16#FFFF_FFFF;  // 丢弃计数饱和上限 [条] / drop-counter saturation bound [pcs]
    DL_MQ_EPS        : REAL := 1.0E-6;         // 去重浮点判等容差 [mm] / de-duplication tolerance [mm]
    DL_MQ_INF_GUARD  : REAL := 4.0E38;         // 非有限幅值判定阈（大于 REAL 最大值）[mm] / non-finite magnitude guard [mm]
END_VAR

// 段 1｜三个沿检测实例无条件周期刷新（红线 6：严禁放入 IF / CASE）
// segment 1, three edge instances refreshed unconditionally
fbEnq(CLK := bEnq);
fbDone(CLK := bAxisDone);
fbAxisErr(CLK := bAxisError);

// 段 2｜输出与错误状态预置（bExec 的单拍性由这里的预置保证，R25 三律）
// segment 2, preset outputs and error status; the preset here is what makes bExec a true one-scan pulse
eErr := 0;                                      // 预置无错误 / preset no error
bError := FALSE;                                // 预置无故障标志 / preset no error flag
bExec := FALSE;                                 // 预置无发令，任何状态想发令必须在本拍重新置位 / preset no issue, any state must assert it again this scan
_bParamBad := FALSE;                            // 预置入队参数合法 / preset the incoming command as legal

// 段 3｜队列自愈：指针越界即整队重建，计数与指针推算不符以指针为准（规则见头注释）
// segment 3, queue self-healing; an out-of-range pointer rebuilds the whole queue and a count mismatch follows the pointers
IF (_uHead >= DL_MQ_DEPTH) OR (_uTail >= DL_MQ_DEPTH) OR (_uCount > DL_MQ_DEPTH) THEN
    _uHead := 0;                                // 指针越界，头归零 / out-of-range head reset
    _uTail := 0;                                // 指针越界，尾归零 / out-of-range tail reset
    _uCount := 0;                               // 内容不可信，计数归零 / untrustworthy content, count reset
    _bHaveLast := FALSE;                        // 去重基准随队一起作废 / the de-duplication reference dies with the queue
ELSE
    _uExp := (_uTail + DL_MQ_DEPTH - _uHead) MOD DL_MQ_DEPTH;   // 由双指针反算应有计数 / derive the count from the pointers
    IF (_uCount > 0) AND (_uExp = 0) THEN
        _uExp := DL_MQ_DEPTH;                   // 满队时头尾重合，按满队解释 / a full queue has coincident pointers, read it as full
    END_IF
    IF _uCount <> _uExp THEN
        _uCount := _uExp;                       // 计数与指针不符，以指针为准重建 / a mismatch follows the pointers, which are maintained every scan
    END_IF
END_IF

// 段 4｜清队电平：只清队列内容，不打断在飞指令的完成等待（Buffered 契约）
// segment 4, the clear level empties the queue but never interrupts the wait of the in-flight command
IF bClear THEN
    _uHead := 0;                                // 头归零 / head reset
    _uTail := 0;                                // 尾归零 / tail reset
    _uCount := 0;                               // 计数归零 / count reset
    _bHaveLast := FALSE;                        // 去重基准作废 / the de-duplication reference is void
END_IF

// 段 5｜轴故障应答：上升沿清队并挂起，绝不自动续发（批 4 统一口径）
// segment 5, axis error response, a rising edge clears the queue and suspends, never resuming automatically
IF fbAxisErr.Q THEN
    _uHead := 0;                                // 头归零 / head reset
    _uTail := 0;                                // 尾归零 / tail reset
    _uCount := 0;                               // 清队，故障后不得留残留指令 / clear the queue, no residual command may survive a fault
    _bHaveLast := FALSE;                        // 去重基准作废 / the de-duplication reference is void
    eErr := 16#0004_02F1;                       // 故障级：轴故障应答已清队并挂起 / fault: the axis error response cleared the queue and suspended
    bError := TRUE;                             // 置故障标志 / raise the fault flag
    _eState := E_DL_CmdQueueState.eFault;       // 挂起，等轴故障消失后再给 bClear / suspend until the axis fault is gone and a bClear arrives
END_IF

// 段 6｜入队处理：参数门禁 → 去重 → 满队策略 → 落槽
// segment 6, enqueue path, parameter gate then de-duplication then the full-queue policy then the slot write
IF fbEnq.Q AND (NOT bClear) AND (_eState <> E_DL_CmdQueueState.eFault) THEN
    // 6.1 参数门禁：非有限一律拒收，不占槽、不动计数
    // parameter gate, a non-finite value is rejected without taking a slot or touching the count
    IF (fTargetPos - fTargetPos) <> (fTargetPos - fTargetPos) THEN
        _bParamBad := TRUE;                     // 目标位置为 NaN / the target position is NaN
    ELSIF ABS(fTargetPos) > DL_MQ_INF_GUARD THEN
        _bParamBad := TRUE;                     // 目标位置为 ±Inf / the target position is infinite
    ELSIF (fVelocity - fVelocity) <> (fVelocity - fVelocity) THEN
        _bParamBad := TRUE;                     // 速度为 NaN / the velocity is NaN
    ELSIF ABS(fVelocity) > DL_MQ_INF_GUARD THEN
        _bParamBad := TRUE;                     // 速度为 ±Inf / the velocity is infinite
    END_IF

    IF _bParamBad THEN
        eErr := 16#0004_02F0;                   // 故障级：指令参数非有限，拒收 / fault: non-finite command parameter, rejected
        bError := TRUE;                         // 只拒这一条，不打断整队 / rejects this item only and never disturbs the rest of the queue
    ELSIF _bHaveLast
          AND (ABS(fTargetPos - _fLastPos) <= DL_MQ_EPS)
          AND (ABS(fVelocity - _fLastVel) <= DL_MQ_EPS) THEN
        eErr := 16#0004_01DA;                   // 信息级：与最近一条同目标同速度，合并去重 / info: identical to the latest command, merged
    ELSIF _uCount >= DL_MQ_DEPTH THEN
        // 6.2 满队：按策略处理，两种策略共用 01D9，靠 uDropped 是否自增区分（R90）
        // full queue, both policies share 01D9 and are told apart by whether uDropped grows
        IF bOverwriteOldest AND (_uCount > 0) THEN
            _uHead := (_uHead + 1) MOD DL_MQ_DEPTH;     // 丢最旧：头前移一格 / drop the oldest by advancing the head
            _uCount := _uCount - 1;                     // 计数先减，随后落槽再加回 / decrement first, the slot write adds it back
            IF _uDroppedAcc < DL_MQ_UDINT_MAX THEN
                _uDroppedAcc := _uDroppedAcc + 1;       // 丢弃计数饱和自增 / saturating increment of the drop counter
            END_IF
            _afPos[_uTail] := fTargetPos;               // 落槽（索引已由指针范围检查保证合法）/ write the slot, the index was validated by the pointer check
            _afVel[_uTail] := fVelocity;                // 落槽速度 / write the queued velocity
            _uTail := (_uTail + 1) MOD DL_MQ_DEPTH;     // 尾前移一格 / advance the tail
            _uCount := _uCount + 1;                     // 计数加回 / add the count back
            _fLastPos := fTargetPos;                    // 更新去重基准位置 / update the de-duplication reference
            _fLastVel := fVelocity;                     // 更新去重基准速度 / update the de-duplication reference
            _bHaveLast := TRUE;                         // 基准已建立 / the reference now exists
            eErr := 16#0004_01D9;                       // 信息级：队列满，已丢最旧 / info: the queue was full and the oldest was dropped
        ELSE
            eErr := 16#0004_01D9;                       // 信息级：队列满，拒绝新入队（uDropped 不变）/ info: full and the newcomer is rejected, uDropped stays
        END_IF
    ELSE
        _afPos[_uTail] := fTargetPos;           // 落槽（索引已由指针范围检查保证合法）/ write the slot, the index was validated by the pointer check
        _afVel[_uTail] := fVelocity;            // 落槽速度 / write the queued velocity
        _uTail := (_uTail + 1) MOD DL_MQ_DEPTH; // 尾前移一格 / advance the tail
        _uCount := _uCount + 1;                 // 计数加一 / increment the count
        _fLastPos := fTargetPos;                // 更新去重基准位置 / update the de-duplication reference
        _fLastVel := fVelocity;                 // 更新去重基准速度 / update the de-duplication reference
        _bHaveLast := TRUE;                     // 基准已建立 / the reference now exists
    END_IF
END_IF

// 段 7｜状态机：eIdle 取队首 → eSending 单拍发令并出队 → eWaitDone 等 Done → eIdle
// segment 7, the state machine, take the head in eIdle, issue and dequeue in the one-scan eSending phase, then wait for Done
CASE _eState OF
E_DL_CmdQueueState.eIdle:
    IF (_uCount > 0) AND (NOT bClear) THEN
        _eState := E_DL_CmdQueueState.eSending;     // 有货且未清队，进发令相 / there is work and no clear, enter the sending phase
    END_IF

E_DL_CmdQueueState.eSending:
    IF (_uCount > 0) AND (_uHead < DL_MQ_DEPTH) THEN
        fExecPos := _afPos[_uHead];                 // 读队首位置（索引前置界检）/ read the head position with a bounds check
        fExecVel := _afVel[_uHead];                 // 读队首速度 / read the head velocity
        bExec := TRUE;                              // 单拍发令，段 2 的预置保证下一拍必为 FALSE / the one-scan issue, the preset guarantees FALSE next scan
        _fLastPos := fExecPos;                      // 去重基准同步为已发条目 / the de-duplication reference follows the issued item
        _fLastVel := fExecVel;                      // 去重基准同步为已发条目 / the de-duplication reference follows the issued item
        _bHaveLast := TRUE;                         // 基准已建立 / the reference now exists
        _uHead := (_uHead + 1) MOD DL_MQ_DEPTH;     // 出队在发令这一拍完成，避免与 bClear 混叠 / dequeue right here so bClear cannot alias the slot
        _uCount := _uCount - 1;                     // 上面的 _uCount > 0 判断已挡住无符号下溢 / the guard above prevents an unsigned underflow
        _eState := E_DL_CmdQueueState.eWaitDone;    // 已真实发令：本相转入等待轴 Done / issued for real, now wait for the axis Done
    ELSE
        _eState := E_DL_CmdQueueState.eIdle;        // 进相后队列被 bClear / 故障清空：无在飞指令，直接回空闲，不得空等永不出现的 Done（R22 终审修复：消除竞态挂死）/ the queue was emptied after entering this phase, no command is in flight, return to idle instead of waiting forever
    END_IF

E_DL_CmdQueueState.eWaitDone:
    IF fbDone.Q THEN
        _eState := E_DL_CmdQueueState.eIdle;        // 前条完成，允许发下一条 / the previous move is done and the next may be issued
    END_IF

E_DL_CmdQueueState.eFault:
    // 退出条件：轴故障已消失且人来清队——两者缺一不可，绝不自动续发
    // exit needs both a vanished axis fault and an operator clear, no automatic resume
    IF bClear AND (NOT bAxisError) AND (NOT fbAxisErr.Q) THEN
        _eState := E_DL_CmdQueueState.eIdle;        // 允许回空闲，队列此时已空；进入故障的这一拍不得退出，否则故障码只闪一拍 / back to idle, but never on the entering scan or the fault code would flash for a single scan
    END_IF

ELSE
    eErr := 16#0004_02F2;                           // 故障级：状态机落 ELSE / fault: the state machine fell into ELSE
    bError := TRUE;                                 // 置故障标志 / raise the fault flag
    _uHead := 0;                                    // 非法态一律清队，绝不带着未知队列继续跑 / an illegal state always clears the queue
    _uTail := 0;
    _uCount := 0;
    _bHaveLast := FALSE;                            // 去重基准作废 / the de-duplication reference is void
    _eState := E_DL_CmdQueueState.eIdle;            // 回空闲 / back to idle
END_CASE

// 段 8｜出口汇总：计数类只做发布，不再二次改写（禁隐式回夹）
// segment 8, exit aggregation; counters are published here and never rewritten again
uCount := _uCount;                              // 队列条目数发布 [条] / publish the queued item count [pcs]
uDropped := _uDroppedAcc;                       // 丢弃累计发布 [条] / publish the accumulated drops [pcs]
bFull := (_uCount >= DL_MQ_DEPTH);              // 满队标志 / full-queue flag
bValid := NOT bError;                           // 输出可用 = 无故障级错误 / outputs are valid when no fault-level code is present
END_FUNCTION_BLOCK
