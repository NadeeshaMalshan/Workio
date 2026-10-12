using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Xunit;
using FluentAssertions;
using Superbass.Controllers;
using Superbass.Models;
using Moq;
using Microsoft.EntityFrameworkCore;

namespace Superbass.Tests.ResidentTests
{
    public class ResidentTc09ReviewBookingDuplicateTests
    {
        [Fact]
        public async Task ReviewBooking_Duplicate_ReturnsBadRequest()
        {
            var options = new DbContextOptionsBuilder<SuperbassDbContext>().UseInMemoryDatabase(System.Guid.NewGuid().ToString()).Options;
            using var context = new SuperbassDbContext(options);
            context.Residents.Add(new Resident { Email = "resident2@test.com", Name = "Resident", PhoneNo = "12345" });
            context.Workers.Add(new Worker { Id = 2, Name = "Worker", Email = "worker2@test.com" });
            context.Bookings.Add(new Booking { Id = 2, WorkerId = 2, ResidentEmail = "resident2@test.com", JobTitle = "Electrical", Status = "Reviewed", ReviewRating = 5 });
            await context.SaveChangesAsync();
            var controller = new BookingsController(context, null, null, null);
            var result = await controller.ReviewBooking(2, new ReviewBookingRequest { QualityRating = 1, PunctualityRating = 1, CommunicationRating = 1 });
            // This exposes the duplicate review bug
            result.Should().BeOfType<BadRequestObjectResult>("Because a booking already reviewed should not be reviewed again.");
        }
    }
}
