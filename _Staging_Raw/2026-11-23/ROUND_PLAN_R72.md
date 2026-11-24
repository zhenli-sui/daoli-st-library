# ROUND_PLAN_R72 —— 第 R72 轮构建计划（阶段一盘点 + 阶段二按源矩阵选题）

> 轮次：R72 ｜ 日期：2026-11-23 ｜ 轮型：零检索轮（WebSearch 0 次，取材全部复用既有 SOURCE_HUNTING_MATRIX 台账与内部族）
> 配额：**新件 12 件**（对 20 目标如实少报，不注水）+ **1 个点修**（批 0，不占 12 配额）。按依赖切 **4 批 × 3 件**。
> 本轮只做规划，不写任何 `.st` 代码；不修改 `.st` / `INDEX_REGISTRY.json` / JSONL / README / CHANGELOG / VERSION / ROADMAP / MATRIX。

---

## §1 库态盘点（数据源：`INDEX_REGISTRY.json` v2.63.0 实测提取，非记忆）

| 指标 | 实测值 | 说明 |
|---|---|---|
| 总库规模 | **1,206 / 10,000（12.06%）** | registry `total_components` 实测，counts：Base 152 / MathData 288 / Algo 135 / Device 220 / Motion 125 / Process 286 |
| 今日产出（11-23） | **0 / 200** | R71 收口于 11-22，今日尚未开张；本轮 +12 预计 12/200 |
| 500 冲刺里程碑 | **已超额**（1,206 ≫ 500，达成率 241.2%） | 万级冲刺 Phase 2 进行中；本轮后预计 1,218 |
| JSONL 语料 | 1,239 条（R71 战报实测） | 本轮 12 新 + 1 点修重注入，收口后 +13，不注水 |
| 源矩阵覆盖率 | 可判定组 27：**✔ 收口 9（33%）、◐ 深化 7、☐ 待挖 11** | R60 口径维持（R71 战报同口径）；本轮零新开组、零整组收口，逐组补口 |
| ROADMAP 待办 | **55 条**（>30 阈值） | **本轮不补写 ROADMAP**（纪律：只在 <30 条时补写；本句仅记于本计划） |
| 编译验证债 | R71 已落地 L2 真编译闸（RuSTy 1.0.8），基线 80% / 新件 6/8 | R195 硬闸口径：本轮 12 件**无编解码/数学/转换类高复杂度件**（11×C1~C2 + 1×C3 顺控件），不触闸；收口时逐件过 L2 闸（R71 遗留 P0：新件逐件 PASS 或缺口留档） |
| R71 挂账承接 | `FC_DL_AirSpecificVolume` E032（补 `bValid => 回执`） | 本轮批 0 点修，不占 12 配额 |

---

## §2 选题依据（零检索轮 · 取材清单）

本轮 **WebSearch 0 次**。取材全部来自 `SOURCE_HUNTING_MATRIX.md` §5 台账既有组与 ROADMAP 遗留口径，逐源标注状态与行号：

| 来源标签 | 矩阵位置 | 状态 | 本轮取材方式 |
|---|---|---|---|
| T0-2 定时器/日历变体线 | 矩阵行 146 | ✔（收口警示内建链未实测） | `FC_DL_HmsToTodChk`（TOD 组态口）+ `FC_DL_DaysInMonthChk`（日历原子，R14 零检索变体三判据准入，**不用任何日历内建链**，纯整数算术 + 复用 `FC_DL_LeapYearChk`） |
| T0-4 数学函数域闸样板 | 矩阵行 148 | ✔ | `FC_DL_IntModChk`（IEC MOD 语义防御包装）+ `FC_DL_FiniteClassify`（R79 非有限判据原子化） |
| T0-6 字符串族 | 矩阵行 150 | ✔ | `FC_DL_CharCodeConvert`（字符↔码双向）+ `FC_DL_WordToBinString`（二进制文本化，与 `FC_DL_DwordToHexString` 同族反向补口） |
| T2-1 LGF · Math（统计线） | 矩阵行 157 | ◐ R18 深化 | `FC_DL_ArrayCumSumLreal`（数组前缀累计序列，邻件 `FC_DL_ArraySumLreal` 分工声明） |
| T1-1 OSCAT Basic | 矩阵行 170 | ◐ | `FB_DL_BlinkOutput`（OSCAT BLINK 行为定义，OSCAT 许可免费需致谢，EPL-2.0 类比 R25 先例；零代码行） |
| T2-6 Rockwell AOI | 矩阵行 166 | ◐ R18 深化 | `FB_DL_OilLevelWatch`（设备级粗粒度监视）+ `FB_DL_ToolChangerSeq`（伺服外围件方向，次源 t1-9 国产机床 FB 手册公开功能清单） |
| T2-2 LBP 基础工艺 | 矩阵行 163 | ◐ | `FB_DL_SipLineSterilSeq`（命令→监视→判定三段骨架；次源 T2-8 ISA-88 相语义公开条款） |
| s9-conv（自研输送线） | R7 先例 / R71 计划 §4 同口径 | 自研线 | `FB_DL_RejectBlowCtrl`（剔除气吹执行时序，输送线工程惯例 clean-room） |

**结构合规**：T0 快车道（`iec-std-wrapper` 标签）**6 件**（序号 1/2/4/5/6/7），全部内部委托库内属主件或 IEC 标准语义、严禁重实现数学内核、文件头溯源标注「IEC 61131-3 标准语义的道莅防御性实现」；T1/T2 组 **4 件**（序号 3/8/9/10/12 中 lgf-math、t1-1、t2-6×2、t2-2）；ROADMAP 遗留口径 **1 件**（序号 7，T0-2 日历变体线）；自研线 **1 件**（序号 11）。**分类分布**：MathData 5 / Base 2 / Device 1 / Motion 1 / Process 2 —— MathData 与 Base 为主，Device/Motion/Process 各 ≥1，Algo 0（R60 拒单重灾族，R267 避让纪律延续）。复杂度 2×C1 + 9×C2 + 1×C3。

---

## §3 P0 点修对账结论（挂账描述 vs 源码事实，R386 新规首用轮）

**对账对象**：`FC_DL_AirSpecificVolume`（DL_MathData，v1.0.0，2026-11-22 首版）——R71 战报 §七.1 挂账「E032：补 `bValid => _bAsvOk` 回执（R381 新规首用），并复核同族省略式调用清单」。

**源码事实实测**（两文件逐行核对）：

1. `C:\Library\DL_MathData\FC_DL_AirSpecificVolume.st` 段 5（第 162~166 行）对属主件的调用为：
   `fTempC :=`、`fPvSat => _fPws`、`bClamped => _bPwsClmp`、`eErr => _uPwsCode`、`bError => _bPwsErr` —— **确实省略了 `bValid` 出参回执**。
2. `C:\Library\DL_Algo\FC_DL_VaporPressureSat.st` 形参表共 **6 形参**：`fTempC`（入）+ `fPvSat` / `bClamped` / `eErr` / `bError` / `bValid`（出），其中 `bValid : BOOL`（第 39 行，// 输出可用标志 / Outputs usable flag）在段 1 预置 FALSE、段 5 成功出口置 TRUE —— 与挂账描述完全一致。

**对账结论**：挂账描述与源码事实**一致，无脱节**（对比 R70 量程零域挂账的脱节先例）。补 `bValid => 回执` 的修法成立。两点命名与行为澄清随修法一并落账：

- 局部变量命名：挂账用名 `_bAsvOk` 与既有局部 `_bPwsOk`（承载返回值）/`_bPwsErr`/`_bPwsClmp`/`_bPwsCode` 同前缀族冲突风险，按命名一致性裁定为 **`_bPwsVld`**（`_bPws*` 前缀族第 5 员，R28-4 命名纪律），战报原名差异在此留痕。
- 行为语义：属主件返回值已由 `_bPwsOk` 闸收口（段 5 IF `NOT _bPwsOk OR _bPwsErr` 早退），`bValid` 属主侧在全部非早退路径恒 TRUE，故本回执是**契约完整性修复（E032 编译合规）而非行为修复**——v1.0.1 不改变任何输出行为，收口时 JSONL 按「点修重注入」口径处理。

---

## §4 12 目标表（4 批 × 3）

### §4.1 主表

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | `FC_DL_IntModChk` | DL_MathData | FC_DL_ | DINT 整数取模防御包装：除零闸 + 负操作数语义声明 + DINT_MIN/−1 溢出面拦截 | iec-std-wrapper（T0-4） | 1 | 1 |
| 2 | `FC_DL_FiniteClassify` | DL_MathData | FC_DL_ | LREAL 非有限分类原子：eFinite / ePosInf / eNegInf / eNaN 四态（R79 判据原子化） | iec-std-wrapper（T0-4） | 1 | 1 |
| 3 | `FC_DL_ArrayCumSumLreal` | DL_MathData | FC_DL_ | LREAL 数组前缀累计序列输出 + 总和出口（统计线补件） | lgf-math（T2-1 LGF · Math，矩阵行 157） | 2 | 1 |
| 4 | `FC_DL_CharCodeConvert` | DL_MathData | FC_DL_ | 单字符 ↔ 字符码双向换算（枚举选向，码域/串长域闸） | iec-std-wrapper（T0-6） | 2 | 2 |
| 5 | `FC_DL_WordToBinString` | DL_MathData | FC_DL_ | WORD → 16 字符定长二进制文本（MSB-first 口径，零截断域） | iec-std-wrapper（T0-6，DwordToHexString 同族反向） | 2 | 2 |
| 6 | `FC_DL_HmsToTodChk` | DL_MathData | FC_DL_ | 时/分/秒三分量合成 TOD（HMI 时刻设定入口，组合域闸 + 钳位照算） | iec-std-wrapper（T0-2/T0-5 TIME/TOD 族） | 2 | 2 |
| 7 | `FC_DL_DaysInMonthChk` | DL_Base | FC_DL_ | 年月 → 当月天数（月域闸 + 复用 `FC_DL_LeapYearChk` 闰年属主） | roadmap-t02-calendar（T0-2 日历变体线遗留补口） | 2 | 3 |
| 8 | `FB_DL_BlinkOutput` | DL_Base | FB_DL_ | 方波闪烁输出：tOn/tOff 独立交替两相 TON，失能冻结输出与相位 | t1-1-oscat-basic（矩阵行 170，BLINK 行为定义） | 2 | 3 |
| 9 | `FB_DL_OilLevelWatch` | DL_Device | FB_DL_ | 润滑/液压油油位连续监视：双阈值迟滞 + 确认延时 + NE107 健康出口 | t2-6-rockwell-aoi（矩阵行 166） | 2 | 3 |
| 10 | `FB_DL_ToolChangerSeq` | DL_Motion | FB_DL_ | 换刀机构顺控：刀位校验 → 取刀 → 换刀 → 旧刀回库 → 到位确认 | t2-6-rockwell-aoi（伺服外围件方向；次源 t1-9） | 3 | 4 |
| 11 | `FB_DL_RejectBlowCtrl` | DL_Process | FB_DL_ | 输送线剔除气吹执行时序：NG 预告 → 距离/速度延时 → 定宽气吹 → 漏剔/误剔对账 | s9-conv（自研输送线，R7 先例） | 2 | 4 |
| 12 | `FB_DL_SipLineSterilSeq` | DL_Process | FB_DL_ | 管路 SIP 蒸汽灭菌顺控：排凝 → 升温 → 保温窗（跌破重启）→ 冷却 → 放行 | t2-2-lbp（三段分层骨架；次源 T2-8 相语义） | 2 | 4 |

### §4.2 撞名三查记录（对 `INDEX_REGISTRY.json` v2.63.0 全量 1,206 name 实时精确匹配 + 词根邻件扫描，R327/R214 口径）

判重方法：python 提取 registry 全部 1,206 个 `name` → 候选名做大小写敏感**精确匹配** → 再按词根同义邻件扫描。规划期共探测 5 轮、30+ 词根，**正选 12 件全部零精确命中**（上表已验）。以下列报**被拒/规避候选 14 条**留痕：

| # | 被拒候选 | 拒绝理由 |
|---|---|---|
| 1 | `FC_DL_AngleUnitConvert`（T0 候选） | **精确同名已注册**（deg↔rad 换算已在库） |
| 2 | `FC_DL_DintMsToTod`（T0 候选） | **精确同名已注册**（R17 落地）——故取其邻缺口 `HmsToTodChk`（三分量组态入口 vs 毫秒计数，语义不同层） |
| 3 | `FC_DL_QuantizeStep`（就近取整到步距候选） | **精确同名已注册**，步距量化域已有属主 |
| 4 | `FC_DL_GcdUdintCalc`（齿轮比约分候选） | **精确同名已注册** |
| 5 | `FB_DL_SoftStarterDrive`（软启动器候选） | **精确同名已注册**，电机启动族已收口 |
| 6 | `FB_DL_HealthAggregator`（NE107 多源聚合候选） | **精确同名已注册**（且 `FB_DL_HealthStatusArbiter` / `FB_DL_DeviceHealthArbiter` 同域三件）——矩阵 T2-8「NE107 仲裁件待挖」备注已滞后，改判已覆盖 |
| 7 | `FB_DL_CamDynTrim`（凸轮动态修调候选） | **精确同名已注册**（另有 CamPhaseTrim / CamOverrideTrim / CamTableLiveTrim / CamFollowerLagMonitor 四邻）——矩阵 T1-6「凸轮动态修调待挖」备注已滞后 |
| 8 | `FC_DL_StringPad` / `FC_DL_StringTrim`（定宽填充候选） | **精确同名已注册**，字符串整形域已有属主 |
| 9 | `FC_DL_ModLrealSafe`（整数 MOD 直接立项 LREAL 版） | 属主已注册（LREAL 域）；本件取**整数域 DINT**（`IntModChk`），DINT_MIN/−1 溢出面为 LREAL 版不存在的独立语义，非凑数变体，分工声明写死 |
| 10 | `FB_DL_UvDoseCtrl`（UV 剂量候选） | **精确同名已注册** |
| 11 | `FB_DL_BrakeResistorThermal`（制动电阻热模型候选） | **精确同名已注册** |
| 12 | `FB_DL_GripperStrokeWatch`（夹爪行程建档候选） | 近邻 `FB_DL_CylStrokeTimeBank`（行程时间建档）+ `FB_DL_GripperForceVerify`（夹持力验证）双属主在册，判据面已覆盖，改取 `FB_DL_OilLevelWatch` 补油位监视真空 |
| 13 | `FC_DL_RoundToMultipleChk` / `FC_DL_DhmsToTimeChk` | 前者与 `FC_DL_QuantizeStep` 同义；后者与 `FC_DL_HmsToTodChk` 构成同类双立（凑数），舍天粒度取 HMI 高频的 TOD 版 |
| 14 | `FB_DL_SorterDiverterCtrl`（多通道分选候选） | 与 R71 `FB_DL_LaneDivertCtrl`（道岔分流）语义邻接，分流命令-反馈域已有属主，不立 |

---

## §5 批 0 点修规格：`FC_DL_AirSpecificVolume` v1.0.0 → v1.0.1

- **修法**：段 5 属主件调用补第 6 形参回执 `bValid => _bPwsVld`，新增局部变量 `_bPwsVld : BOOL;` 声明行**同行双语注释**（中文 + 英文，与 `_bPwsErr` 等族内格式一致）；不改行为、不动既有码位、不动引脚契约。属主返回值 `_bPwsOk` 闸维持原语义（`bValid` 回执仅承接契约，**不并入**段 5 判据——若并入则属 E032 之外的行为变更，本轮不做，留 VERSION.md 说明）。
- **头注释披露**：修订记录登记 v1.0.1（R72 点修 · R386 对账 + R381 首用）；边界披露节补一行「段 5 属主件调用为全 6 形参完整回执，E032 合规」。
- **文档同步**：`DL_MathData\VERSION.md` 实测最新节号 +1 续写（R311 口径，任务书假设值仅交叉校验）；JSONL 按「点修重注入」口径处理；L2 闸复验（R71 遗留 P0：点修件必须 PASS 或缺口留档）。
- **同族省略式调用清单复核（编码专家必办）**：grep 全库 `\.st` 文件中 `FC_DL_VaporPressureSat(` 的全部调用点（已知至少 5 处：`FC_DL_HumidityRatioCalc` / `FC_DL_WetBulbTempCalc` / `FC_DL_RhFromDewPoint` / `FC_DL_MixAirStateCalc` / `FC_DL_DewpointReset` 各自头注释声明族内引用），逐点核对 6 形参是否完整回执；**同口径扩展复核**其余多出参 FC（含 `bError`/`bValid`/`nErrCode` 类出参）的省略式调用，命中清单挂账（只挂账不改码，R333 口径——本轮点修范围仅 AirSpecificVolume 一件）。复核输出（查了什么/命中几条）写进 R72 战报，禁止凭记忆判「零遗漏」（R327 口径）。

---

## §6 每件功能规格 + 边界安全条件（供编码专家直接照做）

### 批 1

#### 序号 1｜`FC_DL_IntModChk`（DL_MathData，纯函数）

- **输入输出语义**：输入 nDividend / nDivisor [DINT]（无单位整数域）；输出 nRem [DINT]（余数，符号随被除数，IEC MOD 主流口径）+ bValid + nInfoCode。头注释溯源「IEC 61131-3 标准语义的道莅防御性实现」。
- **判据链**：除零闸（nDivisor = 0 → 故障级早退，输出 0）→ **DINT_MIN / −1 溢出面闸**（被除数 = −2147483648 且除数 = −1 时商溢出 DINT，余数虽恒 0 但三平台 MOD 实现可能内溢，此组合显式拦截出信息级）→ 负操作数语义声明（结果符号与绝对值以头注释 + 注释双口径写死，禁依赖平台默认）→ 出口。
- **边界安全条件**：整数进位点（终审两式 #2）：「除子恰为 0」「被除数 = DINT_MIN 且除子 = −1」两点各推一条向量；与 `FC_DL_ModLrealSafe`（LREAL 域属主）分工声明互引——本件只做 DINT 整数域，不做浮点。
- **真实工况**：齿轮比约分、卷绕圈数余量、分度索引回绕前的余数预判。

#### 序号 2｜`FC_DL_FiniteClassify`（DL_MathData，纯函数）

- **输入输出语义**：输入 fVal [LREAL]（任意物理量纲，无量纲语义，注释声明）；输出 eClass [E_DL_FiniteKind 同文件枚举：eFinite / ePosInf / eNegInf / eNaN] + bFinite [标志]。
- **判据链**（R79 判据原子化，全库首个非有限分类属主）：NaN 用 `x <> x` 自反判 → Inf 用 `(x − x) <> 0` 差值自反判 + 符号二分 → 其余 eFinite。**禁近似阈值**（1.79E308 兜底可作旁证注释但不得作判据）；不做幅值上界筛查（上界筛查属调用方业务语义，本件只分 IEEE 语义四态）。
- **边界安全条件**：无除法/无循环，零除零面；与全库内联 R79 判据的关系 = 「原子提取」而非语义变更——头注释声明各件可组合调用本件但**不强制回改存量**（存量回改挂账不改码，R333）。
- **真实工况**：闸前置分类诊断文本（HMI 显示「断线/无穷/正常」）、诊断日志分桶。

#### 序号 3｜`FC_DL_ArrayCumSumLreal`（DL_MathData，纯函数）

- **输入输出语义**：输入 afIn : ARRAY[1..DL_CUM_NMAX] OF LREAL + nCount [UDINT]（有效样本数）；输出（VAR_IN_OUT）afOut : ARRAY[...] OF LREAL（前缀累计序列 afOut[i] = Σ afIn[1..i]）+ fTotal [LREAL]（= afOut[nCount]）+ bValid + nInfoCode [m³ / kWh / 件 等，量纲随输入，注释声明]。
- **判据链**：nCount 域闸（0 → 信息级空出口 fTotal=0；> 数组上界 → 钳位照算信息级）→ 逐元素非有限闸（**遇非有限样本整体拒绝**，保守口径：部分累计会污染下游余量判断，出故障级码）→ 循环累加（WHILE 带 `DL_GUARD_MAX` 防死锁计数器）→ 溢出面（累计 > 1E30 → 置 bTruncated 中断累加，声明口径）。
- **边界安全条件**：浮点禁 `=` 判等（红线 5）；nCount=0 与 nCount=上界两点各推一条向量；与 `FC_DL_ArraySumLreal` 分工互引——后者只出总和、可零拷贝，本件输出完整序列（须写入调用方数组），非变体。
- **真实工况**：能耗/产量累计曲线、按片批次余量推演、OEE 累计谱。

### 批 2

#### 序号 4｜`FC_DL_CharCodeConvert`（DL_MathData，纯函数）

- **输入输出语义**：输入 eMode [E_DL_CharCodeMode 同文件枚举：eCharToCode / eCodeToChar] + sChar [STRING(1)] 或 uCode [UINT（0~255）]；输出 sChar / uCode 双出（未选向的出口置确定值空串/0）+ bValid + nInfoCode。
- **判据链**：eCodeToChar 向码域闸（>255 → 故障级早退；**扩展 ASCII 128~255 三平台渲染差异在头注释披露**，只保证码值回执不保证显示）→ eCharToCode 向串长闸（空串/多字符 → 拒收信息级）→ 出口。
- **边界安全条件**：换算方向枚举漏项由 ELSE 兜底（若实现含 CASE）；0 与 255 两端点各推一条向量；与 `FC_DL_HexStringToBytes` / `FC_DL_DwordToHexString` 分工——那些是文本↔字节块，本件是单字符↔码值原子。
- **真实工况**：HMI 键盘映射、协议字符组装、标签打印机字符转义。

#### 序号 5｜`FC_DL_WordToBinString`（DL_MathData，纯函数）

- **输入输出语义**：输入 uWord [WORD]；输出 sBin [STRING 定长 16，'0101…' MSB-first] + bValid（本件无域外可能，bValid 恒 TRUE 仅保留契约一致性）。
- **判据链**：逐位提取（位 15 → 位 0 顺序拼接，`SHL` 掩码法全程无 64 位移位、移位量 ≤15）→ 定长出口（无截断可能，头注释声明与可截断族的口径差异）。
- **边界安全条件**：0 与 16#FFFF 两端点各推一条向量（全 0 / 全 1 串）；分工互引：`FC_DL_DwordToHexString`（十六进制文本）、`FC_DL_ReverseBitsWord`（位序重排非文本化）、`FC_DL_FirstSetBit`（位搜索）——本件只做二进制文本化。
- **真实工况**：调试面板位诊断显示、协议帧人读文本、培训/文档向量打印。

#### 序号 6｜`FC_DL_HmsToTodChk`（DL_MathData，纯函数）

- **输入输出语义**：输入 uHours / uMins / uSecs [UDINT，各分量独立输入（HMI 三字段组态入口）]；输出 tTod [TOD_OF_DAY] + bValid + nInfoCode。
- **判据链**：分量非负闸（UDINT 天然非负，仅需声明）→ 组合域闸（uHours > 23 / uMins > 59 / uSecs > 59 → **钳位照算 + 信息级**，与 `FC_DL_DurationFormat` 域外钳位口径对齐）→ 合成毫秒 `uHours×3600000 + uMins×60000 + uSecs×1000`（最大 86399999 < 2^31，乘法无溢出面，头注释留推演）→ TOD 出口。
- **边界安全条件**：整数进位点（终审两式 #2）：「23:59:59 恰为上界」「24:00:00 越界钳位」两点各推一条向量；分工互引：`FC_DL_TodToDintMs` / `FC_DL_DintMsToTod`（毫秒计数口径）、`FC_DL_TimeToHmsString`（TIME→"hh:mm:ss" 文本，本件为其组态侧反向语义非文本变体）。
- **真实工况**：HMI 班次时刻/窗口时刻设定 → 与 `FB_DL_TimeWindowCheck` / `FB_DL_OccScheduleWindow` 联用。

### 批 3

#### 序号 7｜`FC_DL_DaysInMonthChk`（DL_Base，纯函数）

- **输入输出语义**：输入 uYear [UINT，承诺段 1998~2117（DATE 容器秒承载口径一致段），域外钳位照算信息级] / uMonth [UINT]；输出 uDays [USINT，28~31] + bValid + nInfoCode。
- **判据链**：月域闸（1~12 外 → 故障级早退输出 0）→ 二月分支：**组合调用 `FC_DL_LeapYearChk`（闰年律唯一属主，不内联 4/100/400 三级判定——常量单源纪律）** → 大小月出口（31/30/29/28 四值）。
- **边界安全条件**：整数进位点：月域「1 恰为下界」「0/13 越界」两点各推一条向量；闰年向量三组（2024 闰 / 2100 世纪非闰 / 2000 闰）随验收向量落 JSONL；分工互引：`FC_DL_LeapYearChk`（闰年律属主）、`FB_DL_MonthWindowCheck`（月窗判定，消费本件可 simpl 月末界）。
- **真实工况**：月末日期计算、月度报表界、计量月切账日推演。归位声明：日历 FC 原子族（LeapYearChk / DayOfWeekCalc / WeekOfYearCalc / DurationFormat）属主均在 DL_Base（registry 实测），本件随族归位。

#### 序号 8｜`FB_DL_BlinkOutput`（DL_Base）

- **输入输出语义**：输入 bEn [标志] / tOn [ms] / tOff [ms]；输出 bOut [标志]（方波）+ uCycleCount [UDINT]（完整周期计数，饱和上限声明）。
- **状态机/判据链**：两相交替（无 CASE，判据链口径）：eOn 相 TON 计时到 → 切 eOff 相 → 计满回切；**bEn = FALSE 冻结 bOut 与相位计数值**（失能不清相位，恢复时从冻结点续走，R46 末拍快照口径家族一致）；`tOn = 0` 或 `tOff = 0` → 组态锁存码（防全灭/全亮静默——ScaleRangeWatch fGain=0 教训 R386 同型）；TON 本体首部无条件周期刷新（R40 口径）。
- **边界安全条件**：TON IN 极性按 R319 复核（本件 IN = 相内剩余条件，非被监视正常电平，声明即可）；tOn = tOff 恰等（对称方波）与 tOn/tOff 极端幅值（±1E9 ms）各推一条向量；分工互引：`FB_DL_PulseGenerator`（触发式单脉冲）、`FB_DL_PwmDutyController`（高频占空比调制）——本件只做秒级闪烁。
- **真实工况**：塔灯辅闪、报警闪烁、待机呼吸灯。溯源：OSCAT BLINK 行为定义（tOn/tOff 独立交替 + 失能冻结），OSCAT 许可免费需致谢，零代码行复制。

#### 序号 9｜`FB_DL_OilLevelWatch`（DL_Device）

- **输入输出语义**：输入 fLevelMm [mm]（液位连续值引脚注入）、fLowWarnMm [mm]（低油位预警阈值）、fHystMm [mm]（回差）、tConfirm [ms]（欠油确认延时）、bEn / bReset；输出 bLowWarn [标志] + eHealth [引用 E_DL_Ne107Status 唯一属主，不重造：欠油 → eMaintenanceReq，非有限/探头故障 → eFailure] + bError + nErrCode。
- **状态机/判据链**：单相监视（无 CASE）：非有限液位闸（NaN/Inf → **直接故障锁存**——探头断线状态不明比欠油更危险，R71 AxisEncBatteryWatch 口径家族一致）→ 双阈值迟滞判定（fLowWarnMm 与回差构成进入/退出线，防临界抖振）→ TON 连续确认（断输入口径）→ 预警锁存 + NE107 出口。锁存解除**电平式**（R321：禁恢复沿作唯一解除载体——bReset 上升沿唯一人工解除 + 条件恢复自动降级双路，头注释写死）。
- **边界安全条件**：阈值倒置/回差为负 → 组态锁存码；fLevelMm 越物理量程上界（探头饱和）→ 信息级（满油合法工况）；TON 无条件刷新；分工互引：`FB_DL_SiloLevelInterlock`（料仓联锁）、`FB_DL_LevelSwitchVib`（开关量检测）、`FB_DL_HydrostaticLevelComp`（静压补偿换算）——本件只做模拟量油位趋势监视，不做联锁与换算。
- **真实工况**：齿轮箱/液压单元油位巡检，欠油提前补脂防干磨烧轴。

### 批 4

#### 序号 10｜`FB_DL_ToolChangerSeq`（DL_Motion，C3，本轮唯一 ≥250 行件）

- **输入输出语义**：输入 uToolReq [UINT，目标刀位 1 起] / nToolCount [UINT，刀库容量组态] / bToolHome / bArmHome / bArmFwd / bArmBack [标志，机械手取放到位反馈引脚注入] / bSpindleFree [标志，主轴可换刀互锁] / tActTimeout [ms] / bEn / bReset；输出 uToolSelCmd [UINT 刀位指令] / bArmFwdCmd / bArmBackCmd [标志] / bToolDone [标志，单拍脉冲，R24 口径] + eState [E_DL_ 枚举] + bError + nErrCode。
- **状态机要点**（ENUM + CASE + ELSE 兜底）：`eIdle → eSelect（刀位校验/映射）→ ePick（取刀）→ eSwap（主轴换刀，bSpindleFree 才迁入）→ eReturn（旧刀回库）→ eDone（bToolDone 单拍）→ eIdle`；每执行相带独立 TON 超时（段内断输入，R40 口径），超时 → eFault + 锁存码；ELSE 兜底 eFault。
- **边界安全条件**：uToolReq = 0 或 > nToolCount → 拒收 + 信息码（不发指令）；nToolCount = 1（单刀库退化）→ 信息级直接 eSelect→ePick；换刀中途 bSpindleFree 撤销 → 保持相 + 提示（不中断不回退，防半程掉刀——安全侧声明）；失能/故障 → 全输出清零 + 状态回 eIdle（停机相输出清零，R57）；uToolReq 与 eState 判定同拍竞态（同拍竞态闸 R279 清单项）：换刀受理只看迁入沿锁存副本，禁跨拍双判。
- **分工声明**：`FB_DL_TurretToolSelect`（刀塔分度选刀，无机械手取放，DL_Motion 1.0.1 在册）、`FB_DL_ToolLifeBudget`（寿命记账）——本件只管换刀机构「命令-反馈-确认」编排，头注释互引分工边界表。
- **来源边界**：T2-6 设备级 AOI 伺服外围件方向 + t1-9 国产机床 FB 手册公开功能清单（换刀必有反馈对与互锁为公开工程惯例），状态机/码位/时序 100% 自有 clean-room。

#### 序号 11｜`FB_DL_RejectBlowCtrl`（DL_Process）

- **输入输出语义**：输入 bNgFlag [标志，上游 NG 预告（视觉/称重判定输出）]、fBeltVel [mm/s]、fDistNgToGate [mm]（NG 检测位→气吹位间距）、tBlowPulse [ms]（气吹定宽）、tConfirmWin [ms]（剔除确认窗）、bEn / bReset；输出 bBlowCmd [标志，定宽脉冲] / uRejectCount / uMissCount / uFalseCount [UDINT] + eState + bError + nErrCode。
- **状态机/判据链**：`eIdle →（bNgFlag 上升沿布防）eArm（延时窗 = fDistNgToGate / fBeltVel 换算 + 组态容差）→ eBlow（定宽气吹脉冲）→ eConfirm（确认窗内复验 NG 是否已离线）→ eIdle`；ELSE 兜底 eFault。布防沿用 R_TRIG，本体首部无条件刷新。
- **边界安全条件**：fBeltVel 非有限 / ≤ 0 → 拒收 + NG 漏剔计数（不发气吹，防静默放行——速度不明即不剔除，宁可人工清台）；确认窗满拍**复验一次** NG 离线状态（R41/R42 同拍竞态口径：窗满拍反馈迟到临界收敛）；漏剔 = 窗满 NG 仍在位；误剔 = 布防后无 NG 确认却执行气吹 → uFalseCount；失能 → bBlowCmd 清零 + 布防撤销（停机相输出清零）；延时换算除法先判后除（fBeltVel 闸已前置）。
- **分工声明**：`FB_DL_VisionResultGate`（视觉结果放行闸）、`FB_DL_WeightCheckReject`（称重 NG 判定）、`FB_DL_ConveyorJamDetect`（堵塞诊断）——三者均属「判定」域，本件只做「预告→延时→气吹→对账」**执行时序**域（R363 邻接共存先例，头注释分工表）。
- **真实工况**：灌装/包装线吹除 NG 瓶，漏剔误剔对账直接进 OEE 质量因子。

#### 序号 12｜`FB_DL_SipLineSterilSeq`（DL_Process）

- **输入输出语义**：输入 fTempC [℃，工艺温度探头] / bDrainDone [标志] / fHoldTempSet [℃，保温承诺温度] / tHoldTime [s，保温窗] / tDrainTimeout [ms] / bEn / bReset；输出 bDrainCmd / bSteamCmd [标志] / bSterilized [标志，放行] / uHoldRemain [s，保温剩余倒计时，HMI] + eState + bError + nErrCode。
- **状态机要点**（ENUM + CASE + ELSE 兜底）：`eIdle →（bEn ∧ 组态闸）eDrain（排凝，超时 → 故障锁存）→ eHeatUp（升温，fTempC 达 fHoldTempSet 迁入）→ eHold（保温窗 TON；**fTempC 跌破设定 → 计时中止回 eHeatUp + 扰动计数**，恢复后从零重计——SIP 无菌保证不容断点续计）→ eCooldown（关蒸汽，温度回落确认）→ eDone（bSterilized）→ eIdle`；ELSE 兜底 eFault。
- **边界安全条件**：fTempC 非有限 → 故障锁存（温度状态不明不得放行，R42 本拍复验口径：迁入 eHold 迁入拍与每拍判温均取本拍实时值）；fHoldTempSet 越承诺段（< 100 ℃ 声明为组态锁存——SIP 公开最低承诺 121 ℃ 工程惯例，下界提为常量输入可调）；失能 → 双输出清零 + bSterilized 撤销；单探头承诺段声明（多点冷点归上位编排，数组版不立防拆件凑数）。
- **分工声明**：`FB_DL_CipCleaningSeq`（化学清洗顺控）、`FB_DL_AutoclaveSterilSeq`（灭菌釜批次）、`FB_DL_TunnelPasteurizerSeq`（隧道巴氏）——本件专管**管路蒸汽 SIP 连续工艺段**，头注释互引分工边界表。
- **来源边界**：T2-2「命令→监视→判定」三段分层骨架借用；保温窗断点重计与冷点判据 100% 自有；SIP 121 ℃ 最低承诺属公开工程惯例条款。

---

## §7 收口备注

- 三向一致：收口后由 closeout 脚本合并落盘五件套（R219），INDEX_REGISTRY ∪ 文件树 ∪ 本计划 §4 表逐条对账（R192）；12 新 + 1 点修 = 13 条差额全部列账。
- L2 闸（R71 遗留 P0）：新件逐件过 RuSTy 编译（PASS 或命中 INTERFACE-PROPERTY/E032 类缺口留档），批 0 点修件复验必 PASS。
- 终审按 FB-51 两段式：先对全部抽件跑模板定向扫查（闸覆盖/相迁移闸位/同拍竞态/冻结分支出口/TON IN 极性 R319/解除式电平式 R321），其余快速通读；R333 口径——无人值守轮缺陷只挂账不改码。
- 预算可行动归因（R196）：本轮件数 12、复杂度 2×C1 + 9×C2 + 1×C3、返修轮次待收口实测；超时主因只记可行动因子。
- ROADMAP 本轮不补写（55 条 > 30 阈值）；矩阵本轮不整组收口、不新开组，逐组补口待收口轮回写。
