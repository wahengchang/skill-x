# CodeGraph 技能 — 下一步

記錄 `commands-src/codegraph` 技能的後續想法。全部尚未實作,留待第一個真實專案試用後再決定。

## 背景(已驗證)

- 工具:`@colbymchenry/codegraph` 1.5.0,npm 全域安裝。
- CLI pipeline 已在臨時 TS 專案跑通:`init → status → query → callers → callees → impact` 回傳正確。
- 支援 29 種語言(TS/JS、Python、Go、Rust、Java、C/C++、C#、Ruby、PHP、Swift、Kotlin、Scala、Dart、Lua、Solidity、Terraform、Nix…),不含 shell / Markdown / YAML。
- 本 repo 是 bash + markdown,index 不到東西;要驗效果需真實 TS/Go/Python 專案。

## 候選工作

1. **真實專案 smoke test** — 拿第一個 TS/Go/Python 專案跑 `impact` / `affected`,驗證 blast-radius 與 test-impact 的準確度。觸發點:下次動大型 refactor 前。
2. **CI/PR 只跑受影響測試** — `codegraph affected [files...]` 吃 changed files、回傳受影響 test files,可做 PR gate。最值得先接的點。
3. **git hook 自動同步 index** — `codegraph sync -q`(help 標明 "for git hooks")掛 post-merge / pre-commit,避免 index 過期(索引類工具最大失效模式)。
4. **core workflow 補「探索」分支** — `explore <query>`(相關符號 + call paths 一 shot)與 `node <name>`(單一符號 source + caller/callee trail)比 `query → impact` 更適合導航不熟程式碼。兩行即可補進 SKILL.md。
5. **MCP 路線(選用)** — `codegraph install` 可裝進 Claude Code / Cursor / Codex / opencode;哪天想讓 agent 在 session 內直接調 `codegraph_explore` / `codegraph_node` 再評估。純 CLI 目前夠用。

## 狀態

- [x] 技能建立、重寫為 CLI-only、build + sync、commit
- [ ] 上述 1–5 皆未開始
