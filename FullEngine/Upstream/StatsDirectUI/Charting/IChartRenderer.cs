using System;
using StatsDirect.Templates;

namespace StatsDirect.Charting
{
    public interface IChartRenderer : IDisposable
    {
        ParameterBag Plot(ITemplateHost host, bool isForReturnedParametersOnly);
        /// <summary>
        /// Intended to obtain a completed canvas for read only.
        /// </summary>
        IStatsDirectCanvas Canvas { get; }
        string GetAscii();

        ScaleParameters GetScaleParameters();
    }
}
