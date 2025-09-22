import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/google_drive_service.dart';
import 'photo_draw_page.dart' as photo;
import 'permissions_helper.dart';

class DriveArchiveItem {
  final String name;
  final List<String> pathParts; // FotoJeolog altındaki yol (Kat/Ayna/Km)
  final List<DriveArchiveItem> children;
  bool isExpanded;

  DriveArchiveItem({
    required this.name,
    required this.pathParts,
    this.children = const [],
    this.isExpanded = false,
  });
}

class DriveArchivePage extends StatefulWidget {
  const DriveArchivePage({super.key});

  @override
  _DriveArchivePageState createState() => _DriveArchivePageState();
}

class _DriveArchivePageState extends State<DriveArchivePage> {
  bool _isLoading = true;
  String? _errorMessage;
  String _loadingMessage = 'Drive bağlantısı kuruluyor...';

  // Ağaç görünümü için
  List<DriveArchiveItem> _tree = [];

  // Grid görünümü için
  List<Map<String, dynamic>> _currentKmFiles = [];
  List<String>? _currentKmPathParts;
  
  // 🚀 PERFORMANS: Tüm dosyaları cache'de tut
  List<Map<String, dynamic>> _allDriveFiles = [];
  static DateTime? _lastCacheTime;
  static const Duration _cacheExpireTime = Duration(minutes: 5); // 5 dakika cache

  // 🗑️ ÇOKLU SİLME: Seçim durumu
  bool _isSelectionMode = false;
  Set<String> _selectedItems = {}; // baseName'leri tut

  @override
  void initState() {
    super.initState();
    _loadDriveTree();
  }

  Future<void> _loadDriveTree() async {
    print('🔄 DriveArchivePage: _loadDriveTree başlatıldı');
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _currentKmFiles = [];
      _currentKmPathParts = null;
      _loadingMessage = 'Drive bağlantısı kuruluyor...';
    });

    try {
      // 🚀 CACHE: Önceki veriler hala geçerli mi kontrol et
      bool useCache = false;
      if (_allDriveFiles.isNotEmpty && _lastCacheTime != null) {
        final timeDiff = DateTime.now().difference(_lastCacheTime!);
        if (timeDiff < _cacheExpireTime) {
          useCache = true;
          setState(() => _loadingMessage = 'Önbellek veriler kullanılıyor...');
          print('📋 Cache kullanılıyor, yaş: ${timeDiff.inSeconds} saniye');
        }
      }
      
      List<Map<String, dynamic>> files;
      if (useCache) {
        files = _allDriveFiles;
      } else {
        setState(() => _loadingMessage = 'Drive dosyaları yükleniyor...');
        await Future.delayed(const Duration(milliseconds: 100)); // UI güncellemesi için
        
        print('📞 DriveArchivePage: GoogleDriveService.listFotojeologFiles() çağrılıyor...');
        files = await GoogleDriveService.instance.listFotojeologFiles();
        print('📦 DriveArchivePage: ${files.length} dosya döndü');
        
        // 🚀 PERFORMANS: Dosyaları cache'de sakla
        _allDriveFiles = files;
        _lastCacheTime = DateTime.now();
      }
      
      setState(() => _loadingMessage = 'Klasör yapısı oluşturuluyor...');
      await Future.delayed(const Duration(milliseconds: 50)); // UI güncellemesi için

      // files elemanları: { imageFile, jsonFile, baseName, modifiedTime, pathParts }
      // pathParts: [Kat, Ayna, Km] veya daha kısa olabilir
      final Map<String, Map<String, List<String>>> grouping = {}; // Kat -> Ayna -> Km listesi

      for (final m in files) {
        final parts = (m['pathParts'] as List?)?.cast<String>() ?? <String>[];
        print('📄 Dosya analizi: pathParts=$parts, baseName=${m['baseName']}');
        if (parts.isEmpty) continue; // Kat/Ayna/Km bekliyoruz; boşsa atlasın
        final kat = parts.isNotEmpty ? parts[0] : 'Genel';
        final ayna = parts.length > 1 ? parts[1] : 'Ayna1';
        final km = parts.length > 2 ? parts[2] : 'Km1';
        print('📂 Klasörler: kat=$kat, ayna=$ayna, km=$km');

        grouping.putIfAbsent(kat, () => {});
        grouping[kat]!.putIfAbsent(ayna, () => <String>[]);
        if (!grouping[kat]![ayna]!.contains(km)) {
          grouping[kat]![ayna]!.add(km);
        }
      }
      
      print('🏗️ Ağaç yapısı: ${grouping.length} kat bulundu');
      grouping.forEach((kat, aynalar) {
        print('  📁 $kat: ${aynalar.length} ayna');
        aynalar.forEach((ayna, kmler) {
          print('    📁 $ayna: ${kmler.length} km (${kmler.join(', ')})');
        });
      });

      setState(() => _loadingMessage = 'Klasör yapısı oluşturuluyor...');
      await Future.delayed(const Duration(milliseconds: 100)); // UI güncellemesi için

      // Ağacı kur
      final List<DriveArchiveItem> tree = [];
      grouping.forEach((kat, aynalar) {
        final List<DriveArchiveItem> aynaItems = [];
        aynalar.forEach((ayna, kmler) {
          final kmItems = kmler.map((km) => DriveArchiveItem(
            name: km,
            pathParts: [kat, ayna, km],
          )).toList();
          aynaItems.add(DriveArchiveItem(
            name: ayna,
            pathParts: [kat, ayna],
            children: kmItems,
          ));
        });
        tree.add(DriveArchiveItem(
          name: kat,
          pathParts: [kat],
          children: aynaItems,
        ));
      });

      setState(() {
        _tree = tree;
        _isLoading = false;

        if (GoogleDriveService.instance.lastError != null) {
          _errorMessage = GoogleDriveService.instance.lastError;
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Drive verileri yüklenemedi: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _openKm(List<String> pathParts) async {
    print('📂 Km açılıyor: ${pathParts.join('/')}');
    
    // Seçilen Km için dosyaları filtrele
    setState(() {
      _isLoading = true;
      _currentKmFiles = [];
      _currentKmPathParts = pathParts;
      _loadingMessage = 'Km klasörü yükleniyor...';
    });
    
    try {
      // 🚀 PERFORMANS: Cache'den filtrele, API çağrısı yapma!
      print('🎯 Cacheden filtreleniyor: ${_allDriveFiles.length} dosya arasinda');
      
      final filtered = _allDriveFiles.where((m) {
        final parts = (m['pathParts'] as List?)?.cast<String>() ?? <String>[];
        // pathParts başlangıcı eşleşsin (kat/ayna/km)
        if (pathParts.length > parts.length) return false;
        for (int i = 0; i < pathParts.length; i++) {
          if (parts[i] != pathParts[i]) return false;
        }
        return true;
      }).toList();
      
      print('✅ ${filtered.length} dosya bulundu: ${pathParts.join('/')}');

      setState(() {
        _currentKmFiles = filtered;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Km filtreleme hatası: $e');
      setState(() {
        _errorMessage = 'Km içeriği yüklenemedi: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _openDrivePhoto(Map<String, dynamic> m) async {
    final imageFile = m['imageFile'];
    final jsonFile = m['jsonFile']; // JSON notları da al
    final baseName = m['baseName'];
    
    print('🖼️ Drive fotoğraf açılıyor: $baseName');
    print('📄 JSON dosyası var mı: ${jsonFile != null}');
    
    try {
      final tempDir = await getTemporaryDirectory();
      final imagePath = '${tempDir.path}/$baseName.png';
      final jsonPath = '${tempDir.path}/$baseName.notes.json';
      
      // PNG dosyasını indir
      final imageOk = await GoogleDriveService.instance.downloadFile(imageFile.id, imagePath);
      if (!imageOk) throw Exception('PNG indirilemedi');
      
      // JSON dosyası varsa onu da indir
      if (jsonFile != null) {
        print('📥 JSON dosyası indiriliyor: ${jsonFile.id}');
        final jsonOk = await GoogleDriveService.instance.downloadFile(jsonFile.id, jsonPath);
        if (!jsonOk) {
          print('⚠️ JSON dosyası indirilemedi, notlar olmayacak');
        } else {
          print('✅ JSON dosyası başarıyla indirildi');
        }
      } else {
        print('ℹ️ Bu fotoğrafın notu yok');
      }
      
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => photo.PhotoDrawPage.fromDriveImage(File(imagePath), jsonPath: jsonFile != null ? jsonPath : null),
        ),
      );
    } catch (e) {
      print('❌ Drive fotoğraf açma hatası: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fotoğraf açılamadı: $e')),
      );
    }
  }

  Future<void> _deleteDrivePhoto(Map<String, dynamic> m) async {
    final imageFile = m['imageFile'];
    final jsonFile = m['jsonFile'];
    final baseName = m['baseName'];
    
    // Onay dialogu göster
    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Fotoğrafı Sil'),
          content: Text('$baseName fotoğrafını Drive\'dan kalıcı olarak silmek istiyor musunuz?\n\nBu işlem geri alınamaz.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );
    
    if (confirmDelete != true) return;
    
    try {
      print('🗑️ Drive fotoğraf siliniyor: $baseName');
      
      // PNG dosyasını sil
      final imageDeleted = await GoogleDriveService.instance.deleteFile(imageFile.id);
      
      // JSON dosyası varsa onu da sil
      bool jsonDeleted = true;
      if (jsonFile != null) {
        jsonDeleted = await GoogleDriveService.instance.deleteFile(jsonFile.id);
      }
      
      if (imageDeleted && jsonDeleted) {
        print('✅ Fotoğraf Drive\'dan silindi: $baseName');
        
        // Cache'i temizle ve listeyi yenile
        _allDriveFiles.clear();
        await _loadDriveTree();
        
        if (_currentKmPathParts != null) {
          await _openKm(_currentKmPathParts!);
          // Eğer bu KM klasöründe hiç fotoğraf kalmadıysa klasörü de otomatik sil
          if (_currentKmFiles.isEmpty) {
            final ok = await GoogleDriveService.instance.deleteFolderByPath(_currentKmPathParts!);
            if (ok) {
              setState(() {
                _currentKmFiles = [];
                _currentKmPathParts = null;
              });
              await _loadDriveTree();
            }
          }
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$baseName Drive\'dan silindi'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Silme işlemi başarısız');
      }
    } catch (e) {
      print('❌ Drive silme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Silme hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteMultiplePhotos() async {
    if (_selectedItems.isEmpty) return;

    final selectedCount = _selectedItems.length;
    
    // Onay dialogu göster
    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Çoklu Fotoğraf Silme'),
          content: Text('Seçili $selectedCount fotoğrafı Drive\'dan kalıcı olarak silmek istiyor musunuz?\n\nBu işlem geri alınamaz.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );
    
    if (confirmDelete != true) return;

    try {
      int deletedCount = 0;
      final List<String> failedItems = [];

      for (final baseName in _selectedItems) {
        print('🗑️ Çoklu silme: $baseName');
        
        // Bu dosyayı bul
        final fileData = _currentKmFiles.firstWhere(
          (f) => f['baseName'] == baseName,
          orElse: () => <String, dynamic>{},
        );
        
        if (fileData.isEmpty) continue;

        final imageFile = fileData['imageFile'];
        final jsonFile = fileData['jsonFile'];
        
        try {
          // PNG dosyasını sil
          final imageDeleted = await GoogleDriveService.instance.deleteFile(imageFile.id);
          
          // JSON dosyası varsa onu da sil
          bool jsonDeleted = true;
          if (jsonFile != null) {
            jsonDeleted = await GoogleDriveService.instance.deleteFile(jsonFile.id);
          }
          
          if (imageDeleted && jsonDeleted) {
            deletedCount++;
            print('✅ Silindi: $baseName');
          } else {
            failedItems.add(baseName);
          }
        } catch (e) {
          print('❌ Silme hatası: $baseName - $e');
          failedItems.add(baseName);
        }
      }

      // Seçim modundan çık
      setState(() {
        _isSelectionMode = false;
        _selectedItems.clear();
      });

      // Cache'i temizle ve listeyi yenile
      _allDriveFiles.clear();
      await _loadDriveTree();
      
      if (_currentKmPathParts != null) {
        await _openKm(_currentKmPathParts!);
        // Eğer bu KM klasöründe hiç fotoğraf kalmadıysa klasörü de otomatik sil
        if (_currentKmFiles.isEmpty) {
          final ok = await GoogleDriveService.instance.deleteFolderByPath(_currentKmPathParts!);
          if (ok) {
            setState(() {
              _currentKmFiles = [];
              _currentKmPathParts = null;
            });
            await _loadDriveTree();
          }
        }
      }

      // Sonuç mesajı
      if (mounted) {
        final message = failedItems.isEmpty 
            ? '$deletedCount fotoğraf başarıyla silindi'
            : '$deletedCount silindi, ${failedItems.length} başarısız: ${failedItems.join(', ')}';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: failedItems.isEmpty ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('❌ Çoklu silme genel hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Çoklu silme hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickFromGalleryToCurrentKm() async {
    if (_currentKmPathParts == null || _currentKmPathParts!.length != 3) return;
    
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

      // Seçilen Km klasörünün Drive path bilgisini hazırla
      final driveKmPath = _currentKmPathParts!; // [Kat, Ayna, Km]
      
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => photo.PhotoDrawPage.fromImage(
            File(picked.path),
            driveKmPath: driveKmPath, // Drive'a yüklemek için path
          ),
        ),
      );
      
      // Dönüşte cache'i temizle ve listeyi yenile
      _allDriveFiles.clear();
      await _loadDriveTree();
      
      if (_currentKmPathParts != null) {
        await _openKm(_currentKmPathParts!);
      }
    } catch (e) {
      debugPrint('Drive galeriden seçme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Galeriden ekleme hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildDriveTree() {
    if (_tree.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('Drive\'da uygun klasör bulunamadı'),
          ],
        ),
      );
    }

    Widget buildNode(DriveArchiveItem item, int depth) {
      final hasChildren = item.children.isNotEmpty;
      final isKmLevel = depth == 2;
      return Column(
        children: [
          ListTile(
            leading: Icon(
              isKmLevel ? Icons.signpost_rounded :
              depth == 0 ? Icons.layers_rounded : Icons.view_in_ar_rounded,
              color: Colors.green[600],
            ),
            title: Text(item.name),
            trailing: hasChildren
                ? Icon(item.isExpanded ? Icons.expand_less : Icons.expand_more)
                : isKmLevel
                    ? IconButton(
                        icon: const Icon(Icons.photo_library),
                        onPressed: () => _openKm(item.pathParts),
                      )
                    : null,
            onTap: hasChildren
                ? () => setState(() => item.isExpanded = !item.isExpanded)
                : isKmLevel
                    ? () => _openKm(item.pathParts)
                    : null,
          ),
          if (item.isExpanded && hasChildren)
            Padding(
              padding: EdgeInsets.only(left: depth * 24.0),
              child: Column(
                children: item.children.map((c) => buildNode(c, depth + 1)).toList(),
              ),
            ),
        ],
      );
    }

    return ListView.builder(
      itemCount: _tree.length,
      itemBuilder: (context, index) => buildNode(_tree[index], 0),
    );
  }

  Widget _buildDriveGrid() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.green),
                onPressed: () {
                  setState(() {
                    _currentKmFiles = [];
                    _currentKmPathParts = null;
                  });
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Fotoğraflar',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_currentKmPathParts != null)
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Tooltip(
                          message: 'Galeriden fotoğraf ekle',
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              minimumSize: const Size(0, 36),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: _pickFromGalleryToCurrentKm,
                            icon: const Icon(Icons.add_photo_alternate_outlined),
                            label: const Text('Galeriden Ekle'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _currentKmFiles.length,
            itemBuilder: (context, index) {
              final m = _currentKmFiles[index];
              final imageFile = m['imageFile'];
              final jsonFile = m['jsonFile']; // JSON notları kontrolü için
              final baseName = m['baseName'];
              // Kart başlığında göstermek üzere KM adını dosyanın kendi pathParts'ından türet
              final List<String> itemPathParts = (m['pathParts'] as List?)?.cast<String>() ?? const <String>[];
              final String kmName = itemPathParts.isNotEmpty
                  ? itemPathParts.last
                  : (_currentKmPathParts?.last ?? 'Km?');
              final thumbUrl = imageFile.thumbnailLink as String?;
              final hasNotes = jsonFile != null; // Not var mı?
              final isSelected = _selectedItems.contains(baseName);
              
              return InkWell(
                onTap: _isSelectionMode 
                    ? () {
                        setState(() {
                          if (isSelected) {
                            _selectedItems.remove(baseName);
                          } else {
                            _selectedItems.add(baseName);
                          }
                        });
                      }
                    : () => _openDrivePhoto(m),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isSelectionMode && isSelected 
                          ? Colors.blue.shade600 
                          : Colors.green.shade400,
                      width: _isSelectionMode && isSelected ? 3 : 1,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Küçük önizleme
                      Positioned.fill(
                        child: FutureBuilder<Map<String, String>?>(
                          future: GoogleDriveService.instance.getAuthHeaders(),
                          builder: (context, snap) {
                            final headers = snap.data;
                            if (thumbUrl != null && thumbUrl.isNotEmpty && headers != null) {
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(11),
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: Image.network(
                                        thumbUrl,
                                        headers: headers,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) {
                                          return Center(
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.image_not_supported, color: Colors.green[700]),
                                                const SizedBox(height: 8),
                                                Text(baseName, maxLines: 1, overflow: TextOverflow.ellipsis),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    // Alt kısımda km bilgisi göster
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
                              );
                            }
                            // Placeholder
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.image, color: Colors.green[700]),
                                  const SizedBox(height: 8),
                                  Text(baseName, maxLines: 1, overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      Positioned(
                        right: 6,
                        top: 6,
                        child: _isSelectionMode ? const SizedBox.shrink() : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 🗑️ SİLME BUTONU
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () async {
                                  await _deleteDrivePhoto(m);
                                },
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
                            // 📤 PAYLAŞ BUTONU
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () async {
                                  // Paylaşmak için indir
                                  try {
                                    final tempDir = await getTemporaryDirectory();
                                    final imagePath = '${tempDir.path}/$baseName-share.png';
                                    final ok = await GoogleDriveService.instance.downloadFile(imageFile.id, imagePath);
                                    if (ok) {
                                      await Share.shareXFiles([XFile(imagePath)]);
                                    }
                                  } catch (_) {}
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
                      // 📝 NOT İKONU: Sol alt köşede not var mı göster
                      if (hasNotes)
                        Positioned(
                          left: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.note_alt, color: Colors.white, size: 16),
                          ),
                        ),
                      // ✅ SEÇİM CHECKBOX'I: Seçim modunda sol üst köşede
                      if (_isSelectionMode)
                        Positioned(
                          left: 6,
                          top: 6,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade400),
                            ),
                            child: Checkbox(
                              value: isSelected,
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedItems.add(baseName);
                                  } else {
                                    _selectedItems.remove(baseName);
                                  }
                                });
                              },
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green.shade800,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Ortak Saha Arşivi'),
        actions: [
          // Çoklu seçim modu için butonlar
          if (_isSelectionMode && _currentKmFiles.isNotEmpty) ...[
            // Tümünü seç/seç kaldır
            IconButton(
              icon: Icon(_selectedItems.length == _currentKmFiles.length ? Icons.select_all : Icons.check_box_outline_blank),
              onPressed: () {
                setState(() {
                  if (_selectedItems.length == _currentKmFiles.length) {
                    _selectedItems.clear();
                  } else {
                    _selectedItems = _currentKmFiles.map((f) => f['baseName'] as String).toSet();
                  }
                });
              },
              tooltip: _selectedItems.length == _currentKmFiles.length ? 'Tümünü Kaldır' : 'Tümünü Seç',
            ),
            // Seçilenleri sil
            IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              onPressed: _selectedItems.isEmpty ? null : () => _deleteMultiplePhotos(),
              tooltip: 'Seçilenleri Sil (${_selectedItems.length})',
            ),
            // Seçim modundan çık
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isSelectionMode = false;
                  _selectedItems.clear();
                });
              },
              tooltip: 'Seçim Modundan Çık',
            ),
          ],
          // Normal mod butonları
          if (!_isSelectionMode) ...[
            // Çoklu seçim moduna geç (sadece Km açıkken göster)
            if (_currentKmFiles.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.checklist_rounded),
                onPressed: () {
                  setState(() {
                    _isSelectionMode = true;
                    _selectedItems.clear();
                  });
                },
                tooltip: 'Çoklu Seçim',
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                print('🔄 Ortak Saha Arşivi yenileniyor...');
                // Cache'i sıfırla ve tüm verileri yeniden yükle
                _allDriveFiles.clear();
                if (_currentKmPathParts == null) {
                  await _loadDriveTree();
                } else {
                  await _loadDriveTree(); // Önce cache'i doldur
                  await _openKm(_currentKmPathParts!); // Sonra filtrele
                }
              },
            ),
          ],
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF102A12),
              Color(0xFF1B5E20),
              Color(0xFF2E7D32),
            ],
          ),
        ),
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _loadingMessage,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  if (_errorMessage != null)
                    Container(
                      width: double.infinity,
                      color: Colors.red.withOpacity(0.1),
                      padding: const EdgeInsets.all(8),
                      child: Text(_errorMessage!, style: const TextStyle(color: Colors.white)),
                    ),
                  Expanded(
                    child: _currentKmPathParts == null
                        ? _buildDriveTree()
                        : _buildDriveGrid(),
                  ),
                ],
              ),
      ),
    );
  }
}