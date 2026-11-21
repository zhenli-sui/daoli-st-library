# R12 码位占用台账 / CODE SEGMENT LEDGER (R12)

> **用途**：下一环节新组件落码前先查本表，按各节末尾「极大值摘要」顺延取号，杜绝多轮撞号返工。
> **生成日期**：2026-11-15 ｜ **数据基准**：`INDEX_REGISTRY.json`（168 条）+ 全库 `.st` 实测码位字面量 ｜ **生成脚本**：`_Staging_Raw/2026-11-15/gen_ledger_r12.py`（只读，不改库）

**口径说明**

- 码位段优先取注册表 `code_segment` 原文；注册表未登记的组件回落到 `.st` 内 `uErrorId` 字面量，前缀 `实测`，仅作占用参考、不代表已发布契约。
- 公共区不参与按件分配：`0000_xxxx`（无故障基准）、各码族 `xxxx_0000~00FF`（公共 / 预留区）、`FFFF_xxxx`（占位填充）。低带实测值单列在节末，不计入极大值。
- 号段带：`01xx` 信息级 / `02xx` 故障级 / `0Xxx` 特殊带 / `1x00` DL_Algo 按件算法带。

## 0. 结论速览 / Next Available Slots

| 目录 | 信息级已用至（本目录） | 故障级已用至（本目录） | 建议起号（信息 ／ 故障） | 码族 |
|---|---|---|---|---|
| `DL_Base` | `16#0001_0120` | `16#0001_0218` | `16#0001_0125` ／ `16#0001_021A` | 0001+0002 |
| `DL_MathData` | `16#0001_0124` | `16#0001_0219` | `16#0001_0125` ／ `16#0001_021A` | 0001+0002 |
| `DL_Algo` | `16#0002_0102` | `16#0002_1F10` | `16#0002_2001` ／ `16#0002_2010` | 0002 |
| `DL_Device` | `16#0003_0148` | `16#0003_0308` | `16#0003_0149` ／ `16#0003_0309` | 0003 |
| `DL_Motion` | `16#0004_01C2` | `16#0004_02D1` | `16#0004_01C3` ／ `16#0004_02D2` | 0004 |
| `DL_Process` | `16#0005_01C4` | `16#0005_02F2` | `16#0005_01C5` ／ `16#0005_02F3` | 0005 |

> 速览表左侧两列只给「本目录自身」极大值；右侧起号已按**码族合计**计算（`0001` / `0002` 跨目录共用），故 DL_Base 与 DL_MathData 的起号相同——取号时任选其一占位，另一方不得重复使用。
>
> DL_Algo 例外：算法件按「一件一带」独占 `Nx00` 带，带内 `01~06` 为信息级、`10` 起为故障级；共享区 `0002_01xx/02xx` 的历史占号（`0101`、`0102`、`0201`、`0301`…）实为早期算法件带码，不构成共享区耗尽。

## DL_Base（34 件）

| # | 组件名 | 码位段 | 标签 |
|---|---|---|---|
| 1 | `FB_DL_SignalDebounce` | 无（仅用公共码） | debounce, signal-conditioning, state-machine, edge-detection, industrial-io |
| 2 | `FB_DL_DualEdgeTrig` | 无（仅用公共码） | edge-detection, r_trig, pulse, counter, signal-conditioning |
| 3 | `FC_DL_BitGet` | 无（仅用公共码） | bit-manipulation, bounds-check, status-word, portability |
| 4 | `FC_DL_BitSet` | 无（仅用公共码） | bit-manipulation, pure-function, status-word, mask |
| 5 | `FC_DL_BitCount` | 无（仅用公共码） | population-count, brian-kernighan, voting, loop-guard |
| 6 | `FC_DL_PackBitsToWord` | 无（仅用公共码） | bit-packing, status-word, modbus, pure-function |
| 7 | `FB_DL_UnpackWordToBits` | 无（仅用公共码） | bit-unpacking, status-word, modbus, change-detection, invert-mask |
| 8 | `FC_DL_GrayToBinary` | 无（仅用公共码） | gray-code, encoder, bit-manipulation, width-clamp |
| 9 | `FC_DL_BinaryToGray` | 无（仅用公共码） | gray-code, encoder, bit-manipulation, inverse-function |
| 10 | `FB_DL_CycleTimeMeasure` | 无（仅用公共码） | cycle-time, performance-monitoring, statistics, delta-injection, diagnostics |
| 11 | `FB_DL_RuntimeMeter` | 无（仅用公共码） | runtime-meter, maintenance, predictive-maintenance, counter, delta-injection |
| 12 | `FB_DL_WatchdogMonitor` | 无按件码位（低带实测 16#0001_000C） | watchdog, heartbeat, toggle-interval, fault-latch, comm-diagnostics |
| 13 | `FB_DL_PulseGenerator` | 无（仅用公共码） | pulse-generator, pwm, duty-cycle, phase-state-machine, timer |
| 14 | `FB_DL_ExtendedTimer` | 无按件码位（低带实测 16#0001_000E） | on-delay, off-delay, retentive-timer, pulse, state-machine |
| 15 | `FB_DL_AlarmManager` | 无（仅用公共码） | alarm-management, priority-arbitration, first-out, isa-18.2, interlock |
| 16 | `FB_DL_StepSequencer` | 无按件码位（低带实测 16#0001_000B） | step-sequencer, sfc, grafcet, step-timeout, single-step |
| 17 | `FB_DL_DutyStandbyRotation` | 无按件码位（低带实测 16#0002_0007~0008） | lead-lag, runtime-balancing, duty-cycle, pump-scheduling, wear-leveling, lbp-basic-process, lead-lag |
| 18 | `FB_DL_InterlockMatrix` | 无（仅用公共码） | interlock, first-out-tracking, safety-trip, bit-matrix, latched-fault, isa18-2, lgf-bitlogic |
| 19 | `FB_DL_RedundantSwitch` | 无按件码位（低带实测 16#0002_0006） | redundancy, failover, bumpless-transfer, deviation-monitor, arbitration, lgf-comparator, redundancy |
| 20 | `FB_DL_TwoHandSafety` | 无（仅用公共码） | two-hand-control, safety-interlock, simultaneity-window, hold-to-run, fail-safe, iec60204, iso13851 |
| 21 | `FC_DL_DayOfWeekCalc` | 实测 16#0001_0201（注册表未登记） | day-of-week, iso-8601, leap-year, pure-function, lgf-datetime |
| 22 | `FB_DL_TimeWindowCheck` | 实测 16#0001_0202（注册表未登记） | time-window, cross-midnight, weekday-enable, edge-pulse, lgf-datetime |
| 23 | `FB_DL_EventCounter` | 实测 16#0001_0101~0102 / 16#0001_0210（注册表未登记） | event-counter, bidirectional-count, preset-load, wrap-around, compare-output, lgf-counter |
| 24 | `FB_DL_ModuloCounter` | 实测 16#0001_0103~0104 / 16#0001_0211（注册表未登记） | modulo-counter, station-index, conditional-wrap, jump-validate, lgf-counter |
| 25 | `FB_DL_ToleranceWindow` | 16#0001_0112(信息级) / 16#0001_0213(故障级) | lgf-comparator, tolerance-band, hysteresis, three-state-verdict, window-monitor |
| 26 | `FC_DL_LimitClassify` | 16#0001_0214(故障级) | lgf-comparator, limit-classification, four-threshold, pure-function, severity-grading |
| 27 | `FC_DL_WordBitPack` | 16#0001_0108(故障级) | lgf-bitlogic, bit-field-pack, mask-operations, pure-function, status-word |
| 28 | `FB_DL_MonthWindowCheck` | 16#0001_0109(信息级) / 16#0001_0203(信息级) | lgf-datetime, month-window, annual-window, countdown-day, maintenance-schedule |
| 29 | `FB_DL_PresetCounterSat` | 16#0001_0212(故障级) | lgf-counter, preset-counter, saturation, threshold-event, batch-full |
| 30 | `FC_DL_BitFieldExtract` | 16#0001_0113~0115(信息级) | lgf-bitlogic, bit-field-extract, offset-width, right-align, mask-construction |
| 31 | `FC_DL_WeekOfYearCalc` | 16#0001_0116~0117(信息级) | lgf-datetime, iso-8601, week-number, thursday-attribution, zeller-congruence |
| 32 | `FB_DL_BidirectionalCounter` | 16#0001_0118(信息级) / 16#0001_0215、0216(故障级) | lgf-counter, ctud-superset, dual-preset, saturation, up-priority-arbitration |
| 33 | `FB_DL_YearWindowCheck` | 16#0001_011E~011F(信息级) | lgf-datetime, calendar, year-window, state-machine |
| 34 | `FB_DL_RolloverCounter` | 16#0001_0120(信息级) / 16#0001_0218(故障级) | lgf-counter, wrap-around, counting, state-machine |

**DL_Base 已占用号段极大值摘要**

| 号段带 | 已用极大值 | 占用码数 | 标注构成 |
|---|---|---|---|
| 信息级带 `01xx` | `16#0001_0120` | 16 | 信息级×11 / 故障级×1 / 实测无标注×4 |
| 故障级带 `02xx` | `16#0001_0218` | 11 | 故障级×6 / 实测无标注×4 / 信息级×1 |

- **下一可用**：信息级 `16#0001_0125` 起；故障级 `16#0001_021A` 起（同族合计）。
- 本目录合计按件占用 **27** 码（不含公共区）；`0001` / `0002` 两族与 DL_MathData（及 DL_Algo 的 `0002`）共用，取码须查末节合计表。
- 低带 `0000~00FF` 公共/预留区实测占用 6 码：16#0001_000B~000C / 16#0001_000E / 16#0002_0006~0008（历史件，不参与后续分配）。

## DL_MathData（33 件）

| # | 组件名 | 码位段 | 标签 |
|---|---|---|---|
| 1 | `FC_DL_LinearScale` | 无（仅用公共码） | analog-scaling, linear-interpolation, clamping, divide-by-zero-guard |
| 2 | `FC_DL_Deadband` | 无（仅用公共码） | deadband, signal-filtering, pid, actuator-wear |
| 3 | `FC_DL_Hysteresis` | 无（仅用公共码） | hysteresis, schmitt-trigger, stateful-function, pump-control |
| 4 | `FB_DL_MovingAverage` | 无（仅用公共码） | moving-average, o1-recursion, ring-buffer, startup-ramp, drift-correction |
| 5 | `FC_DL_Crc16Modbus` | 无（仅用公共码） | crc16, modbus-rtu, checksum, bit-manipulation, protocol |
| 6 | `FC_DL_SwapBytes16` | 无（仅用公共码） | byte-order, swap-bytes, bit-manipulation, pure-function, modbus |
| 7 | `FC_DL_SwapBytes32` | 无按件码位（低带实测 16#0001_000E） | byte-order, modbus, float-decoding, byte-swap, pure-function |
| 8 | `FB_DL_RingBufferLReal` | 无按件码位（低带实测 16#0001_000A） | ring-buffer, fifo, o1-operation, history-cache, fault-trace |
| 9 | `FC_DL_StringTrim` | 无（仅用公共码） | string-trim, whitespace, barcode, csv-parsing, pure-function |
| 10 | `FC_DL_StringSplit` | 无按件码位（低带实测 16#0001_000D） | string-split, csv-parsing, tokenizer, barcode, var-in-out |
| 11 | `FB_DL_LifoStack` | 无按件码位（低带实测 16#0001_000A） | lifo, stack, push-pop, buffer, path-backtracking, lgf-datahandling |
| 12 | `FB_DL_MedianFilter` | 无（仅用公共码） | median-filter, spike-removal, window-sort, analog-conditioning, noise, lgf-measurement, oscat-basic |
| 13 | `FB_DL_SignalStatistics` | 无按件码位（低带实测 16#0002_0009） | statistics, variance, stddev, min-max, welford, lgf-math, oscat-basic |
| 14 | `FC_DL_Crc32Ethernet` | 无（仅用公共码） | crc32, ieee8023, checksum, ethernet, reflected-polynomial, oscat-network, crc32-iso-hdlc |
| 15 | `FC_DL_HexStringToBytes` | 无按件码位（低带实测 16#0002_000A） | hex-parse, ascii-to-bytes, protocol-decode, validation, modbus-ascii, lgf-converter, modbus-ascii |
| 16 | `FC_DL_LineIntersection` | 无按件码位（低带实测 16#0002_000D） | line-intersection, geometry, parallel-detection, divide-guard, vision-alignment, lgf-math |
| 17 | `FC_DL_LrcChecksum` | 无（仅用公共码） | lrc, modbus-ascii, checksum, frame-validation, two-complement, oscat-network, modbus-ascii |
| 18 | `FC_DL_MultiPointLinear` | 无按件码位（低带实测 16#0002_000B） | piecewise-linear, interpolation, table-lookup, binary-search, sensor-calibration, lgf-math, lbp-basic-process |
| 19 | `FC_DL_PolygonArea` | 无按件码位（低带实测 16#0002_000C） | polygon-area, shoelace, centroid, vision-metrology, geometry, lgf-math |
| 20 | `FC_DL_QuickSortLReal` | 无（仅用公共码） | quicksort, iterative, explicit-stack, sorting, worst-case-guard, lgf-datahandling, oscat-basic |
| 21 | `FB_DL_FifoBuffer` | 16#0001_010A~010D(信息级) / 16#0001_0204(故障级) | lgf-datahandling, fifo-queue, fixed-slot-buffer, overflow-underflow, pointer-consistency |
| 22 | `FB_DL_ArraySearchFirst` | 16#0001_010E(信息级) / 16#0001_0205(故障级) | lgf-datahandling, linear-search, array-scan, multi-hit-count, index-report |
| 23 | `FC_DL_BinarySearchLReal` | 16#0001_010F(信息级) / 16#0001_0206(故障级) | lgf-datahandling, binary-search, sorted-array, pure-function, tolerance-compare |
| 24 | `FC_DL_TempUnitConvert` | 16#0001_0110(信息级) / 16#0001_0207~0208(故障级) | lgf-converter, temperature-unit, celsius-fahrenheit-kelvin, pure-function, absolute-zero-guard |
| 25 | `FC_DL_BcdToWord` | 16#0001_0105(故障级) | lgf-converter, bcd-decode, nibble-validation, pure-function, dip-switch |
| 26 | `FC_DL_WordToBcd` | 16#0001_0106~0107(故障级) | lgf-converter, bcd-encode, overflow-saturation, pure-function, seven-segment |
| 27 | `FC_DL_SearchMinMax` | 16#0001_0119、011A(信息级) / 16#0001_0217(故障级) | lgf-math, extremum-scan, index-report, nan-guard, single-pass |
| 28 | `FC_DL_NthRoot` | 16#0001_011B、011C(信息级) | lgf-math, nth-root, odd-even-branch, negative-domain-guard, pure-function |
| 29 | `FC_DL_FactorialSat` | 16#0001_011D(信息级) | lgf-math, factorial, saturation, domain-0-12, pure-function |
| 30 | `FC_DL_RangeOverlapCheck` | 16#0001_0121(信息级) | lgf-comparator, interval, geometry, pure-function |
| 31 | `FC_DL_CalcDistance3D` | 16#0001_0122(信息级) / 16#0001_0219(故障级) | lgf-math, geometry, distance, pure-function |
| 32 | `FC_DL_RandomNext` | 16#0001_0123(信息级) | lgf-math, prng, deterministic, pure-function |
| 33 | `FC_DL_PercentileLReal` | 16#0001_0124 / 16#0002_000E(信息级) | lgf-math, statistics, percentile, pure-function |

**DL_MathData 已占用号段极大值摘要**

| 号段带 | 已用极大值 | 占用码数 | 标注构成 |
|---|---|---|---|
| 公共/预留带 `00xx` | `16#0002_000E` | 1 | 信息级×1 |
| 信息级带 `01xx` | `16#0001_0124` | 19 | 信息级×15 / 故障级×3 / 兜底/其他×1 |
| 故障级带 `02xx` | `16#0001_0219` | 7 | 故障级×7 |

- **下一可用**：信息级 `16#0001_0125` 起；故障级 `16#0001_021A` 起（同族合计）。
- 本目录合计按件占用 **27** 码（不含公共区）；`0001` / `0002` 两族与 DL_Base（及 DL_Algo 的 `0002`）共用，取码须查末节合计表。
- 低带 `0000~00FF` 公共/预留区实测占用 8 码：16#0001_000A / 16#0001_000D~000E / 16#0002_0009~000D（历史件，不参与后续分配）。

## DL_Algo（25 件）

| # | 组件名 | 码位段 | 标签 |
|---|---|---|---|
| 1 | `FB_DL_PidController` | 实测 16#0002_0101~0102（注册表未登记） | pid, mod-pid-control, oscat-basic, lgf-technology, anti-windup, bumpless-transfer |
| 2 | `FB_DL_CascadePid` | 实测 16#0002_0201（注册表未登记） | pid, cascade-control, mod-pid-control, lgf-technology, bumpless-transfer |
| 3 | `FB_DL_SplitRangeControl` | 实测 16#0002_0301（注册表未登记） | split-range, mod-pid-control, output-allocation, lgf-technology |
| 4 | `FB_DL_FeedforwardComp` | 实测 16#0002_0401~0402（注册表未登记） | feedforward, lgf-technology, disturbance-compensation, dead-time |
| 5 | `FB_DL_SmithPredictor` | 实测 16#0002_0501~0502（注册表未登记） | smith-predictor, dead-time-compensation, lgf-technology, mod-pid-control, pid |
| 6 | `FB_DL_RateLimiter` | 无（仅用公共码） | rate-limiter, slew-rate, lgf-technology, lgf-signalgen |
| 7 | `FB_DL_RampGenerator` | 实测 16#0002_0601（注册表未登记） | ramp, setpoint-profiling, lgf-signalgen, lgf-technology, rate-limit |
| 8 | `FB_DL_SCurveGenerator` | 实测 16#0002_0701~0702（注册表未登记） | s-curve, trajectory-planning, jerk-limited, lgf-signalgen, lgf-technology |
| 9 | `FB_DL_PwmDutyController` | 实测 16#0002_0801（注册表未登记） | pwm, time-proportional, ssr-drive, lgf-signalgen, mod-pid-control |
| 10 | `FB_DL_Integrator` | 无（仅用公共码） | integrator, trapezoidal, totalizer, oscat-basic, lgf-math |
| 11 | `FB_DL_Differentiator` | 实测 16#0002_1401（注册表未登记） | differentiator, rate-of-change, oscat-basic, lgf-measurement, noise-suppression |
| 12 | `FB_DL_LowPassFilter` | 实测 16#0002_1001（注册表未登记） | low-pass-filter, pt1, lgf-measurement, signal-conditioning, bumpless-transfer |
| 13 | `FB_DL_SecondOrderFilter` | 实测 16#0002_1101（注册表未登记） | butterworth, second-order-filter, biquad, lgf-measurement, signal-conditioning |
| 14 | `FB_DL_HighPassFilter` | 实测 16#0002_1201（注册表未登记） | high-pass-filter, hp1, lgf-measurement, vibration-monitoring, signal-conditioning |
| 15 | `FC_DL_DewPointCalc` | 实测 16#0002_1501~1502（注册表未登记） | dew-point, magnus-tetens, hvac, oscat-basic, psychrometrics |
| 16 | `FC_DL_FlowCompensate` | 实测 16#0002_1601~1602（注册表未登记） | flow-compensation, standard-volume, oscat-basic, gas-metering, ideal-gas |
| 17 | `FC_DL_HumidAirEnthalpy` | 实测 16#0002_1701~1703（注册表未登记） | enthalpy, psychrometrics, magnus-tetens, hvac, oscat-building |
| 18 | `FB_DL_RampSoakProfile` | 实测 16#0002_1801~1804 / 16#0002_1810（注册表未登记） | ramp-soak-profile, multi-segment, hold-freeze, skip-segment, track-resync, loop-profile, lgf-technology |
| 19 | `FB_DL_PeakDetector` | 16#0002_1901~1904(信息级 / 入参降级) | lgf-math, peak-hold, extremum-tracking, signal-conditioning, envelope-detection |
| 20 | `FB_DL_StepController` | 16#0002_1A01~1A06(信息级 / 参数钳位) | lbp-step-controller, lgf-technology, stage-control, hysteresis, load-rotation |
| 21 | `FB_DL_SineGenerator` | 16#0002_1B01~1B04(信息级) / 16#0002_1B10、1B11(故障级) | lgf-signalgen, sine-wave, phase-accumulation, amplitude-offset, clamp-output |
| 22 | `FB_DL_SawtoothGenerator` | 16#0002_1C01~1C03(信息级) / 16#0002_1C10(故障级) | lgf-signalgen, sawtooth-triangle, symmetry-ratio, phase-normalised, clamp-output |
| 23 | `FC_DL_CoilDiameterCalc` | 16#0002_1D01~1D04(信息级) / 16#0002_1D10(故障级) | lgf-technology, coil-diameter, line-speed-ratio, low-speed-hold, layer-count |
| 24 | `FC_DL_AirDensity` | 16#0002_1E01~1E04(信息级) / 16#0002_1E10(故障级) | oscat-building, moist-air-density, magnus-tetens, partial-pressure, domain-clamp |
| 25 | `FB_DL_R2rEwmaTuner` | 16#0002_1F01~1F03(信息级) / 16#0002_1F10(故障级) | semiconductor-apc, lgf-math, ewma, run-to-run, state-machine |

**DL_Algo 已占用号段极大值摘要**

| 号段带 | 已用极大值 | 占用码数 | 标注构成 |
|---|---|---|---|
| 信息级带 `01xx` | `16#0002_0102` | 2 | 实测无标注×2 |
| 故障级带 `02xx` | `16#0002_0201` | 1 | 实测无标注×1 |
| 特殊带 `03xx` | `16#0002_0301` | 1 | 实测无标注×1 |
| 特殊带 `04xx` | `16#0002_0402` | 2 | 实测无标注×2 |
| 特殊带 `05xx` | `16#0002_0502` | 2 | 实测无标注×2 |
| 特殊带 `06xx` | `16#0002_0601` | 1 | 实测无标注×1 |
| 特殊带 `07xx` | `16#0002_0702` | 2 | 实测无标注×2 |
| 特殊带 `08xx` | `16#0002_0801` | 1 | 实测无标注×1 |
| 算法按件带 `1x00` | `16#0002_1F10` | 50 | 信息级×28 / 实测无标注×16 / 故障级×6 |

- **下一可用**：信息级 `16#0002_2001` 起；故障级 `16#0002_2010` 起（新带首码，故障子码沿用 +0x0F 约定）。
- 本目录合计按件占用 **62** 码（不含公共区）；`0002` 族与 DL_Base / DL_MathData 共用 `01xx~03xx`；算法自有 `1x00` 带逐件独占。

## DL_Device（40 件）

| # | 组件名 | 码位段 | 标签 |
|---|---|---|---|
| 1 | `I_DL_Cylinder` | 无（仅用公共码） | cylinder-interface, state-machine, dependency-injection, device-abstraction, lbp-device |
| 2 | `FB_DL_PneumaticCylinder` | 实测 16#0003_0201~0204（注册表未登记） | pneumatic-cylinder, reed-debounce, double-solenoid, fault-latch, timeout-protection, lbp-device |
| 3 | `I_DL_MotorDriver` | 无（仅用公共码） | motor-interface, dol-motor, dependency-injection, device-abstraction, lbp-device |
| 4 | `FB_DL_DolMotor` | 实测 16#0003_0201 / 16#0003_0205~020A（注册表未登记） | dol-motor, contactor-feedback, thermal-overload, restart-inhibit, starts-per-hour, lbp-device |
| 5 | `I_DL_AnalogSensor` | 无（仅用公共码） | analog-sensor-interface, signal-quality, alarm-limits, device-abstraction, namur-ne43 |
| 6 | `FB_DL_AnalogTransmitter` | 实测 16#0003_0102~0104 / 16#0003_0210（注册表未登记） | analog-transmitter, span-scaling, moving-average, wire-break, alarm-limits, hold-last-good, namur-ne43 |
| 7 | `I_DL_TemperatureZone` | 无（仅用公共码） | temperature-zone-interface, pid, dependency-injection, device-abstraction, lbp-device |
| 8 | `FB_DL_HeatCoolZone` | 实测 16#0003_0101 / 16#0003_0211~0213（注册表未登记） | heat-cool-zone, split-range, pid-consumer, pwm-ssr, sensor-break, lbp-device, namur-ne43 |
| 9 | `FB_DL_SingleSolenoidCyl` | 实测 16#0003_0220~0222（注册表未登记） | single-solenoid-cylinder, spring-return, time-mode, reed-check, stroke-count, lbp-basic-process, lbp-device |
| 10 | `I_DL_VacuumGenerator` | 无（仅用公共码） | vacuum-generator-interface, dependency-injection, device-abstraction, lbp-basic-process, lbp-device |
| 11 | `FB_DL_VacuumEjector` | 实测 16#0003_0230~0232（注册表未登记） | vacuum-ejector, hysteresis, blow-off-pulse, dual-confirm, hold-last-good, lbp-basic-process, lbp-device |
| 12 | `FB_DL_StarDeltaMotor` | 实测 16#0003_0201 / 16#0003_0208 / 16#0003_0240~0246（注册表未登记） | star-delta-motor, contactor-sequence, dead-time-interlock, mutual-exclusion-assert, restart-inhibit, lbp-basic-process, lbp-device |
| 13 | `I_DL_VfdDrive` | 无（仅用公共码） | vfd-interface, preset-speed, dependency-injection, device-abstraction, lbp-basic-process, lbp-device |
| 14 | `FB_DL_VfdGeneric` | 实测 16#0003_0106~0107 / 16#0003_0250~0252（注册表未登记） | vfd-generic, terminal-control, jog-priority, preset-speed-table, analog-frequency-mapping, fault-reset-pulse, lbp-basic-process, lbp-device |
| 15 | `I_DL_ProportionalValve` | 无（仅用公共码） | proportional-valve-interface, dependency-injection, device-abstraction, lbp-basic-process, lbp-device |
| 16 | `FB_DL_AnalogValve` | 实测 16#0003_0108~0109 / 16#0003_0112 / 16#0003_0260~0261（注册表未登记） | analog-valve, deadband-compensation, deviation-alarm, span-mapping, lbp-basic-process, lbp-device |
| 17 | `I_DL_MotorizedValve` | 无（仅用公共码） | motorized-valve-interface, pulse-drive, dependency-injection, device-abstraction, lbp-basic-process, lbp-device |
| 18 | `FB_DL_ThreePointValve` | 实测 16#0003_0110~0111 / 16#0003_0270~0272（注册表未登记） | three-point-valve, position-integration, limit-anchoring, endpoint-guard, travel-count, lbp-basic-process, lbp-device |
| 19 | `I_DL_BarcodeScanner` | 无（仅用公共码） | barcode-scanner-interface, trigger-handshake, dependency-injection, device-abstraction, tcopen-component, scanner-handshake |
| 20 | `FB_DL_SerialScanner` | 实测 16#0003_0117 / 16#0003_0119 / 16#0003_0120 / 16#0003_0280 / 16#0003_0282（注册表未登记） | serial-scanner, trigger-ack-handshake, noread-retry, escalation-fault, trailing-crlf-strip, tcopen-component, scanner-handshake |
| 21 | `I_DL_SafetyDoor` | 无（仅用公共码） | safety-door-interface, interlock-sequence, dependency-injection, tcopen-component, safety-interlock |
| 22 | `FB_DL_GuardLockDoor` | 实测 16#0003_0121 / 16#0003_0290~0293（注册表未登记） | guard-lock-door, unlock-sequence, standstill-confirm, run-down-timer, tamper-conflict, restart-inhibit, open-audit, tcopen-component, safety-interlock |
| 23 | `I_DL_LightCurtain` | 无（仅用公共码） | light-curtain-interface, muting-abstraction, safestop-mirror, tcopen-component, light-curtain-muting |
| 24 | `FB_DL_SafetyLightCurtain` | 实测 16#0003_0118 / 16#0003_0122 / 16#0003_02A0~02A2（注册表未登记） | safety-light-curtain, ossd-discrepancy, sequential-muting, four-sensor, muting-timeout, override-lamp-blink, restart-interlock, tcopen-component, light-curtain-muting |
| 25 | `I_DL_FlowMeter` | 无（仅用公共码） | flow-meter-interface, totalizer, dependency-injection, tcopen-component, flow-totalizer |
| 26 | `FB_DL_PulseFlowMeter` | 实测 16#0003_0113~0115 / 16#0003_02B0（注册表未登记） | pulse-flow-meter, k-factor, sample-window, double-buffer, low-flow-cutoff, totalizer, tcopen-component, flow-totalizer |
| 27 | `I_DL_LevelSwitch` | 无（仅用公共码） | level-switch-interface, failsafe-normalize, tcopen-component, level-switch-failsafe |
| 28 | `FB_DL_LevelSwitchVib` | 实测 16#0003_02C0（注册表未登记） | vibrating-level-switch, debounce, cover-bare-delay, failsafe-high-low, interlock-mirror, tcopen-component, level-switch-failsafe |
| 29 | `I_DL_TowerLight` | 无（接口契约不发布故障码，码位由实现块承担） | tcopen-component, stack-light, andon, tower-light, interface-contract |
| 30 | `FB_DL_SignalTower` | 16#0003_0123~0126(信息级) / 16#0003_02D0~02D1(故障级) | tcopen-component, stack-light, andon, priority-arbitration, buzzer-silence |
| 31 | `I_DL_StepperOpenLoop` | 无（接口契约不发布故障码，码位由实现块承担） | stepper, tcopen, open-loop-contract, pulse-direction, interface-contract |
| 32 | `FB_DL_PulseDirStepper` | 16#0003_0130~0137(信息级) / 16#0003_02E0~02E4(故障级) | stepper, plcopen-motion, pulse-direction, trapezoidal-ramp, stall-timeout |
| 33 | `I_DL_RfidReader` | 无（接口契约不发布故障码，码位由实现块承担） | tcopen-component, rockwell-aoi, interface-contract, rfid-reader, tag-snapshot |
| 34 | `FB_DL_RfidTagHandler` | 16#0003_0138~013A(信息级) / 16#0003_02F0~02F3(故障级) | tcopen-component, rockwell-aoi, rfid-fsm, duplicate-suppression, retry-chain |
| 35 | `FB_DL_AxiolineDiagLatch` | 16#0003_013B、013C(信息级) / 16#0003_02F4~02F6(故障级) | plcnext-community, axioline-diagnosis, bit-field-parse, first-out-latch, slot-locating |
| 36 | `FB_DL_PdiReadScheduler` | 16#0003_013D~013F(信息级) / 16#0003_02F7~02F9(故障级) | plcnext-community, pdi-read, async-scheduler, dual-code-packing, length-verify |
| 37 | `FB_DL_PortDiagAggregator` | 16#0003_0140~0141(信息级) / 16#0003_0300~0301,0307(故障级) | plcnext-community, profinet-diag, port-diagnostics, first-out, state-machine |
| 38 | `FB_DL_StatusWordSegDecoder` | 16#0003_0142~0144(信息级) / 16#0003_0302(故障级) | lgf-bitlogic, rockwell-aoi, bit-segment, status-word, table-driven |
| 39 | `FB_DL_NtcTempScan` | 16#0003_0145~0146(信息级) / 16#0003_0303~0304(故障级) | rockwell-aoi, oscat-building, temperature, multi-channel, device-level |
| 40 | `FB_DL_RollerGapAdjust` | 16#0003_0147~0148(信息级) / 16#0003_0305~0306,0308(故障级) | rockwell-aoi, lbp-process, servo-adjust, backlash, state-machine |

**DL_Device 已占用号段极大值摘要**

| 号段带 | 已用极大值 | 占用码数 | 标注构成 |
|---|---|---|---|
| 信息级带 `01xx` | `16#0003_0148` | 49 | 信息级×29 / 实测无标注×20 |
| 故障级带 `02xx` | `16#0003_02F9` | 63 | 实测无标注×46 / 故障级×17 |
| 特殊带 `03xx` | `16#0003_0308` | 9 | 故障级×9 |

- **下一可用**：信息级 `16#0003_0149` 起；故障级 `16#0003_0309` 起。
- 本目录合计按件占用 **121** 码（不含公共区）；`0003` 族本库独占。

## DL_Motion（16 件）

| # | 组件名 | 码位段 | 标签 |
|---|---|---|---|
| 1 | `I_DL_MotionAxis` | 无（仅用公共码） | motion-axis-interface, plcopen-states, dependency-injection, s7-motion, plcopen |
| 2 | `FB_DL_SingleAxis` | 实测 16#0004_0101 / 16#0004_0103~0105 / 16#0004_0201~0203（注册表未登记） | single-axis, virtual-kinematics, soft-limit, command-arbitration, fault-latch, s7-motion, plcopen |
| 3 | `FB_DL_AxisJogController` | 实测 16#0004_0102~0103 / 16#0004_0105（注册表未登记） | jog-controller, two-speed, braking-distance, soft-limit, s7-motion |
| 4 | `FB_DL_AxisHomingSeq` | 实测 16#0004_0106 / 16#0004_0210~0213（注册表未登记） | axis-homing, homing-sequence, limit-switch-homing, zero-pulse-homing, torque-block-homing, travel-guard, plcopen-motion, s7-motion |
| 5 | `FB_DL_AxisRelativeMove` | 实测 16#0004_0106 / 16#0004_0201 / 16#0004_0220~0221（注册表未登记） | axis-relative-move, chain-stepping, polling-state, command-arbitration, plcopen-motion, s7-motion |
| 6 | `FB_DL_AxisVelocityMove` | 实测 16#0004_0106~0107 / 16#0004_0201 / 16#0004_0230（注册表未登记） | axis-velocity-move, dynamic-retarget, velocity-clamp, polling-state, plcopen-motion, s7-motion |
| 7 | `FB_DL_SoftLimitGuard` | 实测 16#0004_0108 / 16#0004_0240~0241（注册表未登记） | soft-limit-guard, braking-distance, latency-compensation, directional-intercept, plcopen-motion |
| 8 | `FB_DL_ElectronicGear` | 16#0004_0130~0132(信息级) / 16#0004_0250~0252(故障级) / 16#0004_0299(兜底) | electronic-gear, gear-ratio-coupling, plcopen-motion, phase-compensation, speed-synchronization |
| 9 | `FB_DL_ElectronicCam` | 16#0004_0140~0142(信息级) / 16#0004_0260~0265(故障级) / 16#0004_0298(兜底) | electronic-cam, cam-profile, plcopen-motion, flying-shear, phase-correction |
| 10 | `FB_DL_GantrySyncAxis` | 16#0004_0150~0152(信息级) / 16#0004_0270~0274(故障级) / 16#0004_0297(兜底) | gantry-sync, dual-drive, skew-protection, plcopen-motion, following-error |
| 11 | `FB_DL_TorqueLimitControl` | 16#0004_0160~0164(信息级) / 16#0004_0280~0284(故障级) / 16#0004_0296(兜底) | torque-limit, press-fit, plcopen-motion, stop-point-detection, in-position-window |
| 12 | `FB_DL_MarkPositionLatch` | 16#0004_0170~0171(信息级) / 16#0004_0290(故障级) / 16#0004_0295(兜底) | mark-latch, registration-mark, plcopen-motion, position-capture, pitch-measurement |
| 13 | `FC_DL_CalcMoveTime` | 16#0004_0180~0184(入参非法 / 不可达，无故障锁存) | cycle-time-estimation, trapezoidal-profile, plcopen-motion, motion-planning, pure-function |
| 14 | `FB_DL_SuperimposedMove` | 16#0004_01A0~01A3(信息级) / 16#0004_02B0~02B2(故障级) | plcopen-motion, s7-motion, superimposed-move, offset-compensation, vision-correction |
| 15 | `FB_DL_WindingTraverse` | 16#0004_01B0~01B3(信息级) / 16#0004_02C0~02C3(故障级) | lgf-technology, s7-motion, diameter-recursion, traverse-winding, endpoint-dwell |
| 16 | `FB_DL_WindingTensionCtrl` | 16#0004_01C0~01C2(信息级) / 16#0004_02D0~02D1(故障级) | lgf-technology, s7-motion, tension-control, taper, state-machine |

**DL_Motion 已占用号段极大值摘要**

| 号段带 | 已用极大值 | 占用码数 | 标注构成 |
|---|---|---|---|
| 信息级带 `01xx` | `16#0004_01C2` | 40 | 信息级×32 / 实测无标注×8 |
| 故障级带 `02xx` | `16#0004_02D1` | 46 | 实测无标注×12 / 故障级×29 / 兜底/其他×5 |

- **下一可用**：信息级 `16#0004_01C3` 起；故障级 `16#0004_02D2` 起。
- 本目录合计按件占用 **86** 码（不含公共区）；`0004` 族本库独占。

## DL_Process（20 件）

| # | 组件名 | 码位段 | 标签 |
|---|---|---|---|
| 1 | `FB_DL_PackMlStateMachine` | 实测 16#0005_0101 / 16#0005_0201（注册表未登记） | packml, state-machine, isa-tr88, unit-mode, abort-recovery, packml-omac |
| 2 | `FB_DL_PackMlCmdDecoder` | 实测 16#0005_0102（注册表未登记） | packml, command-decoder, one-shot, conflict-detection, packml-omac |
| 3 | `FB_DL_EnthalpyCompareCtrl` | 实测 16#0005_0103 / 16#0005_0201~0202（注册表未登记） | enthalpy-compare, economizer, schmitt-hysteresis, high-limit-trip, minimum-oa-position, oscat-building, lgf-datetime, hvac |
| 4 | `FB_DL_OccScheduleWindow` | 实测 16#0005_0210~0211（注册表未登记） | occupancy-schedule, multi-window, holiday-override, pre-start-lead, weekday-matrix, oscat-building, lgf-datetime, hvac |
| 5 | `FB_DL_OeeCalculator` | 实测 16#0005_0110~0112 / 16#0005_0200（注册表未登记） | oee-calculator, availability, performance, quality, packml-root-cause, shift-statistics, packml-oee |
| 6 | `FB_DL_ConveyorZone` | 实测 16#0005_0113 / 16#0005_0212~0214（注册表未登记） | conveyor-zone, zero-pressure-accumulation, run-on, jam-detection, vfd-interface-consumer, surge-stagger, conveyor-accumulation |
| 7 | `FB_DL_BatchDosingControl` | 实测 16#0005_0114~0115 / 16#0005_0220~0223（注册表未登记） | batch-dosing, coarse-fine, inflight-learning, settle-window, no-flow-watchdog, isa-88, lbp-batch-dosing |
| 8 | `FB_DL_ConveyorLineLink` | 16#0005_0130~0133(信息级) / 16#0005_0230~0231(故障级) | smema, handshake, conveyor-cascade, line-link, watchdog |
| 9 | `FB_DL_RecipeManager` | 16#0005_0140~0143(信息级) / 16#0005_0240~0246(故障级) | recipe-management, codesys-forge, parameter-validation, recipe-switch, checksum |
| 10 | `FB_DL_LeakTestStation` | 16#0005_0150~0153(信息级) / 16#0005_0250~0257(故障级) | leak-test, pressure-decay, leak-rate, test-station, ok-ng-verdict |
| 11 | `FB_DL_MixRecipeControl` | 16#0005_0160~0164(信息级) / 16#0005_0260~0265(故障级) | mixing, isa-88-phase, agitation, torque-limit, recipe-control |
| 12 | `FB_DL_CipCleaningSeq` | 16#0005_0170~0173(信息级) / 16#0005_0270~0274(故障级) | cip-cleaning, isa-88-phase, phase-sequencing, conductivity-endpoint, tact-interlock |
| 13 | `FB_DL_BufferMagazine` | 16#0005_0180~0186(信息级) / 16#0005_0280~0283(故障级) | buffer-magazine, slot-management, storage-scheduling, lift-control, material-handling |
| 14 | `FB_DL_ModbusPollMaster` | 16#0005_0190~0193(信息级) / 16#0005_0290~0292(故障级) | codesys-forge-modbus, modbus-rtu, poll-scheduler, retry-timeout, transport-abstraction |
| 15 | `FB_DL_AndonCallSystem` | 16#0005_01A0~01A1(信息级) / 16#0005_02A0~02A1(故障级) | andon, omac, call-escalation, response-time-stat, shift-reset |
| 16 | `FB_DL_PickAndPlaceStation` | 16#0005_01B0~01B4(信息级) / 16#0005_02B0~02B7(故障级) | packml-omac, tcopen-component, pick-and-place, state-machine, dependency-injection |
| 17 | `FB_DL_PressFitStation` | 16#0005_01C0~01C1(信息级) / 16#0005_02C0~02C3(故障级) | lbp-process, plcopen-motion, isa-88, press-fit, state-machine |
| 18 | `FB_DL_RotaryIndexTable` | 16#0005_01C2(信息级) / 16#0005_02D0~02D3(故障级) | packml-omac, lgf-bitlogic, indexing-table, station-scheduling, state-machine |
| 19 | `FB_DL_AgvDockingHandshake` | 16#0005_01C3(信息级) / 16#0005_02E0~02E4(故障级) | packml-omac, isa-88, lbp-process, agv-handshake, state-machine |
| 20 | `FB_DL_EnergySavingMode` | 16#0005_01C4(信息级) / 16#0005_02F0~02F2(故障级) | isa-88, lbp-process, namur-ne43, energy-saving, state-machine |

**DL_Process 已占用号段极大值摘要**

| 号段带 | 已用极大值 | 占用码数 | 标注构成 |
|---|---|---|---|
| 信息级带 `01xx` | `16#0005_01C4` | 53 | 信息级×44 / 实测无标注×9 |
| 故障级带 `02xx` | `16#0005_02F2` | 73 | 实测无标注×12 / 故障级×61 |

- **下一可用**：信息级 `16#0005_01C5` 起；故障级 `16#0005_02F3` 起。
- 本目录合计按件占用 **126** 码（不含公共区）；`0005` 族本库独占。

## 附：共享码族合计极大值（跨目录取码必查）

| 码族 | 参与目录 | 信息带 `01xx` 极大值 | 故障带 `02xx` 极大值 | 特殊带极大值 |
|---|---|---|---|---|
| `16#0001_xxxx` | DL_Base + DL_MathData | `16#0001_0124` | `16#0001_0219` | — |
| `16#0002_xxxx` | DL_Base + DL_MathData + DL_Algo | `16#0002_0102` | `16#0002_0201` | `16#0002_1F10` |

> `0002` 族的算法按件带（`1x00`）计入「特殊带」列；带内故障子码沿用 `+0x0F` 约定（如 `1F03` → 故障 `1F10`）。
