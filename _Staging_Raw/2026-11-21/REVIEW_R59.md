# R59 五抽终审报告（2026-11-21 · 无人值守轮 · 按 R333 只挂账不改码）

抽查件：FB_DL_TwoStepConfirm（DL_Base）｜ FB_DL_MracAdaptiveCtrl（DL_Algo）｜ FC_DL_FftRadix2（DL_MathData）｜ FB_DL_LotoSequence（DL_Process）｜ FC_DL_ConductivityTempComp（DL_MathData）
定级口径：严重（编译阻断/安全语义漏洞）/ 中（静默非有限、闸穿透）/ 轻（边界竞态、风格）/ PASS

## 终审矩阵

| 件 | 定级 | ①死代码 | ②静默 | ③粘滞 | ④窗口末退出 | ⑤前置闸 | ⑥声明 | ⑦回夹/混用 |
|---|---|---|---|---|---|---|---|---|
| FB_DL_TwoStepConfirm | 轻 | ✔ | ✔ | ✔ | ✔ | ✔（无除法） | ✔ | ✔ |
| FB_DL_MracAdaptiveCtrl | 中 | ✔ | ✘ | —（连续量） | — | ✘（闸覆盖不全） | ✔ | ✔（单点回夹） |
| FC_DL_FftRadix2 | PASS | ✔ | ✔ | — | ✔（WHILE 有界） | ✔ | ✔ | ✔ |
| FB_DL_LotoSequence | 中 | ✔ | ✔ | ✔ | ✔ | ✔（下标闸齐） | ✔ | ✘（相迁移漏复检） |
| FC_DL_ConductivityTempComp | PASS | ✔ | ✔ | — | — | ✔（分母闸防负） | ✔ | ✔ |

## 逐条定位与修复建议

### 1. FB_DL_MracAdaptiveCtrl — 中（2 处，合并记 1 件）
- **L92~L97**：`_bFin` 有限闸只覆盖 fRefCmd/fYMeas/fGamma/fSigma，**漏 fDtSec/fTmSec/fKmin/fKmax 四参数**。NaN 借 `_bCfg` 比较恒假侥幸兜住，但 `fTmSec=+Inf`（过域闸）、`fKmax=+Inf`（过钳位序闸）直穿：L111~L118 增益无界发散、fU 可为 ±Inf 且 bBad=FALSE / bValid=TRUE，非有限静默穿透（违纪律②）。
  修复建议：`_bFin` 扩为八参数全覆盖；`_bCfg` 对 fKmin/fKmax 追加有限判据。
- **L86~L89 + L122**：首拍 `_fModel := fYMeas` 在闸判之前执行，若首拍 fYMeas=NaN，闸拦后走 ELSE 分支，L122 `fModelY := _fModel` 把污染状态原样送上输出（状态冻结分支同样禁静默非有限出口）。
  修复建议：ELSE 分支对 fModelY/fETrack 出口加非有限防护（污染即置零）。

### 2. FB_DL_LotoSequence — 中（1 处）
- **L121~L128**：`eLotoIsolate` 迁移判据 `(_nOk >= nIsoCnt) AND bTagLedger` **未复检 bError**。运行中把 nIsoCnt 改为 0 → 段 2 置 bError 锁存，但隔离相仍满足 `_nOk(0) >= 0` 双闸齐 → 迁 `eLotoLocked`，实现 **0 隔离点上锁**（安全语义漏洞）。同族 eLotoIdle(L117)/eLotoUnlocked(L147) 已查 bError，唯 isolate 漏。
  修复建议：迁移判据补 `AND (NOT bError)`；并建议 CASE 全部迁入上锁路径的判据统一携带闸位复检（模板级）。
- 观察项（不计缺陷）：L85 `tonTry` IN 用前一拍 `_ePhase`，一拍延迟，与 R7 无冲突，仅记录。

### 3. FB_DL_TwoStepConfirm — 轻（1 处）
- **L67~L70 与 L73~L79 同拍竞态**：窗口到期拍恰逢二按上升沿时，段 3 先置 `_bArmed:=FALSE` + bTimeout，段 4 读到 `NOT _bArmed` 按首按处理重新武装——二按被吞，用户需按第三次。发生概率低（一个扫描拍窗口）但属于可消除竞态。
  修复建议：段 4 判据改为「本拍沿且沿到达时仍在窗内」（先消化沿判据、再消化超时迁移），或段 3 超时迁移前预消化 rtBtn.Q。

### 4. FC_DL_FftRadix2 — PASS
逐项核过：非有限逐点早退（L90~96）✔；除子 nN-1 受点数闸 nN≥2（L84/L101）✔；位反转 WHILE 步进位折半有界（L112~115）✔；蝶形下标 nBase+nJ+nHalf < nLen ≤ nN ≤ 256 全程有界 ✔；输出数组全量预清零（L73~76）✔；全部局部变量声明齐 ✔。

### 5. FC_DL_ConductivityTempComp — PASS
逐项核过：非有限四参数全覆盖（L70~73）✔；分母下限闸同时防除零与负分母（含 fRefTempC 越域产生大负 ΔT 场景，L99~103）✔；四段式出口预置齐（L62~67）✔；信息级 bOutOfRange/bClamped 与故障级 bError 分轨清晰 ✔。

## R60 挂账清单（按优先级）

| # | 优先级 | 件 | 挂账内容 |
|---|---|---|---|
| 1 | P0 | FB_DL_MracAdaptiveCtrl | `_bFin` 扩 fDtSec/fTmSec/fKmin/fKmax 四参数有限闸；ELSE 冻结分支 fModelY/fETrack 非有限出口防护 |
| 2 | P0 | FB_DL_LotoSequence | eLotoIsolate 迁移判据补 `AND (NOT bError)`（0 隔离点上锁安全漏洞） |
| 3 | P1 | FB_DL_TwoStepConfirm | 窗口到期拍与二按沿同拍竞态，二按被吞；超时迁移前先消化本拍沿 |
| 4 | P2 | 机检增补 | 「有限闸/域闸参数覆盖率」扫查：闸条件未引用的 LREAL 输入参数清单化报警，防 Mrac 族复发 |
| 5 | P2 | FB_DL_LotoSequence | tonTry 一拍延迟观察项确认（低风险，可只记不改） |

统计：**严重 0 / 中 2 / 轻 1 / PASS 2**，无编译阻断级缺陷。
