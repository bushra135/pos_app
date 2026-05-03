import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../firebase_options.dart';

class CashiersManagementScreen extends StatefulWidget {
  final String storeCode;

  const CashiersManagementScreen({
    super.key,
    required this.storeCode,
  });

  @override
  State<CashiersManagementScreen> createState() =>
      _CashiersManagementScreenState();
}

class _CashiersManagementScreenState extends State<CashiersManagementScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _cashiersStream() {
    return _firestore
        .collection('users')
        .where('storeCode', isEqualTo: widget.storeCode)
        .where('role', isEqualTo: 'cashier')
        .snapshots();
  }

  Future<FirebaseAuth> _cashierCreationAuth() async {
    try {
      final app = Firebase.app('cashierCreation');
      return FirebaseAuth.instanceFor(app: app);
    } on FirebaseException catch (e) {
      if (e.code != 'no-app') rethrow;
    }

    final app = await Firebase.initializeApp(
      name: 'cashierCreation',
      options: DefaultFirebaseOptions.currentPlatform,
    );

    return FirebaseAuth.instanceFor(app: app);
  }

  Future<void> _createCashier() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    final cashierAuth = await _cashierCreationAuth();
    UserCredential? credential;

    try {
      credential = await cashierAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = credential.user!.uid;

      await _firestore.collection('users').doc(uid).set({
        'uid': uid,
        'fullName': name,
        'email': email,
        'role': 'cashier',
        'storeCode': widget.storeCode,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': FirebaseAuth.instance.currentUser?.uid,
      });
    } catch (e) {
      try {
        await credential?.user?.delete();
      } catch (_) {}
      rethrow;
    } finally {
      await cashierAuth.signOut();
    }
  }

  Future<void> _updateCashierStatus(String uid, bool isActive) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'isActive': isActive,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isActive ? 'Cashier activated' : 'Cashier disabled'),
        ),
      );
    } catch (e) {
      debugPrint('Error updating cashier status: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update cashier')),
      );
    }
  }

  Future<void> _showAddCashierDialog() async {
    _nameController.clear();
    _emailController.clear();
    _passwordController.clear();

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
                await _createCashier();

                if (!mounted) return;

                Navigator.of(dialogContext).pop();

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cashier added successfully')),
                );
              } catch (e) {
                debugPrint('Error creating cashier: $e');

                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to add cashier: $e')),
                );

                setDialogState(() => isSaving = false);
              }
            }

            return AlertDialog(
              title: const Text('Add Cashier'),
              content: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          prefixIcon: Icon(Icons.person),
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
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Enter email';
                          }
                          if (!value.contains('@')) {
                            return 'Enter valid email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(Icons.lock),
                        ),
                        validator: (value) {
                          if (value == null || value.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSaving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving ? null : submit,
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        title: const Text('Cashiers'),
        backgroundColor: const Color(0xFF2F80FF),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddCashierDialog,
        backgroundColor: const Color(0xFF2F80FF),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Cashier'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _cashiersStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Failed to load cashiers'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No cashiers yet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();

              final name = data['fullName'] ?? 'Unnamed cashier';
              final email = data['email'] ?? '';
              final isActive = (data['isActive'] ?? false) == true;

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          isActive ? Colors.green.shade100 : Colors.grey[300],
                      child: Icon(
                        Icons.person,
                        color: isActive ? Colors.green : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            isActive ? 'Active' : 'Disabled',
                            style: TextStyle(
                              color: isActive ? Colors.green : Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: isActive,
                      activeColor: Colors.green,
                      onChanged: (value) {
                        _updateCashierStatus(doc.id, value);
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
