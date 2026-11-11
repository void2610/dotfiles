---
name: push
description: "`git push` するときは必ずこのスキルを使う。トリガー: 「push して」「プッシュして」「リモートに上げて」等のユーザー指示、およびコミット後に push が要るとき。pr-create・pr-review-fix・ship の中の push もこのスキルで行う。force push は扱わない。"
---

# push

コミット済みの変更をリモートへ送るスキル。push はすべてこのスキルで行う。コミット作成は担当しない (先に commit スキルで済ませる)。
ユーザーに手動実行を頼まず、確認が必要なケース以外は確認なしで送る。

## 確認が必要なケース (これ以外は確認なしで進める)

- デフォルトブランチ (main 等) へ送ろうとしているが、セッション内の指示でもリポジトリの CLAUDE.md でも main での直接作業が許可されていない。ユーザーが push を明示的に指示した場合は許可とみなす
- リモートの取り込みでコンフリクトした
- force push が要る (push 済みの履歴を書き換えた等)。このスキルでは実行せず、理由を添えて確認する

## ワークフロー

1. **事前チェック**

   ```bash
   git status --short                              # 未コミットの変更は送られない。送るべき変更なら先に commit スキル
   git rev-parse --abbrev-ref HEAD                 # 現ブランチ
   git fetch origin
   git rev-parse --abbrev-ref @{u} 2>/dev/null     # upstream。無ければ初回 push
   git rev-list --left-right --count @{u}...HEAD   # 「behind ahead」
   git log --oneline @{u}..HEAD                    # 送るコミット (upstream が無ければ origin/HEAD..HEAD)
   ```

2. **判定**
   - ahead が 0 → 送るものが無いと報告して終了
   - behind が 1 以上 → `git pull --no-rebase --no-edit` でマージして取り込む (push 済みの履歴を書き換えないため rebase しない)。コンフリクトしたら `git merge --abort` で戻して報告する
   - 現ブランチがデフォルトブランチ → 「確認が必要なケース」に当たらないか確かめる。当たるなら branch-create → pr-create の流れへ切り替えるかを確認する

3. **push** — 実行コマンドには `CLAUDE_GIT_SKILL=push` を前置する (guards Mod の `git-skill-enforcer.ts` がこのマーカーでスキル経由かを判定し、無いと直接実行はブロックされる)

   ```bash
   # upstream 未設定 (branch-track-guard に合わせ、同名のリモートブランチへ紐づける)
   CLAUDE_GIT_SKILL=push git push -u origin HEAD

   # upstream 設定済み
   CLAUDE_GIT_SKILL=push git push
   ```

   `--force` / `-f` / `--force-with-lease` / `+<refspec>` は付けない。

4. **報告** — 送ったブランチ、範囲 (`<旧 SHA>..<新 SHA>`)、コミット件数を伝える。ブランチに OPEN な PR があれば (`gh pr view --json url`) その URL も添える

## トラブル

- **認証 / 権限エラー**: `gh auth status` と `git remote -v` の結果を添えて報告
- **non-fast-forward で拒否**: 手順 2 の取り込みからやり直す。force では解決しない
- **保護ブランチで拒否**: main へ直接送れないリポジトリなので、branch-create → pr-create の流れへ切り替える
