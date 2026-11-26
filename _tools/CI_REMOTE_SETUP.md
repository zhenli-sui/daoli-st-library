# GitHub Remote / CI 配置记录（2026-11-24 晨，R78 后补）

- 远端：https://github.com/zhenli-sui/daoli-st-library（public，main）
- 令牌：`C:/Library/_tools/.gh_token`（classic，repo+workflow；勿提交、勿外传）
- 首次全量推送：Git Data API 方式（`_tools/gh_api_push.py`，1,891 文件 / 54.4MB，commit c7087cd）
  - **为什么不用 git push**：本机代理（127.0.0.1:53288）对 `github.com:443` CONNECT 不通（502/断连），但 `api.github.com` 稳定 → 一切推送走 API。
  - blob 缓存：`_Staging_Raw/gh_blob_cache.json`（断点续传）。
- CI：`.github/workflows/iec-compile.yml`（iec-compile-gate）
  - L1 dl_gate 全库扫描 ✔（修复了 dl_gate/matic_manifest/matic_runner 三个脚本的 `C:/Library` 硬编码，改为脚本父目录解析）
  - L2 iec2iec 全库解析 ✔ 端到端执行（stdlib 需 `cp -r /tmp/matiec/lib ./lib`）
  - **当前基线（run 45294324945）**：L1 1,425/1,490 PASS（MAJOR 19 / BLOCK 46，存量挂产线清理）；L2 0/1,490 PASS——MatIEC 老方言与库内语法系统性差异（ENUM 规范/声明闭合等），待 dialect 适配专项。
- 后续每轮 push：用 `gh_push_matic_fix.py` 的同款 API 三步法（blob→tree(base_tree)→commit→ref）。
