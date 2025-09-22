import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionsHelper {
  /// Android 13+ için READ_MEDIA_IMAGES, 12- için READ_EXTERNAL_STORAGE;
  /// iOS için Photos izni; web için gerekmez.
  static Future<bool> ensureGalleryPermission() async {
    if (kIsWeb) return true;

    if (Platform.isAndroid) {
      // Android 13+ READ_MEDIA_IMAGES, eski sürümler READ_EXTERNAL_STORAGE
      final status13 = await Permission.photos.status;
      // permission_handler, Android'de Photos'u READ_MEDIA_IMAGES ile map'ler
      if (status13.isGranted) return true;

      final req = await Permission.photos.request();
      return req.isGranted;
    } else if (Platform.isIOS) {
      final status = await Permission.photos.status;
      if (status.isGranted) return true;
      final req = await Permission.photos.request();
      return req.isGranted;
    } else {
      return true;
    }
  }

  static Future<bool> ensureCameraPermission() async {
    if (kIsWeb) return true;
    if (!(Platform.isAndroid || Platform.isIOS)) return true;

    final status = await Permission.camera.status;
    if (status.isGranted) return true;
    final req = await Permission.camera.request();
    return req.isGranted;
  }

  static Future<void> openAppSettingsIfPermanentlyDenied() async {
    final perms = [Permission.photos, Permission.camera];
    for (final p in perms) {
      final st = await p.status;
      if (st.isPermanentlyDenied) {
        await openAppSettings();
        break;
      }
    }
  }
}
