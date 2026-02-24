# Unity ピクセルパーフェクト描画セットアップスキル

Zenn記事（https://zenn.dev/matsu_friends/articles/c4a5d36b1de94e）に基づき、Unity 6でピクセルパーフェクト描画を完全にセットアップします。RenderTextureへの低解像度レンダリング → 合成カメラでの整数倍アップスケーリングにより、鮮明なドット絵表示を実現します。

## 入力

$ARGUMENTS

以下のパラメータを受け取ります:

- **仮想解像度**（幅×高さ）: ゲームの内部描画解像度（例: 320×180）
- **PPU**（Pixels Per Unit）: 全アセット共通のピクセル密度（例: 16）
- **（任意）スプライト検索パス**: 一括設定するスプライトの格納フォルダ（例: Assets/Sprites）
- **（任意）フォントアセットパス**: TMPフォントアセットのパス
- **（任意）サンプリングポイントサイズ**: フォントのサンプリングサイズ（整数）

## 前提条件

- Unity 6 + URP（Universal Render Pipeline）
- 2D Renderer使用
- `com.unity.2d.pixel-perfect` パッケージがインストール済み
  - 未インストールの場合: Package Managerから「2D Pixel Perfect」を追加

## Step 1: スプライト設定

See [step1-sprite-settings.md](./step1-sprite-settings.md) for:
- TextureImporterの一括設定（Point filter / 圧縮なし / PPU統一 / Full Rect）
- SpriteAtlasの設定
- `execute-dynamic-code`用コード例

## Step 2: RenderTexture + メインカメラ設定

See [step2-rendertexture-camera.md](./step2-rendertexture-camera.md) for:
- RenderTexture作成（R8G8B8A8_UNorm / Point filter）
- メインカメラ設定（orthographicSize計算 / UI除外）
- Pixel Perfect Cameraをメインカメラに付けない理由

## Step 3: TMPフォントアセット設定

See [step3-tmp-font.md](./step3-tmp-font.md) for:
- Font Asset Creator起動・設定ガイド（RASTERモード）
- 生成済みフォントアセットの検証・修正コード
- フォントサイズの制約（Sampling Point Sizeの整数倍のみ）

## Step 4: 合成カメラ + 表示Canvas

See [step4-composite-camera.md](./step4-composite-camera.md) for:
- 合成カメラ作成（PixelPerfectCamera / Upscale RT / CropFrame）
- Canvas + RawImage構成（Screen Space - Camera）
- `execute-dynamic-code`用コード例

## 注意事項

See [notes.md](./notes.md) for:
- PPU統一の必須ルール
- Transform Scale/Rotationの制約
- ポストプロセシングの適用先
- 8bit Color Formatによる2D Lighting離散化

## 検証手順

See [verification.md](./verification.md) for:
- uLoopコマンドによるコンパイル・ヒエラルキー・ビジュアル確認
- 全設定の整合性を検証する`execute-dynamic-code`コード

## 実行手順まとめ

1. パラメータ（仮想解像度・PPU）を確認
2. **Step 1**: スプライトのインポート設定を一括変更
3. **Step 2**: RenderTexture作成 → メインカメラ設定
4. **Step 3**: TMPフォントアセットの検証・修正（フォントがある場合のみ）
5. **Step 4**: 合成カメラ + Canvas + RawImage作成
6. **検証**: compile → get-hierarchy → Play + capture-window で動作確認
