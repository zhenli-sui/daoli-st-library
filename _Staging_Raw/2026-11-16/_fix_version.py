# -*- coding: utf-8 -*-
import re

def patch_version(sub, old, new, total_old, total_new, section):
    p = sub + '/VERSION.md'
    s = open(p, encoding='utf-8').read()
    s = s.replace('| 子库版本 / Sublibrary Version | **v%s** |' % old,
                  '| 子库版本 / Sublibrary Version | **v%s** |' % new, 1)
    s = re.sub(r'\| 组件总数 / Components \| \*\*' + str(total_old) + ' /',
               '| 组件总数 / Components | **' + str(total_new) + ' /', s, count=1)
    s = s.replace('| 库总版本 / Library Version | v2.6.0 |',
                  '| 库总版本 / Library Version | v2.7.0 |', 1)
    m = re.search(r'\n## v[0-9]', s)
    i = m.start() + 1
    s = s[:i] + section + s[i:]
    open(p, 'w', encoding='utf-8', newline='\n').write(s)
    print(sub, '->', new)

BASE = """## v1.12.0 ｜ 2026-11-16 ｜ R18 场景件第 5 轮：边沿分频 + 首出锁存 + 脉冲展宽 + 位段块搬移 4 件 / R18 Scenario Lane — 4 Signal-Shaping Components

**变更性质**：MINOR（新增 4 个组件），无破坏性变更，无迁移动作。终审 4/4 通过，机检 16 规则全 PASS。

### 新增组件（4 件）/ Added Components

| 组件 | 类型 | 一句话功能 | 关键引脚 |
|---|---|---|---|
| `FB_DL_EdgeDivider` | FB | 每 N 个上升沿输出一个单周期脉冲（双作用气缸交替动作） | `bIn` / `uDivide` |
| `FB_DL_FirstOutLatch` | FB | 16 路故障源并行输入，首个到来者锁存为唯一首出原因 | `aSrcFault` / `bReset` |
| `FB_DL_PulseStretch` | FB | 窄脉冲展宽到下游最小响应时间以上 | `bIn` / `tMinPulse` |
| `FC_DL_BitSegmentBlockMove` | FC | 段表驱动，一次调用搬移源 128 位窗口内至多 8 个位段 | `auDstBit` / `auWidth` |

### 码位台账追加（R18）/ Error Code Ledger Additions (R18)

> 本轮 4 件码位逐件映射以 `INDEX_REGISTRY.json` 的 `code_segment` 为准（已登记）；全库跨文件重叠复测 = 0（CLASH=NONE）。本子库不新增封存带。

"""

MATH = """## v1.12.0 ｜ 2026-11-16 ｜ R18 场景件第 5 轮：仿射变换 + Cpk + CRC-16 三变体 + 二维插值 4 件 / R18 Scenario Lane — 4 Calibration & Checksum Components

**变更性质**：MINOR（新增 4 个组件）+ PATCH（`FC_DL_Crc16Ccitt` 空帧越界修复 v1.0.0→v1.0.1），对外引脚零变更。

### 新增组件（4 件）/ Added Components

| 组件 | 类型 | 一句话功能 | 关键引脚 |
|---|---|---|---|
| `FC_DL_AffineTransformPoint` | FC | 旋转 → 缩放 → 平移一次合成的点变换 | `fRotDeg` / `fY` |
| `FC_DL_CpkIndex` | FC | 样本数组算 Cp/Cpk/均值/样本标准差（n−1 分母） | `uCount` / `fLsl` |
| `FC_DL_Crc16Ccitt` | FC | CRC-16 三变体，`123456789`→`29B1`/`31C3`/`2189` 对拍 | `auData` / `uLen` / `eVari` |
| `FC_DL_InterpolateTable2D` | FC | 8×8 标定网格双线性插值（温压二维补偿表） | `afGridY` / `afValue` |

### 码位台账追加（R18）/ Error Code Ledger Additions (R18)

| 码位 | 级别 | 语义 | 属主 |
|---|---|---|---|
| `16#0001_023D` | 信息 | 长度超 256 已截断，仅校验前 256 字节 | `FC_DL_Crc16Ccitt` |
| `16#0001_023E` | 信息 | 预留禁用（不得挪用） | — |
| `16#0001_0313` | 故障 | 变体枚举值非法（CASE 落 ELSE），返回 0 | `FC_DL_Crc16Ccitt` |
| `16#0001_0312` / `0314` | 故障 | 预留禁用（不得挪用） | — |

> 其余 3 件码位以注册表 `code_segment` 为准；本轮信息级总区间 `0235`~`0244`、故障级 `0306`~`0314`，全库跨文件重叠复测 = 0。

"""

ALGO = """## v1.8.0 ｜ 2026-11-16 ｜ R18 场景件第 5 轮：无扰切换 + 增益调度 + 陷波 + I2t 热模型 4 件 / R18 Scenario Lane — 4 Control Compensation Components

**变更性质**：MINOR（新增 4 个组件），无破坏性变更，无迁移动作。

### 新增组件（4 件）/ Added Components

| 组件 | 类型 | 一句话功能 | 关键引脚 |
|---|---|---|---|
| `FB_DL_BumplessTransfer` | FB | 手动末值按限斜率过渡到 PID 输出，手动期反算跟踪 | `fPidOut` / `fRateMax` / `fOut` |
| `FB_DL_GainScheduler` | FB | 按调度变量落区间输出该段一组 PID 参数 | `fScheduleVar` |
| `FB_DL_NotchFilter` | FB | 中心频率 + Q 可调二阶陷波，改参只重算系数不清状态 | `fCenterFreq` / `fQuality` / `tSampleTime` |
| `FB_DL_ThermalI2tModel` | FB | 按 d(theta)/dt = ((I/Ir)^2 - theta)/tau 累积热容量 | `fCurrent` |

> 码位以注册表 `code_segment` 为准；全库重叠复测 = 0。

"""

DEVICE = """## v0.10.0 ｜ 2026-11-16 ｜ R18 场景件第 5 轮：夹爪契约 + 平行夹爪实现 + 固态继电器加热驱动 3 件 / R18 Scenario Lane — Gripper Contract & SSR Heater Drive

**变更性质**：MINOR（新增 1 接口 + 2 实现块）。**契约要点**：接口件 `I_DL_Gripper` 不占码位（R67）；实现块的 5 个契约量只以 PROPERTY 对外、不设同名输出引脚（R66）。

### 新增组件（3 件）/ Added Components

| 组件 | 类型 | 一句话功能 | 关键引脚 |
|---|---|---|---|
| `I_DL_Gripper` | I | 夹爪能力收敛为 7 只读属性 + 4 方法（Open/Close/Release/ClearFault） | `bOpened` / `fWidth` / `eHealth` |
| `FB_DL_ParallelGripper` | FB | 驱动 → 到位确认 → 夹持力保持三段动作，含超时与空夹判定 | `bCmdClose` / `bCloseFeedback` / `fForceSetpoint` |
| `FB_DL_SsrHeaterDrive` | FB | 0~100 % 功率需求转周期 PWM 通断指令，含占空比足量而不升温的判定 | `fPowerDemand` |

> 码位以注册表 `code_segment` 为准；接口条目为空（R67）；全库重叠复测 = 0。

"""

MOTION = """## v0.10.0 ｜ 2026-11-16 ｜ R18 场景件第 5 轮：跟随误差监控 + 同步停 + 背隙补偿 3 件 / R18 Scenario Lane — 3 Axis Protection Components

**变更性质**：MINOR（新增 3 个组件）+ PATCH（`FB_DL_BacklashCompensator` 学习率下限常量与声明域对齐 v1.0.0→v1.0.1）。

### 新增组件（3 件）/ Added Components

| 组件 | 类型 | 一句话功能 | 关键引脚 |
|---|---|---|---|
| `FB_DL_AxisFollowingErrorMonitor` | FB | 指令/实际位置快照算跟随误差并三级判定 | `fSetPosition` |
| `FB_DL_AxisSynchronizedStop` | FB | 按固定减速度斜坡生成停车指令序列并预估停止距离 | `bExecute` |
| `FB_DL_BacklashCompensator` | FB | 换向瞬间叠加方向性补偿量，EWMA 自学习背隙 | `fCmdPosition` / `fBacklash` / `bAutoLearn` |

> 码位以注册表 `code_segment` 为准；全库重叠复测 = 0。

"""

PROC = """## v0.10.0 ｜ 2026-11-16 ｜ R18 场景件第 5 轮：五步换产顺控 + 停机原因分类 2 件 / R18 Scenario Lane — Changeover Sequence & Downtime Classifier

**变更性质**：MINOR（新增 2 个组件）+ PATCH（`FB_DL_ChangeoverSequence` 失能路径漏清放行镜像修复 v1.0.0→v1.0.1）。

### 新增组件（2 件）/ Added Components

| 组件 | 类型 | 一句话功能 | 关键引脚 |
|---|---|---|---|
| `FB_DL_ChangeoverSequence` | FB | 停机→排空清洁→配方装载→参数下发→首件 五步可确认顺控，步内超时重装 | `bStart` / `tStepTimeout` / `bReadyForProduction` |
| `FB_DL_DowntimeClassifier` | FB | 停转时抓首个动作的原因源，给出停机原因序号与时长 | `bEnable` |

> 码位以注册表 `code_segment` 为准；全库重叠复测 = 0。

"""

patch_version('DL_Base', '1.11.0', '1.12.0', 59, 63, BASE)
patch_version('DL_MathData', '1.11.0', '1.12.0', 103, 107, MATH)
patch_version('DL_Algo', '1.7.0', '1.8.0', 28, 32, ALGO)
patch_version('DL_Device', '0.9.0', '0.10.0', 50, 53, DEVICE)
patch_version('DL_Motion', '0.9.0', '0.10.0', 18, 21, MOTION)
patch_version('DL_Process', '0.9.0', '0.10.0', 26, 28, PROC)
