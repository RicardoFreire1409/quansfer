import 'package:flutter/material.dart';
import '../app_state.dart';

class SettingsPage extends StatefulWidget {
  final AppState appState;
  const SettingsPage({super.key, required this.appState});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _c =
      TextEditingController(text: widget.appState.baseUrl);
  bool _saving = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final v = _c.text.trim();
    if (v.isEmpty || (!v.startsWith('http://') && !v.startsWith('https://'))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incluye http:// o https://')),
      );
      return;
    }
    setState(() => _saving = true);
    await widget.appState.setBaseUrl(v);
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Base URL guardada')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Backend Base URL', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _c,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'http://IP:PUERTO',
              helperText: 'Ej: http://192.168.0.5:8000',
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: const Text('Guardar'),
            ),
          ),
        ],
      ),
    );
  }
}
