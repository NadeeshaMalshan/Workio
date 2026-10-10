using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Superbass.Controllers;
using Superbass.Models;
using Xunit;

namespace Superbass.Tests.WorkerTests
{
    public class WorkerTc05UpdateWorkerTests
    {
        [Fact]
        public async Task Update_UpdatesExistingWorker_ReturnsUpdatedWorkerOrNotFound()
        {
            var repo = new MockWorkerRepository();
            var config = WorkerTestHelper.CreateMockConfiguration();
            var residentRepo = new FakeResidentRepository();
            using var db = WorkerTestHelper.CreateInMemoryDbContext();
            var controller = new WorkersController(repo, config, residentRepo, db);

            var updatePayload = new Worker
            {
                Name = "Kamal P. Silva",
                Description = "Master Plumber with 10 years experience",
                PrimaryServiceArea = "Colombo South",
                PricingModel = "Hourly",
                HourlyRate = 3000m,
                IsAvailable = true
            };

            // Test 1: Update existing worker
            var result = await controller.Update(1, updatePayload);
            var okResult = Assert.IsType<OkObjectResult>(result);
            var updated = Assert.IsType<Worker>(okResult.Value);

            Assert.Equal("Kamal P. Silva", updated.Name);
            Assert.Equal(3000m, updated.HourlyRate);

            // Test 2: Nonexistent worker
            var notFoundResult = await controller.Update(999, updatePayload);
            Assert.IsType<NotFoundObjectResult>(notFoundResult);
        }
    }
}
