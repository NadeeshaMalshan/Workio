using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Claims;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Superbass.Models;
using Superbass.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.Extensions.Configuration;
using CloudinaryDotNet;
using CloudinaryDotNet.Actions;

namespace Superbass.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    [Authorize]
    public class ConversationsController : ControllerBase
    {
        private readonly ICommunicationRepository _communicationRepo;
        private readonly IHubContext<ChatHub> _hubContext;
        private readonly IWebHostEnvironment _environment;
        private readonly IPushNotificationService _pushNotificationService;
        private readonly IConfiguration _configuration;
        private readonly SuperbassDbContext _context;

        public ConversationsController(
            ICommunicationRepository communicationRepo,
            IHubContext<ChatHub> hubContext,
            IWebHostEnvironment environment,
            IPushNotificationService pushNotificationService,
            IConfiguration configuration,
            SuperbassDbContext context)
        {
            _communicationRepo = communicationRepo;
            _hubContext = hubContext;
            _environment = environment;
            _pushNotificationService = pushNotificationService;
            _configuration = configuration;
            _context = context;
        }

        private string? GetCurrentUserEmail()
        {
            var email = User.FindFirstValue(ClaimTypes.Email) 
                     ?? User.FindFirstValue("email") 
                     ?? User.FindFirstValue(ClaimTypes.NameIdentifier);
            if (!string.IsNullOrEmpty(email)) return email;

            var authHeader = Request.Headers["Authorization"].FirstOrDefault();
            if (authHeader != null && authHeader.StartsWith("Bearer "))
            {
                var token = authHeader.Substring("Bearer ".Length).Trim();
                var tokenHandler = new System.IdentityModel.Tokens.Jwt.JwtSecurityTokenHandler();
                var key = System.Text.Encoding.ASCII.GetBytes(_configuration["Authentication:Jwt:Secret"] ?? "super_secret_key_that_must_be_long_enough_12345");
                try
                {
                    tokenHandler.ValidateToken(token, new Microsoft.IdentityModel.Tokens.TokenValidationParameters
                    {
                        ValidateIssuerSigningKey = true,
                        IssuerSigningKey = new Microsoft.IdentityModel.Tokens.SymmetricSecurityKey(key),
                        ValidateIssuer = false,
                        ValidateAudience = false,
                        ClockSkew = TimeSpan.Zero
                    }, out Microsoft.IdentityModel.Tokens.SecurityToken validatedToken);

                    var jwtToken = (System.IdentityModel.Tokens.Jwt.JwtSecurityToken)validatedToken;
                    return jwtToken.Claims.FirstOrDefault(x => x.Type == ClaimTypes.Email || x.Type == "email" || x.Type == "sub")?.Value;
                }
                catch { }
            }
            return null;
        }

        // GET: /api/conversations?userEmail=test@example.com or ?email=test@example.com
        [HttpGet]
        public async Task<IActionResult> GetConversations([FromQuery] string? userEmail, [FromQuery] string? email)
        {
            var targetEmail = userEmail ?? email ?? GetCurrentUserEmail();
            if (string.IsNullOrWhiteSpace(targetEmail))
            {
                return BadRequest(new { message = "User email must be provided or present in JWT claims." });
            }

            var conversations = await _communicationRepo.GetUserConversationsAsync(targetEmail);
            return Ok(conversations);
        }

        // GET: /api/conversations/5?userEmail=test@example.com or ?email=test@example.com
        [HttpGet("{id:int}")]
        public async Task<IActionResult> GetConversationById(int id, [FromQuery] string? userEmail, [FromQuery] string? email)
        {
            var targetEmail = userEmail ?? email ?? GetCurrentUserEmail();
            if (string.IsNullOrWhiteSpace(targetEmail))
            {
                return BadRequest(new { message = "User email must be provided or present in JWT claims." });
            }

            var conversation = await _communicationRepo.GetConversationByIdAsync(id, targetEmail);
            if (conversation == null)
            {
                return NotFound(new { message = "Conversation not found or access denied." });
            }

            return Ok(conversation);
        }

        // POST: /api/conversations
        [HttpPost]
        public async Task<IActionResult> CreateOrGetConversation([FromBody] CreateConversationRequest request)
        {
            if (request == null || (request.WorkerId <= 0 && string.IsNullOrWhiteSpace(request.WorkerEmail) && string.IsNullOrWhiteSpace(request.WorkerName)))
            {
                return BadRequest(new { message = "Worker identifier (workerId or workerEmail) is required." });
            }

            var residentEmail = request.ResidentEmail ?? GetCurrentUserEmail();
            if (string.IsNullOrWhiteSpace(residentEmail))
            {
                residentEmail = "resident@superbass.lk";
            }

            try
            {
                var summary = await _communicationRepo.GetOrCreateConversationAsync(request, residentEmail);
                return Ok(summary);
            }
            catch (Exception ex)
            {
                return BadRequest(new { message = ex.Message });
            }
        }

        // GET: /api/conversations/5/messages?page=1&pageSize=50
        [HttpGet("{id:int}/messages")]
        public async Task<IActionResult> GetMessages(int id, [FromQuery] string? userEmail, [FromQuery] int page = 1, [FromQuery] int pageSize = 50)
        {
            var email = userEmail ?? GetCurrentUserEmail() ?? string.Empty;
            var messages = await _communicationRepo.GetMessagesAsync(id, email, page, pageSize);
            return Ok(messages);
        }

        // POST: /api/conversations/5/messages
        [HttpPost("{id:int}/messages")]
        [HttpPost("{id:int}/message")]
        public async Task<IActionResult> SendMessage(int id, [FromBody] SendMessageRequest request)
        {
            if (request == null || (string.IsNullOrWhiteSpace(request.Content) && string.IsNullOrWhiteSpace(request.AttachmentUrl)))
            {
                return BadRequest(new { message = "Message content or attachment URL is required." });
            }

            var senderEmail = request.SenderEmail ?? GetCurrentUserEmail();
            if (string.IsNullOrWhiteSpace(senderEmail))
            {
                return BadRequest(new { message = "Sender email must be provided or present in JWT claims." });
            }

            var senderRole = request.SenderRole ?? "Resident";

            try
            {
                var messageDto = await _communicationRepo.SendMessageAsync(id, senderEmail, senderRole, request);

                // Broadcast via SignalR to room
                var groupName = $"conversation_{id}";
                await _hubContext.Clients.Group(groupName).SendAsync("ReceiveMessage", messageDto);

                // Send Push Notification via OneSignal
                if (!string.IsNullOrWhiteSpace(messageDto.ReceiverEmail))
                {
                    _ = _pushNotificationService.SendPushNotificationAsync(
                        recipientEmail: messageDto.ReceiverEmail,
                        title: $"New Message from {senderRole} 💬",
                        message: !string.IsNullOrWhiteSpace(messageDto.Content) ? messageDto.Content : "Sent an attachment",
                        data: new Dictionary<string, string>
                        {
                            { "conversationId", id.ToString() },
                            { "type", "chat" }
                        }
                    );
                }

                return Ok(messageDto);
            }
            catch (KeyNotFoundException ex)
            {
                return NotFound(new { message = ex.Message });
            }
        }

        // POST: /api/conversations/5/share-contact
        // Secure worker contact-sharing: only verified phone already in DB, only by assigned worker, only for valid booking.
        [HttpPost("{id:int}/share-contact")]
        public async Task<IActionResult> ShareContact(int id)
        {
            var requesterEmail = GetCurrentUserEmail();
            if (string.IsNullOrWhiteSpace(requesterEmail))
            {
                return Unauthorized(new { message = "You must be logged in to share contact details." });
            }

            var cleanRequester = requesterEmail.Trim().ToLower();

            var conv = await _context.Conversations
                .Include(c => c.Worker)
                .Include(c => c.Resident)
                .FirstOrDefaultAsync(c => c.Id == id);

            if (conv == null)
            {
                return NotFound(new { message = "Conversation not found." });
            }

            // 1. Only allow the correct worker
            var isCorrectWorker = conv.Worker != null && 
                string.Equals(conv.Worker.Email?.Trim().ToLower(), cleanRequester, StringComparison.OrdinalIgnoreCase);

            if (!isCorrectWorker)
            {
                return StatusCode(403, new { message = "Only the assigned worker for this conversation can share contact details." });
            }

            // 2. Validate valid booking
            Booking? booking = null;
            if (conv.BookingId.HasValue)
            {
                booking = await _context.Bookings.FirstOrDefaultAsync(b => b.Id == conv.BookingId.Value);
            }

            if (booking == null)
            {
                booking = await _context.Bookings
                    .Where(b => b.WorkerId == conv.WorkerId && b.ResidentEmail.ToLower() == conv.ResidentEmail.ToLower())
                    .OrderByDescending(b => b.CreatedAt)
                    .FirstOrDefaultAsync();
            }

            if (booking == null)
            {
                return BadRequest(new { message = "No booking exists between this worker and resident." });
            }

            var allowedStatuses = new[] { "Confirmed", "InProgress", "Completed" };
            if (!allowedStatuses.Contains(booking.Status))
            {
                return BadRequest(new { message = $"Contact can only be shared after the booking is accepted." });
            }

            // 3. Get the worker's verified phone number stored in the system (cannot be manually entered or modified)
            var worker = await _context.Workers.FirstOrDefaultAsync(w => w.Id == conv.WorkerId);
            if (worker == null || string.IsNullOrWhiteSpace(worker.PhoneNo))
            {
                return BadRequest(new { message = "No verified phone number found on your worker profile. Please update your profile with a valid phone number first." });
            }

            var verifiedPhone = worker.PhoneNo.Trim();

            // Mark booking contact shared
            booking.IsContactShared = true;
            await _context.SaveChangesAsync();

            // 4. Construct Worker Contact Card message payload
            var cardPayload = System.Text.Json.JsonSerializer.Serialize(new
            {
                type = "WorkerContactCard",
                workerId = worker.Id,
                workerName = worker.Name,
                phoneNo = verifiedPhone,
                service = worker.PrimaryServiceArea,
                avatar = worker.ProfileImage,
                bookingId = booking.Id,
                jobTitle = booking.JobTitle,
                sharedAt = DateTime.UtcNow
            });

            var msgRequest = new SendMessageRequest
            {
                SenderEmail = requesterEmail,
                SenderRole = "Worker",
                ReceiverEmail = conv.ResidentEmail,
                ReceiverRole = "Resident",
                MessageType = "ContactCard",
                Content = cardPayload
            };

            var messageDto = await _communicationRepo.SendMessageAsync(id, requesterEmail, "Worker", msgRequest);

            // 5. Broadcast live via SignalR to conversation room
            var groupName = $"conversation_{id}";
            await _hubContext.Clients.Group(groupName).SendAsync("ReceiveMessage", messageDto);

            // 6. Send push notification to resident
            if (!string.IsNullOrWhiteSpace(conv.ResidentEmail))
            {
                _ = _pushNotificationService.SendPushNotificationAsync(
                    recipientEmail: conv.ResidentEmail,
                    title: "Worker Contact Shared 📞",
                    message: $"{worker.Name} has shared their verified phone number with you in chat.",
                    data: new Dictionary<string, string>
                    {
                        { "conversationId", id.ToString() },
                        { "type", "contact_card" },
                        { "bookingId", booking.Id.ToString() }
                    }
                );
            }

            return Ok(new
            {
                message = "Worker contact card shared successfully.",
                chatMessage = messageDto
            });
        }

        // PUT/POST: /api/conversations/5/read
        [HttpPut("{id:int}/read")]
        [HttpPost("{id:int}/read")]
        public async Task<IActionResult> MarkRead(int id, [FromBody] MarkReadRequest? request, [FromQuery] string? email, [FromQuery] string? readerEmail)
        {
            var targetEmail = request?.ReaderEmail ?? readerEmail ?? email ?? GetCurrentUserEmail();
            if (string.IsNullOrWhiteSpace(targetEmail))
            {
                return BadRequest(new { message = "Reader email is required." });
            }

            var updated = await _communicationRepo.MarkConversationAsReadAsync(id, targetEmail.Trim());

            if (updated)
            {
                var groupName = $"conversation_{id}";
                await _hubContext.Clients.Group(groupName).SendAsync("MessagesRead", new 
                { 
                    conversationId = id, 
                    readerEmail = targetEmail 
                });
            }

            return Ok(new { success = true, marked = updated });
        }

        // POST: /api/conversations/5/typing
        [HttpPost("{id:int}/typing")]
        public async Task<IActionResult> ReportTyping(int id, [FromBody] TypingRequest? request)
        {
            var userEmail = request?.UserEmail ?? GetCurrentUserEmail() ?? "user@superbass.lk";
            var groupName = $"conversation_{id}";
            await _hubContext.Clients.Group(groupName).SendAsync("UserTyping", new 
            { 
                conversationId = id, 
                userEmail, 
                isTyping = request?.IsTyping ?? true 
            });

            return Ok(new { success = true });
        }

        // DELETE: /api/conversations/messages/10?userEmail=test@example.com
        [HttpDelete("messages/{messageId:int}")]
        public async Task<IActionResult> DeleteMessage(int messageId, [FromQuery] string? userEmail)
        {
            var email = userEmail ?? GetCurrentUserEmail();
            if (string.IsNullOrWhiteSpace(email))
            {
                return BadRequest(new { message = "User email is required." });
            }

            try
            {
                var result = await _communicationRepo.DeleteMessageAsync(messageId, email);
                if (!result)
                {
                    return NotFound(new { message = "Message not found." });
                }
                return Ok(new { success = true, message = "Message deleted successfully." });
            }
            catch (UnauthorizedAccessException ex)
            {
                return StatusCode(StatusCodes.Status403Forbidden, new { message = ex.Message });
            }
        }

        // POST: /api/conversations/messages/delete?userEmail=test@example.com
        [HttpPost("messages/delete")]
        public async Task<IActionResult> DeleteMessages([FromBody] List<int> messageIds, [FromQuery] string? userEmail)
        {
            var email = userEmail ?? GetCurrentUserEmail();
            if (string.IsNullOrWhiteSpace(email))
            {
                return BadRequest(new { message = "User email is required." });
            }

            if (messageIds == null || !messageIds.Any())
            {
                return BadRequest(new { message = "No message IDs provided." });
            }

            try
            {
                var result = await _communicationRepo.DeleteMessagesAsync(messageIds, email);
                if (!result)
                {
                    return NotFound(new { message = "Messages not found or could not be deleted." });
                }
                return Ok(new { success = true, message = "Messages deleted successfully." });
            }
            catch (UnauthorizedAccessException ex)
            {
                return StatusCode(StatusCodes.Status403Forbidden, new { message = ex.Message });
            }
            catch (InvalidOperationException ex)
            {
                return BadRequest(new { message = ex.Message });
            }
        }

        // DELETE: /api/conversations/10?userEmail=test@example.com
        [HttpDelete("{id:int}")]
        public async Task<IActionResult> DeleteConversation(int id, [FromQuery] string? userEmail)
        {
            var email = userEmail ?? GetCurrentUserEmail();
            if (string.IsNullOrWhiteSpace(email))
            {
                return BadRequest(new { message = "User email is required." });
            }

            try
            {
                var result = await _communicationRepo.SoftDeleteConversationAsync(id, email);
                if (!result)
                {
                    return NotFound(new { message = "Conversation not found or access denied." });
                }
                return Ok(new { success = true, message = "Conversation deleted successfully." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { message = ex.Message });
            }
        }

        // GET: /api/conversations/presence?userEmail=test@example.com
        [HttpGet("presence")]
        public IActionResult GetPresence([FromQuery] string? userEmail)
        {
            if (string.IsNullOrWhiteSpace(userEmail))
            {
                return BadRequest(new { message = "User email is required." });
            }

            var isOnline = ChatHub.IsUserOnline(userEmail);
            var lastSeen = ChatHub.GetLastSeen(userEmail);

            return Ok(new { userEmail, isOnline, lastSeen });
        }

        // POST: /api/conversations/heartbeat
        [HttpPost("heartbeat")]
        public IActionResult Heartbeat([FromBody] TypingRequest? request)
        {
            var email = request?.UserEmail ?? GetCurrentUserEmail();
            if (!string.IsNullOrWhiteSpace(email))
            {
                ChatHub.RecordActivity(email);
            }
            return Ok(new { success = true });
        }

        // GET: /api/conversations/unread-count?userEmail=test@example.com
        [HttpGet("unread-count")]
        [AllowAnonymous]
        public async Task<IActionResult> GetUnreadCount([FromQuery] string? userEmail)
        {
            var email = userEmail ?? GetCurrentUserEmail();
            if (string.IsNullOrWhiteSpace(email))
            {
                return BadRequest(new { message = "User email is required." });
            }

            var count = await _communicationRepo.GetTotalUnreadCountAsync(email);
            return Ok(new { unreadCount = count });
        }

        [HttpPost("upload")]
        public async Task<IActionResult> UploadAttachment(IFormFile file)
        {
            if (file == null || file.Length == 0)
            {
                return BadRequest(new { message = "No file uploaded." });
            }

            // Max file size 25MB
            if (file.Length > 25 * 1024 * 1024)
            {
                return BadRequest(new { message = "File size exceeds 25MB limit." });
            }

            var isImage = file.ContentType.StartsWith("image/", StringComparison.OrdinalIgnoreCase);

            var cloudName = _configuration["Cloudinary:CloudName"];
            var apiKey = _configuration["Cloudinary:ApiKey"];
            var apiSecret = _configuration["Cloudinary:ApiSecret"];

            if (string.IsNullOrEmpty(cloudName) || string.IsNullOrEmpty(apiKey) || string.IsNullOrEmpty(apiSecret))
            {
                // Fallback to local storage
                var uploadDir = Path.Combine(_environment.WebRootPath ?? Path.Combine(Directory.GetCurrentDirectory(), "wwwroot"), "uploads", "chat");
                if (!Directory.Exists(uploadDir))
                {
                    Directory.CreateDirectory(uploadDir);
                }

                var fileExt = Path.GetExtension(file.FileName);
                var uniqueFileName = $"{Guid.NewGuid():N}{fileExt}";
                var filePath = Path.Combine(uploadDir, uniqueFileName);

                using (var stream = new FileStream(filePath, FileMode.Create))
                {
                    await file.CopyToAsync(stream);
                }

                var fileUrl = $"/uploads/chat/{uniqueFileName}";

                return Ok(new
                {
                    url = fileUrl,
                    fileName = file.FileName,
                    fileSize = file.Length,
                    isImage,
                    contentType = file.ContentType
                });
            }

            // Cloudinary upload
            var account = new Account(cloudName, apiKey, apiSecret);
            var cloudinary = new Cloudinary(account);

            using var uploadStream = file.OpenReadStream();
            
            var uploadParams = new RawUploadParams()
            {
                File = new FileDescription(file.FileName, uploadStream),
                Folder = "superbass/chat"
            };

            var uploadResult = await cloudinary.UploadAsync(uploadParams);

            if (uploadResult.Error != null)
            {
                return BadRequest(new { message = uploadResult.Error.Message });
            }

            return Ok(new
            {
                url = uploadResult.SecureUrl.ToString(),
                fileName = file.FileName,
                fileSize = file.Length,
                isImage,
                contentType = file.ContentType
            });
        }
    }
}
