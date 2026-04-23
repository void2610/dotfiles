---
name: pr-review-fix
description: "Pull Request の未解決レビューコメントを網羅的に取り込み、修正計画 → ユーザー承認 → 実装 → 返信 & resolve まで一気通貫で対応する。GitHub PR のレビュー対応、「レビューを直して」「コメントに対応」「PR review fix」等に使う。"
---

# pr-review-fix

現在のブランチに紐づく PR の **未解決 (unresolved) レビューコメント** を全件集約し、
分類 → 計画 → ユーザー承認 → 実装 → コミット → push → 返信 + resolve まで 7 フェーズで進める。

## 前提

- 現在のブランチに PR が紐づいていない場合は即座に作業終了する。
- GitHub の「Resolve conversation」で閉じたスレッドは **既に対応済み** と見なし、以降のすべてのフェーズから除外する。判定は GraphQL の `reviewThreads.isResolved == false` を基準にする (REST `/pulls/{N}/comments` には `isResolved` フィールドが無いため単独判定不可)。
- スキル起点ディレクトリは `${CLAUDE_SKILL_DIR:-$(dirname "$0")}` 相当で、配下に `scripts/` と `references/` を持つ。

## ワークフロー (7 Phase)

### Phase 1 — 未解決レビュースレッド収集

`scripts/fetch_unresolved_threads.sh` を実行して `isResolved == false` の review thread を JSON 配列で取得する。

```bash
scripts/fetch_unresolved_threads.sh               # 現ブランチの PR を自動検出
scripts/fetch_unresolved_threads.sh <pr_number>   # PR 番号を明示
```

出力の各要素から以下を抜き出し **対応表 (通し番号 ↔ thread_id / comment_id / path / line / body / author)** を作る:

- `nodes[].id` → thread_id (`PRRT_...` 形式、Phase 7 の resolve に使う)
- `nodes[].comments.nodes[].databaseId` → comment_id (Phase 7 の返信に使う)

補助的に以下も見てよい (判断材料ではなく概要把握):

- `gh pr view --comments` — PR 全体の概要
- `gh api repos/{owner}/{repo}/pulls/{N}/reviews` — レビュー本体サマリー
- `gh api repos/{owner}/{repo}/issues/{N}/comments` — PR 一般コメント (resolve 概念なし、全件対象)

### Phase 2 — 分類

各コメントに対して、以下 3 軸で分類する。詳細タクソノミーは [`references/classification.md`](references/classification.md) を参照。

1. **対応方針**: 🔴 必須 / 🟡 推奨 / 🟢 質問・議論
2. **技術的重要度**: 🚨 / 🔥 / 📈 / 📝 / 🎯
3. **カテゴリー**: 仕様適合性 / コーディングルール / パフォーマンス / アーキテクチャ / テスト品質 / エラーハンドリング / 可読性・保守性

### Phase 3 — 修正計画の立案

深く考え (ultrathink) 修正計画を作り、ユーザーに提示する。テンプレートとセルフチェックリストは [`references/plan_template.md`](references/plan_template.md) を参照。

**必須ルール**:
- 修正対象は 🔴 と 🟡 のみ。🟢 は計画対象外。
- **全ての表で先頭列に通し番号 `#` を付ける**。以降 Phase 6 / Phase 7 でも同じ番号で参照する。

### Phase 4 — 計画品質チェック

[`references/plan_template.md`](references/plan_template.md) の「Phase 4 セルフチェックリスト」を 80% 以上満たすまで Phase 5 に進まない。

### Phase 5 — ユーザー承認

計画を提示し、以下を確認する。**承認を得るまで Phase 6 に進まない。**

- 修正方針に問題がないか
- 優先順位が適切か
- 追加で考慮すべき点がないか

### Phase 6 — 実装

ユーザー承認後:

1. ブランチ状態・依存関係・計画を再確認。
2. 通し番号順に修正実施。論理単位でコミットを分割する。
3. コミットメッセージには PR 番号と修正内容を記載。**コミット直後に `<通し番号, commit_hash (完全 SHA), comment_id, thread_id>` を対応表に書き足す** (Phase 7 で使用)。
4. lint / typecheck / test を実行してグリーンを確認。
5. `git push` でリモート反映。

> **注意**: push 前に resolve するとコミットが GitHub に未到達で返信リンクが壊れる可能性がある。
> 必ず push 後に Phase 7 に進む。

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
scripts/reply_to_comment.sh <comment_id> "<FULL_SHA> で修正しました。"
```

実際に投稿される本文 (スクリプトが自動で署名 (英語) を付加):

```
abc1234567890abcdef1234567890abcdef12345678 で修正しました。

---
🤖 Replied by [Claude Code](https://claude.com/claude-code) via `pr-review-fix` skill
```

#### 2. スレッドを resolve

```bash
scripts/resolve_thread.sh <thread_id>
```

#### 3. 処理ポリシー

- 🔴 / 🟡 を実装・コミットしたコメント: 返信 + resolve
- 🟢 質問・議論: 返信のみ (resolve しない) またはスキップ。回答が必要な場合は事前にユーザーに確認。
- 既に `isResolved: true` のスレッドは再 resolve しない。
- コード変更を伴わない修正 (PR description 更新・既存コミットで対応済み等) でも、返信に対応コミットの SHA / 説明を入れて resolve する。
- 返信 or resolve に失敗した場合はエラーを報告し、残りの処理は継続。

#### 4. 完了報告

[`references/plan_template.md`](references/plan_template.md) の「Phase 7 完了報告テーブル」でユーザーに提示する。先頭列に Phase 3 と同じ通し番号を必ず付ける。

## トラブルシューティング

- **PR が見つからない**: `gh pr view` で紐付け確認。無ければスキル終了。
- **返信 API が 422**: `comment_id` が top-level か確認 (既に返信スレッド内のコメント ID に対しては `in_reply_to` できない場合がある — その場合はスレッドの先頭コメント ID を使う)。
- **resolve が 403**: ログイン中のアカウントにリポジトリへの triage 以上の権限があるか確認。
- **古い情報が必要**: Web 情報を参照する場合は 2026 年 1 月以降の最新情報を参照する。
