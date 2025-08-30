import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../widgets/brand_logo.dart';
import '../widgets/primary_button.dart';
import '../widgets/info_tile.dart';
import '../services/crypto_service.dart';
import 'receiver_page.dart';
import '../app_state.dart';
import 'settings_page.dart';
class HomePage extends StatefulWidget {
  final AppState appState;
  const HomePage({super.key, required this.appState});
  
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
    String get _baseUrl => widget.appState.baseUrl;

  Uint8List? _fileBytes;
  String? _fileName;
  String? _keyHex;
  bool _busy = false;

  final _crypto = CryptoService();

  Future<void> _getBB84Key() async {
    setState(() => _busy = true);
    try {
        final r = await http.get(Uri.parse('$_baseUrl/qkd/key'));      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        setState(() => _keyHex = data['key_hex'] as String);
        _toast('BB84 key ready.');
      } else {
        _toast('Server error: ${r.statusCode}', isError: true);
      }
    } catch (e) {
      _toast('Network error: $e', isError: true);
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(withData: true);
    if (!mounted) return;
    if (res != null && res.files.isNotEmpty) {
      setState(() {
        _fileBytes = res.files.first.bytes!;
        _fileName  = res.files.first.name;
      });
    }
  }

  Future<void> _encryptAndUpload() async {
    if (_fileBytes == null || _keyHex == null) {
      _toast('Select a file and fetch BB84 key first.', isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      // hex → bytes
      final keyBytes = Uint8List(_keyHex!.length ~/ 2);
      for (var i = 0; i < _keyHex!.length; i += 2) {
        keyBytes[i ~/ 2] = int.parse(_keyHex!.substring(i, i + 2), radix: 16);
      }

      final result = _crypto.encryptBytes(_fileBytes!, keyBytes, _crypto.randomIv());
      final cipher = result['cipher'] as Uint8List;
      final ivB64  = result['ivB64'] as String;

      final req = http.MultipartRequest('POST', Uri.parse('$_baseUrl/upload'))
        ..fields['iv_b64'] = ivB64
        ..fields['key_hex'] = _keyHex!
        ..files.add(http.MultipartFile.fromBytes('file', cipher, filename: '${_fileName ?? 'file'}.enc'));

      final resp = await req.send();
      if (resp.statusCode == 200) {
        final body = await http.Response.fromStream(resp);
        final data = jsonDecode(body.body) as Map<String, dynamic>;
        final transferId = data['transfer_id'] as String;

        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Transfer created'),
            content: SelectableText('Transfer ID:\n$transferId'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
      } else {
        _toast('Upload error: ${resp.statusCode}', isError: true);
      }
    } catch (e) {
      _toast('Encrypt/Upload error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade700 : null,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final canEncrypt = _fileBytes != null && _keyHex != null;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/logo_quansfer.png', height: 28),
            const SizedBox(width: 10),
            const Text('Quansfer'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Receiver',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ReceiverPage(appState: widget.appState)),
            ),
            icon: const Icon(Icons.swap_vert),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SettingsPage(appState: widget.appState)),
            ),
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          const SizedBox(height: 8),
          const BrandLogo(size: 86, showWordmark: false),
          const SizedBox(height: 18),

          Text("Secure file exchange with BB84",
              style: Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text("Generate a quantum-derived key, encrypt locally, and upload safely.",
              style: Theme.of(context).textTheme.bodyMedium),

          const SizedBox(height: 18),
          InfoTile(
            icon: Icons.key,
            title: _keyHex == null ? 'No key yet' : 'BB84 key ready',
            subtitle: _keyHex == null
                ? 'Tap to fetch a fresh shared key from server.'
                : 'A secure key is available for this session.',
          ),
          const SizedBox(height: 10),
          InfoTile(
            icon: Icons.insert_drive_file,
            title: _fileName ?? 'No file selected',
            subtitle: _fileName == null ? 'Pick any file to encrypt & upload.' : 'Ready to encrypt.',
          ),

          const SizedBox(height: 18),
          PrimaryButton(
            onPressed: _busy ? null : _getBB84Key,
            icon: Icons.vpn_key,
            label: '1) Fetch BB84 key',
            loading: _busy && _keyHex == null,
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            onPressed: _busy ? null : _pickFile,
            icon: Icons.attach_file,
            label: '2) Choose file',
            loading: false,
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            onPressed: _busy || !canEncrypt ? null : _encryptAndUpload,
            icon: Icons.lock,
            label: '3) Encrypt & upload',
            loading: _busy && canEncrypt,
          ),

          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: scheme.secondaryContainer.withOpacity(.35),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Keep your Transfer ID safe. You will use it on Receiver to download or decrypt.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
