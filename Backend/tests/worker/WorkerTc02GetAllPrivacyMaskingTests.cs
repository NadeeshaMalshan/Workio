using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Superbass.Controllers;
using Superbass.Models;
using Xunit;

namespace Superbass.Tests.WorkerTests
{
    public class WorkerTc02GetAllPrivacyMaskingTests
    {
        [Fact]
        public async Task GetAll_MasksPhoneNumbersForPrivacy_AndFiltersVerified()
        {
            var repo = new MockWorkerRepository();
            var config = WorkerTestHelper.CreateMockConfiguration();
            var residentRepo = new FakeResidentRepository();
            using var db = WorkerTestHelper.CreateInMemoryDbContext();
            var controller = new WorkersController(repo, config, residentRepo, db);

            // Test 1: GetAll with null onlyVerified returns all workers with PhoneNo = null
            var resultAll = await controller.GetAll(onlyVerified: null);
            var okResult = Assert.IsType<OkObjectResult>(resultAll);
            var workers = Assert.IsAssignableFrom<IEnumerable<Worker>>(okResult.Value).ToList();

            Assert.Equal(2, workers.Count);
            foreach (var w in workers)
            {
                Assert.Null(w.PhoneNo);
            }

            // Test 2: GetAll with onlyVerified = true returns only verified workers
            var resultVerified = await controller.GetAll(onlyVerified: true);
            var okVerified = Assert.IsType<OkObjectResult>(resultVerified);
            var verifiedWorkers = Assert.IsAssignableFrom<IEnumerable<Worker>>(okVerified.Value).ToList();

            Assert.Single(verifiedWorkers);
            Assert.True(verifiedWorkers[0].IsVerified);
            Assert.Null(verifiedWorkers[0].PhoneNo);
        }
    }
}
