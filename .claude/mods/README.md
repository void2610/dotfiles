# Claude Code Mods

Claude Code の function hooks (`CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1`) で動く自作プラグイン群。
常時ロードは `.claude/skills/<name>` → `../mods/<name>` の symlink で行う (`--plugin-dir` 不要)。

## Mod 一覧

| Mod | 主なイベント | 機能 |
| --- | --- | --- |
| `git-context` | `prompt.context` | 現在ブランチ・`git status --short`・main からの差分コミットを毎ターンのコンテキストに注入 |
| `guards` | `prompt.submit` / `tool.call` | ガード集約 (下表参照)。イベント登録は `index.ts` に一本化し、機能は 1 ファイル 1 ガード |
| `pr-watch` | `clock` / `prompt.submit` / `ui.render` | 現在ブランチの OPEN PR を常駐監視 (gh 60 秒間隔 + バックオフ)。CI fail / Copilot レビュー未解決スレッドで `$.prompt.submit` によりセッションを自動起床。プロンプト直上の監視行はボタンで、押すと PR の checks ページを開く。`/pr-watch` で即時更新 |
| `ship-hud` | `ui.render` / `command.run` | ship 状態機械をプロンプト直上 (AbovePrompt) に常時表示 (goal・フェーズ列・report / quiz の approve ボタン)。`/ship-hud` で表示トグル、`mcp__ship-hud__status` 等のツールも提供 |
| `scratchpad-open` | `ui.render` / `command.run` / `clock` | scratchpad にファイルがある時だけプロンプト直上に `scratchpad (N)` ボタンを表示し、押すと Finder で開く。`/scratchpad` コマンドも同じ動作 |
| `artifact-archive` | `tool.call` | 一時ディレクトリ (`/tmp`・`/var/folders` = scratchpad) からの Artifact publish を deny し、`~/Documents/claude-artifacts/` への保存へ誘導 |
| `ntfy-notify` | `turn.complete` | メインループのターン完了を `notify.sh` 経由で ntfy.sh にプッシュ通知 (サブエージェント・中断・autopilot 実行中は除外) |
| `autopilot` | `turn.complete` / `turn.start` / `prompt.submit` / `session.compact` / `ui.render` / `command.run` / `tool.call` | 自走モード。ターン終了ごとに `$.prompt.submit` で次のターンを起こし、時間・ターン数・進捗なし (git 差分と状態ファイルの指紋)・API エラーの上限で止める。Esc で一時停止。`/autopilot start <目標>` / pause / resume / stop と `mcp__autopilot__start/stop/wait/status` で操作し、状態は `~/.claude/state/autopilot/<repo キー>/` (手順は autopilot-playbook スキル) |
| `turn-timer` | `turn.complete` | ターンの所要時間とトークン消費をトースト表示 |

## guards の内訳 (`guards/hooks/`)

| ファイル | 発火 | 内容 |
| --- | --- | --- |
| `git-skill-enforcer.ts` | Bash | `git commit` / `git push` / `gh pr create` の直接実行を deny し、`CLAUDE_GIT_SKILL=<skill>` マーカー付き (スキル経由) のみ許可 |
| `branch-track-guard.ts` | Bash | `origin/main` 起点のブランチ作成 (`--no-track` なし) と upstream の main 向け変更を deny |
| `comment-style-guard.ts` | Edit / Write | 複数行コメントブロックの追加を検知し、CLAUDE.md の Comments ルールに沿った削減ワークフローを注入 |
| `feedback-memory-router.ts` | Edit / Write | feedback メモリ保存時に適用スコープの再配置判断 (hook 化提案 / repo 配置 / メモリ維持) を注入 |
| `task-contract-trigger.ts` | prompt.submit | 開放的依頼の語彙を検知し task-contract スキルの発動を指示 |
| `reset-restack-hint.ts` | prompt.submit | reset / 積み直し系の依頼で「破壊的操作をせずコミットを積み直せ」と注入 |
| `gh-stack-help.ts` | prompt.submit | スタック PR 関連の依頼で gh の help をセッション 1 回だけ注入 |

## 開発メモ

- 検証 3 段: `claude plugin validate <dir>` / `cd .claude/mods && biome check <dir>` / `npx -y -p typescript tsc -p tsconfig.json --noEmit`
- 型生成: `claude -p "/plugin-types .claude/mods/types"` (`types/` と `node_modules/` は gitignore)
- biome はリポジトリルートから実行すると nested root エラーになるため、この `mods/` ディレクトリから実行する
- 同一イベントの matcher なし重複登録はエンジンに拒否されるため、イベント登録は各 Mod の `index.ts(x)` に束ねる
- 自前登録ツールや `Artifact` 等、生成型の tool union に無いツールの `tool.call` matcher は RegExp で書く
- ブランチの移動・作成を機械的に止めるガードは置かない。ship フロー中や open PR ありの移動を禁じる ship-branch-lock は、worktree や段の移動を多用する運用の妨げになったため撤去した
- `--plugin-dir` で読み込んだ Mod には、エンジンが `.claude-plugin/types/` に型定義を生成する (自前の `.gitignore` 付き)。biome.json で対象から外している
- autopilot は Stop hook ではなく `turn.complete` → `$.prompt.submit` で次のターンを起こす。起床の経路を pr-watch と揃え、Esc による中断を `reason` で見分けて一時停止にするため。コマンドやツールの処理中に submit すると届かないことがあったので、`$.clock.after(0)` で処理を抜けてから送る
- autopilot の指示文 (確認を挟まずに進める等) を書き換える変更は、auto mode の判定器に拒否されることがある。manual モードに切り替え、ユーザーの承認を受けながら編集する
