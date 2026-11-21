# RAW_NOTES R33 — 2026-11-18

**检索预算**：WebSearch **0 / 3**（零检索轮）。本轮 20 件全部来自 ROADMAP 既有待办池 + 源矩阵已收口族复用，无新增外部源。

## 来源清单

| 件 | 来源族 | 来源标签 | URL / 出处 | 许可证 | 提取点 |
|---|---|---|---|---|---|
| `FB_DL_InverterDeratingCtrl` | 西门子 LGF 11 组（驱动/热保护组） | t2-ne107 | 源矩阵既有条目（无新检索） | 闭源，仅借分类 | 降额状态分级（OK/Warning/Alarm）与热模型时基概念；代码自研 |
| `FB_DL_PigLauncherSeq` | 西门子 LGF 顺控组 + PackML 状态语义 | t2-lgf | 源矩阵既有条目 | 闭源，仅借分类 | 「准备-发射-推进-回收」四相顺控骨架；步超时与联锁自研 |
| `FB_DL_RollChangeoverSeq` | ISA-88 配方切换语义 | t2-isa88 | 公开标准语义（非代码） | 标准文本语义 | 配方校验 → 张力回零 → 参数切换 → 复位四段；实现 clean-room |
| `FB_DL_AndonLinePack` | ISA-18.2 报警 + 安灯分级惯例 | t2-isa182 | 公开标准语义（非代码） | 标准文本语义 | 三级呼叫仲裁 + 呼叫/应答/解除三段计时；台账自研 |
| 其余 16 件 | 道莅自研 clean-room（行业工艺常识 + 既有 DL 库复用） | r33-plan | — | 自有 | 无外部代码接触 |

## 合规声明

- 零代码行复制；T2 四件仅接触「分类 / 参数域 / 命名组织」三层，实现全部自研。
- 未检索、未阅读任何 GPL/AGPL 源码；无闭源源码抄录。
- 本轮 `SOURCE_HUNTING_MATRIX.md` 状态列未改动（无新源收口），仅在文末追加 R33 台账。

## 复用关系（本轮内部依赖）

- `FB_DL_CoolingTowerOpt` ← 冷却塔群控语义参考既有 `FB_DL_ChillerStagingCurve`（无实例依赖）
- `FB_DL_PressFitCurveArchive` ← 包络判定复用 `FB_DL_PressFitMonitor` 口径（自含实现）
- `FB_DL_RollChangeoverSeq` ← 张力回零语义对齐既有 `FB_DL_FilmTensionDancer`（无实例依赖）
