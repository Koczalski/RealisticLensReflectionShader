# Refract Debug Stencil Shader (Unity Built-in RP)

## 概要

Unity Built-in Render Pipeline 用の **GrabPass 屈折シェーダー**です。
メガネのレンズや透明オブジェクトの屈折を表現できます。さらに **ステンシルマスク**によって「屈折させない部分（フレームなど）」を除外できます。

本リポジトリには、以下が含まれます：

* **NoRefractMask.shader** : 除外オブジェクト用（ステンシル刻印のみ）
* **Refract\_Debug\_Stencil.shader** : 屈折シェーダー（デバッグ機能付き）

## 特徴

* **スネルの法則**に基づいた屈折計算
* **GrabPass** による背景の屈折描画
* **Stencil マスク対応**（メガネフレームなどを除外可能）
* **デバッグモード**：

  * `_BypassStencil` : ステンシルを無視して屈折を強制表示
  * `_ForceOffset` : 強制的に歪みを発生させ確認
  * `_DebugMode` : オフセットベクトル可視化 / Grabのみ表示
* **Fresnel反射のブレンド**による自然な見た目

## 使い方

### 1. 除外オブジェクト（例: メガネフレーム）

* マテリアルに `NoRefractMask.shader` を割り当て
* `Stencil Ref` を 1 に設定（デフォルト）
* Render Queue は自動で `Transparent-1` になります

### 2. 屈折オブジェクト（例: レンズ）

* マテリアルに `Refract_Debug_Stencil.shader` を割り当て
* `Stencil Ref` をマスクと同じ値（通常 1）に設定
* `_OutsideIOR` / `_InsideIOR` で屈折率を調整（例: 空気=1.0, ガラス=1.5）
* `_ScreenOffsetScale` を上げ下げして歪み量を調整

### 3. デバッグ手順

1. **Bypass Stencil** にチェック → ステンシルを無視して動作確認
2. **Force Offset** を有効にして必ず歪むか確認
3. **DebugMode** を 1 または 2 に設定してオフセット挙動を可視化
4. 問題なければ Bypass を OFF に戻し、Stencil 除外が機能するか確認

## パラメータ例

* ガラス風: `_InsideIOR = 1.5`, `_ScreenOffsetScale = 0.12`
* 水風: `_InsideIOR = 1.33`, `_ScreenOffsetScale = 0.18`
* Fresnel強調: `_FresnelScale = 0.8`, `_ReflectTint = (1,1,1)`

## 注意事項

* **Built-in RP 専用**です。URP/HDRP では GrabPass が使えません。
* 透明オブジェクトのソート順によって結果が異なる場合があります。
* GrabPass は負荷が高いため、大量のオブジェクトでの使用には注意してください。

## ライセンス

Apache License 2.0
