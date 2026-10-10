import 'package:flutter/material.dart';
import 'worker_list_card.dart';
import 'post_cards.dart';
import 'booking_cards.dart';
import 'review_cards.dart';
import 'service_categories_card.dart';
import 'agent_misc_cards.dart';

class AgentCardDispatcher extends StatelessWidget {
  final String? responseType;
  final Map<String, dynamic>? cardData;
  final String? message;
  final void Function(String actionType, dynamic payload)? onAction;

  const AgentCardDispatcher({
    super.key,
    required this.responseType,
    required this.cardData,
    this.message,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    if (responseType == null && cardData == null) {
      return const SizedBox.shrink();
    }

    final String type = (responseType ?? '').toLowerCase().trim();
    final Map<String, dynamic> data = cardData ?? {};

    switch (type) {
      case 'worker_list':
      case 'worker_recommendation':
        return WorkerListCard(data: data, onAction: onAction);

      case 'post_list':
      case 'community_post_list':
        return PostListCard(data: data, onAction: onAction);

      case 'post_detail':
        return PostDetailCard(data: data, onAction: onAction);

      case 'create_community_post':
        return CreateCommunityPostCard(data: data, onAction: onAction);

      case 'edit_community_post':
        return EditCommunityPostCard(data: data, onAction: onAction);

      case 'post_confirmation':
        if (data['action'] == 'update') {
          return EditCommunityPostCard(data: data, onAction: onAction);
        }
        return CreateCommunityPostCard(data: data, onAction: onAction);

      case 'post_created':
      case 'post_updated':
      case 'post_deleted':
        return PostActionStatusCard(data: data, actionType: type, onAction: onAction);

      case 'booking_list':
      case 'bookings_overview':
        return BookingListCard(data: data, onAction: onAction);

      case 'booking_form':
        return BookingFormCard(data: data, onAction: onAction);

      case 'booking_confirmation':
        return BookingConfirmationCard(data: data, onAction: onAction);

      case 'booking_confirmed':
        return BookingStatusCard(data: data, onAction: onAction);

      case 'review_form':
        return ReviewFormCard(data: data, onAction: onAction);

      case 'review_submitted':
        return ReviewSubmittedCard(data: data, onAction: onAction);

      case 'service_categories':
        return ServiceCategoriesCard(data: data, onAction: onAction);

      case 'user_profile':
        return UserProfileCard(data: data, onAction: onAction);

      case 'dispute_ticket':
        return DisputeTicketCard(data: data, onAction: onAction);

      case 'error':
        return ErrorCard(data: data, onAction: onAction);

      case 'text_message':
      default:
        // If data contains workers or posts despite type being text_message
        if (data.containsKey('workers') && data['workers'] is List) {
          return WorkerListCard(data: data, onAction: onAction);
        }
        if (data.containsKey('posts') && data['posts'] is List) {
          return PostListCard(data: data, onAction: onAction);
        }
        if (data.containsKey('suggestions') && (data['suggestions'] is List && (data['suggestions'] as List).isNotEmpty)) {
          return TextMessageCard(data: data, onAction: onAction);
        }
        return const SizedBox.shrink();
    }
  }
}
