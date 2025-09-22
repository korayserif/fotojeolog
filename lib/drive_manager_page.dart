import 'package:flutter/material.dart';
import 'services/google_drive_service.dart';

class DriveManagerPage extends StatefulWidget {
  const DriveManagerPage({super.key});

  @override
  State<DriveManagerPage> createState() => _DriveManagerPageState();
}

class _DriveManagerPageState extends State<DriveManagerPage> {
  List<Map<String, dynamic>> _driveFiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDriveFiles();
  }

  Future<void> _loadDriveFiles() async {
    setState(() => _loading = true);
    try {
      final files = await GoogleDriveService.instance.listFiles();
      if (mounted) {
        setState(() {
          // listFiles returns List<drive.File>?; map to simple maps for UI
          final mapped = (files ?? []).map((f) => {
                'id': f.id ?? '',
                'name': f.name ?? '—',
                'createdTime': f.createdTime?.toIso8601String() ?? '',
              }).toList();
          _driveFiles = mapped;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Drive dosyaları yüklenemedi: $e')),
        );
      }
    }
  }

  Future<void> _deleteFile(String fileId, String fileName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dosyayı sil'),
        content: Text('$fileName dosyasını Drive\'dan silmek istediğinizden emin misiniz?'),
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

    if (confirm == true) {
      try {
        await GoogleDriveService.instance.deleteFile(fileId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Dosya silindi')),
          );
          _loadDriveFiles(); // Listeyi yenile
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Silme hatası: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drive Dosyalarım'),
        backgroundColor: const Color(0xFF1B1F24),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDriveFiles,
          ),
        ],
      ),
      backgroundColor: const Color(0xFF0F1215),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _driveFiles.isEmpty
              ? const Center(
                  child: Text(
                    'Drive\'da henüz dosya yok',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _driveFiles.length,
                  itemBuilder: (context, index) {
                    final file = _driveFiles[index];
                    final fileName = file['name'] ?? 'Bilinmeyen dosya';
                    final fileId = file['id'] ?? '';
                    final createdTime = file['createdTime'] ?? '';
                    
                    return Card(
                      color: const Color(0xFF2A2F35),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(
                          Icons.insert_drive_file,
                          color: Color(0xFFFFC107),
                        ),
                        title: Text(
                          fileName,
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          createdTime.isNotEmpty 
                              ? 'Oluşturulma: ${createdTime.substring(0, 10)}'
                              : 'Tarih bilinmiyor',
                          style: const TextStyle(color: Colors.white54),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteFile(fileId, fileName),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}