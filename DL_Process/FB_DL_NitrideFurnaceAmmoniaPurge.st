(*==============================================================================
 * 组件名称 (Component)  : FB_DL_NitrideFurnaceAmmoniaPurge
 * 所属子库 (Sublibrary) : DL_Process
 * 归属目录 (Directory)  : C:\Library\DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 分类/来源标签         : 功能块（FUNCTION_BLOCK）· 热处理工艺 · 氮化炉氨吹扫顺控
 *                         industry-pool / heat-treatment / nitriding / purge-seq
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library 的 TON / ABS
 * 溯源声明 (Provenance) : 道莅自研 clean-room——只借公开规范条款与工程惯例，零代码行复制。
 * 功能一句话 (Summary)  : 氮化炉氨吹扫两段顺控：大流量吹扫 + 小流量置换，
 *                         氨分解率与残氨双判据，残氨排放联锁超限即中止。
 *
 * 功能描述 (Function)   : 六相状态机：待机/预检/一段吹扫/二段置换/合格判定/
 *                         中止保持。预检校验分解率与残氨数据有效；一段按
 *                         时限大流量吹扫，二段按时限小流量置换；任一相残氨
 *                         超联锁阈立即转中止保持（保守方向：氨阀关、氮阀
 *                         关、排放风机停），分解率域外或非有限同样中止；
 *                         两段时限全部走完且残氨合格转合格判定（信息级）。
 *                         中止保持仅撤使能或重新起动指令可解除。
 * 与既有件边界 (Boundary): 本件只编排吹扫阀组与排放风机，不控炉温；
 *                         氨分解率分析仪信号由引脚注入。
 * 码位说明 (Codes)      : 信息 16#0006_302D 吹扫合格完成
 *                         故障 16#0006_302E 输入非有限，保守中止
 *                         故障 16#0006_302F 残氨超排放联锁阈，中止保持
 *                         故障 16#0006_3030 分解率域外（小于 0 或大于 100）
 *                         段 16#06_0_2D~31 首槽信息级、次槽起故障级。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 TON / ABS。
 * 红线自检 (Redline)    : 零全局依赖 ｜ 零 VAR_EXTERNAL ｜ 零 %I/%Q（阀组引脚）
 *                         NaN/Inf 精确判据拦截 ｜ 浮点比较带 fEps 容差
 *                         ENUM 配 CASE 且 ELSE 兜底 ｜ TON 每周期无条件刷新
 *                         全变量双语同行注释 ｜ 安全联锁最高优先、保守失败方向
 * 修订历史 (Revision)   : 2026-11-18  v1.0.0  首版入库（R32 · 批 4）
 *============================================================================*)

FUNCTION_BLOCK FB_DL_NitrideFurnaceAmmoniaPurge
VAR_INPUT
    bRun       : BOOL;                    // 顺控使能，假则中止保持清故障 / Enable, FALSE aborts and clears
    bStart     : BOOL;                    // 起动指令 [事件]，待机相起动 / Start command
    fDissocPct : LREAL;                   // 氨分解率 [％]，域 0 到 100 / Ammonia dissociation percent
    fNh3Ppm    : LREAL;                   // 残氨浓度 [ppm] / Residual ammonia ppm
    fNh3IlkPpm : LREAL := 1000.0;         // 残氨排放联锁阈 [ppm] / Emission interlock threshold
    fNh3OkPpm  : LREAL := 200.0;         // 吹扫合格残氨阈 [ppm] / Purge pass threshold
    tStage1S   : TIME  := T#20M;          // 一段大流量吹扫时限 [s] / Stage 1 duration
    tStage2S   : TIME  := T#10M;          // 二段小流量置换时限 [s] / Stage 2 duration
    fEps       : LREAL := 1.0E-6;         // 浮点判零容差 [实数域] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    oNh3Valve  : BOOL;                  // 氨阀输出 [引脚] / Ammonia valve output
    oN2Valve   : BOOL;                  // 氮阀输出 [引脚] / Nitrogen valve output
    oExhFan    : BOOL;                  // 排放风机输出 [引脚] / Exhaust fan output
    ePhase     : (ePhStandby := 0, ePhPrecheck := 1, ePhStage1 := 2, ePhStage2 := 3, ePhVerify := 4, ePhAbort := 5);  // 相枚举输出 / Phase output
    bDone      : BOOL;                  // 吹扫完成脉冲 [事件] / One-shot done pulse
    bError     : BOOL;                  // 故障标志，与故障码配对 / Fault flag paired with codes
    uErrorId   : UDINT;                 // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    _ePhase   : (ePhStandby := 0, ePhPrecheck := 1, ePhStage1 := 2, ePhStage2 := 3, ePhVerify := 4, ePhAbort := 5);   // 内部相 / Internal phase
    tonSt1    : TON;    // 一段时限定时器 [s]，每拍无条件刷新 / Stage 1 timer
    tonSt2    : TON;    // 二段时限定时器 [s]，每拍无条件刷新 / Stage 2 timer
    bSigOk    : BOOL;   // 分析数据有效标志 / Analyzer validity flag
    bStartEdge: BOOL;   // 起动沿暂存 / Start edge staging
    uCodeLatch: UDINT;  // 故障锁存码 [码] / Latched fault code
    uInfoCode : UDINT;  // 信息级单拍码 [码] / One-shot info code
    uPrevStart: BOOL;   // 上拍起动指令快照 [开关] / Previous start snapshot
END_VAR

(* 段 1｜定时器无条件刷新（红线 7）/ Timers refreshed unconditionally *)
tonSt1(IN := (_ePhase = ePhStage1) AND bRun, PT := tStage1S);    // 一段计时 / Stage 1 timing
tonSt2(IN := (_ePhase = ePhStage2) AND bRun, PT := tStage2S);    // 二段计时 / Stage 2 timing
bStartEdge := bStart AND (NOT uPrevStart);                       // 起动上升沿 / Start rising edge
uPrevStart := bStart;                                            // 快照更新 / Update the snapshot

(* 段 2｜分析数据有效性（每拍计算，判据门控挂状态量）/ Analyzer validity each scan *)
bSigOk := (fNh3Ppm = fNh3Ppm) AND (fDissocPct = fDissocPct)      // NaN 自反判据 / NaN reflexivity
          AND (ABS(fNh3Ppm) < 1.0E308) AND (ABS(fDissocPct) < 1.0E308)   // Inf 上限判据 / Inf limit
          AND (fDissocPct >= -fEps) AND (fDissocPct <= 100.0 + fEps);    // 分解率物理域 / Physical domain

(* 段 3｜最高优先级安全联锁（先于 CASE）：残氨超阈或数据无效即中止
 *      Highest-priority safety before the CASE: abort on interlock or bad data *)
IF (bRun AND bSigOk AND (fNh3Ppm > fNh3IlkPpm)) OR (bRun AND (NOT bSigOk) AND (_ePhase <> ePhStandby)) THEN
    _ePhase := ePhAbort;                // 拍 N 转中止保持 / To abort hold
    IF NOT bSigOk THEN
        uCodeLatch := 16#0006_302E;     // 故障级：数据非有限 / Fault: non-finite data
    ELSE
        uCodeLatch := 16#0006_302F;     // 故障级：残氨超联锁阈 / Fault: over interlock
    END_IF
END_IF
IF bRun AND bSigOk AND ((fDissocPct < -fEps) OR (fDissocPct > 100.0 + fEps)) THEN
    _ePhase := ePhAbort;                // 分解率域外中止 / Abort on out-of-domain dissociation
    uCodeLatch := 16#0006_3030;         // 故障级：分解率域外 / Fault: dissociation out of domain
END_IF

(* 段 4｜相状态机主分派（ENUM 配 CASE，ELSE 兜底）/ Phase dispatch with ELSE interception *)
CASE _ePhase OF

    ePhStandby:
        (* 本拍行为：阀组全关保守待机；使能与起动沿俱备拍 N+1 进预检 / Valves closed; arm on start edge *)
        oNh3Valve := FALSE;             // 关氨阀 / Close the ammonia valve
        oN2Valve := FALSE;              // 关氮阀 / Close the nitrogen valve
        oExhFan := FALSE;               // 停排放风机 / Stop the fan
        bDone := FALSE;                 // 完成脉冲清 / Clear the done pulse
        IF bRun AND bStartEdge THEN
            _ePhase := ePhPrecheck;     // 拍 N+1 进预检 / To precheck next scan
        END_IF

    ePhPrecheck:
        (* 本拍行为：数据有效即开阀起步；无效保守回待机 / Arm the valves when data valid *)
        IF NOT bSigOk THEN
            _ePhase := ePhAbort;        // 拍 N+1 中止 / To abort next scan
            uCodeLatch := 16#0006_302E; // 故障级：数据无效 / Fault: bad data
        ELSE
            oN2Valve := TRUE;           // 氮阀常开吹扫 / Nitrogen valve open
            oExhFan := TRUE;            // 排放风机开 / Fan on
            _ePhase := ePhStage1;       // 拍 N+1 进一段 / To stage 1 next scan
        END_IF

    ePhStage1:
        (* 本拍行为：氨阀开大流量吹扫，时限满转二段 / Big flow purge, transfer on time *)
        oNh3Valve := TRUE;              // 氨阀开 / Ammonia valve open
        oN2Valve := TRUE;               // 氮阀开 / Nitrogen valve open
        oExhFan := TRUE;                // 风机开 / Fan on
        IF NOT bRun THEN
            _ePhase := ePhAbort;        // 撤使能中止 / Disable aborts
        ELSIF tonSt1.Q THEN
            oNh3Valve := FALSE;         // 氨阀关进二段 / Close ammonia for stage 2
            _ePhase := ePhStage2;       // 拍 N+1 进二段 / To stage 2 next scan
        END_IF

    ePhStage2:
        (* 本拍行为：小流量氮置换，时限满转合格判定 / Small flow swap, transfer on time *)
        oNh3Valve := FALSE;             // 氨阀保持关 / Ammonia stays closed
        oN2Valve := TRUE;               // 氮阀开 / Nitrogen valve open
        oExhFan := TRUE;                // 风机开 / Fan on
        IF NOT bRun THEN
            _ePhase := ePhAbort;        // 撤使能中止 / Disable aborts
        ELSIF tonSt2.Q THEN
            _ePhase := ePhVerify;       // 拍 N+1 进合格判定 / To verify next scan
        END_IF

    ePhVerify:
        (* 本拍行为：残氨合格即完成（信息级），超合格阈但低于联锁阈转中止保守重来 / Verify *)
        oNh3Valve := FALSE;             // 阀组保持 / Valves held
        oN2Valve := TRUE;
        oExhFan := TRUE;
        IF fNh3Ppm <= fNh3OkPpm THEN
            oNh3Valve := FALSE;         // 全阀收 / Close all
            oN2Valve := FALSE;
            oExhFan := FALSE;
            bDone := TRUE;              // 完成脉冲（单拍）/ One-shot done
            uInfoCode := 16#0006_302D;  // 信息级：吹扫合格 / Info: purge passed
            _ePhase := ePhStandby;      // 拍 N+1 回待机 / To standby next scan
        ELSE
            _ePhase := ePhAbort;        // 拍 N+1 中止保守重来 / To abort, conservative retry
            uCodeLatch := 16#0006_302F; // 故障级：残氨未达合格阈 / Fault: residual over pass threshold
        END_IF

    ePhAbort:
        (* 本拍行为：保守中止三输出全关；撤使能或重新起动沿解除 / Conservative abort, all outputs closed *)
        oNh3Valve := FALSE;             // 全关保守方向 / All closed, conservative
        oN2Valve := FALSE;
        oExhFan := FALSE;               // 风机停防残氨扩散受控 / Fan off, controlled containment
        IF (NOT bRun) OR bStartEdge THEN
            uCodeLatch := 16#0000_0000; // 解除锁存（可达解除路径）/ Clear the latch, reachable reset
            _ePhase := ePhStandby;      // 拍 N+1 回待机 / To standby next scan
        END_IF

ELSE
    oNh3Valve := FALSE;                 // 非法相全关保守 / Illegal phase, all closed
    oN2Valve := FALSE;
    oExhFan := FALSE;
    _ePhase := ePhAbort;                // 拦截进中止 / Intercept to abort
    uCodeLatch := 16#0006_302E;         // 故障：相越界 / Fault: phase out of range
END_CASE

(* 段 5｜出口装配 / Exit assembly *)
ePhase := _ePhase;                      // 相枚举输出 / Phase output
bError := (uCodeLatch <> 16#0000_0000); // 故障锁存回放 / Latched fault replay
IF uCodeLatch <> 16#0000_0000 THEN
    uErrorId := uCodeLatch;             // 故障码优先 / Fault first
    uInfoCode := 16#0000_0000;
ELSE
    uErrorId := uInfoCode;              // 信息码单拍 / Info one shot
    uInfoCode := 16#0000_0000;
END_IF
END_FUNCTION_BLOCK
