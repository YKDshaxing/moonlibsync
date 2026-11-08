# 公开字节 API 示例

从仓库根选择固定工具链后，分别运行 `moon run examples/basic --target native`、`--target js`、`--target wasm-gc`。本包只导入公开根库；无文件、环境、Python或rdiff导入。发送端函数只接收签名和新字节。

旧数据为值0x10..0x17的八个64字节块；新数据在256处插入00 80 ff。签名参数64/32。示例检查恢复相等及delta小于515字节，失败非零；正常输出实际大小及本次delta十六进制。`scripts/check_example.py --target TARGET` 调用同一个示例，用既有独立严格指令解析器检查实际delta的内容与COPY>=512，不要求delta永远18字节。

固定工具链 `moon info` 为本可执行包实际生成空公开声明 `pkg.generated.mbti`，该文件纳入提交与生成前后保护，不是新增公开库API。其余已有Native可执行包的接口行为按显式包范围同时检查。

CI证据在 `_build/examples/TARGET.log`、`TARGET.json` 与 `TARGET.delta`，记录源码HEAD/dirty、命令、退出码和实际计数。隔离失败门禁另有损坏/正常复验运行，不计入三次正常示例或99项库测试。
