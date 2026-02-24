# Step 2: RenderTexture + メインカメラ設定

低解像度のRenderTextureにゲーム画面を描画し、後段で整数倍にアップスケーリングします。

## 2-1. RenderTexture作成

| 項目 | 値 |
|---|---|
| サイズ | 仮想解像度（例: 320×180） |
| Color Format | R8G8B8A8_UNorm（8bitで2D Lightingが自動離散化） |
| Depth Buffer | なし（0） |
| Filter Mode | Point |
| Anti-aliasing | None（1x） |

### `execute-dynamic-code`用コード

```csharp
using UnityEngine;
using UnityEditor;

// ピクセルパーフェクト用RenderTextureを作成
var rt = new RenderTexture($WIDTH, $HEIGHT, 0, RenderTextureFormat.ARGB32);
rt.filterMode = FilterMode.Point;
rt.antiAliasing = 1;
rt.name = "PixelPerfectRT";

// 保存先フォルダを確保
if (!AssetDatabase.IsValidFolder("Assets/RenderTextures"))
    AssetDatabase.CreateFolder("Assets", "RenderTextures");

AssetDatabase.CreateAsset(rt, "Assets/RenderTextures/PixelPerfectRT.asset");
AssetDatabase.SaveAssets();
return "RenderTexture作成完了: " + $WIDTH + "x" + $HEIGHT;
```

## 2-2. メインカメラ設定

| 項目 | 値 |
|---|---|
| Target Texture | 作成したRenderTexture |
| Projection | Orthographic |
| Orthographic Size | RT高さ ÷ PPU ÷ 2 |
| Culling Mask | UIレイヤーを除外 |
| Pixel Perfect Camera | **付けない**（合成カメラ側で使用） |

### `execute-dynamic-code`用コード

```csharp
using UnityEngine;
using UnityEditor;

// メインカメラをRenderTextureへの低解像度レンダリング用に設定
var cam = Camera.main;
if (cam == null) return "エラー: メインカメラが見つかりません";

var rt = AssetDatabase.LoadAssetAtPath<RenderTexture>(
    "Assets/RenderTextures/PixelPerfectRT.asset");
if (rt == null) return "エラー: RenderTextureが見つかりません（Step 2-1を先に実行）";

cam.targetTexture = rt;
cam.orthographic = true;
cam.orthographicSize = $HEIGHT / (float)$PPU / 2f;

// UIレイヤーをカリングマスクから除外
cam.cullingMask &= ~(1 << LayerMask.NameToLayer("UI"));

// Pixel Perfect Cameraが付いていれば除去（合成カメラ側で使う）
var ppc = cam.GetComponent<UnityEngine.Rendering.Universal.PixelPerfectCamera>();
if (ppc != null)
{
    Object.DestroyImmediate(ppc);
    return "メインカメラ設定完了（既存のPixel Perfect Cameraを除去しました）";
}

EditorUtility.SetDirty(cam);
return $"メインカメラ設定完了: orthographicSize = {cam.orthographicSize}";
```
