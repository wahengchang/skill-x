# skill-x-starter

把同一組個人 `SKILL.md` 技能部署到 Claude Code、Codex CLI 與 OpenCode。內容以 private Git repository 為唯一來源；個人電腦使用 symlink 與可選更新，容器 image 則安裝固定版本的副本。

## 安裝

```bash
git clone <private-repo-url> ~/.skill-x-starter
cd ~/.skill-x-starter
./install.sh
```

安裝程式會建立部署版本並同步到：

- `~/.claude/skills/`
- `~/.codex/skills/`
- `~/.agents/skills/`（Codex 防禦性相容路徑）
- `~/.config/opencode/skills/`
- `~/.config/opencode/commands/`（僅 OpenCode v1，見下節）

以 `bin/doctor.sh` 檢視同步狀態。Windows 若未開啟 symlink 權限，目前不支援自動退回複製模式。

## 各工具的明確叫用方式

同一顆技能在三個工具的顯式叫用語法不同：

| 工具 | 叫用方式 | 來源 |
| --- | --- | --- |
| Claude Code | `/<skill>` | `~/.claude/skills/<skill>/SKILL.md` 自動成為 slash command，不需額外檔案 |
| Codex | `$<skill>`，或用 `/skills` 選單 | `~/.codex/skills/<skill>/SKILL.md`；已棄用的 custom prompts（`/prompts:<name>`）預設不安裝 |
| OpenCode v1 | `/<skill>` | 由 `bin/build.sh` 產生、再 symlink 到 `~/.config/opencode/commands/<skill>.md` 的 command shim |
| OpenCode v2 | `/<skill>` | 原生 skill slash 目錄；不安裝 shim，避免重複項目 |

OpenCode v1 的 shim 是薄薄一層：它只叫 OpenCode 用 `skill` 工具載入 canonical skill 並轉送 `$ARGUMENTS`，不複製技能內容。技能內容的唯一來源仍是 `commands-src/<name>/SKILL.md`。

版本偵測預設執行 `opencode --version`。偵測不到（例如 OpenCode 尚未安裝或不在 `PATH`）時視為 v1 並提示，可用環境變數強制指定：

| 變數 | 預設值 | 用途 |
| --- | --- | --- |
| `SKILL_X_OPENCODE_VERSION` | `auto` | `auto`／`v1`（安裝 shim）／`v2`（改用原生 slash，並移除既有 shim） |

撞名行為與技能同步一致：既有的非 symlink 檔案只警告不覆蓋，受管理的 symlink 可重複執行且冪等，技能刪除後對應的 shim 會被移除。從 v1 切換到 v2 時，`bin/sync-skills.sh` 會清掉自己產生的 shim，使用者自己寫的 command 檔案不受影響。

## 維護技能

在 Codex 開發環境新增技能時，建議把貼上的草稿或一句需求交給 repository-local 的 `.codex/skills/canonicalize-skill`。它會釐清觸發條件與範圍、建立格式正確的 `commands-src/<name>/SKILL.md`、在撞名時先詢問，並在完成後詢問是否立即執行 build。例如：

```text
請使用 canonicalize-skill：當我要求整理每週工作紀錄時，產生一份依專案分組的週報。
```

canonical skill 的唯一來源仍是 `commands-src/<name>/`；不要直接編輯產生的 `commands/`、`opencode-commands/`，也不要把這些 disposable artifact commit 進 repository（它們在 `.gitignore`）。建立或修改完成後執行 `bin/build.sh`，只需要 commit source 與 build 設定。若要手動撰寫或查看完整命名規則，請參考 [CONTRIBUTING.md](./CONTRIBUTING.md)。

`canonicalize-skill` 是建置階段的 authoring tool，不是此 framework 的輸出；它不會進入 `commands/`，也不會由 `bin/sync-skills.sh` 分發到各 AI agents。framework 的輸入是 `commands-src/` 中完成 canonicalize 的 skill set，輸出才是跨 agents 使用的 generated skill set。

支援檔案（例如 `scripts/`、`references/`）會一併複製。修改 `_shared/update-check-header.md` 後也必須重跑 `bin/build.sh`。

## `x-*` 開發週期技能組

`x-` 前綴的六顆技能是一整套開發流程：把一次盤點變成 Cycle、把工作準備到可直接開工、由獨立 Agent 審查、以證據除錯、交付成一個 PR，最後把完成的 Cycle 壓成一份短 log。

| 技能 | 回答的問題 | 主要輸出 |
| --- | --- | --- |
| `x-discovery` | 這個範圍內有哪些工作？ | `.dev-hub/active/cycle-*/hub.md` 與 `WK-XXX` 工作總表 |
| `x-plan-eng` | 每項工作要做什麼、工程上怎麼做？ | `IS-*` / `SP-*` / `WG-*`、Owner、branch 與 worktree |
| `x-review` | 這份最終內容有什麼真實風險？ | `RV-*`（含 severity、`file:line`、失效情境） |
| `x-debug` | 已知問題的 root cause 是什麼？ | `DBG-*`、根因修正與 regression test |
| `x-ship` | 能否安全交付，並形成一個 PR？ | commits、pushed branch、create-or-update 的單一 PR |
| `x-housekeeping` | 哪些執行殘留已可安全刪除？ | 清理結果與 `.dev-hub/logs/cycle-*.md` |

六顆技能都能只憑「專案背景、repo 文件、程式碼、Prompt」獨立啟動，不需要先有 Cycle。使用者輸入 `continue` 時，接續依據是 artifact 裡的 Handover 區塊，沒有隱藏的全域狀態機。

執行期狀態一律留在 repo 內的 `.dev-hub/`，不寫 `~/.x-*` 或系統 `/tmp`：

```text
.dev-hub/
├── active/      進行中的 Cycle（ignored）
├── worktrees/   WG 的 linked worktrees（ignored）
├── runtime/     standalone 執行的暫存（ignored）
│   └── standalone/  沒有 Cycle 時的規劃文件；路徑固定，才能重用與上鎖
└── logs/        完成 Cycle 的短紀錄（tracked，唯一會進 Git 的部分）
```

重複、可驗證的操作由技能資料夾內的 `scripts/xdh` 負責：從任一 worktree 解析共用 `.dev-hub`、發配不重複的 ID、冪等地建立 Cycle / work item / WG / branch / worktree、計算綁定內容的 review fingerprint、create-or-update 單一 PR，以及只刪除「已證明安全」的殘留。所有輸出都是 `KEY=value`，重跑不會產生第二份 Cycle、worktree 或 PR。

```bash
bin/doctor.sh                       # 確認技能已同步
~/.claude/skills/x-discovery/scripts/xdh help
```

三顆核心規則值得單獨記住：`1 WG = 1 branch = 1 worktree = 1 PR`；最終 review 必須由非實作者的 Agent 執行，否則結果是 `BLOCKED` 而不是降級的 self-review；approval 綁定 fingerprint，內容一改就失效。

方法論參考 Garry Tan 的 [`gstack`](https://github.com/garrytan/gstack)（snapshot `d078622`，MIT），只借用流程與紀律，不使用其 global state、telemetry 或 reviewer auto-fix 行為；詳見各技能的 Provenance 段落。

## 範例技能

`funny-text-rewriter` 是一個適合新手參考的簡單技能：提供任意文字並要求改寫得有趣，它會保留原意與重要細節，只調整表達風格。例如：

```text
請使用 funny-text-rewriter 改寫：The meeting starts at 9 AM. Please don't be late.
```

## 更新行為

技能執行前至多每小時以 `git ls-remote` 檢查一次。發現更新時，AI 必須先詢問；同意才執行 `bin/apply-update.sh`。拒絕後預設七天不再詢問。可用以下環境變數調整：

| 變數 | 預設值 | 用途 |
| --- | ---: | --- |
| `SKILL_X_CHECK_INTERVAL_SECONDS` | `3600` | 遠端檢查節流秒數 |
| `SKILL_X_SNOOZE_DAYS` | `7` | 拒絕後延後天數 |
| `SKILL_X_STATE_DIR` | `~/.skill-x-starter-state` | 本機狀態目錄 |

## 容器 / 雲端 image

在 image build 階段執行：

```bash
bin/cloud-bootstrap.sh <private-repo-url> <tag-or-commit>
```

腳本會 checkout 指定 ref，**就地跑 `bin/build.sh` 產出 disposable artifact**，再把 canonical skill 複製到四個目標，最後視 OpenCode 版本決定要不要安裝 command shim。pinned ref 不需要夾帶 `commands/` 或 `opencode-commands/`——它們每次都從 source 重新產生。private repo 的 SSH agent、deploy key 或 BuildKit secret 應由你自己的建置環境提供，腳本不接收憑證。升級時改 ref 並重建 image。

> 請使用不可變的 tag 或完整 commit SHA。一般 branch 名稱雖可被 Git 解析，並不符合可重現建置的目的。

## 測試

本專案附有不需要網路、也不會改動真實家目錄的整合測試。測試會在暫存目錄建立本機 bare Git remote，驗證 build、symlink、更新、snooze、fast-forward pull 與 pinned cloud copy：

```bash
make test
```

測試結束時應顯示 `RESULT: 36 passed, 0 failed`。這能驗證 shell 腳本與檔案行為；Claude Code、Codex CLI、OpenCode 是否實際發現技能，以及 AI 是否依照自然語言指示詢問，仍需分別在三個工具做端到端人工 smoke test：

1. 執行 `./install.sh` 與 `bin/doctor.sh`，確認四個技能路徑與 OpenCode command 區段皆為 `OK`。
2. 重新啟動三個工具（skills 與 commands 在啟動時載入）。
3. Claude Code：輸入 `/example-skill`，確認技能內容被載入。
4. Codex：輸入 `$example-skill`，再開 `/skills` 確認技能出現在清單。
5. OpenCode：輸入 `/example-skill`。v1 應看到它透過 `skill` 工具載入 canonical skill；v2 應只出現一個項目，沒有重複。
6. 帶參數再試一次（例如 `/funny-text-rewriter 明天九點開會`），確認 `$ARGUMENTS` 有被轉送。

測試腳本另外需要 [`ripgrep`](https://github.com/BurntSushi/ripgrep)（`rg` 指令）來比對輸出，執行 `make test` 前請確認已安裝（例如 `brew install ripgrep` 或 `apt install ripgrep`）。
