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

## 明確呼叫技能

| Agent | 呼叫方式 | 實作方式 |
| --- | --- | --- |
| Claude Code | `/<skill-name>` | Claude Code 從 skills 目錄原生建立 slash command。 |
| Codex | `$<skill-name>` 或 `/skills` | 使用原生 skill UX；不安裝已棄用的 custom prompt。 |
| OpenCode v1 | `/<skill-name>` | 安裝輕量 command shim，由 `skill` tool 載入 canonical skill 並轉送參數。 |
| OpenCode v2 | `/<skill-name>` | 使用原生 skill slash catalog，不安裝重複 shim。 |

同步程式會從 `opencode --version` 自動判斷 OpenCode major version。若執行同步的環境沒有 OpenCode，請明確指定版本：

```bash
SKILL_X_OPENCODE_VERSION=v1 ./install.sh  # 安裝 v1 command shims
SKILL_X_OPENCODE_VERSION=v2 ./install.sh  # 僅使用 v2 原生 slash entries
```

`auto`（預設）、`v1`、`v2` 是有效值。產生的 `opencode-commands/` 只包含載入 canonical skill 與轉送 `$ARGUMENTS` 的 shim，不複製技能本文。同步不會覆蓋同名的非受管檔案；技能刪除或改用 v2 時，則會清除由目前 checkout 管理的 symlink。

以 `bin/doctor.sh` 檢視同步狀態。Windows 若未開啟 symlink 權限，目前不支援自動退回複製模式。

## 維護技能

在 Codex 開發環境新增技能時，建議把貼上的草稿或一句需求交給 repository-local 的 `.codex/skills/canonicalize-skill`。它會釐清觸發條件與範圍、建立格式正確的 `commands-src/<name>/SKILL.md`、在撞名時先詢問，並在完成後詢問是否立即執行 build。例如：

```text
請使用 canonicalize-skill：當我要求整理每週工作紀錄時，產生一份依專案分組的週報。
```

canonical skill 的唯一來源仍是 `commands-src/<name>/`；不要直接編輯產生的 `commands/`。建立或修改完成後執行 `bin/build.sh`，並將 source 與 generated skill 一起 commit。若要手動撰寫或查看完整命名規則，請參考 [CONTRIBUTING.md](./CONTRIBUTING.md)。

`canonicalize-skill` 是建置階段的 authoring tool，不是此 framework 的輸出；它不會進入 `commands/`，也不會由 `bin/sync-skills.sh` 分發到各 AI agents。framework 的輸入是 `commands-src/` 中完成 canonicalize 的 skill set，輸出才是跨 agents 使用的 generated skill set。

支援檔案（例如 `scripts/`、`references/`）會一併複製。修改 `_shared/update-check-header.md` 後也必須重跑 `bin/build.sh`。

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

腳本會 checkout 指定 ref，再把技能複製到目標路徑；runtime 不需保留 Git checkout。若 image 使用 OpenCode v1 且 build 環境無法偵測版本，請在命令前設定 `SKILL_X_OPENCODE_VERSION=v1`，以一併複製 command shims。private repo 的 SSH agent、deploy key 或 BuildKit secret 應由你自己的建置環境提供，腳本不接收憑證。升級時改 ref 並重建 image。

> 請使用不可變的 tag 或完整 commit SHA。一般 branch 名稱雖可被 Git 解析，並不符合可重現建置的目的。

## 測試

本專案附有不需要網路、也不會改動真實家目錄的整合測試。測試會在暫存目錄建立本機 bare Git remote，驗證 build、symlink、更新、snooze、fast-forward pull 與 pinned cloud copy：

```bash
make test
```

這能驗證 shell 腳本與檔案行為；三個工具仍需做端到端人工 smoke test：重新啟動 agent，依上表明確呼叫 `example-skill` 並確認載入；OpenCode v1 另帶一段文字，確認 shim 將參數傳給 skill。

測試腳本另外需要 [`ripgrep`](https://github.com/BurntSushi/ripgrep)（`rg` 指令）來比對輸出，執行 `make test` 前請確認已安裝（例如 `brew install ripgrep` 或 `apt install ripgrep`）。
