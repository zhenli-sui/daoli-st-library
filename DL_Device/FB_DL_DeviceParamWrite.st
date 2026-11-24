(*
    FB_DL_DeviceParamWrite —— 设备参数写回事务
    ------------------------------------------------------------------
    分类      : DL_Device / DeviceAccess
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 设备参数「读 → 比 → 判」三段流程的下半段划分（写回 / 复核 / 回滚）；
                只借流程骨架的分类事实，示例页面未声明许可，故按最严口径处置：
                零代码行、零注释引用；白名单机制、事务状态机、回滚策略、错误分级与
                码位 100% 自有；clean-room 重写，未复制任何闭源厂商源码
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R19）
    ------------------------------------------------------------------
    功能说明  : 备份快照 → 白名单逐项写 → 读回复核 → 不一致即回滚。
                归属裁定（关闭矩阵勘误 M-E3 的悬置项）：参数写回属设备层——写回是设备访问
                能力，工艺层只应下发语义参数，故本件落在 DL_Device 而非 DL_Process。
                核心防御：① 项数越界即拒绝启动事务，不索引数组；
                ② 白名单外项（只读）绝不写，跳过并计数——写只读项在多数设备上会被静默
                   忽略或引发参数区校验失败，后者会让整块参数失效；
                ③ 写超时转回滚；读回偏差超容差同样转回滚（写进去却没保持住 = 参数区有问题）；
                ④ 回滚失败置 033B 并锁存，禁止自动重试——参数区已不可信须人工介入；
                ⑤ bAbort 中止事务但不触发回滚（中止是人为决策，回滚由调用方再发事务决定）。
                规格补正：物理读写不在本件内完成（零厂商库红线），本件经 afActual 输入取
                设备实际值、经 bWriteNow + uActiveIdx 输出驱动上层 IO/驱动层执行写入——
                派单引脚表未含读回通道，实测无法闭环复核，特此补正三个引脚并在收口报告留档。
    错误码    : 16#0003_0170 白名单外项已跳过（uSkipped 非 0）——信息级，正常防御
                16#0003_0171 预留禁用（信息级，不得挪用）
                16#0003_0339 项数越界（不在 1~16）——故障级，事务不启动且不索引数组
                16#0003_033A 写超时 / 读回复核不一致 / 写值非有限——故障级，已转回滚
                16#0003_033B 回滚失败或状态机兜底——故障级，参数区不可信须人工介入（锁存）
    码位总账  : 16#0003_0170 用 / 16#0003_0171 预留 ｜ 16#0003_0339 用 / 16#0003_033A 用 / 16#0003_033B 用
    状态机    : E_DL_ParamWriteState（eIdle / eBackup / eWrite / eVerify / eRollback / eDone / eFault）
                七态，CASE 含 ELSE 兜底，ELSE 回 eFault 并置故障级 033B。
    采样约定  : fbTrigExec / fbTrigAbort / fbTrigReset 与 fbWrite / fbVerify 五个实例在本体首部
                无条件刷新，绝不放入 IF 或 CASE；tWriteTimeout 覆盖整个写入相与回滚相（不做单相
                复位，否则就要在 CASE 内调用实例，违反周期刷新红线），tVerifyTimeout 覆盖复核相；
                bDone 为单周期脉冲，bRollback 保持锁存直到 bReset。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R19）
*)

(*
    枚举 : E_DL_ParamWriteState —— 参数写回事务状态（本文件为全库唯一属主）
*)
TYPE E_DL_ParamWriteState :
(
    eIdle     := 0,                           // 空闲：无事务 / idle, no transaction
    eBackup   := 1,                           // 备份：抓取写前快照 / backup, capture the pre-write snapshot
    eWrite    := 2,                           // 写入：逐项白名单写 / write, item by item with the whitelist
    eVerify   := 3,                           // 复核：读回比对全部已写项 / verify, compare every written item
    eRollback := 4,                           // 回滚：恢复备份快照 / rollback, restore the backup snapshot
    eDone     := 5,                           // 完成：写入并复核通过 / done, written and verified
    eFault    := 6                            // 故障：事务失败或参数区不可信 / fault, the transaction failed or the parameter area is untrustworthy
);
END_TYPE

FUNCTION_BLOCK FB_DL_DeviceParamWrite
VAR_INPUT
    bEnable         : BOOL;                   // 使能，FALSE 中止并撤 bBusy / enable, FALSE aborts and drops the busy flag
    bExecute        : BOOL;                   // 执行，上升沿启动一次写回事务 / execute, rising edge starts one write transaction
    bAbort          : BOOL;                   // 中止，上升沿中止（不触发回滚）/ abort, rising edge aborts without triggering a rollback
    bReset          : BOOL;                   // 复位，上升沿清故障与 bRollback / reset, rising edge clears the faults and the rollback flag
    auIndex         : ARRAY[0..15] OF UINT;   // 参数索引 [索引]，范围 1~65535 / parameter index [index], range 1~65535
    afWriteValue    : ARRAY[0..15] OF REAL;   // 待写值 [用户单位] / value to write [user unit]
    abWritable      : ARRAY[0..15] OF BOOL;   // 白名单：FALSE = 只读项，禁止写 / whitelist, FALSE means read only and forbidden
    afActual        : ARRAY[0..15] OF REAL;   // 设备实际值（由 IO/驱动层每拍提供，规格补正引脚）[用户单位] / device actual values supplied by the IO layer each cycle, a spec correction pin [user unit]
    uCount          : UINT := 0;              // 有效项数 [项]，范围 1~16 / valid item count [item], range 1~16
    fVerifyTol      : REAL := 0.001;          // 读回值容差 [用户单位]，范围 >= 0（0 = 严格相等，不推荐）/ readback tolerance [user unit], >= 0
    tWriteTimeout   : TIME := T#5S;           // 单项写超时 [ms]，范围 100~60000 / per item write timeout [ms], range 100~60000
    tVerifyTimeout  : TIME := T#5S;           // 读回复核超时 [ms]，范围 100~60000 / verification timeout [ms], range 100~60000
END_VAR
VAR_OUTPUT
    bBusy           : BOOL;                   // 事务进行中 / transaction in progress
    bDone           : BOOL;                   // 全部写入并复核通过（单周期脉冲）/ everything written and verified, a single-cycle pulse
    bRollback       : BOOL;                   // 发生过回滚（锁存）/ a rollback occurred, latched
    uWritten        : UINT;                   // 实际写入并复核通过的项数 [项] / items written and verified [item]
    uSkipped        : UINT;                   // 因白名单或非法索引被跳过的项数 [项] / items skipped due to the whitelist or an illegal index [item]
    uFailedIdx      : UINT;                   // 首个失败项索引，16#FFFF = 无 [索引] / first failed item index, sentinel 16#FFFF when none [index]
    afReadback      : ARRAY[0..15] OF REAL;   // 复核读回值 [用户单位] / verification readback values [user unit]
    uActiveIdx      : UINT;                   // 当前事务活动项索引（供 IO 层定位，规格补正引脚）[索引] / active item index for the IO layer, a spec correction pin [index]
    bWriteNow       : BOOL;                   // 本拍请求 IO 层执行写入/回写（规格补正引脚）/ request the IO layer to perform the write or the restore in this cycle, a spec correction pin
    eErr            : UDINT;                  // 错误码，0=正常 / error id, 0=ok
    bError          : BOOL;                   // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
END_VAR
VAR
    eState          : E_DL_ParamWriteState := eIdle; // 状态机当前态 / current state machine state
    fbTrigExec      : R_TRIG;                 // 执行沿实例，本体首部无条件刷新 / execute edge instance, refreshed unconditionally
    fbTrigAbort     : R_TRIG;                 // 中止沿实例，本体首部无条件刷新 / abort edge instance, refreshed unconditionally
    fbTrigReset     : R_TRIG;                 // 复位沿实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    fbWrite         : TON;                    // 写超时实例，本体首部无条件刷新 / write timeout instance, refreshed unconditionally
    fbVerify        : TON;                    // 复核超时实例，本体首部无条件刷新 / verification timeout instance, refreshed unconditionally
    uIdx            : UINT;                   // 事务游标 [索引]，范围 0~15 / transaction cursor [index], range 0~15
    uScan           : UINT;                   // 全表扫描游标 [索引] / full table scan cursor [index]
    afBackup        : ARRAY[0..15] OF REAL;   // 写前快照 [用户单位] / pre-write snapshot [user unit]
    bAllOk         : BOOL;                    // 全表一致性判定标志 / full table consistency flag
    bItemOk        : BOOL;                    // 单项一致性判定标志 / single item consistency flag
    bNonFin        : BOOL;                    // 写值非有限判定标志 / non-finite write value flag
    fTolEff        : REAL;                    // 生效容差（负值收敛到 0）[用户单位] / effective tolerance, negatives converge to zero [user unit]
END_VAR
VAR CONSTANT
    DL_DPW_ITEM_MAX  : UINT := 16;            // 项数上限 [项] / item count upper bound [item]
    DL_DPW_NONE      : UINT := 16#FFFF;       // 无失败项哨兵 [索引] / no failed item sentinel [index]
    DL_DPW_TMO_MIN   : TIME := T#100MS;       // 超时下限 [ms] / timeout lower bound [ms]
    DL_DPW_TMO_MAX   : TIME := T#60S;         // 超时上限 [ms] / timeout upper bound [ms]
    DL_DPW_CNT_MAX   : UINT := 65535;         // 项数计数饱和值 [项] / item counter saturation value [item]
    DL_FLOAT_EPS     : REAL := 1.0E-6;        // 浮点判等容差 [无量纲] / float equality tolerance [dimensionless]
    DL_DPW_INF_GUARD : REAL := 1.0E38;        // 非有限幅值判定阈值 [无量纲] / non-finite magnitude guard [dimensionless]
    DL_DPW_ZERO      : REAL := 0.0;           // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
    DL_DPW_CNT_ZERO  : UINT := 0;             // 无符号零常量 [无量纲] / unsigned zero constant [dimensionless]
END_VAR

// 段 1｜边沿与定时器实例无条件周期刷新（红线：严禁放入条件分支）/ segment 1, unconditional refresh
fbTrigExec(CLK := bExecute);
fbTrigAbort(CLK := bAbort);
fbTrigReset(CLK := bReset);
fbWrite(IN := (eState = eWrite) OR (eState = eRollback), PT := tWriteTimeout); // 写入与回写共用写超时 / writing and restoring share the write timeout
fbVerify(IN := (eState = eVerify), PT := tVerifyTimeout);                      // 复核独立超时 / verification has its own timeout

// 段 2｜输出与错误状态预置（bRollback 为保持量，不预置）/ segment 2, preset outputs, the rollback latch is kept
bDone := FALSE;                               // 单周期脉冲先清 / clear the single-cycle pulse first
bWriteNow := FALSE;                           // 写请求先清 / clear the write request
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bBusy := (eState <> eIdle) AND (eState <> eDone) AND (eState <> eFault); // 忙标志由状态导出 / the busy flag derives from the state

// 段 3｜复位沿清故障与回滚锁存 / segment 3, reset clears the faults and the rollback latch
IF fbTrigReset.Q THEN
    bRollback := FALSE;                       // 清回滚锁存 / clear the rollback latch
    uFailedIdx := DL_DPW_NONE;                // 清失败项索引 / clear the failed item index
    IF (eState = eFault) OR (eState = eDone) THEN
        eState := eIdle;                      // 复位允许离开故障与完成态 / a reset leaves the fault and done states
    END_IF
END_IF

// 段 4｜中止沿：人为中止不置故障、不自动回滚 / segment 4, abort without a fault and without a rollback
IF fbTrigAbort.Q THEN
    eState := eIdle;                          // 回空闲态 / back to idle
    bBusy := FALSE;                           // 撤忙标志 / drop the busy flag
    bWriteNow := FALSE;                       // 撤写请求 / drop the write request
    RETURN;                                   // 中止即出口 / abort is the exit
END_IF

// 段 5｜使能闸 / segment 5, enable gate
IF NOT bEnable THEN
    eState := eIdle;                          // 回空闲态 / back to idle
    bBusy := FALSE;                           // 撤忙标志 / drop the busy flag
    RETURN;                                   // 失能即出口 / disabled is the exit
END_IF

// 段 6｜容差收敛与参数闸（超时与容差先口径统一）/ segment 6, tolerance and timeout convergence
fTolEff := MAX(fVerifyTol, DL_DPW_ZERO);      // 容差负数收敛到 0（0 = 严格相等，不推荐）/ a negative tolerance converges to zero
IF (tWriteTimeout < DL_DPW_TMO_MIN) OR (tWriteTimeout > DL_DPW_TMO_MAX)
   OR (tVerifyTimeout < DL_DPW_TMO_MIN) OR (tVerifyTimeout > DL_DPW_TMO_MAX) THEN
    eErr := 16#0003_0339;                     // 超时参数越界按项数同码处理（事务不可启动）/ an illegal timeout shares the item count fault id, the transaction cannot start
    bError := TRUE;                           // 置故障标志 / raise the error flag
    eState := eFault;                         // 落故障态 / enter the fault state
    bBusy := FALSE;                           // 不忙 / not busy
    RETURN;                                   // 故障级提前返回 / early return on fault
END_IF

// 段 7｜执行沿启动：项数闸在最前，越界绝不索引数组 / segment 7, start edge with the item count gate first
IF fbTrigExec.Q AND ((eState = eIdle) OR (eState = eDone) OR (eState = eFault)) THEN
    IF (uCount < 1) OR (uCount > DL_DPW_ITEM_MAX) THEN
        eErr := 16#0003_0339;                 // 项数越界故障码 / item count out of range fault id
        bError := TRUE;                       // 置故障标志 / raise the error flag
        eState := eFault;                     // 落故障态 / enter the fault state
        RETURN;                               // 事务不启动 / the transaction never starts
    END_IF
    uIdx := DL_DPW_CNT_ZERO;                  // 游标归零 / reset the cursor
    uWritten := DL_DPW_CNT_ZERO;              // 已写项数清零 / clear the written count
    uSkipped := DL_DPW_CNT_ZERO;              // 跳过项数清零 / clear the skipped count
    uFailedIdx := DL_DPW_NONE;                // 失败项清哨兵 / reset the failed item to the sentinel
    uActiveIdx := DL_DPW_NONE;                // 活动项清哨兵 / reset the active index to the sentinel
    eState := eBackup;                        // 进入备份相 / enter the backup phase
END_IF

// 段 8｜状态机（含 ELSE 兜底）/ segment 8, state machine with ELSE fallback
CASE eState OF
    eIdle:
        bBusy := FALSE;                       // 空闲不忙 / idle is not busy

    eBackup:
        // 段 9｜抓取写前快照（白名单外项也备份，回滚需要完整镜像）/ segment 9, capture the pre-write snapshot
        FOR uScan := 0 TO uCount - 1 DO
            afBackup[uScan] := afActual[uScan]; // 快照取设备实际值 / the snapshot takes the device actual value
            afReadback[uScan] := afActual[uScan]; // 读回镜像同步初始化 / initialise the readback mirror
        END_FOR
        eState := eWrite;                     // 备份完成进入写入相 / the backup is complete, enter the write phase

    eWrite:
        // 段 10｜逐项白名单写：只读项绝不写，跳过并计数 / segment 10, whitelisted writes only
        IF uIdx >= uCount THEN
            eState := eVerify;                // 全部处理完进入复核相 / everything processed, enter the verification phase
        ELSE
            bNonFin := (afWriteValue[uIdx] <> afWriteValue[uIdx])
                    OR (afWriteValue[uIdx] > DL_DPW_INF_GUARD)
                    OR (afWriteValue[uIdx] < -DL_DPW_INF_GUARD); // 写值非有限判定 / non-finite write value detection
            IF bNonFin THEN
                eErr := 16#0003_033A;         // 写值非有限，转回滚 / a non-finite value triggers the rollback
                bError := TRUE;               // 置故障标志 / raise the error flag
                uFailedIdx := uIdx;           // 记录失败项 / record the failed item
                eState := eRollback;          // 转回滚相 / enter the rollback phase
            ELSIF (NOT abWritable[uIdx]) OR (auIndex[uIdx] < 1) THEN
                IF uSkipped < DL_DPW_CNT_MAX THEN
                    uSkipped := uSkipped + 1; // 白名单外或索引非法：饱和计数跳过 / outside the whitelist or an illegal index, saturating skip count
                END_IF
                eErr := 16#0003_0170;         // 信息级：白名单外项已跳过 / info level, the item was skipped
                uIdx := uIdx + 1;             // 游标前进 / advance the cursor
            ELSE
                uActiveIdx := uIdx;           // 发布活动项 / publish the active item
                bWriteNow := TRUE;            // 请求 IO 层执行写入 / request the IO layer to write
                afReadback[uIdx] := afActual[uIdx]; // 同步读回镜像 / keep the readback mirror in step
                bItemOk := ABS(afActual[uIdx] - afWriteValue[uIdx]) <= fTolEff; // 单项落值判定 / single item settled test
                IF bItemOk THEN
                    uWritten := uWritten + 1; // 落值即计入已写 / a settled value counts as written
                    uIdx := uIdx + 1;         // 游标前进（超时按整个写入相计，避免在 CASE 内调用实例）/ advance the cursor, the timeout covers the whole write phase so no instance call lives inside CASE
                ELSIF fbWrite.Q THEN
                    eErr := 16#0003_033A;     // 写超时，转回滚 / a write timeout triggers the rollback
                    bError := TRUE;           // 置故障标志 / raise the error flag
                    uFailedIdx := uIdx;       // 记录失败项 / record the failed item
                    eState := eRollback;      // 转回滚相 / enter the rollback phase
                END_IF
            END_IF
        END_IF

    eVerify:
        // 段 11｜全表复核：读回值与目标值逐项比对（只读项不参与）/ segment 11, full table verification
        bAllOk := TRUE;                       // 先假设一致 / assume consistency first
        FOR uScan := 0 TO uCount - 1 DO
            IF abWritable[uScan] AND (auIndex[uScan] >= 1) THEN
                afReadback[uScan] := afActual[uScan]; // 抓取复核读回值 / capture the verification readback
                IF ABS(afActual[uScan] - afWriteValue[uScan]) > fTolEff THEN
                    bAllOk := FALSE;          // 任一项不一致即失败 / a single mismatch fails the verification
                    uFailedIdx := uScan;      // 记录首个不一致项 / record the first mismatching item
                END_IF
            END_IF
        END_FOR
        IF bAllOk THEN
            eState := eDone;                  // 复核通过 / verification passed
            bDone := TRUE;                    // 单周期完成脉冲 / single-cycle done pulse
            bBusy := FALSE;                   // 事务结束 / the transaction finished
        ELSIF fbVerify.Q THEN
            eErr := 16#0003_033A;             // 复核不一致且超时，转回滚 / verification failed within its timeout, roll back
            bError := TRUE;                   // 置故障标志 / raise the error flag
            eState := eRollback;              // 转回滚相 / enter the rollback phase
        ELSE
            bBusy := TRUE;                    // 复核进行中 / verification in progress
        END_IF

    eRollback:
        // 段 12｜回滚：把备份快照逐项写回，全表恢复才算出清 / segment 12, restore the snapshot
        bAllOk := TRUE;                       // 先假设已恢复 / assume restored first
        bWriteNow := TRUE;                    // 持续请求 IO 层回写 / keep requesting the restore
        FOR uScan := 0 TO uCount - 1 DO
            IF abWritable[uScan] AND (auIndex[uScan] >= 1) THEN
                uActiveIdx := uScan;          // 回写活动项 / the item being restored
                IF ABS(afActual[uScan] - afBackup[uScan]) > fTolEff THEN
                    bAllOk := FALSE;          // 尚未恢复 / not yet restored
                    uFailedIdx := uScan;      // 记录回滚受阻项 / record the blocked item
                END_IF
                afReadback[uScan] := afActual[uScan]; // 同步读回 / keep the readback in step
            END_IF
        END_FOR
        IF bAllOk THEN
            bRollback := TRUE;                // 回滚完成，锁存 / the rollback completed, latch it
            eErr := 16#0003_033A;             // 事务失败（已回滚）故障码 / the transaction failed and was rolled back
            bError := TRUE;                   // 置故障标志 / raise the error flag
            eState := eFault;                 // 进故障态待人工确认 / enter the fault state pending manual acknowledgement
            bWriteNow := FALSE;               // 撤回写请求 / drop the restore request
        ELSIF fbWrite.Q THEN
            bRollback := TRUE;                // 回滚失败同样锁存 / a failed rollback is latched as well
            eErr := 16#0003_033B;             // 参数区不可信，禁止自动重试 / the parameter area is untrustworthy, no automatic retry
            bError := TRUE;                   // 置故障标志 / raise the error flag
            eState := eFault;                 // 进故障态锁存 / latch the fault state
            bWriteNow := FALSE;               // 撤回写请求 / drop the restore request
        END_IF

    eDone:
        bBusy := FALSE;                       // 完成态不忙 / the done state is not busy
        bWriteNow := FALSE;                   // 撤写请求 / drop the write request

    eFault:
        bBusy := FALSE;                       // 故障态不忙 / the fault state is not busy
        bWriteNow := FALSE;                   // 撤写请求 / drop the write request

ELSE
    eErr := 16#0003_033B;                     // 故障级：非法状态兜底 / fault level, illegal state fallback
    bError := TRUE;                           // 置故障标志 / raise the error flag
    eState := eFault;                         // 回故障态 / fall back to the fault state
    bWriteNow := FALSE;                       // 撤写请求，绝不留在写入状态 / drop the write request, never stay in a writing state
END_CASE
END_FUNCTION_BLOCK
