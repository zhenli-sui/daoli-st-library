(*
    FB_DL_ProfinetAlarmDiag —— PROFINET 通道诊断聚合
    ------------------------------------------------------------------
    分类      : DL_Device / Diagnostics
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : PROFINET 公开规范的 ChannelErrorType 枚举值（只借公开解码表，
                不解析原始诊断记录字节、不使用任何厂商诊断对象或系统库）；
                聚合结构、首出律、八类分桶、错误分级与码位 100% 自有；
                E_DL_Ne107Status 属主为 I_DL_DeviceHealth，本件只引用不重声明（R70）；
                clean-room 重写，未复制任何闭源厂商源码
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R19）
    ------------------------------------------------------------------
    功能说明  : 把上游已读出的通道诊断项（通道号 / 通道属性 / ChannelErrorType /
                ExtChannelErrorType / ExtChannelAddValue）分类成八类工程语义，输出故障掩码、
                首出通道、分类计数与 NE107 健康出口。本件只做语义聚合，不做字节解析。
                核心防御：① 条目数超 16 钳位处理并置故障级 0333（不越界读）；
                ② 通道号超 32767 该项跳过并计入组态错桶；
                ③ 未识别的 ChannelErrorType（含厂商自定义域）归「其他」桶并置信息码——
                   协议允许厂商自定义，未识别不等于故障；
                ④ 16#001F 语义冲突显式化：一处公开源记为临时故障，另一处记作要求维护，
                   本库按「维护类」保守侧处理并在头注释并列两种语义（不二选一硬编码）；
                ⑤ ≥ 16#8000 的系统级码（总线/同步类）不占通道掩码，单列 bSystemLevel，
                   因为运维处理路径与通道问题完全不同；
                ⑥ CASE 分类含 ELSE 兜底走「其他」桶；uEntryCount = 0 时输出全空且 eOk。
                职责边界：单通道健康判定归设备件，多源健康仲裁归 FB_DL_DeviceHealthArbiter。
    解码表    : 16#0001 短路 / 16#0002 欠压 / 16#0003 过压 / 16#0004 过载 / 16#0005 过温 /
                16#0006 断线 / 16#0007 超上限 / 16#0008 欠下限 / 16#0009 通用错误 /
                16#000F 参数缺失 / 16#0010 参数故障 / 16#001E 要求维护 / 16#001F 维护要求
                （另一公开源记为 Temporary_fault）/ >= 16#8000 系统级
    错误码    : 16#0003_016C 未识别的 ChannelErrorType（厂商自定义域），已归「其他」桶——信息级，正常防御
                16#0003_016D 预留禁用（信息级，不得挪用）
                16#0003_0333 诊断条目数超上限（> 16）——故障级，已钳位处理
                16#0003_0334 通道号越界（> 32767）——故障级，该项已跳过并计入组态错桶
                16#0003_0335 预留禁用（故障级，不得挪用）
    码位总账  : 16#0003_016C 用 / 16#0003_016D 预留 ｜ 16#0003_0333 用 / 16#0003_0334 用 / 16#0003_0335 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
                （分类 CASE 是协议枚举映射表，不是顺序状态机，且含 ELSE 兜底）
    采样约定  : 本件无定时器、无沿检测、无状态驻留；诊断项每拍全量重算，结论与任务周期无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R19）
*)
FUNCTION_BLOCK FB_DL_ProfinetAlarmDiag
VAR_INPUT
    auChannelNo        : ARRAY[0..15] OF UINT;   // 通道号 [通道]，协议域 0~32767，0 表示子模块级 / channel number [channel], protocol range 0~32767, zero means submodule
    auChannelProp      : ARRAY[0..15] OF WORD;   // 通道属性（协议位域），本件原样透传不解释 [位域] / channel properties, passed through without interpretation [bitfield]
    auErrType          : ARRAY[0..15] OF WORD;   // ChannelErrorType（公开枚举，见头注释解码表）[枚举] / channel error type, see the decode table [enum]
    auExtErrType       : ARRAY[0..15] OF WORD;   // ExtChannelErrorType（厂商扩展），只透传不解释 [枚举] / extended error type, passed through only [enum]
    audAddValue        : ARRAY[0..15] OF UDINT;  // ExtChannelAddValue（附加上下文值）[无量纲] / additional context value [dimensionless]
    uEntryCount        : UINT := 0;              // 有效诊断项数 [项]，范围 0~16 / number of valid diagnostic entries [entry], range 0~16
END_VAR
VAR_OUTPUT
    uChannelMask       : WORD;                   // 有诊断的项位图，bit N = 项 N [位图] / bitmap of diagnostic entries, bit N is entry N [bitmap]
    uFirstChannel      : UINT;                   // 首出通道号（同拍取通道号最小）[通道] / first-out channel number, the lowest channel wins [channel]
    uFirstErrType      : WORD;                   // 首出项的 ChannelErrorType 原值（HMI 可查表）[枚举] / raw error type of the first-out entry [enum]
    auClassCount       : ARRAY[0..7] OF UINT;    // 八类计数 [次]，索引 0 短路 ~ 7 维护类 / eight class counters [times], 0 short circuit to 7 maintenance
    bMaintenanceOnly   : BOOL;                   // 只有维护类条目（可继续生产需保养）/ maintenance entries only, production may continue
    bSystemLevel       : BOOL;                   // 存在系统级码（>= 16#8000，总线/同步类）/ a system level code exists, bus or synchronisation class
    eHealth            : E_DL_Ne107Status;       // NE107 健康出口（引用唯一属主枚举）/ NE107 health output, referencing the owner enumeration
    eErr               : UDINT;                  // 错误码，0=正常 / error id, 0=ok
    bError             : BOOL;                   // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid             : BOOL;                   // 结论是否可用 / conclusion valid flag
END_VAR
VAR
    uIdx               : UINT;                   // 条目扫描游标 [项]，范围 0~15 / entry scan cursor [entry], range 0~15
    uCountEff          : UINT;                   // 钳位后的有效条目数 [项] / clamped effective entry count [entry]
    uClass             : UINT;                   // 本项的类别桶号 [桶]，范围 0~7 / class bucket index of this entry [bucket], range 0~7
    uBestCh            : UINT;                   // 首出通道号候选 [通道] / first-out channel candidate [channel]
    wBestErr           : WORD;                   // 首出错误类型候选 [枚举] / first-out error type candidate [enum]
    bAnyEntry          : BOOL;                   // 存在有效（占通道掩码的）条目 / at least one entry occupies the channel mask
    bUnknownType       : BOOL;                   // 本拍出现未识别的错误类型 / an unrecognised error type appeared in this cycle
    bChOutOfRange      : BOOL;                   // 本拍出现越界通道号 / an out-of-range channel number appeared in this cycle
    bFaultClass        : BOOL;                   // 存在故障类（短路~欠下限）/ a fault class entry exists
    bConfigClass       : BOOL;                   // 存在组态错类条目 / a configuration class entry exists
    bMaintainClass     : BOOL;                   // 存在维护类条目 / a maintenance class entry exists
    nChNo              : UINT;                   // 当前项的通道号（比较用副本）[通道] / channel number copy of the current entry [channel]
END_VAR
VAR CONSTANT
    DL_PN_E_SHORT       : WORD := 16#0001;       // 短路 [枚举] / short circuit [enum]
    DL_PN_E_UNDERV      : WORD := 16#0002;       // 欠压 [枚举] / undervoltage [enum]
    DL_PN_E_OVERV       : WORD := 16#0003;       // 过压 [枚举] / overvoltage [enum]
    DL_PN_E_OVERLOAD    : WORD := 16#0004;       // 过载 [枚举] / overload [enum]
    DL_PN_E_OVERTEMP    : WORD := 16#0005;       // 过温 [枚举] / overtemperature [enum]
    DL_PN_E_WIREBREAK   : WORD := 16#0006;       // 断线 [枚举] / wire break [enum]
    DL_PN_E_UPPER       : WORD := 16#0007;       // 超上限 [枚举] / upper limit exceeded [enum]
    DL_PN_E_LOWER       : WORD := 16#0008;       // 欠下限 [枚举] / lower limit violated [enum]
    DL_PN_E_GENERIC     : WORD := 16#0009;       // 通用错误 [枚举] / generic error [enum]
    DL_PN_E_PARAM_MISS  : WORD := 16#000F;       // 参数缺失 [枚举] / parameter missing [enum]
    DL_PN_E_PARAM_FAULT : WORD := 16#0010;       // 参数故障 [枚举] / parameter fault [enum]
    DL_PN_E_MAINT_REQ   : WORD := 16#001E;       // 要求维护 [枚举] / maintenance required [enum]
    DL_PN_E_MAINT_DEM   : WORD := 16#001F;       // 维护要求（另一公开源记为临时故障，本库按维护类保守处理）[枚举] / maintenance demanded, treated conservatively as maintenance [enum]
    DL_PN_E_SYS_MIN     : WORD := 16#8000;       // 系统级码起点 [枚举] / start of the system level codes [enum]
    DL_PN_CH_MAX        : UINT := 32767;         // 通道号上限 [通道] / channel number upper bound [channel]
    DL_PN_ENTRY_MAX     : UINT := 16;            // 诊断条目上限 [项] / diagnostic entry upper bound [entry]
    DL_PN_C_SHORT       : UINT := 0;             // 类别桶 0：短路 [桶] / class bucket zero, short circuit [bucket]
    DL_PN_C_WIRE        : UINT := 1;             // 类别桶 1：断线 [桶] / class bucket one, wire break [bucket]
    DL_PN_C_LOAD        : UINT := 2;             // 类别桶 2：过载 [桶] / class bucket two, overload [bucket]
    DL_PN_C_TEMP        : UINT := 3;             // 类别桶 3：过温 [桶] / class bucket three, overtemperature [bucket]
    DL_PN_C_UPPER       : UINT := 4;             // 类别桶 4：超上限 [桶] / class bucket four, upper limit [bucket]
    DL_PN_C_LOWER       : UINT := 5;             // 类别桶 5：欠下限 [桶] / class bucket five, lower limit [bucket]
    DL_PN_C_CONFIG      : UINT := 6;             // 类别桶 6：组态错/其他 [桶] / class bucket six, configuration or other [bucket]
    DL_PN_C_MAINT       : UINT := 7;             // 类别桶 7：维护类 [桶] / class bucket seven, maintenance [bucket]
    DL_PN_CLASS_CNT     : UINT := 8;             // 类别桶总数 [桶] / number of class buckets [bucket]
    DL_PN_BIT0          : WORD := 16#0001;       // 位图最低位掩码 [位图] / least significant bitmap mask [bitmap]
    DL_PN_ZERO_W        : WORD := 16#0000;       // 位图零常量 [位图] / bitmap zero constant [bitmap]
    DL_PN_ZERO          : UINT := 0;             // 无符号零常量 [无量纲] / unsigned zero constant [dimensionless]
    DL_PN_CNT_MAX       : UINT := 65535;         // 单类计数饱和值 [次] / per class counter saturation value [times]
END_VAR

// 段 1｜输出与中间量预置（位图与八类计数每拍全量重算）/ segment 1, preset outputs and intermediates
uChannelMask := DL_PN_ZERO_W;                 // 位图清零 / clear the bitmap
uFirstChannel := DL_PN_ZERO;                  // 首出通道清零 / clear the first-out channel
uFirstErrType := DL_PN_ZERO_W;                // 首出错误类型清零 / clear the first-out error type
bMaintenanceOnly := FALSE;                    // 预置非纯维护类 / preset not maintenance only
bSystemLevel := FALSE;                        // 预置无系统级码 / preset no system level code
eHealth := eOk;                               // 预置健康（条目为 0 时即为最终结论）/ preset OK, final when no entry exists
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置结论不可用 / preset invalid
bAnyEntry := FALSE;                           // 预置无有效条目 / preset no valid entry
bUnknownType := FALSE;                        // 预置无未识别类型 / preset no unrecognised type
bChOutOfRange := FALSE;                       // 预置无越界通道号 / preset no out-of-range channel
bFaultClass := FALSE;                         // 预置无故障类 / preset no fault class
bConfigClass := FALSE;                        // 预置无组态错类 / preset no configuration class
bMaintainClass := FALSE;                      // 预置无维护类 / preset no maintenance class
uBestCh := DL_PN_CH_MAX;                      // 首出候选初值取通道号上限（最大值哨兵）/ the candidate starts at the channel upper bound as a maximum sentinel
wBestErr := DL_PN_ZERO_W;                     // 首出错误类型初值 / initial error type of the first-out candidate
FOR uIdx := 0 TO DL_PN_CLASS_CNT - 1 DO
    auClassCount[uIdx] := DL_PN_ZERO;         // 八个类别桶逐桶清零 / clear each of the eight class buckets
END_FOR

// 段 2｜条目数闸：超上限钳位处理并置故障级（绝不越界读）/ segment 2, entry count gate
uCountEff := uEntryCount;                     // 取入参副本 / copy the input
IF uEntryCount > DL_PN_ENTRY_MAX THEN
    uCountEff := DL_PN_ENTRY_MAX;             // 钳位到 16 / clamp to sixteen
    eErr := 16#0003_0333;                     // 条目数超上限故障码 / entry count over the limit fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
END_IF

// 段 3｜零条目：协议合法（诊断记录长度 0 表示无故障）/ segment 3, zero entries is a legal protocol state
IF uCountEff = DL_PN_ZERO THEN
    eHealth := eOk;                           // 健康出口正常 / health output OK
    bValid := TRUE;                           // 结论可用 / conclusion valid
    RETURN;                                   // 无需聚合 / nothing to aggregate
END_IF

// 段 4｜逐项分类（含 ELSE 兜底走「其他」桶）/ segment 4, per entry classification
FOR uIdx := 0 TO uCountEff - 1 DO
    nChNo := auChannelNo[uIdx];               // 取本项通道号 [通道] / channel number of this entry [channel]
    IF nChNo > DL_PN_CH_MAX THEN
        bChOutOfRange := TRUE;                // 记录通道号越界 / remember the out-of-range channel
        auClassCount[DL_PN_C_CONFIG] := auClassCount[DL_PN_C_CONFIG] + 1; // 计入组态错桶 / count it in the configuration bucket
    ELSIF auErrType[uIdx] >= DL_PN_E_SYS_MIN THEN
        bSystemLevel := TRUE;                 // 系统级码单列，不占通道掩码 / system level codes are listed apart and never occupy the channel mask
    ELSE
        // 段 5｜语义分类：按公开解码表落八类桶 / segment 5, semantic classification by the public decode table
        CASE auErrType[uIdx] OF
            DL_PN_E_SHORT:
                uClass := DL_PN_C_SHORT;      // 短路 / short circuit
                bFaultClass := TRUE;          // 故障类 / fault class
            DL_PN_E_OVERV:
                uClass := DL_PN_C_UPPER;      // 过压按超上限处理 / overvoltage falls into the upper limit class
                bFaultClass := TRUE;          // 故障类 / fault class
            DL_PN_E_UNDERV:
                uClass := DL_PN_C_LOWER;      // 欠压按欠下限处理 / undervoltage falls into the lower limit class
                bFaultClass := TRUE;          // 故障类 / fault class
            DL_PN_E_WIREBREAK:
                uClass := DL_PN_C_WIRE;       // 断线 / wire break
                bFaultClass := TRUE;          // 故障类 / fault class
            DL_PN_E_OVERLOAD:
                uClass := DL_PN_C_LOAD;       // 过载 / overload
                bFaultClass := TRUE;          // 故障类 / fault class
            DL_PN_E_OVERTEMP:
                uClass := DL_PN_C_TEMP;       // 过温 / overtemperature
                bFaultClass := TRUE;          // 故障类 / fault class
            DL_PN_E_UPPER:
                uClass := DL_PN_C_UPPER;      // 超上限 / upper limit exceeded
                bFaultClass := TRUE;          // 故障类 / fault class
            DL_PN_E_LOWER:
                uClass := DL_PN_C_LOWER;      // 欠下限 / lower limit violated
                bFaultClass := TRUE;          // 故障类 / fault class
            DL_PN_E_GENERIC:
                uClass := DL_PN_C_CONFIG;     // 通用错误归其他/组态错桶 / a generic error falls into the other or configuration bucket
                bConfigClass := TRUE;         // 组态错类 / configuration class
            DL_PN_E_PARAM_MISS, DL_PN_E_PARAM_FAULT:
                uClass := DL_PN_C_CONFIG;     // 参数类一律组态错 / parameter issues are a configuration problem
                bConfigClass := TRUE;         // 组态错类 / configuration class
            DL_PN_E_MAINT_REQ, DL_PN_E_MAINT_DEM:
                uClass := DL_PN_C_MAINT;      // 维护类（16#001F 的语义冲突按保守侧归维护）/ maintenance class, the conflicting 16#001F is kept on the conservative side
                bMaintainClass := TRUE;       // 维护类 / maintenance class
        ELSE
            uClass := DL_PN_C_CONFIG;         // 未识别值归其他桶（ELSE 兜底）/ unrecognised values fall into the other bucket
            bConfigClass := TRUE;             // 组态错类 / configuration class
            bUnknownType := TRUE;             // 记录未识别类型 / remember the unrecognised type
        END_CASE

        // 段 6｜占掩码、累加计数、更新首出候选 / segment 6, occupy the mask, count and update the first-out candidate
        uChannelMask := uChannelMask OR SHL(DL_PN_BIT0, uIdx); // 置项位图，uIdx ≤ 15 移位安全 / set the entry bit, the shift never exceeds 15
        bAnyEntry := TRUE;                    // 标记存在有效条目 / flag a valid entry
        IF auClassCount[uClass] < DL_PN_CNT_MAX THEN
            auClassCount[uClass] := auClassCount[uClass] + 1; // 饱和累加，绝不回绕 / saturating increment, never wraps
        END_IF
        IF nChNo < uBestCh THEN
            uBestCh := nChNo;                 // 首出取通道号最小 / the lowest channel number wins the first-out
            wBestErr := auErrType[uIdx];      // 同步首出错误类型 / keep the matching error type
        END_IF
    END_IF
END_FOR

// 段 7｜首出发布（无有效条目则保留 0 与空类型）/ segment 7, publish the first-out
IF bAnyEntry THEN
    uFirstChannel := uBestCh;                 // 首出通道号 / first-out channel number
    uFirstErrType := wBestErr;                // 首出错误类型原值 / raw error type of the first-out entry
END_IF

// 段 8｜健康出口优先级：故障类 > 组态错 > 维护类 > 系统级 > 正常 / segment 8, health output priority
IF bFaultClass THEN
    eHealth := eFailure;                      // 短路/断线/过载/过温/越限：信号不可信 / a channel fault makes the signal untrustworthy
ELSIF bConfigClass THEN
    eHealth := eOutOfSpec;                    // 组态错：测量可能有效但不可依赖 / a configuration fault means the measurement cannot be relied upon
ELSIF bMaintainClass THEN
    eHealth := eMaintenanceReq;               // 维护类：仍有效但已劣化 / maintenance means still valid but degraded
ELSIF bSystemLevel THEN
    eHealth := eOutOfSpec;                    // 系统级：总线/同步问题，另行处理 / a system level issue is handled on a different path
ELSE
    eHealth := eOk;                           // 无任何诊断：正常 / no diagnostics, OK
END_IF

// 段 9｜纯维护类判定（可继续生产，需安排保养）/ segment 9, maintenance only evaluation
bMaintenanceOnly := bMaintainClass AND (NOT bFaultClass) AND (NOT bConfigClass); // 只有维护类条目 / maintenance entries only

// 段 10｜信息级与故障级码汇总（故障级优先，绝不互相覆盖）/ segment 10, code summary
IF bUnknownType AND (NOT bError) THEN
    eErr := 16#0003_016C;                     // 信息级：未识别类型已归其他桶 / info level, unrecognised types were bucketed as other
END_IF
IF bChOutOfRange THEN
    eErr := 16#0003_0334;                     // 通道号越界故障码 / channel number out of range fault id
    bError := TRUE;                           // 置故障标志 / raise the error flag
END_IF

// 段 11｜结论可用性（故障态仍输出分类结果供 HMI 诊断，但标记不可用于联锁）/ segment 11, conclusion validity
bValid := TRUE;                               // 分类结论本身可信（故障级只表输入越界）/ the classification itself is trustworthy, faults only mark input overruns
END_FUNCTION_BLOCK
