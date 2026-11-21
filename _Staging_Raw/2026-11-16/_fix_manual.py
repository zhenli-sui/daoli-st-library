# -*- coding: utf-8 -*-
import re

def add_manual(path, block):
    s = open(path, encoding='utf-8').read()
    idx = s.rfind('*Last updated')
    if idx == -1:
        s = s.rstrip('\n') + '\n\n' + block
    else:
        # 插在末段说明之前
        start = s.rfind('\n---', 0, idx)
        pos = start if start != -1 and start > len(s) * 0.5 else idx
        s = s[:pos] + '\n' + block + s[pos:]
    open(path, 'w', encoding='utf-8', newline='\n').write(s)
    print('manual ok', path)

H = '### R18 新件接口一览（2026-11-16 追加）/ Round 18 Interface Summary\n\n'

B = H + ('| 组件 | 一句话功能 | 关键引脚 |\n|---|---|---|\n'
 '| `FB_DL_EdgeDivider` | 每 N 个上升沿出一个单周期脉冲，供双作用气缸交替动作 | `bIn` / `uDivide` / `bOut` |\n'
 '| `FB_DL_FirstOutLatch` | 16 路故障源首出锁存，只认第一个到来的原因 | `aSrcFault` / `bReset` / `uFirstOutNo` |\n'
 '| `FB_DL_PulseStretch` | 窄脉冲展宽到下游最小响应时间以上 | `bIn` / `tMinPulse` / `bOut` |\n'
 '| `FC_DL_BitSegmentBlockMove` | 段表驱动搬移源 128 位窗口内至多 8 个位段 | `auDstBit` / `auWidth` / `auSrcBits` |\n\n'
 '> 用法要点：`FirstOutLatch` 的输入端必须一次性给全 16 路（未用的置 FALSE），否则「首出」语义失真；`PulseStretch` 的 `tMinPulse` 取下位执行机构最小响应时间的 1.5 倍。\n\n')

M = H + ('| 组件 | 一句话功能 | 关键引脚 |\n|---|---|---|\n'
 '| `FC_DL_AffineTransformPoint` | 旋转 → 缩放 → 平移一次合成的点变换 | `fRotDeg` / `fX` / `fY` |\n'
 '| `FC_DL_CpkIndex` | 样本数组算 Cp/Cpk/均值/样本标准差（n−1 分母） | `uCount` / `fLsl` / `fCpk` |\n'
 '| `FC_DL_Crc16Ccitt` | CRC-16 三变体，验收向量 `123456789`→`29B1`/`31C3`/`2189` | `auData` / `uLen` / `eVari` |\n'
 '| `FC_DL_InterpolateTable2D` | 8×8 标定网格双线性插值 | `afGridY` / `afValue` / `fOut` |\n\n'
 '> 用法要点：`Crc16Ccitt` 的 `uLen = 0` 是合法空帧（返回 init 值且 `bValid = TRUE`），不要当故障处理；`CpkIndex` 需 `uCount ≥ 2`，单样本返回故障码。\n\n')

A = H + ('| 组件 | 一句话功能 | 关键引脚 |\n|---|---|---|\n'
 '| `FB_DL_BumplessTransfer` | 手动末值按限斜率过渡到 PID 输出，手动期反算跟踪 | `fPidOut` / `fRateMax` / `fOut` |\n'
 '| `FB_DL_GainScheduler` | 按调度变量落区间输出该段一组 PID 参数 | `fScheduleVar` / `fKp` / `fKi` |\n'
 '| `FB_DL_NotchFilter` | 中心频率 + Q 可调二阶陷波，改参只重算系数、状态保留 | `fCenterFreq` / `fQuality` / `tSampleTime` |\n'
 '| `FB_DL_ThermalI2tModel` | I²t 热容量累积，输出热态系数供过载降额 | `fCurrent` / `fTheta` |\n\n'
 '> 用法要点：`BumplessTransfer` 不内联 PID（PID 输出由上层注入，避免两套积分器）；`NotchFilter` 的中心频率必须低于 0.45 倍采样频率，超了陷波会变放大器（本件已拦截并旁路）。\n\n')

D = H + ('| 组件 | 一句话功能 | 关键引脚 |\n|---|---|---|\n'
 '| `I_DL_Gripper` | 夹爪契约：7 只读属性 + 4 方法 | `bOpened` / `eHealth` / `uErrorId` |\n'
 '| `FB_DL_ParallelGripper` | 驱动 → 到位确认 → 夹持力保持三段动作 | `bCmdClose` / `bCloseFeedback` / `fForceSetpoint` |\n'
 '| `FB_DL_SsrHeaterDrive` | 0~100 % 功率需求转周期 PWM 通断指令 | `fPowerDemand` / `bSsrOut` |\n\n'
 '> 用法要点：`ParallelGripper` 的 5 个契约量（`bOpened`/`bClosed`/`bWorkpiecePresent`/`fWidth`/`bError`）只以属性对外，**不设同名输出引脚**（R66，同名成员会阻断三平台编译）；`Close(fForceSetpoint)` 的形参优先于同名引脚给定（R73）。`bValveOut` 必须由上层映射到物理点。\n\n')

O = H + ('| 组件 | 一句话功能 | 关键引脚 |\n|---|---|---|\n'
 '| `FB_DL_AxisFollowingErrorMonitor` | 跟随误差三级判定（提示 / 严重 / 断使能建议） | `fSetPosition` / `fActPosition` / `fError` |\n'
 '| `FB_DL_AxisSynchronizedStop` | 按固定减速度斜坡生成停车序列并预估停止距离 | `bExecute` / `fDecel` / `fStopDistance` |\n'
 '| `FB_DL_BacklashCompensator` | 换向瞬间叠加方向性补偿量，EWMA 自学习背隙 | `fCmdPosition` / `fBacklash` / `bAutoLearn` |\n\n'
 '> 用法要点：`BacklashCompensator` 与 `FB_DL_RollerGapAdjust`（工艺辊缝顺控）职责不重叠；首拍无历史方向时**不补偿**，否则轴会凭空跳一下；`fLearnGain` 有效域 0.01~0.5（越界钳位并置信息码）。\n\n')

P = H + ('| 组件 | 一句话功能 | 关键引脚 |\n|---|---|---|\n'
 '| `FB_DL_ChangeoverSequence` | 五步可确认换产顺控，每步独立超时、步内重装 | `bStart` / `tStepTimeout` / `bReadyForProduction` |\n'
 '| `FB_DL_DowntimeClassifier` | 停转时抓首个动作的原因源，输出停机原因序号与时长 | `bEnable` / `uReasonNo` / `tDuration` |\n\n'
 '> 用法要点：`ChangeoverSequence` 超时只置信息码并记录阻塞步号（人等确认是正常生产行为），绝不自动跳步；`bReadyForProduction` 在失能当拍清零（安全侧，v1.0.1 修复项）。\n\n')

add_manual('DL_Base/MANUAL_DL_Base.md', B)
add_manual('DL_MathData/MANUAL_DL_MathData.md', M)
add_manual('DL_Algo/MANUAL_DL_Algo.md', A)
add_manual('MANUAL_DL_Device.md', D)
add_manual('MANUAL_DL_Motion.md', O)
add_manual('MANUAL_DL_Process.md', P)
