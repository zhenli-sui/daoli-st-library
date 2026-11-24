# RAW_NOTES R60（2026-11-21 · 固化批次轮）

> 本轮 **WebSearch 0/3**（零检索轮）：12 件全部复用 `SOURCE_HUNTING_MATRIX.md` 既有源行与既有 `RAW_NOTES_R52~R59` 的域语义留痕，无 ☐→◐ 新开组。合规三铁律全程遵守：① 闭源源只借分类/参数域/命名组织；② GPL/AGPL 只读思想不入码；③ 本文件逐件留痕来源/许可证/提取点。

## 逐件来源与提取点

| 组件 | 源标签 | 源与许可证 | 提取点（只取语义，不取代码行） |
|---|---|---|---|
| FC_DL_SearchMinMaxDint / Udint | t2-1-lgf-math | 西门子 LGF「Math」极值检索域分类（闭源，只借域划分与参数域：nCount 有效前缀 + 索引同出） | 域语义「单遍扫描同时出极值与索引」；实现 clean-room（整数域无 NaN，无效哨兵口径为道莅自定 DL_SMM_INVALID / _U） |
| FB_DL_RolloverCounterUdint | t2-1-lgf-counter | LGF「Counter」计数组域语义（闭源） | 模差求增量、回绕脉冲、重试/预置参数域；64 位宽域累加与半域可疑判据为自研 |
| FB_DL_ReqAckHandshake | self-std | 公开时序语义（无第三方代码） | 请求-应答-重试三段式 + R239 双窗配比约束（tAck > tRetry > 0）为道莅自研范式 |
| FC_DL_BitFieldExtractLword | t2-1-lgf-bitlogic | LGF「BitLogic」位域提取域分类（闭源） | 「起始位 + 位宽 + 扩展模式」参数域；掩码桥接法（避 64 位移位未定义行为）为自研 |
| FC_DL_Affine2DChain | t2-1-lgf-math | LGF「Math」几何变换域分类（闭源） | 齐次矩阵串联语义；三维数组传参 + 逐级委托 `FC_DL_Affine2DCompose`（库内复用）为自研 |
| FC_DL_ThdCalc | self-std | 公开电能质量语义（IEEE 519 概念层，无代码） | THD = √Σh²/\|h₁\| 公开定义；非有限双判据与三件套置码按 R258 自研 |
| FB_DL_InputShaperZv | self-std | 公开控制理论（Singer & Seering ZV 整形，公开文献语义） | ZV 双脉冲幅值/时延公式；实现 clean-room，禁抄任何厂商运动库 |
| FC_DL_InterpolateTable3D | t2-1-lgf-math | LGF「Math」查表插值域分类（闭源） | 「非等距轴向 + 边界钳位不外插」参数域；trilerp 权重构造为自研 |
| FB_DL_ValveTerminalDiag | t2-6-rockwell-aoi + t2-2-lbp | Rockwell AOI 阀岛诊断（闭源）/ LBP「命令-监视-判定」三段分层 | 诊断分类域（开路/短路/未定型）+ 三段分层组织；去抖与隔离逻辑 clean-room |
| FB_DL_AxisCmdArbiter | t1-6-plcopen | PLCopen 运动控制接口语义（规范公开，非代码） | 「命令源身份随命令字同行」语义；优先级数值与降级双通道一致为自研 |
| FB_DL_ShiftHandoverCheck | self-std | 公开生产管理语义（无第三方代码） | 交接快照 + 清单确认闭环；R253 零长窗显式分支、R275 事件优先为自研范式 |

## 合规声明
- 零代码行复制：12 件实现均由编码侧独立编写，未查阅任何厂商源码文本，仅依据上表「提取点」列的语义级描述。
- 闭源源（LGF / Rockwell AOI / LBP / PLCopen）使用边界：**只借分类组织与参数域**，不借命名前缀、不借内部变量名、不借错误码数值。
- 拒单留痕：候选 24 → 收录 12（拒 12，50%）。按族分布：Algo 解耦/滤波/PID 3、Motion 热补偿/倍率 2、Process 灭菌/统计 2、ROADMAP 池脏项 2、其余 3。触 R228 阈值边界 → 按 R267 记族避让，下轮选题避开 Algo 解耦/滤波族与 Motion 热补偿族。

*R60 规划与狩猎 ｜ 2026-11-21 ｜ 道莅工控代码库产品总监*
