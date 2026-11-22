# RAW_NOTES_R67 — 来源留痕（2026-11-22，零检索轮）

> 本轮规划 0 次 WebSearch，全部复用 `SOURCE_HUNTING_MATRIX.md` 既有组与 R66 REVIEW 挂账，未开新源、未重复检索任何已挖源。

| 来源标签 | 矩阵行 | URL/出处 | 许可证 | 提取点 → 目标件 |
|---|---|---|---|---|
| self-std | 自研/挂账线 | `REVIEW_R66.md` §二 | 库内自有 | QuadPolyFit M2+L1 / LotMergeGate L2+L3 / TaktPaceMonitor L4 点修规格 |
| t2-1-lgf-math | T2-1 LGF「Math Operations」组（◐ 深化） | Siemens LGF V5.3.0 文档 ID 109479728（只借分类与参数域，铁律 1 clean-room） | 免费闭源，禁抄代码 | 距离/角度/归一化分类 → CalcDistance2D / AngleDiffRad / NormTo01 |
| t2-1-lgf-technology | T2-1 LGF「Technology Operations」组（◐ 深化） | 同上 | 同上 | 变化率评估语义 → SlewRateCalc |
| t2-1-lgf-signalgen | T2-1 LGF「Signal Generators」组（◐ 深化） | 同上 | 同上 | 信号发生器分型（Sine/Sawtooth 已有，补三角波）→ TriangleGenerator |
| t2-8-ne43 | T2-8 NAMUR NE43 信号质量契约（R12 已落地 2 件先例） | NAMUR NE43 公开判据 | 公开规范 | 失效保持/陈旧超限语义 → LastGoodValueHold |
| t1-1-oscat-basic | T1-1 OSCAT Basic 3.3x（◐） | oscat.de | OSCAT 许可（免费，需致谢） | IMPULSE 脉冲继电器触发语义 → ImpulseRelay（clean-room） |
| iec-std-wrapper | T0-6 字符串组（✔ 收口后补口） | IEC 61131-3 标准字符串语义 | 标准（无版权文本） | HEX 文本互转防御包装 → HexToStr / StrToHex |

合规结论：全部为「既有组深化/补口 + 公开规范判据 + 标准语义包装」，无 GPL/AGPL 触碰，无闭源代码行复制，可商用。

*R67 狩猎线 ｜ 零检索轮 ｜ 道莅工控代码库产品总监*
