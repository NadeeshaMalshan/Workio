using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Superbass.Controllers;
using Superbass.Models;
using Xunit;

namespace Superbass.Tests.WorkerTests
{
    public class WorkerTc04SearchWorkersTests
    {
        [Fact]
        public async Task Search_ReturnsMatchingWorkers_SetsTotalCountHeader()
        {
            var repo = new MockWorkerRepository();
            var config = WorkerTestHelper.CreateMockConfiguration();
            var residentRepo = new FakeResidentRepository();
            using var db = WorkerTestHelper.CreateInMemoryDbContext();
            var controller = new WorkersController(repo, config, residentRepo, db)
            {
                ControllerContext = new ControllerContext
                {
                    HttpContext = new DefaultHttpContext()
                }
            };

            var result = await controller.Search(
                q: "Kamal",
                skill: null,
                location: "Colombo",
                province: null,
                district: null,
                residentLat: null,
                residentLng: null,
                onlyVerified: true);

            var okResult = Assert.IsType<OkObjectResult>(result);
            var workers = Assert.IsAssignableFrom<IEnumerable<Worker>>(okResult.Value).ToList();

            Assert.Single(workers);
            Assert.Equal("Kamal Perera", workers[0].Name);
            Assert.Null(workers[0].PhoneNo);
            Assert.Equal("1", controller.Response.Headers["X-Total-Count"].ToString());
        }
    }
}
