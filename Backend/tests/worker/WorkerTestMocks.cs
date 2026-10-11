using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Superbass.Models;
using Superbass.Services;

namespace Superbass.Tests.WorkerTests
{
    public class MockWorkerRepository : WorkerRepository
    {
        public List<Worker> Workers { get; set; } = new();

        public MockWorkerRepository()
        {
            Workers.Add(new Worker
            {
                Id = 1,
                Name = "Kamal Perera",
                Email = "kamal@workio.lk",
                PhoneNo = "0771234567",
                IsVerified = true,
                PrimaryServiceArea = "Colombo",
                CoverageRadiusKm = 10,
                PricingModel = "Hourly",
                HourlyRate = 2500m,
                DailyRate = 12000m,
                IsAvailable = true,
                OverallRating = 4.8,
                QualityRating = 5,
                PunctualityRating = 5,
                CommunicationRating = 5,
                CompletedJobs = 20,
                AcceptedJobs = 22,
                RejectedJobs = 2,
                CancelledJobs = 1,
                Skills = new List<WorkerSkill>
                {
                    new WorkerSkill
                    {
                        Id = 101,
                        WorkerId = 1,
                        ServiceName = "Plumbing",
                        SkillName = "Plumbing",
                        Skills = new List<string> { "Pipe Fitting", "Leak Repair" },
                        ExperienceYears = 5
                    }
                }
            });

            Workers.Add(new Worker
            {
                Id = 2,
                Name = "Nimal Silva",
                Email = "nimal@workio.lk",
                PhoneNo = "0719876543",
                IsVerified = false,
                PrimaryServiceArea = "Kandy",
                CoverageRadiusKm = 15,
                PricingModel = "Daily",
                HourlyRate = 1500m,
                DailyRate = 8000m,
                IsAvailable = false,
                OverallRating = 4.2,
                QualityRating = 4,
                PunctualityRating = 4,
                CommunicationRating = 4,
                CompletedJobs = 10,
                AcceptedJobs = 12,
                RejectedJobs = 3,
                CancelledJobs = 2,
                Skills = new List<WorkerSkill>
                {
                    new WorkerSkill
                    {
                        Id = 102,
                        WorkerId = 2,
                        ServiceName = "Electrical",
                        SkillName = "Electrical",
                        Skills = new List<string> { "Wiring", "Circuit Repair" },
                        ExperienceYears = 3
                    }
                }
            });
        }

        public Task<IEnumerable<Worker>> GetAllWorkersAsync()
        {
            return Task.FromResult<IEnumerable<Worker>>(Workers.ToList());
        }

        public Task<Worker?> GetWorkerByIdAsync(int id)
        {
            return Task.FromResult(Workers.FirstOrDefault(w => w.Id == id));
        }

        public Task<Worker?> GetWorkerByEmailAsync(string email)
        {
            return Task.FromResult(Workers.FirstOrDefault(w => string.Equals(w.Email, email, StringComparison.OrdinalIgnoreCase)));
        }

        public Task<(IEnumerable<Worker> Workers, int TotalCount)> SearchWorkersAsync(
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
            var query = Workers.AsEnumerable();

            if (onlyVerified)
                query = query.Where(w => w.IsVerified);

            if (!string.IsNullOrWhiteSpace(q))
                query = query.Where(w => w.Name.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                                         (w.Description != null && w.Description.Contains(q, StringComparison.OrdinalIgnoreCase)));

            if (!string.IsNullOrWhiteSpace(skill))
                query = query.Where(w => w.Skills.Any(s => s.ServiceName.Equals(skill, StringComparison.OrdinalIgnoreCase) ||
                                                           s.SkillName.Equals(skill, StringComparison.OrdinalIgnoreCase)));

            if (!string.IsNullOrWhiteSpace(location))
                query = query.Where(w => w.PrimaryServiceArea.Contains(location, StringComparison.OrdinalIgnoreCase));

            if (maxHourlyRate.HasValue)
                query = query.Where(w => w.HourlyRate <= maxHourlyRate.Value);

            if (minHourlyRate.HasValue)
                query = query.Where(w => w.HourlyRate >= minHourlyRate.Value);

            var list = query.ToList();
            var paged = list.Skip((page - 1) * pageSize).Take(pageSize).ToList();
            return Task.FromResult(((IEnumerable<Worker>)paged, list.Count));
        }

        public Task<Worker> CreateWorkerAsync(Worker worker)
        {
            worker.Id = Workers.Count > 0 ? Workers.Max(w => w.Id) + 1 : 1;
            Workers.Add(worker);
            return Task.FromResult(worker);
        }

        public Task<Worker> CreateWorkerDirectAsync(string email, string? name, string? description, string primaryServiceArea, double coverageRadiusKm, string pricingModel, decimal? hourlyRate, decimal? dailyRate, List<WorkerSkill> skills)
        {
            var worker = new Worker
            {
                Id = Workers.Count > 0 ? Workers.Max(w => w.Id) + 1 : 1,
                Email = email,
                Name = name ?? "Worker",
                Description = description,
                PrimaryServiceArea = primaryServiceArea,
                CoverageRadiusKm = coverageRadiusKm,
                PricingModel = pricingModel,
                HourlyRate = hourlyRate,
                DailyRate = dailyRate,
                Skills = skills
            };
            Workers.Add(worker);
            return Task.FromResult(worker);
        }

        public Task<Worker?> UpdateWorkerAsync(int id, Worker updatedWorker)
        {
            var existing = Workers.FirstOrDefault(w => w.Id == id);
            if (existing == null) return Task.FromResult<Worker?>(null);

            existing.Name = updatedWorker.Name;
            existing.Description = updatedWorker.Description;
            existing.PrimaryServiceArea = updatedWorker.PrimaryServiceArea;
            existing.PricingModel = updatedWorker.PricingModel;
            existing.HourlyRate = updatedWorker.HourlyRate;
            existing.DailyRate = updatedWorker.DailyRate;
            existing.IsAvailable = updatedWorker.IsAvailable;
            return Task.FromResult<Worker?>(existing);
        }

        public Task<bool> DeleteWorkerAsync(int id)
        {
            var existing = Workers.FirstOrDefault(w => w.Id == id);
            if (existing == null) return Task.FromResult(false);
            Workers.Remove(existing);
            return Task.FromResult(true);
        }

        public Task<bool> DeleteWorkerByEmailAsync(string email)
        {
            var existing = Workers.FirstOrDefault(w => string.Equals(w.Email, email, StringComparison.OrdinalIgnoreCase));
            if (existing == null) return Task.FromResult(false);
            Workers.Remove(existing);
            return Task.FromResult(true);
        }

        public Task<Worker?> UpdatePerformanceAsync(int id, double rating, bool isCompleted)
        {
            var worker = Workers.FirstOrDefault(w => w.Id == id);
            if (worker == null) return Task.FromResult<Worker?>(null);
            if (isCompleted) worker.CompletedJobs++;
            worker.OverallRating = rating;
            return Task.FromResult<Worker?>(worker);
        }

        public Task<WorkerSkill?> AddSkillAsync(int workerId, WorkerSkill skill)
        {
            var worker = Workers.FirstOrDefault(w => w.Id == workerId);
            if (worker == null) return Task.FromResult<WorkerSkill?>(null);
            skill.Id = worker.Skills.Count > 0 ? worker.Skills.Max(s => s.Id) + 1 : 1;
            skill.WorkerId = workerId;
            worker.Skills.Add(skill);
            return Task.FromResult<WorkerSkill?>(skill);
        }

        public Task<bool> RemoveSkillAsync(int workerId, int skillId)
        {
            var worker = Workers.FirstOrDefault(w => w.Id == workerId);
            if (worker == null) return Task.FromResult(false);
            var skill = worker.Skills.FirstOrDefault(s => s.Id == skillId);
            if (skill == null) return Task.FromResult(false);
            worker.Skills.Remove(skill);
            return Task.FromResult(true);
        }

        public Task<bool> UpdateAvailabilityAsync(int workerId, bool isAvailable, string? scheduleJson)
        {
            var worker = Workers.FirstOrDefault(w => w.Id == workerId);
            if (worker == null) return Task.FromResult(false);
            worker.IsAvailable = isAvailable;
            worker.AvailabilityScheduleJson = scheduleJson;
            return Task.FromResult(true);
        }

        public Task<bool> UpdatePricingAsync(int workerId, string model, decimal? hourlyRate, decimal? dailyRate)
        {
            var worker = Workers.FirstOrDefault(w => w.Id == workerId);
            if (worker == null) return Task.FromResult(false);
            worker.PricingModel = model;
            worker.HourlyRate = hourlyRate;
            worker.DailyRate = dailyRate;
            return Task.FromResult(true);
        }

        public Task<bool> UpdateServiceAreaAsync(int workerId, string serviceArea, double radiusKm)
        {
            var worker = Workers.FirstOrDefault(w => w.Id == workerId);
            if (worker == null) return Task.FromResult(false);
            worker.PrimaryServiceArea = serviceArea;
            worker.CoverageRadiusKm = radiusKm;
            return Task.FromResult(true);
        }

        public Task<bool> UpdatePasswordAsync(int workerId, string newPassword)
        {
            var worker = Workers.FirstOrDefault(w => w.Id == workerId);
            if (worker == null) return Task.FromResult(false);
            worker.PasswordHash = newPassword;
            return Task.FromResult(true);
        }
    }

    public class FakeResidentRepository : IResidentRepository
    {
        public Task<Resident?> GetResidentAsync(string email) => Task.FromResult<Resident?>(null);
        public Task<bool> UpdateResidentAsync(string email, ResidentUpdateDto residentDto) => Task.FromResult(true);
        public Task<bool> DeleteResidentAsync(string email) => Task.FromResult(true);
        public Task<bool> VerifyResidentAsync(string email, string? nicNumber) => Task.FromResult(true);
    }

    public static class WorkerTestHelper
    {
        public static SuperbassDbContext CreateInMemoryDbContext()
        {
            var options = new DbContextOptionsBuilder<SuperbassDbContext>()
                .UseInMemoryDatabase(databaseName: Guid.NewGuid().ToString())
                .Options;

            var context = new SuperbassDbContext(options);

            var worker1 = new Worker
            {
                Id = 1,
                Name = "Kamal Perera",
                Email = "kamal@workio.lk",
                PhoneNo = "0771234567",
                IsVerified = true,
                PrimaryServiceArea = "Colombo",
                CoverageRadiusKm = 10,
                PricingModel = "Hourly",
                HourlyRate = 2500m,
                DailyRate = 12000m,
                IsAvailable = true,
                OverallRating = 4.8,
                QualityRating = 5,
                PunctualityRating = 5,
                CommunicationRating = 5,
                CompletedJobs = 20,
                AcceptedJobs = 22,
                RejectedJobs = 2,
                CancelledJobs = 1
            };

            var worker2 = new Worker
            {
                Id = 2,
                Name = "Nimal Silva",
                Email = "nimal@workio.lk",
                PhoneNo = "0719876543",
                IsVerified = false,
                PrimaryServiceArea = "Kandy",
                CoverageRadiusKm = 15,
                PricingModel = "Daily",
                HourlyRate = 1500m,
                DailyRate = 8000m,
                IsAvailable = false,
                OverallRating = 4.2,
                CompletedJobs = 10,
                AcceptedJobs = 12,
                RejectedJobs = 3,
                CancelledJobs = 2
            };

            context.Workers.AddRange(worker1, worker2);

            var skill1 = new WorkerSkill
            {
                Id = 101,
                WorkerId = 1,
                ServiceName = "Plumbing",
                SkillName = "Plumbing",
                Skills = new List<string> { "Pipe Fitting", "Leak Repair" },
                ExperienceYears = 5
            };

            var skill2 = new WorkerSkill
            {
                Id = 102,
                WorkerId = 2,
                ServiceName = "Electrical",
                SkillName = "Electrical",
                Skills = new List<string> { "Wiring", "Circuit Repair" },
                ExperienceYears = 3
            };

            context.WorkerSkills.AddRange(skill1, skill2);
            context.SaveChanges();

            return context;
        }

        public static IConfiguration CreateMockConfiguration()
        {
            var inMemorySettings = new Dictionary<string, string?> {
                {"Jwt:Key", "SuperSecretKeyForWorkioAuthentication2026!#$"},
                {"Jwt:Issuer", "SuperbassAPI"},
                {"Jwt:Audience", "SuperbassClient"}
            };
            return new ConfigurationBuilder()
                .AddInMemoryCollection(inMemorySettings)
                .Build();
        }
    }
}
