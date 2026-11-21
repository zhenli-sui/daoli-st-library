# ROUND PLAN R22 —— 阶段一盘点 + 阶段二狩猎派单（20 件 / 4 批）

> 轮次：**R22** ｜ 生成时间：2026-11-16 23:06 ｜ 编制：道莅工控代码库产品总监（daoli-library-director / 召唤模式：原生）
> 性质：**结构补位轮**——六库占比再平衡（Motion / Process / Device 扩容）+ 1 个 T2-1 LGF 待挖子族收口 + 2 件 T0 变体线补位
> 本文性质：**派单规格书**。阶段一（盘点与锁定 20 目标）+ 阶段二（按源矩阵狩猎与留痕）产物；**不写组件代码，不改 `INDEX_REGISTRY.json` / JSONL / 任何 `.st`**
> 检索预算：**2 次 WebSearch / 3 次**（均已执行，见 `RAW_NOTES_R22.md`）；T0 变体线 2 件零检索；LGF 子族复用 R21 已有留痕（同源不重复检索）

---

## 0 盘点区（Step 1 · 状态读取 · 全部当场实测，不沿用交接口径）

### 0.1 总库状态（`INDEX_REGISTRY.json` 实解析 + `DL_*/*.st` glob 实测 + JSONL 行数实测）

| 项 | 实测值 | 校验 |
|---|---|---|
| `version` | **2.10.0** | ✔ |
| `total_components` | **364** | 与 `counts` 求和 **364** 一致 ✔ |
| `last_updated` | `2026-11-16T21:18:00+08:00` | ✔ |
| 物理 `.st` 文件数 | **364** | 三方自洽 ✔ |
| 语料 JSONL 行数 | **364** | 三方自洽 ✔ |
| 子库分布（`counts` 实读） | `DL_Base` **71** ｜ `DL_MathData` **145** ｜ `DL_Algo` **36** ｜ `DL_Device` **57** ｜ `DL_Motion` **25** ｜ `DL_Process` **30** | ✔ |
| 总库完成度 | **364 / 10 000 = 3.64 %** | — |
| 今日累计（11-16） | **178 / 200 = 89.0 %** | 交接值复核一致 ✔ |
| 距今日 200 目标 | **22 件**（R22 交付 20 件后仍差 2 件，如实记账） | — |
| 距 500 里程碑 | **136 件** | — |

### 0.2 六库占比与扩容裁定（本轮主裁定依据）

| 子库 | 件数 | 占比 | 本轮件数 | 轮后占比 | 裁定 |
|---|---|---|---|---|---|
| `DL_MathData` | 145 | **39.8 %** | **3** | 39.3 % | **限额**：仅接 T2-1 LGF 子族收口，不再接受纯变体 |
| `DL_Base` | 71 | 19.5 % | **2** | 19.2 % | **限额**：仅接 T0 变体线确有工程意义的原子 |
| `DL_Algo` | 36 | 9.9 % | **2** | 9.6 % | 持平 |
| `DL_Device` | 57 | 15.7 % | **4** | 15.9 % | 扩容（ROADMAP 未注册项清零 4 条） |
| `DL_Motion` | 25 | **6.9 %（最低）** | **5** | 7.4 % | **本轮主力扩容**：轴侧安全时序与指令管理层全空 |
| `DL_Process` | 30 | 8.2 % | **4** | 8.7 % | 扩容（过程单元保护 + 批处理顺控） |

> **裁定逻辑**：`DL_MathData` 已占近四成，任何「再多一个数学变体」都会把库推向失衡。R21 已把数学安全原子与文本序列化收口，R22 起 MathData 只接「源矩阵真有子族缺口」的件（本轮 3 件定宽数值字段族全部挂 T2-1 LGF 待挖子族）。Motion 只有 25 件而承载轴控全部语义，是六库中最薄的承重墙，本轮给最大配额。

### 0.3 源矩阵取源判定（`SOURCE_HUNTING_MATRIX.md` 逐行解析）

| 判定项 | 实测 | 结论 |
|---|---|---|
| T0-1 ~ T0-8 八行 | **8 / 8 全 ✔ 收口** | 只允许「变体线深化」，**禁止重挖已 ✔ 收口组的存量语义** |
| T1-1~9 / T2-1~9 / NE43 / ESC 自研 | **19 行全部 ◐，☐ = 0** | 无新源可开，只能 ◐ 深化 |
| T2-1 LGF 待挖子族（R21 留痕 §5） | 「LWORD 多段一次搬」**已由 R18 `FC_DL_BitSegmentBlockMove` 覆盖**（段表驱动 128 位窗口，实测存在）；「数值→定宽字段对齐」**仍空** | 本轮取**定宽数值字段编解码**子族收口；多段搬**不重复立项**（R85 反虚账） |
| T1-3 OSCAT Network 待挖两项 | 「RTU 帧长/字节数一致性」**已由 R19 `FC_DL_ModbusRtuFrameCheck` 收口**（实测头注释四路互校）；仅余「ASCII 帧 LRC 定位」 | 丙件属框架解析薄件，本轮**不立项**，理由写入 `RAW_NOTES_R22.md` §3.2 |
| ROADMAP 未注册待办（P0/P1） | 行业池 §7/§9 中 **[ ] 未勾选项 60+** | **本轮取 8 条**（Device 4 + Process 4），占 40 %，符合「ROADMAP 未注册项优先于源矩阵待挖组」的取源优先级 |

### 0.4 ⚠ 码位游标当场实测（R61 铁律：禁信交接数字）

全库 364 个 `.st` 正则 `16#([0-9A-Fa-f]{4})_([0-9A-Fa-f]{4})` 全量扫描去重后，按段/子带统计：

| 段（属主） | 子带实测 | 已用上界 | **本轮起点** | 与交接值核对 |
|---|---|---|---|---|
| `16#0001_`（`DL_Base` + `DL_MathData` **共用命名空间**） | 信息 `04xx` | `045B` | 信息 **`045C`** | 交接「045A」→ 实测 **045B**，差 1（本文件采实测） |
| 同上 | 故障 `03xx` | `03A7` | 故障 **`03A8`** | 交接「约 03A8」→ 实测 **03A7 已用**，起点 03A8 ✔ |
| `16#0002_`（`DL_Algo`，CC 网格） | `CC01/CC02` 信息 + `CC10/CC11/CC12` 故障 | CC = `2A` | 下一 CC = **`2B`** | ✔ 一致 |
| `16#0003_`（`DL_Device`） | 信息 `01xx` / 故障 `03xx` | `0171` / `033B` | **`0172` / `033C`** | 交接「0170」→ 实测 0171（本文件采实测） |
| `16#0004_`（`DL_Motion`） | 信息 `01xx` / 故障 `02xx` | `01D4` / `02E9` | **`01D5` / `02EA`** | 交接「01D3」→ 实测 01D4（本文件采实测） |
| `16#0005_`（`DL_Process`） | 信息 `01xx` / 故障 `03xx` | `01D9` / `030A` | **`01DA` / `030B`** | 交接「01D8」→ 实测 01D9（本文件采实测） |

> **三条结构事实（R22 实测新增，写入派单约束）**：
> 1. `16#0001_` 是 `DL_Base` 与 `DL_MathData` **共用命名空间**，两库槽位必须**统一顺延分配**，不得各自起算（R17 交叉撞车根因形态）。
> 2. `16#0003_` 的 `02xx` 子带是**早期设备件的故障带**（`DolMotor` 0201~020A 等），R13 起新件改用 `03xx`；本轮 Device 四件**一律走 `03xx`**，不得回填 `02xx`。
> 3. `16#0005_` 的 `02xx` 子带按块分段占用至 `02FF`（`DowntimeClassifier` 已占 02FF），**无连续空位**；Process 新件故障带改走 `03xx` 连续区（`030B` 起）。

### 0.5 候选名查重与剔除（实测）

20 个候选 POU 名对全库 `DL_*/*.st` 逐一 grep：**20/20 零命中（EXIT=1）**。
计划 100 个码位槽对全库做占用比对：**`CLASH: []`，零冲突**（脚本口径：`16#<seg>_<code>` 全字符串集合求交）。

**剔除名单（宁少勿滥，防凑数）**：

| 被剔除候选 | 剔除理由 |
|---|---|
| `FC_DL_SearchMinMaxDint` | R21 已判「仅差数据类型的伪重载」，本轮不得翻案 |
| `FC_DL_ModbusAsciiFrameCheck` | ASCII 帧结构校验本质是「定界符 + 十六进制字符域」两行判据，`LRC` 已由 `FC_DL_LrcChecksum` 占位，独立成件属框架解析薄件 |
| `FB_DL_DebounceBank` | 与存量 `FB_DL_SignalDebounce` 语义完全重合（只是多实例打包），数组化收益不足以占配额 |
| `FC_DL_NibbleSwap` | 半字节交换可由 `FC_DL_SwapBytes16` + 掩码一行合成，属薄包装 |
| `FB_DL_WaferHandoffSeq` | 「双机械手交接」与已收口 `FB_DL_PickAndPlaceStation`（九步序）+ `FB_DL_ParallelGripper`（夹持确认）叠加即得，重复度检验不通过 |
| `FB_DL_UnwinderDiameterCalc` | 层厚递推已由 `FB_DL_WindingLayerCounter` 覆盖、速度比法已由 `FC_DL_CoilDiameterCalc` 覆盖，再立件即三重重复 |

---

## 1 R22 20 目标一览（锁定，宁少勿滥）

| # | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批 | 码位段（信息 / 故障） |
|---|---|---|---|---|---|---|---|---|
| 1 | `FC_DL_IntToFixedField` | DL_MathData | FC_DL_ | 整数 → 定宽零填充/空格填充字段（MES 流水号与 ASCII 报文定长） | T2-1 LGF Converter/Data Handling（定宽数值字段子族） | M | 1 | 0001 · 045C / 03A8 |
| 2 | `FC_DL_FixedFieldToInt` | DL_MathData | FC_DL_ | 定宽十进制字段 → 整数（前导填充剥离 + 非法字符定位 + 饱和出口） | T2-1 LGF Converter/Data Handling（同上逆向对） | M | 1 | 0001 · 045E / 03AB |
| 3 | `FC_DL_LrealToFixedField` | DL_MathData | FC_DL_ | 浮点 → 定宽定点文本（固定小数位 + 四舍五入 + 非有限拦截） | T2-1 LGF Converter（`TimeToString`/`IntToString` 行为定义族补位） | H | 1 | 0001 · 0460 / 03AE |
| 4 | `FC_DL_FirstSetBit` | DL_Base | FC_DL_ | 首个置位位定位（低位/高位优先 + 8/16/32/64 有效位宽） | T0-7 变体线（零检索；位串族缺「搜索」轴） | M | 1 | 0001 · 0462 / 03B1 |
| 5 | `FB_DL_FrequencyMeasure` | DL_Base | FB_DL_ | 门时计数测频（Hz）+ 分辨率与低频死区显式化 | T0-2 变体线（零检索；定时器族缺「计频」轴） | M | 1 | 0001 · 0464 / 03B4 |
| 6 | `FB_DL_CrossLimitSelect` | DL_Algo | FB_DL_ | 燃烧双交叉限幅（空燃比先行裕度 + 双侧限幅出口） | T2-5 Mod_PID_Control（参数域纪律次源）+ 燃烧控制公开惯例 | M | 2 | 0002 · 2B01 / 2B10 |
| 7 | `FB_DL_ExcessAirTrim` | DL_Algo | FB_DL_ | 氧量修正（死区 + 限幅 + 负荷变化率冻结） | T2-5 Mod_PID_Control（参数域纪律次源）+ 燃烧控制公开惯例 | M | 2 | 0002 · 2C01 / 2C10 |
| 8 | `FB_DL_SlitValveInterlock` | DL_Device | FB_DL_ | 真空闸阀互斥互锁（真空度/门位/机械臂三条件 + 阻塞码掩码） | T2-8 ISA-88 互锁语义次源 + 自研（半导体真空） | M | 2 | 0003 · 0172 / 033C |
| 9 | `FB_DL_PressureReliefMonitor` | DL_Device | FB_DL_ | 安全阀起跳/回座监视（动作次数 + 累计开启时长 + NE107 出口） | T2-8 NE107 判据次源（`eOutOfSpec`/`eMaintenanceReq`） | M | 2 | 0003 · 0174 / 033F |
| 10 | `FB_DL_SteamTrapMonitor` | DL_Device | FB_DL_ | 疏水阀堵塞/泄漏温差判据（停机工况不判故障） | T1-1 OSCAT Basic 式「域外行为显式化」纪律次源 + 公开疏水阀温差判据 | M | 3 | 0003 · 0176 / 0342 |
| 11 | `FB_DL_LevelRadarValidate` | DL_Device | FB_DL_ | 雷达液位回波可信度仲裁（置信度/信噪比/量程/跳变四判据） | T1-2 OSCAT Building 域外行为显式化 + NAMUR NE43 信号质量契约 | M | 3 | 0003 · 0178 / 0345 |
| 12 | `FB_DL_AxisBrakeSeq` | DL_Motion | FB_DL_ | 伺服抱闸时序（先释放后使能 / 先静止后抱闸再断使能） | T1-6 PLCopen `MC_Power` 使能时序纪律 + T2-4 S7 Motion 抱闸组织 | M | 4 | 0004 · 01D5 / 02EA |
| 13 | `FB_DL_VirtualMasterAxis` | DL_Motion | FB_DL_ | 虚拟主轴相位源（速度/加减速限值积分，供凸轮/齿轮主轴） | T2-4 S7 Motion 工艺对象分型（SynchronousAxis 主值源） | M | 4 | 0004 · 01D7 / 02ED |
| 14 | `FB_DL_MotionCmdQueue` | DL_Motion | FB_DL_ | 运动指令排队器（Buffered 语义：前条 Done 才发下条 + 满队策略） | T1-6 PLCopen `MC_BUFFERMODE`（Aborting/Buffered/Blending 公开条款） | H | 4 | 0004 · 01D9 / 02F0 |
| 15 | `FC_DL_CamTableValidate` | DL_Motion | FC_DL_ | 凸轮表合法性校验（相位单调 + 首尾闭合 + 斜率上限） | T1-6 PLCopen `MC_CamTableSelect` 表选择纪律 | M | 4 | 0004 · 01DB / 02F3 |
| 16 | `FB_DL_AxisInPosMonitor` | DL_Motion | FB_DL_ | 到位稳定判定（位置窗 + 速度阈 + 稳定时间 + 抖振计数） | T1-6 PLCopen `InPosition`/`Standstill` 输出语义 | M | 4 | 0004 · 01DD / 02F6 |
| 17 | `FB_DL_CompressorSurgeGuard` | DL_Process | FB_DL_ | 压缩机防喘振（最小流量线 + 放空阀快开慢关） | 公开喘振判据惯例 + T2-1 LGF Technology 变化率限幅语义次源 | H | 2 | 0005 · 01DA / 030B |
| 18 | `FB_DL_ColumnDpCtrl` | DL_Process | FB_DL_ | 精馏塔压差控制（ΔP 死区 + 回流/再沸分配 + 防冲塔） | T2-5 Mod_PID_Control 参数域（死区/抗饱和）次源 | M | 3 | 0005 · 01DC / 030E |
| 19 | `FB_DL_InertPurgeSeq` | DL_Process | FB_DL_ | 氮气置换顺控（抽真空-充氮-保压-取样判据 + 循环上限） | T2-7 PackML 最小子集态命名（次源，不作主源） | M | 3 | 0005 · 01DE / 0311 |
| 20 | `FB_DL_BatchTransferSeq` | DL_Process | FB_DL_ | 批次物料转移顺控（阀位确认-计量转移-排空验证-关阀停泵） | T2-8 ISA-88 相/步骤语义次源（公开条款） | M | 3 | 0005 · 01E0 / 0314 |

**分布**：`DL_MathData` **3**（#1-3）｜ `DL_Base` **2**（#4-5）｜ `DL_Algo` **2**（#6-7）｜ `DL_Device` **4**（#8-11）｜ `DL_Motion` **5**（#12-16）｜ `DL_Process` **4**（#17-20）＝ **20**
**类型**：FC **5**（#1 `IntToFixedField`、#2 `FixedFieldToInt`、#3 `LrealToFixedField`、#4 `FirstSetBit`、#15 `CamTableValidate`）｜ FB **15**
**复杂度**：H **3**（#3、#14、#17）｜ M **17**｜ L **0**
**新接口契约**：**0 个 `I_DL_*`**（本轮无新设备契约，避免契约层膨胀；`E_DL_Ne107Status` **引用不重声明**）

### 1.1 为什么这 20 件不是「凑数变体」（逐族辩护）

1. **#1~#3 是 LGF 子族的真实缺位，且是「编码闭环」缺口**：库内 `FC_DL_StringFixedField`（R13）解决「定长串**填充/对齐**」，`FC_DL_DintToStringTrim`（R20）解决「数值→文本**去空格**」，但「数值→**定宽零填充**字段」（MES 流水号 `00012345`、ASCII 报文定长十进制）与「定宽字段→数值」（前导零/空格/符号解析 + 非法字符位置）两侧全空。R21 `RAW_NOTES §5` 已把「数值→定宽字段对齐」登记为 LGF 待挖子族。三个件构成**编码对 + 浮点定点**，缺任一件则报文层无法闭环（能拼出定宽整数却拼不出定宽称重值）。
2. **#4 是位串族第四轴**：位串族已有「读写（`BitGet`/`BitSet`）、统计（`BitCount`）、提取（`BitFieldExtract`）、批量（`BitArray*`）、旋转/掩码比较（R13）」，唯独**搜索**缺失——现场「状态字→首个故障位号」「IO 字→首个空位」每次手写循环。LGF 位操作/计数与边沿组亦把搜索与统计分立，反证这是分类缺口而非臆造。
3. **#5 是定时器族的第五轴（测而非生）**：`PulseGenerator` 生脉冲、`SamplingTrigger` 生节拍、`CycleTimeMeasure` 测任务周期，**没有任何件测量外部脉冲频率**。脉冲流量计 K 系数、编码器线速度、风机转速全部落在这一格。R21 已判「LGF `Frequency` 发生器不立」（与 `PulseGenerator` 重叠），但**测量侧与之相反，是真缺口**。
4. **#6/#7 是燃烧控制的两条互补律**：双交叉限幅管「空燃两侧谁先给」，氧量修正管「长期空燃比偏置」。二者不能合并（一个是同拍选择律、一个是慢时标积分律，合并后验收向量无法独立复算）。库内 `SplitRangeControl`（单输出分程）、`RatioController`（比值站）都不解这两个语义。ROADMAP §7.6 的锅炉/加热炉条目全部依赖它们。
5. **#8~#11 是设备诊断层的四条实缺**：真空闸阀互斥（半导体 EFEM 必备，库内只有 `InterlockMatrix` 的通用掩码，无门类语义）；安全阀起跳计数（过程安全台账刚需，`AlarmManager` 数的是报警不是动作）；疏水阀诊断（蒸汽系统节能刚需，全域零覆盖）；雷达回波质量（液位可靠性，`I_DL_AnalogSensor` 只管 4~20 mA 质量码，不解回波域）。
6. **#12~#16 是轴侧「安全管理层」整层缺失**：库内 25 件 Motion 覆盖了运动**指令**（定位/速度/齿轮/凸轮/叠加/回零/软限位/锁存），但**没有一个件管轴的生命周期安全时序**——抱闸与使能的先后（掉落风险的唯一防线）、虚拟主轴（凸轮/齿轮主值来源）、指令排队（上位机连发必丢单）、凸轮表校验（表错则整机撞机）、到位稳定判定（`InPosition` 是取放联锁的判据）。这一层不做，Motion 就只是「指令封装」而不是「轴安全」。
7. **#17~#20 是过程单元的保护与顺控**：防喘振（压缩机爆炸防护级）、塔压差控制（精馏稳定性）、氮气置换（可燃气氛点火前的强制步骤）、批次转移（相/步骤最小实证件）。四件全部只编排已收口能力（`RateLimiter` / `BatchPhaseBase` 的纪律、`Integrator` 由调用方注入）。

### 1.2 来源配比（本轮取源账目）

| 源 | 件数 | 件号 | 借用层级 |
|---|---|---|---|
| **T2-1 LGF**（Converter / Data Handling） | **3** | #1/#2/#3 | 分类事实 + 行为定义（闭源，零代码行） |
| T2-5 Mod_PID_Control | 2（次源） | #6/#7/#18 | 参数域组织（零代码行） |
| T2-7 PackML | 1（次源） | #19 | 最小子集态命名（不作主源） |
| T2-8 ISA-88 / NE107 | 3（次源） | #8/#9/#20 | 互锁语义 / 健康分级 / 相步骤语义 |
| T2-4 S7 Motion | 2（次源） | #12/#13 | 工艺对象分型与使能时序组织 |
| **T1-6 PLCopen** | **3（次源）** | #14/#15/#16 | `MC_BUFFERMODE` / CamTableSelect 纪律 / `InPosition` 语义（公开规范） |
| T1-1 OSCAT Basic / T1-2 OSCAT Building | 2（次源） | #10/#11 | 「域外行为显式化」写法纪律（零函数体、零常量名） |
| **T0-7 / T0-2 变体线** | **2** | #4/#5 | 零检索（R14 三判据准入：逐引脚对应标准语义 + 委托标准语义 + clean-room） |
| 自研线（公开工程惯例） | 1（主源） | #17 | 喘振判据公开惯例 |

> **配额结论**：满足「至少 1 个组件族来自 T2 或 T1 源」（T2-1 LGF 3 件为独立子族；T1-6 三件、T2-5/7/8 各若干为次源）；满足源矩阵 §4「≥1 个 T2 非 ST 源 + ≥1 个 T1 ST 原生源」双向要求；**未触碰任何已 ✔ 收口组（T0 八行）的存量语义**，T0-7/T0-2 只做变体线扩族，按 M-E5 裁定**不改状态列 ✔**。

---

## 2 四批划分与码位账目

| 批 | 主题 | 件号 | 件数 | 信息级槽（2/件） | 故障级槽（3/件） |
|---|---|---|---|---|---|
| 批 1 | **Level 0 数据编码与时基原子** | #1-5 | 5 | `045C`~`0465` | `03A8`~`03B6` |
| 批 2 | **限值选择律与安全互斥族** | #6 #7 #17 #8 #9 | 5 | `2B01`/`2B02` · `2C01`/`2C02` · `01DA`/`01DB` · `0172`/`0173` · `0174`/`0175` | `2B10`-`2B12` · `2C10`-`2C12` · `030B`-`030D` · `033C`-`033E` · `033F`-`0341` |
| 批 3 | **过程诊断与批处理顺控** | #10 #11 #18 #19 #20 | 5 | `0176`/`0177` · `0178`/`0179` · `01DC`/`01DD` · `01DE`/`01DF` · `01E0`/`01E1` | `0342`-`0344` · `0345`-`0347` · `030E`-`0310` · `0311`-`0313` · `0314`-`0316` |
| 批 4 | **轴侧安全与指令管理** | #12-16 | 5 | `01D5`~`01DE` | `02EA`~`02F8` |

**槽位账目**：20 件 × 5 槽 = **100 槽**（信息 40 + 故障 60）。
**实测校验**：100 个码位对全库 364 件做占用比对 → **`CLASH: []`**（零冲突）；五个段的分带起点均为「实测上界 + 1」。
**R22 收尾游标（供 R23 引用，届时须当场复测）**：

| 段 | 轮后信息级游标 | 轮后故障级游标 |
|---|---|---|
| `0001` | **`0466`** | **`03B7`** |
| `0002` | **下一 CC = `2D`** | — |
| `0003` | **`017A`** | **`0348`** |
| `0004` | **`01DF`** | **`02F9`** |
| `0005` | **`01E2`** | **`0317`** |

**逐件 5 槽码位块（派单原文，编码专家照抄，不得自选码位）**：

| # | 组件 | 信息槽 1（用） | 信息槽 2 | 故障槽 1（用） | 故障槽 2（用） | 故障槽 3 |
|---|---|---|---|---|---|---|
| 1 | `IntToFixedField` | `0001_045C` | `045D` 预留 | `03A8` | `03A9` 预留 | `03AA` 预留 |
| 2 | `FixedFieldToInt` | `045E` | `045F` | `03AB` | `03AC` | `03AD` 预留 |
| 3 | `LrealToFixedField` | `0460` | `0461` | `03AE` | `03AF` | `03B0` 预留 |
| 4 | `FirstSetBit` | `0462` | `0463` | `03B1` | `03B2` 预留 | `03B3` 预留 |
| 5 | `FrequencyMeasure` | `0464` | `0465` | `03B4` | `03B5` | `03B6` 预留 |
| 6 | `CrossLimitSelect` | `0002_2B01` | `2B02` | `2B10` | `2B11` | `2B12`（兜底） |
| 7 | `ExcessAirTrim` | `2C01` | `2C02` | `2C10` | `2C11` | `2C12`（兜底） |
| 8 | `SlitValveInterlock` | `0003_0172` | `0173` | `033C` | `033D` | `033E`（兜底） |
| 9 | `PressureReliefMonitor` | `0174` | `0175` | `033F` | `0340` | `0341`（兜底） |
| 10 | `SteamTrapMonitor` | `0176` | `0177` | `0342` | `0343` | `0344`（兜底） |
| 11 | `LevelRadarValidate` | `0178` | `0179` | `0345` | `0346` | `0347`（兜底） |
| 12 | `AxisBrakeSeq` | `0004_01D5` | `01D6` | `02EA` | `02EB` | `02EC`（兜底） |
| 13 | `VirtualMasterAxis` | `01D7` | `01D8` | `02ED` | `02EE` | `02EF`（兜底） |
| 14 | `MotionCmdQueue` | `01D9` | `01DA` | `02F0` | `02F1` | `02F2`（兜底） |
| 15 | `CamTableValidate` | `01DB` | `01DC` | `02F3` | `02F4` | `02F5` |
| 16 | `AxisInPosMonitor` | `01DD` | `01DE` | `02F6` | `02F7` | `02F8`（兜底） |
| 17 | `CompressorSurgeGuard` | `0005_01DA` | `01DB` | `030B` | `030C` | `030D`（兜底） |
| 18 | `ColumnDpCtrl` | `01DC` | `01DD` | `030E` | `030F` | `0310`（兜底） |
| 19 | `InertPurgeSeq` | `01DE` | `01DF` | `0311` | `0312` | `0313`（兜底 + 耗尽复用，R90） |
| 20 | `BatchTransferSeq` | `01E0` | `01E1` | `0314` | `0315` | `0316`（兜底） |

> **预留槽纪律**：标「预留」的槽必须在头注释错误码表内写 `预留禁用（不得挪用）`，**实现体不得出现该码的任何赋值**（机检按「码位出现即算占用」判，出现即违规）。

---

## 3 编码派单规格（引脚级，可直接编码）

> **通用接口三件套（全 20 件统一）**：`VAR_OUTPUT` 必须含 `eErr : UDINT`（0 = 无错）、`bError : BOOL`（**仅故障级置位**）、`bValid : BOOL`（返回值/输出可用）。
> **单位纪律**：每件头注释的「单位表」段列出全部物理量单位；引脚注释同行 `// 中文 [单位] / English [unit]`，无单位裸数值一律驳回。
> **子库依赖纪律（本轮硬约束，勿破）**：
> - `DL_Algo` 件（#6/#7）**不得引用** `DL_Base` / `DL_MathData`（`DL_Algo/VERSION.md` 明示只依赖 `Standard.library` + 子库内部）；需要迟滞/限幅时**内联等价实现**并在头注释「依赖收窄」段声明（R11 留档③先例）。
> - `DL_Motion` 件（#12~#16）**不得引用任何其他 `DL_` 子库**（`DL_Motion/VERSION.md` 明示），只能用 `Standard.library`（`TON`/`R_TRIG`/`MIN`/`MAX`/`ABS`/`LIMIT`）。
> - `DL_Device` 件（#8~#11）默认**仅 `Standard.library`**；健康出口可引用同库契约 `E_DL_Ne107Status`（**引用不重声明**，R70 唯一属主）。
> - `DL_Process` 件（#17~#20）可依赖 Level 0/1（合法方向），但**只允许组合调用**，不得复制低层算法；跨件调用须按 R36 手算退出跟踪首拍。

### 3.1 批 1（Level 0 数据编码与时基原子）

#### #1 `FC_DL_IntToFixedField` —— 整数 → 定宽字段
- **分类**：`DL_MathData / DataFormat` ｜ **前缀** `FC_DL_` ｜ **类型** FUNCTION → `BOOL`（TRUE = 编码成功）｜ **复杂度** M
- **VAR_INPUT**：
  | 引脚 | 类型 | 默认 | 单位 | 说明 |
  |---|---|---|---|---|
  | `nValue` | `DINT` | — | — | 待编码整数，全域 |
  | `uWidth` | `UINT` | `8` | 字符 | 字段宽度，范围 1~20 |
  | `bZeroPad` | `BOOL` | `TRUE` | — | TRUE 零填充 / FALSE 空格填充 |
  | `bForceSign` | `BOOL` | `FALSE` | — | 正数是否强制 `+` 号 |
- **VAR_OUTPUT**：`sField : STRING(20)`（编码结果，右对齐）、`uFieldLen : UINT`（实际写入字符数）、`eErr` / `bError` / `bValid`
- **VAR CONSTANT**：`DL_FIELD_MAX : UINT := 20`（`STRING(20)` 物理上限，禁写成 255）
- **功能规格**：符号位 + 数字位逐字符从右往左写；填充字符（`'0'` 或 `' '`）填满剩余位；**整数分解必须走负域**——`DINT` 最小值 `−2147483648` 取绝对值溢出，故一律 `nWork := nValue; WHILE nWork < 0 DO digit := -(nWork MOD 10)` 式负域取模（或先判 `nValue = DL_DINT_MIN` 走常量字符串分支），**禁 `ABS(nValue)` 后再取模**。
- **边界安全条件**：① `uWidth < 1` → 钳到 1 + 信息 `045C`；`uWidth > 20` → 钳到 20 + 信息 `045C`；② 可用宽度（`uWidth − 符号位`）不足以容纳全部数字位 → **拒绝编码**（`sField := ''`、`bValid := FALSE`）+ 故障 `03A8`，**绝不输出半截数字**；③ 索引写入一律 `< uWidth` 且有 `IF uIdx <= DL_FIELD_MAX` 二次闸；④ 无状态机（`状态机 : N/A`，纯函数无 CASE）。
- **码位**：信息 `045C`（宽度已钳位）/ `045D` 预留 ｜ 故障 `03A8`（宽度不足，拒绝编码）/ `03A9` 预留 / `03AA` 预留
- **来源**：T2-1 LGF Converter/Data Handling（只借「数值↔定宽文本独立成族」的分类事实与行为定义；参数名、填充策略、码位 100 % 自有）

#### #2 `FC_DL_FixedFieldToInt` —— 定宽字段 → 整数
- **分类**：`DL_MathData / DataFormat` ｜ FUNCTION → `BOOL` ｜ **复杂度** M
- **VAR_INPUT**：`sField : STRING(20)`；`uWidth : UINT := 8`（参与解析的字符数，1~20）；`bAllowLeadingSpace : BOOL := TRUE`；`bAllowSign : BOOL := TRUE`
- **VAR_OUTPUT**：`nValue : DINT`；`uParsedLen : UINT`（成功解析的数字位数）；`nErrPos : UINT`（1 基首个非法字符位置，0 = 无）；`bSaturated : BOOL`；`eErr` / `bError` / `bValid`
- **功能规格**：先 `LEN` 一次锁存（**R37/R38**：不得边解析边重算长度），宽度取 `MIN(uWidth, 锁存长度)`；剥前导填充（零与/或空格，按 `bAllowLeadingSpace`）→ 取符号 → 逐字符 `'0'..'9'` 校验 → **负域累乘**（`nAcc := nAcc * 10 - digit`，全程负域避免超上界）→ 末尾取反。
- **边界安全条件**：① `uWidth < 1` → 故障 `03AC`；② 有效字符数（剥填充后）= 0 → 故障 `03AC`；③ 非数字字符 → 故障 `03AB` + `nErrPos` 精确到字符（`nValue` 置 0、`bValid := FALSE`）；④ 累乘越 `DINT` 域 → 饱和到 `±2147483647`（下界用 `−2147483647` 哨兵，`−2147483648` 不可达，见 R21 `DL_DINT_MIN_ABS` 先例）+ `bSaturated := TRUE` + 信息 `045F`，`bValid := TRUE`（饱和可观测，与「非法字符」性质不同）；⑤ 剥填充动作发生 → 信息 `045E`。
- **码位**：信息 `045E`（已剥离前导填充）/ `045F`（数值超域已饱和）｜ 故障 `03AB`（非法字符）/ `03AC`（有效字符数为 0 或宽度非法）/ `03AD` 预留
- **来源**：同 #1（与 #1 构成逆运算对，验收必须做「#1 → #2 round-trip」向量）

#### #3 `FC_DL_LrealToFixedField` —— 浮点 → 定宽定点文本
- **分类**：`DL_MathData / DataFormat` ｜ FUNCTION → `BOOL` ｜ **复杂度** **H**
- **VAR_INPUT**：`fValue : LREAL`；`uIntDigits : UINT := 6`（整数部分最少字符数，1~15）；`uDecDigits : UINT := 3`（小数位，0~6）；`bRound : BOOL := TRUE`（TRUE 四舍五入 / FALSE 截断）；`bForceSign : BOOL := FALSE`
- **VAR_OUTPUT**：`sField : STRING(24)`；`uFieldLen : UINT`；`bSaturated : BOOL`；`eErr` / `bError` / `bValid`
- **VAR CONSTANT**：`DL_FF_MAXLEN : UINT := 24`；`DL_FF_INTMAX : UINT := 15`（LREAL 有效十进制位上限，2^53 ≈ 9.007E15）；`DL_FF_DECMAX : UINT := 6`
- **功能规格**：**禁用平台 `LREAL_TO_STRING`**（小数位/科学计数法口径三平台不一致）。自行分解：`ABS(fValue)` → 按 10 的幂缩放取整（四舍五入加 `0.5 × 10^-d` 后 `TRUNC`；**负值在绝对值域处理**，末位再加符号，天然对称）→ 整数部分逐位负域分解（同 #1）→ 小数部分按位取余 → 拼接。进位导致整数位溢出可用宽度时按饱和处理。
- **边界安全条件**：① 非有限输入（NaN 用 `(x−x)<>(x−x)`，±Inf 用 `ABS(x) > 1.7976931348623157E308`，**R79 精确判据，禁近似阈值**）→ 故障 `03AE`、`bValid := FALSE`（**不得输出 `'NaN'` 冒充合法报文**）；② `uIntDigits` 钳到 1~15、`uDecDigits` 钳到 0~6，越界钳位 + 信息 `0460`；③ `uIntDigits + uDecDigits + 2 > DL_FF_MAXLEN` → 故障 `03AF`（字段装不下）；④ 整数部分有效位 > `uIntDigits` → 饱和到全 `9` + `bSaturated := TRUE` + 信息 `0461`，`bValid := TRUE`；⑤ 小数位四舍五入实际进位 → 信息 `0460` 复用（**R90 不加码**，头注释写明复用理由）。
- **码位**：信息 `0460`（宽度/小数位已钳位 或 舍入进位）/ `0461`（整数部分已饱和）｜ 故障 `03AE`（非有限输入）/ `03AF`（字段宽度装不下）/ `03B0` 预留
- **遗留假设段（必须写进头注释）**：整数部分 > 15 位十进制时 LREAL 已无精确表示，本件按「输入本身已失真」处理，不承诺末位准确。

#### #4 `FC_DL_FirstSetBit` —— 首个置位位定位
- **分类**：`DL_Base / BitString` ｜ FUNCTION → `BOOL`（TRUE = 找到）｜ **复杂度** M
- **VAR_INPUT**：`uValue : LWORD`；`uWidth : UINT := 64`（有效位宽 8 / 16 / 32 / 64）；`bHighFirst : BOOL := FALSE`（TRUE 高位优先）
- **VAR_OUTPUT**：`uBitIndex : UINT`（0 基位号，未找到 = 0）、`bFound : BOOL`、`eErr` / `bError` / `bValid`
- **功能规格**：按有效位宽构造掩码（宽 64 用 `DL_MASK64_ALL` **常量掩码**，全程无 `SHL(x,64)`——R10/R48 已两次实证该行为未定义）→ 屏蔽无效高位 → 低位优先从 0 升扫，高位优先从 `uWidth−1` 降扫；用 `WHILE` + `nGuard` 计数器（上限 `uWidth`，超限即退出，**防死锁**）。
- **边界安全条件**：① `uWidth` 不在 {8,16,32,64} → 钳到最近的合法值 + 信息 `0463`；② `uWidth = 0` → 故障 `03B1`、`bFound := FALSE`、`bValid := FALSE`；③ 屏蔽后全零 → `bFound := FALSE`、`bValid := TRUE` + 信息 `0462`（「没有置位位」是合法结论不是错误）；④ 高位优先模式下被屏蔽位绝不参与仲裁（先屏蔽后扫描，顺序不可反）。
- **码位**：信息 `0462`（全零，无置位位）/ `0463`（位宽已钳位）｜ 故障 `03B1`（位宽为 0）/ `03B2` 预留 / `03B3` 预留
- **来源**：T0-7 变体线，零检索。立项依据：R13 `BitArrayRotate`/`MaskCompare` 与 R21 `LwordBitFieldExtract` 三次留痕「位串族缺搜索」，属族内第四轴。

#### #5 `FB_DL_FrequencyMeasure` —— 门时计数测频
- **分类**：`DL_Base / Timing` ｜ **前缀** `FB_DL_` ｜ **复杂度** M
- **VAR_INPUT**：`bPulse : BOOL`（待测脉冲，任意占空比）；`bEnable : BOOL`；`tGateTime : TIME := T#100MS`（门时间，1 ms~10 000 ms）；`fLowFreqDead : REAL := 0.5`（低频死区，Hz，低于此值输出 0）
- **VAR_OUTPUT**：`fFreq : REAL`（[Hz]，分辨率 = `1/tGateTime`）、`fFreqRes : REAL`（[Hz] 当拍实际分辨率）、`uLastCount : UDINT`（上一门内沿数）、`bValid : BOOL`、`eErr` / `bError`
- **状态机**：`E_DL_FreqMeasState`（`eIdle` / `eGating` / `eReady` / `eFault`），`CASE` 含 `ELSE` 兜底（落 ELSE 置 `03B5` 并回 `eIdle`）。
- **功能规格**：`R_TRIG` 捕脉冲上升沿计数；`TON` 做门计时；门到时：`fFreq := uCount / TIME_TO_REAL(tGateEff) * 1000.0`（ms → s 换算，**带单位注释**）→ 计数清零重开门。
- **边界安全条件**：① `tGateTime < T#1MS` → 钳到 1 ms + 信息 `0464`；`> T#10S` → 钳到 10 s + 信息 `0464`；② `fFreq < fLowFreqDead` → 输出 0 + 信息 `0465`（**不得输出抖动小数冒充低频**）；③ `tGateTime` 参数非法（= 0 经钳位后不可能）→ 故障 `03B4` 保留给「门时间为 0 的构造路径」；④ `uCount` 在门切换拍出现回退（外部改写/溢出）→ 故障 `03B5`、`bValid := FALSE`；⑤ **`R_TRIG` 与 `TON` 实例必须在主体最前部无条件刷新**（R40 家族）。
- **码位**：信息 `0464`（门时间已钳位）/ `0465`（低于死区按 0 输出）｜ 故障 `03B4`（门时间为 0/非法）/ `03B5`（计数回退不可信，含状态机兜底复用，R90）/ `03B6` 预留
- **遗留假设段**：门切换拍可能多计/漏计 1 个沿，测量不确定度 `±1 计数`，即 `±1/tGateTime` Hz，须在头注释显式声明（**不得声称精确**）。

### 3.2 批 2（限值选择律与安全互斥族）

#### #6 `FB_DL_CrossLimitSelect` —— 燃烧双交叉限幅
- **分类**：`DL_Algo / ProcessControl` ｜ **复杂度** M
- **VAR_INPUT**：`fMasterOut : REAL`（[%] 主控输出 0~100）；`fAirFlow : REAL`（[Nm³/h] 实测空气流量）；`fGasFlow : REAL`（[Nm³/h] 实测燃气流量）；`fAirFuelRatio : REAL := 10.0`（[Nm³空气/Nm³燃气] 目标空燃比）；`fLeadMargin : REAL := 1.05`（[倍] 先行裕度，≥ 1.0）；`bAirLead : BOOL := TRUE`（TRUE 空气先行 / FALSE 燃气先行）；`bEnable : BOOL`
- **VAR_OUTPUT**：`fAirSp : REAL`（[%] 空气给定）；`fGasSp : REAL`（[%] 燃气给定）；`bLimited : BOOL`；`fLimitMargin : REAL`（[%] 距限幅点余量）；`eErr` / `bError` / `bValid`
- **状态机**：`E_DL_CrossLimitState`（`eIdle` / `eNormal` / `eAirLimited` / `eGasLimited` / `eFault`），`CASE` + `ELSE` 兜底。
- **功能规格**：空气先行时 `fGasAvail := fAirFlow / fAirFuelRatio`（燃气侧受空气实测约束）；燃气先行时 `fAirNeed := fGasFlow * fAirFuelRatio`。给定 = `MIN(主控折算值, 受约束侧可用值 × fLeadMargin)`，双侧钳 0~100。**先行裕度必须 > 1**（> 1 表示允许领先侧超前一拍），`fLeadMargin < 1.0` → 故障 `2B10` 并**双侧给定归零**（安全侧 = 切断燃料）。
- **边界安全条件**：① `fAirFuelRatio <= 0` → 故障 `2B10`、双侧归零；② 任一流量/输出非有限 → 故障 `2B11`、**保持末次有效给定**（切 0 会熄火/爆燃，与 #18 同侧策略）；③ 限幅生效 → 信息 `2B01`（空气侧受限）/ `2B02`（燃气侧受限）；④ 失能 → `eIdle`，`fGasSp := 0`、`fAirSp := 0`，两个输出**逐个显式赋 0**（R72 双路径清零，不依赖段尾镜像）；⑤ 除零前置闸先于任何除法。
- **码位**：信息 `2B01`（空气侧限幅生效）/ `2B02`（燃气侧限幅生效）｜ 故障 `2B10`（空燃比/先行裕度非法）/ `2B11`（输入非有限，保持末值）/ `2B12`（状态机兜底）
- **依赖纪律**：**不得引用** `DL_Base`/`DL_MathData`；迟滞与限幅内联等价实现并在头注释声明。

#### #7 `FB_DL_ExcessAirTrim` —— 氧量修正
- **分类**：`DL_Algo / ProcessControl` ｜ **复杂度** M
- **VAR_INPUT**：`fO2Meas : REAL`（[%] 烟气含氧量实测）；`fO2Target : REAL := 3.0`（[%] 目标氧量）；`fO2Deadband : REAL := 0.3`（[%] 死区半宽）；`fTrimLimit : REAL := 5.0`（[%] 修正量上限，对称）；`fTrimStep : REAL := 0.05`（[%] 单步修正量，> 0）；`fLoadRate : REAL`（[%/s] 负荷变化率）；`fRateFreeze : REAL := 2.0`（[%/s] 冻结门限）；`tConfirm : TIME := T#30S`；`bEnable : BOOL`
- **VAR_OUTPUT**：`fTrim : REAL`（[%] 空燃比修正量）；`bActive : BOOL`；`bFrozen : BOOL`；`eErr` / `bError` / `bValid`
- **状态机**：`E_DL_O2TrimState`（`eIdle` / `eActive` / `eFrozen` / `eFault`），`CASE` + `ELSE` 兜底。
- **功能规格**：偏差 `fDev := fO2Meas − fO2Target`；`|fDev| <= fO2Deadband` → 不修正（信息 `2C01`）、`fTrim` 保持；越死区且持续 `tConfirm` → 按固定步长（引脚 `fTrimStep`，缺省 0.05 %）累加修正，**累加后双侧钳 `±fTrimLimit`（抗饱和，不做积分回算）**；`|fLoadRate| > fRateFreeze` → 冻结修正（信息 `2C02`）、`fTrim` 保持。
- **边界安全条件**：① `fO2Target <= 0` 或 `fO2Deadband < 0` 或 `fTrimLimit <= 0` 或 `fTrimStep <= 0` → 故障 `2C10`、`fTrim := 0`（退回纯交叉限幅，安全可利用）；② 氧量或负荷率非有限 → 故障 `2C11`、保持末次 `fTrim`；③ `tConfirm = T#0S` → 直接生效（合法语义，不置错）；④ `TON` 实例无条件刷新；⑤ 失能 → `eIdle`、`fTrim := 0`、`bActive := FALSE`（逐项赋，R72）。
- **码位**：信息 `2C01`（死区内不修正）/ `2C02`（负荷变化率超限已冻结）｜ 故障 `2C10`（参数非法）/ `2C11`（输入非有限，保持末值）/ `2C12`（状态机兜底）

#### #17 `FB_DL_CompressorSurgeGuard` —— 压缩机防喘振
- **分类**：`DL_Process / ProcessSafety` ｜ **复杂度** **H**
- **VAR_INPUT**：`fSuctionPress : REAL`（[kPa abs] 吸入压力）；`fDischargePress : REAL`（[kPa abs] 排出压力）；`fFlow : REAL`（[Nm³/h] 实测流量）；`fFlowMinLine : REAL := 500.0`（[Nm³/h] 最小流量线）；`fSurgeMargin : REAL := 0.10`（[倍] 危险线裕度）；`fOpenRamp : REAL := 20.0`（[%/s] 放空阀快开斜率）；`fCloseRamp : REAL := 1.0`（[%/s] 慢关斜率）；`tConfirm : TIME := T#200MS`；`bEnable : BOOL`
- **VAR_OUTPUT**：`fBlowoffValve : REAL`（[%] 放空阀开度给定）；`bSurgeRisk : BOOL`；`bBlowoffActive : BOOL`；`fPressureRatio : REAL`（[倍] 压比）；`eErr` / `bError` / `bValid`
- **状态机**：`E_DL_SurgeState`（`eIdle` / `eNormal` / `eRiskBlowoff` / `eRecovering` / `eFault`），`CASE` + `ELSE` 兜底。
- **功能规格**：压比 `fPressureRatio := fDischargePress / fSuctionPress`（除零前置闸）；危险流量线按压比修正（`fFlowDanger := fFlowMinLine × (1 + fSurgeMargin × (fPressureRatio − 1))`，线性近似，公式与系数 100 % 自有）；`fFlow < fFlowDanger` 持续 `tConfirm` → 阀**快开**（`fOpenRamp`）；流量恢复到 `fFlowDanger × (1 + 回差)` 以上 → **慢关**（`fCloseRamp`），回差常量 `DL_SURGE_HYST := 0.15`（[倍]，禁裸数）。斜率限制**组合调用** `FB_DL_RateLimiter`（Level 1 → Level 0/1 合法），两方向斜率各一实例，**须按 R36 手算首次扫描退出跟踪首拍**。
- **边界安全条件**：① `fFlowMinLine <= 0` 或 `fSurgeMargin <= 0` 或斜率 `<= 0` → 故障 `030B`、阀**全开**（安全侧：宁可放空不可喘振）；② 任一输入非有限 → 故障 `030C`、**保持末次阀位**（P0 级：不得因坏值关阀）；③ 吸入压力 `<= 0` → 按 `030B` 参数类处理（压比无意义）；④ 失能 → 阀按 `fCloseRamp` 关闭但 `bBlowoffActive := FALSE`、`bSurgeRisk` 保持可观测；⑤ `eRiskBlowoff` 不得被 `eNormal` 直接抢占（必须经 `eRecovering` 回差确认，R41 家族）。
- **码位**：信息 `01DA`（流量低于危险线已开放空阀）/ `01DB`（压比回落出回差带，已退出放空）｜ 故障 `030B`（参数非法）/ `030C`（输入非有限，保持末值）/ `030D`（状态机兜底）

#### #8 `FB_DL_SlitValveInterlock` —— 真空闸阀互斥互锁
- **分类**：`DL_Device / ValveInterlock` ｜ **复杂度** M
- **VAR_INPUT**：`bRequest : BOOL`（开闸阀请求）；`bAtmDoorClosed : BOOL`（大气侧门「已关」反馈）；`bAtmDoorOpen : BOOL`（大气侧门「已开」反馈）；`fChamberVac : REAL`（[Pa] 腔体真空度）；`fVacThreshold : REAL := 100.0`（[Pa] 允许开闸阀的真空阈值）；`bArmRetracted : BOOL`（机械臂已退出腔体）；`tFbTimeout : TIME := T#3S`（到位反馈超时）；`bEnable : BOOL`
- **VAR_OUTPUT**：`bValveOpenCmd : BOOL`；`bValveCloseCmd : BOOL`；`bInterlockOk : BOOL`；`uBlockMask : WORD`（1 = 真空不足 / 2 = 大气门未关 / 4 = 机械臂未退 / 8 = 反馈超时）；`eErr` / `bError` / `bValid`
- **状态机**：`E_DL_SlitValveState`（`eIdle` / `eOpening` / `eOpen` / `eClosing` / `eInterlock` / `eFault`），`CASE` + `ELSE` 兜底。
- **功能规格**：三条件同拍与（真空达标 ∧ 大气门已关 ∧ 机械臂已退）→ 放行开阀；任一不满足 → `uBlockMask` 置对应位、拒绝开阀。`bValveOpenCmd` 与 `bValveCloseCmd` **互斥，先清后置**（同拍双 TRUE 是电磁阀线圈烧毁根因）。
- **边界安全条件**：① 门位反馈自相矛盾（`bAtmDoorOpen AND bAtmDoorClosed` 或两者皆 FALSE 持续 `tFbTimeout`）→ 故障 `033D`，**按「门未关」处理**（保守侧）；② 真空度非有限或 `< 0` → 故障 `033E`，按「真空不足」处理（**不假定真空**）；③ 联锁不满足 → 故障 `033C` + `uBlockMask`（HMI 直接显示位）；④ 到位反馈超时 → 信息 `0173`，保持当前指令并提示（不自行反转）；⑤ 失能 → `eClosing`（先关阀），`bValveOpenCmd := FALSE`；⑥ `TON` 实例无条件刷新。
- **码位**：信息 `0172`（联锁满足，已放行开阀）/ `0173`（到位反馈超时，保持指令）｜ 故障 `033C`（联锁不满足拒绝开阀）/ `033D`（门位反馈自相矛盾）/ `033E`（真空度非法，按不足处理）

#### #9 `FB_DL_PressureReliefMonitor` —— 安全阀起跳/回座监视
- **分类**：`DL_Device / SafetyMonitor` ｜ **复杂度** M
- **VAR_INPUT**：`fUpPressure : REAL`（[bar g] 阀前压力）；`fDnPressure : REAL`（[bar g] 阀后压力）；`fSetPressure : REAL := 10.0`（[bar g] 整定压力）；`fBlowdown : REAL := 0.90`（[倍] 回座压力 / 整定压力，0.5~0.95）；`tConfirm : TIME := T#200MS`；`tMinLift : TIME := T#500MS`（最短起跳时长，低于此按工艺波动滤除）；`uMaintLimit : UINT := 50`（[次] 动作次数维护门限）；`bEnable : BOOL`
- **VAR_OUTPUT**：`bLifted : BOOL`；`nLiftCount : UDINT`（[次] 累计动作次数）；`tOpenTotal : TIME`（累计开启时长）；`fPeakPressure : REAL`（[bar g] 本次起跳峰值）；`eHealth : E_DL_Ne107Status`（引用唯一属主）；`eErr` / `bError` / `bValid`
- **状态机**：`E_DL_ReliefState`（`eIdle` / `eLifted` / `eReseat` / `eFault`），`CASE` + `ELSE` 兜底。
- **功能规格**：`fUpPressure > fSetPressure` 持续 `tConfirm` → 起跳；回座判据 `fUpPressure < fSetPressure × fBlowdown`（**必须用回座比做迟滞，硬阈值会在整定点抖动计数**）；单次起跳时长 `< tMinLift` → 不计入 `nLiftCount`（信息 `0175`）。健康映射（写死头注释）：起跳计数 ≥ `uMaintLimit` → `eMaintenanceReq`；阀前持续超整定且阀后压力同步升高（疑似不泄放）→ `eFailure`；其余 → `eOk`。
- **边界安全条件**：① `fSetPressure <= 0` 或 `fBlowdown <= 0` 或 `>= 1.0` → 故障 `033F`、`bValid := FALSE`；② 任一压力非有限 → 故障 `0340`，**保持 `bLifted` 与计数不变**（坏值不得伪造动作）；③ `bError` 置位源必须在 `uErrorId`（`eErr`）找到对应码（R45 纪律）；④ 计数与累计时长 `UDINT`/`TIME` 溢出守卫（累加前判上界，饱和不回绕，R35）；⑤ 失能 → 计数与累计时长**保持**（台账不得因失能清零）。
- **码位**：信息 `0174`（起跳事件已记录）/ `0175`（起跳时长低于 `tMinLift`，按工艺波动滤除）｜ 故障 `033F`（整定压力/回座比非法）/ `0340`（压力输入非有限，保持台账）/ `0341`（状态机兜底）

### 3.3 批 3（过程诊断与批处理顺控）

#### #10 `FB_DL_SteamTrapMonitor` —— 疏水阀堵塞/泄漏诊断
- **分类**：`DL_Device / Diagnostic` ｜ **复杂度** M
- **VAR_INPUT**：`fTin : REAL`（[°C] 阀前温度）；`fTout : REAL`（[°C] 阀后温度）；`fDeltaNormal : REAL := 10.0`（[K] 正常最小温差）；`fDeltaLeak : REAL := 5.0`（[K] 泄漏判定温差上限）；`fTinMin : REAL := 80.0`（[°C] 蒸汽工况最低阀前温度）；`tConfirm : TIME := T#30S`；`bEnable : BOOL`
- **VAR_OUTPUT**：`fDelta : REAL`（[K] 实测温差 = `fTin − fTout`）；`bNormal : BOOL`；`bSteamLeak : BOOL`；`bBlocked : BOOL`；`eHealth : E_DL_Ne107Status`；`eErr` / `bError` / `bValid`
- **状态机**：`E_DL_TrapState`（`eIdle` / `eNormal` / `eLeak` / `eBlocked` / `eFault`），`CASE` + `ELSE` 兜底。
- **功能规格**（公开工程判据，clean-room）：`fDelta >= fDeltaNormal` → 正常；`fDelta <= fDeltaLeak` **且阀前温度达工况** → 蒸汽泄漏；`fTin < fTinMin`（进出口均偏低、无温差）→ 堵塞。三判据各带 `tConfirm` 持续确认窗，**单拍越限不迁移**（A5-D1 家族）。
- **边界安全条件**：① `fDeltaLeak >= fDeltaNormal` → 故障 `0343`（判据自相矛盾，区间为空）、`bValid := FALSE`；② 温度非有限 → 故障 `0342`、保持上次判定；③ 阀前温度低于 `fTinMin` → 信息 `0177`「工况未建立」，**冻结全部故障判定**（冷态停机时全域「泄漏」是最大误报源）；④ 判定落入正常带 → 信息 `0176`；⑤ 健康映射：泄漏 → `eOutOfSpec`（能耗越界）、堵塞 → `eMaintenanceReq`（需拆检）、均写进头注释（等级→健康映射不得散落实现体）。
- **码位**：信息 `0176`（温差判据落入正常带）/ `0177`（工况未建立，冻结判定）｜ 故障 `0342`（温度输入非有限）/ `0343`（判据阈值自相矛盾）/ `0344`（状态机兜底）
- **来源**：T1-1 OSCAT 式「域外行为显式化」写法纪律（次源）+ 公开疏水阀温差判据（见 `RAW_NOTES_R22.md` §2）。**未复制任何代码行、函数名、常量名**。

#### #11 `FB_DL_LevelRadarValidate` —— 雷达液位回波可信度仲裁
- **分类**：`DL_Device / SignalQuality` ｜ **复杂度** M
- **VAR_INPUT**：`fLevel : REAL`（[m] 雷达测得液位）；`fQuality : REAL`（[%] 回波置信度 0~100）；`fSnr : REAL`（[dB] 回波信噪比）；`fSpan : REAL := 10.0`（[m] 量程上限）；`fQualityMin : REAL := 40.0`（[%] 置信度门限）；`fSnrMin : REAL := 10.0`（[dB] 信噪比门限）；`fRateLimit : REAL := 0.5`（[m/s] 液位变化率上限，防跳变）；`tConfirm : TIME := T#10S`；`bEnable : BOOL`
- **VAR_OUTPUT**：`fLevelOut : REAL`（[m] 发布值：可信则实时值，否则末次可信值）；`bTrusted : BOOL`；`uSuspectMask : WORD`（1 = 置信度低 / 2 = 信噪比低 / 4 = 超量程 / 8 = 变化率跳变）；`eHealth : E_DL_Ne107Status`；`eErr` / `bError` / `bValid`
- **状态机**：`E_DL_RadarState`（`eIdle` / `eTrusted` / `eSuspect` / `eFault`），`CASE` + `ELSE` 兜底。
- **功能规格**：四判据同拍评估（非逐条早退，**全部判据都要写进掩码**便于现场定位）；`bTrusted = (uSuspectMask = 0)`；不可信时 `fLevelOut` 保持末次可信值且 `eHealth := eCheckFunction`（NE107 「需检查功能」侧）。变化率判据用 `fLevel` 与末次可信值差 / 采样周期（采样周期由 `tSample` 引脚注入，**禁读系统时钟**）。
- **边界安全条件**：① `fSpan <= 0` 或门限非法 → 故障 `0345`、`bValid := FALSE`；② 任一输入非有限 → 故障 `0346`、本次不更新 `fLevelOut`（**R42：跨拍取值必须本拍复验，坏值绝不进联锁**）；③ 液位 `< 0` 或 `> fSpan` → 掩码置「超量程」，不按可信值发布；④ 初始无历史可信值 → `fLevelOut := 0` + `bValid := FALSE`（**不得把 0 m 当可信液位发布**，R43 家族）；⑤ 失能 → `bTrusted := FALSE`、`eHealth := eUnknown`。
- **码位**：信息 `0178`（质量指标低于门限，保持末次可信值）/ `0179`（变化率跳变，单拍剔除）｜ 故障 `0345`（量程/门限参数非法）/ `0346`（输入非有限，不更新发布值）/ `0347`（状态机兜底）

#### #18 `FB_DL_ColumnDpCtrl` —— 精馏塔压差控制
- **分类**：`DL_Process / ProcessControl` ｜ **复杂度** M
- **VAR_INPUT**：`fDpMeas : REAL`（[kPa] 塔压差实测）；`fDpSp : REAL := 5.0`（[kPa] 压差设定）；`fDpDeadband : REAL := 0.2`（[kPa] 死区半宽）；`fOutMin : REAL := 0.0`（[%]）；`fOutMax : REAL := 100.0`（[%]）；`fDpHighLimit : REAL := 8.0`（[kPa] 防冲塔上限）；`tConfirm : TIME := T#2S`；`bEnable : BOOL`
- **VAR_OUTPUT**：`fRefluxOut : REAL`（[%] 回流量给定）；`fReboilOut : REAL`（[%] 再沸热源给定）；`bDpHigh : BOOL`；`bLimited : BOOL`；`eErr` / `bError` / `bValid`
- **状态机**：`E_DL_ColumnDpState`（`eIdle` / `eNormal` / `eDpHigh` / `eDpLow` / `eFault`），`CASE` + `ELSE` 兜底。
- **功能规格**：以 `fDpSp` 为基准做**增量式**双向调节（ΔP 偏高 → 增回流 / 减再沸；偏低 → 反向），步长引脚 `fStep`（缺省 1.0 %），累加后钳 `fOutMin`~`fOutMax`（抗饱和：**钳位后不再累加，防积分堆死**）。`fDpMeas > fDpHighLimit` 持续 `tConfirm` → `bDpHigh`：再沸**立即降到 `fOutMin`**（防冲塔优先于压差调节），回流抬到上限。
- **边界安全条件**：① `fDpSp <= 0`、`fOutMin >= fOutMax`、`fDpHighLimit <= fDpSp`、`fStep <= 0` 任一 → 故障 `030E`、双输出置 `fOutMin`；② `fDpMeas` 非有限 → 故障 `030F`、**保持末次输出**（塔不能因坏值断热）；③ 死区内 → 信息 `01DC`（不调节）、输出保持；④ `bDpHigh` 进入/退出各一条信息码（`01DD` 进 / 复用 `01DC` 出，R90 注明）；⑤ 失能 → `eIdle`、输出置 `fOutMin`、`bDpHigh` 清零（逐项赋）。
- **码位**：信息 `01DC`（ΔP 在死区内不调节 或 已退出防冲塔）/ `01DD`（ΔP 越上限，已按防冲塔策略分配）｜ 故障 `030E`（参数非法）/ `030F`（输入非有限，保持末值）/ `0310`（状态机兜底）

#### #19 `FB_DL_InertPurgeSeq` —— 氮气置换顺控
- **分类**：`DL_Process / Sequence` ｜ **复杂度** M
- **VAR_INPUT**：`bStart : BOOL`；`bAbort : BOOL`；`fO2Meas : REAL`（[%] 氧含量实测）；`bO2SensorOk : BOOL`（氧分析仪有效性）；`fO2Target : REAL := 2.0`（[%] 目标氧含量）；`uMaxCycles : UINT := 3`（[次] 最大置换循环）；`tEvac : TIME := T#60S`（抽真空时长）；`tFill : TIME := T#60S`（充氮时长）；`tHold : TIME := T#30S`（保压取样时长）；`fVacOk : REAL := -80.0`（[kPa g] 抽真空到位阈值）
- **VAR_OUTPUT**：`bVacValveCmd : BOOL`；`bN2ValveCmd : BOOL`；`bVentValveCmd : BOOL`；`uCycleDone : UINT`（[次]）；`bDone : BOOL`；`bFailed : BOOL`；`eErr` / `bError` / `bValid`
- **状态机**：`E_DL_PurgeState`（`eIdle` / `eEvacuate` / `eFillN2` / `eHoldVerify` / `eCycleDone` / `eComplete` / `eFailed` / `eFault`），`CASE` + `ELSE` 兜底。
- **功能规格**：单循环 = 抽真空（`tEvac` 且真空达 `fVacOk`）→ 充氮（`tFill`）→ 保压取样（`tHold` 后读 `fO2Meas`）；`fO2Meas <= fO2Target` → `eComplete`；否则 `uCycleDone + 1`，达 `uMaxCycles` 仍不达标 → `eFailed`。**每个相各一只 `TON` 实例、相转出时按段断输入一拍**（R40 家族高危区：跨相复用一只 `TON` 是三次事故的共同形态）。
- **边界安全条件**：① `fO2Target <= 0` 或 `uMaxCycles = 0` 或任一 `TIME = T#0S` → 故障 `0311`、回 `eIdle`；② `bO2SensorOk = FALSE` → 故障 `0312`、**禁止放行**（`bDone` 恒 FALSE），阀全关；③ 循环耗尽未达标 → `bFailed := TRUE` + 故障 `0313`；④ `bAbort` **任意拍**生效 → 三相阀全关、回 `eIdle`（不排队、不回退重来，R34 家族）；⑤ 状态机兜底复用 `0313`（R90 不加码，头注释写明）；⑥ 三个阀输出互斥，先清后置。
- **码位**：信息 `01DE`（单循环未达标，进入下一循环）/ `01DF`（取样窗内氧含量已达目标）｜ 故障 `0311`（参数非法）/ `0312`（氧分析仪无效，禁止放行）/ `0313`（置换循环耗尽未达标，含状态机兜底复用）

#### #20 `FB_DL_BatchTransferSeq` —— 批次物料转移顺控
- **分类**：`DL_Process / Sequence` ｜ **复杂度** M
- **VAR_INPUT**：`bStart : BOOL`；`bAbort : BOOL`；`bSrcValveFb : BOOL`（源阀开到位）；`bDstValveFb : BOOL`（目标阀开到位）；`fTransferred : REAL`（[m³] **由调用方注入累计量**，本件不积分）；`fVolumeTarget : REAL := 5.0`（[m³] 目标转移量）；`fFlow : REAL`（[m³/h] 实测流量）；`fDrainFlow : REAL := 0.05`（[m³/h] 排空判据流量门限）；`tDrainVerify : TIME := T#10S`；`tValveFb : TIME := T#5S`；`tTimeout : TIME := T#30M`
- **VAR_OUTPUT**：`bPumpCmd : BOOL`；`bSrcValveCmd : BOOL`；`bDstValveCmd : BOOL`；`bDrained : BOOL`；`bDone : BOOL`；`bFailed : BOOL`；`eErr` / `bError` / `bValid`
- **状态机**：`E_DL_TransferState`（`eIdle` / `ePrepValve` / `eTransferring` / `eDraining` / `eClosing` / `eComplete` / `eAbort` / `eFault`），`CASE` + `ELSE` 兜底。
- **功能规格**：开阀 → 等双阀到位反馈 → 启泵（**泵必须在阀到位后启，干转烧泵是 OEE 头号杀手**）→ `fTransferred >= fVolumeTarget` → 停泵 → 排空验证（`fFlow < fDrainFlow` 持续 `tDrainVerify`）→ 关阀 → `eComplete`。累计量由调用方用 `FB_DL_Integrator` 注入（**复用优先，不内联积分**）。
- **边界安全条件**：① `fVolumeTarget <= 0` 或 `tTimeout = T#0S` → 故障 `0315`；② 阀位反馈超 `tValveFb` 未到位 → 故障 `0314`、**不启泵**、回 `eIdle`（先清输出）；③ 转移总时长超 `tTimeout` → 故障 `0315`（复用，R90）；④ `fTransferred` 回退（累计器复位/换批）→ 以本拍值为准并在头注释声明「批次切换须由调用方清零累计器」；⑤ `bAbort` 任意拍 → 停泵 → 关阀 → `eAbort`，**先停泵后关阀**（顺序不可反，防管道憋压）；⑥ 泵/阀三输出互斥，先清后置；⑦ 三个 `TON` 实例无条件刷新。
- **码位**：信息 `01E0`（累计量由外部积分器注入，本件不重复积分）/ `01E1`（排空验证窗内流量持续低于门限，判排空完成）｜ 故障 `0314`（阀位反馈超时，不启泵）/ `0315`（转移超时或参数非法，含复用）/ `0316`（状态机兜底）

### 3.4 批 4（轴侧安全与指令管理）

> **本批硬约束**：`DL_Motion` 不得引用任何其他 `DL_` 子库（`DL_Motion/VERSION.md` 明示），本批 5 件一律**自包含**，只用 `Standard.library` 的 `TON` / `R_TRIG` / `MIN` / `MAX` / `ABS` / `LIMIT`。

#### #12 `FB_DL_AxisBrakeSeq` —— 伺服抱闸时序
- **分类**：`DL_Motion / AxisSafety` ｜ **复杂度** M
- **VAR_INPUT**：`bEnableReq : BOOL`；`fActVel : REAL`（[mm/s] 轴实际速度）；`fStandstillVel : REAL := 1.0`（[mm/s] 静止判定速度阈）；`bBrakeReleaseFb : BOOL`（抱闸释放到位反馈）；`bBrakeFbAvailable : BOOL := TRUE`（现场无反馈时置 FALSE，按纯时间序列）；`tBrakeRelease : TIME := T#200MS`；`tBrakeHold : TIME := T#300MS`；`tStandstill : TIME := T#100MS`；`tFbTimeout : TIME := T#2S`
- **VAR_OUTPUT**：`bServoEnable : BOOL`；`bBrakeReleaseCmd : BOOL`；`bSeqDone : BOOL`；`eErr` / `bError` / `bValid`
- **状态机**：`E_DL_BrakeSeqState`（`eIdle` / `eReleasing` / `eEnabled` / `eStopping` / `eBraking` / `eDisabled` / `eFault`），`CASE` + `ELSE` 兜底。
- **功能规格**：
  - 上电序列：`bEnableReq` → `bBrakeReleaseCmd := TRUE` → 等 `bBrakeReleaseFb`（无反馈时等 `tBrakeRelease`）→ `bServoEnable := TRUE` → `eEnabled`。**先释放抱闸后使能**（先使能会让电机顶着抱闸出力，抱闸片烧蚀）。
  - 断电序列：`bEnableReq` 落 → `eStopping`：等 `|fActVel| < fStandstillVel` 持续 `tStandstill` → `bBrakeReleaseCmd := FALSE` → 等 `tBrakeHold` → `bServoEnable := FALSE`。**必须先静止后抱闸、先抱闸后断使能**（任一步序颠倒即掉轴）。
- **边界安全条件**：① 断电序列中轴未静止超 `tFbTimeout` → 故障 `02EB`、**拒绝断使能**（保持使能与抱闸打开，宁可报警不可掉轴）；② 抱闸释放反馈超 `tFbTimeout` → 故障 `02EA`、**禁止使能**；③ `bBrakeFbAvailable = FALSE` → 信息 `01D5`（按时间序列放行，头注释必须声明「无反馈时该风险由现场调试承担」）；④ 上电序列反馈迟到但收到 → 信息 `01D6`；⑤ 两输出互斥不适用（抱闸与使能是**有序**而非互斥），但输出必须**每拍先在段首赋 FALSE 再按状态置位**（R72 双路径）；⑥ 三个 `TON` 实例无条件刷新；⑦ 失能请求**不得**从 `eEnabled` 直跳 `eDisabled`（必经 `eStopping`）。
- **码位**：信息 `01D5`（抱闸反馈缺失，按时间序列放行）/ `01D6`（静止确认超时已延长抱闸等待）｜ 故障 `02EA`（抱闸释放反馈超时，禁止使能）/ `02EB`（断使能时轴仍未静止，拒绝断使能）/ `02EC`（状态机兜底）

#### #13 `FB_DL_VirtualMasterAxis` —— 虚拟主轴相位源
- **分类**：`DL_Motion / MasterSource` ｜ **复杂度** M
- **VAR_INPUT**：`bEnable : BOOL`；`fVelSet : REAL`（[mm/s] 主轴速度给定）；`fAccLimit : REAL := 1000.0`（[mm/s²] 加速限值）；`fDecLimit : REAL := 1000.0`（[mm/s²] 减速限值）；`bHold : BOOL`（保持当前相位）；`bPhaseReset : BOOL`（相位复位，上升沿生效）；`fPosInit : REAL := 0.0`（[mm] 复位目标相位）；`tSample : TIME := T#1MS`（[ms] 采样周期，**禁读系统时钟**）
- **VAR_OUTPUT**：`fMasterPos : LREAL`（[mm] 主轴相位）；`fMasterVel : REAL`（[mm/s]）；`fMasterAcc : REAL`（[mm/s²]）；`bReady : BOOL`；`bLimited : BOOL`；`eErr` / `bError` / `bValid`
- **状态机**：`E_DL_VMasterState`（`eIdle` / `eRamping` / `eSteady` / `eHolding` / `eFault`），`CASE` + `ELSE` 兜底。
- **功能规格**：速度按 `fAccLimit`/`fDecLimit` 斜坡逼近 `fVelSet`（`df := LIMIT(−fDecLimit·dt, fVelSet − fVel, +fAccLimit·dt)`）；`fMasterPos += fVel × dt`（`LREAL` 累加）。`bHold` 时速度斜坡降到 0（**不是瞬间归零**，瞬间归零会让从轴指令跳变）。`bPhaseReset` 上升沿 → `fMasterPos := fPosInit`、`fVel := 0`（`R_TRIG` 无条件刷新）。
- **边界安全条件**：① `tSample <= T#0MS` → 故障 `02ED`、`bValid := FALSE`；② `fVelSet` / 限制非有限 → 故障 `02ED`（复用）/ 保持末次有效速度；③ `|fMasterPos| > 1.0E15`（超过 LREAL 有效整数精度）→ 故障 `02EE`、**冻结相位**并提示调用方复位（浮点累计精度耗尽即相位失真，凸轮会错位）；④ 斜坡中 `bLimited := TRUE` + 信息 `01D7`；⑤ 复位执行 → 信息 `01D8`，且**复位与失能同拍时复位优先**（先复位后判状态）；⑥ 失能 → `eIdle`，速度按减速限值降到 0（不得阶跃）。
- **码位**：信息 `01D7`（加速度限幅生效，仍在斜坡）/ `01D8`（相位复位已执行）｜ 故障 `02ED`（采样周期或速度参数非法）/ `02EE`（相位累计超 LREAL 有效精度，已冻结）/ `02EF`（状态机兜底）

#### #14 `FB_DL_MotionCmdQueue` —— 运动指令排队器
- **分类**：`DL_Motion / CommandMgmt` ｜ **复杂度** **H**
- **VAR_INPUT**：`bEnq : BOOL`（入队请求，上升沿生效）；`fTargetPos : REAL`（[mm]）；`fVelocity : REAL`（[mm/s]）；`bAxisDone : BOOL`（轴 Done 输入，**由调用方注入，本件不消费轴状态**）；`bAxisError : BOOL`（轴故障输入）；`bOverwriteOldest : BOOL := TRUE`（满队策略：TRUE 丢最旧 / FALSE 拒绝新入队）；`bClear : BOOL`（清队）
- **VAR_OUTPUT**：`bExec : BOOL`（单拍发令）；`fExecPos : REAL`（[mm]）；`fExecVel : REAL`（[mm/s]）；`uCount : UINT`（[条] 当前排队数，0~8）；`bFull : BOOL`；`uDropped : UDINT`（[条] 累计丢弃数）；`eErr` / `bError` / `bValid`
- **VAR CONSTANT**：`DL_MQ_DEPTH : UINT := 8`（队列深度，固定不参数化——动态内存违反零厂商依赖）
- **状态机**：`E_DL_CmdQueueState`（`eIdle` / `eSending` / `eWaitDone` / `eFault`），`CASE` + `ELSE` 兜底。
- **功能规格**（`MC_BUFFERMODE = Buffered` 公开语义：新指令等前一条 `Done` 后才影响轴）：`eIdle` 且有排队 → 取队首、`bExec := TRUE`（**单拍**）→ `eWaitDone`；`bAxisDone` 或 `bAxisError` 上升沿 → 出队 → 回 `eIdle`。环形缓冲（头尾双指针 + 计数），指针一致性自愈（`uCount` 与指针推算不符即重建，写进头注释）。
- **边界安全条件**：① `fTargetPos`/`fVelocity` 非有限 → **拒绝入队**（不入队、不占槽）+ 故障 `02F0`；② 满队且 `bOverwriteOldest` → 丢最旧 + `uDropped + 1` + 信息 `01D9`；满队且不覆盖 → 拒绝新入队 + 信息 `01D9`（复用，R90 注明「两种策略共用一条信息码，靠 `uDropped` 是否自增区分」——**头注释必须写清**）；③ 连续同目标+同速度指令 → 合并去重 + 信息 `01DA`；④ `bAxisError` → 清队、回 `eIdle` + 故障 `02F1`（故障后**不得自动续发**，需先清故障再 `bClear`）；⑤ 数组索引全部前置界检（`< DL_MQ_DEPTH`）；⑥ `R_TRIG` ×3（入队/Done/Error）无条件刷新；⑦ `bExec` 单拍标志：**置位后必须在本拍或下一拍显式清零**（R25 三律）。
- **码位**：信息 `01D9`（队列满，按策略丢弃/拒绝）/ `01DA`（同目标指令已合并去重）｜ 故障 `02F0`（指令参数非有限，拒绝入队）/ `02F1`（轴故障应答，已清队并挂起）/ `02F2`（状态机兜底）
- **来源**：T1-6 PLCopen `MC_BUFFERMODE` 公开条款（`RAW_NOTES_R22.md` §2 已核：Aborting / Buffered / BlendingLow / BlendingHigh / BlendingPrevious / BlendingNext 六种，Buffered = 「等前一条 Done」）。本件**只做 Buffered 一种语义**，Blending 系列**不立**（需轴侧速度融合，本库接口无指令速度反馈通道）。

#### #15 `FC_DL_CamTableValidate` —— 凸轮表合法性校验
- **分类**：`DL_Motion / CamData` ｜ FUNCTION → `BOOL`（TRUE = 表可用）｜ **复杂度** M
- **VAR_INPUT**：`afPhase : ARRAY[0..63] OF REAL`（[°] 主轴相位，须严格递增）；`afSlave : ARRAY[0..63] OF REAL`（[mm] 从轴位置）；`uSegCount : UINT := 8`（有效点数 2~64）；`bCyclic : BOOL := TRUE`（周期表须首尾相位闭合）；`fPhaseTol : REAL := 0.01`（[°] 闭合容差）；`fMaxSlope : REAL := 100.0`（[mm/°] 斜率上限）
- **VAR_OUTPUT**：`uFailMask : WORD`（**全部**失败项同时置位：1 = 相位非单调 / 2 = 从轴值非有限 / 4 = 首尾未闭合 / 8 = 斜率超限 / 16 = 点数非法）；`uFailIdx : UINT`（1 基首个失败段号，0 = 无）；`fMaxSlopeFound : REAL`（[mm/°] 实测最大斜率）；`eErr` / `bError` / `bValid`
- **功能规格**：单趟扫描（`nGuard` 计数器上限 `64`）同时评估四项，**不早退**（掩码要完整，现场才能一次改全）；斜率 `fMaxSlopeFound := MAX(|Δslave/Δphase|)`，`Δphase = 0` 时按「重复点」计入非单调（**前置除零闸，先判 `Δphase <= 0` 再算商**）。
- **边界安全条件**：① `uSegCount < 2` 或 `> 64` → 掩码置 16 + 故障 `02F3`（复用，R90）/ `bValid := FALSE`；② 相位非单调 → 故障 `02F3`；③ 从轴值非有限（NaN 用 `(x−x)<>(x−x)`）→ 故障 `02F4`；④ 周期表首尾未闭合（`|afPhase[uSegCount−1] − afPhase[0] − 360.0| > fPhaseTol`）→ 故障 `02F5`；⑤ 斜率超限 → 掩码置 8 但**仍返回 TRUE**（表可用，仅提示；`bValid := TRUE`）+ 信息 `01DC`；⑥ 非周期表（`bCyclic = FALSE`）跳过闭合校验 + 信息 `01DB`；⑦ 纯函数无状态机（`状态机 : N/A`）。
- **码位**：信息 `01DB`（非周期表，跳过闭合校验）/ `01DC`（斜率超限，表仍可用）｜ 故障 `02F3`（相位非单调或点数非法）/ `02F4`（从轴值非有限）/ `02F5`（周期表首尾相位未闭合）

#### #16 `FB_DL_AxisInPosMonitor` —— 到位稳定判定
- **分类**：`DL_Motion / AxisMonitor` ｜ **复杂度** M
- **VAR_INPUT**：`bEnable : BOOL`；`fActPos : REAL`（[mm]）；`fTargetPos : REAL`（[mm]）；`fActVel : REAL`（[mm/s]）；`fPosTol : REAL := 0.05`（[mm] 位置窗）；`fVelTol : REAL := 1.0`（[mm/s] 速度阈）；`tSettle : TIME := T#100MS`（稳定时间）；`uChatterLimit : UINT := 5`（[次] 抖振计数上限）；`tChatterWin : TIME := T#2S`（[s] 抖振观察窗）
- **VAR_OUTPUT**：`bInPos : BOOL`（位置入窗 + 速度达标）；`bSettled : BOOL`（入窗并稳定 `tSettle`，**取放联锁用这个**）；`uChatterCount : UINT`（[次] 窗内出窗次数）；`bChatterAlarm : BOOL`；`eErr` / `bError` / `bValid`
- **状态机**：`E_DL_InPosState`（`eIdle` / `eMoving` / `eSettling` / `eInPos` / `eChatter` / `eFault`），`CASE` + `ELSE` 兜底。
- **功能规格**：`bInPos := (|fActPos − fTargetPos| <= fPosTol) AND (|fActVel| <= fVelTol)`（同拍组合，不做先后）；`eSettling` 内 `bInPos` 保持 `tSettle` 连续为 TRUE → `bSettled := TRUE`；观察窗 `tChatterWin` 内出窗计数 `>= uChatterLimit` → `bChatterAlarm`。
- **边界安全条件**：① 参数非法（`fPosTol <= 0`、`fVelTol <= 0`、`tSettle = 0`、`tChatterWin = 0`）→ 故障 `02F6`、`bValid := FALSE`；② 位置/速度非有限 → 故障 `02F7`、**保持上次判定**（坏值不得伪造「到位」，取放会夹空）；③ `bSettled` 出窗后**立即清零**（不得锁存到下一件料，R34 家族），且 `uChatterCount` 按窗清；④ 失能 → 全输出清零（逐项赋，R72）；⑤ `TON` ×2（settle / chatter 窗）无条件刷新；⑥ 与驱动器内置跟随误差监视**职责划界**（R8 已否「跟随误差监视」立项，本件只判「到位稳定」，头注释必须写这段边界）。
- **码位**：信息 `01DD`（入窗但稳定时间未到，不计到位）/ `01DE`（抖振计数已清零，稳定保持）｜ 故障 `02F6`（容差/时间参数非法）/ `02F7`（位置或速度非有限，保持上次判定）/ `02F8`（状态机兜底）

---

## 4 派单规格（每批 5 件 · 含样板原文，编码专家照抄）

### 4.0 全批通用样板（**原文照抄，不得改写**）

#### 4.0.1 头注释错误码段样板（每件必抄，替换数字与文案）

```iecst
    错误码    : 16#0001_045C 字段宽度越界已钳位到 1~20——信息级，正常防御
                16#0001_045D 预留禁用（信息级，不得挪用）
                16#0001_03A8 可用宽度不足以容纳完整数值，拒绝编码（不输出半截数字）——故障级，返回 FALSE
                16#0001_03A9 预留禁用（故障级，不得挪用）
                16#0001_03AA 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_045C 用 / 16#0001_045D 预留 ｜ 16#0001_03A8 用 / 16#0001_03A9 预留 / 16#0001_03AA 预留
    状态机    : N/A —— 纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 纯组合函数，无定时器、无内部驻留状态，调用即出结果
```

> 有状态机的件，`状态机` 段改为：`E_DL_XxxState（eA / eB / eC），CASE 含 ELSE 兜底，ELSE 分支置故障级 16#...._.. 并回 eIdle；失能无条件回 eIdle`。

#### 4.0.2 输出声明样板（**漏声明 `VAR_OUTPUT` 是本库历史第一高发缺陷**）

```iecst
VAR_OUTPUT
    eErr     : UDINT;                          // 错误码，0 表示无错 / error code, 0 means no error
    bError   : BOOL;                           // 故障级标志，仅故障级错误置位 / fault-class flag, set only on fault-level codes
    bValid   : BOOL;                           // 返回值/输出可用标志 / return value or outputs valid flag
END_VAR
```

#### 4.0.3 变量声明行注释样板（**中英双语、同行、带单位；禁「同上式」、禁「/」分隔中英**，R68/R92）

```iecst
    uWidth      : UINT := 8;                   // 字段宽度 [字符]，范围 1~20 / field width [char], range 1~20
    bZeroPad    : BOOL := TRUE;                // 零填充开关 / zero padding enable
    tGateTime   : TIME := T#100MS;             // 门时间 [ms]，范围 1~10000 / gate time [ms], range 1~10000
    fFreq       : REAL;                        // 测量频率 [Hz]，分辨率 1/tGateTime / measured frequency [Hz], resolution 1/gate time
```

#### 4.0.4 七条红线（**写进每件自检行，逐条自我声明通过**）

1. **零 GVL / 零 `VAR_EXTERNAL` / 零 `%I`·`%Q`·`%M` 绝对地址**——外部量一律 `VAR_INPUT` / `VAR_IN_OUT` 注入。
2. **纯 IEC 61131-3 跨平台**——只用 `Standard.library`（含 `TON` / `R_TRIG` / `MIN` / `MAX` / `ABS` / `LIMIT` / `TRUNC` / `LEN` / `LEFT` / `RIGHT` / `CONCAT` / `MID`）；子库依赖按 §3 各批约束。
3. **防御性编程**——浮点判等一律 `ABS(a−b) < 1.0E-6`（或件内声明的 EPS 常量）；除法前置防零；数组索引前置界检；`WHILE` 一律带 `nGuard` 计数器 + 超限置故障。
4. **变量声明同行中英双语注释 + 物理单位**（见 4.0.3）。
5. **`ENUM` + `CASE` 且必须含 `ELSE` 安全兜底**（ELSE 置兜底故障码并回安全态）。
6. **`TON` / `TOF` / `TP` / `R_TRIG` / `F_TRIG` 实例在主体最前部无条件刷新**（不得嵌在 `IF`/`CASE` 内，R40 家族）。
7. **无魔法数**——阈值/限幅/超时一律 `VAR CONSTANT` 或输入引脚，且常量名带语义与单位。

#### 4.0.5 历史教训重点防清单（**逐件过一遍，命中即返工**）

| # | 教训 | 本批高危件 |
|---|---|---|
| L1 | 漏声明 `VAR_OUTPUT`（`eErr`/`bError`/`bValid` 三缺一） | 全 20 件 |
| L2 | 注释嵌套 `(* ... (* ... *) ... *)` —— IEC 注释不可嵌套 | 全 20 件 |
| L3 | 枚举成员单冒号 `eA : 0` 写错 / 枚举成员用 `;` 分隔 | #5/#6/#7/#8/#9/#10/#11/#12~#14/#16~#20 |
| L4 | 隐性回夹（先写 `STRING` 再算长度，长度取到旧值） | #1/#2/#3（R37 四步样板：`LEN` 一次锁存 → 比较 → 置标志 → 分路写） |
| L5 | 锁存副本与实时镜像量同名混用 | #19/#20（相内锁存 vs 实时反馈）、#14（`uCount` 与指针推算） |
| L6 | 单拍标志只置不清（`bExec` / `bSeqDone` / `bDone`） | #12/#14/#19/#20（R25 三律） |
| L7 | `CASE` 前置无条件状态改写吞掉复位沿 | 全有状态机件（R45：复位判据段不得被前置无条件赋值覆盖） |
| L8 | 分段监控定时器跨段复用同一 `TON` 实例 | #19（三相）、#20（阀位/转移/排空三段）、#12（上电/断电两序）—— R40：**每段一只实例，段转出时断输入一拍** |
| L9 | 早退分支漏统一后处理（如反射/符号/清零） | #2（`nErrPos` 与饱和出口）、#3（非有限早退）、#15（掩码不全）—— R94 |
| L10 | 饱和保存与故障上报二者只做其一 | #2、#3、#9、#18 —— 饱和可观测（`bSaturated`/信息码）+ `bValid` 语义分离须写清 |
| L11 | 失能/故障分支只清主输出，漏清状态与派生出口 | 全有状态机件（R72 双路径显式清零） |
| L12 | 以「保持上次值」替代「安全侧」——保持值未夹进有效域 | #8（真空不足按不满足）、#11（初始 0 m 不得当可信）、#13（复位相位夹进域）—— R43 |

#### 4.0.6 验收向量强制集（**每件至少四类，缺一类不放行**）

1. **域外早退**：参数非法 / NaN / ±Inf / 空串 / 宽度 0 各一例。
2. **上限截断或饱和**：字段装不下 / 数值超域 / 计数超限 / 队列满各一例。
3. **跨段跨相时序**：分段 `TON` 转出拍、排队与 Done 同拍、抱闸与使能同拍各一例（R40/R41/R42）。
4. **恢复/复位首拍**：`bClear` / `bAbort` / `bPhaseReset` / 失能恢复首拍各一例（R36/R41/R43）。

> 向量随 `.st` 一并提交到 `_Staging_Raw/2026-11-16/`（建议 `VERIFY_R22.md`），逐条给「输入 → 期望输出 → 实际输出」三列，**纯函数件必须给 round-trip 向量**（#1↔#2、#15 的正/负表各一）。

### 4.1 批 1 派单（#1-#5 · `DL_MathData` 3 + `DL_Base` 2）

**批目标**：把 Level 0 数据编码（定宽数值字段三件套）与两条族内缺失轴（位串搜索、门时测频）一次补齐；本批 5 件全部零外部依赖（仅 `Standard.library`）。
**码位块**：`0001` 段 信息 `045C`~`0465`（10 槽）/ 故障 `03A8`~`03B6`（15 槽），**逐件见 §2 表**。
**派单要点（逐件不可省）**：
1. `#1` 整数分解**必须走负域**，`DINT` 最小值是唯一能踩的坑；宽度不足**拒绝编码**而非截断。
2. `#2` `LEN` 一次锁存（L4）；`nErrPos` 在**任何**失败出口都要写（R21 `StringToDint` 缺陷复盘点）。
3. `#3` 禁 `LREAL_TO_STRING`；NaN 用 `(x−x)<>(x−x)`；负值在绝对值域取整后加符号。
4. `#4` 宽 64 用常量掩码，**全程无 `SHL(x,64)`**；`WHILE` 带 `nGuard`。
5. `#5` `R_TRIG` + `TON` 首部无条件刷新；门切换拍不确定度 `±1 计数`写进「遗留假设段」。
**批内一致性检查**：`#1`/`#2` 构成逆运算对，`#3` 的填充/对齐规则必须与 `#1` 同口径（右对齐、零/空格填充），否则报文拼不起来——**派单要求两件共享同一段填充规则注释原文**。

**批 1 注释样板（`#1` 引脚段原文，其余件照此格式替换）**：

```iecst
VAR_INPUT
    nValue      : DINT;                        // 待编码整数，全 DINT 域 / integer to encode, full DINT range
    uWidth      : UINT := 8;                   // 字段宽度 [字符]，范围 1~20 / field width [char], range 1~20
    bZeroPad    : BOOL := TRUE;                // TRUE 零填充 / FALSE 空格填充 / TRUE zero padding, FALSE space padding
    bForceSign  : BOOL := FALSE;               // 正数是否强制 '+' 号 / force '+' sign on positive values
END_VAR
VAR_OUTPUT
    sField      : STRING(20);                  // 编码结果，右对齐 [字符] / encoded field, right aligned [char]
    uFieldLen   : UINT;                        // 实际写入字符数 [字符] / actual written length [char]
    eErr        : UDINT;                       // 错误码，0 表示无错 / error code, 0 means no error
    bError      : BOOL;                        // 故障级标志 / fault-class flag
    bValid      : BOOL;                        // 结果可用标志 / result valid flag
END_VAR
```

**批 1 码值样板（`#4` 头注释错误码段原文）**：

```iecst
    错误码    : 16#0001_0462 屏蔽后全零，无置位位（bFound = FALSE）——信息级，正常结论非错误
                16#0001_0463 有效位宽不在 8/16/32/64，已钳位到最近合法值——信息级，正常防御
                16#0001_03B1 有效位宽为 0，无法仲裁——故障级，bFound = FALSE 且 bValid = FALSE
                16#0001_03B2 预留禁用（故障级，不得挪用）
                16#0001_03B3 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_0462 用 / 16#0001_0463 用 ｜ 16#0001_03B1 用 / 16#0001_03B2 预留 / 16#0001_03B3 预留
```

### 4.2 批 2 派单（#6 #7 #17 #8 #9 · `DL_Algo` 2 + `DL_Process` 1 + `DL_Device` 2）

**批目标**：三条「保护律」（交叉限幅 / 氧量修正 / 防喘振）+ 两条「互锁与台账」（真空闸阀 / 安全阀），全部围绕「限值、先行、回差、台账」四个语义。
**码位块**：`0002` CC `2B`/`2C`（各 5 槽）｜ `0005` 信息 `01DA`/`01DB` + 故障 `030B`-`030D`｜ `0003` 信息 `0172`-`0175` + 故障 `033C`-`0341`。
**派单要点**：
1. `#6`/`#7` **禁止引用** `DL_Base`/`DL_MathData`；迟滞与限幅内联等价实现 + 头注释「依赖收窄」段声明。
2. `#17` 允许组合调用 `FB_DL_RateLimiter`，**必须按 R36 手算退出跟踪首拍**（首次扫描/失能恢复时 `fStep` 取 0，不得阶跃）。
3. `#17` 参数非法时阀**全开**、输入非有限时**保持末值**——两条安全方向相反，头注释必须并列写清。
4. `#8` 门位反馈矛盾按「门未关」处理；真空非法按「真空不足」处理——**一律取保守侧**。
5. `#9` 起跳判据必须用回座比做迟滞；单次时长 `< tMinLift` 不计入台账。
**批内一致性检查**：三件保护律的「失能方向」必须逐件写明（`#6` 双给 0 / `#7` 修正 0 / `#17` 阀全开），派单要求同段连续声明，便于终审横向比对。

**批 2 注释样板（`#17` 安全方向段原文）**：

```iecst
VAR_INPUT
    fSuctionPress  : REAL;                     // 吸入压力 [kPa abs] / suction pressure [kPa abs]
    fDischargePress: REAL;                     // 排出压力 [kPa abs] / discharge pressure [kPa abs]
    fFlow          : REAL;                     // 实测流量 [Nm3/h] / measured flow [Nm3/h]
    fFlowMinLine   : REAL := 500.0;            // 最小流量线 [Nm3/h] / minimum flow line [Nm3/h]
    fSurgeMargin   : REAL := 0.10;             // 危险线裕度 [倍]，须 > 0 / surge margin [ratio], must be > 0
    fOpenRamp      : REAL := 20.0;             // 放空阀快开斜率 [%/s] / blowoff fast-open ramp [%/s]
    fCloseRamp     : REAL := 1.0;              // 放空阀慢关斜率 [%/s] / blowoff slow-close ramp [%/s]
    tConfirm       : TIME := T#200MS;          // 危险线确认时间 [ms] / danger line confirm time [ms]
    bEnable        : BOOL;                     // 使能 / enable
END_VAR
```

**批 2 码值样板（`#9` 头注释错误码段原文）**：

```iecst
    错误码    : 16#0003_0174 起跳事件已记录（动作次数 +1，累计时长开始累加）——信息级，正常记录
                16#0003_0175 单次起跳时长低于 tMinLift，按工艺波动滤除不计入台账——信息级，正常防御
                16#0003_033F 整定压力或回座比非法（fSetPressure <= 0 或 fBlowdown 不在 0~1）——故障级，bValid = FALSE
                16#0003_0340 压力输入非有限，保持台账与判定不变——故障级，坏值不得伪造动作
                16#0003_0341 状态机落 ELSE 兜底（非法状态）——故障级，回 eIdle 并保持台账
    码位总账  : 16#0003_0174 用 / 16#0003_0175 用 ｜ 16#0003_033F 用 / 16#0003_0340 用 / 16#0003_0341 用
```

### 4.3 批 3 派单（#10 #11 #18 #19 #20 · `DL_Device` 2 + `DL_Process` 3）

**批目标**：两条「诊断判据」+ 三条「过程单元顺控」；共同主题是「工况未建立时不得判故障」与「相/步骤转出必须断输入」。
**码位块**：`0003` 信息 `0176`-`0179` + 故障 `0342`-`0347`｜ `0005` 信息 `01DC`-`01E1` + 故障 `030E`-`0316`。
**派单要点**：
1. `#10` 冷态（`fTin < fTinMin`）**冻结全部故障判定**——这是本件唯一真正容易写错的语义。
2. `#11` 初始无历史可信值时 `fLevelOut := 0` **必须配 `bValid := FALSE`**，不得让 0 m 进联锁。
3. `#18` 抗饱和：钳位后**不再累加**；`bDpHigh` 期间再沸强制落 `fOutMin`。
4. `#19` 三个相**各一只 `TON`**，相转出断输入一拍；`bAbort` 任意拍生效且不排队。
5. `#20` **先停泵后关阀**；泵必须在双阀到位反馈后启；累计量由调用方注入（不内联积分）。
**批内一致性检查**：三件顺控的「急停/中止」路径必须**先清执行输出再回状态**，且中止后不得自动续跑；派单要求三件共用同一段「中止语义注释原文」。

**批 3 注释样板（`#19` 阀输出与状态段原文）**：

```iecst
VAR_OUTPUT
    bVacValveCmd  : BOOL;                      // 抽真空阀指令 / vacuum valve command
    bN2ValveCmd   : BOOL;                      // 氮气阀指令 / nitrogen valve command
    bVentValveCmd : BOOL;                      // 放空阀指令 / vent valve command
    uCycleDone    : UINT;                      // 已完成置换循环数 [次] / completed purge cycles [count]
    bDone         : BOOL;                      // 置换合格放行 / purge qualified, production released
    bFailed       : BOOL;                      // 置换失败锁定 / purge failed, latched
    eErr          : UDINT;                     // 错误码，0 表示无错 / error code, 0 means no error
    bError        : BOOL;                      // 故障级标志 / fault-class flag
    bValid        : BOOL;                      // 输出可用标志 / outputs valid flag
END_VAR
```

**批 3 码值样板（`#20` 头注释错误码段原文）**：

```iecst
    错误码    : 16#0005_01E0 累计转移量由调用方积分器注入，本件不重复积分——信息级，口径声明
                16#0005_01E1 排空验证窗内流量持续低于门限，判排空完成——信息级，正常结论
                16#0005_0314 阀位反馈超时未到位，拒绝启泵——故障级，回 eIdle 并先清输出
                16#0005_0315 转移总时长超时或体积/超时参数非法——故障级，停泵关阀
                16#0005_0316 状态机落 ELSE 兜底（非法状态）——故障级，回 eIdle 并先清输出
    码位总账  : 16#0005_01E0 用 / 16#0005_01E1 用 ｜ 16#0005_0314 用 / 16#0005_0315 用 / 16#0005_0316 用
```

### 4.4 批 4 派单（#12-#16 · `DL_Motion` 5）

**批目标**：轴侧「生命周期安全层」从零建立——抱闸时序、主值源、指令排队、表校验、到位判定。
**码位块**：`0004` 信息 `01D5`~`01DE`（10 槽）/ 故障 `02EA`~`02F8`（15 槽）。
**派单要点**：
1. **本批 5 件一律不得引用其他 `DL_` 子库**（含 `DL_Base` 的 `SignalDebounce`）；只用 `Standard.library`。
2. `#12` 上电序「先释放抱闸后使能」、断电序「先静止后抱闸、先抱闸后断使能」——**两条序写反即掉轴**，头注释必须把两条序画成文字时序。
3. `#12` 断使能条件不满足时**拒绝断使能**并报警（`02EB`），这是「宁可报警不可掉轴」的取舍，必须写进头注释的「设计取舍」段。
4. `#13` `bHold` 走减速斜坡而非瞬时归零；相位复位沿优先于失能判定（同拍复位生效）。
5. `#14` 只做 `Buffered` 一种语义，Blending 系列**不立**（接口无速度融合通道），偏离须写入头注释「职责边界」段。
6. `#15` 四判据**全部写进掩码不早退**；`Δphase <= 0` 前置闸先于除法。
7. `#16` `bSettled` 出窗即清零（不锁存跨件）；与驱动器内置跟随误差监视的**职责划界段**必写。
**批内一致性检查**：5 件对「轴故障」的处置必须一致——**收到 `bAxisError` 只挂起不自动续发**；派单要求 `#14` 与 `#16` 同口径声明。

**批 4 注释样板（`#12` 状态与时序段原文）**：

```iecst
VAR_INPUT
    bEnableReq        : BOOL;                  // 使能请求（上电序触发，落沿启动断电序）/ enable request
    fActVel           : REAL;                  // 轴实际速度 [mm/s] / axis actual velocity [mm/s]
    fStandstillVel    : REAL := 1.0;           // 静止判定速度阈 [mm/s] / standstill velocity threshold [mm/s]
    bBrakeReleaseFb   : BOOL;                  // 抱闸释放到位反馈 / brake released feedback
    bBrakeFbAvailable : BOOL := TRUE;          // FALSE 时按纯时间序列（无反馈现场）/ FALSE = time-based sequence only
    tBrakeRelease     : TIME := T#200MS;       // 抱闸释放等待 [ms] / brake release wait [ms]
    tBrakeHold        : TIME := T#300MS;       // 抱闸闭合保持等待 [ms] / brake hold wait [ms]
    tStandstill       : TIME := T#100MS;       // 静止确认时间 [ms] / standstill confirm time [ms]
    tFbTimeout        : TIME := T#2S;          // 序列超时 [ms] / sequence timeout [ms]
END_VAR
```

**批 4 码值样板（`#14` 头注释错误码段原文）**：

```iecst
    错误码    : 16#0004_01D9 队列满：bOverwriteOldest=TRUE 丢最旧 / FALSE 拒绝新入队（共用本码，靠 uDropped 是否自增区分）——信息级
                16#0004_01DA 连续同目标同速度指令已合并去重——信息级，正常防御
                16#0004_02F0 指令参数非有限（NaN/Inf），拒绝入队不占槽——故障级，bValid = FALSE
                16#0004_02F1 轴故障应答（bAxisError），已清队并挂起，禁止自动续发——故障级
                16#0004_02F2 状态机落 ELSE 兜底（非法状态）——故障级，回 eIdle 并清队首标志
    码位总账  : 16#0004_01D9 用 / 16#0004_01DA 用 ｜ 16#0004_02F0 用 / 16#0004_02F1 用 / 16#0004_02F2 用
```

---

## 5 收口与回写要求（阶段三~六执行，本轮不动）

| 动作 | 责任 | 硬要求 |
|---|---|---|
| `.st` 落盘 | 编码专家 | 文件名 = POU 名；20 件分 4 批提交；每件附四类验收向量 |
| 全库唯一性断言 | 收口脚本 | 100 个新码位 + 364 件存量做全字符串集合求交，**`CLASH` 必须为空**；同时复测 §2「轮后游标」 |
| `INDEX_REGISTRY.json` | 收口脚本 | `total_components` 364 → **384**；`version` 2.10.0 → **2.11.0**；`counts` 变为 Base **73** / MathData **148** / Algo **38** / Device **61** / Motion **30** / Process **34** |
| JSONL | 收口脚本 | +20 条 → **384** 条，sha256 逐件 MATCH |
| 子库 `VERSION.md` / `MANUAL_DL_*.md` | 文档线 | 六本全动；手册接口表按「每轮 ≤10 件」纪律分批补录（R88） |
| 顶层五件 | 文档线 | `CHANGELOG.md` / `README.md` / `LIBRARY_MANUAL.md` / `ROADMAP.md`（池子扩容 ≥30 条 + 8 条已注册项勾除）/ `SOURCE_HUNTING_MATRIX.md`（按 `RAW_NOTES_R22.md` §4 回写） |
| `AGENT_EVOLUTION_LOG.md` | 总监 | 新规则入册（未固化 18 条 + 本轮预计 6~10 条 → **R22 末触发第二批固化**，阈值 20） |

---

## 6 风险与编译债（本轮如实挂账）

| 级别 | 项 | 说明 |
|---|---|---|
| **P0** | **编译验证债连续 17 轮悬置** | 本轮新增 3 条：`STRING(20)/(24)` 在 TwinCAT 接口实现一致性、`LWORD` 型 `VAR_INPUT` 在 InoProShop 的可用性、`TRUNC` 对 LREAL 的向零口径。**R22 起建议把「最小空工程编译 1 个子库」列为交付资格项**（R21 已同类建议，仍未执行） |
| P1 | `#3` 浮点定点文本的精度承诺 | 整数部分 > 15 位十进制时 LREAL 无精确表示，头注释必须声明「输入本身已失真」 |
| P1 | `#5` 测频不确定度 | 门切换拍 `±1 计数`，不得声称精确 |
| P1 | `#10` 疏水阀判据阈值开工况差异 | 公开资料温差门限 10 K / 20 K 两说并存，故做成引脚（`fDeltaNormal` 缺省 10 K），**不得写死** |
| P2 | `#14` 队列深度固定 8 | 与西门子轴组 8 条一致，但不做动态扩深（零动态内存红线） |
| P2 | `#13` 相位累计精度 | 1.0E15 mm 门限为经验值，属件内常量，须注释说明推导 |

---

*ROUND_PLAN_R22 ｜ 2026-11-16 23:06 ｜ 20 件 / 4 批 / 100 槽零冲突 / 2 次检索 ｜ 本文件不含任何组件代码，仅派单规格*
