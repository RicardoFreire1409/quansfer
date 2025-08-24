import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/crypto_service.dart';
import 'dart:io';    
class ReceiverPage extends StatefulWidget {
  final String baseUrl;
  const ReceiverPage({super.key, required this.baseUrl});

  @override
  State<ReceiverPage> createState() => _ReceiverPageState();
}

class _ReceiverPageState extends State<ReceiverPage> {
  final _crypto = CryptoService();
  Uint8List? _encBytes;
  String? _encName;

  final _ivController = TextEditingController();
  final _keyHexController = TextEditingController();
  bool _busy = false;

  Future<void> _pickEncFile() async {
  try {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.any,      // 👈 abre el picker en todos los dispositivos
      allowMultiple: false,
      withData: true,          // intenta traer bytes en memoria
    );

    if (res == null || res.files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selección cancelada')),
        );
      }
      return;
    }

    final file = res.files.first;

    // Validamos extensión .enc (case-insensitive)
    final name = file.name;
    final isEnc = name.toLowerCase().endsWith('.enc');
    if (!isEnc) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Selecciona un archivo .enc (elegiste: $name)')),
        );
      }
      return;
    }

    // Obtenemos bytes: si withData falló, leemos por path (solo no-web)
    Uint8List bytes;
    if (file.bytes != null) {
      bytes = file.bytes!;
    } else if (!kIsWeb && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudieron obtener bytes del .enc')),
        );
      }
      return;
    }

    setState(() {
      _encBytes = bytes;
      _encName  = name;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Seleccionado: $_encName')),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al seleccionar: $e')),
      );
    }
  }
}

  Future<void> _fetchKeyFromServer() async {
    setState(() => _busy = true);
    try {
      final r = await http.get(Uri.parse('${widget.baseUrl}/qkd/key'));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        _keyHexController.text = data['key_hex'] as String;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clave (BB84) obtenida del servidor.')));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error clave: ${r.statusCode}')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decryptLocally() async {
    if (_encBytes == null || _ivController.text.isEmpty || _keyHexController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Falta archivo .enc, IV o clave.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final iv = base64Decode(_ivController.text.trim());
      final keyHex = _keyHexController.text.trim();
      final keyBytes = <int>[];
      for (var i = 0; i < keyHex.length; i += 2) {
        keyBytes.add(int.parse(keyHex.substring(i, i + 2), radix: 16));
      }
      final plain = _crypto.decryptBytes(_encBytes!, Uint8List.fromList(keyBytes), Uint8List.fromList(iv));

      // Nombre de salida
      var outName = _encName ?? 'output.enc';
      if (outName.endsWith('.enc')) outName = outName.substring(0, outName.length - 4);

      // Guardar archivo
      await FileSaver.instance.saveFile(
        name: outName,
        bytes: plain,
        mimeType: MimeType.other,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Archivo guardado: $outName')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fallo al descifrar: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decryptOnServer() async {
    if (_encBytes == null || _ivController.text.isEmpty || _keyHexController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Falta archivo .enc, IV o clave.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final req = http.MultipartRequest('POST', Uri.parse('${widget.baseUrl}/decrypt'));
      req.fields['iv_b64'] = _ivController.text.trim();
      req.fields['key_hex'] = _keyHexController.text.trim();
      if (_encName != null) req.fields['original_name'] = _encName!.endsWith('.enc') ? _encName!.substring(0, _encName!.length - 4) : _encName!;
      req.files.add(http.MultipartFile.fromBytes('file', _encBytes!, filename: _encName ?? 'file.enc'));

      final resp = await req.send();
      if (resp.statusCode == 200) {
        final bytes = await resp.stream.toBytes();
        var outName = _encName ?? 'output.enc';
        if (outName.endsWith('.enc')) outName = outName.substring(0, outName.length - 4);
        await FileSaver.instance.saveFile(name: outName, bytes: bytes, mimeType: MimeType.other);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Descifrado en servidor y guardado: $outName')));
        }
      } else {
        final body = await resp.stream.bytesToString();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Servidor respondió ${resp.statusCode}: $body')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receptor (Descifrar)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            FilledButton.icon(
              onPressed: _pickEncFile,
              icon: const Icon(Icons.attach_file),
              label: Text(_encName == null ? 'Seleccionar archivo .enc' : 'Archivo: $_encName'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ivController,
              decoration: const InputDecoration(
                labelText: 'IV (Base64)',
                hintText: 'Ej: 3ux1sLk... (16 bytes base64)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keyHexController,
              decoration: const InputDecoration(
                labelText: 'Clave (Hex)',
                hintText: '32 hex chars para AES-128',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _fetchKeyFromServer,
                  icon: const Icon(Icons.key),
                  label: const Text('Pedir clave al servidor'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _decryptLocally,
              icon: const Icon(Icons.lock_open),
              label: const Text('Descifrar LOCAL y guardar'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _decryptOnServer,
              icon: const Icon(Icons.cloud_download),
              label: const Text('Descifrar en SERVIDOR y guardar'),
            ),
            const SizedBox(height: 16),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
