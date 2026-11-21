# R38 返修任务书（P0，2 件，不占 20 新件名额）

> 主控 2026-11-18 23:2x 编制。两件均为 R37 终审挂账「禁止投运」，修复后版本升 v1.0.2（LineShaftClutch 现 v1.0.1 / CurtainEFEMZone 现 v1.0.1），并在头注释「修订历史」追加 R38 行、**删除**「R37 终审挂账」警示行改为「R38 已修复」。

## 返修 1：`C:\Library\DL_Motion\FB_DL_LineShaftClutch.st`

**缺陷（R37 终审）**：脱离相耦合权重起始值取成满值，脱开过程存在反向驱动风险。

**实测代码路径**：`E_DL_ClutchState.eDisengaging` 相内不自写 `_fWeight`，权重由段 6A 统一演进：
```
ELSIF _eState = eDisengaging THEN
    _fWeight := MAX(0.0, 1.0 - TIME_TO_REAL(tonRamp.ET) / (_fRampSec * 1000.0));
```
`_fWeight` 的基准硬编码为 `1.0`。凡从 **权重非 1 的相**进入脱开（典型：`eAligning` 相收到 `bDisengageCmd`／`bEnable` 掉电，此时 `_fWeight = 0.0`），进入脱开当拍 `tonRamp.ET = 0` → `_fWeight` 由 0 跳变为 **1.0**，从轴在整段 `fEngageRampTime` 内被主轴以满权重拖动（速度方向与从轴当前运动相反，即反向驱动）。`eAligning` 分支注释「权重已为 0，单拍即完」与实现不符。

**修复口径（最小改动，禁重构）**：
1. `VAR` 区新增 `_fW0Diseng : REAL := 0.0;`（脱开起始权重快照），注释中英双语。
2. 所有把 `_eState` 置为 `eDisengaging` 的分支（共 6 处：`eIdle` 命令冲突链外、`eAligning` 两处、`eRamping` 两处、`eEngaged` 两处）在置相**同一处**补 `_fW0Diseng := _fWeight;`（先快照后置相，禁在段 6A 反推）。
3. 段 6A 脱开分支改为按快照比例回落：
   `_fWeight := MAX(0.0, _fW0Diseng * (1.0 - TIME_TO_REAL(tonRamp.ET) / (_fRampSec * 1000.0)));`
4. `eDisengaging` 相内：若 `_fW0Diseng <= DL_W0_EPS`（本件常量 `DL_W0_EPS : REAL := 1.0E-6`）→ 不再等斜坡，直接 `_fWeight := 0.0; _eState := eIdle;`（单拍收口，兑现原注释语义）。
5. 补信息码 `16#0004_08A2`「脱开起始权重为 0，单拍收口」；码表同步追加一行。
6. 头注释「功能」第 2) 条补一句「脱开权重自进入脱开相的实际权重按斜坡线性回落到 0，禁跳变到满值」。

**自检点**：① 六处置相点均带快照（`grep -c "_fW0Diseng := _fWeight"` 应 ≥ 6）；② `eEngaged → eDisengaging` 路径权重 1.0 起步、`eAligning → eDisengaging` 路径 0.0 起步单拍收口，两条向量用注释写清；③ ENUM/CASE/ELSE 兜底不受影响；④ 权重出口 `fSyncWeight` 语义不变。

## 返修 2：`C:\Library\DL_Device\FB_DL_CurtainEFEMZone.st`

**缺陷（R37 终审）**：间隙计时器不随新遮光事件重启，非顺序遮光（爬行通过）可能漏判并停留屏蔽态。

**实测代码路径**：段 0 `tonGap(IN := (_nSeqLen > 0) AND (_nSeqLen < 4), PT := tSequenceGap);` —— IN 只与「序列缓冲长度」挂钩，不随新遮光沿重启。首个遮光后 ET 持续累加，`tonGap.Q` 一旦为真且序列长度仍在 1~3，Q 保持为真、ET 继续走；后续遮光事件不重置 ET，导致「相邻遮光间隔」判据从第二路起失去意义（间隔再长也不再产生新的 Q 上升沿），爬行通过时既不判顺序失败也不解屏蔽 → 停留屏蔽态（安全侧失守）。

**修复口径（最小改动）**：
1. `VAR` 区新增 `_bGapBreak : BOOL := FALSE;`（间隙计时断输入请求），中英双语注释。
2. 段 0 改：
   `tonGap(IN := ((_nSeqLen > 0) AND (_nSeqLen < 4)) AND (NOT _bGapBreak), PT := tSequenceGap);`
   调用之后紧接 `_bGapBreak := FALSE;`（与 `tonRamp` 的 `_bRampBreak` 范式一致，R182 同族）。
3. 每检测到**新遮光上升沿**（写入序列缓冲那一处，逐路 4 个分支或统一汇合点均可）置 `_bGapBreak := TRUE;`，使下一拍 ET 归零、间隙从新事件重新计时。
4. 依赖 `tonGap.Q` 的两处判据（屏蔽中序列超时、判向相超时）保持原位，不改判定语义；但须确认 `_bGapBreak` 置位当拍 `tonGap.Q` 不为真（TON 断输入即 Q=FALSE，天然满足），并在注释写明。
5. 头注释「边界」③ 追加一句「间隙计时随每次新遮光事件重启，间隔判据对每一对相邻事件均生效」。

**自检点**：① 4 路遮光上升沿路径全部能触发 `_bGapBreak`（逐条列出）；② 无新事件时 `tonGap` 仍按原语义到点置 Q；③ 屏蔽窗时限 `tMutingMax` 与序列判据互不掩盖（两条 TON 各自独立）；④ 既有 `23C/22C/21C/20C` 码表不变，若新增码须逐条入表。

## 通用红线（两件共同）

- 只改上述点，**禁改**状态机相序、码位（`16#04_0_A2` / `16#03_2_0C` 不变）、导出接口清单（`VAR_OUTPUT` 名与类型不变）。
- 保持 CRLF、UTF-8 无 BOM、双语同行注释率不低于现状。
- 版本号 → `1.0.2`；「修订历史」追加 `2026-11-18  v1.0.2  R38 返修：<一句话>`。
- 改完各自自查：`VAR_OUTPUT` 全声明、CASE 全 ELSE 兜底、TON/R_TRIG 无条件周期刷新、无 GVL/VAR_EXTERNAL/`%I`/`%Q`。
