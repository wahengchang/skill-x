# 架構與交接文件

## 目標與資料流

本專案是個人指令集框架。private Git repository 是唯一來源：作者編輯 `commands-src/`，`bin/build.sh` 注入共用更新指示並產生已 commit 的 `commands/`。互動式個人電腦把部署版本 symlink 到各工具；不可變 image 在 build 階段複製指定 ref 的部署版本。

```text
commands-src ── build.sh ──> commands (committed)
                     │          ├─ sync-skills.sh ─> local symlinks
                     │          └─ cloud-bootstrap ─> pinned image copies
                     └──────> opencode-commands (committed, OpenCode v1 shims)
                                ├─ sync-skills.sh ─> ~/.config/opencode/commands
                                └─ cloud-bootstrap ─> pinned image copies
```

## 詞彙表

| 詞彙 | 意義 |
| --- | --- |
| **raw skill** | 從其他專案、零散草稿或一句描述取得，尚未格式化也尚未信任的技能素材。 |
| **canonicalize**（動詞） | 把 raw skill 釐清並整理成本專案標準格式的動作。 |
| **canonical skill** | canonicalize 的結果；位於 `commands-src/<name>/SKILL.md`，是技能內容的單一來源。 |
| **sync / distribute** | 既有 `bin/build.sh` 與 `bin/sync-skills.sh` 負責的建置及分發流程。目前三個目標工具皆讀取 `SKILL.md`，不需要格式轉換。 |
| **generated skill** | 產生於 `commands/<name>/SKILL.md`、再 symlink 到各工具的部署副本。 |
| **command shim** | 產生於 `opencode-commands/<name>.md` 的薄層 command 檔，只為 OpenCode v1 補上 `/<name>`；它叫 OpenCode 用 `skill` 工具載入 canonical skill，不含技能內容。 |

raw skill 先由 Codex 建置環境專用的 `.codex/skills/canonicalize-skill` 產生 canonical skill，之後才進入既有 build 與 sync 流程。canonicalizer 是 framework 的開發工具，不是 canonical skill set 的成員，因此不會建置到 `commands/` 或分發給各 AI agents。v1 不做近似重複的自動偵測；來源專案或原始 prompt 也不強制寫入，以免為單人維護增加不必要的 metadata。

## 關鍵決策

1. **共同格式**：一個技能一個資料夾，以含 YAML frontmatter 的 `SKILL.md` 作為三個工具的最大公約數。
2. **內容一致**：暫不為工具分支；真正出現差異需求時才加入條件或子目錄。技能**內容**不分支，只有「叫用管道」按工具補齊（決策 #9）。
3. **自建分發**：不使用單一工具的 marketplace，以一致的 update-check、詢問與 symlink 流程換取跨工具一致體驗。
4. **按需檢查**：技能呼叫時檢查，預設一小時節流，不執行 daemon。
5. **更新需同意**：個人電腦永不靜默更新；拒絕後預設延後七天。
6. **不可變 image**：build 時由使用者自己的 CI/建置環境提供 private repo 認證，固定 ref 並複製檔案；runtime 不依賴 Git。
7. **作者版與部署版都入庫**：其他機器 pull 後不必具備 build 工具鏈即可同步。
8. **雙版本節奏**：個人電腦 rolling，image pinned。
9. **叫用管道按工具補齊**：Claude Code 與 Codex 從 skills 目錄自動產生 `/<skill>` 與 `$<skill>`，OpenCode v2 也有原生 slash 目錄，只有 OpenCode v1 需要額外的 command 檔案。因此只為 v1 產生 shim，其餘工具不產生任何重複項目，也不安裝 Codex 已棄用的 custom prompts。
10. **共用支援檔以 symlink 收斂、以複製部署**：一組技能若共用同一份腳本，作者版只保留一份（`commands-src/_x-shared/`），各技能以 symlink 指過去；`bin/build.sh` 用 `find -L` 與 `cp -aL` 解引用，讓 `commands/<name>/` 得到真實副本。這是必要的：技能是各自 symlink 進 `~/.claude/skills/<name>` 的，執行期無法保證讀得到兄弟技能的檔案，所以部署版必須自給自足。決策 #2（內容不分支）仍然成立——收斂的是**來源**，不是內容。
11. **開發週期狀態一律 project-local**：`x-*` 技能組的所有執行期狀態放在 repo 內的 `.dev-hub/`，不使用 `~/.x-*` 或系統 `/tmp`。`active/`、`worktrees/`、`runtime/` 由 `xdh` 自動加進 `.gitignore`；只有 `logs/` 進 Git。理由是可稽核與可丟棄：一個 Cycle 的全部痕跡都能用一般 Git 指令檢視或清掉，換機器也不會帶著看不見的全域狀態。

## 核心機制

### Build

`bin/build.sh` 要求 `SKILL.md` 第一行為 `---`，在第二個 `---` 後插入 `_shared/update-check-header.md`，並原樣複製其他支援檔。同時為每顆技能產生 `opencode-commands/<name>.md` shim，`description` 取自 canonical frontmatter。它先在暫存目錄完成全部輸出，再一次替換 `commands/` 與 `opencode-commands/`，避免半成品。

### 明確叫用（command shim）

各工具的顯式叫用語法整理在 README 的能力對照表。實作面只有兩件事：

- shim 內容刻意極薄——指示 OpenCode 用 `skill` 工具載入 canonical skill、轉送 `$ARGUMENTS`，並帶一個 `skill-x-managed-command` 標記。技能內容不複製，避免出現第二份會過期的指示。
- `bin/opencode-version.sh` 解析 `opencode --version` 的主版號決定 v1／v2，`SKILL_X_OPENCODE_VERSION=auto|v1|v2` 可覆寫。偵測失敗時回退 v1 並在 stderr 說明；v1 安裝 shim symlink，v2 反向移除自己產生的 shim，兩者都不動使用者自有的 command 檔案。

### `x-*` 開發週期技能組

六顆技能（`x-discovery`、`x-plan-eng`、`x-review`、`x-debug`、`x-ship`、`x-housekeeping`）共用一份 `commands-src/_x-shared/`，內含 `scripts/xdh` 與七份 Markdown 樣板。分工是刻意的：**技能負責判斷，腳本負責可重複的操作**。

`xdh` 的責任邊界：

| 子指令 | 責任 |
| --- | --- |
| `paths` / `init` | 以 `git rev-parse --git-common-dir` 從任一 linked worktree 解析回 main repo，建立 `.dev-hub` 骨架與 `.gitignore` |
| `cycle new/list/show/check/close` | 建立或沿用 Cycle、關閉前檢查 gate、把完成 Cycle 壓成 `logs/` 短紀錄 |
| `id next`、`item new`、`wg new`、`artifact new` | 在 `mkdir` 互斥鎖內同時配發 ID 與建立檔案，避免兩個 agent 拿到同一個編號 |
| `field get/set` | 以 atomic write 改寫單一 `- Field: value`，保留檔案其餘所有內容 |
| `fingerprint [verify]` | 把整個工作狀態（含未 commit 變更）寫進暫時 index 並取得 tree，作為 review 目標 |
| `pr status/upsert` | 有 `gh` 就 create-or-update 單一 PR，沒有就回報 `no-provider` 而不是假裝有 PR |
| `worktree`、`clean scan/apply` | 分類 SAFE / DIRTY / UNMERGED / ACTIVE / ORPHAN，只刪 SAFE，且刪前再檢查一次 |

兩個設計選擇值得說明：

- **Fingerprint 綁內容，不綁時間。** 用暫時 `GIT_INDEX_FILE` 做 `read-tree` + `add -A` + `write-tree`，得到的 tree 同時涵蓋已 commit 與未 commit 的內容，因此「把未 commit 的東西 commit 起來」不會改變 fingerprint，而任何一個字元的改動都會。快照前會先把 `.dev-hub/active|runtime|worktrees` 從暫時 index 移除，否則這個指令自己產生的暫存檔會讓結果不穩定。
- **ID 配發與檔案建立同在鎖內。** `id next` 只是查詢；真正保證不重號的是 `item new` / `wg new` / `artifact new`，它們在同一個鎖裡掃描既有檔名與 `hub.md` 內容取最大值再建檔。重跑時同 slug 會直接沿用既有檔案（`X_ITEM_REUSED=yes`），不會在 `IS-001` 旁邊多出一個內容相同的 `IS-002`。

### 更新檢查

`bin/update-check` 依序檢查 snooze 與一小時節流狀態，再以 `git ls-remote origin HEAD` 比較本地 HEAD。只有遠端查詢成功才寫入 `last-check`；網路或 Git 失敗時保持靜默，不阻擋技能。輸出契約只有：

- `UP_TO_DATE`
- `UPGRADE_AVAILABLE <local_sha> <remote_sha>`
- 無輸出（無法檢查）

共用 header 指示 AI 發現更新時先詢問；同意後 `git pull --ff-only` 並重建 symlink，拒絕則寫入七天後的 snooze timestamp。狀態位於 `~/.skill-x-starter-state/`。

### 同步路徑

`bin/sync-skills.sh` 防禦性同步四個個人層級路徑：Claude、OpenCode、`~/.codex/skills` 與 `~/.agents/skills`，並在 OpenCode v1 時額外同步 `~/.config/opencode/commands`。遇到同名非 symlink 內容只警告而不覆蓋。之所以暫時保留兩個 Codex 路徑，是官方文件查詢在本次建置環境因 DNS/網路限制失敗，尚無法可靠裁決；應在真實 Codex CLI 跑 `bin/doctor.sh` 的步驟後回填並簡化。

### 容器部署

`bin/cloud-bootstrap.sh` 接受 repo URL 與 ref，在暫存 checkout 中取得該版本的 `commands/`，複製到四個目標。認證由 image builder 的 SSH agent/secret 負責，避免 token 進入參數、log 或 image layer。部署後只有技能副本，沒有 repository 腳本，因此嵌入的本地更新檢查自然無法執行且必須靜默繼續。

## 目錄

```text
commands-src/                  手動編輯的作者版
commands-src/_x-shared/        x-* 技能組共用的 xdh 腳本與 Markdown 樣板（各技能以 symlink 引用）
commands/                      build 產生、需 commit 的部署版
opencode-commands/             build 產生、需 commit 的 OpenCode v1 command shim
.codex/skills/canonicalize-skill/ Codex 建置環境專用的 raw skill authoring tool（不分發）
_shared/update-check-header.md 共用更新與詢問指示
bin/build.sh                   產生部署版
bin/update-check               節流遠端檢查
bin/apply-update.sh            fast-forward 更新與重新同步
bin/snooze.sh                  延後提醒
bin/sync-skills.sh             個人電腦 symlink
bin/opencode-version.sh        OpenCode v1/v2 判定與覆寫
bin/cloud-bootstrap.sh         image 固定版本複製
bin/doctor.sh                  目標路徑診斷
install.sh                     安裝入口
tests/run.sh                   不需網路的整合測試
```

## 已知限制與優先驗證

1. **Codex 路徑仍需實機驗證（中）**：目前同時覆蓋兩個候選全域路徑；先跑 doctor 與範例技能，再依實際載入來源簡化。
2. **Windows symlink（中）**：沒有 copy fallback；需 Developer Mode 或相應權限。
3. **自然語言詢問（中）**：各工具互動能力不同，無法由 shell 測試完全保證。
4. **無簽章驗證（低）**：信任 private origin；雲端應 pin commit，未驗證 commit signature。
5. **狀態無鎖（低）**：同時呼叫可能競爭寫入 timestamp，但個人使用影響有限。
6. **跨機與三工具實測待補**：優先測 pull、拒絕/snooze、重新啟動後技能發現與 `/`、`$` 叫用。
7. **OpenCode 版本判定是啟發式（中）**：只讀 `opencode --version` 的主版號，偵測不到時回退 v1。同一台機器裝多個 OpenCode 版本或版本字串改格式時，須用 `SKILL_X_OPENCODE_VERSION` 明確指定。
8. **`xdh pr` 只支援 GitHub `gh`（中）**：沒有 `gh` 時回報 `X_PR_PROVIDER=none`，由技能改成輸出手動建立 PR 的指示。要支援 GitLab 等平台需再加一個 provider 分支。
9. **獨立 Reviewer 由 host 決定（中）**：`x-review` 要求另一個 Agent，但能否真的啟動獨立 Agent 取決於當下工具。無法啟動時規定回報 `BLOCKED_NO_INDEPENDENT_REVIEWER`，這條是靠指示而非機制保證的。
10. **`.dev-hub` 沿用者的既有 `.gitignore`（低）**：`xdh` 只在缺少時附加三行，不會移除使用者自己寫的規則；若使用者手動刪掉這些行，Cycle 內容可能被誤 commit。

## 未採用方案

- **工具原生 marketplace/plugin**：Claude Code 可少維護，但無法提供三邊相同體驗。
- **GNU Stow**：能管理 symlink，但簡單迴圈已足夠，新增依賴的收益有限。
- **chezmoi / bare dotfiles repo**：能同步檔案，卻不會提供技能內的 update-check-and-ask 行為。
- **Syncthing 等常駐同步**：版本控制與 rollback 較弱，也違反 image pinned、不可變的策略。

## 維護規則

- 只改 `commands-src/` 或 `_shared/`，隨後執行 `bin/build.sh` 並一併 commit `commands/`。
- 新機器：clone 後執行 `./install.sh`。
- 個人機器手動更新：`git pull --ff-only && bin/sync-skills.sh`。
- image 升級：更新 pinned ref 並重建，不在 runtime pull。
- 每次修改腳本後執行 `make test`；測試使用暫存 HOME 與本機 bare Git remote，不會接觸使用者的真實技能目錄或遠端 repository。
