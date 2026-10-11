using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Superbass.Controllers;
using Xunit;

namespace Superbass.Tests.WorkerTests
{
    public class WorkerTc06DeleteWorkerTests
    {
        [Fact]
        public async Task Delete_ReturnsNoContentOnSuccess_AndNotFoundOnMissing()
        {
            var repo = new MockWorkerRepository();
            var config = WorkerTestHelper.CreateMockConfiguration();
            var residentRepo = new FakeResidentRepository();
            using var db = WorkerTestHelper.CreateInMemoryDbContext();
            var controller = new WorkersController(repo, config, residentRepo, db);

            // Test 1: Successful deletion returns 204 NoContent
            var result = await controller.Delete(1);
            Assert.IsType<NoContentResult>(result);

            // Test 2: Deleting again returns 404 NotFound
            var missingResult = await controller.Delete(1);
            Assert.IsType<NotFoundResult>(missingResult);
        }
    }
}
