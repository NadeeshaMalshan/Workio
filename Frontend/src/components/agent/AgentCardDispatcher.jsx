import React, { Component } from 'react';
import CreateCommunityPostCard from './CreateCommunityPostCard.jsx';
import EditCommunityPostCard from './EditCommunityPostCard.jsx';
import PostConfirmationCard from './PostConfirmationCard.jsx';
import PostCreatedCard from './PostCreatedCard.jsx';
import PostListCard from './PostListCard.jsx';
import PostDetailCard from './PostDetailCard.jsx';
import PostUpdatedCard from './PostUpdatedCard.jsx';
import PostDeletedCard from './PostDeletedCard.jsx';
import UserProfileCard from './UserProfileCard.jsx';
import TextMessageCard from './TextMessageCard.jsx';
import ErrorCard from './ErrorCard.jsx';
import ServiceCategoriesCard from './ServiceCategoriesCard.jsx';
import WorkerListCard from './WorkerListCard.jsx';
import BookingFormCard from './BookingFormCard.jsx';
import BookingConfirmationCard from './BookingConfirmationCard.jsx';
import BookingConfirmedCard from './BookingConfirmedCard.jsx';
import BookingListCard from './BookingListCard.jsx';
import ReviewFormCard from './ReviewFormCard.jsx';
import ReviewSubmittedCard from './ReviewSubmittedCard.jsx';
import DisputeTicketCard from './DisputeTicketCard.jsx';
import InitialWelcomeCard from './InitialWelcomeCard.jsx';

/**
 * Dispatcher component that examines `response_type` and renders the matching UI card.
 */
class CardErrorBoundary extends Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError() {
    return { hasError: true };
  }

  componentDidCatch(error, errorInfo) {
    console.error("Card render error:", error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return <ErrorCard data={{ message: "This card failed to load." }} onAction={this.props.onAction} />;
    }
    return this.props.children;
  }
}

export default function AgentCardDispatcher({ response, onAction }) {
  if (!response) return null;

  const { response_type, message, card_data = {} } = response;

  const renderCard = () => {

  switch (response_type) {
    case 'initial_welcome':
      return <InitialWelcomeCard data={card_data} onAction={onAction} />;
    case 'create_community_post':
      return <CreateCommunityPostCard data={card_data} onAction={onAction} />;
    case 'edit_community_post':
      return <EditCommunityPostCard data={card_data} onAction={onAction} />;
    case 'post_confirmation':
      if (card_data?.action === 'update') {
        return <EditCommunityPostCard data={card_data} onAction={onAction} />;
      }
      return <CreateCommunityPostCard data={card_data} onAction={onAction} />;
    case 'post_created':
      return <PostCreatedCard data={card_data} onAction={onAction} />;

    case 'post_list':
      return <PostListCard data={card_data} onAction={onAction} />;
    case 'post_detail':
      return <PostDetailCard data={card_data} onAction={onAction} />;
    case 'post_updated':
      return <PostUpdatedCard data={card_data} onAction={onAction} />;
    case 'post_deleted':
      return <PostDeletedCard data={card_data} onAction={onAction} />;
    case 'user_profile':
      return <UserProfileCard data={card_data} onAction={onAction} />;
    case 'service_categories':
      return <ServiceCategoriesCard data={card_data} onAction={onAction} />;
    case 'worker_list':
      return <WorkerListCard data={card_data} onAction={onAction} />;
    case 'booking_form':
      return <BookingFormCard data={card_data} onAction={onAction} />;
    case 'booking_confirmation':
      return <BookingConfirmationCard data={card_data} onAction={onAction} />;
    case 'booking_confirmed':
      return <BookingConfirmedCard data={card_data} onAction={onAction} />;
    case 'booking_list':
      return <BookingListCard data={card_data} onAction={onAction} />;
    case 'review_form':
      return <ReviewFormCard data={card_data} onAction={onAction} />;
    case 'review_submitted':
      return <ReviewSubmittedCard data={card_data} onAction={onAction} />;
    case 'dispute_ticket':
      return <DisputeTicketCard data={card_data} onAction={onAction} />;
    case 'error':
      return <ErrorCard data={card_data} onAction={onAction} />;
    case 'text_message':
    default:
            return (
              <TextMessageCard
                data={{
                  ...card_data,
                  text: card_data.text || message,
                  suggestions: card_data.suggestions,
                }}
                onAction={onAction}
              />
            );
  }
  };

  return <CardErrorBoundary onAction={onAction}>{renderCard()}</CardErrorBoundary>;
}
