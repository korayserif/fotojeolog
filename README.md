# FotoJeolog

Jeoloji çalışmaları için fotoğraf çizim uygulaması (Flutter).

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## CI/CD

### iOS Build (Unsigned IPA)
GitHub Actions’daki `iOS Build` workflow’u imzasız IPA oluşturur ve artefact olarak yükler.

### TestFlight (Signed & Upload)
`iOS TestFlight` workflow’u imzalı IPA üretip TestFlight’a yükler. Çalışması için GitHub Secrets altında aşağıdaki anahtarları tanımlayın:

- APPLE_TEAM_ID: Apple Developer Team ID
- ASC_ISSUER_ID: App Store Connect API Issuer ID
- ASC_KEY_ID: App Store Connect API Key ID
- ASC_API_KEY_P8: App Store Connect API .p8 içeriği (base64)
- IOS_CERT_P12: iOS dağıtım sertifikası (.p12) base64
- IOS_CERT_PASSWORD: .p12 şifresi
- IOS_PROVISIONING_PROFILE: App Store (Distribution) provisioning profile (base64)

Sonra Actions > `iOS TestFlight` > Run workflow ile tetikleyebilirsiniz.

## Android: İmzalı APK/Bundle

1) Keystore oluştur (Windows cmd):
	- JDK yüklü olsun, sonra:
	  - `keytool -genkey -v -keystore android\keystore\fotojeolog.keystore -alias fotojeolog -keyalg RSA -keysize 2048 -validity 36500`
	- Doldurduğun parola ve alias’ı not et.

2) `android/key.properties` dosyasını oluştur:
	- `android/key.properties.sample` dosyasını kopyalayıp parolaları doldur.

3) İmzalı derleme:
	- APK: `flutter build apk --release`
	- App Bundle: `flutter build appbundle --release`

Oluşan dosyalar:
 - APK: `build/app/outputs/flutter-apk/app-release.apk`
 - AAB: `build/app/outputs/bundle/release/app-release.aab`
