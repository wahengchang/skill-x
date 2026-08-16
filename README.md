# skill-x

skill-x 是一套參考 Garry Tan 的 gstack 產品形態打造的個人 skill 管理框架。它以 Git repository 作為唯一來源，透過單一入口 `bin/skill-x` 管理整組 skill set 的 install、update 與 uninstall，並將同一組技能同步到 Codex、Claude Code 與 OpenCode；個人電腦使用 symlink 與可選更新，容器 image 則安裝固定版本的副本。

內建的 `x-discovery`、`x-plan`、`x-plan-product`、`x-plan-design`、`x-plan-devex`、`x-plan-eng`、`x-review`、`x-debug`、`x-ship` 與 `x-housekeeping` 十顆技能，串起設計 → 開發 → ship 的 handover 週期，讓各階段的工作脈絡能持續交接。

### 一眼看懂工作週期

```text
┌────────────── 設計 ──────────────┐   ┌────────────── 開發 ──────────────┐   ┌────────────── Ship ──────────────┐
│                                  │   │                                  │   │                                  │
│  x-discovery ───▶ x-plan        ├──▶│  x-debug ◀──────▶ x-review      ├──▶│  x-ship ───▶ x-housekeeping      │
│  釐清問題           四面向規劃    │   │  修正問題            驗證成果     │   │  交付成果       收尾並準備下一輪   │
└──────────────────────────────────┘   └──────────────────────────────────┘   └───────────────────┬──────────────┘
           ▲                                                                               │
           └────────────────────────────── 下一個 handover 週期 ────────────────────────────┘
```

### 一份 skill set，三個工具

```text
                         Git repository（唯一來源）
                                     │
                               bin/skill-x
                      ├── install ─┐
                      ├── update ──┴── build / sync ──┬──▶ Claude Code
                      │                               ├──▶ Codex
                      │                               └──▶ OpenCode
                      └── uninstall ── 移除受管理的部署項目
```

## 五分鐘快速上手

```bash
git clone https://github.com/wahengchang/skill-x.git ~/skill-x
cd ~/skill-x
./install.sh                 # 等同 bin/skill-x init
```

`init` 會偵測本機安裝了哪些 agent、讓你確認要部署的目標、建置技能、建立 symlink，最後印出每個 agent 的叫用語法與後續指令。非互動環境（CI、容器）請直接指定目標：

```bash
bin/skill-x init --agents claude,codex
```

接著重新啟動各 agent（技能與 command 在啟動時載入），輸入 `/x-discovery` 或 `$x-discovery` 驗證。

想確認安裝狀態：

```bash
bin/skill-x status           # 落後幾個 commit、選了哪些 agent、路徑是否健康
bin/skill-x doctor           # 每個受管理路徑的逐項診斷
```

> 想用自己的 private fork：把上面的 clone URL 換成你的 repository 即可，其餘指令完全相同。認證由你的 Git 設定（SSH key 或 credential helper）負責，本專案的腳本不接收也不儲存憑證。

## 指令總覽

| 指令 | 用途 |
| --- | --- |
| `bin/skill-x init [--agents ...]` | 選擇目標 agent、建置、同步、驗證。互動時會先確認選擇。 |
| `bin/skill-x install [--agents ...]` | 以既有選擇重新套用；可重複執行且冪等，也是搬移 checkout 後的修復指令。 |
| `bin/skill-x sync [--agents ...]` | 只重建 symlink，不重新 build。 |
| `bin/skill-x status [--json] [--no-fetch]` | 安裝狀態、更新狀態、agent 版本、路徑健康度。 |
| `bin/skill-x doctor [--strict] [--json]` | 逐項檢查受管理路徑；`--strict` 在有問題時以非零結束。 |
| `bin/skill-x update [--check] [--yes]` | 先 fetch，再預覽變更，最後 fast-forward。永不靜默更新。 |
| `bin/skill-x uninstall [--agents ...] [--remove-checkout]` | 只移除本安裝記錄的項目。 |

`install.sh`、`bin/sync-skills.sh`、`bin/doctor.sh`、`bin/apply-update.sh` 仍可使用，它們現在只是轉呼叫上面的指令。

## 安裝目標與路徑

只有被選到的 agent 會建立目錄；沒選的 agent 不會在家目錄留下任何東西。

| Agent | 技能路徑 | 說明 |
| --- | --- | --- |
| `claude` | `~/.claude/skills/` | |
| `codex` | `~/.agents/skills/` | 文件化的主要路徑 |
| `codex` | `~/.codex/skills/` | 相容路徑，可用 `SKILL_X_CODEX_COMPAT=0` 關閉 |
| `opencode` | `~/.config/opencode/skills/` | |
| `opencode` | `~/.config/opencode/commands/` | 只有 OpenCode v1 需要，見下節 |

同名衝突一律保守處理：既有的非 symlink 檔案只警告不覆蓋，`uninstall` 也不會刪除它們。

## 各工具的明確叫用方式

同一顆技能在三個工具的顯式叫用語法不同：

| 工具 | 叫用方式 | 來源 |
| --- | --- | --- |
| Claude Code | `/<skill>` | `~/.claude/skills/<skill>/SKILL.md` 自動成為 slash command，不需額外檔案 |
| Codex | `$<skill>`，或用 `/skills` 選單 | `~/.agents/skills/<skill>/SKILL.md`；已棄用的 custom prompts（`/prompts:<name>`）預設不安裝 |
| OpenCode v1 | `/<skill>` | 由 `bin/build.sh` 產生、再 symlink 到 `~/.config/opencode/commands/<skill>.md` 的 command shim |
| OpenCode v2 | `/<skill>` | 原生 skill slash 目錄；不安裝 shim，避免重複項目 |

OpenCode v1 的 shim 是薄薄一層：它只叫 OpenCode 用 `skill` 工具載入 canonical skill 並轉送 `$ARGUMENTS`，不複製技能內容。技能內容的唯一來源仍是 `commands-src/<name>/SKILL.md`。

版本偵測預設執行 `opencode --version`。偵測不到（例如 OpenCode 尚未安裝或不在 `PATH`）時視為 v1 並提示，可用環境變數強制指定。從 v1 切換到 v2 時，`bin/skill-x sync` 會清掉自己產生的 shim，使用者自己寫的 command 檔案不受影響。

## 安裝狀態（manifest）

每個 checkout 都有自己的安裝記錄：

```text
~/.local/state/skill-x/<installation-id>/install.json
```

裡面記錄 repository URL、checkout 路徑、安裝的 commit、選擇的 agent 與偵測到的版本、解析出的 OpenCode 模式、技能清單、每一條受管理的 symlink 及其目標，以及最後一次成功的 install／sync／update 時間。`status`、`doctor`、`uninstall` 全部以它為準——所以 skill-x 只會移除自己建立的東西，也能在 checkout 被搬走時說出到底發生什麼事。

installation id 存在 `.git/skill-x-install-id`，因此搬移或改名 checkout 之後仍是同一個安裝。更新提醒的節流與 snooze 狀態也放在同一個目錄，不同 checkout 之間互不干擾。

## 更新

```bash
bin/skill-x update --check    # 只看會變什麼，不動任何東西
bin/skill-x update            # 預覽後詢問；同意才套用
bin/skill-x update --yes      # 非互動環境（已確認）
```

`update` 一定先 `git fetch` 追蹤中的 upstream 再判斷狀態，不會只比對本地的 remote-tracking ref。套用時只做 fast-forward，接著重新 build、同步選定的 agent、跑一次 doctor。

安全規則：

- 工作區有未 commit 的追蹤檔案變更 → 拒絕更新，已部署的技能維持原狀。
- 本地與 upstream 分岔 → 拒絕更新，並提示先 rebase。
- 沒有終端機可以詢問又沒有 `--yes` → 拒絕更新。

技能執行前的更新檢查仍然存在（至多每小時一次 `git ls-remote`，發現更新時由 AI 詢問），但它只是提示；權威狀態一律以 `bin/skill-x status` 為準。可用 `SKILL_X_DISABLE_UPDATE_CHECK=1` 完全關掉。

## 移除

```bash
bin/skill-x uninstall                      # 移除所有受管理項目，保留 checkout
bin/skill-x uninstall --agents opencode    # 只移除某個 agent
bin/skill-x uninstall --remove-checkout    # 連 checkout 一起刪除
```

只有 manifest 記錄、且現在仍指向預期目標的 symlink 會被刪除；使用者自己的技能、command、目錄與同名衝突檔案一律保留，並在輸出中列為 `preserved`。`--remove-checkout` 在 checkout 有未 commit 或未追蹤的內容時會直接拒絕，且拒絕時不會先移除任何東西。

## 環境變數

| 變數 | 預設值 | 用途 |
| --- | --- | --- |
| `SKILL_X_AGENTS` | 未設定 | 預設的 agent 選擇（`--agents` 優先） |
| `SKILL_X_OPENCODE_VERSION` | `auto` | `auto`／`v1`（安裝 shim）／`v2`（改用原生 slash，並移除既有 shim） |
| `SKILL_X_CODEX_COMPAT` | `1` | 設為 `0` 時不再同步 `~/.codex/skills` |
| `SKILL_X_STATE_HOME` | `~/.local/state` | 安裝狀態的根目錄（也吃 `XDG_STATE_HOME`） |
| `SKILL_X_STATE_DIR` | 未設定 | 指定單一狀態目錄（舊版配置） |
| `SKILL_X_DISABLE_UPDATE_CHECK` | `0` | 設為 `1` 時停用技能執行前的更新檢查 |
| `SKILL_X_CHECK_INTERVAL_SECONDS` | `3600` | 遠端檢查節流秒數 |
| `SKILL_X_SNOOZE_DAYS` | `7` | 拒絕更新後延後天數 |

## 疑難排解

| 症狀 | 處理方式 |
| --- | --- |
| `doctor` 出現 `FOREIGN` | 該路徑不是 skill-x 建立的（你自己的技能或別的工具）。skill-x 不會覆蓋也不會刪除它；要讓 skill-x 接手，先自行改名或移除。 |
| `doctor` 出現 `STALE` | symlink 還在，但目標不見了——通常是 checkout 被搬走或技能被刪除。跑 `bin/skill-x install` 重新指向。 |
| `doctor` 出現 `MOVED` | manifest 記錄的 checkout 路徑與現在執行的位置不同。跑 `bin/skill-x install` 即可修復全部連結並更新 manifest。 |
| `doctor` 出現 `ORPHAN` | 同一個家目錄裡還有別的安裝記錄，但它的 checkout 已經不存在。依照輸出的指令帶 `SKILL_X_STATE_DIR=` 移除該筆記錄。 |
| `status` 顯示 `unreachable` | 不是 git checkout、沒有追蹤 upstream，或連不到遠端。`state_reason` 會說明是哪一種。 |
| 更新被拒（dirty） | `git status --short` 看一下，commit 或 stash 之後再跑一次。未追蹤的檔案不會擋更新。 |
| 更新被拒（diverged） | 本地有 upstream 沒有的 commit。先 `git rebase <upstream>`，再跑 `bin/skill-x update`。 |
| OpenCode 版本判斷錯誤 | 偵測不到時會回退 v1 並在 stderr 說明。用 `SKILL_X_OPENCODE_VERSION=v1\|v2` 明確指定。 |
| Windows 沒有 symlink 權限 | 目前不支援自動退回複製模式，需要 Developer Mode 或相應權限。 |

## 維護技能

在 Codex 開發環境新增技能時，建議把貼上的草稿或一句需求交給 repository-local 的 `.codex/skills/canonicalize-skill`。它會釐清觸發條件與範圍、建立格式正確的 `commands-src/<name>/SKILL.md`、在撞名時先詢問，並在完成後詢問是否立即執行 build。例如：

```text
請使用 canonicalize-skill：當我要求整理每週工作紀錄時，產生一份依專案分組的週報。
```

canonical skill 的唯一來源仍是 `commands-src/<name>/`；不要直接編輯產生的 `commands/`、`opencode-commands/`，也不要把這些 disposable artifact commit 進 repository（它們在 `.gitignore`）。建立或修改完成後執行 `bin/build.sh`，只需要 commit source 與 build 設定。若要手動撰寫或查看完整命名規則，請參考 [CONTRIBUTING.md](./CONTRIBUTING.md)。

`canonicalize-skill` 是建置階段的 authoring tool，不是此 framework 的輸出；它不會進入 `commands/`，也不會被分發到各 AI agents。framework 的輸入是 `commands-src/` 中完成 canonicalize 的 skill set，輸出才是跨 agents 使用的 generated skill set。

支援檔案（例如 `scripts/`、`references/`）會一併複製。修改 `_shared/update-check-header.md` 後也必須重跑 `bin/build.sh`。

## `x-*` 開發週期技能組

`x-` 前綴的十顆技能是一整套開發流程：把一次盤點變成 Cycle、把工作準備到可直接開工、由獨立 Agent 審查、以證據除錯、交付成一個 PR，最後把完成的 Cycle 壓成一份短 log。

| 技能 | 回答的問題 | 主要輸出 |
| --- | --- | --- |
| `x-discovery` | 這個範圍內有哪些工作？ | `.dev-hub/active/cycle-*/hub.md` 與 `WK-XXX` 工作總表 |
| `x-plan` | 如何把工作準備到可直接開工？ | 分派 Product→Design→DevEx→Engineering 四面向，產出 `IS-*` / `SP-*` / `WG-*`、Owner 與 planning fingerprint |
| `x-plan-product` | 產品面向：目標、範圍、使用者可見行為與優先序？ | 產品決策與證據、pending Owner Decision |
| `x-plan-design` | 設計面向：UX、互動與能力（Image Generate / Display / Compare）？ | 設計決策、能力階梯與證據 |
| `x-plan-devex` | DevEx 面向：setup→首次變更→測試→除錯→CI/release 的旅程？ | 各階段可驗證的證據 |
| `x-plan-eng` | 工程面向：每項工作工程上怎麼做？ | `## Engineering Facet`、架構 / 資料流 / 測試 / 驗收 |
| `x-review` | 這份最終內容有什麼真實風險？ | `RV-*`（含 severity、`file:line`、失效情境） |
| `x-debug` | 已知問題的 root cause 是什麼？ | `DBG-*`、根因修正與 regression test |
| `x-ship` | 能否安全交付，並形成一個 PR？ | commits、pushed branch、create-or-update 的單一 PR |
| `x-housekeeping` | 哪些執行殘留已可安全刪除？ | 清理結果與 `.dev-hub/logs/cycle-*.md` |

`x-plan` 是規劃階段的 orchestration 入口：它先解析唯一 scope 與 target，把每項工作依「Product → Design → DevEx → Engineering」的順序分派給對應的 specialist（Engineering 一律 mandatory、永遠最後），每個 facet 以「自己的唯一寫入指令」記錄決策與證據，最後用 `plan check → wg new → plan ready` 這道 gate 讓 new-format 的工作項到達 `ready`。整份計畫綁定在確定性的 planning fingerprint 上，內容一改 fingerprint 就失效。

十顆技能都能只憑「專案背景、repo 文件、程式碼、Prompt」獨立啟動，不需要先有 Cycle。使用者輸入 `continue` 時，接續依據是 artifact 裡的 Handover 區塊，沒有隱藏的全域狀態機。

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

## 容器 / 雲端 image

在 image build 階段執行：

```bash
bin/cloud-bootstrap.sh <repo-url> <tag-or-commit>
```

腳本會 checkout 指定 ref，**就地跑 `bin/build.sh` 產出 disposable artifact**，再把 canonical skill 複製到四個目標，最後視 OpenCode 版本決定要不要安裝 command shim。pinned ref 不需要夾帶 `commands/` 或 `opencode-commands/`——它們每次都從 source 重新產生。private repo 的 SSH agent、deploy key 或 BuildKit secret 應由你自己的建置環境提供，腳本不接收憑證。升級時改 ref 並重建 image。

> 請使用不可變的 tag 或完整 commit SHA。一般 branch 名稱雖可被 Git 解析，並不符合可重現建置的目的。

如果 image layer 或 HOME 是重複使用的，pinned 複製前會先解開自己建立的 symlink，避免 `cp` 穿過連結寫回原始 checkout；從 v1 切到 v2 時也會移除帶有 `skill-x-managed-command` 標記的 command 副本，使用者自有的 command 不受影響。

## 測試

本專案附有不需要網路、也不會改動真實家目錄的整合測試。測試會在暫存目錄建立本機 bare Git remote 與暫存 HOME，驗證 build、symlink、安裝 manifest、status 狀態、更新安全性、修復、移除保留行為與 pinned cloud copy。測試分成兩組：

```bash
make test        # 快速組：canonical build、artifact/shim 產生與冒煙測試
make test-full   # 完整組：上面全部 + 生命週期、更新、cloud bootstrap、target adapter、xdh 回歸
```

日常只改技能內容（`commands-src/`、`_shared/`）時跑 `make test` 就夠；改到 `bin/`、`tests/` 或任何腳本行為時請跑 `make test-full`（細節見 CONTRIBUTING.md）。兩組都會列出每個測試的耗時與最慢的前五名，單一測試超過 `SKILL_X_TEST_TIMEOUT`（預設 240 秒）會被中止並標成 `TIMEOUT` 失敗。

`make test-full` 結束時應讓每個已註冊 suite 都顯示 `RESULT ... 0 failed`。這能驗證 shell 腳本與檔案行為；Claude Code、Codex CLI、OpenCode 是否實際發現技能，以及 AI 是否依照自然語言指示詢問，仍需分別在三個工具做端到端人工 smoke test：

1. 執行 `./install.sh` 與 `bin/skill-x doctor`，確認選定的技能路徑與 OpenCode command 區段皆為 `OK`。
2. 重新啟動三個工具（skills 與 commands 在啟動時載入）。
3. Claude Code：輸入 `/x-discovery`，確認技能內容被載入。
4. Codex：輸入 `$x-discovery`，再開 `/skills` 確認技能出現在清單。
5. OpenCode：輸入 `/x-discovery`。v1 應看到它透過 `skill` 工具載入 canonical skill；v2 應只出現一個項目，沒有重複。
6. 帶參數再試一次（例如 `/x-discovery 規劃下一個功能`），確認 `$ARGUMENTS` 有被轉送。

測試腳本另外需要 [`ripgrep`](https://github.com/BurntSushi/ripgrep)（`rg` 指令）來比對輸出，執行測試前請確認已安裝（例如 `brew install ripgrep` 或 `apt install ripgrep`）。
