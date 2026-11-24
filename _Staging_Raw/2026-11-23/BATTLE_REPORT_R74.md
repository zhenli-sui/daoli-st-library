# BATTLE_REPORT_R74（2026-11-23 07:54–08:55，60′ 硬顶内）

## 看板
- 今日 11-23：**46/300**（R72 12 + R73 20 + R74 14）｜总库 **1,252/10,000（12.52%）**｜v2.66.0｜SFT 语料 **1,291**
- 分档：新件 **复杂 3**（MultiPumpRotationCtrl/SafetyLightCurtainMute/KilnTempZoneCascade/WinderTensionTaperCtrl 中 C4×4 — 计复杂 4）｜**简单 10**｜**修复 22**（存量专项回写）｜拒收 6

## L2 编译闸（串行 jobs=1，42 件增量）
- **42 检 / 39 PASS / 3 豁免 → 通过率 92.9%**（豁免后判定位 100%）
- 首检 31/42（73.8%）→ 编码专家回修 1 轮 → 39/39 判定位全过；修复 8 件：E048×6（镜像变量/拼写）、E052×1（枚举零定义补 TYPE）、E032×1（Hysteresis 全回执）
- 豁免 3 件（编译器缺口，逐件列名）：SingleAxis、BatchDosingControl（E007：RuSTy 1.0.8 不解析 FB 内 PROPERTY，最小复现在案）；CamOverrideTrim（E037：VLA→VLA 透传）。下轮 P0：闸侧 PROPERTY 剥离预处理器
- 机检扫增量（dl_gate --hours 3）；TIME_TO_DWORD 残留实测 0（R73 已清账）

## CI 结论
- `git remote -v` 无 origin → **MatIEC-CI 待配 remote**（挂账第 N 轮，值守项顺延）。启用方式：`GITHUB_TOKEN=<PAT> bash C:\Library\_tools\setup_github_remote.sh <owner>/<repo>`

## 开源供料（猎人真跑）
- oss_harvest 实跑 2 仓（OttoMeister TIA-PID WTFPL 黄区 / RWTH-EBC AixOCAT MIT，均 R73 已采，工具无 --exclude 致重复）→ **净增 0**，队列终态 **29 条**（绿区 28 / 黄区 1 / 红区 0）
- 事故披露：剔除禁采条目时误删队列存量 3 条，经 GitHub API 重建（recovered:R74-restored 标记），全程 HARVEST_R74.md 在案
- 新件队列溯源占比：8/14 = 57%（EuclidDist2DCalc/Log10Safe/SwapNibbles/GrayToByteConv/SensorGlitchFilter 等）

## 五角色召唤模式
总监=主控直跑（规划/终审/收口）｜猎人=原生｜PLC 编码=原生（2 次调用：修复+生产批、回修批）｜编译验证=闸由主控串行直跑（原生专家未单独召唤，诊断直读）｜审校去重=原生。兜底 0/5。

## 进化
- 账本 +12 条（总监 3 / PLC 3 / 猎人 2 / 编译 2 / QA 2），游标 R408 → **R420**
- **新规则（本 prompt 候选，待创始人审阅）**：R15 编码前语义查重强制化；R16 FB 内禁 PROPERTY
- 系统性发现：**「同名避让」被用作绕过语义去重通道**（4 件中 3 件撞车）→ 改名入库须附最近语义邻件比对声明

## 下轮计划（R75 P0）
1. 闸侧 FB-PROPERTY 剥离预处理器（解 2 豁免件）；2. CamTableInterp 显式点数字段解 VLA；3. 改名邻件比对规则落 skills + 历史同名避让件语义复核；4. 新件配额 40（今日余量 254/300，需产能回调）；5. 值守三项第 6 轮顺延。

## RESUME
无未完批（40 计划中 6 拒收已结案，22 修复全收口）。
