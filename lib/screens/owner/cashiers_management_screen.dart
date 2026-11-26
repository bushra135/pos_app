import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app/app_colors.dart';
import '../../app/app_spacing.dart';
import '../../app/app_typography.dart';
import '../../app/app_language.dart';
import '../../widgets/adaptive_layout.dart';

/// Manages store cashier profiles; account access and on-duty availability are separate.
class CashiersManagementScreen extends StatefulWidget {
  final String storeCode;

  const CashiersManagementScreen({super.key, required this.storeCode});

  @override
  State<CashiersManagementScreen> createState() => _CashiersManagementScreenState();
}

/// Lists the store's cashiers live and lets the owner invite, approve, disable,
/// delete them and set their permissions.
class _CashiersManagementScreenState extends State<CashiersManagementScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _cashiersStream() {
    return _firestore
        .collection('users')
        .where('storeCode', isEqualTo: widget.storeCode)
        .where('role', isEqualTo: 'cashier')
        .snapshots();
  }

  /// Saves an invite for a new cashier email; throws if that email is already in the store.
  Future<void> _createCashierInvite() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();

    final existingSnapshot = await _firestore
        .collection('users')
        .where('storeCode', isEqualTo: widget.storeCode)
        .where('role', isEqualTo: 'cashier')
        .get();

    final emailExists = existingSnapshot.docs.any((doc) {
      final data = doc.data();
      return (data['email'] ?? '').toString().toLowerCase() == email;
    });

    if (emailExists) {
      throw Exception('This cashier already exists');
    }

    // Store invites as separate users documents; an empty uid marks an unregistered account.
    await _firestore.collection('users').add({
      'uid': '',
      'fullName': name,
      'email': email,
      'role': 'cashier',
      'storeCode': widget.storeCode,
      'isActive': true,
      'status': 'invited',
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': FirebaseAuth.instance.currentUser?.uid,
    });
  }

  /// The owner decides, per cashier, whether they may change products/prices and stock.
  /// Firestore rules enforce the same flags, so hiding buttons is not the only guard.
  Future<void> _updatePermission(String docId, String field, bool value) async {
    try {
      await _firestore.collection('users').doc(docId).update({
        field: value,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error updating cashier permission: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update cashier'.tr)));
    }
  }

  /// A switch for one cashier permission (edit products, adjust stock), saved immediately.
  Widget _permissionSwitch({
    required String docId,
    required String field,
    required bool value,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: value,
      activeThumbColor: AppColors.primaryDark,
      onChanged: (next) => _updatePermission(docId, field, next),
      secondary: Icon(icon, color: value ? AppColors.primaryDark : AppColors.muted, size: 22),
      title: Text(
        title.tr,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: AppTypography.body),
      ),
      subtitle: Text(
        subtitle.tr,
        style: const TextStyle(color: AppColors.muted, fontSize: AppTypography.caption),
      ),
    );
  }

  /// Turns a cashier on or off. Enabling a registered account makes it active;
  /// an invite that has not signed up yet stays invited.
  Future<void> _updateCashierStatus({
    required String docId,
    required Map<String, dynamic> data,
    required bool isActive,
  }) async {
    try {
      final uid = (data['uid'] ?? '').toString();
      // Enabling an invite keeps it invited; a registered account becomes active.
      final newStatus = isActive ? (uid.isEmpty ? 'invited' : 'active') : 'disabled';

      await _firestore.collection('users').doc(docId).update({
        'isActive': isActive,
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((isActive ? 'Cashier enabled' : 'Cashier disabled').tr)),
      );
    } catch (e) {
      debugPrint('Error updating cashier status: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update cashier'.tr)));
    }
  }

  /// Asks for confirmation, then deletes the cashier's record from the store.
  Future<void> _deleteCashier(String docId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Delete cashier'.tr),
          content: Text('Are you sure you want to delete "{name}"?'.trArgs({'name': name})),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel'.tr)),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Delete'.tr, style: TextStyle(color: AppColors.danger)),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _firestore.collection('users').doc(docId).delete();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cashier deleted'.tr)));
    } catch (e) {
      debugPrint('Error deleting cashier: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete cashier'.tr)));
    }
  }

  /// Dialog with name and email fields that creates a cashier invite.
  Future<void> _showAddCashierDialog() async {
    _nameController.clear();
    _emailController.clear();

    bool isSaving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (!_formKey.currentState!.validate()) return;

              setDialogState(() => isSaving = true);

              try {
                await _createCashierInvite();

                if (!mounted || !context.mounted || !dialogContext.mounted) {
                  return;
                }
                final messenger = ScaffoldMessenger.of(context);
                Navigator.of(dialogContext).pop();

                messenger.showSnackBar(SnackBar(content: Text('Cashier invited successfully'.tr)));
              } catch (e) {
                debugPrint('Error inviting cashier: $e');

                if (!mounted || !context.mounted) return;

                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));

                setDialogState(() => isSaving = false);
              }
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.text.withValues(alpha: 0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: AppColors.soft,
                              child: Icon(
                                Icons.person_add_alt_1_rounded,
                                color: AppColors.primaryDark,
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Invite cashier'.tr,
                                style: TextStyle(
                                  fontSize: AppTypography.title,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.text,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'The cashier will set their own password.'.tr,
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: AppTypography.body,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _nameController,
                          decoration: _inputDecoration(
                            label: 'Full name'.tr,
                            icon: Icons.person_rounded,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Enter cashier name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: _inputDecoration(
                            label: 'Email'.tr,
                            icon: Icons.email_rounded,
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';

                            if (email.isEmpty) return 'Enter email';
                            if (!email.contains('@') || !email.contains('.')) {
                              return 'Enter valid email';
                            }

                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: isSaving
                                    ? null
                                    : () => Navigator.of(dialogContext).pop(),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  side: BorderSide(color: AppColors.border),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                                  ),
                                ),
                                child: Text(
                                  'Cancel'.tr,
                                  style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: AppTypography.button,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: isSaving ? null : submit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                                  ),
                                ),
                                child: isSaving
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: AppColors.onBrand,
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : Text(
                                        'Invite'.tr,
                                        style: TextStyle(
                                          color: AppColors.onBrand,
                                          fontSize: AppTypography.button,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Filled, borderless field style used in the invite dialog.
  InputDecoration _inputDecoration({required String label, required IconData icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
        borderSide: BorderSide.none,
      ),
    );
  }

  _CashierStatus _statusFrom(Map<String, dynamic> data) {
    final rawStatus = (data['status'] ?? '').toString().toLowerCase();
    final isActive = (data['isActive'] ?? false) == true;
    final uid = (data['uid'] ?? '').toString();

    // Disabled status takes priority over invite details or an existing uid.
    if (!isActive || rawStatus == 'disabled') {
      return _CashierStatus(
        label: 'Disabled'.tr,
        color: AppColors.danger,
        bgColor: AppColors.dangerSoft,
      );
    }

    if (rawStatus == 'invited' || uid.isEmpty) {
      return _CashierStatus(
        label: 'Invited'.tr,
        color: AppColors.warning,
        bgColor: AppColors.warningSoft,
      );
    }

    return _CashierStatus(
      label: 'Active'.tr,
      color: AppColors.success,
      bgColor: AppColors.successSoft,
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortedDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sorted = [...docs];
    const statusOrder = {'Active': 0, 'Invited': 1, 'Disabled': 2};

    sorted.sort((a, b) {
      final aStatus = _statusFrom(a.data()).label;
      final bStatus = _statusFrom(b.data()).label;
      final aName = (a.data()['fullName'] ?? '').toString().toLowerCase();
      final bName = (b.data()['fullName'] ?? '').toString().toLowerCase();

      final statusCompare = (statusOrder[aStatus] ?? 3).compareTo(statusOrder[bStatus] ?? 3);

      if (statusCompare != 0) return statusCompare;

      return aName.compareTo(bName);
    });

    return sorted;
  }

  /// Back button, title and short explanation at the top of the screen.
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      decoration: const BoxDecoration(color: AppColors.background),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.surface,
            child: IconButton(
              tooltip: 'Back'.tr,
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded, color: AppColors.text),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cashiers'.tr,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: AppTypography.metric,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Manage cashier access and status'.tr,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: AppTypography.body,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Counts of active, invited and disabled cashiers.
  Widget _buildSummary(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    int active = 0;
    int invited = 0;
    int disabled = 0;

    for (final doc in docs) {
      final status = _statusFrom(doc.data()).label;

      if (status == 'Active') active++;
      if (status == 'Invited') invited++;
      if (status == 'Disabled') disabled++;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, 16, AppSpacing.page, 8),
      child: Row(
        children: [
          Expanded(
            child: _SummaryPill(label: 'Active'.tr, value: '$active', color: AppColors.success),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SummaryPill(label: 'Invited'.tr, value: '$invited', color: AppColors.warning),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SummaryPill(label: 'Disabled'.tr, value: '$disabled', color: AppColors.danger),
          ),
        ],
      ),
    );
  }

  /// One cashier: name, email, status, on/off switch, permissions and delete.
  Widget _buildCashierCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();

    final name = (data['fullName'] ?? 'Unnamed cashier').toString();
    final email = (data['email'] ?? '').toString();
    final uid = (data['uid'] ?? '').toString();
    final isActive = (data['isActive'] ?? false) == true;
    final status = _statusFrom(data);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: status.bgColor,
                child: Icon(
                  status.label == 'Invited'
                      ? Icons.mark_email_unread_rounded
                      : Icons.person_rounded,
                  color: status.color,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppTypography.label,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: AppTypography.body,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: status.bgColor,
                            borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
                          ),
                          child: Text(
                            status.label.tr,
                            style: TextStyle(
                              color: status.color,
                              fontSize: AppTypography.caption,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (uid.isEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            'Waiting setup'.tr,
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: AppTypography.caption,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                // Own node, so a screen reader announces just this switch, not the whole card.
                container: true,
                label: 'Account active'.tr,
                child: Switch(
                  value: isActive,
                  activeThumbColor: AppColors.primaryDark,
                  onChanged: (value) {
                    _updateCashierStatus(docId: doc.id, data: data, isActive: value);
                  },
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) {
                  if (value == 'delete') {
                    _deleteCashier(doc.id, name);
                  }
                },
                itemBuilder: (context) {
                  return [
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                          SizedBox(width: 10),
                          Text('Delete'.tr, style: TextStyle(color: AppColors.danger)),
                        ],
                      ),
                    ),
                  ];
                },
              ),
            ],
          ),
          const Divider(height: 20),
          Text(
            'What this cashier can do'.tr,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: AppTypography.caption,
              color: AppColors.muted,
            ),
          ),
          _permissionSwitch(
            docId: doc.id,
            field: 'canEditProducts',
            value: data['canEditProducts'] == true,
            icon: Icons.sell_outlined,
            title: 'Change products and prices',
            subtitle: 'Edit names, prices and details, and delete products',
          ),
          _permissionSwitch(
            docId: doc.id,
            field: 'canAdjustStock',
            value: data['canAdjustStock'] == true,
            icon: Icons.inventory_2_outlined,
            title: 'Adjust stock',
            subtitle: 'Restock and correct counts; every change is recorded for you',
          ),
        ],
      ),
    );
  }

  /// Shown when the store has no cashiers yet, with an invite button.
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.soft,
                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              ),
              child: const Icon(Icons.people_alt_rounded, color: AppColors.primaryDark, size: 34),
            ),
            const SizedBox(height: 16),
            Text(
              'No cashiers yet'.tr,
              style: TextStyle(
                fontSize: AppTypography.section,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Invite your first cashier to start managing access.'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.muted,
                fontSize: AppTypography.body,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _showAddCashierDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onBrand,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                ),
              ),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text(
                'Invite cashier'.tr,
                style: TextStyle(fontSize: AppTypography.button, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: DecoratedBox(
        decoration: const BoxDecoration(),
        child: FloatingActionButton.extended(
          onPressed: _showAddCashierDialog,
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onBrand,
          shape: const StadiumBorder(),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: Text(
            'Invite cashier'.tr,
            style: TextStyle(fontSize: AppTypography.button, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      body: SafeArea(
        child: ContentWidth(
          maxWidth: 720,
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _cashiersStream(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(child: Text('Failed to load cashiers'.tr));
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final docs = _sortedDocs(snapshot.data?.docs ?? []);

                    if (docs.isEmpty) {
                      return _buildEmptyState();
                    }

                    return Column(
                      children: [
                        _buildSummary(docs),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.page,
                              8,
                              AppSpacing.page,
                              96,
                            ),
                            itemCount: docs.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              return _buildCashierCard(docs[index]);
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Coloured pill with a count, used in the status summary.
class _SummaryPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryPill({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: AppTypography.metric,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: AppTypography.caption,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Display label and colours for a cashier's status.
class _CashierStatus {
  final String label;
  final Color color;
  final Color bgColor;

  const _CashierStatus({required this.label, required this.color, required this.bgColor});
}
