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
<<<<<<< HEAD
=======

Wi-Fi 情報を設定している場合は、あわせて Wi-Fi 接続と Distributed Erlang の起動ログも表示されます。

例:

```text
wifi: first-time provision (stored Wi-Fi credentials in NVS)
wifi: connected to AP
wifi: got IP {{192,168,1,123},{255,255,255,0},{192,168,1,1}}
disterl: started
disterl: node :"piyopiyo@192.168.1.123"
disterl: cookie <<"AtomVM">>
disterl: registered process :disterl
sntp: synced {tv_sec, tv_usec}
```

Wi-Fi 情報を設定せずに書き込んだ場合でも、顔表示そのものは動作します。
その場合、Wi-Fi と Distributed Erlang は起動せず、シリアルログにその旨が表示されます。

## リモート操作

Wi-Fi と Distributed Erlang が起動していれば、別端末の IEx から顔を変更できます。

まず、開発端末側で IEx をノード名付きで起動します。
`YOUR_HOST_LAN_IP` には、ESP32 と同じネットワーク上の開発端末の IP アドレスを指定してください。

```sh
iex --name host@YOUR_HOST_LAN_IP --cookie AtomVM
```

次に IEx 上で ESP32 ノードへ接続します。
`YOUR_ESP32_IP` には、シリアルログに表示された IP アドレスを指定してください。

```elixir
device = :"piyopiyo@YOUR_ESP32_IP"

Node.connect(device)
Node.list(:connected)

:erpc.call(device, SampleApp.DistErl, :hello, [])
:erpc.call(device, SampleApp.DistErl, :set_expression, [:happy])
:erpc.call(device, SampleApp.DistErl, :set_gaze, [0.8, -0.4])
:erpc.call(device, SampleApp.DistErl, :set_mouth_open, [0.9])
:erpc.call(device, SampleApp.DistErl, :get_face_state, [])
send({:disterl, device}, :demo_message)
```

期待される動作:

- `Node.connect(device)` が `true` を返す
- `Node.list(:connected)` に `device` が含まれる
- `:erpc.call(device, SampleApp.DistErl, :hello, [])` が `{:hello_from_atomvm, :"piyopiyo@192.168.1.123"}` のような値を返す
- `send({:disterl, device}, :demo_message)` により ESP32 側で `disterl: received :demo_message` が表示される

表情には次を指定できます。

- `:neutral`
- `:happy`
- `:angry`
- `:sad`
- `:doubt`
- `:sleepy`

## Wi-Fi プロビジョニング

Wi-Fi 情報は起動時に NVS へ保存され、次回以降の起動でも再利用されます。

### 環境変数

| 環境変数                 | NVS キー          | 説明                                                        |
| ------------------------ | ----------------- | ----------------------------------------------------------- |
| `ATOMVM_WIFI_SSID`       | `wifi_ssid`       | 保存する Wi-Fi SSID                                         |
| `ATOMVM_WIFI_PASSPHRASE` | `wifi_passphrase` | 保存する Wi-Fi パスフレーズ。オープンネットワークでは省略可 |
| `ATOMVM_WIFI_FORCE`      | —                 | 設定されていると、起動時に認証情報を上書きする              |

### 挙動

- 初回起動時
  - `ATOMVM_WIFI_SSID` が設定されていれば NVS に保存される
- 2 回目以降の起動
  - NVS に保存済みの情報を再利用する
- `ATOMVM_WIFI_FORCE` を設定した場合
  - 起動のたびに NVS の認証情報を上書きする
  - パスフレーズ未指定で上書きすると、既存のパスフレーズは削除される

## 参考情報

- AtomVM Distributed Erlang guide
  - https://doc.atomvm.org/main/distributed-erlang.html
- AtomVM Getting Started Guide
  - https://doc.atomvm.org/main/getting-started-guide.html
>>>>>>> 118072c (chore: lock atomlgfx down to v1)
