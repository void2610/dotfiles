---
name: ship
description: 開発フロー (計画 → ブランチ → 実装 → テスト → フォーマット → コミット → 実装報告 → クイズ → PR → Copilot レビュー → レビュー対応) を状態機械で進めるパイプラインスキル。グローバル CLAUDE.md の基本ルールにより、複数フェーズにわたる開発依頼の標準フロー。中断したフローの再開にも使う。
---

# ship — 開発フローパイプライン

指示から PR レビュー対応までを、`scripts/ship.sh` の状態機械に沿って進める。
本スキルは順序と確認ポイントの管理だけを行い、各作業は既存スキルに委譲する。

## 絶対原則

1. **現在地と次アクションは必ず `ship.sh` に聞く** (`status` / `next`)。自分の記憶でフェーズを進めない。セッション途中参加・再開時も最初に `status` を打つ
2. **フェーズ遷移は必ず `ship.sh done <phase>` 経由**。postcondition が実測検証され、NG の間は次へ進めない。NG を解消してから再実行する (検証の握りつぶし・skip での回避は禁止)
3. `ship.sh next` が `checkpoint=yes` を返したら、**そのフェーズの作業を始めずに**現状を報告してユーザーの指示を待つ
4. **branch フェーズ完了後はフロー完走までブランチを固定する**。全フェーズが done になるまで、新しいブランチの作成 (`git switch -c` / `git checkout -b` / worktree 追加等) とブランチ移動 (`git switch` / `git checkout <branch>`) を一切行わない。別ブランチでの作業が必要になったらユーザーに報告して指示を待つ (enforce-ship-branch-lock.sh hook が `ship.sh guard` で機械的にもブロックする)
5. **柔軟性はユーザーの自然言語をそのまま状態に反映する**。選択肢の提示はしない
   - 「コミット前で毎回止めて」→ `ship.sh checkpoint add commit`
   - 「もう止めなくていい」→ `ship.sh checkpoint remove <phase>`
   - 「テストは飛ばして」→ `ship.sh skip test <ユーザーの理由>`
   - 「ここで中断」→ 状態はファイルに残る。次回 `/ship` で status から再開

## フェーズと担当

| phase | 担当 | `done` の検証内容 |
|---|---|---|
| plan | 依頼が開放的なら task-contract で契約確認 → `ship.sh init "<goal>"` | goal 記録済み (init が plan を done にする) |
| branch | branch-create スキル | デフォルトブランチ以外にいる |
| impl | 本体実装 (このセッション) | 差分が存在する |
| test | `ship.sh done test` 自体が実行 | `.claude/ship.json` の test コマンドが exit 0 |
| format | 同上 | format コマンドが exit 0 |
| knowledge | 得た知見の `Knowledge/` (OKF等) への永続化を検討し、書く/書かないを `ship.sh knowledge "<内容 or 理由>"` で記録 (プロジェクトに知識ベースが無ければ理由に明記して skip 可) | 検討記録が存在する |
| commit | commit スキル | working tree clean かつコミットが積まれている |
| report | 実装報告を提示 (変更内容・設計判断・検証結果)。ユーザーが報告を読み承認したら `ship.sh report approve`。ホスト `PCmac24055` のみ有効 (他マシンでは自動 skip) | 承認済み SHA が現 HEAD と一致 |
| quiz | push-quiz スキル (全問正答 + ユーザーの push 許可後に `ship.sh quiz approve`)。ホスト `PCmac24055` のみ有効 (他マシンでは自動 skip) | 承認済み SHA が現 HEAD と一致 |
| pr | pr-create スキル (Copilot 依頼 + レビュー/CI ポーリングの background 起動まで担当) | 現ブランチに OPEN な PR |
| review | ポーリング完了通知を待つ (催促されたら status で状況報告)。CI が fail なら原因を修正して push する | Copilot レビューが実在し、CI が fail/pending でない |
| fix | 未解決スレッドが残っていれば pr-review-fix スキル | 未解決レビュースレッド 0 件 |

全フェーズ done になったら PR URL と各フェーズの記録を添えて完了報告する。

## 初回セットアップ (リポジトリごと)

`.claude/ship.json` が無い場合、リポジトリの実体 (Taskfile / Makefile / package.json / CLAUDE.md) から
test / format コマンドを推定して提示し、ユーザー承認後に書き込む:

```json
{"test": "task test", "format": "task format"}
```

## 非担当

- コミット分割・PR 本文・レビュー返信の各ルール → それぞれ commit / pr-create / pr-review-fix が持つ
- 計画の深掘り → grill-me / grill-with-docs
