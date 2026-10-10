using System.Collections.Generic;
using Microsoft.AspNetCore.Mvc;
using Superbass.Controllers;
using Superbass.Models;
using Xunit;

namespace Superbass.Tests.WorkerTests
{
    public class WorkerTc01GetCategoriesTests
    {
        [Fact]
        public void GetCategories_ReturnsAll21OfficialCategories()
        {
            var repo = new MockWorkerRepository();
            var config = WorkerTestHelper.CreateMockConfiguration();
            var residentRepo = new FakeResidentRepository();
            using var db = WorkerTestHelper.CreateInMemoryDbContext();
            var controller = new WorkersController(repo, config, residentRepo, db);

            var result = controller.GetCategories();

            var okResult = Assert.IsType<OkObjectResult>(result);
            var categories = Assert.IsAssignableFrom<IEnumerable<ServiceCategory>>(okResult.Value);
            
            var list = new List<ServiceCategory>(categories);
            Assert.Equal(22, list.Count);
            Assert.Contains(list, c => c.Name == "Plumbing");
            Assert.Contains(list, c => c.Name == "Electrical");
            Assert.Contains(list, c => c.Name == "Carpentry");
        }
    }
}
