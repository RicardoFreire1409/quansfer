import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;

/// AES-CBC con IV aleatorio y PKCS7
class CryptoService {
  /// Si BB84 ya te entrega 16 bytes, úsala tal cual (AES-128).
  Uint8List deriveKey(List<int> bb84Bytes) {
    if (bb84Bytes.length >= 16) {
      return Uint8List.fromList(bb84Bytes.take(16).toList());
    }
    // Si por alguna razón viniera más corta (no debería), la rellenamos simple.
    final padded = List<int>.from(bb84Bytes);
    while (padded.length < 16) padded.add(0);
    return Uint8List.fromList(padded);
  }

  Uint8List randomIv() {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  /// Retorna { cipher: Uint8List, ivB64: String }
  Map<String, dynamic> encryptBytes(Uint8List plain, Uint8List key, Uint8List iv) {
    final k = enc.Key(key);
    final ivObj = enc.IV(iv);
    final encrypter = enc.Encrypter(enc.AES(k, mode: enc.AESMode.cbc, padding: 'PKCS7'));
    final encrypted = encrypter.encryptBytes(plain, iv: ivObj);
    return {'cipher': Uint8List.fromList(encrypted.bytes), 'ivB64': base64Encode(iv)};
  }

  /// Descifrar (por si luego añades pantalla Receptor)
  Uint8List decryptBytes(Uint8List cipher, Uint8List key, Uint8List iv) {
    final k = enc.Key(key);
    final ivObj = enc.IV(iv);
    final encrypter = enc.Encrypter(enc.AES(k, mode: enc.AESMode.cbc, padding: 'PKCS7'));
    return Uint8List.fromList(encrypter.decryptBytes(enc.Encrypted(cipher), iv: ivObj));
  }
}
