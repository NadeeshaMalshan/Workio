using Microsoft.AspNetCore.Mvc;
using Superbass.Models;
using Superbass.Services;
using System.Security.Claims;
using System.IdentityModel.Tokens.Jwt;
using Microsoft.IdentityModel.Tokens;
using System.Text;

using Microsoft.EntityFrameworkCore;

namespace Superbass.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class WorkersController : ControllerBase
    {
        private readonly WorkerRepository _workerRepository;
        private readonly IConfiguration _configuration;
        private readonly IResidentRepository _residentRepository;
        private readonly SuperbassDbContext _dbContext;

        public WorkersController(
            WorkerRepository workerRepository,
            IConfiguration configuration,
            IResidentRepository residentRepository,
            SuperbassDbContext dbContext)
        {
            _workerRepository = workerRepository;
            _configuration = configuration;
            _residentRepository = residentRepository;
            _dbContext = dbContext;
        }

        // GET: /api/workers
        [HttpGet]
        public async Task<IActionResult> GetAll([FromQuery] bool? onlyVerified = null)
        {
            var workers = await _workerRepository.GetAllWorkersAsync();
            if (onlyVerified.HasValue)
            {
                workers = workers.Where(w => w.IsVerified == onlyVerified.Value);
            }
            foreach (var w in workers)
            {
                w.PhoneNo = null; // Privacy: Worker contact is hidden until worker explicitly shares it via chat
            }
            return Ok(workers);
        }

        // GET: /api/workers/categories
        [HttpGet("categories")]
        public IActionResult GetCategories()
        {
            return Ok(ServiceCategoryConstants.CategoryDefinitions);
        }

        // GET: /api/workers/5
        [HttpGet("{id}")]
        public async Task<IActionResult> GetById(int id)
        {
            var worker = await _workerRepository.GetWorkerByIdAsync(id);
            if (worker == null) return NotFound(new { message = "Worker not found" });

            var requesterEmail = GetEmailFromRequest();
            var isSelf = !string.IsNullOrEmpty(requesterEmail) && 
                string.Equals(requesterEmail, worker.Email, StringComparison.OrdinalIgnoreCase);

            if (!isSelf)
            {
                worker.PhoneNo = null; // Privacy: Worker contact is hidden on public profile
            }

            return Ok(worker);
        }

        // GET: /api/workers/search?skill=Plumbing&location=Colombo&residentLat=6.9&residentLng=79.8
        [HttpGet("search")]
        public async Task<IActionResult> Search(
            [FromQuery] string? q,
            [FromQuery] string? skill,
            [FromQuery] string? location,
            [FromQuery] string? province,
            [FromQuery] string? district,
            [FromQuery] double? residentLat,
            [FromQuery] double? residentLng,
            [FromQuery] decimal? maxHourlyRate = null,
            [FromQuery] decimal? minHourlyRate = null,
            [FromQuery] bool onlyVerified = true,
            [FromQuery] int page = 1,
            [FromQuery] int pageSize = 20)
        {
            var (workers, totalCount) = await _workerRepository.SearchWorkersAsync(
                q: q, 
                skill: skill, 
                location: location, 
                maxDistanceKm: null, 
                residentLat: residentLat, 
                residentLng: residentLng, 
                maxHourlyRate: maxHourlyRate, 
                minHourlyRate: minHourlyRate, 
                province: province, 
                district: district, 
                onlyVerified: onlyVerified,
                page: page,
                pageSize: pageSize);

            foreach (var w in workers)
            {
                w.PhoneNo = null; // Privacy: Worker contact is hidden on public search
            }

            Response.Headers["X-Total-Count"] = totalCount.ToString();
            return Ok(workers);
        }

        // PUT: /api/workers/5
        [HttpPut("{id}")]
        public async Task<IActionResult> Update(int id, [FromBody] Worker worker)
        {
            var updated = await _workerRepository.UpdateWorkerAsync(id, worker);
            if (updated == null) return NotFound(new { message = "Worker not found" });
            return Ok(updated);
        }

        // DELETE: /api/workers/5
        [HttpDelete("{id}")]
        public async Task<IActionResult> Delete(int id)
        {
            var success = await _workerRepository.DeleteWorkerAsync(id);
            if (!success) return NotFound();
            return NoContent();
        }

                // GET: /api/workers/5/performance
        [HttpGet("{id}/performance")]
        public async Task<IActionResult> GetPerformance(int id)
        {
            var worker = await _workerRepository.GetWorkerByIdAsync(id);
            if (worker == null) return NotFound();

            var totalResponded = worker.AcceptedJobs + worker.RejectedJobs;
            var totalFinished = worker.CompletedJobs + worker.CancelledJobs;

            return Ok(new
            {
                worker.Id,
                worker.Name,
                OverallRating = worker.OverallRating,
                QualityRating = worker.QualityRating,
                PunctualityRating = worker.PunctualityRating,
                CommunicationRating = worker.CommunicationRating,
                worker.CompletedJobs,
                worker.CancelledJobs,
                AcceptanceRate = totalResponded > 0 ? $"{worker.AcceptanceRate:F1}%" : "N/A",
                CompletionRate = totalFinished > 0 ? $"{worker.CompletionRate:F1}%" : "N/A",
                CancellationRate = totalFinished > 0 ? $"{worker.CancellationRate:F1}%" : "N/A"
            });
        }

        // GET: /api/workers/{id}/reviews
        [HttpGet("{id}/reviews")]
        public async Task<IActionResult> GetReviews(int id)
        {
            var reviews = await _dbContext.Bookings
                .Include(b => b.Resident)
                .Where(b => b.WorkerId == id && b.ReviewRating.HasValue)
                .OrderByDescending(b => b.ReviewedAt ?? b.UpdatedAt)
                .Select(b => new
                {
                    b.Id,
                    b.WorkerId,
                    ReviewRating = b.ReviewRating ?? 5.0,
                    QualityRating = b.QualityRating ?? 5,
                    PunctualityRating = b.PunctualityRating ?? 5,
                    CommunicationRating = b.CommunicationRating ?? 5,
                    ReviewComment = b.ReviewComment,
                    ReviewedAt = b.ReviewedAt ?? b.UpdatedAt,
                    ResidentName = b.Resident != null ? b.Resident.Name : "Verified Resident",
                    ResidentAvatar = b.Resident != null ? b.Resident.ProfileImage : null,
                    JobTitle = b.JobTitle ?? "Home Service"
                })
                .ToListAsync();

            return Ok(reviews);
        }

        // POST /api/workers/{id}/skills
        [HttpPost("{id}/skills")]
        public async Task<IActionResult> AddSkill(int id, [FromBody] WorkerSkillDto dto)
        {
            var rawService = !string.IsNullOrWhiteSpace(dto.ServiceName) ? dto.ServiceName : (!string.IsNullOrWhiteSpace(dto.Service) ? dto.Service : dto.SkillName);
            if (!ServiceCategoryConstants.IsValidCategory(rawService))
            {
                return BadRequest(new
                {
                    message = $"Invalid service category '{rawService}'. Workers can only select from the 21 official categories: {string.Join(", ", ServiceCategoryConstants.Categories)}"
                });
            }

            var service = ServiceCategoryConstants.NormalizeCategoryName(rawService);
            var subSkills = dto.Skills != null && dto.Skills.Count > 0 ? dto.Skills : (!string.IsNullOrWhiteSpace(dto.SkillName) && dto.SkillName != service ? new List<string> { dto.SkillName } : new List<string>());

            var skill = new WorkerSkill
            {
                WorkerId = id,
                ServiceName = service,
                Skills = subSkills,
                ExperienceYears = dto.ExperienceYears >= 0 ? dto.ExperienceYears : 0,
                SkillName = service
            };

            var created = await _workerRepository.AddSkillAsync(id, skill);
            if (created == null) return NotFound();
            return Ok(created);
        }

        // DELETE /api/workers/{id}/skills/{skillId}
        [HttpDelete("{id}/skills/{skillId}")]
        public async Task<IActionResult> RemoveSkill(int id, int skillId)
        {
            var totalSkills = await _dbContext.WorkerSkills.CountAsync(s => s.WorkerId == id);
            if (totalSkills <= 1)
            {
                return BadRequest(new { message = "You cannot delete your only active service. A worker must offer at least one service. Please add another service first." });
            }

            var success = await _workerRepository.RemoveSkillAsync(id, skillId);
            if (!success) return NotFound();
            return NoContent();
        }

        // PUT /api/workers/{id}/availability
        [HttpPut("{id}/availability")]
        public async Task<IActionResult> UpdateAvailability(int id, [FromBody] AvailabilityUpdateDto dto)
        {
            var success = await _workerRepository.UpdateAvailabilityAsync(id, dto.IsAvailable, dto.ScheduleJson);
            if (!success) return NotFound();
            return Ok(new { message = "Availability updated successfully" });
        }

        // PUT /api/workers/{id}/pricing
        [HttpPut("{id}/pricing")]
        public async Task<IActionResult> UpdatePricing(int id, [FromBody] PricingUpdateDto dto)
        {
            var success = await _workerRepository.UpdatePricingAsync(id, dto.PricingModel, dto.HourlyRate, dto.DailyRate);
            if (!success) return NotFound();
            return Ok(new { message = "Pricing updated successfully" });
        }

        // PUT /api/workers/{id}/service-area
        [HttpPut("{id}/service-area")]
        public async Task<IActionResult> UpdateServiceArea(int id, [FromBody] ServiceAreaUpdateDto dto)
        {
            var success = await _workerRepository.UpdateServiceAreaAsync(id, dto.ServiceArea, dto.RadiusKm);
            if (!success) return NotFound();
            return Ok(new { message = "Service area updated successfully" });
        }

        // PUT /api/workers/{id}/bio
        [HttpPut("{id}/bio")]
        public async Task<IActionResult> UpdateBio(int id, [FromBody] WorkerBioUpdateDto dto)
        {
            var worker = await _dbContext.Workers.FindAsync(id);
            if (worker == null) return NotFound(new { message = "Worker not found" });

            if (!string.IsNullOrWhiteSpace(dto.Name))
            {
                worker.Name = dto.Name.Trim();
            }
            if (dto.PhoneNo != null)
            {
                worker.PhoneNo = dto.PhoneNo.Trim();
            }
            if (dto.Description != null)
            {
                worker.Description = dto.Description.Trim();
            }
            if (!string.IsNullOrWhiteSpace(dto.ProfileImage))
            {
                worker.ProfileImage = dto.ProfileImage;
            }

            await _dbContext.SaveChangesAsync();

            return Ok(new 
            { 
                message = "Bio details updated successfully",
                worker = new 
                {
                    worker.Id,
                    worker.Name,
                    worker.PhoneNo,
                    worker.Description,
                    worker.ProfileImage
                }
            });
        }

        // POST /api/workers/{id}/verify
        [HttpPost("{id}/verify")]
        public async Task<IActionResult> VerifyWorker(int id, [FromBody] VerifyWorkerDto dto)
        {
            var worker = await _dbContext.Workers.FindAsync(id);
            if (worker == null) return NotFound(new { message = "Worker not found" });

            worker.IsVerified = true;
            if (!string.IsNullOrWhiteSpace(dto.NicNumber))
            {
                worker.NicNumber = dto.NicNumber.Trim();
            }

            // Workers are independent — no sync to residents table

            await _dbContext.SaveChangesAsync();

            return Ok(new 
            { 
                message = "Worker account verified successfully!", 
                isVerified = true,
                workerId = worker.Id,
                nicNumber = worker.NicNumber
            });
        }
        // GET: /api/workers/me
        [HttpGet("me")]
        public async Task<IActionResult> GetMyWorkerProfile([FromQuery] string? email)
        {
            var targetEmail = email ?? GetEmailFromRequest();
            if (string.IsNullOrEmpty(targetEmail))
            {
                return BadRequest(new { message = "Email is required or must be provided in Authorization header." });
            }

            var worker = await _workerRepository.GetWorkerByEmailAsync(targetEmail);
            if (worker == null)
            {
                return Ok(new { worker = (object?)null, activeRole = "Resident", message = "User is not a worker." });
            }

            return Ok(new { worker, activeRole = "Worker" });
        }

        // POST: /api/workers/onboarding
        // Fully and atomically creates the Worker profile ONLY after all onboarding steps are finished.
        [HttpPost("onboarding")]
        public async Task<IActionResult> WorkerOnboarding([FromBody] WorkerOnboardingDto dto)
        {
            var targetEmail = dto.Email ?? GetEmailFromRequest();
            if (string.IsNullOrEmpty(targetEmail))
            {
                return BadRequest(new { message = "Email is required in payload or Authorization header." });
            }

            var cleanEmail = targetEmail.Trim().ToLower();

            // Workers and residents are independent entities — check worker table only
            var existingWorker = await _dbContext.Workers.Include(w => w.Skills)
                .FirstOrDefaultAsync(w => w.Email != null && w.Email.ToLower() == cleanEmail);

            if (dto.Skills == null || !dto.Skills.Any())
            {
                return BadRequest(new { message = "At least one skill category is required." });
            }

            // Category validation
            foreach (var s in dto.Skills)
            {
                var rawService = !string.IsNullOrWhiteSpace(s.ServiceName) ? s.ServiceName : (!string.IsNullOrWhiteSpace(s.Service) ? s.Service : s.SkillName);
                if (!ServiceCategoryConstants.IsValidCategory(rawService))
                {
                    return BadRequest(new
                    {
                        message = $"Invalid service category '{rawService}'. Workers can only select from the 21 official categories."
                    });
                }
            }

            var skills = dto.Skills.Select(s => {
                var rawService = !string.IsNullOrWhiteSpace(s.ServiceName) ? s.ServiceName : (!string.IsNullOrWhiteSpace(s.Service) ? s.Service : s.SkillName);
                var service = ServiceCategoryConstants.NormalizeCategoryName(rawService);
                var subSkills = s.Skills != null && s.Skills.Count > 0 ? s.Skills : (!string.IsNullOrWhiteSpace(s.SkillName) && s.SkillName != service ? new List<string> { s.SkillName } : new List<string>());
                return new WorkerSkill
                {
                    ServiceName = service,
                    Skills = subSkills,
                    ExperienceYears = s.ExperienceYears >= 0 ? s.ExperienceYears : 0,
                    SkillName = service
                };
            }).ToList();

            // Create or Update Worker profile atomically — Resident table is untouched!
            if (existingWorker == null)
            {
                existingWorker = new Worker
                {
                    Email = cleanEmail,
                    Name = dto.Name ?? cleanEmail.Split('@')[0],
                    PhoneNo = dto.PhoneNo,
                    ProfileImage = dto.ProfileImage,
                    Description = dto.Description,
                    PrimaryServiceArea = dto.PrimaryServiceArea ?? "Colombo",
                    Province = dto.Province,
                    District = dto.District,
                    LocationLat = dto.LocationLat,
                    LocationLng = dto.LocationLng,
                    CoverageRadiusKm = dto.CoverageRadiusKm > 0 ? dto.CoverageRadiusKm : 10.0,
                    PricingModel = dto.PricingModel ?? "Hourly",
                    HourlyRate = dto.HourlyRate,
                    DailyRate = dto.DailyRate,
                    IsAvailable = dto.IsAvailable,
                    Skills = skills
                };
                _dbContext.Workers.Add(existingWorker);
            }
            else
            {
                existingWorker.Name = dto.Name ?? existingWorker.Name;
                existingWorker.PhoneNo = dto.PhoneNo ?? existingWorker.PhoneNo;
                if (!string.IsNullOrWhiteSpace(dto.ProfileImage)) existingWorker.ProfileImage = dto.ProfileImage;
                existingWorker.Description = dto.Description ?? existingWorker.Description;
                existingWorker.PrimaryServiceArea = dto.PrimaryServiceArea ?? existingWorker.PrimaryServiceArea;
                if (!string.IsNullOrWhiteSpace(dto.Province)) existingWorker.Province = dto.Province;
                if (!string.IsNullOrWhiteSpace(dto.District)) existingWorker.District = dto.District;
                if (dto.LocationLat.HasValue) existingWorker.LocationLat = dto.LocationLat;
                if (dto.LocationLng.HasValue) existingWorker.LocationLng = dto.LocationLng;
                if (dto.CoverageRadiusKm > 0) existingWorker.CoverageRadiusKm = dto.CoverageRadiusKm;
                existingWorker.PricingModel = dto.PricingModel ?? existingWorker.PricingModel;
                if (dto.HourlyRate.HasValue) existingWorker.HourlyRate = dto.HourlyRate;
                if (dto.DailyRate.HasValue) existingWorker.DailyRate = dto.DailyRate;
                existingWorker.IsAvailable = dto.IsAvailable;

                if (existingWorker.Skills != null && existingWorker.Skills.Any())
                {
                    _dbContext.WorkerSkills.RemoveRange(existingWorker.Skills);
                }
                existingWorker.Skills = skills;
            }

            await _dbContext.SaveChangesAsync();

            return Ok(new
            {
                worker = existingWorker,
                activeRole = "Worker",
                message = "Worker profile successfully created and onboarding completed!"
            });
        }

        // POST: /api/workers/become-worker
        [HttpPost("become-worker")]
        public async Task<IActionResult> BecomeWorker([FromBody] BecomeWorkerDto dto)
        {
            var targetEmail = dto.Email ?? GetEmailFromRequest();
            if (string.IsNullOrEmpty(targetEmail))
            {
                return BadRequest(new { message = "Email is required in payload or Authorization header." });
            }

            try
            {
                if (dto.Skills == null || !dto.Skills.Any())
                {
                    return BadRequest(new { message = "At least one skill category is required." });
                }

                // Strict validation: Worker can ONLY select from the 21 official categories
                foreach (var s in dto.Skills)
                {
                    var rawService = !string.IsNullOrWhiteSpace(s.ServiceName) ? s.ServiceName : (!string.IsNullOrWhiteSpace(s.Service) ? s.Service : s.SkillName);
                    if (!ServiceCategoryConstants.IsValidCategory(rawService))
                    {
                        return BadRequest(new
                        {
                            message = $"Invalid service category '{rawService}'. Workers can only select from the 21 official categories: {string.Join(", ", ServiceCategoryConstants.Categories)}"
                        });
                    }
                }

                var skills = dto.Skills.Select(s => {
                    var rawService = !string.IsNullOrWhiteSpace(s.ServiceName) ? s.ServiceName : (!string.IsNullOrWhiteSpace(s.Service) ? s.Service : s.SkillName);
                    var service = ServiceCategoryConstants.NormalizeCategoryName(rawService);
                    var subSkills = s.Skills != null && s.Skills.Count > 0 ? s.Skills : (!string.IsNullOrWhiteSpace(s.SkillName) && s.SkillName != service ? new List<string> { s.SkillName } : new List<string>());
                    return new WorkerSkill
                    {
                        ServiceName = service,
                        Skills = subSkills,
                        ExperienceYears = s.ExperienceYears >= 0 ? s.ExperienceYears : 0,
                        SkillName = service
                    };
                }).ToList();

                var worker = await _workerRepository.CreateWorkerDirectAsync(
                    targetEmail,
                    null,
                    dto.Description,
                    dto.PrimaryServiceArea,
                    dto.CoverageRadiusKm,
                    dto.PricingModel,
                    dto.HourlyRate,
                    dto.DailyRate,
                    skills
                );

                return CreatedAtAction(nameof(GetById), new { id = worker.Id }, new { worker, activeRole = "Worker", message = "Successfully upgraded to Worker." });
            }
            catch (KeyNotFoundException ex)
            {
                return NotFound(new { message = ex.Message });
            }
            catch (InvalidOperationException ex)
            {
                return BadRequest(new { message = ex.Message });
            }
        }



        // DELETE: /api/workers/delete-account
        [HttpDelete("delete-account")]
        public async Task<IActionResult> DeleteWorkerAccount([FromQuery] string? email)
        {
            var targetEmail = email ?? GetEmailFromRequest();
            if (string.IsNullOrEmpty(targetEmail))
            {
                return BadRequest(new { message = "Email is required or must be provided in Authorization header." });
            }

            var deleted = await _workerRepository.DeleteWorkerByEmailAsync(targetEmail);
            if (!deleted)
            {
                var worker = await _workerRepository.GetWorkerByEmailAsync(targetEmail);
                if (worker != null)
                {
                    await _workerRepository.DeleteWorkerAsync(worker.Id);
                }
            }

            return Ok(new { message = "Worker account and all associated data permanently deleted." });
        }

        private string? GetEmailFromRequest()
        {
            var emailClaim = User?.FindFirst(ClaimTypes.Email)?.Value ?? User?.FindFirst("email")?.Value;
            if (!string.IsNullOrEmpty(emailClaim)) return emailClaim;

            var authHeader = Request.Headers["Authorization"].FirstOrDefault();
            if (authHeader != null && authHeader.StartsWith("Bearer "))
            {
                var token = authHeader.Substring("Bearer ".Length).Trim();
                var tokenHandler = new JwtSecurityTokenHandler();
                var key = Encoding.ASCII.GetBytes(_configuration["Authentication:Jwt:Secret"] ?? "super_secret_key_that_must_be_long_enough_12345");
                
                try
                {
                    tokenHandler.ValidateToken(token, new TokenValidationParameters
                    {
                        ValidateIssuerSigningKey = true,
                        IssuerSigningKey = new SymmetricSecurityKey(key),
                        ValidateIssuer = false,
                        ValidateAudience = false,
                        ClockSkew = TimeSpan.Zero
                    }, out SecurityToken validatedToken);

                    var jwtToken = (JwtSecurityToken)validatedToken;
                    var claim = jwtToken.Claims.FirstOrDefault(x => x.Type == ClaimTypes.Email || x.Type == "email" || x.Type.Contains("emailaddress"));
                    if (claim != null) return claim.Value;
                }
                catch
                {
                    // Ignore token parse errors and fall through
                }
            }

            return null;
        }

        // DTOs for new endpoints
        public class BecomeWorkerDto
        {
            public string? Email { get; set; }
            public string? Description { get; set; }
            public string PrimaryServiceArea { get; set; } = "Default Area";
            public double CoverageRadiusKm { get; set; } = 10.0;
            public string PricingModel { get; set; } = "Hourly";
            public decimal? HourlyRate { get; set; }
            public decimal? DailyRate { get; set; }
            public List<WorkerSkillDto> Skills { get; set; } = new();
        }

        public class WorkerSkillDto
        {
            public string? ServiceName { get; set; }
            public string? Service { get; set; } // Alias for convenience
            public string? SkillName { get; set; } // Fallback
            public List<string> Skills { get; set; } = new(); // Array of skills relevant to the service
            public int ExperienceYears { get; set; } = 1;
        }

        public class AvailabilityUpdateDto
        {
            public bool IsAvailable { get; set; }
            public string? ScheduleJson { get; set; }
        }

        public class PricingUpdateDto
        {
            public string PricingModel { get; set; } = string.Empty;
            public decimal? HourlyRate { get; set; }
            public decimal? DailyRate { get; set; }
        }

        public class ServiceAreaUpdateDto
        {
            public string ServiceArea { get; set; } = string.Empty;
            public double RadiusKm { get; set; }
        }

        public class PasswordUpdateDto
        {
            public string NewPassword { get; set; } = string.Empty;
        }

        public class WorkerBioUpdateDto
        {
            public string? Name { get; set; }
            public string? PhoneNo { get; set; }
            public string? Description { get; set; }
            public string? ProfileImage { get; set; }
        }

        public class WorkerOnboardingDto
        {
            public string? Name { get; set; }
            public string? Email { get; set; }
            public string? PhoneNo { get; set; }
            public string? Address { get; set; }
            public string? ProfileImage { get; set; }
            public double? LocationLat { get; set; }
            public double? LocationLng { get; set; }
            public string? Description { get; set; }
            public string? PrimaryServiceArea { get; set; } = "Colombo";
            public string? Province { get; set; }
            public string? District { get; set; }
            public double CoverageRadiusKm { get; set; } = 10.0;
            public string PricingModel { get; set; } = "Hourly";
            public decimal? HourlyRate { get; set; }
            public decimal? DailyRate { get; set; }
            public bool IsAvailable { get; set; } = true;
            public List<WorkerSkillDto> Skills { get; set; } = new();
        }

        public class VerifyWorkerDto
        {
            public string? NicNumber { get; set; }
            public string? DateOfBirth { get; set; }
            public string? Gender { get; set; }
        }
    }
}
