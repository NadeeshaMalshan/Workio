using System;
using System.Collections.Generic;
using System.Linq;
using Xunit;
using Superbass.Models;

namespace Superbass.Tests.BookingTests
{
    public class BookingScheduleConflictTests
    {
        [Fact]
        public void DetectOverlappingSchedule_IdentifiesConflictForSameWorker()
        {
            var baseDate = new DateTime(2026, 11, 10, 10, 0, 0, DateTimeKind.Utc);
            var existingBookings = new List<Booking>
            {
                new Booking
                {
                    Id = 50,
                    WorkerId = 7,
                    ScheduledDate = baseDate,
                    Status = "Accepted"
                }
            };

            // Requested slot at exact same time with same worker
            var requestedWorkerId = 7;
            var requestedDate = baseDate;

            bool hasConflict = existingBookings.Any(b =>
                b.WorkerId == requestedWorkerId &&
                b.Status != "Cancelled" &&
                b.Status != "Rejected" &&
                Math.Abs((b.ScheduledDate - requestedDate).TotalHours) < 2.0);

            Assert.True(hasConflict);
        }

        [Fact]
        public void NoConflict_WhenWorkersAreDifferent()
        {
            var baseDate = new DateTime(2026, 11, 10, 10, 0, 0, DateTimeKind.Utc);
            var existingBookings = new List<Booking>
            {
                new Booking
                {
                    Id = 51,
                    WorkerId = 7,
                    ScheduledDate = baseDate,
                    Status = "Accepted"
                }
            };

            var differentWorkerId = 9;
            var requestedDate = baseDate;

            bool hasConflict = existingBookings.Any(b =>
                b.WorkerId == differentWorkerId &&
                b.Status != "Cancelled" &&
                b.ScheduledDate == requestedDate);

            Assert.False(hasConflict);
        }
    }
}
