# HARVEST R79 采集简报（2026-11-24 03:00–03:40）

采集席：dlf-oss-hunter（开源资产猎人）｜轮次：R79｜队列文件：`_Staging_Raw/2026-11-24/candidate_queue.jsonl`
备份：`candidate_queue.jsonl.backup_R79.jsonl`（R78 终态 69 行 / 64 live，写入前已拷出）

---

## 0. 本轮通道变更（最重要的一条发现）

| 通道 | 状态 | 配额成本 | 结论 |
|---|---|---|---|
| `raw.githubusercontent.com` | **不可达（curl 000，代理拦截）** | — | R73 起一直是 0 产出主因 |
| `api.github.com/contents` | 可用 | **1 core / 文件**（匿名 60/h） | 只能撑 3 仓 × 12 文件 |
| `api.github.com/search` | 可用 | 10/min（独立配额） | 域名相关性极差（见 §5） |
| **`codeload.github.com/<repo>/tar.gz/refs/heads/<br>`** | **可用（200，最大拉到 49MB）** | **0 REST 配额** | ★ 本轮改用此通道做整仓下载 + 本地抽取，摆脱 60/h 天花板 |

新增工具（本地，不入库）：`_tools/r79_probe.py`（整仓探测/许可判级/家族命中）、`_tools/r79_extract.py`（签名+家族抽取）、`_tools/r79_oscat_bones.py`（只读声明块抽骨）、`_tools/r79_queue.py`（人工核验后写队列）。

---

## 1. 扫描量

### 1.1 规定命令（真跑，未跳过）
```
python _tools/oss_harvest.py --search --max-repos 3 --max-files-per-repo 12
```
| 仓 | 许可 | tier | listed | fetched | failed | 入队 |
|---|---|---|---|---|---|---|
| OttoMeister/Siemens-Tia-Portal-PID-Controller | WTFPL | 黄 | 8 | 8 | 0 | 1（垃圾名 VAR_INPUT → 已 rejected） |
| RWTH-EBC/AixOCAT | MIT | 绿 | 12 | 12 | 0 | 1（E_SMStatus → 无防御缺口，已 rejected） |
| NathanLi/iOSCategoryPropertyDynamicSupport | 无 | 黄 | 0 | 0 | 0 | 0 |
- 检索 9 条查询，其中 `org:PLCnext-Community` **再次 422**（R78 复现，R79 第 2 次）；该 org 实际不存在（`/orgs/PLCnext-Community` → 404），真实存在的是 `PLCnext` org 与 `plcnextusa`。
- 规定命令净有效 = **0 条**（2 条入队经人工核验全部剔除）。**如实记录：工具通用检索通道本轮零产出。**

### 1.2 codeload 定向采集（本轮主力）
| 仓 | 分支 | 许可（实读 LICENSE 文本） | ST 文件 | 家族命中 | 结果 |
|---|---|---|---|---|---|
| tkucic/brOscatLib | main | MIT + **OSCAT_LICENSE（双证）** | 1813 | cal33/stat3/cksum4/num2/geo1 | **黄区借骨，出料 18** |
| fisothemes/TwinCAT-Hashing-Algorithms | master | MIT | 14 | cksum1 | F_CRC32 → 语义重复，未入队 |
| fisothemes/FisoThemes-Time-Library-for-TwinCAT | master | MIT | 19 | cal2 | **绿区出料 3**（T_DayOfMonth/T_DayOfYear/FB_TimeInstance） |
| fisothemes/FisoThemes-Standard-Library-for-TwinCAT | master | MIT | 47 | 0 | 0（仅计时器/数学基础，无 5 族内容） |
| fisothemes/FisoThemes-Common-Library-for-TwinCAT | master | MIT | 150 | geo1（关键词误命中） | 0 |
| Technical-Software-Solutions/twincat-tools | main | MIT | 16 | 0 | 0 |
| stiana/SARUtils | main | MIT | 3 | 0 | 0 |
| AppliedMotionProducts/CODESYS | main | Apache-2.0 | 0 | — | 0（无 ST，工程为二进制 .library） |
| WitchCraftWorks/IEC61131-3-CDSV3 | master | MIT | 0 | — | 0 |
| pn8ocq/IIOT_Library | main | MIT | 0 | — | 0 |
| mihaiginta/TcOscatBasic | main | NOASSERTION | 577 | cal30/stat3/cksum3 | **未采**：与 brOscatLib 同源 OSCAT 语料且许可不可判定 → 拒收 |
| simsum/oscat | master | 无 LICENSE 文件 | 559 | cal31/stat3/cksum3 | **拒收**：unknown 许可（质量门 100% 可判定） |
| sagatowski/alltwincat.com-oscat-basic | master | 无 LICENSE 文件 | 0 | — | **拒收**：unknown 许可 |
| WagoAlex/codesys-project-generator | main | **GPL-2.0** | 0 | — | **红区，零拉取**（0 ST 文件） |

合计：**规定命令 3 仓 + codeload 14 仓 = 17 仓尝试，5 仓有效出料**；ST 文件列出 ≈ 3411、实际读取 ≈ 2650、失败 0。
抽取签名（含去重前）：OSCAT 声明块解析 **543 个 FUNCTION/FB 块**，命中 5 族 **53 条骨**；绿区抽取 6 条。

---

## 2. 进队数

| 项 | 数 |
|---|---|
| 本轮入队 | **21**（绿 3 / 黄 18 / 红 0） |
| 入队后被剔（工具误捕） | 2（VAR_INPUT 垃圾名、E_SMStatus 无增量） |
| 按语错误标记的存量重复行 | 7（R78 的 7 条 SRCI 枚举，与 R75 同 name 同 source_url） |
| **净增（相对 R78 的 64 live）** | **+13** |
| 拒收（许可不可判定/红区） | 4 仓（simsum、sagatowski、TcOscatBasic、WagoAlex-GPL） |
| 语义重复拒收（未入队） | 6（F_CRC32、PARITY、CHECK_PARITY、FACT、BIT_COUNT、INT_TO_BCDC/BCDC_TO_INT 计 2） |

### 2.1 五个补料方向命中明细

| # | 方向 | 入队 | 未命中/拒收说明 |
|---|---|---|---|
| ① | 日历/日期算术 | **10** | DAY_OF_WEEK、DAY_OF_YEAR、MONTH_END、DAYS_DELTA、DATE_ADD、WORK_WEEK、EASTER（黄）+ T_DayOfMonth、T_DayOfYear、FB_TimeInstance（绿）；LEAP_YEAR/LEAP_DAY 因与库内 `FC_DL_LeapYearChk` 同义被拒 |
| ② | 整数数论/位宽安全 | **2** | GCD（欧几里得二进制法）、SQRTN（n 次根）；FACT 撞 `FC_DL_FactorialSat`、BIT_COUNT 撞库内名、BCDC↔INT 撞 `FC_DL_BcdToByte/ByteToBcd` 全拒 |
| ③ | 二维平面几何 | **4** | CIRCLE_A、CIRCLE_SEG、TRIANGLE_A（SAS 面积）、R2_ADD（2D 向量）；HYPOT 撞 `FC_DL_HypotChk` 拒 |
| ④ | 统计扩展 | **4** | ARRAY_VAR（批量两遍法方差）、ARRAY_SPR（极差）、TREND（在线斜率 FB）、_ARRAY_MEDIAN（批量中位数）；ARRAY_SDV 与 ARRAY_VAR 同参同义只留其一 |
| ⑤ | 校验和 | **1** | CRC_GEN（**带 PN/INIT/REV/PL 参数域的通用 CRC**，可覆盖 CRC-8/MAXIM）；F_CRC32 撞 `FC_DL_Crc32Ethernet`、PARITY/CHECK_PARITY 撞 `FC_DL_ParityCalc` 拒；Fletcher-16/32、XOR-8、二补和 BCC **本族仍 0 命中** |

---

## 3. 队列终态

- **77 条（绿 55 / 黄 22 / 红 0）**，名字唯一 77（重名已清 0）
- 行数 92 = live 77 + rejected 15（全部保留行，仅改 status，无删行）
- **队列深度 77 < 200 → 红色告警**：按 300 件/日 × 50% 语料占比 ≈ 可支撑 **0.5 天**生产；R79 编码席 41 件的溯源够用，R80 起将再次断料。
- 溯源占比（本轮）：21 条候选覆盖编码席 5 族 41 件中约 **31 件**（日历 10/数论 6/几何 5/统计 6/校验 4），**75%（31/41）**。

---

## 4. 剔除与备份记录

| 动作 | 数量 | 手段 |
|---|---|---|
| 工具误捕垃圾名 | 1（VAR_INPUT） | 标 `status=rejected` + reject_reason |
| 无增量价值枚举 | 1（E_SMStatus） | 同上 |
| 存量重复行（R78 遗留） | 7 | 标 rejected，保留首条；`(name, 源仓)` 双键判重 |
| 删行 | **0** | 备份 `candidate_queue.jsonl.backup_R79.jsonl` 已留在位 |

---

## 5. 新发现高价值源

| 仓 | 许可 | 价值 |
|---|---|---|
| **tkucic/brOscatLib** | MIT + OSCAT_LICENSE（双证） | ★ 本轮唯一高产源：543 个 FUNCTION/FB **声明块**集中在 `oscatBasic/oscatBasic.fun`（纯接口、零实现），是"借骨"的教科书式素材；5 族全覆盖 |
| **fisothemes/FisoThemes-Time-Library-for-TwinCAT** | MIT | 绿区：日期分量**子范围类型**（UINT(1..31) / UINT(1..366)）+ 时间实例组件，可直接改写成 DL_ 组件的入参契约 |
| fisothemes/TwinCAT-Hashing-Algorithms | MIT | 绿区 7 个哈希/CRC 函数（F_CRC32/DJB2/FNV1a/MurmurHash3/SDBM），作既有 CRC 组件的对照与缺口核查 |
| fisothemes/* 系列（7 仓全 MIT） | MIT | 该 owner 是 TwinCAT 生态里许可最干净的库作者，后续轮次优先扫全家桶 |

---

## 6. 合规异常（按严重度）

1. **红区泄漏 0 行**：WagoAlex/codesys-project-generator（GPL-2.0）ST 文件 0，未拉任何源码；struckig（GPL-3.0）本轮未触碰。
2. **unknown 许可拒收 2 仓**：`simsum/oscat`、`sagatowski/alltwincat.com-oscat-basic` 均无 LICENSE 文件 → 按质量门拒收，未入队（这是本轮"少拿 60+ 条"的直接原因，合规优先）。
3. **双证仓降级**：brOscatLib 顶层 MIT，但同仓 `OSCAT_LICENSE` 为上游限制性许可 → 全仓降 **黄区 bones-only**，仅取 name/参数域/语义，`compliance` 字段逐条写明"实现必须 clean-room，禁止复制代码行与符号名"。**未写入任何 code_excerpt。**
4. **口径异常（重要）**：R78 报"净增 +7"，实为 **0**——7 条 SRCI 枚举与 R75 同 name 同 source_url 重复入队，工具只对 registry 去重、**从不查队列**。本轮已修正并回补规则。

---

## 7. 缺陷复现清单（工具侧，仍待修）

| # | 缺陷 | 状态 |
|---|---|---|
| 1 | `raw.githubusercontent.com` 不可达 + 无 codeload 通道 | R79 绕行（本地脚本），**工具本体未修** |
| 2 | 签名正则捕关键字（METHOD/EXTENDS/VAR_INPUT） | R76→R79 第 4 次复现 |
| 3 | 无队列级查重（只比 registry） | 本轮新发现，导致 R78 假净增 |
| 4 | 无 `--exclude` 已采仓黑名单 | R74→R79 未修 |
| 5 | `org:` 检索 422 / 目标 org 名不存在 | R78→R79 第 2 次 |
| 6 | 无法暴露 `commit_sha`（用 codeload 时 tar 重打包无 sha） | 本轮新增；当前 `commit` 字段为 `分支@日期`，provenance.json 需补 sha |

---

## 8. 给总监的 3 条建议

1. **先修工具再谈产量**：给 `oss_harvest.py` 加 codeload 通道（零配额）+ 队列级 `(name, source_url)` 查重 + 关键字白名单。三条合起来能把单轮净增从 13 提到 40+，且消除"假净增"。
2. **许可策略要立规**：`simsum/oscat`、`sagatowski/*`（各 550+ ST 文件）因无 LICENSE 被拒，实际是最大的两块未开发矿产。建议法务口径明确"无 LICENSE = 仅可读思想、不入队"，并允许把它们写入 EDGE_CASE_KB 的语义笔记（不入队），把 31 个日历/3 个统计语义用起来。
3. **R80 优先挖**：fisothemes 全家桶（7 仓全 MIT，尚未扫 Standard/Common 的算法区）+ `PLCnext` org 直列（用 `/orgs/PLCnext/repos`，避开 422）+ Fletcher/BCD 族的 OSCAT 声明块（`oscatNetw` 目录未扫，126 文件里可能有 CRC/Fletcher）。

---

## 9. 本轮候选清单（按族，供编码席取件）

**① 日历/日期算术**
| 候选 | tier | 许可 | 可改写为 |
|---|---|---|---|
| DAY_OF_WEEK | 黄 | MIT+OSCAT | FC_DL_DayOfWeek（MOD 7 星期推算，1..7） |
| DAY_OF_YEAR | 黄 | MIT+OSCAT | FC_DL_DayOfYear（月偏移表 + 闰年补偿） |
| MONTH_END | 黄 | MIT+OSCAT | FC_DL_MonthEnd（月末夹取） |
| DAYS_DELTA | 黄 | MIT+OSCAT | FC_DL_DaysDelta（两 DATE 差，DINT） |
| DATE_ADD | 黄 | MIT+OSCAT | FC_DL_DateAdd（D/W/M/Y 四路叠加） |
| WORK_WEEK | 黄 | MIT+OSCAT | FC_DL_IsoWeekNo（ISO 周编号） |
| EASTER | 黄 | MIT+OSCAT | FC_DL_EasterDate（节假日表生成） |
| T_DayOfMonth / T_DayOfYear | **绿** | MIT | T_DL_DayOfMonth / T_DL_DayOfYear（子范围类型） |
| FB_TimeInstance | **绿** | MIT | FB_DL_TimeInstance（时间分量分解） |

**② 数论** GCD、SQRTN（黄）｜**③ 几何** CIRCLE_A、CIRCLE_SEG、TRIANGLE_A、R2_ADD（黄）｜**④ 统计** ARRAY_VAR、ARRAY_SPR、TREND、_ARRAY_MEDIAN（黄）｜**⑤ 校验** CRC_GEN（黄，PN/INIT/REV/PL 参数域）
