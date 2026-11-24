# _TESTS — 边界测试向量契约

每个组件一个同名 JSON：`_TESTS/<ComponentName>.json`

```json
{"name":"FB_DL_X","cases":[
  {"in":{"fIn":0.0},"expect":{"bError":true,"eErr":"16#0001_0001"},"why":"除零"},
  {"in":{"fIn":1.5},"expect":{"fOut":1.5,"bValid":true},"why":"正常直通"}
]}
```

硬性要求：
1. 每个有状态 FB 至少 3 例：正常 / 组态非法 / 边界（除零、非有限、越界、复位）各一。
2. 纯函数 FC 至少 2 例：典型值 + 定义域外。
3. 断言只写可判定的输出字段，不写内部状态。
4. 向量由编译验证工程师维护，编码专家不得自写自判。
