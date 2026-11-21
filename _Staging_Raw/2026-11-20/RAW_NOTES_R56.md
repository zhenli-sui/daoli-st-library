# R56 源狩猎留痕（2026-11-20，零检索轮 WebSearch 0/3）

> 本轮零 WebSearch：全部复用既有 RAW_NOTES（R39~R55）与 `SOURCE_HUNTING_MATRIX.md` 既有源行，同源不重复检索。
> 提取点纪律：只借分类组织·参数域·命名组织，**零代码行**；闭源源实现 100% clean-room。

## 逐件来源台账（20 件）

| # | 组件 | 来源标签 | 参考源名 | URL 或矩阵行号 | 许可证 | 提取点（零代码行） |
|---|---|---|---|---|---|---|
| 1 | FC_DL_HermiteInterp | t2-1-lgf-math | Siemens LGF V5.3.0 Math Operations 组 | 矩阵行「T2-1 LGF · Math」（文档 ID 109479728） | 免费使用但闭源版权 | 只借「数学函数独立成组 + 定义域先判」分类事实；Hermite 三次基函数取公开数值分析教材公式，clean-room |
| 2 | FC_DL_QuatSlerp | t2-1-lgf-math | 同上 LGF Math 组 | 矩阵行「T2-1 LGF · Math」 | 同上 | 只借分类事实；SLERP 算法取 Shoemake 1985 公开文献（公共领域数学），clean-room |
| 3 | FC_DL_RoundSigFigs | t2-1-lgf-math | 同上 LGF Math 组 | 矩阵行「T2-1 LGF · Math」 | 同上 | 只借「舍入族独立成件、误差半位闸」的参数域组织；有效数字幂定位算法为公开数值方法 |
| 4 | FC_DL_RtdLinearization | t2-1-lgf-converter | Siemens LGF Converter Operations 组 + IEC 60751 | 矩阵行「T2-1 LGF · Converter」 | 同上（IEC 60751 标准系数为公开标准条款） | 只借「传感器换算独立成族」分类事实；CVD 方程系数取 IEC 60751 公开标准，clean-room |
| 5 | FC_DL_Kalman2DSmoother | t2-1-lgf-measurement | LGF Measurement 组边界 + Kalman 公开理论 | 矩阵行「T2-1 LGF · Measurement」（R8 实测更正：统计滤波归 Math/Measurement 行） | 同上 | 只借「滤波归测量」组边界；序贯卡尔曼更新取 Kalman 1960 公开理论，与 R46 `KalmanFilter1D` 同组纪律 |
| 6 | FB_DL_EStopDualChannel | 自研线（IEC 60204-1 公开条款） | IEC 60204-1 / ISO 13849-1 双回路监视逻辑结构 | 矩阵第 1 节 T3「功能安全」行（仅参考联锁与安全拦截逻辑结构） | 公开标准免费条款 | 只读双回路不一致/单路失效/复位链的公开逻辑结构，不实现安全认证功能；状态机与码位 100% 自有 |
| 7 | FB_DL_SignalSeqGuard | 自研线（次借 t2-2-lbp） | LBP「命令→监视→判定」三段分层骨架 | 矩阵行「T2-2 LBP 基础工艺」 | 闭源（免费使用） | 只借三段分层骨架；序号数组配置与乱序/超时判据本库自有 |
| 8 | FB_DL_TwoDofPid | t2-5-modpid | Siemens Mod_PID_Control 手册参数域 + Åström-Hägglund 2-DOF 公开结构 | 矩阵行「T2-5 Mod_PID_Control」（R18 起「参数域已取尽」，本轮为结构语义深化） | 文档版权 | 只借 PID 结构参数域组织；设定值加权 β/γ 为公开控制理论，零代码行 |
| 9 | FB_DL_AxisAccelFeedforward | t1-6-plcopen | PLCopen TC2/TC4 Motion 公开前馈语义域 | 矩阵行「T1-6 PLCopen Motion」 | PLCopen 规范（免费） | 只借加速度前馈公开接口概念域，不复制任何功能块签名；惯量比折算本库自有 |
| 10 | FB_DL_HydraulicAccumPreChg | t2-2-lbp | Siemens LBP 阀/驱动参数化分类 + 公开气体定律 | 矩阵行「T2-2 LBP 基础工艺」 | 闭源（免费使用） | 只借「设备工艺参数化」组织方式；气体定律为公开物理公式，判据与状态机 100% 自有 |
| 11 | FB_DL_VacIonizerBalance | 半导体 ESC 自研线 | ESC 自研线纪律 + ANSI/ESD SP3.4 公开测试方法语义 | 矩阵行「半导体 ESC 自研（工艺专家 clean-room）」 | 公开测试方法（只读语义） | 只借「同口径自研、先拆可验收粒度」纪律与公开双判据（平衡电压/衰减时间）语义，实现 clean-room |
| 12 | FB_DL_FanVfdBypassSwap | t2-2-lbp | LBP 电机控制族（DOL/驱动参数化） | 矩阵行「T2-2 LBP 基础工艺」（R6 阀门/驱动族分层先例） | 闭源（免费使用） | 只借「命令-监视-判定」三段分层与切换互锁参数域；接触器间隔窗时序本库自有 |
| 13 | FB_DL_AxisCantileverComp | t2-4-s7-motion 次源 | S7-1500 Motion Control 示例（TO_PositioningAxis 补偿分层） | 矩阵行「T2-4 Motion Control 示例」 | 文档版权 | 只借定位轴补偿量分层注入组织；悬臂挠曲公式取材料力学公开式，clean-room |
| 14 | FB_DL_HotRunnerZoneBalance | t2-2-lbp | LBP 温控族多区编排分类 | 矩阵行「T2-2 LBP 基础工艺」 | 闭源（免费使用） | 只借多温区编排参数域组织；均衡偏差分级与孤立区判据本库自有 |
| 15 | FB_DL_SlurrySieveClogWatch | t2-6-rockwell-aoi | Rockwell AOI 应用示例「每告警带独立确认延时」三分类诊断结构 | 矩阵行「T2-6 Rockwell AOI」（R13 AhuDamperStuckDiag 同纪律） | 文档版权 | 只借设备级诊断确认窗组织方式；压差比+流量衰减双判据与分级 100% 自有 |
| 16 | FB_DL_LossInWeightFeeder | t2-2-lbp | LBP 定量族（LBP_Dosing 分类） | 矩阵行「T2-2 LBP 基础工艺」（R7 BatchDosingControl 同源先例） | 闭源（免费使用） | 只借定量族「给料速率」参数域与三段分层；失重法速率闭环与重灌装相本库自有 |
| 17 | FB_DL_UvDoseCtrl | 自研线 | 无外部源（剂量=功率×时间为公开物理定义） | 矩阵「自研线」惯例（R13 ESC 线口径） | 不适用 | 100% clean-room；灯老化补偿模型为本库自有偏离，已留档 |
| 18 | FB_DL_UltrasonicWeldCtrl | t2-2-lbp | LBP 工艺接口分层组织方式 | 矩阵行「T2-2 LBP 基础工艺」 | 闭源（免费使用） | 只借工艺接口分层（能量/振幅/时间参数域）；三模终点判据、过载保护、焊接窗口审计 100% 自有 |
| 19 | FB_DL_AxisProbeMeasCycle | t1-6-plcopen | PLCopen MC_TouchProbe 公开触发锁存语义 | 矩阵行「T1-6 PLCopen Motion」（R8 MarkPositionLatch 同源先例） | PLCopen 规范（免费） | 只借 TouchProbe 触发锁存公开语义域；趋近级联、回退、N 点评价序列本库自有 |
| 20 | FB_DL_AirShowerInterlockSeq | t2-2-lbp | LBP「命令→监视→判定」三段分层骨架 | 矩阵行「T2-2 LBP 基础工艺」（R11 PressFitStation 同骨架先例） | 闭源（免费使用） | 只借三段分层骨架；双侧门+吹淋定时序列与「吹淋不完整禁行」判据本库自有 |

## 状态列裁定（供主控收尾脚本回写矩阵）

- 无 ☐→◐ 新开组（矩阵 ☐ 组维持 0）；无整行 ◐→✔ 收口。
- ◐ 深化触及：T2-1 LGF Math（3）｜T2-1 LGF Converter（1）｜T2-1 LGF Measurement（1）｜T2-2 LBP（6）｜T2-5 Mod_PID（1）｜T2-6 Rockwell AOI（1）｜T1-6 PLCopen（2）｜T2-4 S7 Motion（1，次源）｜ESC 自研线（1）｜自研线（2）。
- T0 八组维持 8/8 ✔，余量 0，本轮 T0 = 0 件，未硬凑（R228）。

## 本轮合规声明

1. **零检索**：本轮 WebSearch 0/3，全部来源复用 `SOURCE_HUNTING_MATRIX.md` 既有源行与 RAW_NOTES R39~R55，无同源重复检索、无新源开组。
2. **闭源源隔离**：LGF / LBP / Mod_PID_Control / Rockwell AOI / S7 Motion / ESD SP3.4 等闭源或文档版权源，**只借分类组织·参数域·命名组织，实现 100% clean-room，零代码行复制**；文件头 `开源溯源 (Origin)` 字段须逐件如实标注「原创实现（参考 XXX 分类与参数域）」。
3. **开源规范源**：IEC 60204-1 / ISO 13849-1 / IEC 60751 / PLCopen / Kalman 1960 / Shoemake 1985 / 公开物理公式均为公开标准或公共领域知识，只读语义不构成版权文本。
4. **功能安全豁免**：`FB_DL_EStopDualChannel` 仅参考公开联锁逻辑结构，不声明、不实现任何安全认证功能（矩阵 T3 行铁律延续）。
5. **GPL 隔离**：本轮未触及任何 GPL/AGPL 源，无许可证传染风险；全部交付物按本库 MIT/Apache-2.0 发布口径可商用。

---

*R56 阶段二 ｜ 2026-11-20 ｜ 道莅工控代码库产品总监*
