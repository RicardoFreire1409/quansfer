import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'receiver_page.dart';   // ✅
import 'dart:io';
import '../services/key_service.dart';
import '../services/crypto_service.dart';

class HomePage extends StatefulWidget {
  final String baseUrl;
  const HomePage({super.key, required this.baseUrl});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Uint8List? _fileBytes;
  String? _fileName;
  List<int>? _bb84Key;
  late final KeyService _keyService;
  final _crypto = CryptoService();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _keyService = KeyService(widget.baseUrl);
  }

  Future<void> _getKey() async {
    setState(() => _busy = true);
    try {
      final k = await _keyService.fetchSharedKey();
      setState(() => _bb84Key = k);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Clave BB84 obtenida.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clave: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFile() async {
  try {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.any,      // fuerza cualquier tipo
      allowMultiple: false,
      withData: true,          // importante para tener bytes en memoria
    );

    if (res == null || res.files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selección cancelada o vacía')),
        );
      }
      return;
    }

    final file = res.files.first;
    if (file.bytes == null) {
      // En algunos dispositivos, withData puede no traer bytes.
      // Podemos leer por path si existe:
      if (file.path == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudieron obtener bytes del archivo.')),
          );
        }
        return;
      }
      // Lee desde path como fallback:
      final bytes = await File(file.path!).readAsBytes();
      setState(() {
        _fileBytes = bytes;
        _fileName  = file.name;
      });
    } else {
      setState(() {
        _fileBytes = file.bytes!;
        _fileName  = file.name;
      });
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Seleccionado: $_fileName')),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al seleccionar archivo: $e')),
      );
    }
  }
}
  Future<void> _encryptAndUpload() async {
    if (_fileBytes == null || _bb84Key == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona archivo y genera la clave primero.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final key = _crypto.deriveKey(_bb84Key!); // 16 bytes
      final iv  = _crypto.randomIv();
      final encData = _crypto.encryptBytes(_fileBytes!, key, iv);
      final cipher = encData['cipher'] as Uint8List;
      final ivB64  = encData['ivB64'] as String;

      final req = http.MultipartRequest('POST', Uri.parse('${widget.baseUrl}/upload'));
      req.fields['iv_b64'] = ivB64;
      req.files.add(http.MultipartFile.fromBytes(
        'file',
        cipher,
        filename: '${_fileName ?? 'file'}.enc',
      ));

      final resp = await req.send();
      if (resp.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Archivo cifrado enviado con éxito.')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al subir: ${resp.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fallo cifrado/subida: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEncrypt = _fileBytes != null && _bb84Key != null;
    return Scaffold(
      appBar: AppBar(title: const Text('quansfer')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _getKey,
              icon: const Icon(Icons.key),
              label: const Text('1) Obtener clave (BB84)'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _pickFile,
              icon: const Icon(Icons.attach_file),
              label: const Text('2) Seleccionar archivo'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy || !canEncrypt ? null : _encryptAndUpload,
              icon: const Icon(Icons.lock),
              label: const Text('3) Cifrar (AES-CBC) y subir'),
            ),
            const SizedBox(height: 24),
            if (_fileName != null) Text('Archivo: $_fileName'),
            const SizedBox(height: 12),
            if (_busy) const LinearProgressIndicator(),
            ElevatedButton.icon(
  onPressed: () {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReceiverPage(baseUrl: widget.baseUrl),
    ));
  },
  icon: const Icon(Icons.download),
  label: const Text('Ir a Receptor (Descifrar)'),
),
          ],
          
        ),
      ),
    );
  }
}
