# -*- coding: utf-8 -*-
"""R25 VERSION.md 增量：当前版本表计数/版本行+库总版本行就地更新，历史正文不动，末尾追加 vX.Y.Z 节（追加式）。"""
import re, os

os.chdir("C:/Library")

SPEC = {
 "DL_MathData": dict(old="1.17.0", new="1.18.0", comp_old=151, comp_new=152, adds=1, lines=172,
   row="| `FC_DL_Affine2DInvert` | v1.0.0 | 二维仿射矩阵求逆（2x2 伴随 + 平移列反算，奇异出零阵不泄半逆） | T2-1 LGF Math 仿射族补口（clean-room） |",
   note="R25 新增仿射逆映射 1 件，仿射「合成-应用-逆」三元闭环齐备", cur="信息级推进至 **`0471`** ｜ 故障级推进至 **`03BF`**"),
 "DL_Algo": dict(old="1.12.0", new="1.13.0", comp_old=44, comp_new=48, adds=4, lines=1335,
   row="""| `FB_DL_ParticleCounterStat` | v1.0.0 | 洁净室粒子计数 ISO 14644-1 等级判定（表驱动 + 失采识别） | ROADMAP P1 §253 |
| `FB_DL_CoolingTowerApproachCalc` | v1.0.0 | 冷却塔逼近度计算与加/减风机台数建议（湿球组合调用） | R24 增补池 |
| `FB_DL_DuctStaticReset` | v1.0.0 | 风管静压设定重置（最不利阀位 + 死区 + 限斜率） | ROADMAP P1 §291 |
| `FB_DL_DewpointReset` | v1.0.0 | 冷冻水供水温度按露点重置（露点 + 余量 + 斜率限制） | ROADMAP P1 §293 |""",
   note="R25 新增暖通/洁净室算法 4 件（0x33~0x36 四个 CC 子块）", cur="下一 CC 子块 **`0x37`**"),
 "DL_Device": dict(old="0.14.0", new="0.15.0", comp_old=72, comp_new=76, adds=4, lines=1245,
   row="""| `FB_DL_InverterGridSync` | v1.0.0 | 逆变器并网四窗核对与合闸许可（只出许可不控合闸） | ROADMAP P1 §233 |
| `FB_DL_HeatPumpDefrost` | v1.0.0 | 空气源热泵三条件除霜顺控（最小间隔 + 超时强制退出） | ROADMAP P1 §290 |
| `FB_DL_VavBoxCtrl` | v1.0.0→**v1.0.1** | 压力无关型 VAV 风量闭环 + 风阀限幅（反馈无效保持开度）。**R25 终审修复**：非有限闸的安全侧赋值原写 fOpenMinPct，而下限脚本身在本闸判定集合内 → NaN 下限会把 NaN 当安全值出口；改为先算可用下限 fFloorPct（脚非有限回默认 20%） | ROADMAP P1 §289 |
| `FB_DL_WaferMapping` | v1.0.0 | 晶圆盒槽位 Mapping（片位图 + 空位/双片/斜插三分型） | ROADMAP P1 §251 |""",
   note="R25 新增设备抽象 4 件", cur="信息级推进至 **`0198`** ｜ 故障级推进至 **`0375`**"),
 "DL_Motion": dict(old="0.14.0", new="0.15.0", comp_old=36, comp_new=38, adds=2, lines=702,
   row="""| `FB_DL_StackingAlignCtrl` | v1.0.0 | 叠片机 CCD 纠偏（标定矩阵经 FC_DL_Affine2DInvert 求逆 + 行程限幅 + NG 锁存） | ROADMAP P1 §210 |
| `FB_DL_LabelApplySync` | v1.0.0 | 贴标同步出标（编码器提前量 + 低速暂停出标） | ROADMAP P1 §271 |""",
   note="R25 新增运动封装 2 件", cur="信息级推进至 **`01EF`** ｜ 故障级推进至 **`0312`**"),
 "DL_Process": dict(old="0.14.0", new="0.15.0", comp_old=48, comp_new=57, adds=9, lines=3720,
   row="""| `FB_DL_RoomClimateCtrl` | v1.0.0→**v1.0.1** | 房间温湿度双回路耦合控制（双 PID 分程 + 防结露联锁 + 冷侧优先仲裁）。**R25 终审修复**：补失能出口收口（段 11）——PID 件失能输出回 rOutMin=−100%，经分程映射为 100% 冷却，四阀归零要等下一拍 eIdle，失能沿那一拍破坏「失能=四阀回 0%」契约 | T1-2 OSCAT ROOM_CONTROL 开族第 2 件 |
| `FB_DL_WeightCheckReject` | v1.0.0 | 动态称重与剔除控制（滤波窗 + 剔除反馈拒动诊断 + 停线判据） | ROADMAP P1 §272 |
| `FB_DL_CasePackerPattern` | v1.0.0 | 装箱排列图案生成（容量钳位 + 交错/层旋转） | ROADMAP P1 §273 |
| `FB_DL_BatteryTestCycler` | v1.0.0→**v1.0.1** | 单通道电池充放电工步机（恒流/恒压/静置 + 安时积分 + 温度电压硬判断流）。**R25 终审修复**：补 eFault 独立 CASE 标签——原 eFault(99) 落进 ELSE 兜底支路，每拍把 034B/034C 覆盖成 034D「非法状态」，激励消失后真因码丢失 | ROADMAP P1 §215 |
| `FB_DL_PalletizerLayerSeq` | v1.0.0→**v1.0.1** | 码垛层排布顺控（层容量自算 + 奇偶层旋转经 FC_DL_Affine2Apply + 取放握手重试）。**R25 终审修复**：①旋转层阵外平移量由 fPalletLengthMm 改为 (nRowsEff−1)×箱宽（原式整体多推一个箱宽致首行越界）；②bPalletDone 取消同拍自撤（原同拍置位又撤位，脉冲永不外显） | R24 增补池 §1022 |
| `FB_DL_SplicerAutoJoint` | v1.0.0→**v1.0.1** | 自动接膜零停机顺控（余量面积折算 + 同步双条件 + 未同步绝不裁切）。**R25 终审修复**：eSyncWait 补「进相前置消失」第二退出条件（bNewRollReady 撤销退回 ePreAccel）；遗留挂账：同步相无自有超时，下轮新增 tSyncMax（MINOR） | ROADMAP P1 §280 |
| `FB_DL_ChillerSeqMgr` | v1.0.0 | 冷水机组群控（双延迟加减机 + 轮值委托 FB_DL_DutyStandbyRotation + 供水低温保护） | ROADMAP P1 §288 |
| `FB_DL_FormationChannelMgr` | v1.0.0 | 化成/分容柜多通道调度（分配 + 异常通道隔离锁存 + 台账） | ROADMAP P1 §209 |
| `FB_DL_SolarStringGroundFault` | v1.0.0→**v1.0.1** | 光伏组串对地绝缘阻抗检测（不平衡电桥 + 分级确认锁存）。**R25 终审修复**：组态闸补 fWarnKOhm ≥ 上限哨兵 1.0E9 kΩ → 035A（防哨兵值被判成「低于预警阈值」误报警）；量纲链经总监独立验算裁定除式 Rb×(Vp+Vn)/(Vbus−Vp−Vn) 正确、派单乘式倒置 | R24 增补池 §1023 |""",
   note="R25 新增工艺模板 9 件（含 T1-2 ROOM_CONTROL 开族、电池/码垛/接膜/群控/化成/光伏）」",
   cur="信息级推进至 **`0412`** ｜ 故障级推进至 **`035D`**"),
}

for cat, s in SPEC.items():
    p = "%s/VERSION.md" % cat
    txt = open(p, encoding="utf-8", newline="").read()
    assert "**v%s**" % s["old"] in txt, (cat, "version row missing")
    txt = txt.replace("| 子库版本 / Sublibrary Version | **v%s** |" % s["old"],
                      "| 子库版本 / Sublibrary Version | **v%s** |" % s["new"], 1)
    txt = re.sub(r"\*\*%d\*\*（以注册表 counts 为准" % s["comp_old"],
                 "**%d**（以注册表 counts 为准" % s["comp_new"], txt, count=1)
    txt = re.sub(r"(\| 库总版本 / Library Version \| )v[\d.]+", r"\g<1>v2.14.0", txt, count=1)
    sec = ["", "---", "",
           "## v%s ｜ 2026-11-17 ｜ R25 %s / R25 Batch" % (s["new"], s["note"]),
           "",
           "**批次**：本轮 20 件中本子库 **%d 件**，合计 **%d 行**（全库 20 件 7,097 行，终审修复后 7,174 行）" % (s["adds"], s["lines"]),
           "**码位游标（收口后实测）**：%s" % s["cur"],
           "",
           "| 组件 | 版本 | 一句话功能 / 终审结论 | 来源 |",
           "|---|---|---|---|",
           s["row"],
           ""]
    open(p, "w", encoding="utf-8", newline="").write(txt.rstrip("\n") + "\n" + "\n".join(sec))
    print("updated", p, "->", s["new"])
