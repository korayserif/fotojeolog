import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;
import 'firebase_auth_service.dart';

class FirestoreService {
  FirestoreService._();
  static final FirestoreService instance = FirestoreService._();

  FirebaseFirestore? _firestore;
  FirebaseStorage? _storage;
  
  /// Firebase'i başlat
  Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
      _firestore = FirebaseFirestore.instance;
      _storage = FirebaseStorage.instance;
      
      // Firebase Auth'u da başlat
      await FirebaseAuthService.instance.initialize();
    } catch (e) {
      throw Exception('Firestore başlatma hatası: $e');
    }
  }

  /// Fotoğraf verilerini Firestore'a kaydet
  Future<String> savePhotoData({
    required String imagePath,
    required String notes,
    String? projectName,
    String? kat,
    String? ayna,
    String? km,
  }) async {
    try {
      print('🚀 ===== FIRESTORE SAVE BAŞLADI =====');
      print('📁 Image path: $imagePath');
      print('📝 Notes length: ${notes.length}');
      print('🏗️ Kat: $kat');
      print('🏗️ Ayna: $ayna');
      print('🏗️ Km: $km');
      
      if (_firestore == null || _storage == null) {
        await initialize();
      }
      
      // HER ZAMAN GÜNCEL KULLANICIYI AL
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('Kullanıcı kimlik doğrulaması gerekli');
      }
      
      print('👤 Current user: ${currentUser.email} (${currentUser.uid})');
      
      // Dosya adı oluştur
      final fileName = _generateFileName(path.basename(imagePath));
      print('📄 Generated filename: $fileName');
      
      // 1. Önce dosyayı Firebase Storage'a yükle
      final file = File(imagePath);
      if (!await file.exists()) {
        throw Exception('Fotoğraf dosyası bulunamadı: $imagePath');
      }
      
      // Firebase Storage yolu - KULLANICIYA ÖZGÜ
      String storagePath;
      if (kat != null && ayna != null && km != null) {
        storagePath = 'users/${currentUser.uid}/photos/$kat/$ayna/$km/$fileName';
      } else {
        storagePath = 'users/${currentUser.uid}/photos/$fileName';
      }
      
      print('📂 Storage path: $storagePath');
      
      // Firebase Storage'a yükle
      final storageRef = _storage!.ref().child(storagePath);
      final uploadTask = await storageRef.putFile(file);
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      
      print('✅ File uploaded to Firebase Storage: $downloadUrl');
      
      // 2. Sonra metadata'yı Firestore'a kaydet
      final photoData = {
        'fileName': fileName,
        'imagePath': downloadUrl, // Firebase Storage URL'i
        'notes': notes,
        'project': projectName ?? 'Genel',
        'uploadTime': FieldValue.serverTimestamp(),
        'uploader': 'FotoJeolog App',
        'userId': currentUser.uid,
        'email': currentUser.email,
        'kat': kat ?? '',
        'ayna': ayna ?? '',
        'km': km ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'storagePath': storagePath,
      };
      
      print('📋 Photo data created');
      
      // Firestore'a kaydet - KULLANICIYA ÖZGÜ YOL
      final docRef = await _firestore!
          .collection('users')
          .doc(currentUser.uid) // Kullanıcının UID'si
          .collection('photos')
          .add(photoData);
      
      print('✅ Photo saved to Firestore with ID: ${docRef.id}');
      print('🚀 ===== FIRESTORE SAVE BİTTİ =====');
      
      return docRef.id;
      
    } catch (e) {
      print('❌ Firestore save hatası: $e');
      throw Exception('Firestore save hatası: $e');
    }
  }

  /// Kullanıcıya özgü fotoğrafları Firestore'dan al
  Future<List<FirestorePhoto>> getUserPhotos() async {
    try {
      print('🚀 ===== FIRESTORE GET BAŞLADI =====');
      
      if (_firestore == null) {
        await initialize();
      }
      
      // HER ZAMAN GÜNCEL KULLANICIYI AL
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('Kullanıcı kimlik doğrulaması gerekli');
      }
      
      print('👤 Current user: ${currentUser.email} (${currentUser.uid})');
      print('📂 Getting photos for user: ${currentUser.uid}');
      
      // Kullanıcıya özgü fotoğrafları al
      final QuerySnapshot snapshot = await _firestore!
          .collection('users')
          .doc(currentUser.uid) // Kullanıcının UID'si
          .collection('photos')
          .orderBy('uploadTime', descending: true)
          .get();
      
      print('📁 Found ${snapshot.docs.length} photos in Firestore');
      
      List<FirestorePhoto> photos = [];
      
      for (QueryDocumentSnapshot doc in snapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;
          
          photos.add(FirestorePhoto(
            id: doc.id,
            fileName: data['fileName'] ?? '',
            imagePath: data['imagePath'] ?? '',
            notes: data['notes'] ?? '',
            project: data['project'] ?? 'Genel',
            uploadTime: (data['uploadTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
            uploader: data['uploader'] ?? 'Bilinmeyen',
            userId: data['userId'] ?? '',
            email: data['email'] ?? '',
            kat: data['kat'] ?? '',
            ayna: data['ayna'] ?? '',
            km: data['km'] ?? '',
            createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          ));
          
          print('📄 Photo added: ${data['fileName']}');
        } catch (e) {
          print('❌ Photo data error: ${doc.id} - $e');
        }
      }
      
      print('✅ Total ${photos.length} photos retrieved');
      print('🚀 ===== FIRESTORE GET BİTTİ =====');
      
      return photos;
      
    } catch (e) {
      print('❌ Firestore get hatası: $e');
      throw Exception('Firestore get hatası: $e');
    }
  }

  /// Fotoğrafı Firestore'dan ve Firebase Storage'dan sil
  Future<void> deletePhoto(String photoId) async {
    try {
      if (_firestore == null || _storage == null) {
        await initialize();
      }
      
      // HER ZAMAN GÜNCEL KULLANICIYI AL
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('Kullanıcı kimlik doğrulaması gerekli');
      }
      
      // Önce Firestore'dan fotoğraf bilgilerini al
      final docRef = _firestore!
          .collection('users')
          .doc(currentUser.uid)
          .collection('photos')
          .doc(photoId);
      
      final doc = await docRef.get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final storagePath = data['storagePath'] as String?;
        
        // Firebase Storage'dan dosyayı sil
        if (storagePath != null) {
          try {
            await _storage!.ref().child(storagePath).delete();
            print('✅ File deleted from Firebase Storage: $storagePath');
          } catch (e) {
            print('⚠️ Firebase Storage delete hatası: $e');
          }
        }
        
        // Firestore'dan metadata'yı sil
        await docRef.delete();
        print('✅ Photo deleted from Firestore: $photoId');
      } else {
        print('⚠️ Photo not found in Firestore: $photoId');
      }
      
    } catch (e) {
      throw Exception('Firestore delete hatası: $e');
    }
  }

  /// Dosya adı oluştur
  String _generateFileName(String originalName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = path.extension(originalName);
    return 'jeoloji_$timestamp$extension';
  }
}

/// Firestore fotoğraf modeli
class FirestorePhoto {
  final String id;
  final String fileName;
  final String imagePath;
  final String notes;
  final String project;
  final DateTime uploadTime;
  final String uploader;
  final String userId;
  final String email;
  final String kat;
  final String ayna;
  final String km;
  final DateTime createdAt;

  FirestorePhoto({
    required this.id,
    required this.fileName,
    required this.imagePath,
    required this.notes,
    required this.project,
    required this.uploadTime,
    required this.uploader,
    required this.userId,
    required this.email,
    this.kat = '',
    this.ayna = '',
    this.km = '',
    required this.createdAt,
  });

  /// Upload zamanını formatla
  String get formattedUploadTime {
    return '${uploadTime.day}/${uploadTime.month}/${uploadTime.year} ${uploadTime.hour}:${uploadTime.minute.toString().padLeft(2, '0')}';
  }

  /// Klasör yolunu göster
  String get folderPath {
    if (kat.isNotEmpty && ayna.isNotEmpty && km.isNotEmpty) {
      return '$kat/$ayna/$km';
    }
    return 'Genel';
  }
}
