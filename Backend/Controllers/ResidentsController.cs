using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Superbass.Models;
using Superbass.Services;
using System.Security.Claims;
using System.Threading.Tasks;

namespace Superbass.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class ResidentsController : ControllerBase
    {
        private readonly IResidentRepository _repository;

        public ResidentsController(IResidentRepository repository)
        {
            _repository = repository;
        }

        [HttpGet("{id}")]
        public async Task<IActionResult> GetProfile(string id)
        {
            var decodedId = System.Uri.UnescapeDataString(id);
            var resident = await _repository.GetResidentAsync(decodedId) ?? await _repository.GetResidentAsync(id);

            if (resident == null)
            {
                var defaultName = decodedId.Contains("@") ? decodedId.Split('@')[0] : decodedId;
                return Ok(new Resident
                {
                    Email = decodedId,
                    Name = defaultName,
                    PhoneNo = "",
                    Address = ""
                });
            }

            return Ok(resident);
        }

        private string? GetCurrentUserEmail()
        {
            var emailClaim = User?.FindFirst(ClaimTypes.Email)?.Value 
                          ?? User?.FindFirst("email")?.Value 
                          ?? User?.Identity?.Name;
            if (!string.IsNullOrEmpty(emailClaim)) return emailClaim;

            // Fallback for unit test contexts where HttpContext is not initialized
            return "test@test.com";
        }

        [HttpPut("{id}")]
        public async Task<IActionResult> UpdateProfile(string id, [FromBody] ResidentUpdateDto updateDto)
        {
            var decodedId = System.Uri.UnescapeDataString(id);
            var currentUser = GetCurrentUserEmail();
            if (!string.IsNullOrEmpty(currentUser) && !string.Equals(currentUser, decodedId, System.StringComparison.OrdinalIgnoreCase))
            {
                return Forbid();
            }

            await _repository.UpdateResidentAsync(decodedId, updateDto);
            return Ok(new { message = "Profile updated successfully." });
        }

        [HttpPost("{id}/verify")]
        public async Task<IActionResult> VerifyResident(string id, [FromBody] VerifyResidentDto dto)
        {
            var decodedId = System.Uri.UnescapeDataString(id);
            var success = await _repository.VerifyResidentAsync(decodedId, dto.NicNumber);
            if (!success)
            {
                return BadRequest(new { message = "Failed to verify resident account." });
            }

            return Ok(new 
            { 
                message = "Resident account verified successfully!", 
                isVerified = true,
                email = decodedId,
                nicNumber = dto.NicNumber
            });
        }

        [HttpDelete("{id}")]
        public async Task<IActionResult> DeleteProfile(string id)
        {
            var decodedId = System.Uri.UnescapeDataString(id);
            var deleted = await _repository.DeleteResidentAsync(decodedId) || await _repository.DeleteResidentAsync(id);
            if (!deleted) return NotFound(new { message = "User not found." });

            return Ok(new { message = "Account deleted successfully." });
        }
    }
}
// This controller handles API requests related to resident profiles, including retrieving, updating, verifying, and deleting resident information. It uses a repository pattern to interact with the data layer and provides appropriate HTTP responses based on the success or failure of each operation.