# RAW_NOTES R52（2026-11-20 · 零检索轮 · 20 目标来源留痕）

## 0 零检索声明

本轮为**零检索轮**：WebSearch = **0 / 3**（指令硬约束「禁止 WebSearch，全部复用既有台账行」）。**未从任何仓库获取新代码**，未下载任何源文件，`_Staging_Raw\2026-11-20\` 下无本轮原始码备份（本轮无原始码）。20 个目标全部为**矩阵既有 ◐ 行语义派生 + ROADMAP 未勾条目认领**，实现一律 clean-room 独立编写（道莅标准 `.st`，无第三方代码行）。

## 1 三条合规铁律复述（`SOURCE_HUNTING_MATRIX.md` §0，本轮逐条执行）

1. **只借骨、不抄肉**：闭源源（Siemens LGF V5.3.0 / LBP V2.7 / S7-1500 Motion 示例 / Rockwell AOI / 三菱欧姆龙手册）**仅借鉴功能分类体系、接口参数域定义与命名组织方式**；实现、注释、结构一律 clean-room 独立编写，**零代码行、零 DB 结构、零注释原文复制**。
2. **许可证隔离**：GPL / AGPL 源（OpenPLC、Beremiz、MatIEC）**只读算法思想，禁止复制任何代码行**，防许可证传染（本库按 MIT / Apache-2.0 发布）；EPL / Apache / MIT 源（TcOpen、CODESYS Forge 免费库）可借鉴结构并在文件头致谢；OSCAT 为免费但需致谢口径，本库按「参考函数清单与参数域」处理。
3. **来源留痕**：每件 `.st` 头注释 `开源溯源 (Origin)` 字段如实标注「原创实现（参考 XXX 分类与参数域）」；本文件即本轮留痕台账，含组名 / 语义提取点 / 许可证结论。

> 本轮 20 件的合规结论：**19 件「闭源-分类借鉴 / 原创实现」＋1 件纯自研（`FC_DL_WrapIndexNeg`，源自本库 R193 环窗族缺陷治理）**；无 GPL/AGPL 接触，无商用限制风险。

## 2 目标 → 矩阵台账行回指（逐件）

| # | 组件 | 分类 | 来源标签（矩阵行/组） | 语义提取点（只此，不含实现） | 许可证结论 |
|---|---|---|---|---|---|
| 1 | `FC_DL_BitCountOnes` | Base | `t2-1-lgf` §2 Bit Logic Operations（矩阵 L73 组） | 组内「位测试/计数」粒度：popcount 属该组未覆盖的横向重载位 | 闭源→只借分类，可商用 |
| 2 | `FC_DL_WrapIndexNeg` | MathData | **纯自研线**（R193 环窗族治理，非矩阵行） | 源自本轮裁决 A 实测：环窗下标旋转需统一归正函数 | 原创，MIT |
| 3 | `FC_DL_LogDomainNormalize` | MathData | `t1-1-oscat-basic` Math 组（矩阵 L37 行） | OSCAT 数学组含对数/衰减族；只借「对数域映射」功能分类 | 免费需致谢→只借分类 |
| 4 | `FC_DL_PriorityEncodeWord` | Base | `t2-1-lgf` Bit Logic Operations | 组内「置位位定位」语义粒度（首位检索），非代码 | 闭源→只借分类，可商用 |
| 5 | `FC_DL_ZnTune` | Algo | `t2-5-modpid`（矩阵 L57 行，R34/R41/R44 三次深化） | ModPID 手册「整定方法」参数域：Ku/Tu → Kp/Ti/Td 三口 | 文档版权→只借参数域 |
| 6 | `FB_DL_SchmittTriggerGap` | Base | `t2-1-lgf` Comparator Operations（矩阵 L77 组） | 组内「限值/区间」粒度 + 双阈值滞环语义 | 闭源→只借分类 |
| 7 | `FB_DL_EdgeIntervalMeter` | Base | `t2-1-lgf` Date and Timer Operations（L75 组） | 组内「脉冲/周期」语义：周期-占空比-抖动测量三出口 | 闭源→只借分类 |
| 8 | `FB_DL_AdaptiveDeadbandZone` | Algo | `t2-5-modpid`（L57） | ModPID「死区」参数域：死区随噪声带宽自适应的语义定位 | 文档版权→只借参数域 |
| 9 | `FB_DL_DerivativeNoiseWeight` | Algo | `t2-5-modpid`（L57） | ModPID「微分作用/滤波」参数域：Kd 降权语义 | 文档版权→只借参数域 |
| 10 | `FB_DL_ControlOutputSlewWatch` | Algo | `t2-1-lgf` Measurement 组（L80 附近测量子组） | 组内「测量/监视」粒度：控制输出速率监视（诊断型） | 闭源→只借分类 |
| 11 | `FB_DL_PidParamDriftAudit` | Algo | `t2-3` 编程与风格指南（矩阵 L55 行） | 风格指南「参数集/多实例一致性」组织方式 → 漂移审计语义 | 文档版权→只借组织方式 |
| 12 | `FB_DL_BrakeResistorThermal` | Device | `t2-6-rockwell-aoi`（矩阵 L59 行，R42/R44/R46 深化） | AOI 设备封装粒度：变频器附属元件（制动电阻）热模型参数域 | 文档版权→只借粒度 |
| 13 | `FB_DL_PressureSwitchChatter` | Device | `t2-8` NAMUR NE107 + ISA-18.2（矩阵 L61 行，NE107 六态已四次入册） | NE107 诊断分级映射：抖动→「需要维护」档语义 | 公开规范→可借鉴 |
| 14 | `FB_DL_MeterPulseLossDetect` | Device | `t1-3-oscat-network`（矩阵 L39 行）+ 计量语义 | 网络/诊断组「计数器丢失/帧丢失」判据 → 脉冲丢失类比 | 免费需致谢→只借判据思想 |
| 15 | `FB_DL_HeatTraceCircuitMon` | Device | `t2-8` ISA-18.2 / ISA-88（矩阵 L61）+ `t2-1-lgf` Technology | 回路一致性判据（电流存在 × 温升响应）语义组合 | 公开规范/闭源分类→可商用 |
| 16 | `FB_DL_AxisJerkLimitCheck` | Motion | `t1-6-plcopen` Motion（矩阵 L43 行，R41/R44/R46 深化） | PLCopen 运动接口「限制类」参数域（jerk/acc/dec 三口）+ 状态机闸 | PLCopen 规范免费→可借鉴 |
| 17 | `FB_DL_AxisHomeRepeatVerify` | Motion | `t1-6-plcopen` + Motion（homing 状态机） | MC_Home 系列「回零完成位 + 位置反馈」接口契约 → 重复性统计 | PLCopen 规范免费 |
| 18 | `FB_DL_AxisSoftLimitPredict` | Motion | `t2-4-s7-motion`（矩阵 L56 行，R38/R44/R46 深化） | S7 TO_PositioningAxis「软限位/减速」参数域 + 预判语义 | 文档版权→只借参数域 |
| 19 | `FB_DL_MakeupWaterDosing` | Process | `ROADMAP.md` L501（未勾真缺口，P2，水务/暖通） | 无矩阵行：自研 clean-room，复用 `FB_DL_Integrator` 累计契约 | 纯原创，MIT |
| 20 | `FB_DL_DieBinCounter` | Process | `ROADMAP.md` L647（未勾真缺口，P2，半导体后道） | 无矩阵行：自研 clean-room，复用 `FB_DL_BidirectionalCounter` + `FC_DL_LimitClassify` | 纯原创，MIT |

## 3 复用依赖（跨件契约，显式列出以防内联重复实现）

- 全 20 件 **零 GVL / 零 VAR_EXTERNAL / 零 %I·%Q·%M 地址**，外部数据只经 `VAR_INPUT`/`VAR_OUTPUT`/`VAR_IN_OUT` 或 `I_DL_` 接口注入。
- 依赖方向单向：Base/MathData 件不引用任何 Level 1 类型；Algo 件只引用 Base/MathData；Device/Motion/Process 件可引用 Level 0~1。
- 重点复用契约：`FB_DL_Integrator`（#19 流量累计）、`FB_DL_BidirectionalCounter` + `FC_DL_LimitClassify`（#20 分箱分档）、`FB_DL_RingBufferLReal` + `FC_DL_TrendSlopeCalc`（诊断族趋势，**须按时间序读出**，见 plan 裁决 C）。
- 新件 `FC_DL_WrapIndexNeg`（#2）供 #6/#7/#13 的窗口下标复用，**禁止在三处内联手写 MOD 归正**。

## 4 反证与拒单记录（双查实测，R52 撞名审查）

本轮「全库同名 + 同义邻件」双查（`INDEX_REGISTRY.json` 925 名全量比对）**拒单 9 项**，全部因已在册：

| 拒单候选 | 命中存量件 | 处置 |
|---|---|---|
| `FC_DL_PolyEvalHorner` | `FC_DL_PolyEvalHorner` | 拒（同名） |
| `FB_DL_SmithPredictor` | `FB_DL_SmithPredictor` | 拒（同名） |
| `FB_DL_CrossLimitSelect` | `FB_DL_CrossLimitSelect` | 拒（同名） |
| `FB_DL_FanBeltSlipDetect` | `FB_DL_FanBeltSlipDetect` / `FB_DL_FanBeltSlipDiag` | 拒（同名 + 同义邻件双命中） |
| `FB_DL_PulseStretchMin` | `FB_DL_PulseStretch` | 拒（同义变体） |
| `FB_DL_PumpCavitationWatch` | `FB_DL_PumpCavitationGuard` | 拒（同义变体） |
| `FB_DL_ValveCharInverse` | `FB_DL_ValveCharacteristic` | 拒（同义变体） |
| `FB_DL_SolenoidCurrentProfile` | `FB_DL_SolenoidCoilHealth` | 拒（同义变体） |
| `FB_DL_ChillerYearWinStart` / `FB_DL_ReactorYearWinClean` | 均已注册 | 拒 + 记三向差额（plan §0.1） |

> 拒单 9 / 候选 29 = 31% 拒单率，`FB_DL_ChillerYearWinStart` 等 2 例同时暴露 ROADMAP 未勾但已存在 → R53 回写。

## 5 边界条件清单（每件必备的真实工况边界，编写时逐条落测试向量）

- #1/#4：全 0 位串（哨兵 0）、全 1 位串（溢出计数 = 位宽）、位宽边界（BYTE 8 / LWORD 64）。
- #2：`i = 0`、`i = -1`（→ depth）、`i = depth`、`depth = 1`（退化为恒 0）。
- #3：输入 ≤ 0（定义域外→错误码 + 输出钳 0）、底数 = 1（除零守卫）、上限溢出。
- #5：Tu ≤ 0（拒算）、Ku 极值、输出 PID 三参上下限钳位（Ki=Kp/Ti，Ti=0 防除零）。
- #6：阈值上下限倒置（自动交换 + 告警位）、迟滞带 = 0（退化单阈值）。
- #7：无沿（超时→周期出口保持末值 + 有效位 FALSE）、抖动（翻转次数统计）、首沿配对缺失。
- #8/#9：噪声带宽为 0（死区钳下限）、Kd 降权至 0 下限、滤波器未收敛期禁用降权。
- #10：输出恒定（速率 0 → 不判振荡）、步进（单次大跳变区别于持续振荡）。
- #11：基准快照缺失（首拍自学习基线）、参数浮点比较用容差（禁 `=`）。
- #12：电阻温升 > 上限（锁存 + 冷却计时）、I²t 累计溢出钳位、断电后热状态不保持（明示）。
- #13：窗口内翻转 0 次（正常）、满窗无窗口样本（数据不足不判）、衰减系数 = 0 守卫。
- #14：指令脉冲 0 且反馈 0（停机态不判丢脉冲）、单周期多脉冲、速率超量程。
- #15：电流有而温升无（断缆）/ 温升有而电流无（串流误接）/ 两者皆无（未投用）。
- #16：jerk = 0（非法）、单段限值上调（需二次确认位）、越限钳位后指令与实际差镜像。
- #17：回零次数 < 3（样本不足不判）、标准差 = 0（完美重复）、单次离群（用 MAD 而非 3σ）。
- #18：速度 = 0（不预判）、减速度 = 0（除零守卫→报配置错）、已在限位内但方向朝外（仍须预警）。
- #19：流量累计 = 0（不投加）、加药比 = 0（关断）、累计溢出回绕。
- #20：满箱阈值 = 0（配置错）、切箱请求与满箱同拍（优先级：满箱优先）、清箱未确认（保持拒收）。

## 6 本轮不做（明确排除，防越界）

- 人格文件微调（第 3 次顺延，R53）。
- 7 条三向差额的 ROADMAP 勾选回写（R53 首位）。
- `FB_DL_ValveSeatLeakWatch` r1.0.1 落地（本轮只出裁决与修法，编码留 R53 批内首件）。
- 全库 `_aX[` 头游标写入模式的机检规则化（R53）。
