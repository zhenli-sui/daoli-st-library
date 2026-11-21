# RAW_NOTES_R28（来源台账 · 零检索轮）

## 1 检索声明
- **本轮 WebSearch：0 次**。依据：17 件全部取自 `ROADMAP.md` 既有未勾选条目（逐条与 registry 483 个 POU 名做重名排除后仍有 **263 条可用**），语义层复用 `SOURCE_HUNTING_MATRIX.md` 已收口/◐ 组；风机相似定律为公开工程公式（公有领域），无需检索。
- **零代码行复制**：17 件 100% clean-room 自写，未复制任何上游函数体 / 符号名 / 常量名。`_Staging_Raw` 本轮**不新增源码备份目录**（无外部抓取）。
- ROADMAP **新增条目 0 条**（池充足，遵守「不扩写」纪律）。

## 2 选题过滤留痕（供下轮免重复论证）
| 动作 | 结果 |
|---|---|
| 扫 ROADMAP 未勾选行 | 314 行（含非组件类债务条目） |
| 提取 POU 名并与 registry 比对 | 已入库同名 **51 条**（ROADMAP 勾选状态滞后，非真缺件）→ 剔除 |
| 剩余可立项 | **263 条**：Process 128 / Device 59 / Motion 14 / Algo 1 / Base 1 / 其他 60（无库标签） |
| 优先序 | P0 4 条（`StringBarcodeTrace`/`WaferScanRouter`/`CartonScannerSort` 等扫码路由族，均为「复用 `I_DL_BarcodeScanner`」薄编排，本轮不取——见 §4 观察）；P1 86 条按库缺口加权 |
| 反例（明确不立） | `FC_DL_ShlDwordEx` / `FC_DL_ShrDwordEx`（ROADMAP-L948 自标「疑似与存量同义」，且 Base 已有 `ShlEx/ShrEx`）→ 不入批；DL_MathData 158 件过配，本轮 0 件 |
| Algo 池现状 | 唯一可用 P1 仅 `FB_DL_FanLawRootCalc`（L661）→ 本轮 Algo = 1 件，不是选题偏好而是池枯竭事实 |

## 3 逐件来源台账（ROADMAP 行号 + 矩阵行号）
| 序号 | 组件 | ROADMAP | 矩阵行（组） | 许可证 | 仅借鉴点 |
|---|---|---|---|---|---|
| 1 | FC_DL_FanLawRootCalc | L661 | T0（公开公式，不记矩阵行） | 公有领域（相似定律 Q∝n、p∝n²、P∝n³） | 指数化参数域；实现与钳位自有 |
| 2 | FB_DL_StepperXyzGantry | L546 | L172 T1-8 GitHub topics（stepper 线，R9/R12 已开组） | 所据仓多为 MIT/Apache，未复制 | 「接口契约 + 实现」双件范式；三轴编排自有 |
| 3 | FB_DL_StepperFeederBelt | L572 | L172 T1-8（同线） | 同上 | 间歇送料 + 色标校正的语义域；补偿逻辑自有 |
| 4 | FB_DL_CheckweighZeroTrack | L719 | L164 T1-1 OSCAT Basic（「域外行为显式化」纪律） | OSCAT 免费需致谢（零复制） | 域外保持上次有效值 + 掩码标出的写法纪律；零点窗逻辑自有 |
| 5 | FB_DL_EfEmDoorInterlockPlus | L709 | L162 T2-8 ISA-18.2（分级 / 首因）+ L169 T1-5（契约分层） | 公开规范语义，无代码 | 首因仲裁组织 + 门/阀/真空三域划分；状态机与码位自有 |
| 6 | FB_DL_LaserTabWeldTrack | L882 | L160 T2-6 Rockwell AOI（多判据 + 主判优先级） | 文档版权，clean-room | 三判据同拍与确认窗组织；掩码/阈值/码位自有 |
| 7 | FB_DL_NotchAlignSeq | L823 | L167 T1-6 PLCopen Motion（在位确认 + 超时中止纪律） | 规范语义，无代码 | 相序与超时中止纪律（R22 已沉淀）；六相实现自有 |
| 8 | FB_DL_EdgeTrimTraverse | L638 | L158 T2-4 S7 Motion（定位对象外部接口组织） | 文档版权，clean-room | 「预检先行 + 段终点停止」纪律；往复状态机自有 |
| 9 | FB_DL_NtcChannelHealth | L691 | L165 T1-2 OSCAT Building（域外行为显式化） | OSCAT 免费需致谢（零复制） | 通道掩码语义复用（不复制 `NtcTempScan` 内核）；评分模型自有 |
| 10 | FB_DL_WaferCassetteSlot | L636 | L149 T2-1 LGF Counter（饱和预置 + 复位优先级） | 文档版权，clean-room | 双向计数与饱和语义；**拒绝回绕/借位**为自有加严 |
| 11 | FB_DL_LamCtrlDualZone | L361 | L157 T2-2 LBP（命令→监视→判定三段分层） | 文档版权，clean-room | 三段分层骨架 + 双执行机构分程；差压保护与码位自有 |
| 12 | FB_DL_LaminatorVacLeakTrend | L700 | L155 T2-1 LGF Technology（变化率限幅 / 包络） | 文档版权，clean-room | 「速率 vs 基线」判据组织；基线刷新禁令自有 |
| 13 | FB_DL_ChamberPumpDownProfile | L708 | L155 T2-1 LGF Technology（同上） | 文档版权，clean-room | 分段包络 + 早停建议（不切泵）职责切分自有 |
| 14 | FB_DL_SealJawDwellTrim | L716 | L161 T2-7 PackML（相驻留语义，clean-room） | 公开规范，无代码 | 「驻留随工况整定」语义；限速→钳制次序自有 |
| 15 | FB_DL_BatchDeviationAlarm | L734 | L162 T2-8 ISA-18.2（激活/确认/清除生命周期） | 公开规范，无代码 | 生命周期三段分账 + 四档分级；首出与升 P1 自有 |
| 16 | FB_DL_InlineCheckweighGauge | L379 | L156 T2-1 LGF Measurement（窗口统计归属「测量」） | 文档版权，clean-room | 「逐件判据不平滑 / σ 满窗才判」两条纪律自有 |
| 17 | FB_DL_ChillerStagingCurve | L385 | L165 T1-2 OSCAT Building（轮值 / 分级投切纪律） | OSCAT 免费需致谢（零复制） | 分级投切与死区纪律；曲线选点算法自有 |

## 4 复用依赖核验（17 件全部依赖既有件，无前置缺口）
`FC_DL_NthRoot`、`I_DL_StepperOpenLoop`、`FB_DL_MarkPositionLatch`、`FB_DL_SoftLimitGuard`、`FB_DL_SignalStatistics`、`FB_DL_Differentiator`、`FB_DL_RateLimiter`、`FB_DL_MedianFilter`、`FB_DL_InterlockMatrix`、`FB_DL_StatusWordSegDecoder`、`FB_DL_ToleranceWindow`、`FC_DL_LimitClassify`、`FB_DL_DutyStandbyRotation`、`FB_DL_NtcTempScan`、`FB_DL_StepperZLiftMicron`（同族范式）—— **全部在 registry 中实测存在**。
口径修正留痕：registry 的 `components[].name` **只索引 POU**，辅助 `TYPE`（如 `E_DL_Ne107Status`，grep 实测 146 处引用、归属 `I_DL_DeviceHealth` 同文件）不在其中 → 依赖核验必须以 **grep 源码**为准，不能只查 registry，否则会把「已存在的枚举」判成缺失（R28 规划期曾误判一次，已当场纠正）。本轮 17 件无一条依赖该枚举，故不影响派单。
观察（留 P1，不入本轮）：扫码路由族 3 条 P0（L469/L486/L492）只是「`I_DL_BarcodeScanner` + 分道放行」的薄编排，价值密度低于本轮 17 件；建议 R29 与 `FB_DL_TrackBarcodeTrace`（L469）合并成一个「条码路由族」一次成族，而不是三件散做。

## 5 合规结论
- 17 件**全部可商用**：来源为 ROADMAP 既有条目 + 公开发布的标准/规范语义（clean-room）+ 公有领域物理公式 + 本库自有组件组合调用。
- **零 GPL/AGPL 代码接触**（OSCAT 仅作行为定义参照，未复制函数体/函数名/常量名）；无加密狗绑定；无厂商专有库依赖。
- 闭源源（T2-1/T2-2/T2-4/T2-6）只借「分类骨架 / 参数域组织 / 判据优先级」，代码、状态机、码位、引脚契约 100% 自有，与既有 27 轮口径一致。
- 溯源短语统一写「道莅 clean-room 防御性实现」；T0 件（序 1）写「IEC 61131-3 标准语义的道莅防御性实现」。
