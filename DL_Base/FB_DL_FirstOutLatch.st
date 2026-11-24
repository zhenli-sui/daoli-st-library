(*
    FB_DL_FirstOutLatch —— 多源故障首出锁存
    ------------------------------------------------------------------
    分类      : DL_Base / Signal
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : T2-8 ISA-18.2 公开的「首出 / 确认 / 锁存」生命周期语义；
                本库 FB_DL_PortDiagAggregator 首出三律（最小序号仲裁）同口径复用。
                只借公开首出语义与仲裁次序，不借任何实现代码行；clean-room 重写，
                未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R18）
    ------------------------------------------------------------------
    功能说明  : 16 路故障源并行输入，首个到来的源被锁存为唯一「首出原因」，后续源
                不得覆盖；bReset 上升沿清锁存且当拍不重新锁存（防复位自杀）；
                同拍多源按源序号最小仲裁，与库内首出三律同一口径，避免两套规则；
                uSrcCount 越界时不索引数组、全输出回安全值；
                bAnyFault / uFaultWord 为组合量（每拍重算不锁存），
                bLatched / uFirstIdx 为锁存量（仅复位或失能清除）。
    错误码    : 16#0001_0235 同拍多源故障，已按源序号最小仲裁为唯一首出——信息级，正常防御
                16#0001_0236 预留禁用（信息级，不得挪用）
                16#0001_0306 源数量参数越界（uSrcCount 不在 1~16）——故障级，本拍不锁存
                16#0001_0307 预留禁用（故障级，不得挪用）
                16#0001_0308 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_0235 用 / 16#0001_0236 预留 ｜ 16#0001_0306 用 / 16#0001_0307 预留 / 16#0001_0308 预留
    状态机    : 无 CASE，锁存由单比特保持（bLatchedInt），非法状态不可能出现，故以本节说明替代 ELSE 兜底
    采样约定  : bReset 的上升沿由 R_TRIG 在本体首部无条件刷新，绝不放入条件分支；
                本件无时间量参与，仲裁结果与任务周期无关，一个任务周期即完成一次仲裁。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R18）
*)
FUNCTION_BLOCK FB_DL_FirstOutLatch
VAR_INPUT
    bEnable   : BOOL;                          // 使能，FALSE 清锁存并冻结仲裁 / enable, FALSE clears the latch and freezes arbitration
    bReset    : BOOL;                          // 复位，上升沿清首出锁存且当拍不重新锁存 / reset, rising edge clears the first-out latch and does not re-latch this cycle
    aSrcFault : ARRAY[0..15] OF BOOL;          // 16 路故障源，索引即优先级 0 最高 [路] / 16 fault sources, index is priority, 0 highest [ch]
    uSrcCount : UINT := 16;                    // 有效源数 [路]，范围 1~16 / valid source count [ch], range 1~16
END_VAR
VAR_OUTPUT
    bAnyFault : BOOL;                          // 任一源故障，组合值不锁存 / any source fault, combination value not latched
    bLatched  : BOOL;                          // 首出已被锁存 / first-out latched
    uFirstIdx : UINT;                          // 首出源序号 0~15，未锁存时为哨兵 16#FFFF / first-out index 0~15, sentinel 16#FFFF when not latched
    uFaultWord: WORD;                          // 当拍故障位图，bit0 = 源 0 [位图] / current fault bitmap, bit0 = source 0 [bitmap]
    eErr      : UDINT;                         // 错误码，0=正常 / error id, 0=ok
    bError    : BOOL;                          // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
END_VAR
VAR
    fbTrigReset : R_TRIG;                      // 复位上升沿检测实例，本体首部无条件刷新 / reset rising edge instance, refreshed unconditionally at body top
    uIdx        : UINT;                        // 源扫描游标 [路] / source scan cursor [ch]
    bAny        : BOOL;                        // 本拍存在故障源的中间标志 / intermediate flag, any source active this cycle
    bInit       : BOOL := FALSE;               // 首扫标志，初值 FALSE，判据 NOT bInit / first-scan flag, initial FALSE, tested with NOT
    bLatchedInt : BOOL;                        // 内部首出锁存位 / internal first-out latch bit
    uFirstInt   : UINT := 16#FFFF;             // 内部首出序号寄存，初值为哨兵 / internal first-out index register, initialised to the sentinel
    uActCnt     : UINT;                        // 本拍有效故障源计数，用于多源仲裁提示 [路] / active source count this cycle, used for the arbitration hint [ch]
END_VAR
VAR CONSTANT
    DL_FIRSTOUT_SRC_MAX : UINT := 16;          // 源上限 [路] / source upper bound [ch]
    DL_FIRSTOUT_NONE    : UINT := 16#FFFF;     // 无首出哨兵 [无量纲] / no-first-out sentinel [dimensionless]
    DL_FIRSTOUT_BIT_MAX : UINT := 15;          // 位图最高位号 [位] / highest bitmap index [bit]
    DL_FIRSTOUT_BIT0    : WORD := 16#0001;     // 位图最低位掩码 [位图] / least significant bitmap mask [bitmap]
END_VAR

// 段 1｜边沿实例无条件周期刷新（红线：严禁放入条件分支）/ segment 1, unconditional edge refresh
fbTrigReset(CLK := bReset);

// 段 2｜输出与中间量预置：组合量每拍重算，锁存量由内部位承载 / segment 2, preset outputs and temporaries
bAnyFault := FALSE;                            // 组合量先按无故障预置 / preset no fault on the combination output
uFaultWord := 0;                               // 位图先清零 / clear the bitmap
eErr := 0;                                     // 预置无错误 / preset no error
bError := FALSE;                               // 预置无故障标志 / preset no fault flag
bAny := FALSE;                                 // 中间标志清零 / clear the intermediate flag
uActCnt := 0;                                  // 有效源计数清零 / clear the active source count

// 段 3｜首扫初始化（唯一合法范式：初值 FALSE，判据 NOT bInit）/ segment 3, first-scan initialisation
IF NOT bInit THEN
    bLatchedInt := FALSE;                      // 首扫不留锁存 / no latch survives the first scan
    uFirstInt := DL_FIRSTOUT_NONE;             // 首出序号回哨兵 / first-out index back to the sentinel
    bInit := TRUE;                             // 首扫只做一次 / first scan runs once only
END_IF

// 段 4｜使能闸：失能清锁存并冻结，不索引数组 / segment 4, enable gate clears the latch and freezes
IF NOT bEnable THEN
    bLatchedInt := FALSE;                      // 清锁存位 / clear the latch bit
    uFirstInt := DL_FIRSTOUT_NONE;             // 清首出序号 / clear the first-out index
    bLatched := FALSE;                         // 对外锁存输出复位 / reset the latched output
    uFirstIdx := DL_FIRSTOUT_NONE;             // 对外序号回哨兵 / reset the index output to the sentinel
    RETURN;                                    // 失能即出口，本拍不仲裁 / disabled is the exit, no arbitration this cycle
END_IF

// 段 5｜源数量参数闸：越界即故障级，全输出回安全值且绝不索引数组 / segment 5, source count gate
IF (uSrcCount < 1) OR (uSrcCount > DL_FIRSTOUT_SRC_MAX) THEN
    eErr := 16#0001_0306;                      // 源数量越界故障码 / source count out of range fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    bLatched := FALSE;                         // 锁存输出回安全值 / latched output to the safe value
    uFirstIdx := DL_FIRSTOUT_NONE;             // 序号输出回哨兵 / index output to the sentinel
    bLatchedInt := FALSE;                      // 内部锁存位清除 / clear the internal latch bit
    uFirstInt := DL_FIRSTOUT_NONE;             // 内部序号清除 / clear the internal index
    RETURN;                                    // 故障级提前返回 / early return on fault
END_IF

// 段 6｜组合扫描：位图与有效源计数（索引上界已由段 5 保证，位号不超过 15）/ segment 6, combination scan
FOR uIdx := 0 TO uSrcCount - 1 DO
    IF aSrcFault[uIdx] THEN
        bAny := TRUE;                          // 至少一源动作 / at least one source is active
        uActCnt := uActCnt + 1;                // 累加有效源数 / accumulate the active source count
        uFaultWord := uFaultWord OR SHL(DL_FIRSTOUT_BIT0, uIdx); // 置对应位，uIdx 不超过 15 故移位安全 / set the bit, uIdx never exceeds 15 so the shift is safe
    END_IF
END_FOR
bAnyFault := bAny;                             // 组合量对外输出 / publish the combination value

// 段 7｜复位沿优先于锁存（防自杀）：复位拍只清不锁 / segment 7, reset edge has priority over latching
IF fbTrigReset.Q THEN
    bLatchedInt := FALSE;                      // 复位清锁存 / reset clears the latch
    uFirstInt := DL_FIRSTOUT_NONE;             // 复位清序号 / reset clears the index
ELSIF (NOT bLatchedInt) AND bAny THEN
    FOR uIdx := 0 TO uSrcCount - 1 DO
        IF (uFirstInt = DL_FIRSTOUT_NONE) AND aSrcFault[uIdx] THEN
            uFirstInt := uIdx;                 // 只记第一个为真的源，索引最小即优先级最高 / record only the first active source, lowest index wins
        END_IF
    END_FOR
    bLatchedInt := TRUE;                       // 锁定首出 / latch the first-out source
    IF uActCnt > 1 THEN
        eErr := 16#0001_0235;                  // 同拍多源，已按最小序号仲裁（信息级不置故障）/ multiple sources in one cycle, arbitrated by lowest index (info level, no fault)
    END_IF
END_IF

// 段 8｜锁存量对位镜像 / segment 8, mirror the latched state to the outputs
bLatched := bLatchedInt;                       // 锁存输出镜像 / latched output mirror
uFirstIdx := uFirstInt;                        // 首出序号镜像 / first-out index mirror
END_FUNCTION_BLOCK
