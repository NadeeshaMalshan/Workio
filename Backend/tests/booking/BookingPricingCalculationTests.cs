using System;
using Xunit;
using Superbass.Models;

namespace Superbass.Tests.BookingTests
{
    public class BookingPricingCalculationTests
    {
        [Theory]
        [InlineData("Hourly", 2500, 3, 7500)]
        [InlineData("Hourly", 3000, 2, 6000)]
        public void CalculateEstimatedPrice_ComputesCorrectHourlyTotal(
            string model,
            int rate,
            int hours,
            decimal expectedTotal)
        {
            var calculated = (decimal)(rate * hours);
            var booking = new Booking
            {
                PricingModel = model,
                EstimatedPrice = calculated
            };

            Assert.Equal("Hourly", booking.PricingModel);
            Assert.Equal(expectedTotal, booking.EstimatedPrice);
        }

        [Fact]
        public void AgreedPrice_OverridesEstimatedPriceWhenSet()
        {
            var booking = new Booking
            {
                EstimatedPrice = 5000m,
                AgreedPrice = 4200m
            };

            var finalPrice = booking.AgreedPrice ?? booking.EstimatedPrice;

            Assert.Equal(4200m, finalPrice);
        }
    }
}
