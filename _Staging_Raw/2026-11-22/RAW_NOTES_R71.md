# RAW_NOTES_R71 —— R71 轮取材留痕

> 轮次：R71 ｜ 日期：2026-11-22 ｜ **WebSearch 0 次（检索预算 0/3）**——本轮为第 6 个连续零检索轮，取材**全部来自既有 MATRIX 台账与内部族深化**，无任何外部网页/仓库访问。
> 判重依据：`INDEX_REGISTRY.json` v2.62.0（1,199 件）实时提取 name 全表，python 精确匹配 + 词根邻件扫描（R327 口径），留痕见 `ROUND_PLAN_R71.md` §2.2（拒单 9 条）。

## 取材来源逐件留痕（来源 / URL 或内部族 / 许可证 / 提取点）

| # | 组件 | 来源标签 | 来源与定位方式 | 许可证 | 提取点（只借什么） |
|---|---|---|---|---|---|
| 1 | FB_DL_ScaleRangeWatch v1.0.1 点修 | r70-plan | 内部：`_Staging_Raw/2026-11-22/BATTLE_REPORT_R70.md` P0 挂账「量程零域复核」+ `C:\Library\DL_MathData\FB_DL_ScaleRangeWatch.st` v1.0.0 全文实测（183 行） | 本库自有 MIT | 零外部借鉴。缺陷假设三则（文档口径漂移 / 零量程双闸覆盖推演 / 复位当拍重锁存披露）与修法判据见 `ROUND_PLAN_R71.md` §3-1；预期为披露级点修，不改行为 |
| 2 | FC_DL_AirSpecificVolume | t1-2-oscat-building | 内部：`SOURCE_HUNTING_MATRIX.md` T1-2 行（OSCAT Building 焓湿图族「全参族待挖」）——历史轮次 R5/R10/R12/R25 已按同一组纪律落地 DewPointCalc/AirDensity/HumidityRatioCalc 等 | EPL-2.0（历史轮已核，行为定义借鉴口径沿用 R25 先例） | 只借「按公开物理公式链逐件落地」的组纪律；Magnus-Tetens 饱和分压与理想气体分压叠加为公开湿空气学公式；饱和分压常数属主复用库内 `FC_DL_VaporPressureSat`（调用不复制）；比容输出语义、引脚名、信息码、域闸 100% 自有 |
| 3 | FB_DL_AxisEncBatteryWatch | t2-6-rockwell-aoi + t2-8-ne107 次源 | 内部：MATRIX T2-6 行「设备级 AOI 粒度族（阀/电机/夹爪）待挖」→ 本件取伺服外围（编码器电池）方向；T2-8 行 NE107 六态公开语义（R13 已落地属主 `E_DL_Ne107Status`） | 闭源，按最严口径零代码行 | 只借「设备级粗粒度监视 + 双阈值分型（warn/fault 两线迟滞）」的组织方式；NE107 只借公开分级条款（欠压预警→eOutOfSpec、状态不明→eMaintenanceReq）；电压判据链、阈值默认域、码位、迟滞口径 100% 自有 |
| 4 | FC_DL_DurationFormat | iec-std-wrapper（T0-2 族内补口） | 内部：MATRIX T0-2 行（Date and Timer → DL_Base 分类事实，八组 8/8 ✔ 维护模式，本轮 T0=1 属允许区间 0~1 族内补口） | IEC 61131-3 标准语义，无版权文本 | TIME 时长 → 天/时/分/秒分解为标准算术语义；与既有 TimeToDintMs/TimeToLrealSec 的「单一数值换算 vs 日历分量分解」职责分离为本库自有规格；无平台内建链依赖（R195 闸合规） |
| 5 | FB_DL_FlyingShearSync | t1-6-plcopen | 内部：MATRIX T1-6 行（PLCopen Motion 深化方向；飞剪/飞锯属 MC 同步应用公开分类）——历史轮次 R6/R8/R11/R13 已按「公开语义 clean-room」纪律落地回零/齿轮/凸轮/张力族 | 规范文档公开语义（PLCopen 与厂商应用手册均为公开技术文献），零代码行 | 只借「飞剪属同步应用、同步窗 + 速度匹配」的分类事实与参数域组织方式；四段状态机（加速-同步-剪切-退出）、切长积分触发、单拍剪切脉冲（R24 范式）、全部码位 100% 自有；不自造轴状态枚举（R31 家族高危区纪律，工艺态只用 bSyncDone 类标志） |
| 6 | FB_DL_LaneDivertCtrl | s9-conv（t2-7-packml 次源） | 内部：S-9 输送线工程惯例（R7 ZPA 先例）+ MATRIX T2-7 行 PackML「最小子集 + 明确终止态」态命名语义（R10/R11 先例） | 工程惯例公开；ISA-TR88.00.02 公开条款 | 只借「命令-反馈-确认」三段组织与最小子集态命名；道岔动作器握手、拒放计数、放行撤销、全部码位 100% 自有 |
| 7 | FC_DL_TriangleSolveSSS | t2-1-lgf-math | 内部：MATRIX T2-1 Math 行备注（R64 订正后遗留「三角方向仍待挖」）→ 本件为三角方向首件（SSS 解三角形） | 闭源，只借分类事实 | 只借「几何原子归 Math 组」的分类事实；余弦定理/三角形不等式为公开数学，clean-room 全量自有；ACOS 入参钳位、三角和复验、信息码均本库自有判据；泛名 `TriangleSolve` 因与 `FB_DL_TriangleGenerator` 同根异义被拒改名（R28-4 三处记账，见 ROUND_PLAN §2.2 #7） |
| 8 | FB_DL_PumpPrimingWatch | t2-2-lbp（self 判据） | 内部：MATRIX T2-2 行「命令-监视-判定」三段分层骨架（R11/R13 先例）+ 泵族四件既有属主（DryRunProtect/CavitationGuard/AlternationLead/PrimingWatch 间隔定位） | 闭源，只借骨架 | 只借三段分层骨架；灌泵确认窗、流量∧压力双判据同拍复验（R42）、窗满拍复验收敛（R41 竞态）、码位 100% 自有；与运行期干转/汽蚀件的分工边界表写入头注释 |

## 本轮零检索声明

- **WebSearch：0 次**（预算 0/3）。取材定位全部通过阅读 `C:\Library\SOURCE_HUNTING_MATRIX.md` 台账组状态列、`C:\Library\ROADMAP.md` 55 条待办、`INDEX_REGISTRY.json` v2.62.0 name 全表与既有 `.st` 源码完成。
- 组级状态结论：无 ☐→◐ 开组、无整组 ◐→✔ 收口（✔ 9/27 维持）；触及行 = t1-2 ◐ 深化、t2-6 ◐ 深化、t0-2 族内补口（行级）、t1-6 ◐ 深化、t2-1 ◐ 深化、t2-2 ◐ 深化——编码收口后由 closeout 脚本回写状态列（R219/R335）。
- 合规：零 GPL/AGPL 接触；闭源源（Rockwell AOI / PLCopen / LGF / LBP / PackML）零代码行、零 DB 结构、零注释原文复制；逐件 `.st` 头注释按铁律 3 标注「原创实现（参考 XXX 分类与参数域）」。
