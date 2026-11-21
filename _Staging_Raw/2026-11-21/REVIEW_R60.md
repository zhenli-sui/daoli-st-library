# REVIEW_R60（2026-11-21 · R60 固化批次轮 · 五抽两段式终审）

> 范围：5 抽（InputShaperZv / ShiftHandoverCheck / InterpolateTable3D / Affine2DChain / AxisCmdArbiter）+ 返修件 TwoStepConfirm v1.0.1 的 R275 修复正确性复核。
> 纪律：R333 只判定与挂账，本轮零改码、不动 `.st`；表内行号为实测（`Get-Content` 逐行核对）。
> 结论（件级）：**严重 0 / 中 4 件 / 轻 0 / PASS 1 件**；处级 **中 7 / 轻 6**。无编译阻断级（R271 三族开闭词 6 件全配对、委托签名全匹配）。
> 路径订正：`FB_DL_TwoStepConfirm` 实测属 **DL_Base**，R59 memory 记 DL_Process 有误，以本次实测为准（R290）。

## 第一段 定向扫查（R279 模板模式）

| 件 | R272 闸覆盖（浮点入参/闸内引用） | R275 同拍竞态 | R274 安全相闸位 | R271 三族开闭词 | R273 冻结/ELSE 出口 |
|---|---|---|---|---|---|
| InputShaperZv | 2/2 ✔（fWn、fZeta 逐个点名，L114） | 触发沿仅 eIdle 消费，eWaitB 无输入沿→无竞态 ✔ | eIdle→eWaitB 带 bEnable∧_bFin∧¬bFault∧fWn>0 ✔（L140） | 0/0/0 ✔ | 故障相 fAmp/tDelay 冻结保持（边界五声明），脉冲 AND bEnable ✔ |
| ShiftHandoverCheck | 0 浮点入参（TIME/DINT/UDINT）→ 闸退化为 TIME 域闸 ✔ | **段 3 先消化确认沿、段 4 才判到期 ✔**（L132→L154） | eIdle→eWait 四闸齐全 ✔（L144） | 0/0/0 ✔ | 出口为状态直镜像，无污染连续量 ✔；`_bIncomplete` 双写点（L155 被 L179 覆盖） |
| InterpolateTable3D | **3/6 有效：fX/fY/fZ ✔，afX/afY/afZ 轴向量未判 ✘**；表角点 8/8 ✔ | 无状态机（纯 FC）n/a | n/a | FOR 6 / WHILE 0 / REPEAT 0，6↔6 配对 ✔ | 结果非有限兜底置 0 + 三件套 ✔（但借用 0629 码，D10） |
| Affine2DChain | 9×nUsed 全枚举 ✔（L115-124），钳位外的级未用亦未判（合理） | n/a | n/a | FOR 6 / 0 / 0，6↔6 配对 ✔ | abort 保持单位阵不外泄 ✔；信息级码置 bError ✘（D5） |
| AxisCmdArbiter | **2/8：4 源×2 浮点字段仅胜出源（_stWin）受闸**，非胜出源不入出口属有界豁免但**未登记**（D11） | n/a（纯组合件，R227 声明） | n/a | 0/0/0 ✔ | 段 3 ELSE 分支全量零赋值 ✔；段 4 降级不镜像污染量 ✔ 但双通道标签分裂（D1） |

## 第二段 快速通读（7 红线 / 双语同行注释 / CASE ELSE / TON·R_TRIG 无条件刷新 / 除零越界 / 分工 R216 / TYPE 归属 R264 / 命名 R265）

| 件 | 判定 | 通读要点 |
|---|---|---|
| InputShaperZv | PASS | 除子 `1+_fA ≥ 1`、`ωn·√(1−ζ²) > 0` 双重可证；0610 用 ABS 容差 ✔；分工具名 NotchFilter ✔；TON/R_TRIG 段 0 无条件 ✔ |
| ShiftHandoverCheck | 中 | 四条退出并列 ✔、复位清单含快照（R243）✔；`_nPending` 声明「开始沿锁定」与实现不符（D6） |
| InterpolateTable3D | 中 | 索引钳位 [0,n−2] 无越界；fSpan>容差 三道闸 ✔；ENUM 无（纯 FC，CASE 不适用）；段 6 缩进错位（D7） |
| Affine2DChain | 中 | 委托 `FC_DL_Affine2DCompose` 实参名/型全匹配（编译可通过）；三维数组切片先拷 afMk 合规；单级链漏奇异判（D4） |
| AxisCmdArbiter | 中 | 属主行声明 E_DL_AxisCmdSrc/ST_DL_AxisCmd（R264 ✔）；优先级为 ELSIF 写死而非枚举数值比较（与边界二文义有偏，轻）；首拍 eNone→有源会误发 bSwitched（轻，可接受） |

## 缺陷明细（段号 / 行号 / 成因 / 修法）

| # | 件 | 级 | 定位 | 成因一句话 | 建议修法 | 引 |
|---|---|---|---|---|---|---|
| D1 | AxisCmdArbiter | 中 | 段 4 L146-151 + 段 6 L160 | 非有限降级只把 `_stWin.eSrc` 落 eNone，`eWinner` 仍报 eSafe，双通道来源自相矛盾 | 降级同时置 `_eWinner := eNone`，或显式声明仅单通道可判 | R283/R191 |
| D2 | AxisCmdArbiter | 中 | 声明 L80 vs 段 6 L164-166 | `bError` 注释为「故障锁存位」，实现为逐拍重算，0622 故障级码不锁存、现场丢事件 | 增 `_bFault` 锁存位 + 复位引脚；或改声明为「逐拍故障位」 | R187/R191 |
| D3 | InterpolateTable3D | 中 | 段 3 L145-159 | 轴向量未做有限性点名，边界三自证「轴向量逐个判」不实；NaN 轴使 `>=` 恒假，序闸兜不住 | 三个 k 循环内并入轴元素非有限判，置 bNonFin → 独立码 | R272/R273 |
| D4 | InterpolateTable3D | 中 | 段 2 L120-121、L140-141 | 信息级码 0626 置 `bError := TRUE`，与 InputShaper/AxisCmd 侧口径相反 | 删两处置位（或全库族级裁决后统一改反侧） | R45/R285 |
| D5 | Affine2DChain | 中 | 段 4 L133-141 | nUsed=1 时 FOR 不进入，属主的行列式可逆判据整体缺失，奇异单矩阵可 bValid=TRUE 外泄 | nUsed=1 时以单位阵为左乘调一次委托 | R284 |
| D6 | Affine2DChain | 中 | 段 2 L101-106、段 5 L190-193 | 信息级码 0622 置 bError（同 D4 口径） | 同 D4 | R45/R285 |
| D7 | ShiftHandoverCheck | 中 | 段 2 L124-130 vs VAR 注释 L84 | 注释称「开始沿锁定」，实现每拍由 `nPendingItems` 重算；窗内改参即改完成判据 | 增 `_nPendingLock`，仅于 eIdle 迁入沿赋值 | R191/R259 |
| D8 | InterpolateTable3D | 轻 | 段 6 L232-253 | 7 段同构 IF 多缩进 4 空格成孤立块（无包围结构），语义等价但破坏行形一致性 | 缩进对齐 L254 | R282 |
| D9 | InterpolateTable3D | 轻 | 段 8 L276 | 0629 文义为「轴或表值非有限」，被复用于「结果非有限」，码义扩大 | 新增 0630 结果非有限 | R190 |
| D10 | ShiftHandoverCheck | 轻 | L66-67、L73-74 | UDINT 字段沿用 `n` 前缀（同族 RolloverCounterUdint 用 `u`），前缀口径分裂 | 族内统一 `u`（破坏性，走 MAJOR + 别名）或头注释登记例外 | R200 |
| D11 | AxisCmdArbiter | 轻 | 头注释边界（L21-33） | R272 有界豁免（仅判胜出源）未在边界段登记，机检按 2/8 必命中 | 边界增一条「豁免：非胜出源不入出口」 | R272 |
| D12 | InputShaperZv | 轻 | 段 0 L101 vs 段 3 L134 | `tonGap.PT` 取上拍 `_tDelay`（段 0 先于段 3），ωn 突变拍间隔滞后一扫描 | 段 3 前移，或在边界段声明该一拍滞后 | 时序 |
| D13 | InputShaperZv / ShiftHandover | 轻 | 头注释 | 两件为 E_DL_ZvPhase / E_DL_HandoverPhase 属主，但无「归属 Ownership」行，R264 反向核验会误判为漏声明 | 各补一行属主声明 | R264 |

## 返修复核：FB_DL_TwoStepConfirm v1.0.1（R275 竞态是否真堵住）

- 修法核验：段 3（L76-84）先消化本拍 `rtBtn.Q` 并置 `_bEvtTaken`；段 4（L87）判据改为 `tonArm.Q AND NOT _bEvtTaken`。**到期拍+二按同拍**：段 3 置 bConfirmed、清 `_bArmed`，段 4 被 `_bEvtTaken` 阻断 → 不再发 bTimeout、不再把二按当首按重新武装 → **原缺陷路径闭合，判定 PASS**。
- 反向向量：①仅到期无按 → 段 4 正常超时（`_bEvtTaken`=FALSE）✔；②到期拍后一拍按 → 先超时后武装（正确语义）✔；③首按拍 → `tonArm.Q`=FALSE，段 4 不动作 ✔；④`_bEvtTaken` 必须存在（删掉后确认拍会多出一个假超时脉冲），非冗余。
- 残留轻（不影响 R275 结论，挂 R61）：段 4 判据建议补 `AND _bArmed` 作双保险；`bArmed` 为实时镜像、`_bArmed` 为锁存（R191 名实双出口已达标）。

## 挂 R61 返修清单（优先级序，P0→P2）

1. **P0 D1+D2 AxisCmdArbiter**：安全侧仲裁件，降级路径双通道矛盾 + 故障级码不锁存，现场定位会指向错误源。
2. **P1 D4+D6 信息级码置 bError 口径分裂**（Table3D/Affine，2 件 5 处）：族级口径必须先裁决，否则同族横比持续分裂（R285 首扫即命中）。
3. **P1 D5 Affine2DChain 单级链漏奇异判**：退化链静默输出奇异阵，属结果正确性缺陷。
4. **P2 D3 Table3D 轴向量有限性点名**（声明-实现一致性 + R272 机检全量跑必命中）。
5. **P2 D7 ShiftHandoverCheck `_nPending` 名实不符**；余下轻项 D8~D13 同批顺手（同子库合并返修，计 6 处 × 5 件 × R60 挂账）。
6. 记账口径：中 7 处 × 4 件 × R60；轻 6 处 × 5 件 × R60。抽检挂账 ≥3 → 按 R193 下轮件数下调 20%（12 → 10 已在配额内）。
