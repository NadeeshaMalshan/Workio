using System.Collections.Generic;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Superbass.Controllers;
using Superbass.Models;
using Xunit;

namespace Superbass.Tests.WorkerTests
{
    public class WorkerTc08AddSkillValidationTests
    {
        [Fact]
        public async Task AddSkill_ValidatesAgainstOfficialCategories_RejectsInvalidWithBadRequest()
        {
            var repo = new MockWorkerRepository();
            var config = WorkerTestHelper.CreateMockConfiguration();
            var residentRepo = new FakeResidentRepository();
            using var db = WorkerTestHelper.CreateInMemoryDbContext();
            var controller = new WorkersController(repo, config, residentRepo, db);

            // Test 1: Invalid category rejects with BadRequest
            var invalidDto = new WorkersController.WorkerSkillDto
            {
                ServiceName = "Astronaut Repair",
                ExperienceYears = 2,
                Skills = new List<string> { "Rocket Fuel" }
            };

            var badResult = await controller.AddSkill(1, invalidDto);
            var badRequest = Assert.IsType<BadRequestObjectResult>(badResult);
            Assert.Contains("Invalid service category", badRequest.Value!.ToString());

            // Test 2: Valid category succeeds
            var validDto = new WorkersController.WorkerSkillDto
            {
                ServiceName = "Electrical",
                ExperienceYears = 4,
                Skills = new List<string> { "DB Wiring" }
            };

            var goodResult = await controller.AddSkill(1, validDto);
            var okResult = Assert.IsType<OkObjectResult>(goodResult);
            var createdSkill = Assert.IsType<WorkerSkill>(okResult.Value);
            Assert.Equal("Electrical", createdSkill.ServiceName);
        }
    }
}
