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
| Layer | UI |

Canvas直下にRawImageを配置し、RenderTextureを表示します。UI要素はこのRawImageと同階層に配置します。

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
canvasGO.AddComponent<CanvasScaler>();
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
