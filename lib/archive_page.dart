import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fotojeolog/photo_draw_page.dart' as photo;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'services/google_drive_service.dart';
import 'services/photo_metadata_service.dart';
import 'permissions_helper.dart';

class ArchiveItem {
  final String name;
  final String path;
  final List<ArchiveItem> children;
  bool isExpanded;

  ArchiveItem({
    required this.name,
    required this.path,
    this.children = const [],
    this.isExpanded = false,
  });
}

class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key});

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  List<ArchiveItem> _archiveItems = [];
  List<Map<String, dynamic>> _photos = []; // Drive gibi Map listesi kullan
  bool _isLoading = true;
  String? _currentKmPath; // Seçili kilometre klasörü
  final Set<Map<String, dynamic>> _selectedPhotos = {}; // Seçili fotoğraflar

  // Klasör temizleme metodu kaldırıldı - Android DCIM kısıtlamaları nedeniyle

  // Force delete metodu kaldırıldı - Android DCIM kısıtlamaları nedeniyle

  @override
  void initState() {
    super.initState();
    _loadArchiveStructure();
  }

  Future<void> _loadArchiveStructure() async {
    setState(() => _isLoading = true);
    try {
      // Galeri konumunu kullan (DCIM/FotoJeolog)
      final rootDir = Directory('/storage/emulated/0/DCIM/FotoJeolog');
      
      if (!rootDir.existsSync()) {
        setState(() => _isLoading = false);
        return;
      }

      final floorDirs = rootDir.listSync()
          .whereType<Directory>()
          .where((dir) {
            final name = dir.path.split('/').last.split('\\').last;
            return name != 'bilinmeyen_kat' && name != 'flutter_assets';
          })
          .toList();

      List<ArchiveItem> items = [];
      
      // Sınıfsız klasöründeki fotoğrafları kontrol et
      final sinifSizDir = Directory('${rootDir.path}/Sınıfsız');
      if (sinifSizDir.existsSync()) {
        final sinifSizFiles = sinifSizDir.listSync()
            .whereType<File>()
            .where((file) => file.path.toLowerCase().endsWith('.png') || 
                            file.path.toLowerCase().endsWith('.jpg') || 
                            file.path.toLowerCase().endsWith('.jpeg'))
            .toList();
        
        if (sinifSizFiles.isNotEmpty) {
          final sinifSizItem = ArchiveItem(
            name: 'Sınıfsız',
            path: sinifSizDir.path,
            children: [],
          );
          items.add(sinifSizItem);
        }
      }
      
      for (final floorDir in floorDirs) {
        final floorName = floorDir.path.split('/').last.split('\\').last;
        final floorItem = ArchiveItem(
          name: floorName,
          path: floorDir.path,
          children: await _loadFloorChildren(floorDir),
        );
        items.add(floorItem);
      }
      
      setState(() {
        _archiveItems = items;
        _photos = [];
        _isLoading = false;
      });

      // Boş klasör temizliği devre dışı - Android DCIM kısıtlamaları nedeniyle
      // Future.microtask(() => _cleanupEmptyKmDirs(rootDir));
    } catch (e) {
      debugPrint('Arşiv yükleme hatası: $e');
      setState(() => _isLoading = false);
    }
  }

  // Boş klasör temizliği metodu kaldırıldı - Android DCIM kısıtlamaları nedeniyle

  // Akıllı klasör silme metodları kaldırıldı - Android DCIM kısıtlamaları nedeniyle

  // KM klasörü resim kontrolü metodu kaldırıldı - Android DCIM kısıtlamaları nedeniyle

  // KM klasörü silme metodu kaldırıldı - Android DCIM kısıtlamaları nedeniyle

  Future<List<ArchiveItem>> _loadFloorChildren(Directory floorDir) async {
    final faceDirs = floorDir.listSync()
        .whereType<Directory>()
        .where((dir) => dir.path.split('/').last.split('\\').last != 'bilinmeyen_ayna')
        .toList();

    List<ArchiveItem> faceItems = [];
    
    for (final faceDir in faceDirs) {
      final faceName = faceDir.path.split('/').last.split('\\').last;
      final faceItem = ArchiveItem(
        name: faceName,
        path: faceDir.path,
        children: await _loadFaceChildren(faceDir),
      );
      faceItems.add(faceItem);
    }
    
    return faceItems;
  }

  Future<List<ArchiveItem>> _loadFaceChildren(Directory faceDir) async {
    final kmDirs = faceDir.listSync()
        .whereType<Directory>()
        .where((dir) => dir.path.split('/').last.split('\\').last != 'km0')
        .toList();

    List<ArchiveItem> kmItems = [];
    
    for (final kmDir in kmDirs) {
      final kmName = kmDir.path.split('/').last.split('\\').last;
      final kmItem = ArchiveItem(
        name: kmName,
        path: kmDir.path,
      );
      kmItems.add(kmItem);
    }
    
    return kmItems;
  }

  Future<void> _loadPhotos(String kmPath) async {
    debugPrint('📷 Fotoğraf yükleme başlıyor: $kmPath');
    setState(() => _isLoading = true);
    try {
      final kmDir = Directory(kmPath);
      
      if (!kmDir.existsSync()) {
        debugPrint('❌ KM klasörü bulunamadı: $kmPath');
        setState(() {
          _photos = [];
          _currentKmPath = kmPath;
          _isLoading = false;
        });
        return;
      }

      debugPrint('📂 KM klasörü var, dosyalar taranıyor...');
      
      // Görsel uzantılarını boyuta bakmadan dahil et (büyük dosyalar gizlenip "kayboluyor" sorununu önlemek için)
      final photoFiles = <File>[];
      int totalFiles = 0;
      await for (final entity in kmDir.list(followLinks: false)) {
        totalFiles++;
        if (entity is! File) {
          debugPrint('⏭️ Dosya değil, atlaniyor: ${entity.path}');
          continue;
        }
        final p = entity.path.toLowerCase();
        final isImage = p.endsWith('.png') || p.endsWith('.jpg') || p.endsWith('.jpeg') ||
            p.endsWith('.webp') || p.endsWith('.heic') || p.endsWith('.heif') || p.endsWith('.bmp');
        if (isImage) {
          final fileSize = await entity.length();
          if (fileSize > 0) {
            debugPrint('✅ Resim dosyası bulundu: ${entity.path} (${fileSize} bytes)');
            photoFiles.add(entity);
          } else {
            debugPrint('⚠️ Boş resim dosyası atlanıyor: ${entity.path} (${fileSize} bytes)');
          }
        } else {
          debugPrint('⏭️ Resim dosyası değil: ${entity.path}');
        }
      }
      
      debugPrint('📊 Tarama tamamlandı - Toplam dosya: $totalFiles, Resim dosyası: ${photoFiles.length}');
      
      // Görselleri son değiştirilme zamanına göre yeni→eski sırala (stabil görünüm)
      final photoMaps = <Map<String, dynamic>>[];
      for (final file in photoFiles) {
        photoMaps.add({
          'file': file,
          'path': file.path,
          'name': file.path.split(Platform.pathSeparator).last,
        });
      }
      
      try {
        photoMaps.sort((a, b) {
          final sa = (a['file'] as File).statSync().modified;
          final sb = (b['file'] as File).statSync().modified;
          return sb.compareTo(sa);
        });
        debugPrint('📋 Dosyalar tarihe göre sıralandı');
      } catch (e) {
        debugPrint('⚠️ Sıralama hatası: $e');
      }
      
      debugPrint('✅ Fotoğraf listesi güncelleniyor: ${photoMaps.length} adet');
      setState(() {
        _photos = photoMaps;
        _currentKmPath = kmPath;
        _isLoading = false;
      });
      debugPrint('🎯 setState tamamlandı, UI güncellenecek');
    } catch (e) {
      debugPrint('❌ Fotoğraf listesi yükleme hatası: $e');
      setState(() {
        _photos = [];
        _currentKmPath = kmPath;
        _isLoading = false;
      });
    }
  }

  Future<void> _deletePhoto(File photoFile) async {
    // Onay dialogu göster
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D1B0E),
        title: Row(
          children: const [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Fotoğrafı Sil',
                style: TextStyle(color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: const Text(
          'Bu fotoğrafı kalıcı olarak silmek istediğinizden emin misiniz?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal', style: TextStyle(color: Colors.orange)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await photoFile.delete();
        // Yan not dosyasını da temizle (varsa) – hem "_notes.json" hem de ".notes.json" varyasyonları
        try {
          // Sidecar yolunu türetmek için yaygın görsel uzantılarını kaldır
          final baseNoExt = photoFile.path.replaceAll(
            RegExp(r'\.(png|jpg|jpeg|webp|heic|heif|bmp)$', caseSensitive: false),
            '',
          );
          final sidecarCandidates = <String>[
            '${baseNoExt}_notes.json',
            '${baseNoExt}.notes.json',
          ];
          for (final c in sidecarCandidates) {
            final f = File(c);
            if (await f.exists()) {
              try { await f.delete(); } catch (_) {}
            }
          }
        } catch (_) {}
        // Fotoğraf listesini yeniden yükle
        if (_currentKmPath != null) {
          await _loadPhotos(_currentKmPath!);
          // Otomatik klasör silme devre dışı - Android DCIM kısıtlamaları nedeniyle
          // Boş klasörler kalacak ama zarar vermez
          if (_photos.isEmpty && mounted) {
            setState(() { 
              _photos = [];
              _currentKmPath = null; 
            });
            await _loadArchiveStructure();
          }
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fotoğraf başarıyla silindi'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        debugPrint('Fotoğraf silme hatası: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fotoğraf silinemedi'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickFromGalleryToCurrentKm() async {
    if (_currentKmPath == null) return;
    try {
      final hasGallery = await PermissionsHelper.ensureGalleryPermission();
      if (!hasGallery) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fotoğraflara erişim izni gerekiyor. Lütfen izin verin.')),
        );
        await PermissionsHelper.openAppSettingsIfPermanentlyDenied();
        return;
      }

      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => photo.PhotoDrawPage.fromImage(
            File(picked.path),
            saveDirectoryPath: _currentKmPath,
          ),
        ),
      );
      // Dönüşte listeyi yenile
      await _loadPhotos(_currentKmPath!);
    } catch (e) {
      debugPrint('Galeriden seçme hatası: $e');
    }
  }

  void _toggleExpansion(ArchiveItem item) {
    setState(() {
      item.isExpanded = !item.isExpanded;
    });
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
              Icons.terrain_rounded,
              size: 24,
              color: Colors.amber[400],
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'Saha Arşivi',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (_currentKmPath != null && _selectedPhotos.isNotEmpty) ...[
            // Çoklu silme butonu
            Tooltip(
              message: 'Seçili fotoğrafları sil',
              child: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: _deleteSelectedPhotos,
              ),
            ),
            // Google Drive yükleme butonu
            Tooltip(
              message: 'Seçili fotoğrafları Google Drive\'a yükle',
              child: IconButton(
                icon: const Icon(Icons.cloud_upload_outlined, color: Colors.white),
                onPressed: _uploadSelectedToGoogleDrive,
              ),
            ),
          ],
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
                      builder: (context) => photo.PhotoDrawPage.fromImage(File(picked.path)),
                    ),
                  );
                  await _loadArchiveStructure();
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
              Color(0xFF2D3436),
              Color(0xFF4A4F54),
            ],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: _currentKmPath == null
                        ? _buildArchiveTree()
                        : _buildPhotoGrid(),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildArchiveTree() {
    if (_archiveItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_library_rounded,
              size: 64,
              color: Colors.amber[400]?.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Henüz kaydedilmiş fotoğraf bulunmuyor',
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

    return ListView.builder(
      itemCount: _archiveItems.length,
      itemBuilder: (context, index) {
        return _buildArchiveItem(_archiveItems[index], 0);
      },
    );
  }

  Widget _buildArchiveItem(ArchiveItem item, int depth) {
    final hasChildren = item.children.isNotEmpty;
    final isKmLevel = depth == 2; // Kilometre seviyesi
    final isSinifSiz = item.name == 'Sınıfsız' && depth == 0; // Sınıfsız özel durumu

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
          trailing: hasChildren
              ? Icon(
                  item.isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white70,
                )
              : (isKmLevel || isSinifSiz)
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.photo_library, color: Colors.amber, size: 20),
                            onPressed: () => _loadPhotos(item.path),
                            tooltip: 'Fotoğrafları göster',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                          ),
                          // Boş klasör silme düğmesi kaldırıldı - Android DCIM kısıtlamaları nedeniyle
                        ],
                      ),
                    )
                  : null,
          onTap: hasChildren
              ? () => _toggleExpansion(item)
              : (isKmLevel || isSinifSiz)
                  ? () => _loadPhotos(item.path)
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
                  .map((child) => _buildArchiveItem(child, depth + 1))
                  .toList(),
            ),
          ),
      ],
    );
  }



  Widget _buildPhotoGrid() {
    return Column(
      children: [
        // Geri butonu
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useIconOnly = constraints.maxWidth < 320;
              return Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.amber),
                    onPressed: () {
                      setState(() {
                        _photos = [];
                        _currentKmPath = null;
                      });
                    },
                    tooltip: 'Arşive geri dön',
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Fotoğraflar',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (_currentKmPath != null)
                    (useIconOnly
                        ? Tooltip(
                            message: 'Galeriden fotoğraf ekle',
                            child: IconButton(
                              onPressed: _pickFromGalleryToCurrentKm,
                              icon: const Icon(Icons.add_photo_alternate_outlined, color: Colors.amber),
                              tooltip: 'Galeriden fotoğraf ekle',
                            ),
                          )
                        : Tooltip(
                            message: 'Galeriden fotoğraf ekle',
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                minimumSize: const Size(0, 36),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: _pickFromGalleryToCurrentKm,
                              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                              label: const Text('Galeriden Ekle'),
                            ),
                          )),
                ],
              );
            },
          ),
        ),
        // Fotoğraf grid'i
        Expanded(
          child: _photos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Bu klasörde fotoğraf yok',
                        style: TextStyle(color: Colors.white70),
                      ),
                      // Klasör silme düğmesi kaldırıldı - Android DCIM kısıtlamaları nedeniyle
                    ],
                  ),
                )
              : GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _photos.length,
            itemBuilder: (context, index) {
              final photoMap = _photos[index];
              final photoFile = photoMap['file'] as File;
              String lastSegment(String p) {
                final norm = p.replaceAll('\\', '/');
                final parts = norm.split('/');
                return parts.isNotEmpty ? parts.last : p;
              }
              final kmName = lastSegment(photoFile.parent.path);

              return Stack(
                children: [
                  InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => photo.PhotoDrawPage.fromImage(photoFile),
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber[700]!),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Stack(
                          children: [
                            // Ana fotoğraf gösterimi
                            Positioned.fill(
                              child: Image.file(
                                photoFile,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  debugPrint('🚨 Image.file ERROR: $error');
                                  debugPrint('🚨 Image path: ${photoFile.path}');
                                  debugPrint('🚨 File exists: ${photoFile.existsSync()}');
                                  return Container(
                                    color: Colors.grey[300],
                                    child: const Center(
                                      child: Icon(Icons.image_not_supported, color: Colors.grey, size: 40),
                                    ),
                                  );
                                },
                              ),
                            ),
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
                                  kmName,
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
                                if (_selectedPhotos.contains(photoMap)) {
                                  _selectedPhotos.remove(photoMap);
                                } else {
                                  _selectedPhotos.add(photoMap);
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: _selectedPhotos.contains(photoMap)
                                    ? Colors.blue.withOpacity(0.8)
                                    : Colors.black54,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Icon(
                                _selectedPhotos.contains(photoMap)
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
                            onTap: () => _deletePhoto(photoFile),
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
                            onTap: () async {
                              try {
                                await Share.shareXFiles([XFile(photoFile.path)]);
                              } catch (e) {
                                debugPrint('Paylaşım hatası: $e');
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Paylaşım yapılamadı')),
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.black54,
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
            },
          ),
        ),
      ],
    );
  }

  // Yerelde klasör silme butonu kaldırıldı; son fotoğraf silindiğinde klasör otomatik siliniyor.

  // Google Drive'a seçili fotoğrafları yükleme metodu
  Future<void> _uploadSelectedToGoogleDrive() async {
    // Google Drive giriş kontrolü
    if (!GoogleDriveService.instance.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Google Drive\'a giriş yapmanız gerekiyor'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (_selectedPhotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yüklemek için fotoğraf seçin')),
      );
      return;
    }

    if (_currentKmPath == null) return;

    setState(() => _isLoading = true);

    try {
      // Km path'den klasör bilgilerini çıkar
      final pathSegments = _currentKmPath!
          .replaceAll('\\', '/')
          .split('/')
          .where((e) => e.isNotEmpty)
          .toList();

      String kat = 'Diğer';
      String ayna = 'Diğer';
      String km = 'Diğer';

      if (pathSegments.length >= 3) {
        kat = pathSegments[pathSegments.length - 3];
        ayna = pathSegments[pathSegments.length - 2];
        km = pathSegments.last;
      }

      final driveService = GoogleDriveService.instance;
      final metadataService = PhotoMetadataService.instance;
      int uploaded = 0;
      int total = _selectedPhotos.length;
      
      // Paralel işleme için fotoğrafları küçük gruplara böl
      const batchSize = 3; // Aynı anda max 3 dosya yükle
      final photoBatches = <List<File>>[];
      
      for (int i = 0; i < _selectedPhotos.length; i += batchSize) {
        final endIndex = (i + batchSize > _selectedPhotos.length) 
            ? _selectedPhotos.length 
            : i + batchSize;
        final batch = _selectedPhotos.skip(i).take(endIndex - i).toList();
        photoBatches.add(batch.map((photoMap) => photoMap['file'] as File).toList());
      }

      for (final batch in photoBatches) {
        final futures = batch.map((photo) async {
          try {
            // JSON not dosyasını oku
            String notes = '';
            final photoPath = photo.path;
            final extension = photoPath.split('.').last;
            final basePath = photoPath.substring(0, photoPath.lastIndexOf('.'));
            
            // Farklı not dosyası formatlarını dene
            final possiblePaths = [
              '${basePath}.notes.json',           // annotated_123.notes.json (DOĞRU FORMAT)
              '${basePath}_notes.json',           // annotated_123_notes.json
              photoPath.replaceAll('.png', '.notes.json').replaceAll('.jpg', '.notes.json'), // Eski format
              photoPath.replaceAll('.png', '_notes.json').replaceAll('.jpg', '_notes.json'), // Başka format
            ];
            
            // Aynı klasördeki tüm .json dosyalarını da kontrol et
            final photoDir = Directory(photoPath.substring(0, photoPath.lastIndexOf('/')));
            if (await photoDir.exists()) {
              final jsonFiles = await photoDir.list()
                  .where((file) => file.path.endsWith('.json'))
                  .cast<File>()
                  .toList();
              for (final jsonFile in jsonFiles) {
                possiblePaths.add(jsonFile.path);
              }
            }
            
            print('🔍 ===== GOOGLE DRIVE YÜKLEME BAŞLADI =====');
            print('🔍 Fotoğraf yolu: $photoPath');
            print('🔍 Base path: $basePath');
            print('🔍 Extension: $extension');
            print('🔍 Olası not dosyası yolları:');
            for (int i = 0; i < possiblePaths.length; i++) {
              print('   $i: ${possiblePaths[i]}');
            }
            
            bool notesFound = false;
            for (final jsonPath in possiblePaths) {
              final jsonFile = File(jsonPath);
              print('🔍 Kontrol ediliyor: $jsonPath');
              if (await jsonFile.exists()) {
                notes = await jsonFile.readAsString();
                print('✅ Not dosyası bulundu: $jsonPath (${notes.length} karakter)');
                print('📄 Not içeriği: ${notes.substring(0, notes.length.clamp(0, 100))}...');
                notesFound = true;
                
                // Debug için SnackBar göster
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Not bulundu: ${notes.length} karakter'),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
                break;
              } else {
                print('❌ Dosya bulunamadı: $jsonPath');
              }
            }
            
            if (!notesFound) {
              print('❌ Orijinal klasörde not dosyası bulunamadı');
              print('🔍 Yedek sidecar dosyası kontrol ediliyor...');
              
              // Debug için SnackBar göster
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('❌ Not dosyası bulunamadı: $basePath.notes.json'),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
              
              // Yedek sidecar dosyasını kontrol et
              try {
                // Uygulama belgeleri dizinini al
                final appDir = await getApplicationDocumentsDirectory();
                final sidecarDirPath = '${appDir.path}/FotoJeolog/sidecars';
                final sidecarDir = Directory(sidecarDirPath);
                if (await sidecarDir.exists()) {
                  // Base64 encoded path oluştur
                  final bytes = utf8.encode(photoPath);
                  final base64Path = base64.encode(bytes);
                  final sidecarPath = '${appDir.path}/FotoJeolog/sidecars/$base64Path.notes.json';
                  
                  print('🔍 Yedek sidecar yolu: $sidecarPath');
                  final sidecarFile = File(sidecarPath);
                  if (await sidecarFile.exists()) {
                    notes = await sidecarFile.readAsString();
                    print('✅ Yedek sidecar dosyası bulundu: $sidecarPath (${notes.length} karakter)');
                    print('📄 Yedek not içeriği: ${notes.substring(0, notes.length.clamp(0, 100))}...');
                    notesFound = true;
                  } else {
                    print('❌ Yedek sidecar dosyası da bulunamadı: $sidecarPath');
                  }
                } else {
                  print('❌ Sidecar klasörü mevcut değil: $sidecarDir');
                }
              } catch (e) {
                print('❌ Yedek sidecar kontrolü hatası: $e');
              }
              
              if (!notesFound) {
                print('❌ Hiçbir not dosyası bulunamadı');
                print('🔍 Klasördeki tüm dosyalar:');
                try {
                  final photoDir = Directory(photoPath.substring(0, photoPath.lastIndexOf('/')));
                  if (await photoDir.exists()) {
                    final allFiles = await photoDir.list().toList();
                    for (final file in allFiles) {
                      print('   📁 ${file.path}');
                    }
                  }
                } catch (e) {
                  print('❌ Klasör listesi alınamadı: $e');
                }
                
                // Debug için SnackBar göster
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ Hiçbir not dosyası bulunamadı: $basePath'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              }
            }
            
            print('🔍 Google Drive\'a yüklenecek not uzunluğu: ${notes.length}');
            print('🔍 ===== GOOGLE DRIVE YÜKLEME BİTTİ =====');

            // Önce fotoğrafı Google Drive'a yükle
            final fileName = 'jeoloji_${DateTime.now().millisecondsSinceEpoch}.png';
            List<String> folderPath = [kat, ayna, km];
            
            final imageFileId = await driveService.uploadFile(photo.path, folderPath);
            
            if (imageFileId != null) {
              // Sonra metadata'yı kaydet
              await metadataService.savePhotoMetadata(
                imageFileName: fileName,
                notes: notes,
                projectName: 'FotoJeolog Saha',
                kat: kat,
                ayna: ayna,
                km: km,
              );
              
              // Debug için SnackBar göster
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('☁️ Google Drive\'a yüklendi: ${notes.length} karakter not ile'),
                    backgroundColor: Colors.blue,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            } else {
              throw Exception('Fotoğraf Google Drive\'a yüklenemedi');
            }

            return true;
          } catch (e) {
            debugPrint('Fotoğraf yükleme hatası: $e');
            return false;
          }
        });

        final results = await Future.wait(futures);
        uploaded += results.where((success) => success).length;
        
        // İlerleme güncelleme
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('İlerleme: $uploaded/$total yüklendi'),
              duration: const Duration(milliseconds: 500),
            ),
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ $uploaded/$total fotoğraf Google Drive\'a yüklendi'),
          backgroundColor: uploaded == total ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
      
      // Debug: Yükleme sonucu detayı
      print('🔍 Yükleme tamamlandı: $uploaded/$total fotoğraf yüklendi');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🔍 Debug: $uploaded/$total fotoğraf yüklendi'),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Seçimi temizle
      setState(() => _selectedPhotos.clear());

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Google Drive yükleme hatası: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }

    setState(() => _isLoading = false);
  }

  /// Seçili fotoğrafları sil
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
    print('🗑️ Yerel arşiv: ${selectedCount} fotoğraf silinecek');

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
        print('🗑️ Yerel silme işlemi başlatılıyor...');
        
        int deletedCount = 0;
        for (final photoMap in _selectedPhotos) {
          try {
            final photoFile = photoMap['file'] as File;
            if (await photoFile.exists()) {
              await photoFile.delete();
              deletedCount++;
              print('✅ Yerel silindi: ${photoFile.path}');
            }
          } catch (e) {
            print('❌ Yerel silme hatası: ${photoMap['file']} - $e');
          }
        }
        
        setState(() {
          _selectedPhotos.clear();
        });
        
        // Fotoğrafları yeniden yükle
        if (_currentKmPath != null) {
          await _loadPhotos(_currentKmPath!);
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$deletedCount fotoğraf silindi'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        
        print('✅ Yerel silme işlemi tamamlandı: $deletedCount/$selectedCount');
      } catch (e) {
        print('❌ Yerel toplu silme hatası: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Silme işlemi sırasında hata: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } else {
      print('❌ Yerel silme işlemi iptal edildi');
    }
  }
}