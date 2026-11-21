# RAW NOTES R20 —— 检索/决策留痕

> 轮次：R20（纯 T0 快车道轮）｜ 生成时间：2026-11-16 ｜ 编制：道莅工控代码库产品总监
> **WebSearch 使用次数：0**（T0 组零检索红线达成；同源零重复检索）

---

## 1 T0 零检索决策依据（本节代替检索记录）

1. **目标域来源**：本件候选全部落在源矩阵 T0 台账已收口七组（T0-1~T0-7）的**真缺位子族**与 ROADMAP §22.2 未结项（P0/P1 各一组），取源优先级第 1/第 2 档，未动源矩阵 T1/T2 待挖掘队列（500 冲刺期允许 T1/T2 减配至 0~1，本轮取 0）。
2. **逐候选查重留痕（R61 教训：不凭清单臆断，grep 实测）**：对 20 个候选名逐一 `grep -rl "DL_<Name>" DL_*/`，全部返回 FREE；对疑似撞车族另行 grep 全名核实：
   - BCD 谱系实测 = `FC_DL_BcdToWord` / `FC_DL_WordToBcd`（R9）+ `FC_DL_BcdToUdint` / `FC_DL_UdintToBcd`（R16）——**BYTE 2 位拨码容器确实缺位**，故 #9/#10 立项、Dword 容器变体不立项（与 `BcdToUdint` 同义，凑数禁令）。
   - 字节序谱系实测 = `FC_DL_SwapBytes16` / `FC_DL_SwapBytes32`——64 位缺位，#13 立项。
   - `*ToString*` 全库 grep 为空——字符串化族未占用，#14/#15 立项。
   - SEMA/Mutex/Semaphore 全库 grep 为空——IEC 标准功能块 SEMA 未被任何轮包装，#20 立项。
   - TodAdd/TodDiff/DateAdd/DateDiff/TimeAbs/LeapYear/Epoch 全库 grep 为空。
3. **T0 定位红线自查**：20 件全部为「防御性包装 + 内部委托平台内建/库内既有件」，无一件重实现数学内核（#13 委托库内 `FC_DL_SwapBytes32` 组合属同库资产复用，R12 PortDiagBoard 先例；#9/#10 的「商 10/余 10 拼半字节」仅在平台缺 BCD 内建时的容器校验后合成路径，规格留档，非数学内核重实现）。`function_tags` 编码时统一带 `iec-std-wrapper`。
4. **文件头溯源统一口径**：「IEC 61131-3 标准语义的道莅防御性实现（内部委托平台内建函数…clean-room，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）」——样板取自 `FC_DL_LintToUdintSat.st`（R19 最新 T0 件，见 ROUND_PLAN_R20 §4）。

## 2 码位实测记录（R61/R75 教训执行）

- 扫描脚本口径：对 324 个 `DL_*/*.st` 全文正则 `16#000[1-5]_[0-9A-Fa-f]{4}`，去重 1109 个「段+偏移」。
- 逐段 max：`0001` 信息 02xx 满带（n=193 max `02FF`）/ 04xx 子带已用 `0400~040B`（全为 R19 件）/ 故障 03xx max `032F`；`0002` CC `01~2A`（`0002_8011` 为 PdiReadScheduler 头注释示例非占用）；`0003` 信息 `0171` / 故障 `033B`；`0004` 信息 `01D4` / 故障 `02E9`；`0005` 信息 `01D9` / 故障 `030A`。
- 裁定：本轮全部 20 件落 `0001` 段，信息 `040C~0433`（40 槽）、故障 `0330~036B`（60 槽），逐件 5 槽（2 信息 + 3 故障），全程不回填碎片孔洞（R65 纪律）。编码线收尾须复跑正则断言零交集。

## 3 关键裁定与理由（逐件）

| 裁定 | 理由 |
|---|---|
| `FC_DL_UdintToLintChk` 立项并重定义语义为「round-trip 升位验真」 | UDINT→LINT 数学上恒无损，若按字面实现即为凑数；实测发现真实工程风险是**平台把中间量经 32 位有符号路径转换时对 ≥2^31 值做错误符号扩展**（R56/D-13 类型转换异构教训的验真式延伸），round-trip 复核（`LINT_TO_UDINT(UDINT_TO_LINT(x)) = x`）是该错的唯一廉价拦截手段。ROADMAP §22.2 P1 承诺件按此语义结项。 |
| `FC_DL_ShlDwordEx / FC_DL_ShrDwordEx`（§22.2 P2）**不立项** | §22.2 自标「疑似与存量同义，立项前必过 R61 式实测查重」；宁少勿滥，维持警示不结项。 |
| `FC_DL_BcdToDword / FC_DL_DwordToBcd` 不立项 | 与 R16 `FC_DL_BcdToUdint / FC_DL_UdintToBcd` 同容器同义（Udint=Dword 32 位），grep 实测后否决。 |
| TOD 回绕算术采用「条件加减 + 整商」禁 MOD | R11 RolloverCounter 纪律（负数取余三平台不一致）在 TOD 域同样成立；#11 超一日偏移主动收窄为故障级（规格级收窄，收口不得改判）。 |
| DT/DATE 族 8 件附编译门槛预评估义务 | ROADMAP §22.3「日历/TOD 内建链新件一律先做编译门槛评估再派单」债务兑现：#1~#4 #11 #12 #16 #17 规格均给出「平台缺直接内建时的先判后算合成路径」，防止 R17 式派单即拦。 |
| #18 `FC_DL_TimeAbsSat` 的 −MAX−1 案单列故障码 | 32 位 DINT 最小值取绝对值溢出是 R17「−MAX−1 计算式」教训的 TIME 口径复用，不容静默饱和。 |
| #20 `FB_DL_SemaMutex` 超时强制归还定为故障级 | 死锁被系统归还意味着调用方持有的资源已失效，与「正常防御」不同级（对齐 #11 超一日偏移裁定口径）。 |

## 4 R19 遗留事实确认（不做处理，仅登记）

- `MANUAL_DL_Device.md` / `MANUAL_DL_Motion.md` / `MANUAL_DL_Process.md` 实测仅含 R19 批次接口表（抽查 GuardLockDoor/LightCurtain/PulseFlowMeter、ElectronicGear/SoftLimitGuard、OeeCalculator/BatchDosingControl 命中），历史组件（57/25/30 件）接口表缺失——R19 遗留 P1 成立，本轮文档线补录。

## 5 本轮遗留与下轮建议

1. 三本手册历史件接口表补录 + `LIBRARY_MANUAL.md` R18/R19 增量（文档线 P0）。
2. 500 冲刺：324 → 500 差 176，纯 T0 轮 20 件/轮约 9 轮；T0 剩余真缺位子族约 10~15 件（本轮后），下轮起需混合「源矩阵 ☐/◐ 待挖组 + 行业池 P1」恢复非纯 T0 配比。
3. P0 CODESYS 最小工程编译验证连续多轮悬置（R19 账本第④条），批 1 日历族 8 件的门槛预评估结果是下一个最佳验证切入点。

---

*R20 阶段一/二 ｜ 2026-11-16 ｜ 道莅工控代码库产品总监（零检索轮）*
