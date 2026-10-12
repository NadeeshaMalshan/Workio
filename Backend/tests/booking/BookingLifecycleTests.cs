using System;
using Xunit;
using Superbass.Models;

namespace Superbass.Tests.BookingTests
{
    public class BookingLifecycleTests
    {
        [Fact]
        public void BookingLifecycle_TransitionsThroughValidStatuses()
        {
            var booking = new Booking
            {
                Id = 101,
                ResidentEmail = "resident@test.com",
                WorkerId = 20,
                JobTitle = "AC Servicing",
                Status = "Pending",
                CreatedAt = DateTime.UtcNow
            };

            Assert.Equal("Pending", booking.Status);

            // Step 1: Worker Accepts
            booking.Status = "Accepted";
            booking.UpdatedAt = DateTime.UtcNow;
            Assert.Equal("Accepted", booking.Status);

            // Step 2: Worker Starts Job
            booking.Status = "InProgress";
            booking.UpdatedAt = DateTime.UtcNow;
            Assert.Equal("InProgress", booking.Status);

            // Step 3: Worker Completes Job
            booking.Status = "Completed";
            booking.UpdatedAt = DateTime.UtcNow;
            Assert.Equal("Completed", booking.Status);
        }

        [Fact]
        public void BookingResponseDto_AllowsStatusAndAgreedPriceUpdates()
        {
            var responseDto = new BookingResponseDto
            {
                Status = "Accepted",
                AgreedPrice = 4500m,
                IsContactShared = true
            };

            Assert.Equal("Accepted", responseDto.Status);
            Assert.Equal(4500m, responseDto.AgreedPrice);
            Assert.True(responseDto.IsContactShared);
        }
    }
}
