import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';
import '../data/sri_lanka_locations.dart';
import '../models/auth_user.dart';
import '../models/community_post_model.dart';
import '../models/worker_model.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../theme/app_colors.dart';
import '../widgets/verified_badge.dart';
import 'chat_screen.dart';

class CommunityScreen extends StatefulWidget {
  final bool isWorkerMode;
  const CommunityScreen({super.key, this.isWorkerMode = false});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<CommunityPostModel> _allPosts = [];
  List<CommunityPostModel> _myPosts = [];
  List<ServiceCategoryModel> _categories = [];
  bool _isLoading = true;
  String _selectedCategory = 'All';
  String _searchQuery = '';
  String _sortBy = 'latest'; // 'latest' or 'popular'
  String _selectedLocation = 'All Locations';
  String? _primaryAddressCity;
  Map<String, WorkerModel> _workersByEmail = {};
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadInitialData();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    _loadPrimaryAddress();
    await Future.wait([
      _fetchCategories(),
      _fetchPosts(),
      _fetchWorkersMap(),
    ]);
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchWorkersMap() async {
    try {
      final workers = await ApiService().fetchWorkers();
      final map = <String, WorkerModel>{};
      for (final w in workers) {
        if (w.residentEmail.isNotEmpty) map[w.residentEmail.toLowerCase()] = w;
        if (w.email.isNotEmpty) map[w.email.toLowerCase()] = w;
      }
      if (mounted) {
        setState(() => _workersByEmail = map);
      }
    } catch (_) {}
  }

  Future<void> _loadPrimaryAddress() async {
    try {
      final user = AuthService().currentUser;
      final city = await LocationService.getPrimaryAddressCity(user?.email);
      if (mounted && city != null && city.isNotEmpty) {
        setState(() {
          _primaryAddressCity = city;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchCategories() async {
    final cats = await ApiService().fetchCommunityCategories();
    if (mounted) {
      setState(() {
        _categories = cats;
      });
    }
  }

  Future<void> _fetchPosts() async {
    _requestId++;
    final currentRequestId = _requestId;

    final currentUserEmail = AuthService().currentUser?.email;
    final isAllLocations = _selectedLocation == 'All' ||
        _selectedLocation == 'All Locations' ||
        _selectedLocation.trim().isEmpty;
    final locationQuery = isAllLocations ? null : _selectedLocation.trim();

    final posts = await ApiService().fetchCommunityPosts(
      category: _selectedCategory,
      search: _searchQuery,
      sort: _sortBy,
      location: locationQuery,
    );

    if (!mounted || currentRequestId != _requestId) return;

    final filteredPosts = isAllLocations
        ? posts
        : posts
            .where((p) => LocationService.workerMatchesLocation(
                p.location, _selectedLocation))
            .toList();

    List<CommunityPostModel> userPosts = [];
    if (currentUserEmail != null && currentUserEmail.isNotEmpty) {
      userPosts = await ApiService().fetchUserCommunityPosts(currentUserEmail);
      
      if (!mounted || currentRequestId != _requestId) return;

      if (!isAllLocations) {
        userPosts = userPosts
            .where((p) => LocationService.workerMatchesLocation(
                p.location, _selectedLocation))
            .toList();
      }
    }

    if (mounted) {
      setState(() {
        _allPosts = isAllLocations ? posts : filteredPosts;
        _myPosts = userPosts;
      });
    }
  }

  void _updateLocation(String newLocation) {
    setState(() {
      _selectedLocation = newLocation;
    });
    _fetchPosts();
  }

  void _onCategorySelected(String categoryId) {
    setState(() {
      _selectedCategory = categoryId;
    });
    _fetchPosts();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
    });
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _fetchPosts();
    });
  }

  void _toggleSort() {
    setState(() {
      _sortBy = _sortBy == 'latest' ? 'popular' : 'latest';
    });
    _fetchPosts();
  }

  void _showLocationPickerSheet() {
    final TextEditingController searchController = TextEditingController();
    bool isDetecting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final query = searchController.text.trim().toLowerCase();

          const sriLankaDistricts = [
            'All Locations',
            'Ampara',
            'Anuradhapura',
            'Badulla',
            'Batticaloa',
            'Colombo',
            'Galle',
            'Gampaha',
            'Hambantota',
            'Jaffna',
            'Kalutara',
            'Kandy',
            'Kegalle',
            'Kilinochchi',
            'Kurunegala',
            'Mannar',
            'Matale',
            'Matara',
            'Monaragala',
            'Mullaitivu',
            'Nuwara Eliya',
            'Polonnaruwa',
            'Puttalam',
            'Ratnapura',
            'Trincomalee',
            'Vavuniya',
          ];

          final List<Map<String, String>> matchingPlaces = [];
          if (query.isNotEmpty) {
            for (final entry in SriLankaLocations.districtDsMap.entries) {
              final district = entry.key;
              if (district.toLowerCase().contains(query)) {
                matchingPlaces.add({'name': district, 'type': 'District'});
              }
              for (final ds in entry.value) {
                final dsName = ds.split('/').first.split('-').first.trim();
                if (dsName.toLowerCase().contains(query)) {
                  matchingPlaces.add({
                    'name': dsName,
                    'type': '$district District',
                  });
                }
              }
            }
          }

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Select Location',
                            style: GoogleFonts.dmSans(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Filter community discussions by location',
                            style: GoogleFonts.dmSans(
                              fontSize: 12.5,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close, color: Colors.black),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),

                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    children: [
                      // Option 1: Use Current Location (GPS)
                      InkWell(
                        onTap: isDetecting
                            ? null
                            : () async {
                                setModalState(() => isDetecting = true);
                                try {
                                  final city = await LocationService.detectGpsCity();
                                  if (mounted && city != null && city.isNotEmpty) {
                                    _updateLocation(city);
                                    if (ctx.mounted) Navigator.pop(ctx);
                                  } else {
                                    setModalState(() => isDetecting = false);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Could not detect GPS location. Please select your city below.'),
                                        ),
                                      );
                                    }
                                  }
                                } catch (_) {
                                  setModalState(() => isDetecting = false);
                                }
                              },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            borderRadius: BorderRadius.circular(12),
                            color: const Color(0xFFFAFAFA),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: const BoxDecoration(
                                  color: Colors.black,
                                  shape: BoxShape.circle,
                                ),
                                child: isDetecting
                                    ? const Padding(
                                        padding: EdgeInsets.all(10.0),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.my_location,
                                        size: 19,
                                        color: Colors.white,
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Use Current Location',
                                      style: GoogleFonts.dmSans(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      isDetecting
                                          ? 'Detecting your district via GPS...'
                                          : 'Filter posts by your district using device GPS',
                                      style: GoogleFonts.dmSans(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                size: 20,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Option 2: Use Primary Address City
                      InkWell(
                        onTap: () async {
                          if (_primaryAddressCity != null && _primaryAddressCity!.isNotEmpty) {
                            _updateLocation(_primaryAddressCity!);
                            Navigator.pop(ctx);
                          } else {
                            final user = AuthService().currentUser;
                            final city = await LocationService.getPrimaryAddressCity(user?.email);
                            if (city != null && city.isNotEmpty) {
                              _primaryAddressCity = city;
                              _updateLocation(city);
                              if (ctx.mounted) Navigator.pop(ctx);
                            } else {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('No primary address found. Please enter or select a city below.'),
                                  ),
                                );
                              }
                            }
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            borderRadius: BorderRadius.circular(12),
                            color: const Color(0xFFFAFAFA),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: const BoxDecoration(
                                  color: Colors.black,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.home_outlined,
                                  size: 20,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Use Primary Address',
                                      style: GoogleFonts.dmSans(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      (_primaryAddressCity != null && _primaryAddressCity!.isNotEmpty)
                                          ? 'Saved: $_primaryAddressCity'
                                          : 'From your resident account profile',
                                      style: GoogleFonts.dmSans(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                size: 20,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Search text input
                      TextField(
                        controller: searchController,
                        onChanged: (_) => setModalState(() {}),
                        style: GoogleFonts.dmSans(fontSize: 14, color: Colors.black),
                        decoration: InputDecoration(
                          hintText: 'Search city or district (e.g. Ratnapura, Colombo)...',
                          hintStyle: GoogleFonts.dmSans(fontSize: 13, color: Colors.grey[500]),
                          prefixIcon: const Icon(Icons.search, size: 20, color: Colors.black87),
                          suffixIcon: searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    searchController.clear();
                                    setModalState(() {});
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),

                      // If manual query has text, show "Use '<query>'" tile so user can type any custom name
                      if (searchController.text.trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        InkWell(
                          onTap: () {
                            final custom = LocationService.cleanLocationName(searchController.text.trim());
                            if (custom.isNotEmpty) {
                              _updateLocation(custom);
                              Navigator.pop(ctx);
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.location_on, size: 18, color: Colors.white),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Use "${searchController.text.trim()}"',
                                    style: GoogleFonts.dmSans(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                      color: Colors.white,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(Icons.arrow_forward, size: 16, color: Colors.white),
                              ],
                            ),
                          ),
                        ),
                      ],

                      // If search query is empty, show Districts chips
                      if (searchController.text.trim().isEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Districts (Sri Lanka)',
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: sriLankaDistricts.map((district) {
                            final isSelected = _selectedLocation.toLowerCase() == district.toLowerCase();
                            return ChoiceChip(
                              label: Text(district),
                              selected: isSelected,
                              onSelected: (_) {
                                _updateLocation(district);
                                Navigator.pop(ctx);
                              },
                              selectedColor: Colors.black,
                              backgroundColor: const Color(0xFFF1F5F9),
                              labelStyle: GoogleFonts.dmSans(
                                fontSize: 12.5,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected ? Colors.white : Colors.black87,
                              ),
                              side: BorderSide(
                                color: isSelected ? Colors.black : const Color(0xFFE2E8F0),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              showCheckmark: false,
                            );
                          }).toList(),
                        ),
                      ],

                      // If search query is not empty, show matching results from SriLankaLocations
                      if (query.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          'Matching Locations (${matchingPlaces.length})',
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (matchingPlaces.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16.0),
                            child: Center(
                              child: Text(
                                'No official district/division found.\nYou can tap "Use \\"${searchController.text}\\"" above.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.dmSans(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                          )
                        else
                          ...matchingPlaces.map((place) {
                            final name = place['name']!;
                            final type = place['type']!;
                            final isSelected = _selectedLocation.toLowerCase() == name.toLowerCase();
                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                              leading: Icon(
                                Icons.location_on_outlined,
                                size: 20,
                                color: isSelected ? Colors.black : Colors.grey[600],
                              ),
                              title: Text(
                                name,
                                style: GoogleFonts.dmSans(
                                  fontSize: 14,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: Colors.black,
                                ),
                              ),
                              subtitle: Text(
                                type,
                                style: GoogleFonts.dmSans(fontSize: 11.5, color: Colors.grey[600]),
                              ),
                              trailing: isSelected
                                  ? const Icon(Icons.check, size: 18, color: Colors.black)
                                  : null,
                              onTap: () {
                                _updateLocation(name);
                                Navigator.pop(ctx);
                              },
                            );
                          }),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Handle Create or Edit Post Sheet
  void _showPostDialog({CommunityPostModel? postToEdit}) {
    final isEditing = postToEdit != null;
    final titleController = TextEditingController(text: postToEdit?.title ?? '');
    final contentController = TextEditingController(text: postToEdit?.content ?? '');
    final imageController = TextEditingController(
      text: (postToEdit?.images != null && postToEdit!.images.isNotEmpty) ? postToEdit.images.first : '',
    );
    String selectedCatId = postToEdit?.serviceCategoryId.isNotEmpty == true ? postToEdit!.serviceCategoryId : 'general';

    // Parse existing location into District & Province
    String? selectedDistrict;
    String? selectedProvince;
    if (postToEdit?.location != null && postToEdit!.location.isNotEmpty) {
      final locLower = postToEdit.location.toLowerCase();
      for (final dist in SriLankaLocations.districts) {
        if (locLower.contains(dist.toLowerCase())) {
          selectedDistrict = dist;
          break;
        }
      }
      for (final prov in SriLankaLocations.provinces) {
        final provBase = prov.toLowerCase().replaceAll(' province', '');
        if (locLower.contains(provBase)) {
          selectedProvince = prov;
          break;
        }
      }
    }
    selectedDistrict ??= 'Colombo';
    selectedProvince ??= SriLankaLocations.getProvinceForDistrict(selectedDistrict) ?? 'Western Province';

    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          final hasImage = imageController.text.trim().isNotEmpty;

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(modalCtx).viewInsets.bottom,
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.all(24),
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
                          color: AppColors.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isEditing ? 'Edit Community Post' : 'Create Community Post',
                          style: GoogleFonts.dmSans(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.onSurface,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Category Selector
                    Text(
                      'Category',
                      style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Builder(
                      builder: (context) {
                        final Map<String, String> categoryOptions = {
                          'general': 'General Advice',
                        };
                        for (var c in _categories) {
                          if (c.id.isNotEmpty && c.name.isNotEmpty) {
                            categoryOptions[c.id] = c.name;
                          }
                        }

                        final effectiveValue = categoryOptions.keys.firstWhere(
                          (k) => k.toLowerCase() == selectedCatId.toLowerCase(),
                          orElse: () => categoryOptions.keys.first,
                        );

                        return DropdownButtonFormField<String>(
                          initialValue: effectiveValue,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                          items: categoryOptions.entries.map((entry) {
                            return DropdownMenuItem<String>(
                              value: entry.key,
                              child: Text(entry.value),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() => selectedCatId = val);
                            }
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 14),

                    // Title
                    Text(
                      'Title',
                      style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        hintText: 'e.g., Looking for a reliable electrician in Homagama',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Location - District & Province Section
                    Text(
                      'Location (District & Province)',
                      style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // District Dropdown
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: SriLankaLocations.districts.contains(selectedDistrict)
                                ? selectedDistrict
                                : SriLankaLocations.districts.first,
                            decoration: InputDecoration(
                              labelText: 'District',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            items: SriLankaLocations.districts.map((dist) {
                              return DropdownMenuItem<String>(
                                value: dist,
                                child: Text(dist, overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setModalState(() {
                                  selectedDistrict = val;
                                  final prov = SriLankaLocations.getProvinceForDistrict(val);
                                  if (prov != null) {
                                    selectedProvince = prov;
                                  }
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Province Dropdown
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: SriLankaLocations.provinces.contains(selectedProvince)
                                ? selectedProvince
                                : SriLankaLocations.provinces.first,
                            decoration: InputDecoration(
                              labelText: 'Province',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            items: SriLankaLocations.provinces.map((prov) {
                              return DropdownMenuItem<String>(
                                value: prov,
                                child: Text(prov, overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setModalState(() {
                                  selectedProvince = val;
                                  final distsInProv = SriLankaLocations.getDistrictsForProvince(val);
                                  if (!distsInProv.contains(selectedDistrict)) {
                                    selectedDistrict = distsInProv.isNotEmpty ? distsInProv.first : 'Colombo';
                                  }
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Content
                    Text(
                      'Description / Details',
                      style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: contentController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Describe what service, recommendation, or advice you are seeking...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Image Attachment Section (Upload Only)
                    Text(
                      'Image Attachment (Optional)',
                      style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () async {
                              final ImagePicker picker = ImagePicker();
                              final XFile? file = await picker.pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 1024,
                                maxHeight: 1024,
                                imageQuality: 85,
                              );
                              if (file != null) {
                                final bytes = await file.readAsBytes();
                                final mime = file.mimeType ?? 'image/jpeg';
                                final base64Str = base64Encode(bytes);
                                final dataUri = 'data:$mime;base64,$base64Str';
                                setModalState(() {
                                  imageController.text = dataUri;
                                });
                              }
                            },
                            icon: const Icon(Icons.add_a_photo_outlined),
                            label: Text(hasImage ? 'Change Selected Photo' : 'Attach Photo from Device'),
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: AppColors.surfaceVariant,
                              foregroundColor: AppColors.onSurface,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),

                          // Image Preview Thumbnail
                          if (hasImage) ...[
                            const SizedBox(height: 12),
                            Stack(
                              children: [
                                Container(
                                  height: 120,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: imageController.text.startsWith('data:image/')
                                        ? Image.memory(
                                            base64Decode(imageController.text.split(',').last),
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image)),
                                          )
                                        : Image.network(
                                            imageController.text,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image)),
                                          ),
                                  ),
                                ),
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: CircleAvatar(
                                    backgroundColor: Colors.black54,
                                    radius: 14,
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(Icons.close, size: 16, color: Colors.white),
                                      onPressed: () {
                                        setModalState(() {
                                          imageController.clear();
                                        });
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                final title = titleController.text.trim();
                                final content = contentController.text.trim();
                                final constructedLocation = '$selectedDistrict, $selectedProvince';
                                final imageUrl = imageController.text.trim();

                                if (title.isEmpty || content.isEmpty) {
                                  ScaffoldMessenger.of(modalCtx).showSnackBar(
                                    const SnackBar(content: Text('Please enter both Title and Content')),
                                  );
                                  return;
                                }

                                setModalState(() => isSubmitting = true);

                                final imagesList = imageUrl.isNotEmpty ? [imageUrl] : <String>[];

                                CommunityPostModel? result;
                                final scaffoldMessenger = ScaffoldMessenger.of(context);
                                final navigator = Navigator.of(modalCtx);

                                if (isEditing) {
                                  result = await ApiService().updateCommunityPost(
                                    id: postToEdit.postId,
                                    title: title,
                                    content: content,
                                    serviceCategoryId: selectedCatId,
                                    location: constructedLocation,
                                    images: imagesList,
                                  );
                                } else {
                                  final currentUser = AuthService().currentUser;
                                  final myWorkerInfo = currentUser != null
                                      ? _workersByEmail[currentUser.email.toLowerCase()]
                                      : null;
                                  final isWorker = widget.isWorkerMode || myWorkerInfo != null;

                                  result = await ApiService().createCommunityPost(
                                    title: title,
                                    content: content,
                                    serviceCategoryId: selectedCatId,
                                    location: constructedLocation,
                                    images: imagesList,
                                    authorRole: isWorker ? 'worker' : 'resident',
                                    workerTrade: myWorkerInfo?.trade,
                                    workerRating: myWorkerInfo?.rating,
                                  );
                                }

                                if (modalCtx.mounted) {
                                  navigator.pop();
                                }
                                if (mounted) {
                                  if (result != null) {
                                    scaffoldMessenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          isEditing ? 'Post updated successfully!' : 'Post created successfully!',
                                        ),
                                        backgroundColor: AppColors.success,
                                      ),
                                    );
                                    _fetchPosts();
                                  } else {
                                    scaffoldMessenger.showSnackBar(
                                      const SnackBar(
                                        content: Text('Failed to save post. Please try again.'),
                                        backgroundColor: AppColors.error,
                                      ),
                                    );
                                  }
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(width: 24, height: 24, child: LoadingIndicatorM3E())
                            : Text(
                                isEditing ? 'Update Post' : 'Publish Community Post',
                                style: GoogleFonts.dmSans(fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Handle Delete Post Confirmation
  void _confirmDeletePost(CommunityPostModel post) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Post', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
        content: Text('Are you sure you want to delete "${post.title}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await ApiService().deleteCommunityPost(post.postId);
              if (mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Post deleted successfully'), backgroundColor: AppColors.success),
                  );
                  _fetchPosts();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to delete post'), backgroundColor: AppColors.error),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Handle Report Post Dialog
  void _showReportDialog(CommunityPostModel post) {
    final reasonController = TextEditingController();
    String selectedReason = 'Spam / Advertising';
    final reasons = ['Spam / Advertising', 'Inappropriate Content', 'Off-topic', 'Harassment', 'Other'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            title: Text('Report Community Post', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select reason for reporting this post to moderators:'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedReason,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: reasons.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedReason = val);
                  },
                ),
                if (selectedReason == 'Other') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    decoration: const InputDecoration(
                      hintText: 'Explain the issue...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandYellow, foregroundColor: Colors.white),
                onPressed: () async {
                  final finalReason = selectedReason == 'Other' ? reasonController.text.trim() : selectedReason;
                  Navigator.pop(dialogCtx);
                  final success = await ApiService().reportCommunityPost(postId: post.postId, reason: finalReason);
                  if (mounted) {
                    if (success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Report submitted to community moderators. Thank you!')),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Failed to submit report. Please try again.')),
                      );
                    }
                  }
                },
                child: const Text('Submit Report'),
              ),
            ],
          );
        },
      ),
    );
  }

  // Handle Post Comments Bottom Sheet
  void _showCommentsSheet(CommunityPostModel post) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PostCommentsSheet(post: post, onCommentAdded: () => _fetchPosts()),
    );
  }

  // Handle Like Toggle
  Future<void> _toggleLike(CommunityPostModel post) async {
    final result = await ApiService().togglePostLike(post.postId);
    if (result != null) {
      final bool newIsLiked = result['isLiked'] as bool? ?? false;
      final int newLikesCount = result['likesCount'] as int? ?? post.likesCount;

      setState(() {
        final index = _allPosts.indexWhere((p) => p.postId == post.postId);
        if (index != -1) {
          _allPosts[index] = _allPosts[index].copyWith(
            isLikedByMe: newIsLiked,
            likesCount: newLikesCount,
          );
        }
        final myIndex = _myPosts.indexWhere((p) => p.postId == post.postId);
        if (myIndex != -1) {
          _myPosts[myIndex] = _myPosts[myIndex].copyWith(
            isLikedByMe: newIsLiked,
            likesCount: newLikesCount,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthService().currentUser;
    final bool isMyPosts = _tabController.index == 1;
    final posts = isMyPosts ? _myPosts : _allPosts;

    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: widget.isWorkerMode ? 74.0 : 0.0),
        child: FloatingActionButton.extended(
          backgroundColor: const Color(0xFF000000),
          foregroundColor: Colors.white,
          elevation: 3,
          shape: const StadiumBorder(),
          onPressed: () {
            if (AuthService().currentUser == null) {
              Navigator.pushNamed(context, '/join');
            } else {
              _showPostDialog();
            }
          },
          icon: const Icon(Icons.add_rounded, size: 22),
          label: Text(
            'New post',
            style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 14.5),
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: Colors.black,
          onRefresh: _fetchPosts,
          child: ListView(
            padding: EdgeInsets.fromLTRB(0, 14, 0, widget.isWorkerMode ? 96 : 32),
            children: [
              // 1. Large "Community" Title
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 14, 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Community',
                      style: GoogleFonts.dmSans(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF000000),
                        letterSpacing: -0.6,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _sortBy == 'latest' ? Icons.access_time_rounded : Icons.local_fire_department_rounded,
                        size: 22,
                        color: const Color(0xFF000000),
                      ),
                      tooltip: _sortBy == 'latest' ? 'Showing Latest' : 'Showing Popular',
                      onPressed: _toggleSort,
                    ),
                  ],
                ),
              ),

              // 2. Feed Selector & Location Row (All feed, My posts, All locations v)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _buildTabPill(
                      label: 'All feed',
                      isSelected: _tabController.index == 0,
                      onTap: () {
                        setState(() {
                          _tabController.animateTo(0);
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildTabPill(
                      label: 'My posts',
                      isSelected: _tabController.index == 1,
                      onTap: () {
                        setState(() {
                          _tabController.animateTo(1);
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: _showLocationPickerSheet,
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F3F5),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 17,
                              color: Color(0xFF0F172A),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _selectedLocation,
                              style: GoogleFonts.dmSans(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: Color(0xFF0F172A),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 3. Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F3F5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: GoogleFonts.dmSans(
                      fontSize: 14.5,
                      color: const Color(0xFF0F172A),
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search community posts',
                      hintStyle: GoogleFonts.dmSans(
                        fontSize: 14.5,
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w400,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        size: 22,
                        color: Color(0xFF334155),
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFF64748B)),
                              onPressed: () {
                                _searchController.clear();
                                _onSearchChanged('');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 4. Categories Filter Row (All, Plumbing, Electrical, Carpentry, ...)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _buildModernCategoryChip('All', 'All'),
                    ..._categories.map((c) => _buildModernCategoryChip(c.id, c.name)),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Subtle Divider
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Divider(height: 1, thickness: 1, color: Color(0xFFF1F3F5)),
              ),
              const SizedBox(height: 8),

              // 7. Posts Feed
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40.0),
                    child: LoadingIndicatorM3E(),
                  ),
                )
              else if (posts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(Icons.forum_outlined, size: 48, color: Color(0xFF94A3B8)),
                          const SizedBox(height: 12),
                          Text(
                            isMyPosts
                                ? 'You have not created any posts yet'
                                : (_selectedLocation != 'All Locations' && _selectedLocation != 'All'
                                    ? 'No community posts found in $_selectedLocation'
                                    : 'No community posts found'),
                            style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isMyPosts
                                ? 'Tap "+ New post" below to start your first community discussion!'
                                : (_selectedLocation != 'All Locations' && _selectedLocation != 'All'
                                    ? 'Try switching to "All Locations" or be the first to post!'
                                    : 'Be the first to post recommendations or ask for help in your area!'),
                            style: GoogleFonts.dmSans(fontSize: 13, color: const Color(0xFF64748B)),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                ...posts.map((post) => _buildPostCard(post, currentUser)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabPill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF000000) : const Color(0xFFF1F3F5),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 13.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
      ),
    );
  }

  Widget _buildModernCategoryChip(String id, String label) {
    final isSelected = _selectedCategory.toLowerCase() == id.toLowerCase();
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: InkWell(
        onTap: () => _onCategorySelected(id),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF000000) : const Color(0xFFF1F3F5),
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPostCard(CommunityPostModel post, AuthUser? currentUser) {
    final bool canManage = post.isAuthor(currentUser?.email, currentUser?.name);

    // Identify if author is a Pro Worker
    final String postEmail = post.userId.trim().toLowerCase();
    final worker = _workersByEmail[postEmail] ??
        _workersByEmail.values.cast<WorkerModel?>().firstWhere(
              (w) =>
                  (w != null && w.name.trim().toLowerCase() == post.userName.trim().toLowerCase()) ||
                  (w != null && w.email.trim().toLowerCase() == postEmail) ||
                  (w != null && w.residentEmail.trim().toLowerCase() == postEmail),
              orElse: () => null,
            );

    final bool isWorkerAuthor = post.isWorker || worker != null;
    final String workerTrade = (post.workerTrade != null && post.workerTrade!.isNotEmpty)
        ? post.workerTrade!
        : (worker?.trade ?? '');
    final double workerRating = (post.workerRating != null && post.workerRating! > 0)
        ? post.workerRating!
        : (worker?.rating ?? 0.0);

    // Viewer context
    final currentEmail = (currentUser?.email ?? '').trim().toLowerCase();
    final isViewerWorker = widget.isWorkerMode || _workersByEmail.containsKey(currentEmail);
    final bool isMyPost = post.isAuthor(currentUser?.email, currentUser?.name);
    final bool isAuthorVerified = post.isAuthorVerified ||
        (isMyPost && (currentUser?.isVerified ?? false)) ||
        (worker?.isVerified ?? false) ||
        (currentUser != null &&
            post.userId.trim().isNotEmpty &&
            post.userId.trim().toLowerCase() == currentEmail &&
            currentUser.isVerified);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author Header Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar: Clean Black Circle with White Initial (or image)
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF000000),
                ),
                child: ClipOval(
                  child: post.userAvatar.isNotEmpty && post.userAvatar.startsWith('http')
                      ? Image.network(
                          post.userAvatar,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _buildAvatarFallback(post, isWorkerAuthor),
                        )
                      : _buildAvatarFallback(post, isWorkerAuthor),
                ),
              ),
              const SizedBox(width: 12),

              // Name + Subtitle (Location · Time)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            post.userName,
                            style: GoogleFonts.dmSans(
                              fontWeight: FontWeight.w800,
                              fontSize: 15.5,
                              color: const Color(0xFF000000),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isAuthorVerified) ...[
                          const SizedBox(width: 5),
                          const VerifiedBadge(size: 15),
                        ],
                        if (isWorkerAuthor && workerRating > 0) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.star_rounded, size: 14, color: Color(0xFFD97706)),
                          const SizedBox(width: 1),
                          Text(
                            workerRating.toStringAsFixed(1),
                            style: GoogleFonts.dmSans(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF92400E),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isWorkerAuthor && workerTrade.isNotEmpty
                          ? '$workerTrade · ${post.location} · ${_formatTimeAgo(post.createdAt)}'
                          : '${post.location} · ${_formatTimeAgo(post.createdAt)}',
                      style: GoogleFonts.dmSans(
                        fontSize: 12.5,
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Category Pill (e.g. Others, Plumbing)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F3F5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  post.serviceCategoryName,
                  style: GoogleFonts.dmSans(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: const Color(0xFF334155),
                  ),
                ),
              ),

              // Three Dots Action Menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 20, color: Color(0xFF334155)),
                padding: EdgeInsets.zero,
                onSelected: (val) {
                  if (val == 'edit') {
                    _showPostDialog(postToEdit: post);
                  } else if (val == 'delete') {
                    _confirmDeletePost(post);
                  } else if (val == 'report') {
                    _showReportDialog(post);
                  }
                },
                itemBuilder: (ctx) => [
                  if (canManage) ...[
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Edit Post'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                          SizedBox(width: 8),
                          Text('Delete Post', style: TextStyle(color: AppColors.error)),
                        ],
                      ),
                    ),
                  ] else ...[
                    const PopupMenuItem(
                      value: 'report',
                      child: Row(
                        children: [
                          Icon(Icons.flag_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Report Post'),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Post Title
          Text(
            post.title,
            style: GoogleFonts.dmSans(
              fontWeight: FontWeight.w800,
              fontSize: 17.5,
              color: const Color(0xFF000000),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),

          // Post Content
          Text(
            post.content,
            style: GoogleFonts.dmSans(
              fontSize: 14.5,
              color: const Color(0xFF475569),
              height: 1.4,
            ),
          ),

          // Images if present
          if (post.images.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: post.images.first.startsWith('data:image/')
                  ? Image.memory(
                      base64Decode(post.images.first.split(',').last),
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    )
                  : Image.network(
                      post.images.first,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
            ),
          ],

          const SizedBox(height: 14),

          // Action Row (Like, Comment, Share)
          Row(
            children: [
              // Like Pill Button
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _toggleLike(post),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: post.isLikedByMe ? const Color(0xFFFEE2E2) : const Color(0xFFF1F3F5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        post.isLikedByMe ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        size: 16,
                        color: post.isLikedByMe ? const Color(0xFFEF4444) : const Color(0xFF000000),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${post.likesCount}',
                        style: GoogleFonts.dmSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: post.isLikedByMe ? const Color(0xFFDC2626) : const Color(0xFF000000),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Comment Pill Button
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _showCommentsSheet(post),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F3F5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 15,
                        color: Color(0xFF000000),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${post.commentsCount} ${post.commentsCount == 1 ? "comment" : "comments"}',
                        style: GoogleFonts.dmSans(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: const Color(0xFF000000),
                        ),
                      ),
                    ],
                  ),
                ),
              ),


              const Spacer(),

              // Share button
              IconButton(
                icon: const Icon(Icons.share_outlined, size: 20, color: Color(0xFF000000)),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Post link copied to clipboard!')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF1F3F5)),
        ],
      ),
    );
  }

  Widget _buildAvatarFallback(CommunityPostModel post, bool isWorker) {
    final initial = post.userName.isNotEmpty ? post.userName[0].toUpperCase() : 'U';
    return Container(
      color: const Color(0xFF000000),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: GoogleFonts.dmSans(
          fontWeight: FontWeight.w800,
          fontSize: 17,
          color: Colors.white,
        ),
      ),
    );
  }

  Future<void> _openChatWithUser(CommunityPostModel post, {WorkerModel? worker}) async {
    final currentUser = AuthService().currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please sign in to start a conversation.', style: GoogleFonts.dmSans()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final targetEmail = post.userId.isNotEmpty ? post.userId : (worker?.email ?? worker?.residentEmail ?? '');
    final myEmail = currentUser.email.toLowerCase();
    if (targetEmail.isEmpty || targetEmail.toLowerCase() == myEmail) {
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: SizedBox(
          width: 36,
          height: 36,
          child: LoadingIndicatorM3E(),
        ),
      ),
    );

    try {
      final conv = await ApiService().getOrCreateConversation(
        workerId: worker?.id ?? 0,
        workerEmail: worker != null ? (worker.email.isNotEmpty ? worker.email : worker.residentEmail) : targetEmail,
        workerName: worker?.name ?? post.userName,
        workerAvatar: worker?.profileImage ?? post.userAvatar,
        residentEmail: currentUser.email,
      );

      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      final convId = conv != null ? (conv['id'] is int ? conv['id'] : int.tryParse(conv['id']?.toString() ?? '')) : null;

      if (convId != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              conversationId: convId,
              name: post.userName,
              profileImage: post.userAvatar.isNotEmpty ? post.userAvatar : null,
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start chat with ${post.userName}.', style: GoogleFonts.dmSans()),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting chat: $e', style: GoogleFonts.dmSans()),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}

// Sub-sheet component for Comments
class PostCommentsSheet extends StatefulWidget {
  final CommunityPostModel post;
  final VoidCallback onCommentAdded;

  const PostCommentsSheet({
    super.key,
    required this.post,
    required this.onCommentAdded,
  });

  @override
  State<PostCommentsSheet> createState() => _PostCommentsSheetState();
}

class _PostCommentsSheetState extends State<PostCommentsSheet> {
  List<CommunityCommentModel> _comments = [];
  bool _isLoading = true;
  bool _isSending = false;
  final TextEditingController _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _fetchComments() async {
    setState(() => _isLoading = true);
    final comments = await ApiService().fetchPostComments(widget.post.postId);
    if (mounted) {
      setState(() {
        _comments = comments;
        _isLoading = false;
      });
    }
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    if (AuthService().currentUser == null) {
      Navigator.pushNamed(context, '/join');
      return;
    }

    setState(() => _isSending = true);
    final result = await ApiService().addPostComment(postId: widget.post.postId, content: text);
    if (mounted) {
      setState(() => _isSending = false);
      if (result != null) {
        _commentController.clear();
        _fetchComments();
        widget.onCommentAdded();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to post comment. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Comments',
                      style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _isLoading
                  ? const Center(child: LoadingIndicatorM3E())
                  : _comments.isEmpty
                      ? Center(
                          child: Text(
                            'No comments yet. Be the first to comment!',
                            style: GoogleFonts.dmSans(color: AppColors.onSurfaceVariant),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(20),
                          itemCount: _comments.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 14),
                          itemBuilder: (context, index) {
                            final c = _comments[index];
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: AppColors.surfaceVariant,
                                  child: Text(
                                    c.userName.isNotEmpty ? c.userName[0].toUpperCase() : 'U',
                                    style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceVariant.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  c.userName,
                                                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 13),
                                                ),
                                                if (c.isUserVerified) const VerifiedBadge(size: 13),
                                              ],
                                            ),
                                            Text(
                                              _formatTimeAgo(c.createdAt),
                                              style: GoogleFonts.dmSans(fontSize: 10, color: AppColors.onSurfaceVariant),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          c.content,
                                          style: GoogleFonts.dmSans(fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      decoration: InputDecoration(
                        hintText: 'Add a comment...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: AppColors.surfaceVariant,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: AppColors.brandYellow, foregroundColor: Colors.white),
                    onPressed: _isSending ? null : _sendComment,
                    icon: _isSending
                        ? const SizedBox(width: 18, height: 18, child: LoadingIndicatorM3E())
                        : const Icon(Icons.send_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}
