using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Claims;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Cors;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Superbass.Models;
using Superbass.Services;
using Microsoft.AspNetCore.Authorization;

namespace Superbass.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    [EnableCors("AllowFrontend")]
    [Authorize]
    public class BookingsController : ControllerBase
    {
        private readonly SuperbassDbContext _context;
        private readonly ICommunicationRepository _communicationRepo;
        private readonly IHubContext<ChatHub> _hubContext;
        private readonly IPushNotificationService _pushNotificationService;

        public BookingsController(
            SuperbassDbContext context,
            ICommunicationRepository communicationRepo,
            IHubContext<ChatHub> hubContext,
            IPushNotificationService pushNotificationService)
        {
            _context = context;
            _communicationRepo = communicationRepo;
            _hubContext = hubContext;
            _pushNotificationService = pushNotificationService;
        }

        private string? GetCurrentUserEmail()
        {
            var email = User.FindFirstValue(ClaimTypes.Email)
                     ?? User.FindFirstValue("email")
                     ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
            if (!string.IsNullOrEmpty(email)) return email;

            var authHeader = Request.Headers["Authorization"].FirstOrDefault();
            if (!string.IsNullOrEmpty(authHeader) && authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
            {
                try
                {
                    var token = authHeader.Substring("Bearer ".Length).Trim();
                    var handler = new System.IdentityModel.Tokens.Jwt.JwtSecurityTokenHandler();
                    var jwtToken = handler.ReadJwtToken(token);
                    return jwtToken.Claims.FirstOrDefault(c => c.Type == "email" || c.Type == ClaimTypes.Email || c.Type == ClaimTypes.NameIdentifier)?.Value;
                }
                catch { }
            }
            return null;
        }

        private static BookingResponseDto MapToDto(Booking b)
        {
            return new BookingResponseDto
            {
                Id = b.Id,
                ResidentEmail = b.ResidentEmail,
                ResidentName = b.Resident?.Name ?? b.ResidentEmail.Split('@')[0],
                ResidentPhone = b.Resident?.PhoneNo ?? b.ContactPhone,
                ResidentProfileImage = b.Resident?.ProfileImage,
                WorkerId = b.WorkerId,
                WorkerName = b.Worker?.Name ?? "Worker",
                WorkerEmail = b.Worker?.Email ?? string.Empty,
                WorkerPhone = b.IsContactShared ? b.Worker?.PhoneNo : null,
                WorkerProfileImage = b.Worker?.ProfileImage,
                JobTitle = b.JobTitle,
                Description = b.Description,
                Urgency = b.Urgency,
                ScheduledDate = b.ScheduledDate,
                LocationAddress = b.LocationAddress,
                LocationLat = b.LocationLat,
                LocationLng = b.LocationLng,
                ContactPhone = b.ContactPhone,
                PricingModel = b.PricingModel,
                EstimatedPrice = b.EstimatedPrice,
                AgreedPrice = b.AgreedPrice,
                Status = b.Status,
                RejectionReason = b.RejectionReason,
                CancellationReason = b.CancellationReason,
                ReviewRating = b.ReviewRating,
                QualityRating = b.QualityRating,
                PunctualityRating = b.PunctualityRating,
                CommunicationRating = b.CommunicationRating,
                ReviewComment = b.ReviewComment,
                ReviewedAt = b.ReviewedAt,
                ConversationId = b.ConversationId,
                IsContactShared = b.IsContactShared,
                IsWorkerVerified = b.Worker?.IsVerified ?? false,
                IsResidentVerified = b.Resident?.IsVerified ?? false,
                CreatedAt = b.CreatedAt,
                UpdatedAt = b.UpdatedAt
            };
        }

        // POST: /api/bookings
        [HttpPost]
        [AllowAnonymous]
        public async Task<IActionResult> CreateBooking([FromBody] CreateBookingRequest request)
        {
            try
            {
                if (request == null || request.WorkerId <= 0 || string.IsNullOrWhiteSpace(request.JobTitle))
                {
                    return BadRequest(new { message = "Worker ID and Job Title are required." });
                }

                var residentEmail = request.ResidentEmail ?? GetCurrentUserEmail();
                if (string.IsNullOrWhiteSpace(residentEmail))
                {
                    residentEmail = "resident@superbass.lk";
                }

                // Reject if hiring account is a worker
                var isWorkerAccount = await _context.Workers.AnyAsync(w => w.Email == residentEmail);
                if (isWorkerAccount)
                {
                    return BadRequest(new { message = "Workers are not permitted to hire or create bookings. Please switch to a Resident account to book services." });
                }

                // Ensure Resident exists
                var resident = await _context.Residents.FindAsync(residentEmail);
                if (resident == null)
                {
                    resident = new Resident
                    {
                        Email = residentEmail,
                        Name = residentEmail.Split('@')[0],
                        PhoneNo = request.ContactPhone ?? "0771234567"
                    };
                    _context.Residents.Add(resident);
                    await _context.SaveChangesAsync();
                }

                // Ensure Worker exists
                var worker = await _context.Workers.FindAsync(request.WorkerId);
                if (worker == null)
                {
                    return NotFound(new { message = $"Worker with ID {request.WorkerId} not found." });
                }

                // Create or Link Conversation
                int? conversationId = null;
                try
                {
                    var convSummary = await _communicationRepo.GetOrCreateConversationAsync(new CreateConversationRequest
                    {
                        WorkerId = worker.Id,
                        WorkerEmail = worker.Email,
                        WorkerName = worker.Name,
                        WorkerAvatar = worker.ProfileImage,
                        ResidentEmail = residentEmail,
                        InitialMessage = $"New Hire Request: {request.JobTitle} scheduled for {(request.ScheduledDate ?? DateTime.UtcNow.AddDays(1)):dd MMM yyyy}."
                    }, residentEmail);
                    conversationId = convSummary.Id;
                }
                catch (Exception)
                {
                    // Fallback: Continue booking creation even if chat linking encounters a non-critical error
                }

                var scheduledUtc = request.ScheduledDate.HasValue 
                    ? DateTime.SpecifyKind(request.ScheduledDate.Value.Date, DateTimeKind.Utc)
                    : DateTime.SpecifyKind(DateTime.UtcNow.AddDays(1).Date, DateTimeKind.Utc);

                var booking = new Booking
                {
                    ResidentEmail = residentEmail,
                    WorkerId = worker.Id,
                    JobTitle = request.JobTitle,
                    Description = request.Description ?? string.Empty,
                    Urgency = request.Urgency ?? "Medium",
                    ScheduledDate = scheduledUtc,
                    LocationAddress = request.LocationAddress ?? resident.Address ?? "Colombo",
                    LocationLat = request.LocationLat ?? resident.LocationLat,
                    LocationLng = request.LocationLng ?? resident.LocationLng,
                    ContactPhone = request.ContactPhone ?? resident.PhoneNo ?? string.Empty,
                    PricingModel = request.PricingModel ?? worker.PricingModel ?? "Hourly",
                    EstimatedPrice = request.EstimatedPrice ?? (worker.HourlyRate ?? worker.DailyRate),
                    Status = "Requested",
                    ConversationId = conversationId,
                    CreatedAt = DateTime.UtcNow,
                    UpdatedAt = DateTime.UtcNow
                };

                _context.Bookings.Add(booking);
                await _context.SaveChangesAsync();

                // Send notification message inside conversation
                if (conversationId.HasValue)
                {
                    try
                    {
                        await _communicationRepo.SendMessageAsync(conversationId.Value, residentEmail, "Resident", new SendMessageRequest
                        {
                            SenderEmail = residentEmail,
                            SenderRole = "Resident",
                            MessageType = "BookingUpdate",
                            Content = $"📋 Booking Requested #{booking.Id}: {booking.JobTitle} ({booking.Urgency} Priority)"
                        });
                    }
                    catch { }
                }

                // Reload with navigations
                var savedBooking = await _context.Bookings
                    .Include(b => b.Resident)
                    .Include(b => b.Worker)
                    .FirstAsync(b => b.Id == booking.Id);

                // Send OneSignal push notification to worker
                var workerTargetEmail = worker.Email;
                if (!string.IsNullOrWhiteSpace(workerTargetEmail))
                {
                    try
                    {
                        _ = _pushNotificationService.SendPushNotificationAsync(
                            recipientEmail: workerTargetEmail,
                            title: "New Booking Request! 📋",
                            message: $"New request for '{booking.JobTitle}' from {resident.Name}.",
                            data: new Dictionary<string, string>
                            {
                                { "bookingId", booking.Id.ToString() },
                                { "type", "booking" }
                            }
                        );
                    }
                    catch { }
                }

                return StatusCode(201, MapToDto(savedBooking));
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"[Error in CreateBooking]: {ex}");
                return StatusCode(500, new { message = "Failed to create booking: " + ex.Message });
            }
        }

        // GET: /api/bookings/{id}
        [HttpGet("{id:int}")]
        [AllowAnonymous]
        public async Task<IActionResult> GetBookingById(int id)
        {
            var booking = await _context.Bookings
                .Include(b => b.Resident)
                .Include(b => b.Worker)
                .FirstOrDefaultAsync(b => b.Id == id);

            if (booking == null)
            {
                return NotFound(new { message = "Booking not found." });
            }

            return Ok(MapToDto(booking));
        }

        // GET: /api/bookings/resident?email=...
        [HttpGet("resident")]
        [AllowAnonymous]
        public async Task<IActionResult> GetResidentBookings([FromQuery] string? email)
        {
            var userEmail = email ?? GetCurrentUserEmail();
            if (string.IsNullOrWhiteSpace(userEmail))
            {
                return BadRequest(new { message = "Resident email is required." });
            }

            var bookings = await _context.Bookings
                .Include(b => b.Resident)
                .Include(b => b.Worker)
                .Where(b => b.ResidentEmail == userEmail)
                .OrderByDescending(b => b.CreatedAt)
                .ToListAsync();

            return Ok(bookings.Select(MapToDto));
        }

        // GET: /api/bookings/worker?email=... or ?workerId=...
        [HttpGet("worker")]
        [AllowAnonymous]
        public async Task<IActionResult> GetWorkerBookings([FromQuery] string? email, [FromQuery] int? workerId)
        {
            var query = _context.Bookings
                .Include(b => b.Resident)
                .Include(b => b.Worker)
                .AsQueryable();

            if (workerId.HasValue && workerId.Value > 0)
            {
                query = query.Where(b => b.WorkerId == workerId.Value);
            }
            else
            {
                var userEmail = email ?? GetCurrentUserEmail();
                if (string.IsNullOrWhiteSpace(userEmail))
                {
                    return BadRequest(new { message = "Worker ID or email is required." });
                }
                query = query.Where(b => b.Worker != null && b.Worker.Email == userEmail);
            }

            var bookings = await query.OrderByDescending(b => b.CreatedAt).ToListAsync();
            return Ok(bookings.Select(MapToDto));
        }

        // POST: /api/bookings/{id}/accept
        [HttpPost("{id:int}/accept")]
        public async Task<IActionResult> AcceptBooking(int id)
        {
            var booking = await _context.Bookings
                .Include(b => b.Resident)
                .Include(b => b.Worker)
                .FirstOrDefaultAsync(b => b.Id == id);

            if (booking == null) return NotFound(new { message = "Booking not found." });

            booking.Status = "Confirmed";
            booking.UpdatedAt = DateTime.UtcNow;

            if (booking.Worker != null)
            {
                booking.Worker.AcceptedJobs += 1;
            }

            // Ensure private booking chat conversation exists
            if (!booking.ConversationId.HasValue)
            {
                try
                {
                    var conv = await _communicationRepo.GetOrCreateConversationAsync(new CreateConversationRequest
                    {
                        WorkerId = booking.WorkerId,
                        ResidentEmail = booking.ResidentEmail,
                        BookingId = booking.Id,
                        WorkerEmail = booking.Worker?.Email,
                        WorkerName = booking.Worker?.Name,
                        WorkerAvatar = booking.Worker?.ProfileImage
                    }, booking.ResidentEmail);
                    booking.ConversationId = conv.Id;
                }
                catch { }
            }

            await _context.SaveChangesAsync();

            // Send notification message to conversation
            if (booking.ConversationId.HasValue)
            {
                try
                {
                    await _communicationRepo.SendMessageAsync(booking.ConversationId.Value, booking.Worker?.Email ?? "worker", "Worker", new SendMessageRequest
                    {
                        SenderEmail = booking.Worker?.Email,
                        SenderRole = "Worker",
                        MessageType = "BookingUpdate",
                        Content = $"✅ Booking Confirmed! The worker has accepted your request for {booking.JobTitle}."
                    });
                }
                catch { }
            }

            // Send OneSignal push to resident
            _ = _pushNotificationService.SendPushNotificationAsync(
                recipientEmail: booking.ResidentEmail,
                title: "Booking Confirmed! 🎉",
                message: $"{booking.Worker?.Name ?? "Worker"} has accepted your booking for '{booking.JobTitle}'.",
                data: new Dictionary<string, string> { { "bookingId", booking.Id.ToString() }, { "type", "booking" } }
            );

            return Ok(MapToDto(booking));
        }

        // POST: /api/bookings/{id}/reject
        [HttpPost("{id:int}/reject")]
        public async Task<IActionResult> RejectBooking(int id, [FromBody] UpdateBookingStatusRequest? request)
        {
            var booking = await _context.Bookings
                .Include(b => b.Resident)
                .Include(b => b.Worker)
                .FirstOrDefaultAsync(b => b.Id == id);

            if (booking == null) return NotFound(new { message = "Booking not found." });

            booking.Status = "Rejected";
            booking.RejectionReason = request?.Reason ?? "Worker unavailable at this time.";
            booking.UpdatedAt = DateTime.UtcNow;

            if (booking.Worker != null)
            {
                booking.Worker.RejectedJobs += 1;
            }

            await _context.SaveChangesAsync();

            if (booking.ConversationId.HasValue)
            {
                try
                {
                    await _communicationRepo.SendMessageAsync(booking.ConversationId.Value, booking.Worker?.Email ?? "worker", "Worker", new SendMessageRequest
                    {
                        SenderEmail = booking.Worker?.Email,
                        SenderRole = "Worker",
                        MessageType = "BookingUpdate",
                        Content = $"❌ Booking Declined: {booking.RejectionReason}"
                    });
                }
                catch { }
            }

            // Send OneSignal push to resident
            _ = _pushNotificationService.SendPushNotificationAsync(
                recipientEmail: booking.ResidentEmail,
                title: "Booking Declined ❌",
                message: $"Your booking for '{booking.JobTitle}' was declined: {booking.RejectionReason}",
                data: new Dictionary<string, string> { { "bookingId", booking.Id.ToString() }, { "type", "booking" } }
            );

            return Ok(MapToDto(booking));
        }

        // POST: /api/bookings/{id}/start
        [HttpPost("{id:int}/start")]
        public async Task<IActionResult> StartBooking(int id)
        {
            var booking = await _context.Bookings
                .Include(b => b.Resident)
                .Include(b => b.Worker)
                .FirstOrDefaultAsync(b => b.Id == id);

            if (booking == null) return NotFound(new { message = "Booking not found." });

            // Check if worker already has another job in progress
            var isAlreadyBusy = await _context.Bookings.AnyAsync(b => b.WorkerId == booking.WorkerId && b.Id != booking.Id && b.Status == "InProgress");
            if (isAlreadyBusy)
            {
                return BadRequest(new { message = "You already have another job in progress. Please complete it before starting a new job." });
            }

            booking.Status = "InProgress";
            booking.UpdatedAt = DateTime.UtcNow;

            // Mark worker as Busy (IsAvailable = false)
            if (booking.Worker != null)
            {
                booking.Worker.IsAvailable = false;
            }

            await _context.SaveChangesAsync();

            if (booking.ConversationId.HasValue)
            {
                try
                {
                    await _communicationRepo.SendMessageAsync(booking.ConversationId.Value, booking.Worker?.Email ?? "worker", "Worker", new SendMessageRequest
                    {
                        SenderEmail = booking.Worker?.Email,
                        SenderRole = "Worker",
                        MessageType = "BookingUpdate",
                        Content = $"🚀 Job In Progress: Worker has started working on '{booking.JobTitle}'."
                    });
                }
                catch { }
            }

            // Send OneSignal push to resident
            _ = _pushNotificationService.SendPushNotificationAsync(
                recipientEmail: booking.ResidentEmail,
                title: "Job In Progress 🚀",
                message: $"Worker has started working on '{booking.JobTitle}'.",
                data: new Dictionary<string, string> { { "bookingId", booking.Id.ToString() }, { "type", "booking" } }
            );

            return Ok(MapToDto(booking));
        }

        // POST: /api/bookings/{id}/complete
        [HttpPost("{id:int}/complete")]
        public async Task<IActionResult> CompleteBooking(int id)
        {
            var booking = await _context.Bookings
                .Include(b => b.Resident)
                .Include(b => b.Worker)
                .FirstOrDefaultAsync(b => b.Id == id);

            if (booking == null) return NotFound(new { message = "Booking not found." });

            booking.Status = "Completed";
            booking.UpdatedAt = DateTime.UtcNow;

            if (booking.Worker != null)
            {
                booking.Worker.CompletedJobs += 1;

                // Check if worker has any remaining in-progress jobs
                var hasOtherActiveJobs = await _context.Bookings.AnyAsync(b => b.WorkerId == booking.WorkerId && b.Id != booking.Id && b.Status == "InProgress");
                if (!hasOtherActiveJobs)
                {
                    booking.Worker.IsAvailable = true; // Worker is Available again!
                }
            }

            await _context.SaveChangesAsync();

            if (booking.ConversationId.HasValue)
            {
                try
                {
                    await _communicationRepo.SendMessageAsync(booking.ConversationId.Value, booking.Worker?.Email ?? "worker", "Worker", new SendMessageRequest
                    {
                        SenderEmail = booking.Worker?.Email,
                        SenderRole = "Worker",
                        MessageType = "BookingUpdate",
                        Content = $"🎉 Job Completed! Worker has marked '{booking.JobTitle}' as finished. Please leave a rating and review."
                    });
                }
                catch { }
            }

            // Send OneSignal push to resident
            _ = _pushNotificationService.SendPushNotificationAsync(
                recipientEmail: booking.ResidentEmail,
                title: "Job Completed! ✅",
                message: $"Your service for '{booking.JobTitle}' has been completed.",
                data: new Dictionary<string, string> { { "bookingId", booking.Id.ToString() }, { "type", "booking" } }
            );

            return Ok(MapToDto(booking));
        }

        // POST: /api/bookings/{id}/cancel
        [HttpPost("{id:int}/cancel")]
        public async Task<IActionResult> CancelBooking(int id, [FromBody] UpdateBookingStatusRequest? request)
        {
            var booking = await _context.Bookings
                .Include(b => b.Resident)
                .Include(b => b.Worker)
                .FirstOrDefaultAsync(b => b.Id == id);

            if (booking == null) return NotFound(new { message = "Booking not found." });

            // Cannot cancel if job is already in progress
            if (booking.Status == "InProgress")
            {
                return BadRequest(new { message = "Job is currently in progress and cannot be cancelled. Please complete the job or contact support." });
            }

            booking.Status = "Cancelled";
            booking.CancellationReason = request?.Reason ?? "Cancelled by user";
            booking.UpdatedAt = DateTime.UtcNow;

            if (booking.Worker != null)
            {
                booking.Worker.CancelledJobs += 1;
            }

            await _context.SaveChangesAsync();

            // Send OneSignal push to the other party
            var currentUser = GetCurrentUserEmail();
            var isCancelledByResident = string.Equals(currentUser, booking.ResidentEmail, StringComparison.OrdinalIgnoreCase);
            var notifyEmail = isCancelledByResident ? booking.Worker?.Email : booking.ResidentEmail;
            if (!string.IsNullOrWhiteSpace(notifyEmail))
            {
                _ = _pushNotificationService.SendPushNotificationAsync(
                    recipientEmail: notifyEmail,
                    title: "Booking Cancelled ⚠️",
                    message: $"The booking for '{booking.JobTitle}' was cancelled.",
                    data: new Dictionary<string, string> { { "bookingId", booking.Id.ToString() }, { "type", "booking" } }
                );
            }

            return Ok(MapToDto(booking));
        }


        // POST: /api/bookings/{id}/review
        [HttpPost("{id:int}/review")]
        [AllowAnonymous]
        public async Task<IActionResult> ReviewBooking(int id, [FromBody] ReviewBookingRequest request)
        {
            var booking = await _context.Bookings
                .Include(b => b.Resident)
                .Include(b => b.Worker)
                .FirstOrDefaultAsync(b => b.Id == id);

            if (booking == null) return NotFound(new { message = "Booking not found." });

            if (booking.Status == "Reviewed" || booking.ReviewRating.HasValue)
            {
                return BadRequest(new { message = "Booking has already been reviewed." });
            }

            var q = Math.Clamp(request.QualityRating, 1, 5);
            var p = Math.Clamp(request.PunctualityRating, 1, 5);
            var c = Math.Clamp(request.CommunicationRating, 1, 5);
            var avgRating = Math.Round((q + p + c) / 3.0, 1);

            booking.QualityRating = q;
            booking.PunctualityRating = p;
            booking.CommunicationRating = c;
            booking.ReviewRating = avgRating;
            booking.ReviewComment = request.ReviewComment;
            booking.ReviewedAt = DateTime.UtcNow;
            booking.Status = "Reviewed";
            booking.UpdatedAt = DateTime.UtcNow;

            // Recalculate Worker ratings based on real reviews
            if (booking.Worker != null)
            {
                var reviewedBookings = await _context.Bookings
                    .Where(b => b.WorkerId == booking.WorkerId && b.Id != booking.Id && b.ReviewRating.HasValue)
                    .ToListAsync();

                var allQuality = reviewedBookings.Where(b => b.QualityRating.HasValue).Select(b => b.QualityRating!.Value).Concat(new[] { q }).ToList();
                var allPunc = reviewedBookings.Where(b => b.PunctualityRating.HasValue).Select(b => b.PunctualityRating!.Value).Concat(new[] { p }).ToList();
                var allComm = reviewedBookings.Where(b => b.CommunicationRating.HasValue).Select(b => b.CommunicationRating!.Value).Concat(new[] { c }).ToList();

                booking.Worker.QualityRating = (int)Math.Round(allQuality.Average());
                booking.Worker.PunctualityRating = (int)Math.Round(allPunc.Average());
                booking.Worker.CommunicationRating = (int)Math.Round(allComm.Average());
                booking.Worker.OverallRating = Math.Round((allQuality.Average() + allPunc.Average() + allComm.Average()) / 3.0, 1);
            }

            await _context.SaveChangesAsync();

            if (booking.ConversationId.HasValue)
            {
                try
                {
                    await _communicationRepo.SendMessageAsync(booking.ConversationId.Value, booking.ResidentEmail, "Resident", new SendMessageRequest
                    {
                        SenderEmail = booking.ResidentEmail,
                        SenderRole = "Resident",
                        MessageType = "BookingUpdate",
                        Content = $"⭐ Resident left a {avgRating}★ review: \"{request.ReviewComment}\""
                    });
                }
                catch { }
            }

            return Ok(MapToDto(booking));
        }

        // DELETE: api/bookings/{id}
        [HttpDelete("{id}")]
        public async Task<IActionResult> DeleteBooking(int id)
        {
            var booking = await _context.Bookings.FindAsync(id);
            if (booking == null)
            {
                return NotFound(new { message = "Booking not found." });
            }

            _context.Bookings.Remove(booking);
            await _context.SaveChangesAsync();

            return Ok(new { message = "Booking deleted successfully." });
        }
    }
}
