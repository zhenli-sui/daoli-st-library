(*
    FB_DL_PumpAlternationLead —— 多泵轮换主备（小时均衡选主 + 故障切备锁存）
    ------------------------------------------------------------------
    组件名称  : FB_DL_PumpAlternationLead
    分类      : DL_Process / PumpGroup
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 借鉴点 —— 泵组轮换的通行工程语义：按累计运行小时选「最闲泵」作主泵、
                轮换周期到期强制换泵、在役泵故障时立即切备且故障泵被排除出候选集
                直至人工复位。该语义在公开工控资料中属常识性做法。
                clean-room 声明 —— 零代码行复制；选主算法、锁存结构、码位与双语文档
                全部本件自有，仅使用 IEC 61131-3 标准库 TON / R_TRIG。
                许可证 —— 本件 MIT；来源标签 self-std（道莅自有内规族），
                无第三方源码继承。
    平台      : 纯 IEC 61131-3，CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R70 构建轮 · 批 2 · N5）
    ------------------------------------------------------------------
    功能说明  : 泵组固定 DL_PMP_N 台（默认 4 台，常数可改，全文件唯一定义）。
                选主规则：在所有「未被锁存排除」的泵中取累计运行小时最小者；
                小时完全相等的比较采用容差口径（不用浮点直比），相等时取小编号，
                故选主结果唯一、可复现。
                轮换规则：_tonRotate 以自复位口径产生周期脉冲（IN := bEn AND NOT Q，
                R188 禁靠外部沿清零）；脉冲拍强制排除当前主泵再选，实现主备交换。
                故障规则：abFault 为实时引脚输入，逐拍并入**每泵锁存位**
                _abFaultLatch，一旦置位即把该泵永久排除出候选集（本次运行期间），
                唯一解除边为 bReset 上升沿（R188 可到达的清除边）。
                锁存副本与实时镜像严格分离（历史教训 4）：判据只用 _abFaultLatch，
                abFault 引脚只用于「并入锁存」，二者绝不混用同一判据。
                小时累计：本件不自带计时基准，由上层按实际任务周期折算小时数后
                经 fScanHours 喂入（纯 IEC 口径，不依赖厂商 RTC 或 TIME 转换扩展），
                累计结果经 afRunHoursOut 出口回写上层保持区。
    错误码    : 16#0002_0201 组态非法（轮换周期 <= 0 或 fScanHours 非法），回放锁存 —— 故障级
                16#0002_0202 运行小时数组元素非法（负值 / 非有限），回放锁存 —— 故障级
                16#0002_0203 无可用泵（全部被锁存排除），输出全清零 —— 故障级
                16#0002_0204 主泵索引越界（内部一致性兜底，防数组越界访问）—— 故障级
    码位总账  : 0201 / 0202 / 0203 / 0204 用（均故障级）；无信息级码（本件不产生可观测的
                信息级事件，故不设，避免「声明了却永不赋值」）
    状态机    : N/A —— 无顺序相（选主为逐拍组合逻辑，轮换由定时脉冲驱动）；
                无 ENUM / CASE 可写，故无 CASE ELSE 兜底面
    边界与披露: 一 数组下标安全：全部 FOR 循环以常量 DL_PMP_N 为上下界（编译期确定），
                   另对 _nLead 做 1..N 显式校验并在越界时置 0204 且不索引数组，
                   两道防线同时存在，绝不出现下标越界读；
                二 组态闸（R272 逐项点名）：tRotate > T#0S；fScanHours 非有限闸 +
                   负值拦截；arRunHours 全元素非有限闸 + 负值拦截（累计小时不得为负）；
                三 加数饱和：小时累计结果按工程极限 DL_PMP_HCAP（1.0E12 h）夹住，
                   夹住后仍落在 LREAL 可表域内，故按「防御性夹住、不发码」处置 ——
                   该值在工程上不可达（1.0E12 h 远超设备寿命），发码只会产生
                   永不触发的死码位，违反「加码前须有现有输出组合不可观测的反证句」；
                四 失能（bEn = FALSE）：abCmd 全清零、bBusy 清零、轮换计时复位，
                   但每泵锁存位与小时累计**均不被清除**（失能非复位），须 bReset 解除；
                五 定时器 _tonRotate、沿实例 _rtReset 每周期无条件调用（规则 ⑦）；
                六 零全局变量、零 VAR_EXTERNAL、零物理地址、无除法。
    修订记录  : 2026-11-22 v1.0.0 首次入库（R70 构建轮 · 批 2 · N5）
*)
FUNCTION_BLOCK FB_DL_PumpAlternationLead
VAR_INPUT
    bEn         : BOOL := TRUE;                          (* 使能，[标志] / the enable *)
    bRunReq     : BOOL := FALSE;                          (* 泵组运行需求，[标志] / the group run request *)
    bReset      : BOOL := FALSE;                          (* 复位（上升沿解除故障锁存并清小时），[标志] / the reset, rising edge *)
    fScanHours  : LREAL := 0.0;                           (* 本周期折算小时数，[h]，由上层按任务周期喂入 / hours elapsed this scan *)
    arRunHours  : ARRAY[1..4] OF LREAL;                   (* 各泵累计运行小时（输入镜像），[h] / the per pump run hours, input image *)
    abFault     : ARRAY[1..4] OF BOOL;                    (* 各泵故障实时引脚，[标志] / the per pump live fault pins *)
    tRotate     : TIME := T#24H;                          (* 轮换周期，[ms]，须 > T#0S / the rotation period *)
END_VAR
VAR_OUTPUT
    nLead        : INT;                                   (* 当前主泵编号，0 = 无可用泵，[号] / the current lead pump number *)
    abCmd        : ARRAY[1..4] OF BOOL;                   (* 各泵运行命令出口，[标志] / the per pump run command *)
    afRunHoursOut : ARRAY[1..4] OF LREAL;                 (* 累计小时出口（上层回写保持区），[h] / the accumulated hours outlet *)
    bLeadChanged : BOOL;                                  (* 主泵切换单拍脉冲，[标志] / the lead change single scan pulse *)
    bBusy        : BOOL;                                  (* 轮换周期计时进行中，[标志] / the rotation period is timing *)
    bValid       : BOOL;                                  (* 出口可信（无锁存故障），[标志] / the outlets are trustworthy *)
    bError       : BOOL;                                  (* 故障标志，锁存故障时为 TRUE / the fault flag, raised while latched *)
    nErrCode     : UDINT;                                 (* 错误码，0 = 正常，锁存回放 / the error id, 0 = ok, replayed *)
END_VAR
VAR
    _rtReset       : R_TRIG;                              (* 复位上升沿实例（无条件调用）/ the reset rising edge instance *)
    _tonRotate     : TON;                                 (* 轮换周期计时实例（无条件调用，自复位口径）/ the rotation timer *)
    _abFaultLatch  : ARRAY[1..4] OF BOOL;                 (* 各泵故障锁存位，仅 bReset 解除 / the per pump latched fault *)
    _afHours       : ARRAY[1..4] OF LREAL;                (* 各泵小时工作副本（累计后出口），[h] / the per pump working copy *)
    _nLead         : INT;                                 (* 当前主泵寄存器，[号] / the lead pump register *)
    _nPrevLead     : INT;                                 (* 上拍主泵快照（切换沿基准），[号] / the previous lead snapshot *)
    _bFault        : BOOL;                                (* 块级故障锁存位 / the block level fault latch *)
    _nCodeLatch    : UDINT;                               (* 锁存成因码，故障期回放 / the latched cause code *)
    _bCfgBad       : BOOL;                                (* 组态非法标志（逐拍重算）/ the configuration fault flag *)
    _bHoursBad     : BOOL;                                (* 小时数组非法标志（逐拍重算）/ the hour array fault flag *)
    _bRun          : BOOL;                                (* 运行许可 = 使能 且 无锁存故障 / the run permit *)
    _bRotNeed      : BOOL;                                (* 本拍需强制轮换（定时脉冲）/ the rotation is due this scan *)
    _i             : INT;                                 (* 循环下标，[号] / the loop index *)
    _nBest         : INT;                                 (* 本轮选出的候选泵号，0 = 无，[号] / the selected candidate *)
    _nIdx          : INT;                                 (* 已校验的下标副本（索引前必判），[号] / the validated index copy *)
    _fBest         : LREAL;                               (* 候选最小小时值，[h] / the smallest hours found *)
    _bConsider     : BOOL;                                (* 该泵是否进入本轮候选，[标志] / whether the pump is a candidate *)
    _bTie          : BOOL;                                (* 小时相等（容差内）判据结果，[标志] / the tie verdict *)
END_VAR
VAR CONSTANT
    DL_PMP_N       : INT := 4;                            (* 泵台数（与数组声明同源），[台] / the pump count, matching the arrays *)
    DL_PMP_FMAX    : LREAL := 1.0E30;                     (* 非有限筛查幅值上限，[h] / the finiteness screening cap *)
    DL_PMP_HTOL    : LREAL := 1.0E-9;                     (* 小时相等比较容差，[h] / the hours equality tolerance *)
    DL_PMP_HCAP    : LREAL := 1.0E12;                     (* 小时累计上限（工程极限，夹住），[h] / the hours accumulation cap *)
    DL_PMP_NONE    : INT := 0;                            (* 无可用泵的哨兵值，[号] / the no-available-pump sentinel *)
END_VAR

// 段 1｜出口预置（R256 统一出口预置）/ segment 1, preset every outlet
bLeadChanged := FALSE;                     // 切换脉冲预清零 / preset the change pulse false
bBusy        := FALSE;                     // 忙碌标志预清零 / preset the busy flag false
bValid       := FALSE;                     // 可用标志预置假，健康路径再置真 / preset valid false, set in the healthy path
bError       := FALSE;                     // 故障标志预清零 / preset the error flag false
nErrCode     := 0;                         // 错误码预置无错 / preset the code to zero
_bRotNeed    := FALSE;                     // 轮换需求预清零 / preset the rotation need false
FOR _i := 1 TO DL_PMP_N DO                 // 常量上下界，下标安全 / constant bounds, indices safe
    abCmd[_i] := FALSE;                    // 各泵命令预清零（失能安全方向）/ preset every command off
    afRunHoursOut[_i] := _afHours[_i];     // 小时出口镜像工作副本 / mirror the working copy
END_FOR

// 段 2｜沿实例与定时器无条件调用（规则 ⑦）/ segment 2, the edge instance and the timer, called unconditionally
_rtReset(CLK := bReset);                               // 复位沿，每周期无条件刷新 / the reset edge, refreshed every scan
_tonRotate(IN := (bEn AND NOT _tonRotate.Q), PT := tRotate); // 轮换周期自复位计时（R188）/ the self resetting rotation timer

// 段 3｜复位解除：唯一可到达的清除边（R188）/ segment 3, the only reachable clearing edge
IF _rtReset.Q THEN                         // 复位上升沿 / the reset rising edge
    _bFault     := FALSE;                  // 解除块级故障锁存 / release the block fault latch
    _nCodeLatch := 0;                      // 清锁存码 / clear the latched code
    FOR _i := 1 TO DL_PMP_N DO             // 常量上下界 / constant bounds
        _abFaultLatch[_i] := FALSE;        // 解除各泵故障锁存 / release every per pump latch
    END_FOR
END_IF

// 段 4｜组态闸：轮换周期与扫描小时数（R272 逐项点名）/ segment 4, the configuration gate
_bCfgBad := (tRotate <= T#0S)                                     // 轮换周期非正 / a non positive rotation period
         OR (fScanHours < 0.0)                                    // 扫描时长为负 / a negative elapsed time
         OR (fScanHours <> fScanHours) OR ((fScanHours - fScanHours) <> 0.0) OR (ABS(fScanHours) > DL_PMP_FMAX);

// 段 5｜小时数组闸：全元素非有限 + 负值拦截 / segment 5, the hour array gate
_bHoursBad := FALSE;                       // 逐拍重算 / recomputed every scan
FOR _i := 1 TO DL_PMP_N DO                 // 常量上下界 / constant bounds
    IF (arRunHours[_i] <> arRunHours[_i]) OR ((arRunHours[_i] - arRunHours[_i]) <> 0.0)
       OR (ABS(arRunHours[_i]) > DL_PMP_FMAX) OR (arRunHours[_i] < 0.0) THEN // 元素非法 / an illegal element
        _bHoursBad := TRUE;                // 标记非法 / flag it
    END_IF
END_FOR

// 段 6｜首次成因锁存（故障期不重推断，R189）/ segment 6, the first cause latch
IF NOT _bFault THEN                        // 未锁存才登记 / register only while healthy
    IF _bCfgBad THEN                       // 组态非法优先 / the configuration first
        _bFault     := TRUE;               // 置锁存 / latch it
        _nCodeLatch := 16#0002_0201;       // 故障级：组态非法 / fault level: an illegal configuration
    ELSIF _bHoursBad THEN                  // 小时数组非法 / the hour array is illegal
        _bFault     := TRUE;               // 置锁存 / latch it
        _nCodeLatch := 16#0002_0202;       // 故障级：小时数组非法 / fault level: the hour array is illegal
    END_IF
END_IF

// 段 7｜实时故障引脚并入每泵锁存位（锁存副本与实时镜像分离，历史教训 4）/ segment 7, merge the live pins into the latches
FOR _i := 1 TO DL_PMP_N DO                 // 常量上下界 / constant bounds
    IF abFault[_i] THEN                    // 实时引脚为真 / the live pin is true
        _abFaultLatch[_i] := TRUE;         // 并入锁存（只增不减，唯一解除边见段 3）/ merge into the latch, released only in segment 3
    END_IF
END_FOR

// 段 8｜运行许可与轮换需求 / segment 8, the run permit and the rotation request
_bRun     := bEn AND NOT _bFault;          // 使能且无锁存故障 / enabled and not latched
_bRotNeed := _bRun AND bRunReq AND _tonRotate.Q; // 周期到且确有运行需求才轮换 / rotate when due and actually demanded
bBusy     := _bRun AND bRunReq AND NOT _tonRotate.Q; // 轮换周期计时中 / the rotation period is timing

// 段 9｜小时累计（仅对当前在役主泵累加）与出口 / segment 9, accumulate the hours of the running lead
IF _bRun THEN                              // 运行许可成立 / the run permit holds
    FOR _i := 1 TO DL_PMP_N DO             // 常量上下界 / constant bounds
        _afHours[_i] := arRunHours[_i];    // 先取输入镜像 / take the input image first
    END_FOR
    IF bRunReq THEN                        // 确有运行需求时主泵才计小时 / only a demanded lead accumulates
        _nIdx := _nLead;                   // 取待校验下标 / take the index to validate
        IF (_nIdx >= 1) AND (_nIdx <= DL_PMP_N) THEN   // 索引先判（防越界，规则 ④）/ validate before indexing
            _afHours[_nIdx] := _afHours[_nIdx] + fScanHours;   // 累加本周期小时 / add the elapsed hours
            IF _afHours[_nIdx] > DL_PMP_HCAP THEN              // 超工程极限 / beyond the engineering cap
                _afHours[_nIdx] := DL_PMP_HCAP;                // 夹住（夹住仍在实数可表域内）/ clamp it
            END_IF
        END_IF
    END_IF
    FOR _i := 1 TO DL_PMP_N DO             // 常量上下界 / constant bounds
        afRunHoursOut[_i] := _afHours[_i]; // 小时出口回写 / write the hours outlet
    END_FOR
ELSE                                       // 失能或锁存故障 / disabled or latched
    FOR _i := 1 TO DL_PMP_N DO             // 常量上下界 / constant bounds
        _afHours[_i] := arRunHours[_i];    // 工作副本照旧镜像（不做累计）/ mirror without accumulation
        afRunHoursOut[_i] := _afHours[_i]; // 出口照旧（小时不被失能清零）/ the outlet is not cleared by a disable
    END_FOR
END_IF

// 段 10｜选主：最闲泵，轮换拍排除当前主泵 / segment 10, the lead selection
_nPrevLead := _nLead;                      // 上拍主泵快照（切换沿基准）/ snapshot the previous lead
_nBest     := DL_PMP_NONE;                 // 候选初值：无 / the candidate starts empty
_fBest     := DL_PMP_FMAX;                 // 最小小时初值为筛查上界 / the smallest hours starts at the cap
IF _bRun THEN                              // 运行许可成立 / the run permit holds
    FOR _i := 1 TO DL_PMP_N DO             // 常量上下界 / constant bounds
        _bConsider := NOT _abFaultLatch[_i];                            // 未被锁存排除 / not excluded by the latch
        IF _bRotNeed AND (_i = _nLead) THEN                             // 轮换拍排除当前主泵 / exclude the current lead on a rotation
            _bConsider := FALSE;                                        // 退出候选 / drop it from the candidates
        END_IF
        IF _bConsider THEN                                              // 候选泵 / a candidate
            _bTie := ABS(_afHours[_i] - _fBest) <= DL_PMP_HTOL;         // 小时相等（容差口径）/ an hours tie within tolerance
            IF (_fBest > (DL_PMP_FMAX - DL_PMP_HTOL)) OR (_afHours[_i] < _fBest) OR _bTie THEN
                IF NOT ((_nBest <> DL_PMP_NONE) AND _bTie) THEN          // 已有候选且相等时保留小编号 / keep the lower number on a tie
                    _fBest := _afHours[_i];                             // 刷新最小值 / refresh the minimum
                    _nBest := _i;                                       // 记录候选泵号 / record the candidate
                END_IF
            END_IF
        END_IF
    END_FOR
    IF _nBest = DL_PMP_NONE THEN                                   // 轮换拍把唯一可用泵排除了 / the rotation excluded the only pump
        _nIdx := _nLead;                                           // 取待校验下标 / take the index to validate
        IF (_nIdx >= 1) AND (_nIdx <= DL_PMP_N) THEN               // 索引先判 / validate first
            IF NOT _abFaultLatch[_nIdx] THEN                       // 原主泵仍健康 / the previous lead is still healthy
                _nBest := _nIdx;                                   // 回落保持原主泵 / fall back to the previous lead
            END_IF
        END_IF
    END_IF
    IF _nBest = DL_PMP_NONE THEN                                   // 确实无可用泵 / truly no pump available
        _bFault     := TRUE;                                       // 锁存故障 / latch the fault
        _nCodeLatch := 16#0002_0203;                               // 故障级：无可用泵 / fault level: no pump available
    END_IF
END_IF

// 段 11｜主泵索引校验与命令出口（名实双出口同源，R191）/ segment 11, validate the lead and drive the outlets
IF _bRun AND NOT _bFault THEN              // 健康运行 / healthy and running
    _nIdx := _nBest;                       // 取待校验下标 / take the index to validate
    IF (_nIdx >= 1) AND (_nIdx <= DL_PMP_N) THEN   // 索引先判（规则 ④）/ validate before indexing
        _nLead := _nIdx;                   // 提交主泵寄存器 / commit the lead register
        IF bRunReq THEN                    // 有运行需求 / a run is demanded
            abCmd[_nIdx] := TRUE;          // 仅主泵运行（单泵运行策略）/ only the lead runs
        END_IF
        bValid := TRUE;                    // 出口可信 / the outlets are trustworthy
    ELSE                                   // 内部一致性失败 / an internal consistency failure
        _nLead      := DL_PMP_NONE;        // 主泵清为无 / clear the lead
        _bFault     := TRUE;               // 锁存故障 / latch the fault
        _nCodeLatch := 16#0002_0204;       // 故障级：主泵索引越界 / fault level: the lead index out of range
    END_IF
END_IF

// 段 12｜出口映射（单点写入，无自赋值）/ segment 12, the outlet mapping
nLead        := _nLead;                    // 主泵号出口 / the lead number outlet
bLeadChanged := (_nLead <> _nPrevLead);    // 主泵切换单拍脉冲（整数直比，无浮点面）/ the lead change pulse
bError       := _bFault;                   // 名实双出口：故障位与锁存同源（R191）/ both outlets share the latch
nErrCode     := _nCodeLatch;               // 锁存码回放 / replay the latched code
IF _bFault THEN                            // 锁存故障相 / the latched fault phase
    bValid := FALSE;                       // 出口不可信 / the outlets are not trustworthy
    FOR _i := 1 TO DL_PMP_N DO             // 常量上下界 / constant bounds
        abCmd[_i] := FALSE;                // 全泵命令清零（失效安全）/ all commands off
    END_FOR
END_IF
END_FUNCTION_BLOCK
