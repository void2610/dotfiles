# Step 4: 合成カメラ + 表示Canvas

RenderTextureの内容を実画面に整数倍でアップスケーリング表示します。

## 4-1. 合成カメラ

| 項目 | 値 |
|---|---|
| Clear Flags | Solid Color（黒） |
| Culling Mask | UIのみ |
| Projection | Orthographic |
| Depth | 10（メインカメラより後に描画） |
| Pixel Perfect Camera | 追加する |
| Assets PPU | 指定PPU値 |
| Upscale Render Texture | ON |
| Crop Frame | X/Y両方ON（レターボックス対応） |

## 4-2. Canvas構成

| 項目 | 値 |
|---|---|
| Render Mode | Screen Space - Camera |
| Render Camera | 合成カメラ |
| Pixel Perfect | **true** |
| Layer | UI |

### CanvasScaler設定

**仮想解像度に合わせて設定する。** RenderTextureの解像度ではなく、Pixel Perfect Cameraの参照解像度を使用する。

| 項目 | 値 |
|---|---|
| UI Scale Mode | **Scale With Screen Size** |
| Reference Resolution | **仮想解像度と同じ**（例: 320×180） |
| Screen Match Mode | **Expand** |

### UI配置ルール

Canvas直下にRawImageを配置し、RenderTextureを表示する。UI要素はRawImageの**後（下）**に配置する。

```
PixelPerfectCanvas
  ├── RTDisplay (RawImage) ← ゲーム画面表示
  ├── UIテキスト等...       ← RawImageより後に配置
  └── ...
```

### 既存UIの統合

既存のCanvasがある場合、子要素をPixelPerfectCanvasに移動し、旧Canvasを削除する。

### フォントサイズの注意

仮想解像度（例: 320×180）基準でフォントサイズを設定する。1920×1080向けのサイズをそのまま使うとテキストが巨大になる。Sampling Point Sizeの整数倍のみ使用可能（例: SPSが16なら16, 32, 48...）。

## `execute-dynamic-code`用コード

```csharp
using UnityEngine;
using UnityEngine.UI;
using UnityEngine.Rendering.Universal;
using UnityEditor;

// === 合成カメラ作成 ===
var compositeGO = new GameObject("CompositeCamera");
var compositeCam = compositeGO.AddComponent<Camera>();
compositeCam.clearFlags = CameraClearFlags.SolidColor;
compositeCam.backgroundColor = Color.black;
compositeCam.cullingMask = 1 << LayerMask.NameToLayer("UI");
compositeCam.orthographic = true;
compositeCam.depth = 10;

// Pixel Perfect Camera（合成カメラ側に付ける）
var ppc = compositeGO.AddComponent<PixelPerfectCamera>();
ppc.assetsPPU = $PPU;
ppc.upscaleRT = true;
ppc.cropFrameX = true;
ppc.cropFrameY = true;

// URPカメラデータ取得（追加カメラの設定）
var camData = compositeCam.GetUniversalAdditionalCameraData();
if (camData != null)
{
    camData.renderType = CameraRenderType.Base;
}

// === Canvas + RawImage 作成 ===
var canvasGO = new GameObject("PixelPerfectCanvas");
canvasGO.layer = LayerMask.NameToLayer("UI");
var canvas = canvasGO.AddComponent<Canvas>();
canvas.renderMode = RenderMode.ScreenSpaceCamera;
canvas.worldCamera = compositeCam;
canvas.pixelPerfect = true;
var scaler = canvasGO.AddComponent<CanvasScaler>();
scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
scaler.referenceResolution = new Vector2($VIRTUAL_WIDTH, $VIRTUAL_HEIGHT);
scaler.screenMatchMode = CanvasScaler.ScreenMatchMode.Expand;
canvasGO.AddComponent<GraphicRaycaster>();

// RawImageでRenderTextureを表示
var rawImageGO = new GameObject("RTDisplay");
rawImageGO.transform.SetParent(canvasGO.transform, false);
rawImageGO.layer = LayerMask.NameToLayer("UI");
var rawImage = rawImageGO.AddComponent<RawImage>();
rawImage.texture = AssetDatabase.LoadAssetAtPath<RenderTexture>(
    "Assets/RenderTextures/PixelPerfectRT.asset");

// RawImageを画面全体に引き伸ばし
var rect = rawImage.GetComponent<RectTransform>();
rect.anchorMin = Vector2.zero;
rect.anchorMax = Vector2.one;
rect.sizeDelta = Vector2.zero;

EditorUtility.SetDirty(compositeGO);
EditorUtility.SetDirty(canvasGO);
return "合成カメラ + Canvas作成完了";
```
