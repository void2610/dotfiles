---
name: gh-pr-review-fix
description: Review and address GitHub Pull Request review comments on the current branch. Use when Codex needs to inspect the PR tied to the current branch, collect review comments, classify them into required/suggested/questions, propose a concrete fix plan, wait for user approval, and then implement the approved fixes.
---

# GH PR Review Fix

Use this skill when the user wants Codex to fix PR review comments for the current branch.

## Workflow

1. Identify whether the current branch is associated with a GitHub Pull Request.
2. If no PR is associated, stop and report that there is nothing to process.
3. Collect all available PR comments and review data.
4. Analyze every collected comment and classify it.
5. Produce a repair plan and get user approval before making code changes.
6. After approval, implement the required and suggested fixes.
7. Verify the result and report what changed.

## Data Collection

Collect PR information with these commands:

```bash
gh pr view --comments
gh api repos/{ORGANIZATION}/{CURRENT_REPO}/pulls/{PR_NUMBER}/comments
gh api repos/{ORGANIZATION}/{CURRENT_REPO}/pulls/{PR_NUMBER}/reviews
```

Check issue comments too when they may contain actionable feedback:

```bash
gh api repos/{ORGANIZATION}/{CURRENT_REPO}/issues/{PR_NUMBER}/comments
```

Use web lookup only when local context or repository artifacts are not enough.

## Comment Analysis

Analyze every comment with these dimensions.

### Comment Class

- Required fix
- Suggested fix
- Question or discussion

Only required fixes and suggested fixes become implementation candidates.

### Technical Severity

- Critical
- High
- Medium
- Low
- Improvement

### Category

- Spec compliance
- Coding rules
- Performance
- Architecture
- Test quality
- Error handling
- Readability and maintainability

### Impact Scope

- Single file
- Multiple files
- Architecture change
- Dependency change
- Database schema change
- API contract change

## Plan Output

Think deeply before drafting the plan. Cover all collected comments and keep questions or discussions out of the implementation queue.

Use this format:

```markdown
# PR #{PR_NUMBER} 修正計画

## コメント一覧
| コメントの分類 | カテゴリー | ファイル | 内容 | レビュアー |
|--------|------------|----------|------|-----------|
| 🔴 | Code Quality | src/main.js:15 | 変数名をより具体的に | @reviewer1 |
| 🟡 | Performance | src/api.js:42 | キャッシュ機能の追加検討 | @reviewer2 |

## 修正方針
### 必須修正項目
- [ ] 項目1: 詳細な修正内容
- [ ] 項目2: 詳細な修正内容

### 推奨修正項目
- [ ] 項目1: 詳細な修正内容
- [ ] 項目2: 詳細な修正内容

## 実装順序
1. 必須修正項目の実装
2. 推奨修正項目の実装
3. テスト実行・検証
4. 必要ならコミット

## 注意事項
- 質問・議論項目に分類したものは計画に含めない
- 修正による既存機能への影響を確認する
- テストがある場合は実行する
- 依存関係変更は慎重に扱う
```

## Plan Quality Gate

Do not move on until the plan is good enough.

Check at least these points:

- All PR comments were reviewed
- Every comment was classified as required, suggested, or question/discussion
- The analysis explains why each actionable item matters
- The fix approach is concrete enough to implement

Do not proceed to implementation until this quality bar is met.

## Approval Gate

After presenting the plan, ask the user to approve it.

Do not change code before explicit user approval.

Confirm:

- Whether the fix direction is acceptable
- Whether the priority order is acceptable
- Whether there are extra constraints to consider

## Implementation

After approval:

1. Reconfirm the working tree and relevant files.
2. Implement required fixes first, then suggested fixes.
3. Keep question or discussion items as notes unless the user explicitly asks to address them.
4. Run the project-appropriate validation.
5. Report what was changed, what was not changed, and any remaining risks.

Create commits only if the user asks for commits or the repository workflow explicitly requires them.
