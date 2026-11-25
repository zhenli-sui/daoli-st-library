// ST_DL_EtSlaveDiagBase v1.0.0
// 开源溯源：TcOpen / URL https://github.com/TcOpenGroup / 许可证 MIT / 借鉴 EtcSlaveBase 结构语义（从站诊断基），clean-room 重写
(*
  道莅工业代码库 | DL_Device | ST_DL_EtSlaveDiagBase
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  功能: EtherCAT 从站诊断基结构（AL 状态/在线/DC 同步/错误计数字段聚合），
        供各品牌从站诊断 FB 组合扩展
  邻件关系: 与 ProfinetAlarmDiag（PROFINET 告警诊断）协议域不同；本件为
            EtherCAT 域首件结构属主；同步单元级诊断见 ST_DL_EtSyncUnitDiagBase
            （设备级 vs 单元级聚合）
  命名声明: clean-room 重构，字段名全为自命名语义名，不含任何厂商库
            哈希后缀名（原队列条目 EtcSlaveBase_82538BE2 语义对标）
*)
TYPE ST_DL_EtSlaveDiagBase :
STRUCT
    uSlaveAddr      : UINT;      // 从站物理地址 [站号] / EtherCAT slave physical address
    bSlaveOnline    : BOOL;      // 从站在线标志 [-] / Slave online flag
    bSlavePresent   : BOOL;      // 从站配置存在（扫描表匹配）[-] / Slave present per scan list match
    nAlState        : USINT;     // AL 状态码 [码值，0=Init..8=Op] / AL state code, 0=Init..8=Op
    nAlErrCode      : UINT;      // AL 错误码 [AL status code] / AL error status code
    bDcSyncOk       : BOOL;      // 分布式时钟同步合格 [-] / Distributed clock sync ok
    nDcDiffUs       : DINT;      // DC 偏差 [微秒 us] / DC deviation [us]
    uWcStateCnt     : UDINT;     // 工作计数器读数 [计数] / Working counter reading
    uErrFrameCnt    : UDINT;     // 错误帧累计 [帧] / Error frame cumulative count
    uLostLinkCnt    : UDINT;     // 链路丢失累计 [次] / Lost link cumulative count
    bDiagStale      : BOOL;      // 诊断数据过期（看门狗超时）[-] / Diagnostic data stale flag
END_STRUCT
END_TYPE
