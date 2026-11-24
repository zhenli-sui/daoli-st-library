# RAW_NOTES_R57 来源台账（2026-11-21，WebSearch 预算归零零检索轮）

| 来源 | URL | 许可证 | 提取点 |
|---|---|---|---|
| T0（IEC 61131-3 标准函数/功能块防御性包装） | 无外部 URL | IEC 61131-3 标准语义，道莅防御性实现，无外部代码 | TpRetrigger / EdgeMasterSlaveSync / EncoderQuadCount / SignalStagnationWatch / AsinSafe / AcosSafe / LogSafe / ExpSat / PowIntSat / SignumCalc / RmsCalc / ParityCalc / PeakToPeakCalc / InterpStepNearest——共 14 件，委托平台内建 + 统一错误码/钳位/双语文档，禁重实现数学内核 |
| T1-2 OSCAT Building（ROOM_CONTROL 待挖子项） | https://www.oscat.de/ （OSCAT Building 3.3x 手册页） | OSCAT 许可（免费使用，需致谢） | NightPurgeSeq：只取「夜间吹扫行为定义 + 温差/时段判据参数域」，零代码行复制；与 FrostProtectFreeze 分工写进头注释 |
| T1-1 OSCAT Basic（域外行为显式化纪律） | https://www.oscat.de/ | OSCAT 许可（免费，需致谢） | SensorDropoutHold：只借「断线/无效保持上次有效值 + 掩码标出」写法纪律（R11 NtcTempScan 同口径），实现与常量自有 |
| T2-2 LBP 基础工艺库（三段分层骨架） | https://support.industry.siemens.com/cs/document/109766793 （LBP Library of Basic Processes V2.x 文档页） | 免费使用但闭源版权（只借分层结构与参数域，零代码行） | PassboxInterlockSeq：「命令-监视-判定」三段分层骨架借用（R11/R13 先例同口径），状态机/码位/判据 100% 自有 |
| T2-8 ISA-88 / ISA-18.2 / NAMUR NE107 | 公开标准条款（ISA-TR88 / NE107 状态模型摘要页） | 公开规范（clean-room 条款引用） | ProofTestSeq：证明试验相语义 + eCheckFunction/eMaintenanceReq 六态映射（引用唯一属主 E_DL_Ne107Status，不重复声明）；EsdGroundMonitor 健康出口次源同口径 |
| ROADMAP R56 评估转正（ESD 族，半导体 ESC 自研线） | 无外部 URL | 道莅自研（公开工程惯例） | EsdGroundMonitor / IonizerAirflowInterlock：ROADMAP L1086 评估项转正，先拆可验收粒度（电阻窗 / 风速窗 + 迟滞 + 确认窗） |

## 本轮检索结论
- WebSearch 0 次（预算归零）；全部来源复用 SOURCE_HUNTING_MATRIX.md 既有记录与公开标准语义，零外部仓库抓取、零代码行复制。
- T0 组状态：本轮触及 T0-1（主从沿变体）、T0-2（TP 变体）、T0-3（正交计数变体）、T0-4（Asin/Acos/LN/EXP/EXPT 补口）、T0-6 关联纪律（无字符串新件——StringXxxEx 族实测已覆盖，见拒单记录）——均为既有 ◐ 行深化，无 ☐→◐ 开组、无 ◐→✔ 收口申报。
- 撞名教训（记 AGENT_EVOLUTION_LOG 候选）：T0 各族「Ex 系」命名已高度覆盖，下轮候选生成前必须先跑 `StringXxxEx / XxxEx / XxxSat` 三类后缀正交扫描，再拟新名（本轮 36 个候选中 19 个被拒，命中率 47%，下一轮应先查后拟）。
