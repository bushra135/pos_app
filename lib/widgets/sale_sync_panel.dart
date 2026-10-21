import 'package:flutter/material.dart';

import '../app/app_colors.dart';
import '../services/local_pos_store.dart';
import '../services/sale_sync_service.dart';

/// Cash receipts stay visible until the server confirms their stock deduction.
class SaleSyncPanel extends StatelessWidget {
  const SaleSyncPanel({super.key, this.service});

  final SaleSyncService? service;

  @override
  Widget build(BuildContext context) {
    final sync = service ?? SaleSyncService.maybeInstance;
    if (sync == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final count = sync.pendingSales.length;
        final conflicts = sync.pendingSales
            .where((sale) => sale.isConflict)
            .length;
        final color = conflicts > 0 ? AppColors.danger : AppColors.primaryDark;
        final status = sync.syncing
            ? 'Syncing saved sales...'
            : !sync.online
            ? 'Offline · cash sales saved on this device'
            : conflicts > 0
            ? '$conflicts ${conflicts == 1 ? 'sale needs' : 'sales need'} attention'
            : count > 0
            ? '$count ${count == 1 ? 'sale pending' : 'sales pending'} confirmation'
            : 'Online · sales synchronized';

        return Material(
          color: conflicts > 0 ? AppColors.dangerSoft : AppColors.soft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(
                  conflicts > 0
                      ? Icons.error_outline
                      : sync.online
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status,
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () => _showPendingSales(context, sync),
                  child: const Text('Details'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPendingSales(BuildContext context, SaleSyncService sync) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.8,
          child: ListenableBuilder(
            listenable: sync,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Saved cash sales',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Pending receipts are saved on this device. Stock and sales '
                    'reports are final only after server confirmation.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  if (sync.lastError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        sync.lastError!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: sync.syncing ? null : sync.synchronize,
                    icon: sync.syncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: Text(
                      sync.syncing
                          ? 'Synchronizing...'
                          : 'Check connection & sync',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: sync.pendingSales.isEmpty
                        ? const Center(child: Text('No pending cash sales'))
                        : ListView.separated(
                            itemCount: sync.pendingSales.length,
                            separatorBuilder: (_, index) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) => _PendingSaleCard(
                              pending: sync.pendingSales[index],
                              sync: sync,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingSaleCard extends StatelessWidget {
  const _PendingSaleCard({required this.pending, required this.sync});

  final PendingSale pending;
  final SaleSyncService sync;

  @override
  Widget build(BuildContext context) {
    final sale = pending.sale;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: pending.isConflict ? AppColors.dangerSoft : AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            sale.receiptNumber,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '${MaterialLocalizations.of(context).formatShortDate(sale.createdAt.toLocal())}'
            ' · \$${sale.total.toStringAsFixed(2)} · Cash received',
          ),
          const SizedBox(height: 6),
          for (final item in sale.items)
            Text('${item.quantity} × ${item.name}'),
          const SizedBox(height: 8),
          Text(
            pending.isConflict
                ? 'Needs attention'
                : 'Pending server confirmation',
            style: TextStyle(
              color: pending.isConflict ? AppColors.danger : AppColors.warning,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (pending.isConflict) ...[
            const SizedBox(height: 4),
            Text(pending.conflictMessage!),
            const SizedBox(height: 6),
            const Text(
              'Cash has been received. Ask the manager to resolve the issue, '
              'then retry this receipt.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            TextButton.icon(
              onPressed: sync.syncing ? null : () => sync.retry(sale.id),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry after resolving'),
            ),
          ],
        ],
      ),
    );
  }
}
