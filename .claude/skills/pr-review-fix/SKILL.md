---
name: pr-review-fix
description: "GitHub Pull Request のレビューコメントに一括対応する時に使う。トリガー: 「PR レビュー直して」「レビューコメント対応」「レビューフィードバック反映」「PR の指摘対応」「PR #123 のコメント対応」「review fix」「apply PR review」「address PR feedback」等のユーザー指示、または `/pr-review-fix` スラッシュコマンド、`pr-review-fix` スキル指定。未解決 (isResolved=false) スレッドを網羅収集 → 分類 → 承認付き修正計画 → 実装コミット → push → 返信 & resolve まで 7 フェーズで一気通貫。"
---

# pr-review-fix

現在のブランチに紐づく PR の **未解決 (unresolved) レビューコメント** を全件集約し、
分類 → 計画 → ユーザー承認 → 実装 → コミット → push → 返信 + resolve まで 7 フェーズで進める。

## 前提

- 現在のブランチに PR が紐づいていない場合は即座に作業終了する。
- GitHub の「Resolve conversation」で閉じたスレッドは **既に対応済み** と見なし、以降のすべてのフェーズから除外する。判定は GraphQL の `reviewThreads.isResolved == false` を基準にする (REST `/pulls/{N}/comments` には `isResolved` フィールドが無いため単独判定不可)。
- スキルディレクトリは `~/.claude/skills/pr-review-fix/` で、配下に `scripts/` と `references/` を持つ。スクリプトは常に絶対パス `~/.claude/skills/pr-review-fix/scripts/<name>.sh` で呼び出す (Claude の cwd は通常プロジェクトルートなので相対パスは不可)。
- 依存: `gh` CLI (authenticated、v2.4.0+ 推奨)、`git`。`jq` は不要 (`gh api --jq` の内蔵 gojq を使用)。

## ワークフロー (7 Phase)

### Phase 1 — 未解決レビュースレッド収集

`fetch_unresolved_threads.sh` を実行して `isResolved == false` の review thread を **NDJSON (1 行 1 thread)** で取得する。fork PR の base repository を自動参照し、`gh api --paginate` で 100 件超の大 PR も全ページ取得する。

```bash
~/.claude/skills/pr-review-fix/scripts/fetch_unresolved_threads.sh               # 現ブランチの PR を自動検出
~/.claude/skills/pr-review-fix/scripts/fetch_unresolved_threads.sh <pr_number>   # PR 番号を明示
```

出力 (NDJSON, 1 行 = 1 thread) の各行から以下を抜き出し **対応表 (通し番号 ↔ thread_id / comment_id / path / line / body / author)** を作る:

- `.id` → thread_id (`PRRT_...` 形式、Phase 7 の resolve に使う)
- `.comments.nodes[].databaseId` → comment_id (Phase 7 の返信に使う)

**対応表の永続化** (必須):

コメント数が多い / context が長くなる場合に備え、対応表をプロジェクトの `outputs/pr-review-fix/pr-<N>-mapping.json` に書き出す。Claude は context が切れても再開できる。

```bash
mkdir -p outputs/pr-review-fix
~/.claude/skills/pr-review-fix/scripts/fetch_unresolved_threads.sh <pr_number> \
  > outputs/pr-review-fix/pr-<pr_number>-threads.ndjson
```

その後 Claude が以下のスキーマで `pr-<N>-mapping.json` を作成・維持する:

```json
[
  {"seq": 1, "thread_id": "PRRT_...", "comment_id": 123, "path": "src/a.py", "line": 42,
   "classification": "🔴", "category": "アーキテクチャ", "author": "reviewer1",
   "body_summary": "...", "fix_plan": "...",
   "commit_hash": null, "replied": false, "resolved": false}
]
```

Phase 6 でコミットするたび `commit_hash` を、Phase 7 で返信・resolve するたび `replied` / `resolved` を更新する。利用する各プロジェクトで `outputs/` を `.gitignore` に含めて、これらの生成ファイルが誤って commit されないようにする。

補助的に以下も見てよい (判断材料ではなく概要把握):

- `gh pr view --comments` — PR 全体の概要
- `gh api repos/{owner}/{repo}/pulls/{N}/reviews` — レビュー本体サマリー
- `gh api repos/{owner}/{repo}/issues/{N}/comments` — PR 一般コメント (resolve 概念なし、全件対象)

### Phase 2 — 分類

各コメントに対して、以下 2 軸で分類する。詳細タクソノミーは [`references/classification.md`](references/classification.md) を参照。

1. **対応方針**: 🔴 必須 / 🟡 推奨 / 🟢 質問・議論
2. **カテゴリー**: 仕様適合性 / コーディングルール / パフォーマンス / アーキテクチャ / テスト品質 / エラーハンドリング / 可読性・保守性

### Phase 3 — 修正計画の立案

深く考え (ultrathink) 修正計画を作り、ユーザーに提示する。テンプレートとセルフチェックリストは [`references/plan_template.md`](references/plan_template.md) を参照。

**必須ルール**:
- 修正対象は 🔴 と 🟡 のみ。🟢 は計画対象外。
- **全ての表は対応方針の降順 (🔴 > 🟡 > 🟢) → 収集順 (stable) でソートして表示する**。通し番号 `#` はソート後に 1 から振り、以降 Phase 6 / Phase 7 でも同じ番号で参照する (表示順 = 処理順 = 重要度順)。

### Phase 4 — 計画品質チェック

[`references/plan_template.md`](references/plan_template.md) の「Phase 4 セルフチェックリスト」を **内部で** 実行し、80% 以上満たすまで Phase 5 に進まない。**チェックリストの実行結果はユーザーに出力しない** (内部判定のみ)。

### Phase 5 — ユーザー承認

計画を提示し、以下を確認する。**承認を得るまで Phase 6 に進まない。**

- 修正方針に問題がないか
- 優先順位が適切か
- 追加で考慮すべき点がないか

**リトライフロー**: ユーザーが差し戻し (方針変更・優先度変更・追加の検討事項・分類変更) を指示した場合は **Phase 3 に戻って計画を再作成** し、Phase 4 セルフチェック → Phase 5 再提示を繰り返す。承認を得られるまでこのループ。差し戻し内容を `outputs/pr-review-fix/pr-<N>-mapping.json` の該当エントリの `fix_plan` に反映させる。

### Phase 6 — 実装

ユーザー承認後:

1. ブランチ状態・依存関係・計画を再確認。
2. 通し番号順に修正実施。論理単位でコミットを分割する。
3. コミットメッセージには修正内容を記載。**コミット直後に対応表 (`outputs/pr-review-fix/pr-<N>-mapping.json`) の該当エントリに `commit_hash` (完全 SHA) を書き込む**。
4. lint / typecheck / test を実行してグリーンを確認。
5. `git push` でリモート反映。

> **注意**: push 前に resolve するとコミットが GitHub に未到達で返信リンクが壊れる可能性がある。
> 必ず push 後に Phase 7 に進む。

**非コード修正のパターン**:

PR description の修正など、コミットを作らずに対応する場合の典型:

```bash
# 現在の body を取得 → 編集 → 書き戻し
gh pr view <pr_number> --json body -q .body > /tmp/pr_body.md
# $EDITOR /tmp/pr_body.md  または sed/awk 等で編集
gh pr edit <pr_number> --body-file /tmp/pr_body.md
```

対応表では `commit_hash` を `null` のままにし、代わりに `fix_plan` に "PR description 更新 (kv=6_000 に合わせた)" 等の説明を残す。Phase 7 の返信本文は `"PR description を更新しました。"` のような non-SHA 文で渡す。

### Phase 7 — 返信 & resolve

対応表の各エントリについて以下を実施。

#### 1. 固定フォーマットで返信 (日本語)

`scripts/reply_to_comment.sh` は本文末尾に **Claude Code 署名行を必ず自動付加する** ので、呼び出し側は本文 1 文 (日本語) だけ渡す。これにより全コメントへの返信が同一フォーマットになり、人間の直レビューと一目で区別できる。

本文は **次の 2 パターンのみ** 使う。

| ケース | 本文 (body) の形 | 例 |
|--------|---------------|---|
| A: 新規コミットで修正 | `<FULL_SHA> で修正しました。` | `abc1234567890abcdef1234567890abcdef12345678 で修正しました。` |
| B: 非コード修正 (PR description 更新 / 既存コミット流用など) | 日本語 1 文 | `PR description を更新しました。` / `<FULL_SHA> で既に対応済みです。` |

- **完全 SHA (40 文字、バッククォート無し)** で書く。GitHub UI が自動でコミットリンクに整形する。短縮形は不可。
- 複数コミットに跨る場合は読点区切り: `<SHA1>、<SHA2> で修正しました。`
- 完全 SHA は `git rev-parse HEAD` / `git log --format=%H -1` で取得。

```bash
~/.claude/skills/pr-review-fix/scripts/reply_to_comment.sh <comment_id> "<FULL_SHA> で修正しました。"
```

実際に投稿される本文 (スクリプトが自動で署名 (英語) を付加):

```
abc1234567890abcdef1234567890abcdef12345678 で修正しました。

---
🤖 Replied by [Claude Code](https://claude.com/claude-code) via `pr-review-fix` skill
```

#### 2. スレッドを resolve

```bash
~/.claude/skills/pr-review-fix/scripts/resolve_thread.sh <thread_id>
```

#### 3. 処理ポリシー

- 🔴 / 🟡 を実装・コミットしたコメント: 返信 + resolve
- 🟢 質問・議論: 返信のみ (resolve しない) またはスキップ。回答が必要な場合は事前にユーザーに確認。
- 既に `isResolved: true` のスレッドは再 resolve しない。
- コード変更を伴わない修正 (PR description 更新・既存コミットで対応済み等) でも、返信に対応コミットの SHA / 説明を入れて resolve する。
- 返信 or resolve に失敗した場合はエラーを報告し、残りの処理は継続。
- 各処理後に `outputs/pr-review-fix/pr-<N>-mapping.json` の該当エントリの `replied` / `resolved` を `true` に更新 (context 切れ時の再開用)。
- body に `` ` ``・`$(...)`・バックスラッシュ等のシェル特殊文字を含めたい場合は stdin モードを使う:
  ```bash
  printf '%s' "<body>" | ~/.claude/skills/pr-review-fix/scripts/reply_to_comment.sh <comment_id> -
  ```

#### 4. 完了報告

[`references/plan_template.md`](references/plan_template.md) の「Phase 7 完了報告テーブル」でユーザーに提示する。先頭列に Phase 3 と同じ通し番号を必ず付ける。

## トラブルシューティング

- **PR が見つからない**: `gh pr view` で紐付け確認。無ければスキル終了。
- **返信 API が 422**: `comment_id` が top-level か確認 (既に返信スレッド内のコメント ID に対しては `in_reply_to` できない場合がある — その場合はスレッドの先頭コメント ID を使う)。
- **resolve が 403**: ログイン中のアカウントにリポジトリへの triage 以上の権限があるか確認。
- **古い情報が必要**: Web 情報を参照する場合は 2026 年 1 月以降の最新情報を参照する。
