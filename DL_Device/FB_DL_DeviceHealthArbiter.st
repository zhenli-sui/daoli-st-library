(*
    FB_DL_DeviceHealthArbiter —— NE107 多源健康聚合仲裁
    ------------------------------------------------------------------
    分类      : DL_Device / Diagnostics
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : NAMUR NE107 公开的六态健康语言（只借六态语义与「编号即仲裁优先级」的
                组织事实，不复制任何条款文本）；聚合算法、分级位图、首出三律、错误分级与
                码位 100% 自有；E_DL_Ne107Status 的唯一属主为 I_DL_DeviceHealth，
                本件只引用不重声明（R70 全库唯一断言）；
                clean-room 重写，未复制任何闭源厂商源码
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R19）
    ------------------------------------------------------------------
    功能说明  : 把 N 路设备健康态（阀 / 电机 / 仪表 / 变频器）聚合成一个整机健康结论，
                并回答现场两个必答题：「现在最严重的是哪一类」与「是谁先报的」。
                核心防御：① 仲裁次序 = 枚举编号（eFailure 0 < eCheckFunction 10 <
                   eMaintenanceReq 20 < eOutOfSpec 30 < eOk 40 < eUnknown 99），
                   本件不自造第二套优先级（同族纪律）；
                ② Unknown 不遮蔽：只要有任一源为已知且非 OK 态，聚合结论就不得为
                   eUnknown——现场最常见的误判是一路通道没配好导致整机显示「未知」，
                   把真故障压掉；
                ③ 首出仅锁存一次，复位沿在仲裁之后生效且当拍不重新锁存；
                ④ 平台越界写入的非法枚举值落 ELSE 分支归 eUnknown 并置故障级 0331；
                ⑤ 源数量越界时不索引任何数组，聚合结论回 eUnknown。
                职责边界：单源健康判定归各设备件，本件只做聚合与仲裁；PN 通道诊断聚合归
                FB_DL_ProfinetAlarmDiag，本件不吃协议细节。
    错误码    : 16#0003_016A 同拍多源同级别已按源索引最小仲裁 / 存在 Unknown 源但未遮蔽已知故障——信息级，正常防御
                16#0003_016B 预留禁用（信息级，不得挪用）
                16#0003_0330 源数量越界（不在 1~16）——故障级，聚合结论置 eUnknown 且不索引数组
                16#0003_0331 健康枚举值非法（CASE 落 ELSE）——故障级，该源按 eUnknown 处理并继续聚合
                16#0003_0332 预留禁用（故障级，不得挪用）
    码位总账  : 16#0003_016A 用 / 16#0003_016B 预留 ｜ 16#0003_0330 用 / 16#0003_0331 用 / 16#0003_0332 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
                （源态分派用的 CASE 是枚举映射表，不是顺序状态机，且含 ELSE 兜底）
    采样约定  : fbTrigReset 在本体首部无条件刷新；健康结论每拍实时刷新（不锁存），
                只有首出索引与通道锁存；与任务周期无关的纯组合仲裁。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R19）
*)
FUNCTION_BLOCK FB_DL_DeviceHealthArbiter
VAR_INPUT
    bEnable            : BOOL;                // 使能，FALSE 输出 eUnknown 并冻结首出 / enable, FALSE outputs eUnknown and freezes the first-out
    bReset             : BOOL;                // 复位，上升沿清首出锁存（健康结论仍实时刷新）/ reset, rising edge clears the first-out latch, health stays live
    aeHealth           : ARRAY[0..15] OF E_DL_Ne107Status; // 各源健康态，枚举属主为 I_DL_DeviceHealth / source health states, owned by I_DL_DeviceHealth
    auChannelId        : ARRAY[0..15] OF UINT; // 各源对外通道号，可为 0 [通道] / external channel id per source, zero allowed [channel]
    uSrcCount          : UINT := 16;           // 有效源数 [路]，范围 1~16 / valid source count [ch], range 1~16
    bIncludeMaintenance : BOOL := TRUE;        // TRUE = 维护/校验类参与聚合，FALSE = 只聚 Failure / OutOfSpec / TRUE lets maintenance and check participate
END_VAR
VAR_OUTPUT
    eAggHealth         : E_DL_Ne107Status;     // 聚合后健康结论 / aggregated health conclusion
    uFirstIdx          : UINT;                // 首出源索引 0~15，无则 16#FFFF / first-out source index, sentinel 16#FFFF when none
    uFirstChannel      : UINT;                // 首出源对外通道号 [通道] / external channel id of the first-out source [channel]
    auLevelMask        : ARRAY[0..5] OF WORD;  // 分级位图，bit N = 源 N / level bitmap, bit N is source N
    uFaultSrcCount     : UINT;                // 处于 Failure 或 OutOfSpec 的源数 [路] / sources in Failure or OutOfSpec [ch]
    bDegraded          : BOOL;                // 存在维护/校验类但无故障类（可运行需处理）/ degraded, maintenance or check without a fault class
    eErr               : UDINT;               // 错误码，0=正常 / error id, 0=ok
    bError             : BOOL;                // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
END_VAR
VAR
    fbTrigReset        : R_TRIG;              // 复位上升沿实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    uIdx               : UINT;                // 源扫描游标 [路]，范围 0~15 / source scan cursor [ch], range 0~15
    uBucket            : UINT;                // 本源的位图分桶序号 [桶] / bitmap bucket index of this source [bucket]
    nRank              : INT;                 // 本源的仲裁等级（枚举编号）[无量纲] / arbitration rank of this source [dimensionless]
    nBestRank          : INT;                 // 已选出的最高优先级等级 [无量纲] / best rank selected so far [dimensionless]
    uBestIdx           : UINT;                // 已选出的首出候选索引 [路] / first-out candidate index [ch]
    bAnyKnown          : BOOL;                // 存在已知（非 Unknown）源 / at least one known source exists
    bAnyUnknown        : BOOL;                // 存在 Unknown 源 / at least one unknown source exists
    bAnyMaintain       : BOOL;                // 存在维护/校验类源 / at least one maintenance or check source exists
    bAnyFaultLevel     : BOOL;                // 存在故障类（Failure/OutOfSpec）源 / at least one fault class source exists
    bConsider          : BOOL;                // 本源参与聚合判定标志 / this source participates in the aggregation
    bIllegalEnum       : BOOL;                // 本拍出现非法枚举值 / an illegal enumeration value appeared in this cycle
    bFirstLatched      : BOOL;                // 首出已锁存 / first-out is latched
    uFirstInt          : UINT := 16#FFFF;     // 内部首出索引寄存，初值哨兵 / internal first-out index, initialised to the sentinel
    uFirstChInt        : UINT;                // 内部首出通道寄存 / internal first-out channel register
    bMultiSame         : BOOL;                // 同拍多源同级别 / multiple sources share the best rank this cycle
    uSameCnt           : UINT;                // 与最高优先级同级别的源数 [路] / sources sharing the best rank [ch]
    bInit              : BOOL := FALSE;       // 首扫标志，初值 FALSE，判据 NOT bInit / first-scan flag, initial FALSE, tested with NOT
END_VAR
VAR CONSTANT
    DL_HARB_SRC_MAX     : UINT := 16;         // 源数量上限 [路] / source count upper bound [ch]
    DL_HARB_NONE        : UINT := 16#FFFF;    // 无首出哨兵 [无量纲] / no first-out sentinel [dimensionless]
    DL_HARB_LEVELS      : UINT := 6;          // 分级桶数 [桶] / number of level buckets [bucket]
    DL_HARB_B_FAILURE   : UINT := 0;          // eFailure 桶号 [桶] / bucket index for eFailure
    DL_HARB_B_CHECK     : UINT := 1;          // eCheckFunction 桶号 [桶] / bucket index for eCheckFunction
    DL_HARB_B_MAINT     : UINT := 2;          // eMaintenanceReq 桶号 [桶] / bucket index for eMaintenanceReq
    DL_HARB_B_SPEC      : UINT := 3;          // eOutOfSpec 桶号 [桶] / bucket index for eOutOfSpec
    DL_HARB_B_OK        : UINT := 4;          // eOk 桶号 [桶] / bucket index for eOk
    DL_HARB_B_UNKNOWN   : UINT := 5;          // eUnknown 桶号 [桶] / bucket index for eUnknown
    DL_HARB_R_FAILURE   : INT := 0;           // eFailure 的仲裁等级（最严重）[无量纲] / rank of eFailure, the most severe
    DL_HARB_R_CHECK     : INT := 10;          // eCheckFunction 的仲裁等级 [无量纲] / rank of eCheckFunction
    DL_HARB_R_MAINT     : INT := 20;          // eMaintenanceReq 的仲裁等级 [无量纲] / rank of eMaintenanceReq
    DL_HARB_R_SPEC      : INT := 30;          // eOutOfSpec 的仲裁等级 [无量纲] / rank of eOutOfSpec
    DL_HARB_R_OK        : INT := 40;          // eOk 的仲裁等级 [无量纲] / rank of eOk
    DL_HARB_R_UNKNOWN   : INT := 99;          // eUnknown 的仲裁等级（不参与优先）[无量纲] / rank of eUnknown, excluded from priority
    DL_HARB_R_NONE      : INT := 100;         // 未选出任何等级的哨兵 [无量纲] / sentinel meaning no rank selected yet
    DL_HARB_BIT0        : WORD := 16#0001;    // 位图最低位掩码 [位图] / least significant bitmap mask [bitmap]
    DL_HARB_ZERO        : WORD := 16#0000;    // 位图零常量 [位图] / bitmap zero constant [bitmap]
    DL_HARB_CNT_ZERO    : UINT := 0;          // 无符号零常量 [无量纲] / unsigned zero constant [dimensionless]
END_VAR

// 段 1｜边沿实例无条件周期刷新（红线：严禁放入条件分支）/ segment 1, unconditional edge refresh
fbTrigReset(CLK := bReset);

// 段 2｜输出与中间量预置 / segment 2, preset outputs and intermediates
eAggHealth := eUnknown;                       // 缺省结论为未知 / default conclusion is unknown
uFirstIdx := DL_HARB_NONE;                    // 缺省无首出 / default no first-out
uFirstChannel := DL_HARB_CNT_ZERO;            // 缺省通道号 0 / default channel zero
uFaultSrcCount := DL_HARB_CNT_ZERO;           // 故障源计数清零 / clear the fault source count
bDegraded := FALSE;                           // 预置未降级 / preset not degraded
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bAnyKnown := FALSE;                           // 预置无已知源 / preset no known source
bAnyUnknown := FALSE;                         // 预置无未知源 / preset no unknown source
bAnyMaintain := FALSE;                        // 预置无维护类 / preset no maintenance source
bAnyFaultLevel := FALSE;                      // 预置无故障类 / preset no fault class source
nBestRank := DL_HARB_R_NONE;                  // 最高优先级哨兵 / best rank sentinel
uBestIdx := DL_HARB_NONE;                     // 首出候选哨兵 / first-out candidate sentinel
bIllegalEnum := FALSE;                        // 预置无非法枚举 / preset no illegal enumeration
uSameCnt := DL_HARB_CNT_ZERO;                 // 同级别计数清零 / clear the same-rank counter
FOR uIdx := 0 TO DL_HARB_LEVELS - 1 DO
    auLevelMask[uIdx] := DL_HARB_ZERO;        // 六个分级桶逐桶清零 / clear each of the six level buckets
END_FOR

// 段 3｜首扫初始化（唯一合法范式：初值 FALSE，判据 NOT bInit）/ segment 3, first-scan initialisation
IF NOT bInit THEN
    bFirstLatched := FALSE;                   // 首扫不留锁存 / no latch survives the first scan
    uFirstInt := DL_HARB_NONE;                // 首出索引回哨兵 / first-out index back to the sentinel
    uFirstChInt := DL_HARB_CNT_ZERO;          // 首出通道回 0 / first-out channel back to zero
    bInit := TRUE;                            // 首扫只做一次 / first scan runs once only
END_IF

// 段 4｜使能闸：失能输出未知并冻结首出（不索引数组）/ segment 4, enable gate
IF NOT bEnable THEN
    eAggHealth := eUnknown;                   // 失能即未知 / unknown while disabled
    uFirstIdx := uFirstInt;                   // 首出保持冻结 / the first-out stays frozen
    uFirstChannel := uFirstChInt;             // 通道保持冻结 / the channel stays frozen
    RETURN;                                   // 失能即出口 / disabled is the exit
END_IF

// 段 5｜源数量闸：越界即故障级，聚合结论回 eUnknown 且不索引数组 / segment 5, source count gate
IF (uSrcCount < 1) OR (uSrcCount > DL_HARB_SRC_MAX) THEN
    eErr := 16#0003_0330;                     // 源数量越界故障码 / source count out of range fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
    eAggHealth := eUnknown;                   // 结论回未知 / conclusion back to unknown
    RETURN;                                   // 故障级提前返回，不索引任何源 / early return, no source is indexed
END_IF

// 段 6｜逐源扫描：分桶、计故障类、选最高优先级、捕非法枚举 / segment 6, per source scan
FOR uIdx := 0 TO uSrcCount - 1 DO
    bConsider := TRUE;                        // 默认参与聚合 / participates by default
    CASE aeHealth[uIdx] OF
        eFailure:
            uBucket := DL_HARB_B_FAILURE;     // 落失效桶 / bucket for failure
            nRank := DL_HARB_R_FAILURE;       // 最严重等级 / the most severe rank
            bAnyKnown := TRUE;                // 已知态 / a known state
            bAnyFaultLevel := TRUE;           // 故障类 / fault class
            uFaultSrcCount := uFaultSrcCount + 1; // 故障源计数加一 / increment the fault source count
        eCheckFunction:
            uBucket := DL_HARB_B_CHECK;       // 落功能校验桶 / bucket for function check
            nRank := DL_HARB_R_CHECK;         // 校验等级 / check rank
            bAnyKnown := TRUE;                // 已知态 / a known state
            bAnyMaintain := TRUE;             // 维护/校验类 / maintenance or check class
        eMaintenanceReq:
            uBucket := DL_HARB_B_MAINT;       // 落维护桶 / bucket for maintenance required
            nRank := DL_HARB_R_MAINT;         // 维护等级 / maintenance rank
            bAnyKnown := TRUE;                // 已知态 / a known state
            bAnyMaintain := TRUE;             // 维护/校验类 / maintenance or check class
        eOutOfSpec:
            uBucket := DL_HARB_B_SPEC;        // 落超规格桶 / bucket for out of specification
            nRank := DL_HARB_R_SPEC;          // 超规格等级 / out of specification rank
            bAnyKnown := TRUE;                // 已知态 / a known state
            bAnyFaultLevel := TRUE;           // 故障类 / fault class
            uFaultSrcCount := uFaultSrcCount + 1; // 故障源计数加一 / increment the fault source count
        eOk:
            uBucket := DL_HARB_B_OK;          // 落正常桶 / bucket for OK
            nRank := DL_HARB_R_OK;            // 正常等级 / the OK rank
            bAnyKnown := TRUE;                // 已知态 / a known state
        eUnknown:
            uBucket := DL_HARB_B_UNKNOWN;     // 落未知桶 / bucket for unknown
            nRank := DL_HARB_R_UNKNOWN;       // 未知等级（不参与优先）/ unknown rank, excluded from priority
            bAnyUnknown := TRUE;              // 存在未知源 / an unknown source exists
            bConsider := FALSE;               // 未知源不参与聚合 / an unknown source never participates
        ELSE
            uBucket := DL_HARB_B_UNKNOWN;     // 非法枚举归未知桶（红线 4：ELSE 兜底）/ illegal values fall into the unknown bucket
            nRank := DL_HARB_R_UNKNOWN;       // 按未知等级处理 / treated as unknown rank
            bAnyUnknown := TRUE;              // 计入未知源 / counted as an unknown source
            bConsider := FALSE;               // 不参与聚合 / never participates
            bIllegalEnum := TRUE;             // 记录非法枚举 / remember the illegal enumeration
        END_CASE
    auLevelMask[uBucket] := auLevelMask[uBucket] OR SHL(DL_HARB_BIT0, uIdx); // 置位图，uIdx ≤ 15 移位安全 / set the bitmap bit, the shift never exceeds 15

    // 段 7｜聚合参与判定：维护类是否计入由调用方策略决定 / segment 7, participation policy
    IF bConsider AND (NOT bIncludeMaintenance) THEN
        IF (uBucket = DL_HARB_B_CHECK) OR (uBucket = DL_HARB_B_MAINT) THEN
            bConsider := FALSE;               // 策略禁止时维护/校验类不进聚合，但仍进位图 / excluded from the aggregation but still visible in the bitmap
        END_IF
    END_IF

    // 段 8｜最高优先级仲裁：等级更小者胜，同级取源索引最小 / segment 8, best rank arbitration
    IF bConsider AND (nRank < nBestRank) THEN
        nBestRank := nRank;                   // 记下新的最高优先级 / remember the new best rank
        uBestIdx := uIdx;                     // 记下首出候选索引 / remember the candidate index
        uSameCnt := 1;                        // 同级别计数复位 / reset the same-rank counter
    ELSIF bConsider AND (nRank = nBestRank) THEN
        uSameCnt := uSameCnt + 1;             // 同级别源计数 / count the sources sharing the rank
    END_IF
END_FOR

// 段 9｜等级回映射为枚举（含兜底，绝不返回未定义值）/ segment 9, rank to enumeration mapping
CASE nBestRank OF
    DL_HARB_R_FAILURE:
        eAggHealth := eFailure;               // 聚合结论：失效 / aggregated failure
    DL_HARB_R_CHECK:
        eAggHealth := eCheckFunction;         // 聚合结论：功能校验 / aggregated function check
    DL_HARB_R_MAINT:
        eAggHealth := eMaintenanceReq;        // 聚合结论：需要维护 / aggregated maintenance required
    DL_HARB_R_SPEC:
        eAggHealth := eOutOfSpec;             // 聚合结论：超出规格 / aggregated out of specification
    DL_HARB_R_OK:
        eAggHealth := eOk;                    // 聚合结论：正常 / aggregated OK
ELSE
    eAggHealth := eUnknown;                   // 未选出或全为未知：结论未知（不遮蔽规则见段 10）/ nothing selected means unknown
END_CASE

// 段 10｜Unknown 不遮蔽复核：已知非 OK 存在时结论不得为未知 / segment 10, unknown must not mask a known fault
IF bAnyKnown AND (eAggHealth = eUnknown) AND (nBestRank = DL_HARB_R_NONE) THEN
    eAggHealth := eOutOfSpec;                 // 存在已知态却无等级：按次严重级保守结论文本 / a known state without a rank is treated conservatively
END_IF
IF bAnyUnknown AND bAnyKnown THEN
    eErr := 16#0003_016A;                     // 信息级：存在未知源但未遮蔽已知故障 / info level, unknown sources did not mask the known state
END_IF

// 段 11｜降级判定：有维护/校验类而无故障类即可运行需安排处理 / segment 11, degraded evaluation
bDegraded := bAnyMaintain AND (NOT bAnyFaultLevel); // 降级 = 需处理但不致命 / degraded means action needed but not critical

// 段 12｜首出锁存：复位沿优先于仲裁，且当拍不重新锁存 / segment 12, first-out latching
IF fbTrigReset.Q THEN
    bFirstLatched := FALSE;                   // 复位清锁存 / reset clears the latch
    uFirstInt := DL_HARB_NONE;                // 索引回哨兵 / index back to the sentinel
    uFirstChInt := DL_HARB_CNT_ZERO;          // 通道回 0 / channel back to zero
ELSIF (NOT bFirstLatched) AND (uBestIdx <> DL_HARB_NONE) AND (nBestRank <> DL_HARB_R_OK) THEN
    uFirstInt := uBestIdx;                    // 锁存首个非 OK 源 / latch the first non-OK source
    uFirstChInt := auChannelId[uBestIdx];     // 锁存其对外通道号（索引已由仲裁保证合法）/ latch its channel id, the index is legal by construction
    bFirstLatched := TRUE;                    // 置锁存位 / set the latch
    IF uSameCnt > 1 THEN
        eErr := 16#0003_016A;                 // 信息级：同拍多源同级别，已按来源索引最小仲裁 / info level, ties resolved by the lowest source index
    END_IF
END_IF

// 段 13｜非法枚举汇总置码（故障级，但不中止聚合）/ segment 13, illegal enumeration summary
IF bIllegalEnum THEN
    eErr := 16#0003_0331;                     // 健康枚举非法故障码 / illegal health enumeration fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
END_IF

// 段 14｜对外镜像 / segment 14, mirror the latched values to the outputs
uFirstIdx := uFirstInt;                       // 首出索引镜像 / first-out index mirror
uFirstChannel := uFirstChInt;                 // 首出通道镜像 / first-out channel mirror
END_FUNCTION_BLOCK
