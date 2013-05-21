ZFS バックアップスクリプト
======================================================================

  * Copyright (c) 2011-2013 SATOH Fumiyasu @ OSS Technology Corp., Japan
  * License: GNU General Public License version 3
  * URL: <https://GitHub.com/fumiyas/zfs-backup>
  * Twitter: <https://twitter.com/satoh_fumiyasu>

使い方
----------------------------------------------------------------------

    /usr/local/sbin/zfs-backup [オプション] バックアップ対象 バックアップ先

説明
----------------------------------------------------------------------

ZFS のスナップショット作成機能 (zfs snapshot) と差分転送機能
(zfs send, zfs receive) を利用したZFS 用のバックアップスクリプトです。
「バックアップ対象」と「バックアップ先」には ZFS の名前もしくはマウント
場所を指定します。SSH を介してのリモートホスト上の ZFS も指定可能です。
その場合は「ホスト名:バックアップ対象」、「ホスト名:バックアップ先」の
ように指定します。

実行すると以下のような動作を行います:

  1. バックアップ対象の ZFS のスナップショットを作成する。
  2. 前回のスナップショットとの差分をバックアップ先 ZFS に転送する。
  3. バックアップ対象 ZFS の古いスナップショットを削除する。
  4. バックアップ先 ZFS の古いスナップショットを削除する。

オプション
----------------------------------------------------------------------

### -n, --no-run

実際のバックアップ処理を実行しません。--verbose
オプションと組み合わせて動作内容を確認したいときに有用です。

### -v, --verbose

冗長な情報を出力します。

### -N, --no-create-snapshot

バックアップ対象のスナップショットを作成しません。

バックアップ対象を複数のバックアップ先にバックアップする場合、
二箇所目以降のバックアップを行なうときにこのオプションを指定
するとよいでしょう。

### -R, --recursive

バックアップ対象配下のすべての ZFS もバックアップします。

### -p, --property

ZFS のプロパティもバックアップします。

### -t, --target-snapshot-limit NUMBER

バックアップ対象に保持しておくスナップショットの最大数です。
これを超える数のスナップショットは古いものから順番に削除されます。
0 以下を指定するとスナップショットは削除されません。 (既定値: 31)

### -b, --backup-snapshot-limit NUMBER

バックアップ先に保持しておくスナップショットの最大数です。
これを超える数のスナップショットは古いものから順番に削除されます。
0 以下を指定するとスナップショットは削除されません。(既定値: 31)

TODO
----------------------------------------------------------------------

  * dd を挟む。
    https://twitter.com/satoh_fumiyasu/statuses/277085637633507328

