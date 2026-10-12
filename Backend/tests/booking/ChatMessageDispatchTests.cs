using System;
using Xunit;
using Superbass.Models;

namespace Superbass.Tests.BookingTests
{
    public class ChatMessageDispatchTests
    {
        [Fact]
        public void CreateChatMessage_PopulatesPayloadAndDefaultsToUnread()
        {
            var msg = new ChatMessage
            {
                Id = 100,
                ConversationId = 15,
                SenderEmail = "resident@workio.lk",
                ReceiverEmail = "worker@workio.lk",
                Content = "Could you bring an extra valve?",
                CreatedAt = DateTime.UtcNow,
                IsRead = false
            };

            Assert.Equal(15, msg.ConversationId);
            Assert.Equal("resident@workio.lk", msg.SenderEmail);
            Assert.Equal("worker@workio.lk", msg.ReceiverEmail);
            Assert.Equal("Could you bring an extra valve?", msg.Content);
            Assert.False(msg.IsRead);
            Assert.Null(msg.ReadAt);
        }

        [Fact]
        public void SendMessageRequest_CarriesContentAndReceiver()
        {
            var dto = new SendMessageRequest
            {
                ReceiverEmail = "worker@workio.lk",
                Content = "Yes, I will bring it."
            };

            Assert.Equal("worker@workio.lk", dto.ReceiverEmail);
            Assert.Equal("Yes, I will bring it.", dto.Content);
        }
    }
}
