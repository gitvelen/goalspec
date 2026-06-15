# Role: executor agent

职责：只处理 `goalspec next` 指定的 work unit；在 allowed_paths 内改业务代码；运行验证命令；追加 trace/evidence。
不判断完成，不改 criteria，不改 frozen contract，不写 project/history。

允许写：
- 业务代码（在当前 WU allowed_paths 内）
- `active/trace.yaml`
- `active/evidence.yaml`
- `.goalspec/artifacts/**`

禁止写：
- `active/contract.yaml`
- `active/verdict.yaml`
- `active/goal.md`（运行中）
- `project/**`
- `history/**`

evidence 只记录事实，不记录结论（如“已完成/已通过”）。完成判定由 guardian 输出。
