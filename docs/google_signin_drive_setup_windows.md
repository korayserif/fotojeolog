# Google Sign-In + Google Drive Kurulum Rehberi (Windows/Android)

Bu proje Android tarafında Google ile oturum açıp Google Drive'a yükleme yapıyor. "ApiException: 10 (DEVELOPER_ERROR)" hatası alıyorsanız, aşağıdaki adımları eksiksiz tamamlayın.

## 0) Proje Kimliği
- Android uygulama kimliği (package name): `com.example.yeni_clean`
- Bu paket adıyla Firebase'de Android uygulaması ekli olmalı.

## 1) SHA-1 ve SHA-256 Parmak İzleri
Android debug build için SHA-1 ve SHA-256 değerlerini eklemeniz gerekir.

### Yöntem A — Gradle signingReport (önerilen)
CMD (cmd.exe) açın ve:

```bat
cd /d "c:\asistan deneme - Kopya\fotojeolog\android"
gradlew.bat signingReport
```

Çıktıda `Variant: debug` altında `SHA1` ve `SHA-256` satırlarını kopyalayın.

### Yöntem B — keytool (alternatif)
JDK kuruluysa (veya Android Studio'nun jbr’ı):

```bat
keytool -list -v -alias androiddebugkey -keystore %USERPROFILE%\.android\debug.keystore -storepass android -keypass android
```

Keytool bulunamazsa şu konumdaki keytool'u deneyin (Android Studio sürümüne göre değişebilir):

```bat
"C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -list -v -alias androiddebugkey -keystore %USERPROFILE%\.android\debug.keystore -storepass android -keypass android
```

Release imzası da kullanılacaksa kendi keystore’unuzun SHA’larını da ekleyin:

```bat
keytool -list -v -keystore "c:\asistan deneme - Kopya\fotojeolog\android\keystore\fotojeolog.keystore" -alias <keyAlias> -storepass <storePassword> -keypass <keyPassword>
```

## 2) Firebase Console Ayarları
- Firebase Console > Projekt Ayarları (Settings) > Your apps > Android
  - App package name: `com.example.yeni_clean`
  - `SHA certificate fingerprints` bölümüne az önce aldığınız **SHA-1** ve **SHA-256** değerlerini ekleyin
- Authentication > Sign-in method > Google = Enabled
- Kaydedin ve yeni `google-services.json` dosyasını indirin
- Dosyayı projede `android/app/google-services.json` üzerine yazın (mevcut template dosyayı değiştirin).

## 3) Google Drive API'yi Etkinleştirin
- Google Cloud Console (Firebase projesi aynı hesap/organizasyonda):
  - APIs & Services > Library > `Google Drive API` aratın ve **Enable** yapın.

## 4) Emülatör Kontrolleri
- Emülatörde Google hesabı ekli olsun:
  - Settings > Accounts (veya Passwords & Accounts) > Add account > Google
- Google Play Services ve Play Store güncel olsun (Play Store’u açıp güncelleyin)
- Sistem imajı `Google APIs` içersin (AOSP değil). Gerekirse yeni bir AVD oluşturun.
- Giriş hâlâ başarısızsa Play Services’in verisini temizlemeyi deneyin (Settings > Apps > Google Play services > Storage > Clear storage) ve emülatörü yeniden başlatın.

## 5) Temizle ve Yeniden Derle
Proje kökünde:

```bat
flutter clean
flutter pub get
flutter run -d emulator-5554
```

## 6) Başarılı Çalışma Kriteri
- Ana sayfadaki "Drive’a giriş yap" butonuna bastığınızda Google hesap seçimi gelir.
- Hesabı seçtikten sonra üst bölümde e-posta görünüyor olmalı ve "Google Drive girişi başarılı!" mesajı çıkmalı.
- Hata 10 (DEVELOPER_ERROR) görülüyorsa 1-2-5. adımları yeniden kontrol edin; özellikle paket adı, **SHA-1/256** ve `google-services.json`.

## Sorun Giderme
- `ApiException: 10`: Paket adı/SHA/`google-services.json` eşleşmiyor.
- `signIn()` hiç açılmıyor: Emülatörde Google hesabı yok veya Play Services eski.
- Drive yüklemeleri 403 hatası: Drive API etkin değil (bkz. adım 3).

Bu rehberi takip ettikten sonra girişin tamamlanması gerekir. Yine sorun yaşarsanız `gradlew signingReport` çıktısını ve `google-services.json` (gizli anahtarları kaldırarak) paylaşın; doğrulayıp yönlendirebilirim.
