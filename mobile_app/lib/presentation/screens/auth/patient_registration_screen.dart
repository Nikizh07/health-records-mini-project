import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../providers/auth_provider.dart';

class PatientRegistrationScreen extends ConsumerStatefulWidget {
  const PatientRegistrationScreen({super.key});

  @override
  ConsumerState<PatientRegistrationScreen> createState() => _PatientRegistrationScreenState();
}

class _PatientRegistrationScreenState extends ConsumerState<PatientRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _dobController = TextEditingController();

  String _selectedGender = 'Male';
  String _selectedLanguage = 'Bengali';

  final List<String> _genderOptions = ['Male', 'Female', 'Other'];
  final List<String> _languageOptions = [
    'Bengali',
    'Hindi',
    'English',
    'Tamil',
    'Malayalam',
    'Odia',
    'Telugu',
    'Assamese',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  Future<void> _selectDateOfBirth() async {
    final DateTime now = DateTime.now();
    final DateTime initialDate = DateTime(now.year - 25, 1, 1);
    final DateTime firstDate = DateTime(1940);
    final DateTime lastDate = now;

    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Select Date of Birth',
    );

    if (pickedDate != null) {
      final String formatted =
          '${pickedDate.year.toString().padLeft(4, '0')}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}';
      setState(() {
        _dobController.text = formatted;
      });
    }
  }

  Future<void> _handleSubmit() async {
    if (_formKey.currentState?.validate() ?? false) {
      final success = await ref.read(authNotifierProvider.notifier).registerPatient(
            name: _nameController.text.trim(),
            dob: _dobController.text.trim(),
            gender: _selectedGender,
            languagePref: _selectedLanguage,
          );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile created. Welcome!'),
            backgroundColor: Color(0xFF006A6A),
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.go('/');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Patient Profile'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Card
                    Card(
                      color: const Color(0xFF006A6A).withValues(alpha: 0.08),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            const Icon(Icons.badge_outlined, color: Color(0xFF006A6A), size: 32),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'First Time Registration',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    switch (authState.phoneNumber) {
                                      null || '' || 'guest' => 'Guest account',
                                      final phone => 'Phone: $phone',
                                    },
                                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Full Name Field
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Full Name *',
                        hintText: 'e.g. Rahul Mondal',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (value) {
                        final trimmed = value?.trim() ?? '';
                        if (trimmed.isEmpty) {
                          return 'Full Name is required';
                        }
                        if (trimmed.length < 2) {
                          return 'Name must be at least 2 characters';
                        }
                        if (trimmed.length > 80) {
                          return 'Name cannot exceed 80 characters';
                        }
                        // Any script (Latin, Devanagari, Tamil, ...) — letters + combining marks.
                        if (!RegExp(r"^[\p{L}\p{M}\s.\-']+$", unicode: true).hasMatch(trimmed)) {
                          return 'Name can only contain letters, spaces, dots, and hyphens';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Date of Birth Field
                    TextFormField(
                      controller: _dobController,
                      readOnly: true,
                      onTap: _selectDateOfBirth,
                      decoration: InputDecoration(
                        labelText: 'Date of Birth (YYYY-MM-DD) *',
                        hintText: 'Tap to select DOB',
                        prefixIcon: const Icon(Icons.calendar_month_outlined),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.calendar_today),
                          onPressed: _selectDateOfBirth,
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (value) {
                        final dob = value?.trim() ?? '';
                        if (dob.isEmpty) {
                          return 'Please select your Date of Birth';
                        }
                        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dob)) {
                          return 'Enter valid date format (YYYY-MM-DD)';
                        }
                        final parsed = DateTime.tryParse(dob);
                        if (parsed == null) {
                          return 'Invalid calendar date';
                        }
                        final now = DateTime.now();
                        if (parsed.isAfter(now)) {
                          return 'Date of birth cannot be in the future';
                        }
                        if (parsed.isBefore(DateTime(1900))) {
                          return 'Please select a valid birth year';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Gender Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: _selectedGender,
                      decoration: InputDecoration(
                        labelText: 'Gender *',
                        prefixIcon: const Icon(Icons.transgender_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: _genderOptions.map((g) {
                        return DropdownMenuItem(value: g, child: Text(g));
                      }).toList(),
                      validator: (val) =>
                          (val == null || val.isEmpty) ? 'Please select a gender' : null,
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedGender = val);
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Preferred Language Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: _selectedLanguage,
                      decoration: InputDecoration(
                        labelText: 'Preferred Language *',
                        prefixIcon: const Icon(Icons.translate_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: _languageOptions.map((l) {
                        return DropdownMenuItem(value: l, child: Text(l));
                      }).toList(),
                      validator: (val) =>
                          (val == null || val.isEmpty) ? 'Please select a preferred language' : null,
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedLanguage = val);
                        }
                      },
                    ),

                    const SizedBox(height: 28),

                    // Error Message Banner (if any)
                    if (authState.errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(
                          authState.errorMessage!,
                          style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Submit Button
                    FilledButton(
                      onPressed: authState.isLoading ? null : _handleSubmit,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF006A6A),
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: authState.isLoading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Save & Go to Dashboard',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
