# Step 3: TMPフォントアセット設定

ドット絵と統一感のあるフォント表示を実現します。SDF（Signed Distance Field）レンダリングはピクセルパーフェクトに不向きなため、RASTERモードを使用します。

## フォントアセット作成ガイド

1. `Window > TextMeshPro > Font Asset Creator` を開く
2. 以下を設定:

| 項目 | 値 |
|---|---|
| Source Font File | 使用するフォントファイル（.ttf / .otf） |
| Render Mode | **RASTER** または **RASTER_HINTED** |
| Sampling Point Size | 指定値（整数。例: 8, 16） |
| Padding | **Sampling Point Sizeと同じ値**（小さすぎると文字が正しく描画されない） |

3. 「Generate Font Atlas」→「Save」でアセット保存

## Font Asset Creatorの起動

`execute-menu-item`で以下を実行:

```
Window/TextMeshPro/Font Asset Creator
```

## `execute-dynamic-code`用コード（検証・修正）

生成済みフォントアセットの設定を検証し、必要に応じてアトラスのフィルターモードを修正します。

```csharp
using TMPro;
using UnityEditor;
using UnityEngine;

// TMPフォントアセットのピクセルパーフェクト設定を検証
var fontAsset = AssetDatabase.LoadAssetAtPath<TMP_FontAsset>("$FONT_ASSET_PATH");
if (fontAsset == null) return "エラー: フォントアセットが見つかりません: $FONT_ASSET_PATH";

var atlas = fontAsset.atlasTexture;
var sb = new System.Text.StringBuilder();
sb.AppendLine("=== TMPフォントアセット検証結果 ===");
sb.AppendLine($"フォント名: {fontAsset.name}");
sb.AppendLine($"レンダーモード: {fontAsset.atlasRenderMode}");
sb.AppendLine($"アトラスフィルターモード: {atlas.filterMode}");
sb.AppendLine($"サンプリングポイントサイズ: {fontAsset.faceInfo.pointSize}");

// フィルターモード検証・修正
if (atlas.filterMode != FilterMode.Point)
{
    atlas.filterMode = FilterMode.Point;
    EditorUtility.SetDirty(atlas);
    AssetDatabase.SaveAssets();
    sb.AppendLine("→ フィルターモードをPointに修正しました");
}
else
{
    sb.AppendLine("→ フィルターモードOK");
}

// レンダーモード警告（GlyphRasterModesはinternalのため文字列で判定）
var renderModeStr = fontAsset.atlasRenderMode.ToString();
if (renderModeStr.Contains("RASTER"))
{
    sb.AppendLine("→ レンダーモードOK");
}
else
{
    sb.AppendLine($"警告: レンダーモードが{renderModeStr}です。RASTER or RASTER_HINTEDに変更してください");
}

return sb.ToString();
```

## `execute-dynamic-code`用コード（TMPデフォルトフォント設定）

TMP Settingsのデフォルトフォントを変更し、新規TextMeshProコンポーネントに自動適用されるようにします。

```csharp
using TMPro;
using UnityEditor;
using UnityEngine;

// TMP Settingsのデフォルトフォントを変更
var settings = AssetDatabase.LoadAssetAtPath<TMP_Settings>("Assets/TextMesh Pro/Resources/TMP Settings.asset");
if (settings == null) return "エラー: TMP Settingsが見つかりません";

var fontAsset = AssetDatabase.LoadAssetAtPath<TMP_FontAsset>("$FONT_ASSET_PATH");
if (fontAsset == null) return "エラー: フォントアセットが見つかりません: $FONT_ASSET_PATH";

// SerializedObjectで設定を変更
var so = new SerializedObject(settings);
var defaultFontProp = so.FindProperty("m_defaultFontAsset");
if (defaultFontProp == null) return "エラー: m_defaultFontAssetプロパティが見つかりません";

var previousFont = defaultFontProp.objectReferenceValue;
defaultFontProp.objectReferenceValue = fontAsset;
so.ApplyModifiedProperties();
EditorUtility.SetDirty(settings);
AssetDatabase.SaveAssets();

return $"デフォルトフォントを変更: {(previousFont != null ? previousFont.name : "なし")} → {fontAsset.name}";
```

## フォントサイズの制約

ゲーム内で使用するフォントサイズは**Sampling Point Sizeの整数倍のみ**にしてください。

- Sampling Point Size = 8 の場合: 8, 16, 24, 32 ... が使用可能
- 非整数倍を指定するとボケやジャギが発生します
