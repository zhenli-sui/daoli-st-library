# RAW NOTES — Round 09（R9）狩猎留痕

> 日期：2026-11-15 ｜ 配套计划：`_Staging_Raw/2026-11-15/ROUND_PLAN_R9.md` ｜ 记录人：道莅工控代码库产品总监
> 记录口径：沿用 SOURCE_HUNTING_MATRIX 第 0 节三条铁律——每来源必填「来源名称 / URL / 许可证 / 提取点」；非开源闭源资料**只借功能分类体系、接口参数域定义、命名组织方式**，实现一律 clean-room 独立编写；GPL 类源零代码行接触。

## 0 本轮总体合规声明

- 本轮全部 16 个组件均为「**只借分类 / 参数域 / 命名，clean-room 实现**」：未复制任何来源的代码行、DB/结构体布局原文、注释原文；全部引脚契约、枚举编号、状态机、故障码位 100% 本库自有设计。
- 闭源版权资料（西门子 LGF / LBP / S7-1500 MC 手册）仅提取**公开手册中的功能分类与参数域定义**（各组名称、组件粒度、参数取值范围惯例），不提取任何实现细节。
- 开源资料（Apache-2.0 / MIT）仅借鉴结构分层思想与算法公开语义，文件头溯源字段如实标注「参考 XXX 分类与参数域，独立实现，不构成衍生作品」。
- 本轮 16 件预计行数约 5,920 行，全部按道莅八条红线重构（详见 ROUND_PLAN_R9.md 通用要求节）。

## 1 本轮来源清单（按源矩阵 T 编号）

| # | 来源名称 | URL | 许可证 | 提取点 | 对应组件 |
|---|---|---|---|---|---|
| S-1 | Siemens LGF（Library of General Functions）V5.3.0 · Data Handling 组公开手册 |西门子支持中心文档库，文档 ID 109479728（矩阵 T2-1 台账锚点）| 免费使用但闭源版权 | Data Handling 组的组件分类骨架与参数域：FIFO/LIFO/数组搜索/排序/环形缓冲的**组内粒度切分**与「容量/计数/指针诊断」参数域惯例 | ①FB_DL_FifoBuffer ②FB_DL_ArraySearchFirst ③FC_DL_BinarySearchLReal（lgf-datahandling）|
| S-2 | Siemens LGF V5.3.0 · Comparator 组公开手册 | 同上（文档 ID 109479728）| 同上 | Comparator 组的「区间判断 / 公差窗口 / 限值分档」分类骨架与公差带、迟滞、四阈值参数域惯例 | ④FB_DL_ToleranceWindow ⑤FC_DL_LimitClassify（lgf-comparator）|
| S-3 | Siemens LGF V5.3.0 · Converter 组公开手册 | 同上（文档 ID 109479728）| 同上 | Converter 组的「温度单位 / BCD / 字节序 / 格雷码」分类骨架与三温标枚举选择、BCD 半字节校验参数域惯例 | ⑥FC_DL_TempUnitConvert ⑦FC_DL_BcdToWord ⑧FC_DL_WordToBcd（lgf-converter）|
| S-4 | Siemens LGF V5.3.0 · Bit Logic 组公开手册 | 同上（文档 ID 109479728）| 同上 | Bit Logic 组的「位测试 / 置位 / 位段操作」分类骨架与「位偏移 + 位宽」参数化位段参数域惯例 | ⑨FC_DL_WordBitPack（lgf-bitlogic）|
| S-5 | Siemens LGF V5.3.0 · Date and Timer 组公开手册 | 同上（文档 ID 109479728）| 同上 | Date and Timer 组的「日历 / 周期窗」分类骨架与「月内第 N 天 / 月末倒数日」参数域惯例；闰年与月长行为定义沿用本库 FC_DL_DayOfWeekCalc 已沉淀口径（独立实现） | ⑩FB_DL_MonthWindowCheck（lgf-datetime）|
| S-6 | Siemens LGF V5.3.0 · Counter 组公开手册 | 同上（文档 ID 109479728）| 同上 | Counter 组的「事件 / 循环 / 预设计数」分类骨架与「带饱和不回绕」参数域惯例；与已入库 EventCounter / ModuloCounter 的职责分离口径（R7 已声明「带饱和预设计数待挖」） | ⑪FB_DL_PresetCounterSat（lgf-counter）|
| S-7 | Siemens S7-1500 Motion Control 公开手册（TO_PositioningAxis 叠加运动章节）| 西门子支持中心文档库（矩阵 T2-4 台账锚点）| 文档版权 | MC_MoveSuperimposed 公开语义：基础运动与叠加偏移正交叠加、偏移斜坡限速、零偏移归零（keep overlay active）行为定义——只提取行为语义域 | ⑫FB_DL_SuperimposedMove（s7-motion，双源之一）|
| S-8 | PLCopen TC3（Part 1~4）叠加运动与多命令公开语义 | www.plcopen.org（TC 规范公开页）| PLCopen 规范（免费公开）| 运动叠加的公开语义域：叠加命令与基础命令并行、幅值/速率限制、收敛判据惯例；与 S-7 互为印证 | ⑫FB_DL_SuperimposedMove（plcopen-motion，双源之一）|
| S-9 | GitHub 开源步进电机驱动项目（AccelStepper 及同类）| github.com/adafruit/AccelStepper 等公开仓库 | MIT | 开环步进「梯形加减速脉冲频率规划」公开算法思想与「脉冲当量 / 最大速度 / 加速度」参数域惯例——仅取算法思想与参数域，C++ 实现零复制 | ⑬I_DL_StepperOpenLoop ⑭FB_DL_PulseDirStepper（stepper，T1-8 开组）|
| S-10 | TcOpen 组件分层惯例（已开组 T1-5，沿用）| github.com/TcOpenGroup/TcOpen | Apache-2.0 | 「契约-实现分离 + 属性/方法三段式」接口分层思想（R7 已沉淀，本轮仅复用其范式，不新增提取点） | ⑬I_DL_StepperOpenLoop（接口设计范式）|
| S-11 | CODESYS Forge / Store 免费库 · ModbusFB 公开文档 | forge.codesys.com（ModbusFB / 免费库公开页面）| 逐页确认；本轮所据公开文档页未显式声明许可条款，按最严口径处置 | ModbusFB 的「主站轮询 / 站表 / 超时重试」组织分类与参数域（站数、超时、重试、轮询间隔惯例）；帧构造与校验归传输层的分层语义 | ⑮FB_DL_ModbusPollMaster（codesys-forge-modbus，T1-4 开族续挖）|
| S-12 | PackML / OMAC 人员响应域公开语义（Andon）| ISA-TR88.00.02 公开规范 + OMAC 包装机工作组建模惯例（矩阵 T2-7 台账锚点）| 公开规范 | 安灯呼叫的四级分类（缺料/品质/设备/维修）、应答-解除生命周期、升级上报与班次统计惯例——只提取功能分类与状态域，全部状态机/枚举/码位自有设计 | ⑯FB_DL_AndonCallSystem（andon/omac，T2-7/8 开族）|
| S-13 | FC_DL_Crc16Modbus 公开算法定义（本库已入库组件，R3）| 本库 DL_MathData（思想源：OSCAT Network T1-3，已开组）| 本库自有（MIT/Apache 口径）| 仅引用「Modbus RTU CRC-16 公开算法定义存在」这一事实与公开标准（Modbus 应用协议规范）；调度层不调用、不内联任何校验逻辑，帧校验归传输层实现块 | ⑮FB_DL_ModbusPollMaster（注释级引用）|

## 2 许可证与合规裁决一览

| 来源组 | 许可证类型 | 处置口径 |
|---|---|---|
| S-1~S-7 西门子文档线 | 免费使用但闭源版权 | 只借功能分类体系 / 参数域 / 命名组织；clean-room；文件头标注「原创实现（参考西门子 LGF/MC 公开手册分类与参数域）」 |
| S-8 PLCopen | 公开规范（免费）| 行为语义域提取；clean-room；文件头致谢 PLCopen 公开规范 |
| S-9 AccelStepper | MIT | 算法思想借鉴；clean-room；文件头标注参考仓库与协议，不构成衍生作品 |
| S-10 TcOpen | Apache-2.0 | 分层范式复用（R7 已合规沉淀）|
| S-11 CODESYS Forge ModbusFB | 所据页面未显式声明许可 | **按最严口径**：只借组织分类与参数域，零代码行复制（与 R8 RecipeManager 同口径）|
| S-12 PackML / OMAC | 公开规范 | 分类与状态域提取；clean-room |

## 3 矩阵回写计划（SOURCE_HUNTING_MATRIX 第 5 节，本轮收尾时执行）

> 本轮只写回写计划，不改动矩阵文件本体（收尾轮统一回写）。☐=待挖掘 / ◐=部分 / ✔=已挖掘。

| 矩阵行 | 回写动作 | 内容 |
|---|---|---|
| T2-1 LGF · Data Handling | ◐ 深化 | +FifoBuffer / ArraySearchFirst / BinarySearchLReal（累计 5 项）；「变长数组与通用化缓冲族」仍待挖 |
| T2-1 LGF · Comparator | ◐ 深化 | +ToleranceWindow / LimitClassify（累计 3 项）；开闭区间变体、数据类型重载族待挖 |
| T2-1 LGF · Converter | ◐ 深化 | +TempUnitConvert / BcdToWord / WordToBcd（累计 4 项）；DTL-String 族（依赖平台日历类型，评估可移植性后再排）待挖 |
| T2-1 LGF · Bit Logic | ◐ 深化 | +WordBitPack（累计 2 项）；DWORD/LWORD 数组位段批量族待挖 |
| T2-1 LGF · Date and Timer | ◐ 深化 | +MonthWindowCheck（累计 4 项）；周窗/年窗/天文钟族待挖 |
| T2-1 LGF · Counter | ◐ 深化 | +PresetCounterSat（累计 3 项）；双向预设计数（CTUD 全语义）族待挖 |
| T2-4 Motion Control 示例 | ◐ 深化 | +SuperimposedMove（累计 5 项）；SpeedAxis/SynchronousAxis/外部编码器分型待挖 |
| T1-8 GitHub topics | ☐→◐ **开组** | 新增行：stepper 线（AccelStepper 等 MIT 仓库，算法思想借鉴）→ I_DL_StepperOpenLoop / FB_DL_PulseDirStepper；组内其余高质量组件按需续挖 |
| T1-4 CODESYS Forge | ◐ 深化 | +ModbusPollMaster（codesys-forge-modbus，累计 2 项）；DeviceReader / SysFile 族待挖 |
| T2-7 PackML / OMAC | ◐ 深化 | +AndonCallSystem（andon/omac 开族，累计 4 项）；配方切换 / 批次编排（ISA-88 衔接）待挖 |
| T1-6 PLCopen Motion | ◐ 深化（语义借用）| 叠加运动公开语义供 SuperimposedMove 双源印证；本行组件数不变（组件主源记 T2-4 行）|
| T2-8 ISA-88 / ISA-18.2 / NE107 | ◐ 深化（语义借用）| OMAC 人员响应域归 T2-7 行记账，本行不重复登记（沿用 R8「实测修正」的记账纪律）|

## 4 配额自检（矩阵第 4 节硬性要求）

- T2 非 ST 源 ≥ 1 组件族：S-1~S-6（LGF 七组，9 件）+ S-7（T2-4，1 件）+ S-12（T2-7/8，1 件）→ **满足**。
- T1 ST 原生源 ≥ 1 组件族：S-8/S-7（PLCopen + s7-motion 双源）+ S-9（T1-8 开组）+ S-11（T1-4）→ **满足**。
- 禁止重复挖掘同一组：本轮 LGF 六组均为「◐ 深化」且各组件语义域互不重叠、与已入库组件职责分离口径已写入规格；未触碰任何已收口组 → **满足**。

## 5 留痕归档

- 本文件路径：`C:\Library\_Staging_Raw\2026-11-15\RAW_NOTES_R9.md`（与 ROUND_PLAN_R9.md、BATTLE_REPORT_R9.md 同日归档）。
- 各组件 `.st` 文件头「开源溯源」字段措辞与本文件第 1 节逐一对应，收尾轮终审时逐件核对。
- 本轮原始代码抓取为零（全部为手册语义级狩猎，无逐行参考对象），故不新建 `original_*.st` 子目录；如终审裁定某组件需补抓原始对照，届时按目录契约补 `_Staging_Raw\<来源>_<YYYYMMDD>\README_SOURCE.md`。

---

*Round 09 狩猎留痕 ｜ 2026-11-15 ｜ 道莅工控代码库产品总监*
