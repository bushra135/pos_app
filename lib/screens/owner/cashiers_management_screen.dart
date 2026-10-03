import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../utils/app_colors.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_typography.dart';

class CashiersManagementScreen extends StatefulWidget {
  final String storeCode;

  const CashiersManagementScreen({super.key, required this.storeCode});

  @override
  State<CashiersManagementScreen> createState() =>
      _CashiersManagementScreenState();
}

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

  Future<void> _updateCashierStatus({
    required String docId,
    required Map<String, dynamic> data,
    required bool isActive,
  }) async {
    try {
      final uid = (data['uid'] ?? '').toString();
      // Enabling an invite keeps it invited; a registered account becomes active.
      final newStatus = isActive
          ? (uid.isEmpty ? 'invited' : 'active')
          : 'disabled';

      await _firestore.collection('users').doc(docId).update({
        'isActive': isActive,
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isActive ? 'Cashier enabled' : 'Cashier disabled'),
        ),
      );
    } catch (e) {
      debugPrint('Error updating cashier status: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to update cashier')));
    }
  }

  Future<void> _deleteCashier(String docId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Cashier'),
          content: Text('Are you sure you want to delete "$name"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Delete',
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _firestore.collection('users').doc(docId).delete();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cashier deleted')));
    } catch (e) {
      debugPrint('Error deleting cashier: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to delete cashier')));
    }
  }

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

                messenger.showSnackBar(
                  const SnackBar(content: Text('Cashier invited successfully')),
                );
              } catch (e) {
                debugPrint('Error inviting cashier: $e');

                if (!mounted || !context.mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(e.toString().replaceAll('Exception: ', '')),
                  ),
                );

                setDialogState(() => isSaving = false);
              }
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white,
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
                        const Row(
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
                                'Invite Cashier',
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
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'The cashier will set their own password.',
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
                            label: 'Full name',
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
                            label: 'Email',
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
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  side: BorderSide(color: AppColors.border),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text(
                                  'Cancel',
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
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
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
                                    : const Text(
                                        'Invite',
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

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
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
      return const _CashierStatus(
        label: 'Disabled',
        color: AppColors.danger,
        bgColor: AppColors.dangerSoft,
      );
    }

    if (rawStatus == 'invited' || uid.isEmpty) {
      return const _CashierStatus(
        label: 'Invited',
        color: AppColors.warning,
        bgColor: AppColors.warningSoft,
      );
    }

    return const _CashierStatus(
      label: 'Active',
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

      final statusCompare = (statusOrder[aStatus] ?? 3).compareTo(
        statusOrder[bStatus] ?? 3,
      );

      if (statusCompare != 0) return statusCompare;

      return aName.compareTo(bName);
    });

    return sorted;
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      decoration: const BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.white.withValues(alpha: 0.24),
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: AppColors.onBrand,
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cashiers',
                  style: TextStyle(
                    color: AppColors.onBrand,
                    fontSize: AppTypography.title,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Manage cashier access and status',
                  style: TextStyle(
                    color: AppColors.onBrand,
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        16,
        AppSpacing.page,
        8,
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryPill(
              label: 'Active',
              value: '$active',
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SummaryPill(
              label: 'Invited',
              value: '$invited',
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SummaryPill(
              label: 'Disabled',
              value: '$disabled',
              color: AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }

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
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.text.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Row(
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: status.bgColor,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        status.label,
                        style: TextStyle(
                          color: status.color,
                          fontSize: AppTypography.caption,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (uid.isEmpty) ...[
                      const SizedBox(width: 8),
                      const Text(
                        'Waiting setup',
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
          Switch(
            value: isActive,
            activeThumbColor: AppColors.primaryDark,
            onChanged: (value) {
              _updateCashierStatus(docId: doc.id, data: data, isActive: value);
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              if (value == 'delete') {
                _deleteCashier(doc.id, name);
              }
            },
            itemBuilder: (context) {
              return const [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.danger,
                      ),
                      SizedBox(width: 10),
                      Text('Delete', style: TextStyle(color: AppColors.danger)),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
    );
  }

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
              child: const Icon(
                Icons.people_alt_rounded,
                color: AppColors.primaryDark,
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No cashiers yet',
              style: TextStyle(
                fontSize: AppTypography.section,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Invite your first cashier to start managing access.',
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text(
                'Invite Cashier',
                style: TextStyle(
                  fontSize: AppTypography.button,
                  fontWeight: FontWeight.w600,
                ),
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
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
        ),
        child: FloatingActionButton.extended(
          onPressed: _showAddCashierDialog,
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.onBrand,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
          ),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text(
            'Invite Cashier',
            style: TextStyle(
              fontSize: AppTypography.button,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _cashiersStream(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(child: Text('Failed to load cashiers'));
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
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
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
    );
  }
}

class _SummaryPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.text.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
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

class _CashierStatus {
  final String label;
  final Color color;
  final Color bgColor;

  const _CashierStatus({
    required this.label,
    required this.color,
    required this.bgColor,
  });
}
