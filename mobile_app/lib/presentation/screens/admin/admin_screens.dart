import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/appointment_provider.dart';
import '../../../providers/auth_provider.dart';

// ============================================================================
// 3. ADMIN "MANAGE DOCTORS" SCREEN (Day 20 - Task 3)
// ============================================================================

class AdminManageDoctorsScreen extends ConsumerStatefulWidget {
  const AdminManageDoctorsScreen({super.key});

  @override
  ConsumerState<AdminManageDoctorsScreen> createState() => _AdminManageDoctorsScreenState();
}

class _AdminManageDoctorsScreenState extends ConsumerState<AdminManageDoctorsScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final userMap = authState.patientProfile?['user'] as Map<String, dynamic>?;
    final role = (userMap?['role'] ?? authState.patientProfile?['role'] ?? 'PATIENT')
        .toString()
        .toUpperCase();

    // Guard: ADMIN only
    if (role != 'ADMIN') {
      return Scaffold(
        appBar: AppBar(title: const Text('Manage Doctors')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline, size: 64, color: Colors.redAccent),
                const SizedBox(height: 16),
                const Text(
                  'Access Restricted',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'This console is only accessible to System Administrators (ADMIN role). Your current role is $role.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to Dashboard'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final doctorsAsync = ref.watch(adminDoctorsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Doctor Directory'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Doctors',
            onPressed: () => ref.invalidate(adminDoctorsProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search & Filter Bar ───────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by doctor name or specialization...',
                prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF8338EC)),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF8338EC).withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val.trim().toLowerCase();
                });
              },
            ),
          ),

          // ── Doctors List ──────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(adminDoctorsProvider);
              },
              child: doctorsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: Color(0xFF8338EC)),
                ),
                error: (err, stack) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                        const SizedBox(height: 12),
                        const Text(
                          'Failed to load doctors',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          err.toString().replaceAll('Exception: ', ''),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => ref.invalidate(adminDoctorsProvider),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (doctors) {
                  final filtered = doctors.where((doc) {
                    final name = (doc['name'] ?? '').toString().toLowerCase();
                    final spec = (doc['specialization'] ?? '').toString().toLowerCase();
                    final clinicName = (doc['clinic']?['name'] ?? '').toString().toLowerCase();
                    return name.contains(_searchQuery) ||
                        spec.contains(_searchQuery) ||
                        clinicName.contains(_searchQuery);
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8338EC).withValues(alpha: 0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.medical_services_outlined,
                                  size: 56,
                                  color: Color(0xFF8338EC),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'No doctors matching "$_searchQuery"'
                                    : 'No Doctors Registered Yet',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2B2D42),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'Try adjusting your search terms.'
                                    : 'Tap the button below to onboard the first doctor.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final doc = filtered[index];
                      return _DoctorDirectoryCard(doctor: doc);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddDoctorModal(context),
        backgroundColor: const Color(0xFF8338EC),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add Doctor'),
      ),
    );
  }

  void _openAddDoctorModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _AddDoctorModalSheet(),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Doctor Card in Directory
// ────────────────────────────────────────────────────────────────────────────

class _DoctorDirectoryCard extends StatelessWidget {
  final Map<String, dynamic> doctor;

  const _DoctorDirectoryCard({required this.doctor});

  @override
  Widget build(BuildContext context) {
    final rawName = doctor['name']?.toString() ?? 'Doctor';
    final displayName = rawName.startsWith('Dr.') ? rawName : 'Dr. $rawName';
    final spec = doctor['specialization']?.toString() ?? 'General Practice';
    final phone = doctor['phone']?.toString() ?? 'No phone';
    final clinic = doctor['clinic'] as Map<String, dynamic>? ?? {};
    final clinicName = clinic['name']?.toString() ?? 'Unassigned Clinic';
    final clinicLocation = clinic['location']?.toString() ?? '';

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
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFF8338EC).withValues(alpha: 0.1),
                  child: const Icon(
                    Icons.medical_services_outlined,
                    color: Color(0xFF8338EC),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2B2D42),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8338EC).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          spec,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF8338EC),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Clinic assignment
            Row(
              children: [
                const Icon(Icons.apartment, size: 16, color: Color(0xFF8338EC)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    clinicLocation.isNotEmpty
                        ? '$clinicName • $clinicLocation'
                        : clinicName,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Phone
            Row(
              children: [
                Icon(Icons.phone_outlined, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  phone,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Add Doctor Modal Sheet
// ────────────────────────────────────────────────────────────────────────────

class _AddDoctorModalSheet extends ConsumerStatefulWidget {
  const _AddDoctorModalSheet();

  @override
  ConsumerState<_AddDoctorModalSheet> createState() => _AddDoctorModalSheetState();
}

class _AddDoctorModalSheetState extends ConsumerState<_AddDoctorModalSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _specializationController = TextEditingController();
  final _phoneController = TextEditingController();

  String? _selectedClinicId;
  bool _isSaving = false;

  final List<String> _commonSpecializations = [
    'General Practice',
    'Internal Medicine',
    'Dermatology',
    'Occupational Health',
    'Emergency Care',
    'Orthopedics',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _specializationController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submitNewDoctor() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedClinicId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a clinic for the doctor.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final token = ref.read(authTokenProvider);
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not authenticated.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final adminService = ref.read(adminServiceProvider);
      await adminService.createDoctor(
        idToken: token,
        name: _nameController.text.trim(),
        clinicId: _selectedClinicId!,
        specialization: _specializationController.text.trim(),
        phone: _phoneController.text.trim(),
      );

      // Invalidate both doctor providers
      ref.invalidate(adminDoctorsProvider);
      ref.invalidate(clinicsProvider);

      if (!mounted) return;
      Navigator.pop(context); // Close bottom sheet

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 Doctor "${_nameController.text.trim()}" onboarded successfully!'),
          backgroundColor: const Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final clinicsAsync = ref.watch(adminClinicsProvider);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Modal Handle & Title
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.person_add_alt_1, color: Color(0xFF8338EC)),
                  SizedBox(width: 10),
                  Text(
                    'Onboard New Doctor',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2B2D42),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Register a licensed doctor and link them to an active clinic branch.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),

              // ── 1. Doctor Name ────────────────────────────────────
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Doctor Full Name *',
                  hintText: 'e.g. Sarah Lee or Dr. Rajan',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                validator: (val) {
                  if (val == null || val.trim().length < 2) {
                    return 'Please enter a valid name (at least 2 characters)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // ── 2. Specialization & Suggestions ───────────────────
              TextFormField(
                controller: _specializationController,
                decoration: InputDecoration(
                  labelText: 'Medical Specialization *',
                  hintText: 'e.g. General Practice, Dermatology',
                  prefixIcon: const Icon(Icons.medical_information_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                validator: (val) {
                  if (val == null || val.trim().length < 2) {
                    return 'Specialization is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),

              // Quick Specialization Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _commonSpecializations.map((spec) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: ActionChip(
                        label: Text(spec),
                        labelStyle: const TextStyle(fontSize: 11),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Colors.grey.shade100,
                        onPressed: () {
                          _specializationController.text = spec;
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),

              // ── 3. Assigned Clinic Dropdown ───────────────────────
              clinicsAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (e, _) => Text(
                  'Failed to load clinics: $e',
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
                data: (clinics) {
                  if (clinics.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: const Text(
                        'No clinics available. Please register a clinic first.',
                        style: TextStyle(color: Colors.brown, fontSize: 12),
                      ),
                    );
                  }

                  return DropdownButtonFormField<String>(
                    initialValue: _selectedClinicId,
                    decoration: InputDecoration(
                      labelText: 'Assign to Clinic *',
                      prefixIcon: const Icon(Icons.apartment_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    items: clinics.map((c) {
                      final id = c['id']?.toString() ?? '';
                      final name = c['name']?.toString() ?? 'Clinic';
                      final location = c['location']?.toString() ?? '';
                      return DropdownMenuItem<String>(
                        value: id,
                        child: Text(
                          location.isNotEmpty ? '$name ($location)' : name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedClinicId = val;
                      });
                    },
                    validator: (val) => val == null ? 'Please select a clinic' : null,
                  );
                },
              ),
              const SizedBox(height: 16),

              // ── 4. Contact Phone Number ───────────────────────────
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone Number *',
                  hintText: 'e.g. +919876543210 or +60123456789',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                validator: (val) {
                  if (val == null || val.trim().length < 5) {
                    return 'Please enter a valid phone number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // ── 5. Submit Button ─────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _submitNewDoctor,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check),
                  label: Text(_isSaving ? 'Registering...' : 'Register Doctor'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8338EC),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
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

// ============================================================================
// 4. ADMIN "MANAGE CLINICS" SCREEN (Day 20 - Task 4)
// ============================================================================

class AdminManageClinicsScreen extends ConsumerStatefulWidget {
  const AdminManageClinicsScreen({super.key});

  @override
  ConsumerState<AdminManageClinicsScreen> createState() => _AdminManageClinicsScreenState();
}

class _AdminManageClinicsScreenState extends ConsumerState<AdminManageClinicsScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final userMap = authState.patientProfile?['user'] as Map<String, dynamic>?;
    final role = (userMap?['role'] ?? authState.patientProfile?['role'] ?? 'PATIENT')
        .toString()
        .toUpperCase();

    // Guard: ADMIN only
    if (role != 'ADMIN') {
      return Scaffold(
        appBar: AppBar(title: const Text('Manage Clinics')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline, size: 64, color: Colors.redAccent),
                const SizedBox(height: 16),
                const Text(
                  'Access Restricted',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'This console is only accessible to System Administrators (ADMIN role). Your current role is $role.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to Dashboard'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final clinicsAsync = ref.watch(adminClinicsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Clinic Facilities'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Clinics',
            onPressed: () => ref.invalidate(adminClinicsProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search Bar ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search clinic name or location...',
                prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF8338EC)),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF8338EC).withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val.trim().toLowerCase();
                });
              },
            ),
          ),

          // ── Clinics List ──────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(adminClinicsProvider);
              },
              child: clinicsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: Color(0xFF8338EC)),
                ),
                error: (err, stack) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                        const SizedBox(height: 12),
                        const Text(
                          'Failed to load clinics',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          err.toString().replaceAll('Exception: ', ''),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => ref.invalidate(adminClinicsProvider),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (clinics) {
                  final filtered = clinics.where((c) {
                    final name = (c['name'] ?? '').toString().toLowerCase();
                    final loc = (c['location'] ?? '').toString().toLowerCase();
                    return name.contains(_searchQuery) || loc.contains(_searchQuery);
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8338EC).withValues(alpha: 0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.apartment,
                                  size: 56,
                                  color: Color(0xFF8338EC),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'No clinics matching "$_searchQuery"'
                                    : 'No Clinics Available',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2B2D42),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'Try searching with a different name or location.'
                                    : 'Clinic facilities will appear here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final clinic = filtered[index];
                      return _ClinicFacilityCard(
                        clinic: clinic,
                        onEdit: () => _openEditClinicModal(context, clinic),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openEditClinicModal(BuildContext context, Map<String, dynamic> clinic) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditClinicModalSheet(clinic: clinic),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Clinic Facility Card Widget
// ────────────────────────────────────────────────────────────────────────────

class _ClinicFacilityCard extends StatelessWidget {
  final Map<String, dynamic> clinic;
  final VoidCallback onEdit;

  const _ClinicFacilityCard({
    required this.clinic,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final name = clinic['name']?.toString() ?? 'Clinic';
    final location = clinic['location']?.toString() ?? 'Location N/A';
    final contactNumber = clinic['contact_number']?.toString() ?? 'No phone';
    final lat = clinic['latitude'];
    final lng = clinic['longitude'];

    final hasCoordinates = lat != null && lng != null;

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
            // Top: Name + GPS Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFF8338EC).withValues(alpha: 0.1),
                  child: const Icon(Icons.apartment, color: Color(0xFF8338EC), size: 24),
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
                          color: Color(0xFF2B2D42),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: hasCoordinates ? Colors.green.shade50 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: hasCoordinates ? Colors.green.shade200 : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 12,
                              color: hasCoordinates ? Colors.green.shade700 : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              hasCoordinates ? '$lat, $lng' : 'GPS coordinates not set',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: hasCoordinates ? Colors.green.shade800 : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Location
            Row(
              children: [
                Icon(Icons.place_outlined, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    location,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Contact Number
            Row(
              children: [
                Icon(Icons.phone_outlined, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  contactNumber,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Edit Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF8338EC)),
                label: const Text(
                  'Edit Clinic Details',
                  style: TextStyle(color: Color(0xFF8338EC), fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF8338EC)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Edit Clinic Modal Sheet
// ────────────────────────────────────────────────────────────────────────────

class _EditClinicModalSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> clinic;

  const _EditClinicModalSheet({required this.clinic});

  @override
  ConsumerState<_EditClinicModalSheet> createState() => _EditClinicModalSheetState();
}

class _EditClinicModalSheetState extends ConsumerState<_EditClinicModalSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _locationController;
  late final TextEditingController _contactController;
  late final TextEditingController _latController;
  late final TextEditingController _lngController;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.clinic['name']?.toString() ?? '');
    _locationController =
        TextEditingController(text: widget.clinic['location']?.toString() ?? '');
    _contactController =
        TextEditingController(text: widget.clinic['contact_number']?.toString() ?? '');
    _latController =
        TextEditingController(text: widget.clinic['latitude']?.toString() ?? '');
    _lngController =
        TextEditingController(text: widget.clinic['longitude']?.toString() ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _contactController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  Future<void> _submitClinicUpdate() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final token = ref.read(authTokenProvider);
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not authenticated.')),
      );
      return;
    }

    final clinicId = widget.clinic['id']?.toString() ?? '';
    if (clinicId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clinic ID is missing.')),
      );
      return;
    }

    // Parse lat/lng
    double? latitude;
    double? longitude;
    if (_latController.text.trim().isNotEmpty) {
      latitude = double.tryParse(_latController.text.trim());
    }
    if (_lngController.text.trim().isNotEmpty) {
      longitude = double.tryParse(_lngController.text.trim());
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final adminService = ref.read(adminServiceProvider);
      await adminService.updateClinic(
        idToken: token,
        clinicId: clinicId,
        name: _nameController.text.trim(),
        location: _locationController.text.trim(),
        contactNumber: _contactController.text.trim(),
        latitude: latitude,
        longitude: longitude,
      );

      // Invalidate providers so patient appointment booking and admin lists refresh
      ref.invalidate(adminClinicsProvider);
      ref.invalidate(clinicsProvider);
      ref.invalidate(adminDoctorsProvider);

      if (!mounted) return;
      Navigator.pop(context); // Close bottom sheet

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Clinic "${_nameController.text.trim()}" updated successfully!'),
          backgroundColor: const Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle & Header
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.edit_location_alt, color: Color(0xFF8338EC)),
                  SizedBox(width: 10),
                  Text(
                    'Edit Clinic Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2B2D42),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Update clinic name, address, contact, and GPS coordinates for distance sorting.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),

              // ── 1. Clinic Name ────────────────────────────────────
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Clinic Name *',
                  prefixIcon: const Icon(Icons.apartment),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                validator: (val) {
                  if (val == null || val.trim().length < 2) {
                    return 'Clinic name must be at least 2 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // ── 2. Clinic Location / Address ──────────────────────
              TextFormField(
                controller: _locationController,
                decoration: InputDecoration(
                  labelText: 'Location / Physical Address *',
                  hintText: 'e.g. Block 4, Puchong Industrial Area',
                  prefixIcon: const Icon(Icons.place_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                validator: (val) {
                  if (val == null || val.trim().length < 2) {
                    return 'Location is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // ── 3. Contact Number ─────────────────────────────────
              TextFormField(
                controller: _contactController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Contact Phone Number *',
                  hintText: 'e.g. +60123456789',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                validator: (val) {
                  if (val == null || val.trim().length < 5) {
                    return 'Please enter a valid contact number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // ── 4. GPS Coordinates ────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: InputDecoration(
                        labelText: 'Latitude',
                        hintText: 'e.g. 3.0333',
                        prefixIcon: const Icon(Icons.my_location, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      validator: (val) {
                        if (val != null && val.trim().isNotEmpty) {
                          if (double.tryParse(val.trim()) == null) {
                            return 'Invalid number';
                          }
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lngController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: InputDecoration(
                        labelText: 'Longitude',
                        hintText: 'e.g. 101.6167',
                        prefixIcon: const Icon(Icons.my_location, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      validator: (val) {
                        if (val != null && val.trim().isNotEmpty) {
                          if (double.tryParse(val.trim()) == null) {
                            return 'Invalid number';
                          }
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── 5. Submit Button ─────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _submitClinicUpdate,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_isSaving ? 'Updating...' : 'Save Clinic Details'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8338EC),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
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

