import 'dart:convert';

class StickyNote {
  String id;
  double x; // Görüntü (scene) koordinatında X
  double y; // Görüntü (scene) koordinatında Y
  String text;
  String? author; // e-posta veya ad
  double fontSize;
  bool collapsed;
  int color; // Arka plan renk değeri (Color.value olarak saklanacak)
  int textColor; // Yazı renk değeri (Color.value olarak saklanacak)
  double width; // Not kutusu genişliği (overlay pikseli)
  double height; // Not kutusu yüksekliği (overlay pikseli)
  DateTime createdAt;
  DateTime updatedAt;

  StickyNote({
    required this.id,
    required this.x,
    required this.y,
    required this.text,
    this.author,
    double? fontSize,
    bool? collapsed,
    int? color,
    int? textColor,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? width,
    double? height,
  })  : fontSize = fontSize ?? 14.0,
        collapsed = collapsed ?? false,
        color = color ?? 0xFFFFF59D, // Varsayılan sarı renk
        textColor = textColor ?? 0xFF000000, // Varsayılan siyah yazı
        width = width ?? 200.0,
        height = height ?? 120.0,
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        'text': text,
        'author': author,
        'fontSize': fontSize,
        'collapsed': collapsed,
        'color': color,
        'textColor': textColor,
        'width': width,
        'height': height,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static StickyNote fromJson(Map<String, dynamic> json) => StickyNote(
        id: json['id'] as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        text: json['text'] as String? ?? '',
        author: json['author'] as String?,
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
        collapsed: (json['collapsed'] as bool?) ?? false,
        color: (json['color'] as int?) ?? 0xFFFFF59D, // Varsayılan sarı
        textColor: (json['textColor'] as int?) ?? 0xFF000000, // Varsayılan siyah yazı
        width: (json['width'] as num?)?.toDouble() ?? 200.0,
        height: (json['height'] as num?)?.toDouble() ?? 120.0,
        createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now(),
      );

  static String encodeList(List<StickyNote> notes) => jsonEncode(notes.map((e) => e.toJson()).toList());
  static List<StickyNote> decodeList(String jsonStr) {
    final decoded = jsonDecode(jsonStr) as List<dynamic>;
    return decoded.map((e) => StickyNote.fromJson(e as Map<String, dynamic>)).toList();
  }
}
