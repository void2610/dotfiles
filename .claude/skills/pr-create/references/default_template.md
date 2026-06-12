# pr-create default PR 本文テンプレート

リポジトリに `pull_request_template.md` 系ファイルが **存在しない** 場合にのみ使うフォールバックテンプレート。SKILL.md Phase 3-C から参照される。

リポジトリ側にテンプレートがあれば必ずそちらを優先すること (Phase 3-A → Phase 3-B)。

## テンプレート本体

```markdown
## 概要
<なぜこの変更が必要か、1〜3 行で>

## 変更点
- <主要な変更点を箇条書き>

## 動作確認
- [ ] <人間が実際に行う確認項目>
```

## 各セクションの書き方

- **概要**: Why を 1行で書く。コードから読める What の冗長説明は書かない
- **変更点**: 
  - コミット、ファイル単位ではなく、わかりやすい機能単位で分割する。
  - コードを読めばわかる具体名は極力書かない。 
  - 悪い例: 旧 `experiments/sim2real/utils/action_dr.py` を削除し、engine (`LowFreqNoiseInjector` / `dagger_offset_approach_iter` / `sample_duration_scale` / `sample_ee_perturbation` / `taper_weight`) を `polaris/dr/motion_noise.py` に移設
  - 良い例: DR関連のutil関数を正しい場所へ移設
- **動作確認**: 簡潔に 2〜3 項目程度まで。実行者が実際に確認する最低限に絞り、網羅リストにしない
