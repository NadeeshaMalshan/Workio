import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/booking_model.dart';
import '../models/community_post_model.dart';
import '../models/worker_model.dart';
import 'api_config.dart';
import 'auth_service.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  Map<String, String> get _headers {
    final token = AuthService().currentUser?.token;
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// 1. Fetch Workers from /api/workers or /api/workers/search
  Future<List<WorkerModel>> fetchWorkers({
    String? q,
    int? page,
    int? pageSize,
    String? skill,
    String? location,
    double? residentLat,
    double? residentLng,
    bool onlyVerified = true,
  }) async {
    try {
      final user = AuthService().currentUserNotifier.value;
      final lat = residentLat ?? user?.locationLat;
      final lng = residentLng ?? user?.locationLng;
      Uri uri;

      final queryParams = <String, String>{
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        if (page != null) 'page': page.toString(),
        if (pageSize != null) 'pageSize': pageSize.toString(),
        if (skill != null && skill.isNotEmpty && skill != 'All Pros') 'skill': skill,
        if (location != null && location.isNotEmpty) 'location': location,
        if (lat != null) 'residentLat': lat.toString(),
        if (lng != null) 'residentLng': lng.toString(),
        'onlyVerified': onlyVerified.toString(),
      };

      if ((skill != null && skill.isNotEmpty && skill != 'All Pros') ||
          (location != null && location.isNotEmpty) ||
          (lat != null && lng != null) ||
          (q != null && q.trim().isNotEmpty)) {
        uri = Uri.parse('${ApiConfig.baseUrl}/api/workers/search').replace(
          queryParameters: queryParams,
        );
      } else {
        uri = Uri.parse('${ApiConfig.baseUrl}/api/workers').replace(
          queryParameters: {
            'onlyVerified': onlyVerified.toString(),
            if (page != null) 'page': page.toString(),
            if (pageSize != null) 'pageSize': pageSize.toString(),
          },
        );
      }

      debugPrint('Fetching workers from: $uri');
      final response = await http.get(uri, headers: _headers);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dynamic data = jsonDecode(response.body);
        if (data is List) {
          return data.map((json) => WorkerModel.fromJson(json as Map<String, dynamic>)).toList();
        }
      }
      debugPrint('Failed to load workers (${response.statusCode}): ${response.body}');
      return [];
    } catch (e) {
      debugPrint('Error fetching workers: $e');
      return [];
    }
  }

  // ==========================================
  // COMMUNITY POSTS API ENDPOINTS
  // ==========================================

  /// Fetch Service Categories from GET /api/community-posts/categories
  Future<List<ServiceCategoryModel>> fetchCommunityCategories() async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/community-posts/categories');
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dynamic data = jsonDecode(response.body);
        if (data is List) {
          return data.map((json) => ServiceCategoryModel.fromJson(json as Map<String, dynamic>)).toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching community categories: $e');
      return [];
    }
  }

  /// Fetch Community Posts from GET /api/community-posts?search=&category=&location=&sort=
  Future<List<CommunityPostModel>> fetchCommunityPosts({
    String? category,
    String? search,
    String? location,
    String? sort,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/community-posts').replace(
        queryParameters: {
          if (category != null && category.isNotEmpty && category.toLowerCase() != 'all') 'category': category,
          if (search != null && search.isNotEmpty) 'search': search,
          if (location != null && location.isNotEmpty && location.toLowerCase() != 'all') 'location': location,
          if (sort != null && sort.isNotEmpty) 'sort': sort,
        },
      );

      debugPrint('Fetching community posts from: $uri');
      final response = await http.get(uri, headers: _headers);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dynamic data = jsonDecode(response.body);
        final currentUserEmail = AuthService().currentUser?.email;
        if (data is List) {
          return data
              .map((json) => CommunityPostModel.fromJson(json as Map<String, dynamic>, currentUserEmail: currentUserEmail))
              .toList();
        }
      }
      debugPrint('Failed to load community posts (${response.statusCode}): ${response.body}');
      return [];
    } catch (e) {
      debugPrint('Error fetching community posts: $e');
      return [];
    }
  }

  /// Fetch User's Own Community Posts from GET /api/community-posts/user/{email}
  Future<List<CommunityPostModel>> fetchUserCommunityPosts(String email) async {
    try {
      final encodedEmail = Uri.encodeComponent(email);
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/community-posts/user/$encodedEmail');
      debugPrint('Fetching user community posts from: $uri');
      final response = await http.get(uri, headers: _headers);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dynamic data = jsonDecode(response.body);
        final currentUserEmail = AuthService().currentUser?.email;
        if (data is List) {
          return data
              .map((json) => CommunityPostModel.fromJson(json as Map<String, dynamic>, currentUserEmail: currentUserEmail))
              .toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching user community posts: $e');
      return [];
    }
  }

  /// Fetch single Post Details: GET /api/community-posts/{id}
  Future<CommunityPostModel?> fetchCommunityPostById(int id) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/community-posts/$id');
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final currentUserEmail = AuthService().currentUser?.email;
        return CommunityPostModel.fromJson(data, currentUserEmail: currentUserEmail);
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching community post #$id: $e');
      return null;
    }
  }

  /// Create Post: POST /api/community-posts
  Future<CommunityPostModel?> createCommunityPost({
    required String title,
    required String content,
    String? serviceCategoryId,
    String? location,
    List<String>? images,
    String? authorRole,
    String? workerTrade,
    double? workerRating,
  }) async {
    try {
      final user = AuthService().currentUser;
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/community-posts');

      final body = jsonEncode({
        'title': title,
        'content': content,
        'serviceCategoryId': (serviceCategoryId != null && serviceCategoryId.isNotEmpty) ? serviceCategoryId : 'general',
        'location': (location != null && location.isNotEmpty) ? location : 'Colombo',
        'images': images ?? [],
        'userName': user?.name ?? 'Resident',
        'userAvatar': user?.picture ?? '',
        'userEmail': user?.email ?? 'demo_user_1',
        'userId': user?.email ?? 'demo_user_1',
        if (authorRole != null && authorRole.isNotEmpty) 'authorRole': authorRole,
        if (workerTrade != null && workerTrade.isNotEmpty) 'workerTrade': workerTrade,
        if (workerRating != null && workerRating > 0) 'workerRating': workerRating,
      });

      debugPrint('Creating post: $body');
      final response = await http.post(uri, headers: _headers, body: body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return CommunityPostModel.fromJson(data, currentUserEmail: user?.email);
      }
      debugPrint('Failed to create post (${response.statusCode}): ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Error creating community post: $e');
      return null;
    }
  }

  /// Update Post: PUT /api/community-posts/{id}
  Future<CommunityPostModel?> updateCommunityPost({
    required int id,
    required String title,
    required String content,
    String? serviceCategoryId,
    String? location,
    List<String>? images,
  }) async {
    try {
      final user = AuthService().currentUser;
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/community-posts/$id');

      final body = jsonEncode({
        'title': title,
        'content': content,
        'serviceCategoryId': (serviceCategoryId != null && serviceCategoryId.isNotEmpty) ? serviceCategoryId : 'general',
        'location': (location != null && location.isNotEmpty) ? location : 'Colombo',
        'images': images ?? [],
        'userName': user?.name ?? 'Resident',
        'userEmail': user?.email ?? 'demo_user_1',
        'userId': user?.email ?? 'demo_user_1',
      });

      debugPrint('Updating post #$id: $body');
      final response = await http.put(uri, headers: _headers, body: body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return CommunityPostModel.fromJson(data, currentUserEmail: user?.email);
      }
      debugPrint('Failed to update post (${response.statusCode}): ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Error updating community post: $e');
      return null;
    }
  }

  /// Delete Post: DELETE /api/community-posts/{id}
  Future<bool> deleteCommunityPost(int id, {String? requesterEmail, String? requesterName}) async {
    try {
      final user = AuthService().currentUser;
      final email = requesterEmail ?? user?.email ?? 'demo_user_1';
      final name = requesterName ?? user?.name ?? 'Resident';

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/community-posts/$id').replace(
        queryParameters: {
          'requesterEmail': email,
          'requesterName': name,
        },
      );

      debugPrint('Deleting post #$id: $uri');
      final response = await http.delete(uri, headers: _headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
      debugPrint('Failed to delete post (${response.statusCode}): ${response.body}');
      return false;
    } catch (e) {
      debugPrint('Error deleting community post: $e');
      return false;
    }
  }

  /// Fetch Post Comments: GET /api/community-posts/{id}/comments
  Future<List<CommunityCommentModel>> fetchPostComments(int postId) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/community-posts/$postId/comments');
      final response = await http.get(uri, headers: _headers);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dynamic data = jsonDecode(response.body);
        if (data is List) {
          return data.map((json) => CommunityCommentModel.fromJson(json as Map<String, dynamic>)).toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching comments for post #$postId: $e');
      return [];
    }
  }

  /// Add Comment to Post: POST /api/community-posts/{id}/comments
  Future<CommunityCommentModel?> addPostComment({
    required int postId,
    required String content,
  }) async {
    try {
      final user = AuthService().currentUser;
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/community-posts/$postId/comments');

      final body = jsonEncode({
        'content': content,
        'userName': user?.name ?? 'Resident',
        'userAvatar': user?.picture ?? '',
        'userEmail': user?.email ?? '',
        'userId': user?.email ?? '',
      });

      debugPrint('Adding comment to post #$postId: $body');
      final response = await http.post(uri, headers: _headers, body: body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return CommunityCommentModel.fromJson(data);
      }
      debugPrint('Failed to add comment (${response.statusCode}): ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Error adding comment: $e');
      return null;
    }
  }

  /// Toggle Like on Post: POST /api/community-posts/{id}/like
  Future<Map<String, dynamic>?> togglePostLike(int postId) async {
    try {
      final user = AuthService().currentUser;
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/community-posts/$postId/like');
      final body = jsonEncode({
        'userId': user?.email ?? 'demo_user_1',
        'userEmail': user?.email ?? '',
        'userName': user?.name ?? 'Resident',
      });
      final response = await http.post(uri, headers: _headers, body: body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      debugPrint('Failed to toggle like (${response.statusCode}): ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Error toggling post like: $e');
      return null;
    }
  }

  /// Report Post: POST /api/community-posts/{id}/report
  Future<bool> reportCommunityPost({
    required int postId,
    required String reason,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/community-posts/$postId/report');
      final body = jsonEncode({'reason': reason});

      final response = await http.post(uri, headers: _headers, body: body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
      debugPrint('Failed to report post (${response.statusCode}): ${response.body}');
      return false;
    } catch (e) {
      debugPrint('Error reporting post: $e');
      return false;
    }
  }

  // ==========================================
  // BOOKINGS & CHAT API ENDPOINTS
  // ==========================================

  /// 3. Fetch Bookings for resident from /api/bookings/resident?email=...
  Future<List<BookingModel>> fetchResidentBookings(String residentEmail) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/bookings/resident').replace(
        queryParameters: {'email': residentEmail},
      );

      debugPrint('Fetching bookings from: $uri');
      final response = await http.get(uri, headers: _headers);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dynamic data = jsonDecode(response.body);
        if (data is List) {
          return data.map((json) => BookingModel.fromJson(json as Map<String, dynamic>)).toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching bookings: $e');
      return [];
    }
  }

  /// 3b. Fetch Bookings for worker from /api/bookings/worker?email=...
  Future<List<BookingModel>> fetchWorkerBookings(String workerEmail) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/bookings/worker').replace(
        queryParameters: {'email': workerEmail},
      );

      debugPrint('Fetching worker bookings from: $uri');
      final response = await http.get(uri, headers: _headers);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dynamic data = jsonDecode(response.body);
        if (data is List) {
          return data.map((json) => BookingModel.fromJson(json as Map<String, dynamic>)).toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching worker bookings: $e');
      return [];
    }
  }

  /// 4. Create a new Booking: POST /api/bookings
  Future<BookingModel?> createBooking({
    required int workerId,
    required String jobTitle,
    required String description,
    required String urgency,
    DateTime? scheduledDate,
    String? locationAddress,
    String? contactPhone,
    double? estimatedPrice,
    String pricingModel = 'Hourly',
    double? locationLat,
    double? locationLng,
  }) async {
    try {
      final residentEmail = AuthService().currentUser?.email ?? 'resident@superbass.lk';
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/bookings');

      final body = jsonEncode({
        'workerId': workerId,
        'residentEmail': residentEmail,
        'jobTitle': jobTitle,
        'description': description,
        'urgency': urgency,
        'scheduledDate': (scheduledDate ?? DateTime.now().add(const Duration(days: 1))).toIso8601String(),
        'locationAddress': locationAddress ?? 'Colombo',
        'contactPhone': contactPhone ?? '0771234567',
        'pricingModel': pricingModel,
        'estimatedPrice': estimatedPrice ?? 2500.0,
        if (locationLat != null) 'locationLat': locationLat, // ignore: use_null_aware_elements
        if (locationLng != null) 'locationLng': locationLng, // ignore: use_null_aware_elements
      });

      debugPrint('Creating booking: $body');
      final response = await http.post(uri, headers: _headers, body: body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return BookingModel.fromJson(data);
      }
      debugPrint('Failed to create booking (${response.statusCode}): ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Error creating booking: $e');
      return null;
    }
  }

  /// 4b. Cancel a booking: POST /api/bookings/{id}/cancel
  Future<bool> cancelBooking(int bookingId, {String reason = 'Cancelled by resident'}) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/bookings/$bookingId/cancel');
      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode({'reason': reason}),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
      debugPrint('Failed to cancel booking (${response.statusCode}): ${response.body}');
      return false;
    } catch (e) {
      debugPrint('Error cancelling booking: $e');
      return false;
    }
  }

  // ==========================================
  // WORKER MANAGEMENT API ENDPOINTS
  // ==========================================

  /// Get current user's worker profile: GET /api/workers/me?email=...
  Future<WorkerModel?> fetchMyWorkerProfile(String email) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/workers/me').replace(
        queryParameters: {'email': email},
      );
      debugPrint('Fetching worker profile from: $uri');
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['worker'] != null) {
          return WorkerModel.fromJson(data['worker'] as Map<String, dynamic>);
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching worker profile: $e');
      return null;
    }
  }

  /// Get worker performance analytics: GET /api/workers/{id}/performance
  Future<Map<String, dynamic>?> fetchWorkerPerformance(int workerId) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/workers/$workerId/performance');
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching worker performance: $e');
      return null;
    }
  }

  /// Accept a booking request: POST /api/bookings/{id}/accept
  Future<BookingModel?> acceptBooking(int bookingId) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/bookings/$bookingId/accept');
      final response = await http.post(uri, headers: _headers, body: jsonEncode({}));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        return BookingModel.fromJson(data as Map<String, dynamic>);
      }
      debugPrint('Failed to accept booking (${response.statusCode}): ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Error accepting booking: $e');
      return null;
    }
  }

  /// Reject / Decline a booking request: POST /api/bookings/{id}/reject
  Future<BookingModel?> rejectBooking(int bookingId, {String? reason}) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/bookings/$bookingId/reject');
      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode({'reason': reason ?? 'Worker schedule unavailable'}),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        return BookingModel.fromJson(data as Map<String, dynamic>);
      }
      debugPrint('Failed to reject booking (${response.statusCode}): ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Error rejecting booking: $e');
      return null;
    }
  }

  /// Mark booking as started (in progress): POST /api/bookings/{id}/start
  Future<BookingModel?> startBooking(int bookingId) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/bookings/$bookingId/start');
      final response = await http.post(uri, headers: _headers, body: jsonEncode({}));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        return BookingModel.fromJson(data as Map<String, dynamic>);
      }
      debugPrint('Failed to start booking (${response.statusCode}): ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Error starting booking: $e');
      return null;
    }
  }

  /// Mark booking as completed: POST /api/bookings/{id}/complete
  Future<BookingModel?> completeBooking(int bookingId) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/bookings/$bookingId/complete');
      final response = await http.post(uri, headers: _headers, body: jsonEncode({}));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        return BookingModel.fromJson(data as Map<String, dynamic>);
      }
      debugPrint('Failed to complete booking (${response.statusCode}): ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Error completing booking: $e');
      return null;
    }
  }

  /// Submit a review for a completed booking: POST /api/bookings/{id}/review
  Future<BookingModel?> submitReview(int bookingId, {
    required int qualityRating,
    required int punctualityRating,
    required int communicationRating,
    required String reviewComment,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/bookings/$bookingId/review');
      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode({
          'qualityRating': qualityRating,
          'punctualityRating': punctualityRating,
          'communicationRating': communicationRating,
          'reviewComment': reviewComment,
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        return BookingModel.fromJson(data as Map<String, dynamic>);
      }
      debugPrint('Failed to submit review (${response.statusCode}): ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Error submitting review: $e');
      return null;
    }
  }

  /// Update Worker Availability & Schedule: PUT /api/workers/{id}/availability
  Future<bool> updateWorkerAvailability(
    int workerId, {
    required bool isAvailable,
    String? scheduleJson,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/workers/$workerId/availability');
      final payload = <String, dynamic>{
        'isAvailable': isAvailable,
      };
      if (scheduleJson != null) {
        payload['scheduleJson'] = scheduleJson;
      }
      final response = await http.put(
        uri,
        headers: _headers,
        body: jsonEncode(payload),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('Error updating worker availability: $e');
      return false;
    }
  }

  /// Update Worker Pricing: PUT /api/workers/{id}/pricing
  Future<bool> updateWorkerPricing(
    int workerId, {
    required String pricingModel,
    double? hourlyRate,
    double? dailyRate,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/workers/$workerId/pricing');
      final response = await http.put(
        uri,
        headers: _headers,
        body: jsonEncode({
          'pricingModel': pricingModel,
          'hourlyRate': hourlyRate ?? 0.0,
          'dailyRate': dailyRate ?? 0.0,
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('Error updating worker pricing: $e');
      return false;
    }
  }

  /// Update Worker Service Area: PUT /api/workers/{id}/service-area
  Future<bool> updateWorkerServiceArea(
    int workerId, {
    required String serviceArea,
    required double radiusKm,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/workers/$workerId/service-area');
      final response = await http.put(
        uri,
        headers: _headers,
        body: jsonEncode({
          'serviceArea': serviceArea,
          'radiusKm': radiusKm,
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('Error updating worker service area: $e');
      return false;
    }
  }

  /// Update Worker Bio & Personal details: PUT /api/workers/{id}/bio with fallback to PUT /api/workers/{id}
  Future<bool> updateWorkerBio(
    int workerId, {
    required String name,
    required String phoneNo,
    required String description,
    String? profileImage,
    WorkerModel? currentWorker,
  }) async {
    try {
      final bioUri = Uri.parse('${ApiConfig.baseUrl}/api/workers/$workerId/bio');
      final bioPayload = <String, dynamic>{
        'name': name,
        'phoneNo': phoneNo,
        'description': description,
      };
      if (profileImage != null) {
        bioPayload['profileImage'] = profileImage;
      }
      final bioResponse = await http.put(
        bioUri,
        headers: _headers,
        body: jsonEncode(bioPayload),
      );
      if (bioResponse.statusCode >= 200 && bioResponse.statusCode < 300) {
        return true;
      }

      // If /bio returns 404 (e.g. Render hosted backend has not deployed the new route yet),
      // fall back to standard PUT /api/workers/{id}
      if (bioResponse.statusCode == 404) {
        debugPrint('/api/workers/$workerId/bio 404. Falling back to PUT /api/workers/$workerId');
        final fallbackUri = Uri.parse('${ApiConfig.baseUrl}/api/workers/$workerId');
        final fallbackPayload = <String, dynamic>{
          'id': workerId,
          'email': currentWorker?.email ?? AuthService().currentUser?.email ?? '',
          'name': name,
          'phoneNo': phoneNo,
          'description': description,
          'profileImage': profileImage ?? currentWorker?.profileImage,
          'primaryServiceArea': currentWorker?.primaryServiceArea ?? 'Colombo',
          'coverageRadiusKm': currentWorker?.coverageRadiusKm ?? 10.0,
          'pricingModel': currentWorker?.pricingModel ?? 'Hourly',
          'hourlyRate': currentWorker?.hourlyRate ?? 1500.0,
          'dailyRate': currentWorker?.dailyRate ?? 8000.0,
          'isAvailable': currentWorker?.isAvailable ?? true,
        };
        if (currentWorker?.availabilityScheduleJson != null) {
          fallbackPayload['availabilityScheduleJson'] = currentWorker!.availabilityScheduleJson;
        }
        if (currentWorker?.locationLat != null) {
          fallbackPayload['locationLat'] = currentWorker!.locationLat;
        }
        if (currentWorker?.locationLng != null) {
          fallbackPayload['locationLng'] = currentWorker!.locationLng;
        }
        final fallbackResponse = await http.put(
          fallbackUri,
          headers: _headers,
          body: jsonEncode(fallbackPayload),
        );
        return fallbackResponse.statusCode >= 200 && fallbackResponse.statusCode < 300;
      }

      debugPrint('Failed to update worker bio (${bioResponse.statusCode}): ${bioResponse.body}');
      return false;
    } catch (e) {
      debugPrint('Error updating worker bio: $e');
      return false;
    }
  }

  /// Update Worker Password: PUT /api/workers/{id}/password
  Future<bool> updateWorkerPassword(int workerId, String newPassword) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/workers/$workerId/password');
      final response = await http.put(
        uri,
        headers: _headers,
        body: jsonEncode({'newPassword': newPassword}),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('Error updating worker password: $e');
      return false;
    }
  }

  /// Add Worker Skill / Service: POST /api/workers/{id}/skills
  Future<WorkerSkillItem?> addWorkerSkill(
    int workerId, {
    required String serviceName,
    List<String> skills = const [],
    int experienceYears = 1,
    String? skillName,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/workers/$workerId/skills');
      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode({
          'serviceName': serviceName,
          'service': serviceName,
          'skills': skills,
          'experienceYears': experienceYears,
          'skillName': skillName ?? serviceName,
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        return WorkerSkillItem.fromJson(data as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('Error adding worker skill: $e');
      return null;
    }
  }

  /// Remove Worker Skill: DELETE /api/workers/{id}/skills/{skillId}
  Future<bool> removeWorkerSkill(int workerId, int skillId) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/workers/$workerId/skills/$skillId');
      final response = await http.delete(uri, headers: _headers);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('Error removing worker skill: $e');
      return false;
    }
  }

  /// Complete Worker Onboarding: POST /api/workers/onboarding
  Future<Map<String, dynamic>> workerOnboarding({
    required String email,
    required String name,
    required String phoneNo,
    String? address,
    String? profileImage,
    String? description,
    required String primaryServiceArea,
    String? province,
    String? district,
    double? locationLat,
    double? locationLng,
    double coverageRadiusKm = 10.0,
    String pricingModel = 'Hourly',
    double? hourlyRate,
    double? dailyRate,
    required List<Map<String, dynamic>> skills,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/workers/onboarding');
      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode({
          'email': email,
          'name': name,
          'phoneNo': phoneNo,
          'address': address,
          'profileImage': profileImage,
          'description': description,
          'primaryServiceArea': primaryServiceArea,
          'province': province,
          'district': district,
          'locationLat': locationLat,
          'locationLng': locationLng,
          'coverageRadiusKm': coverageRadiusKm,
          'pricingModel': pricingModel,
          'hourlyRate': hourlyRate,
          'dailyRate': dailyRate,
          'isAvailable': true,
          'skills': skills,
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        return {'success': true, 'data': data};
      }
      final err = jsonDecode(response.body);
      return {'success': false, 'message': err['message'] ?? 'Failed to complete worker onboarding'};
    } catch (e) {
      debugPrint('Error in worker onboarding: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Permanently delete Worker Account: DELETE /api/workers/delete-account?email=...
  Future<bool> deleteWorkerAccount(String email) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/workers/delete-account').replace(
        queryParameters: {'email': email},
      );
      final response = await http.delete(uri, headers: _headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
      debugPrint('Failed to delete worker account (${response.statusCode}): ${response.body}');
      return false;
    } catch (e) {
      debugPrint('Error deleting worker account: $e');
      return false;
    }
  }

  /// Upgrade Resident to Worker: POST /api/workers/become-worker
  Future<WorkerModel?> becomeWorker({
    required String email,
    required String description,
    required String primaryServiceArea,
    required double coverageRadiusKm,
    required String pricingModel,
    double? hourlyRate,
    double? dailyRate,
    required List<Map<String, dynamic>> skills,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/workers/become-worker');
      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode({
          'email': email,
          'description': description,
          'primaryServiceArea': primaryServiceArea,
          'coverageRadiusKm': coverageRadiusKm,
          'pricingModel': pricingModel,
          'hourlyRate': hourlyRate ?? 0.0,
          'dailyRate': dailyRate ?? 0.0,
          'skills': skills,
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['worker'] != null) {
          return WorkerModel.fromJson(data['worker'] as Map<String, dynamic>);
        }
      }
      debugPrint('Failed to become worker (${response.statusCode}): ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Error becoming worker: $e');
      return null;
    }
  }

  /// 5. Fetch user conversations: GET /api/conversations?userEmail=...
  Future<List<Map<String, dynamic>>> fetchConversations(String userEmail) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/conversations').replace(
        queryParameters: {'userEmail': userEmail},
      );

      final response = await http.get(uri, headers: _headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dynamic data = jsonDecode(response.body);
        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching conversations: $e');
      return [];
    }
  }

  /// 5.1 Create or get existing conversation: POST /api/conversations
  Future<Map<String, dynamic>?> getOrCreateConversation({
    int workerId = 0,
    String? workerEmail,
    String? workerName,
    String? workerAvatar,
    String? residentEmail,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/conversations');
      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode({
          'workerId': workerId,
          'workerEmail': workerEmail,
          'workerName': workerName,
          'workerAvatar': workerAvatar,
          'residentEmail': residentEmail,
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Error creating/getting conversation: $e');
      return null;
    }
  }

  /// 5.5 Fetch conversation details: GET /api/conversations/{id}
  Future<Map<String, dynamic>?> fetchConversationDetails(int conversationId, String userEmail) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/conversations/$conversationId').replace(
        queryParameters: {'userEmail': userEmail},
      );
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching conversation details: $e');
      return null;
    }
  }

  /// 6. Fetch messages for a conversation: GET /api/conversations/{id}/messages
  Future<List<Map<String, dynamic>>> fetchMessages(int conversationId, String userEmail) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/conversations/$conversationId/messages').replace(
        queryParameters: {'userEmail': userEmail},
      );
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dynamic data = jsonDecode(response.body);
        if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching messages: $e');
      return [];
    }
  }

  /// 7. Send a message to a conversation
  Future<Map<String, dynamic>?> sendMessage({
    required int conversationId,
    required String content,
    required String senderEmail,
    String senderRole = 'Resident',
    String? attachmentUrl,
    String? messageType,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/conversations/$conversationId/messages');
      final Map<String, dynamic> bodyMap = {
        'senderEmail': senderEmail,
        'senderRole': senderRole,
        'content': content,
      };
      if (attachmentUrl != null && attachmentUrl.isNotEmpty) {
        bodyMap['attachmentUrl'] = attachmentUrl;
      }
      if (messageType != null && messageType.isNotEmpty) {
        bodyMap['messageType'] = messageType;
      }
      final body = jsonEncode(bodyMap);

      final response = await http.post(uri, headers: _headers, body: body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        debugPrint('Failed to send message: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Error sending message: $e');
      return null;
    }
  }

  /// 8. Mark conversation messages as read: POST /api/conversations/{id}/read
  Future<bool> markConversationAsRead(int conversationId, String readerEmail) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/conversations/$conversationId/read');
      final body = jsonEncode({'readerEmail': readerEmail});
      final response = await http.post(uri, headers: _headers, body: body);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('Error marking conversation $conversationId as read: $e');
      return false;
    }
  }

  /// 9. Delete/Unsend messages: POST /api/conversations/messages/delete?userEmail={email}
  Future<bool> deleteMessages(List<int> messageIds, String userEmail) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/conversations/messages/delete').replace(
        queryParameters: {'userEmail': userEmail},
      );
      final body = jsonEncode(messageIds);
      final response = await http.post(
        uri,
        headers: {
          ..._headers,
          'Content-Type': 'application/json',
        },
        body: body,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
      debugPrint('Delete messages failed (${response.statusCode}): ${response.body}');
      return false;
    } catch (e) {
      debugPrint('Error deleting messages: $e');
      return false;
    }
  }

  /// Delete/Clear conversation: DELETE /api/conversations/{id}?userEmail={email}
  Future<bool> deleteConversation(int conversationId, String userEmail) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/conversations/$conversationId').replace(
        queryParameters: {'userEmail': userEmail},
      );
      final response = await http.delete(uri, headers: _headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
      debugPrint('Delete conversation failed (${response.statusCode}): ${response.body}');
      return false;
    } catch (e) {
      debugPrint('Error deleting conversation: $e');
      return false;
    }
  }

  /// Complete Onboarding: POST /api/auth/onboarding
  Future<Map<String, dynamic>> completeOnboarding({
    required String phoneNo,
    required String address,
    double? locationLat,
    double? locationLng,
  }) async {
    try {
      final uri = Uri.parse(ApiConfig.onboardingUrl);
      final body = jsonEncode({
        'phoneNo': phoneNo,
        'address': address,
        'locationLat': locationLat,
        'locationLng': locationLng,
      });
      debugPrint('Completing onboarding via: $uri');
      final response = await http.post(uri, headers: _headers, body: body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'success': true, 'message': 'Onboarding complete'};
      }

      String errorMsg = 'Failed to complete onboarding (${response.statusCode})';
      try {
        final errJson = jsonDecode(response.body);
        if (errJson['message'] != null) {
          errorMsg = errJson['message'];
        }
      } catch (_) {}
      return {'success': false, 'message': errorMsg};
    } catch (e) {
      debugPrint('Error completing onboarding: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Get Resident Profile: GET /api/residents/{email}
  Future<Map<String, dynamic>?> getResidentProfile(String email) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/residents/${Uri.encodeComponent(email)}');
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      debugPrint('Failed to get resident profile: ${response.statusCode} - ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Error getting resident profile: $e');
      return null;
    }
  }

  /// Get User Address: GET /api/residents/{email} (extract address from profile)
  Future<String?> getUserAddress(String email) async {
    try {
      final profile = await getResidentProfile(email);
      if (profile != null && profile.containsKey('address')) {
        return profile['address'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('Error getting user address: $e');
      return null;
    }
  }

  /// Update Profile: PUT /api/residents/{email}
  Future<bool> updateProfile(String email, Map<String, dynamic> data) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/residents/${Uri.encodeComponent(email)}');
      final response = await http.put(uri, headers: _headers, body: jsonEncode(data));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
      debugPrint('Failed to update profile: ${response.statusCode} - ${response.body}');
      return false;
    } catch (e) {
      debugPrint('Error updating profile: $e');
      return false;
    }
  }

  /// Delete Profile: DELETE /api/residents/{email}
  Future<bool> deleteProfile(String email) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/residents/${Uri.encodeComponent(email)}');
      final response = await http.delete(uri, headers: _headers);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
      debugPrint('Failed to delete profile: ${response.statusCode} - ${response.body}');
      return false;
    } catch (e) {
      debugPrint('Error deleting profile: $e');
      return false;
    }
  }

  /// Verify Resident Account: POST /api/residents/{email}/verify
  Future<bool> verifyResident(String email, {String? nicNumber}) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/residents/${Uri.encodeComponent(email)}/verify');
      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode({'nicNumber': nicNumber ?? ''}),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
      debugPrint('Failed to verify resident: ${response.statusCode} - ${response.body}');
      return false;
    } catch (e) {
      debugPrint('Error verifying resident: $e');
      return false;
    }
  }

  /// Verify Worker Account: POST /api/workers/{id}/verify
  Future<bool> verifyWorker(int workerId, {String? nicNumber}) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/workers/$workerId/verify');
      final response = await http.post(
        uri,
        headers: _headers,
        body: jsonEncode({'nicNumber': nicNumber ?? ''}),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
      debugPrint('Failed to verify worker: ${response.statusCode} - ${response.body}');
      return false;
    } catch (e) {
      debugPrint('Error verifying worker: $e');
      return false;
    }
  }
}