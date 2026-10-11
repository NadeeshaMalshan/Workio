using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Superbass.Controllers;
using Superbass.Models;
using Xunit;

namespace Superbass.Tests.WorkerTests
{
    public class WorkerTc03GetByIdSelfVsPublicTests
    {
        [Fact]
        public async Task GetById_ReturnsWorkerWithMaskedPhone_OrNotFound()
        {
            var repo = new MockWorkerRepository();
            var config = WorkerTestHelper.CreateMockConfiguration();
            var residentRepo = new FakeResidentRepository();
            using var db = WorkerTestHelper.CreateInMemoryDbContext();
            var controller = new WorkersController(repo, config, residentRepo, db)
            {
                ControllerContext = new ControllerContext
                {
                    HttpContext = new Microsoft.AspNetCore.Http.DefaultHttpContext()
                }
            };

            // Test 1: Public lookup masks PhoneNo
            var result = await controller.GetById(1);
            var okResult = Assert.IsType<OkObjectResult>(result);
            var worker = Assert.IsType<Worker>(okResult.Value);

            Assert.Equal("Kamal Perera", worker.Name);
            Assert.Null(worker.PhoneNo); // Privacy requirement

            // Test 2: Non-existent worker returns 404
            var notFoundResult = await controller.GetById(999);
            Assert.IsType<NotFoundObjectResult>(notFoundResult);
        }
    }
}
