# RAW_NOTES R86（2026-11-24 夜轮 · 四族 + 四复杂件定向）

## 1. 真跑命令与退出码
```
python C:/Library/_tools/oss_harvest.py --search --max-repos 3 --max-files-per-repo 12
EXIT_CODE=0
  HTTP 422 .../search/repositories?q=org:PLCnext-Community   （已知缺陷，R74/R84 已记）
  repo OttoMeister/Siemens-Tia-Portal-PID-Controller  WTFPL   yellow  files=8/8  added=1
  repo RWTH-EBC/AixOCAT                               MIT     green   files=12/12 added=1
  repo NathanLi/iOSCategoryPropertyDynamicSupport     None    yellow  files=0     added=0
TOTAL candidates added: 2
```
**两行均为存量重复**（VAR_INPUT 为 SIG 正则误捕关键字的垃圾名；E_SMStatus 是 R73 已入队行），已按规矩「先备份再标记」：
`candidate_queue.jsonl.backup_R86_pre.jsonl` 已存在，两行加 `"dropped": true` + `dropped_reason`，**未删行**。

## 2. 定向补充检索（code search + codeload）
查询（只读 token，6 条）：`"FUNCTION_BLOCK" valve AND seat AND stroke`(18)、`gear AND ratio AND sync`(641)、
`flying AND shear`(15)、`reactor AND jacket`(16)、`unit AND conversion AND factor`(2020)、`bit AND shift AND mask`(4160)。
其中 3 条宽查询 top-20 命中几乎全为 C/C++/Rust 标识符噪音（与 R85 结论一致）。

| 仓 | SPDX(API) | 实际 LICENSE | tier | ST 数 | 处置 |
|---|---|---|---|---|---|
| **simatic-ax/LAxisCtrl** | NOASSERTION | Siemens Royalty-free 1.4（闭源文档类） | 黄 | 58 | **有效出料 10 条骨头** |
| **mod-bee/modbee-openplc** | NOASSERTION | **AGPL-3.0（LICENSE 正文）** | **红** | 143 | 零代码入队，**本地 tar.gz 已删除**，仅登记思想 |
| Chenjie1002/Lee_Workshop | None | — | unknown | 0 | 拒收（无证 + 0 ST） |
| brentjm/chemical-process-digital-twin | None | — | unknown | 0 | 拒收（反应釜夹套为 Python 仿真） |
| DavidWenzler/reAM250 | NOASSERTION | — | 黄 | 0 | 拒收（0 ST） |
| Aneesh495/gantry | MIT | — | 绿 | 0 | 拒收（0 ST） |
| Beckhoff-USA-Community/SPT-Libraries | — | — | — | — | codeload 取包失败（非 gzip），不计入 |

## 3. 入队 10 条（全黄，code_excerpt 全为 null）
`FB_DL_AxisErrorWordSplit / AxisStatusWordSplit / AxisWarningWordSplit / GearInPosPhaseSeq / GearInVelPhaseSeq /
GearOutPhaseSeq / PhasingAbsPhaseSeq / CamInProfileGate / AxisFastStopParamCheck / AxisDiagStructSnapshot`

借骨点：Execute→StartSync→InSync 三相；RatioNum/Den 比例域；-1.0 = 用轴默认动态值哨兵；SyncDirection=3 最短路径；
`WORD#16#8002` 单一错误码惯例；位域逐位语义拆分字段表。**实现一律 clean-room**，文件头须致谢 `simatic-ax/LAxisCtrl` 并标提取点。

## 4. 四族 + 四复杂件判断（诚实计数）
| 族 | 开源可借鉴点 | 可借码比例 |
|---|---|---|
| A 位运算/位域 | ✔ 真命中：错误字/状态字/警告字三件「逐位语义拆分 + reserved 位」范式；位序随固件漂移需自加版本闸 | **0%**（黄区，字段语义可借，代码不可借） |
| B 工程单位换算 | ✘ 本轮 0 命中（`unit AND conversion AND factor` 2020 命中 top-20 全非 ST）；registry 已有 ExternalEncoderScaler/ChamberTempUnitBank 等 120 件覆盖 | **0%** |
| C 信号滤波/限幅 | ✘ 0 新命中；registry 已饱和（AdaptiveLmsFilter/BiquadFilter/ControlOutputSlewWatch/99 件） | **0%** |
| D 阀门/执行器诊断 | ✘ 绿区 0；唯一实件 modbee-openplc(阀位-阀座-行程三参) 为 AGPL 红区 → 只取「分级判据结构」思想，代码零入队 | **0%** |
| X1 伺服电子齿轮同步 | ✔ 相序 + 比例域 + 同步位置锚点 + SyncDirection 语义（4 件） | 0%（接口骨） |
| X2 压机多段压力曲线 | ✘ 0 命中（`press` 类 registry 有 HydroPressRampSeq/CalenderRollPress，semantic 已覆盖） | 0% |
| X3 反应釜升温保温 | ✘ 0 命中（唯一命中仓为 Python 仿真，无证拒收）；registry 已 8 件 Reactor* 覆盖 | 0% |
| X4 贴标机飞剪同步 | ✘ `flying AND shear` 15 命中 top-20 内 0 个 ST（DeLuAle 无证）；registry 有 BagFeedDancerSync/BilletShearGaugeSeq | 0% |

## 5. 语义邻域与合规
- 语义邻件：**5/10 相邻** —— GearInPosPhaseSeq/GearInVelPhaseSeq/GearOutPhaseSeq 邻 `FB_DL_GearInPhaseAlign`/`FB_DL_ElectronicGear`/`FB_DL_GearDecouple`；
  CamInProfileGate 邻 `FB_DL_CamPhaseTrim` 系；**5/10 为新语义**（三件位域拆分 + 快停参数域 + 诊断结构体）。相邻件建议编码席优先做「与在册件的差异闸」再决定是否收编。
- 红区：**1 仓（AGPL-3.0）零代码入队**，本地落地包已删除；黄区 10 条 `code_excerpt=null`；unknown 2 仓零代码入队。

## 6. 队列
采集前 215 行（green 163 / yellow 52）→ 采集后 227 行，标 dropped 2 行 → **有效 225 条（green 163 / yellow 62 / red 0）**，净增 **+10**（全黄）。
按 300 件/日 × 50% ≈ **1.5 天**余量，≥200 无红警，但**绿区连续两轮零增量**需在下一轮解。
