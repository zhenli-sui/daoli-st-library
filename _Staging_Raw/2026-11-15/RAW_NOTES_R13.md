# R13 狩猎留痕 / RAW NOTES R13

> **轮次**：Phase 1 第十三轮（R13）｜ **日期**：2026-11-15 ｜ **执行**：兜底模式（原生双专家 not available）
> **性质**：**只读检索**。本轮**未克隆任何仓库、未下载任何 `.lib` / `.library` / 源码包、未落一行第三方代码**，全部提取点为「公开文档目录、公开规范条款、公开技术文章」。
> **取证口径**：因未抓取文件，本轮**不写 commit hash / tag**。凡涉及版次的结论一律标注「版次以实测为准」，不把版次号作为分类结论的依据（沿用矩阵勘误 M-E1 纪律）。

---

## 0 检索元信息

| 编号 | 检索组 | 查询意图 | 主要命中 | 支撑组件 |
|---|---|---|---|---|
| S-1 | T2-1 LGF 组内块清单 | 核实 LGF 11 组内**实际块粒度**，找未挖子族 | Siemens LGF 官方文档目录（V5.0.0 / V5.2.1 英文版），含逐块索引 | B1/B2/B3/B4/B5/B6 |
| S-2 | T2-8 NAMUR NE107 | 四态诊断语义、优先级与严重度关系 | NAMUR 官方公告（2025-07-15 版）+ Endress+Hauser / Electrical&Control 解读 | A1/A3/A4/A5/A6 |
| S-3 | T2-2 LBP 块清单 | 核实 23 块清单与「有无混合/定量组」 | Siemens LBP 官方文档 Table 1-1（V2.6）+ 西门子 1847 课程页 + 中文解读（V2.8） | A5/C6 及查漏 |
| S-4 | T2-6 Rockwell AOI | 设备级 AOI 的**诊断分类**与参数分段 | P_ValveSO 参考手册（SYSLIB-RM015）+ AOI 参数属性文档 | A5（次源）、C3（次源） |
| S-5 | 阀门黏滞检测方法 | 非侵入式判据族的**可用性与失效边界** | Choudhury & Shah (DYCOPS 2004)、Horch 互相关法、2023 形状相似度论文、JPC 综述 | A4 |
| S-6 | T1-1/T1-2 OSCAT 行为定义 | 核实 OSCAT 是否有孔板/CRC8 等对应行为定义 | OSCAT 官方文档站（EPL-2.0）+ 归档仓说明 + CODESYS 楼宇库资源页 | B3、B6、C1 |

---

## 1 逐条记录

### S-1 ｜ T2-1 Siemens LGF（Library of General Functions）

| 字段 | 内容 |
|---|---|
| 来源 | Siemens Industry Support，Entry ID **109479728**；英文文档 `109479728_LGF_DOC_V5_2_1_en.pdf` 与 `109479728_LGF_TIAV16_DOC_V5_0_0_en.pdf` |
| URL | `https://support.industry.siemens.com/cs/attachments/109479728/109479728_LGF_DOC_V5_2_1_en.pdf`（及同 ID 的 V5_0_0 版） |
| 许可证 | **免费使用但闭源版权**（西门子文档版权）。按矩阵「只借骨不抄肉」铁律处置 |
| 可提取点 | ① 组划分与**组内块清单**（见下）；② 每组的**粒度习惯**（单点 / 单段 / 批量的三层）；③ 块的**参数域命名组织**（Cfg_ / Inp_ / Sts_ 风格的存在性，不抄字面） |
| 实测块清单要点 | `00 Bit logic`：BitSet / BitSetTo / BitReset / BitTest / BitToggle / PulseRelay / lecTimerOnOff；`01 Date and timer`：GetCalendarDay / GetCalendarWeek_ISO / _US / IsGermanHoliday / AstroClock / DelayProgram / GetClockState / SetTime / TimerSwitch；`02 Counter`：BitCount / **CountArrayElements** / **CountBooleanEdges** / CountFallInDWord / CountRisInDWord / **GetBitStates**；`03 Comparator`：**BinaryMaskCompare** / CompareLReal / CompareLRealByPrecision / **CompareString** / CompareVariant；`04 Math`：**MatrixAddition / MatrixInverse / MatrixMultiplication / MatrixScalarMultiplication / MatrixSubtraction / MatrixTranspose / MatrixCompare（七件）** / StoreMinMax / Random_Real / Random_DInt / Random_UDInt / RandomRange_DInt / RandomRange_UDInt / RandomRange_Real / SearchMinMax（含 _DInt / _UDInt 重载）/ NthRoot / IsValueInRange / IsValueInTolerance / IsValueInLimits / Integration / GetFactorial / CalcDistance_2D / CalcDistance_3D；`05 Data handling`：FIFO / LIFO / **ShellSort_DInt / _UDInt / _LReal** / **CalcCRC8 / CalcCRC8Advanced** |
| 本轮提取结论 | ① **矩阵第 2 节 Math 组的展开策略漏记了「矩阵运算」子族**（7 个块），属矩阵自身漏记 → 勘误 **M-E4**（见 §3）；② Data Handling 组含 **CRC8 双件**，而本库 CRC 族已有 CRC16/CRC32/LRC，**CRC8 为真实缺口**；③ Data Handling 的字符串族在 LGF 侧只有「定长缓冲」形态，**无流式分词器**（与 R12 结论一致），字符串转数值亦无专块 → 本库自研形态可行且不与源头同构 |
| clean-room 边界 | 只取「组内有哪些块、粒度如何切分」这一层事实。**函数名、块名、参数名、常量名、内部算法一律不沿用**；本库件名（如 `FC_DL_MaskCompare` / `FC_DL_Crc8`）为本库自定语义命名 |

### S-2 ｜ T2-8 NAMUR NE107（现场设备自监测与诊断）

| 字段 | 内容 |
|---|---|
| 来源 | NAMUR 官方公告《NE107 "Self-monitoring and diagnostics of field devices" has been revised》（Edition 2025-07-15）；Endress+Hauser Netilion 技术博客；Electrical & Control 标准解读 |
| URL | `https://www.namur.net/en/publications/news-archive/ne107-self-monitoring-and-diagnostics-of-field-devices-has-been-revised.html` ／ `https://netilion.endress.com/blog/namur-ne-107/` ／ `https://www.electricalandcontrol.com/namur-ne-107-standard-for-modern-instrumentation-diagnostics/` |
| 许可证 | **公开推荐规范**（非代码，无代码复制问题）；引用其**条款语义**，不复制图表与图标 |
| 可提取点 | ① **四态集合**：Failure (F) / Function Check (C) / Out of Specification (S) / Maintenance Required (M)；② **优先级数值**：F=1、C=2、M=3、S=4（**优先级 ≠ 严重度**：C/M 严重度低但 C 的处置优先级高于 M）；③ 颜色/图标为「标准化呈现」诉求，本库不实现图形，只输出**枚举 + 优先级 + 建议动作码**；④ 规范明确「诊断能力的技术可行性不在本推荐范围内」——即**规范只管分类与呈现，不管怎么算**，这为本库自研判据留出了合法空间 |
| 本轮用法 | 作为 **A 泳道六件的统一健康出口语言**：`E_DL_Ne107Status` 为本库唯一权威定义，四态编号按**优先级顺序**（10/20/30/40，数值小者优先），并在头注释声明「编号表达优先级，不表达 NE107 官方图标顺序」 |
| 边界 | 不声明「符合 NE107 认证」；不复制其图标/颜色表；「哪些工况算 Failure」的判据 100% 本库自有（规范恰好把这一层留空） |

### S-3 ｜ T2-2 Siemens LBP（Library of Basic Processes）

| 字段 | 内容 |
|---|---|
| 来源 | Siemens Entry ID **109749508**《LBP – Operation / Implementation》V2.6 英文文档 Table 1-1；西门子 1847 工业学习平台课程页；中文解读文（记 V2.8） |
| URL | `https://support.industry.siemens.com/cs/attachments/109749508/109749508_LBP_V2.6_Operation_DOC_en.pdf` ／ `https://1847.siemens.com.cn/course/detail/2/1809665/17472` ／ `https://jianzhigongkong.com/node/3291` |
| 许可证 | 免费使用但**闭源版权**（文档版权）。只借分层与参数域 |
| 可提取点 | **23 块实测清单**：Aggr8（≤8 台设备组控）/ AnaAvg（带合理性检查的平均）/ AnaRead / ClctVal / CntrA / CntrD / CntrP / CtrlPID / CtrlStp / Intlk8 / Msg8（8 条消息块）/ Mtr / MtrDS / MtrF / SimoDir / SimoRev / Sina / SinaExt / OpAna / OpDig / Polygon / Select / SetCrv / TimeSw / Vlv / VlvA / 3wVlv |
| 关键复核 | ① **复核 R8 结论成立**：清单内**无「混合」「定量」独立功能组**，混合工艺只能走 ISA-88 相语义；② **无「泵」「阀黏滞」「换热器」专项块**——LBP 只到「单台设备启停/开度」层，**设备本体退化诊断是 LBP 的能力边界之外**，本轮 A4/A6/C1 属本库自研增量，LBP 只贡献「命令 → 监视 → 判定」三段分层骨架；③ `AnaAvg` 的「带合理性检查」提示：**先判数据可用性再算统计量**（与 R42 同源），本轮 A3/A4/C1 全部按此顺序排段 |
| clean-room 边界 | 块名/参数名/DB 结构/注释零沿用；「命令-监视-判定」三段为工业通用分层，不构成某一家专有表达 |

### S-4 ｜ T2-6 Rockwell PlantPAx 设备级 AOI

| 字段 | 内容 |
|---|---|
| 来源 | Rockwell《Library of Process Objects: Solenoid-operated Valve (P_ValveSO)》SYSLIB-RM015；Studio 5000 AOI 参数属性文档（Input/Output/InOut/Local + External Access） |
| URL | `https://literature.rockwellautomation.com/idc/groups/literature/documents/rm/syslib-rm015_-en-e.pdf` ／ `https://punchout.rockwellautomation.com/en-in/docs/studio-5000-logix-designer/38-00/contents-ditamap/quick-start-steps/creating-add-on-instructions.html` |
| 许可证 | **文档版权**。只借分类与参数域 |
| 可提取点 | ① **三分类诊断**：`Full Stall`（指令下发但**完全未离开原位**）/ `Transit Stall`（已离开原位但**未达目标**）/ `I/O Fault`（I/O 通信故障外部注入）——三者对应三种**不同的物理失效机理**，比「一个卡滞位」信息量高一个量级；② 每个告警有**可配置延时**（给执行器对齐时间），即「判据必须带确认窗」；③ 模式五态（Operator / Program / Override / Maintenance / Hand）中 **Hand 模式为「跟踪」语义**（跟踪现场硬手操状态，以便无扰切回），即「无扰切换 = 跟踪 + 首拍无阶跃」；④ 参数四分段（In / Out / InOut / Local）与 External Access 等级沿用 R10 已确立映射 |
| 本轮用法 | A5 的诊断枚举直接按「完全不动 / 动而未达 / I/O 失联」三分类建模（这是本轮最有价值的一次结构借用）；C3 借「单块覆盖 指令-反馈-判定-诊断 四段」的粒度 |
| clean-room 边界 | 不沿用 P_ 前缀、Cfg_/Inp_/Sts_ 命名体系、告警对象结构、UDT 布局；**延时、阈值、状态机、码位全部自有** |

### S-5 ｜ 阀门黏滞（Stiction）检测方法族

| 字段 | 内容 |
|---|---|
| 来源 | Choudhury / Shah / Thornhill《Detection and Quantification of Control Valve Stiction》（DYCOPS 2004，公开 PDF）；Horch 互相关法（经多篇独立文献转述）；《Shape similarity index》会议论文（2023）；Journal of Process Control 综述（2011 / 2018） |
| URL | `https://skoge.folk.ntnu.no/prost/proceedings/dycops04/pdffiles/papers/85.pdf` ／ `https://skoge.folk.ntnu.no/prost/proceedings/focapo-cpc-2023/Oral%20Talks/11_Oral.pdf` ／ `https://www.sciencedirect.com/science/article/pii/S0959152411001181` |
| 许可证 | 学术公开文献（**只读思想**，不复制公式推导图、不复制其数据） |
| 可提取点与**失效边界**（本轮最重要的一次「反向结论」） | ① 文献共识：过程工业 **20~30% 的控制回路振荡源于阀门非线性**，其中黏滞最常见（可作件头注释的立项理由引述）；② 判据族有四类——互相关相位（Horch）、PV-OP 图椭圆拟合（Choudhury）、高阶统计/双相干、波形形状相似度；③ **Horch 法在含积分环节或可压缩流体回路失效**（文献明确）；④ **椭圆拟合法受控制器整定与过程模型影响**，只能给「量级」不能给「精确值」；⑤ 2023 综述结论：**没有单一技术能 100% 置信判定，须多判据并用** |
| 本轮决策（写进规格） | A4 **不做互相关**（需长窗 FFT/大量存储，违背 O(1) 内存与定长数组的红线），**不做椭圆曲线拟合**（需二维最小二乘迭代，非确定性、不可逐拍复算）；只做**三判据并发**：ⓐ 指令-反馈**方向性滞后**（上升行程与下降行程在同一 OP 处的 PV 差 → 黏滞带估计）；ⓑ **停滞拍计数**（指令变化超阈而阀位移动小于阈，持续超时）；ⓒ **反转确认延迟**（方向反转后阀位开始移动的滞后时间）。三者同时成立才升 `eSevere`，单成立只到 `eSlight`。**头注释必须写明「本件输出为趋势判据，不作黏滞量的计量级量化」**——这是把文献的「不可能」如实写进契约，而不是包装成精度承诺 |
| clean-room 边界 | 不复制任何论文公式的符号体系与推导；阈值、窗口、状态机、码位、等级划分 100% 自有 |

### S-6 ｜ T1-1 OSCAT Basic / T1-2 OSCAT Building 行为定义

| 字段 | 内容 |
|---|---|
| 来源 | OSCAT 官方文档站（master / Basic / Network / Building 四项目）；`eclipse-oscat/oscat-libs-archive` 归档仓说明（含版次谱系 1.10→3.36）；CODESYS 在线帮助「Building Automation · Other useful resources」页 |
| URL | `https://oscat.readthedocs.io/en/latest/` ／ `https://github.com/eclipse-oscat/oscat-libs-archive` ／ `https://content.helpme-codesys.com/en/libs/Building%20Automation/1.0.0.0/BuildingAutomation/Doc/other_ressourcesrst.html` |
| 许可证 | **EPL-2.0**（现行）；**归档仓历史文件明确排除 EPL-2.0**，仍受原始许可约束。两者均只允许「借鉴算法思路 / 行为定义后独立实现」 |
| 可提取点 | Basic：数学（数组/几何/向量/复数）、逻辑（存储/触发器/计数/定时）、字符串、时间日期、控制工程（PID/滤波/信号处理）、测量与传感器、列表处理；Building：**AIR_DENSITY / DEW_TEMP / DEW_RH / SDD / SDD_NH3 / WATER_DENSITY / WATER_ENTHALPY / WATER_CP / AIR_ENTHALPY / HEAT_METER** 等「物理量行为定义」清单 |
| 本轮结论（含一次**撤项**） | ① 原拟的「孔板差压流量」件：**OSCAT 侧无对应行为定义块**（清单内无 ORIFICE 类），若强行标 `oscat-basic` 属**伪 T1 归属** → **本轮撤项**，改列 R14 候选并改挂 T3（ISO 5167 公开公式条款），避免为凑配额造假归属；② CRC8：OSCAT Network 侧有 CRC 家族但**本轮未取得其块级清单**，故 B3 主源记 **T2-1 LGF Data Handling（CalcCRC8/CRC8Advanced 的存在性）**，T1-3 记为次源（仅「诊断/校验独立成族」这一分类事实），**不声称取到 OSCAT CRC8 行为定义**；③ Building 的 WATER_CP / WATER_DENSITY / SDD 三项仍是干净的 T1-2 待挖行为定义，留 R14 |
| clean-room 边界 | 未取得函数体，故无逐行改写风险；件头一律写「原创实现（参考 XXX 行为定义 / 分类与参数域）」，**不写「改写自」** |

---

## 2 clean-room 处置分类（18 件归属）

| 处置 | 件数 | 组件 |
|---|---|---|
| 只借**分类与参数域**（闭源文档线：LGF / LBP / Rockwell） | 8 | B1、B2、B3、B4、B5、B6、A5、C3 |
| 只借**公开规范条款**（NE107 / ISO 10816 等公开值） | 4 | A1、A3、A4、A6 |
| 只借**行为定义**（OSCAT，EPL 线，仅语义） | 1 | C1（换热器传热量的「Q / LMTD / K」行为定义组织，公式取自公开传热学常识） |
| **库内纪律复用，不重复记账** | 2 | A2（契约分层沿用 `I_DL_FlowMeter` 三段式）、C2（轴状态只由运动层拥有，R31 家族纪律） |
| 自研为主、源头仅作立项理由 | 3 | C4（ESC 氦检，无对应开源件）、C5（seasoning 台账）、C6（夹套温差） |

> **本轮 18/18 clean-room 独立实现**，零代码行、零块名、零参数名、零注释引用。五条「不立 / 撤项 / 不声称」决定见 §4。

---

## 3 矩阵自身勘误（本轮就地更正，编号接 R12 的 M-E1~M-E3）

| 编号 | 位置 | 原文 / 现状 | 实测问题 | 更正 |
|---|---|---|---|---|
| **M-E4** | 第 2 节「Math Operations」行 + 第 5 节 T2-1 Math 行 | 第 2 节 Math 组展开策略列了「线性标度 / N 次根 / 阶乘 / 2D-3D 距离 / 均值标准差 / min-max+索引 / 随机数」，**未列矩阵运算** | LGF 官方文档目录实测含 **7 个 Matrix 块**（Addition / Inverse / Multiplication / ScalarMultiplication / Subtraction / Transpose / Compare） | 第 2 节 Math 行补「矩阵运算（7 件）」子族；第 5 节 T2-1 Math 行备注补「**Matrix 子族 R13 开族（2 件：3×3 求逆 / 3×3 乘）**，余 5 件（加/减/标量乘/转置/比较）留 R14」 |
| **M-E5** | 第 5 节 T2-2 行 | R8 记「实测 23 块」，M-E1 记「V2.7 vs V2.8 版次口径不一致」 | 本轮三源交叉：官方 V2.6 文档 Table 1-1 与中文 V2.8 解读**块清单同构（23 块）**，仅 `SinaExt`/`SineExt` 一处拼写差异 | 结论维持「版次以实测为准」；补一条：**块清单在 V2.6~V2.8 间稳定**，故「LBP 无混合组 / 无本体诊断块」两条结论**不随版次失效**，可作为长期判据 |
| **M-E6** | 第 5 节结构性总述 | 表内 16 行**全部为 ◐**，无一行 ☐ | R13 起**已无 ☐ 组可开**：唯二未开的两条是 **T1-9（汇川/信捷/台达 FB 手册）** 与 **T2-9（三菱/欧姆龙/FateK 手册）**，二者均为「文档版权 + 无 ST 接口」，只能产出**查漏清单**、不能产出组件 | 「☐ 组优先」条款自 R13 起**失去适用对象**，改按「**子族收口**」执行；且第 5 节「待挖」描述**必须拆到可独立验收的粒度**（R12 §5.1 方法论勘误的落地）。本轮 18 件均为子族收口或开新子族，**新开组 = 0，新开子族 = 3**（NE107 诊断族 / LGF Matrix 子族 / LGF CRC8 子族） |

---

## 4 反向清单（明确「不立 / 撤项 / 不声称」，防下轮重复立项）

1. **孔板差压流量件——撤项（原拟 B6）**：OSCAT 无对应行为定义，标 `oscat-basic` 属伪 T1 归属；ISO 5167 属标准条款（T3）。改 R14 候选，届时按 T3 立项并只用「公式链公开、系数由用户注入」的形态，**不得内置任何标准表**（表数据有版权）。
2. **CRC8 反射变体（CRC-8/MAXIM-DOW，poly 0x31 反射）——本轮不立**：反射位序是**另一套算法族**（LSB-first + 位反转），与本件 MSB-first 参数化结构不同构；硬塞进同一 `E_DL_Crc8Variant` 会让「变体」概念失真（同 R10 正弦/锯齿不合并 `eWaveform` 的教训）。另立 R14 候选 `FC_DL_Crc8Reflected`。
3. **阀门黏滞的「互相关法 / 椭圆拟合」——不立**：见 S-5，需长窗 FFT 或二维迭代，与「O(1) 内存 + 逐拍可复算验收」红线冲突。A4 只做三判据并发，并**明确不承诺量化精度**。
4. **`SysFile` / 文件系统类——继续不立**（沿用 M-E3）：违反「零厂商专有库、仅 Standard.library」红线。
5. **不声称「符合 NE107 / 符合 ISA-88 / 符合 ISO 10816」**：NE107 只借四态语义与优先级；ISO 10816 只借「4.5 mm/s 为 C 区边界」这一**公知阈值**并在引脚暴露可改；ISA-88 系列继续只写「采用公开相状态模型」。
6. **T1-9 / T2-9 不造件**：本轮用其公开块清单做**覆盖率查漏**（见 §5），结论写入 R14 候选，不为其临时造组件。

---

## 5 国产 / 日系 FB 手册线查漏（T1-9 + T2-9 的唯一合法用法）

抽样 10 个「国产/日系平台高频块」对照本库 186 件：

| # | 平台常见块 | 本库对应 | 覆盖 |
|---|---|---|---|
| 1 | 多段速运行（变频 8/16 段速表） | `FB_DL_VfdGeneric`（preset-speed-table） | ✅ |
| 2 | 简易 PLC 程序段（PR 程序，按时序切段速） | `FB_DL_RampSoakProfile` + `FB_DL_StepSequencer` | ✅（组合） |
| 3 | 脉冲输出定位（PLSY/PLSR 类） | `FB_DL_PulseDirStepper` | ✅ |
| 4 | 原点回归（ZRN/DSZR 类） | `FB_DL_AxisHomingSeq`（四模式） | ✅ |
| 5 | 电子齿轮 / 凸轮（DRVI/DRVA、CAM） | `FB_DL_ElectronicGear` / `FB_DL_ElectronicCam` | ✅ |
| 6 | 高速计数器（单相/AB 相，带比较输出） | `FB_DL_EventCounter` / `FB_DL_BidirectionalCounter` | ◐（**无 AB 相正交解码 + 4 倍频**） |
| 7 | 模拟量平均（带合理性检查） | `FB_DL_MovingAverage` + `FB_DL_AnalogTransmitter` | ✅ |
| 8 | 温控 PID 自整定 | `FB_DL_PidController`（无自整定） | ◐（**自整定未立**，属 R2R/继电器反馈族） |
| 9 | 定位完成窗口 + 到位输出 | `FB_DL_SingleAxis` | ✅ |
| 10 | 通信断线检测（心跳） | `FB_DL_WatchdogMonitor` | ✅ |

**结论**：覆盖 8/10 全备、2/10 部分 → 两个真缺口（**AB 相正交解码 4 倍频计数**、**PID 自整定**）写入 R14 候选（前者 T1-8 GitHub topics 线，后者 T2-5 Mod_PID_Control 手自动/自整定手册细节线）。此项证明：**☐ 组不开也能产出有效的缺口情报**，查漏本身即产出。

---

## 6 给 R14 的源建议（按性价比排序）

1. **T2-1 LGF Matrix 子族余量 5 件**（加/减/标量乘/转置/比较）——同一子族连续收口，边际成本最低。
2. **T2-1 LGF Counter 组三个未挖块**（`CountArrayElements` / `CountBooleanEdges` / `GetBitStates`）——与既有计数器族天然衔接。
3. **T2-1 LGF Data Handling `ShellSort_DInt/_UDInt`**——与既有 `QuickSortLReal` 构成「小数组合适插入/希尔、大数组快排」的选型对，需在规格里写明**选型判据**（长度分界）。
4. **T2-9 查漏两缺口**：AB 相正交解码（T1-8）、PID 自整定（T2-5）。
5. **T1-2 OSCAT Building 余量**：`WATER_CP` / `WATER_DENSITY` / `SDD`（饱和蒸汽压）三件，行为定义干净、与既有 `FC_DL_WaterEnthalpy` 同族。

---

*RAW NOTES R13 ｜ 2026-11-15 ｜ 道莅工控代码库产品总监 ｜ 只读检索，零源码落盘*
