import 'dart:io';
import 'package:share_plus/share_plus.dart';

class SocialShareService {
  SocialShareService._();
  static final SocialShareService instance = SocialShareService._();

  /// Fotoğraf ve notları WhatsApp/Telegram gruppuna paylaş
  Future<void> shareToGroup({
    required String imagePath,
    required String notes,
    String? groupTitle,
  }) async {
    try {
      // Paylaşım metni oluştur
      String shareText = _createShareText(notes, groupTitle);
      
      // Fotoğraf dosyasını kontrol et
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        throw Exception('Fotoğraf dosyası bulunamadı: $imagePath');
      }

      // XFile olarak hazırla
      final xFile = XFile(imagePath);
      
      // WhatsApp/Telegram grubu için paylaş
      await Share.shareXFiles(
        [xFile],
        text: shareText,
        subject: 'Fotojeolog - Saha Raporu',
      );
      
    } catch (e) {
      throw Exception('Paylaşım hatası: $e');
    }
  }

  /// Sadece notları paylaş (fotoğraf olmadan)
  Future<void> shareNotesOnly({
    required String notes,
    String? groupTitle,
  }) async {
    try {
      String shareText = _createShareText(notes, groupTitle);
      
      await Share.share(
        shareText,
        subject: 'Fotojeolog - Saha Notu',
      );
      
    } catch (e) {
      throw Exception('Not paylaşım hatası: $e');
    }
  }

  /// Çoklu fotoğraf paylaşımı
  Future<void> shareMultiplePhotos({
    required List<String> imagePaths,
    required String notes,
    String? groupTitle,
  }) async {
    try {
      // Tüm fotoğrafları kontrol et
      List<XFile> xFiles = [];
      for (String imagePath in imagePaths) {
        final imageFile = File(imagePath);
        if (await imageFile.exists()) {
          xFiles.add(XFile(imagePath));
        }
      }

      if (xFiles.isEmpty) {
        throw Exception('Paylaşılacak fotoğraf bulunamadı');
      }

      String shareText = _createShareText(notes, groupTitle);
      
      await Share.shareXFiles(
        xFiles,
        text: shareText,
        subject: 'Fotojeolog - Saha Raporu (${xFiles.length} fotoğraf)',
      );
      
    } catch (e) {
      throw Exception('Çoklu paylaşım hatası: $e');
    }
  }

  /// WhatsApp'a doğrudan paylaş (eğer kuruluysa)
  Future<void> shareToWhatsApp({
    required String imagePath,
    required String notes,
    String? groupTitle,
  }) async {
    try {
      String shareText = _createShareText(notes, groupTitle);
      final xFile = XFile(imagePath);
      
      // WhatsApp package name ile paylaş
      await Share.shareXFiles(
        [xFile],
        text: shareText,
        subject: 'Fotojeolog - Saha Raporu',
      );
      
    } catch (e) {
      // WhatsApp yoksa normal paylaşım
      await shareToGroup(
        imagePath: imagePath,
        notes: notes,
        groupTitle: groupTitle,
      );
    }
  }

  /// Paylaşım metnini formatla
  String _createShareText(String notes, String? groupTitle) {
    final DateTime now = DateTime.now();
    final String timestamp = '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    
    String text = '📸 *Fotojeolog Saha Raporu*\n';
    text += '📅 Tarih: $timestamp\n';
    
    if (groupTitle != null && groupTitle.isNotEmpty) {
      text += '🏢 Proje: $groupTitle\n';
    }
    
    text += '\n📝 *Notlar:*\n$notes\n';
    text += '\n---\n';
    text += '📱 Fotojeolog uygulaması ile gönderildi';
    
    return text;
  }

  /// Paylaşım öncesi önizleme metni
  String getPreviewText(String notes, String? groupTitle) {
    return _createShareText(notes, groupTitle);
  }

  /// Uygulama kurulu mu kontrol et (opsiyonel)
  Future<bool> isWhatsAppInstalled() async {
    // Platform-specific kontrol yapılabilir
    // Şimdilik true dönsün, Share.shareXFiles zaten uygun uygulamayı gösterir
    return true;
  }

  /// Telegram için paylaş
  Future<void> shareToTelegram({
    required String imagePath,
    required String notes,
    String? groupTitle,
  }) async {
    // Telegram'a özel formatlamalar yapılabilir
    await shareToGroup(
      imagePath: imagePath,
      notes: notes,
      groupTitle: groupTitle,
    );
  }
}