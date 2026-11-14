# 問い合わせ先・製品版公開時の設定

- 共通窓口：kojinapp.support@gmail.com
- 共通フォーム：https://docs.google.com/forms/d/e/1FAIpQLSdelw1zoYyDkDhv1JgkTIPrD26dQwMW9S0c3WKh73iUE52Hfg/viewform
- サポートURL：https://coolcoolboys-svg.github.io/noreru-bus-support/

製品版・TestFlightはこのブランチの最新コミットから作成すること。既存のIPAに変更は反映されないため再ビルドが必要。
ビルド前に `python3 scripts/verify-support-contact.py` を実行する。Codemagicでも同じ検査を実行する。

App Store Connectで次回アップロード・提出する際は、問い合わせ用の公開メール、App Reviewの連絡先メール、TestFlightのフィードバック用メール・Beta App Review連絡先を kojinapp.support@gmail.com にする。サポートURLは上記、プライバシーポリシーは各アプリの既存URLを使う。設定値は release-support.json を参照する。
このファイルはストア側の設定変更を自動実行しない。アップロード・提出時に既存の値を確認して反映する。
Apple ID、署名、Google広告のログイン、通知先として別途指定された開発用メールは問い合わせ先とは独立して管理する。
