# RAW_NOTES R81 — 来源表（2026-11-24）

通道：`codeload.github.com/<owner>/<repo>/tar.gz/refs/heads/{main|master}`（整仓，零 REST 配额）。
落盘：`C:\Library\_Staging_Raw\2026-11-24\r81\*.tgz` → 解包 `x_*`（只解 ST/LICENSE/README 后缀，省时）。

## 来源表（12 条，全 MIT）

| 源 | 许可 | 提取点 | 入队名 | tier |
|---|---|---|---|---|
| CGainsWorks/plc-cip-batch-control `plc/fb/FB_CipPhase.st` | MIT | 电导率增量+回流温度+流量三判据验收、xInSpec/保压达成 | FB_DL_CipPhaseAcceptance | green |
| 同上 `plc/fb/FB_UnitStateMachine.st` | MIT | ISA-88 命令优先级矩阵（abort 抢占 + tAbortSettle） | FB_DL_UnitStateCommandMatrix | green |
| 同上 `plc/fb/FB_Totaliser.st` | MIT | 速率积分 + 死区截断（化学品/水量分摊） | FB_DL_CipChemicalTotaliser | green |
| 同上 `plc/fb/FB_Pump.st` | MIT | 启动反馈超时互锁 + xInterlockOk 串联 | FB_DL_CipPumpFlowInterlock | green |
| sulemanali5760/twincat3-hrl-rbg-library `Units/FB_Srm.TcPOU` | MIT | 三轴顺序互锁、伸叉前 Row/Col 就位、jog 互斥 | FB_DL_StackerCraneAxisSeq | green |
| 同上 `Rack/FB_Rack.TcPOU` | MIT | 货位占用位图 + 双深位配对 + reserve 预占 | FB_DL_RackSlotOccupancyMap | green |
| 同上 `Machine/FB_Hrl.TcPOU` | MIT | 巷道站台预留/出库允许/门禁联锁 | FB_DL_AisleTrafficInterlock | green |
| 同上 `Safety/FB_SafetyInterface.TcPOU` | MIT | 安全门/区域/STO → bDriveEnable/bRestartLock 许可链 | FB_DL_SrmSafetyZoneGate | green |
| 同上 `Performance/F_TravelTime.TcPOU` | MIT | 梯形速度走行/提升时间（FEM 9.851） | FC_DL_SrmTravelTimeEstimate | green |
| 同上 `Performance/F_DoubleCycleTime.TcPOU` | MIT | 复合循环工时与单循环比（WCS 排程） | FC_DL_DoubleCycleTimeEstimate | green |
| 同上 `Mfr/FB_TelegramCodec.TcPOU` | MIT | WCS 报文 帧头/长度/偏移 编解码 | FB_DL_WmsTelegramCodec | green |
| 同上 `Config/FB_HrlConfig.TcPOU` | MIT | 货架几何配置校验 + 容量推导 + sError | FB_DL_RackGeometryConfigCheck | green |

## 有效仓但 0 增量

| 源 | 许可 | 原因 |
|---|---|---|
| rruiter87/TcControl（11 ST） | MIT | PidController/Signal/IIR 与在册 FB_DL_LowPassFilter/FB_DL_SecondOrderFilter/FB_DL_PidController 语义同族 → 语义邻件拒 |
| milanlazov/twincat-dual-axis-coordinator（8 ST） | MIT | FB_AxisController/FB_AxisDualDrive 与在册 FB_DL_GantrySyncAxis/FB_DL_AxisDualFeedbackGuard 同义 → 拒；FB_InputEdgeDetection 与 FB_DL_DualEdgeTrig 同义 |

## 拒收

| 源 | 原因 |
|---|---|
| NewConsTiio/PLC-Automatic-Storage-Retrieval-WarehouseSystem | Apache-2.0 合规，但 78MB 包内 **0 个文本 ST 块**（TIA 二进制工程）→ 无可抽签名，拒收 |
| VikneshRM/Siemens-plc-conveyor-automation | MIT，但仓内仅 README（2KB），**无任何 ST 文件** → 拒收 |

## 命令留痕
搜索（search API，3 组×2 批，均 200）：`conveyor+plc`(390)→ 命中 VikneshRM；`warehouse+plc`(62)→ NewConsTiio；
`codesys+library`(94) / `twincat+library`(156) → 命中 TcControl、dual-axis；
`cip+clean+plc`(2) → ★CGainsWorks；`structured-text+plc+library`(13) → ★sulemanali5760。
`shuttle+warehouse+plc` / `vacuum+ejector+plc` / `compressor+station+plc+structured` 均 total_count=0。
