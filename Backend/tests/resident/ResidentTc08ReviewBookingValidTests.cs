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
    public class ResidentTc08ReviewBookingValidTests
    {
        [Fact]
        public async Task ReviewBooking_Valid_ReturnsOk()
        {
            var options = new DbContextOptionsBuilder<SuperbassDbContext>().UseInMemoryDatabase(System.Guid.NewGuid().ToString()).Options;
            using var context = new SuperbassDbContext(options);
            context.Residents.Add(new Resident { Email = "resident1@test.com", Name = "Resident", PhoneNo = "12345" });
            context.Workers.Add(new Worker { Id = 1, Name = "Worker", Email = "worker1@test.com" });
            context.Bookings.Add(new Booking { Id = 1, WorkerId = 1, ResidentEmail = "resident1@test.com", JobTitle = "Plumbing", Status = "Completed" });
            await context.SaveChangesAsync();
            var controller = new BookingsController(context, null, null, null);
            var result = await controller.ReviewBooking(1, new ReviewBookingRequest { QualityRating = 5, PunctualityRating = 5, CommunicationRating = 5 });
            result.Should().BeOfType<OkObjectResult>();
        }
    }
}
