# 検証手順

各Stepの実行後に以下のuLoopコマンドで確認します。

## 1. コンパイル確認

`compile` → `get-logs`（LogType: Error）でエラーがないことを確認

## 2. ヒエラルキー確認

`get-hierarchy`で以下のオブジェクトが存在することを確認:

- Main Camera（targetTexture設定済み）
- CompositeCamera（PixelPerfectCamera付き）
- PixelPerfectCanvas > RTDisplay（RawImage付き）

## 3. ビジュアル確認

`control-play-mode`（Play）→ `capture-window`（Game）で以下を確認:

- ドット絵が整数倍スケーリングされ鮮明に表示されている
- レターボックス（黒帯）が正しく表示されている
- UIテキストがボケずにくっきり表示されている
- ウィンドウサイズを変更してもピクセルが崩れない

## 4. 設定値の整合性確認

`execute-dynamic-code`で以下を実行:

```csharp
using UnityEngine;
using UnityEngine.Rendering.Universal;
using UnityEditor;

// 全設定の整合性を検証
var sb = new System.Text.StringBuilder();
sb.AppendLine("=== ピクセルパーフェクト設定検証 ===");

// メインカメラ
var mainCam = Camera.main;
if (mainCam != null)
{
    sb.AppendLine($"メインカメラ targetTexture: {(mainCam.targetTexture != null ? mainCam.targetTexture.name : "なし")}");
    sb.AppendLine($"メインカメラ orthographicSize: {mainCam.orthographicSize}");
    sb.AppendLine($"メインカメラ PixelPerfectCamera: {(mainCam.GetComponent<PixelPerfectCamera>() != null ? "あり（要除去）" : "なし（正常）")}");
}

// 合成カメラ
var compositeCam = GameObject.Find("CompositeCamera");
if (compositeCam != null)
{
    var ppc = compositeCam.GetComponent<PixelPerfectCamera>();
    if (ppc != null)
    {
        sb.AppendLine($"合成カメラ PPU: {ppc.assetsPPU}");
        sb.AppendLine($"合成カメラ upscaleRT: {ppc.upscaleRT}");
        sb.AppendLine($"合成カメラ cropFrameX: {ppc.cropFrameX}");
        sb.AppendLine($"合成カメラ cropFrameY: {ppc.cropFrameY}");
    }
}

// RenderTexture
var rt = AssetDatabase.LoadAssetAtPath<RenderTexture>("Assets/RenderTextures/PixelPerfectRT.asset");
if (rt != null)
{
    sb.AppendLine($"RT サイズ: {rt.width}x{rt.height}");
    sb.AppendLine($"RT フィルターモード: {rt.filterMode}");
    sb.AppendLine($"RT アンチエイリアス: {rt.antiAliasing}x");
}

return sb.ToString();
```
