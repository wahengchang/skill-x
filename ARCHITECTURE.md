# 架構與交接文件

## 目標與資料流

本專案以 `commands-src/` 作為唯一作者來源，並有兩個 distribution surface：`bin/build-registry.sh` 產生、需要 commit 的 `skills/`，供 `npx skills add` 直接安裝；`bin/build.sh` 產生 gitignored 的 `commands/` 與 `opencode-commands/`，只供既有 checkout-based lifecycle 使用。

```text
commands-src/ ───┐
_shared/      ───┼── bin/build-registry.sh ──> skills/ (tracked, self-contained)
bin/targets/  ───┤
                 └── bin/build.sh ──> commands/           (gitignored artifact)
                                      opencode-commands/  (gitignored artifact)
                              │
                              ├─ skill-x install ──> build + sync + manifest
                              ├─ skill-x update  ──> fetch + fast-forward + build + sync + doctor
                              └─ bin/cloud-bootstrap ──> clone pinned ref + build + cp
```

`bin/skill-x` 是使用者面對的唯一入口（init / install / sync / status / doctor /
update / uninstall）。`install.sh`、`bin/sync-skills.sh`、`bin/doctor.sh`、
`bin/apply-update.sh` 保留為轉呼叫用的相容包裝。

## 詞彙表

| 詞彙 | 意義 |
| --- | --- |
| **raw skill** | 從其他專案、零散草稿或一句描述取得，尚未格式化也尚未信任的技能素材。 |
| **canonicalize**（動詞） | 把 raw skill 釐清並整理成本專案標準格式的動作。 |
| **canonical skill** | canonicalize 的結果；位於 `commands-src/<name>/SKILL.md`，是技能內容的單一來源。 |
| **build input** | 受版本控制的來源：`commands-src/`、`_shared/`、與 `bin/`（包含 `bin/targets/`）。 |
| **published skill** | `skills/<name>/` 下可由 `npx skills` 單獨安裝的自包含 skill；由 source 產生、進 Git、不可手動編輯。 |
| **generated artifact** | `bin/build.sh` 產生的 disposable artifact tree，列在 `.gitignore`。`commands/`、`opencode-commands/`，以及未來任何新增的 transform 產物。 |
| **canonical-format consumer** | 直接讀取 `commands/<name>/SKILL.md` 不需轉換的 runtime；由 `CANONICAL_CONSUMERS` 描述。 |
| **transform adapter** | 把 common build 完成後的 canonical artifact 轉成另一個 runtime 需要的 wire format 的腳本，位於 `bin/targets/<adapter>.sh`。 |
| **sync / distribute** | `bin/skill-x sync` 與 `bin/cloud-bootstrap.sh` 負責把 build 出的 artifact 部署到目標路徑；它們不是 build pipeline 的一部分。 |
| **installation manifest** | `~/.local/state/skill-x/<id>/install.json`，記錄某個 checkout 部署了什麼。status／doctor／uninstall 都以它為準。 |
| **managed entry** | manifest 記錄、由 skill-x 建立的單一路徑（目前都是 symlink）。沒被記錄的同名檔案一律視為使用者所有。 |
| **command shim** | 產生於 `opencode-commands/<name>.md` 的薄層 command 檔，只為 OpenCode v1 補上 `/<name>`；它叫 OpenCode 用 `skill` 工具載入 canonical skill，不含技能內容。 |

raw skill 先由 Codex 建置環境專用的 `.codex/skills/canonicalize-skill` 產生 canonical skill，之後才進入既有 build 與 sync 流程。canonicalizer 是 framework 的開發工具，不是 canonical skill set 的成員，因此不會建置到 `commands/` 或分發給各 AI agents。v1 不做近似重複的自動偵測；來源專案或原始 prompt 也不強制寫入，以免為單人維護增加不必要的 metadata。

## 關鍵決策

1. **共同格式**：一個技能一個資料夾，以含 YAML frontmatter 的 `SKILL.md` 作為三個工具的最大公約數。
2. **內容一致**：暫不為工具分支；真正出現差異需求時才加入條件或子目錄。技能**內容**不分支，只有「叫用管道」按工具補齊（決策 #11）。
3. **自建分發**：不使用單一工具的 marketplace，以一致的 update-check、詢問與 symlink 流程換取跨工具一致體驗。
4. **按需檢查**：技能呼叫時檢查，預設一小時節流，不執行 daemon。
5. **更新需同意**：個人電腦永不靜默更新；拒絕後預設延後七天。
6. **不可變 image**：build 時由使用者自己的 CI/建置環境提供 private repo 認證，固定 ref 並複製檔案；runtime 不依賴 Git。pinned ref 不需要夾帶 artifact，bootstrap 會就地 build。
7. **build input 入庫，artifact 為 disposable**：個人 clone 或 image build 不必預先夾帶 `commands/` 或 `opencode-commands/`；一律從 source 重新生成。
8. **雙版本節奏**：個人電腦 rolling，image pinned。
9. **生命週期由 CLI 擁有**：安裝狀態寫進 per-installation 的 manifest，而不是靠掃描家目錄猜測。這是「只移除自己建立的東西」「搬移 checkout 可診斷、可修復」「未選的 agent 不留痕跡」三件事的共同前提。
10. **更新一律先 fetch**：只比對本地 HEAD 與遠端 HEAD（或過期的 remote-tracking ref）會讓安裝在無聲中落後；`status` 與 `update` 都先 fetch 追蹤中的 upstream 再判斷。
11. **叫用管道按工具補齊**：Claude Code 與 Codex 從 skills 目錄自動產生 `/<skill>` 與 `$<skill>`，OpenCode v2 也有原生 slash 目錄，只有 OpenCode v1 需要額外的 command 檔案。因此只為 v1 產生 shim，其餘工具不產生任何重複項目，也不安裝 Codex 已棄用的 custom prompts。
12. **共用支援檔以 symlink 收斂、以複製部署**：一組技能若共用同一份腳本，作者版只保留一份（`commands-src/_x-shared/`），各技能以 symlink 指過去；`bin/build.sh` 用 `find -L` 與 `cp -aL` 解引用，讓 `commands/<name>/` 得到真實副本。這是必要的：技能是各自 symlink 進 `~/.claude/skills/<name>` 的，執行期無法保證讀得到兄弟技能的檔案，所以部署版必須自給自足。決策 #2（內容不分支）仍然成立——收斂的是**來源**，不是內容。
13. **開發週期狀態一律 project-local**：`x-*` 技能組的所有執行期狀態放在 repo 內的 `.dev-hub/`，不使用 `~/.x-*` 或系統 `/tmp`。`active/`、`worktrees/`、`runtime/` 由 `xdh` 自動加進 `.gitignore`；只有 `logs/` 進 Git。理由是可稽核與可丟棄：一個 Cycle 的全部痕跡都能用一般 Git 指令檢視或清掉，換機器也不會帶著看不見的全域狀態。
14. **target 擴充走 metadata + adapter**：加新 runtime 時，讀 canonical `SKILL.md` 的加進 `CANONICAL_CONSUMERS`、需要不同表示的加 adapter 腳本並登記到 `TRANSFORMED_TARGETS`。build pipeline 不需要改。

15. **token 成本是設計約束，不是事後最佳化**：技能的 `SKILL.md` 每次執行都整份載入，所以它的大小是**每次呼叫**都要付的成本。三條規則因此成立：(a) 機械可得的事實由 `xdh` 產出，不由 AI 逐檔讀取——`xdh survey ensure` 把專案概況（layout、entry point、文件、測試、DevEx 指令、變更熱點）收集成一份有 8 KB 上限的快取，以 commit + working tree + schema 版號為 key，變了才重收；`x-discovery` 與 `x-plan-eng` 都消費同一份，不各掃一次。(b) 同一段內容只放一個地方——facet contract 由 specialist 自己讀，orchestrator 只讀 `references/facet-dispatch.md`；`## Provenance` 是 repository 的維護史而非 agent 的指令，由 `bin/build.sh` 在建置時剝除，只留在 `commands-src/`。(c) 上限要有測試守住——`tests/survey-regression.sh` 對每顆部署版技能斷言位元組上限，否則規則會一次補一點又長回去。

16. **預設路由只有 engineering**：實務上絕大多數工作只需要工程面向。Product / Design / DevEx 必須由使用者明講或 `hub.md` 標記才進 route，不由「感覺像產品問題」自動展開；route 只有 `engineering` 時 `x-plan` 直接交棒 `x-plan-eng` Direct mode，不走 orchestration——單一 facet 走 orchestration 只多一次 fingerprint 交接與一次 contract 載入，換不到任何東西。DevEx 的「開發者旅程」是**專案**屬性不是工作項屬性，收集一次後每項工作只回答「有沒有動到」。

17. **fingerprint 只對實質變動反應**：planning fingerprint 是為了偵測「規劃輸入的意義改了」。原本對原始位元組雜湊，連 tab、重複空白、多一行空行都會 rotate，把所有已完成的 facet 標成 stale——防呆變成噪音。`x_plan_normalize_body` 在雜湊前做保守正規化（tab 展開、行內連續空白、行尾空白、連續空行），但**保留前導縮排**，因為它承載清單層級，是語意。結論未受影響的 facet 用 `xdh plan facet set --reaffirm` 重新蓋章：它只能平移一個已經記錄過的同類狀態，永遠無法無中生有一個 completed。

18. **關係查詢按專案分類 routing**：「誰呼叫這個 / 改了會影響誰 / 哪些測試會壞」由 CodeGraph 的索引回答，比讀檔案便宜一到兩個數量級——在 `wf-comic` 與 `owlchi-site-system` 上實測，一次 callers 查詢的純文字答案是 0.2–1.3 KB，而含有該符號的檔案總量是 26–243 KB。但 CodeGraph 不支援 shell / Markdown / YAML，skill-x 自己就索引不到東西，所以能力必須是**可選**的：`xdh survey` 一次分類（有沒有程式碼 → 是否已 init → 索引是否非空），輸出 `X_SURVEY_NAV`，技能只讀這個結果。第一關刻意只是「存在性」而非「佔比」：曾經要求支援語言達到一定佔比，那等於用「這個 repo 有多少不是程式碼」來判斷圖有沒有用——一個 200 篇 markdown + 40 個 TS 檔的內容系統只有 17%，會被拒絕走圖，但那 40 個檔正是規劃的對象。而且佔比在真實 repo 上（62% / 65% / 0%）從未真正做過決定，卻帶著那個誤判。「圖夠不夠用」由索引裡有沒有符號回答。`unsupported` / `empty` / `absent` 都是正常狀態，靜默降級回讀檔路線，不得產生警告噪音。

    三個實測發現寫進了技能文字，因為官方文件沒有講：(a) `--json` 的輸出約是純文字的兩倍而事實相同，agent 該用純文字；(b) `codegraph affected` 的預設 glob 只認 `*.test.*` / `*.spec.*`，Python 的 `test_*.py` 會回「No test files affected」——與真正的空結果無法區分，所以 survey 從專案的測試命名推導出 glob 並寫進 `## Code graph`，而且 `affected` 只能當**正面訊號**（它走 import 邊，Playwright 那種跑瀏覽器的套件連不到）；(c) CLI 預設開啟 telemetry，跑在私有 repo 上一律 `CODEGRAPH_TELEMETRY=0`。

19. **索引新鮮度搭 survey 的便車，且永不阻擋**：`survey ensure` 只在**自己要重建時**才跑 `codegraph sync -q`——survey 的快取鍵問的正是「程式碼變了沒」，與 sync 要回答的是同一個問題，重用它等於零額外過期邏輯、零額外成本（實測 fresh 路徑 358ms，rebuild 含 sync 858ms）。所有 codegraph 呼叫都有 120 秒硬 timeout，失敗或逾時一律降級成 `files`：**過期的圖會給出有自信但錯誤的答案，比沒有圖更糟**。`codegraph index`（全量重建）永遠不自動執行——小專案 1.8 秒，但大 repo 是分鐘級，在規劃流程中途卡住比原本的問題更糟；survey 只回報 `uninitialized` 讓使用者自己決定。

    `## Code graph` 區塊刻意很薄：索引狀態、測試 glob、指令選單。早期版本還會探測 fan-in 最高的符號，那需要 40 次連續 `codegraph callers` 行程、在 353 檔的專案上要 11 秒——對一個每次重建都跑的東西太貴，而且形狀也不對：fan-in 是該對「這次真正動到的符號」問的問題。

## 核心機制

### Build

`bin/build.sh` 從 `bin/targets/targets.conf` 讀取 canonical 目的地與 target 註冊資料，並驗證所有 adapter 腳本都已宣告（反之亦然）。接著：

1. **Common canonical build**：掃描 `commands-src/`，對每顆技能的 `SKILL.md` 注入 `_shared/update-check-header.md`、保留 support 檔，輸出到 `$CANONICAL_DEST`（預設 `commands/`）的 staging tree。
2. **Transform adapters**：依序執行 `bin/targets/<adapter>.sh build "$canonical_tmp" "$staging"`；adapter 收到的是 common build 完成後的 canonical staging artifact，而不是 raw `commands-src/`，因此 header injection 與 support-file materialization 只維護一份。adapter 再把 canonical artifact 轉成該 runtime 需要的表示（例如 OpenCode v1 的 command shim），輸出到自己的 artifact 目錄。

adapter 的 action contract 固定為：`build <canonical-staging-dir> <artifact-staging-dir>`、`sync <artifact-dir>`、`bootstrap <artifact-dir>`。所有輸出都先寫到 `mktemp` 暫存樹，全部建置成功後才逐棵以 `mv` 替換最終 artifact 目錄，所以消費者不會看到任一目錄的半成品。生成的 `commands/`、`opencode-commands/`，以及未來任何 transform artifact，都列在 `.gitignore`，正常 commit 不會把它們送進 repository。

### Target metadata

`bin/targets/targets.conf` 是 build 與 bootstrap 之間的合約：

- `CANONICAL_DEST`：canonical artifact 目錄（目前 `commands`）；build、sync 與 bootstrap 都必須從這個值取得 canonical tree，不得另外 hardcode `commands/`。
- `CANONICAL_CONSUMERS`：直接讀 SKILL.md 的 runtime 與其部署路徑，例如 `claude-code:~/.claude/skills`。bootstrap 用這份清單決定要把 canonical artifact 拷貝到哪裡。
- `TRANSFORMED_TARGETS`：需要 adapter 的 target，格式 `<adapter-script-stem>:<artifact-directory-under-repo-root>`。bootstrap 看到這份清單才把 transform 產物拷貝給有需要的 runtime。

加新 runtime 時，視需要只動這個檔，build pipeline 不必改。

### 明確叫用（command shim）

各工具的顯式叫用語法整理在 README 的能力對照表。實作面只有兩件事：

- shim 內容刻意極薄——指示 OpenCode 用 `skill` 工具載入 canonical skill、轉送 `$ARGUMENTS`，並帶一個 `skill-x-managed-command` 標記。技能內容不複製，避免出現第二份會過期的指示。
- `bin/opencode-version.sh` 解析 `opencode --version` 的主版號決定 v1／v2，`SKILL_X_OPENCODE_VERSION=auto|v1|v2` 可覆寫。偵測失敗時回退 v1 並在 stderr 說明；v1 安裝 shim symlink，v2 反向移除自己產生的 shim，兩者都不動使用者自有的 command 檔案。

### `x-*` 開發週期技能組

十顆技能（`x-discovery`、`x-plan`、`x-plan-product`、`x-plan-design`、`x-plan-devex`、`x-plan-eng`、`x-review`、`x-debug`、`x-ship`、`x-housekeeping`）共用一份 `commands-src/_x-shared/`，內含 `scripts/xdh`、七份 Markdown 樣板與四份 facet 合約。分工是刻意的：**技能負責判斷，腳本負責可重複的操作**。

`xdh` 的責任邊界：

| 子指令 | 責任 |
| --- | --- |
| `paths` / `init` | 以 `git rev-parse --git-common-dir` 從任一 linked worktree 解析回 main repo，建立 `.dev-hub` 骨架與 `.gitignore` |
| `survey ensure/path` | 產出並快取專案概況（layout、entry point、文件、測試、DevEx 指令、變更熱點），8 KB 上限；以 commit + working tree + schema 版號為 key，變了才重收。同時分類專案並輸出 `X_SURVEY_NAV=graph\|files` 決定關係查詢走哪條路 |
| `cycle new/list/show/check/close` | 建立或沿用 Cycle、關閉前檢查 gate、把完成 Cycle 壓成 `logs/` 短紀錄 |
| `id next`、`item new`、`wg new`、`artifact new` | 在 `mkdir` 互斥鎖內完成「檢查既有 → 配號 → 建檔」，避免兩個 agent 拿到同一個編號 |
| `plan init / facet set / decision set / fingerprint / check / ready` | 初始化規劃路由、以 scoped writer 記錄 facet 與 Owner Decision 狀態、計算 planning fingerprint、檢查並放行 new-format 工作項到 `ready` |
| `design prepare` | 接收三項明確的 Image capability 狀態，依 slug 與 fingerprint 準備（或重用）設計工作目錄，回報 `X_DESIGN_DIR` / `X_DESIGN_REUSED` |
| `field get/set` | 以 atomic write 改寫單一 `- Field: value`，保留檔案其餘所有內容 |
| `fingerprint [verify]` | 把整個工作狀態（含未 commit 變更）寫進暫時 index 並取得 tree，作為 review 目標 |
| `pr status/upsert` | 以 head branch **與 head repository owner** 兩者定位 PR，create-or-update 單一 PR；沒有 `gh` 就回報 `no-provider` 而不是假裝有 PR |
| `worktree`、`clean scan/apply` | 分類 SAFE / DIRTY / UNMERGED / ACTIVE / ORPHAN，只刪 SAFE，且刪前再檢查一次 |

facet 合約的單一權威來源是 `commands-src/_x-shared/facets/`：四份合約
（`product` / `design` / `devex` / `engineering`）各只有一份，由**owning
specialist** 以 symlink 收斂成自己的 `references/facet-contract.md`；`bin/build.sh`
用 `find -L` + `cp -aL` 解引用，讓 `commands/<skill>/references/` 得到**自給自足
的真實副本**（與 scripts/templates 相同的決策 #12 收斂方式）。

`x-plan` **不**收斂這四份合約。orchestrator 需要的是「分派誰、傳什麼、回來查
什麼」，那是它自己的 `references/facet-dispatch.md`；合約要等 specialist 真的
跑起來才需要，由 specialist 自己讀。兩邊都帶會讓同一份內容在一次規劃裡進
context 兩次（決策 #15）。

七個設計選擇值得說明：

- **Fingerprint 綁內容，不綁時間。** 用暫時 `GIT_INDEX_FILE` 做 `read-tree` + `add -A` + `write-tree`，得到的 tree 同時涵蓋已 commit 與未 commit 的內容，因此「把未 commit 的東西 commit 起來」不會改變 fingerprint，而任何一個字元的改動都會。快照前會先把 `.dev-hub/active|runtime|worktrees` 從暫時 index 移除，否則這個指令自己產生的暫存檔會讓結果不穩定。
- **「檢查既有」與「配號建檔」必須在同一個 critical section。** `id next` 只是查詢；真正保證不重號的是 `cycle new` / `item new` / `wg new` / `artifact new`——它們在同一個鎖裡完成「掃描是否已存在 → 取最大號 +1 → 寫檔（讓下一次掃描看得到）」。只鎖住配號、把寫檔留到鎖外，會讓兩個同時規劃的 agent 都掃到空目錄、都拿到 `WG-001`。`cycle new` 也要上鎖：目錄名帶到分鐘的時間戳，跨分鐘邊界的兩個併發呼叫會建出兩個同 slug 的 active Cycle，之後每一次 lookup 都變成 ambiguous。
- **worktree 的「已註冊」不等於「可用」。** 目錄被手動刪掉時 `git worktree list` 仍會列出它。所以重用前要確認 `path/.git` 真的存在、而且 HEAD 就在預期的 branch 上；註冊是 stale 就 `git worktree prune` 後重建，路徑被無關內容佔用則直接停下來，不覆蓋。
- **機器可讀記錄一律 TSV。** 路徑會含空白（macOS 的 `My Projects`、`Mobile Documents` 是常態），所以以空白分隔的記錄不是格式而是陷阱：`clean apply` 曾用 `read -r _ class kind target rest` 解析，repo 位於 `/home/u/proj v2/` 時 `target` 被截成 `/home/u/proj`，dirty 護欄因為 `git -C <截斷路徑>` 失敗而靜默通過，`rm -rf` 則打到一個真實存在的同層目錄。現在 `clean scan`、`worktree list` 與 `pr` 查詢一律 tab 分隔、以 `IFS=$'\t'` 讀取；刪除前另有一道與解析無關的收容檢查，確保任何 kind 都只能刪到它該待的目錄底下。
- **standalone scope 必須是固定路徑。** 沒有 Cycle 時，規劃文件的 scope 曾用 `xdh runtime new` 產生帶秒級時間戳的目錄，等於每次呼叫都換一個位置：reuse 掃描永遠掃到空的、ID 每次從 001 重來、跨分鐘重跑會替同一個 slug 生出第二條 branch 與第二個 worktree，而且鎖開在那個每次都不同的目錄裡——standalone 模式根本沒有互斥。現在固定為 `.dev-hub/runtime/standalone/`，Cycle 模式與 standalone 模式走同一套 reuse／配號／上鎖邏輯。相對的，`clean scan` 也必須知道「含有未終結 WG／work item 的 runtime 目錄是活的」，否則保留期一過就會把還開著的 Work Group 刪掉。work item 與 WG 的終結狀態不同（前者 done/cancelled/deferred，後者 merged/closed/…），這個判斷收斂在 `x_status_is_terminal`，避免 closure gate 與 housekeeping 兩處各寫一份而漂移。
- **auxiliary 檔案的收容邊界要從 item 解析，不能從 cwd。** `--section-file` 與 `--owner-decision-file` 的「必須在專案內」檢查原本比對 `X_MAIN_ROOT`，而那是由**行程的工作目錄**解析出來的。一旦 WG 有了自己的 worktree，agent 的 cwd 就不等於 item 所在的 repo，於是每一個合法的 section file 都被判成 `section-file-outside-project`。現在改用 `x_plan_project_root_for <item>`，與 `x_plan_mutable_target` 用同一個依據。舊測試只驗過拒絕路徑，所以這個 bug 一直沒被看見——收容檢查一定要連 happy path 一起測。
- **PR 不能只用 branch name 當 key。** branch 推到 fork 時，同一個 base repository 上可能有多個 fork 都開著叫 `fix` 的 PR。因此查詢會同時比對 `headRefName` 與 `headRepositoryOwner`（owner 由 push remote 的 URL 推得）；仍然分不出來時回報 `X_PR_STATE=ambiguous` 並拒絕更新，而不是賭一個把別人的 PR body 蓋掉。查詢用 `gh --jq` 輸出 TSV，比對留在 shell 字串比較，既避免手寫 JSON parser，也讓這段邏輯可以被測試。
### 生命週期與安裝 manifest

`bin/skill-x` 把「選擇→部署→記錄」做成一條路徑。每個 checkout 有一個 installation id，存在 `.git/skill-x-install-id`（不是 git repo 時退回路徑雜湊），所以搬移或改名 checkout 之後仍是同一個安裝——manifest 裡的 `checkout_path` 與現在的執行位置不同時，`status`／`doctor` 會直接說「搬過家」，`install` 會把每一條連結重新指向。

manifest 是刻意規則化的 JSON：頂層純量縮排兩格，陣列與物件寫在同一行，每個 entry 一行。這樣 `bin/lib/manifest.awk` 這種只會掃描字串的讀取器就夠用，不必為了讀回自己的狀態而引入 `jq` 依賴。

`status` 會回報 `current`／`behind`／`ahead`／`diverged`／`unreachable`（外加獨立的 `dirty` 旗標），`--json` 的鍵順序是被測試釘住的契約。`doctor` 逐項判斷 `ok`／`missing`／`stale`／`foreign`，`--strict` 在有問題時以非零結束，適合放進自動化。

upstream 由 `branch.<name>.remote` / `branch.<name>.merge` 推出，而不是 `@{upstream}`：remote-tracking ref 被 prune 掉時 `git rev-parse @{upstream}` 會一邊失敗一邊把字面字串印到 stdout，那正是安裝狀態會變成胡言亂語的來源。

`uninstall` 只刪除 manifest 記錄、且現在仍指向預期目標的項目；其餘一律保留並列為 `preserved`。`--remove-checkout` 的髒工作區檢查放在最前面，拒絕時不會留下拆到一半的安裝。

### 更新檢查

`bin/update-check` 是技能執行時的便宜提示（權威狀態在 `bin/skill-x status`），可用 `SKILL_X_DISABLE_UPDATE_CHECK=1` 關閉。它依序檢查 snooze 與一小時節流狀態，再以 `git ls-remote origin HEAD` 比較本地 HEAD。只有遠端查詢成功才寫入 `last-check`；網路或 Git 失敗時保持靜默，不阻擋技能。輸出契約只有：

- `UP_TO_DATE`
- `UPGRADE_AVAILABLE <local_sha> <remote_sha>`
- 無輸出（無法檢查）

共用 header 指示 AI 發現更新時先詢問；同意後執行 `bin/skill-x update --yes`（fetch → 預覽 → fast-forward → 重新 build → 同步 → doctor），拒絕則寫入七天後的 snooze timestamp。節流與 snooze 狀態跟 manifest 放在同一個 per-installation 目錄，不同 checkout 之間互不干擾。

### 同步路徑

`bin/skill-x sync` 從 `targets.conf` 取得 `$CANONICAL_DEST`、`CANONICAL_CONSUMERS` 與 `TRANSFORMED_TARGETS`，只同步 manifest 選到的 agent。Claude 是 `~/.claude/skills`，Codex 是 `~/.agents/skills`（主要路徑）與 `~/.codex/skills`（相容路徑，`SKILL_X_CODEX_COMPAT=0` 可關閉），OpenCode 是 `~/.config/opencode/skills`；transform adapter 負責 OpenCode v1 command shim 的生命週期。遇到同名非 symlink 內容只警告而不覆蓋。取消選擇某個 agent 時，manifest 差集會把先前建立的連結收回，使用者自有檔案不動。

### 容器部署

`bin/cloud-bootstrap.sh` 接受 repo URL 與 ref，先 clone 到暫存目錄、checkout 指定 ref、**就地跑該 ref 的 `bin/build.sh`** 產出 artifact。新版 ref 會照 `CANONICAL_CONSUMERS` 拷貝 canonical artifact，再由 transform adapter 的 `bootstrap` action 處理 transform 產物；若 pinned ref 早於 target registry，則回退到歷史 `commands/` + `opencode-commands/` layout。重複使用的 HOME 或 image layer 可能留有互動安裝建立的 symlink，pinned 複製前會先解開它，避免 `cp` 穿過連結寫回原始 checkout；從 v1 換到 v2 時也會移除帶 `skill-x-managed-command` 標記的 command 副本。認證由 image builder 的 SSH agent/secret 負責，避免 token 進入參數、log 或 image layer。部署後只有技能副本，沒有 repository 腳本，因此嵌入的本地更新檢查自然無法執行且必須靜默繼續。

## 目錄

```text
commands-src/                  手動編輯的作者版（build input）
commands-src/_x-shared/        x-* 技能組共用的 xdh 腳本與 Markdown 樣板（各技能以 symlink 引用）
_shared/update-check-header.md 共用更新與詢問指示（build input）
.codex/skills/canonicalize-skill/ Codex 建置環境專用的 raw skill authoring tool（不分發）
bin/skill-x                    生命週期入口（init/install/sync/status/doctor/update/uninstall）
bin/lib/common.sh              agent 註冊表、狀態目錄、manifest 讀寫、git 輔助
bin/lib/manifest.awk           manifest 讀取器（無外部相依）
bin/build.sh                   產生 disposable artifact tree
bin/targets/targets.conf       canonical 目的地與 target 註冊資料
bin/targets/<adapter>.sh       各 transform adapter
bin/update-check               節流遠端檢查（提示用，可停用）
bin/apply-update.sh            相容包裝 → skill-x update --yes
bin/snooze.sh                  延後提醒
bin/sync-skills.sh             相容包裝 → skill-x sync
bin/opencode-version.sh        OpenCode v1/v2 判定與覆寫
bin/cloud-bootstrap.sh         image 固定版本複製（含就地 build）
bin/doctor.sh                  相容包裝 → skill-x doctor
commands/                      build 產生的 canonical artifact（.gitignore）
opencode-commands/             build 產生的 OpenCode v1 command shim（.gitignore）
install.sh                     相容包裝 → skill-x init
tests/run.sh                   不需網路的整合測試（`--fast` 只跑常用子集，預設全跑）
tests/plan-machine-regression.sh 規劃 gate 的機器行為 regression tests
tests/plan-content-regression.sh 規劃技能內容契約 regression tests
tests/pr10-safety-regression.sh 擁有權安全性 regression tests
tests/pr15-regression.sh       target contract 與 legacy pinned-ref regression tests
tests/lib/harness.sh           共用測試 harness：suite 選擇、計時、逾時、fixture 快取
tests/lib/timeout-fixture.sh   驗證 harness 逾時路徑的受控 fixture
```

## 已知限制與優先驗證

1. **Codex 路徑仍需實機驗證（中）**：目前把 `~/.agents/skills` 當主要路徑、`~/.codex/skills` 當相容路徑同時覆蓋；先跑 `bin/skill-x doctor` 並呼叫 `x-discovery` 技能驗證，再依實際載入來源用 `SKILL_X_CODEX_COMPAT=0` 簡化。
2. **Windows symlink（中）**：沒有 copy fallback；需 Developer Mode 或相應權限。
3. **自然語言詢問（中）**：各工具互動能力不同，無法由 shell 測試完全保證。
4. **無簽章驗證（低）**：信任 private origin；雲端應 pin commit，未驗證 commit signature。
5. **狀態無鎖（低）**：同時呼叫可能競爭寫入 timestamp 或 manifest，但個人使用影響有限。
6. **manifest 只記 symlink（低）**：cloud pinned 複製不寫 manifest，因此 `uninstall` 不負責清理 image 內的副本；image 的生命週期由重建 image 決定。
7. **跨機與三工具實測待補**：優先測 pull、拒絕/snooze、重新啟動後技能發現與 `/`、`$` 叫用。
8. **OpenCode 版本判定是啟發式（中）**：只讀 `opencode --version` 的主版號，偵測不到時回退 v1。同一台機器裝多個 OpenCode 版本或版本字串改格式時，須用 `SKILL_X_OPENCODE_VERSION` 明確指定。
9. **`xdh pr` 只支援 GitHub `gh`（中）**：沒有 `gh` 時回報 `X_PR_PROVIDER=none`，由技能改成輸出手動建立 PR 的指示。要支援 GitLab 等平台需再加一個 provider 分支。head owner 由 push remote URL 推得，若 remote 未設定則退回只比對 branch name，此時多筆相符會回報 `ambiguous` 而不是任選一筆。
10. **獨立 Reviewer 由 host 決定（中）**：`x-review` 要求另一個 Agent，但能否真的啟動獨立 Agent 取決於當下工具。無法啟動時規定回報 `BLOCKED_NO_INDEPENDENT_REVIEWER`，這條是靠指示而非機制保證的。
11. **`.dev-hub` 沿用者的既有 `.gitignore`（低）**：`xdh` 只在缺少時附加三行，不會移除使用者自己寫的規則；若使用者手動刪掉這些行，Cycle 內容可能被誤 commit。
12. **awk 不得使用 interval expression（中）**：`xdh` 的判斷邏輯大量寫在 awk 裡，而 Debian／Ubuntu 的預設 awk 是 mawk。mawk 1.3.4 (20240123) 遇到 interval 後接 alternation group（例如 `^#{1,6}([ \t]|$)`）會直接 `REcompile() - panic` 中止，於是 `x_plan_has_content` 對每一個 section 都回報 empty，`xdh plan check` 在這種機器上永遠無法通過。開發機是 macOS 時看不到這個現象，CI 也可能因為 mawk 版本不同而漏掉。新增 awk regex 一律改用 `+`／`*` 或明確列舉，不用 `{n,m}`。
13. **鎖是同機器內的（低）**：`x_lock` 用 `mkdir` 互斥，只保護同一台機器上的併發 agent。若 `.dev-hub` 放在多台機器共掛的網路檔案系統上，`mkdir` 的原子性不再保證。超過兩分鐘未釋放的鎖會被視為死行程留下的而清除。

## 未採用方案

- **工具原生 marketplace/plugin**：Claude Code 可少維護，但無法提供三邊相同體驗。
- **GNU Stow**：能管理 symlink，但簡單迴圈已足夠，新增依賴的收益有限。
- **chezmoi / bare dotfiles repo**：能同步檔案，卻不會提供技能內的 update-check-and-ask 行為。
- **Syncthing 等常駐同步**：版本控制與 rollback 較弱，也違反 image pinned、不可變的策略。

## 維護規則

- 只改 `commands-src/`、`_shared/`、`bin/` 等 build input；隨後執行 `bin/build.sh`，不需 commit `commands/` 或 `opencode-commands/`（它們在 `.gitignore`）。
- 新機器：clone 後執行 `./install.sh`（或 `bin/skill-x init --agents ...`）。
- 個人機器手動更新：`bin/skill-x update`（或非互動時 `bin/skill-x update --yes`）。
- image 升級：更新 pinned ref 並重建，不在 runtime pull。
- 每次修改腳本（`bin/`、`tests/`、`install.sh`）後執行 `make test-full`；只改技能內容時 `make test`（快速組）即可。兩組都使用暫存 HOME 與本機 bare Git remote，不會接觸使用者的真實技能目錄或遠端 repository。
