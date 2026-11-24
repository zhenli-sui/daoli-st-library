(*
  ==================================================================
  组件名 Component  : FB_DL_FirstArticleLock
  分类   Category   : DL_Process
  复杂度 Complexity  : cx5
  版本   Version    : 1.0.0
  功能   Purpose    : 首件检验锁定。首件未放行禁止批量运行（许可出口挂锁定
                      状态量）；换型信号沿自动重锁；首件检验合格沿解锁放行
                      并出单拍放行脉冲与台账；锁定期的运行请求出单拍拒绝
                      指示。汽车 / 电子行业公开首件流程语义。
  来源   Source     : self（行业公开流程）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；首件检验锁定为
                      公开行业流程语义，clean-room 自研实现，未复制任何厂商
                      私有库源码。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: R_TRIG，无私有库）
  分工声明 Split     : 与 FB_DL_MaterialHoldTimeEnforce 分工——保持时限件做
                      在制批次时限门控，本件做换型后批量运行前置门控；与
                      存量批次追溯件分工——本件不含履历数据，只有锁存与台账。
  作者   Author     : 道莅代码库 · PLC 编程专家（R58）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 上电默认锁定（_bInit 首扫置锁）：首件未放行禁止批
                         量运行，安全侧缺省；
                      二 锁定解除路径 = bFaPass 上升沿（唯一解锁路径，R188
                         头注释声明）；重锁路径 = bChangeover 上升沿（换型
                         自动重锁）；
                      三 许可出口挂状态量 _bLocked（R99：禁挂单拍标志）；
                      四 单拍标志 bFaRelease / bRunBlocked 每拍预清零（R25，
                         置位点在段 3，统一出口单拍映射两段式 R189）；
                      五 复位沿作用域：清台账 / 恢复默认锁定（两项逐项声明）；
                      六 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R58 首版（批 4 · 序号 16）
  ==================================================================
*)

FUNCTION_BLOCK FB_DL_FirstArticleLock
VAR_INPUT
    bEnable     : BOOL := TRUE;   // 使能，失能许可出口安全侧 FALSE [-] / enable, disabling clears the permit
    bReset      : BOOL := FALSE;  // 复位上升沿清台账并恢复默认锁定 [-] / reset rising edge clears the ledger and restores the default lock
    bChangeover : BOOL := FALSE;  // 换型信号（沿生效，自动重锁）[-] / the changeover signal, edge effective, auto relock
    bFaPass     : BOOL := FALSE;  // 首件检验合格（沿生效）[-] / the first article pass, edge effective
    bRunReq     : BOOL := FALSE;  // 批量运行请求电平 [-] / the batch run request level
END_VAR
VAR_OUTPUT
    bBatchPermit: BOOL := FALSE; // 批量运行许可出口（挂锁定状态量）[-] / the batch run permit outlet, gated by the lock state
    bLocked     : BOOL := FALSE; // 锁定中指示出口 [-] / the locked indicator outlet
    bFaRelease  : BOOL := FALSE; // 首件放行单拍出口 [-] / the first article release pulse outlet
    bRunBlocked : BOOL := FALSE; // 锁定期运行请求拒绝单拍出口 [-] / the run request blocked pulse outlet
    nLockCnt    : UDINT := 0;    // 累计重锁次数 [次] / the total relock count
    nRelCnt     : UDINT := 0;    // 累计放行次数 [次] / the total release count
END_VAR
VAR
    rtChg   : R_TRIG; // 换型沿检测，段 0 无条件刷新 / the changeover edge
    rtPass  : R_TRIG; // 首件合格沿检测，段 0 无条件刷新 / the pass edge
    rtReset : R_TRIG; // 复位沿检测，段 0 无条件刷新 / the reset edge
    _bLocked: BOOL := TRUE;  // 锁定状态量（上电缺省锁定，边界一）/ the lock state, the power up default locked
    _bRel   : BOOL := FALSE; // 放行脉冲内部保持量（统一出口映射单拍）/ the release pulse internal holder
    _bBlk   : BOOL := FALSE; // 拒绝脉冲内部保持量 / the blocked pulse internal holder
    _bInit  : BOOL := FALSE; // 首扫初始化完成标志（R310）/ the first scan flag
END_VAR
VAR CONSTANT
    DL_FAL_CNTMAX : UDINT := 4294967294; // 台账计数钳定界 [次]，防 UDINT 回绕 / the ledger clamp against a wrap
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支，FB50-1）/ segment 0, the unconditional refresh
rtChg(CLK := bChangeover); // 换型沿 / the changeover edge
rtPass(CLK := bFaPass); // 合格沿 / the pass edge
rtReset(CLK := bReset); // 复位沿 / the reset edge

// 段 1｜首扫初始化（R310）：上电默认锁定（边界一）/ segment 1, the first scan, the default locked
IF NOT _bInit THEN // 首扫一拍 / the first scan
    _bInit := TRUE; // 置首扫标志 / raise the flag
    _bLocked := TRUE; // 上电默认锁定 / the default locked
END_IF

// 段 2｜复位沿作用域：清台账 / 恢复默认锁定（两项逐项声明，边界五）/ segment 2, the reset edge scope
IF rtReset.Q THEN // 复位沿 / the reset edge
    nLockCnt := 0; // 作用域一：清重锁台账 / scope one, clear the relock ledger
    nRelCnt := 0; // 作用域一：清放行台账 / scope one, clear the release ledger
    _bLocked := TRUE; // 作用域二：恢复默认锁定（安全侧）/ scope two, restore the default lock
END_IF

// 段 3｜重锁与解锁沿判定 + 单拍保持量置位（边界二三四）/ segment 3, the relock and the unlock edges
IF rtChg.Q THEN // 换型沿自动重锁 / the changeover edge relocks
    _bLocked := TRUE; // 置锁定 / raise the lock
    IF nLockCnt < DL_FAL_CNTMAX THEN // 台账防回绕 / the ledger wrap guard
        nLockCnt := nLockCnt + 1; // 重锁台账推进 / advance the relock ledger
    END_IF
END_IF
IF _bLocked AND rtPass.Q THEN // 锁定中且首件合格沿（唯一解锁路径，R188）/ locked with the pass edge
    _bLocked := FALSE; // 解锁 / release the lock
    IF nRelCnt < DL_FAL_CNTMAX THEN // 台账防回绕 / the ledger wrap guard
        nRelCnt := nRelCnt + 1; // 放行台账推进 / advance the release ledger
    END_IF
    _bRel := TRUE; // 置放行内部保持量 / raise the release holder
END_IF
IF _bLocked AND bRunReq THEN // 锁定期收到运行请求 / a run request while locked
    _bBlk := TRUE; // 置拒绝内部保持量 / raise the blocked holder
END_IF
bFaRelease := FALSE; // 放行单拍每拍预清零（R25）/ the release pulse preset false each scan
bRunBlocked := FALSE; // 拒绝单拍每拍预清零（R25）/ the blocked pulse preset false each scan

// 段 4｜统一出口（边界三四：状态量门控 + 单拍两段式映射）/ segment 4, the unified outlet
bBatchPermit := (NOT _bLocked) AND bEnable; // 许可挂锁定状态量（R99）/ the permit gated by the lock state
bLocked := _bLocked; // 锁定指示同源 / the indicator shares the state
IF _bRel THEN // 放行保持量 → 统一出口单拍映射（两段式，R189）/ the holder mapped to the pulse
    bFaRelease := TRUE; // 放行单拍 / the release pulse
    _bRel := FALSE; // 消费保持量 / consume the holder
END_IF
IF _bBlk THEN // 拒绝保持量 → 统一出口单拍映射 / the holder mapped to the pulse
    bRunBlocked := TRUE; // 拒绝单拍 / the blocked pulse
    _bBlk := FALSE; // 消费保持量 / consume the holder
END_IF
END_FUNCTION_BLOCK
