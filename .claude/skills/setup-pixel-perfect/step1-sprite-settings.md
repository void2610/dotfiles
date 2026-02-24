# Step 1: スプライト設定

対象スプライトのTextureImporterを一括設定します。

## 設定値

| 項目 | 値 |
|---|---|
| Filter Mode | Point（フィルターなし） |
| Compression | None（圧縮なし） |
| Pixels Per Unit | 指定PPU値 |
| Mesh Type | Full Rect |

## uLoop手順

1. `unity-search`でスプライトアセットを検索し対象を確認
2. `execute-dynamic-code`で一括設定を実行

## `execute-dynamic-code`用コード

```csharp
using UnityEditor;
using UnityEngine;

// 指定フォルダ内のスプライトを一括でピクセルパーフェクト設定に変更
var guids = AssetDatabase.FindAssets("t:Sprite", new[] { "$ASSET_PATH" });
int count = 0;
foreach (var guid in guids)
{
    var path = AssetDatabase.GUIDToAssetPath(guid);
    var importer = AssetImporter.GetAtPath(path) as TextureImporter;
    if (importer == null) continue;

    importer.textureType = TextureImporterType.Sprite;
    importer.filterMode = FilterMode.Point;
    importer.textureCompression = TextureImporterCompression.Uncompressed;
    importer.spritePixelsPerUnit = $PPU;
    importer.spriteMeshType = SpriteMeshType.FullRect;
    importer.SaveAndReimport();
    count++;
}
return $"{count}個のスプライトを設定完了";
```

## SpriteAtlasがある場合

SpriteAtlasも同様にPoint filter・圧縮なしに設定が必要です。

```csharp
using UnityEditor;
using UnityEditor.U2D;
using UnityEngine;
using UnityEngine.U2D;

// SpriteAtlasのフィルターと圧縮設定を修正
var guids = AssetDatabase.FindAssets("t:SpriteAtlas");
int count = 0;
foreach (var guid in guids)
{
    var path = AssetDatabase.GUIDToAssetPath(guid);
    var atlas = AssetDatabase.LoadAssetAtPath<SpriteAtlas>(path);
    if (atlas == null) continue;

    var texSettings = atlas.GetTextureSettings();
    texSettings.filterMode = FilterMode.Point;
    atlas.SetTextureSettings(texSettings);

    var platformSettings = atlas.GetPlatformSettings("DefaultTexturePlatform");
    platformSettings.textureCompression = TextureImporterCompression.Uncompressed;
    atlas.SetPlatformSettings(platformSettings);

    EditorUtility.SetDirty(atlas);
    count++;
}
AssetDatabase.SaveAssets();
return $"{count}個のSpriteAtlasを設定完了";
```
