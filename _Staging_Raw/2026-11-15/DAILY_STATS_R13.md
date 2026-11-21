# R13 当日（跨日）统计看板 ｜ DAILY_STATS_R13

- 生成时间：2026-11-16（11-16 零点后首轮收尾文档线落笔）
- 统计口径：Phase 1 目标 200 件 ｜ 总库规划 10,000 件

---

## 一、按日进度

| 日期 | 新增 | 累计 | Phase 1 达成率 | 备注 |
|---|---|---|---|---|
| 2026-11-15（全天收日） | 160 | 186 | **80.0%** | R1~R12 共十二轮全部落在此日 |
| **2026-11-16（开账）** | **18** | **204** | **9.0%** | R13 轮 18 件，registered_at 落 11-16 |
| **合计** | **178** | **204** | **102%**（相对 200 目标） | Phase 1 目标已越过 |

## 二、总库水位

| 指标 | 数值 |
|---|---|
| 总库组件 | **204 / 10,000（2.04%）** |
| 子库分布（实测，与 INDEX_REGISTRY counts 一致） | DL_Base **40** ｜ DL_MathData **42** ｜ DL_Algo **28** ｜ DL_Device **50** ｜ DL_Motion **18** ｜ DL_Process **26**（合计 204） |
| 全库 .st 行数（`wc -l DL_*/*.st` 实测） | **62,667 行 / 204 文件** |

## 三、语料（JSONL）【注册收口已完成】

| 指标 | 数值 |
|---|---|
| 语料条数（实测 2026-11-16 00:34） | 186 → **204 条**（+18 新增、2 条存量再同步：InterlockMatrix / AgvDockingHandshake v1.0.1） |
| 注册表 | `INDEX_REGISTRY.json` total_components = **204/204**，v2.2.0，last_updated 2026-11-16T00:34:03+08:00 |
| sha256 一致性 | 204/204 一致，**以注册收口脚本实测为准**（收口记录不落 sha 字段） |
| 快照 | `backup_R13`（收口前 186 行）建立于 2026-11-16 00:29 |

## 四、机检状态

| 项 | 状态 |
|---|---|
| 覆盖 | **204 件 × 16 条规则**（audit_library_r13.py：banned_hits / placeholder / terminator / bilingual_comment / case_else / enum_case_completeness / enum_separator / nested_comment / undefined_identifier / single_colon_or_semicolon / duplicate_pou_name / line_count / r37 / r38 / r39 / r40） |
| 本轮修复件 | 三泳道修复后全部 `fail=0 warn=0` |
| r39 全库终值 | `files=204 fail=3 warn=2` |
| r39 残余裁定 | **3 FAIL + 2 WARN 均为误报，逐件人工推演裁定留档**（FB_DL_Integrator / FB_DL_PidController / FB_DL_PulseDirStepper / FB_DL_PortDiagBoard / FB_DL_AxisVelocityMove）——未采用任何仅为机检变绿的硬改语义 |
| 遗留 | R14 立项 r39 豁免机制（排除项判据扩全段 + 复位先于覆盖豁免形态） |
| 编译验证 | 连续十四轮悬置；替代验证方案落地前，「机检全绿」不构成放行依据 |

## 五、本轮质量速览

- 本轮 18 件终审 **18/18 PASS**，确定缺陷修复 **14 处**（泳道 A 9 + B 1 + C 3 + R39 存量 2），升版件 8（v1.0.0 → v1.0.1）。
- 新规则 **R45**（CASE 前置无条件状态改写吞复位沿——R39 首轮实战确证 + 三类误报形态登记）入规则库。
- 明星条目 **#36~#38** 追加（ValveStictionDetect / DeviceHealth+ModbusPowerMeter / Matrix3Inverse），累计 38 篇。
- 并发事件：21:50 僵尸锁（超 90 分钟）接管，18 件半成品完整续跑，未重写未重复。

---

*DAILY_STATS_R13 ｜ 2026-11-16 ｜ 道莅工控代码库产品总监（兜底模式）｜ 注册收口已于 00:34 完成，本看板全部为实测值*
