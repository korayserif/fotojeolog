import 'package:flutter/material.dart';
import 'services/google_drive_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _cloudEnabled = false;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Google Drive durumunu kontrol et
    setState(() {
      _cloudEnabled = GoogleDriveService.instance.isSignedIn;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar'),
        backgroundColor: const Color(0xFF1B1F24),
        foregroundColor: Colors.white,
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SwitchListTile(
                  title: const Text('Google Drive\'a otomatik yükle'),
                  subtitle: const Text('Kaydederken buluta da yedekle'),
                  value: _cloudEnabled,
                  onChanged: (v) async {
                    setState(() => _cloudEnabled = v);
                    // Google Drive otomatik yükleme ayarı burada yapılabilir
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.account_circle),
                  title: Text(GoogleDriveService.instance.isSignedIn
                      ? (GoogleDriveService.instance.displayName ??
                          GoogleDriveService.instance.email ??
                          'Oturum açık')
                      : 'Google Drive ile oturum aç'),
                  subtitle: Text(GoogleDriveService.instance.isSignedIn
                      ? (GoogleDriveService.instance.email ?? '')
                      : 'Google Drive\'a yüklemek için giriş yapın'),
                  trailing: ElevatedButton(
                    onPressed: () async {
                      if (GoogleDriveService.instance.isSignedIn) {
                        print('🚪 Settings sayfasından çıkış yapılıyor...');
                        await GoogleDriveService.instance.signOut();
                        if (!mounted) return;
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Başarıyla çıkış yapıldı'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } else {
                        try {
                          await GoogleDriveService.instance.signIn();
                          if (!mounted) return;
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Giriş başarılı')),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Giriş hatası: $e')),
                          );
                        }
                      }
                    },
                    child: Text(GoogleDriveService.instance.isSignedIn
                        ? 'Çıkış yap'
                        : 'Giriş yap'),
                  ),
                ),
              ],
            ),
    );
  }
}
