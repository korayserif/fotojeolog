import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/firebase_auth_service.dart';
import 'services/google_drive_service.dart';

class FirebaseLoginPage extends StatefulWidget {
  const FirebaseLoginPage({super.key});

  @override
  State<FirebaseLoginPage> createState() => _FirebaseLoginPageState();
}

class _FirebaseLoginPageState extends State<FirebaseLoginPage> {
  bool _isLoading = false;
  String? _error;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  
  // Email/Password girişi için
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1215),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Firebase Giriş',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          // Eğer kullanıcı giriş yapmışsa çıkış butonu göster
          if (FirebaseAuthService.instance.isSignedIn)
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.red),
              onPressed: _signOut,
              tooltip: 'Çıkış Yap',
            ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F1215), Color(0xFF1B1F24)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo ve başlık
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: const Icon(
                    Icons.cloud_upload,
                    size: 64,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(height: 32),
                
                const Text(
                  'Firebase Arşivi',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                
                const Text(
                  'Fotoğraflarınızı bulutta güvenle saklayın',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                
                // Hata mesajı
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                // Email/Password girişi
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isSignUp ? 'Hesap Oluştur' : 'Email ile Giriş',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Email alanı
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Email',
                          labelStyle: const TextStyle(color: Colors.white70),
                          prefixIcon: const Icon(Icons.email, color: Colors.white70),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.white30),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.orange),
                          ),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Şifre alanı
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Şifre',
                          labelStyle: const TextStyle(color: Colors.white70),
                          prefixIcon: const Icon(Icons.lock, color: Colors.white70),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.white30),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.orange),
                          ),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Email/Password giriş butonu
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _signInWithEmail,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            _isSignUp ? 'Hesap Oluştur' : 'Giriş Yap',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Kayıt/Giriş geçiş butonu
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isSignUp = !_isSignUp;
                            _error = null;
                          });
                        },
                        child: Text(
                          _isSignUp 
                            ? 'Zaten hesabınız var mı? Giriş yapın'
                            : 'Hesabınız yok mu? Kayıt olun',
                          style: const TextStyle(color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                // Ayırıcı
                Row(
                  children: [
                    const Expanded(child: Divider(color: Colors.white30)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'veya',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                    const Expanded(child: Divider(color: Colors.white30)),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Google Sign-In butonu
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _signInWithGoogle,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Image.asset(
                            'assets/google_logo.png',
                            height: 24,
                            width: 24,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(Icons.account_circle, color: Colors.white);
                            },
                          ),
                    label: Text(
                      _isLoading ? 'Giriş yapılıyor...' : 'Google ile Giriş Yap',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4285F4),
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: const Color(0xFF4285F4).withOpacity(0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Google Drive giriş butonu
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _signInWithGoogleDrive,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.cloud, color: Colors.white),
                    label: Text(
                      _isLoading ? 'Giriş yapılıyor...' : 'Google Drive ile Giriş Yap',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF34A853),
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: const Color(0xFF34A853).withOpacity(0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Anonim giriş butonu
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _signInAnonymously,
                    icon: const Icon(Icons.person_outline, color: Colors.white70),
                    label: const Text(
                      'Anonim Olarak Devam Et',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.white70,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white30),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                
                // Açıklama metni
                const Text(
                  'Google hesabınızla giriş yaparak fotoğraflarınızı güvenle saklayabilir ve diğer cihazlarınızdan erişebilirsiniz.',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Google Sign-In işlemi
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        // Kullanıcı giriş işlemini iptal etti
        setState(() => _isLoading = false);
        return;
      }

      // Google kimlik bilgilerini al
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Firebase credential oluştur
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Firebase'e giriş yap
      await FirebaseAuth.instance.signInWithCredential(credential);
      
      // Auth servisini güncelle
      await FirebaseAuthService.instance.initialize();
      
      if (mounted) {
        // Ana sayfaya dön
        Navigator.of(context).pop();
      }
      
    } catch (e) {
      setState(() {
        _error = 'Google giriş hatası: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _signInAnonymously() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await FirebaseAuthService.instance.signInAnonymously();
      
      if (mounted) {
        // Ana sayfaya dön
        Navigator.of(context).pop();
      }
      
    } catch (e) {
      setState(() {
        _error = 'Anonim giriş hatası: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _signInWithEmail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      if (email.isEmpty || password.isEmpty) {
        setState(() {
          _error = 'Lütfen email ve şifre girin';
          _isLoading = false;
        });
        return;
      }

      if (_isSignUp) {
        // Kayıt ol
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        // Giriş yap
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      // Auth servisini güncelle
      await FirebaseAuthService.instance.initialize();
      
      if (mounted) {
        // Ana sayfaya dön
        Navigator.of(context).pop();
      }
      
    } catch (e) {
      setState(() {
        _error = _isSignUp 
          ? 'Kayıt hatası: ${e.toString()}'
          : 'Giriş hatası: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _signInWithGoogleDrive() async {
    // Kullanıcıya hesap seçimi seçeneği sun
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Google Drive Girişi', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Google Drive\'a giriş yapmak için hesap seçimi yapın:',
          style: TextStyle(color: Colors.white70),
        ),
        backgroundColor: const Color(0xFF2A2F35),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'silent'),
            child: const Text('Mevcut Hesabı Kullan', style: TextStyle(color: Colors.blue)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'manual'),
            child: const Text('Hesap Seç', style: TextStyle(color: Colors.green)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('İptal', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );

    if (choice == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      bool success;
      if (choice == 'silent') {
        // Sessiz giriş dene
        success = await GoogleDriveService.instance.signInSilently();
      } else {
        // Manuel hesap seçimi
        success = await GoogleDriveService.instance.signIn();
      }
      
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Google Drive\'a giriş yapıldı: ${GoogleDriveService.instance.userEmail}'),
              backgroundColor: Colors.green,
            ),
          );
          // Ana sayfaya dön
          Navigator.of(context).pop();
        }
      } else {
        setState(() {
          _error = 'Google Drive girişi başarısız: ${GoogleDriveService.instance.lastError}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Google Drive giriş hatası: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _signOut() async {
    try {
      print('🚪 Firebase Login sayfasından çıkış yapılıyor...');
      await FirebaseAuthService.instance.signOut();
      
      if (mounted) {
        setState(() {
          _error = null;
          _isLoading = false;
        });
        
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
        setState(() {
          _error = 'Çıkış hatası: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
