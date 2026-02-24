# 注意事項

## 必ず守ること

- **PPUは全アセットで統一**: スプライト、RenderTexture、Pixel Perfect Cameraすべてで同じPPU値を使用
- **フォントサイズはSampling Point Sizeの整数倍のみ**: 非整数倍はボケの原因
- **スプライトのTransform Scale/Rotationに注意**: 非整数スケールや45度以外の回転はジャギの原因。アニメーション等で回転する場合はスプライトシートで対応

## ポストプロセシング

- ポストプロセシングは**メインカメラ側**で適用（低解像度RTに対して処理）
- 合成カメラにはポストプロセシング不要

## 8bit Color Formatの利点

- RenderTextureをR8G8B8A8_UNormにすることで、2D Lightingの計算結果が自動的に離散化される
- ドット絵に適した段階的なライティング表現が自動で得られる
