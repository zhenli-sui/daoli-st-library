# R87 拒收说明

| 文件 | 原路径 | 拒收理由 |
|---|---|---|
| FB_DL_ServoEnableSeq.st | DL_Motion/ | **语义真重复**。与在册 `FB_DL_AxisBrakeSeq`（v1.0.1，头注自称"伺服轴上电/断电两条序的唯一属主件"）的上电序 A 三同：同族（轴使能-抱闸生命周期）、同入形（EnableReq/MainsReady/EnableFbk/BrakeFb + 超时）、同出形（EnableCmd/BrakeReleaseCmd/Ready/Error）。本轮新增的 `FB_DL_ServoBrakeReleaseSeq` 已覆盖纯抱闸时序，本件为第三份同构实现，按「三道去重·道3 语义同义」拒收。 |

## 复核记录（主控）
- 审校席对 `FB_DL_ServoDisableSafeSeq` 报 BLOCK（"先撤使能后合抱闸，与 AxisBrakeSeq 禁忌相反"）→ **主控复核判定：指控部分成立、不构成拒收**。
  - 源码 `:88-105` 实序为「eDecel 保持使能减速到零速 → eDisable 撤使能 → eBrake 合抱闸」，属 IEC 60204-1 停止类别 1（SS1）标准序；
  - `FB_DL_AxisBrakeSeq` 为重力轴抱闸优先序（先建立抱闸力矩再撤使能），二者适用工况不同，属有效变体（防误杀口径：不同拓扑/不同工况）；
  - 真实问题是**属主声称冲突**（AxisBrakeSeq 自称唯一属主）→ 已在件头补「工况边界」声明 5 行，明确二者边界，缺陷关闭，本件放行。
- 结论：审校 BLOCK 1 项 → 成立 1 项（属主冲突）但降级为 MAJOR 已修；拒收仅 1 件，非审校建议的 2 件。
