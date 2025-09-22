import 'dart:io';
import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'services/google_drive_service.dart';

class DriveImportPage extends StatefulWidget {
  const DriveImportPage({super.key});

  @override
  State<DriveImportPage> createState() => _DriveImportPageState();
}

class _DriveImportPageState extends State<DriveImportPage> {
  bool _loading = true;
  List<drive.File> _kats = [];
  List<drive.File> _aynas = [];
  List<drive.File> _kms = [];
  List<drive.File> _pngs = [];

  drive.File? _selKat;
  drive.File? _selAyna;
  drive.File? _selKm;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => _loading = true);
    await GoogleDriveService.instance.init();
    if (!GoogleDriveService.instance.isSignedIn) {
      setState(() => _loading = false);
      return;
    }
    final rootId = await GoogleDriveService.instance.ensureRootFotoJeolog();
    final kats = await GoogleDriveService.instance.listFolders(parentId: rootId);
    setState(() {
      _kats = kats;
      _loading = false;
    });
  }

  Future<void> _selectKat(drive.File kat) async {
    setState(() {
      _selKat = kat;
      _selAyna = null;
      _selKm = null;
      _aynas = [];
      _kms = [];
      _pngs = [];
      _loading = true;
    });
    final aynas = await GoogleDriveService.instance.listFolders(parentId: kat.id!);
    setState(() {
      _aynas = aynas;
      _loading = false;
    });
  }

  Future<void> _selectAyna(drive.File ayna) async {
    setState(() {
      _selAyna = ayna;
      _selKm = null;
      _kms = [];
      _pngs = [];
      _loading = true;
    });
    final kms = await GoogleDriveService.instance.listFolders(parentId: ayna.id!);
    setState(() {
      _kms = kms;
      _loading = false;
    });
  }

  Future<void> _selectKm(drive.File km) async {
    setState(() {
      _selKm = km;
      _pngs = [];
      _loading = true;
    });
    final pngs = await GoogleDriveService.instance.listPngFiles(parentId: km.id!);
    setState(() {
      _pngs = pngs;
      _loading = false;
    });
  }

  Future<void> _downloadToLocal(drive.File f) async {
    if (_selKat == null || _selAyna == null || _selKm == null) return;
    final dir = Directory('/storage/emulated/0/DCIM/FotoJeolog/${_selKat!.name}/${_selAyna!.name}/${_selKm!.name}');
    if (!dir.existsSync()) await dir.create(recursive: true);
    final filePath = '${dir.path}/${f.name}';
    try {
  await GoogleDriveService.instance.downloadFile(f.id!, filePath);
      // Yanında .notes.json dosyası varsa onu da indir
      final base = (f.name ?? '').replaceAll(RegExp(r'\.png$', caseSensitive: false, multiLine: false), '');
      final notesName = '$base.notes.json';
      final parentId = _selKm!.id!;
      final maybeNotes = await GoogleDriveService.instance.findFileByNameInParent(parentId: parentId, name: notesName);
      if (maybeNotes != null && maybeNotes.id != null) {
        final notesPath = '${dir.path}/$notesName';
  await GoogleDriveService.instance.downloadFile(maybeNotes.id!, notesPath);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İndirildi: ${f.name}${maybeNotes != null ? ' + notlar' : ''}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İndirme hatası: ${f.name}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drive’dan İçe Aktar'),
        backgroundColor: const Color(0xFF1B1F24),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !GoogleDriveService.instance.isSignedIn
              ? _needSignIn()
              : Column(
                  children: [
                    _rowSelector('Kat', _kats, _selKat, _selectKat),
                    _rowSelector('Ayna', _aynas, _selAyna, _selectAyna),
                    _rowSelector('Km', _kms, _selKm, _selectKm),
                    const Divider(),
                    Expanded(child: _pngGrid()),
                  ],
                ),
    );
  }

  Widget _needSignIn() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Drive’a erişim için Ayarlar’dan Google ile giriş yapın'),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () async {
              final ok = await GoogleDriveService.instance.signIn();
              if (ok) {
                await _init();
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Giriş başarısız/iptal')),
                );
              }
            },
            child: const Text('Google ile giriş yap'),
          ),
        ],
      ),
    );
  }

  Widget _rowSelector(String label, List<drive.File> items, drive.File? selected,
      Future<void> Function(drive.File) onSelect) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final it in items)
                  ChoiceChip(
                    label: Text(it.name ?? '—'),
                    selected: selected?.id == it.id,
                    onSelected: (_) => onSelect(it),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pngGrid() {
    if (_pngs.isEmpty) {
      return const Center(child: Text('Seçilen KM altında PNG bulunamadı'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _pngs.length,
      itemBuilder: (context, index) {
        final f = _pngs[index];
        return Card(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Icon(Icons.image, size: 48, color: Colors.grey[600]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  f.name ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: ElevatedButton.icon(
                  onPressed: () => _downloadToLocal(f),
                  icon: const Icon(Icons.download),
                  label: const Text('İndir'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
