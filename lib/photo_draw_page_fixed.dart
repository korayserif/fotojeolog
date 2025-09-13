import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'error_handler.dart';
import 'platform_utils.dart';

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

  const PhotoDrawPage({super.key, this.saveDirectoryPath})
    : initialImage = null;

  const PhotoDrawPage.fromImage(File image, {super.key, this.saveDirectoryPath})
    : initialImage = image;

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
  bool _showGrid = false;
  final TransformationController _transformController =
      TransformationController();
  final GlobalKey _globalKey = GlobalKey();
  // Çizim koordinatlarını düzgün almak için viewer key'i
  final GlobalKey _viewerKey = GlobalKey();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedImage = widget.initialImage;
    if (_selectedImage != null) {
      _loadImageSize(_selectedImage!);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    setState(() => _isLoading = true);
    await ErrorHandler.safeExecute(
      () async {
        final picker = ImagePicker();
        final XFile? pickedFile = await picker.pickImage(source: source);
        if (pickedFile != null) {
          setState(() {
            _selectedImage = File(pickedFile.path);
            _strokes.clear();
            _redoStack.clear();
            _imageSize = null;
          });
          await _loadImageSize(_selectedImage!);
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

  Future<void> _saveImage() async {
    if (_selectedImage == null) return;

    setState(() => _isLoading = true);
    await ErrorHandler.safeExecute(
      () async {
        final boundary =
            _globalKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) return;

        final pngBytes = byteData.buffer.asUint8List();

        // 1) Kullanıcıdan Kat / Ayna / Km bilgilerini iste
        final Directory targetDir = await _askAndResolveTargetDir();

        final now = DateTime.now();
        final fileName = 'annotated_${now.millisecondsSinceEpoch}.png';
        final file = File('${targetDir.path}/$fileName');

        await file.writeAsBytes(pngBytes);

        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Kaydedildi: ${file.path}')));
      },
      context,
      errorTitle: 'Kaydetme Hatası',
      errorMessage: 'Görüntü kaydedilirken bir hata oluştu.',
    );
    setState(() => _isLoading = false);
  }

  Future<Directory> _askAndResolveTargetDir() async {
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
      return await getApplicationDocumentsDirectory();
    }
    final kat = result['kat']!;
    final ayna = result['ayna']!;
    final km = result['km']!;

    final base = await getApplicationDocumentsDirectory();
    final target = Directory('${base.path}/$kat/$ayna/$km');
    if (!target.existsSync()) {
      target.createSync(recursive: true);
    }
    return target;
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
      backgroundColor: const Color(0xFF1A1A1A), // Koyu maden arka planı
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
        backgroundColor: const Color(0xFF2D1B0E), // Kahverengi maden rengi
        elevation: 3,
        shadowColor: Colors.orange.withOpacity(0.3),
        actions: [
          if (_selectedImage != null)
            IconButton(
              icon: const Icon(Icons.save, color: Colors.orange),
              onPressed: _isLoading ? null : _saveImage,
            ),
        ],
      ),
      body: Stack(
        children: [
          // Tünel efekti arkaplan
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.5,
                colors: [
                  Color(0xFF2D1B0E), // Kahverengi maden tonu - merkez
                  Color(0xFF1A1A1A), // Koyu gri
                  Color(0xFF0F0F0F), // Çok koyu - kenarlar
                ],
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.orange.withOpacity(0.6),
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.2),
                    blurRadius: 15,
                    spreadRadius: 3,
                  ),
                ],
              ),
              margin: const EdgeInsets.all(20),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.orange.withOpacity(0.4),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                margin: const EdgeInsets.all(15),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.orange.withOpacity(0.2),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  margin: const EdgeInsets.all(10),
                  child: _selectedImage == null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Jeoloji temalı başlık
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.orange.withOpacity(0.4),
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.orange.withOpacity(0.2),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Column(
                                    children: [
                                      Icon(
                                        Icons.landscape,
                                        color: Colors.orange,
                                        size: 52,
                                      ),
                                      SizedBox(height: 12),
                                      Text(
                                        'Jeoloji Fotoğraflama',
                                        style: TextStyle(
                                          color: Colors.orange,
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'Sahadan bir fotoğraf seçin ve jeolojik\nnotlarınızı ekleyin',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 32),
                                if (PlatformUtils.supportsCamera)
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                    ),
                                    child: ElevatedButton.icon(
                                      icon: const Icon(
                                        Icons.camera_alt,
                                        color: Colors.white,
                                      ),
                                      label: const Text(
                                        'Sahadan Fotoğraf Çek',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      onPressed: _isLoading
                                          ? null
                                          : () =>
                                                _pickImage(ImageSource.camera),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        elevation: 3,
                                      ),
                                    ),
                                  ),
                                if (PlatformUtils.supportsCamera)
                                  const SizedBox(height: 16),
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  child: ElevatedButton.icon(
                                    icon: const Icon(
                                      Icons.photo_library,
                                      color: Color(0xFF2D1B0E),
                                    ),
                                    label: const Text(
                                      'Galeriden Seç',
                                      style: TextStyle(
                                        color: Color(0xFF2D1B0E),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    onPressed: _isLoading
                                        ? null
                                        : () => _pickImage(ImageSource.gallery),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.amber,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      elevation: 3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            Expanded(
                              child: RepaintBoundary(
                                key: _globalKey,
                                child: InteractiveViewer(
                                  key: _viewerKey,
                                  transformationController:
                                      _transformController,
                                  panEnabled: false,
                                  minScale: 1.0,
                                  maxScale: 5.0,
                                  child: _imageSize == null
                                      ? Center(
                                          child: Image.file(_selectedImage!),
                                        )
                                      : SizedBox(
                                          width: _imageSize!.width,
                                          height: _imageSize!.height,
                                          child: Stack(
                                            children: [
                                              Positioned.fill(
                                                child: Image.file(
                                                  _selectedImage!,
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                              GestureDetector(
                                                onPanStart: (details) {
                                                  final box =
                                                      _viewerKey.currentContext
                                                              ?.findRenderObject()
                                                          as RenderBox?;
                                                  if (box == null) return;
                                                  final local = box
                                                      .globalToLocal(
                                                        details.globalPosition,
                                                      );
                                                  final scenePoint =
                                                      _transformController
                                                          .toScene(local);
                                                  setState(() {
                                                    _strokes.add(
                                                      Stroke(
                                                        points: [scenePoint],
                                                        color: selectedColor
                                                            .withOpacity(
                                                              strokeOpacity,
                                                            ),
                                                        width: strokeWidth,
                                                        isEraser: _isEraser,
                                                      ),
                                                    );
                                                    _redoStack.clear();
                                                  });
                                                },
                                                onPanUpdate: (details) {
                                                  final box =
                                                      _viewerKey.currentContext
                                                              ?.findRenderObject()
                                                          as RenderBox?;
                                                  if (box == null ||
                                                      _strokes.isEmpty)
                                                    return;
                                                  final local = box
                                                      .globalToLocal(
                                                        details.globalPosition,
                                                      );
                                                  final scenePoint =
                                                      _transformController
                                                          .toScene(local);
                                                  setState(() {
                                                    _strokes.last.points.add(
                                                      scenePoint,
                                                    );
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
                            ),
                            // Araç çubuğu
                            Container(
                              padding: const EdgeInsets.all(6.0),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0xFF2D1B0E), // Kahverengi maden tonu
                                    Color(0xFF1A1A1A), // Koyu gri
                                  ],
                                ),
                                border: Border(
                                  top: BorderSide(
                                    color: Colors.orange.withOpacity(0.6),
                                    width: 2,
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.orange.withOpacity(0.2),
                                    blurRadius: 4,
                                    offset: const Offset(0, -2),
                                  ),
                                ],
                              ),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildToolButton(
                                      icon: Icons.undo,
                                      color: Colors.orange,
                                      onPressed: _strokes.isNotEmpty
                                          ? _undo
                                          : null,
                                    ),
                                    _buildToolButton(
                                      icon: Icons.redo,
                                      color: Colors.orange,
                                      onPressed: _redoStack.isNotEmpty
                                          ? _redo
                                          : null,
                                    ),
                                    _buildToolButton(
                                      icon: Icons.delete_outline,
                                      color: Colors.red,
                                      onPressed: _strokes.isNotEmpty
                                          ? _clear
                                          : null,
                                    ),
                                    _buildToolButton(
                                      icon: Icons.palette,
                                      color: selectedColor,
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            backgroundColor: const Color(
                                              0xFF2D1B0E,
                                            ),
                                            title: const Row(
                                              children: [
                                                Icon(
                                                  Icons.palette,
                                                  color: Colors.orange,
                                                ),
                                                SizedBox(width: 8),
                                                Text(
                                                  'Renk Seç',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            content: SingleChildScrollView(
                                              child: BlockPicker(
                                                pickerColor: selectedColor,
                                                onColorChanged: (color) =>
                                                    setState(
                                                      () =>
                                                          selectedColor = color,
                                                    ),
                                              ),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                                child: const Text(
                                                  'Kapat',
                                                  style: TextStyle(
                                                    color: Colors.orange,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                    _buildToolButton(
                                      icon: _isEraser
                                          ? Icons.cleaning_services
                                          : Icons.cleaning_services_outlined,
                                      color: _isEraser
                                          ? Colors.red
                                          : Colors.grey,
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
                          ],
                        ),
                ),
              ),
            ),
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
        // renk önemsiz; clear modunda şeffaf çizilecek
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
