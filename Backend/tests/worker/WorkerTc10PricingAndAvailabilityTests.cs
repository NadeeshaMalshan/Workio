using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Superbass.Controllers;
using Superbass.Models;
using Xunit;

namespace Superbass.Tests.WorkerTests
{
    public class WorkerTc10PricingAndAvailabilityTests
    {
        [Fact]
        public async Task UpdatePricingAndAvailability_SuccessfullyUpdatesWorker()
        {
            var repo = new MockWorkerRepository();
            var config = WorkerTestHelper.CreateMockConfiguration();
            var residentRepo = new FakeResidentRepository();
            using var db = WorkerTestHelper.CreateInMemoryDbContext();
            var controller = new WorkersController(repo, config, residentRepo, db);

            // Test 1: Update Pricing
            var pricingDto = new WorkersController.PricingUpdateDto
            {
                PricingModel = "Hourly",
                HourlyRate = 3500m,
                DailyRate = 18000m
            };

            var pricingResult = await controller.UpdatePricing(1, pricingDto);
            var okPricing = Assert.IsType<OkObjectResult>(pricingResult);
            Assert.Contains("Pricing updated successfully", okPricing.Value!.ToString());

            var worker = repo.Workers[0];
            Assert.Equal("Hourly", worker.PricingModel);
            Assert.Equal(3500m, worker.HourlyRate);
            Assert.Equal(18000m, worker.DailyRate);

            // Test 2: Update Availability
            var availDto = new WorkersController.AvailabilityUpdateDto
            {
                IsAvailable = false,
                ScheduleJson = "{\"mon\": false, \"tue\": true}"
            };

            var availResult = await controller.UpdateAvailability(1, availDto);
            var okAvail = Assert.IsType<OkObjectResult>(availResult);
            Assert.Contains("Availability updated successfully", okAvail.Value!.ToString());
            Assert.False(worker.IsAvailable);
        }
    }
}
