import 'dart:io';
import 'dart:convert';
import 'package:googleapis/drive/v3.dart' as drive;
import 'google_drive_service.dart';

/// Fotoğraf metadata yönetimi için servis
/// Firestore yerine Google Drive'da JSON dosyaları olarak metadata saklar
class PhotoMetadataService {
  PhotoMetadataService._();
  static final PhotoMetadataService instance = PhotoMetadataService._();
  
  // Cache için
  List<PhotoMetadata>? _cachedMetadata;
  DateTime? _lastCacheTime;

  final GoogleDriveService _driveService = GoogleDriveService.instance;

  /// Fotoğraf metadata'sını Google Drive'a kaydet
  Future<String?> savePhotoMetadata({
    required String imageFileName,
    required String notes,
    String? projectName,
    String? kat,
    String? ayna,
    String? km,
  }) async {
    try {
      print('🚀 ===== PHOTO METADATA SAVE BAŞLADI =====');
      print('📁 Image file: $imageFileName');
      print('📝 Notes length: ${notes.length}');
      print('🏗️ Kat: $kat, Ayna: $ayna, Km: $km');
      
      if (!_driveService.isSignedIn) {
        throw Exception('Google Drive\'a giriş yapılmamış');
      }
      
      // Metadata objesi oluştur
      final metadata = {
        'fileName': imageFileName,
        'notes': notes,
        'project': projectName ?? 'Genel',
        'uploadTime': DateTime.now().toIso8601String(),
        'uploader': 'FotoJeolog App',
        'userEmail': _driveService.userEmail,
        'kat': kat ?? '',
        'ayna': ayna ?? '',
        'km': km ?? '',
        'createdAt': DateTime.now().toIso8601String(),
      };
      
      // JSON dosya adı oluştur
      final baseName = imageFileName.replaceAll(RegExp(r'\.(png|jpg|jpeg)$', caseSensitive: false), '');
      final jsonFileName = '${baseName}_notes.json';
      
      // Geçici JSON dosyası oluştur
      final tempDir = Directory.systemTemp;
      final tempJsonFile = File('${tempDir.path}/$jsonFileName');
      await tempJsonFile.writeAsString(jsonEncode(metadata));
      
      // Klasör yolu oluştur
      List<String> folderPath = [];
      if (kat == 'Sınıfsız') {
        // Sınıfsız kaydet: FotoJeolog/Diğer
        folderPath = ['Diğer'];
        print('🔍 METADATA: Sınıfsız kaydetme - folderPath = $folderPath (FotoJeolog/Diğer)');
      } else if (kat != null && ayna != null && km != null && kat.isNotEmpty && ayna.isNotEmpty && km.isNotEmpty) {
        // Normal sınıflandırma ile kaydet
        folderPath = [kat, ayna, km];
        print('🔍 METADATA: Normal kaydetme - folderPath = $folderPath');
      } else {
        // Geçersiz parametreler - FotoJeolog/Diğer'e kaydet
        folderPath = ['Diğer'];
        print('🔍 METADATA: Geçersiz parametreler - FotoJeolog/Diğer: $folderPath');
      }
      
      // Google Drive'a JSON dosyasını yükle
      final fileId = await _driveService.uploadFile(tempJsonFile.path, folderPath);
      
      // Geçici dosyayı sil
      if (await tempJsonFile.exists()) {
        await tempJsonFile.delete();
      }
      
      if (fileId != null) {
        print('✅ Photo metadata saved to Google Drive: $fileId');
        print('🚀 ===== PHOTO METADATA SAVE BİTTİ =====');
        return fileId;
      } else {
        throw Exception('Metadata dosyası yüklenemedi');
      }
      
    } catch (e) {
      print('❌ Photo metadata save hatası: $e');
      throw Exception('Photo metadata save hatası: $e');
    }
  }

  /// Kullanıcıya özgü fotoğraf metadata'larını Google Drive'dan al
  Future<List<PhotoMetadata>> getUserPhotoMetadata() async {
    try {
      // Cache kontrolü - 5 dakika geçerli
      if (_cachedMetadata != null && _lastCacheTime != null) {
        final timeDiff = DateTime.now().difference(_lastCacheTime!);
        if (timeDiff.inMinutes < 5) {
          print('📁 Cache\'den ${_cachedMetadata!.length} fotoğraf yüklendi (${timeDiff.inSeconds}s önce)');
          return _cachedMetadata!;
        }
      }
      
      print('📁 Google Drive fotoğraflar yükleniyor...');
      
      if (!_driveService.isSignedIn) {
        throw Exception('Google Drive\'a giriş yapılmamış');
      }
      
      // Kullanıcının klasöründeki tüm dosyaları listele
      final files = await _driveService.listFotojeologFiles();
      
      // Dosya sayısı: ${files.length}
      
      List<PhotoMetadata> metadataList = [];
      
      for (final fileData in files) {
        try {
          final imageFile = fileData['imageFile'] as drive.File;
          final jsonFile = fileData['jsonFile'] as drive.File?;
          final pathParts = fileData['pathParts'] as List<String>;
          
          // Sadece hata durumlarında log yaz
          
          if (jsonFile != null) {
            // JSON dosyasını indir ve parse et
            final tempDir = Directory.systemTemp;
            final tempJsonFile = File('${tempDir.path}/temp_${jsonFile.id}.json');
            
            final downloadSuccess = await _driveService.downloadFile(jsonFile.id!, tempJsonFile.path);
            
            if (downloadSuccess && await tempJsonFile.exists()) {
              final jsonContent = await tempJsonFile.readAsString();
              final metadata = jsonDecode(jsonContent) as Map<String, dynamic>;
              
              // Sınıfsız fotoğraflar için kat/ayna/km alanlarını kontrol et
              String kat = metadata['kat'] ?? '';
              String ayna = metadata['ayna'] ?? '';
              String km = metadata['km'] ?? '';
              
              // Eğer metadata'da kat/ayna/km boşsa, pathParts'tan al veya 'Sınıfsız' yap
              if (kat.isEmpty || ayna.isEmpty || km.isEmpty) {
                kat = pathParts.isNotEmpty ? pathParts[0] : 'Sınıfsız';
                ayna = pathParts.length > 1 ? pathParts[1] : 'Sınıfsız';
                km = pathParts.length > 2 ? pathParts[2] : 'Sınıfsız';
              }
              
              metadataList.add(PhotoMetadata(
                id: jsonFile.id!,
                fileName: metadata['fileName'] ?? imageFile.name ?? '',
                imageFileId: imageFile.id!,
                notes: metadata['notes'] ?? '',
                project: metadata['project'] ?? 'Genel',
                uploadTime: DateTime.tryParse(metadata['uploadTime'] ?? '') ?? (imageFile.modifiedTime ?? DateTime.now()),
                uploader: metadata['uploader'] ?? 'Bilinmeyen',
                userEmail: metadata['userEmail'] ?? '',
                kat: kat,
                ayna: ayna,
                km: km,
                createdAt: DateTime.tryParse(metadata['createdAt'] ?? '') ?? (imageFile.modifiedTime ?? DateTime.now()),
                pathParts: pathParts,
              ));
              
              // Metadata eklendi
            } else {
              // JSON download failed
            }
            
            // Geçici dosyayı sil
            if (await tempJsonFile.exists()) {
              await tempJsonFile.delete();
            }
          } else {
            // JSON dosyası yoksa, sadece fotoğraf bilgilerini kullan
            print('⚠️ No JSON file found, creating metadata from image file only');
            metadataList.add(PhotoMetadata(
              id: imageFile.id!,
              fileName: imageFile.name ?? '',
              imageFileId: imageFile.id!,
              notes: 'Metadata dosyası bulunamadı',
              project: 'Genel',
              uploadTime: imageFile.modifiedTime ?? DateTime.now(),
              uploader: 'Bilinmeyen',
              userEmail: '',
              kat: pathParts.isNotEmpty ? pathParts[0] : 'Sınıfsız',
              ayna: pathParts.length > 1 ? pathParts[1] : 'Sınıfsız',
              km: pathParts.length > 2 ? pathParts[2] : 'Sınıfsız',
              createdAt: imageFile.modifiedTime ?? DateTime.now(),
              pathParts: pathParts,
            ));
            
            // JSON dosyası olmadan eklendi
          }
        } catch (e) {
          // Metadata parse error: $e
        }
      }
      
      // Tarihine göre sırala (en yeni önce)
      metadataList.sort((a, b) => b.uploadTime.compareTo(a.uploadTime));
      
      print('✅ ${metadataList.length} fotoğraf yüklendi');
      
      // Cache'i güncelle
      _cachedMetadata = metadataList;
      _lastCacheTime = DateTime.now();
      
      return metadataList;
      
    } catch (e) {
      // Photo metadata get hatası: $e
      throw Exception('Photo metadata get hatası: $e');
    }
  }
  
  /// Cache'i temizle (yeni fotoğraf eklendikten sonra)
  void clearCache() {
    _cachedMetadata = null;
    _lastCacheTime = null;
    // Google Drive klasör cache'ini de temizle
    _driveService.clearFolderCache();
  }

  /// Fotoğraf metadata'sını Google Drive'dan sil
  Future<void> deletePhotoMetadata(String metadataId) async {
    try {
      if (!_driveService.isSignedIn) {
        throw Exception('Google Drive\'a giriş yapılmamış');
      }
      
      final success = await _driveService.deleteFile(metadataId);
      if (success) {
        print('✅ Photo metadata deleted: $metadataId');
      } else {
        throw Exception('Metadata dosyası silinemedi');
      }
      
    } catch (e) {
      print('❌ Photo metadata delete hatası: $e');
      throw Exception('Photo metadata delete hatası: $e');
    }
  }
}

/// Fotoğraf metadata modeli
class PhotoMetadata {
  final String id;
  final String fileName;
  final String imageFileId;
  final String notes;
  final String project;
  final DateTime uploadTime;
  final String uploader;
  final String userEmail;
  final String kat;
  final String ayna;
  final String km;
  final DateTime createdAt;
  final List<String> pathParts;

  PhotoMetadata({
    required this.id,
    required this.fileName,
    required this.imageFileId,
    required this.notes,
    required this.project,
    required this.uploadTime,
    required this.uploader,
    required this.userEmail,
    this.kat = '',
    this.ayna = '',
    this.km = '',
    required this.createdAt,
    required this.pathParts,
  });

  /// Upload zamanını formatla
  String get formattedUploadTime {
    return '${uploadTime.day}/${uploadTime.month}/${uploadTime.year} ${uploadTime.hour}:${uploadTime.minute.toString().padLeft(2, '0')}';
  }

  /// Klasör yolunu göster
  String get folderPath {
    if (kat.isNotEmpty && ayna.isNotEmpty && km.isNotEmpty) {
      return '$kat/$ayna/$km';
    }
    return 'Genel';
  }
}
