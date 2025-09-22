import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/photo_metadata_service.dart';
import 'services/google_drive_service.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'photo_draw_page.dart' as photo;
import 'firebase_login_page.dart';

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

class FirebaseArchivePage extends StatefulWidget {
  const FirebaseArchivePage({super.key});

  @override
  State<FirebaseArchivePage> createState() => _FirebaseArchivePageState();
}

class _FirebaseArchivePageState extends State<FirebaseArchivePage> {
  List<DriveArchiveItem> _archiveItems = [];
  bool _isLoading = false;
  String? _error;
  bool _isSelectionMode = false;
  final Set<PhotoMetadata> _selectedPhotos = {};
  String? _currentKmPath; // Seçili kilometre klasörü
  List<PhotoMetadata> _currentPhotos = []; // Seçili km'deki fotoğraflar

  @override
  void initState() {
    super.initState();
    _checkAuthAndLoadFiles();
  }

  Future<void> _checkAuthAndLoadFiles() async {
    // Firebase Auth servisini başlat
    await FirebaseAuthService.instance.initialize();
    
    // HER ZAMAN GÜNCEL KULLANICIYI KONTROL ET
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      print('🔍 Kullanıcı oturum açmamış, login sayfasına yönlendiriliyor...');
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const FirebaseLoginPage(),
          ),
        );
      }
      return;
    }
    
    print('✅ Kullanıcı oturum açmış: ${currentUser.email} (${currentUser.uid})');
    // Giriş yapmışsa dosyaları yükle
    _initializeAndLoadFiles();
  }

  Future<void> _initializeAndLoadFiles() async {
    try {
      // Firebase servislerini başlat
      await FirebaseAuthService.instance.initialize();
      await FirestoreService.instance.initialize();
      
      // Dosyaları yükle
      _loadFiles();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Firebase başlatma hatası: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadFiles() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      print('🔍 Firestore dosyaları yükleniyor...');
      final service = FirestoreService.instance;
      print('🚀 ===== FIRESTORE ARCHIVE PAGE BAŞLADI =====');
      print('🔍 FirestoreService.instance alındı');
      print('🔍 getUserPhotos() çağrılıyor...');
      final photos = await service.getUserPhotos();
      print('📁 Firestore\'dan ${photos.length} fotoğraf alındı');
      print('🚀 ===== FIRESTORE ARCHIVE PAGE BİTTİ =====');
      
      // Debug: İlk fotoğrafın metadata'sını kontrol et
      if (photos.isNotEmpty) {
        final firstPhoto = photos.first;
        print('🔍 İlk fotoğraf: ${firstPhoto.fileName}');
        print('🔍 İlk fotoğraf notları: "${firstPhoto.notes}"');
        print('🔍 İlk fotoğraf notları uzunluğu: ${firstPhoto.notes.length}');
        
        // Debug: Tüm fotoğrafların notlarını kontrol et
        print('🔍 ===== TÜM FOTOĞRAFLARIN NOTLARI =====');
        for (int i = 0; i < photos.length; i++) {
          final photo = photos[i];
          print('🔍 Fotoğraf $i: ${photo.fileName} - Notlar: "${photo.notes}" (${photo.notes.length} karakter)');
        }
        print('🔍 ===== TÜM FOTOĞRAFLARIN NOTLARI BİTTİ =====');
      }
      
      // Hiyerarşik yapı oluştur
      final archiveItems = _buildHierarchy(photos);
      print('🌳 ${archiveItems.length} hiyerarşik öğe oluşturuldu');
      
      if (mounted) {
        setState(() {
          _archiveItems = archiveItems;
          _isLoading = false;
        });
        print('✅ Firestore arşiv güncellendi');
      }
    } catch (e) {
      print('❌ Firestore yükleme hatası: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  List<FirestoreArchiveItem> _buildHierarchy(List<FirestorePhoto> photos) {
    final Map<String, FirestoreArchiveItem> katMap = {};
    
    for (final photo in photos) {
      print('📄 Fotoğraf işleniyor: ${photo.fileName}');
      print('   Kat: "${photo.kat}", Ayna: "${photo.ayna}", Km: "${photo.km}"');
      
      final kat = photo.kat.isNotEmpty ? photo.kat : 'Diğer';
      final ayna = photo.ayna.isNotEmpty ? photo.ayna : 'Diğer';
      final km = photo.km.isNotEmpty ? photo.km : 'Diğer';
      
      // Kat seviyesi
      if (!katMap.containsKey(kat)) {
        katMap[kat] = FirestoreArchiveItem(
          name: kat,
          path: 'kat/$kat',
        );
        print('   ✅ Kat eklendi: $kat');
      }
      
      // Ayna seviyesi
      final katItem = katMap[kat]!;
      var aynaItem = katItem.children.firstWhere(
        (item) => item.name == ayna,
        orElse: () => FirestoreArchiveItem(
          name: ayna,
          path: 'kat/$kat/ayna/$ayna',
        ),
      );
      
      if (!katItem.children.contains(aynaItem)) {
        katItem.children.add(aynaItem);
        print('   ✅ Ayna eklendi: $ayna');
      }
      
      // Km seviyesi
      var kmItem = aynaItem.children.firstWhere(
        (item) => item.name == km,
        orElse: () => FirestoreArchiveItem(
          name: km,
          path: 'kat/$kat/ayna/$ayna/km/$km',
        ),
      );
      
      if (!aynaItem.children.contains(kmItem)) {
        aynaItem.children.add(kmItem);
        print('   ✅ Km eklendi: $km');
      }
      
      // Fotoğrafı ekle
      kmItem.photos.add(photo);
      print('   ✅ Fotoğraf eklendi: ${photo.fileName}');
    }
    
    // Boş klasörleri temizle
    _cleanupEmptyFolders(katMap);
    
    print('🌳 Hiyerarşi oluşturuldu: ${katMap.length} kat');
    for (final kat in katMap.values) {
      print('   📁 ${kat.name}: ${kat.children.length} ayna');
      for (final ayna in kat.children) {
        print('     👁️ ${ayna.name}: ${ayna.children.length} km');
        for (final km in ayna.children) {
          print('       📍 ${km.name}: ${km.photos.length} fotoğraf');
        }
      }
    }
    
    return katMap.values.toList();
  }

  void _cleanupEmptyFolders(Map<String, FirestoreArchiveItem> katMap) {
    print('🧹 Boş klasörler temizleniyor...');
    
    // Kat seviyesinden başla
    final emptyKats = <String>[];
    for (final entry in katMap.entries) {
      final kat = entry.value;
      print('   🔍 Kat kontrolü: ${kat.name} (${kat.children.length} ayna)');
      
      // Ayna seviyesini temizle
      final emptyAynas = <FirestoreArchiveItem>[];
      for (final ayna in kat.children) {
        print('     🔍 Ayna kontrolü: ${ayna.name} (${ayna.children.length} km)');
        
        // Km seviyesini temizle
        final emptyKms = <FirestoreArchiveItem>[];
        for (final km in ayna.children) {
          print('       🔍 Km kontrolü: ${km.name} (${km.photos.length} fotoğraf)');
          if (km.photos.isEmpty) {
            emptyKms.add(km);
            print('       🗑️ Boş Km silindi: ${km.name}');
          }
        }
        ayna.children.removeWhere((km) => emptyKms.contains(km));
        
        // Boş ayna kontrolü
        if (ayna.children.isEmpty) {
          emptyAynas.add(ayna);
          print('     🗑️ Boş Ayna silindi: ${ayna.name}');
        } else {
          print('     ✅ Ayna korundu: ${ayna.name} (${ayna.children.length} km)');
        }
      }
      kat.children.removeWhere((ayna) => emptyAynas.contains(ayna));
      
      // Boş kat kontrolü
      if (kat.children.isEmpty) {
        emptyKats.add(entry.key);
        print('   🗑️ Boş Kat silindi: ${kat.name}');
      } else {
        print('   ✅ Kat korundu: ${kat.name} (${kat.children.length} ayna)');
      }
    }
    
    // Boş katları sil
    for (final emptyKat in emptyKats) {
      katMap.remove(emptyKat);
    }
    
    print('✅ Boş klasör temizliği tamamlandı');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseAuthService.instance.authStateChanges,
      builder: (context, snapshot) {
        final user = snapshot.data;
        
        if (user == null) {
          return _buildLoginRequired();
        }
        
        return Scaffold(
          backgroundColor: const Color(0xFF1A1A1A),
          appBar: _buildAppBar(user),
          body: _buildBody(),
        );
      },
    );
  }

  Widget _buildLoginRequired() {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        title: const Text('Firebase Arşiv', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF2D2D2D),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Firebase\'e erişim için giriş yapın',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showLoginPage,
              icon: const Icon(Icons.login),
              label: const Text('Giriş Yap'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(user) {
    if (_isSelectionMode) {
      return AppBar(
        backgroundColor: Colors.orange,
        title: Text('${_selectedPhotos.length} seçili'),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () {
            setState(() {
              _isSelectionMode = false;
              _selectedPhotos.clear();
            });
          },
        ),
        actions: [
          TextButton(
            onPressed: _selectAll,
            child: const Text('Tümünü Seç', style: TextStyle(color: Colors.white)),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.white),
            onPressed: _selectedPhotos.isNotEmpty ? _deleteSelectedPhotos : null,
          ),
        ],
      );
    }
    
    if (_currentKmPath != null) {
      return AppBar(
        title: const Text('Fotoğraflar', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF2D2D2D),
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            setState(() {
              _currentKmPath = null;
              _currentPhotos = [];
              _isSelectionMode = false;
              _selectedPhotos.clear();
            });
          },
        ),
      );
    }
    
    return AppBar(
      title: Wrap(
        children: [
          const Text('Firebase Arşiv', style: TextStyle(color: Colors.white)),
          if (user != null)
            Text(
              ' - ${user.isAnonymous ? 'Misafir' : user.displayName ?? 'Kullanıcı'}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
        ],
      ),
      backgroundColor: const Color(0xFF2D2D2D),
      iconTheme: const IconThemeData(color: Colors.white),
      actions: [
        if (user != null)
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle, color: Colors.white),
            onSelected: (value) {
              switch (value) {
                case 'logout':
                  _signOut();
                  break;
                case 'login':
                  _showLoginPage();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Çıkış Yap'),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildBody() {
    if (_currentKmPath != null) {
      return _buildPhotoGrid();
    }
    
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.orange),
      );
    }
    
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Hata: $_error', style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadFiles,
              child: const Text('Tekrar Dene'),
            ),
          ],
        ),
      );
    }
    
    if (_archiveItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Firebase\'de fotoğraf bulunmuyor',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _loadFiles,
      color: Colors.orange,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _archiveItems.length,
        itemBuilder: (context, index) {
          return _buildArchiveItemWidget(_archiveItems[index], 0);
        },
      ),
    );
  }

  Widget _buildArchiveItemWidget(FirestoreArchiveItem item, double indent) {
    final hasChildren = item.children.isNotEmpty;
    final hasPhotos = item.photos.isNotEmpty;
    final isKmLevel = item.path.contains('/km/');
    
    return Column(
      children: [
        Card(
          margin: EdgeInsets.only(left: indent, bottom: 4),
          color: const Color(0xFF2D2D2D),
          child: ListTile(
            leading: Icon(
              isKmLevel ? Icons.location_on : 
              item.path.contains('/ayna/') ? Icons.visibility : Icons.layers,
              color: Colors.orange,
            ),
            title: Text(
              item.name,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: isKmLevel && hasPhotos
                ? Text(
                    '${item.photos.length} fotoğraf',
                    style: const TextStyle(color: Colors.grey),
                  )
                : null,
            trailing: hasChildren || (isKmLevel && hasPhotos)
                ? Icon(
                    item.isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white,
                  )
                : null,
            onTap: () {
              if (isKmLevel && hasPhotos) {
                // Km seviyesine tıklandığında grid görünümüne geç
                _loadPhotos(item.photos, item.path);
              } else if (hasChildren) {
                setState(() {
                  item.isExpanded = !item.isExpanded;
                });
              }
            },
          ),
        ),
        // Alt öğeleri göster
        if (item.isExpanded && hasChildren)
          ...item.children.map((child) => _buildArchiveItemWidget(child, indent + 16)),
      ],
    );
  }

  void _loadPhotos(List<FirestorePhoto> photos, String path) {
    setState(() {
      _currentKmPath = path;
      _currentPhotos = photos;
      _isSelectionMode = false;
      _selectedPhotos.clear();
    });
  }

  Widget _buildPhotoGrid() {
    if (_currentPhotos.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Bu klasörde fotoğraf bulunmuyor',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Geri dön butonu
        Container(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    _currentKmPath = null;
                    _currentPhotos = [];
                    _isSelectionMode = false;
                    _selectedPhotos.clear();
                  });
                },
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              Expanded(
                child: Text(
                  'Fotoğraflar (${_currentPhotos.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Fotoğraf grid'i
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1,
            ),
            itemCount: _currentPhotos.length,
            itemBuilder: (context, index) {
              final photo = _currentPhotos[index];
              return _buildPhotoGridItem(photo);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoGridItem(FirestorePhoto photo) {
    final isSelected = _selectedPhotos.contains(photo);
    
    return Stack(
      children: [
        InkWell(
          onTap: () => _downloadAndOpenImage(photo),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber[700]!),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                photo.imagePath,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: Colors.grey[800],
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.orange),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey[800],
                    child: const Center(
                      child: Icon(Icons.error, color: Colors.red, size: 32),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        // Seçim checkbox'ı
        Positioned(
          top: 8,
          left: 8,
          child: GestureDetector(
            onTap: () {
              setState(() {
                if (_selectedPhotos.contains(photo)) {
                  _selectedPhotos.remove(photo);
                } else {
                  _selectedPhotos.add(photo);
                }
                _isSelectionMode = _selectedPhotos.isNotEmpty;
              });
            },
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isSelected ? Colors.blue : Colors.white.withOpacity(0.8),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.blue, width: 2),
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
          ),
        ),
        // Silme butonu
        if (_isSelectionMode)
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () => _deleteSinglePhoto(photo),
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete, color: Colors.white, size: 16),
              ),
            ),
          ),
        // Paylaşım butonu
        Positioned(
          bottom: 8,
          right: 8,
          child: GestureDetector(
            onTap: () => _sharePhoto(photo),
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.share, color: Colors.white, size: 18),
            ),
          ),
        ),
        // Km etiketi
        Positioned(
          bottom: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              photo.km.isNotEmpty ? photo.km : 'Km',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _downloadAndOpenImage(FirestorePhoto photoFile) async {
    try {
      setState(() => _isLoading = true);

      print('🔍 Firestore fotoğraf açılıyor: ${photoFile.fileName}');
      print('📄 Notlar var mı: ${photoFile.notes.isNotEmpty}');
      print('📄 Notlar uzunluğu: ${photoFile.notes.length}');
      print('📄 Notlar içeriği: ${photoFile.notes.substring(0, photoFile.notes.length.clamp(0, 300))}...');

      // Geçici dosya oluştur
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${photoFile.fileName}');
      final jsonFile = File('${tempDir.path}/${photoFile.fileName}.notes.json');

      // Firestore'dan resmi indir (imagePath kullan)
      final response = await http.get(Uri.parse(photoFile.imagePath));
      if (response.statusCode == 200) {
        await tempFile.writeAsBytes(response.bodyBytes);
        print('✅ Firestore fotoğrafı indirildi: ${tempFile.path}');

        // Notları JSON dosyasına yaz
        if (photoFile.notes.isNotEmpty) {
          try {
            // Firestore'dan gelen notları doğrudan JSON dosyasına yaz
            await jsonFile.writeAsString(photoFile.notes);
            print('✅ Firestore notları JSON dosyasına yazıldı: ${jsonFile.path}');
            print('📄 JSON dosyası var mı: ${await jsonFile.exists()}');
            print('📄 JSON dosyası boyutu: ${await jsonFile.length()} bytes');
            
            // JSON dosyasının içeriğini kontrol et
            final jsonContent = await jsonFile.readAsString();
            print('📄 JSON dosyası içeriği: ${jsonContent.substring(0, jsonContent.length.clamp(0, 200))}...');
          } catch (e) {
            print('⚠️ Firestore notları yazılamadı: $e');
          }
        } else {
          print('ℹ️ Bu fotoğrafın notu yok');
        }

        if (mounted) {
          // Fotoğraf çizim sayfasında aç (JSON dosyası ile birlikte)
          final jsonPath = photoFile.notes.isNotEmpty ? jsonFile.path : null;
          print('🔍 PhotoDrawPage açılıyor - JSON path: $jsonPath');
          
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => photo.PhotoDrawPage.fromImage(
                tempFile,
                jsonPath: jsonPath,
              ),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Firebase fotoğraf açma hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('İndirme hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sharePhoto(FirestorePhoto photoFile) async {
    try {
      // Geçici dosya oluştur
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${photoFile.fileName}');

      // Firestore'dan resmi indir
      final response = await http.get(Uri.parse(photoFile.imagePath));
      if (response.statusCode == 200) {
        await tempFile.writeAsBytes(response.bodyBytes);

        // Paylaş
        await Share.shareXFiles(
          [XFile(tempFile.path)],
          text: 'FotoJeolog - ${photoFile.kat}/${photoFile.ayna}/${photoFile.km}',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Paylaşım hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _selectAll() {
    setState(() {
      if (_selectedPhotos.length == _currentPhotos.length) {
        _selectedPhotos.clear();
      } else {
        _selectedPhotos.addAll(_currentPhotos);
      }
    });
  }

  Future<void> _deleteSinglePhoto(FirestorePhoto photoFile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fotoğrafı Sil'),
        content: const Text('Bu fotoğrafı silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirestoreService.instance.deletePhoto(photoFile.id);
        setState(() {
          _currentPhotos.remove(photoFile);
          _selectedPhotos.remove(photoFile);
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Fotoğraf silindi'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
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
  }

  Future<void> _deleteSelectedPhotos() async {
    if (_selectedPhotos.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fotoğrafları Sil'),
        content: Text('${_selectedPhotos.length} fotoğrafı silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final service = FirestoreService.instance;
        int successCount = 0;
        
        for (final photo in _selectedPhotos) {
          try {
            await service.deletePhoto(photo.id);
            _currentPhotos.remove(photo);
            successCount++;
          } catch (e) {
            print('Fotoğraf silinemedi: ${photo.fileName} - $e');
          }
        }
        
        setState(() {
          _selectedPhotos.clear();
          _isSelectionMode = false;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$successCount fotoğraf silindi'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
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
  }

  void _showLoginPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const FirebaseLoginPage(),
      ),
    );
  }

  Future<void> _signOut() async {
    try {
      print('🚪 Firebase Archive sayfasından çıkış yapılıyor...');
      
      // Kullanıcı verilerini temizle
      setState(() {
        _archiveItems = [];
        _currentPhotos = [];
        _selectedPhotos.clear();
        _isLoading = false;
        _error = null;
      });
      
      // Firebase'den çıkış yap
      await FirebaseAuthService.instance.signOut();
      
      if (mounted) {
        // Login sayfasına yönlendir
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const FirebaseLoginPage(),
          ),
        );
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Başarıyla çıkış yapıldı'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ Çıkış hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Çıkış hatası: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}