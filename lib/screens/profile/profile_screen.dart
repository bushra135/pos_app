import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF39C79A),
                      Color(0xFF2F80FF),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(26),
                    bottomRight: Radius.circular(26),
                  ),
                ),
                child: const Column(
                  children: [
                    CircleAvatar(
                      radius: 42,
                      backgroundColor: Colors.white24,
                      child: Icon(
                        Icons.person_outline,
                        size: 42,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 14),
                    Text(
                      'John Smith',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Owner',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -26),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Column(
                    children: [
                      _InfoRow(
                        icon: Icons.storefront_outlined,
                        iconBg: Color(0xFFE7FAF4),
                        iconColor: Color(0xFF27BFA2),
                        title: 'Store Name',
                        value: 'My Retail Shop',
                      ),
                      SizedBox(height: 16),
                      _InfoRow(
                        icon: Icons.tag_outlined,
                        iconBg: Color(0xFFFFF3E2),
                        iconColor: Color(0xFFF59E0B),
                        title: 'Store Code',
                        value: 'SHOP123',
                      ),
                      SizedBox(height: 16),
                      _InfoRow(
                        icon: Icons.email_outlined,
                        iconBg: Color(0xFFEAF1FF),
                        iconColor: Color(0xFF3B82F6),
                        title: 'Email',
                        value: 'admin@shop.com',
                      ),
                      SizedBox(height: 16),
                      _InfoRow(
                        icon: Icons.phone_outlined,
                        iconBg: Color(0xFFF6EAFE),
                        iconColor: Color(0xFFA855F7),
                        title: 'Phone',
                        value: '+1 (555) 123-4567',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 2),
              const _SettingsCard(),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Column(
                  children: [
                    Text(
                      'AI Assisted Pocket Register',
                      style: TextStyle(
                        fontSize: 15,
                        color: Color(0xFF667085),
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Version 1.0.0',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF98A2B3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  Navigator.pushReplacementNamed(context, '/login');
                },
                child: Container(
                  width: double.infinity,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFEF4444),
                      width: 1.6,
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.logout, color: Color(0xFFEF4444)),
                      SizedBox(width: 10),
                      Text(
                        'Logout',
                        style: TextStyle(
                          color: Color(0xFFEF4444),
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            icon,
            color: iconColor,
            size: 26,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF98A2B3),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  color: Color(0xFF1F2A44),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: const Column(
        children: [
          _SettingItem(
            icon: Icons.settings_outlined,
            iconBg: Color(0xFFF2F4F7),
            iconColor: Color(0xFF667085),
            title: 'Account Settings',
          ),
          Divider(height: 1),
          _SettingItem(
            icon: Icons.notifications_none,
            iconBg: Color(0xFFEAF1FF),
            iconColor: Color(0xFF3B82F6),
            title: 'Notifications',
          ),
          Divider(height: 1),
          _SettingItem(
            icon: Icons.shield_outlined,
            iconBg: Color(0xFFE7FAF0),
            iconColor: Color(0xFF22C55E),
            title: 'Privacy & Security',
          ),
          Divider(height: 1),
          _SettingItem(
            icon: Icons.help_outline,
            iconBg: Color(0xFFF6EAFE),
            iconColor: Color(0xFFA855F7),
            title: 'Help & Support',
          ),
        ],
      ),
    );
  }
}

class _SettingItem extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;

  const _SettingItem({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2A44),
              ),
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: Color(0xFF98A2B3),
          ),
        ],
      ),
    );
  }
}