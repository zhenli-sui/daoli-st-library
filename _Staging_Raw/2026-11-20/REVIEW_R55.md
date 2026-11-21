# R55 五抽语义终审报告（2026-11-20）

抽检口径：非有限值穿透出口 = 中及以上；状态回夹 / 复位不清 = 严重；死变量 / 注释瑕疵 = 轻。
无人值守轮（R333）：缺陷只挂账下轮返修，不当场改码。

## 逐件判定

### 1. FB_DL_CoinCellAssembler（DL_Process，cx5）—— 判定：轻

- 现象：内部变量 `_eCause`（信息级成因工作值）全文件仅在首扫清零与出口映射处出现，没有任何赋值路径写入非 eNone 值，属死变量；信息级成因通道实际永不生效。
- 其余自洽：五窗互斥证明成立；锁存解除（rtReset 沿清 `_bFault`/`_eFaultCause`）可达；命令预置-撤销两段式无回夹；压紧力非有限判据（自反 + 差值自减）完备。
- 行级修法：删除 `_eCause` 死变量并简化段 7 出口映射（或为后续信息级成因预留时补注释声明其恒空契约）。

### 2. FB_DL_StringElImageMap（DL_Process，cx4）—— 判定：轻

- 现象：复位沿（段 2）声称"清故障锁存与全部统计"，但未清最近归档出口 `fLastXmm / fLastYmm / fLastSizeMm2 / nLastType`，复位后旧缺陷坐标残留在出口；`_stCur.uBatchId` 也未随复位重同步，复位后首条新批报告可能被误判入旧批窗口（仅批号恰好回绕到同值时触发，概率低）。
- 其余自洽：环窗回钳 1..64、先算槽位后写入顺序正确；除零闸（`_fPrevMaxB > 0.0`）完备；类型回钳证明 SHL 位移 0..7 成立；非有限输入不穿透出口。
- 行级修法：段 2 复位作用域补 4 行清零 `fLastXmm/fLastYmm/fLastSizeMm2/nLastType`，并补 `_stCur.uBatchId := uBatchId;` 重同步。

### 3. FB_DL_BacdHvacPoll（DL_Process，cx4）—— 判定：严重（编译阻断）

- 现象：内部工作值 `_nCurRetry` 在段 2（L143）、段 4 响应支路（L199）、超时支路（L228/229/235）、eFault 相（L281）、出口映射（L324）共 7 处引用与赋值，但 VAR 声明区从未声明该变量（仅声明了出口 `nCurRetry`）——任何平台编译即报未声明标识符，属编译阻断级。
- 次要（轻）：段 7 成因分派中 `ELSIF _nUseCount < 1` 分支恒假（`_nUseCount` 已在段 3 回钳 ≥1），`eNoDevice` 成因永远不可达，属死分支。
- 行级修法：VAR 区补声明 `_nCurRetry : INT := 0;  // 当前设备已重试次数工作值 [次] / retry working value`；死分支可删除或改为按 `nDevCount` 原始引脚判定后挂账。

### 4. FB_DL_FopdtStepIdent（DL_Algo，cx4）—— 判定：中

- 现象：切线法死区时间计算 `_fDeadTan := _fTSlopeMax - (_fPvSlopeMax - _fPvBase) / _fSlopeMax`（L396）使用的是**绝对值**斜率 `_fSlopeMax`。负向阶跃（fMvStep < 0）时 `(_fPvSlopeMax - _fPvBase) < 0`，除以正的绝对值斜率得到负的截距项，`t - 负值 = t + |截距|`，死区时间被系统性高估；两点法不受影响（T 只用 t63-t28，L = t63 - T 符号自洽），但 bUseTangent=TRUE 出口即取错误值。增益、除零、越域闸均完好，缺陷只在符号语义。
- 次要（轻）：eDone 相重启分支（L461~470）比 eIdle 分支少清 `_fPvSlopeMax / _fTSlopeMax` 两个变量，二次辨识若无新斜率峰值则残留首辨识值。
- 行级修法：L396 改用带符号斜率，如引入 `_fSlopeSig := _fSlopeMax * SIGN(_fDeltaPv);` 后以 `_fDeadTan := _fTSlopeMax - (_fPvSlopeMax - _fPvBase) / _fSlopeSig;` 求截距（分母量级仍由 `_fSlopeMax > DL_FOPDT_EPS` 证明）；eDone 分支补清两残留变量。

### 5. FB_DL_PackMlUnitMode（DL_Process，cx3）—— 判定：轻

- 现象一：段 4 模式切换受理 `_eMode := eModeReq` 前不校验 eModeReq 合法枚举；越域值（如 99）被采纳后存在一拍"非法模式窗口"，下一拍才被段 3 两级回退拉回 eProduction，且该次采纳/回退均无拒绝留痕（_eReject 保持 eNone），外部 HMI 无从察觉。
- 现象二（注释瑕疵）：段 9 / 段 10 头注释错标 "segment 10 / segment 11"（L374、L380），段号漂移。
- 其余自洽：过渡超时→强制 eAborting 后故障锁存虽使 eClear 命令被段 7 `NOT _bFault` 闸住，但 bReset 沿解除路径可达（段 2），不构成恒假锁死；命令闸"状态闸在前、模式闸在后"顺序一致；受理/拒绝单拍脉冲两段式无回夹。
- 行级修法：段 4 受理前补枚举合法性校验（仿段 3 五选一判式），非法请求改记 `_eReject := E_DL_PmlReject.eModeBlocked;` 不采纳；注释段号回正。

## 汇总

| # | 组件 | 子库 | 判定 | 缺陷等级挂账 |
|---|------|------|------|--------------|
| 1 | FB_DL_CoinCellAssembler | DL_Process | 轻 | `_eCause` 死变量（1 处族） |
| 2 | FB_DL_StringElImageMap | DL_Process | 轻 | 复位作用域漏清 4 出口 + 批号重同步（1 处族） |
| 3 | FB_DL_BacdHvacPoll | DL_Process | **严重（编译阻断）** | `_nCurRetry` 未声明 7 处引用 + eNoDevice 死分支 |
| 4 | FB_DL_FopdtStepIdent | DL_Algo | **中** | 切线法负向阶跃死区符号错（1 处）+ eDone 漏清 2 变量 |
| 5 | FB_DL_PackMlUnitMode | DL_Process | 轻 | eModeReq 采纳前未校验（1 处）+ 段号注释漂移（2 处） |

- 挂账合计：严重 1 件 / 中 1 件 / 轻 3 件。按 R193/R194 记账：返修处数 = 7（BacdHvacPoll 未声明引用）+ 1（Fopdt 符号）+ 2（Fopdt 漏清）+ 1（SEI 复位族）+ 1（CCA 死变量）+ 1（PML 校验）+ 2（PML 注释）= 15 处 × 5 件 × R55 批次。
- 抽检挂账 5/5，触发"抽检不是免责"扩检条款候选：下轮建议对 R55 批 4 的其余组件做同族复查（尤其批 4 的声明区完整性）。
- 下轮排程首位：FB_DL_BacdHvacPoll 补声明并全库 grep `\b_nCurRetry\b` 类"先引用后声明"模式专项扫描。

（R333：本轮只挂账，未改任何源码。）
