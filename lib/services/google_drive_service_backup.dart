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

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: <String>[
      drive.DriveApi.driveFileScope, // Uygulamanın oluşturduğu dosyalar
      drive.DriveApi.driveReadonlyScope, // Paylaşılan fotoğrafları listelemek/indirmek
    ],
  );

  drive.DriveApi? _driveApi;
  GoogleSignInAccount? _user;
  SharedPreferences? _prefs;

  // Son hata bilgileri (UI'da gösterim için)
  int? lastErrorCode;
  String? lastError;

  static const _cloudSyncKey = 'cloud_sync_enabled';

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    // Mevcut oturumu sessiz geri yüklemeyi dene
    _user = await _googleSignIn.signInSilently();
    if (_user != null) {
      await _initDriveApi();
    }
  }

  bool get isSignedIn => _user != null;
  String? get displayName => _user?.displayName;
  String? get email => _user?.email;

  bool get cloudSyncEnabled => _prefs?.getBool(_cloudSyncKey) ?? false;
  Future<void> setCloudSyncEnabled(bool value) async {
    final p = _prefs ?? await SharedPreferences.getInstance();
    await p.setBool(_cloudSyncKey, value);
  }

  Future<bool> signIn() async {
    try {
      // Önce sessiz giriş dene (önceki oturum varsa)
      _user = await _googleSignIn.signInSilently();
      
      if (_user == null) {
        // Mevcut oturumu temizle
        await _googleSignIn.signOut();
        
        // Ana thread deadlock problemini önlemek için gecikme
        await Future.delayed(Duration(milliseconds: 300));
        
        // Manuel giriş denemesi
        _user = await _googleSignIn.signIn();
        if (_user == null) {
          // Kullanıcı iptal etti veya başarısız oldu
          lastError = 'Kullanıcı iptal etti veya hesap seçimi başarısız oldu';
          lastErrorCode = null;
          return false;
        }
      }
      
      // Drive API'yi başlat
      await _initDriveApi();
      
      lastError = null;
      lastErrorCode = null;
      return true;
    } on PlatformException catch (e) {
      print('PlatformException: ${e.code} - ${e.message}');
      lastError = e.message ?? 'Platform hatası';
      
      if (e.code == 'sign_in_required' || e.code == 'NEED_REMOTE_CONSENT') {
        lastErrorCode = 999; // OAuth yetkilendirme sorunu
        lastError = 'OAuth yetkilendirme gerekli. Lütfen uygulamayı yeniden başlatıp tekrar deneyin.';
      } else if (e.message?.contains('main thread') == true || e.message?.contains('deadlock') == true) {
        lastErrorCode = 999; // Main thread hatası
        lastError = 'Ana thread deadlock hatası. Uygulamayı yeniden başlatın.';
      } else if (e.code.contains('10') || e.message?.contains('ApiException: 10') == true) {
        lastErrorCode = 10; // Developer error
        lastError = 'SHA imza hatası veya Firebase yapılandırma sorunu';
      } else {
        lastErrorCode = int.tryParse(e.code) ?? 999;
      }
      return false;
    } catch (e) {
      // Hata durumunu logla ve kodu yakala
      print('Google Sign-In genel hatası: $e');
      lastError = e.toString();
      lastErrorCode = 999;
      return false;
    }
  }

  // Alternative sign-in method for OAuth issues
  Future<bool> signInWithRetry() async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        print('Google Sign-In denemesi: $attempt/3');
        
        if (attempt > 1) {
          // Retry'da önce temizle
          await _googleSignIn.signOut();
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        }
        
        // Sessiz giriş dene
        _user = await _googleSignIn.signInSilently();
        
        if (_user == null) {
          // Manual giriş
          _user = await _googleSignIn.signIn();
        }
        
        if (_user != null) {
          await _initDriveApi();
          lastError = null;
          lastErrorCode = null;
          print('Google Sign-In başarılı: attempt $attempt');
          return true;
        }
        
      } on PlatformException catch (e) {
        print('Attempt $attempt PlatformException: ${e.code} - ${e.message}');
        
        if (attempt == 3) {
          // Son denemede hataları kaydet
          lastError = e.message ?? 'Platform hatası';
          if (e.code == 'NEED_REMOTE_CONSENT') {
            lastErrorCode = 999;
            lastError = 'OAuth consent hatası. Uygulama izinlerini yenileyin.';
          } else {
            lastErrorCode = int.tryParse(e.code) ?? 999;
          }
        }
      } catch (e) {
        print('Attempt $attempt genel hata: $e');
        if (attempt == 3) {
          lastError = e.toString();
          lastErrorCode = 999;
        }
      }
      
      // Deneme arası bekleme
      if (attempt < 3) {
        await Future.delayed(Duration(seconds: attempt));
      }
    }
    
    return false;
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.disconnect();
    } finally {
      _user = null;
      _driveApi = null;
    }
  }

  Future<void> _initDriveApi() async {
    if (_user == null) return;
    final headers = await _user!.authHeaders;
    final client = _GoogleAuthClient(headers);
    _driveApi = drive.DriveApi(client);
  }

  // pathParts örnek: ['FotoJeolog', 'Kat1', 'Ayna1', 'Km1']
  Future<String> _ensureFolderPath(List<String> pathParts) async {
    if (_driveApi == null) {
      throw Exception('Drive API başlatılmamış');
    }

    String currentParentId = 'root';
    final api = _driveApi!;

    for (final folderName in pathParts) {
      // Bu parentta aynı isimde klasör var mı kontrol et
      final query = "name='$folderName' and parents in '$currentParentId' and mimeType='application/vnd.google-apps.folder'";
      final existing = await api.files.list(q: query);

      if (existing.files != null && existing.files!.isNotEmpty) {
        // Mevcut klasörü kullan
        currentParentId = existing.files!.first.id!;
      } else {
        // Yeni klasör oluştur
        final folder = drive.File()
          ..name = folderName
          ..mimeType = 'application/vnd.google-apps.folder'
          ..parents = [currentParentId];
        final created = await api.files.create(folder);
        currentParentId = created.id!;
      }
    }

    return currentParentId;
  }

  Future<String?> uploadFile(String filePath, List<String> folderPath) async {
    if (!isSignedIn) return null;
    if (_driveApi == null) await _initDriveApi();
    final api = _driveApi!;

    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;

      // Klasör hiyerarşisini oluştur
      final parentId = await _ensureFolderPath(folderPath);

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

      return response.id;
    } catch (e) {
      print('Dosya yükleme hatası: $e');
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
      return true;
    } catch (e) {
      print('Dosya silme hatası: $e');
      return false;
    }
  }
}