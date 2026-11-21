# R17 战报（BATTLE REPORT R17）—— T0 纯函数第 4 轮收口 ｜ 2026-11-16

> 轮次：R17 ｜ 性质：纯 T0 零检索（T0-4/T0-5/T0-7 变体扩族）｜ WebSearch 0 次 ｜ T1/T2 配额 0 ｜ 召唤模式：**原生**（daoli-library-director + plc-programming-expert）

## 一、四批完成情况（20/20，机检 16 规则 20/20 PASS fail=0，1,481 行）

| 批 | 域 | 子库 | 件数 | 组件 | 终审要点（独立验算结论） |
|---|---|---|---|---|---|
| 批1 | 对数/dB | DL_MathData | 5 | LogEx / LogBaseEx / AmpDbToRatio / RatioToAmpDb / PwrDbToRatio | LogBaseEx 底数退化闸 + 除子复判双保险、绝不到达除法行；20/10 因子分型正确；PwrDb 硬限 380 dB 可表性论证成立 |
| 批2 | TIME/TOD | DL_MathData | 5 | TimeToDintMs / DintMsToTime / TimeToLrealSec / LrealSecToTime / TodToDintMs | 先判后算（超限值不进内建转换）；DintMsToTime 无上域闸论证正确（DINT 正域 < TIME 域）且留档；TOD_TO_TIME 标准链不自实现累加 |
| 批3 | 精度/饱和 | DL_MathData | 6 | DintToRealChk / UdintToRealChk / LintToDintSat / RealToLintSat / LrealToLintSat / LwordToLrealChk | 升位比较（REAL 域界不可精确表示）；TRUNC 向零；下界 −DL_DINT_MAX−1 计算式；2^24 / 2^53 精度口径正确 |
| 批4 | LWORD 64 位域 | DL_Base 4 + DL_MathData 1 | 4+1 | Shl/Shr/Rol/RorLwordEx（DL_Base）+ LwordToLrealChk（DL_MathData） | Shl/Shr 闸后调用、nN ≥ 64 置零；Rol/Ror MOD 64 归一 + 零移位直通；2^53 单侧比较（无符号合法） |

**终审结论：20/20 件级零缺陷 PASS，无需修改任何 .st / registry / JSONL**（JSONL 284 条，本轮 20 条 sha256 全 MATCH）。

## 二、关键数字

- **今日累计 98 / 200**（284 − 186 = 98，11-16 开账）｜ **总库 284 / 10,000（2.84%）** ｜ **距 500 冲刺差 216**
- registry 264 → **284**（v2.6.0），counts：DL_Base **59** / DL_MathData **103** / DL_Algo 28 / DL_Device 50 / DL_Motion 18 / DL_Process 26
- JSONL **284 条** ｜ 全库约 **69,500 行** ｜ 所用源：**纯 T0 零检索**（T0-4 对数/dB 5、T0-5 TIME/TOD+精度饱和 11、T0-7 LWORD 4）
- 召唤模式：**原生**（连续第四轮原生可用）｜ 专家进化新增规则：**4 条（R61~R64）**

## 三、码位改判事件与教训（本轮核心事件）

1. **改判一（派单中途）**：规划声称「存量信息级已用至 02C9、01E8~020F 空闲」经注册表实测**不实**（存量分散占用 0203~0207、0212~021A、021C、021F）→ RealToLintSat 预留 0203→**0210**；LrealToLintSat 0204→**0211**、预留 0205→**021B**；ShlLwordEx 0206→**021D**、预留 0207→**021E**。fault 段 02CA~0305 实测全空闲未动。
2. **改判二（收口复测，未执行）**：全库正则复测发现改判落点**仍与七组存量件交叉撞车**——0201(DayOfWeekCalc) / 0202(TimeWindowCheck) / 0208(TempUnitConvert) / 0210(EventCounter) / 0211(ModuloCounter) / 021B(BitArrayChangeWatch) / 021D~021E(StringTokenStream)。按「严重缺陷不静默大改」纪律列明 R18 改判专项方案（新落点 **0213~0219 + 0220** 经实测全空闲），本版维持源码现状。
3. **教训立规**：R61「码位游标必须以注册表正则实测为准，不得沿用上一轮战报口头交接值」（总监线）；R62「改判双向断言——旧码查重 + 新落点复跑全库唯一性」（总监线）；R63「换算硬限必须反算目标浮点域可表」（PLC 线）；R64「存疑内建转换链必须头注释声明三平台交付门槛」（PLC 线）。

## 四、R18 下轮计划

- **P0 码位改判专项**（先于一切新件）：按 ROADMAP §22.1 执行 8 件 8 码改判（.st / registry / JSONL 五处同步 + sha256 复验）；**R18 码位游标（总监实测值）：信息级起点 `0221`（改判专项先占 0213~0219 + 0220），故障级起点 `0306`**。
- **P0 日历族编译门槛评估**：DT/DTL 日历族（DtToDintEpoch 等）先评估 TOD/DT 内建链跨平台行为，通过后再派单（R64 纪律）。
- **P1 补位组（零检索）**：TimeRatioCalc、DintMsToTod、RatioToPwrDb、Lint↔Udint 交叉域对。
- **P1 LGF 未挖子族**：LWORD 单字版、多段一次搬、仿射变换组合等（按源矩阵 T2-1 行待挖清单）。

## 五、文档落盘清单

README.md（徽章 284 + Round 17 区块）｜ CHANGELOG.md（v2.6.0 节 + 码位改判说明）｜ DL_Base/VERSION.md、DL_MathData/VERSION.md（v1.11.0 + 码位台账）｜ MANUAL_DL_Base.md（§44）、MANUAL_DL_MathData.md（§48）｜ SOURCE_HUNTING_MATRIX.md（T0-4/5/7 三行回写 + R17 实测行）｜ ROADMAP.md（§22 R17 补条 8 条）｜ AGENT_EVOLUTION_LOG.md（R17 节）｜ PLC_EXPERT_EVOLUTION.md、DIRECTOR_EVOLUTION.md（R61~R64）｜ 本战报 + DAILY_STATS_R17.md。
**未动**：INDEX_REGISTRY.json、daoli_st_sft_dataset.jsonl（终审零缺陷，无改码需求）。

---

*R17 ｜ 2026-11-16 ｜ 道莅工控代码库产品总监*
