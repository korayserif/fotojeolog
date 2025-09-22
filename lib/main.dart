import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fotojeolog/photo_draw_page.dart' as photo;
import 'package:fotojeolog/archive_page.dart' as archive;
import 'package:fotojeolog/settings_page.dart';
import 'package:fotojeolog/google_drive_archive_page.dart';
import 'services/google_drive_service.dart';
import 'permissions_helper.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  bool _isGoogleDriveSignedIn = false;
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    // Drive servisini arka planda hazırla
    _initializeGoogleDrive();
  }

  Future<void> _initializeGoogleDrive() async {
    await GoogleDriveService.instance.init();
    setState(() {
      _isGoogleDriveSignedIn = GoogleDriveService.instance.isSignedIn;
      _userEmail = GoogleDriveService.instance.userEmail;
    });
  }

  Future<void> _signInToGoogleDrive() async {
    try {
      setState(() {
        // Loading state
      });
      
      final success = await GoogleDriveService.instance.signIn();
      
      if (success) {
        setState(() {
          _isGoogleDriveSignedIn = true;
          _userEmail = GoogleDriveService.instance.userEmail;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Google Drive\'a giriş yapıldı: $_userEmail'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Google Drive girişi başarısız: ${GoogleDriveService.instance.lastError}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _signOutFromGoogleDrive() async {
    await GoogleDriveService.instance.signOut();
    setState(() {
      _isGoogleDriveSignedIn = false;
      _userEmail = null;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('👋 Google Drive\'dan çıkış yapıldı'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _takePicture() async {
    // Kamera iznini iste
    final hasCam = await PermissionsHelper.ensureCameraPermission();
    if (!hasCam) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kamera izni gerekiyor. Lütfen izin verin.')),
        );
      }
      await PermissionsHelper.openAppSettingsIfPermanentlyDenied();
      return;
    }

    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) =>
              photo.PhotoDrawPage.fromImage(File(pickedFile.path)),
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
            colors: [Color(0xFF0F1215), Color(0xFF1B1F24), Color(0xFF2A2F35)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Üst sağda Google Drive durumu ve ayarlar düğmeleri
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Sol tarafta Google Drive durumu
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _isGoogleDriveSignedIn ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _isGoogleDriveSignedIn ? Colors.green : Colors.red,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isGoogleDriveSignedIn ? Icons.cloud_done : Icons.cloud_off,
                              color: _isGoogleDriveSignedIn ? Colors.green : Colors.red,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _isGoogleDriveSignedIn 
                                  ? 'Google Drive: ${_userEmail ?? "Bağlı"}' 
                                  : 'Google Drive: Bağlı değil',
                                style: TextStyle(
                                  color: _isGoogleDriveSignedIn ? Colors.green : Colors.red,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Sağ tarafta düğmeler
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Google Drive giriş/çıkış düğmesi
                        ElevatedButton.icon(
                          onPressed: _isGoogleDriveSignedIn ? _signOutFromGoogleDrive : _signInToGoogleDrive,
                          icon: Icon(
                            _isGoogleDriveSignedIn ? Icons.logout : Icons.login,
                            size: 16,
                          ),
                          label: Text(
                            _isGoogleDriveSignedIn ? 'Çıkış' : 'Giriş',
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isGoogleDriveSignedIn ? Colors.red : Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: Size.zero,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ],
                ),
                SizedBox(
                  height: 120,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(painter: _TunnelPatternPainter()),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: const [
                            Icon(
                              Icons.engineering,
                              color: Color(0xFFFFC107),
                              size: 36,
                            ),
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
                const SizedBox(height: 24),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.cloud_upload),
                          label: const Text('ORTAK SAHA ARŞİVİ'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2196F3),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const GoogleDriveArchivePage(),
                              ),
                            );
                          },
                        ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0x33FFC107)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(
                        Icons.engineering,
                        size: 14,
                        color: Color(0xFFFFC107),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Geliştirici: Adil Koray Şerifağaoğlu',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
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
