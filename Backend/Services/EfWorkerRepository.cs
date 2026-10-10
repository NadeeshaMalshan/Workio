using System;
using Microsoft.EntityFrameworkCore;
using Superbass.Models;

namespace Superbass.Services
{
    public class EfWorkerRepository : WorkerRepository
    {
        private readonly SuperbassDbContext _context;

        public EfWorkerRepository(SuperbassDbContext context)
        {
            _context = context;
        }

        public async Task<IEnumerable<Worker>> GetAllWorkersAsync()
        {
            return await _context.Workers.Include(w => w.Skills).ToListAsync();
        }

        public async Task<Worker?> GetWorkerByIdAsync(int id)
        {
            return await _context.Workers.Include(w => w.Skills).FirstOrDefaultAsync(w => w.Id == id);
        }

        public async Task<Worker?> GetWorkerByEmailAsync(string email)
        {
            var cleanEmail = email.Trim().ToLower();
            return await _context.Workers.Include(w => w.Skills).FirstOrDefaultAsync(w => w.Email.ToLower() == cleanEmail);
        }

        public async Task<(IEnumerable<Worker> Workers, int TotalCount)> SearchWorkersAsync(
            string? q = null,
            string? skill = null,
            string? location = null,
            double? maxDistanceKm = null,
            double? residentLat = null,
            double? residentLng = null,
            decimal? maxHourlyRate = null,
            decimal? minHourlyRate = null,
            string? province = null,
            string? district = null,
            bool onlyVerified = true,
            int page = 1,
            int pageSize = 20)
        {
            var query = _context.Workers.Include(w => w.Skills).AsQueryable();

            if (onlyVerified)
            {
                query = query.Where(w => w.IsVerified);
            }

            if (!string.IsNullOrWhiteSpace(q))
            {
                var qTerm = $"%{q.Trim()}%";
                query = query.Where(w => 
                    EF.Functions.ILike(w.Name, qTerm) ||
                    w.Skills.Any(s => 
                        (s.ServiceName != null && EF.Functions.ILike(s.ServiceName, qTerm)) ||
                        (s.SkillName != null && EF.Functions.ILike(s.SkillName, qTerm)) ||
                        s.Skills.Any(sub => EF.Functions.ILike(sub, qTerm))
                    )
                );
            }

            if (!string.IsNullOrWhiteSpace(skill))
            {
                var term = skill.Trim().ToLower();
                var primary = term;
                var alias = "";
                if (term.Contains("car") || term.Contains("vehicle") || term.Contains("mechanic") || term.Contains("auto") || term.Contains("mcanin") || term.Contains("vechil"))
                {
                    alias = "vehicle";
                }
                else if (term.Contains("plumb") || term.Contains("pipe") || term.Contains("leak") || term.Contains("tap"))
                {
                    alias = "plumbing";
                }
                else if (term.Contains("electr") || term.Contains("wire") || term.Contains("wiring"))
                {
                    alias = "electrical";
                }
                else if (term.Contains("ac") || term.Contains("air condition"))
                {
                    alias = "air conditioning";
                }

                if (!string.IsNullOrEmpty(alias))
                {
                    query = query.Where(w => w.Skills.Any(s => 
                        (s.ServiceName != null && (s.ServiceName.ToLower().Contains(primary) || s.ServiceName.ToLower().Contains(alias))) ||
                        (s.SkillName != null && (s.SkillName.ToLower().Contains(primary) || s.SkillName.ToLower().Contains(alias))) ||
                        s.Skills.Any(sub => sub.ToLower().Contains(primary) || sub.ToLower().Contains(alias))
                    ));
                }
                else
                {
                    query = query.Where(w => w.Skills.Any(s => 
                        (s.ServiceName != null && s.ServiceName.ToLower().Contains(primary)) ||
                        (s.SkillName != null && s.SkillName.ToLower().Contains(primary)) ||
                        s.Skills.Any(sub => sub.ToLower().Contains(primary))
                    ));
                }
            }

            if (!string.IsNullOrWhiteSpace(location))
            {
                query = query.Where(w => w.PrimaryServiceArea != null && w.PrimaryServiceArea.ToLower().Contains(location.ToLower()));
            }

            // Province Filtering
            if (!string.IsNullOrWhiteSpace(province) && !province.Equals("all", StringComparison.OrdinalIgnoreCase))
            {
                var provTerm = province.Trim().ToLower().Replace(" province", "");
                var matchingDistricts = DistrictToProvinceMap
                    .Where(kv => kv.Value.ToLower().Contains(provTerm))
                    .Select(kv => kv.Key.ToLower())
                    .ToList();

                var matchingAreas = AreaToDistrictMap
                    .Where(kv => matchingDistricts.Contains(kv.Value.ToLower()))
                    .Select(kv => kv.Key.ToLower())
                    .ToList();

                query = query.Where(w =>
                    (w.Province != null && w.Province.ToLower().Contains(provTerm)) ||
                    (w.District != null && matchingDistricts.Contains(w.District.ToLower())) ||
                    (w.PrimaryServiceArea != null && (
                        matchingAreas.Contains(w.PrimaryServiceArea.ToLower()) ||
                        matchingDistricts.Contains(w.PrimaryServiceArea.ToLower()) ||
                        w.PrimaryServiceArea.ToLower().Contains(provTerm)
                    ))
                );
            }

            // District Filtering
            if (!string.IsNullOrWhiteSpace(district) && !district.Equals("all", StringComparison.OrdinalIgnoreCase))
            {
                var distTerm = district.Trim().ToLower();
                var matchingAreas = AreaToDistrictMap
                    .Where(kv => kv.Value.ToLower().Equals(distTerm, StringComparison.OrdinalIgnoreCase))
                    .Select(kv => kv.Key.ToLower())
                    .ToList();

                query = query.Where(w =>
                    (w.District != null && w.District.ToLower().Contains(distTerm)) ||
                    (w.PrimaryServiceArea != null && (
                        w.PrimaryServiceArea.ToLower().Contains(distTerm) ||
                        matchingAreas.Contains(w.PrimaryServiceArea.ToLower())
                    ))
                );
            }

            if (maxHourlyRate.HasValue)
            {
                query = query.Where(w => w.HourlyRate != null && w.HourlyRate <= maxHourlyRate.Value);
            }

            if (minHourlyRate.HasValue)
            {
                query = query.Where(w => w.HourlyRate != null && w.HourlyRate >= minHourlyRate.Value);
            }

            var workers = await query.ToListAsync();

            if (residentLat.HasValue && residentLng.HasValue)
            {
                foreach (var w in workers)
                {
                    double? lat = w.LocationLat;
                    double? lng = w.LocationLng;

                    if (!lat.HasValue || !lng.HasValue)
                    {
                        var cityCoords = GetCityCoordinates(w.PrimaryServiceArea);
                        if (cityCoords.HasValue)
                        {
                            lat = cityCoords.Value.Lat;
                            lng = cityCoords.Value.Lng;
                        }
                    }

                    if (lat.HasValue && lng.HasValue)
                    {
                        w.Distance = CalculateHaversineDistance(residentLat.Value, residentLng.Value, lat.Value, lng.Value);
                    }
                }
                
                if (maxDistanceKm.HasValue)
                {
                    workers = workers.Where(w => !w.Distance.HasValue || w.Distance.Value <= maxDistanceKm.Value).ToList();
                }

                workers = workers.OrderBy(w => w.Distance ?? double.MaxValue).ToList();
            }

            var totalCount = workers.Count;
            if (pageSize > 50) pageSize = 50;
            if (page < 1) page = 1;
            
            var pagedWorkers = workers.Skip((page - 1) * pageSize).Take(pageSize).ToList();

            return (pagedWorkers, totalCount);
        }

        public static readonly Dictionary<string, string> DistrictToProvinceMap = new(StringComparer.OrdinalIgnoreCase)
        {
            // Western Province
            { "Colombo", "Western Province" },
            { "Gampaha", "Western Province" },
            { "Kalutara", "Western Province" },
            // Central Province
            { "Kandy", "Central Province" },
            { "Matale", "Central Province" },
            { "Nuwara Eliya", "Central Province" },
            // Southern Province
            { "Galle", "Southern Province" },
            { "Matara", "Southern Province" },
            { "Hambantota", "Southern Province" },
            // Northern Province
            { "Jaffna", "Northern Province" },
            { "Kilinochchi", "Northern Province" },
            { "Mannar", "Northern Province" },
            { "Mullaitivu", "Northern Province" },
            { "Vavuniya", "Northern Province" },
            // Eastern Province
            { "Trincomalee", "Eastern Province" },
            { "Batticaloa", "Eastern Province" },
            { "Ampara", "Eastern Province" },
            // North Western Province
            { "Kurunegala", "North Western Province" },
            { "Puttalam", "North Western Province" },
            // North Central Province
            { "Anuradhapura", "North Central Province" },
            { "Polonnaruwa", "North Central Province" },
            // Uva Province
            { "Badulla", "Uva Province" },
            { "Monaragala", "Uva Province" },
            // Sabaragamuwa Province
            { "Ratnapura", "Sabaragamuwa Province" },
            { "Kegalle", "Sabaragamuwa Province" }
        };

        public static readonly Dictionary<string, string> AreaToDistrictMap = new(StringComparer.OrdinalIgnoreCase)
        {
            // Colombo District
            { "Colombo", "Colombo" }, { "Dehiwala", "Colombo" }, { "Mount Lavinia", "Colombo" },
            { "Moratuwa", "Colombo" }, { "Kotte", "Colombo" }, { "Kaduwela", "Colombo" },
            { "Maharagama", "Colombo" }, { "Kesbewa", "Colombo" }, { "Homagama", "Colombo" },
            { "Kolonnawa", "Colombo" }, { "Padukka", "Colombo" }, { "Hanwella", "Colombo" },
            { "Ratmalana", "Colombo" }, { "Nugegoda", "Colombo" }, { "Battaramulla", "Colombo" },
            { "Rajagiriya", "Colombo" }, { "Malabe", "Colombo" }, { "Piliyandala", "Colombo" },
            { "Pannipitiya", "Colombo" }, { "Kottawa", "Colombo" }, { "Athurugiriya", "Colombo" },

            // Gampaha District
            { "Gampaha", "Gampaha" }, { "Negombo", "Gampaha" }, { "Kelaniya", "Gampaha" },
            { "Wattala", "Gampaha" }, { "Ja-Ela", "Gampaha" }, { "Kandana", "Gampaha" },
            { "Ragama", "Gampaha" }, { "Kiribathgoda", "Gampaha" }, { "Minuwangoda", "Gampaha" },
            { "Mirigama", "Gampaha" }, { "Veyangoda", "Gampaha" }, { "Kadawatha", "Gampaha" },

            // Kalutara District
            { "Kalutara", "Kalutara" }, { "Panadura", "Kalutara" }, { "Horana", "Kalutara" },
            { "Beruwala", "Kalutara" }, { "Wadduwa", "Kalutara" }, { "Aluthgama", "Kalutara" },
            { "Matugama", "Kalutara" }, { "Bandaragama", "Kalutara" },

            // Central Province
            { "Kandy", "Kandy" }, { "Peradeniya", "Kandy" }, { "Katugastota", "Kandy" }, { "Gampola", "Kandy" },
            { "Matale", "Matale" }, { "Dambulla", "Matale" },
            { "Nuwara Eliya", "Nuwara Eliya" }, { "Hatton", "Nuwara Eliya" },

            // Southern Province
            { "Galle", "Galle" }, { "Hikkaduwa", "Galle" }, { "Karapitiya", "Galle" }, { "Ambalangoda", "Galle" },
            { "Matara", "Matara" }, { "Weligama", "Matara" }, { "Dickwella", "Matara" },
            { "Hambantota", "Hambantota" }, { "Tangalle", "Hambantota" },

            // Sabaragamuwa Province
            { "Ratnapura", "Ratnapura" }, { "Balangoda", "Ratnapura" }, { "Embilipitiya", "Ratnapura" },
            { "Kegalle", "Kegalle" }, { "Mawanella", "Kegalle" }
        };

        private static readonly Dictionary<string, (double Lat, double Lng)> KnownCityCoordinates = new(StringComparer.OrdinalIgnoreCase)
        {
            { "Colombo", (6.9271, 79.8612) },
            { "Dehiwala", (6.8511, 79.8659) },
            { "Mount Lavinia", (6.8378, 79.8667) },
            { "Moratuwa", (6.7730, 79.8816) },
            { "Kotte", (6.8914, 79.9048) },
            { "Kaduwela", (6.9333, 79.9833) },
            { "Gampaha", (7.0840, 79.9925) },
            { "Negombo", (7.2008, 79.8736) },
            { "Kalutara", (6.5854, 79.9607) },
            { "Kandy", (7.2906, 80.6337) },
            { "Matale", (7.4675, 80.6234) },
            { "Nuwara Eliya", (6.9497, 80.7891) },
            { "Galle", (6.0535, 80.2210) },
            { "Matara", (5.9549, 80.5550) },
            { "Hambantota", (6.1429, 81.1212) },
            { "Jaffna", (9.6615, 80.0255) },
            { "Kurunegala", (7.4863, 80.3623) },
            { "Puttalam", (8.0362, 79.8283) },
            { "Anuradhapura", (8.3114, 80.4037) },
            { "Polonnaruwa", (7.9403, 81.0188) },
            { "Badulla", (6.9934, 81.0550) },
            { "Ratnapura", (6.6828, 80.4034) },
            { "Trincomalee", (8.5874, 81.2152) },
            { "Batticaloa", (7.7310, 81.6747) }
        };

        private (double Lat, double Lng)? GetCityCoordinates(string? location)
        {
            if (string.IsNullOrWhiteSpace(location)) return null;
            foreach (var kvp in KnownCityCoordinates)
            {
                if (location.Contains(kvp.Key, StringComparison.OrdinalIgnoreCase))
                {
                    return kvp.Value;
                }
            }
            return null;
        }

        private double CalculateHaversineDistance(double lat1, double lon1, double lat2, double lon2)
        {
            var R = 6371; // Radius of the earth in km
            var dLat = ToRadians(lat2 - lat1);
            var dLon = ToRadians(lon2 - lon1);
            var a = 
                Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(ToRadians(lat1)) * Math.Cos(ToRadians(lat2)) * 
                Math.Sin(dLon / 2) * Math.Sin(dLon / 2); 
            var c = 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a)); 
            return R * c; // Distance in km
        }

        private double ToRadians(double deg) => deg * (Math.PI / 180);

        public async Task<Worker> CreateWorkerAsync(Worker worker)
        {
            _context.Workers.Add(worker);
            await _context.SaveChangesAsync();
            return worker;
        }

        public async Task<Worker> CreateWorkerDirectAsync(string email, string? name, string? description, string primaryServiceArea, double coverageRadiusKm, string pricingModel, decimal? hourlyRate, decimal? dailyRate, List<WorkerSkill> skills)
        {
            var cleanEmail = email.Trim().ToLower();
            var existingWorker = await _context.Workers.Include(w => w.Skills).FirstOrDefaultAsync(w => w.Email.ToLower() == cleanEmail);
            if (existingWorker != null)
            {
                if (!string.IsNullOrWhiteSpace(name)) existingWorker.Name = name;
                existingWorker.Description = description ?? existingWorker.Description;
                existingWorker.PrimaryServiceArea = primaryServiceArea ?? existingWorker.PrimaryServiceArea;
                if (coverageRadiusKm > 0) existingWorker.CoverageRadiusKm = coverageRadiusKm;
                existingWorker.PricingModel = pricingModel ?? existingWorker.PricingModel;
                if (hourlyRate != null) existingWorker.HourlyRate = hourlyRate;
                if (dailyRate != null) existingWorker.DailyRate = dailyRate;
                if (skills != null && skills.Count > 0)
                {
                    _context.WorkerSkills.RemoveRange(existingWorker.Skills);
                    existingWorker.Skills = skills;
                }
                await _context.SaveChangesAsync();
                return existingWorker;
            }

            var worker = new Worker
            {
                Email = cleanEmail,
                Name = !string.IsNullOrWhiteSpace(name) ? name : cleanEmail.Split('@')[0],
                Description = description,
                PrimaryServiceArea = primaryServiceArea,
                CoverageRadiusKm = coverageRadiusKm > 0 ? coverageRadiusKm : 10.0,
                PricingModel = pricingModel,
                HourlyRate = hourlyRate,
                DailyRate = dailyRate,
                IsAvailable = true,
                IsVerified = false,
                Skills = skills ?? new List<WorkerSkill>()
            };

            _context.Workers.Add(worker);
            await _context.SaveChangesAsync();
            return worker;
        }

        public async Task<Worker?> UpdateWorkerAsync(int id, Worker updatedWorker)
        {
            var existing = await _context.Workers.Include(w => w.Skills).FirstOrDefaultAsync(w => w.Id == id);
            if (existing == null) return null;

            if (!string.IsNullOrWhiteSpace(updatedWorker.Name)) existing.Name = updatedWorker.Name;
            if (updatedWorker.PhoneNo != null) existing.PhoneNo = updatedWorker.PhoneNo;
            if (!string.IsNullOrWhiteSpace(updatedWorker.ProfileImage)) existing.ProfileImage = updatedWorker.ProfileImage;
            if (updatedWorker.Description != null) existing.Description = updatedWorker.Description;
            if (!string.IsNullOrWhiteSpace(updatedWorker.PrimaryServiceArea)) existing.PrimaryServiceArea = updatedWorker.PrimaryServiceArea;
            if (!string.IsNullOrWhiteSpace(updatedWorker.Province)) existing.Province = updatedWorker.Province;
            if (!string.IsNullOrWhiteSpace(updatedWorker.District)) existing.District = updatedWorker.District;
            if (!string.IsNullOrWhiteSpace(updatedWorker.PricingModel)) existing.PricingModel = updatedWorker.PricingModel;
            if (updatedWorker.HourlyRate.HasValue && updatedWorker.HourlyRate > 0) existing.HourlyRate = updatedWorker.HourlyRate;
            if (updatedWorker.DailyRate.HasValue && updatedWorker.DailyRate > 0) existing.DailyRate = updatedWorker.DailyRate;
            existing.IsAvailable = updatedWorker.IsAvailable;

            await _context.SaveChangesAsync();
            return existing;
        }

        public async Task<bool> DeleteWorkerAsync(int id)
        {
            var worker = await _context.Workers.FindAsync(id);
            if (worker == null) return false;

            using var transaction = await _context.Database.BeginTransactionAsync();
            try
            {
                // Permanent hard-delete of worker and worker-specific associations:
                // 1. Delete worker conversations and chat messages
                var convIds = await _context.Conversations
                    .Where(c => c.WorkerId == id)
                    .Select(c => c.Id)
                    .ToListAsync();

                if (convIds.Any())
                {
                    await _context.ChatMessages
                        .Where(m => convIds.Contains(m.ConversationId))
                        .ExecuteDeleteAsync();

                    await _context.Conversations
                        .Where(c => convIds.Contains(c.Id))
                        .ExecuteDeleteAsync();
                }

                // 2. Delete bookings associated with this worker
                await _context.Bookings
                    .Where(b => b.WorkerId == id)
                    .ExecuteDeleteAsync();

                // 3. Delete worker skills
                await _context.WorkerSkills
                    .Where(s => s.WorkerId == id)
                    .ExecuteDeleteAsync();

                // 4. Delete the worker record itself
                _context.Workers.Remove(worker);
                await _context.SaveChangesAsync();
                await transaction.CommitAsync();
                return true;
            }
            catch
            {
                await transaction.RollbackAsync();
                throw;
            }
        }

        public async Task<bool> DeleteWorkerByEmailAsync(string email)
        {
            var cleanEmail = email.Trim().ToLower();
            var worker = await _context.Workers.FirstOrDefaultAsync(w => w.Email.ToLower() == cleanEmail);
            if (worker == null) return false;

            return await DeleteWorkerAsync(worker.Id);
        }

        public async Task<Worker?> UpdatePerformanceAsync(int id, double rating, bool isCompleted)
        {
            var worker = await _context.Workers.FindAsync(id);
            if (worker == null) return null;

            if (isCompleted)
            {
                worker.CompletedJobs += 1;
                // Calculate moving average rating safely when previous OverallRating might be null
                var prevRating = worker.OverallRating ?? rating;
                worker.OverallRating = Math.Round(((prevRating * (worker.CompletedJobs - 1)) + rating) / worker.CompletedJobs, 2);
            }

            await _context.SaveChangesAsync();
            return worker;
        }

        public async Task<WorkerSkill?> AddSkillAsync(int workerId, WorkerSkill skill)
        {
            var worker = await _context.Workers.FindAsync(workerId);
            if (worker == null) return null;

            skill.WorkerId = workerId;
            _context.WorkerSkills.Add(skill);
            await _context.SaveChangesAsync();

            return skill;
        }

        public async Task<bool> RemoveSkillAsync(int workerId, int skillId)
        {
            var entry = await _context.WorkerSkills
                .FirstOrDefaultAsync(s => s.WorkerId == workerId && s.Id == skillId);

            if (entry == null) return false;

            _context.WorkerSkills.Remove(entry);
            await _context.SaveChangesAsync();
            return true;
        }

        public async Task<bool> UpdateAvailabilityAsync(int workerId, bool isAvailable, string? scheduleJson)
        {
            var worker = await _context.Workers.FindAsync(workerId);
            if (worker == null) return false;

            worker.IsAvailable = isAvailable;
            worker.AvailabilityScheduleJson = scheduleJson;

            await _context.SaveChangesAsync();
            return true;
        }

        public async Task<bool> UpdatePricingAsync(int workerId, string model, decimal? hourlyRate, decimal? dailyRate)
        {
            var worker = await _context.Workers.FindAsync(workerId);
            if (worker == null) return false;

            worker.PricingModel = model;
            worker.HourlyRate = hourlyRate;
            worker.DailyRate = dailyRate;

            await _context.SaveChangesAsync();
            return true;
        }

        public async Task<bool> UpdateServiceAreaAsync(int workerId, string serviceArea, double radiusKm)
        {
            var worker = await _context.Workers.FindAsync(workerId);
            if (worker == null) return false;

            worker.PrimaryServiceArea = serviceArea;
            worker.CoverageRadiusKm = radiusKm;

            if (!string.IsNullOrWhiteSpace(serviceArea))
            {
                if (DistrictToProvinceMap.TryGetValue(serviceArea, out var prov))
                {
                    worker.District = serviceArea;
                    worker.Province = prov;
                }
                else if (AreaToDistrictMap.TryGetValue(serviceArea, out var dist))
                {
                    worker.District = dist;
                    if (DistrictToProvinceMap.TryGetValue(dist, out var p))
                    {
                        worker.Province = p;
                    }
                }
            }

            await _context.SaveChangesAsync();
            return true;
        }

        public async Task<bool> UpdatePasswordAsync(int workerId, string newPassword)
        {
            var worker = await _context.Workers.FindAsync(workerId);
            if (worker == null) return false;

            worker.PasswordHash = newPassword; // Simple hash / string update

            await _context.SaveChangesAsync();
            return true;
        }
    }
}
