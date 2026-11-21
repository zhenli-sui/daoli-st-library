# RAW NOTES R17 —— 检索与核对留痕（T0 零检索轮）

> 轮次：R17（500 冲刺快车道第 4 轮，T0 为主）｜ 日期：2026-11-16 ｜ 记录人：工控代码库产品总监
> 性质：**纯 T0 轮**。**T0 零检索，复用既有台账** —— 本轮无任何新增外部源抓取，`_Staging_Raw` 下无新增 `original_*.st`，无新增许可证条目。
> **WebSearch 调用次数：0**（预算 ≤2 次，未动用）。**T1/T2 组：未动用**（纯 T0 轮配额减配至 0，符合「本轮 T0 为主、T1/T2 允许 0~1 个」的授权口径）。

---

## 1 检索结论（如实声明）

| 项 | 结论 |
|---|---|
| 本轮是否联网检索 | **否**。四族 20 件全部为 IEC 61131-3 标准函数/运算符的防御性包装，接口语义由标准定义、不构成版权文本，属 R14 既定「T0 三判据准入」免检路径 |
| WebSearch 次数 | **0**（预算 2，剩余 2） |
| 是否新增暂存区原始件 | 否（零外部代码进入 `_Staging_Raw`） |
| 是否新增许可证核查 | 否（本轮无第三方代码行，无协议传染风险） |
| 既有台账复用 | 是。复用 `SOURCE_HUNTING_MATRIX.md` §1 T0 组定义、§5 挖掘状态台账 T0-4/T0-5/T0-7 三行、`AGENT_EVOLUTION_LOG.md` R45/R50/R54~R60 范式 |

**T0 三判据（R14 立，本轮逐族复核通过）**：
1. **逐引脚对应标准语义**：每个 `VAR_INPUT` 都能在 IEC 61131-3 标准函数/运算符定义中找到对应参数（`LOG(x)`、`EXPT(base, exp)`、`TIME_TO_DINT`、`TRUNC`、`SHL/SHR/ROL/ROR`）；
2. **内部委托平台内建**：数学内核一律调内建，道莅只加域闸/钳位/错误码（逐件见 `ROUND_PLAN_R17.md` §4「委托内建」行）；
3. **clean-room 溯源**：文件头统一「IEC 61131-3 标准语义的道莅防御性实现」，不引用任何厂商实现。

---

## 2 本轮核对动作（按指令：快速核对，禁止全库扫描）

只读 3 份状态文件 + 3 次定点 grep，**未做全库逐文件遍历**。

### 2.1 `INDEX_REGISTRY.json`（`python -c` 解析，未落盘修改）

| 核对项 | 实测值 |
|---|---|
| `version` | **2.5.0** |
| `total_components` | **264** |
| `last_updated` | `2026-11-16T07:32:00+08:00` |
| `counts` | DL_Base 55 / DL_MathData 87 / DL_Algo 28 / DL_Device 50 / DL_Motion 18 / DL_Process 26（合计 264 ✔ 与 `total_components` 自洽） |
| 末批注册时间戳 | 20 件全部 `2026-11-16T07:32`（即 R16 批） |
| `function_tags` 含 `iec-std-wrapper` 的件数 | **60**（R14 4 + R15 16 + R16 20 + 早期 20，逐件名单已抽取核对，本轮 20 个新名称**零重名**） |

**重名核查**：把 R17 拟立的 20 个名称与 registry 全部 264 条 `name` 做集合比对，**交集为空**；另与 `DL_*/` 目录实际文件名比对同样为空。

### 2.2 错误码游标反算（定点 grep，不依赖 manifest）

| 核对项 | 实测 |
|---|---|
| `16#0001_*` 已用最大码 | **`16#0001_02C9`**（命中 1 处，R16 `FC_DL_TimeDivChk` 预留槽）→ R17 故障级起点 `02CA` ✔ 与 R16 战报交接一致 |
| `16#0001_*` 已用不同码数 | 277 个 |
| `16#0002_*` 占用情况 | 已用 `0001`~`04xx` 与 `1D01`~`2212`（DL_Algo / Device / Motion 类段），**`16#0002_02xx` 属 DL_Algo 类段已占区** |
| 类段映射（抽样验证） | `DL_Algo/FB_DL_RateLimiter.st` → `16#0002_*`；`DL_Motion/FB_DL_SingleAxis.st` → `16#0004_*`；`DL_Process/FB_DL_PickAndPlaceStation.st` → `16#0005_*`；`DL_Base/FC_DL_ShlEx.st` → `16#0001_*` |
| **裁定结论** | R17 20 件全部落 DL_Base / DL_MathData，类段 = `16#0001_`；指令样板中的「`16#0002_XXXX`（故障级）」在本批**等价写作 `16#0001_02XX`**（`0001_` 类段内的故障子段）。若按 `0002_` 字面，将与 DL_Algo 类段存量 `0002_0001`~`0002_04xx` / `0002_1D01`~`0002_2212` 撞车。**此裁定已在 `ROUND_PLAN_R17.md` §0.2 留痕，报请创始人知悉** |

### 2.3 缺口核实（本轮立族的事实依据）

| 缺口 | 核实方法 | 结论 |
|---|---|---|
| **T0-4 缺 `LOG`（底 10）** | 矩阵 §1 T0-4 列明 12 个标准函数（含 `LOG`）→ 抽取 registry 中 12 个 T0-4 实交件名（SqrtEx/LnEx/TanEx/AbsEx/SinEx/CosEx/AsinEx/AcosEx/AtanEx/Atan2Ex/ExpEx/ExptEx）→ **`LOG` 缺席、由 `ATAN2` 补位** | 真缺口，`FC_DL_LogEx` 立为批 1 第 1 件；此发现建议在矩阵 §5 T0-4 行补注（收口时执行） |
| **对数/dB 族全库零覆盖** | `grep -i "log\|dB\|分贝"` 打 `DL_*/` 文件名清单 + registry name 集合 | 零命中 → 批 1 五件全部为净新增语义 |
| **TIME↔标量转换零覆盖** | 库内 TIME 相关件仅 R16 四件算术（Add/Sub/Scale/Div）+ Timer 族，**无任何 TIME↔DINT/LREAL/TOD 转换件** | 批 2 五件为净新增 |
| **LINT 目标域与精度告警缺口** | R16 饱和族仅覆盖 REAL→UDINT/UINT/BYTE、DINT→UINT、UDINT→DINT、LINT→LREAL、LREAL→DINT、LREAL→REAL；`LINT_TO_DINT`、`*_TO_LINT`、`DINT/UDINT→REAL 精度告警` 均无 | 批 3 五件为净新增 |
| **LWORD 64 位位串零覆盖** | 位串族现有 `FC_DL_ShlEx/ShrEx/RolEx/RorEx`（DWORD 32 位，头注释显式声明「仅支持 32 位位串，BYTE/WORD 先转 DWORD」） | 批 4 四件为 64 位重载；`LWORD` 类型先例核实见下 |
| **LWORD 平台风险排查** | `grep -rlw "LWORD" DL_*/*.st` → 3 件命中；`FC_DL_BitArrayExtract` / `FC_DL_BitArrayInsert` 已在用 `uField/uMask/uWide : LWORD`、`DL_MASK64_ALL : LWORD := 16#FFFF_FFFF_FFFF_FFFF`、`SHL(LWORD#1, …)` | **库内既有 LWORD 实践 → 批 4 无新增平台风险** |
| ROADMAP 是否已有上述条目 | `grep -n "LOG\|对数\|dB\|DTL\|LWORD\|TOD" ROADMAP.md` | ROADMAP 无 LOG / dB / TIME 转换 / LWORD 位移条目 → 与「ROADMAP 未注册项」判据一致，不重复立项 |

---

## 3 本轮不检索的三条风险与对冲（写清以免下轮误判为疏漏）

1. **`TOD_TO_TIME` / `DT_TO_DTL` 类标准转换在三个目标平台的存在性未联网核实**：属 T0 免检件的唯一不确定点，对冲手段 = 把 `FC_DL_TodToDintMs` 设为**强制三平台编译门槛件**（`ROUND_PLAN_R17.md` §5-C），并把日历族（DT/DTL）整体**延后 P1**，避免把可移植性红线押在未证实前提上。
2. **`EXPT` 溢出行为的平台差异未联网核实**：对冲手段 = 批 1 第 3/5 件在主体计算后**强制结果复检**（非有限即按方向饱和），不假设内建行为一致。
3. **`LWORD` 在 InoProShop 的 64 位支持度未联网核实**：对冲手段 = 库内 R12 既有 LWORD 组件先例（同平台已发版）+ 批 4 全部为 `SHL/SHR/ROL/ROR` 纯委托件，若某平台告警只需在头注释降级声明，不涉及算法改写。

---

## 4 状态一致性观测（留给收口）

- `INDEX_REGISTRY.json` 有 `backup_R8`~`backup_R13` 六个备份，**缺 backup_R14 / R15 / R16**（R14 起改为只留 JSONL 备份 + staging 内 `INDEX_REGISTRY.backup_R15.json`）。**建议收口时统一备份策略**（每轮一个 `.backup_R<n>` 或改为 JSONL 单轨），此条已记入本项目 PDCA，请收口轮次确认是否补建。
- `AGENT_EVOLUTION_LOG.md` 已记录 R16「R15 的 CHANGELOG v2.4.0 条目漏更，以补记形式追加」；R17 收口时须核对 `CHANGELOG.md` 是否已有 v2.5.0（R16）条目，**若无同样以补记追加，不重写历史条目**。
- `ROUND_PLAN_R16.md` 仅 43 行、未内嵌三段样板原文，与本轮（R17）规格口径存在代差；**R17 起规格模板以本文件为基线**（R50 教训 + R59 验证），无需回头改 R16 历史文件。

---

## 5 本轮产出清单（只落盘规划与留痕，零 `.st`）

| 文件 | 性质 | 说明 |
|---|---|---|
| `C:\Library\_Staging_Raw\2026-11-16\ROUND_PLAN_R17.md` | 规划（新建） | 20 件派单 + 4 批引脚级规格 + 三段样板原文 + 码位总账 + 16 项自检 + 禁区表 |
| `C:\Library\_Staging_Raw\2026-11-16\RAW_NOTES_R17.md` | 留痕（本文件，新建） | 零检索声明 + 核对动作 + 缺口证据 + 风险对冲 + 状态观测 |

**未触碰**：`INDEX_REGISTRY.json`、`*.jsonl`、`ROADMAP.md`、`SOURCE_HUNTING_MATRIX.md`、`CHANGELOG.md`、`README.md`、`LIBRARY_MANUAL.md`、各子库 `VERSION.md` / `MANUAL_DL_*.md`、任何 `DL_*/` 下的 `.st`（按指令：回写由收口完成）。

---

*R17 RAW NOTES ｜ 2026-11-16 ｜ WebSearch 0 次 ｜ T1/T2 未动用 ｜ 子代理 0 个*
