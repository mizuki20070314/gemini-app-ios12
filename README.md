# Gemini for iOS 12

iOS 12 (iPod touch 第6世代 / iPad mini 2 など) 向けの **非公式・端末完結型** Gemini クライアントです。外部中継サーバーを必要とせず、端末から直接 `gemini.google.com` および `geminiweb-pa.clients6.google.com/v1/processSession`（WebChannel）と通信する `gemini-web2api` 同等のプロトコルを Swift 5 + UIKit（外部依存ゼロ）で実装しています。

## 主な機能

- **端末完結型 Gemini Web プロトコル**:
  - **ゲストモード**: ログイン不要ですぐに起動・チャット可能（`3.5 Flash-Lite` / `Auto`）。
  - **Google アカウントログイン**: アプリ内 WKWebView ログイン、または Cookie ヘッダー / `gemini-web2api` JSON インポートに対応（Keychain 保存）。
  - **マルチアカウント `/u/N`・Cookie 自動ローテーション (`RotateCookies`)** 対応。
  - **動的モデルカタログ (`otAQ7b`)**: アカウントで利用可能な全モデル（`4 Hydrogen`, `4 Carbon`, `4 Argon`, `3.5 Flash-Lite`, `Auto` 等）、公式ツール（`Nano Banana 2` 画像生成, `Canvas`, `Guided Learning`）、および **Gems (`CNgdBe`)** を自動取得。
  - **WebChannel リアルタイムストリーミング**: 思考プロセス（Thinking）表示・推論強度切替（Low / Medium / High）、マルチターン会話継続（CID / RID / RCID / Token）、途中停止 (`NkpXw`)。
  - **画像・テキストファイル添付**: `push.clients6.google.com/upload/` + `ProcessFile` によるネイティブアップロード。
  - **生成画像の自動取得・表示・保存**: `c8o8Fe` + `?alr=yes` リレー解決による高画質画像プレビュー＆カメラロール保存。
  - **引用ソース（Citations）表示 & Markdown / コードブロック（シンタックスハイライト・コピー対応）**。
- **UI**:
  - Gemini デザインのライト / ダークテーマ。
  - 会話履歴のローカル保存・検索・ピン留め・リネーム・削除。
  - iPod touch / iPhone スライドドロワー＆iPad 常時表示サイドバー。

## 動作要件・ビルド

- iOS 12.0 以上 / arm64
- GitHub Actions (`macos-15` / Xcode 16.4 / XcodeGen) により未署名 IPA を自動ビルドします。
