import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/vault_service.dart';
import '../widgets/confirm_dialog.dart';

/// Credential vault manager mirroring the Electron build: list / reveal /
/// copy / delete entries plus an add & edit form, backed by the OS keyring.
class VaultDialog extends StatefulWidget {
  const VaultDialog({super.key});

  @override
  State<VaultDialog> createState() => _VaultDialogState();
}

class _VaultDialogState extends State<VaultDialog> {
  List<VaultEntry> _entries = [];
  bool _loading = true;
  final Set<String> _revealed = {};
  final Map<String, String> _passwords = {};
  final Set<String> _copied = {};
  String? _pendingDelete;

  bool _showForm = false;
  String? _editingApp; // non-null = editing existing entry
  final _appCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePass = true;
  String? _formError;

  // Unsaved-changes guard: the form is dirty when its contents differ from
  // the snapshot taken when the form was opened / last filled from keyring.
  bool _restoringForm = false;
  String _formSnapshot = '';

  @override
  void initState() {
    super.initState();
    _appCtrl.addListener(_formEdited);
    _userCtrl.addListener(_formEdited);
    _passCtrl.addListener(_formEdited);
    _reload();
  }

  void _formEdited() {
    // Skip while we bulk-fill the form; the enclosing setState refreshes us
    if (!_showForm || _restoringForm || !mounted) return;
    setState(() {});
  }

  String get _formText =>
      '${_appCtrl.text}|${_userCtrl.text}|${_passCtrl.text}';

  bool get _formDirty => _showForm && _formText != _formSnapshot;

  void _captureSnapshot() => _formSnapshot = _formText;

  @override
  void dispose() {
    _appCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final entries = await VaultService.list();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  void _openForm({VaultEntry? entry}) {
    setState(() {
      _showForm = true;
      _editingApp = entry?.appName;
      _restoringForm = true;
      _appCtrl.text = entry?.appName ?? '';
      _userCtrl.text = entry?.username ?? '';
      _passCtrl.text = _passwords[entry?.appName] ?? '';
      _captureSnapshot();
      _restoringForm = false;
      _formError = null;
      _obscurePass = true;
    });
    if (entry != null) {
      _ensurePassword(entry.appName).then((_) {
        if (mounted) {
          setState(() {
            _restoringForm = true;
            _passCtrl.text = _passwords[entry.appName] ?? '';
            _captureSnapshot();
            _restoringForm = false;
          });
        }
      });
    }
  }

  /// Dialog close (X / Esc / barrier) — confirm while the form has edits.
  Future<void> _requestClose() async {
    if (!_formDirty || await confirmDiscardChanges(context)) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<String?> _ensurePassword(String appName) async {
    if (_passwords.containsKey(appName)) return _passwords[appName];
    final cred = await VaultService.get(appName);
    if (cred != null) _passwords[appName] = cred.password;
    return cred?.password;
  }

  Future<void> _saveForm() async {
    final app = _appCtrl.text.trim();
    if (app.isEmpty) {
      setState(() => _formError = 'App name is required');
      return;
    }
    if (_editingApp != null && _editingApp != app) {
      // Renaming — remove the old key so we don't leave a duplicate
      await VaultService.delete(_editingApp!);
    }
    final ok = await VaultService.save(
      appName: app,
      username: _userCtrl.text.trim(),
      password: _passCtrl.text,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _formError = 'Could not reach the system keyring');
      return;
    }
    setState(() {
      _showForm = false;
      _editingApp = null;
      _passwords[app] = _passCtrl.text;
    });
    await _reload();
  }

  Future<void> _copyPassword(String appName) async {
    final password = await _ensurePassword(appName);
    if (password == null) return;
    await Clipboard.setData(ClipboardData(text: password));
    if (!mounted) return;
    setState(() => _copied.add(appName));
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied.remove(appName));
  }

  Widget _row(BuildContext context, VaultEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    final isRevealed = _revealed.contains(entry.appName);
    final isCopied = _copied.contains(entry.appName);
    final pendingDelete = _pendingDelete == entry.appName;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: pendingDelete ? scheme.error : scheme.onSurface.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.vpn_key_outlined, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.appName,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  isRevealed
                      ? '${entry.username.isEmpty ? "•" : entry.username}  ·  ${_passwords[entry.appName] ?? "••••••"}'
                      : entry.username.isEmpty
                          ? '••••••••'
                          : '${entry.username}  ·  ••••••••',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontFamily: isRevealed ? 'monospace' : null,
                    color: scheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: isRevealed ? 'Hide' : 'Reveal',
            icon: Icon(
                isRevealed ? Icons.visibility_off : Icons.visibility,
                size: 17),
            color: scheme.onSurfaceVariant,
            splashRadius: 14,
            onPressed: () async {
              if (!isRevealed) await _ensurePassword(entry.appName);
              setState(() {
                if (isRevealed) {
                  _revealed.remove(entry.appName);
                } else {
                  _revealed.add(entry.appName);
                }
              });
            },
          ),
          IconButton(
            tooltip: isCopied ? 'Copied!' : 'Copy password',
            icon: Icon(isCopied ? Icons.check : Icons.copy, size: 17),
            color: isCopied ? scheme.primary : scheme.onSurfaceVariant,
            splashRadius: 14,
            onPressed: () => _copyPassword(entry.appName),
          ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, size: 17),
            color: scheme.onSurfaceVariant,
            splashRadius: 14,
            onPressed: () => _openForm(entry: entry),
          ),
          IconButton(
            tooltip: pendingDelete ? 'Click again to delete' : 'Delete',
            icon: Icon(pendingDelete ? Icons.delete_forever : Icons.delete_outline,
                size: 17),
            color: pendingDelete ? scheme.error : scheme.onSurfaceVariant,
            splashRadius: 14,
            onPressed: () async {
              if (pendingDelete) {
                await VaultService.delete(entry.appName);
                _passwords.remove(entry.appName);
                if (mounted) setState(() => _pendingDelete = null);
                await _reload();
              } else {
                setState(() => _pendingDelete = entry.appName);
                await Future.delayed(const Duration(seconds: 3));
                if (mounted && _pendingDelete == entry.appName) {
                  setState(() => _pendingDelete = null);
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _form(BuildContext context, {required VoidCallback onCancel}) {
    final scheme = Theme.of(context).colorScheme;

    InputDecoration decoration(String label, {bool isPass = false}) =>
        InputDecoration(
          isDense: true,
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: isPass
              ? IconButton(
                  icon: Icon(
                      _obscurePass ? Icons.visibility : Icons.visibility_off,
                      size: 17),
                  onPressed: () =>
                      setState(() => _obscurePass = !_obscurePass),
                )
              : null,
        );

    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _editingApp == null ? 'New credential' : 'Edit credential',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _appCtrl,
            decoration: decoration('App name (e.g. Gmail)'),
            style: const TextStyle(fontSize: 13.5),
            enabled: _editingApp == null,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _userCtrl,
            decoration: decoration('Username / email'),
            style: const TextStyle(fontSize: 13.5),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _passCtrl,
            obscureText: _obscurePass,
            decoration: decoration('Password', isPass: true),
            style: const TextStyle(fontSize: 13.5),
          ),
          if (_formError != null) ...[
            const SizedBox(height: 8),
            Text(_formError!,
                style: TextStyle(color: scheme.error, fontSize: 12.5)),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saveForm,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_formDirty,
      onPopInvokedWithResult: (didPop, result) {
        // Esc / back gesture / barrier tap with form edits → confirm first
        if (!didPop) _requestClose();
      },
      child: Dialog(
      child: SizedBox(
        width: 560,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
              child: Row(
                children: [
                  Text('Credential Vault',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    splashRadius: 16,
                    onPressed: _requestClose,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
              child: Text(
                'Stored in your system keyring — passwords are never kept in plain text.',
                style: TextStyle(
                    fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (_showForm)
                          _form(context,
                              onCancel: () => setState(() {
                                    _showForm = false;
                                    _editingApp = null;
                                  })),
                        if (_entries.isEmpty && !_showForm)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 60),
                              child: Column(
                                children: [
                                  Icon(Icons.lock_open_outlined,
                                      size: 48, color: scheme.onSurfaceVariant),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No credentials stored yet',
                                    style: TextStyle(
                                        color: scheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        for (final entry in _entries) _row(context, entry),
                      ],
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(
                children: [
                  Text(
                    '${_entries.length} credential${_entries.length == 1 ? '' : 's'}',
                    style:
                        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add credential'),
                    onPressed: () => _openForm(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
