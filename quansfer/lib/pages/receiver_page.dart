// lib/pages/receiver_page.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../widgets/primary_button.dart';
import '../widgets/info_tile.dart';
import '../app_state.dart';

class ReceiverPage extends StatefulWidget {
  final AppState appState;
  const ReceiverPage({super.key, required this.appState});

  @override
  State<ReceiverPage> createState() => _ReceiverPageState();
}

class _ReceiverPageState extends State<ReceiverPage> {
  final _transferIdController = TextEditingController();
  bool _busy = false;
  String? _filename; // nombre ORIGINAL (con extensión) desde el backend
  String get _baseUrl => widget.appState.baseUrl;

  @override
  void dispose() {
    _transferIdController.dispose();
    super.dispose();
  }

  // -------------------- Helpers --------------------
  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<http.Response> _get(String path) {
    return http.get(Uri.parse('$_baseUrl$path')).timeout(const Duration(seconds: 60));
  }

  /// Garantiza que _filename (del backend) esté cargado para el id actual.
  Future<void> _ensureMeta(String id) async {
    if (id.isEmpty) return;
    if (_filename != null && _filename!.isNotEmpty) return;
    try {
      final r = await _get('/transfer/$id');
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        final fname = (data['filename_original'] as String?)?.trim();
        if (fname != null && fname.isNotEmpty && mounted) {
          setState(() => _filename = fname);
        }
      }
    } catch (_) {
      // Silencioso; no bloqueamos el flujo si falla la metadata.
    }
  }

  /// Extrae filename de Content-Disposition.
  String? _filenameFromHeaders(Map<String, String> headers) {
    final cd = headers.entries
        .firstWhere(
          (e) => e.key.toLowerCase() == 'content-disposition',
          orElse: () => const MapEntry('', ''),
        )
        .value;
    if (cd.isEmpty) return null;

    // Raw triple quotes (sin escapes) para Dart.
    final fnStar = RegExp(
      r'''filename\*\s*=\s*[^'"]*''([^;]+)''',
      caseSensitive: false,
    ).firstMatch(cd);
    if (fnStar != null) {
      try {
        return Uri.decodeComponent(fnStar.group(1)!.trim());
      } catch (_) {}
    }

    final fn = RegExp(r'filename\s*=\s*"([^"]+)"', caseSensitive: false).firstMatch(cd);
    if (fn != null) return fn.group(1)!.trim();

    final fn2 = RegExp(r'filename\s*=\s*([^;]+)', caseSensitive: false).firstMatch(cd);
    if (fn2 != null) return fn2.group(1)!.trim();

    return null;
  }

  /// Guardar bytes mostrando “Guardar en…” (SAF/UIDocumentPicker) en TODAS las plataformas soportadas.
  /// Requiere file_selector (+ file_selector_android / file_selector_ios).
  Future<void> _saveWithPicker(Uint8List bytes, String suggestedName) async {
  try {
    // 1) INTENTA usar el diálogo nativo (SAF/UIDocumentPicker)
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [XTypeGroup(label: 'All', extensions: ['*'])],
    );
    if (location == null) {
      _toast('Guardado cancelado');
      return;
    }
    final xf = XFile.fromData(bytes, name: suggestedName, mimeType: 'application/octet-stream');
    await xf.saveTo(location.path);
    _toast('Guardado correctamente');
    return;
  } on UnimplementedError {
    // 2) FALLBACK para dispositivos sin proveedor SAF (p.ej., algunos MIUI)
    try {
      // (Opcional) para Android < 10 podrías pedir WRITE_EXTERNAL_STORAGE:
      // await Permission.storage.request();

      // a) Guarda en directorio de la app (accesible vía "Archivos" > Android > data en algunos SO)
      final dir = await getExternalStorageDirectory(); // /Android/data/<pkg>/files en Android
      final fallbackDir = Directory('${dir!.path}/quansfer');
      if (!await fallbackDir.exists()) {
        await fallbackDir.create(recursive: true);
      }
      final filePath = '${fallbackDir.path}/$suggestedName';
      final f = File(filePath);
      await f.writeAsBytes(bytes);

      // b) Ofrece COMPARTIR para que el usuario lo envíe a "Descargas/Drive/Files"
      await Share.shareXFiles([XFile(f.path)], text: 'Saved via Quansfer');

      _toast('Guardado en carpeta de la app y compartido');
      return;
    } catch (e2) {
      _toast('Guardado no soportado en esta plataforma y fallback falló: $e2', isError: true);
    }
  } catch (e) {
    _toast('Error al guardar: $e', isError: true);
  }
}


  String _decideEncryptedName(String? headerName) {
    if (headerName != null && headerName.isNotEmpty) return headerName;
    if (_filename != null && _filename!.isNotEmpty) return '${_filename!}.enc';
    return 'file.enc';
  }

  String _decideDecryptedName(String? headerName) {
    if (_filename != null && _filename!.isNotEmpty) return _filename!;
    if (headerName != null && headerName.isNotEmpty) return headerName;
    return 'output.data';
  }

  // -------------------- API calls --------------------
  Future<void> _loadMeta() async {
    final id = _transferIdController.text.trim();
    if (id.isEmpty) return;
    try {
      final r = await _get('/transfer/$id');
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        setState(() => _filename = (data['filename_original'] as String?)?.trim());
      } else {
        _toast('Transfer not found (${r.statusCode})', isError: true);
      }
    } catch (e) {
      _toast('Network error: $e', isError: true);
    }
  }

  Future<void> _downloadEncrypted() async {
    final id = _transferIdController.text.trim();
    if (id.isEmpty) return;

    setState(() => _busy = true);
    try {
      await _ensureMeta(id);

      final r = await _get('/download/$id');
      if (r.statusCode != 200) {
        _toast('Download error: ${r.statusCode} – ${r.body}', isError: true);
        return;
      }

      final headerName = _filenameFromHeaders(r.headers);
      final name = _decideEncryptedName(headerName);

      await _saveWithPicker(Uint8List.fromList(r.bodyBytes), name);
    } catch (e) {
      _toast('Download error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decryptOnServer() async {
    final id = _transferIdController.text.trim();
    if (id.isEmpty) return;

    setState(() => _busy = true);
    try {
      await _ensureMeta(id);

      final r = await _get('/decrypt_by_id/$id');
      if (r.statusCode != 200) {
        _toast('Decrypt error: ${r.statusCode} – ${r.body}', isError: true);
        return;
      }
      final headerName = _filenameFromHeaders(r.headers);
      final outName = _decideDecryptedName(headerName);

      await _saveWithPicker(Uint8List.fromList(r.bodyBytes), outName);
    } catch (e) {
      _toast('Decrypt error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decryptAndShare() async {
    final id = _transferIdController.text.trim();
    if (id.isEmpty) return;

    setState(() => _busy = true);
    try {
      await _ensureMeta(id);

      final r = await _get('/decrypt_by_id/$id');
      if (r.statusCode != 200) {
        _toast('Decrypt/Share error: ${r.statusCode} – ${r.body}', isError: true);
        return;
      }
      final headerName = _filenameFromHeaders(r.headers);
      final outName = _decideDecryptedName(headerName);

      final tmp = await getTemporaryDirectory();
      final f = File('${tmp.path}/$outName');
      await f.writeAsBytes(r.bodyBytes);

      await Share.shareXFiles(
        [XFile(f.path)],
        text: 'Decrypted via Quansfer',
      );
    } catch (e) {
      _toast('Decrypt/Share error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -------------------- UI --------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receiver')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          Text(
            'Use your Transfer ID',
            style: Theme.of(context)
                .textTheme
                .titleMedium!
                .copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _transferIdController,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _loadMeta(),
            decoration: const InputDecoration(
              labelText: 'Transfer ID',
              hintText: 'Paste or type your ID',
            ),
          ),
          const SizedBox(height: 12),

          InfoTile(
            icon: Icons.insert_drive_file,
            title: _filename ?? 'No file metadata',
            subtitle: 'Tap buttons below to download or decrypt.',
          ),
          const SizedBox(height: 16),

          PrimaryButton(
            onPressed: _busy ? null : _downloadEncrypted,
            icon: Icons.download,
            label: 'Download encrypted file',
            loading: _busy,
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            onPressed: _busy ? null : _decryptOnServer,
            icon: Icons.lock_open,
            label: 'Decrypt on server',
            loading: _busy,
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            onPressed: _busy ? null : _decryptAndShare,
            icon: Icons.ios_share,
            label: 'Decrypt & share',
            loading: _busy,
          ),

          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _loadMeta,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh metadata'),
          ),
        ],
      ),
    );
  }
}
