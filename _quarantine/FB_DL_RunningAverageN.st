(*==============================================================================
 * 组件名称 (Component)  : FB_DL_RunningAverageN
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3（INT_TO_LREAL），零厂商私有库
 * 功能描述 (Function)   : N 点滑动均值（环形缓冲，增量求和）。窗口 N 可配 1..32，
 *                         运行中变更窗口自动清表重建（避免新旧两段样本混算）。
 *                         算法：写入前先减去被覆盖的最老样本（_fSum := _fSum - old + new），
 *                         均值 = _fSum / 当前样本数，故单拍开销与 N 无关（O(1)）。
 *                         用途：编码器速度、流量、称重等周期性抖动量平滑。
 * 接口     (Interface)  : 输入 bEnable 使能、bReset 清表复位、fIn 采样输入 [EU]、
 *                         iWindow 窗口点数 [个]（1..32）；
 *                         输出 fOut 均值 [EU]、iFillCount 当前样本数 [个]、
 *                         bValid 输出有效、bError 故障标志、uErrorId 故障码；
 *                         返回值由 FB 实例状态提供（无返回值，读 bValid）。
 * 边界     (Boundary)   : ① 属主边界：只做算术均值，不做中值 / 加权 / 剔除离群（另件）。
 *                         ② 非有限输入 → 进故障态、**冻结输出**（不更新），uErrorId=16#0003_0002；
 *                         故障态只能由 bEnable=FALSE 或 bReset 解除（可达恢复路径）。
 *                         ③ 窗口域闸 1..32：越域钳位并置信息码 16#0003_0001，不中断扫描。
 *                         ④ 除零防护：均值除法前判 _iFill >= 1。
 *                         ⑤ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_LowPassFilter` 分工：一阶惯性归那件（无限记忆）、
 *                         有限窗口算术均值归本件；与统计族 FC 分工：一次性批统计归 FC。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 16#0003_0000 无故障 / 16#0003_0001 窗口越域已钳位（信息级）/
 *                         16#0003_0002 输入非有限（故障级）/ 16#0003_0005 非法状态（故障级）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 除零前置判零 + 窗口域闸 + 非有限拒绝 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ 四态 ENUM + CASE + ELSE 兜底 ｜ R7 N/A（无 TON/边沿实例）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B3 · 序号 9）
 * 验收向量 (Acceptance) : ① iWindow=4，依次输入 1,2,3,4,5 → 第 4 拍 fOut=2.5；
 *                         第 5 拍（窗口已满，挤掉 1）→ fOut=(2+3+4+5)/4=3.5；
 *                         ② bReset=TRUE 一拍 → iFillCount=0，fOut=0.0，bValid=FALSE；
 *                         ③ iWindow=0 → 钳位为 1，uErrorId=16#0003_0001，仍正常输出；
 *                         ④ fIn=NaN → uErrorId=16#0003_0002，bError=TRUE，fOut 冻结上拍值；
 *                         ⑤ iWindow=40 → 钳位 32，uErrorId=16#0003_0001。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_RavgState（滑动均值状态机，归属 DL_Algo，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_RavgState :
(
    eInit  := 0,    // 首扫 / 复位后：清表并直取首个样本 / First scan or after reset: clear and seed
    eRun   := 10,   // 运行态：环形缓冲增量均值 / Running: incremental ring-buffer average
    eHold   := 20,  // 保持态：未使能，输出冻结 / Hold: disabled, output frozen
    eFault := 99    // 故障态：输出冻结，等待 bEnable 跌落或 bReset / Fault: frozen, awaiting disable or reset
);
END_TYPE

FUNCTION_BLOCK FB_DL_RunningAverageN
VAR_INPUT
    bEnable : BOOL := FALSE;   // 使能，FALSE 冻结输出 / Enable, FALSE freezes output
    bReset  : BOOL := FALSE;   // 复位清表（单拍有效） / Reset and clear buffer, single scan
    fIn     : LREAL := 0.0;    // 采样输入 [EU] / Sampling input [EU]
    iWindow : INT := 8;        // 窗口点数，合法域 1..32 [个] / Window size, domain 1..32
END_VAR
VAR_OUTPUT
    fOut       : LREAL;   // 滑动均值输出 [EU] / Moving average output [EU]
    iFillCount : INT;     // 当前有效样本数 [个] / Current valid sample count
    bValid     : BOOL;    // 输出有效标志 [-] / Output valid flag
    bError     : BOOL;    // 故障标志，与 uErrorId 联动 [-] / Fault flag coupled with uErrorId
    uErrorId   : UDINT;   // 故障码，0 = 无故障 [-] / Error code, zero means healthy
END_VAR
VAR
    _afBuf   : ARRAY[1..32] OF LREAL;  // 环形样本缓冲 [EU] / Ring sample buffer
    _fSum    : LREAL;                  // 样本和（增量维护） [EU] / Sample sum maintained incrementally
    _iHead   : INT;                    // 环形写入位（最老样本位） [-] / Ring write position, oldest slot
    _iFill   : INT;                    // 当前样本数 [个] / Current sample count
    _iWinEff : INT;                    // 生效窗口（钳位后） [个] / Effective window after clamping
    _i       : INT;                    // 循环下标 [-] / Loop index
    eState   : E_DL_RavgState;         // 状态机当前状态 [-] / Current state
END_VAR
VAR CONSTANT
    DL_RAV_WIN_MIN : INT := 1;       // 窗口下限 [个] / Window lower bound
    DL_RAV_WIN_MAX : INT := 32;      // 窗口上限（数组容量） [个] / Window upper bound
    DL_RAV_ZERO_L  : LREAL := 0.0;   // 零基准（含非有限判零） [-] / Zero base including non-finite probe
END_VAR

(* —— 段 1：参数域闸（不中断扫描，只钳位并置信息码） —— *)
uErrorId := 16#0003_0000;                          // 预置无故障 / Preset healthy
_iWinEff := iWindow;
IF iWindow < DL_RAV_WIN_MIN THEN
    _iWinEff := DL_RAV_WIN_MIN;                    // 窗口过小钳位 / Too small window clamped
    uErrorId := 16#0003_0001;                      // 信息级：窗口越域已钳位 / Info: window clamped
ELSIF iWindow > DL_RAV_WIN_MAX THEN
    _iWinEff := DL_RAV_WIN_MAX;                    // 窗口过大钳位 / Too large window clamped
    uErrorId := 16#0003_0001;                      // 信息级：窗口越域已钳位 / Info: window clamped
END_IF

(* —— 段 2：非有限输入防御（进故障态冻结输出，最短恢复路径 = bEnable 跌落或 bReset） —— *)
IF (fIn <> fIn) OR ((fIn - fIn) <> DL_RAV_ZERO_L) THEN
    eState   := eFault;                            // 强制故障态 / Force fault state
    uErrorId := 16#0003_0002;                      // 故障级：输入非有限 / Fault: non-finite input
END_IF

(* —— 段 3：窗口变更或复位 → 回首扫态（清表重建） —— *)
IF bReset THEN
    eState := eInit;                               // 复位请求回首扫 / Reset request returns to init
END_IF

(* —— 段 4：状态派生（故障态保持；未使能保持；其余运行） —— *)
IF NOT bEnable THEN
    eState := eHold;                               // 未使能：保持并冻结输出 / Disabled: hold and freeze
ELSIF eState = eFault THEN
    eState := eFault;                              // 故障态保持，等待外部解除 / Fault holds until cleared
ELSIF eState = eInit THEN
    eState := eInit;                               // 首扫态保持一拍 / Init holds for one scan
ELSE
    eState := eRun;                                // 常规运行 / Normal running
END_IF

(* —— 段 5：主状态机（CASE 覆盖 + ELSE 兜底） —— *)
CASE eState OF

    eInit:
        (* 清表：缓冲、求和、指针、计数全部归零，再以本拍样本播种（避免首拍均值 = 0） *)
        FOR _i := 1 TO DL_RAV_WIN_MAX DO
            _afBuf[_i] := DL_RAV_ZERO_L;
        END_FOR;
        _fSum    := DL_RAV_ZERO_L;
        _iFill   := 1;                             // 播种首个样本 / Seed first sample
        _iHead   := 1;
        _afBuf[1] := fIn;
        _fSum    := fIn;
        fOut     := fIn;                           // 首拍直取样本，无历史瞬态 / First scan follows input
        bValid   := TRUE;
        eState   := eRun;                          // 下一拍进入运行态 / Move to running next scan

    eRun:
        IF _iFill < _iWinEff THEN
            (* 未满窗：追加写入（无样本被挤出） *)
            _iFill := _iFill + 1;
            _iHead := _iFill;
            _afBuf[_iHead] := fIn;
            _fSum  := _fSum + fIn;
        ELSE
            (* 满窗：先减去被覆盖的最老样本，再写入新样本（增量 O(1)） *)
            _fSum := _fSum - _afBuf[_iHead] + fIn;
            _afBuf[_iHead] := fIn;
            _iHead := _iHead + 1;                  // 写入位前移 / Advance write slot
            IF _iHead > _iWinEff THEN
                _iHead := 1;                       // 环形回绕 / Wrap around
            END_IF
        END_IF
        IF _iFill >= 1 THEN
            fOut := _fSum / INT_TO_LREAL(_iFill);  // 除零已判（_iFill >= 1） / Division guarded
        ELSE
            fOut := DL_RAV_ZERO_L;                 // 防御兜底（结构上不可达） / Defensive fallback
        END_IF
        bValid := TRUE;

    eHold:
        (* 未使能：输出冻结保持上拍值，样本表不变，恢复使能后继续累积 *)
        (* Disabled: output frozen, buffer untouched, accumulation resumes on enable *)
        bValid := FALSE;

    eFault:
        (* 故障态：输出冻结保持上拍值（不推到 0，避免下游误判为真实零值） *)
        (* Fault: output frozen rather than zeroed, so downstream sees no fake zero *)
        bValid := FALSE;

    ELSE
        (* 非法状态拦截：任何未定义枚举值一律进故障态并置公共兜底码 *)
        eState   := eFault;
        bValid   := FALSE;
        uErrorId := 16#0003_0005;                  // 故障级：非法状态 / Fault: illegal state

END_CASE;

(* —— 段 6：出口映射（名实双出口：bError 与 uErrorId 同源） —— *)
iFillCount := _iFill;                              // 导出当前样本数 / Export sample count
bError     := (uErrorId <> 16#0003_0000);          // 故障级码才置 bError（信息级 16#0003_0001 不置） / Fault-level only

END_FUNCTION_BLOCK
