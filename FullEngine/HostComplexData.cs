using System;
using System.Linq;
using System.Collections.Generic;
using StatsDirect.Builtins;
using StatsDirect.Data;
using StatsDirect.Numerics;
using StatsDirect.Templates;
using StatsDirect.Utilities;

// Host-side data arrangement mirrors GridSelectionProcessor; all statistical work stays in Builtins.
internal static class HostComplexData {
    internal static DataFrame AskFrame(OperationJob job, string title, int min, int max, bool equal = false, int length = 0) {
        string error = null;
        while (true) {
            var input = job.Ask(new() { ["kind"]="grid",["title"]=title,["prompt"]=title,["minColumns"]=min,["maxColumns"]=max,["rows"]=Math.Max(12,length),["length"]=length,["equalLength"]=equal,["error"]=error });
            try {
                var frame = HostParameters.ReadFrame(input, DataAcquisitionMode.NumericReplaceMissing);
                if (frame.VariableCount < min || frame.VariableCount > max) throw new ArgumentException($"Select {min} to {max} columns.");
                if (equal && frame.MinRows != frame.MaxRows) throw new ArgumentException("All columns must have equal length. Use * for missing observations.");
                if (length > 0 && (frame.MinRows != length || frame.MaxRows != length)) throw new ArgumentException($"Each column must have {length} rows.");
                job.Record(title,input); return frame;
            } catch (ArgumentException ex) { error = ex.Message; }
        }
    }
    internal static DataFrame2D Frame2D(OperationJob job, Frame2DParameter p, ITemplateProcessor processor, ParameterBag context) {
        bool repeats = p.DataAcquisitionMode == DataAcquisitionMode2D.BlockThenGroup;
        string title = repeats ? "Number of repeats" : "Number of groups";
        var number = HostAmendments.Form(job, title, new[]{HostAmendments.Field("n",title,2,"integer",2,100)}, v=>{double n=HostParameters.Number(v.GetProperty("n"));if(n<2||n>100||n!=Math.Truncate(n))throw new ArgumentException("Enter a whole number from 2 to 100.");});
        int count = (int)HostParameters.Number(number.GetProperty("n")); var frames = new List<DataFrame>();
        for(int i=0;i<count;i++) frames.Add(AskFrame(job,repeats?$"Repeat {i+1}: subjects in rows, treatments in columns":$"Group {i+1}: one column per subgroup",p.MinimumColumns(processor,context),p.MaximumColumns(processor,context),p.ColumnsAreSameLength,repeats&&i>0?frames[0].MaxRows:0));
        var result = new DataFrame2D(); result.Name=string.Join("; ",frames.Select(f=>f.Name));
        if(repeats) {
            int rows=frames[0].MaxRows,cols=frames[0].VariableCount;
            if(frames.Any(f=>f.VariableCount!=cols))throw new ArgumentException("Every repeat must have the same treatments.");
            result.EnsureVariablesSquare(rows,cols);
            for(int r=0;r<rows;r++)for(int c=0;c<cols;c++)result.Variables[r][c]=new DoubleVariable(frames.Select(f=>((DoubleVariable)f.Variables[c]).Data[r]).ToArray(),frames[0].Variables[c].Title);
        } else {
            for(int g=0;g<count;g++){result.EnsureVariablesJagged(g+1,frames[g].VariableCount);for(int c=0;c<frames[g].VariableCount;c++)result.Variables[g][c]=frames[g].Variables[c];}
            if(p.ShouldSquare)foreach(var group in result.Variables)foreach(var v in group) v?.EnsureLengthAndPadWithMissing(result.MaxRows);
        }
        return result;
    }
    internal static GroupedCovarianceData GroupedCovariance(OperationJob job, OperationHost host) {
        var predictors=AskFrame(job,"Select predictor (X) series — one column per group",2,200);
        // The Windows grouped-covariance form removes missing observations within each selected series.
        foreach(DoubleVariable v in predictors.Variables)v.Data=v.Data.Where(n=>n!=Constant.MISSING).ToArray();
        int k=predictors.VariableCount,maxr=predictors.MaxRows;
        bool replicate=host.GetBoolean("Use Y replicates", "Grouped linear covariance",false,out _);
        var outcomes=new List<DataFrame>();int maxreps=1;
        for(int g=0;g<k;g++){
            int n=predictors.Variables[g].Length;
            var frame=AskFrame(job,replicate?$"Group {g+1}: one column of Y replicates for each X value":$"Group {g+1}: Y outcomes for {predictors.Variables[g].Title}",replicate?n:1,replicate?n:1,!replicate,replicate?0:n);
            foreach(DoubleVariable v in frame.Variables)v.Data=v.Data.Where(n=>n!=Constant.MISSING).ToArray();
            if(!replicate&&frame.MaxRows!=n)throw new ArgumentException("Missing Y observations do not match the X series. Supply complete paired observations.");
            outcomes.Add(frame);if(replicate)maxreps=Math.Max(maxreps,frame.MaxRows);
        }
        var ci=HostAmendments.Form(job,"Confidence level",new[]{HostAmendments.Field("ci","Confidence level (%)",host.Preferences.DefaultConfidenceInterval*100)},v=>{var ci=HostParameters.Number(v.GetProperty("ci"));if(ci<=0||ci>=100)throw new ArgumentException("Confidence must be greater than 0 and less than 100%.");});
        var data=new GroupedCovarianceData {k=k,maxr=maxr,maxreps=maxreps,GAMMA=HostParameters.Number(ci.GetProperty("ci"))/100,
            a=new double[k+1],b=new double[k+1],bnam=new string[k+1],cx=new ColumnData[k+1],nxi=new int[k+1],ny=new int[k+1,maxr+1],rssx=new double[k+1],xmean=new double[k+1],ymean=new double[k+1],xt=new double[k+1,maxr+1],y=new double[k+1,maxr+1,maxreps+1],
            xlab=string.Join(" ",predictors.Variables.Select(v=>v.Title)),minMax=new MinMax {MinX=double.MaxValue,MaxX=double.MinValue,MinY=double.MaxValue,MaxY=double.MinValue}};
        for(int g=1;g<=k;g++){
            var x=(DoubleVariable)predictors.Variables[g-1];data.cx[g]=new ColumnData {Title=x.Title,Rows=x.Length,Sum=x.Sum};data.nxi[g]=x.Length;
            for(int r=1;r<=x.Length;r++){
                data.xt[g,r]=x.Data[r-1];data.minMax.MinX=Math.Min(data.minMax.MinX,x.Data[r-1]);data.minMax.MaxX=Math.Max(data.minMax.MaxX,x.Data[r-1]);
                var values=replicate?((DoubleVariable)outcomes[g-1].Variables[r-1]).Data:new[]{((DoubleVariable)outcomes[g-1].Variables[0]).Data[r-1]};data.ny[g,r]=values.Length;
                for(int n=0;n<values.Length;n++){data.y[g,r,n+1]=values[n];data.minMax.MinY=Math.Min(data.minMax.MinY,values[n]);data.minMax.MaxY=Math.Max(data.minMax.MaxY,values[n]);}
            }
        }
        return data;
    }
}
