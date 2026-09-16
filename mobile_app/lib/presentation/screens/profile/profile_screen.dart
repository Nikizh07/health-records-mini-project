import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/locale_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _isEditing = false;
  bool _isSaving = false;

  late TextEditingController _nameController;
  late TextEditingController _dobController;
  String _selectedGender = 'Male';
  DateTime? _selectedDobDate;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _dobController = TextEditingController();
    _populateFields();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  void _populateFields() {
    final profile = ref.read(authNotifierProvider).patientProfile;
    if (profile == null) return;

    _nameController.text = profile['name']?.toString() ?? '';

    // Parse DOB
    final rawDob = profile['dob']?.toString();
    if (rawDob != null && rawDob.isNotEmpty) {
      try {
        final parsed = DateTime.parse(rawDob);
        _selectedDobDate = parsed;
        _dobController.text = DateFormat('yyyy-MM-dd').format(parsed);
      } catch (_) {
        _dobController.text = rawDob.split('T').first;
      }
    }

    final rawGender = profile['gender']?.toString() ?? 'Male';
    if (['Male', 'Female', 'Other'].contains(rawGender)) {
      _selectedGender = rawGender;
    } else {
      _selectedGender = 'Male';
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    if (!_isEditing) return;

    final initialDate = _selectedDobDate ?? DateTime(1995, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF006A6A),
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDobDate = picked;
        _dobController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _handleSaveProfile(AppLocalizations l10n) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final currentLocale = ref.read(localeNotifierProvider);
      final backendLang = localeToBackendCode(currentLocale);

      await ref.read(authNotifierProvider.notifier).updateProfile(
            name: _nameController.text.trim(),
            dob: _dobController.text.trim(),
            gender: _selectedGender,
            languagePref: backendLang,
          );

      if (mounted) {
        setState(() {
          _isEditing = false;
          _isSaving = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text(l10n.profileUpdated),
              ],
            ),
            backgroundColor: const Color(0xFF006A6A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleLanguageChange(Locale newLocale) async {
    // 1. Update UI locale in Riverpod immediately
    ref.read(localeNotifierProvider.notifier).setLocale(newLocale);

    // 2. Persist in backend if patient profile exists
    final authState = ref.read(authNotifierProvider);
    if (authState.patientProfile != null) {
      final langName = localeToBackendCode(newLocale);
      try {
        await ref.read(authNotifierProvider.notifier).updateProfile(
              languagePref: langName,
            );
      } catch (_) {
        // Backend silent fallback
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final l10n = AppLocalizations.of(context)!;
    final currentLocale = ref.watch(localeNotifierProvider);

    final userMap = authState.patientProfile?['user'] as Map<String, dynamic>?;
    final role = (userMap?['role'] ?? authState.patientProfile?['role'] ?? 'PATIENT')
        .toString()
        .toUpperCase();

    final profile = authState.patientProfile ?? {};
    final rawName = profile['name']?.toString() ?? 'User';
    final phone = profile['phone']?.toString() ?? authState.phoneNumber ?? 'N/A';
    final healthId = profile['health_id']?.toString() ?? 'MWH-PENDING';

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileTitle),
        elevation: 0,
        actions: [
          if (role == 'PATIENT' && !_isEditing)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: l10n.editProfile,
              onPressed: () {
                _populateFields();
                setState(() {
                  _isEditing = true;
                });
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Avatar & Identity Banner
            _buildProfileHeader(rawName, role, healthId),
            const SizedBox(height: 20),

            // Task 2: Language Preference Selector Card
            _buildLanguageCard(context, l10n, currentLocale),
            const SizedBox(height: 20),

            // Role-specific Profile Details
            if (role == 'DOCTOR')
              _buildDoctorProfileCard(profile, l10n)
            else if (role == 'ADMIN')
              _buildAdminProfileCard(profile, l10n)
            else
              _buildPatientProfileCard(profile, phone, healthId, l10n),

            // Consent, share code and access history (patients).
            if (ref.watch(authNotifierProvider).can('consent:respond')) ...[
              const SizedBox(height: 20),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined, color: Color(0xFF006A6A)),
                  title: const Text('Privacy & access'),
                  subtitle: const Text('Share code, who can see your history, access log'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/privacy'),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Logout & Account Actions
            _buildAccountActions(context, ref, l10n),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(String name, String role, String healthId) {
    Color badgeColor = const Color(0xFF006A6A);
    IconData roleIcon = Icons.person;
    String displayRole = 'Migrant Worker';

    if (role == 'DOCTOR') {
      badgeColor = const Color(0xFF006D77);
      roleIcon = Icons.medical_services;
      displayRole = 'Medical Doctor';
    } else if (role == 'ADMIN') {
      badgeColor = const Color(0xFF8338EC);
      roleIcon = Icons.admin_panel_settings;
      displayRole = 'Administrator';
    }

    final initials = name.isNotEmpty
        ? name.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join()
        : 'U';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            badgeColor,
            badgeColor.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: badgeColor.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: Colors.white,
            child: Text(
              initials.toUpperCase(),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: badgeColor,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role == 'DOCTOR' && !name.startsWith('Dr.') ? 'Dr. $name' : name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(roleIcon, size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        displayRole,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (role == 'PATIENT') ...[
                  const SizedBox(height: 6),
                  Text(
                    'Health ID: $healthId',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.9),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageCard(
    BuildContext context,
    AppLocalizations l10n,
    Locale currentLocale,
  ) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF006A6A).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.language,
                    color: Color(0xFF006A6A),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.languagePreference,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Change UI language immediately',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _buildLanguageChip(
                  label: 'English',
                  code: 'en',
                  isSelected: currentLocale.languageCode == 'en',
                  onTap: () => _handleLanguageChange(const Locale('en')),
                ),
                const SizedBox(width: 8),
                _buildLanguageChip(
                  label: 'தமிழ்',
                  code: 'ta',
                  isSelected: currentLocale.languageCode == 'ta',
                  onTap: () => _handleLanguageChange(const Locale('ta')),
                ),
                const SizedBox(width: 8),
                _buildLanguageChip(
                  label: 'हिंदी',
                  code: 'hi',
                  isSelected: currentLocale.languageCode == 'hi',
                  onTap: () => _handleLanguageChange(const Locale('hi')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageChip({
    required String label,
    required String code,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF006A6A)
                : const Color(0xFF006A6A).withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF006A6A)
                  : Colors.grey.shade300,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                code.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.8)
                      : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPatientProfileCard(
    Map<String, dynamic> profile,
    String phone,
    String healthId,
    AppLocalizations l10n,
  ) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isEditing ? l10n.editProfile : l10n.accountInfo,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (!_isEditing)
                    TextButton.icon(
                      icon: const Icon(Icons.edit, size: 16),
                      label: Text(l10n.editProfile),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF006A6A),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () {
                        _populateFields();
                        setState(() {
                          _isEditing = true;
                        });
                      },
                    ),
                ],
              ),
              const Divider(height: 24),

              // Full Name (Editable)
              if (_isEditing)
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: '${l10n.name} *',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  validator: (val) {
                    final trimmed = val?.trim() ?? '';
                    if (trimmed.isEmpty) return 'Full Name is required';
                    if (trimmed.length < 2) return 'Name must be at least 2 characters';
                    if (trimmed.length > 80) return 'Name cannot exceed 80 characters';
                    if (!RegExp(r"^[a-zA-Z\s\.\-']+$").hasMatch(trimmed)) {
                      return 'Name can only contain letters, spaces, dots, and hyphens';
                    }
                    return null;
                  },
                )
              else
                _buildInfoRow(
                  icon: Icons.person_outline,
                  label: l10n.name,
                  value: profile['name']?.toString() ?? 'N/A',
                ),

              const SizedBox(height: 14),

              // Date of Birth (Editable with DatePicker)
              if (_isEditing)
                TextFormField(
                  controller: _dobController,
                  readOnly: true,
                  onTap: () => _selectDate(context),
                  decoration: InputDecoration(
                    labelText: '${l10n.dateOfBirth} (YYYY-MM-DD) *',
                    prefixIcon: const Icon(Icons.calendar_today_outlined),
                    suffixIcon: const Icon(Icons.arrow_drop_down),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  validator: (val) {
                    final dob = val?.trim() ?? '';
                    if (dob.isEmpty) return 'Please select your Date of Birth';
                    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dob)) {
                      return 'Date must be in YYYY-MM-DD format';
                    }
                    final parsed = DateTime.tryParse(dob);
                    if (parsed == null) return 'Invalid calendar date';
                    if (parsed.isAfter(DateTime.now())) {
                      return 'Date of birth cannot be in the future';
                    }
                    if (parsed.isBefore(DateTime(1900))) {
                      return 'Please select a valid birth year';
                    }
                    return null;
                  },
                )
              else
                _buildInfoRow(
                  icon: Icons.calendar_today_outlined,
                  label: l10n.dateOfBirth,
                  value: _dobController.text.isNotEmpty
                      ? _dobController.text
                      : (profile['dob']?.toString().split('T').first ?? 'N/A'),
                ),

              const SizedBox(height: 14),

              // Gender (Editable Dropdown)
              if (_isEditing)
                DropdownButtonFormField<String>(
                  initialValue: _selectedGender,
                  decoration: InputDecoration(
                    labelText: '${l10n.gender} *',
                    prefixIcon: const Icon(Icons.wc_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Male', child: Text('Male')),
                    DropdownMenuItem(value: 'Female', child: Text('Female')),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedGender = val;
                      });
                    }
                  },
                )
              else
                _buildInfoRow(
                  icon: Icons.wc_outlined,
                  label: l10n.gender,
                  value: profile['gender']?.toString() ?? 'N/A',
                ),

              const SizedBox(height: 14),

              // Phone Number (Read-only)
              _buildInfoRow(
                icon: Icons.phone_outlined,
                label: l10n.phone,
                value: phone,
                isReadOnly: true,
              ),

              const SizedBox(height: 14),

              // Health ID (Read-only with Copy button)
              _buildInfoRow(
                icon: Icons.badge_outlined,
                label: l10n.healthId,
                value: healthId,
                isReadOnly: true,
                trailing: IconButton(
                  icon: const Icon(Icons.copy, size: 18, color: Color(0xFF006A6A)),
                  tooltip: 'Copy Health ID',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: healthId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Health ID copied to clipboard!'),
                        duration: Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ),

              // Edit Action Controls
              if (_isEditing) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSaving
                            ? null
                            : () {
                                setState(() {
                                  _isEditing = false;
                                  _populateFields();
                                });
                              },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(l10n.cancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : () => _handleSaveProfile(l10n),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF006A6A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(l10n.saveChanges),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDoctorProfileCard(Map<String, dynamic> profile, AppLocalizations l10n) {
    final specialization = profile['specialization'] ??
        profile['doctor']?['specialization'] ??
        'General Medicine & Occupational Health';
    final clinicName = profile['clinic_name'] ??
        profile['clinic']?['name'] ??
        'Central Migrant Health Hub';
    final email = profile['email'] ??
        profile['user']?['email'] ??
        'doctor@migranthealth.org';

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.medical_information_outlined, color: Color(0xFF006D77)),
                const SizedBox(width: 8),
                const Text(
                  'Clinical Practitioner Details',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildInfoRow(
              icon: Icons.psychology_outlined,
              label: l10n.specialization,
              value: specialization.toString(),
            ),
            const SizedBox(height: 14),
            _buildInfoRow(
              icon: Icons.apartment_outlined,
              label: l10n.clinic,
              value: clinicName.toString(),
            ),
            const SizedBox(height: 14),
            _buildInfoRow(
              icon: Icons.email_outlined,
              label: 'Email',
              value: email.toString(),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20, color: Colors.blue.shade800),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Clinical affiliations and shift schedules are managed via the Hospital Administration portal.',
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminProfileCard(Map<String, dynamic> profile, AppLocalizations l10n) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.admin_panel_settings_outlined, color: Color(0xFF8338EC)),
                const SizedBox(width: 8),
                const Text(
                  'System Administrator Profile',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildInfoRow(
              icon: Icons.verified_user_outlined,
              label: 'Access Level',
              value: 'Super Administrator (Full Cluster Read/Write)',
            ),
            const SizedBox(height: 14),
            _buildInfoRow(
              icon: Icons.security_outlined,
              label: 'Audit Status',
              value: 'Active & Logged to Central Security Vault',
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.purple.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, size: 20, color: Colors.purple.shade800),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Admin accounts are authorized to manage clinics, register doctors, and inspect audit trails.',
                      style: TextStyle(fontSize: 12, color: Colors.purple.shade900),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    bool isReadOnly = false,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: Colors.grey.shade700),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (isReadOnly) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.lock_outline, size: 12, color: Colors.grey.shade400),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }

  Widget _buildAccountActions(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.logout, color: Colors.red),
        label: Text(
          l10n.logout,
          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: Colors.red.shade300),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: () => _showLogoutDialog(context, ref, l10n),
      ),
    );
  }

  void _showLogoutDialog(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.logout),
        content: const Text('Are you sure you want to sign out of your account?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              await ref.read(authNotifierProvider.notifier).signOut();
              if (context.mounted) {
                context.go('/login');
              }
            },
            child: Text(l10n.logout),
          ),
        ],
      ),
    );
  }
}
