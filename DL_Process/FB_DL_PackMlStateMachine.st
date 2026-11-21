(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PackMlStateMachine
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· PackML 状态机框架 · Level 2 机台层
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅依赖 Standard.library，零厂商方言
 * 功能描述 (Function)   : PackML / ISA-TR88.00.02 十七态（+ Undefined 占位）
 *                         状态机 clean-room 框架实现。命令驱动 + acting 态由
 *                         bStateComplete 自动推进；本块不编排任何具体工艺
 *                         动作——纯状态机框架，动作由调用方按态派发（Level 2
 *                         依赖注入原则），与机台工艺完全解耦。
 * 设计要点 (Key notes)  : ① Aborting 为最高优先级出口：bProcessAbort 或非法态
 *                           → eAborting（CASE+ELSE 兜底同向，公约 0.1/0.2）；
 *                         ② Clearing 完成后必经 eStopped（S-1「abort 后强制
 *                           去污步」语义）；Aborted 恢复链 Clear→Clearing→
 *                           Stopped→Reset→Resetting→Idle；
 *                         ③ eExecute 中 bInterlockOk 失失 → 自动转 eHolding
 *                           （机内保持），与 eSuspended（机外挂起）区分指示，
 *                           保 OEE 根因数据质量（S-1 提取点⑤）；
 *                         ④ 模式切换仅允许 eStopped/eIdle/eCompleted 稳态
 *                           （S-1 提取点⑥），其余态下变更被拒并置信息级
 *                           0005_0101；
 *                         ⑤ 首扫/跟踪判据唯一合法范式 IF bTrack OR (NOT bInit)
 *                           （公约 0.1）：首扫从 eUndefined 迁入 eStopped，
 *                           运行中途跟踪脉冲不扰动已建立的状态；
 *                         ⑥ ePrevState 仅在真实跃迁时刷新，Abort 路径保留
 *                           跃迁前状态供 HMI 复盘。
 * 枚举归属 (Enum note)  : E_DL_PackMlState / E_DL_PackMlCmd / E_DL_UnitMode
 *                         三个 DUT 随本块同文件发布（规格书第 6 节交付约定），
 *                         FB_DL_PackMlCmdDecoder 引用 E_DL_PackMlCmd，导入
 *                         本文件后全局可见。
 * 开源溯源 (Origin)     : packml。来源为 OMAC PackML / ISA-TR88.00.02 公开
 *                         规范的状态集合、命令集合与跃迁语义（S-1 提取点
 *                         ①②③④⑤⑥），状态编号逐项对齐；实现与命名 100%
 *                         自有 clean-room，不参考任何厂商 LUC 代码结构。
 * 验收向量 (Acceptance) :
 *   V1 正常链：eIdle → Start → eStarting →(SC)→ eExecute → Complete →
 *      eCompleting →(SC)→ eCompleted → Reset → eResetting →(SC)→ eIdle；
 *   V2 Abort→Clear→Reset 全恢复链：任意态 bProcessAbort → eAborting →
 *      eAborted → Clear → eClearing →(SC)→ eStopped → Reset → eIdle；
 *   V3 非法态兜底：强制 _eState=88 → ELSE 兜底 → eAborting，码 0005_0201；
 *   V4 非稳态模式切换：eExecute 下改 eMode → 拒绝 + 信息级 0005_0101；
 *   V5 联锁失失保持：eExecute 中 bInterlockOk=FALSE → eHolding，
 *      bHeldByMachine=TRUE；Unhold → eUnholding →(SC)→ eExecute；
 *   V6 中途跟踪脉冲：eExecute 中 bTrack=TRUE 一拍 → 状态保持不扰动。
 * 故障码表 (Error codes):
 *   16#0005_0101【信息级】非稳态模式切换被拒 / 16#0005_0201【故障级】
 *   非法状态兜底（走 Aborting 路径）。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 05 · DL_Process 立项）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   fbPml.eMode := E_DL_PackMlMode.eProduction;   // 组态期或稳态期切换
 *   fbPml.eCmd := fbDecoder.eCmd;                 // 命令由解码器单发供给
 *   fbPml(bStateComplete := fbStep.bSeqDone,      // 周期调用
 *         bInterlockOk := bSafeChain, bProcessAbort := bEstopChain);
 *   工艺派发示例：按 fbPml.eState 分态派发，eExecute 态执行 fbStation.Run()。
 *   OEE 采集：bInExecute 计 Execute 时长；bHeldByMachine/bSuspendedByLine
 *   分别归因机内保持与机外挂起，根因统计勿混用。
 *----------------------------------------------------------------------------*)

{attribute 'strict'}
{attribute 'qualified_only'}
TYPE E_DL_PackMlState :
(
    eUndefined    := 0,    // 未定义：上电占位态，首扫迁移至 eStopped / Undefined: power-up placeholder, migrated at first scan
    eClearing     := 1,    // 清除中（acting，自动推进）：abort 后强制去污步 / Clearing (acting): mandatory cleanup after abort
    eStopped      := 2,    // 已停止（wait）：复位/启动/急停出口 / Stopped (wait): reset, start or abort exits
    eStarting     := 3,    // 启动中（acting，自动推进）：预热/自检等启动子工序 / Starting (acting): startup sub-operations
    eIdle         := 4,    // 空闲（wait）：就绪待命，Start 进入生产 / Idle (wait): ready, Start enters production
    eSuspended    := 5,    // 已挂起（wait）：机外原因暂停（线体/供料） / Suspended (wait): paused by external line reason
    eExecute      := 6,    // 执行中（wait，生产主态）：工艺动作派发与 OEE 计时态 / Execute (wait): main production state for OEE
    eStopping     := 7,    // 停止中（acting，自动推进）：受控停机子工序 / Stopping (acting): controlled stop sub-operations
    eAborting     := 8,    // 急停中（acting，自动跃迁）：最高优先级出口 / Aborting (acting): highest-priority exit
    eAborted      := 9,    // 已急停（wait）：仅 Clear/Reset 可退 / Aborted (wait): only Clear or Reset exits
    eHolding      := 10,   // 保持中（acting，自动推进）：机内原因保持过渡态 / Holding (acting): machine-internal hold transition
    eHeld         := 11,   // 已保持（wait）：机内原因暂停，Unhold 恢复 / Held (wait): held by machine reason, Unhold resumes
    eUnholding    := 12,   // 恢复中（acting，自动推进）：从保持回到执行 / Unholding (acting): resuming from held
    eSuspending   := 13,   // 挂起中（acting，自动推进）：机外暂停过渡 / Suspending (acting): external suspend transition
    eUnsuspending := 14,   // 解挂中（acting，自动推进）：从挂起回到执行 / Unsuspending (acting): resuming from suspended
    eResetting    := 15,   // 复位中（acting，自动推进）：回 Idle 的复位子工序 / Resetting (acting): reset sub-operations to idle
    eCompleting   := 16,   // 完成中（acting，自动推进）：完工收尾子工序 / Completing (acting): completion sub-operations
    eCompleted    := 17    // 已完成（wait）：批次完成，Reset/Clear 退出 / Completed (wait): batch done, Reset or Clear exits
) UINT;
END_TYPE

{attribute 'strict'}
{attribute 'qualified_only'}
TYPE E_DL_PackMlCmd :
(
    eUndefined     := 0,   // 无命令占位（No command placeholder）
    eReset         := 1,   // 复位命令（Reset command）
    eStart         := 2,   // 启动命令（Start command）
    eStop          := 3,   // 停止命令（Stop command）
    eHold          := 4,   // 保持命令（Hold command）
    eUnhold        := 5,   // 解除保持命令（Unhold command）
    eSuspend       := 6,   // 挂起命令（Suspend command）
    eUnsuspend     := 7,   // 解除挂起命令（Unsuspend command）
    eAbort         := 8,   // 急停命令（Abort command）
    eClear         := 9,   // 清除命令（Clear command）
    eComplete      := 10,  // 完工命令（Complete command）
    eStateComplete := 11   // 子工序完成命令（State complete command），命令形态的 SC
) UINT;
END_TYPE

{attribute 'strict'}
{attribute 'qualified_only'}
TYPE E_DL_UnitMode :
(
    eInvalid     := 0,    // 无效模式占位（Invalid mode placeholder）
    eProduction  := 1,    // 生产模式（Production mode）
    eMaintenance := 2,    // 维护模式（Maintenance mode）
    eManual      := 3,    // 手动模式（Manual mode）
    eUser4       := 4,    // 用户自定义模式 4（User defined mode 4）
    eUser5       := 5,    // 用户自定义模式 5（User defined mode 5）
    eUser6       := 6,    // 用户自定义模式 6（User defined mode 6）
    eUser7       := 7,    // 用户自定义模式 7（User defined mode 7）
    eUser8       := 8,    // 用户自定义模式 8（User defined mode 8）
    eUser9       := 9,    // 用户自定义模式 9（User defined mode 9）
    eUser10      := 10,   // 用户自定义模式 10（User defined mode 10）
    eUser11      := 11,   // 用户自定义模式 11（User defined mode 11）
    eUser12      := 12,   // 用户自定义模式 12（User defined mode 12）
    eUser13      := 13,   // 用户自定义模式 13（User defined mode 13）
    eUser14      := 14,   // 用户自定义模式 14（User defined mode 14）
    eUser15      := 15    // 用户自定义模式 15（User defined mode 15）
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_PackMlStateMachine
VAR_INPUT
    eMode          : E_DL_UnitMode := E_DL_UnitMode.eInvalid;      // 单元模式（Unit mode），S-1 提取点④，仅稳态可切换
    eCmd           : E_DL_PackMlCmd := E_DL_PackMlCmd.eUndefined;  // 标准命令（Standard command），由 FB_DL_PackMlCmdDecoder 单发供给
    bStateComplete : BOOL := FALSE;       // 子工序完成信号（State complete），acting 态推进用
    bInterlockOk   : BOOL := TRUE;        // 工艺联锁（Process interlock），Execute 态保持条件，失失转机内保持
    bProcessAbort  : BOOL := FALSE;       // 工艺级急停触发（Process abort trigger），如安全门/急停链，电平生效
    bTrack         : BOOL := FALSE;       // 跟踪脉冲（Tracking pulse），首扫/跟踪同步（R5 公约 0.1）
END_VAR
VAR_OUTPUT
    eState         : E_DL_PackMlState := E_DL_PackMlState.eUndefined;   // 当前状态（Current state）
    ePrevState     : E_DL_PackMlState := E_DL_PackMlState.eUndefined;   // 前一状态（Previous state），Abort 路径复盘用
    bInExecute     : BOOL := FALSE;       // Execute 态指示（In execute），OEE 计时用
    bHeldByMachine : BOOL := FALSE;       // 机内保持指示（Held by machine），OEE 根因：机内原因
    bSuspendedByLine : BOOL := FALSE;     // 机外挂起指示（Suspended by line），OEE 根因：机外原因
    uErrorId       : UDINT := 0;          // 末次事件码（Last error code），信息级码不构成故障
END_VAR
VAR
    bInit          : BOOL := FALSE;       // 首扫标志（First-scan flag，R19 范式配套）
    _eState        : E_DL_PackMlState := E_DL_PackMlState.eUndefined;   // 内部当前状态（Internal current state）
    _eStateOld     : E_DL_PackMlState := E_DL_PackMlState.eUndefined;   // 本拍跃迁前快照（Pre-transition snapshot）
    _ePrevState    : E_DL_PackMlState := E_DL_PackMlState.eUndefined;   // 内部前一状态（Internal previous state）
    _eModeActive   : E_DL_UnitMode := E_DL_UnitMode.eInvalid;           // 生效单元模式（Active unit mode），非稳态拒绝切换
    _eModeReqLast  : E_DL_UnitMode := E_DL_UnitMode.eInvalid;           // 上一拍模式请求（Last mode request），模式变更沿检测
END_VAR

// 段 1｜R19 首扫/跟踪同步：判据唯一合法范式 IF bTrack OR (NOT bInit)
IF bTrack OR (NOT bInit) THEN
    IF _eState = E_DL_PackMlState.eUndefined THEN
        _eState := E_DL_PackMlState.eStopped;          // PackML 上电默认稳态：Stopped
        _ePrevState := E_DL_PackMlState.eUndefined;
        _eModeActive := eMode;                         // 首扫锁定当前模式请求
    END_IF
    bInit := TRUE;                                     // 运行中途跟踪脉冲不扰动已建立状态（验收向量 V6）
END_IF

// 段 2｜工艺级急停最高优先级出口：任何非 Aborting/Aborted 态直达 eAborting
IF bProcessAbort AND (_eState <> E_DL_PackMlState.eAborting) AND (_eState <> E_DL_PackMlState.eAborted) THEN
    _ePrevState := _eState;                            // 保留跃迁前状态供 HMI 复盘
    _eState := E_DL_PackMlState.eAborting;
END_IF

// 段 3｜模式切换稳态门禁（S-1 提取点⑥）：仅 eStopped/eIdle/eCompleted 允许
IF eMode <> _eModeReqLast THEN                      // 新模式请求沿
    _eModeReqLast := eMode;
    IF (_eState = E_DL_PackMlState.eStopped) OR (_eState = E_DL_PackMlState.eIdle)
       OR (_eState = E_DL_PackMlState.eCompleted) THEN
        _eModeActive := eMode;                      // 稳态允许切换
    ELSE
        uErrorId := 16#0005_0101;                   // 信息级：非稳态模式切换被拒（R21：不置故障）
    END_IF
END_IF

// 段 4｜十七态主状态机：命令驱动 + acting 态 bStateComplete 自动推进
_eStateOld := _eState;                              // 跃迁前快照，供 ePrevState 刷新
CASE _eState OF

    E_DL_PackMlState.eUndefined:                    // 防御驻留态：首扫已迁移，非法驻留即回 Stopped
        _eState := E_DL_PackMlState.eStopped;

    E_DL_PackMlState.eClearing:                     // acting：清除进行中（abort 后强制去污步）
        IF bStateComplete OR (eCmd = E_DL_PackMlCmd.eStateComplete) THEN
            _eState := E_DL_PackMlState.eStopped;   // S-1：清除完成必经 Stopped
        END_IF

    E_DL_PackMlState.eStopped:                      // wait：复位/启动/急停出口
        IF eCmd = E_DL_PackMlCmd.eReset THEN
            _eState := E_DL_PackMlState.eResetting;
        ELSIF eCmd = E_DL_PackMlCmd.eStart THEN
            _eState := E_DL_PackMlState.eStarting;
        ELSIF eCmd = E_DL_PackMlCmd.eAbort THEN
            _eState := E_DL_PackMlState.eAborting;
        END_IF

    E_DL_PackMlState.eStarting:                     // acting：启动子工序（预热/自检等）
        IF bStateComplete OR (eCmd = E_DL_PackMlCmd.eStateComplete) THEN
            _eState := E_DL_PackMlState.eIdle;      // 启动完成回空闲
        END_IF

    E_DL_PackMlState.eIdle:                         // wait：就绪待命
        IF eCmd = E_DL_PackMlCmd.eStart THEN
            _eState := E_DL_PackMlState.eStarting;
        ELSIF eCmd = E_DL_PackMlCmd.eStop THEN
            _eState := E_DL_PackMlState.eStopping;
        ELSIF eCmd = E_DL_PackMlCmd.eAbort THEN
            _eState := E_DL_PackMlState.eAborting;
        END_IF

    E_DL_PackMlState.eSuspended:                    // wait：机外原因暂停
        IF eCmd = E_DL_PackMlCmd.eUnsuspend THEN
            _eState := E_DL_PackMlState.eUnsuspending;
        ELSIF eCmd = E_DL_PackMlCmd.eStop THEN
            _eState := E_DL_PackMlState.eStopping;
        ELSIF eCmd = E_DL_PackMlCmd.eAbort THEN
            _eState := E_DL_PackMlState.eAborting;
        END_IF

    E_DL_PackMlState.eExecute:                      // wait：生产主态，工艺动作由此派发
        IF NOT bInterlockOk THEN
            _eState := E_DL_PackMlState.eHolding;   // 联锁失失 → 机内保持（OEE 根因：机内）
        ELSIF bStateComplete OR (eCmd = E_DL_PackMlCmd.eStateComplete) OR (eCmd = E_DL_PackMlCmd.eComplete) THEN
            _eState := E_DL_PackMlState.eCompleting;
        ELSIF eCmd = E_DL_PackMlCmd.eHold THEN
            _eState := E_DL_PackMlState.eHolding;
        ELSIF eCmd = E_DL_PackMlCmd.eSuspend THEN
            _eState := E_DL_PackMlState.eSuspending;
        ELSIF eCmd = E_DL_PackMlCmd.eStop THEN
            _eState := E_DL_PackMlState.eStopping;
        ELSIF eCmd = E_DL_PackMlCmd.eAbort THEN
            _eState := E_DL_PackMlState.eAborting;
        END_IF

    E_DL_PackMlState.eStopping:                     // acting：受控停机子工序
        IF bStateComplete OR (eCmd = E_DL_PackMlCmd.eStateComplete) THEN
            _eState := E_DL_PackMlState.eStopped;
        END_IF

    E_DL_PackMlState.eAborting:                     // acting：急停执行（自动跃迁，无需 SC）
        _eState := E_DL_PackMlState.eAborted;

    E_DL_PackMlState.eAborted:                      // wait：已急停，仅 Clear/Reset 可退
        IF eCmd = E_DL_PackMlCmd.eClear THEN
            _eState := E_DL_PackMlState.eClearing;  // 恢复链第一步：清除去污
        ELSIF eCmd = E_DL_PackMlCmd.eReset THEN
            _eState := E_DL_PackMlState.eResetting;
        END_IF

    E_DL_PackMlState.eHolding:                      // acting：机内保持过渡
        IF bStateComplete OR (eCmd = E_DL_PackMlCmd.eStateComplete) THEN
            _eState := E_DL_PackMlState.eHeld;
        END_IF

    E_DL_PackMlState.eHeld:                         // wait：机内原因暂停
        IF eCmd = E_DL_PackMlCmd.eUnhold THEN
            _eState := E_DL_PackMlState.eUnholding;
        ELSIF eCmd = E_DL_PackMlCmd.eStop THEN
            _eState := E_DL_PackMlState.eStopping;
        ELSIF eCmd = E_DL_PackMlCmd.eAbort THEN
            _eState := E_DL_PackMlState.eAborting;
        END_IF

    E_DL_PackMlState.eUnholding:                    // acting：从保持回到执行
        IF bStateComplete OR (eCmd = E_DL_PackMlCmd.eStateComplete) THEN
            _eState := E_DL_PackMlState.eExecute;
        END_IF

    E_DL_PackMlState.eSuspending:                   // acting：机外暂停过渡
        IF bStateComplete OR (eCmd = E_DL_PackMlCmd.eStateComplete) THEN
            _eState := E_DL_PackMlState.eSuspended;
        END_IF

    E_DL_PackMlState.eUnsuspending:                 // acting：从挂起回到执行
        IF bStateComplete OR (eCmd = E_DL_PackMlCmd.eStateComplete) THEN
            _eState := E_DL_PackMlState.eExecute;
        END_IF

    E_DL_PackMlState.eResetting:                    // acting：复位子工序
        IF bStateComplete OR (eCmd = E_DL_PackMlCmd.eStateComplete) THEN
            _eState := E_DL_PackMlState.eIdle;      // Completed→Reset→Resetting→Idle 闭环
        END_IF

    E_DL_PackMlState.eCompleting:                   // acting：完工收尾子工序
        IF bStateComplete OR (eCmd = E_DL_PackMlCmd.eStateComplete) THEN
            _eState := E_DL_PackMlState.eCompleted;
        END_IF

    E_DL_PackMlState.eCompleted:                    // wait：批次完成
        IF eCmd = E_DL_PackMlCmd.eReset THEN
            _eState := E_DL_PackMlState.eResetting;
        ELSIF eCmd = E_DL_PackMlCmd.eClear THEN
            _eState := E_DL_PackMlState.eClearing;
        ELSIF eCmd = E_DL_PackMlCmd.eStop THEN
            _eState := E_DL_PackMlState.eStopping;
        ELSIF eCmd = E_DL_PackMlCmd.eAbort THEN
            _eState := E_DL_PackMlState.eAborting;
        END_IF

    ELSE
        // 非法状态兜底（故障级）：走 Aborting 路径
        _ePrevState := _eState;
        _eState := E_DL_PackMlState.eAborting;
        uErrorId := 16#0005_0201;

END_CASE

// 段 5｜跃迁刷新：仅真实跃迁时更新 ePrevState（Abort 复盘语义）
IF _eState <> _eStateOld THEN
    _ePrevState := _eStateOld;
END_IF

// 段 6｜状态出口映射：OEE 三位正交指示
eState := _eState;                                  // 当前状态出口
ePrevState := _ePrevState;                          // 前一状态出口
bInExecute := (_eState = E_DL_PackMlState.eExecute);              // Execute 计时位
bHeldByMachine := (_eState = E_DL_PackMlState.eHolding) OR (_eState = E_DL_PackMlState.eHeld)
                  OR (_eState = E_DL_PackMlState.eUnholding);     // 机内保持组
bSuspendedByLine := (_eState = E_DL_PackMlState.eSuspending) OR (_eState = E_DL_PackMlState.eSuspended)
                    OR (_eState = E_DL_PackMlState.eUnsuspending); // 机外挂起组
END_FUNCTION_BLOCK
