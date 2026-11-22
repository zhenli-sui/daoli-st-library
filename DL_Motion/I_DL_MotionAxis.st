(*==============================================================================
 * 组件名称 (Component)  : I_DL_MotionAxis
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 接口（INTERFACE）· 运动控制抽象契约 · Level 1 工艺层
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅依赖 Standard.library，零厂商方言
 * 功能描述 (Function)   : 单轴运动控制标准抽象契约，按本库接口三段式公约
 *                         （0.11）组织：属性（PROPERTY GET）+ 方法（METHOD）
 *                         + 状态枚举。上层工艺块（点动器、工站、HMI 适配层）
 *                         仅依赖本接口引用，即可用同一套代码适配真实伺服
 *                         驱动、虚拟运动学仿真轴与第三方轴封装。
 * 方法数红线 (Budget)   : 方法共 6 个，恰在本库接口方法数红线（≤6）临界：
 *                         Enable / Reset / Stop / MoveAbsolute / MoveRelative /
 *                         MoveVelocity。回原（Homing）职责由后续轮次
 *                         FB_DL_AxisHomingSeq 承载，不入本接口。
 * 状态语义 (Semantics)  : E_DL_AxisState 按 PLCopen 轴状态模型 clean-room
 *                         重排：六态 + 禁用态，编号显式、间隔 10 预留扩展位
 *                         （R5 提取点 S-2④）。
 * 开源溯源 (Origin)     : plcopen / s7-motion。仅提取 PLCopen（TC5 接口规范
 *                         公开语义）轴状态名与命令动词、S7-1500 Motion Control
 *                         手册公开的工艺对象接口参数域；实现与命名 100% 自有，
 *                         clean-room，未参考任何厂商源码行。
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 N/A（契约件无运算）
 *                         R5 ✓ 全枚举项/方法参数双语注释 ｜ R6 N/A（接口无状态机）
 *                         R7 N/A（无实例调用）｜ R18 ✓ INTERFACE/END_INTERFACE 成对
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 05 · DL_Motion 开库 · 接口契约件）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   VAR fbAxis : FB_DL_SingleAxis; END_VAR
 *   fbAxis();                                    // 先注入实参再周期调用
 *   bOk := fbAxis.Enable(bOn := TRUE);           // 上使能（MC_Power 语义）
 *   bOk := fbAxis.MoveAbsolute(fPos := 120.0, fVel := 50.0, fAcc := 500.0);
 *   fbAxis();                                    // 每周期调用驱动状态机
 *   IF fbAxis.bError THEN bOk2 := fbAxis.Reset(); END_IF
 *   上层注入：JogController.iAxis := fbAxis;（接口引用指向实现块实例）
 *   注意：方法全部非阻塞，仅置内部请求标志；跨周期动作由 FB 主体状态机执行。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 常见误用与现场提示 (Field notes)：
 *   1 eState = eStopping 时一切运动指令被拒绝（MC_Stop 语义），上层不要
 *     在停止未完成前抢发定位指令，指令会直接返回 FALSE 而不排队。
 *   2 MoveRelative 的 fDist 带符号，负值即负向；MoveVelocity 的 fVel 同理，
 *     上层不必先换算方向再调用。
 *   3 bError 为派生式（仅反映 eErrorStop 态），信息级事件码只进 uErrorId，
 *     上层 HMI 报警分组时应同时读两者。
 *   4 bHomed 在本库当前版本恒为 FALSE 占位，回原由后续轮次组件驱动后置位；
 *     依赖回原联锁的工站请先行用安全限位方案替代。
 *   5 接口方法在实现块内必须逐个落地，任何新增实现块（真实驱动适配层）
 *     不得增删方法签名，否则破坏依赖本接口的全部上层块。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 状态跃迁契约 (Transition contract)：
 *   实现块必须保证以下跃迁语义，供上层联锁与 HMI 依赖（本接口只定契约，
 *   实现块 FB_DL_SingleAxis 为参考实现，后续真实驱动适配层须逐条对齐）：
 *   1 eDisabled：唯一入态；仅 Enable(bOn=TRUE) 且驱动就绪可迁出至
 *     eStandstill，迁移后 bEnabled 必须为 TRUE。
 *   2 eStandstill：唯一可接收三种 Move 指令的稳态（速度模式可在
 *     eContinuousMotion 中改速）；下使能指令必须回到 eDisabled。
 *   3 eDiscreteMotion / eContinuousMotion：执行中收到 Stop 必须转入
 *     eStopping 受控减速，禁止直接跳变；到位/限位停车后回 eStandstill。
 *   4 eStopping：拒绝一切运动指令；停稳后回 eStandstill，期间不得有
 *     任何速度输出残留。
 *   5 eErrorStop：故障唯一锁存态，仅 Reset 且故障源消除后可退回
 *     eStandstill 或 eDisabled；bError 派生式仅反映本态。
 *   6 eHoming：预留态，回原序列由后续轮次 FB_DL_AxisHomingSeq 承载，
 *     实现块在本态内不得自行产生运动输出。
 *   7 任何跃迁语义变化视为 MAJOR 变更（见子库版本号约定），必须回写
 *     VERSION.md 迁移指引并同步依赖本接口的全部上层块。
 *   8 实现块文件头必须标注本接口版本依赖关系，接口升版时实现块同步
 *     升版并重跑验收向量基线（见前节）。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 方法前置条件与返回值语义 (Method contract)：
 *   Enable(bOn) : BOOL    — 故障态或驱动未就绪时上使能请求返回 FALSE；
 *                           下使能请求恒受理（返回 TRUE），电平语义。
 *   Reset()     : BOOL    — 仅 eErrorStop 态受理返回 TRUE，其余态返回
 *                           FALSE；复位语义为"确认报警"，故障源未消除时
 *                           实现块不得真正退态。
 *   Stop()              — 受理后进入 eStopping；eErrorStop 态调用无效；
 *                           MC_Stop 语义：停止完成后仍拒绝新任务直至新
 *                           运动指令被显式受理。
 *   MoveAbsolute(fPos, fVel, fAcc) : BOOL
 *                         — 仅 eStandstill 受理；参数非法（非有限值、非
 *                           正值）或目标位超软限位返回 FALSE 且轴状态
 *                           不得发生任何改变。
 *   MoveRelative(fDist, fVel, fAcc) : BOOL
 *                         — 同上；fDist 带符号，目标落点 = 当前位置 +
 *                           fDist，落点越限即拒绝。
 *   MoveVelocity(fVel, fAcc) : BOOL
 *                         — eStandstill / eContinuousMotion 两态受理；
 *                           fVel 带符号，连续运动中再次调用为改速而非
 *                           重启。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 实现块落地契约清单 (Implementer checklist)：
 *   后续任何新增实现块（真实伺服适配层、仿真轴、第三方轴包装类）实现
 *   本接口时必须逐条满足，否则视为违反库架构公约：
 *   1 七个 PROPERTY GET 必须全部落地，返回值与内部状态实时一致；
 *   2 六个 METHOD 必须全部落地且签名逐字一致，不得增删参数；
 *   3 方法内不得阻塞、不得跨扫描周期驻留临时状态，跨周期动作一律
 *     经内部请求标志由 FB 主体状态机执行；
 *   4 bError 必须为派生式且仅反映 eErrorStop 态，信息级事件只进
 *     uErrorId（R19/R21 公约）；
 *   5 实现块不得出现任何全局变量引用、外部变量声明或物理地址直写
 *     （R1/R2 红线），硬件差异全部由上层适配层吸收；
 *   6 状态枚举 E_DL_AxisState 的取值与语义不得重定义或扩展；
 *   7 故障码沿用 DL_Motion 族段位 16#0004_xxxx（信息级 01xx / 故障级
 *     02xx 起），不得自造码段。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 验收向量基线 (Acceptance baseline)：
 *   本接口为契约件，验收向量在实现块上执行；实现块验收必须覆盖：
 *   1 正常跃迁链：Enable → eStandstill → MoveAbsolute → 到位回待机；
 *   2 非法状态兜底：内部状态被破坏后实现块 CASE+ELSE 兜底进 eErrorStop；
 *   3 运行中途插入跟踪脉冲：运动态插入 bTrack → 位置重同步 + 受控停车
 *     （R5 公约 0.1 必测向量）；
 *   4 指令门禁：eStopping/eErrorStop 态全部 Move 方法返回 FALSE 且
 *     轴状态不变；
 *   5 参数防御：非有限值与非正值参数被拒绝，接口引用未注入时上层
 *     调用不产生任何轴动作。
 *   6 一致性回归：实现块更新后须重跑 1~5 向量，任何跃迁语义变化视为
 *     MAJOR 变更（见子库版本号约定），必须回写 VERSION.md 迁移指引。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 归属声明 (Ownership note)：
 *   E_DL_AxisState 为本接口契约的组成枚举，随本接口同文件发布（规格书
 *   第 6 节交付约定：接口与其枚举同文件，头注释注明归属）。导入 .st 后
 *   枚举全局可见，实现块 FB_DL_SingleAxis 与上层工艺块直接引用。
 *----------------------------------------------------------------------------*)

{attribute 'strict'}
{attribute 'qualified_only'}
TYPE E_DL_AxisState :
(
    eDisabled         := 0,    // 禁用：伺服未上使能，输出级切断 / Disabled: servo not enabled, outputs cut off
    eStandstill       := 10,   // 待机：已使能且静止就绪，可接收运动指令 / Standstill: enabled and stationary, ready for motion commands
    eHoming           := 20,   // 回原中：回原点序列执行中（后续轮次组件承载） / Homing: homing sequence in progress (reserved)
    eDiscreteMotion   := 30,   // 离散运动中：绝对/相对定位执行中 / Discrete motion: absolute or relative positioning active
    eContinuousMotion := 40,   // 连续运动中：速度模式执行中 / Continuous motion: velocity mode active
    eStopping         := 50,   // 受控停止中：按减速度斜坡停车，拒绝新任务 / Stopping: controlled deceleration, new tasks rejected
    eErrorStop        := 60    // 故障停机：报警锁存，仅 Reset 可退回 / Error stop: fault latched, only Reset can leave
) UINT;
END_TYPE

INTERFACE I_DL_MotionAxis

(* —— 段 1｜属性（PROPERTY GET）：状态只读出口，实现块一一落地 —— *)
PROPERTY eState    : E_DL_AxisState   // 当前轴状态（Current axis state），枚举见 E_DL_AxisState
PROPERTY fPosition : REAL             // 当前位置（Current position）[mm 或 deg，单位由实现组态注释约定]
PROPERTY fVelocity : REAL             // 当前速度（Current velocity）[mm/s 或 deg/s]，带符号，负值=负向
PROPERTY bEnabled  : BOOL             // 使能状态（Enabled status），TRUE=伺服已上使能
PROPERTY bHomed    : BOOL             // 回原完成（Homed status），TRUE=坐标系已建立
PROPERTY bError    : BOOL             // 故障锁存（Error latched），TRUE=处于 eErrorStop 态
PROPERTY uErrorId  : UDINT            // 末次事件码（Last error code），信息级码不置 bError

(* —— 段 2｜方法（METHOD）：命令入口，全部非阻塞单发化 —— *)
METHOD Enable : BOOL                       // 使能请求（Enable request），MC_Power 语义
VAR_INPUT
    bOn : BOOL;                            // 使能电平（Enable on/off），TRUE=上使能请求 / FALSE=下使能请求
END_VAR

    END_METHOD

METHOD Reset : BOOL                        // 故障复位（Fault reset），MC_Reset 语义，确认报警
VAR_INPUT
END_VAR

    END_METHOD

METHOD Stop                                // 受控停止（Controlled stop），MC_Stop 语义：停车并拒绝新任务
VAR_INPUT
END_VAR

    END_METHOD

METHOD MoveAbsolute : BOOL                 // 绝对定位（Move absolute）
VAR_INPUT
    fPos : REAL;                           // 目标绝对位置（Target absolute position）[mm 或 deg]
    fVel : REAL;                           // 运行速度（Run velocity）[mm/s]，正值，超上限自动钳位
    fAcc : REAL;                           // 加/减速度（Acceleration and deceleration）[mm/s²]，正值
END_VAR

    END_METHOD

METHOD MoveRelative : BOOL                 // 相对定位（Move relative）
VAR_INPUT
    fDist : REAL;                          // 相对位移（Relative distance）[mm]，带符号，负值=负向
    fVel  : REAL;                          // 运行速度（Run velocity）[mm/s]，正值
    fAcc  : REAL;                          // 加/减速度（Acceleration and deceleration）[mm/s²]，正值
END_VAR

    END_METHOD

METHOD MoveVelocity : BOOL                 // 速度模式（Move velocity），可在连续运动中改速
VAR_INPUT
    fVel : REAL;                           // 目标速度（Target velocity）[mm/s]，带符号，负值=负向
    fAcc : REAL;                           // 加/减速度（Acceleration and deceleration）[mm/s²]，正值
END_VAR

    END_METHOD
END_INTERFACE
