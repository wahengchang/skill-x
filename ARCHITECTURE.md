# 架構與交接文件

## 目標與資料流

本專案是個人指令集框架。private Git repository 是唯一來源：作者編輯 `commands-src/`，`bin/build.sh` 注入共用更新指示並產生已 commit 的 `commands/`。互動式個人電腦把部署版本 symlink 到各工具；不可變 image 在 build 階段複製指定 ref 的部署版本。

```text
commands-src ── build.sh ──> commands (committed)
                                ├─ sync-skills.sh ─> local symlinks
                                └─ cloud-bootstrap ─> pinned image copies
             └─ build.sh ──> opencode-commands (committed v1 shims)
```

## 詞彙表

| 詞彙 | 意義 |
| --- | --- |
| **raw skill** | 從其他專案、零散草稿或一句描述取得，尚未格式化也尚未信任的技能素材。 |
| **canonicalize**（動詞） | 把 raw skill 釐清並整理成本專案標準格式的動作。 |
| **canonical skill** | canonicalize 的結果；位於 `commands-src/<name>/SKILL.md`，是技能內容的單一來源。 |
| **sync / distribute** | 既有 `bin/build.sh` 與 `bin/sync-skills.sh` 負責的建置及分發流程。目前三個目標工具皆讀取 `SKILL.md`，不需要格式轉換。 |
| **generated skill** | 產生於 `commands/<name>/SKILL.md`、再 symlink 到各工具的部署副本。 |

raw skill 先由 Codex 建置環境專用的 `.codex/skills/canonicalize-skill` 產生 canonical skill，之後才進入既有 build 與 sync 流程。canonicalizer 是 framework 的開發工具，不是 canonical skill set 的成員，因此不會建置到 `commands/` 或分發給各 AI agents。v1 不做近似重複的自動偵測；來源專案或原始 prompt 也不強制寫入，以免為單人維護增加不必要的 metadata。

## 關鍵決策

1. **共同格式**：一個技能一個資料夾，以含 YAML frontmatter 的 `SKILL.md` 作為三個工具的最大公約數。
2. **內容一致**：暫不為工具分支；真正出現差異需求時才加入條件或子目錄。
3. **自建分發**：不使用單一工具的 marketplace，以一致的 update-check、詢問與 symlink 流程換取跨工具一致體驗。
4. **按需檢查**：技能呼叫時檢查，預設一小時節流，不執行 daemon。
5. **更新需同意**：個人電腦永不靜默更新；拒絕後預設延後七天。
6. **不可變 image**：build 時由使用者自己的 CI/建置環境提供 private repo 認證，固定 ref 並複製檔案；runtime 不依賴 Git。
7. **作者版與部署版都入庫**：其他機器 pull 後不必具備 build 工具鏈即可同步。
8. **雙版本節奏**：個人電腦 rolling，image pinned。

## 核心機制

### Build

`bin/build.sh` 要求 `SKILL.md` 第一行為 `---`，在第二個 `---` 後插入 `_shared/update-check-header.md`，並原樣複製其他支援檔。它先在暫存目錄完成全部輸出，再替換 `commands/`，避免半成品。

### 更新檢查

`bin/update-check` 依序檢查 snooze 與一小時節流狀態，再以 `git ls-remote origin HEAD` 比較本地 HEAD。只有遠端查詢成功才寫入 `last-check`；網路或 Git 失敗時保持靜默，不阻擋技能。輸出契約只有：

- `UP_TO_DATE`
- `UPGRADE_AVAILABLE <local_sha> <remote_sha>`
- 無輸出（無法檢查）

共用 header 指示 AI 發現更新時先詢問；同意後 `git pull --ff-only` 並重建 symlink，拒絕則寫入七天後的 snooze timestamp。狀態位於 `~/.skill-x-starter-state/`。

### 同步路徑

`bin/sync-skills.sh` 防禦性同步四個個人層級路徑：Claude、OpenCode、`~/.codex/skills` 與 `~/.agents/skills`。遇到同名非 symlink 內容只警告而不覆蓋。之所以暫時保留兩個 Codex 路徑，是官方文件查詢在本次建置環境因 DNS/網路限制失敗，尚無法可靠裁決；應在真實 Codex CLI 跑 `bin/doctor.sh` 的步驟後回填並簡化。

OpenCode v1 另外需要 `~/.config/opencode/commands/<name>.md` 才能明確以 slash command 呼叫。`bin/build.sh` 從 canonical skill 名稱產生只負責呼叫 `skill` tool 與轉送 `$ARGUMENTS` 的 shim；v2 使用原生 skill slash catalog。同步時優先使用 `SKILL_X_OPENCODE_VERSION`，否則偵測 CLI major version；無法判斷時不猜測並提示使用者指定。所有清理只碰指向此 checkout 產物的受管 symlink。

### 容器部署

`bin/cloud-bootstrap.sh` 接受 repo URL 與 ref，在暫存 checkout 中取得該版本的 `commands/`，複製到四個目標。認證由 image builder 的 SSH agent/secret 負責，避免 token 進入參數、log 或 image layer。部署後只有技能副本，沒有 repository 腳本，因此嵌入的本地更新檢查自然無法執行且必須靜默繼續。

## 目錄

```text
commands-src/                  手動編輯的作者版
commands/                      build 產生、需 commit 的部署版
opencode-commands/             build 產生、需 commit 的 OpenCode v1 command shims
.codex/skills/canonicalize-skill/ Codex 建置環境專用的 raw skill authoring tool（不分發）
_shared/update-check-header.md 共用更新與詢問指示
bin/build.sh                   產生部署版
bin/update-check               節流遠端檢查
bin/apply-update.sh            fast-forward 更新與重新同步
bin/snooze.sh                  延後提醒
bin/sync-skills.sh             個人電腦 symlink
bin/opencode-version.sh        OpenCode major version override / detection
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
6. **跨機與三工具實測待補**：優先測 pull、拒絕/snooze、重新啟動後技能發現。

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
