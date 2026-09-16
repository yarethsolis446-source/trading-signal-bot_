# Trading Signal Bot — iOS reconstruction

This project is a new Flutter reconstruction based on the supplied `app-release.apk`.

## Important

The APK does not contain the original Dart source tree (`lib/main.dart`, `pubspec.yaml`, `ios/`, etc.). The project here therefore reproduces the recoverable behavior and UI structure; it is not the original source code byte-for-byte.

Recoverable behavior used:
- Flutter application.
- Direct Biquote REST API.
- Biquote SignalR tick endpoint.
- 1-minute OHLC analysis.
- CALL / PUT / WAIT signal presentation.
- Entry countdown.
- Syncfusion candlestick chart.
- Asset and timeframe selectors.
- EMA20 / EMA50 / RSI / MACD / ADX display.
- Original APK icon extracted from the supplied APK.

## Build on a Mac

1. Install Flutter and Xcode.
2. From this directory:
   `flutter pub get`
3. Open `ios/Runner.xcworkspace` after Flutter creates the iOS files.
4. Set a unique Bundle Identifier in Xcode.
5. Sign in with your Apple Developer account.
6. Test:
   `flutter run -d <your-iphone>`
7. Build:
   `flutter build ipa --release`

For TestFlight/App Store distribution, archive/upload through Xcode or App Store Connect after configuring signing.

## Windows

Windows can edit this project, but official iOS compilation/signing requires macOS/Xcode.
