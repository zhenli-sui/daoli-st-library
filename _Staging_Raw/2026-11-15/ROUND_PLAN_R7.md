# ROUND_PLAN_R7 —— Round 07 引脚级规格书（16 项）

> 轮次：R7（2026-11-15）｜ 方向：**DL_Device 收尾件五族（10 项）** + DL_Process 三件（OEE/输送线/配料）+ DL_Motion 补充件 1 项 + DL_Base LGF Counter 组开组 2 项（T2 硬性配额）
> 编制：道莅工控代码库产品总监（兜底模式）｜ 狩猎留痕：同目录 `RAW_NOTES_R7.md`（S-1~S-11）
> 执行规则：本规格书为编码阶段唯一契约；偏离必须在 .st 头注释按规则 R11 留档。
> 合规铁律：闭源源（LGF/西门子示例/厂商文档）只借分类/参数域/语义，**clean-room 独立实现**；每个 `.st` 文件头「开源溯源 (Origin)」按 RAW_NOTES_R7 对应 S 条目如实标注。
> 计划声明：16 项全部为高工程价值目标，无凑数变体；若编码/终审阶段裁定某项不具备高质量落地条件，宁减不凑（允许 14~15 项交付，须在战报注明原因）。

---

## 第 0 节 公共约定（编码侧逐字遵守，优先级高于逐组件条款）

0.1 **R19 首扫范式**：含初始化/跟踪逻辑的 FB 首扫判据一律 `IF bTrack OR (NOT bInit) THEN ... bInit := TRUE`（bInit 初值 FALSE），禁止反序写法；验收向量必含「运行中途插入跟踪脉冲」向量。**R23 例外**：纯事件型组件标注「事件型，免首扫」，不设 bInit。
0.2 **R21 信息级码**：`bFault`/`bError` 一律为显式排除信息级码的派生式；故障码表逐条标注【故障级】/【信息级】；信息级码只进 `uErrorId` 不进报警链。
0.3 **R20 量纲**：状态变量注释量纲 = 赋值表达式量纲推导结果；被限幅钳位的量，注释量纲与限幅域一致。
0.4 **双语注释**：每个引脚/枚举项声明行 `// 中文物理意义（English term）[单位] 取值范围/默认行为`。
0.5 **R7 定时器/边沿**：TON/TOF/R_TRIG/F_TRIG 实例在主体最前部无条件周期刷新，严禁置于 IF/CASE 分支；实例入参一律先算成普通变量再喂实例。
0.6 **R14 语义参数变更**：TON 的 PT/相位类语义参数变化时必须显式断输入一拍使已计时归零。
0.7 **R15 故障码锁存**：锁存型故障只在解除路径清码；瞬时型告警每拍重算，不得混写。
0.8 **故障码段位（沿用公约）**：DL_Base `16#0001_xxxx`、DL_Motion `16#0004_xxxx`、DL_Process `16#0005_xxxx`、DL_Device `16#0003_xxxx`。信息级 `16#0xxx_01xx` 起、故障级 `16#0xxx_02xx` 起。**编码前必须与各子库 VERSION.md 故障码表核对一次已占码位，冲突顺延；本规格给出的码位为建议值，以核对结果为准。**
0.9 **非有限值防御**：全部 REAL/LREAL 输入先做 `fX <> fX` 检测再比较；出口默认值在第一条防御 IF 之前赋值。
0.10 **零全局耦合**：时间/反馈量/位置量一律引脚注入，禁读 CPU 钟；禁一切物理地址、全局变量表与外部变量引用；文件头红线自检用语义转述（R10：不出现被禁记号原文）。
0.11 **接口契约三段式**：每个 `I_DL_*` 按「状态枚举（同文件，头注释注明归属）+ 属性（PROPERTY GET）+ 方法（METHOD）」三段定义；方法 ≤6。
0.12 **R22 接口实现块 OUT 列**：规格 OUT 列成员与接口属性同名者，实现块以只读 PROPERTY GET 承载，非接口成员保留 VAR_OUTPUT；头注释 R11 留档。
0.13 **安全组件定位声明**（S-4/S-5/S-11 适用）：本库安全相关组件为**标准 PLC 逻辑编排与诊断镜像层**，头部与注释显式声明「不构成 ISO 13849 / IEC 62061 认证安全功能，安全回路由认证安全控制器/安全 PLC 承载」；不实现、不替代任何安全认证回路。
0.14 **浮点与除法防御**：浮点禁 `=` 判等（用 `ABS(fA-fB) < 1E-6`）；一切除法带 `ABS(分母) > 1E-6` 防零分支并置错误码；`WHILE` 带防死锁计数器。
0.15 **单位标注**：位置 mm、速度 mm/s、加速度 mm/s²、流量 L/min 或 m³/h（引脚注释注明）、重量 kg、时间 TIME 字面量。

### 泳道划分（四泳道并行编码，互不冲突）

| 泳道 | 组件 | 文件落点 | 泳道内自持契约 | 跨泳道依赖（全部为已入库组件） |
|---|---|---|---|---|
| A | #3~#12（DL_Device 10 项） | `C:\Library\DL_Device\` | 5 个新接口枚举各自随接口文件发布（E_DL_ScannerState / E_DL_SafetyDoorState / E_DL_CurtainState / E_DL_FlowMeterState / E_DL_LevelState） | 无 |
| B | #13~#15（DL_Process 3 项） | `C:\Library\DL_Process\` | E_DL_DosingPhase 随 #15 发布 | #13 消费 PackML 根因位语义（引脚注入，不引组件）；#14 消费泳道 A 的 I_DL_VfdDrive（**既有接口，非本轮新增**，零合并冲突） |
| C | #16（DL_Motion 1 项） | `C:\Library\DL_Motion\` | — | 仅依赖既有 I_DL_MotionAxis |
| D | #1~#2（DL_Base 2 项） | `C:\Library\DL_Base\` | — | 无 |

四泳道之间零新增共享 DUT、零文件交集；公共依赖全部为已入库组件或本泳道自持契约，无合并冲突。#14 对 I_DL_VfdDrive 仅引用既有契约文件，不修改。

---

## 第 1 节 泳道 D｜DL_Base LGF Counter 组开组（2 项，T2-1 LGF，标签 `lgf-counter`）

### 1.1 `FB_DL_EventCounter`（功能块）｜DL_Base｜来源标签 `lgf-counter`（RAW_NOTES S-1）

功能：双向事件计数器（DINT 域）。计数脉冲沿计数，方向独立；预设值比较输出；饱和/回绕模式可选；禁止与已注册任何计数/位组件重名或语义重复（`FC_DL_BitCount` 为位统计、`FB_DL_RuntimeMeter` 为时间累计，本块为通用事件计数）。**事件型，免首扫（R23）**。

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| bCntUp | BOOL | IN | 递增计数脉冲（Count-up pulse），R_TRIG 上升沿 +1 |
| bCntDown | BOOL | IN | 递减计数脉冲（Count-down pulse），R_TRIG 上升沿 -1 |
| bLoad | BOOL | IN | 预置装载指令（Preset load），R_TRIG 上升沿把 nPreset 写入计数值 |
| nPreset | DINT | IN | 预置值（Preset value）[-]，任意 DINT 域 |
| bWrap | BOOL | IN | 回绕模式使能（Wrap-around enable），TRUE=上溢回 nMin/nMax 循环；FALSE=饱和钳位 |
| nMin | DINT | IN | 计数下限（Count lower limit）[-]，默认 -2147483648 常量提为 VAR CONSTANT |
| nMax | DINT | IN | 计数上限（Count upper limit）[-]，默认 2147483647 |
| nCompHigh | DINT | IN | 高阈值比较（High compare）[-]，bCompHigh 输出判据 |
| nCompLow | DINT | IN | 低阈值比较（Low compare）[-] |
| bReset | BOOL | IN | 上升沿复位故障与清零计数值 |
| nCount | DINT | OUT | 当前计数值（Current count）[-] |
| bCompHigh / bCompLow | BOOL | OUT | 高/低阈值比较结果（High/low compare output），每拍重算非锁存 |
| bOverflow / bUnderflow | BOOL | OUT | 上溢/下溢事件标志（Overflow/underflow event），脉冲沿发生置位一拍；饱和模式下计数值钳位 |
| bFault | BOOL | OUT | 故障标志（仅参数非法等故障级），排除信息级 |
| uErrorId | UDINT | OUT | 故障码（16#0001_xxxx 段） |

设计要点：
- 双脉冲同拍到达：视为一次 +1 与一次 -1 相互抵消（净变化 0），置信息级码提示，不计数——避免扫描时序歧义。
- 回绕语义：nCount > nMax 时回 nMin 继续；饱和语义：钳位并置 bOverflow 一拍。nMin ≥ nMax → 参数非法故障锁存【故障级】。
- bLoad 优先级最高（同拍覆盖计数脉冲，置信息级提示）。
- 故障集（建议，核对后顺延）：`0001_0210` 计数下限 ≥ 上限【故障级】、`0001_0220` 非法状态兜底【故障级】（CASE ELSE，如适用）、`0001_0101` 双脉冲抵消【信息级】、`0001_0102` 装载覆盖计数【信息级】。
- 验收向量：V1 增/减/抵消逐拍推演；V2 回绕跨上下限；V3 饱和钳位+溢出标志；V4 预置装载；V5 参数非法；V6 复位清零。

### 1.2 `FB_DL_ModuloCounter`（功能块）｜DL_Base｜来源标签 `lgf-counter`（RAW_NOTES S-1）

功能：循环计数器（转盘/弹夹工位索引）。0..(nMod-1) 取模回绕，支持步进方向、跳步与工位号合法性校验。与 FB_DL_EventCounter 职责分离（通用计数 vs 取模索引），非重复组件。**事件型，免首扫（R23）**。

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| bStepFwd | BOOL | IN | 前进步进脉冲（Step forward），R_TRIG 上升沿 +1 取模 |
| bStepRev | BOOL | IN | 后退步进脉冲（Step reverse），R_TRIG 上升沿 -1 取模 |
| bJump | BOOL | IN | 跳步指令（Jump to index），上升沿装载 nJumpTo（带合法性校验） |
| nJumpTo | UINT | IN | 跳步目标工位号（Jump target index）[-]，域 0..nMod-1 |
| nMod | UINT | IN | 循环模数（Modulo count，工位数）[-]，域 2..65535，禁止 0/1（除零与退化防御） |
| bReset | BOOL | IN | 上升沿复位故障与清零 |
| uIndex | UINT | OUT | 当前工位索引（Current index）[-]，0..nMod-1 |
| bWrapped | BOOL | OUT | 回绕事件标志（Wrapped event），跨零点步进置位一拍（转盘单圈计数用） |
| bFault | BOOL | OUT | 故障标志（排除信息级） |
| uErrorId | UDINT | OUT | 故障码（16#0001_xxxx 段） |

设计要点：
- 取模实现禁用 `%` 对负数的平台差异——用条件加减法（减 nMod / 加 nMod）实现回绕，注释写明跨平台意图（CODESYS/TwinCAT/汇川三平台 UINT 运算一致）。
- nMod < 2 → 参数非法故障锁存【故障级】；nJumpTo ≥ nMod → 跳步拒绝 + 信息级【信息级】。
- bStepFwd 与 bStepRev 同拍到达：抵消，置信息级。
- 故障集（建议）：`0001_0211` 模数非法【故障级】、`0001_0103` 跳步目标越界拒绝【信息级】、`0001_0104` 双向抵消【信息级】。
- 验收向量：V1 连续步进跨零回绕；V2 反向跨零；V3 合法/非法跳步；V4 模数=2 边界；V5 复位。

---

## 第 2 节 泳道 A｜DL_Device 收尾件五族（10 项）

> 本轮 DL_Device 一次性收口 ROADMAP 第四章剩余全部 8 项收尾件（扫码枪/安全门/光幕/流量计 4 族 8 件）+ 新增料位开关族 2 件。五族接口全部遵循 S-2 TcOpen 三段式范式（属性 + 方法 ≤6 + 状态枚举），实现遵循既有「cmd/ind 命令-反馈分离」家族范式。

### 2.1 `I_DL_BarcodeScanner`（接口）｜DL_Device｜来源标签 `tcopen-component` / `scanner-handshake`（RAW_NOTES S-2/S-3）

功能：工业固定式扫码枪标准抽象接口。路由分拣、批次追溯、上下料校验等 DL_Process 模板依赖注入件。

- 状态枚举（随接口同文件）`E_DL_ScannerState`：eIdle(0)/eTriggered(10)/eReading(20)/eOk(30)/eNoRead(40)/eFault(99)，编号步长 10、双语注释、eFault 末位。
- 属性（PROPERTY GET）：`eState`、`bReady : BOOL`（就绪可触发 Scanner ready）、`bReadOk : BOOL`（解码成功且结果有效 Read OK）、`bNoRead : BOOL`（未读到 NoRead）、`sBarcode : STRING`（最近有效条码字符串，长度 ≤255）、`nReadCount : UDINT`（累计成功解码次数）、`bFault : BOOL`、`uErrorId : UDINT`（段位 16#0003_xxxx）。
- 方法（3 个，≤6）：`CmdTrigger() : BOOL`（触发一次解码，非 eIdle/eFault 态拒绝返回 FALSE）；`CmdAck() : BOOL`（应答清除结果保持位，触发下一次解码前提）；`CmdReset() : BOOL`（复位故障）。
- 边界防错：故障态一律拒绝方法；接口层不做任何串口/总线收发（数据经实现块 IN_OUT 注入）。

### 2.2 `FB_DL_SerialScanner`（功能块，实现 I_DL_BarcodeScanner）｜DL_Device｜来源标签 `tcopen-component` / `scanner-handshake`（RAW_NOTES S-3）

功能：扫码枪触发-结果握手状态机实现（串口/现场总线数据本体由上层注入，本块只编排握手）。一次 NOREAD 自动重试、二次升级故障；结果按长度校验收纳。

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| bCmdTrigger | BOOL | IN | 触发指令（Trigger command），R_TRIG 上升沿单发；电平不连发 |
| bCmdAck | BOOL | IN | 应答指令（Acknowledge），上升沿清除结果保持位 |
| bReset | BOOL | IN | 上升沿复位故障 |
| sRawData | STRING | IN_OUT | 扫码枪原始接收字符串（Raw received string，含 CR/LF 终止符），由串口/总线接收层写入；本块只读 |
| bDataNew | BOOL | IN | 新数据标志（New data flag），接收层置位、本块消费后经 bDataAck 输出清除 |
| bDataAck | BOOL | OUT | 新数据消费应答（Data consumed ack），接收层据此清 bDataNew |
| bDevReady | BOOL | IN | 扫码枪就绪反馈（Device ready，可选），TRUE=可触发；恒 FALSE 时跳过就绪门控（信息级提示一次） |
| sNoReadMark | STRING | IN | NOREAD 标记字符串（NoRead marker），域如 'NOREAD'；长度 0=按超时判定 |
| tResultWindow | TIME | IN | 结果等待窗口（Result window），默认 T#1S，域 100MS~10S |
| nRetryMax | USINT | IN | 最大自动重试次数（Max retry），默认 1，域 0~5；0=不重试 |
| sBarcode / nReadCount / bReady / bReadOk / bNoRead / eState / bFault / uErrorId | — | OUT | 接口属性映射（R22） |
| bTriggerOut | BOOL | OUT | 扫码枪触发输出（Trigger output），单拍脉冲语义由实现以 TP 自清时序承载（**R24 范式：自清在实例调用之后**） |

设计要点：
- 状态机 `E_DL_ScannerState` + CASE + ELSE（ELSE → eFault）。
- 序列：eIdle →（触发沿 + 就绪）eReading：置 bTriggerOut 单拍 → 等结果窗内 bDataNew → 判 sRawData 非空且 ≠ sNoReadMark → eOk 锁存 sBarcode；超窗/空串/标记串 → 重试计数 < nRetryMax 再发 → 仍失败 → eNoRead（信息级）→ 累计连续 NoRead 达 3 次（常量提为 VAR CONSTANT）升级故障【故障级】。
- sRawData 长度校验：> 255 截断并置信息级；先 FC 风格去终止符再锁存。
- 结果消费链：eOk 态调用方 CmdAck → 清 sBarcode/bReadOk → eIdle。
- R24 验收向量必含三段逐拍推演（触发置位→枪响应→自清后），防 TP 自清同模板致命缺陷复发。
- 故障集（建议，0003 段核对顺延）：`0003_0250` 连续 NoRead 超限【故障级】、`0003_0251` 设备长时间无就绪【故障级】、`0003_0101` 条码超长截断【信息级】、`0003_0102` 无设备就绪门控跳过【信息级】、`0003_0252` 非法状态兜底【故障级】。
- 验收向量：V1 正常解码全链；V2 NoRead→重试→成功；V3 NoRead→升级故障；V4 超长截断；V5 Ack 消费链；V6 R24 三段推演。

### 2.3 `I_DL_SafetyDoor`（接口）｜DL_Device｜来源标签 `tcopen-component` / `safety-interlock`（RAW_NOTES S-2/S-4）

功能：安全门联锁标准抽象接口（电磁锁扣门）。**定位声明（公约 0.13）**：逻辑编排与诊断镜像层，非认证安全功能。

- 状态枚举 `E_DL_SafetyDoorState`：eIdle(0)/eLocked(10)/eStopRequested(20)/eStandstillConfirmed(30)/eUnlocked(40)/eOpened(50)/eFault(99)。
- 属性：`eState`、`bClosed : BOOL`（门已关闭 Door closed）、`bLocked : BOOL`（锁已闭锁 Lock engaged）、`bUnlockPermitted : BOOL`（允许解锁 Unlock permitted）、`bOpened : BOOL`（门开启 Door open）、`bFault : BOOL`、`uErrorId : UDINT`（段位 16#0003_xxxx）。
- 方法（4 个）：`CmdRequestUnlock() : BOOL`（请求解锁：发起停机请求并进入解锁时序）；`CmdRelock() : BOOL`（重新闭锁指令）；`CmdReset() : BOOL`（复位故障）；`CmdAuditClear() : BOOL`（清除开门审计记录，供批次收尾调用）。
- 边界防错：门开态下拒绝 CmdRelock 之外的全部动作；接口层不写物理输出。

### 2.4 `FB_DL_GuardLockDoor`（功能块，实现 I_DL_SafetyDoor）｜DL_Device｜来源标签 `tcopen-component` / `safety-interlock`（RAW_NOTES S-4）

功能：带电磁锁扣安全门联锁控制器。时序骨架（ISO 14119 公开语义 clean-room）：请求解锁 → 停机请求输出 → 静止确认（零速反馈或 run-down 计时器二选一）→ 解锁输出 → 开门审计 → 关门再锁定 → 复位后才允许重启（禁止自动重启）。

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| bCmdUnlock | BOOL | IN | 解锁请求指令（Unlock request），上升沿发起解锁时序 |
| bCmdRelock | BOOL | IN | 重新闭锁指令（Relock command），电平生效 |
| bReset | BOOL | IN | 上升沿复位故障与重启抑制 |
| bDoorClosed | BOOL | IN | 门关闭反馈（Door closed feedback），TRUE=门已关；NC 语义由接线层保证 |
| bLockEngaged | BOOL | IN | 锁闭反馈（Lock engaged feedback），TRUE=机械锁扣已闭 |
| bStandstill | BOOL | IN | 静止确认反馈（Standstill feedback，可选零速信号），TRUE=危险运动已停止 |
| bUseStandstillFb | BOOL | IN | 静止反馈使能（Standstill feedback enable），TRUE=用 bStandstill 判静止；FALSE=用 run-down 计时器 |
| tRunDown | TIME | IN | 停机走完计时（Run-down time），默认 T#5S；按实测最差停机时间整定（制动维护后重测，注释写明） |
| bUnlockCoil | BOOL | OUT | 解锁电磁铁输出（Unlock solenoid coil），断电解锁方向（失电=保持锁定，弹簧锁语义） |
| bStopRequest | BOOL | OUT | 停机请求输出（Stop request），解锁时序中置位直到静止确认 |
| bClosed / bLocked / bUnlockPermitted / bOpened / eState / bFault / uErrorId | — | OUT | 接口属性映射（R22） |
| uOpenCount | UDINT | OUT | 开门次数审计（Open audit count） |

设计要点：
- 解锁链硬约束：`bUnlockCoil` 置位前提 = （bStandstill 或 tRunDown 计满）AND bDoorClosed AND bLockEngaged；三条件不满足时解锁输出恒断（出口断言式写法）。
- 不合理组合诊断：门开 + 锁闭反馈同时为真 → 防篡改冲突【故障级】（S-4 提取点 ②）。
- 关门再锁定：bDoorClosed 沿 → 锁闭反馈确认窗（TON，默认 T#2S 可配为内部常量+引脚覆盖）内未闭 → 故障。
- 重启抑制：故障/开门事件后必须 bReset 且门锁全确认才回 eIdle；无任何自动重启路径。
- 故障集（建议）：`0003_0260` 静止确认超时（解锁链未达成）【故障级】、`0003_0261` 门锁不合理组合（防篡改冲突）【故障级】、`0003_0262` 再锁定超时【故障级】、`0003_0105` run-down 计时器模式提示（非零速实测）【信息级】、`0003_0263` 非法状态兜底【故障级】。
- 验收向量：V1 解锁全链（零速模式）；V2 run-down 模式计时链；V3 静止确认超时；V4 防篡改冲突注入；V5 开门审计与再锁定；V6 复位后重启抑制。

### 2.5 `I_DL_LightCurtain`（接口）｜DL_Device｜来源标签 `tcopen-component` / `light-curtain-muting`（RAW_NOTES S-2/S-5）

功能：安全光幕监控与屏蔽（Muting）标准抽象接口。**定位声明（公约 0.13）**适用。

- 状态枚举 `E_DL_CurtainState`：eClear(0)/eBlocked(10)/eMuting(20)/eOverride(30)/eFault(99)。
- 属性：`eState`、`bClear : BOOL`（光幕通光 Clear）、`bMutingActive : BOOL`（屏蔽进行中 Muting active）、`bOverrideActive : BOOL`（滞留清除进行中 Override active）、`bSafeStop : BOOL`（应停机输出：光幕被遮挡且未屏蔽），本接口核心安全镜像位、`bFault : BOOL`、`uErrorId : UDINT`（段位 16#0003_xxxx）。
- 方法（3 个）：`CmdOverride() : BOOL`（滞留物清除请求，前提至少一个屏蔽传感器仍遮挡，否则拒绝）；`CmdAck() : BOOL`（屏蔽/故障确认复位）；`CmdReset() : BOOL`（复位故障与重启联锁）。
- 边界防错：bSafeStop 输出永不因屏蔽/override 置假——屏蔽态下 bSafeStop 断言恒 FALSE（光幕正常）。

### 2.6 `FB_DL_SafetyLightCurtain`（功能块，实现 I_DL_LightCurtain）｜DL_Device｜来源标签 `tcopen-component` / `light-curtain-muting`（RAW_NOTES S-5）

功能：光幕 OSSD 监控 + 2/4 传感器序列屏蔽状态机 + 屏蔽超时 + 滞留清除 override + 屏蔽灯输出 + 复位联锁（SICK mut_p / 西门子 Sequential Muting 公开语义 clean-room）。

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| bOssd1 / bOssd2 | BOOL | IN | 光幕 OSSD 双通道（OSSD channel 1/2），TRUE=通光；两通道不一致超窗 → 故障 |
| bMutSens1 / bMutSens2 | BOOL | IN | 屏蔽传感器 1/2（Muting sensor 1/2），2 传感器模式使用；TRUE=被遮挡 |
| bMutSens3 / bMutSens4 | BOOL | IN | 屏蔽传感器 3/4（Muting sensor 3/4），4 传感器模式使用；2 传感器模式恒 FALSE |
| bFourSensorMode | BOOL | IN | 四传感器模式选择（Four-sensor mode），TRUE=序列式 4 传感器；FALSE=2 传感器 |
| bEnableMuting | BOOL | IN | 屏蔽功能总使能（Muting enable），FALSE=任何屏蔽条件都不生效（纯防护模式） |
| bOverrideKey | BOOL | IN | 滞留清除钥匙开关（Override key，双通道语义由接线层保证），电平保持式 |
| bReset | BOOL | IN | 复位按钮（Reset），上升沿复位故障与重启联锁 |
| tMutingTimeout | TIME | IN | 屏蔽总时长上限（Muting timeout），默认 T#30S，域 1S~600S；首末传感器间隔超限 → 故障 |
| tDiscrepancy | TIME | IN | 传感器容差窗（Sensor discrepancy time），默认 T#3S，域 100MS~10S |
| tOverrideMax | TIME | IN | 滞留清除硬帽（Override max time），默认 T#30S，域 1S~60S |
| bSafeStop / bClear / bMutingActive / bOverrideActive / eState / bFault / uErrorId | — | OUT | 接口属性映射（R22） |
| bMutingLamp | BOOL | OUT | 屏蔽灯输出（Muting lamp）：屏蔽常亮、override 闪烁（T#250MS 方波，常量提为 VAR CONSTANT） |

设计要点：
- 序列状态机（4 传感器正向 M1→M2→M3→M4 / 反向镜像；2 传感器 M1→M2）：序列错乱或时序超容差窗 → 立即退出屏蔽 + bSafeStop 按光幕实际状态输出 + 故障【故障级】（S-5 提取点 ①③④）。
- override 准入硬约束：`bOverrideKey AND (bMutSens1..4 至少一真)` 才进入 eOverride；无遮挡拒绝（S-5 提取点 ⑤），拒绝置信息级。
- 屏蔽灯闪烁用主周期累加翻转自实现（TON 不适用方波生成，用时间戳累积法；R14 断输入一拍规则不涉及，注释说明）。
- OSSD 双通道不一致超 tDiscrepancy → 故障锁存。
- 故障集（建议）：`0003_0270` 屏蔽传感器序列错误【故障级】、`0003_0271` 屏蔽超时【故障级】、`0003_0272` OSSD 双通道不一致【故障级】、`0003_0106` override 准入拒绝（无遮挡）【信息级】、`0003_0273` 非法状态兜底【故障级】。
- 验收向量：V1 无屏蔽遮挡停机链；V2 2 传感器合法序列屏蔽→货物通过→退出；V3 序列错乱停机；V4 屏蔽超时故障；V5 override 准入/拒绝/硬帽；V6 OSSD 不一致；V7 复位联锁。

### 2.7 `I_DL_FlowMeter`（接口）｜DL_Device｜来源标签 `tcopen-component` / `flow-totalizer`（RAW_NOTES S-2/S-6）

功能：流量计标准抽象接口（脉冲型/模拟型均可适配）。

- 状态枚举 `E_DL_FlowMeterState`：eIdle(0)/eMeasuring(10)/eFlowOk(20)/eLowCutoff(30)/eFault(99)。eLowCutoff = 低流量截止态（有效但被截零）。
- 属性：`eState`、`fFlowRate : REAL`（瞬时流量 [L/min]，按 K 系数域换算）、`fTotal : LREAL`（累计总量 [L]，LREAL 防累计精度丢失）、`nPulseCount : UDINT`（窗口内脉冲计数原始值）、`bFault : BOOL`、`uErrorId : UDINT`（段位 16#0003_xxxx）。
- 方法（3 个）：`CmdTotalReset() : BOOL`（总量清零，批控切换零点）；`CmdTotalPreset(fPreset : LREAL) : BOOL`（总量预置）；`CmdReset() : BOOL`（复位故障）。
- 边界防错：接口层不读物理输入；累计溢出防护在实现块。

### 2.8 `FB_DL_PulseFlowMeter`（功能块，实现 I_DL_FlowMeter）｜DL_Device｜来源标签 `tcopen-component` / `flow-totalizer`（RAW_NOTES S-6，T1-1 OSCAT Basic ◐ 深化旁证）

功能：脉冲型流量计瞬时流量与累计总量计量。脉冲沿计数 → 滑动窗频率估计 → K 系数换算；总量按脉冲计数法累计（精度优于流量积分法）；低流量截止；K 系数防除零。滑动窗计数为 Device 层内联实现（依赖方向合规：不引 DL_MathData 组件，注释注明）。

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| bPulseIn | BOOL | IN | 脉冲输入（Pulse input），R_TRIG 上升沿计数；硬件滤波由输入层保证 |
| bCmdTotalReset | BOOL | IN | 总量清零指令（Total reset），上升沿生效 |
| fKFactor | REAL | IN | 流量计 K 系数（K-factor）[pulses/L]，域 > 0，默认 100.0；标定证书值 |
| tSampleWindow | TIME | IN | 频率估计采样窗（Sample window），默认 T#1S，域 100MS~10S；低流量场景增大 |
| fLowCutoff | REAL | IN | 低流量截止阈值（Low-flow cutoff）[L/min]，默认 0.5；低于阈值输出置零 |
| tPulseTimeout | TIME | IN | 脉冲丢失超时（Pulse timeout），默认 T#5S；运行中窗口超时无脉冲 → 流量置零 + 信息级 |
| bReset | BOOL | IN | 上升沿复位故障 |
| fFlowRate / fTotal / nPulseCount / eState / bFault / uErrorId | — | OUT | 接口属性映射（R22） |
| bTotalNearLimit | BOOL | OUT | 总量接近溢出预警（Total near limit），fTotal > 9.0E15 时置位（LREAL 整数精度边界） |

设计要点：
- 瞬时流量：采样窗内脉冲数 nP / 窗秒数 / fKFactor × 60 → [L/min]；窗计数用双缓冲（计数中缓冲 + 窗沿交换）避免读撕裂。
- 除零防御三处：fKFactor ≤ 1E-6 → 参数故障锁存；窗秒数恒 ≥ 采样窗常量非零；周期法不使用（统一窗法，简化跨平台）。
- 低流量截止：fFlowRate < fLowCutoff → 输出置零 + eState=eLowCutoff【信息级】。
- fTotal 以脉冲计数法：fTotal += (窗脉冲数)/fKFactor；总量清零沿单发。
- 脉冲频率上限防御：单窗脉冲数超常量上限（VAR CONSTANT，如 10000）→ 频率超量程【信息级】（提示输入层配置 HSC）。
- 故障集（建议）：`0003_0280` K 系数非法【故障级】、`0003_0107` 低流量截止激活【信息级】、`0003_0108` 脉冲丢失超时【信息级】、`0003_0109` 窗内频率超量程【信息级】。
- 验收向量：V1 已知脉冲序列换算逐拍复算；V2 总量累计与清零；V3 低流量截止；V4 K 系数非法；V5 脉冲丢失；V6 双缓冲无撕裂推演。

### 2.9 `I_DL_LevelSwitch`（接口）｜DL_Device｜来源标签 `tcopen-component` / `level-switch-failsafe`（RAW_NOTES S-2/S-7）

功能：料位开关标准抽象接口（振动叉/阻旋/电容等点式料位开关通用）。高点溢流与低点干转联锁的统一契约。

- 状态枚举 `E_DL_LevelState`：eNoMaterial(0)/eMaterial(10)/eSensorLoss(20)/eFault(99)。eSensorLoss = 传感器失效态（按失效安全方向归一后的镜像）。
- 属性：`eState`、`bMaterial : BOOL`（有料判定输出，已按失效安全方向归一）、`bHighAlarm : BOOL`（高点溢流联锁输出，fail-safe HIGH 语义）、`bLowAlarm : BOOL`（低点干转联锁输出，fail-safe LOW 语义）、`bFault : BOOL`、`uErrorId : UDINT`（段位 16#0003_xxxx）。
- 方法（2 个）：`CmdReset() : BOOL`（复位故障）；`CmdTest() : BOOL`（传感器功能测试请求，输出镜像进入测试态一拍）。
- 边界防错：接口层不做检测算法（检测本体在传感器内部）。

### 2.10 `FB_DL_LevelSwitchVib`（功能块，实现 I_DL_LevelSwitch）｜DL_Device｜来源标签 `tcopen-component` / `level-switch-failsafe`（RAW_NOTES S-7）

功能：振动叉式料位开关信号处理块。原始开关防抖 → 失效安全方向归一（fail-safe HIGH/LOW 可选）→ 覆盖/裸露双延迟 → 有料/无料双联锁输出 + 传感器失效诊断。

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| bRawSwitch | BOOL | IN | 传感器原始开关信号（Raw switch signal），TRUE=触点动作（介质覆盖叉体，按传感器定义） |
| eFailSafeMode | E_DL_FailSafeMode | IN | 失效安全模式（Fail-safe mode），eHigh=失效报有料（防溢流）/eLow=失效报无料（防干转）；枚举随本块接口文件发布 |
| tDebounce | TIME | IN | 防抖窗口（Debounce），默认 T#200MS |
| tCoverDelay | TIME | IN | 覆盖确认延迟（Cover delay），默认 T#1S，防液面波动误翻转 |
| tBareDelay | TIME | IN | 裸露确认延迟（Bare delay），默认 T#1S |
| bEnable | BOOL | IN | 处理使能（Processing enable），FALSE=输出按失效安全方向强制镜像 |
| bReset | BOOL | IN | 上升沿复位故障 |
| bMaterial / bHighAlarm / bLowAlarm / eState / bFault / uErrorId | — | OUT | 接口属性映射（R22） |
| bSensorTest | BOOL | OUT | 传感器测试态镜像（Sensor test mirror），CmdTest 期间一拍 |

设计要点：
- 失效安全归一核心：`bMaterial := bRawSwitch XOR (eFailSafeMode = eLow)` 的语义等价式（用 IF 显式写，禁 XOR 技巧裸用）；bEnable=FALSE 或传感器失效时输出强制归一到安全侧。
- 高/低联锁方向：bHighAlarm = 失效安全归一后的「有料」且本开关组态为高点用途（eFailSafeMode=eHigh 时失效即报警）；bLowAlarm 同理反向——两输出的方向语义在注释中写死，防现场接反。
- 覆盖/裸露双延迟：TON ×2 在主体前部无条件刷新（R7）。
- 故障集（建议）：`0003_0290` 失效安全模式枚举越界【故障级】、`0003_010a` 传感器信号静默提示（长时无变化+测试无响应为可选诊断，本轮仅预留信息级）【信息级】。
- 验收向量：V1 有料/无料双延迟切换逐拍；V2 fail-safe HIGH 断线注入→报警；V3 fail-safe LOW 断线注入→干转报警；V4 使能切断强制镜像；V5 复位。

---

## 第 3 节 泳道 B｜DL_Process（3 项）

### 3.1 `FB_DL_OeeCalculator`（功能块）｜DL_Process｜来源标签 `packml-oee`（RAW_NOTES S-8）

功能：设备综合效率（OEE）班次级统计引擎。OEE = 时间开动率 × 性能开动率 × 合格品率（oee.com / ISO 22400-2 公开口径）。停机时间经 PackML 根因位语义分账（计划停机 vs 计划外停机），与 `FB_DL_PackMlStateMachine` 17 态衔接（引脚注入根因位，不引组件实例）。

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| bMachineRunning | BOOL | IN | 设备运行中（Machine running），TRUE=运行时间累加 |
| bPlannedDown | BOOL | IN | 计划停机中（Planned downtime，换型/休息/保养），TRUE=计划停机累加 |
| bUnplannedDown | BOOL | IN | 计划外停机中（Unplanned downtime，故障/缺料），TRUE=计划外停机累加；与 bPlannedDown 同真 → 信息级（分账歧义） |
| bHeldByMachine | BOOL | IN | 设备侧保持根因位（Held by machine root cause，PackML Held 语义），参与计划外停机细分 |
| bSuspendedByLine | BOOL | IN | 产线侧暂停根因位（Suspended by line root cause，PackML Suspended 语义） |
| bPartFinished | BOOL | IN | 完工计数脉冲（Part finished pulse），R_TRIG 上升沿 +1 总数 |
| bPartRejected | BOOL | IN | 不合格计数脉冲（Part rejected pulse），上升沿 +1 不合格数 |
| fIdealCycleTime | REAL | IN | 理想节拍（Ideal cycle time）[s]，域 > 0，默认 10.0 |
| tShiftLength | TIME | IN | 班次总时长（Shift length），默认 T#8H |
| bShiftStart | BOOL | IN | 班次开始指令（Shift start），上升沿清零全部累计并启动统计 |
| bShiftEnd | BOOL | IN | 班次结束指令（Shift end），上升沿冻结三因子输出 |
| bReset | BOOL | IN | 上升沿复位故障 |
| fAvailability | REAL | OUT | 时间开动率（Availability）[%]，0~100 |
| fPerformance | REAL | OUT | 性能开动率（Performance）[%]，0~100，封顶 100 |
| fQuality | REAL | OUT | 合格品率（Quality）[%]，0~100，零产量取 100 |
| fOee | REAL | OUT | 设备综合效率（OEE）[%]，三因子连乘 |
| nTotalCount / nGoodCount / nRejectCount | UDINT | OUT | 总数/合格数/不合格数（Total/good/reject count） |
| tPlannedTime / tRunTime / tDownTime | TIME | OUT | 计划生产时间/运行时间/停机时间累计（Planned/Run/Down time） |
| bFault / uErrorId | — | OUT | 故障标志与码（16#0005_xxxx 段） |

设计要点：
- 时间累计主周期累加式（扫描周期自测经既有 FB_DL_CycleTimeMeasure 语义由调用方注入 tCycleTime 引脚——**新增引脚**：`tCycleTime : TIME IN`，默认 T#10MS，累计基准）。
- 三因子除零防御：PlannedTime=0 → 全因子 0 + 信息级；RunTime=0 → Availability 0 / Performance 0 / Quality 100；TotalCount=0 → Quality 100。
- Performance = (fIdealCycleTime × nTotalCount) / RunTime 秒，>100 封顶并置信息级（负损失提示：节拍偏短或计数异常）。
- 根因位分账：bHeldByMachine/bSuspendedByLine 仅在 bUnplannedDown 期间细分统计（uDownReason 输出可选——本轮输出 `nUnplannedByHold / nUnplannedBySuspend : UDINT` 计数）。
- 故障集（建议）：`0005_0200` 理想节拍非法【故障级】、`0005_0100` 双停机根因同真【信息级】、`0005_0101` 性能率超 100 封顶【信息级】、`0005_0102` 零计划时间【信息级】。
- 验收向量：V1 oee.com 标准算例复算（420min/373min/19271 件等价缩放向量）；V2 零产量 Quality=100；V3 双停机歧义；V4 性能封顶；V5 班次启停冻结。

### 3.2 `FB_DL_ConveyorZone`（功能块）｜DL_Process｜来源标签 `conveyor-accumulation`（RAW_NOTES S-9）

功能：单段皮带/滚筒输送线积放控制器（Zero-Pressure Accumulation 单区）。积放单句规则：有料且下游允许才走；卡料窗判定；run-on 清区；级联放行信号。消费 `I_DL_VfdDrive`（既有接口，引脚注入接口引用实现驱动控制）。

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| iDrive | I_DL_VfdDrive | IN_OUT | 本区驱动接口引用（Zone drive），由上层注入实例 |
| bPEEntry | BOOL | IN | 入口光电（Entry photoeye），TRUE=有料进入本区 |
| bPEDischarge | BOOL | IN | 出口光电（Discharge photoeye），TRUE=料仍在本区出口未清 |
| bDownstreamReady | BOOL | IN | 下游允许放行（Downstream ready），末区接下游工序就绪；中区接下区 bZoneReady 输出 |
| bZoneEnable | BOOL | IN | 本区使能（Zone enable），FALSE=驱动停止且请求清零 |
| bUpstreamOcc | BOOL | IN | 上区有料（Upstream occupied，可选过渡联动），TRUE=本区为空也补跑合拢 |
| tRunOn | TIME | IN | 清区延续时间（Run-on time），默认 T#1S；出口光电清空后再运行此窗 |
| tJamWindow | TIME | IN | 卡料判定窗（Jam window），默认 T#8S；按区长度/带速整定 |
| tStartDelay | TIME | IN | 启动确认延迟（Start feedback delay），默认 T#500MS |
| bCmdRelease | BOOL | IN | 手动放行指令（Manual release，调试用），上升沿短时放行 |
| bReset | BOOL | IN | 上升沿复位卡料与故障 |
| bDriveRun | BOOL | OUT | 本区运行指令（Drive run command），经 iDrive.CmdRun() 承载（接口方法映射，R11 留档） |
| bZoneReady | BOOL | OUT | 本区就绪（Zone ready），运行无故障且可接收上游来料 |
| bOccupied | BOOL | OUT | 本区有料（Zone occupied），入口或出口光电任一遮挡 |
| bJam | BOOL | OUT | 卡料锁存（Jam latched） |
| eState : E_DL_ZoneState | OUT | OUT | 区状态机：eStopped/eRunning/eAccumulating/eJamFault（枚举随本块文件发布，双语注释） |
| bFault / uErrorId | — | OUT | 故障标志与码（16#0005_xxxx 段） |

设计要点：
- 积放核心：RunReq = bZoneEnable AND NOT bJam AND（bOccupied OR bUpstreamOcc）AND（bDownstreamReady OR bPEDischarge=FALSE 或末区语义由 bDownstreamReady 承担）；末区特殊语义由调用方接线决定（bDownstreamReady 接工序就绪），本块不内判末区（注释写明）。
- 驱动控制经 iDrive：调用 iDrive.CmdRun()/CmdStop()；反馈读 iDrive.bRunning/bFault；指令-反馈失配超 tStartDelay → 驱动故障【故障级】（S-9 提取点 ⑥）。
- 卡料：RunReq 持续 + bPEDischarge 持续遮挡超 tJamWindow → bJam 锁存（仅 bReset 清）。
- 浪涌防护：bZoneEnable 从 FALSE→TRUE 的上升沿后延迟 tStartDelay 再发运行指令（S-9 提取点 ⑤ 间隔释放由多实例 bZoneReady 级联天然承载）。
- 接口方法调用频次：每拍至多一次方法调用；方法返回值 FALSE 且接口 bFault → 本区故障透传。
- 故障集（建议）：`0005_0210` 驱动指令-反馈失配【故障级】、`0005_0211` 下游驱动故障透传【故障级】、`0005_0212` 非法状态兜底【故障级】、`0005_0103` 卡料预警（未到窗）【信息级】。
- 验收向量：V1 有料放行/积存/清区 run-on 逐拍；V2 下游阻断积放充满；V3 卡料窗锁存+复位；V4 驱动失配；V5 上区补跑；V6 手动放行。

### 3.3 `FB_DL_BatchDosingControl`（功能块）｜DL_Process｜来源标签 `lbp-batch-dosing` / `isa-88`（RAW_NOTES S-10）

功能：多原料单通道自动配料称重控制器（单料批次相 Phase 语义）。三段给料顺控（快加→慢加→落定结算）+ 空中落差自学习（误差/2 更新，防振荡）+ 超差 NG 判定 + 断流诊断。执行机构抽象为三离散输出（与给料机/闸门类型解耦）；秤重量 LREAL 引脚注入。

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| bCmdBatchStart | BOOL | IN | 批次启动指令（Batch start），上升沿进入快加 |
| bCmdAbort | BOOL | IN | 批次中止指令（Abort），电平生效，立即关全部输出 |
| fWeight | REAL | IN | 秤实时重量（Live weight）[kg]，非有限值防御；标定由称重层完成 |
| fTareOffset | REAL | IN | 皮重偏移（Tare offset）[kg]，默认 0.0；净重 = fWeight − fTareOffset |
| fSetpoint | REAL | IN | 批次目标净重（Batch setpoint）[kg]，域 > 0 |
| fSwitchCoarse | REAL | IN | 快加切换点（Coarse-to-fine switch）[kg]，默认 = 85% 设定值（引脚覆盖，注释写明默认语义） |
| fInflightComp | REAL | IN_OUT | 空中落差补偿（In-flight compensation）[kg]，学习值跨批次保持；上下限由 fCompLimit 钳位 |
| fCompLimit | REAL | IN | 补偿学习限幅（Compensation limit）[kg]，默认 = 10% 设定值 |
| bLearnEnable | BOOL | IN | 落差自学习使能（Learning enable），TRUE=每批结算后按误差/2 更新 |
| tSettleWindow | TIME | IN | 落定稳窗（Settle window），默认 T#1S，域 500MS~5S |
| fTolerance | REAL | IN | 批次公差（Batch tolerance）[kg]，默认 = 0.5% 设定值语义，引脚显式 |
| tFlowWatch | TIME | IN | 断流监视窗（Flow watchdog），默认 T#10S；给料中重量变化率恒零超窗 → 断流 |
| fFlowDeadband | REAL | IN | 断流判据死区（Flow deadband）[kg]，默认 0.05；稳窗内重量变化 < 死区判断流 |
| bOutCoarse | BOOL | OUT | 快加输出（Coarse feed output），给料机/闸门快加速率 |
| bOutFine | BOOL | OUT | 慢加输出（Fine feed output） |
| bOutDischarge | BOOL | OUT | 卸料输出（Discharge output，批次合格后放料） |
| ePhase : E_DL_DosingPhase | OUT | OUT | 批次相：eIdle/eCoarse/eFine/eSettling/eDone/eNg/eAbort/eFault（枚举随本块文件发布） |
| fNetWeight | REAL | OUT | 当前净重（Net weight）[kg] |
| fFinalWeight | REAL | OUT | 上批次结算净重（Final weight）[kg]，落定后锁存 |
| bBatchOk | BOOL | OUT | 批次合格（Batch OK），fAbs(fFinalWeight−fSetpoint) ≤ fTolerance |
| bFault / uErrorId | — | OUT | 故障标志与码（16#0005_xxxx 段） |

设计要点：
- 截断点公式：慢加关断重量 = fSetpoint − fInflightComp（S-10 提取点 ②）；fInflightComp 初值 0 → 首批必然过冲 → 学习链收敛（注释写明首批预期）。
- 自学习更新：结算后 Error = fFinalWeight − fSetpoint；IF bLearnEnable THEN fInflightComp := fInflightComp + Error/2.0，钳位 ±fCompLimit（S-10 提取点 ③⑤；半误差防振荡语义在注释注明）。
- 稳窗判稳：tSettleWindow 内重量变化 < fFlowDeadband 才结算（防未落定读数）；超窗未稳 → 结算按当前值 + 信息级。
- 断流诊断：给料相中连续 tFlowWatch 重量变化 < fFlowDeadband → 断流【故障级】（快加/慢加独立监视计时重启）。
- 过冲超差 → eNg 锁存 + 卸料输出禁止（NG 不得流入下工序）；Abort 优先级最高（CASE 首分支）。
- 非有限值 fWeight → 批次中止【故障级】，输出全断。
- 故障集（建议）：`0005_0220` 断流/堵料【故障级】、`0005_0221` 秤信号无效【故障级】、`0005_0222` 非法状态兜底【故障级】、`0005_0104` 稳窗超时按当前值结算【信息级】、`0005_0105` 补偿学习触限【信息级】。
- 验收向量：V1 三段给料逐拍（切换点/截断点）；V2 学习链 5 批收敛数值复算（误差/2）；V3 补偿限幅；V4 断流；V5 超差 NG+卸料禁止；V6 中止优先级；V7 非有限值注入。

---

## 第 4 节 泳道 C｜DL_Motion 补充件（1 项）

### 4.1 `FB_DL_SoftLimitGuard`（功能块）｜DL_Motion｜来源标签 `plcopen-motion`（RAW_NOTES S-11，T1-6 ◐ 深化）

功能：软限位安全电子围栏预判器。根据当前速度与减速度实时计算双向制动距离（含扫描/IO/驱动时延项），提前拦截超程指令；超程后仅允许反向指令。**定位声明（公约 0.13）**适用：应用层预判，非认证安全功能，硬限位开关仍是最终防线。

引脚：

| 引脚 | 类型 | 方向 | 注释基线 |
|---|---|---|---|
| iAxis | I_DL_MotionAxis | IN_OUT | 轴接口引用（Axis interface），由上层注入（既有契约）；读位置/速度/状态 |
| fPosLimitPos | REAL | IN | 正向行程边界（Positive travel limit）[mm]，域 > fPosLimitNeg |
| fPosLimitNeg | REAL | IN | 负向行程边界（Negative travel limit）[mm] |
| fDecel | REAL | IN | 拦截减速度（Guard deceleration）[mm/s²]，域 > 0，默认 500.0；按配置减速取保守值 |
| tLatency | TIME | IN | 系统-驱动总时延（System latency），默认 T#23MS（扫描 10 + IO 5 + 驱动 8ms 口径，注释写明三项来源） |
| fMargin | REAL | IN | 安全裕量（Safety margin）[mm]，默认 = 停止距离 × 25%（引脚显式化） |
| bEnable | BOOL | IN | 预判使能（Guard enable），FALSE=仅监视输出不拦截 |
| bReset | BOOL | IN | 上升沿复位故障（离开超程区并复位后方可恢复） |
| bWarnPos / bWarnNeg | BOOL | OUT | 正/负向预警（Positive/negative warning），进入「边界 − 停止距离」预判带即置位 |
| bInterceptPos / bInterceptNeg | BOOL | OUT | 正/负向拦截（Intercept），当前位置 + 预判停止距离越过边界即置位：调用方应禁止该方向指令并减速 |
| bInsideOk | BOOL | OUT | 双向行程内正常（Inside envelope） |
| fStopDistPos / fStopDistNeg | REAL | OUT | 实时正/负向预判停止距离（Predicted stop distance）[mm]，调试/HMI 用 |
| bFault / uErrorId | — | OUT | 故障标志与码（16#0004_xxxx 段） |

设计要点：
- 预判公式（S-11 提取点 ①）：fStopDist = fSpeed × tLatency_s + fSpeed² / (2 × fDecel)；tLatency 换算秒（TIME→REAL 秒，显式转换注释舍入意图）。
- 除零防御：fDecel ≤ 1E-6 → 参数故障锁存；fSpeed² 项在 fSpeed→0 时自然收敛。
- 位置/速度来源：iAxis.fPosition / iAxis.fVelocity（既有接口属性；若接口无速度属性则由调用方经新增 IN_OUT 引脚 `fAxisSpeed : REAL` 注入——编码前核对 I_DL_MotionAxis 契约，二选一并在 R11 留档）。
- 方向语义：bInterceptPos 置位期间仅允许负向指令（向内恢复豁免语义，S-11 提取点 ②）；本块输出建议信号，不直接阻断指令（拦截执行在调用方，注释写明职责边界）。
- 参数防御：fPosLimitPos ≤ fPosLimitNeg → 故障锁存【故障级】。
- 故障集（建议）：`0004_0220` 减速度非法【故障级】、`0004_0221` 行程边界非法【故障级】、`0004_0100` 时延口径提示（默认值与实际不符时建议实测）【信息级】。
- 验收向量：V1 已知速度/减速度停止距离数值复算（含时延项）；V2 预警带进入/退出；V3 双向拦截边界；V4 反向恢复豁免；V5 参数非法；V6 使能切断仅监视。

---

## 第 5 节 泳道优先级与执行顺序建议

1. **泳道 A 优先开跑**（10 项，占比最大，接口先行：先写 5 个 I_DL_* 再写实现，契约稳定后实现块可并行）。
2. 泳道 B 之 #14（ConveyorZone）依赖既有 I_DL_VfdDrive，可立即并行；#13/#15 无跨泳道依赖。
3. 泳道 C/D 体量小，随编随入。
4. 全部组件完成后执行：子库 VERSION.md / MANUAL / CHANGELOG / README / LIBRARY_MANUAL 五件套同步 + SOURCE_HUNTING_MATRIX 回写 + JSONL/INDEX 登记（由收尾/终审阶段执行，本计划阶段不回写）。

## 第 6 节 质量红线提示（编码侧重点防复发项）

1. **R24 范式必查**：#2.2 扫码枪触发单拍输出为 TP/定宽脉冲语义——自清必须位于实例调用之后；验收向量含三段逐拍推演（R6 两处致命缺陷的家族根因）。
2. **接口方法拒绝语义**：全部 I_DL_* 方法在 eFault 态返回 FALSE，不得静默成功。
3. **Device 层依赖方向**：#2.8 流量计滑动窗计数内联实现，禁止引用 DL_MathData 组件。
4. **安全组件声明**：#2.4 / #2.6 / #4.1 头部必含「非认证安全功能」定位声明（公约 0.13）。
5. **信息级/故障级混写防复发**：bFault 派生式显式排除信息级码（R21），终审逐块核对故障码表标注。
6. **枚举编号惯例**：新枚举步长 10、eFault=99 末位、双语同行注释（与 R6 全库口径一致）。

## 第 7 节 交付验收口径

- 16 项全部落地为底线目标；若终审裁定某项不达标，**宁减不凑**，允许 14~15 项交付并在战报注明裁撤原因与补位计划。
- 每组件验收向量按各节 V 清单执行；R24 相关向量逐拍推演不可省略。
- 子库版本预期：DL_Device v0.2.0 → v0.3.0（+10）、DL_Process v0.2.0 → v0.3.0（+3）、DL_Motion v0.2.0 → v0.2.1 或 v0.3.0（+1，按收尾口径）、DL_Base v1.x → MINOR 递增（+2）；总库 v1.5.0 → v1.6.0（终审阶段裁定）。
