# 開發一組新技能：操作手冊

這份文件給「要在這個 repo 裡新增/修改技能」的你自己（或未來接手的人）。README.md 是給使用者看的安裝說明，ARCHITECTURE.md 是給接手工程師看的設計決策；這份文件只講一件事：**動手加技能時，具體步驟跟命名規則是什麼**。

---

## 1. 心智模型：先搞清楚這幾個資料夾

| 資料夾 | 你會做什麼 |
|---|---|
| `commands-src/<name>/SKILL.md` | **唯一手動編輯的地方**。乾淨的技能內容，不含更新檢查樣板文字。 |
| `commands/<name>/SKILL.md` | `bin/build.sh` 產生的 canonical artifact（frontmatter 之後多了 `_shared/update-check-header.md` 的內容）。**永遠不要手動改這裡**，也**不要 commit**——它是 `.gitignore` 的 disposable artifact，下次 build 會被覆蓋。 |
| `opencode-commands/<name>.md` | `bin/build.sh` 產生的 OpenCode v1 command shim，讓技能可用 `/<name>` 叫用。同樣**不要手動改也不要 commit**；它也是 gitignored artifact。 |
| `~/.claude/skills/`、`~/.agents/skills/` 等 | `bin/skill-x sync` 把 `commands/` symlink 過去的地方，AI 工具實際讀取的路徑。 |

一句話：**改 `commands-src/` → `bin/build.sh` 重新產生 `commands/` 與 `opencode-commands/` → 只要 commit source 與 build 設定，不要 commit artifact**。

---

## 2. 開發一顆新技能：完整步驟

```bash
cd ~/skill-x

# 1. 建資料夾，一個技能一個資料夾
mkdir -p commands-src/<skill-name>

# 2. 寫 SKILL.md（frontmatter 只需要 name + description，其餘是技能內容）
cat > commands-src/<skill-name>/SKILL.md <<'EOF'
---
name: <skill-name>
description: 一句話講清楚這個技能做什麼、什麼情況該被觸發。
---

實際的指令內容寫在這裡。
EOF

# 3.（可選）需要輔助檔案就直接放同一個資料夾，build.sh 會原封不動複製
mkdir -p commands-src/<skill-name>/scripts
# commands-src/<skill-name>/scripts/helper.sh ...

# 4. 重新產生部署版本
bin/build.sh

# 5. 跑一次快速測試，確認沒把 build/artifact 弄壞（純技能內容改動這樣就夠）
make test

# 6. 本機同步一次，實際用用看（可選但建議）
bin/skill-x sync
bin/skill-x doctor --strict   # 確認每個受管理路徑都是 OK

# 7. 只 commit build input；artifact 已在 .gitignore
git add commands-src/<skill-name>
git commit -m "add <skill-name> skill"
git push
```

其他機器要跟上：`bin/skill-x update`（會先預覽再詢問），或什麼都不做，等下次呼叫任一技能時它自己會問你要不要更新。

### 開發一整組（多顆）技能

架構上沒有「技能分組資料夾」這種東西（見 ARCHITECTURE.md 決策 #2：三邊指令集內容完全一致，不分子目錄客製）。一組技能就是「多個 `commands-src/<name>/` 資料夾，name 用同一個字首」——分組純粹靠**命名**跟 git 歷史，細節見下一節。

流程跟單顆技能一樣，差別只在一次做完 2～4 步後，一次 commit 多顆：

```bash
mkdir -p commands-src/myapp-deploy commands-src/myapp-rollback commands-src/myapp-status
# 分別寫好三份 SKILL.md ...
bin/build.sh
make test
git add commands-src
git commit -m "add myapp-* skill set (deploy, rollback, status)"
git push
```

### 一組技能共用同一份腳本

如果一組技能要共用腳本或樣板（`x-*` 就是這樣），**不要在每顆技能各放一份副本**——會漂移。作法是把共用檔案放在一個以底線開頭、不含 `SKILL.md` 的目錄（因此 `bin/build.sh` 不會把它當技能），再從各技能 symlink 過去：

```bash
mkdir -p commands-src/_myapp-shared/scripts
# commands-src/_myapp-shared/scripts/helper.sh ...

for s in myapp-deploy myapp-rollback; do
  ln -sfn ../_myapp-shared/scripts "commands-src/$s/scripts"
done
bin/build.sh
```

`bin/build.sh` 會解引用 symlink（`find -L` + `cp -aL`），所以 `commands/<name>/scripts/` 是**真實副本**，執行權限也保留。這是必要的：每顆技能是各自 symlink 進 `~/.claude/skills/<name>` 的，執行期讀不到兄弟技能的檔案（見 ARCHITECTURE.md 決策 #12）。

代價是 `commands/` 底下會出現多份相同副本——那是 disposable artifact，跟注入的更新檢查標頭一樣，不需要 commit。

同理，`x-*` 的四份 facet 合約（`product` / `design` / `devex` / `engineering`）也只在 `commands-src/_x-shared/facets/` 各放一份，當作單一權威來源。`x-plan` 用 symlink 把它們收斂成自己的 `references/<facet>-facet-contract.md`，每個 owning specialist（`x-plan-product` / `x-plan-design` / `x-plan-devex` / `x-plan-eng`）則收斂成自己的 `references/facet-contract.md`；`bin/build.sh` 一樣解引用成真實副本，所以執行期每顆技能都讀得到自己那份，不依賴兄弟技能。

### 測試：`make test`（快）vs. `make test-full`（全）

測試分成兩組，差別只在「你改了什麼」，不是「你有多趕」：

| 指令 | 內容 | 什麼時候用 |
|---|---|---|
| `make test`（等同 `make test-fast`） | `tests/run.sh --fast`：canonical build、header 注入、OpenCode shim 產生、共用資產 materialize、artifact gitignore 檢查、sync 冒煙測試、harness timeout 自檢 | **低風險改動**：只動 `commands-src/**/SKILL.md`、技能的支援檔、`_shared/update-check-header.md`、文件 |
| `make test-full` | `tests/run.sh --full` + `tests/plan-machine-regression.sh` + `tests/plan-content-regression.sh` + `tests/pr10-safety-regression.sh` + `tests/pr15-regression.sh`，執行所有已註冊測試 | **其餘一律用這個**：動到 `bin/`（含 `bin/targets/`）、`tests/`、`install.sh`、`Makefile`，或任何影響 install/sync/update/uninstall 生命週期、Git 更新檢查、cloud bootstrap、target adapter、`xdh` 行為的改動 |

不確定就跑 `make test-full`——它才是送出前的完整把關。

兩組都會印出每個測試的耗時與最慢的前五名，方便日後定位變慢的案例；單一測試超過 `SKILL_X_TEST_TIMEOUT`（預設 240 秒）會被中止並標成 `TIMEOUT` 失敗，不會無限期卡住。要臨時縮短可用 `SKILL_X_TEST_TIMEOUT=60 make test-full`。

兩組都不需要網路，也都在暫存 HOME 與暫存目錄裡跑，不會碰到你真正的 `~/.claude/skills`。

### 修改既有技能 / 修改共用的更新檢查邏輯

- 改某顆技能：直接改 `commands-src/<name>/SKILL.md`，一樣跑 `bin/build.sh` + `make test` + commit 來源。
- 改 `_shared/update-check-header.md`（會影響**所有**技能）：改完必須跑一次 `bin/build.sh` 讓全部技能重新套用；不需要也不應該把 `commands/` 或 `opencode-commands/` 裡的變動 commit 進來——它們是 disposable artifact。

---

## 3. 命名規則

技能的 `name` 會變成四件事：`commands-src/<name>/` 的資料夾名、`commands/<name>/` 的資料夾名、symlink 進 `~/.claude/skills/<name>` 等四個路徑時的名字，以及各工具裡的叫用字串（`/<name>`、`$<name>`）——**這是一個跨工具共用的扁平命名空間**，沒有子目錄隔開，所以撞名的代價比一般專案內的檔名撞名更高（AI 工具會直接看到重複或誤導的技能名稱）。

規則：

1. **格式**：全小寫 kebab-case，只用 `a-z`、`0-9`、`-`，以字母開頭。例如 `myapp-status`、`myapp-deploy`。不要用底線、大寫、空白或中文。
2. **資料夾名必須等於 frontmatter 裡的 `name:`**。目前 `bin/build.sh` 不會幫你檢查這件事，兩者不一致純粹是人為約定——建立資料夾時把 `name:` 複製貼上過去，不要自己改一份。
3. **具體，避免單一泛用詞**。`deploy`、`test`、`sync` 這種字未來很容易撞名（不管是撞你自己的其他技能，還是撞其他來源裝進同一個 `~/.claude/skills/` 的技能/plugin）。一律搭配領域或專案名詞：`myapp-deploy` 而不是 `deploy`。
4. **一組相關技能用共同字首**：例如同一個專案的維運技能，用 `myapp-` 開頭（`myapp-deploy`、`myapp-rollback`、`myapp-status`）。這樣在 `commands-src/` 目錄列表、`bin/skill-x doctor` 輸出裡會自然排在一起，一眼看出彼此相關。
5. **長度**：建議 40 字元以內，太長的名字在各工具的技能選單/描述裡容易被截斷。
6. **`description` 要講清楚「觸發時機」，不只是「做什麼」**。這欄位會被 AI 工具用來判斷什麼時候該主動叫用這個技能，寫得越具體（例如「當使用者要求產生週報時」而不是「產生報告」），觸發準確度越高。

---

## 4. 常見錯誤

- **改了 `commands/` 卻沒改 `commands-src/`**：下次任何人跑 `bin/build.sh` 都會把你的改動蓋掉。永遠改 `commands-src/`。
- **共用資料夾放了 `SKILL.md`**：`commands-src/_x-shared/SKILL.md` 會讓 build 把它當成一顆名為 `_x-shared` 的技能。共用目錄底下只放支援檔。
- **commit 了 `commands/` 或 `opencode-commands/`**：它們是 `.gitignore` 的 disposable artifact；commit 它們只會讓之後的 `git status` 一直叫，或者在 build 之後產生無意義的 conflict。`git rm -r --cached` 清掉就好。
- **改了 `commands-src/`，卻在本機直接跑 `bin/skill-x sync` 而沒先 build**：會同步舊 artifact；改用 `bin/skill-x install`，或先執行 `bin/build.sh`。
- **`name:` 跟資料夾名不一致**：目前無自動檢查，純靠自律；建議寫的當下就對照一次。
- **跑測試前沒裝 `ripgrep`**：測試腳本用 `rg` 做輸出比對，`brew install ripgrep` / `apt install ripgrep` 先裝好。
- **改了 `bin/` 或 `tests/` 卻只跑 `make test`**：快速組不含生命週期、更新、cloud bootstrap、target adapter 與 `xdh` 的覆蓋，這類改動一律要 `make test-full`。

---

## 5. 提交前檢查清單

- [ ] `commands-src/<name>/SKILL.md` 的 `name:` 跟資料夾名一致
- [ ] 命名符合第 3 節規則（kebab-case、具體、必要時共用字首）
- [ ] `description:` 講清楚做什麼 + 何時觸發
- [ ] 跑過 `bin/build.sh`
- [ ] 跑過 `make test`（只改技能內容時），全部 PASS
- [ ] 有動到 `bin/`、`tests/`、`install.sh` 或 `Makefile` 時，另外跑過 `make test-full`，全部 PASS
- [ ] `git status` 沒有列出 `commands/` 或 `opencode-commands/` 的變動（它們是 gitignored artifact）
