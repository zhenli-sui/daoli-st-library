(*==============================================================================
 * 组件名称 (Component)  : I_DL_TowerLight
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         纯 IEC 61131-3（第3版）接口语法，零厂商方言
 * 分类     (Category)   : 状态指示抽象接口（Interface）+ 配套枚举 3 个（DUT）
 * 功能描述 (Function)   : 工业安灯塔（Andon 三色/四色塔灯 + 蜂鸣）标准抽象契约。
 *                         按本库接口三段式组织：状态枚举（随文件发布）+ 只读
 *                         属性组（10 个）+ 指令方法组（3 个）。上层 HMI 面板、
 *                         工站顺序控制、PackML 状态机只需持有本接口引用，即可
 *                         适配直驱型（每色一路数字输出）、模块化型（XVU 类
 *                         集束塔灯）与总线型（IO-Link 塔灯）三类实现，而无需
 *                         感知底层通道数量与驱动方式。
 * 接口三段式 (Contract): ①状态枚举：E_DL_TowerColor / E_DL_TowerPattern /
 *                         E_DL_TowerState（均随本文件发布）；②属性：全部只读
 *                         GET（eState / eRed / eAmber / eGreen / eBlue / eWhite /
 *                         bBuzzer / bSilenced / bError / uErrorId 共 10 个）；
 *                         ③方法：SetColor / SilenceBuzzer / Reset 共 3 个，
 *                         满足接口方法不超过 6 个的拆分红线。
 * 边界防错 (Boundary)   : 接口层不做任何电平输出（灯与蜂鸣的物理通道由实现块
 *                         以输出引脚给出）；接口层不读任何现场输入（状态位由
 *                         实现块引脚注入）；红绿互斥属实现块出口断言职责，
 *                         接口只声明属性语义，不承诺仲裁顺序。
 * 开源溯源 (Origin)     : 原创实现（参考 TcOpen 组件范式）。来源标签
 *                         tcopen-component / stack-light（RAW_NOTES_R8 条目 S-13：
 *                         TcOpen 的 stack-light 组件公开文档所呈现的
 *                         「状态位集合 → 灯色仲裁 → 通道输出」三层分层惯例），
 *                         仅借鉴功能分类、接口参数域与状态语义；接口命名、
 *                         属性与方法签名、枚举取值步长按本库红线独立设计，
 *                         clean-room 未复制任何源码行。许可证说明：TcOpen 采用
 *                         MIT 许可，其公开语义描述可自由借鉴；本文件不含其
 *                         任何代码片段，无许可证传染风险。
 * 归属说明 (Ownership)  : 本文件同时承载三个枚举定义，均归属接口
 *                         I_DL_TowerLight，与其同文件发布（公约 0.18：一文件
 *                         一 POU，枚举随宿主发布，禁止在其他文件重复声明）。
 * 验收向量 (Acceptance) : 本文件为纯契约，无执行体，行为验收沿用实现块
 *                         FB_DL_SignalTower 的 V1 至 V8（见该文件头注释）。
 *                         契约级自查三条：C1 属性共 10 个且全部只读 GET；
 *                         C2 方法共 3 个且均带布尔受理返回值；C3 三个枚举取值
 *                         互不重叠且步长为 10，便于后续插值。
 * 已知限制 (Limits)     : 1 eRotate 依赖实现层是否具备环灯硬件，单色通道实现
 *                         退化为慢闪，属实现选择而非契约缺陷。2 接口不约束仲裁
 *                         优先序与通道数量，跨实现的行为一致性由各实现块头注释
 *                         的优先级表承担。3 消音权限与消音次数限制属上层 HMI
 *                         职责，不在本契约内。
 * 规格偏离 (R11 Dev.)   : 无。三个枚举取值、10 个属性类型与 3 个方法签名与
 *                         规格第 3.1 节逐条一致。
 * 红线自检 (Redline)    : 零全局变量表访问 ✓｜零外部变量声明 ✓｜零物理地址直写 ✓
 *                         纯 IEC 61131-3 ✓｜全成员中英双语同行注释 ✓
 *                         INTERFACE 与 END_INTERFACE 成对 ✓｜三个 TYPE 与 END_TYPE 成对 ✓
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 08 · 泳道 C · DL_Device 状态指示族）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_TowerColor（归属接口 I_DL_TowerLight，与其同文件）
 * 含义: 塔灯灯色通道。数值步长 10 留空位，便于后续插入特殊色（如紫色、
 *       青色）而不破坏已有工程持久化的数值。
 *----------------------------------------------------------------------------*)
TYPE E_DL_TowerColor :
(
    eNone  := 0,     // 无色 / 清除该色通道（No color, channel cleared）
    eRed   := 10,    // 红色（Red），安全与未确认故障主色，优先级最高
    eAmber := 20,    // 黄色 / 琥珀色（Amber），预警与待处理主色
    eGreen := 30,    // 绿色（Green），自动运行正常主色
    eBlue  := 40,    // 蓝色（Blue），手动模式与操作员求助主色
    eWhite := 50     // 白色（White），待机与就绪指示（可选通道）
) UINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_TowerPattern（归属接口 I_DL_TowerLight，与其同文件）
 * 含义: 单色通道的显示模式。闪烁时基一律由实现块的半周期引脚给定，
 *       禁止读取任何内部时钟源。
 *----------------------------------------------------------------------------*)
TYPE E_DL_TowerPattern :
(
    eOff        := 0,   // 熄灭（Off），该色通道无输出
    eSteady     := 10,  // 常亮（Steady），电平恒为真
    eFlashSlow  := 20,  // 慢闪（Slow flash），默认半周期 500 毫秒，全周期约 1 赫兹
    eFlashFast  := 30,  // 快闪（Fast flash），默认半周期 250 毫秒，全周期约 2 赫兹
    eRotate     := 40   // 旋转（Rotate），多色环灯逐色轮转；单色通道实现退化为慢闪
) UINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_TowerState（归属接口 I_DL_TowerLight，与其同文件）
 * 含义: 塔灯"显示状态"的语义分类，取值为仲裁结果的唯一出口分类，不是
 *       实现块内部私有步序；上层可据此做 HMI 文本映射与报警分级。
 *----------------------------------------------------------------------------*)
TYPE E_DL_TowerState :
(
    eNormal      := 0,   // 正常 / 待机（Normal or standby），无主级告警
    eWarning     := 10,  // 预警（Warning），未确认慢闪、已确认常亮
    eFaultAck    := 20,  // 故障已确认（Fault acknowledged），红常亮不鸣
    eFaultUnack  := 30,  // 故障未确认（Fault unacknowledged），红慢闪并鸣
    eSafety      := 40,  // 安全事件（Safety event），红快闪强制鸣，最高优先
    eManual      := 50,  // 手动模式（Manual mode），蓝常亮
    eCall        := 60   // 操作员求助（Operator call），蓝快闪
) UINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 接口: I_DL_TowerLight
 * 契约结构: 属性（只读 GET，10 个）+ 方法（3 个）两段式，方法总数满足
 *           不超过 6 个的拆分红线。方法均为非阻塞单发语义，不含跨扫描周期
 *           状态驻留；返回值仅表示"请求是否被受理"，实际灯效以属性为准。
 * 受理语义: SetColor 在更高优先级占用或故障锁存时返回 FALSE；
 *           SilenceBuzzer 在非蜂鸣期或安全事件期返回 FALSE（安全事件不受
 *           消音约束）；Reset 仅在存在故障锁存时返回 TRUE。
 *----------------------------------------------------------------------------*)
INTERFACE I_DL_TowerLight

// ---- 属性段（全部只读 GET，共 10 个）--------------------------------------

PROPERTY eState     : E_DL_TowerState   // 当前显示状态（Displayed state），等于仲裁结果的语义分类
PROPERTY eRed       : E_DL_TowerPattern // 红色通道当前模式（Red pattern），eOff=不亮
PROPERTY eAmber     : E_DL_TowerPattern // 黄色通道当前模式（Amber pattern），eOff=不亮
PROPERTY eGreen     : E_DL_TowerPattern // 绿色通道当前模式（Green pattern），eOff=不亮
PROPERTY eBlue      : E_DL_TowerPattern // 蓝色通道当前模式（Blue pattern），eOff=不亮
PROPERTY eWhite     : E_DL_TowerPattern // 白色通道当前模式（White pattern），eOff=不亮
PROPERTY bBuzzer    : BOOL              // 蜂鸣器当前输出（Buzzer active），TRUE=正在鸣响
PROPERTY bSilenced  : BOOL              // 已消音（Silenced），消音保持窗内为 TRUE
PROPERTY bError     : BOOL              // 故障锁存（Fault latched），仅故障级码置位，信息级码不置位
PROPERTY uErrorId   : UDINT             // 错误码（Error code），0=无错误，段位 16#0003_xxxx

// ---- 方法段（单发指令，返回受理结果，共 3 个）-----------------------------

(* 请求置某色某模式（Set color and pattern）；返回 FALSE 表示当前被更高优先级
 * 占用、处于故障锁存或使能关闭。色通道生命周期由实现块仲裁表裁决。 *)
METHOD SetColor : BOOL
VAR_INPUT
    eColor   : E_DL_TowerColor;    // 目标灯色（Target color），eNone=撤销人工覆盖
    ePattern : E_DL_TowerPattern;  // 目标模式（Target pattern），eOff=该色熄灭
END_VAR

(* 消音（Silence buzzer）：一次性受理，超过保持时长自动恢复蜂鸣；非蜂鸣期或
 * 处于安全事件期返回 FALSE（安全事件不受消音约束）。 *)
METHOD SilenceBuzzer : BOOL
VAR_INPUT
END_VAR

(* 复位故障锁存（Reset fault latch）：仅存在锁存故障时返回 TRUE，否则 FALSE。 *)
METHOD Reset : BOOL
VAR_INPUT
END_VAR

END_INTERFACE
