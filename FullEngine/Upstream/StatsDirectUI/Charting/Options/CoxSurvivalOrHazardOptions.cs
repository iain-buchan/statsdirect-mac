using StatsDirect.Data;
using StatsDirect.Utilities;
using System;

namespace StatsDirect.Charting
{
    [Serializable]
    public class CoxSurvivalOrHazardOptions : GenericOptions
    {
        public CoxP[] z;
        public int iobs;
        public int istrata;
        public CoxPlotMode plotMode;
        public int igroups;
        public int groupid;
        public bool grouped;
        public bool stratified;
        public double[,,] arr3;
        public ColumnData[] cdat1;
        public bool useTic;
        public bool useMarker;

        public override bool ShowLegendIsRelevant => false;

        public override void Accept(IChartOptionVisitor visitor)
        {
            visitor.Visit(this);
        }

        public CoxSurvivalOrHazardOptions(CoxP[] z, int iobs, int istrata, CoxPlotMode plotMode, int igroups, int groupid, bool grouped, bool stratified, double[,,] arr3, ColumnData[] cdat1, bool useTic, bool useMarker)
        {
            this.z = z;
            this.iobs = iobs;
            this.istrata = istrata;
            this.plotMode = plotMode;
            this.igroups = igroups;
            this.groupid = groupid;
            this.grouped = grouped;
            this.stratified = stratified;
            this.arr3 = arr3;
            this.cdat1 = cdat1;
            this.useTic = useTic;
            this.useMarker = useMarker;
        }
    }
}
