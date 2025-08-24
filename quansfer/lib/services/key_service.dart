import 'dart:convert';
import 'package:http/http.dart' as http;

class KeyService {
  final String baseUrl;
  const KeyService(this.baseUrl);

  Future<List<int>> fetchSharedKey() async {
    final resp = await http.get(Uri.parse('$baseUrl/qkd/key'));
    if (resp.statusCode != 200) {
      throw Exception('No se pudo obtener la clave (status ${resp.statusCode}).');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final hex = data['key_hex'] as String;
    final out = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return out; // 16 bytes
  }
}
