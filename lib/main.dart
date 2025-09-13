import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fotojeolog/photo_draw_page.dart' as photo;
import 'package:fotojeolog/archive_page.dart' as archive;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Jeoloji Fotoğraflama',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFC107),
          secondary: Color(0xFF8D6E63),
          surface: Color(0xFF1B1F24),
          onSurface: Colors.white,
          tertiary: Color(0xFF455A64),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Future<void> _takePicture() async {
    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => photo.PhotoDrawPage.fromImage(File(pickedFile.path)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0F1215),
              Color(0xFF1B1F24),
              Color(0xFF2A2F35),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 120,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _TunnelPatternPainter(),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: const [
                            Icon(Icons.engineering, color: Color(0xFFFFC107), size: 36),
                            SizedBox(width: 12),
                            Text(
                              'Jeoloji\nFotoğraflama',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0x33FFC107)),
                          ),
                          child: const Icon(Icons.engineering, color: Color(0xFFFFC107), size: 40),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.camera_enhance_rounded),
                          label: const Text('SAHA FOTOĞRAFI ÇEK'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFC107),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _takePicture,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.collections_rounded),
                          label: const Text('SAHA ARŞİVİNDEN SEÇ'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF455A64),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const archive.ArchivePage(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x33FFC107)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.engineering, size: 16, color: Color(0xFFFFC107)),
                      SizedBox(width: 8),
                      Text(
                        'Geliştirici: Adil Koray Şerifağaoğlu',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TunnelPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0x11000000);
    canvas.drawRect(Offset.zero & size, bg);

    final line = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 1;

    const gap = 14.0;
    for (double d = -size.height; d < size.width; d += gap) {
      canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height), line);
    }

    for (double y = 0; y < size.height; y += gap * 2) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }

    final ring = Paint()
      ..color = const Color(0x33FFC107)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final center = Offset(size.width * 0.15, size.height * 0.55);
    canvas.drawCircle(center, 22, ring);
    canvas.drawCircle(center, 36, ring);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}