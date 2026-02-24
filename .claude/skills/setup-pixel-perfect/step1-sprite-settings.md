# Step 1: スプライト設定（Presetベース）

TextureImporterのPresetを作成し、Preset Managerに登録することで、新規インポートされるスプライトに自動でピクセルパーフェクト設定を適用します。

## 設定値

| 項目 | 値 |
|---|---|
| Texture Type | Sprite (2D and UI) |
| Filter Mode | Point（フィルターなし） |
| Compression | None（圧縮なし） |
| Pixels Per Unit | 指定PPU値 |
| Mesh Type | Full Rect |

## uLoop手順

### 1. ダミーテクスチャの作成（Bash）

Presetを作るにはTextureImporterのインスタンスが必要なため、一時的なダミーPNGを作成します。

```bash
# ダミーフォルダとPreset保存先を作成
mkdir -p Assets/Sprites
mkdir -p Assets/Editor/Presets

# 1x1の透明PNGをダミーとして作成
python3 -c "
import struct, zlib
def create_png():
    header = b'\x89PNG\r\n\x1a\n'
    ihdr_data = struct.pack('>IIBBBBB', 1, 1, 8, 6, 0, 0, 0)
    ihdr_crc = zlib.crc32(b'IHDR' + ihdr_data)
    ihdr = struct.pack('>I', 13) + b'IHDR' + ihdr_data + struct.pack('>I', ihdr_crc)
    raw = b'\x00\x00\x00\x00\x00'
    compressed = zlib.compress(raw)
    idat_crc = zlib.crc32(b'IDAT' + compressed)
    idat = struct.pack('>I', len(compressed)) + b'IDAT' + compressed + struct.pack('>I', idat_crc)
    iend_crc = zlib.crc32(b'IEND')
    iend = struct.pack('>I', 0) + b'IEND' + struct.pack('>I', iend_crc)
    return header + ihdr + idat + iend
with open('Assets/Sprites/_dummy_for_preset.png', 'wb') as f:
    f.write(create_png())
"
```

### 2. Preset作成・登録（execute-dynamic-code）

```csharp
using UnityEditor;
using UnityEditor.Presets;
using UnityEngine;

// ダミーテクスチャをインポート
AssetDatabase.Refresh();
var dummyPath = "Assets/Sprites/_dummy_for_preset.png";
var importer = AssetImporter.GetAtPath(dummyPath) as TextureImporter;
if (importer == null) return "エラー: ダミーテクスチャのインポーターが取得できません";

// ピクセルパーフェクト用のインポート設定を適用
importer.textureType = TextureImporterType.Sprite;
importer.filterMode = FilterMode.Point;
importer.textureCompression = TextureImporterCompression.Uncompressed;
importer.spritePixelsPerUnit = $PPU;

// MeshTypeはTextureImporterSettings経由で設定
var settings = new TextureImporterSettings();
importer.ReadTextureSettings(settings);
settings.spriteMeshType = SpriteMeshType.FullRect;
importer.SetTextureSettings(settings);

importer.SaveAndReimport();

// インポーターからPresetを作成して保存
var preset = new Preset(importer);
AssetDatabase.CreateAsset(preset, "Assets/Editor/Presets/PixelPerfectSprite.preset");

// Preset ManagerにデフォルトPresetとして登録
// 注意: new PresetType(preset) は IsValid=false になるため、importerインスタンスから作成すること
var presetType = new PresetType(importer);
var existingDefaults = Preset.GetDefaultPresetsForType(presetType);
var newDefaults = new DefaultPreset[existingDefaults.Length + 1];
for (int i = 0; i < existingDefaults.Length; i++)
    newDefaults[i] = existingDefaults[i];
newDefaults[newDefaults.Length - 1] = new DefaultPreset("", preset);
Preset.SetDefaultPresetsForType(presetType, newDefaults);

AssetDatabase.SaveAssets();

// ※ダミーテクスチャの削除はBashで行う（execute-dynamic-codeではDeleteAssetがセキュリティ制限で使用不可）
return "Preset作成・登録完了: Assets/Editor/Presets/PixelPerfectSprite.preset";
```

### 3. プロジェクト設定の保存（execute-menu-item）

Preset Managerの設定をProjectSettingsファイルに永続化します。

```
File/Save Project
```

### 4. Presetの検証（execute-dynamic-code）

SpriteMeshTypeが正しくFullRect(1)になっているか確認し、なっていなければ修正します。

```csharp
using UnityEditor;
using UnityEditor.Presets;
using UnityEngine;

// Presetの主要プロパティを検証
var preset = AssetDatabase.LoadAssetAtPath<Preset>("Assets/Editor/Presets/PixelPerfectSprite.preset");
if (preset == null) return "エラー: Presetが見つかりません";

var sb = new System.Text.StringBuilder();
bool needsFix = false;

foreach (var mod in preset.PropertyModifications)
{
    switch (mod.propertyPath)
    {
        case "m_TextureType":
            sb.AppendLine($"TextureType: {mod.value} (8=Sprite)");
            break;
        case "m_TextureSettings.m_FilterMode":
            sb.AppendLine($"FilterMode: {mod.value} (0=Point)");
            break;
        case "m_SpritePixelsToUnits":
            sb.AppendLine($"PPU: {mod.value}");
            break;
        case "m_SpriteMeshType":
            sb.AppendLine($"MeshType: {mod.value} (1=FullRect)");
            if (mod.value != "1") needsFix = true;
            break;
    }
}

// SpriteMeshTypeが0(Tight)の場合、SerializedObjectで1(FullRect)に修正
if (needsFix)
{
    var so = new SerializedObject(preset);
    var propMods = so.FindProperty("m_Properties");
    for (int i = 0; i < propMods.arraySize; i++)
    {
        var element = propMods.GetArrayElementAtIndex(i);
        if (element.FindPropertyRelative("propertyPath").stringValue == "m_SpriteMeshType")
        {
            element.FindPropertyRelative("value").stringValue = "1";
            break;
        }
    }
    so.ApplyModifiedProperties();
    EditorUtility.SetDirty(preset);
    AssetDatabase.SaveAssets();
    sb.AppendLine("→ SpriteMeshTypeをFullRectに修正しました");
}

return sb.ToString();
```

### 5. ダミーテクスチャの後片付け（Bash）

```bash
rm -f Assets/Sprites/_dummy_for_preset.png
rm -f Assets/Sprites/_dummy_for_preset.png.meta
```

後片付け後に`execute-dynamic-code`で`AssetDatabase.Refresh()`を実行してください。

## 既存スプライトの一括修正

既にインポート済みのスプライトがある場合は、Presetを使って一括適用します。

```csharp
using UnityEditor;
using UnityEditor.Presets;
using UnityEngine;

// 保存済みPresetを読み込み
var preset = AssetDatabase.LoadAssetAtPath<Preset>(
    "Assets/Editor/Presets/PixelPerfectSprite.preset");
if (preset == null) return "エラー: Presetが見つかりません（先にPreset作成を実行してください）";

// 指定フォルダ内のスプライトにPresetを一括適用
var guids = AssetDatabase.FindAssets("t:Texture2D", new[] { "$ASSET_PATH" });
int count = 0;
foreach (var guid in guids)
{
    var path = AssetDatabase.GUIDToAssetPath(guid);
    var importer = AssetImporter.GetAtPath(path) as TextureImporter;
    if (importer == null) continue;

    preset.ApplyTo(importer);
    importer.SaveAndReimport();
    count++;
}
return $"{count}個のスプライトにPresetを適用完了";
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
