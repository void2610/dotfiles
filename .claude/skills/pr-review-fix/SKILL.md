# PR レビューコメント修正コマンド

## 目的
あなたはPull Requestのレビューコメントを網羅的に確認しコードを修正するAIアシスタントです。
現在のブランチ紐づいているPR情報を取得し詳細な計画を作り、コードを修正し、修正内容を報告してください。

## 重要な注意事項
- 必要に応じてWEBの情報を参照してください。なお参照する場合は2026年1月時点最新の情報を参照しましょう
- 現在のブランチにPRが紐づいてない場合はここで作業を終了してください

---
## Pull Request 修正手順

### Phase 1: コメント情報の収集
1. `gh pr view --comments` でPRの詳細とコメントを取得
2. `gh api repos/{ORGANIZATION}/{CURRENT_REPO}/pulls/{PR_NUMBER}/comments` で詳細なコメントデータを取得（`id` = review comment の `databaseId` を必ず保持）
3. `gh api repos/{ORGANIZATION}/{CURRENT_REPO}/pulls/{PR_NUMBER}/reviews` でレビューコメントを取得
4. 必要に応じて `gh api repos/{ORGANIZATION}/{CURRENT_REPO}/issues/{PR_NUMBER}/comments` で一般コメントも確認
5. GraphQL で review thread の ID を取得し、各 comment がどの thread に属するかマッピングを作成する（Phase 7 の resolve に必要）

```bash
gh api graphql -F owner='{ORGANIZATION}' -F repo='{CURRENT_REPO}' -F number={PR_NUMBER} -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          comments(first: 20) { nodes { databaseId body path } }
        }
      }
    }
  }
}'
```

上記の `nodes[].id` が thread ID（`PRRT_xxx` 形式）、`comments.nodes[].databaseId` が review comment ID。コメント修正後にこの対応表を使って返信 & resolve する。

### Phase 2: コメント分析と分類
収集したコメントを以下の観点で分析してください：

1. **コメントの分類**
   - 🔴 必須修正項目（blocking issues）
   - 🟡 推奨修正項目（suggestions）
   - 🟢 質問・議論項目（questions/discussions）

2. **技術的重要度**
   - 🚨 クリティカル（システム障害リスク）
   - 🔥 高（本番環境への影響大）
   - 📈 中（品質・保守性への影響）
   - 📝 低（スタイル・可読性）
   - 🎯 改善提案（将来的な拡張性）

3. **カテゴリー**
   - **仕様適合性に関する指摘**
      - 要件定義との整合性
      - 既存機能の仕様
      - 受け入れ条件
   - **コーディングルールに関する指摘**
      - `docs/`との整合性
      - 命名規則の統一性
      - インデント・フォーマット
   - **パフォーマンスに関する指摘**
      - メモリ使用量の最適化
      - データベースクエリの効率性
      - API呼び出しの最適化
      - キャッシュ戦略
   - **アーキテクチャに関する指摘**
      - 類似実装との統一性
      - 過去意思決定(ADR)との整合性
      - 依存関係の方向性
      - デザインパターンの適用
   - **テスト品質に関する指摘**
      - テストカバレッジの妥当性
      - テストケースの網羅性
      - モックの適切性
      - テストの可読性・保守性
   - **エラーハンドリングに関する指摘**
      - 例外処理の適切性
      - エラーメッセージの明確性
      - ログ出力の妥当性
      - 復旧可能性の考慮
   - **可読性・保守性に関する指摘**
      - コードの自己文書化
      - コメントの適切性
      - 関数・クラスの責務分離
      - 複雑度の管理


### Phase 3: 修正計画の立案

**重要**
- 分析結果について深く考え(ULTRATHINK)、修正計画を作成してください
- 分類されたコメントのうち修正するのは`必須修正項目`と`推奨修正項目`の2つのみでお願いします。

```markdown
# PR #{PR_NUMBER} 修正計画

## 📋 コメント一覧
| コメントの分類 | カテゴリー | ファイル | 内容 | レビュアー |
|--------|------------|----------|------|-----------|
| 🔴 | Code Quality | src/main.js:15 | 変数名をより具体的に | @reviewer1 |
| 🟡 | Performance | src/api.js:42 | キャッシュ機能の追加検討 | @reviewer2 |

## 🎯 修正方針
### 必須修正項目（Phase 1）
- [ ] 項目1: 詳細な修正内容
- [ ] 項目2: 詳細な修正内容

### 推奨修正項目（Phase 2）
- [ ] 項目1: 詳細な修正内容
- [ ] 項目2: 詳細な修正内容

## 📅 実装順序
1. 必須修正項目の実装
2. 推奨修正項目の実装
3. テスト実行・検証
4. プッシュ・レビュー依頼

## ⚠️ 注意事項
- 質問・議論項目に分類されたものは計画不要です
- 修正により既存機能に影響がないか確認
- テストが全て通ることを確認
- 依存関係の変更がある場合は慎重に検討
`​``

### Phase 4: 計画品質のチェック
- [ ] PR上の全コメントを参照している
- [ ] 全コメントが「必須修正項目」「推奨修正項目」「質問・議論項目」の3つに分類されている
- [ ] コメントの内容が分析されている
- [ ] 具体的で明確な修正方針が作成されている

計画の80%がチェックされている状態になるまで次のフェーズに進まないでください。

### Phase 5: ユーザー確認
`修正計画`を提示し、以下を確認してください：
- 修正方針に問題がないか
- 優先順位が適切か
- 追加で考慮すべき点がないか

**この段階で必ずユーザーの承認を得てから次のPhaseに進んでください。**

### Phase 6: 実装実行
ユーザーの承認後、以下の手順で実装を行ってください：

#### 1. 事前準備
- 現在のブランチの状態確認
- 依存関係の確認
- 計画の確認

#### 2. 修正実装
- 優先度順に修正を実施
- 各修正後にコミットを作成
- コミットメッセージにはPR番号と修正内容を記載
- **コミット直後に、そのコミットが対応するレビューコメントの `commit_hash` と `comment_id` / `thread_id` を記録しておく**（Phase 7 で使用）

#### 3. 最終確認
  - 全ての必須項目が完了していることを確認
  - `git push` でリモートへ反映（push 前に resolve するとコミットが GitHub 側に未到達で返信リンクが壊れる可能性があるため、push 後に Phase 7 を実行）

### Phase 7: レビューコメントへの返信と resolve

各修正済みコメントについて、以下を実施してください：

#### 1. 修正コミットハッシュを返信
対応する review comment に対し、`in_reply_to` で返信スレッドを作成します。ハッシュは **完全な形（40 文字）** で書くこと。完全な SHA を書くと GitHub UI が自動的にコミットへのリンク付きテキストに整形してくれる（短縮形やバッククォート付きだとリンク化されない場合がある）。

```bash
gh api -X POST \
  repos/{ORGANIZATION}/{CURRENT_REPO}/pulls/{PR_NUMBER}/comments \
  -F in_reply_to={COMMENT_ID} \
  -f body="{FULL_HASH}"
```

返信本文は完全なコミットハッシュ（40 文字、バッククォートで囲まない）のみ。複数コミットに跨る場合は全 SHA を改行区切りで列挙します。完全 SHA は `git rev-parse HEAD` や `git log --format=%H -1` で取得できます。

#### 2. review thread を resolve
Phase 1 で取得した `thread_id` を使い、GraphQL で resolve します。

```bash
gh api graphql -F threadId='{THREAD_ID}' -f query='
mutation($threadId: ID!) {
  resolveReviewThread(input: {threadId: $threadId}) {
    thread { id isResolved }
  }
}'
```

#### 3. 処理ポリシー
- **必須修正項目 / 推奨修正項目** を実装しコミットしたコメントのみ返信 + resolve
- **質問・議論項目** は返信のみ（resolve しない）またはスキップ。回答が必要な場合はユーザーに確認
- 既に `isResolved: true` のスレッドは再 resolve しない
- 返信 or resolve に失敗した場合はエラーを報告し、残りの処理を継続

#### 4. 完了報告
すべての対象コメントについて、以下の表をユーザーに提示してください：

| comment_id | ファイル:行 | 修正コミット | 返信 | resolve |
|------------|-----------|-----------|------|---------|
| 123456789  | src/main.js:15 | abc1234 | ✅ | ✅ |
