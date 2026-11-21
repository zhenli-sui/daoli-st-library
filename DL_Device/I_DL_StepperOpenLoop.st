(*==============================================================================
 * 组件名称 (Component)  : I_DL_StepperOpenLoop
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 分类     (Category)   : 接口（INTERFACE）· 开环步进执行器抽象契约 · Level 1 设备层
 * 作者     (Author)     : Daoli Library
 * 日期     (Date)       : 2026-11-15
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版）接口语法，
 *                         仅依赖 Standard.library，零厂商方言
 * 功能简介 (Function)   : 开环步进电机（脉冲 + 方向型）标准抽象契约。按本库接口
 *                         三段式公约（0.11）组织：配套结构体（组态参数域）+
 *                         属性（PROPERTY GET，只读状态出口）+ 方法（METHOD，
 *                         单发指令入口）。上层工站、手动调试页、HMI 适配层仅
 *                         依赖本接口引用，即可用同一套代码适配脉冲方向型步进
 *                         驱动器、总线型闭环步进（位置模式降级使用）与仿真
 *                         步进轴，实现「契约-实现」分层与零硬件耦合。
 * 方法数红线 (Budget)   : 方法共 6 个，恰在本库接口方法数红线（≤ 6）临界：
 *                         Init / Enable / MoveRelative / Stop / Reset /
 *                         GetErrorId。回原、点动、绝对定位职责不入本接口，
 *                         由上层工艺块以 MoveRelative 组合实现。
 * 开源溯源 (Origin)     : 来源标签 stepper（GitHub topics 开组）+ TcOpen 分层思想。
 *                         仅参考 MIT 许可开源步进驱动项目（AccelStepper 及同类
 *                         公开仓库）的「梯形加减速脉冲频率规划算法思想」与
 *                         「脉冲当量 / 最大速度 / 加速度 / 超时」参数域惯例，
 *                         以及 TcOpen（Apache-2.0）公开的「契约-实现分离 +
 *                         属性/方法三段式」分层范式；本接口的命名、方法签名、
 *                         状态语义与结构体布局 100% 本库独立设计，clean-room
 *                         实现，未复制任何来源的代码行，不构成衍生作品。
 * 归属说明 (Ownership)  : 本文件同时承载 ST_DL_StepperCfg（步进组态结构体），
 *                         该结构体归属接口 I_DL_StepperOpenLoop，与其同文件
 *                         发布（公约 0.18：一文件一 POU + 随宿主发布配套 DUT）。
 *                         状态枚举 E_DL_StepperState 归属实现块
 *                         FB_DL_PulseDirStepper，随其文件发布，本接口不引用。
 * 红线自检 (Redline)    : 全局隔离 ✓（零全局变量表引用、零外部变量声明、零物理
 *                         地址字面记号）｜命名合规 ✓｜注释完整 ✓（结构体成员与
 *                         方法参数 100% 中英双语同行注释）｜OOP 封装 ✓（属性全部
 *                         只读 GET，动作全部经方法受理）｜周期安全 ✓（接口无实例、
 *                         无状态机，方法不驻留跨周期状态）｜防御编程 ✓（契约层
 *                         写死参数域与拒绝语义）｜可移植性 ✓（纯 IEC 61131-3）｜
 *                         终结符成对 ✓（TYPE/END_TYPE、INTERFACE/END_INTERFACE）
 * 设计要点 (Key notes)  : ① 开环本质：fPosition 是「指令推算位置」而非编码器
 *                          反馈位置，接口注释强制声明禁止当反馈用；上层需要真实
 *                          位置必须外挂编码器并另行封装，不得在本接口上做闭环。
 *                         ② 限位与报警经 uAlarmWord 位域统一回读（bit0 正限位 /
 *                          bit1 负限位 / bit2 驱动器报警 / bit3 堵转超时 /
 *                          bit4~15 保留），避免为每类故障各开一个属性。
 *                         ③ 方法返回 FALSE 时 GetErrorId 必须给出非零码，禁止
 *                          静默失败（契约层强制，实现块逐条落地）。
 *                         ④ 方法全部为非阻塞单发语义：方法内只登记请求并置内部
 *                          标志，跨周期动作由实现块主体状态机执行（公约 3.4）。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 09 · DL_Device 开环步进族 · 契约件）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 结构体: ST_DL_StepperCfg（归属接口 I_DL_StepperOpenLoop，与其同文件发布）
 * 用途: 开环步进的机械换算与运动限制参数域。由调用方持有并经 Init 的
 *       VAR_IN_OUT 注入，实现块仅保存副本、不改写调用方数据。
 * 说明: fTaskCycle 字段为 R9 规格字段表之外的增补项（规格实现条款④要求
 *       「脉冲翻转步长由任务周期与频率求导」，而规格字段表未列该字段），
 *       在此留档说明：增补不改变已列字段语义，仅补齐实现所需的周期基准。
 *----------------------------------------------------------------------------*)
TYPE ST_DL_StepperCfg :
STRUCT
    uStepsPerMm  : UINT := 400;        // 脉冲当量（Pulse equivalent）[脉冲/mm]，域 > 0 / Must be greater than zero
    uMicrostep   : UINT := 1;          // 驱动器细分数（Microstep divisor）[细分]，域 >= 1 / Microstep divisor, one or above
    fMaxSpeed    : LREAL := 50.0;      // 最大运行速度（Max travel speed）[mm/s]，域 > 0 / Must be greater than zero
    fAccel       : LREAL := 500.0;     // 加/减速度（Acceleration and deceleration）[mm/s²]，域 > 0 / Symmetric accel and decel, greater than zero
    tStallTimeout : TIME := T#500MS;   // 堵转判据附加裕度（Stall timeout margin）[ms]，叠加在理论耗时之上 / Added on top of the theoretical move time
    fTaskCycle   : LREAL := 0.01;      // 任务周期（Task cycle time）[s]，频率求导与脉冲翻步基准 / Base for frequency derivation and pulse toggling
END_STRUCT
END_TYPE

(*-----------------------------------------------------------------------------
 * 接口: I_DL_StepperOpenLoop
 * 契约结构: 属性（PROPERTY GET）+ 方法（METHOD）两段式；属性 3 个、方法 6 个。
 * 状态跃迁契约（实现块必须逐条保证）：
 *   1 未 Init 或 Init 失败时，除 Enable(FALSE) 与 GetErrorId 外全部方法
 *     返回 FALSE 并置非零码；拒绝路径不得改变任何内部运动状态。
 *   2 Enable(TRUE) 仅在该轴无故障锁存时受理；Enable(FALSE) 恒受理，且必须
 *     在本拍内冻结脉冲输出（不得留半脉冲），偏移/位置保持不清零。
 *   3 MoveRelative 仅在「已使能 + 无故障 + 空闲」时受理；运行中再次调用
 *     必须拒绝（本接口不定义在线改距语义，改距请先 Stop 再下发）。
 *   4 限位触发后 MoveRelative 必须拒绝同方向指令（反方向恒受理，用于脱离
 *     限位）；方向判据为电平判据，不因复位而失效。
 *   5 Stop 为受控停车：按减速度斜坡降频至零后回空闲；故障锁存期间调用
 *     无效（返回 FALSE 并给出码），硬切请用 Enable(FALSE)。
 *   6 Reset 仅在故障锁存时受理；驱动器报警源（uAlarmWord.bit2）未消失时
 *     复位不得真正解除锁存（ADR 口径：报警源优先）。
 *   7 任何跃迁语义变化视为 MAJOR 变更，必须回写子库 VERSION.md 迁移指引。
 *----------------------------------------------------------------------------*)
INTERFACE I_DL_StepperOpenLoop

(* —— 段 1｜属性（PROPERTY GET）：只读状态出口，实现块一一落地 —— *)
PROPERTY bReady      : BOOL  // 就绪（Ready），TRUE = 已初始化 + 已使能 + 无故障 + 空闲 / Initialized, enabled, fault free and idle
PROPERTY fPosition   : LREAL // 指令位置累计（Command position）[mm]，开环推算值，非编码器反馈 / Open-loop derived position, never an encoder feedback
PROPERTY uAlarmWord  : WORD  // 报警字（Alarm word）[bit]：bit0 正限位 / bit1 负限位 / bit2 驱动器报警 / bit3 堵转超时 / bit4~15 保留 / Bit0 positive limit, bit1 negative limit, bit2 drive alarm, bit3 stall timeout, bits 4 to 15 reserved

(* —— 段 2｜方法（METHOD）：单发指令，返回受理结果 —— *)

METHOD Init : BOOL                  // 初始化（Initialize）：注入组态，校验参数域，返回是否成功
VAR_IN_OUT
    stCfg : ST_DL_StepperCfg;       // 步进组态（Stepper configuration），调用方持有，实现块仅存副本 / Caller-owned configuration, the implementation keeps a copy
END_VAR

METHOD Enable : BOOL                // 使能/去使能（Enable and disable），电平语义，FALSE 时本拍冻结脉冲
VAR_INPUT
    bEnable : BOOL;                 // 使能指令（Enable command），TRUE = 使能 / FALSE = 去使能并冻结脉冲输出 / TRUE enables, FALSE disables and freezes the pulse output
END_VAR

METHOD MoveRelative : BOOL          // 相对位移（Move relative）：从当前指令位置移动指定距离，梯形加减速由实现块规划
VAR_INPUT
    fDistance : LREAL;              // 相对位移（Relative distance）[mm]，正负双向，负值即负向 / Signed distance in millimetres, negative means reverse
    fSpeed    : LREAL;              // 运行速度（Run speed）[mm/s]，域 > 0，超最大速度自动钳位 / Must be positive, clamped to the maximum speed
END_VAR

METHOD Stop : BOOL                  // 受控停车（Controlled stop）：按减速度斜坡降频至零并清除当前运动指令
VAR_INPUT
END_VAR

METHOD Reset : BOOL                 // 故障复位（Fault reset）：清除限位/堵转/参数类锁存，报警源未消失时不解除
VAR_INPUT
END_VAR

METHOD GetErrorId : UDINT           // 故障码查询（Error code query），0 = 无故障；方法返回 FALSE 时必为非零码
VAR_INPUT
END_VAR

END_INTERFACE
