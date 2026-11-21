(*==============================================================================
 * 组件名称 (Component)  : FB_DL_StepTimeRecorder
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 顺控各步耗时在线采集统计（测量侧）。调用方每拍给出
 *                         当前激活步号 nStepId（0 = 无激活步），本件按扫描周期
 *                         tScan 对激活步做时间积分：步切换沿（步号变化或回 0）
 *                         时把累计时长入档（步号槽位记录 count/sum/last/min/max，
 *                         并派生 avg）。批量产线节拍分析、顺控瓶颈定位场景。
 * 来源标签 (Origin)     : 自研线（IEC 61131-3 标准语义的道莅防御性实现，clean-room）
 * 分工声明 (Pairing)    : StepTimeRecorder（测量侧，本件）↔ FB_DL_StepSequencer
 *                         （编排侧，既有件）：本件只消费步号快照做耗时统计，
 *                         不产生步进命令、不干预顺控相位、不持有步状态机
 *                         （R298 属主边界：测量不改编排）。
 * 边界语义 (Boundary)   : ① 步号闸：nStepId 落于 1..16 域外按 0（无激活步）处理
 *                         并置信息级 nWarnCnt 递增（越界钳位，R308 口径）；
 *                         ② 档位满：单步 count 达 DINT 上限饱和不再递增（防回绕，
 *                         上限 2^30 远超工程寿命，sum 同步饱和）；
 *                         ③ 除零防御：avg 仅在 count >= 1 时派生，除子恒 >= 1；
 *                         ④ 组态闸：tScan <= T#0S → bError 锁存（积分失真）；
 *                         ⑤ 监视型无主状态机（R23 周期监视型公约），无 CASE 相。
 * 来源标签 (Origin)     : T0 语义件；本件为自研线补口件，无 T0 对应条目。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL(bError)，
 *                         码位待主控收口统一派号。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 越界钳位/饱和防回绕/除零防御 ✓｜R5 双语同行注释 ✓
 *                         R6 N/A（监视型无状态机，判据纯派生）✓
 *                         R7 R_TRIG 段 0 无条件每拍刷新 ✓
 * 验收向量 (Acceptance) : V1 步 3 激活 2.0s 后切步 → aStepLast[3]=2.0，
 *                         aStepAvg[3]=2.0，aStepCnt[3]=1；
 *                         V2 步 3 再测 3.0s → aStepAvg[3]=2.5，aStepMax[3]=3.0；
 *                         V3 nStepId=99 → 按 0 处理且 nWarnCnt 递增；
 *                         V4 bReset 上升沿全档清零（上电回夹防线）。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R49 首版（批 1 · 序号 5）
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_StepTimeRecorder
VAR_INPUT
    nStepId  : INT := 0;                     (* 当前激活步号，0 = 无激活步，域 1..16 域外按 0 [步] / Active step id, 0 = none *)
    tScan    : TIME := T#10MS;               (* 扫描周期（积分步长），域 > T#0S [ms] / Scan cycle integration step *)
    bEnable  : BOOL := TRUE;                 (* 采集使能，FALSE 时冻结不积分不切档 [-] / Enable, FALSE freezes accumulation *)
    bReset   : BOOL := FALSE;                (* 复位命令，上升沿清全部档位与告警计数 [-] / Reset, rising edge clears all banks *)
END_VAR
VAR_OUTPUT
    aStepCnt  : ARRAY[1..16] OF DINT;        (* 各步样本计数（档位量）[个] / Sample count per step bank *)
    aStepLast : ARRAY[1..16] OF LREAL;       (* 各步最近一次耗时 [s] / Last duration per step *)
    aStepAvg  : ARRAY[1..16] OF LREAL;       (* 各步平均耗时 = sum/count [s] / Average duration per step *)
    aStepMin  : ARRAY[1..16] OF LREAL;       (* 各步最小耗时 [s] / Minimum duration per step *)
    aStepMax  : ARRAY[1..16] OF LREAL;       (* 各步最大耗时 [s] / Maximum duration per step *)
    bBanked   : BOOL;                        (* 本拍完成一次入档的单拍脉冲 [-] / Single-scan bank-update pulse *)
    nBankedId : INT;                         (* 最近入档步号（诊断镜像）[步] / Last banked step id *)
    nWarnCnt  : UDINT;                       (* 非法步号拒收累计（信息级台账）[次] / Illegal id rejection counter *)
    bError    : BOOL;                        (* 组态故障锁存标志（tScan 非法）[-] / Config fault latch flag *)
END_VAR
VAR
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    i        : INT;                          (* 复位清档循环游标 [-] / Reset clear loop cursor *)
    _nPrevId : INT;                          (* 上拍激活步号（切换沿检测基准）[步] / Previous active step id *)
    _fAccS   : LREAL;                        (* 当前步累计时长（积分器）[s] / Current step accumulator *)
    _fScanS  : LREAL := 0.01;                (* 扫描周期秒值缓存（TIME 秒换算）[s] / Scan cycle seconds cache *)
    _nCurId  : INT;                          (* 防御后生效步号（钳位结果）[步] / Sanitized current step id *)
    _bFault  : BOOL;                         (* 组态故障锁存位 / Config fault latch bit *)
END_VAR
VAR CONSTANT
    DL_ST_NMAX   : INT   := 16;              (* 步号容量上限（越界钳位目标）[步] / Step capacity limit *)
    DL_ST_DMAX   : DINT  := 1073741824;      (* 计数饱和上限 2^30（防回绕）[个] / Count saturation limit 2^30 *)
    DL_ST_SUMMAX : LREAL := 1.0E15;          (* 累计和饱和上限（防精度坍缩）[s] / Sum saturation limit *)
END_VAR

(* —— 段 0：当拍判据派生 + 沿实例无条件刷新（R228A） —— *)
rtReset(CLK := bReset);                                      (* 复位沿每拍必调 / Reset edge every scan *)
_fScanS := TIME_TO_LREAL(tScan) / 1000.0;                    (* 毫秒口径换算秒（舍入意图：整毫秒无损）[s] / Convert ms to seconds *)
IF _fScanS <= 1.0E-9 OR (tScan <= T#0S) THEN                 (* 组态闸：步长非法（含 TIME 下溢） / Config gate: illegal step *)
    _bFault := TRUE;                                         (* 锁存组态故障 / Latch config fault *)
END_IF

(* —— 段 1：单拍量预清零（锁存量与档位不入清单，R107） —— *)
bBanked := FALSE;                                            (* 入档单拍位预清，唯一分支置位 / Bank pulse preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清全部档位数组 + 清积分器 + 清台账，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                        (* 清组态故障 / Clear config fault *)
    _fAccS := 0.0;                                           (* 清积分器 / Clear accumulator *)
    _nPrevId := 0;                                           (* 清上拍步号 / Clear previous id *)
    nWarnCnt := 0;                                           (* 清拒收台账 / Clear rejection counter *)
    nBankedId := 0;                                          (* 清入档镜像 / Clear banked mirror *)
    FOR i := 1 TO DL_ST_NMAX DO                              (* 全档位清零（上电回夹防线） / Clear all banks *)
        aStepCnt[i] := 0;                                    (* 清计数 / Clear count *)
        aStepLast[i] := 0.0;                                 (* 清最近值 / Clear last *)
        aStepAvg[i] := 0.0;                                  (* 清均值 / Clear avg *)
        aStepMin[i] := 0.0;                                  (* 清最小值 / Clear min *)
        aStepMax[i] := 0.0;                                  (* 清最大值 / Clear max *)
    END_FOR
END_IF

(* —— 段 3：步号钳位与非法拒收（域外按 0 处理，越界不越界访问，R308） —— *)
_nCurId := nStepId;                                          (* 生效步号初值 / Sanitized id init *)
IF (_nCurId < 1) OR (_nCurId > DL_ST_NMAX) THEN
    IF nStepId <> 0 THEN                                     (* 非零非法步号才记拒收（0 是合法空步） / Only nonzero illegal ids counted *)
        nWarnCnt := nWarnCnt + 1;                            (* 信息级台账递增（不置 bError，R90 信息级口径） / Info-level counter, not fault *)
    END_IF
    _nCurId := 0;                                            (* 按 0 处理 / Treat as none *)
END_IF

(* —— 段 4：激活积分 + 切换沿入档（监视型纯派生，无 CASE 相） —— *)
IF bEnable AND NOT _bFault THEN
    IF _nCurId = _nPrevId THEN
        IF _nCurId > 0 THEN
            _fAccS := _fAccS + _fScanS;                      (* 同步持续：积分累计（饱和防精度坍缩） / Same step: integrate *)
            IF _fAccS > DL_ST_SUMMAX THEN
                _fAccS := DL_ST_SUMMAX;                      (* 累计和饱和 / Saturate accumulator *)
            END_IF
        END_IF
    ELSE
        (* 切换沿：上一激活步收档（_nPrevId > 0 且累计 > 0 才入档，剔除断使能残片） / Step change: bank previous step *)
        IF (_nPrevId >= 1) AND (_nPrevId <= DL_ST_NMAX) AND (_fAccS > 0.0) THEN
            aStepLast[_nPrevId] := _fAccS;                   (* 记最近耗时 / Store last duration *)
            IF aStepCnt[_nPrevId] < DL_ST_DMAX THEN
                aStepAvg[_nPrevId] := (aStepAvg[_nPrevId] * DINT_TO_LREAL(aStepCnt[_nPrevId]) + _fAccS) / DINT_TO_LREAL(aStepCnt[_nPrevId] + 1);   (* 增量均值 = (旧和 + 新值)/(旧计数+1)，除子恒 >= 1 / Incremental mean, divisor >= 1 *)
                aStepCnt[_nPrevId] := aStepCnt[_nPrevId] + 1;   (* 计数递增（回绕防护） / Increment count, wrap-guarded *)
            END_IF
            IF (aStepMin[_nPrevId] <= 0.0) OR (_fAccS < aStepMin[_nPrevId]) THEN
                aStepMin[_nPrevId] := _fAccS;                (* 最小值更新（首样本或更小） / Min update *)
            END_IF
            IF _fAccS > aStepMax[_nPrevId] THEN
                aStepMax[_nPrevId] := _fAccS;                (* 最大值更新 / Max update *)
            END_IF
            bBanked := TRUE;                                 (* 入档单拍脉冲 / Bank pulse *)
            nBankedId := _nPrevId;                           (* 入档步号镜像 / Banked id mirror *)
        END_IF
        _fAccS := 0.0;                                       (* 新步积分器清零重开 / Reset accumulator for new step *)
        _nPrevId := _nCurId;                                 (* 更新切换基准 / Update change reference *)
    END_IF
END_IF

(* —— 段 5：出口映射（R191：bError 与 _bFault 名实同源） —— *)
bError := _bFault;                                           (* 组态故障镜像 / Config fault mirror *)
END_FUNCTION_BLOCK
