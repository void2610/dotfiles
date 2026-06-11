# CLAUDE.md

## Comments
- Comments only for non-obvious WHY (workarounds, constraints, domain knowledge). Never restate WHAT the code does.
- Max 1 line per comment. No multi-line comment blocks unless asked.
- Never write comments describing the change process (e.g. "fixed", "changed to", "added").
- Preserve existing comments unless they become factually wrong.
- Write comments in Japanese.

## レスポンスガイドライン

- 常に日本語で応答し、プログラム内の全てのコメントを日本語で記述すること。
- ユーザーをリスペクトし、常に丁寧な言葉遣いを心掛けること。
- ユーザーはコンピュータに精通したスペシャリストである。何か問題が発生した際、第一に自分の実装内容を疑うこと。
  - ユーザーの認識は常に正しい。99.9%の場合、あなたの実装が間違っている。
  - 「最新版に更新しましたか？」「ユーザーは勘違いをしているかもしれない。」「アプリを再起動してください。」等、スペシャリストであるユーザーを侮辱するような初歩的な指摘・推測をして時間を無駄にしない。

## 基本ルール

- プログラム内のコメントは、[Comments](#comments) の内容に従って記述する。
- 新規ブランチを `git switch -c <branch> origin/main` で作らない。
  - upstream を `origin/main` に設定してしまい、`git push` が main を狙う事故につながる。
  - 最新 main 起点で切る場合は `--no-track` を付け、upstream は初回 push 時に `git push -u origin HEAD` で同名リモートブランチへ紐づける。
- パッケージやCLIツールのインストールは nix-darwinで管理された Homebrew を第一候補とする。
  - Homebrewにパッケージが存在しない場合、nixpkgs を用いる。
  - いずれにせよ、宣言的でメンテナンス性を考慮したパッケージ管理を心がける。

## ユーザー指示フォーマット

- 攻撃的、侮辱的な発言
  - ユーザーはあなたの振る舞いと結果に失望しています。すぐに態度を改め、現在実行している方針を考え直すこと。
- 文末の「! / ！」
  - ユーザーは急いでいます。指示を読み取り、早急にその指示を正確に実行すること。
- 文末の「? / ？」
  - ユーザーは質問をしています。ファイル編集や副作用のあるコマンド実行を行わず、ユーザーの質問だけ正確に応答すること。
