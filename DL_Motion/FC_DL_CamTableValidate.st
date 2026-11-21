(*
    FC_DL_CamTableValidate —— 凸轮表合法性校验
    ------------------------------------------------------------------
    分类      : DL_Motion / CamData
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : T1-6 PLCopen MC_CamTableSelect 表选择纪律（只借「凸轮表在下装前必须
                完成相位单调、首尾闭合、斜率可行性检查」的公开语义）；
                校验算法、掩码布局、容差处理与码位 100% 自有；clean-room 重写，
                未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    道莅 clean-room 防御性实现：语义借鉴、代码与码位 100% 自有
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R22 批 4 · #15）
    ------------------------------------------------------------------
    功能说明  : 凸轮表下装前的离线校验器。一趟扫描内同时评估五项：
                ① 相位严格递增（含重复点与倒序点）② 相位值与从轴值非有限
                ③ 周期表首尾相位闭合 ④ 段斜率上限 ⑤ 有效点数合法。
                返回 TRUE = 表可用于生产（斜率超限只提示不否决）。
    不早退    : 四类判据**全部**评估完再出口，掩码一次给全——现场改一张表往往要一并
                修好几处，早退会让人改一处、重下装、再报下一处，来回好几轮。
    职责边界  : ① 只判相位闭合，不判从轴首尾等值。周期凸轮若从轴不回零点会持续漂移，
                   但这条判据不在派单掩码位内，扩位会破坏下游对掩码位含义的既有依赖；
                   建表工具必须自己保证从轴首尾等值，本函数不替它兜底。
                ② 不判表内点数以外的高阶连续性（加速度跳变、冲击），那属于工艺设计。
                ③ 不修改传入数组，纯只读。
    容差说明  : fPhaseTol 为闭合容差。容差填成负值时闭合判据必然失败（安全侧：宁可不放行），
                本函数**不钳位**——钳位会让负值变成一个「看起来正常」的容差，掩盖填表错误。
                fMaxSlope 填成非正值时任何正斜率都会触发提示码，同样按安全侧处理，不钳位。
    错误码    : 16#0004_01DB 非周期表，已跳过首尾闭合校验——信息级
                16#0004_01DC 斜率超限，表仍可用（仅提示）——信息级
                16#0004_02F3 有效点数非法 / 相位非单调（倒序或重复点）——故障级，
                             掩码位 16（点数）与位 1（单调）共用本码（R90）
                16#0004_02F4 相位值或从轴值非有限（NaN / ±Inf）——故障级，掩码位 2
                16#0004_02F5 周期表首尾相位未闭合——故障级，掩码位 4
    码位总账  : 16#0004_01DB 用 / 16#0004_01DC 用 ｜ 16#0004_02F3 用 / 16#0004_02F4 用 / 16#0004_02F5 用
    掩码总账  : 位 1 = 相位非单调（含重复点）｜ 位 2 = 相位或从轴非有限｜ 位 4 = 首尾未闭合
                ｜ 位 8 = 斜率超限｜ 位 16 = 有效点数非法｜ 其余位恒 0（预留禁用，不得挪用）
    状态机    : N/A —— 纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 纯组合函数，无定时器、无内部驻留状态，调用即出结果。
                数组按值传入（两张表各 64 × 4 字节 = 512 字节），故本函数只应在建表 /
                下装 / 参数变更事件里调用，严禁放进 1 ms 级高速循环（那是拿扫描周期换校验）。
    依赖      : 仅 Standard.library（ABS / MAX / MIN），不引用任何其他 DL_ 子库。
    验收向量  :
                V1 域外早退：uSegCount = 1 → 掩码 16#0010、uFailIdx = 0、02F3、
                   bError = TRUE、返回 FALSE。
                V2 上限/提示：表合格但某段斜率 150 mm/° > fMaxSlope 100 → 掩码 16#0008、
                   01DC、返回 TRUE、bValid = TRUE（可用但需关注）。
                V3 相位重复点：afPhase[3] = afPhase[2]（Δphase = 0）→ 掩码 16#0001、
                   uFailIdx = 3、02F3、返回 FALSE；该段不参与斜率计算（除零前置闸）。
                V4 复位/跳过首拍：bCyclic = FALSE 且其余合格 → 掩码 0、01DB、返回 TRUE。
                V5 round-trip：把同一张表分别做成「闭合的周期表（末点 = 首点 + 360°
                   且从轴末点 = 首点）」与「相位倒序的坏表」，前者 TRUE、后者 FALSE 且
                   掩码恒含位 1。
    红线自检  : 1 全局变量声明零使用 / 外部变量访问零使用 / 物理地址零使用 —— 通过，全部量经引脚传入
                2 纯 IEC 61131-3 跨平台 —— 通过，仅 Standard.library
                3 防御性编程 —— 通过，除零前置闸先判 Δphase > 0 再算商，WHILE 带 nGuard
                   计数器，数组索引全部由已校验的点数上限约束
                4 声明行同行中英双语注释 + 单位 —— 通过，逐行附注
                5 ENUM + CASE —— 不适用（纯函数，状态机 N/A，头注释已声明）
                6 TON / R_TRIG —— 不适用（无实例、无周期驻留）
                7 无魔法数 —— 通过，点数上下限、掩码位、整圈角度全部 VAR CONSTANT
    修订记录  : 2026-11-16 v1.0.0 首次入库（R22 批 4 · #15）
*)
FUNCTION FC_DL_CamTableValidate : BOOL
VAR_INPUT
    afPhase     : ARRAY[0..DL_CAM_LAST_IDX] OF REAL;   // 相位表 [°]，须严格递增 / phase table [deg], must strictly increase
    afSlave     : ARRAY[0..DL_CAM_LAST_IDX] OF REAL;   // 从轴位置表 [mm]，与相位表同下标 / slave position table [mm], indexed like the phase table
    uSegCount   : UINT := 8;                   // 有效点数 [个]，范围 2~64 / number of valid points [pcs], range 2..64
    bCyclic     : BOOL := TRUE;                // 周期表须首尾相位闭合 / a cyclic table must close its phase across the wrap
    fPhaseTol   : REAL := 0.01;                // 闭合容差 [°]，负值即判闭合失败 / closure tolerance [deg], a negative value fails the check
    fMaxSlope   : REAL := 100.0;               // 段斜率上限 [mm/°]，仅提示不否决 / segment slope limit [mm/deg], informational only
END_VAR
VAR_OUTPUT
    uFailMask      : WORD;                     // 失败掩码，全部失败项同时置位 / failure mask, every failing criterion is set at once
    uFailIdx       : UINT;                     // 1 基首个失败段号，0 = 无 / one-based index of the first failing segment, 0 = none
    fMaxSlopeFound : REAL;                     // 实测最大段斜率 [mm/°] / largest measured segment slope [mm/deg]
    eErr           : UDINT;                    // 错误码，0 表示无错 / error code, 0 means no error
    bError         : BOOL;                     // 故障级标志，仅故障级错误置位 / fault-class flag, set only on fault-level codes
    bValid         : BOOL;                     // 校验结论可信标志，= NOT bError / verdict trustworthy flag, equals NOT bError
END_VAR
VAR
    uSegUse     : UINT;                        // 校验时实际使用的点数，已过范围门禁 / point count actually used after the range gate
    uMaskWork   : WORD;                        // 掩码累加器，出口一次性发布 / mask accumulator published once at the exit
    uIdxWork    : UINT;                        // 首个失败段号累加器 / first failing segment accumulator
    nI          : UINT;                        // 扫描下标 [个] / scan index [pcs]
    nGuard      : UINT;                        // 循环保护计数器，上限 DL_CAM_GUARD / loop guard counter bounded by DL_CAM_GUARD
    fDp         : REAL;                        // 本段相位增量 [°] / phase increment of this segment [deg]
    fDs         : REAL;                        // 本段从轴增量 [mm] / slave increment of this segment [mm]
    fSlope      : REAL;                        // 本段斜率 [mm/°] / slope of this segment [mm/deg]
    fClose      : REAL;                        // 首尾相位闭合偏差（已减整圈）[°] / closure deviation after removing one full turn [deg]
END_VAR
VAR CONSTANT
    DL_CAM_LAST_IDX  : UINT := 63;             // 数组末下标 [下标]，即点数上限 64 / last array index, i.e. a capacity of 64 points
    DL_CAM_SEG_MIN   : UINT := 2;              // 有效点数下限 [个] / lower bound of the point count [pcs]
    DL_CAM_SEG_MAX   : UINT := 64;             // 有效点数上限 [个] / upper bound of the point count [pcs]
    DL_CAM_GUARD     : UINT := 64;             // 循环保护上限 [拍]，与点数上限同源 / loop guard bound [scans], tied to the point capacity
    DL_CAM_FULL_TURN : REAL := 360.0;          // 整圈角度 [°] / one full turn [deg]
    DL_CAM_ZERO      : REAL := 0.0;            // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
    DL_CAM_MK_MONO   : WORD := 16#0001;        // 掩码位 1：相位非单调（含重复点）/ mask bit 1, the phase is not increasing
    DL_CAM_MK_FIN    : WORD := 16#0002;        // 掩码位 2：相位或从轴非有限 / mask bit 2, a phase or slave value is not finite
    DL_CAM_MK_CLOSE  : WORD := 16#0004;        // 掩码位 4：首尾相位未闭合 / mask bit 4, the phase does not close
    DL_CAM_MK_SLOPE  : WORD := 16#0008;        // 掩码位 8：斜率超限（仅提示）/ mask bit 8, the slope exceeds the limit, informational
    DL_CAM_MK_COUNT  : WORD := 16#0010;        // 掩码位 16：有效点数非法 / mask bit 16, the point count is illegal
    DL_CAM_MK_NONE   : WORD := 16#0000;        // 空掩码常量，避免裸字面量比较 / empty mask constant, avoids a bare literal comparison
END_VAR

// 段 1｜预置：掩码与段号先清零，出口一次性发布（R94 统一后处理）
// segment 1, preset the mask and the index so the exit publishes them once
uMaskWork := DL_CAM_MK_NONE;                    // 掩码清零 / clear the mask
uIdxWork := 0;                                  // 段号清零，0 = 无失败 / clear the index, 0 = none
fMaxSlopeFound := DL_CAM_ZERO;                  // 实测斜率清零 / clear the measured slope
eErr := 0;                                      // 预置无错误 / preset no error
bError := FALSE;                                // 预置无故障标志 / preset no error flag

// 段 2｜点数门禁：点数非法时后面任何判据都无从谈起，这是唯一的例外早退
// segment 2, the point-count gate, the only early exit because no criterion can be evaluated without a legal count
IF (uSegCount < DL_CAM_SEG_MIN) OR (uSegCount > DL_CAM_SEG_MAX) THEN
    uMaskWork := uMaskWork OR DL_CAM_MK_COUNT;  // 掩码位 16：有效点数非法 / mask bit 16, illegal point count
    uIdxWork := 0;                              // 点数非法时没有「失败段」可言 / an illegal count has no failing segment
    uFailMask := uMaskWork;                     // 发布掩码 / publish the mask
    uFailIdx := uIdxWork;                       // 发布段号 / publish the index
    fMaxSlopeFound := DL_CAM_ZERO;              // 未做扫描，斜率无实测值 / no scan was run so there is no measured slope
    eErr := 16#0004_02F3;                       // 故障级：点数非法（与单调失败共用本码，R90）/ fault: illegal count, shared with the monotonic failure
    bError := TRUE;                             // 置故障标志 / raise the fault flag
    bValid := FALSE;                            // 结论不可信 / the verdict is not trustworthy
    FC_DL_CamTableValidate := FALSE;            // 表不可用 / the table is not usable
ELSE
    uSegUse := uSegCount;                       // 点数合法，按实际点数扫描 / a legal count, scan the actual point set

    // 段 3｜单趟扫描：非有限检测与相位单调/斜率同环评估，绝不早退（R94 掩码要全）
    // segment 3, one pass evaluating the finiteness and the monotonic/slope criteria together, never exiting early
    nI := 0;                                    // 下标起点 / start the index at zero
    nGuard := 0;                                // 循环保护计数清零 / clear the loop guard
    WHILE (nI < uSegUse) AND (nGuard < DL_CAM_GUARD) DO
        // 3.1 非有限检测：同一式兼捕 NaN 与 ±Inf —— Inf 减 Inf 得 NaN，故自不自等同样成立；
        //     有限值减自身恒为 0，不会误报。
        // non-finite detection, one test catches NaN and plus/minus infinity alike while a finite value subtracts to zero
        IF (afSlave[nI] - afSlave[nI]) <> (afSlave[nI] - afSlave[nI]) THEN
            uMaskWork := uMaskWork OR DL_CAM_MK_FIN;    // 从轴值非有限 / the slave value is not finite
            IF uIdxWork = 0 THEN
                IF nI > 0 THEN
                    uIdxWork := nI;             // 该点所在段的段号（1 基）/ the segment that ends at this point
                ELSE
                    uIdxWork := 1;              // 首点归属第 1 段 / the first point belongs to segment one
                END_IF
            END_IF
        END_IF
        IF (afPhase[nI] - afPhase[nI]) <> (afPhase[nI] - afPhase[nI]) THEN
            uMaskWork := uMaskWork OR DL_CAM_MK_FIN;    // 相位值非有限，与从轴共用掩码位 2 / a non-finite phase shares mask bit 2
            IF uIdxWork = 0 THEN
                IF nI > 0 THEN
                    uIdxWork := nI;             // 该点所在段的段号（1 基）/ the segment that ends at this point
                ELSE
                    uIdxWork := 1;              // 首点归属第 1 段 / the first point belongs to segment one
                END_IF
            END_IF
        END_IF

        // 3.2 相位单调与段斜率：增量非正一律判单调失败，且绝不进入除法（除零前置闸）
        // monotonic test and slope, a non-positive increment fails the criterion and never reaches the division
        IF nI > 0 THEN
            fDp := afPhase[nI] - afPhase[nI - 1];   // 本段相位增量 [°] / phase increment of this segment [deg]
            IF NOT (fDp > DL_CAM_ZERO) THEN         // 含 0（重复点）、负（倒序）与 NaN 三种情形 / covers a duplicate, a reversal and NaN alike
                uMaskWork := uMaskWork OR DL_CAM_MK_MONO;   // 掩码位 1：相位非单调 / mask bit 1, the phase is not increasing
                IF uIdxWork = 0 THEN
                    uIdxWork := nI;             // 失败段号 = 末点序号（1 基）/ the failing segment equals the ending point index
                END_IF
            ELSE
                fDs := afSlave[nI] - afSlave[nI - 1];   // 本段从轴增量 [mm] / slave increment of this segment [mm]
                fSlope := ABS(fDs / fDp);               // 斜率绝对值，除子已判正 [mm/°] / absolute slope with a guarded divisor [mm/deg]
                IF fSlope > fMaxSlopeFound THEN
                    fMaxSlopeFound := fSlope;           // 记录实测最大斜率 / keep the largest measured slope
                END_IF
            END_IF
        END_IF

        nI := nI + 1;                           // 下标推进 / advance the index
        nGuard := nGuard + 1;                   // 保护计数推进 / advance the guard
    END_WHILE

    // 段 4｜首尾闭合：仅周期表判，非周期表跳过并留信息码
    // segment 4, closure check applied to cyclic tables only, a non-cyclic table skips it and leaves an info code
    IF bCyclic THEN
        fClose := afPhase[uSegUse - 1] - afPhase[0] - DL_CAM_FULL_TURN;     // 闭合偏差已去掉整圈 [°] / deviation after removing one full turn [deg]
        IF ABS(fClose) > fPhaseTol THEN
            uMaskWork := uMaskWork OR DL_CAM_MK_CLOSE;   // 掩码位 4：首尾相位未闭合 / mask bit 4, the phase does not close
            IF uIdxWork = 0 THEN
                uIdxWork := uSegUse;        // 闭合段是第 N 段（末点回到首点）/ the wrap segment is segment N, the last point back to the first
            END_IF
        END_IF
    END_IF

    // 段 5｜斜率提示：超限只置掩码位 8，绝不否决表（工艺上宽斜率常是有意为之）
    // segment 5, the slope hint sets mask bit 8 only, a wide slope is often deliberate and never rejects the table
    IF (fMaxSlopeFound > fMaxSlope) THEN
        uMaskWork := uMaskWork OR DL_CAM_MK_SLOPE;  // 掩码位 8：斜率超限（仅提示）/ mask bit 8, the slope exceeds the limit, informational only
    END_IF

    // 段 6｜错误码优先级：故障码先占，其次斜率提示，最后非周期提示（同拍只发一条，R45）
    // segment 6, code priority, faults first then the slope hint then the non-cyclic notice, one code per scan
    IF (uMaskWork AND DL_CAM_MK_MONO) <> DL_CAM_MK_NONE THEN
        eErr := 16#0004_02F3;                   // 故障级：相位非单调或点数非法（共用本码，R90）/ fault: the phase is not increasing or the count is illegal, shared code
        bError := TRUE;
    ELSIF (uMaskWork AND DL_CAM_MK_FIN) <> DL_CAM_MK_NONE THEN
        eErr := 16#0004_02F4;                   // 故障级：相位或从轴非有限 / fault: a phase or slave value is not finite
        bError := TRUE;
    ELSIF (uMaskWork AND DL_CAM_MK_CLOSE) <> DL_CAM_MK_NONE THEN
        eErr := 16#0004_02F5;                   // 故障级：周期表首尾相位未闭合 / fault: the cyclic table does not close
        bError := TRUE;
    ELSIF (uMaskWork AND DL_CAM_MK_SLOPE) <> DL_CAM_MK_NONE THEN
        eErr := 16#0004_01DC;                   // 信息级：斜率超限，表仍可用 / info: the slope exceeds the limit and the table stays usable
    ELSIF NOT bCyclic THEN
        eErr := 16#0004_01DB;                   // 信息级：非周期表，已跳过闭合校验 / info: a non-cyclic table skipped the closure check
    END_IF

    // 段 7｜出口：掩码与段号一次性发布，返回可用性
    // segment 7, publish the mask and the index once and return the usability
    uFailMask := uMaskWork;                     // 发布掩码（全部失败项同时给全）/ publish the mask with every failing criterion
    uFailIdx := uIdxWork;                       // 发布首个失败段号 / publish the first failing segment
    bValid := NOT bError;                       // 结论可信 = 无故障级错误（斜率提示不影响可信）/ the verdict is trustworthy without a fault-level code
    FC_DL_CamTableValidate := NOT bError;       // 返回 TRUE = 表可用 / TRUE means the table is usable
END_IF
END_FUNCTION
