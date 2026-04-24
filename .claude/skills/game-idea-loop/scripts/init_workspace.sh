#!/bin/bash
# game-ideas ワークスペース初期化スクリプト
# Usage: bash init_workspace.sh [workspace_name]

set -e

WORKSPACE_NAME="${1:-game-ideas-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$WORKSPACE_NAME/generations"

# 制約条件ファイル
cat > "$WORKSPACE_NAME/constraints.md" << 'EOF'
# 制約条件

## 基本情報
- **作成日時**: TIMESTAMP
- **ジャンル制約**: 
- **プラットフォーム**: 
- **開発規模**: 
- **テーマ/キーワード**: 
- **世代数**: 
- **1世代あたり生成数**: 
- **生存数**: 

## ユーザーからの追加指示

（ループ中のフィードバックもここに追記）
EOF

# 生成ログ
cat > "$WORKSPACE_NAME/generation-log.md" << 'EOF'
# 生成ログ

全世代の進行状況を時系列で記録する。

---
EOF

# 評価ログ
cat > "$WORKSPACE_NAME/evaluation-log.md" << 'EOF'
# 評価ログ

全世代のスコアリング結果を時系列で記録する。

---
EOF

# 殿堂入り
cat > "$WORKSPACE_NAME/hall-of-fame.md" << 'EOF'
# 殿堂入り（Hall of Fame）

全世代を通じてスコア85以上を獲得したアイデア。

---
EOF

# 最終レポート（空ファイル）
touch "$WORKSPACE_NAME/final-report.md"

echo "✅ ワークスペースを作成しました: $WORKSPACE_NAME"
echo ""
echo "構造:"
find "$WORKSPACE_NAME" -type f | sort | sed 's/^/  /'
