# R57 五抽终审报告（2026-11-21 · 抽样 5/20）

**严重 0 / 中 4 / 轻 2 / PASS 1**

抽样：FB_DL_EncoderQuadCount（必审）/ FC_DL_PowIntSat（必审）/ FB_DL_PassboxInterlockSeq（必审）/ FC_DL_RmsCalc（自选）/ FB_DL_NightPurgeSeq（自选）。逐件 .st 全文判读，7 项红线 + F 检项（R240 双向对齐 / R128 枚举⊆CASE）+ 语义三层。

## 审查明细

| 名称 | 严重度 | 位置(行) | 现象 | 修法 |
|---|---|---|---|---|
| FB_DL_EncoderQuadCount | 中 | L71-75 / L95 / L163 | 边界一声明「首拍无假边沿」，但 `_eGrayPv` 初值恒 eQ0，上电时实际格雷态非 00（如 01）则首拍判 00→01 正向假步进 +1；且段 1 `_bInit` 块对 `_eGrayNow` 赋值被段 3 当拍覆盖，属死代码 | 首扫把基准态同步为当拍实测：段 6 前加 `IF NOT _bInit THEN _eGrayPv := _eGrayNow; END_IF`（或在段 6 无条件推进后于首扫回写）；段 1 死代码整块删除 |
| FB_DL_EncoderQuadCount | 轻 | L155-159 | 丢步回绕钳制写法 `+1 后判 =4294967295 回拨 4294967294`，等效钳制但口径绕（终审两式第 2 条：判式应为 >= 而非 =） | 改为 `IF nMissCnt >= 4294967294 THEN nMissCnt := 4294967294; ELSE nMissCnt := nMissCnt + 1; END_IF` 单向钳制 |
| FC_DL_PowIntSat | 轻 | L64-82 | 负指数钳位（置 0002_0002）与底 0 的 0 次幂（置 0002_0003）同拍命中时，后者覆盖前者错误码，违背段 5「首事件优先置码」自家庭口径 | 0^0 判定段改 `IF eErr = 16#0000_0000 THEN eErr := 16#0002_0003; END_IF`（保留先到码） |
| FC_DL_PowIntSat | PASS | — | 双判据非有限闸 ✓ 指数钳位 [0,63] 端点 ✓ 乘前预检防 Inf（除子已证>0）✓ 负底奇偶显式分支 ✓ 段 5 兜底带码 ✓；其余口径合格 | — |
| FC_DL_RmsCalc | 中 | L90-93 | 结果非有限兜底只置 `bValid := FALSE`，不置 eErr/bError：单样本 x² 溢出致 sum=Inf → SQRT(Inf)=Inf 被第二判据捕获归零，但错误码保持 0000，**静默降级**；与 FC_DL_PowIntSat 段 5（置 0002_0001 三件套）家族口径分裂 | 兜底块补 `IF eErr = 16#0000_0000 THEN eErr := 16#0003_0005; bError := TRUE; END_IF`（0003_0005 为本族新码「结果溢出已归零」，需与族内码段连续性核对后定值） |
| FB_DL_PassboxInterlockSeq | 中 | L72 / L132 | `bReqRejected` 仅在 eIdle 双请求分支置 TRUE，**全文件无任何清零路径**，宣称「信息级单拍」实为永久锁存，首次双请求拒绝后恒 TRUE，诊断保真失效 | 统一出口段（段 5 开头）每拍预置 `bReqRejected := FALSE;`，CASE 内只写 TRUE（单拍位生命周期收归出口段） |
| FB_DL_PassboxInterlockSeq | PASS | — | 互锁安全侧方向正确（双侧同拍拒动=复位优先、命令开反馈关保守不推进、故障相命令全断）✓ 锁存解除=bReset 沿唯一可达 ✓ R100 配比 tTransferTo>tOpenConfirm 闸 ✓ 枚举⊆CASE+ELSE ✓ F 检双向对齐 ✓ | — |
| FB_DL_NightPurgeSeq | 中 | L163-170 | 执行相退出条件族缺「夜间窗结束」判据：06:00 窗末后若温差仍 > 退出阈值且许可保持，吹扫将持续全天（组件定位为**夜间**免费制冷），进入判据 `_bNight` 与退出判据不对偶 | 执行相退出链增一条：`ELSIF (NOT _bNight) AND tonMinRun.Q THEN _ePhase := E_DL_NpsPhase.eDwell;`（串 tonMinRun 尊重最小执行时长，与温差退出同构） |
| FB_DL_NightPurgeSeq | PASS | — | 序数法跨午夜无 MOD ✓ 0.5 K 回差进入全阈值/退出减回差 ✓ 非有限双温度闸+传感优先归因 ✓ 组态闸覆盖阈值/序数/零长窗 ✓ bWinCmd 安全侧常闭 ✓ | — |

## F 检项结论（R240 / R128）

- 五件私有变量「引用 vs 声明」双向对齐 **全部通过**（本轮无未声明引用、无死私有变量；R55 CoinCell 式 `_eCause` 死变量未复现）。
- 枚举成员 ⊆ CASE 标签：`E_DL_EncGray` 4/4、`E_DL_PbiPhase` 5/5（eFault 空体标签合法）、`E_DL_NpsPhase` 3/3 **全部通过**，ELSE 兜底齐备。
- TON/R_TRIG 段 0 无条件刷新：五件全部合规，无定时器入分支。

## 汇总

- 严重 0 件：R58 无编译阻断级挂账，编码代理额度可全部投新件。
- 中 4 处 × 4 件（每件 1 处）：均为「单拍位无清零 / 兜底静默降级 / 进入-退出判据不对偶 / 首拍基准态未同步」四类家族性口径问题，按 R333 挂账 R58 首位返修（本轮未改码）。
- 轻 2 处：错误码首事件覆盖（PowIntSat）、钳制判式写法（EncoderQuad），随中项返修顺带收口。
