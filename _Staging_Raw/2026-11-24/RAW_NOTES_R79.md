# RAW_NOTES R79 — 来源表（2026-11-24）

> 本文件是 HARVEST_R79.md 的来源底账。登记口径：仓 → 许可证实读结论 → tier → 抽取点 → 入队条数。
> 纪律：黄区只登记「接口签名 / 参数域 / 语义」，不摘录任何实现语句；红区只登记许可证与去向。

## A. 实读 LICENSE 文本的判级结论

| 仓 | 分支 | LICENSE 实读 | tier | 判级依据 |
|---|---|---|---|---|
| tkucic/brOscatLib | main | `LICENSE`=MIT (c) 2021 Toni Kucic；**同仓另有 `OSCAT_LICENSE`** | 黄 | 双证 → 上游 OSCAT 限制性许可优先，降黄 bones-only（规则 R477） |
| fisothemes/FisoThemes-Time-Library-for-TwinCAT | master | MIT | 绿 | 可改写 + 留痕 |
| fisothemes/FisoThemes-Standard-Library-for-TwinCAT | master | MIT | 绿 | 无 5 族内容，未出料 |
| fisothemes/FisoThemes-Common-Library-for-TwinCAT | master | MIT | 绿 | 关键词误命中，未出料 |
| fisothemes/TwinCAT-Hashing-Algorithms | master | MIT | 绿 | 出料 1 → 语义重复未入队 |
| Technical-Software-Solutions/twincat-tools | main | MIT | 绿 | 16 ST，无 5 族内容 |
| stiana/SARUtils | main | MIT | 绿 | 3 ST，无 5 族内容 |
| AppliedMotionProducts/CODESYS | main | Apache-2.0 | 绿 | 0 ST（工程为二进制 .library） |
| WitchCraftWorks/IEC61131-3-CDSV3 | master | MIT | 绿 | 0 ST |
| pn8ocq/IIOT_Library | main | MIT | 绿 | 0 ST |
| mihaiginta/TcOscatBasic | main | 有 LICENSE 文本但 GitHub 判 NOASSERTION；内容为 OSCAT 语料 | 黄 | 与 brOscatLib 同源重复 + 许可不可判定 → 不入队 |
| simsum/oscat | master | **无 LICENSE 文件** | 拒收 | unknown（质量门：100% 可判定） |
| sagatowski/alltwincat.com-oscat-basic | master | **无 LICENSE 文件** | 拒收 | unknown；且 0 ST 文件 |
| WagoAlex/codesys-project-generator | main | **GPL-2.0** | 红 | 0 ST 文件，零源码拉取，仅登记 |
| OttoMeister/Siemens-Tia-Portal-PID-Controller | master | WTFPL | 黄 | WTFPL 不在绿区白名单（R405 规则） |
| RWTH-EBC/AixOCAT | develop | MIT | 绿 | 出料 1 → 无防御缺口剔除 |

## B. 抽取点登记（入队 21 条的骨来源）

单一来源：`tkucic/brOscatLib` → `oscatBasic/oscatBasic.fun`（**纯声明文件，543 个 FUNCTION/FB 块，无一行实现语句**）。
抽取方式：`_tools/r79_oscat_bones.py` 按 `^(FUNCTION_BLOCK|FUNCTION) <Name> : <RET>` 切块，只取 `VAR_INPUT ... END_VAR` 的参数名/类型/默认值，丢弃其余（含 VAR 私有区与任何语句）。
入队的 18 条黄区：DAY_OF_WEEK、DAY_OF_YEAR、MONTH_END、DAYS_DELTA、DATE_ADD、WORK_WEEK、EASTER、GCD、SQRTN、CIRCLE_A、CIRCLE_SEG、TRIANGLE_A、R2_ADD、ARRAY_VAR、ARRAY_SPR、TREND、_ARRAY_MEDIAN、CRC_GEN。

绿区 3 条抽取点：
- `T_DayOfMonth.TcDUT` / `T_DayOfYear.TcDUT` → `<Declaration>` CDATA 中的 `TYPE ... : UINT(1..31|1..366); END_TYPE`（两行语义 + 注释给的参数域）
- `FB_TimeInstance.TcPOU` → 属性清单（Year/Month/Day/Hour/Minute/Second/Millisecond 的 get/set），未取任何方法体

## C. 未入队但值得记一笔的语义（供 EDGE_CASE_KB 后续提炼）

| 现象 | 载体 | 可落地的缺口 |
|---|---|---|
| 批量方差用两遍法（先均值后偏差平方和），除以 `SIZE-1` | ARRAY_VAR 声明 | 与库内 `FC_DL_StdDevOnline`（Welford 单遍）在数值稳定性上不等价，测试向量需加"大均值小方差"用例 |
| 通用 CRC 的 `PN` 多项式是全开放入参 | CRC_GEN 声明（PT/SIZE/PL/PN/INIT/REV） | 任意 PN 可致反射位错，防御规则应限白名单多项式表 |
| 日期差返回 DINT 而无方向约定 | DAYS_DELTA 声明（DATE_1, DATE_2） | 调用方需明确"后者减前者"，测试向量需正负对称 |
