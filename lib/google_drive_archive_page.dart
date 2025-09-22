import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/photo_metadata_service.dart';
import 'services/google_drive_service.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'photo_draw_page.dart';

// Google Drive arşiv hiyerarşi modeli
class DriveArchiveItem {
  final String name;
  final String path;
  final List<DriveArchiveItem> children;
  final List<PhotoMetadata> photos;
  bool isExpanded;

  DriveArchiveItem({
    required this.name,
    required this.path,
    List<DriveArchiveItem>? children,
    List<PhotoMetadata>? photos,
    this.isExpanded = false,
  }) : children = children ?? [],
       photos = photos ?? [];
}

class GoogleDriveArchivePage extends StatefulWidget {
  const GoogleDriveArchivePage({super.key});

  @override
  State<GoogleDriveArchivePage> createState() => _GoogleDriveArchivePageState();
}

class _GoogleDriveArchivePageState extends State<GoogleDriveArchivePage> {
  List<DriveArchiveItem> _archiveItems = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkAuthAndLoadFiles();
  }

  Future<void> _checkAuthAndLoadFiles() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Google Drive servisini başlat
      await GoogleDriveService.instance.init();
      
      if (!GoogleDriveService.instance.isSignedIn) {
        setState(() {
          _error = 'Google Drive\'a giriş yapmanız gerekiyor';
          _isLoading = false;
        });
        return;
      }

      await _loadFiles();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Dosyalar yüklenirken hata oluştu: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadFiles() async {
    try {
      print('🚀 Google Drive dosyaları yükleniyor...');
      
      final metadataService = PhotoMetadataService.instance;
      final photos = await metadataService.getUserPhotoMetadata();
      
      print('📁 ${photos.length} fotoğraf bulundu');
      
      // Hiyerarşi oluştur
      final hierarchy = _buildHierarchy(photos);
      
      if (mounted) {
        setState(() {
          _archiveItems = hierarchy;
          _isLoading = false;
          _error = null;
        });
      }
      
    } catch (e) {
      print('❌ Dosya yükleme hatası: $e');
      if (mounted) {
        setState(() {
          _error = 'Dosyalar yüklenirken hata oluştu: $e';
          _isLoading = false;
        });
      }
    }
  }

  List<DriveArchiveItem> _buildHierarchy(List<PhotoMetadata> photos) {
    final Map<String, DriveArchiveItem> katMap = {};
    final List<PhotoMetadata> sinifSizPhotos = [];
    
    for (final photo in photos) {
      if (photo.kat.isEmpty || photo.ayna.isEmpty || photo.km.isEmpty) {
        sinifSizPhotos.add(photo); // Sınıfsız fotoğrafları ayrı topla
        continue;
      }
      
      // Kat seviyesi
      if (!katMap.containsKey(photo.kat)) {
        katMap[photo.kat] = DriveArchiveItem(
          name: photo.kat,
          path: photo.kat,
          children: [],
          photos: [],
        );
      }
      
      // Ayna seviyesi
      final katItem = katMap[photo.kat]!;
      final aynaName = photo.ayna;
      var aynaItem = katItem.children.firstWhere(
        (item) => item.name == aynaName,
        orElse: () => DriveArchiveItem(
          name: aynaName,
          path: '${photo.kat}/$aynaName',
          children: [],
          photos: [],
        ),
      );
      
      if (!katItem.children.contains(aynaItem)) {
        katItem.children.add(aynaItem);
      }
      
      // Km seviyesi
      final kmName = photo.km;
      var kmItem = aynaItem.children.firstWhere(
        (item) => item.name == kmName,
        orElse: () => DriveArchiveItem(
          name: kmName,
          path: '${photo.kat}/$aynaName/$kmName',
          children: [],
          photos: [],
        ),
      );
      
      if (!aynaItem.children.contains(kmItem)) {
        aynaItem.children.add(kmItem);
      }
      
      // Fotoğrafı km klasörüne ekle
      kmItem.photos.add(photo);
    }
    
    // Sınıfsız fotoğrafları ekle
    if (sinifSizPhotos.isNotEmpty) {
      final sinifSizItem = DriveArchiveItem(
        name: 'Sınıfsız',
        path: 'Sınıfsız',
        children: [],
        photos: sinifSizPhotos,
      );
      katMap['Sınıfsız'] = sinifSizItem;
    }
    
    return katMap.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B1F24),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_done_rounded,
              size: 24,
              color: Colors.amber[400],
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Google Drive Arşiv',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          // Sadece yenile butonu
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _checkAuthAndLoadFiles,
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1B1F24),
              Color(0xFF2D3436),
              Color(0xFF4A4F54),
            ],
          ),
        ),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.amber),
            SizedBox(height: 16),
            Text(
              'Google Drive dosyaları yükleniyor...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 64, color: Colors.red[400]),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _checkAuthAndLoadFiles,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
              ),
              child: const Text('Tekrar Dene'),
            ),
          ],
        ),
      );
    }

    if (_archiveItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 64,
              color: Colors.amber[400]?.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Henüz Google Drive\'da fotoğraf bulunmuyor',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return _buildHierarchyView();
  }

  Widget _buildHierarchyView() {
    return ListView.builder(
      itemCount: _archiveItems.length,
      itemBuilder: (context, index) {
        return _buildArchiveItem(_archiveItems[index]);
      },
    );
  }

  Widget _buildArchiveItem(DriveArchiveItem item, {int depth = 0}) {
    final hasChildren = item.children.isNotEmpty;
    final hasPhotos = item.photos.isNotEmpty;
    final isKmLevel = depth == 2; // Kilometre seviyesi

    return Column(
      children: [
        ListTile(
          leading: Icon(
            isKmLevel ? Icons.signpost_rounded : 
            depth == 0 ? Icons.layers_rounded : Icons.view_in_ar_rounded,
            color: Colors.amber[400],
          ),
          title: Text(
            item.name,
            style: const TextStyle(color: Colors.white),
          ),
          subtitle: Text(
            '${item.children.length} alt klasör, ${item.photos.length} fotoğraf',
            style: const TextStyle(color: Colors.white70),
          ),
          trailing: hasChildren
              ? Icon(
                  item.isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white70,
                )
              : isKmLevel && hasPhotos
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.photo_library, color: Colors.amber, size: 20),
                            onPressed: () => _showPhotosInKm(item),
                            tooltip: 'Fotoğrafları göster',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                          ),
                        ],
                      ),
                    )
                  : null,
          onTap: hasChildren
              ? () => _toggleExpansion(item)
              : isKmLevel && hasPhotos
                  ? () => _showPhotosInKm(item)
                  : null,
          tileColor: Colors.black26,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          contentPadding: EdgeInsets.only(
            left: 16.0 + (depth * 24.0),
            right: 16.0,
          ),
        ),
        if (item.isExpanded && hasChildren)
          Padding(
            padding: EdgeInsets.only(left: depth * 24.0),
            child: Column(
              children: item.children
                  .map((child) => _buildArchiveItem(child, depth: depth + 1))
                  .toList(),
            ),
          ),
      ],
    );
  }

  void _toggleExpansion(DriveArchiveItem item) {
    setState(() {
      item.isExpanded = !item.isExpanded;
    });
  }

  void _showPhotosInKm(DriveArchiveItem kmItem) {
    // Fotoğrafları yeni sayfa olarak göster (yerel arşiv gibi)
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _GoogleDrivePhotosPage(
          kmItem: kmItem,
          onPhotoTap: _onPhotoTap,
          buildPhotoGridItem: _buildPhotoGridItem,
        ),
      ),
    );
  }

  Widget _buildPhotoGridItem(PhotoMetadata photo) {
    return Stack(
      children: [
        InkWell(
          onTap: () => _onPhotoTap(photo),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.amber[700]!,
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Stack(
                children: [
                  // Ana fotoğraf gösterimi (yerel arşiv ile aynı stil)
                  Positioned.fill(
                    child: FutureBuilder<String?>(
                      future: _getImagePreview(photo),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data != null) {
                          return Image.file(
                            File(snapshot.data!),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              debugPrint('🚨 Google Drive Image.file ERROR: $error');
                              debugPrint('🚨 Image path: ${snapshot.data}');
                              return Container(
                                color: Colors.grey[300],
                                child: const Center(
                                  child: Icon(Icons.image_not_supported, color: Colors.grey, size: 40),
                                ),
                              );
                            },
                          );
                        } else if (snapshot.connectionState == ConnectionState.waiting) {
                          return Container(
                            color: Colors.grey[200],
                            child: const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
                              ),
                            ),
                          );
                        } else {
                          return Container(
                            color: Colors.grey[200],
                            child: const Icon(Icons.image, size: 32, color: Colors.grey),
                          );
                        }
                      },
                    ),
                  ),
                  
                  // Fotoğraf bilgileri (yerel arşiv ile aynı stil)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: const BoxDecoration(
                        color: Color(0x88000000),
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(11),
                          bottomRight: Radius.circular(11),
                        ),
                      ),
                      child: Text(
                        photo.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
      ],
    );
  }

  void _onPhotoTap(PhotoMetadata photo) {
    print('🖱️ Fotoğraf tıklandı: ${photo.fileName}');
    print('   Fotoğraf açılıyor...');
    _downloadAndOpenImage(photo);
  }

  Future<String?> _getImagePreview(PhotoMetadata photo) async {
    try {
      final driveService = GoogleDriveService.instance;
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/preview_${photo.imageFileId}');
      
      // Eğer dosya zaten varsa, onu kullan
      if (await tempFile.exists()) {
        return tempFile.path;
      }
      
      // Google Drive'dan fotoğrafı indir
      final success = await driveService.downloadFile(photo.imageFileId, tempFile.path);
      
      if (success && await tempFile.exists()) {
        return tempFile.path;
      }
      
      return null;
    } catch (e) {
      print('❌ Preview indirme hatası: $e');
      return null;
    }
  }

  Future<void> _downloadAndOpenImage(PhotoMetadata photo) async {
    try {
      print('📥 Fotoğraf indiriliyor: ${photo.fileName}');
      print('   ImageFileId: ${photo.imageFileId}');
      
      // Google Drive'dan fotoğrafı indir
      final driveService = GoogleDriveService.instance;
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${photo.fileName}');
      
      print('   Geçici dosya yolu: ${tempFile.path}');
      
      final success = await driveService.downloadFile(photo.imageFileId, tempFile.path);
      print('   İndirme başarılı: $success');
      
      if (success && await tempFile.exists()) {
        print('   Dosya boyutu: ${await tempFile.length()} bytes');
        
        // JSON dosyasını da indir (varsa)
        String? jsonPath;
        if (photo.id.isNotEmpty) {
          try {
            print('   JSON dosyası indiriliyor: ${photo.id}');
            final jsonFile = File('${tempDir.path}/${photo.fileName}.notes.json');
            final jsonSuccess = await driveService.downloadFile(photo.id, jsonFile.path);
            if (jsonSuccess && await jsonFile.exists()) {
              jsonPath = jsonFile.path;
              print('   JSON dosyası indirildi: $jsonPath');
            } else {
              print('   JSON dosyası indirilemedi');
            }
          } catch (e) {
            print('⚠️ JSON indirme hatası: $e');
          }
        } else {
          print('   JSON ID boş, JSON indirilmiyor');
        }
        
        // Fotoğrafı düzenleme sayfasında aç
        if (mounted) {
          print('   PhotoDrawPage açılıyor...');
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PhotoDrawPage.fromImage(
                tempFile,
                saveDirectoryPath: null,
                jsonPath: jsonPath,
              ),
            ),
          );
          print('   PhotoDrawPage açıldı');
        } else {
          print('   Widget mounted değil, açılamıyor');
        }
      } else {
        print('❌ Fotoğraf indirilemedi veya dosya yok');
        throw Exception('Fotoğraf indirilemedi');
      }
    } catch (e) {
      print('❌ _downloadAndOpenImage hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fotoğraf açılırken hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


}

// Google Drive fotoğrafları için ayrı sayfa (yerel arşiv gibi)
class _GoogleDrivePhotosPage extends StatefulWidget {
  final DriveArchiveItem kmItem;
  final Function(PhotoMetadata) onPhotoTap;
  final Widget Function(PhotoMetadata) buildPhotoGridItem;

  const _GoogleDrivePhotosPage({
    required this.kmItem,
    required this.onPhotoTap,
    required this.buildPhotoGridItem,
  });

  @override
  State<_GoogleDrivePhotosPage> createState() => _GoogleDrivePhotosPageState();
}

class _GoogleDrivePhotosPageState extends State<_GoogleDrivePhotosPage> {
  final Set<PhotoMetadata> _selectedPhotos = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B1F24),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B1F24),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library,
              size: 24,
              color: Colors.amber[400],
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _selectedPhotos.isNotEmpty
                    ? '${_selectedPhotos.length} seçili'
                    : '${widget.kmItem.name} - Fotoğraflar',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          // Seçili fotoğrafları sil butonu
          if (_selectedPhotos.isNotEmpty)
            Tooltip(
              message: 'Seçili fotoğrafları sil',
              child: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: _deleteSelectedPhotos,
              ),
            ),
          // Galeriden ekle butonu
          Tooltip(
            message: 'Galeriden Seç (Gözat)',
            child: IconButton(
              icon: const Icon(Icons.photo_library_outlined, color: Colors.white),
              onPressed: () async {
                try {
                  final picker = ImagePicker();
                  final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
                  if (picked == null) return;
                  if (!mounted) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => PhotoDrawPage.fromImage(File(picked.path)),
                    ),
                  );
                  // Sayfayı yenile
                  Navigator.of(context).pop();
                } catch (e) {
                  debugPrint('Gözat hatası: $e');
                }
              },
            ),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1B1F24),
              Color(0xFF0F1419),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: widget.kmItem.photos.length,
            itemBuilder: (context, index) {
              return _buildPhotoGridItem(widget.kmItem.photos[index]);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoGridItem(PhotoMetadata photo) {
    final isSelected = _selectedPhotos.contains(photo);
    
    return Stack(
      children: [
        InkWell(
          onTap: () => widget.onPhotoTap(photo),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? Colors.blue : Colors.amber[700]!,
                width: isSelected ? 3 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Stack(
                children: [
                  // Ana fotoğraf gösterimi
                  Positioned.fill(
                    child: FutureBuilder<String?>(
                      future: _getImagePreview(photo),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data != null) {
                          return Image.file(
                            File(snapshot.data!),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              debugPrint('🚨 Google Drive Image.file ERROR: $error');
                              debugPrint('🚨 Image path: ${snapshot.data}');
                              return Container(
                                color: Colors.grey[300],
                                child: const Center(
                                  child: Icon(Icons.image_not_supported, color: Colors.grey, size: 40),
                                ),
                              );
                            },
                          );
                        } else if (snapshot.connectionState == ConnectionState.waiting) {
                          return Container(
                            color: Colors.grey[200],
                            child: const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
                              ),
                            ),
                          );
                        } else {
                          return Container(
                            color: Colors.grey[200],
                            child: const Icon(Icons.image, size: 32, color: Colors.grey),
                          );
                        }
                      },
                    ),
                  ),
                  
                  // Fotoğraf bilgileri
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: const BoxDecoration(
                        color: Color(0x88000000),
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(11),
                          bottomRight: Radius.circular(11),
                        ),
                      ),
                      child: Text(
                        photo.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        // Seçim checkbox'u ve silme butonu (her zaman görünür)
        Positioned(
          right: 6,
          top: 6,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Seçim checkbox'u
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    setState(() {
                      if (_selectedPhotos.contains(photo)) {
                        _selectedPhotos.remove(photo);
                      } else {
                        _selectedPhotos.add(photo);
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.blue.withOpacity(0.8)
                          : Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      isSelected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Silme butonu
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _deletePhoto(photo),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.delete, color: Colors.white, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Paylaşım butonu
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _sharePhoto(photo),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.share, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<String?> _getImagePreview(PhotoMetadata photo) async {
    try {
      final driveService = GoogleDriveService.instance;
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/${photo.fileName}');
      
      if (await tempFile.exists()) {
        return tempFile.path;
      }
      
      final success = await driveService.downloadFile(photo.imageFileId, tempFile.path);
      if (success) {
        return tempFile.path;
      }
    } catch (e) {
      debugPrint('🚨 Google Drive önizleme hatası: $e');
    }
    return null;
  }

  Future<void> _deletePhoto(PhotoMetadata photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fotoğrafı Sil'),
        content: Text('${photo.fileName} silinecek. Emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final driveService = GoogleDriveService.instance;
        await driveService.deleteFile(photo.imageFileId);
        
        // Metadata dosyasını da sil (varsa)
        if (photo.id.isNotEmpty) {
          await driveService.deleteFile(photo.id);
        }
        
        setState(() {
          widget.kmItem.photos.remove(photo);
          _selectedPhotos.remove(photo);
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Fotoğraf silindi'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Silme hatası: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  Future<void> _sharePhoto(PhotoMetadata photo) async {
    try {
      final driveService = GoogleDriveService.instance;
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/${photo.fileName}');
      final success = await driveService.downloadFile(photo.imageFileId, tempFile.path);
      
      if (success) {
        await Share.shareXFiles(
          [XFile(tempFile.path)],
          text: 'FotoJeolog - ${photo.fileName}',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Paylaşım hatası: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _deleteSelectedPhotos() async {
    if (_selectedPhotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Silinecek fotoğraf seçiniz'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final selectedCount = _selectedPhotos.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fotoğrafları Sil'),
        content: Text('$selectedCount fotoğraf silinecek. Emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final driveService = GoogleDriveService.instance;
        int deletedCount = 0;
        
        for (final photo in _selectedPhotos.toList()) {
          try {
            await driveService.deleteFile(photo.imageFileId);
            
            // Metadata dosyasını da sil (varsa)
            if (photo.id.isNotEmpty) {
              await driveService.deleteFile(photo.id);
            }
            
            widget.kmItem.photos.remove(photo);
            deletedCount++;
          } catch (e) {
            debugPrint('❌ Google Drive silme hatası: ${photo.fileName} - $e');
          }
        }
        
        setState(() {
          _selectedPhotos.clear();
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$deletedCount fotoğraf silindi'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Toplu silme hatası: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }
}
