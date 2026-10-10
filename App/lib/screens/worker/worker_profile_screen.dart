import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/worker_model.dart';
import '../../models/worker_services_data.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/worker_colors.dart';
import '../../widgets/verified_badge.dart';
import '../../widgets/verification_form.dart';
import '../../widgets/availability_confirm_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WorkerProfileScreen extends StatefulWidget {
  final WorkerModel? worker;
  final bool isOnline;
  final VoidCallback? onWorkerUpdated;
  final ValueChanged<bool>? onAvailabilityChanged;
  final VoidCallback? onExitWorkerMode;

  const WorkerProfileScreen({
    super.key,
    this.worker,
    required this.isOnline,
    this.onWorkerUpdated,
    this.onAvailabilityChanged,
    this.onExitWorkerMode,
  });

  @override
  State<WorkerProfileScreen> createState() => _WorkerProfileScreenState();
}

class _WorkerProfileScreenState extends State<WorkerProfileScreen> {
  // Auth state is read from AuthService notifier directly — no local _isVerified needed
  bool _isUpdatingProfile = false;

  // Bio section
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _descController = TextEditingController();

  // Skills & Rates section
  final _newSkillController = TextEditingController();
  final _hourlyRateController = TextEditingController();
  final _dailyRateController = TextEditingController();
  String _pricingModel = 'Hourly';
  List<WorkerSkillItem> _skills = [];

  // Service Area
  final _serviceAreaController = TextEditingController();
  double _radiusKm = 10.0;

  // Availability & Schedule
  bool _isAvailable = true;
  List<String> _selectedWorkDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 17, minute: 0);

  bool _isSaving = false;

  final List<String> _weekDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    _initValues(widget.worker);
  }

  @override
  void didUpdateWidget(covariant WorkerProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOnline != oldWidget.isOnline) {
      setState(() {
        _isAvailable = widget.isOnline;
      });
    }
    if (widget.worker != oldWidget.worker && widget.worker != null) {
      _initValues(widget.worker);
    }
  }

  void _initValues(WorkerModel? w) {
    final user = AuthService().currentUser;
    _nameController.text = w?.name ?? user?.name ?? '';
    _phoneController.text = w?.phoneNo ?? '';
    _descController.text = w?.description ?? '';

    _pricingModel = w?.pricingModel ?? 'Hourly';
    _hourlyRateController.text = (w?.hourlyRate ?? 1500).round().toString();
    _dailyRateController.text = (w?.dailyRate ?? 8000).round().toString();
    _skills = List.from(w?.skillItems ?? []);

    _serviceAreaController.text = w?.primaryServiceArea ?? 'Colombo';
    _radiusKm = w?.coverageRadiusKm ?? 10.0;

    _isAvailable = widget.isOnline;

    // Parse availabilityScheduleJson if present
    if (w?.availabilityScheduleJson != null && w!.availabilityScheduleJson!.isNotEmpty) {
      try {
        final parsed = jsonDecode(w.availabilityScheduleJson!);
        if (parsed is Map) {
          if (parsed['workDays'] is List) {
            _selectedWorkDays = List<String>.from(parsed['workDays']);
          }
          if (parsed['startTime'] != null) {
            final parts = parsed['startTime'].toString().split(':');
            if (parts.length >= 2) {
              _startTime = TimeOfDay(
                hour: int.tryParse(parts[0]) ?? 8,
                minute: int.tryParse(parts[1]) ?? 0,
              );
            }
          }
          if (parsed['endTime'] != null) {
            final parts = parsed['endTime'].toString().split(':');
            if (parts.length >= 2) {
              _endTime = TimeOfDay(
                hour: int.tryParse(parts[0]) ?? 17,
                minute: int.tryParse(parts[1]) ?? 0,
              );
            }
          }
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _descController.dispose();
    _newSkillController.dispose();
    _hourlyRateController.dispose();
    _dailyRateController.dispose();
    _serviceAreaController.dispose();
    super.dispose();
  }

  void _showFeedback(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
        backgroundColor: isError ? WorkerColors.error : WorkerColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _updateProfilePicture() async {
    if (_isUpdatingProfile) return;
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
    );
    if (image == null) return;

    _isUpdatingProfile = true;
    if (mounted) setState(() {});

    try {
      final bytes = await image.readAsBytes();
      final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      final user = AuthService().currentUserNotifier.value;
      if (user != null) {
        final success = await ApiService().updateProfile(user.email, {
          "profileImage": base64Image,
        });
        if (mounted) {
          if (success) {
            // Update the AuthUser object
            final updatedUser = user.copyWith(picture: base64Image);
            AuthService().currentUserNotifier.value = updatedUser;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Profile picture updated successfully')),
            );
            await AuthService().persistPicture(base64Image);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to update profile picture')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      _isUpdatingProfile = false;
      if (mounted) setState(() {});
    }
  }

  Widget _buildProfileAvatar() {
    final photo = AuthService().currentUserNotifier.value?.picture;
    final name = AuthService().currentUserNotifier.value?.name ?? 'U';
    final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'U';

    Widget avatarContent;
    if (photo != null && photo.isNotEmpty) {
      if (photo.startsWith('data:image/')) {
        try {
          final base64Str = photo.split(',').last;
          final bytes = base64Decode(base64Str);
          avatarContent = ClipOval(
            child: Image.memory(
              bytes,
              width: 100,
              height: 100,
              fit: BoxFit.cover,
            ),
          );
        } catch (_) {
          avatarContent = CircleAvatar(
            radius: 50,
            backgroundColor: WorkerColors.primary,
            child: Text(
              initial,
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          );
        }
      } else {
        avatarContent = CircleAvatar(
          radius: 50,
          backgroundImage: NetworkImage(photo),
        );
      }
    } else {
      avatarContent = CircleAvatar(
        radius: 50,
        backgroundColor: WorkerColors.primary,
        child: Text(
          initial,
          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      );
    }

    return GestureDetector(
      onTap: _updateProfilePicture,
      child: _isUpdatingProfile
          ? const CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(WorkerColors.primary),
            )
          : avatarContent,
    );
  }

  // 1. Add / Remove Service & Skills
  void _showAddServiceDialog() {
    final workerId = widget.worker?.id;
    if (workerId == null) return;

    ServiceCategoryDef selectedCategory = WorkerServicesCatalog.categories.first;
    List<String> selectedSkills = List.from(selectedCategory.defaultSkills.take(2));
    int experienceYears = 2;
    final customSkillController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final suggestedSkills = WorkerServicesCatalog.getSkillsForService(selectedCategory.name);

            return Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Add Service & Specialization',
                      style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 14),

                    // Service Dropdown
                    Text('Select Service', style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategory.name,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: WorkerServicesCatalog.categories.map((c) {
                        return DropdownMenuItem(
                          value: c.name,
                          child: Text('${c.icon}  ${c.name}'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() {
                            selectedCategory = WorkerServicesCatalog.categories
                                .firstWhere((c) => c.name == val, orElse: () => selectedCategory);
                            selectedSkills = List.from(selectedCategory.defaultSkills.take(2));
                          });
                        }
                      },
                    ),

                    const SizedBox(height: 14),
                    // Experience
                    Text('Experience Level', style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      initialValue: experienceYears,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('< 1 Year Experience')),
                        DropdownMenuItem(value: 1, child: Text('1 Year Experience')),
                        DropdownMenuItem(value: 2, child: Text('2 Years Experience')),
                        DropdownMenuItem(value: 3, child: Text('3 Years Experience')),
                        DropdownMenuItem(value: 5, child: Text('5+ Years Experience')),
                        DropdownMenuItem(value: 10, child: Text('10+ Years Experience')),
                      ],
                      onChanged: (val) {
                        if (val != null) setModalState(() => experienceYears = val);
                      },
                    ),

                    const SizedBox(height: 14),
                    // Skills in this service
                    Text('Skills for ${selectedCategory.name}', style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: suggestedSkills.map((sk) {
                        final isSel = selectedSkills.contains(sk);
                        return FilterChip(
                          label: Text(sk),
                          selected: isSel,
                          selectedColor: WorkerColors.primaryLight,
                          checkmarkColor: WorkerColors.primary,
                          labelStyle: GoogleFonts.dmSans(
                            fontSize: 11,
                            fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                            color: isSel ? WorkerColors.primary : const Color(0xFF334155),
                          ),
                          onSelected: (val) {
                            setModalState(() {
                              if (val) {
                                selectedSkills.add(sk);
                              } else {
                                selectedSkills.remove(sk);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 10),
                    // Custom skill input
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: customSkillController,
                            style: GoogleFonts.dmSans(fontSize: 12),
                            decoration: InputDecoration(
                              hintText: 'Add custom skill to ${selectedCategory.name}...',
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final text = customSkillController.text.trim();
                            if (text.isNotEmpty && !selectedSkills.contains(text)) {
                              setModalState(() {
                                selectedSkills.add(text);
                                customSkillController.clear();
                              });
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WorkerColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Add'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: selectedSkills.isEmpty
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                setState(() => _isSaving = true);
                                final newItem = await ApiService().addWorkerSkill(
                                  workerId,
                                  serviceName: selectedCategory.name,
                                  skills: selectedSkills,
                                  experienceYears: experienceYears,
                                );
                                if (mounted) {
                                  setState(() {
                                    _isSaving = false;
                                    if (newItem != null) {
                                      _skills.add(newItem);
                                      _showFeedback('Added ${selectedCategory.name} to your profile!');
                                      widget.onWorkerUpdated?.call();
                                    } else {
                                      _showFeedback('Failed to add service.', isError: true);
                                    }
                                  });
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: WorkerColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Save Service & Skills', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleRemoveSkill(WorkerSkillItem skill) async {
    final workerId = widget.worker?.id;
    if (workerId == null) return;

    // Guard: A worker must have at least one active service
    if (_skills.length <= 1) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Cannot Delete Service',
                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 17),
                ),
              ),
            ],
          ),
          content: Text(
            'You cannot delete your only active service. Workers must have at least one service on their profile to accept jobs.\n\nPlease add another service first before removing this one.',
            style: GoogleFonts.dmSans(fontSize: 14, color: WorkerColors.onSurfaceVariant, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _showAddServiceDialog();
              },
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text('Add Another Service', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: WorkerColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      );
      return;
    }

    final serviceTitle = skill.serviceName.isNotEmpty ? skill.serviceName : skill.skillName;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_outline_rounded, color: WorkerColors.error, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Delete Service',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to remove "$serviceTitle" from your active services?',
          style: GoogleFonts.dmSans(fontSize: 14, color: WorkerColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: WorkerColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Delete', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);
    final success = await ApiService().removeWorkerSkill(workerId, skill.id);
    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        _skills.removeWhere((s) => s.id == skill.id);
        _showFeedback('Service "$serviceTitle" removed.');
        widget.onWorkerUpdated?.call();
      } else {
        _showFeedback('Could not remove service.', isError: true);
      }
    }
  }

  // 1. Save Bio & Personal Details
  Future<void> _handleSaveBio() async {
    final workerId = widget.worker?.id;
    if (workerId == null) {
      _showFeedback('Worker profile not loaded yet.', isError: true);
      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showFeedback('Full name cannot be empty.', isError: true);
      return;
    }

    final phone = _phoneController.text.trim();
    if (phone.isNotEmpty && !RegExp(r'^0\d{9}$').hasMatch(phone)) {
      _showFeedback('Phone number must be exactly 10 digits starting with 0.', isError: true);
      return;
    }

    final description = _descController.text.trim();

    setState(() => _isSaving = true);

    final success = await ApiService().updateWorkerBio(
      workerId,
      name: name,
      phoneNo: phone,
      description: description,
      currentWorker: widget.worker,
    );

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        // Sync current user name in AuthService & SharedPreferences if name changed
        final user = AuthService().currentUserNotifier.value;
        if (user != null && user.name != name) {
          AuthService().currentUserNotifier.value = user.copyWith(name: name);
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('userName', name);
          } catch (_) {}
        }

        _showFeedback('Bio details saved successfully!');
        widget.onWorkerUpdated?.call();
      } else {
        _showFeedback('Failed to save bio details.', isError: true);
      }
    }
  }

  // 2. Save Pricing
  Future<void> _handleSavePricing() async {
    final workerId = widget.worker?.id;
    if (workerId == null) return;

    setState(() => _isSaving = true);
    final hourly = double.tryParse(_hourlyRateController.text.trim()) ?? 0.0;
    final daily = double.tryParse(_dailyRateController.text.trim()) ?? 0.0;

    final success = await ApiService().updateWorkerPricing(
      workerId,
      pricingModel: _pricingModel,
      hourlyRate: hourly,
      dailyRate: daily,
    );

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        _showFeedback('Pricing & rates updated successfully!');
        widget.onWorkerUpdated?.call();
      } else {
        _showFeedback('Failed to update pricing.', isError: true);
      }
    }
  }

  // 3. Save Service Area
  Future<void> _handleSaveServiceArea() async {
    final workerId = widget.worker?.id;
    if (workerId == null) return;

    final area = _serviceAreaController.text.trim();
    if (area.isEmpty) {
      _showFeedback('Please enter a service area.', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    final success = await ApiService().updateWorkerServiceArea(
      workerId,
      serviceArea: area,
      radiusKm: _radiusKm,
    );

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        _showFeedback('Service area & coverage updated!');
        widget.onWorkerUpdated?.call();
      } else {
        _showFeedback('Failed to update service area.', isError: true);
      }
    }
  }

  // 4. Save Availability & Schedule (Synced!)
  Future<void> _handleSaveAvailability() async {
    final workerId = widget.worker?.id;
    if (workerId == null) return;

    setState(() => _isSaving = true);
    final startStr = '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}';
    final endStr = '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}';

    final scheduleJson = jsonEncode({
      'workDays': _selectedWorkDays,
      'startTime': startStr,
      'endTime': endStr,
    });

    final success = await ApiService().updateWorkerAvailability(
      workerId,
      isAvailable: _isAvailable,
      scheduleJson: scheduleJson,
    );

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        // Sync with top bar
        widget.onAvailabilityChanged?.call(_isAvailable);
        _showFeedback('Availability schedule saved successfully!');
        widget.onWorkerUpdated?.call();
      } else {
        _showFeedback('Failed to update availability.', isError: true);
      }
    }
  }

  // 6. Delete Worker Account (Permanent Deletion)
  Future<void> _handleDeleteWorkerAccount() async {
    final TextEditingController confirmController = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final bool isConfirmed = confirmController.text.trim() == 'DELETE';

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: WorkerColors.errorLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.warning_amber_rounded, color: WorkerColors.error, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Delete Worker Account?',
                      style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: WorkerColors.error,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Are you sure you want to permanently delete your Worker account?',
                      style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: WorkerColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• This action is permanent and cannot be undone.\n'
                      '• All your services, skills, bookings, and reviews will be erased.\n'
                      '• Your email will be freed up and you will be signed out.',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        color: WorkerColors.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: WorkerColors.surfaceVariant.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: WorkerColors.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'To confirm, please type DELETE below:',
                            style: GoogleFonts.dmSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: WorkerColors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: confirmController,
                            autofocus: true,
                            decoration: InputDecoration(
                              hintText: 'Type DELETE to confirm',
                              hintStyle: GoogleFonts.dmSans(fontSize: 13, color: WorkerColors.outline),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: isConfirmed ? WorkerColors.error : WorkerColors.outline,
                                  width: isConfirmed ? 2 : 1,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: WorkerColors.error, width: 2),
                              ),
                            ),
                            style: GoogleFonts.dmSans(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: WorkerColors.error,
                            ),
                            onChanged: (_) => setDialogState(() {}),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          'No, Cancel',
                          style: GoogleFonts.dmSans(
                            fontWeight: FontWeight.w700,
                            color: WorkerColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isConfirmed ? () => Navigator.of(ctx).pop(true) : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: WorkerColors.error,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: WorkerColors.error.withValues(alpha: 0.35),
                          disabledForegroundColor: Colors.white70,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          'Yes, Delete',
                          style: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );

    if (confirm != true) return;

    final user = AuthService().currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);
    final success = await ApiService().deleteWorkerAccount(user.email);
    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        _showFeedback('Worker account permanently deleted.');
        await AuthService().logout();
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/join', (route) => false);
        }
      } else {
        _showFeedback('Failed to delete worker account. Please try again.', isError: true);
      }
    }
  }

  Future<void> _handleLogOut(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Log Out',
          style: GoogleFonts.dmSans(
            fontWeight: FontWeight.w800,
            color: WorkerColors.onSurface,
          ),
        ),
        content: Text(
          'Are you sure you want to log out of SuperBass?',
          style: GoogleFonts.dmSans(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.dmSans(color: WorkerColors.onSurfaceVariant),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: WorkerColors.error,
              foregroundColor: Colors.white,
            ),
            child: Text(
              'Log Out',
              style: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AuthService().logout();
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/join', (route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVerified = widget.worker?.isVerified == true || AuthService().currentUser?.isVerified == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isVerified)
            Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: VerificationForm(
                onVerifySuccess: () {
                  // AuthService.markUserVerified() updates SharedPreferences + notifier.
                  // Force a rebuild so isVerified re-evaluates.
                  if (mounted) setState(() {});
                },
              ),
            ),
          // Profile Avatar
          _buildProfileAvatar(),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                'Profile & Settings',
                style: GoogleFonts.dmSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: WorkerColors.onSurface,
                ),
              ),
              if (isVerified) const VerifiedBadge(size: 20),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Manage your public bio, skills, hourly rates, service area, and schedule.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              color: WorkerColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),

          // 1. Personal & Bio Section
          _buildCard(
            title: 'Personal & Bio',
            icon: Icons.person_outline_rounded,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Full Name'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: const InputDecoration(
                  labelText: 'Contact Phone Number (10 digits)',
                  hintText: '07XXXXXXXX',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Professional Bio / Overview',
                  hintText: 'Describe your expertise, equipment, and reliability...',
                ),
              ),
              const SizedBox(height: 14),
              _buildSaveButton(
                label: 'Save Bio Details',
                isLoading: _isSaving,
                onPressed: _isSaving ? null : _handleSaveBio,
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 2. Services, Skills & Rates Section
          _buildCard(
            title: 'Services, Skills & Rates',
            icon: Icons.handyman_outlined,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Active Services & Skills',
                    style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  TextButton.icon(
                    onPressed: _isSaving ? null : _showAddServiceDialog,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Service'),
                    style: TextButton.styleFrom(
                      foregroundColor: WorkerColors.primary,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (_skills.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(Icons.build_circle_outlined, size: 36, color: Color(0xFF94A3B8)),
                        const SizedBox(height: 8),
                        Text(
                          'No services added yet.',
                          style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _showAddServiceDialog,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add Your First Service'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WorkerColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  )
                )
                else
                  Column(
                    children: _skills.map((s) {
                      final serviceTitle = s.serviceName.isNotEmpty ? s.serviceName : s.skillName;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: WorkerColors.primaryLight,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.handyman_rounded, color: WorkerColors.primary, size: 18),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        serviceTitle,
                                        style: GoogleFonts.dmSans(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF0F172A),
                                        ),
                                      ),
                                      Text(
                                        s.experienceYears <= 0
                                            ? 'Less than 1 Year Experience'
                                            : (s.experienceYears == 1
                                                ? '1 Year Experience'
                                                : '${s.experienceYears}+ Years Experience'),
                                        style: GoogleFonts.dmSans(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: WorkerColors.error, size: 20),
                                  onPressed: _isSaving ? null : () => _handleRemoveSkill(s),
                                  tooltip: 'Remove service',
                                ),
                              ],
                            ),
                            if (s.skills.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: s.skills.map((sub) {
                                  return Chip(
                                    label: Text(sub),
                                    backgroundColor: Colors.white,
                                    labelStyle: GoogleFonts.dmSans(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF334155),
                                    ),
                                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  ),

              const SizedBox(height: 18),

              DropdownButtonFormField<String>(
                initialValue: _pricingModel,
                decoration: const InputDecoration(labelText: 'Pricing Model'),
                items: const [
                  DropdownMenuItem(value: 'Hourly', child: Text('Hourly Rate')),
                  DropdownMenuItem(value: 'Daily', child: Text('Daily Rate')),
                  DropdownMenuItem(value: 'Fixed', child: Text('Fixed / Per Job')),
                  DropdownMenuItem(value: 'Negotiable', child: Text('Negotiable')),
                ],
                onChanged: (val) => setState(() => _pricingModel = val ?? 'Hourly'),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _hourlyRateController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Hourly Rate (LKR)',
                        prefixText: 'Rs. ',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _dailyRateController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Daily Rate (LKR)',
                        prefixText: 'Rs. ',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildSaveButton(
                label: 'Save Skills & Rates',
                onPressed: _isSaving ? null : _handleSavePricing,
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 3. Service Area & Radius Section
          _buildCard(
            title: 'Service Area & Coverage',
            icon: Icons.map_outlined,
            children: [
              TextFormField(
                controller: _serviceAreaController,
                decoration: const InputDecoration(
                  labelText: 'Primary City / Region',
                  prefixIcon: Icon(Icons.location_on_outlined, color: WorkerColors.primary),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Coverage Radius',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: WorkerColors.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '${_radiusKm.round()} km',
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: WorkerColors.primary,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _radiusKm,
                min: 2,
                max: 50,
                divisions: 24,
                activeColor: WorkerColors.primary,
                inactiveColor: WorkerColors.outlineVariant,
                label: '${_radiusKm.round()} km',
                onChanged: (val) => setState(() => _radiusKm = val),
              ),
              const SizedBox(height: 10),
              _buildSaveButton(
                label: 'Save Service Area',
                onPressed: _isSaving ? null : _handleSaveServiceArea,
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 4. Availability & Schedule Section (Synced!)
          _buildCard(
            title: 'Availability & Schedule',
            icon: Icons.event_available_outlined,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _isAvailable ? WorkerColors.onlineLight : WorkerColors.offlineLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _isAvailable ? WorkerColors.online : WorkerColors.offline,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isAvailable ? 'Available for Work' : 'Currently Offline',
                          style: GoogleFonts.dmSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _isAvailable ? WorkerColors.online : WorkerColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    Switch(
                      value: _isAvailable,
                      activeThumbColor: WorkerColors.online,
                      onChanged: (val) async {
                        final confirmed = await showAvailabilityConfirmDialog(
                          context,
                          targetOnline: val,
                        );
                        if (!confirmed) return;
                        setState(() => _isAvailable = val);
                        widget.onAvailabilityChanged?.call(val);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Weekly Working Days',
                style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _weekDays.map((day) {
                  final isSelected = _selectedWorkDays.contains(day);
                  return FilterChip(
                    label: Text(day),
                    selected: isSelected,
                    onSelected: (val) {
                      setState(() {
                        if (val) {
                          _selectedWorkDays.add(day);
                        } else {
                          _selectedWorkDays.remove(day);
                        }
                      });
                    },
                    selectedColor: WorkerColors.primaryContainer,
                    checkmarkColor: WorkerColors.primary,
                    labelStyle: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? WorkerColors.primary : WorkerColors.onSurface,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: isSelected ? WorkerColors.primary : WorkerColors.outlineVariant,
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),
              Text(
                'Working Hours',
                style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _startTime,
                        );
                        if (picked != null) setState(() => _startTime = picked);
                      },
                      icon: const Icon(Icons.schedule_rounded, size: 18),
                      label: Text('Start: ${_startTime.format(context)}'),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _endTime,
                        );
                        if (picked != null) setState(() => _endTime = picked);
                      },
                      icon: const Icon(Icons.schedule_rounded, size: 18),
                      label: Text('End: ${_endTime.format(context)}'),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              _buildSaveButton(
                label: 'Save Availability & Schedule',
                onPressed: _isSaving ? null : _handleSaveAvailability,
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 5. Account Settings Section
          _buildCard(
            title: 'Account Settings',
            icon: Icons.manage_accounts_rounded,
            children: [
              // Log Out Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => _handleLogOut(context),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: Text(
                    'Log Out',
                    style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 20),

              // Danger Zone: Delete Worker Account
              Text(
                'Danger Zone',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: WorkerColors.error,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Permanently delete your Worker account. All your services, active jobs, reviews, and worker credentials will be permanently erased.',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: WorkerColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isSaving ? null : _handleDeleteWorkerAccount,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: WorkerColors.error,
                    side: const BorderSide(color: WorkerColors.error),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  label: Text(
                    'Delete Worker Account',
                    style: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: WorkerColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: WorkerColors.primary, size: 22),
              const SizedBox(width: 10),
              Text(
                title,
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: WorkerColors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSaveButton({
    required String label,
    required VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: WorkerColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: WorkerColors.primary.withValues(alpha: 0.6),
          shape: const StadiumBorder(),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}