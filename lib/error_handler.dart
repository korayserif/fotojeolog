import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ErrorHandler {
  static void handleError(dynamic error, StackTrace? stackTrace) {
    if (kDebugMode) {
      print('Error: $error');
      print('StackTrace: $stackTrace');
    }
    // Burada hata loglama servisi entegre edilebilir
  }

  static void showErrorDialog(
      BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  static Future<T> safeExecute<T>(
    Future<T> Function() operation,
    BuildContext context, {
    String errorTitle = 'Hata',
    String errorMessage = 'Bir hata oluştu. Lütfen tekrar deneyin.',
  }) async {
    try {
      return await operation();
    } catch (e, stackTrace) {
      handleError(e, stackTrace);
      if (context.mounted) {
        showErrorDialog(context, errorTitle, errorMessage);
      }
      rethrow;
    }
  }
}
