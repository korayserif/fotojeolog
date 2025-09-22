import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

class FirebaseAuthService {
  FirebaseAuthService._();
  static final FirebaseAuthService instance = FirebaseAuthService._();

  FirebaseAuth? _auth;
  User? _currentUser;

  /// Firebase Auth'u başlat
  Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
      _auth = FirebaseAuth.instance;
      _currentUser = _auth?.currentUser;
      
      // Auth durumu değişikliklerini dinle
      _auth?.authStateChanges().listen((User? user) {
        _currentUser = user;
      });
      
    } catch (e) {
      throw Exception('Firebase Auth başlatma hatası: $e');
    }
  }

  /// Anonim olarak giriş yap
  Future<User?> signInAnonymously() async {
    try {
      if (_auth == null) {
        await initialize();
      }

      final UserCredential result = await _auth!.signInAnonymously();
      _currentUser = result.user;
      
      return _currentUser;
    } catch (e) {
      throw Exception('Anonim giriş hatası: $e');
    }
  }

  /// Email/Password ile giriş yap
  Future<User?> signInWithEmailAndPassword(String email, String password) async {
    try {
      if (_auth == null) {
        await initialize();
      }

      final UserCredential result = await _auth!.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      _currentUser = result.user;
      
      return _currentUser;
    } catch (e) {
      throw Exception('Email giriş hatası: $e');
    }
  }

  /// Email/Password ile kayıt ol
  Future<User?> createUserWithEmailAndPassword(String email, String password) async {
    try {
      if (_auth == null) {
        await initialize();
      }

      final UserCredential result = await _auth!.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      _currentUser = result.user;
      
      return _currentUser;
    } catch (e) {
      throw Exception('Email kayıt hatası: $e');
    }
  }

  /// Mevcut kullanıcıyı al - HER ZAMAN GÜNCEL KULLANICIYI AL
  User? get currentUser => _auth?.currentUser;

  /// Kullanıcı oturum açmış mı?
  bool get isSignedIn => _auth?.currentUser != null;

  /// Kullanıcı ID'si - HER ZAMAN GÜNCEL KULLANICIYI AL
  String? get userId => _auth?.currentUser?.uid;

  /// Kullanıcı email'i - HER ZAMAN GÜNCEL KULLANICIYI AL
  String? get email => _auth?.currentUser?.email;

  /// Kullanıcı görünen adı - HER ZAMAN GÜNCEL KULLANICIYI AL
  String? get displayName => _auth?.currentUser?.displayName;

  /// Auth durumu değişikliklerini dinle
  Stream<User?> get authStateChanges {
    if (_auth == null) {
      return Stream.value(null);
    }
    return _auth!.authStateChanges();
  }

  /// Firebase Auth instance'ını al
  FirebaseAuth? get auth => _auth;

  /// Çıkış yap
  Future<void> signOut() async {
    try {
      print('🚪 Kullanıcı çıkış yapıyor...');
      await _auth?.signOut();
      _currentUser = null;
      print('✅ Kullanıcı başarıyla çıkış yaptı');
      print('🔄 Auth durumu sıfırlandı - yeni giriş için hazır');
    } catch (e) {
      print('❌ Çıkış hatası: $e');
      throw Exception('Çıkış hatası: $e');
    }
  }

  /// Otomatik giriş sağla (anonim)
  Future<void> ensureAuthenticated() async {
    if (!isSignedIn) {
      await signInAnonymously();
    }
  }
}
