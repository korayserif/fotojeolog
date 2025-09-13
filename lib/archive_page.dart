import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fotojeolog/photo_draw_page.dart' as photo;
import 'package:share_plus/share_plus.dart';

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
  List<File> _photos = [];
  bool _isLoading = true;
  String? _currentKmPath; // Seçili kilometre klasörü

  @override
  void initState() {
    super.initState();
    _loadArchiveStructure();
  }

  Future<void> _loadArchiveStructure() async {
    setState(() => _isLoading = true);
    try {
      final baseDir = await getApplicationDocumentsDirectory();
      final rootDir = Directory(baseDir.path);
      
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
    } catch (e) {
      debugPrint('Arşiv yükleme hatası: $e');
      setState(() => _isLoading = false);
    }
  }

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
    setState(() => _isLoading = true);
    try {
      final kmDir = Directory(kmPath);
      
      if (!kmDir.existsSync()) {
        setState(() => _isLoading = false);
        return;
      }

      final photoFiles = kmDir.listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.png'))
          .toList();
      
      setState(() {
        _photos = photoFiles;
        _currentKmPath = kmPath;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Fotoğraf listesi yükleme hatası: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickFromGalleryToCurrentKm() async {
    if (_currentKmPath == null) return;
    try {
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
            const Text('Saha Arşivi'),
          ],
        ),
        actions: [
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
                    child: _photos.isEmpty
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
              : isKmLevel
                  ? IconButton(
                      icon: const Icon(Icons.photo_library, color: Colors.amber),
                      onPressed: () => _loadPhotos(item.path),
                      tooltip: 'Fotoğrafları göster',
                    )
                  : null,
          onTap: hasChildren
              ? () => _toggleExpansion(item)
              : isKmLevel
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
          child: Row(
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
              Text(
                'Fotoğraflar',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_currentKmPath != null)
                Tooltip(
                  message: 'Galeriden fotoğraf ekle',
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onPressed: _pickFromGalleryToCurrentKm,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Galeriden Ekle'),
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
              childAspectRatio: 1,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _photos.length,
            itemBuilder: (context, index) {
              final photoFile = _photos[index];
              String _lastSegment(String p) {
                final norm = p.replaceAll('\\', '/');
                final parts = norm.split('/');
                return parts.isNotEmpty ? parts.last : p;
              }
              final kmName = _lastSegment(photoFile.parent.path);

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
                            Positioned.fill(
                              child: Image.file(
                                photoFile,
                                fit: BoxFit.cover,
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
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Material(
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
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}