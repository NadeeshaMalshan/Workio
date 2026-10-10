using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Superbass.Controllers;
using Xunit;

namespace Superbass.Tests.WorkerTests
{
    public class WorkerTc07PerformanceMetricsTests
    {
        [Fact]
        public async Task GetPerformance_ReturnsCorrectRatesAndRatings()
        {
            var repo = new MockWorkerRepository();
            var config = WorkerTestHelper.CreateMockConfiguration();
            var residentRepo = new FakeResidentRepository();
            using var db = WorkerTestHelper.CreateInMemoryDbContext();
            var controller = new WorkersController(repo, config, residentRepo, db);

            // Worker 1: Accepted=22, Rejected=2 (Total=24). Completed=20, Cancelled=1 (Total=21)
            var result = await controller.GetPerformance(1);
            var okResult = Assert.IsType<OkObjectResult>(result);

            var obj = okResult.Value!;
            var id = (int)obj.GetType().GetProperty("Id")!.GetValue(obj)!;
            var rating = (double)obj.GetType().GetProperty("OverallRating")!.GetValue(obj)!;
            var completed = (int)obj.GetType().GetProperty("CompletedJobs")!.GetValue(obj)!;
            var cancelled = (int)obj.GetType().GetProperty("CancelledJobs")!.GetValue(obj)!;

            Assert.Equal(1, id);
            Assert.Equal(4.8, rating);
            Assert.Equal(20, completed);
            Assert.Equal(1, cancelled);

            // Test 2: Nonexistent worker
            var notFound = await controller.GetPerformance(999);
            Assert.IsType<NotFoundResult>(notFound);
        }
    }
}
