import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/backup_service.dart';
import '../../services/sale_sync_service.dart';
import '../../utils/cart_manager.dart';

/// Owner-only workflow: load copies, preview recovery, then call BackupService.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, required this.storeCode});
  final String storeCode;
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  late final BackupService _backupService;
  List<BackupSummary> _backups = [];
  bool _isBusy = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _backupService = BackupService(
      db: FirebaseFirestore.instance,
      currentUid: () => FirebaseAuth.instance.currentUser?.uid,
      hasPendingSales: () async {
        final sync = SaleSyncService.maybeInstance;
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (sync == null || uid == null) return true;
        final pending = await sync.store.pendingSales(uid, widget.storeCode);
        return pending.isNotEmpty || CartManager.items.isNotEmpty;
      },
    );
    _loadBackups();
  }

  Future<void> _runBackupOperation(Future<void> Function() operation) async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      await operation();
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Backup operation did not finish: $e');
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _loadBackups() => _runBackupOperation(() async {
    final rows = await _backupService.listBackups(widget.storeCode);
    if (mounted) setState(() => _backups = rows);
  });

  Future<void> _createBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create cloud backup?'),
        content: const Text(
          'Pause sales on all store devices and synchronize them first. This copies server products, sales and store/payment settings. Unsynchronized sales on other devices are not included. Internet is required.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create backup'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runBackupOperation(() async {
      final summary = await _backupService.createBackup(widget.storeCode);
      if (!mounted) return;
      setState(() => _backups = [summary, ..._backups]);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cloud backup completed')));
    });
  }

  Future<void> _restoreBackup(BackupSummary summary) async {
    var settings = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Preview recovery'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${summary.createdAt.toLocal()}\n${summary.products} products Ã‚| ${summary.sales} sales\n\n'
                  'Only missing records are restored. Existing records stay unchanged. Recovered products start at zero stock and require a physical count. Sales keep their original IDs and are not charged or deducted again.\n\n'
                  'Pause sales on all devices. If interrupted, some records may already be restored; retrying skips them.',
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings,
                  title: const Text(
                    'Also replace store name and BenefitPay settings from this backup',
                  ),
                  onChanged: (value) => update(() => settings = value ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore missing records'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runBackupOperation(() async {
      final result = await _backupService.restoreMissingRecords(
        widget.storeCode,
        summary.id,
        restoreSettings: settings,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Recovery complete'),
          content: Text(
            '${result.products} products and ${result.sales} sales recovered.\nCount recovered product stock before selling. Reopen Profile to refresh restored settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_isBusy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Backup & recovery')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Cloud backups',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Linked to this store account on Firebase. These are manual recovery copies, not iCloud backups or a full database rollback.',
          ),
          const SizedBox(height: 16),
          Text(
            _backups.isEmpty
                ? 'No completed backup loaded'
                : 'Last successful backup: ${_backups.first.createdAt.toLocal()}',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _isBusy ? null : _createBackup,
            icon: const Icon(Icons.backup_outlined),
            label: const Text('Create backup'),
          ),
          TextButton(
            onPressed: _isBusy ? null : _loadBackups,
            child: const Text('Refresh'),
          ),
          if (_isBusy) const LinearProgressIndicator(),
          if (_errorMessage != null)
            SelectableText(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          for (final backup in _backups)
            Card(
              child: ListTile(
                title: Text(
                  backup.createdAt.toLocal().toString().split('.').first,
                ),
                subtitle: Text(
                  '${backup.products} products Ã‚| ${backup.sales} sales',
                ),
                trailing: IconButton(
                  tooltip: 'Preview recovery',
                  onPressed: _isBusy ? null : () => _restoreBackup(backup),
                  icon: const Icon(Icons.restore),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
