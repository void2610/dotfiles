---
name: pr-create
description: "GitHub Pull Request を作成する時に使う。トリガー: 「PR 作って」「PR 作成」「プルリクエスト作って」「create PR」「open PR」「raise PR」等のユーザー指示、または `pr-create` スキル指定。コミット済みブランチから push 確認 → タイトル / 本文案の提示 → ユーザー承認 → `gh pr create` 実行 → URL 報告までを一気通貫。コミット作成自体は担当せず、事前に commit スキル等で済ませておく前提。"
---

# pr-create

現在のブランチに積まれたコミットから GitHub Pull Request を作成するスキル。
コミット作成は担当せず、push 確認 → タイトル / 本文生成 → 承認 → PR 作成までを行う。

## 前提

- 現ブランチに **PR に載せるコミットが 1 件以上** 積まれていること。無い場合は「PR に含めるコミットがありません」と伝えて終了
- 現ブランチに **既に PR が存在** する場合 (`gh pr view` で検出) は新規作成せず、既存 PR の URL を返して終了
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

- 既存 PR あり → URL を出して終了
- コミットが 0 件 → 終了
- 作業ツリーが汚れている → ユーザーに確認

### Phase 2 — push

```bash
# upstream 未設定の初回 push
git push -u origin HEAD

# upstream 設定済みでローカルが先行
git push
```

push 失敗時は `gh auth status` と `git remote -v` を確認してユーザーに報告。

### Phase 3 — タイトル・本文の生成 → ユーザー承認

コミットログを読み取ってタイトルと本文の **案を生成し、ユーザーに提示して承認を得る**。

**タイトル** (日本語、50 文字程度):

- コミットメッセージの規約 (`feat:` / `fix:` / `docs:` / `refac:` / `chore:` / `style:` / `test:`) を踏襲
- **単一コミット**: その件名をそのまま流用
- **複数コミット**: ブランチ全体の目的を集約して 1 件に要約
- 句点なし、曖昧語 (`いろいろ修正` 等) は避ける

**本文テンプレート** (日本語):

```markdown
## 概要
<なぜこの変更が必要か、1〜3 行で>

## 変更点
- <主要な変更点を箇条書き>

## 動作確認
- [ ] <実際に行う確認項目>
```

- **概要**: Why を 1〜3 行。コードから読める What の冗長説明は書かない
- **変更点**: コミット単位 or 機能単位で主要変更を箇条書き。数個までに絞る
- **動作確認**: **簡潔に 2〜3 項目程度まで**。実行者が実際に確認する最低限に絞り、網羅リストにしない

承認フローでユーザーが修正を指示したら案を更新して再提示。承認を得るまで Phase 4 に進まない。

### Phase 4 — PR 作成

`gh pr create` を HEREDOC で呼び出す (改行・Markdown を安全に渡すため)。

```bash
gh pr create --title "<承認済みタイトル>" --body "$(cat <<'EOF'
## 概要
...

## 変更点
- ...

## 動作確認
- [ ] ...
EOF
)"
```

オプション (ユーザー指示があった時のみ追加):

- `--draft` — draft PR として作成
- `--reviewer <user>[,<user>...]` — レビュアー指定
- `--base <branch>` — base ブランチを明示 (省略時はリポジトリのデフォルトブランチ)
- `--assignee <user>` — アサイン指定

### Phase 5 — Copilot レビュー依頼 (必須・毎回)

PR 作成直後、付属スクリプトで GitHub Copilot を PR レビュアーに登録する。**省略禁止**。

```bash
bash "${CLAUDE_PROJECT_DIR:-$HOME}/.claude/skills/pr-create/scripts/request-copilot-review.sh" <PR番号>
```

スクリプト本体: `~/.claude/skills/pr-create/scripts/request-copilot-review.sh`

- 内部で `gh api graphql` の `requestReviews` mutation を `botIds` 付きで呼び、Copilot PR Reviewer (固定 bot ノード `BOT_kgDOCnlnWA`) を依頼する
- Copilot レビュー機能未有効・既に依頼済み・権限不足などで失敗する場合があるが、**PR 作成自体は成功している**ので終了コード 1 でも警告扱いとし、ユーザーには「Copilot 依頼に失敗 (理由)」と PR URL の両方を伝える

### Phase 6 — 完了報告

作成された PR URL と Copilot 依頼結果を表示して終了。以降のレビュー対応は `pr-review-fix` スキルに委ねる。

```
✅ PR #<N> を作成しました: <URL>
✅ Copilot にレビューを依頼しました
```

(Copilot 依頼が失敗した場合は ⚠️ で警告のみ表示し、PR 作成成功は維持する)

## トラブルシューティング

- **既に PR が存在**: 新規作成せず既存 PR URL を返す。タイトル / 本文の更新が必要なら `gh pr edit <N> --title/--body-file` で対応
- **push 失敗 (403 等)**: `gh auth status` / `git remote -v` で認証と remote を確認
- **作成後にタイトル / 本文を直したい**: `gh pr edit <N> --title "..."` または `gh pr edit <N> --body-file /tmp/body.md`
- **draft ↔ ready の切り替え**: `gh pr ready <N>` / `gh pr ready --undo <N>`
