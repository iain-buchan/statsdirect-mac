using System;
using System.Collections.Generic;
using System.Globalization;

namespace StatsDirect.Templates
{
    public class DateAxisScale: IAxisScale
    {
        public double MinimumDataValue { get; }
        public double MaximumDataValue { get; }
        public double MinimumScaleValue { get; }
        public double MaximumScaleValue { get; }

        public DateAxisScale(double minimumDataValue, double maximumDataValue, double minimumScaleValue, double maximumScaleValue)
        {
            MinimumDataValue = minimumDataValue;
            MaximumDataValue = maximumDataValue;
            MinimumScaleValue = minimumScaleValue;
            MaximumScaleValue = maximumScaleValue;
        }

        public override string ToString()
        {
            return $"DateAxisScale({MinimumScaleValue}, {MaximumScaleValue})";
        }

        IList<Tic> IAxisScale.Tics()
        {
            IList<Tic> tics = new List<Tic>();
            DateTime minimumScaleDate = DateTime.FromOADate(MinimumScaleValue);
            DateTime maximumScaleDate = DateTime.FromOADate(MaximumScaleValue);
            TimeSpan scaleInterval = maximumScaleDate.Subtract(minimumScaleDate);
            if (scaleInterval.TotalMinutes < 12)
            {
                // Use minutes
                DateTime candidate = new(minimumScaleDate.Year, minimumScaleDate.Month, minimumScaleDate.Day, minimumScaleDate.Hour, minimumScaleDate.Minute, 0);
                if (minimumScaleDate.Second > 0)
                    candidate = candidate.AddMinutes(1);
                while (candidate <= maximumScaleDate)
                {
                    tics.Add(new Tic(candidate.ToOADate(), candidate.ToString(CultureInfo.CurrentCulture.DateTimeFormat.ShortTimePattern)));
                    candidate = candidate.AddMinutes(1);
                }
            }
            else if (scaleInterval.TotalMinutes < 30)
            {
                // Use 5-minute intervals
                DateTime candidate = new(minimumScaleDate.Year, minimumScaleDate.Month, minimumScaleDate.Day, minimumScaleDate.Hour, minimumScaleDate.Minute, 0);
                if (minimumScaleDate.Second > 0)
                    candidate = candidate.AddMinutes(1);
                while (candidate.Minute % 5 != 0)
                    candidate = candidate.AddMinutes(1);
                while (candidate <= maximumScaleDate)
                {
                    tics.Add(new Tic(candidate.ToOADate(), candidate.ToString(CultureInfo.CurrentCulture.DateTimeFormat.ShortTimePattern)));
                    candidate = candidate.AddMinutes(5);
                }
            }
            else if (scaleInterval.TotalHours < 2)
            {
                // Use quarter hours
                DateTime candidate = new(minimumScaleDate.Year, minimumScaleDate.Month, minimumScaleDate.Day, minimumScaleDate.Hour, minimumScaleDate.Minute, 0);
                if (minimumScaleDate.Second > 0)
                    candidate = candidate.AddMinutes(1);
                while (candidate.Minute % 15 != 0)
                    candidate = candidate.AddMinutes(1);
                while (candidate <= maximumScaleDate)
                {
                    tics.Add(new Tic(candidate.ToOADate(), candidate.ToString(CultureInfo.CurrentCulture.DateTimeFormat.ShortTimePattern)));
                    candidate = candidate.AddMinutes(15);
                }
            }
            else if (scaleInterval.TotalDays < 1)
            {
                // Use hours
                DateTime candidate = new(minimumScaleDate.Year, minimumScaleDate.Month, minimumScaleDate.Day, minimumScaleDate.Hour, 0, 0);
                if (minimumScaleDate.Minute > 0 || minimumScaleDate.Second > 0)
                    candidate = candidate.AddHours(1);
                while (candidate <= maximumScaleDate)
                {
                    tics.Add(new Tic(candidate.ToOADate(), candidate.ToString()));
                    candidate = candidate.AddHours(1);
                }
            }
            else if (scaleInterval.TotalDays <= 15)
            {
                // Use days
                DateTime candidate = new(minimumScaleDate.Year, minimumScaleDate.Month, minimumScaleDate.Day, 0, 0, 0);
                if (minimumScaleDate.Hour > 0 || minimumScaleDate.Minute > 0 || minimumScaleDate.Second > 0)
                    candidate = candidate.AddDays(1);
                while (candidate <= maximumScaleDate)
                {
                    tics.Add(new Tic(candidate.ToOADate(), candidate.ToString()));
                    candidate = candidate.AddDays(1);
                }
            }
            else if (scaleInterval.TotalDays <= 60)
            {
                // Use weeks
                DateTime candidate = new(minimumScaleDate.Year, minimumScaleDate.Month, minimumScaleDate.Day, 0, 0, 0);
                if (minimumScaleDate.Hour > 0 || minimumScaleDate.Minute > 0 || minimumScaleDate.Second > 0)
                    candidate = candidate.AddDays(1);
                DayOfWeek firstDay = CultureInfo.CurrentCulture.DateTimeFormat.FirstDayOfWeek;
                while (candidate.DayOfWeek != firstDay)
                    candidate = candidate.AddDays(1);
                while (candidate <= maximumScaleDate)
                {
                    tics.Add(new Tic(candidate.ToOADate(), candidate.ToString(CultureInfo.CurrentCulture.DateTimeFormat.ShortDatePattern)));
                    candidate = candidate.AddDays(7);
                }
            }
            else if (scaleInterval.TotalDays <= 200)
            {
                // Use months
                DateTime candidate = new(minimumScaleDate.Year, minimumScaleDate.Month, 1, 0, 0, 0);
                if (minimumScaleDate.Day > 1 || minimumScaleDate.Hour > 0 || minimumScaleDate.Minute > 0 || minimumScaleDate.Second > 0)
                    candidate = candidate.AddMonths(1);
                while (candidate <= maximumScaleDate)
                {
                    tics.Add(new Tic(candidate.ToOADate(), candidate.ToString(CultureInfo.CurrentCulture.DateTimeFormat.ShortDatePattern)));
                    candidate = candidate.AddMonths(1);
                }
            }
            else if (scaleInterval.TotalDays <= 800)
            {
                // Use quarters
                DateTime candidate = new(minimumScaleDate.Year, minimumScaleDate.Month, 1, 0, 0, 0);
                if (minimumScaleDate.Day > 1 || minimumScaleDate.Hour > 0 || minimumScaleDate.Minute > 0 || minimumScaleDate.Second > 0)
                    candidate = candidate.AddMonths(1);
                while (candidate.Month % 3 != 1)
                    candidate = candidate.AddMonths(1);
                while (candidate <= maximumScaleDate)
                {
                    tics.Add(new Tic(candidate.ToOADate(), candidate.ToString(CultureInfo.CurrentCulture.DateTimeFormat.ShortDatePattern)));
                    candidate = candidate.AddMonths(3);
                }
            }
            else if (scaleInterval.TotalDays <= 7400)
            {
                // Use years
                DateTime candidate = new(minimumScaleDate.Year, 1, 1, 0, 0, 0);
                if (minimumScaleDate.DayOfYear > 1 || minimumScaleDate.Hour > 0 || minimumScaleDate.Minute > 0 || minimumScaleDate.Second > 0)
                    candidate = candidate.AddYears(1);
                while (candidate <= maximumScaleDate)
                {
                    tics.Add(new Tic(candidate.ToOADate(), candidate.ToString(CultureInfo.CurrentCulture.DateTimeFormat.ShortDatePattern)));
                    candidate = candidate.AddYears(1);
                }
            }
            else if (scaleInterval.TotalDays <= 74000)
            {
                // Use decades
                DateTime candidate = new(minimumScaleDate.Year, 1, 1, 0, 0, 0);
                if (minimumScaleDate.DayOfYear > 1 || minimumScaleDate.Hour > 0 || minimumScaleDate.Minute > 0 || minimumScaleDate.Second > 0)
                    candidate = candidate.AddYears(1);
                while (candidate.Year % 10 != 0)
                    candidate = candidate.AddYears(1);
                while (candidate <= maximumScaleDate)
                {
                    tics.Add(new Tic(candidate.ToOADate(), candidate.ToString(CultureInfo.CurrentCulture.DateTimeFormat.ShortDatePattern)));
                    candidate = candidate.AddYears(10);
                }
            }
            else
            {
                // Use centuries
                DateTime candidate = new(minimumScaleDate.Year, 1, 1, 0, 0, 0);
                if (minimumScaleDate.DayOfYear > 1 || minimumScaleDate.Hour > 0 || minimumScaleDate.Minute > 0 || minimumScaleDate.Second > 0)
                    candidate = candidate.AddYears(1);
                while (candidate.Year % 10 != 0)
                    candidate = candidate.AddYears(1);
                while (candidate.Year % 100 != 0)
                    candidate = candidate.AddYears(10);
                while (candidate <= maximumScaleDate)
                {
                    tics.Add(new Tic(candidate.ToOADate(), candidate.ToString(CultureInfo.CurrentCulture.DateTimeFormat.ShortDatePattern)));
                    candidate = candidate.AddYears(100);
                }
            }
            return tics;
        }

        void IAxisScale.Accept(IAxisScaleVisitor visitor)
        {
            visitor.Visit(this);
        }
    }
}
