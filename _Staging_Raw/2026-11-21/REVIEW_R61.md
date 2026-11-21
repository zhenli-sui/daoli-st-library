# REVIEW_R61 五抽终审（2026-11-21 · R333 只判定不改码）

## 判定表
| 件 | 子库 | 结论 | 要点 |
|---|---|---|---|
| FB_DL_RailPowerSequence | DL_Base | **严重** | _nCnt=0 断电起步下标 -1 越界读 abRailFb[-1]；另 TON 跨轨连续计时与「单轨超时」标称不符（中） |
| FB_DL_TurretToolSelect | DL_Motion | **中** | E_DL_TurretPhase.eFault 相全库无迁入式（死相位），故障实际落 eIdle，与头注释不符 |
| FB_DL_SensorPairPlausibility | DL_Device | **中** | nTrendWin 逐拍可变时环窗残留旧窗长条目，_fRingSum 含陈旧样本，漂移均值失真 |
| FC_DL_WeightedPercentile | DL_MathData | **轻** | 段4 委托调用返回值与 bValid=>bSortOk 双写同一变量，三平台求值序歧义 |
| FB_DL_LineClearanceVerify | DL_Process | **轻** | 码 3036 头注释「请求时残留非零」与实现「残留>限逐拍提示」口径漂移，默认限 0 全程报 |

七红线快扫：五件均零 GVL/%I/%Q、纯 IEC、TON/R_TRIG 段 0 无条件刷新、ENUM+CASE ELSE 兜底、双语同行注释齐、R272 浮点入参逐个点名（SensorPair 四参 / WeightedPercentile fP+权向量全量）、R271 三族开闭词配对 ✔、R216 分工声明齐（SensorPair↔DriftBaseline 双向互引 ✔）。安全相输出清零：五件✔（SensorPair 故障相冻结快照合规 R273）。

## 缺陷明细
| # | 件 | 级 | 定位 | 成因 | 修法 | 引 |
|---|---|---|---|---|---|---|
| D1 | RailPowerSequence | 严重 | 段3 eIdle rtOff 分支 `_nStep := DINT(_nCnt)-1` | 未上电即断电（_nCnt=0）→ 起步 -1，RampDn 内 `abRailFb[_nStep]` 越界读 | `IF _nStep < 0 THEN _nStep:=0` 或空轨直接 _bDone 迁回空闲 | 越界红线 |
| D2 | RailPowerSequence | 中 | 段0 tonStep IN=_bStepGo 驻留派生 | 标称单轨超时，实际整段时序连续计时，轨间不复位，慢反馈误锁 0643 | 每轨反馈到沿后复位计时（IN 串单轨驻留位） | 头注释一致性 |
| D3 | TurretToolSelect | 中 | E_DL_TurretPhase.eFault 迁入式缺席 | 段4 eIdle/eMoving 故障出口均迁 eIdle，eFault 恒不可达（死相位） | 补 `_bFault→迁 eFault` 迁移闸，或删相并订正头注释 | R274 迁移完备性 |
| D4 | SensorPairPlausibility | 中 | 段3 _fRingSum/_afRing/_nHead | 窗长缩小后旧条目残留在和内，均值除子用新 _nUse，漂移判据失真 | 窗长变更沿清环窗与和，或按有效区求均值 | 边界二 |
| D5 | WeightedPercentile | 轻 | 段4 `bSortOk := FC(...bValid => bSortOk...)` | 返回值与输出映射双写同一局部量，求值序方言差异 | 删 bValid=> 映射或改独立变量 | R66 码随属主 |
| D6 | LineClearanceVerify | 轻 | 段5 3036 判据 | 头注释语义「请求拍残留非零」≠ 实现「_uResidue>nResidueMax 逐拍」 | 订正头注释或改请求拍单点判据 | R285 口径 |

## 挂 R62 返修清单
D1（严重，首位）→ D3 → D2 → D4；D5/D6 轻项随批顺带。返修后 D1/D2/D3 须补终审复扫。
