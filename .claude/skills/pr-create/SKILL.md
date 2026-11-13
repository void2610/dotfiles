---
name: pr-create
description: "GitHub Pull Request を作成する時に使う。トリガー: 「PR 作って」「PR 作成」「プルリクエスト作って」「create PR」「open PR」「raise PR」等のユーザー指示、または `pr-create` スキル指定。コミット済みブランチから push 確認 → タイトル / 本文案の提示 → `gh pr create` 実行 → Copilot レビュー依頼 → 到着をバックグラウンド監視し、指摘があれば pr-review-fix へ自動接続するまでを一気通貫。コミット作成自体は担当せず、事前に commit スキル等で済ませておく前提。"
---

# pr-create

現在のブランチに積まれたコミットから GitHub Pull Request を作成するスキル。
コミット作成は担当せず、push 確認 → タイトル / 本文生成 → PR 作成までを行う。
問題がない限り、ユーザー確認は挟まず全自動で進める。

## 前提

- 現ブランチに **PR に載せるコミットが 1 件以上** 積まれていること。無い場合は「PR に含めるコミットがありません」と伝えて終了
- 現ブランチに **既に PR が存在** する場合 (`gh pr view` で検出) は新規作成せず、**既存 PR の タイトル・説明に現状コードベースを反映する**
- 作業ツリーが汚れている (未コミットの変更がある) 場合はユーザーに扱いを確認 (コミットするか stash するか)
- 依存: `gh` CLI (authenticated)、`git`

## ワークフロー (6 Phase)

### Phase 1 — 事前チェック

```bash
git status --short                                           # 未コミット変更の有無
git rev-parse --abbrev-ref HEAD                              # 現ブランチ名
gh pr view --json number,url 2>/dev/null                     # 既存 PR の検出
git log --oneline "$(git merge-base HEAD @{u} 2>/dev/null || git merge-base HEAD origin/HEAD)"..HEAD
                                                             # PR に載るコミット一覧
```

- 既存 PR あり → タイトル・説明の更新作業に
- コミットが 0 件 → 終了
- 作業ツリーが汚れている → ユーザーに確認

### Phase 2 — push

push スキルで現ブランチを push する。

### Phase 3 — タイトル・本文の生成

コミットログを読み取ってタイトルと本文を生成する。

**タイトル** (日本語、50 文字程度):
- コミットメッセージの規約 (`feat:` / `fix:` / `docs:` / `refac:` / `chore:` / `style:` / `test:`) を踏襲
  - タイトルのprefixは必ず上記7種類のどれかを用いる。 refactor(frontend): 等のprefix改変、スコープ記述は認められない
- 句点なし、曖昧語 (`いろいろ修正` 等) は避ける
- **単一コミット**: その件名をそのまま流用(英語or曖昧な場合は別途日本語のタイトルを考える)
- **複数コミット**: ブランチ全体の目的を集約して 1 件に要約

#### 本文の構成 (必ずこの順で判定する)

**Step 3-A — リポジトリの PR テンプレートを必ず先に検出する**。default テンプレートにフォールバックする前に **必ず** 以下を実行する。スキップ禁止。

```bash
# GitHub が認識する標準パスを全て確認 (大小文字・場所違いを網羅)
for p in \
    .github/pull_request_template.md \
    .github/PULL_REQUEST_TEMPLATE.md \
    docs/pull_request_template.md \
    docs/PULL_REQUEST_TEMPLATE.md \
    pull_request_template.md \
    PULL_REQUEST_TEMPLATE.md; do
  [ -f "$p" ] && echo "FOUND: $p" && break
done
# 複数テンプレート (`.github/PULL_REQUEST_TEMPLATE/*.md`) もありうる
ls .github/PULL_REQUEST_TEMPLATE/ 2>/dev/null
```

**Step 3-B** — Step 3-A でテンプレートが見つかった場合:

1. テンプレートファイルを `Read` ツール等で **必ず内容を読む**
2. 各セクション (`##` 見出し / `<!-- コメント指示 -->` / チェックボックス) を **そのまま維持**
3. テンプレートが要求する情報をコミットログから抽出して埋める
4. テンプレート由来のセクションを削除・改名しない。コメント指示 (`<!-- ... -->`) はそのまま残してよい
5. 不明 / 該当無しのセクションは `- 該当なし` 等で空欄を埋める (削除しない)

**Step 3-C** — Step 3-A で **何も見つからなかった場合のみ**、default テンプレートを使う。詳細は [`references/default_template.md`](references/default_template.md) を参照 (本 SKILL.md にはあえて inline で載せない。フォールバックである旨を明示するため)。

#### 本文の書き方

リポジトリテンプレートの有無にかかわらず、常に以下にしたがって本文を推敲する
- **概要**: Why を 1行で書く。コードから読める What の冗長説明は書かない
- **変更点**: 
  - コミット、ファイル単位ではなく、わかりやすい機能単位で分割する。
  - コードを読めばわかる具体名は極力書かない。 
  - 悪い例: 旧 `experiments/sim2real/utils/action_dr.py` を削除し、engine (`LowFreqNoiseInjector` / `dagger_offset_approach_iter` / `sample_duration_scale` / `sample_ee_perturbation` / `taper_weight`) を `polaris/dr/motion_noise.py` に移設
  - 良い例: DR関連のutil関数を正しい場所へ移設
- **動作確認**: 簡潔に 2〜3 項目程度まで。実行者が実際に確認する最低限に絞り、網羅リストにしない
- **画像・動画**: 画面・描画・ロボットの動きなど見た目で確かめたものは、撮ったスクリーンショットや動画を本文に貼る (2026-11-09「prに画像をはれ」)。手元に撮った画像があるのに文章だけで「出ることを確かめた」と書かない。本文には `![<何の画面か>](./<file>)` で置き、Phase 4 の `--attach` で上げる


### Phase 4 — PR 作成

`gh pr create` を HEREDOC で呼び出す (改行・Markdown を安全に渡すため)。`CLAUDE_GIT_SKILL=pr-create` を前置しないと PreToolUse hook にブロックされる。

```bash
CLAUDE_GIT_SKILL=pr-create gh pr create --title "<承認済みタイトル>" --body "$(cat <<'EOF'
## 概要
...

## 変更点
- ...

## 動作確認
- [ ] ...
EOF
)"
```

画像・動画は `gh` の `--attach` で上げる (gh 2.99 以降。`gh pr create` / `gh pr edit` / `gh pr comment` にある)。本文の `![alt](./before.png)` と同じパスを `--attach './before.png#<alt>'` で渡すと、gh がアップロード先の URL に書き換える。本文に参照が無いファイルは末尾に足される。1 回に 50 ファイルまで。gh は相対パスをカレントディレクトリから解決するので、画像のあるディレクトリで実行するか、本文と `--attach` のパスをそろえる。

```bash
cd <画像のあるディレクトリ> && CLAUDE_GIT_SKILL=pr-create gh pr create --title "..." --body-file /tmp/body.md \
  --attach './live.png#live の表示' --attach './replay.png#replay の表示'
```

オプション (ユーザー指示があった時のみ追加):

- `--draft` — draft PR として作成
- `--reviewer <user>[,<user>...]` — レビュアー指定
- `--base <branch>` — base ブランチを明示 (省略時はリポジトリのデフォルトブランチ)
- `--assignee <user>` — アサイン指定

### Phase 5 — Copilot レビュー依頼 (必須・毎回)

CI とレビュー到着の監視は **pr-watch Mod (`~/.claude/mods/pr-watch`) が常駐で担う**ため、pr-create からの監視起動は不要。Mod が 60 秒おき (CI が通り Copilot レビューの未解決スレッドも無い PR は 5 分おき、push・コミットで HEAD か upstream が変わったときは即時) に現在ブランチの OPEN PR を見て、CI fail / レビュー到着時に prompt 自動投入でセッションを起こす。

PR 作成直後、付属スクリプトで GitHub Copilot を PR レビュアーに登録する。**省略禁止**。

```bash
bash "$HOME/.claude/skills/pr-create/scripts/request-copilot-review.sh" <PR番号> [lite|balanced|max|auto]
```

スクリプト本体: `~/.claude/skills/pr-create/scripts/request-copilot-review.sh`

- 内部で Copilot 専用の `requestCopilotCodeReview` mutation を呼ぶ。既に依頼済みのレビュアー (CODEOWNERS・`--reviewer`) は外れない。第 2 引数でレビューの強さ (`reviewEffort`) を選べ、省略時はリポジトリ・組織の既定
- Copilot レビュー機能未有効・既に依頼済み・権限不足などで失敗する場合があるが、**PR 作成自体は成功している**ので終了コード 1 でも警告扱いとし、ユーザーには「Copilot 依頼に失敗 (理由)」と PR URL の両方を伝える。理由は `failureReason` (`NO_QUOTA_REMAINING`・`REQUEST_CONFLICT` 等) で出る
- 依頼が通っても、枠が足りないと Copilot が「insufficient remaining quota … Try requesting a review at a lower effort level」の COMMENTED レビューを返すことがある。そのときは `lite` を付けて頼み直す (2026-11-09、lerobot-akari #8 で既定の強さが 2 回枠不足になり、`lite` では 3 分ほどでレビューが届いた)

### Phase 6 — 完了報告

作成された PR URL・Copilot 依頼結果を報告していったん終了 (監視は pr-watch Mod が常駐)。

```
✅ PR #<N> を作成しました: <URL>
✅ Copilot にレビューを依頼しました (CI / レビュー到着は pr-watch Mod が監視中)
```

(Copilot 依頼が失敗した場合は ⚠️ で警告のみ表示する)

### Phase 7 — pr-watch Mod からの起床時の自動対応

pr-watch Mod は CI fail / レビュー到着を検知すると、指示文を prompt として自動投入しセッションを起こす。投入された指示に従って動く:

- **CI fail 起床** → `gh pr checks <N>` で失敗原因を確認・修正して push (レビュー指摘対応と重なる場合はまとめて対応してよい)。ship フローの最中は CI が fail のままだと `ship.sh done review` が通らない。再監視は Mod が継続する
- **レビュー到着起床 (未解決 > 0)** → **pr-review-fix スキルを起動**して対応を開始する (修正計画の承認は pr-review-fix 内のフローが担うため、起動自体に確認は不要)。ship フローの最中なら先に `ship.sh done review` を打つ (CI が未完 / fail だと通らない点に注意)
- 未解決 0 件は toast 通知のみで起床しない。未解決数が `?` (取得失敗) の場合は `fetch_unresolved_threads.sh` を手動実行して確認してから判断する (0 件と誤認しない)

## トラブルシューティング

- **既に PR が存在**: 新規作成せず既存 PR URL を返す。タイトル / 本文の更新が必要なら `gh pr edit <N> --title/--body-file` で対応
- **push 失敗 (403 等)**: `gh auth status` / `git remote -v` で認証と remote を確認
- **作成後にタイトル / 本文を直したい**: `gh pr edit <N> --title "..."` または `gh pr edit <N> --body-file /tmp/body.md`
- **作成後に画像を足したい**: `gh pr edit <N> --body-file /tmp/body.md --attach './x.png#<alt>'` (本文に `![alt](./x.png)` を置いた位置に入る)。本文を渡さなければ今の本文の末尾に足される
- **draft ↔ ready の切り替え**: `gh pr ready <N>` / `gh pr ready --undo <N>`
