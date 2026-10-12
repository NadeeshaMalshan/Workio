using System;
using Xunit;
using Superbass.Models;

namespace Superbass.Tests.BookingTests
{
    public class ChatConversationInitializationTests
    {
        [Fact]
        public void CreateConversation_InitializesParticipantsCorrectly()
        {
            var conversation = new Conversation
            {
                Id = 12,
                ResidentEmail = "resident@workio.lk",
                WorkerId = 5,
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            };

            Assert.Equal("resident@workio.lk", conversation.ResidentEmail);
            Assert.Equal(5, conversation.WorkerId);
            Assert.True(conversation.CreatedAt <= DateTime.UtcNow);
        }

        [Fact]
        public void ConversationSummaryDto_ExposesUnreadCountAndParticipants()
        {
            var dto = new ConversationSummaryDto
            {
                Id = 12,
                ResidentEmail = "resident@workio.lk",
                WorkerEmail = "worker@workio.lk",
                WorkerName = "Sunil Electrician",
                LastMessage = "I am on the way.",
                LastMessageAt = DateTime.UtcNow,
                UnreadCount = 3
            };

            Assert.Equal(3, dto.UnreadCount);
            Assert.Equal("resident@workio.lk", dto.ResidentEmail);
            Assert.Equal("worker@workio.lk", dto.WorkerEmail);
            Assert.Equal("Sunil Electrician", dto.WorkerName);
        }
    }
}
