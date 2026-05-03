<!--
SPDX-FileCopyrightText: 2026 piyopiyo.ex members

SPDX-License-Identifier: Apache-2.0
-->

# Hello AtomVM Stack-chan

[LovyanGFX](https://github.com/lovyan03/LovyanGFX) を組み込んだ専用の AtomVM イメージを使って、Stack-chan 風の顔アニメーションを表示するサンプルです。

このサンプルでは、次の動作を確認できます。

- AtomLGFX で液晶に顔を描画する
- タッチ入力に応じて視線と口の開き具合を変える

現在は `mix atomvm.esp32.install` ではなく、このリポジトリーに含まれているカスタム AtomVM イメージを使ってください。

<p align="center">
  <img alt="atomvm-stackchan" width="320" src="https://github.com/user-attachments/assets/6a6f4bd0-20b8-4865-8186-50a9952da7ff">
</p>

## 対象機材

- AtomVM が対応する `ESP32` 開発ボード
- AtomVM が対応する `ESP32-S3` 開発ボード
- データ転送に対応した USB ケーブル

このリポジトリーには現在、次の AtomVM イメージを同梱しています。

- `atomvm-esp32-elixir.img`
- `atomvm-esp32s3-elixir.img`

補足:

- 顔表示のサンプル設定は `M5Stack Core2` 向けの AtomLGFX プリセットを使っています
- 別の表示ハードウェアで動かす場合は、`lib/sample_app/face_server.ex` の open options を調整してください

## 対象開発環境

本サンプルでは、次の環境を想定しています。

- macOS または Linux
- Elixir
- `mix`
- `esptool`
- `tio`

## 使い方

このディレクトリーに移動します。

```sh
cd hello_atomvm_disterl_stackchan
```

依存関係を取得します。

```sh
mix deps.get
```

このサンプル用の AtomVM イメージがまだ書き込まれていない場合は、先に次を実行してください。
すでに書き込み済みの場合は、この手順は不要です。

ESP32 の例:

```sh
# フラッシュ全体を消去して、まっさらな状態にする
esptool --chip esp32 --port /dev/ttyACM0 erase-flash

# このサンプル用の AtomVM イメージを 0x1000 から書き込む
esptool --chip esp32 --port /dev/ttyACM0 write-flash 0x1000 atomvm-esp32-elixir.img
```

ESP32-S3 の例:

```sh
# フラッシュ全体を消去して、まっさらな状態にする
esptool --chip esp32s3 --port /dev/ttyACM0 erase-flash

# このサンプル用の AtomVM イメージを 0x0 から書き込む
esptool --chip esp32s3 --port /dev/ttyACM0 write-flash 0x0 atomvm-esp32s3-elixir.img
```

アプリケーションを書き込みます。

```sh
mix atomvm.esp32.flash --port /dev/ttyACM0
```

接続先は必要に応じて読み替えてください。

例:

- Linux: `/dev/ttyACM0`, `/dev/ttyUSB0`
- macOS: `/dev/cu.usbmodemXXXX`, `/dev/cu.usbserialXXXX`

接続先が分からない場合は、次で確認できます。

```sh
tio --list
```

## 動作確認

別端末でシリアルログを開きます。

```sh
tio /dev/ttyACM0
```

書き込み後、画面上で顔が動いて表示されれば成功です。
