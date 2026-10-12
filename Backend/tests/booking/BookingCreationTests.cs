using System;
using Xunit;
using Superbass.Models;

namespace Superbass.Tests.BookingTests
{
    public class BookingCreationTests
    {
        [Fact]
        public void CreateBooking_InitializesWithPendingStatus()
        {
            var booking = new Booking
            {
                Id = 1,
                ResidentEmail = "resident@workio.lk",
                WorkerId = 10,
                JobTitle = "Plumbing Leak Fix",
                Description = "Pipe leaking under kitchen sink",
                LocationAddress = "Colombo 03",
                ContactPhone = "0771234567",
                PricingModel = "Hourly",
                EstimatedPrice = 3000,
                Status = "Pending",
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            };

            Assert.Equal("Pending", booking.Status);
            Assert.Equal(10, booking.WorkerId);
            Assert.Equal("resident@workio.lk", booking.ResidentEmail);
            Assert.Equal(3000, booking.EstimatedPrice);
            Assert.False(string.IsNullOrWhiteSpace(booking.JobTitle));
        }

        [Theory]
        [InlineData("Emergency", true)]
        [InlineData("High", true)]
        [InlineData("Medium", true)]
        [InlineData("Low", true)]
        public void CreateBooking_SupportsValidUrgencyLevels(string urgency, bool isValid)
        {
            var dto = new CreateBookingRequest
            {
                WorkerId = 5,
                JobTitle = "Electrical Inspection",
                Urgency = urgency,
                LocationAddress = "Kandy City",
                ContactPhone = "0711112233"
            };

            Assert.True(isValid);
            Assert.Equal(urgency, dto.Urgency);
        }
    }
}
