using System.Collections.Generic;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Superbass.Controllers;
using Superbass.Models;
using Xunit;

namespace Superbass.Tests.WorkerTests
{
    public class WorkerTc09RemoveSkillMinimumConstraintTests
    {
        [Fact]
        public async Task RemoveSkill_EnforcesAtLeastOneServiceRule()
        {
            var repo = new MockWorkerRepository();
            var config = WorkerTestHelper.CreateMockConfiguration();
            var residentRepo = new FakeResidentRepository();
            using var db = WorkerTestHelper.CreateInMemoryDbContext();
            var controller = new WorkersController(repo, config, residentRepo, db);

            // In DB seed, Worker 1 only has 1 skill (skillId 101).
            // Attempting to delete the only active service skill must fail with 400 BadRequest.
            var result = await controller.RemoveSkill(1, 101);
            var badRequest = Assert.IsType<BadRequestObjectResult>(result);
            Assert.Contains("cannot delete your only active service", badRequest.Value!.ToString());

            // Now add a second skill to Worker 1
            var secondSkill = new WorkerSkill
            {
                Id = 103,
                WorkerId = 1,
                ServiceName = "Painting",
                SkillName = "Painting"
            };
            db.WorkerSkills.Add(secondSkill);
            repo.Workers[0].Skills.Add(secondSkill);
            await db.SaveChangesAsync();

            // Deleting one of multiple skills now succeeds
            var successResult = await controller.RemoveSkill(1, 103);
            Assert.IsType<NoContentResult>(successResult);
        }
    }
}
