---
name: branch-create
description: "新しい Git ブランチ名を決めて作成するスキル。トリガー: 「ブランチ切って」「ブランチ作って」「create branch」「new branch」等のユーザー指示、または `branch-create` スキル指定。作業内容 (依頼内容 or 未コミット差分) から規約に沿った名前を決定し、最新のデフォルトブランチを起点に `git switch -c` する。"
---

# branch-create

## 命名規約

形式: `<type>/<short-kebab-case-summary>`

type (commit スキルと統一): `feat` / `fix` / `refac` / `docs` / `style` / `test` / `chore`

summary: 英語 kebab-case、30 文字目安、動詞 + 目的語 (`add-x`, `fix-x`, `rename-x-to-y`)。`update` / `change` / `wip` 等の曖昧語単独は禁止。

NG 例: `update`, `feat/various-changes`, `my-branch`, `feat/add_login_form`

## 確認が必要なケース (これ以外は確認なしで進める)

- 依頼文も差分も空でコンテキストが取れない
- 同名ブランチが既に存在
- 未コミット変更があってデフォルトブランチへの `switch` が衝突

## ワークフロー

1. **事前チェック**

   ```bash
   git rev-parse --abbrev-ref HEAD
   git status --short
   git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p'
   ```

2. **コンテキスト収集**: 依頼文 → 未コミット差分 (`git diff --stat`) の順で根拠を集める。

3. **名前決定**: 規約に沿った名前を 1 つ決める。

4. **起点を最新化** (デフォルト動作。「現ブランチから派生で」等の明示指示時のみスキップ):

   ```bash
   git fetch origin
   git switch <default-branch>
   git pull --ff-only
   ```

5. **作成**:

   ```bash
   git switch -c <branch-name>
   ```

push はしない。`pr-create` 側に委ねる。

## トラブル

- **同名衝突**: 既存に switch するか別名にするかをユーザーに確認
- **switch 失敗 (未コミット変更)**: stash / commit / 現ブランチ派生のどれかをユーザーに確認
- **origin なし**: ローカル完結で作成して終了
