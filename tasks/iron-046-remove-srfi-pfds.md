# iron-046 删除 srfi 与 pfds，迁移依赖方

- 里程碑：M9　依赖：iron-042 ~ iron-045　状态：未开始
- 设计依据：[08](../designs/08-std-library.md) §1 D5、§4

## 工作内容
1. 依赖方改用 std：wak、`lib/diff.sls`、`playground/`、示例、测试脚本与 C# 测试。
2. 删除 `src/scheme/lib/srfi`、`lib/pfds`；`system-libraries.ss` 改为 std 清单；测试类别 `SRFI` 改为 `Std`；更新 `THIRD-PARTY.md`、README、设计文档。

## 验收标准
- 仓库中不再有 `(srfi …)`、`(pfds …)` 的引用；全部测试通过；系统库编译与 ILVerify 通过。
