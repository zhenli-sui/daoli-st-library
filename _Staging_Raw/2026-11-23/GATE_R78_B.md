# GATE R78 — B 批裁决表（13 件）

- 轮次: R78 / 批次: B / 裁决人: 编译闸席 dlf-compile-verifier（唯一裁决方）
- 执行方式: 串行 jobs=1，逐件 `python C:\Library\_tools\l2_check.py <路径>`（RuSTy plc.exe --check）
- 日期: 2026-11-23
- **总裁决: BLOCK**（1 件编译阻断 + 1 项 MAJOR 逻辑缺陷，均为 FB_DL_MultiZoneSetpointScheduler.st，回派编码专家）

## 一、工具链自愈记录

| 顺序 | 工具 | 结果 |
|---|---|---|
| 1 | stub_fix.py --full | 未需触发（本轮报错非桩类；STRING_GREATER/STRING_LESS A 批已补，复跑零缺口） |
| 2 | iface_stub_gen.py --verify | 未需触发 |
| 3 | reorder_methods.py / fix_end_method.py | 未需触发 |
| 4 | **l2_check.py find_def_file 兜底修复** | **已执行**：FC_DL_SaturateDecr 初判 E052（Unknown type: E_DL_SaturateErr），根因为 R78 新件未入 INDEX_REGISTRY.json，`find_def_file` 只扫 registry 组件路径定位不到属主件。已在 l2_check.py 中新增文件系统全库兜底扫描（排除 _tools/_Staging_Raw/_archive，与 _scan_iface_files 同口径），备份 l2_check.py.bak_r78b。修复后 SaturateDecr PASS |

## 二、逐件裁决表

| 文件 | 编译裁决 | 错误码 | L1 复核 | 建议动作 |
|---|---|---|---|---|
| DL_MathData/FC_DL_RateLimitReal.st | PASS | — | 通过：x<>x+(x-x)<>0 标准非有限判法；fRateMax/fDt≤0 旁路；fXPrev 非有限重建+ePrevRebuilt | 可入库 |
| DL_MathData/FC_DL_RampStepReal.st | PASS | — | 通过：fX/fXTarget/fStep 非有限闸 R272 全量枚举 | 可入库 |
| DL_MathData/FC_DL_SlewLimitLreal.st | PASS | — | 通过：同 RateLimit 家族判法，LREAL 全量闸 | 可入库 |
| DL_MathData/FC_DL_DeltaClampReal.st | PASS | — | 通过：fX/fMaxDelta 非有限闸；fMaxDelta≤0 旁路 | 可入库 |
| DL_MathData/FC_DL_SaturateIncr.st | PASS | — | 通过：枚举属主声明合法；非有限/倒置/溢出三闸 | 可入库 |
| DL_MathData/FC_DL_SaturateDecr.st | PASS（自愈后） | 曾 E052 | 通过：共用属主枚举只引用不重声明，R264 合规 | 可入库 |
| DL_MathData/FC_DL_AccelUnitConvert.st | PASS | — | 通过：CASE ELSE 拦越域；段 3 除数全常量非零 | 可入库 |
| DL_MathData/FC_DL_DynViscosityUnitConvert.st | PASS | — | 通过：同上 | 可入库 |
| DL_MathData/FC_DL_FlowMassUnitConvert.st | PASS | — | 通过：同上 | 可入库 |
| DL_Process/FB_DL_MultiZoneSetpointScheduler.st | **FAIL** | **E045** Expected array access with 1 dimensions, found 2 | **不通过（MAJOR）**：①编译阻断：嵌套声明 `ARRAY[1..4] OF ARRAY[1..8]` 但访问用逗号 2D 形式 `aSlots[_nZ,_nK]`（行 194/195/204/213×2/214×2/236/240/264，共 8 处）；②**运行时越界 MAJOR**：eHold 分支行 262-263 直接信任外部引脚 `aiZoneSlotCount`，FOR 1 TO _nCnt 前无重校验——外部在 eHold 期间改写 >8 即越界访问 aSlots（eApply 行 185 有校验，eHold 缺失） | **回派编码专家**：①8 处 `aSlots[x,y]` → `aSlots[x][y]`；②eHold 取 _nCnt 后补 `IF (_nCnt<1) OR (_nCnt>DL_MZS_SLOTS)` 故障锁存（或段 2 统一钳位快照）。状态机其余项合格：eFault 有唯一出口（bReset 沿+NOT bEnable→eIdle，行 285-291）且复位清锁存/成因/区号，CASE 全带 ELSE（含非法枚举兜底行 281-286），段尾迁移闸（行 292） |
| DL_Process/FB_DL_PalletizerLayerBuildSeq.st | PASS | — | 通过：tonPhase 在 CASE 外无条件调用（FB50-1①），IN 含 `_eState=_eStatePrev`，相切换 IN 落沿 ET 自清；CASE ELSE；相超时双出口（ePick/ePlace）均锁存成因 | 可入库 |
| DL_Motion/FB_DL_WinderTensionTaperCalc.st | PASS | — | 通过：校验顺序正确（非有限闸行156→组态倒置闸行160 保证 `fDiaMax-fDiaCore>0`→卷径闸行175→MIN/MAX 钳位→除法行189 除零不可达） | 可入库 |
| DL_Device/FB_DL_AnalogSensorHealthClassify.st | PASS | — | 通过：σ² 除法前有 `_nCnt<1` 守卫（行 246，eNoSample 哨兵零出口）；组态闸 nStuckWinNeed<1 拒绝；tonWin 统计窗 CASE 外无条件调用 | 可入库 |

## 三、L1 复核清单逐项结论（8 项）

| 检查项 | 结论 |
|---|---|
| 状态机 eFault 出口/复位回 eIdle | ✓ 三 FB 均达标（MultiZone 行 285-291 唯一出口，复位沿清锁存+成因+区号） |
| CASE 全带 ELSE | ✓ 全部 CASE 块含 ELSE（含非法枚举兜底，awk 逐块扫描零缺） |
| TON 相位计时/相切换 ET 自清 | ✓ tonPhase IN 含 `_eState=_eStatePrev` 相切换自清；两件均 CASE 外无条件调用 |
| 数组下标越界（4 区×8 时段） | ✗ **MAJOR**：MultiZone eHold 分支 aiZoneSlotCount 未重校验（行 262-263） |
| 除零（卷径/σ²/fDt/fRateMax） | ✓ 全部有前置闸或常量除数 |
| 非有限判据禁 ABS(x-x) 死谓词 | ✓ 全件用 x<>x（NaN）+ (x-x)<>0（±Inf）标准判法，无 ABS 死谓词 |
| ENUM 成员 := 赋值 | ✓ 未发现枚举变量数字赋值（TYPE 成员初始化合法） |
| VAR_IN_OUT fXPrev 重建 | ✓ RateLimit 段 2：前值非有限→以本拍输入重建+ePrevRebuilt；SlewLimit 同族 |
| FOR/WHILE 边界 | ✓ 除上述 eHold 缺陷外，全部 FOR 上界经校验或常量 |

## 四、计数与复现命令

- **PASS=12 / FAIL=1 / EXEMPT=0，总 13**
- FAIL 明细: `FB_DL_MultiZoneSetpointScheduler.st — E045 ×8 处 + MAJOR 越界 ×1`
- 复现: `python C:\Library\_tools\l2_check.py <文件>`（串行 jobs=1）
- verdict=BLOCK → 注册脚本本轮拒绝写入 registry 中该件；其余 12 件放行

## 五、缺陷登记

| 级别 | 文件 | 问题 | 处置 |
|---|---|---|---|
| BLOCK | FB_DL_MultiZoneSetpointScheduler.st | E045 逗号 2D 访问 ×8（行 194,195,204,213,214,236,240,264） | 阻断入库，回派编码专家，最小修法见裁决表 |
| MAJOR | FB_DL_MultiZoneSetpointScheduler.st | eHold 分支外部引脚未重校验→数组越界路径（行 262-263） | 阻断入库（安全侧），随 E045 一并修，行为零变更（仅加守卫） |
| MINOR | （工具链）l2_check.py | find_def_file 对未入 registry 新件定位落空 | 已修复并留痕（.bak_r78b），回归验证 3 件全过 |
