# Firebase E-posta Bazlı İzolasyon - Kurulum Rehberi

## Yapılan Değişiklikler

Bu güncelleme ile Firebase uygulamanızda **e-posta bazlı izolasyon** sağlanmıştır. Aynı e-posta ile giriş yapan kullanıcılar ortak çalışma alanını paylaşır, farklı e-postalar izole kalır.

### 🔧 Teknik Değişiklikler

#### 1. Firebase Storage Yapısı
**Eski Yapı:**
```
fotojeolog_saha_arsivi/
├── foto1.jpg
├── foto2.jpg
└── ...
```

**Yeni Yapı (E-posta Bazlı):**
```
fotojeolog_saha_arsivi/
├── emails/
│   ├── 123_at_123_dot_com/
│   │   ├── foto1.jpg (5 arkadaş ortak görür)
│   │   └── foto2.jpg (5 arkadaş ortak görür)
│   └── 11_at_11_dot_com/
│       ├── foto3.jpg (sadece 11@11.com kullanıcıları)
│       └── foto4.jpg (sadece 11@11.com kullanıcıları)
```

#### 2. Güncellenen Dosyalar
- `lib/services/firebase_storage_service.dart` - E-posta bazlı klasör yapısı
- `lib/services/firebase_auth_service.dart` - Geliştirilmiş çıkış işlevi
- `lib/firebase_archive_page.dart` - E-posta bazlı veri listeleme
- `lib/firebase_login_page.dart` - Çıkış butonu eklendi
- `lib/settings_page.dart` - Geliştirilmiş çıkış işlevi

#### 3. Yeni Güvenlik Kuralları
- `firestore.rules` - Firestore güvenlik kuralları
- `storage.rules` - Firebase Storage güvenlik kuralları

## 🚀 Kurulum Adımları

### 1. Firebase Console'da Güvenlik Kurallarını Güncelleyin

#### Firestore Rules:
1. Firebase Console → Firestore Database → Rules
2. `firestore.rules` dosyasının içeriğini kopyalayın
3. Değişiklikleri yayınlayın

#### Storage Rules:
1. Firebase Console → Storage → Rules
2. `storage.rules` dosyasının içeriğini kopyalayın
3. Değişiklikleri yayınlayın

### 2. Uygulamayı Test Edin

1. **Ortak Çalışma Testi (123@123.com):**
   - `123@123.com` ile giriş yapın
   - Mevcut fotoğrafları görün
   - Yeni fotoğraf yükleyin
   - **5 arkadaş aynı e-posta ile giriş yaparsa aynı fotoğrafları görecek**

2. **Farklı E-posta Testi (11@11.com):**
   - Çıkış yapın
   - `11@11.com` ile kayıt olun
   - Boş galeri görmelisiniz (123@123.com'un fotoğrafları görünmez)
   - Yeni fotoğraf yükleyin

3. **E-posta Değiştirme Testi:**
   - 11@11.com'dan çıkış yapın
   - 123@123.com ile giriş yapın
   - Sadece 123@123.com'un fotoğraflarını görmelisiniz

## 🔒 Güvenlik Özellikleri

### E-posta Bazlı İzolasyon
- Aynı e-posta ile giriş yapan kullanıcılar ortak çalışma alanını paylaşır
- Farklı e-postalar birbirlerinin verilerini göremez
- Güvenlik kuralları Firebase seviyesinde uygulanır

### Oturum Yönetimi
- Çıkış yapıldığında tüm kullanıcı verileri temizlenir
- Yeni giriş yapıldığında izole oturum başlar
- Otomatik giriş sadece anonim kullanıcılar için

## 📱 Kullanıcı Deneyimi

### Çıkış İşlemi
- Tüm sayfalarda çıkış butonu mevcut
- Çıkış yapıldığında login sayfasına yönlendirme
- Başarı/hata mesajları

### Veri Yönetimi
- E-posta bazlı klasör yapısı
- Otomatik klasör oluşturma
- Ortak çalışma desteği
- Geriye uyumlu eski metodlar

## ⚠️ Önemli Notlar

1. **Eski Veriler:** Mevcut fotoğraflarınız eski yapıda kalacak, ancak yeni yüklemeler e-posta bazlı klasörlere gidecek.

2. **Güvenlik Kuralları:** Mutlaka Firebase Console'da güvenlik kurallarını güncelleyin.

3. **Test:** Üretim ortamına geçmeden önce tüm senaryoları test edin.

## 🐛 Sorun Giderme

### E-posta Verilerini Göremiyorum
- Firebase Console'da güvenlik kurallarının güncellendiğini kontrol edin
- Kullanıcının doğru e-posta ile giriş yaptığını kontrol edin

### Çıkış Yapamıyorum
- Uygulamayı yeniden başlatın
- Firebase Auth durumunu kontrol edin

### Yeni Fotoğraf Yükleyemiyorum
- E-posta klasörünün oluşturulduğunu kontrol edin
- Storage güvenlik kurallarının doğru olduğunu kontrol edin

## 📞 Destek

Herhangi bir sorun yaşarsanız, lütfen hata mesajlarını ve adımları paylaşın.
