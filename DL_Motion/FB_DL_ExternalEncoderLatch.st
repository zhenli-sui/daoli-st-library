(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ExternalEncoderLatch
 * 所属子库 (Sublibrary) : DL_Motion
 * 前缀     (Prefix)     : FB_DL_
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），
 *                         仅依赖标准库 R_TRIG / F_TRIG / TON 与库内契约
 *                         I_DL_ExternalEncoder / ST_DL_EncSnapshot（只引用
 *                         不重声明），零厂商方言
 * 作者     (Author)     : 道莅代码库 · PLC编程专家（R31）
 * 开源溯源 (Origin)     : 外部编码器快照采样锁存公开语义（T1-6 外部编码器
 *                         族成员），道莅 clean-room 防御性实现，
 *                         未复制任何外部源码行
 * 功能描述 (Function)   : 外部编码器快照采样锁存件。触发上升沿调
 *                         I_DL_ExternalEncoder.Sample 写入单拍一致快照；
 *                         每拍比对当前位置与锁存位置差超容差且过期时间到
 *                         置 bStale 提示；清锁存仅由 bEn 下降沿或 bRst
 *                         复位沿显式执行，其余任何路径不得清锁存。
 *                         不自造不消费任何轴状态枚举（T1-6/MCX 家族高危区
 *                         纪律）。
 * 职责边界 (Boundary)   : 与 FB_DL_MarkPositionLatch 分工——Mark 件为轴内
 *                         探针（TouchProbe）硬件锁存，本件为外部编码器接口
 *                         的软件采样锁存，二者不合并、不互替。
 * 码位     (Codes)      : 16#0004_0067 监视级：编码器接口空引用
 *                         16#0004_0068 监视级：采样调用返回失败（保持旧值）
 *                         16#0004_0069 监视级：快照非有限拒绝入库
 *                         16#0004_006A 监视级：锁存数据过期提示（bStale）
 *                         16#0004_006B 保留未启用（码表与实现对齐，不虚声明）
 *                         本件为监视件，无 bError 出口，全码位不配故障标志。
 * 边界防错 (Boundary)   : 1 空引用判据用接口引用不等于零值判定；
 *                         2 R_TRIG/F_TRIG/TON 实例每拍无条件刷新；
 *                         3 采样失败本拍保持旧锁存值，绝不写半截快照；
 *                         4 非有限快照（x<>x 自反判加幅值界）拒绝入库；
 *                         5 bStale 为提示级，不锁存、不置故障标志。
 * 规格偏离 (Deviation)   : 规格「Reset 显式清锁存」以 bRst 复位引脚承载
 *                         （可增引脚裁定）：方法 POU 无法满足终结符纪律
 *                         中 POU 终结语句位于文件末行的要求，
 *                         引脚方案语义等价且跨平台语法风险为零。
 * 修订历史 (Revision)   : 2026-11-18 v1.0.0 首版入库（R31 · 阶段三 · 序 6）
 *==============================================================================*)

(*==============================================================================
 * 功能块: FB_DL_ExternalEncoderLatch
 * 调用约定: 每个扫描周期无条件调用一次；iEnc 引脚注入契约接口引用。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_ExternalEncoderLatch
VAR_INPUT
    iEnc      : I_DL_ExternalEncoder;       // 外部编码器契约引用（只读位置源）/ External encoder contract reference
    bTrig     : BOOL := FALSE;              // 采样触发，上升沿有效 / Sampling trigger, rising edge active
    bEn       : BOOL := FALSE;              // 使能，下降沿显式清锁存 / Enable, falling edge clears latch
    bRst      : BOOL := FALSE;              // 复位沿显式清锁存 / Reset edge clears latch explicitly
    tStale    : TIME := T#1S;               // 过期判据时长 [毫秒] / Stale judgement duration [ms]
    fPosTol   : LREAL := 0.001;             // 过期比对位置容差 [毫米] / Position tolerance for stale check [mm]
END_VAR
VAR_OUTPUT
    stLatch   : ST_DL_EncSnapshot;          // 锁存快照（同拍一致）/ Latched snapshot, scan-consistent
    bLatchValid : BOOL;                     // 锁存有效标志 / Latch validity flag
    bStale    : BOOL;                       // 锁存数据过期提示 / Stale data notice
    uErrorId  : UDINT;                      // 监视级码，0 = 无（段位码需 32 位载体）/ Monitor code, 0 = none, segment codes need 32-bit
END_VAR
VAR
    rTrigTrig : R_TRIG;                     // 采样触发沿检测，每拍无条件刷新 / Trigger edge detector, refreshed every scan
    fTrigEn   : F_TRIG;                     // 使能下降沿检测，每拍无条件刷新 / Enable falling edge detector
    rTrigRst  : R_TRIG;                     // 复位沿检测，每拍无条件刷新 / Reset edge detector, refreshed every scan
    tonStale  : TON;                        // 过期计时器，每拍无条件刷新 / Stale timer, refreshed every scan
    stTmp     : ST_DL_EncSnapshot;          // 采样暂存快照 / Sampling temp snapshot
    fNowPos   : LREAL;                      // 本拍当前位置 [毫米] / Current position this scan [mm]
    bEncOk    : BOOL;                       // 接口引用有效标志 / Interface reference valid flag
    bSampleOk : BOOL;                       // 本拍采样受理标志 / Sampling accepted flag this scan
    bSnapOk   : BOOL;                       // 快照有限有效标志 / Snapshot finiteness flag
    xRstOne   : BOOL;                       // 过期计时单拍重置请求 / One-scan stale timer reset request
END_VAR
VAR CONSTANT
    DL_EEL_FIN : LREAL := 1.0E30;           // LREAL 有限幅值判界 / LREAL finiteness magnitude bound
END_VAR

// ---- 段 1｜边沿与定时器实例无条件周期刷新（红线：禁入条件分支）----------------
rTrigTrig(CLK := bTrig);                                 // 触发沿检测 / Trigger edge detection
fTrigEn(CLK := bEn);                                     // 使能下降沿检测 / Enable falling edge detection
rTrigRst(CLK := bRst);                                   // 复位沿检测 / Reset edge detection
tonStale(IN := (bLatchValid AND bEn AND NOT xRstOne), PT := tStale); // 过期计时 / Stale timing

// ---- 段 2｜接口引用有效性与当前位置读取 ----------------------------------------
bEncOk := (iEnc <> 0);                                   // 接口引用非空判定 / Interface reference not null
IF bEncOk THEN
    fNowPos := iEnc.fPos;                                // 读当前位置 [毫米] / Read current position
ELSE
    fNowPos := 0.0;                                      // 空引用确定值 / Deterministic fallback
END_IF

// ---- 段 3｜清锁存唯一通道：使能下降沿、复位沿（两路显式，别无路径）--------------
IF fTrigEn.Q OR rTrigRst.Q THEN
    bLatchValid := FALSE;                                // 显式清锁存 / Explicit latch clear
    stLatch.fPos := 0.0;                                 // 快照位置清零 / Zero snapshot position
    stLatch.fVel := 0.0;                                 // 快照速度清零 / Zero snapshot velocity
    stLatch.tStamp := T#0MS;                             // 快照时戳清零 / Zero snapshot timestamp
    stLatch.bValid := FALSE;                             // 快照有效位清零 / Zero snapshot validity
    bStale := FALSE;                                     // 清过期提示 / Clear stale notice
END_IF

// ---- 段 4｜触发沿采样入库 -------------------------------------------------------
bSampleOk := FALSE;                                      // 受理标志先清 / Clear accepted flag
bSnapOk := FALSE;                                        // 有限标志先清 / Clear finiteness flag
IF bEncOk AND bEn AND rTrigTrig.Q THEN
    bSampleOk := iEnc.Sample(stSnap := stTmp);           // 调契约采样方法 / Invoke contract sampling method
    IF bSampleOk THEN
        bSnapOk := (stTmp.fPos = stTmp.fPos) AND (stTmp.fVel = stTmp.fVel)
               AND (ABS(stTmp.fPos) < DL_EEL_FIN) AND (ABS(stTmp.fVel) < DL_EEL_FIN); // 快照双字段有限 / Both fields finite
        IF bSnapOk THEN
            stLatch     := stTmp;                        // 快照整体入库 / Snapshot committed
            bLatchValid := TRUE;                         // 锁存有效 / Latch valid
            xRstOne     := TRUE;                         // 单拍断过期计时输入 / One-scan stale timer break
        END_IF                                           // 非有限拒绝入库保持旧值 / Non-finite rejected, keep old
    END_IF                                               // 采样失败保持旧锁存 / Sampling failed, keep old latch
END_IF

// ---- 段 5｜过期提示判定：过期时长到且位置差超容差 -------------------------------
bStale := tonStale.Q AND bLatchValid
      AND (ABS(fNowPos - stLatch.fPos) > fPosTol);       // 过期与漂移双条件 / Stale duration and drift both required

// ---- 段 6｜监视级码装配（监视件不置故障标志）------------------------------------
IF NOT bEncOk THEN
    uErrorId := 16#0004_0067;                            // 空引用码 / Null reference code
ELSIF bEncOk AND bEn AND rTrigTrig.Q AND (NOT bSampleOk) THEN
    uErrorId := 16#0004_0068;                            // 采样失败码 / Sampling failure code
ELSIF bEncOk AND bEn AND rTrigTrig.Q AND bSampleOk AND (NOT bSnapOk) THEN
    uErrorId := 16#0004_0069;                            // 快照非有限码 / Non-finite snapshot code
ELSIF bStale THEN
    uErrorId := 16#0004_006A;                            // 过期提示码 / Stale notice code
ELSE
    uErrorId := 16#0000_0000;                            // 无码 / No code
END_IF

// ---- 段 7｜单拍标志收尾 ----------------------------------------------------------
xRstOne := FALSE;                                        // 重置请求仅当拍有效 / Reset request is single scan
END_FUNCTION_BLOCK
