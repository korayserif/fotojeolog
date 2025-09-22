import 'dart:io';
import 'dart:ui' as ui;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'error_handler.dart';
import 'platform_utils.dart';
import 'models/sticky_note.dart';
import 'services/google_drive_service.dart';
import 'services/firebase_storage_service.dart';
import 'permissions_helper.dart';

// Kaydetme hedefi: klasör ve kat/ayna/km bilgileri
class _SaveTarget {
  final Directory dir;
  final String? kat;
  final String? ayna;
  final String? km;
  _SaveTarget(this.dir, {this.kat, this.ayna, this.km});
}

class Stroke {
  final List<Offset> points;
  final Color color;
  final double width;
  final bool isEraser;

  Stroke({
    required this.points,
    required this.color,
    required this.width,
    this.isEraser = false,
  });
}

class PhotoDrawPage extends StatefulWidget {
  final File? initialImage;
  final String? saveDirectoryPath; // Hedef klasör (isteğe bağlı)
  final String? driveJsonPath; // Drive'dan indirilen JSON path'i
  final List<String>? driveKmPath; // Drive Km klasörü [Kat, Ayna, Km]

  const PhotoDrawPage({super.key, this.saveDirectoryPath})
      : initialImage = null, driveJsonPath = null, driveKmPath = null;

  const PhotoDrawPage.fromImage(File image, {super.key, this.saveDirectoryPath, this.driveKmPath})
      : initialImage = image, driveJsonPath = null;

  const PhotoDrawPage.fromDriveImage(File image, {super.key, this.saveDirectoryPath, String? jsonPath})
      : initialImage = image, driveJsonPath = jsonPath, driveKmPath = null;

  @override
  State<PhotoDrawPage> createState() => _PhotoDrawPageState();
}

class _PhotoDrawPageState extends State<PhotoDrawPage> {
  File? _selectedImage;
  Size? _imageSize;
  final List<Stroke> _strokes = [];
  final List<Stroke> _redoStack = [];
  Color selectedColor = Colors.amber.shade300;
  double strokeWidth = 2.0;
  double strokeOpacity = 1.0;
  bool _isEraser = false;
  final bool _showGrid = false;
  final TransformationController _transformController =
      TransformationController();
  final GlobalKey _globalKey = GlobalKey();
  // Çizim koordinatlarını düzgün almak için viewer key'i
  final GlobalKey _viewerKey = GlobalKey();
  bool _isLoading = false;

  // Yapışkan notlar durumu
  final List<StickyNote> _notes = [];
  final List<StickyNote> _deletedNotes = []; // Silinen notları geri getirmek için
  final GlobalKey _notesOverlayKey = GlobalKey();
  String? _draggingNoteId;
  Offset _dragDelta = Offset.zero;
  bool _isResizingAnyNote = false;

  // Son seçilen sınıflandırma bilgilerini Drive yüklemesi için tutalım
  String? _lastKat;
  String? _lastAyna;
  String? _lastKm;

  @override
  void initState() {
    super.initState();
    _selectedImage = widget.initialImage;
    if (_selectedImage != null) {
      _loadImageSize(_selectedImage!);
      
      // Drive'dan gelen fotoğraf için özel JSON yükleme
      if (widget.driveJsonPath != null) {
        _loadDriveNotesForImage(widget.driveJsonPath!);
      } else {
        // Normal lokal JSON yükleme
        _tryLoadNotesForImage(_selectedImage!);
        // İlk frame sonrasında da bir kez daha dene (güvence)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final img = _selectedImage;
          if (img != null) {
            _tryLoadNotesForImage(img);
          }
        });
        // İkinci frame sonrasında da dene (görsel yüklendikten sonra)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 500), () {
            final img = _selectedImage;
            if (img != null && mounted) {
              _tryLoadNotesForImage(img);
            }
          });
        });
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    setState(() => _isLoading = true);
    await ErrorHandler.safeExecute(
      () async {
        // Çalışma zamanı izinleri
        if (source == ImageSource.camera) {
          final ok = await PermissionsHelper.ensureCameraPermission();
          if (!ok) {
            throw PlatformException(code: 'permission_denied', message: 'Kamera izni gerekli');
          }
        } else {
          final ok = await PermissionsHelper.ensureGalleryPermission();
          if (!ok) {
            throw PlatformException(code: 'permission_denied', message: 'Fotoğraflara erişim izni gerekli');
          }
        }

        final picker = ImagePicker();
        final XFile? pickedFile = await picker.pickImage(source: source);
        if (pickedFile != null) {
          setState(() {
            _selectedImage = File(pickedFile.path);
            _strokes.clear();
            _redoStack.clear();
            _imageSize = null;
            _notes.clear();
          });
          await _loadImageSize(_selectedImage!);
          await _tryLoadNotesForImage(_selectedImage!);
        }
      },
      context,
      errorTitle: 'Fotoğraf Seçme Hatası',
      errorMessage: 'Fotoğraf seçilirken bir hata oluştu.',
    );
    setState(() => _isLoading = false);
  }

  Future<void> _loadImageSize(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      if (mounted) {
        setState(() {
          _imageSize = Size(img.width.toDouble(), img.height.toDouble());
        });
      }
      img.dispose();
      codec.dispose();
    } catch (_) {
      // ignore
    }
  }

  Future<void> _loadDriveNotesForImage(String jsonPath) async {
    try {
      print('📥 Drive JSON yükleniyor: $jsonPath');
      
      final file = File(jsonPath);
      if (await file.exists()) {
        final json = await file.readAsString();
        print('📄 Drive JSON içeriği uzunluğu: ${json.length}');
        print('📄 Drive JSON içeriği: ${json.substring(0, json.length.clamp(0, 200))}...');
        
        final loaded = StickyNote.decodeList(json);
        if (mounted) {
          setState(() {
            _notes
              ..clear()
              ..addAll(loaded);
          });
          print('✅ Drive\'dan ${loaded.length} not yüklendi');
          
          // Not sayısını kullanıcıya göster
          if (loaded.isNotEmpty && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Drive\'dan ${loaded.length} not yüklendi'),
                duration: const Duration(seconds: 2),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else {
        print('⚠️ Drive JSON dosyası bulunamadı: $jsonPath');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bu fotoğraf için Drive\'da not bulunamadı'),
              duration: Duration(seconds: 1),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Drive JSON yükleme hatası: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Not yükleme hatası: $e'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _tryLoadNotesForImage(File imageFile) async {
    try {
  String sidecar = _sidecarPathForImage(imageFile.path);
  File file = File(sidecar);
      
      debugPrint('🔍 Sidecar yükleme deneniyor:');
      debugPrint('   Görsel: ${imageFile.path}');
      debugPrint('   Sidecar: $sidecar');
      debugPrint('   Var mı: ${await file.exists()}');
      
      if (!(await file.exists())) {
        final alt = await _findExistingSidecarVariant(imageFile.path);
        if (alt != null) {
          sidecar = alt;
          file = File(sidecar);
          debugPrint('🔄 Alternatif sidecar bulundu: $sidecar');
        }
      }

      if (await file.exists() || await (await _fallbackSidecarFile(imageFile.path)).exists()) {
        if (!await file.exists()) {
          // Ana dosya yoksa yedekten oku
          file = await _fallbackSidecarFile(imageFile.path);
          sidecar = file.path;
          debugPrint('📥 Yedek sidecar kullanılıyor: $sidecar');
        }
        final json = await file.readAsString();
        debugPrint('📄 Sidecar içeriği uzunluğu: ${json.length}');
        debugPrint('📄 Sidecar içeriği: ${json.substring(0, json.length.clamp(0, 200))}...');
        
        final loaded = StickyNote.decodeList(json);
        if (mounted) {
          setState(() {
            _notes
              ..clear()
              ..addAll(loaded);
          });
          debugPrint('✅ ${loaded.length} not yüklendi');
          
          // Not sayısını kullanıcıya göster
          if (loaded.isNotEmpty && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${loaded.length} not yüklendi'),
                duration: const Duration(seconds: 2),
                backgroundColor: Colors.green,
              ),
            );
          } else if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Bu fotoğraf için not bulunamadı'),
                duration: Duration(seconds: 1),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } else {
        debugPrint('❌ Sidecar dosyası bulunamadı: $sidecar');
        if (mounted) {
          setState(() => _notes.clear());
          // Kullanıcıya bildir
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Bu fotoğraf için not dosyası yok'),
                duration: Duration(seconds: 1),
                backgroundColor: Colors.blue,
              ),
            );
          }
        }
      }
    } catch (e) {
      // Yükleme başarısız ise sessizce geç ama debug'da göster
      debugPrint('❌ Not yükleme hatası: $e');
      if (mounted) {
        setState(() => _notes.clear());
        // Kullanıcıya hata bildir
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Not yükleme hatası: $e'),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _sidecarPathForImage(String imagePath) {
    final dot = imagePath.lastIndexOf('.');
    final base = dot >= 0 ? imagePath.substring(0, dot) : imagePath;
    return '$base.notes.json';
  }

  Future<String?> _findExistingSidecarVariant(String imagePath) async {
    // png -> jpg/jpeg veya büyük/küçük harf varyasyonlarını dene
    final candidates = <String>[];
    final dot = imagePath.lastIndexOf('.');
    final base = dot >= 0 ? imagePath.substring(0, dot) : imagePath;

    candidates.add('$base.notes.json');
    // En yaygın varyasyonlar
    for (final ext in ['png', 'PNG', 'jpg', 'JPG', 'jpeg', 'JPEG']) {
      final withExt = '$base.$ext';
      final candidate = _sidecarPathForImage(withExt);
      if (!candidates.contains(candidate)) candidates.add(candidate);
    }

    for (final c in candidates) {
      if (await File(c).exists()) return c;
    }
    return null;
  }

  // İzin/veri yolu sorunları için yedek sidecar konumu (uygulama belgeleri altında)
  Future<File> _fallbackSidecarFile(String imagePath) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/FotoJeolog/sidecars');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final key = base64Url.encode(utf8.encode(imagePath));
    return File('${dir.path}/$key.notes.json');
  }

  Future<void> _saveNotesSidecarFor(String pngPath) async {
    try {
      final notesPath = _sidecarPathForImage(pngPath);
      final content = StickyNote.encodeList(_notes);
      final file = File(notesPath);
      await file.writeAsString(content);
    } catch (_) {
      // Dış depolamaya yazılamadıysa, uygulama belgeleri altına yedekle
      try {
        final fallback = await _fallbackSidecarFile(pngPath);
        final content = StickyNote.encodeList(_notes);
        await fallback.writeAsString(content);
        debugPrint('ℹ️ Sidecar yedek konuma yazıldı: ${fallback.path}');
      } catch (e) {
        debugPrint('❌ Sidecar yazma hatası: $e');
      }
    }
  }

  Future<void> _addNoteAtCenter() async {
    if (_imageSize == null) return;

    // Viewer boyutundan merkez viewport noktayı sahne koordinatına çevir
    final viewerBox = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewerBox == null) return;
    final viewportCenter = viewerBox.size.center(Offset.zero);
    final sceneCenter = _transformController.toScene(viewportCenter);

    final newNote = StickyNote(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      x: sceneCenter.dx,
      y: sceneCenter.dy,
      text: '',
      fontSize: 20,
      collapsed: false,
      textColor: 0xFF000000, // Varsayılan siyah yazı
    );

    setState(() => _notes.add(newNote));
    _saveNotesForCurrentImage();
  }

  Future<void> _saveNotesForCurrentImage() async {
    final img = _selectedImage;
    if (img == null) return;
    await _saveNotesSidecarFor(img.path);
  }

  // Alt sayfa not düzenleyicisi kaldırıldı; notlar doğrudan sarı kağıt üzerinde düzenleniyor.

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() {
      _redoStack.add(_strokes.removeLast());
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    setState(() {
      _strokes.add(_redoStack.removeLast());
    });
  }

  void _undoDeletedNote() {
    if (_deletedNotes.isEmpty) return;
    
    final restoredNote = _deletedNotes.removeLast();
    setState(() {
      _notes.add(restoredNote);
    });
    _saveNotesForCurrentImage();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Not geri getirildi'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _saveImage() async {
    if (_selectedImage == null) return;

    setState(() => _isLoading = true);
    await ErrorHandler.safeExecute(
      () async {
        final boundary = _globalKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) return;

        final pngBytes = byteData.buffer.asUint8List();

        // 1) Kullanıcıdan Kat / Ayna / Km bilgilerini iste
        final _SaveTarget target = await _askAndResolveTargetDir();

        final now = DateTime.now();
        final fileName = 'annotated_${now.millisecondsSinceEpoch}.png';
        final pngPath = '${target.dir.path}/$fileName';
        final file = File(pngPath);

        await file.writeAsBytes(pngBytes);
        await _saveNotesSidecarFor(pngPath);

        // 3) Bulut senkronu açıksa Drive'a yükle
        try {
          final driveSvc = GoogleDriveService.instance;
          await driveSvc.init();
          if (driveSvc.cloudSyncEnabled && driveSvc.isSignedIn) {
            // Klasör yolu: FotoJeolog/Kat/Ayna/Km
            final kat = _lastKat ?? 'Kat1';
            final ayna = _lastAyna ?? 'Ayna1';
            final km = _lastKm ?? 'Km1';
            final parts = ['FotoJeolog', kat, ayna, km];

            // PNG yükle
            await driveSvc.uploadFile(file.path, parts);

            // Notlar varsa sistem temp'de JSON oluştur ve yükle
            if (_notes.isNotEmpty) {
              final notesData = _notes.map((n) => n.toJson()).toList();
              final notesJson = jsonEncode(notesData);
              final notesFileName = fileName.replaceAll('.png', '_notes.json');
              
              // Sistem temp klasöründe geçici JSON dosyası oluştur
              final tempDir = Directory.systemTemp;
              final tempNotesFile = File('${tempDir.path}/$notesFileName');
              await tempNotesFile.writeAsString(notesJson);
              
              // Drive'a yükle
              await driveSvc.uploadFile(tempNotesFile.path, parts);
              
              // Geçici dosyayı temizle
              await tempNotesFile.delete();
            }
          }
        } catch (e) {
          // Drive yüklemesi başarısız - kullanıcıya hata göster
          print('Drive sync hatası: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Drive kaydetme hatası: $e')),
            );
          }
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Kaydedildi: $pngPath${_notes.isNotEmpty ? ' (${_notes.length} not ile)' : ''}'),
          duration: const Duration(seconds: 2),
        ));
      },
      context,
      errorTitle: 'Kaydetme Hatası',
      errorMessage: 'Görüntü kaydedilirken bir hata oluştu.',
    );
    setState(() => _isLoading = false);
  }

  Future<void> _saveImageToDrive() async {
    // Drive oturum kontrol kontrolü - daha güçlü
    final driveSvc = GoogleDriveService.instance;
    if (!driveSvc.isSignedIn) {
      print('❌ Drive oturum kapalı - kaydetme iptal');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Drive\'a giriş yapmalısınız! Önce Drive\'a giriş yapın.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaydedilecek görüntü bulunamadı')),
      );
      return;
    }

    // 🎯 EĞER driveKmPath VARSA DİALOG ATLAYIP DİREKT O KLASÖRE KAYDET
    Map<String, String>? result;
    if (widget.driveKmPath != null && widget.driveKmPath!.length == 3) {
      // Drive'dan geliyorsa dialog atla
      result = {
        'kat': widget.driveKmPath![0],
        'ayna': widget.driveKmPath![1], 
        'km': widget.driveKmPath![2],
      };
      print('🎯 Drive Km path var - dialog atlandı: ${widget.driveKmPath!.join('/')}');
    } else {
      // 🎯 Normal akış: SİNIFLANDIRMA EKRANINI GÖSTER
      print('📋 Drive kaydetme için sınıflandırma ekranı açılıyor...');
      
      // Varsayılan değerleri hazırla
      String? defaultKat = _lastKat;
      String? defaultAyna = _lastAyna;
      String? defaultKm = _lastKm;
      
      result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final katCtrl = TextEditingController(text: defaultKat ?? 'Kat1');
        final aynaCtrl = TextEditingController(text: defaultAyna ?? 'Ayna1');
        final kmCtrl = TextEditingController(text: defaultKm ?? 'Km1');
        String? error;
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E2428),
              title: const Text(
                'Drive Kayıt Sınıflandırması',
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: katCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Kat',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  TextField(
                    controller: aynaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ayna',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  TextField(
                    controller: kmCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Kilometre',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final kat = katCtrl.text.trim();
                    final ayna = aynaCtrl.text.trim();
                    final km = kmCtrl.text.trim();
                    if (kat.isEmpty || ayna.isEmpty || km.isEmpty) {
                      setLocal(() => error = 'Lütfen tüm alanları doldurun');
                      return;
                    }
                    Navigator.pop(context, {
                      'kat': kat,
                      'ayna': ayna,
                      'km': km,
                    });
                  },
                  child: const Text('Drive\'a Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );
    }
    
    if (result == null) {
      print('❌ Kullanıcı sınıflandırma iptal etti');
      return; // Kullanıcı iptal etti
    }
    
    // Seçilen değerleri sakla
    _lastKat = result['kat'];
    _lastAyna = result['ayna'];
    _lastKm = result['km'];
    print('📁 Kullanıcı seçimi: Kat=${_lastKat}, Ayna=${_lastAyna}, Km=${_lastKm}');

    setState(() => _isLoading = true);
    
    try {
      print('🚀 Drive kaydetme başlatılıyor...');
      
      // Görüntü yakala
      final boundary = _globalKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('Görüntü yakalanamadı');
      }

      final pngBytes = byteData.buffer.asUint8List();

      // Kat/Ayna/Km bilgilerini al (UI'dan)
      String fileName = 'jeoloji_${DateTime.now().millisecondsSinceEpoch}.png';

      // Drive klasör yolu
      final parts = [
        'FotoJeolog',
        _lastKat ?? 'Genel',
        _lastAyna ?? 'Ayna1', 
        _lastKm ?? 'Km1'
      ];

      print('📁 Klasör yolu: ${parts.join('/')}');
      print('📄 Dosya adı: $fileName');

      // Geçici dosyayı sistem temp klasöründe oluştur
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(pngBytes);
      
      print('💾 Geçici dosya oluşturuldu: ${tempFile.path}');
      
      // Drive'a yükle ve sonucu kontrol et
      final uploadResult = await driveSvc.uploadFile(tempFile.path, parts);
      print('📤 Upload sonucu: $uploadResult');
      
      if (uploadResult == null) {
        throw Exception('Drive yükleme başarısız - oturum kontrolü yapın');
      }

      // Notlar varsa onları da yükle
      if (_notes.isNotEmpty) {
        print('📝 ${_notes.length} not yükleniyor...');
        final notesData = _notes.map((n) => n.toJson()).toList();
        final notesJson = jsonEncode(notesData);
        final notesFileName = fileName.replaceAll('.png', '_notes.json');
        final notesFile = File('${tempDir.path}/$notesFileName');
        await notesFile.writeAsString(notesJson);
        
        final notesUploadResult = await driveSvc.uploadFile(notesFile.path, parts);
        print('📝 Notlar upload sonucu: $notesUploadResult');
        
        if (notesUploadResult == null) {
          print('⚠️ Notlar yüklenemedi ama fotoğraf yüklendi');
        }
        
        // Geçici not dosyasını temizle
        if (await notesFile.exists()) {
          await notesFile.delete();
        }
      }
      
      // Geçici PNG dosyasını temizle
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      print('✅ Drive kaydetme tamamlandı');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Drive\'a başarıyla kaydedildi${_notes.isNotEmpty ? ' (${_notes.length} not ile)' : ''}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('❌ Drive kaydetme hatası: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Drive kaydetme hatası: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
    
    setState(() => _isLoading = false);
  }

  Future<void> _saveImageBoth() async {
    setState(() => _isLoading = true);
    
    // Drive oturum kontrolü daha net yapılacak
    final driveSvc = GoogleDriveService.instance;
    bool driveAvailable = driveSvc.isSignedIn;
    
    try {
      // Önce yerel kaydet
      await _saveImage();
      
      // Drive'a da kaydetmeye çalış
      if (driveAvailable) {
        await _saveImageToDrive();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📱 Telefona kaydedildi. Drive için giriş gerekli!'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Kaydetme hatası: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
    
    setState(() => _isLoading = false);
  }


  Future<void> _saveImageToFirebase() async {
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaydedilecek görüntü bulunamadı')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      // Görüntü yakala
      final boundary = _globalKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Görüntü yakalanamadı');
      final pngBytes = byteData.buffer.asUint8List();
      
      // 1) Kullanıcıdan Kat / Ayna / Km bilgilerini iste (telefona kaydetme gibi)
      await _askAndResolveTargetDir();
      
      // Notları hazırla
      String notesString = '';
      if (_notes.isNotEmpty) {
        final notesData = _notes.map((n) => n.toJson()).toList();
        notesString = jsonEncode(notesData);
      }
      
      // Geçici dosya oluştur
      final tempDir = Directory.systemTemp;
      final fileName = 'jeoloji_${DateTime.now().millisecondsSinceEpoch}.png';
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(pngBytes);
      
      // Firebase upload
      final firebaseService = FirebaseStorageService.instance;
      await firebaseService.uploadPhoto(
        imagePath: tempFile.path,
        notes: notesString,
        projectName: 'FotoJeolog Saha',
        kat: _lastKat,
        ayna: _lastAyna,
        km: _lastKm,
      );
      
      // Geçici dosyayı temizle
      if (await tempFile.exists()) await tempFile.delete();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🔥 Firebase\'e kaydedildi: ${_lastKat}/${_lastAyna}/${_lastKm}'), 
          backgroundColor: Colors.orange
        ),
      );
    } catch (e) {
      print('❌ Firebase kaydetme hatası: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Firebase kaydetme hatası: $e'), backgroundColor: Colors.red),
      );
    }
    setState(() => _isLoading = false);
  }

  Future<_SaveTarget> _askAndResolveTargetDir() async {
    // Varsayılanları saveDirectoryPath'ten türet
    String? defaultKat;
    String? defaultAyna;
    String? defaultKm;
    if (widget.saveDirectoryPath != null &&
        widget.saveDirectoryPath!.isNotEmpty) {
      final segments = widget.saveDirectoryPath!
          .replaceAll('\\', '/')
          .split('/')
          .where((e) => e.isNotEmpty)
          .toList();
      if (segments.length >= 3) {
        defaultKm = segments.last;
        defaultAyna = segments[segments.length - 2];
        defaultKat = segments[segments.length - 3];
      }
    }

    final result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final katCtrl = TextEditingController(text: defaultKat ?? 'Kat1');
        final aynaCtrl = TextEditingController(text: defaultAyna ?? 'Ayna1');
        final kmCtrl = TextEditingController(text: defaultKm ?? 'Km1');
        String? error;
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E2428),
              title: const Text(
                'Kayıt Sınıflandırması',
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: katCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Kat',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  TextField(
                    controller: aynaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ayna',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  TextField(
                    controller: kmCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Kilometre',
                      labelStyle: TextStyle(color: Colors.white70),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final kat = katCtrl.text.trim();
                    final ayna = aynaCtrl.text.trim();
                    final km = kmCtrl.text.trim();
                    if (kat.isEmpty || ayna.isEmpty || km.isEmpty) {
                      setLocal(() => error = 'Lütfen tüm alanları doldurun');
                      return;
                    }
                    Navigator.pop(context, {
                      'kat': kat,
                      'ayna': ayna,
                      'km': km,
                    });
                  },
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );

    // İptal edilirse varsayılana kaydet
    if (result == null) {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}/FotoJeolog');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return _SaveTarget(dir);
    }
    final kat = result['kat']!;
    final ayna = result['ayna']!;
    final km = result['km']!;

    // Son seçimleri sakla
    _lastKat = kat;
    _lastAyna = ayna;
    _lastKm = km;

    Directory target;
    if (PlatformUtils.isAndroid) {
      // Galeri/DCIM hiyerarşisine kaydet
      final root = Directory('/storage/emulated/0/DCIM/FotoJeolog');
      target = Directory('${root.path}/$kat/$ayna/$km');
    } else {
      // Diğer platformlarda uygulama belgeleri altına
      final base = await getApplicationDocumentsDirectory();
      target = Directory('${base.path}/FotoJeolog/$kat/$ayna/$km');
    }
    if (!target.existsSync()) {
      target.createSync(recursive: true);
    }
    return _SaveTarget(target, kat: kat, ayna: ayna, km: km);
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _redoStack.clear();
    });
  }

  void _toggleEraser() {
    setState(() => _isEraser = !_isEraser);
  }

  void _openBrushSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: const Color(0xFF1E2428),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return _BrushSettingsWidget(
          initialStrokeWidth: strokeWidth,
          initialStrokeOpacity: strokeOpacity,
          onStrokeWidthChanged: (value) => setState(() => strokeWidth = value),
          onStrokeOpacityChanged: (value) =>
              setState(() => strokeOpacity = value),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Sade arka plan
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.orange),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.landscape,
              color: Colors.orange,
              size: 22,
            ), // Jeoloji ikonuna değişti
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'Jeoloji Fotoğraflama',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF2D1B0E), // Üst bar rengi korunuyor
        elevation: 3,
        shadowColor: Colors.orange.withOpacity(0.3),
        actions: [
          if (_selectedImage != null) ...[
            // Silinen notları geri getir butonu (en solda)
            IconButton(
              icon: Icon(
                Icons.restore_from_trash, 
                color: _deletedNotes.isNotEmpty ? Colors.orange : Colors.grey.shade600,
              ),
              tooltip: 'Silinen notları geri getir (${_deletedNotes.length})',
              onPressed: _deletedNotes.isNotEmpty ? _undoDeletedNote : null,
            ),
            // Not ekleme butonu (ortada)
            IconButton(
              icon: const Icon(Icons.sticky_note_2, color: Colors.orange),
              tooltip: 'Not ekle',
              onPressed: _addNoteAtCenter,
            ),
            // Kaydet menü butonu (en sağda)
            PopupMenuButton<String>(
              icon: const Icon(Icons.save, color: Colors.orange),
              enabled: !_isLoading,
              onSelected: (value) {
                // Drive oturum kontrolü burada da yapılacak
                if (value == 'drive' || value == 'both') {
                  if (!GoogleDriveService.instance.isSignedIn) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('⚠️ Drive işlemi için önce giriş yapmalısınız!'),
                        backgroundColor: Colors.orange,
                        duration: Duration(seconds: 3),
                      ),
                    );
                    return;
                  }
                }
                
                if (value == 'local') {
                  _saveImage();
                } else if (value == 'drive') {
                  _saveImageToDrive();
                } else if (value == 'firebase') {
                  _saveImageToFirebase();
                } else if (value == 'both') {
                  _saveImageBoth();
                }
              },
              itemBuilder: (context) {
                final isSignedIn = GoogleDriveService.instance.isSignedIn;
                return [
                  const PopupMenuItem(
                    value: 'local',
                    child: Row(
                      children: [
                        Icon(Icons.phone_android, size: 20),
                        SizedBox(width: 8),
                        Text('Telefona kaydet'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'firebase',
                    child: Row(
                      children: [
                        Icon(Icons.cloud_done, size: 20, color: Colors.orange),
                        SizedBox(width: 8),
                        Text('Firebase\'e kaydet'),
                      ],
                    ),
                  ),
                  // Drive seçenekleri sadece oturum açıkken göster
                  if (isSignedIn) ...[
                    const PopupMenuItem(
                      value: 'drive',
                      child: Row(
                        children: [
                          Icon(Icons.cloud_upload, size: 20, color: Colors.green),
                          SizedBox(width: 8),
                          Text('Drive\'a kaydet'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'both',
                      child: Row(
                        children: [
                          Icon(Icons.save, size: 20, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('Her ikisine kaydet'),
                        ],
                      ),
                    ),
                  ] else ...[
                    // Oturum kapalıyken uyarı seçeneği göster
                    PopupMenuItem(
                      enabled: false,
                      child: Row(
                        children: [
                          Icon(Icons.cloud_off, size: 20, color: Colors.grey),
                          SizedBox(width: 8),
                          Text('Drive - Giriş Gerekli', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ];
              },
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          // İçerik: sade düzen; tünel efekti kaldırıldı
          _selectedImage == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (PlatformUtils.supportsCamera)
                          SizedBox(
                            width: 260,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.camera_alt, color: Colors.white),
                              label: const Text('Sahadan Fotoğraf Çek'),
                              onPressed: _isLoading ? null : () => _pickImage(ImageSource.camera),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                            ),
                          ),
                        if (PlatformUtils.supportsCamera) const SizedBox(height: 12),
                        SizedBox(
                          width: 260,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.photo_library, color: Colors.black),
                            label: const Text('Galeriden Seç', style: TextStyle(color: Colors.black)),
                            onPressed: _isLoading ? null : () => _pickImage(ImageSource.gallery),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: Stack(
                        children: <Widget>[
                          // Çizim + Görsel (PNG çıktısı için)
                          RepaintBoundary(
                            key: _globalKey,
                            child: InteractiveViewer(
                              key: _viewerKey,
                              transformationController: _transformController,
                              panEnabled: false,
                              minScale: 1.0,
                              maxScale: 5.0,
                              child: _imageSize == null
                                  ? Center(child: Image.file(_selectedImage!))
                                  : SizedBox(
                                      width: _imageSize!.width,
                                      height: _imageSize!.height,
                                      child: Stack(
                                        children: <Widget>[
                                          Positioned.fill(
                                            child: Image.file(
                                              _selectedImage!,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                          GestureDetector(
                                            onPanStart: (details) {
                                              final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
                                              if (box == null) return;
                                              final local = box.globalToLocal(details.globalPosition);
                                              final scenePoint = _transformController.toScene(local);
                                              setState(() {
                                                _strokes.add(
                                                  Stroke(
                                                    points: [scenePoint],
                                                    color: selectedColor.withOpacity(strokeOpacity),
                                                    width: strokeWidth,
                                                    isEraser: _isEraser,
                                                  ),
                                                );
                                                _redoStack.clear();
                                              });
                                            },
                                            onPanUpdate: (details) {
                                              final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
                                              if (box == null || _strokes.isEmpty) return;
                                              final local = box.globalToLocal(details.globalPosition);
                                              final scenePoint = _transformController.toScene(local);
                                              setState(() {
                                                _strokes.last.points.add(scenePoint);
                                              });
                                            },
                                            child: CustomPaint(
                                              size: Size.infinite,
                                              painter: _DrawingPainter(
                                                strokes: _strokes,
                                                showGrid: _showGrid,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                          ),

                          // Notlar overlay (PNG'ye dahil edilmez). Container kaldırıldı; boş alanlar alttaki çizime geçer.
                          Positioned.fill(
                            child: _imageSize == null
                                ? const SizedBox.shrink()
                                : Stack(
                                    key: _notesOverlayKey,
                                    children: <Widget>[
                                      for (final note in _notes)
                                        _buildPositionedNote(note),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                    // Alt araç çubuğu (not ekleme butonu kaldırıldı)
                    SafeArea(
                      top: false,
                      bottom: true,
                      minimum: const EdgeInsets.only(bottom: 24),
                      child: Container(
                        padding: const EdgeInsets.all(6.0),
                        margin: const EdgeInsets.only(bottom: 12),
                        color: const Color(0xFF1A1A1A),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildToolButton(
                              icon: Icons.undo,
                              color: Colors.orange,
                              onPressed: _strokes.isNotEmpty ? _undo : null,
                            ),
                            _buildToolButton(
                              icon: Icons.redo,
                              color: Colors.orange,
                              onPressed: _redoStack.isNotEmpty ? _redo : null,
                            ),
                            _buildToolButton(
                              icon: Icons.delete_outline,
                              color: Colors.red,
                              onPressed: _strokes.isNotEmpty ? _clear : null,
                            ),
                            _buildToolButton(
                              icon: Icons.palette,
                              color: selectedColor,
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    backgroundColor: const Color(0xFF2D1B0E),
                                    title: const Row(
                                      children: [
                                        Icon(Icons.palette, color: Colors.orange),
                                        SizedBox(width: 8),
                                        Text('Renk Seç', style: TextStyle(color: Colors.white)),
                                      ],
                                    ),
                                    content: SingleChildScrollView(
                                      child: BlockPicker(
                                        pickerColor: selectedColor,
                                        onColorChanged: (color) => setState(() => selectedColor = color),
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Kapat', style: TextStyle(color: Colors.orange)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            _buildToolButton(
                              icon: _isEraser ? Icons.cleaning_services : Icons.cleaning_services_outlined,
                              color: _isEraser ? Colors.red : Colors.grey,
                              onPressed: _toggleEraser,
                              isSelected: _isEraser,
                            ),
                            _buildToolButton(
                              icon: Icons.brush,
                              color: Colors.amber,
                              onPressed: _openBrushSheet,
                            ),
                          ],
                        ),
                      ),
                    ),
                    ),
                  ],
                ),
          // Loading overlay
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    bool isSelected = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: isSelected ? color.withOpacity(0.2) : color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected ? color.withOpacity(0.5) : color.withOpacity(0.3),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: 20),
        onPressed: onPressed,
        iconSize: 20,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      ),
    );
  }

  Widget _buildPositionedNote(StickyNote note) {
    // Sahne koordinatını viewport koordinatına dönüştür
    final m = _transformController.value;
    final viewport = MatrixUtils.transformPoint(m, Offset(note.x, note.y));

    return Positioned(
      left: viewport.dx,
      top: viewport.dy,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Ana note widget'i
          GestureDetector(
            onPanStart: (details) {
              if (_isResizingAnyNote) return; // Resize sırasında taşıma devre dışı
              final box = _notesOverlayKey.currentContext?.findRenderObject() as RenderBox?;
              if (box == null) return;
              final local = box.globalToLocal(details.globalPosition);
              final scenePoint = _transformController.toScene(local);
              _draggingNoteId = note.id;
              _dragDelta = scenePoint - Offset(note.x, note.y);
            },
            onPanUpdate: (details) {
              if (_draggingNoteId != note.id || _isResizingAnyNote) return;
              final box = _notesOverlayKey.currentContext?.findRenderObject() as RenderBox?;
              if (box == null) return;
              final local = box.globalToLocal(details.globalPosition);
              final scenePoint = _transformController.toScene(local);
              setState(() {
                note.x = scenePoint.dx - _dragDelta.dx;
                note.y = scenePoint.dy - _dragDelta.dy;
                note.updatedAt = DateTime.now();
              });
            },
            onPanEnd: (_) {
              if (_draggingNoteId == note.id) {
                _draggingNoteId = null;
                _dragDelta = Offset.zero;
              }
              _saveNotesForCurrentImage();
            },
            child: _StickyNoteWidget(
              note: note,
              onChanged: (updated) {
                setState(() {
                  note.text = updated.text;
                  note.fontSize = updated.fontSize;
                  note.collapsed = updated.collapsed;
                  note.color = updated.color;
                  note.textColor = updated.textColor;
                  note.width = updated.width;
                  note.height = updated.height;
                  note.x = updated.x;
                  note.y = updated.y;
                  note.updatedAt = DateTime.now();
                });
                _saveNotesForCurrentImage();
              },
              onDelete: () {
                // Silinen notu geri getirme için saklayalım
                final noteToDelete = _notes.firstWhere((n) => n.id == note.id);
                
                setState(() {
                  _deletedNotes.add(noteToDelete);
                  // Son 10 silinen notu tutup eski olanları temizleyelim
                  if (_deletedNotes.length > 10) {
                    _deletedNotes.removeAt(0);
                  }
                  // Notu listeden kaldır
                  _notes.removeWhere((n) => n.id == note.id);
                });
                _saveNotesForCurrentImage();
                
                // Basit bilgi mesajı
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Not silindi'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              onAutoSave: _saveNotesForCurrentImage, // Otomatik kaydetme için
              onResizeStart: () { setState(() { _isResizingAnyNote = true; }); },
              onResizeEnd: () { setState(() { _isResizingAnyNote = false; }); _saveNotesForCurrentImage(); },
            ),
          ),
          // Resize handle'ları Stack içinde ama widget dışında
          if (!note.collapsed) ...[
            _buildResizeHandle(Alignment.topLeft, note),
            _buildResizeHandle(Alignment.topRight, note),
            _buildResizeHandle(Alignment.bottomLeft, note),
            _buildResizeHandle(Alignment.bottomRight, note),
          ],
        ],
      ),
    );
  }

  Widget _buildResizeHandle(Alignment alignment, StickyNote note) {
    return Positioned(
      left: alignment.x == -1 ? -5 : null,
      right: alignment.x == 1 ? -5 : null,
      top: alignment.y == -1 ? -5 : null,
      bottom: alignment.y == 1 ? -5 : null,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (details) {
          setState(() { _isResizingAnyNote = true; });
        },
        onPanUpdate: (details) {
          final dx = details.delta.dx;
          final dy = details.delta.dy;

          double newWidth = note.width;
          double newHeight = note.height;
          double newX = note.x;
          double newY = note.y;

          if (alignment.x == 1) {
            newWidth = note.width + dx;
          } else if (alignment.x == -1) {
            newWidth = note.width - dx;
            newX = note.x + dx;
          }

          if (alignment.y == 1) {
            newHeight = note.height + dy;
          } else if (alignment.y == -1) {
            newHeight = note.height - dy;
            newY = note.y + dy;
          }

          newWidth = newWidth.clamp(180.0, 600.0);
          newHeight = newHeight.clamp(120.0, 600.0);

          setState(() {
            note.width = newWidth;
            note.height = newHeight;
            note.x = newX;
            note.y = newY;
            note.updatedAt = DateTime.now();
          });
        },
        onPanEnd: (_) {
          setState(() { _isResizingAnyNote = false; });
          _saveNotesForCurrentImage();
        },
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: Colors.brown.shade300,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.brown.shade600, width: 1),
          ),
        ),
      ),
    );
  }
}

class _DrawingPainter extends CustomPainter {
  final List<Stroke> strokes;
  final bool showGrid;

  _DrawingPainter({required this.strokes, required this.showGrid});

  @override
  void paint(Canvas canvas, Size size) {
    // Yeni bir layer üzerinde çizerek silgi (clear) blendMode'unu destekleyelim
    canvas.saveLayer(Offset.zero & size, Paint());

    for (final stroke in strokes) {
      if (stroke.points.length < 2) continue;
      final paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke.width
        ..color = stroke.color;
      if (stroke.isEraser) {
        paint.blendMode = BlendMode.clear;
        // renk önemsiz; clear modda şeffaf çizilecek
      }

      final path = Path()
        ..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (int i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    // Izgara
    if (showGrid) {
      final gridPaint = Paint()
        ..color = const Color(0x66FFFFFF)
        ..strokeWidth = 0.5;
      const gridSize = 32.0;
      for (double x = 0; x < size.width; x += gridSize) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
      for (double y = 0; y < size.height; y += gridSize) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) => true;
}

class _BrushSettingsWidget extends StatefulWidget {
  final double initialStrokeWidth;
  final double initialStrokeOpacity;
  final Function(double) onStrokeWidthChanged;
  final Function(double) onStrokeOpacityChanged;

  const _BrushSettingsWidget({
    required this.initialStrokeWidth,
    required this.initialStrokeOpacity,
    required this.onStrokeWidthChanged,
    required this.onStrokeOpacityChanged,
  });

  @override
  State<_BrushSettingsWidget> createState() => _BrushSettingsWidgetState();
}

class _BrushSettingsWidgetState extends State<_BrushSettingsWidget> {
  late double _strokeWidth;
  late double _strokeOpacity;

  @override
  void initState() {
    super.initState();
    _strokeWidth = widget.initialStrokeWidth;
    _strokeOpacity = widget.initialStrokeOpacity;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF1E2428),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık
          Row(
            children: [
              const Icon(Icons.brush, color: Colors.amber, size: 24),
              const SizedBox(width: 12),
              Text(
                'Fırça Ayarları',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Kalınlık
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Kalınlık',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _strokeWidth.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Kalınlık Slider
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 14,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 24,
                  ),
                  activeTrackColor: Colors.amber,
                  inactiveTrackColor: Colors.white.withOpacity(0.2),
                  thumbColor: Colors.amber,
                  overlayColor: Colors.amber.withOpacity(0.2),
                ),
                child: Slider(
                  value: _strokeWidth,
                  min: 1.0,
                  max: 24.0,
                  divisions: 23,
                  onChanged: (value) {
                    setState(() => _strokeWidth = value);
                    widget.onStrokeWidthChanged(value);
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Opaklık
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Opaklık',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${(_strokeOpacity * 100).round()}%',
                      style: const TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Opaklık Slider
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 14,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 24,
                  ),
                  activeTrackColor: Colors.amber,
                  inactiveTrackColor: Colors.white.withOpacity(0.2),
                  thumbColor: Colors.amber,
                  overlayColor: Colors.amber.withOpacity(0.2),
                ),
                child: Slider(
                  value: _strokeOpacity,
                  min: 0.1,
                  max: 1.0,
                  divisions: 9,
                  onChanged: (value) {
                    setState(() => _strokeOpacity = value);
                    widget.onStrokeOpacityChanged(value);
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _StickyNoteWidget extends StatefulWidget {
  final StickyNote note;
  final ValueChanged<StickyNote> onChanged;
  final VoidCallback onDelete;
  final VoidCallback? onAutoSave;
  // Resize sırasında dış dünyaya sinyal (taşıma ile çakışmayı engellemek için)
  final VoidCallback? onResizeStart;
  final VoidCallback? onResizeEnd;

  const _StickyNoteWidget({
    required this.note,
    required this.onChanged,
    required this.onDelete,
    this.onAutoSave,
    this.onResizeStart,
    this.onResizeEnd,
  });

  @override
  State<_StickyNoteWidget> createState() => _StickyNoteWidgetState();
}

class _StickyNoteWidgetState extends State<_StickyNoteWidget> {
  late final TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.note.text);
    _ctrl.addListener(_onTextChanged);
    // Her zaman otomatik odaklan ve klavyeyi aç
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.requestFocus();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _StickyNoteWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.text != widget.note.text && _ctrl.text != widget.note.text) {
      final sel = _ctrl.selection;
      _ctrl.text = widget.note.text;
      final newOffset = sel.baseOffset.clamp(0, _ctrl.text.length);
      _ctrl.selection = TextSelection.collapsed(offset: newOffset);
    }
  }

  void _onTextChanged() {
    final val = _ctrl.text;
    if (val != widget.note.text) {
      // Notedaki değişikliği güncelle
      widget.onChanged(StickyNote(
        id: widget.note.id,
        x: widget.note.x,
        y: widget.note.y,
        text: val,
        fontSize: widget.note.fontSize,
        collapsed: widget.note.collapsed,
        author: widget.note.author,
        color: widget.note.color,
        textColor: widget.note.textColor,
        createdAt: widget.note.createdAt,
        updatedAt: DateTime.now(),
        width: widget.note.width,
        height: widget.note.height,
      ));
      
      // Biraz gecikme ile otomatik kaydet (kullanıcı yazmayı bitirsin diye)
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 800), () {
        // Ana widget'ta kaydetme işlemini tetikle
        if (widget.onAutoSave != null) {
          widget.onAutoSave!();
        }
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final baseColor = Color(note.color);
    
    if (note.collapsed) {
      return GestureDetector(
        onDoubleTap: () => widget.onChanged(StickyNote(
          id: note.id,
          x: note.x,
          y: note.y,
          text: note.text,
          fontSize: note.fontSize,
          collapsed: false,
          author: note.author,
          color: note.color,
          textColor: note.textColor,
          createdAt: note.createdAt,
          updatedAt: DateTime.now(),
          width: note.width,
          height: note.height,
        )),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: baseColor,
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
            border: Border.all(color: Colors.brown.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sticky_note_2, size: 12, color: Colors.brown),
              const SizedBox(width: 4),
              Container(
                constraints: const BoxConstraints(maxWidth: 60),
                child: Text(
                  note.text.isEmpty ? 'Not' : (note.text.split('\n').first),
                  style: const TextStyle(color: Colors.black87, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        _focus.requestFocus();
      },
      behavior: HitTestBehavior.translucent,
      child: Container(
        width: note.width,
        height: note.height,
        constraints: const BoxConstraints(minHeight: 120, minWidth: 180),
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
          border: Border.all(color: Colors.brown.shade300),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header - Üst kısımda kontroller
                Container(
                  padding: const EdgeInsets.only(left: 8, right: 12, top: 4, bottom: 4),
                  decoration: BoxDecoration(
                    color: Colors.brown.shade100,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // Simge durumuna küçültme butonu
                        GestureDetector(
                          onTap: () => widget.onChanged(StickyNote(
                            id: note.id,
                            x: note.x,
                            y: note.y,
                            text: note.text,
                            fontSize: note.fontSize,
                            collapsed: true,
                            author: note.author,
                            color: note.color,
                            textColor: note.textColor,
                            createdAt: note.createdAt,
                            updatedAt: DateTime.now(),
                            width: note.width,
                            height: note.height,
                          )),
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: Colors.brown.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(Icons.minimize, size: 12, color: Colors.brown),
                          ),
                        ),
                        const SizedBox(width: 3),
                        // Font boyutu düşür
                        GestureDetector(
                          onTap: () => widget.onChanged(StickyNote(
                            id: note.id,
                            x: note.x,
                            y: note.y,
                            text: note.text,
                            fontSize: (note.fontSize - 2).clamp(8, 64).toDouble(),
                            collapsed: note.collapsed,
                            author: note.author,
                            color: note.color,
                            textColor: note.textColor,
                            createdAt: note.createdAt,
                            updatedAt: DateTime.now(),
                            width: note.width,
                            height: note.height,
                          )),
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: Colors.brown.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(Icons.remove, size: 12, color: Colors.brown),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text('${note.fontSize.round()}', style: const TextStyle(color: Colors.brown, fontSize: 10, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 3),
                        // Font boyutu artır
                        GestureDetector(
                          onTap: () => widget.onChanged(StickyNote(
                            id: note.id,
                            x: note.x,
                            y: note.y,
                            text: note.text,
                            fontSize: (note.fontSize + 2).clamp(8, 64).toDouble(),
                            collapsed: note.collapsed,
                            author: note.author,
                            color: note.color,
                            textColor: note.textColor,
                            createdAt: note.createdAt,
                            updatedAt: DateTime.now(),
                            width: note.width,
                            height: note.height,
                          )),
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: Colors.brown.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(Icons.add, size: 12, color: Colors.brown),
                          ),
                        ),
                        const SizedBox(width: 3),
                        // Renk seçici (arka plan)
                        GestureDetector(
                          onTap: () => _showColorPicker(context, note),
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: baseColor,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.brown.shade300),
                            ),
                            child: const Icon(Icons.palette, size: 12, color: Colors.brown),
                          ),
                        ),
                        const SizedBox(width: 3),
                        // Yazı rengi seçici
                        GestureDetector(
                          onTap: () => _showTextColorPicker(context, note),
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Color(note.textColor),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.brown.shade300),
                            ),
                            child: Icon(Icons.text_format, size: 12, color: Color(note.textColor).computeLuminance() > 0.5 ? Colors.black : Colors.white),
                          ),
                        ),
                        const SizedBox(width: 3),
                        // Manuel kaydet butonu
                        Tooltip(
                          message: 'Notu kaydet',
                          child: GestureDetector(
                            onTap: () {
                              if (widget.onAutoSave != null) {
                                widget.onAutoSave!();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Not kaydedildi!'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              }
                            },
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: Colors.green.shade300,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.green.shade600),
                              ),
                              child: const Icon(Icons.save, size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Text alanı
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: GestureDetector(
                      onTap: () async {
                        _focus.requestFocus();
                        await SystemChannels.textInput.invokeMethod('TextInput.show');
                        Future.delayed(const Duration(milliseconds: 100), () async {
                          if (mounted) {
                            _focus.requestFocus();
                            await SystemChannels.textInput.invokeMethod('TextInput.show');
                          }
                        });
                      },
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focus,
                        maxLines: null,
                        autofocus: true,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Not metni...',
                          hintStyle: TextStyle(color: Colors.black54),
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: TextStyle(fontSize: note.fontSize, color: Color(note.textColor)),
                        onTap: () async {
                          if (!_focus.hasFocus) {
                            _focus.requestFocus();
                          }
                          await SystemChannels.textInput.invokeMethod('TextInput.show');
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Sil butonu sağ üst köşede
            Positioned(
              right: 4,
              top: 4,
              child: GestureDetector(
                onTap: widget.onDelete,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      );
  }

  void _showColorPicker(BuildContext context, StickyNote note) {
    // Önceden tanımlı arka plan renkler
    final List<Color> colors = [
      const Color(0xFFFFF59D), // Sarı (varsayılan)
      const Color(0xFFFFE082), // Açık sarı
      const Color(0xFFFFCDD2), // Açık kırmızı
      const Color(0xFFC8E6C9), // Açık yeşil
      const Color(0xFFBBDEFB), // Açık mavi
      const Color(0xFFE1BEE7), // Açık mor
      const Color(0xFFFFCC80), // Açık turuncu
      const Color(0xFFF8BBD9), // Açık pembe
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Arka Plan Rengi Seç'),
        content: SizedBox(
          width: 300,
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: colors.length,
            itemBuilder: (context, index) {
              final color = colors[index];
              return GestureDetector(
                onTap: () {
                  widget.onChanged(StickyNote(
                    id: note.id,
                    x: note.x,
                    y: note.y,
                    text: note.text,
                    fontSize: note.fontSize,
                    collapsed: note.collapsed,
                    author: note.author,
                    color: color.value,
                    textColor: note.textColor,
                    createdAt: note.createdAt,
                    updatedAt: DateTime.now(),
                    width: note.width,
                    height: note.height,
                  ));
                  Navigator.of(context).pop();
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: color.value == note.color ? Colors.brown : Colors.grey.shade300,
                      width: color.value == note.color ? 3 : 1,
                    ),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal'),
          ),
        ],
      ),
    );
  }

  void _showTextColorPicker(BuildContext context, StickyNote note) {
    // Önceden tanımlı yazı renkleri
    final List<Color> textColors = [
      const Color(0xFF000000), // Siyah (varsayılan)
      const Color(0xFF424242), // Koyu gri
      const Color(0xFF1976D2), // Mavi
      const Color(0xFF388E3C), // Yeşil
      const Color(0xFFD32F2F), // Kırmızı
      const Color(0xFF7B1FA2), // Mor
      const Color(0xFFF57C00), // Turuncu
      const Color(0xFF5D4037), // Kahverengi
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yazı Rengi Seç'),
        content: SizedBox(
          width: 300,
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: textColors.length,
            itemBuilder: (context, index) {
              final color = textColors[index];
              return GestureDetector(
                onTap: () {
                  widget.onChanged(StickyNote(
                    id: note.id,
                    x: note.x,
                    y: note.y,
                    text: note.text,
                    fontSize: note.fontSize,
                    collapsed: note.collapsed,
                    author: note.author,
                    color: note.color,
                    textColor: color.value,
                    createdAt: note.createdAt,
                    updatedAt: DateTime.now(),
                    width: note.width,
                    height: note.height,
                  ));
                  Navigator.of(context).pop();
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: color.value == note.textColor ? Colors.orange : Colors.grey.shade300,
                      width: color.value == note.textColor ? 3 : 1,
                    ),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                  ),
                  child: Center(
                    child: Text(
                      'Aa',
                      style: TextStyle(
                        color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal'),
          ),
        ],
      ),
    );
  }
}
// Dosya sonu
