import 'package:flutter/material.dart';

import '../app/app_colors.dart';
import '../services/local_pos_store.dart';
import '../services/sale_sync_service.dart';
import '../utils/cart_manager.dart';
import '../app/app_language.dart';
import '../app/money.dart';
import '../app/app_typography.dart';
import '../app/app_spacing.dart';

/// Cash receipts stay visible until the server confirms their stock deduction.
class SaleSyncPanel extends StatelessWidget {
  const SaleSyncPanel({super.key, this.service, this.inProfile = false});

  final SaleSyncService? service;
  final bool inProfile;

  @override
  Widget build(BuildContext context) {
    final sync = service ?? SaleSyncService.maybeInstance;
    if (sync == null) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: Listenable.merge([sync, CartManager.revision]),
      builder: (context, _) {
        final count = sync.pendingSales.length;
        final conflicts = sync.pendingSales.where((sale) => sale.isConflict).length;
        final draftError = CartManager.saveError;
        final color = conflicts > 0 || draftError != null
            ? AppColors.danger
            : AppColors.primaryDark;
        final status = draftError != null
            ? 'Cart not saved · open Cart to retry'
            : sync.syncing
            ? 'Syncing saved sales...'
            : !sync.online
            ? 'Offline · cash sales saved on this device'
            : conflicts > 0
            ? '$conflicts ${conflicts == 1 ? 'sale needs' : 'sales need'} attention'
            : count > 0
            ? '$count ${count == 1 ? 'sale pending' : 'sales pending'} confirmation'
            : 'Online · sales synchronized';

        // Keep normal navigation quiet; Profile always exposes sync details.
        if (inProfile) {
          return Card(
            child: ListTile(
              leading: Icon(Icons.cloud_sync_outlined, color: color),
              title: Text('Sales sync'.tr),
              subtitle: Text(status),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showPendingSales(context, sync),
            ),
          );
        }
        if (sync.online &&
            count == 0 &&
            !sync.syncing &&
            sync.lastError == null &&
            draftError == null) {
          return const SizedBox.shrink();
        }

        return Material(
          color: conflicts > 0 || draftError != null ? AppColors.dangerSoft : AppColors.soft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(
                  conflicts > 0 || draftError != null
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
                    style: TextStyle(color: color, fontSize: AppTypography.caption),
                  ),
                ),
                TextButton(
                  onPressed: draftError == null
                      ? () => _showPendingSales(context, sync)
                      : () async {
                          try {
                            await CartManager.flush();
                          } catch (_) {
                            /* The visible error remains available for retry. */
                          }
                        },
                  child: Text(draftError == null ? 'Details' : 'Retry'),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Saved cash sales'.tr,
                          style: TextStyle(
                            fontSize: AppTypography.headline,
                            fontWeight: FontWeight.bold,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close'.tr,
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Pending receipts are saved on this device. Stock and sales '
                    'reports are final only after server confirmation.',
                    style: TextStyle(color: AppColors.muted, fontSize: AppTypography.body),
                  ),
                  const SizedBox(height: 12),
                  if (sync.lastError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(sync.lastError!, style: const TextStyle(color: AppColors.danger)),
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
                    label: Text(sync.syncing ? 'Synchronizing...' : 'Check connection & sync'),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: sync.pendingSales.isEmpty
                        ? Center(child: Text('No pending cash sales'.tr))
                        : ListView.separated(
                            itemCount: sync.pendingSales.length,
                            separatorBuilder: (_, index) => const SizedBox(height: 10),
                            itemBuilder: (context, index) =>
                                _PendingSaleCard(pending: sync.pendingSales[index], sync: sync),
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
        borderRadius: BorderRadius.circular(AppSpacing.smallRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(sale.receiptNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            '${MaterialLocalizations.of(context).formatShortDate(sale.createdAt.toLocal())}'
            ' · ${Money.format(sale.total)} · Cash received',
          ),
          const SizedBox(height: 6),
          for (final item in sale.items) Text('${item.quantity} × ${item.name}'),
          const SizedBox(height: 8),
          Text(
            pending.isConflict ? 'Needs attention' : 'Pending server confirmation',
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
              style: TextStyle(fontSize: AppTypography.caption, color: AppColors.muted),
            ),
            TextButton.icon(
              onPressed: sync.syncing ? null : () => sync.retry(sale.id),
              icon: const Icon(Icons.refresh),
              label: Text('Retry after resolving'.tr),
            ),
          ],
        ],
      ),
    );
  }
}
