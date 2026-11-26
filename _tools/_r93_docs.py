# -*- coding: utf-8 -*-
import io,json,datetime,re
now=datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
# README 徽章
r=io.open('README.md',encoding='utf-8').read()
r2=re.sub(r'(Total Components:\s*)([\d,]+)(\s*/\s*10,000)', lambda m:m.group(1)+'2,001'+m.group(3), r, count=2)
io.open('README.md','w',encoding='utf-8').write(r2)

# CHANGELOG 前插
c=io.open('CHANGELOG.md',encoding='utf-8').read()
blk="""## v2.85.0 — R93（2026-11-25 当日第 6 轮）

### Added
- 39 件新组件（复杂 4 / 简单 35），总库 1,962 → **2,001**（20.01%）。
- 族 A 港口岸桥/场桥：防摇摆角、梯形加速度规划、双卷筒同步、旋锁四角互锁、夹轨判定、风速分级、箱位换算、循环时间、抗倾覆力矩 + `FB_DL_GantryCraneAnchoringSeq`（C4 锚定序列）。
- 族 B 卷烟制丝线（全库真空域）：切丝宽度、梗丝膨胀率、烘丝去水、加料/加香比例、组分掺配、回潮水分、填充值、碎丝率 + `FB_DL_TobaccoCuttingLineSeq`（C4）。
- 族 C 数据中心精密空调：显热制冷量、机柜风量、冷冻水温差、送风温度重置、PUE、旁通混合、UPS 负载率、电池后备、自然冷却小时 + `FB_DL_CrahGroupEconomizerSeq`（C4）。
- 族 D 铸造砂处理：型砂水分目标、砂铁比、混砂配比、膨润土补加、紧实率、合型力、浇注时间、落砂冷却、芯砂烘干 + `FB_DL_MoldingLineSandSeq`（C4）。

### Fixed
- `FB_DL_GantryCraneAnchoringSeq`：删除「降速相驻留超时即升级锚定」（13.8~20 m/s 属降速作业区，原逻辑使 14 m/s 常风永久锚定）；故障清除由电平改下降沿（原逻辑每拍重清 + 重入锚定 → 锚定销周期性重击）；新增段 5b 总使能门；WIND_WARN 滞环判定前置（修复后 tonWarn.Q 恒真会使回 IDLE 分支不可达）。
- `FB_DL_CrahGroupEconomizerSeq`：新增 `xActive` 与段 7 使能门（未使能不下发机组台数）；段 8 故障出口受使能门与机组数钳位（原先覆盖段 7 门控且 `nUnitsAvail=-3` 会下发 -3 台）；码位分判 9602/9603/9604。

### Removed
- `FC_DL_ShakeoutCoolingTimeCalc` 拒收移入 `_quarantine/R93/`：与在册 `FC_DL_CastingSolidificationTimeCalc` 相似度 0.85（同式同三入参），且 Chvorinov 模数为「凝固时间」被误标为「落砂后冷却时间」。
"""
io.open('CHANGELOG.md','w',encoding='utf-8').write(blk+"\n"+c)

# ROADMAP 追加
road="""
### R93（2026-11-25 当日第 6 轮 · 冲刺）小结
- 入库 **39 件**（复杂 4 / 简单 35，简单 89.7%），总库 1,962 → **2,001**（20.01%），v2.85.0，SFT **2,040**。
- 四族：港口岸桥/场桥防摇与锚定（补薄 DL_Motion 181→185）、卷烟制丝线（真空域）、数据中心精密空调与冷通道、铸造砂处理与造型线。
- L2：闸席原生 **39/39 PASS**，首裁 40/40，返修复裁抓出主控修复引入的 2 处新缺陷（N1 吸收态 / N3 门控被覆盖）并全部整改。
- 审校：**零 BLOCK**（R19/R24 两项历史高发项本轮 40/40 件干净），MAJOR 5 条 / MINOR 10 条，拒收 1。
- 规划期语义驳回 8 条（制糖整族废弃换域，因煮糖批次序列与过饱和度已在册）。

### R94 待办（P0）
1. **上轮新件遗留 3 条 MAJOR**（R92）：`FB_DL_BushingPowerBalance` 缺省组态、`FC_DL_BathTempDeviationCalc` 灵敏度 /8、`FC_DL_WinderTraversePitchCalc` 输出语义 31×
2. 库内 **9 组重名 ENUM 类型**清账（`E_DL_BfgCause`/`E_DL_CssState`/`E_DL_CswCause`/`E_DL_CswState`/`E_DL_DamperState`/`E_DL_EscState`/`E_DL_PurgeState`/`E_DL_TempUnit`/`E_DL_RotaryIndexerCycleSeq_State`）
3. **198 件累计待推 CI** + 改 `workflow_dispatch`（Git Data API 更新 ref 不触发 push）
4. `dl_gate.py` 默认模式不跑 F_DECL 的判据缺陷（R93 实测：未声明符号默认模式 PASS）
5. 4 个 C4 的 `TON.PT` 上限钳位（R748 系统项）
6. `_Staging_Raw/_dedup_fingerprints.json` 本体缺失，需与 `.bak` 归并
7. 队列 273 条，可支撑约 1.8 天；DL_Base 223 仍最薄，补 1 族×10
"""
road=io.open('ROADMAP.md',encoding='utf-8').read()
io.open('ROADMAP.md','w',encoding='utf-8').write(road+road)

# AGENT_EVOLUTION_LOG
evo=io.open('AGENT_EVOLUTION_LOG.md',encoding='utf-8').read()
evo_add="""
## R93（2026-11-25 第 6 轮）进化要点
- 新增 R747~R765 共 20 条（DIRECTOR 3 / PLC 4 / OSS 3 / COMPILE 4 / QA 5，QA 由审校席本轮先行写入 R747~R751）。
- 关键：R749 码位分判（非有限量按来源分码，禁止合并成一码，否则现场换错传感器）；R750 使能门必须覆盖全部出口且不被后段覆盖；R751 整型量非负钳位。
- ★ 本轮实证（第 3 次复发）：**主控修复动作本身引入新缺陷**——2/2 次都发生在「只改被报那一处」。返修复裁必须沿数据流再走一遍出口赋值序列。
"""
io.open('AGENT_EVOLUTION_LOG.md','w',encoding='utf-8').write(evo+evo_add)
print("docs done", now)
