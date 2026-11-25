# GATE_R80_B —— R80 第二批 4 件（C3~C4 FB）L2 真编译 + 逻辑级复核

- 日期：2026-11-24
- 批次：R80 / batch B（4 件，全部 FB，全部状态机）
- 复核人：dlf-compile-verifier（编译闸席，一票否决）
- L2 引擎：RuSTy `C:\Library\_tools\rusty\plc.exe`，`l2_check.py`（jobs=1 串行，缓存命中）
- 复现命令：
  ```bash
  python C:\Library\_tools\l2_check.py DL_Process/FB_DL_MultiTankBlendSeq.st
  python C:\Library\_tools\l2_check.py DL_Process/FB_DL_ConveyorMergePrioritySeq.st
  python C:\Library\_tools\l2_check.py DL_Process/FB_DL_DryerZoneProfileSeq.st
  python C:\Library\_tools\l2_check.py DL_Device/FB_DL_RefDefrostCycleSeq.st
  ```

## 一、逐件裁决表

| # | 组件 | 路径 | 复杂度 | L2 真编译 | 逻辑闸 | 裁决 |
|---|---|---|---|---|---|---|
| 1 | FB_DL_MultiTankBlendSeq | DL_Process | C4 | **PASS** | 1 MAJOR / 2 MINOR | PASS（MAJOR 本轮必修） |
| 2 | FB_DL_ConveyorMergePrioritySeq | DL_Process | C3 | **PASS** | 1 MAJOR | PASS（MAJOR 本轮必修） |
| 3 | FB_DL_DryerZoneProfileSeq | DL_Process | C4 | **PASS** | 3 MINOR | PASS（挂账） |
| 4 | FB_DL_RefDefrostCycleSeq | DL_Device | C4 | **PASS** | 1 MAJOR / 3 MINOR | PASS（MAJOR 本轮必修） |

L2 原始输出（4 件一致）：`接口预筛: 可用 22 / 排除 0 | 并行 1 进程 | 缓存 命中` → `PASS=1 FAIL=0 TOTAL=1`

**统计**：L2 PASS 4 / FAIL 0 / EXEMPT 0，通过率 100%；逻辑闸 BLOCK 0 / MAJOR 3 / MINOR 7。
工具链自愈：本轮 0 次（无桩缺失、无 END_METHOD 缺失、无 METHOD 排序报错，`stub_fix / fix_end_method / reorder_methods` 均未触发）。

## 二、§逻辑详情（逐条给行号证据与推演）

### 2.1 FB_DL_MultiTankBlendSeq（C4）

**通项通过项**
- (a) ENUM 可达性与出口：eIdle/eFillA/eFillB/eCirculate/eSample/eRelease/eDone/eFault 八成员全部可达；六执行相皆有退出条件，且等待收敛相各配超时（eFill→tonFill L217、eCirculate→tonCirc L220、eSample→tonSample L225、eRelease→tonRelease L227），零无界驻留相。eDone 以 `NOT bStart`（L284）为出口，属文档声明的「人工确认型驻留」，可接受。
- (b) eFault 复位出口存在（L289-293），且判据自洽：`rtAbort.Q` 为**沿**判据、`(NOT bStart AND NOT bAbort)` 为电平判据；电平支路要求 bAbort 已释放，不会因「停止电平仍成立」而复跳（上一批 WeighHopper 的失败模式在本件不成立）。
- (c) eIdle/eFault 输出清零：段 0 每拍预置（L150-154）+ 段 6 显式全撤（L335-341）双封堵，L2 级零残留。
- (d) 六个 TON + 一个 R_TRIG 全部在段 2（L216-228）CASE 外无条件调用，IN 均含 `NOT .Q` 与 `NOT _bFaultLatch`。
- (e) 无恒假谓词：`(x - x) <> 0` 用于 Inf 检出（L169-178），非 `ABS(x-x)>EPS` 滥用；除零除子 `_rVolTotal` 过 `>EPS` 与 `_bCfgOk` 双检（L345-346）。

**MAJOR-1（安全侧）· L240 · bAbort 电平不抑制启动**
```
L240: IF bStart AND _bCfgOk AND (NOT _bFaultLatch) THEN
```
推演：eFault 复位判据把 bAbort 当**电平**用（L289 要求 `NOT bAbort` 才允许自动复位），但 eIdle 启动判据完全不看 bAbort。若操作员按住/卡死 bAbort（TRUE 保持），此时 bStart 上升 → eIdle→eFillA（L241）→ 次拍 `_bValveA := TRUE`（L245）→ **进料阀在人工中止有效期内打开**。同一件内对 bAbort 的语义两处不一致（一处电平、一处忽略），属实证缺陷。
最小修法（1 行）：`IF bStart AND _bCfgOk AND (NOT bAbort) AND (NOT _bFaultLatch) THEN`

**MINOR-1 · L289 + L240 · 中止沿复位后未重新武装启动，2 拍后进料阀重开**
推演：扫描 N 操作员再按一次 bAbort（上升沿，此时在 eFault）→ 段 2 `rtAbort.Q=TRUE` → 段 3 因锁存已置位不改（L231）→ 段 4 eFault 清锁存并迁 eIdle（L290-292）；扫描 N+1 bStart 仍为 TRUE → 直接迁 eFillA（L240）；扫描 N+2 开 A 阀（L245）。即「按中止键消警」会变成「重启进料」，操作员未按启动。MINOR（需 2 拍且 bStart 保持才复现，且 MAJOR-1 的修法不覆盖此路径）。
最小修法：加一只 `_bStartArmed` 位，进 eFault 时清、bStart 落沿置，eIdle 迁移条件加 `AND _bStartArmed`。

**MINOR-2 · L142 · `DL_BLD_ONE` 声明未使用**（全库仅出现 1 次，即声明行）。

### 2.2 FB_DL_ConveyorMergePrioritySeq（C3）

**通项通过项**
- (a) 六成员全部可达、全部有出口：eGrantMain/eGrantBranch 由 tonGrant（L169）30s 兜底；eJamWait 由 tonJamWait（L172）60s 兜底；eHoldBranch 三个出口分支对「有主线请求 / 有支线请求 / 两者皆无」穷尽（L233-239），单拍必出。
- (b) eFault 唯一出口为 bJamReset 上升沿（段 3 清锁存 L180-186 → 段 4 判锁存位迁相 L251）——沿判据，非电平，复位后不复跳。复位后重入 eGrantMain 时，`bJamMain` 仍真 → 当拍即迁 eJamWait 并由段 6（L288-293）撤权，**不产生授权毛刺**（推演：L200 置 `_bGrantMain:=TRUE`，L201-204 同拍迁 eJamWait，段 6 清 FALSE）。
- (c) eIdle/eFault/eJamWait 三安全相授权全撤（L288-293）。
- (d) 三个 TON + 三个沿实例全部在段 2（L166-177）CASE 外无条件调用。
- (e) 无恒假谓词；`_bSlowMain/_bSlowBranch` 在非有限输入下恒假，由段 1 域闸（L146-148）兜住。

**MAJOR-1 · L174-177 · 支线饥饿计数计时器在默认参数下永不置位（声明功能失效）**
```
L174-177: tonBranchWait(IN := bReqBranch AND (NOT bReqMain)
                 AND ((_eState = eGrantMain) OR (_eState = eHoldBranch))
                 AND (NOT tonBranchWait.Q) AND (NOT _bFaultLatch),
              PT := tJamTimeout);   // 默认 T#60S
```
推演：IN 只在 eGrantMain 与 eHoldBranch 成立。eGrantMain 无出口时最多驻留 tGrantMax（默认 T#30S，L89）即由 tonGrant 锁存码 2 迁出；eHoldBranch 单拍必出（L233-239）。故 IN 的最长连续真值为 30s < PT 60s → `tonBranchWait.Q` 在默认组态下恒假 → 段 5 的 `_nJamCnt + 1`（L280-282）为不可达分支，`bJamAlarm` 只剩「堵车事件计数」与「授权相慢速征兆」两条来源（L301-303）。件头声明的「支线不饿死」计数保护实际失效（非安全侧，属观测/保护缺口）。
最小修法：新增独立引脚 `tBranchWaitMax`（域闸校验 `tBranchWaitMax < tGrantMax`），`PT := tBranchWaitMax`；或把计数点改到 `eHoldBranch → eGrantBranch` 迁移沿（L235-236），一拦一计。

### 2.3 FB_DL_DryerZoneProfileSeq（C4）

**通项通过项**
- (a) 七成员全部可达、全部有出口：ePreheat/eRampUp 由 tonRamp（L241）兜底，eSoak 由 tonSoak（L244），eCoolDown 由 tonCool（L246），eDone 由 `NOT bStart OR rtStop.Q`（L332），eFault 由 bStop 沿（L340）。eFault→eIdle→（bStop 仍 TRUE）不进 ePreheat，出口自洽（L265 要求 `NOT bStop`，与 L343 注释一致）。
- (b) eFault 复位为**沿**判据（L340），非电平；复位后段 6/段 7 双重清零设定与使能（L390-394、L405-412）。
- (c) eIdle/eFault/eDone 设定强制全零（L406-408），加热/风机出口再加相门（L416-417）。
- (d) 超温退避期间**不写** `_aSpRamp`（写入在 `IF NOT _bOverTemp` 内，L286-299），设定确实冻结，未出现「退避→保温」逐拍抖动（我按 L286/L300 的条件互斥性推演确认）。
- (e) 无恒假谓词；除零除子 `rTempTarget` 过 `>EPS` 与 `_bCfgOk` 双检（L413-414）。

**MINOR-1 · L290-293 · 退避恢复时设定出现单拍阶跃下调**
推演：eSoak 内 `_aSpRamp := rTempTarget`（L308）；超温 → 迁 eRampUp（L314），退避期写入被跳过、冻结在 target（正确）。超温消失当拍，L290 判 `target + step < ceil(=target-band)` 为假 → 走 else L293 `_aSpRamp := _rRampCeil`，即设定在 1 拍内**下跌 rSoakBand**；随即 L300 判 `_rMinAct >= ceil-EPS` 成立 → 回 eSoak 又置回 target。与件头 ④「不存在阶跃路径」的声明不符（单拍、加热已被段 6 撤除，物理影响可忽略）。
最小修法：L290 改为 `IF (_aSpRamp[_nIdx] + _rStep) < _rRampCeil AND _aSpRamp[_nIdx] < _rRampCeil`，即只在设定低于上限时才饱和推进，已高于上限则保持不变。

**MINOR-2 · L139 · `DL_DRY_ONE` 声明未使用**（全库仅出现 1 次）。

**MINOR-3 · L340 + L265 · 复位后未重新武装启动**
推演：bStop 沿复位 → eIdle，此时 bStop 仍 TRUE，L265 `NOT bStop` 阻止重启（正确的电平联锁）；**但**操作员松手 bStop 后，bStart 若仍为 TRUE → 自动进 ePreheat 并加热，全程没有第二次启动动作。与 MultiTank 同一类（本件多一层 bStop 电平闸，故降为 MINOR）。
最小修法：同 MultiTank，加 `_bStartArmed`（进 eFault 清、bStart 落沿置），eIdle 迁移条件加 `AND _bStartArmed`。

### 2.4 FB_DL_RefDefrostCycleSeq（C4）

**通项通过项**
- (a) 七成员全部可达、全部有出口：eCooling→tonCoolMin（L176）保证转出；eFrostDetect 单拍决策、IF/ELSE 穷尽（L206-212）；eDefrost→tonDefrost（L178）；eDrip→tonDrip（L180）；eRecover→tonRecover（L182）；eFault→bEnable 沿（L233-237）。
- (b) eFault 唯一出口 `rtEnable.Q`（沿，L233），非电平；复位三项作用域（清锁存/清码/迁相）逐项写明。
- (c) eIdle/eFault 三输出全撤（段 0 L134-136 + 段 5 L274-278）。
- (d) 五个 TON + 一个 R_TRIG 全部在段 2（L175-185）CASE 外无条件调用，IN 含 `NOT .Q` 与 `NOT _bFaultLatch`。
- (e) 无恒假谓词；`_nCount` 单点写入（L208），复位路径不清计数（L234-236 只清锁存与码），与件头 ④/⑤ 声明一致。

**MAJOR-1 · L142 / L184 · 风机反馈不符窗 3s 对**「应停却在转」**方向同样生效 → 融霜入口稳定误报码 3**
```
L142: _bFanMismatch := _bRunActive AND (bFanFeedback <> _bFanExpect);
L140: _bFanExpect := eCooling OR eFrostDetect OR eRecover;   // ⇒ eDefrost/eDrip 期望 FALSE
L184: tonFanFb(..., PT := DL_DFS_FB_WIN);                    // T#3S
```
推演：eCooling→eFrostDetect→eDefrost，进 eDefrost 当拍 `_bFanExpect` 变 FALSE，而离心/轴流冷风机惯性降速普遍 5~15s，`bFanFeedback` 在此期间仍为 TRUE → `_bFanMismatch` 持续真 → 3s 后 `tonFanFb.Q` → 段 4 锁存**码 3**（L259-263）→ 每次正常除霜都被判故障，除霜周期实际不可用；对称地，eCooling/eRecover 风机的加速段（反馈尚未为真）同样落在 3s 窗内。这不是调参能解的窗口问题：两个方向的物理时间常数差一个量级，共用一个 3s 窗必然误报。
最小修法（不改结构，2 处）：① 只对「应当运转却无反馈」方向监视——`_bFanMismatch := _bRunActive AND _bFanExpect AND (NOT bFanFeedback)`；② 若确需监视「应停却在转」，另配一只 `tonFanStop`，`PT := T#15S`（或做成引脚 `tFanStopMax` 并加域闸），且仅在 `NOT _bFanExpect` 相内计时。

**MINOR-1 · L168 + L233 · 参数非法属持续成因，复位后一拍复跳**
推演：bEnable 落沿→再升沿 → 段 3 清锁存迁 eIdle（L234-236）；下一拍段 1 因 `NOT _bCfgOk` 仍真且 bEnable 仍真 → 立即重锁存码 4（L168-172）→ 段 5 迁 eFault。行为是正确的（组态错误不应被复位掩盖），但 HMI 上表现为「复位无效、只闪一拍空闲」。建议在文档/注释中显式声明该「复位不灭持续成因」语义（如需改行为，可在 eFault 复位时同时要求 `_bCfgOk`）。

**MINOR-2 · L286 · `bDefrostAlarm` 与 `bError` 恒等（冗余出口）**
`bDefrostAlarm := _bFaultLatch;` 与 `bError := _bFaultLatch;`（L288）完全同源，件头却声明「除霜告警（故障锁存派生位，需人工/复位确认）」。冗余不影响行为，建议改派生为「码 1/2/3 工艺类故障」或直接并入 bError 说明。

**MINOR-3（超出本件边界，仅记录）**：eRecover→eCooling（L227-229）压缩机立即启动、复位后亦立即启动，无最短停机延时；件头已声明压缩机高低压保护与联锁归压缩机组保护件，本件不重复实现 —— 归为边界内，不扣分。

## 三、结论与处置

| 分级 | 件数 | 明细 |
|---|---|---|
| BLOCK | 0 | — |
| MAJOR | 3 | MultiTank L240（bAbort 不抑制启动，安全侧）；Conveyor L174-177（饥饿计数失效）；Defrost L142/L184（除霜每周期误报码 3） |
| MINOR | 7 | MultiTank L289/L240、L142；Dryer L290-293、L139、L340/L265；Defrost L168/L233、L286 |
| toolchain_fixes | 0 | 本轮三只自愈脚本均未触发 |

**裁决**：4 件 L2 真编译全部 PASS，**无 BLOCK**；3 件各带 1 条 MAJOR，按「MAJOR 在安全侧须阻断、其余挂账但本轮必修」的口径，**建议 MultiTank / Defrost 的 MAJOR 在本轮收尾前就地最小修（各 1~2 行，行为零变更边界的除外）**，Conveyor 的 MAJOR 可挂账至 R81 但须登记验收债项。MINOR 全部挂账。

> 边界声明：本席未修改任何业务源码、registry、JSONL 与文档；上述「最小修法」交编码席执行。
