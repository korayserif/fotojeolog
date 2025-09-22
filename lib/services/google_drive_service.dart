import 'dart:io';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();
  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }
}

class GoogleDriveService {
  GoogleDriveService._();
  static final GoogleDriveService instance = GoogleDriveService._();

  // Sınırlı Drive erişimi - sadece uygulama dosyalarına erişim
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: <String>[
      'https://www.googleapis.com/auth/drive.file',     // Sadece uygulama tarafından oluşturulan dosyalar
      'https://www.googleapis.com/auth/userinfo.email', // Email bilgisine erişim
    ],
    forceCodeForRefreshToken: false, // Sessiz girişe izin ver
  );

  drive.DriveApi? _driveApi;
  GoogleSignInAccount? _user;
  SharedPreferences? _prefs;
  
  // Klasör ID'lerini cache'lemek için - "parentId/folderName" -> "folderId"
  final Map<String, String> _folderCache = {};

  // Son hata bilgileri (UI'da gösterim için)
  int? lastErrorCode;
  String? lastError;

  // Mevcut kullanıcı bilgisine erişim
  GoogleSignInAccount? get currentUser => _user;

  static const _cloudSyncKey = 'cloud_sync_enabled';
  static const _allowedEmailKey = 'allowed_email';
  static const _sharedFolderKey = 'shared_folder_id';
  // Tüm Google hesaplarına izin ver (kısıtlama kaldırıldı)
  static const String? defaultAllowedEmail = null;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    // Email kısıtlaması kaldırıldı - tüm hesaplara izin ver
    // Eski email kısıtlamasını temizle
    await _prefs!.remove(_allowedEmailKey);
    // Mevcut oturumu sessiz geri yüklemeyi dene
    _user = await _googleSignIn.signInSilently();
    if (_user != null) {
      await _initDriveApi();
    }
  }

  // Email kısıtlaması kaldırıldı - tüm hesaplara izin ver
  Future<void> setAllowedEmail(String? email) async {
    _prefs ??= await SharedPreferences.getInstance();
    // Her durumda email kısıtlamasını kaldır
    await _prefs!.remove(_allowedEmailKey);
  }

  String? get allowedEmail => null; // Email kısıtlaması kaldırıldı

  bool get isSignedIn => _user != null;

  String? get userEmail => _user?.email;
  
  String? get email => _user?.email;
  
  String? get displayName => _user?.displayName;
  
  bool get cloudSyncEnabled {
    // Bu getter'ı sync yapmak için basit çözüm
    return _prefs?.getBool(_cloudSyncKey) ?? false;
  }
  
  Future<bool> get cloudSyncEnabledAsync async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!.getBool(_cloudSyncKey) ?? false;
  }

  Future<void> _initDriveApi() async {
    if (_user == null) return;
    
    try {
      final headers = await _user!.authHeaders;
      final client = _GoogleAuthClient(headers);
      _driveApi = drive.DriveApi(client);
      
      print('Drive API başlatıldı: ${_user!.email}');
      
      // Gereksiz FotoJeolog klasörlerini temizle
      await cleanupDuplicateFotojeologFolders();
      
    } catch (e) {
      print('Drive API başlatma hatası: $e');
      lastError = 'Drive API başlatma hatası: $e';
      lastErrorCode = 3;
      _driveApi = null;
    }
  }

  // Kullanıcıdan ek kapsamları (scopes) istemek için incremental consent.
  Future<bool> _ensureDriveScopes() async {
    try {
      final ok = await _googleSignIn.requestScopes(const [
        'https://www.googleapis.com/auth/drive.file',
        'https://www.googleapis.com/auth/userinfo.email',
      ]);
      if (!ok) {
        lastError = 'Drive izinleri verilmedi. Lütfen izinleri onaylayın.';
        lastErrorCode = 403;
        return false;
      }
      // Token yenilenmiş olabilir; Drive API'yi tekrar başlat.
      await _initDriveApi();
      return true;
    } catch (e) {
      lastError = 'İzin isteme hatası: $e';
      lastErrorCode = 999;
      return false;
    }
  }

  // Drive erişimini test et
  Future<void> _testDriveAccess() async {
    if (_driveApi == null) return;
    
    try {
      print('Drive API erişimi test ediliyor...');
      await _driveApi!.files.list(
        pageSize: 1,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );
      print('✅ Drive API erişimi başarılı');
    } catch (e) {
      print('❌ Drive API test hatası: $e');
      final es = e.toString();
      if (es.contains('403') && es.contains('drive.googleapis.com')) {
        lastErrorCode = 403;
        lastError = 'Google Drive API bu projede devre dışı. Lütfen Drive API\'yi etkinleştirip tekrar deneyin.'
            '\nAç: https://console.developers.google.com/apis/api/drive.googleapis.com/overview?project=835803975625';
      }
      throw Exception('Drive API erişim hatası: $e');
    }
  }

  Future<bool> signInSilently() async {
    try {
      // Önce sessiz giriş dene (önceki oturum varsa)
      _user = await _googleSignIn.signInSilently();
      
      if (_user == null) {
        // Sessiz giriş başarısız, manuel giriş yap
        return await signIn();
      }
      
      print('✅ Google kullanıcı sessiz girişi başarılı: ${_user!.email}');
      
      // Drive API'yi başlat ve gerekli izinleri al
      await _initDriveApi();
      final granted = await _ensureDriveScopes();
      if (!granted) {
        lastError = 'Drive izinleri alınamadı';
        lastErrorCode = 403;
        return false;
      }
      
      return true;
    } catch (e) {
      print('❌ Sessiz giriş hatası: $e');
      lastError = 'Sessiz giriş hatası: $e';
      lastErrorCode = 1;
      return false;
    }
  }

  Future<bool> signIn() async {
    try {
      // Her zaman kullanıcıdan hesap seçmesini iste
      print('OAuth2.0 manuel giriş başlatılıyor...');
      print('İzin talep edilen kapsamlar:');
      print('- Google Drive (sadece uygulama dosyaları)');
      print('- Email bilgisi');
      print('- Profil bilgisi');
      
      _user = await _googleSignIn.signIn();
      if (_user == null) {
        // Kullanıcı iptal etti veya başarısız oldu
        lastError = 'Kullanıcı giriş yapmayı iptal etti';
        lastErrorCode = null;
        return false;
      }
      
      print('✅ Google kullanıcı girişi başarılı: ${_user!.email}');

      // Email kısıtlaması kaldırıldı - tüm Google hesaplarına izin ver
      
      // Drive API'yi başlat ve gerekli izinleri al
      await _initDriveApi();
      final granted = await _ensureDriveScopes();
      if (!granted) {
        return false;
      }

      // Drive erişimini test et
      await _testDriveAccess();
      
      lastError = null;
      lastErrorCode = null;
      return true;
    } on PlatformException catch (e) {
      print('❌ PlatformException: ${e.code} - ${e.message}');
      
      if (e.code == 'sign_in_required') {
        lastError = 'Google hesabınızla giriş yapmanız gerekiyor';
      } else if (e.code == 'permission_denied') {
        lastError = 'İzinler reddedildi. Lütfen Drive erişimine izin verin';
      } else {
        lastError = 'OAuth2.0 hatası: ${e.message}';
      }
      
      lastErrorCode = int.tryParse(e.code) ?? 999;
      return false;
    } catch (e) {
      print('❌ Google Sign-In genel hatası: $e');
      lastError = 'Giriş hatası: $e';
      lastErrorCode = 999;
      return false;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _user = null;
    _driveApi = null;
    lastError = null;
    lastErrorCode = null;
  }

  // UI'ların Image.network için Authorization header'a erişebilmesi adına yardımcı
  Future<Map<String, String>?> getAuthHeaders() async {
    try {
      _user ??= await _googleSignIn.signInSilently();
      if (_user == null) return null;
      final headers = await _user!.authHeaders;
      return headers;
    } catch (_) {
      return null;
    }
  }

  Future<bool> get isCloudSyncEnabled async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!.getBool(_cloudSyncKey) ?? false;
  }

  Future<void> setCloudSyncEnabled(bool enabled) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(_cloudSyncKey, enabled);
  }

  Future<String> _ensureFolderPath(List<String> pathParts) async {
    if (_driveApi == null) await _initDriveApi();

    print('🔍 _ensureFolderPath çağrıldı: $pathParts');

    // Tam path'i oluştur: FotoJeolog/pathParts[0]/pathParts[1]/...
    final fullPath = ['FotoJeolog', ...pathParts];
    print('🔍 Tam path: $fullPath');

    // Cache key oluştur
    final cacheKey = fullPath.join('/');
    if (_folderCache.containsKey(cacheKey)) {
      final cachedId = _folderCache[cacheKey]!;
      print('💾 Cache\'den bulundu: $cacheKey (ID: $cachedId)');
      return cachedId;
    }

    // Ortak klasör yapısı: FotoJeolog/[pathParts...] - Tüm kullanıcılar aynı klasörleri görür
    String currentParentId = 'root';
    
    // Tüm path'i tek seferde oluştur
    for (int i = 0; i < fullPath.length; i++) {
      final folderName = fullPath[i];
      print('📁 $i. klasör oluşturuluyor/alınıyor: "$folderName" (parent: $currentParentId)');
      currentParentId = await _ensureFolder(folderName, currentParentId);
      print('✅ $i. klasör ID: $currentParentId');
    }

    // Cache'e kaydet
    _folderCache[cacheKey] = currentParentId;
    print('🎯 Final klasör ID: $currentParentId (cache\'e kaydedildi: $cacheKey)');
    return currentParentId;
  }
  
  Future<String> _ensureFolder(String folderName, String parentId) async {
    if (_driveApi == null) await _initDriveApi();
    final api = _driveApi!;
    
    // Cache key oluştur
    final cacheKey = '$parentId/$folderName';
    
    // Önce cache'den kontrol et
    if (_folderCache.containsKey(cacheKey)) {
      final cachedId = _folderCache[cacheKey]!;
      print('💾 Cache\'den bulundu: "$folderName" (ID: $cachedId)');
      return cachedId;
    }
    
    print('🔍 _ensureFolder: "$folderName" klasörü aranıyor (parent: $parentId)');
    
    // Önce mevcut klasörü bulmaya çalış
    String? existingId = await _findExistingFolder(folderName, parentId);
    
    if (existingId != null) {
      print('✅ Mevcut klasör bulundu: "$folderName" (ID: $existingId)');
      // Cache'e kaydet
      _folderCache[cacheKey] = existingId;
      return existingId;
    }
    
    // Klasör bulunamadı, yeni oluştur
    print('🆕 Yeni klasör oluşturuluyor: "$folderName" (parent: $parentId)');
    try {
      final folder = drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [parentId];
      final created = await api.files.create(folder);
      final newId = created.id!;
      print('✅ Yeni klasör oluşturuldu: "$folderName" (ID: $newId)');
      // Cache'e kaydet
      _folderCache[cacheKey] = newId;
      return newId;
    } catch (e) {
      print('❌ Klasör oluşturma hatası: $e');
      rethrow;
    }
  }
  
  /// Cache'i temizle (eski klasör yapılarını kaldırmak için)
  void clearFolderCache() {
    _folderCache.clear();
    print('🧹 Google Drive klasör cache\'i temizlendi');
  }

  /// Gereksiz FotoJeolog klasörlerini sil (sadece aktif olanı bırak)
  Future<void> cleanupDuplicateFotojeologFolders() async {
    try {
      if (!isSignedIn) return;
      if (_driveApi == null) await _initDriveApi();
      
      print('🧹 Gereksiz FotoJeolog klasörleri temizleniyor...');
      
      // Tüm FotoJeolog klasörlerini bul
      final query = "name='FotoJeolog' and mimeType='application/vnd.google-apps.folder' and trashed=false";
      final response = await _driveApi!.files.list(
        q: query,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
        spaces: 'drive',
        $fields: 'files(id, name, createdTime, modifiedTime)',
      );
      
      if (response.files == null || response.files!.isEmpty) {
        print('📁 FotoJeolog klasörü bulunamadı');
        return;
      }
      
      print('📁 ${response.files!.length} FotoJeolog klasörü bulundu');
      
      if (response.files!.length <= 1) {
        print('✅ Sadece 1 FotoJeolog klasörü var, temizlik gerekmiyor');
        return;
      }
      
      // En son değiştirilen klasörü bul (aktif olan)
      String? activeFolderId;
      DateTime? latestModified;
      
      for (final folder in response.files!) {
        final modifiedTime = folder.modifiedTime;
        if (modifiedTime != null) {
          try {
            final modified = modifiedTime;
            if (latestModified == null || modified.isAfter(latestModified)) {
              latestModified = modified;
              activeFolderId = folder.id!;
            }
          } catch (e) {
            print('❌ Tarih işleme hatası: $modifiedTime - $e');
          }
        }
      }
      
      if (activeFolderId == null) {
        print('❌ Aktif klasör belirlenemedi');
        return;
      }
      
      print('✅ Aktif klasör belirlendi: $activeFolderId');
      
      // Diğer klasörleri sil
      int deletedCount = 0;
      for (final folder in response.files!) {
        if (folder.id != activeFolderId) {
          try {
            print('🗑️ Gereksiz klasör siliniyor: ${folder.id}');
            await _driveApi!.files.delete(folder.id!);
            deletedCount++;
            print('✅ Klasör silindi: ${folder.id}');
          } catch (e) {
            print('❌ Klasör silme hatası (${folder.id}): $e');
          }
        }
      }
      
      print('✅ Temizlik tamamlandı: $deletedCount klasör silindi');
      
      // Cache'i temizle
      clearFolderCache();
      
    } catch (e) {
      print('❌ Gereksiz klasör temizleme hatası: $e');
    }
  }

  /// Boş klasörleri otomatik sil
  Future<void> deleteEmptyFolders() async {
    try {
      if (!isSignedIn) return;
      if (_driveApi == null) await _initDriveApi();
      
      print('🧹 Boş klasörler kontrol ediliyor...');
      
      // FotoJeolog klasörlerini bul
      final query = "name='FotoJeolog' and mimeType='application/vnd.google-apps.folder' and trashed=false";
      final response = await _driveApi!.files.list(
        q: query,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
        spaces: 'drive',
        $fields: 'files(id, name)',
      );
      
      if (response.files == null || response.files!.isEmpty) {
        print('📁 FotoJeolog klasörü bulunamadı');
        return;
      }
      
      print('📁 ${response.files!.length} FotoJeolog klasörü bulundu');
      
      for (final fotojeologFolder in response.files!) {
        print('🔍 FotoJeolog klasörü kontrol ediliyor: ${fotojeologFolder.name} (${fotojeologFolder.id})');
        await _deleteEmptyFoldersRecursively(fotojeologFolder.id!);
      }
      
      print('✅ Boş klasör kontrolü tamamlandı');
    } catch (e) {
      print('❌ Boş klasör silme hatası: $e');
    }
  }

  /// Klasörü ve alt klasörlerini boş olup olmadığını kontrol et ve boş olanları sil
  Future<void> _deleteEmptyFoldersRecursively(String folderId) async {
    try {
      // Bu klasörün içindeki dosya ve klasörleri listele
      final query = "'$folderId' in parents and trashed=false";
      final response = await _driveApi!.files.list(
        q: query,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
        spaces: 'drive',
        $fields: 'files(id, name, mimeType)',
      );
      
      if (response.files == null) {
        print('🔍 Klasör içeriği alınamadı: $folderId');
        return;
      }
      
      print('🔍 Klasör $folderId içeriği: ${response.files!.length} öğe');
      
      // Alt klasörleri önce kontrol et
      final folders = response.files!.where((f) => f.mimeType == 'application/vnd.google-apps.folder').toList();
      print('📁 Alt klasör sayısı: ${folders.length}');
      
      for (final folder in folders) {
        print('🔍 Alt klasör kontrol ediliyor: ${folder.name} (${folder.id})');
        await _deleteEmptyFoldersRecursively(folder.id!);
      }
      
      // Tekrar kontrol et (alt klasörler silinmiş olabilir)
      final updatedResponse = await _driveApi!.files.list(
        q: query,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
        spaces: 'drive',
        $fields: 'files(id, name, mimeType)',
      );
      
      if (updatedResponse.files == null || updatedResponse.files!.isEmpty) {
        // Klasör boş, sil
        print('🗑️ Boş klasör siliniyor: $folderId');
        await _driveApi!.files.delete(folderId);
        print('✅ Boş klasör silindi: $folderId');
        
        // Cache'den de kaldır
        _folderCache.removeWhere((key, value) => value == folderId);
      } else {
        print('📁 Klasör dolu, silinmedi: $folderId (${updatedResponse.files!.length} öğe)');
      }
    } catch (e) {
      print('❌ Klasör silme hatası ($folderId): $e');
    }
  }
  
  // Mevcut klasörü bulmak için ayrı fonksiyon
  Future<String?> _findExistingFolder(String folderName, String parentId) async {
    if (_driveApi == null) await _initDriveApi();
    final api = _driveApi!;
    
    try {
      // Farklı sorgu yöntemleri dene
      final queries = [
        "name='$folderName' and '$parentId' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false",
        "name='$folderName' and parents in '$parentId' and mimeType='application/vnd.google-apps.folder' and trashed=false",
        "name='$folderName' and mimeType='application/vnd.google-apps.folder' and trashed=false"
      ];
      
      for (int i = 0; i < queries.length; i++) {
        final query = queries[i];
        print('🔍 Arama sorgusu ${i + 1}: $query');
        
        final existing = await api.files.list(
          q: query,
          supportsAllDrives: true,
          includeItemsFromAllDrives: true,
          spaces: 'drive',
          $fields: 'files(id, name, parents)',
        );

        print('🔍 Arama sonucu ${i + 1}: ${existing.files?.length ?? 0} klasör bulundu');
        
        if (existing.files != null && existing.files!.isNotEmpty) {
          for (final file in existing.files!) {
            print('🔍 Bulunan klasör: ${file.name} (ID: ${file.id}, Parents: ${file.parents})');
            
            // Parent ID kontrolü - root için özel kontrol
            if (parentId == 'root') {
              // Root'ta olan klasörleri kabul et
              if (file.parents != null && file.parents!.isNotEmpty) {
                print('✅ Root klasör bulundu: ${file.name} (ID: ${file.id})');
                return file.id!;
              }
            } else {
              // Normal parent kontrolü
              if (file.parents != null && file.parents!.contains(parentId)) {
                print('✅ Doğru parent bulundu: ${file.name} (ID: ${file.id})');
                return file.id!;
              }
            }
          }
        }
      }
      
      return null;
    } catch (e) {
      print('❌ _findExistingFolder hatası: $e');
      return null;
    }
  }

  Future<String?> uploadFile(String filePath, List<String> folderPath) async {
    if (!isSignedIn) return null;
    if (_driveApi == null) await _initDriveApi();
    final api = _driveApi!;

    print('📤 uploadFile çağrıldı: $filePath -> $folderPath');

    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;

      // Klasör hiyerarşisini oluştur
      print('📁 Klasör hiyerarşisi oluşturuluyor: $folderPath');
      final parentId = await _ensureFolderPath(folderPath);
      print('✅ Klasör hiyerarşisi oluşturuldu, parent ID: $parentId');

      // Dosya adını al
      final fileName = file.path.split(Platform.pathSeparator).last;

      // Drive dosya metadata'sı
      final driveFile = drive.File()
        ..name = fileName
        ..parents = [parentId];

      // Dosyayı yükle
      final response = await api.files.create(
        driveFile,
        uploadMedia: drive.Media(file.openRead(), file.lengthSync()),
      );

      // Dosya yüklendikten sonra boş klasörleri temizle
      await deleteEmptyFolders();

      return response.id;
    } catch (e) {
      print('Dosya yükleme hatası: $e');
      lastError = 'Dosya yükleme hatası: $e';
      lastErrorCode = 1;
      return null;
    }
  }

  Future<String?> uploadPngFile(String filePath, {List<String>? folderPathParts, String? fileName}) async {
    if (!isSignedIn) return null;
    if (_driveApi == null) await _initDriveApi();
    final api = _driveApi!;

    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;

      // Klasör hiyerarşisini oluştur
      final parentId = await _ensureFolderPath(folderPathParts ?? ['FotoJeolog']);

      // Dosya adını al
      final finalFileName = fileName ?? file.path.split(Platform.pathSeparator).last;

      // Drive dosya metadata'sı
      final driveFile = drive.File()
        ..name = finalFileName
        ..parents = [parentId];

      // Dosyayı yükle
      final response = await api.files.create(
        driveFile,
        uploadMedia: drive.Media(file.openRead(), file.lengthSync()),
      );

      // Dosya yüklendikten sonra boş klasörleri temizle
      await deleteEmptyFolders();

      print('PNG dosya yüklendi: ${response.id}');
      return response.id;
    } catch (e) {
      print('PNG dosya yükleme hatası: $e');
      lastError = 'PNG dosya yükleme hatası: $e';
      lastErrorCode = 2;
      return null;
    }
  }

  Future<bool> downloadFile(String fileId, String localPath) async {
    if (!isSignedIn) return false;
    if (_driveApi == null) await _initDriveApi();
    final api = _driveApi!;

    try {
      final response = await api.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
      final file = File(localPath);
      final sink = file.openWrite();
      await response.stream.pipe(sink);
      return true;
    } catch (e) {
      print('Dosya indirme hatası: $e');
      return false;
    }
  }

  Future<List<drive.File>?> listFiles({String? folderId}) async {
    if (_driveApi == null) await _initDriveApi();
    final api = _driveApi!;

    try {
      String query = 'trashed=false';
      if (folderId != null) {
        query += " and parents in '$folderId'";
      }

      final response = await api.files.list(
        q: query,
        spaces: 'drive',
        $fields: 'files(id, name, mimeType, modifiedTime, size)',
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );

      return response.files;
    } catch (e) {
      print('Dosya listeleme hatası: $e');
      return null;
    }
  }

  Future<bool> deleteFile(String fileId) async {
    if (_driveApi == null) await _initDriveApi();
    final api = _driveApi!;

    try {
      await api.files.delete(fileId);
      print('✅ Dosya silindi: $fileId');
      
      // Dosya silindikten sonra boş klasörleri temizle
      await deleteEmptyFolders();
      
      return true;
    } catch (e) {
      print('❌ Dosya silme hatası: $e');
      return false;
    }
  }

  /// Boş klasörleri otomatik sil
  Future<void> cleanupEmptyFolders() async {
    try {
      if (_driveApi == null) await _initDriveApi();
      
      print('🧹 Boş klasör temizliği başlatılıyor...');
      
      // FotoJeolog klasörünü bul
      final folderQuery = "name='FotoJeolog' and mimeType='application/vnd.google-apps.folder' and trashed=false";
      final folderResponse = await _driveApi!.files.list(
        q: folderQuery,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
        spaces: 'drive',
        $fields: 'files(id, name)'
      );
      
      if (folderResponse.files == null || folderResponse.files!.isEmpty) {
        print('❌ FotoJeolog klasörü bulunamadı');
        return;
      }
      
      final fotojeologFolderId = folderResponse.files!.first.id!;
      print('✅ FotoJeolog klasörü bulundu: $fotojeologFolderId');
      
      // Ortak klasör yapısı - kullanıcı bazlı klasör yok, direkt FotoJeolog klasörünü kullan
      final userFolderId = fotojeologFolderId;
      print('✅ Ortak klasör temizliği yapılıyor: $userFolderId');
      
      // FotoJeolog klasöründeki tüm klasörleri recursive olarak kontrol et
      await _cleanupEmptyFoldersRecursive(userFolderId);
      
    } catch (e) {
      print('❌ Boş klasör temizliği hatası: $e');
    }
  }

  /// Recursive olarak boş klasörleri temizle
  Future<void> _cleanupEmptyFoldersRecursive(String folderId) async {
    try {
      // Bu klasördeki alt klasörleri listele
      final query = "parents in '$folderId' and mimeType='application/vnd.google-apps.folder' and trashed=false";
      final response = await _driveApi!.files.list(
        q: query,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
        spaces: 'drive',
        $fields: 'files(id, name)'
      );
      
      if (response.files == null || response.files!.isEmpty) {
        // Alt klasör yok, bu klasörü kontrol et
        await _checkAndDeleteEmptyFolder(folderId);
        return;
      }
      
      // Alt klasörleri recursive olarak temizle
      for (final folder in response.files!) {
        await _cleanupEmptyFoldersRecursive(folder.id!);
      }
      
      // Alt klasörler temizlendikten sonra bu klasörü kontrol et
      await _checkAndDeleteEmptyFolder(folderId);
      
    } catch (e) {
      print('❌ Recursive temizlik hatası: $e');
    }
  }

  /// Klasörün boş olup olmadığını kontrol et ve boşsa sil
  Future<void> _checkAndDeleteEmptyFolder(String folderId) async {
    try {
      // Bu klasördeki dosya sayısını kontrol et
      final query = "parents in '$folderId' and trashed=false";
      final response = await _driveApi!.files.list(
        q: query,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
        spaces: 'drive',
        $fields: 'files(id, name, mimeType)'
      );
      
      if (response.files == null || response.files!.isEmpty) {
        // Klasör boş, sil
        await _driveApi!.files.delete(folderId);
        print('🗑️ Boş klasör silindi: $folderId');
      } else {
        // Klasörde dosya var, silme
        print('📁 Klasör dolu, silinmedi: $folderId (${response.files!.length} dosya)');
      }
      
    } catch (e) {
      print('❌ Klasör kontrol hatası: $e');
    }
  }

  // Yardımcılar: Bazı sayfaların ihtiyaç duyduğu basit listeleme metodları
  Future<String> ensureRootFotoJeolog() async {
    if (!isSignedIn) throw Exception('Not signed in');
    if (_driveApi == null) await _initDriveApi();
    // Kök altında FotoJeolog klasörünü oluşturup id döndür
    return await _ensureFolderPath(['FotoJeolog']);
  }

  Future<List<drive.File>> listFolders({required String parentId}) async {
    if (!isSignedIn) return [];
    if (_driveApi == null) await _initDriveApi();
    final api = _driveApi!;
    try {
      final res = await api.files.list(
        q: "parents in '$parentId' and mimeType='application/vnd.google-apps.folder' and trashed=false",
        spaces: 'drive',
        $fields: 'files(id, name)',
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );
      return res.files ?? [];
    } catch (e) {
      print('Klasör listeleme hatası: $e');
      return [];
    }
  }

  Future<List<drive.File>> listPngFiles({required String parentId}) async {
    if (!isSignedIn) return [];
    if (_driveApi == null) await _initDriveApi();
    final api = _driveApi!;
    try {
      final res = await api.files.list(
        q: "parents in '$parentId' and mimeType='image/png' and trashed=false",
        spaces: 'drive',
        $fields: 'files(id, name, modifiedTime, size)',
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );
      return res.files ?? [];
    } catch (e) {
      print('PNG listeleme hatası: $e');
      return [];
    }
  }

  Future<drive.File?> findFileByNameInParent({required String parentId, required String name}) async {
    if (!isSignedIn) return null;
    if (_driveApi == null) await _initDriveApi();
    final api = _driveApi!;
    try {
      final res = await api.files.list(
        q: "parents in '$parentId' and name='$name' and trashed=false",
        spaces: 'drive',
        $fields: 'files(id, name)',
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
      );
      final list = res.files ?? [];
      return list.isNotEmpty ? list.first : null;
    } catch (e) {
      print('Dosya bulma hatası: $e');
      return null;
    }
  }

  /// Paylaşımlı klasör ID'sini al veya oluştur
  Future<String?> _getOrCreateSharedFolder() async {
    _prefs ??= await SharedPreferences.getInstance();
    
    // Önce kayıtlı klasör ID'sini kontrol et
    String? savedFolderId = _prefs!.getString(_sharedFolderKey);
    if (savedFolderId != null && savedFolderId.isNotEmpty) {
      print('📁 Kayıtlı paylaşımlı klasör ID: $savedFolderId');
      
      // Klasörün hala var olduğunu kontrol et
      try {
        if (_driveApi == null) await _initDriveApi();
        await _driveApi!.files.get(savedFolderId, $fields: 'id');
        print('✅ Paylaşımlı klasör hala mevcut');
        return savedFolderId;
      } catch (e) {
        print('⚠️ Kayıtlı klasör bulunamadı, yeni oluşturulacak: $e');
        // Klasör bulunamadı, yeni oluştur
      }
    }
    
    // Yeni paylaşımlı klasör oluştur
    print('🆕 Yeni paylaşımlı klasör oluşturuluyor...');
    try {
      if (_driveApi == null) await _initDriveApi();
      
      // FotoJeolog klasörünü oluştur
      final folder = drive.File();
      folder.name = 'FotoJeolog_Shared';
      folder.mimeType = 'application/vnd.google-apps.folder';
      folder.parents = ['root'];
      
      final createdFolder = await _driveApi!.files.create(folder, $fields: 'id');
      final folderId = createdFolder.id!;
      
      print('✅ Paylaşımlı klasör oluşturuldu: $folderId');
      
      // ID'yi kaydet
      await _prefs!.setString(_sharedFolderKey, folderId);
      
      return folderId;
    } catch (e) {
      print('❌ Paylaşımlı klasör oluşturulamadı: $e');
      return null;
    }
  }

  // FotoJeolog klasöründeki fotoğrafları (alt klasörler dahil) listele
  Future<List<Map<String, dynamic>>> listFotojeologFiles() async {
    print('🔍 listFotojeologFiles çağrıldı');
    
    if (!isSignedIn) {
      print('❌ Drive\'a giriş yapılmamış');
      return [];
    }
    if (_driveApi == null) await _initDriveApi();
    final api = _driveApi!;

    try {
      print('📁 Paylaşımlı FotoJeolog klasörü aranıyor...');
      
      // Önce mevcut FotoJeolog klasörünü bul (eski sistem)
      final folderQuery = "name='FotoJeolog' and mimeType='application/vnd.google-apps.folder' and trashed=false";
      final folderResponse = await api.files.list(
        q: folderQuery,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
        spaces: 'drive',
        $fields: 'files(id, name)'
      );
      
      print('📂 Klasör sorgusu sonucu: ${folderResponse.files?.length ?? 0} klasör bulundu');
      
      if (folderResponse.files == null || folderResponse.files!.isEmpty) {
        print('❌ FotoJeolog klasörü bulunamadı - Drive\'da henüz fotoğraf kaydedilmemiş');
        return [];
      }
      
      final fotojeologFolderId = folderResponse.files!.first.id!;
      print('✅ FotoJeolog klasörü bulundu: $fotojeologFolderId');
      
      // Mevcut klasörü kullan
      final sharedFolderId = fotojeologFolderId;
      print('✅ Mevcut klasör kullanılıyor: $sharedFolderId');

      // Alt klasörler dahil özyinelemeli listeleme (pathParts ile)

      // Klasör yol parçalarını (FotoJeolog altındaki klasör adları) taşıyarak listele
      Future<List<Map<String, dynamic>>> listFolderRecursively(
        String folderId,
        List<String> pathParts,
      ) async {
        final folderItems = await api.files.list(
          q: "parents in '$folderId' and trashed=false",
          spaces: 'drive',
          $fields: 'files(id, name, mimeType, modifiedTime, size, thumbnailLink, webViewLink)',
          supportsAllDrives: true,
          includeItemsFromAllDrives: true,
        );

        final files = folderItems.files ?? [];
        final List<Map<String, dynamic>> collected = [];

        // Alt klasörler ve dosyaları ayır
        final subFolders = files
            .where((f) => f.mimeType == 'application/vnd.google-apps.folder')
            .toList();
        final thisFolderFiles = files
            .where((f) => f.mimeType != 'application/vnd.google-apps.folder')
            .toList();

        // Bu klasördeki PNG+JSON eşleştirmesi
        for (final f in thisFolderFiles) {
          final nameLower = (f.name ?? '').toLowerCase();
          if (nameLower.endsWith('.png')) {
            final baseName = f.name!.substring(0, f.name!.length - 4);
            
            drive.File? jsonMatch;
            
            // Çok esnek JSON eşleştirme algoritması
            jsonMatch = null;
            
            // 1. Tam eşleşme dene
            for (final file in thisFolderFiles) {
              if ((file.name ?? '').toLowerCase() == '${baseName.toLowerCase()}_notes.json') {
                jsonMatch = file;
                break;
              }
            }
            
            // 2. Tam eşleşme yoksa, bu klasördeki herhangi bir JSON dosyasını al
            if (jsonMatch == null) {
              for (final file in thisFolderFiles) {
                if ((file.name ?? '').toLowerCase().endsWith('_notes.json')) {
                  jsonMatch = file;
                  break;
                }
              }
            }
            
            // 3. Hala yoksa, herhangi bir JSON dosyası al
            if (jsonMatch == null) {
              for (final file in thisFolderFiles) {
                if ((file.name ?? '').toLowerCase().endsWith('.json')) {
                  jsonMatch = file;
                  break;
                }
              }
            }
            collected.add({
              'imageFile': f,
              'jsonFile': jsonMatch,
              'baseName': baseName,
              'modifiedTime': f.modifiedTime,
              'pathParts': List<String>.from(pathParts), // FotoJeolog alt yolu
            });
          }
        }

        // Alt klasörleri dolaş
        for (final sub in subFolders) {
          final nextParts = List<String>.from(pathParts);
          if ((sub.name ?? '').isNotEmpty) nextParts.add(sub.name!);
          final subResults = await listFolderRecursively(sub.id!, nextParts);
          collected.addAll(subResults);
        }

        return collected;
      }

  final result = await listFolderRecursively(sharedFolderId, []);
      
      // Tarihine göre sırala (en yeni önce)
      result.sort((a, b) {
        final aTime = a['modifiedTime'] as DateTime?;
        final bTime = b['modifiedTime'] as DateTime?;
        if (aTime == null || bTime == null) return 0;
        return bTime.compareTo(aTime);
      });
      
      // Fotoğraf işleme tamamlandı
      return result;
    } catch (e) {
      print('FotoJeolog dosyaları listeleme hatası: $e');
      
      // OAuth izin hatası kontrolü
      if (e.toString().contains('401') || e.toString().contains('unauthorized')) {
        lastError = 'OAuth izinleri gerekli. Tekrar giriş yapın.';
        lastErrorCode = 401;
      } else if (e.toString().contains('403') || e.toString().contains('permission')) {
        lastError = 'Drive erişim izni gerekli. Lütfen uygulamaya izin verin.';
        lastErrorCode = 403;
      } else {
        lastError = 'Drive bağlantısında sorun var. Tekrar giriş yapın.';
        lastErrorCode = 999;
      }
      
      return [];
    }
  }

  // Dosya indirme URL'i al
  Future<String?> getFileDownloadUrl(String fileId) async {
    if (!isSignedIn) return null;
    if (_driveApi == null) await _initDriveApi();
    final api = _driveApi!;

    try {
      final file = await api.files.get(fileId, $fields: 'webViewLink');
      return (file as drive.File).webViewLink;
    } catch (e) {
      print('Dosya URL alma hatası: $e');
      return null;
    }
  }

  // FotoJeolog/[Kat]/[Ayna]/[Km] yolundaki klasörü siler.
  // Güvenlik: Klasörde herhangi bir dosya (özellikle PNG) varsa silmez ve false döner.
  Future<bool> deleteFolderByPath(List<String> pathParts) async {
    if (!isSignedIn) return false;
    if (_driveApi == null) await _initDriveApi();
    final api = _driveApi!;

    try {
      // FotoJeolog kök klasörünü bul
      final folderQuery = "name='FotoJeolog' and mimeType='application/vnd.google-apps.folder' and trashed=false";
      final rootRes = await api.files.list(
        q: folderQuery,
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
        spaces: 'drive',
        $fields: 'files(id, name)'
      );
      if (rootRes.files == null || rootRes.files!.isEmpty) return false;
      String currentParentId = rootRes.files!.first.id!;

      // Yol boyunca klasörleri bul
      for (final name in pathParts) {
        final res = await api.files.list(
          q: "parents in '$currentParentId' and name='$name' and mimeType='application/vnd.google-apps.folder' and trashed=false",
          supportsAllDrives: true,
          includeItemsFromAllDrives: true,
          spaces: 'drive',
          $fields: 'files(id, name)'
        );
        final list = res.files ?? [];
        if (list.isEmpty) return false; // Yol eksikse
        currentParentId = list.first.id!;
      }

      final folderId = currentParentId;

      // Klasörün boş olup olmadığını kontrol et: dosya var mı?
      final contents = await api.files.list(
        q: "parents in '$folderId' and trashed=false",
        supportsAllDrives: true,
        includeItemsFromAllDrives: true,
        spaces: 'drive',
        $fields: 'files(id, name, mimeType)'
      );

      final items = contents.files ?? [];
      // PNG dosyası var mı ya da herhangi bir dosya var mı?
      final hasAnyFile = items.any((f) => (f.mimeType ?? '') != 'application/vnd.google-apps.folder');
      final hasSubFolder = items.any((f) => (f.mimeType ?? '') == 'application/vnd.google-apps.folder');
      if (hasAnyFile || hasSubFolder) {
        // Doluyken silme
        return false;
      }

      // Sil
      await api.files.delete(folderId);
      return true;
    } catch (e) {
      print('Klasör silme hatası: $e');
      return false;
    }
  }
}