using System;
using System.Globalization;
using System.Linq;
using System.Text.Json;
using StatsDirect.Builtins;
using StatsDirect.Data;
using StatsDirect.Expressions;
using StatsDirect.Numerics;
using StatsDirect.Templates;

// Mac equivalents of input controls that live in the Windows shell, not numerics.
internal static class HostDataForms {
    internal static ParameterBag TextCodes(OperationJob job, ParameterBag context) {
        var data=context["data"].AsDataFrame;
        var labels=data.Variables.Cast<StringVariable>().SelectMany(v=>v.Data).Where(s=>!string.IsNullOrWhiteSpace(s)&&s!="*").Distinct().ToArray();
        var fields=labels.Select((s,i)=>HostAmendments.Field("c"+i,s,i+1,"integer")).ToArray();
        var a=HostAmendments.Form(job,"Assign numeric codes",fields,v=>{foreach(var f in v.EnumerateObject()){double n=HostParameters.Number(f.Value);if(n!=Math.Truncate(n)||n<int.MinValue||n>int.MaxValue)throw new ArgumentException("Codes must be whole numbers.");}});
        var codes=labels.Select((s,i)=>new {s,n=HostParameters.Number(a.GetProperty("c"+i))}).ToDictionary(x=>x.s,x=>x.n);
        var output=new DataFrame();foreach(var v in data.Variables.Cast<StringVariable>())output.Variables.Add(new DoubleVariable(v.Data.Select(s=>s!=null&&codes.TryGetValue(s,out var n)?n:Constant.MISSING).ToArray(),v.Title));
        var result=new ParameterBag();result.AddOutput("output",output);return result;
    }
    internal static ParameterBag Categorise(OperationJob job,CategoriseOptions options,ParameterBag context) {
        var valid=options.Data.Data.Where(n=>n!=Constant.MISSING).ToArray();
        if(valid.Length==0)throw new ArgumentException("Select at least one observed value.");
        double[] boundaries=null;
        HostAmendments.Form(job,"Category boundaries",new[]{HostAmendments.Field("boundaries","Upper boundaries, separated by commas",valid.Average().ToString(CultureInfo.InvariantCulture),"text")},a=>{
            if(!a.GetProperty("boundaries").GetString().Split(',').All(s=>double.TryParse(s,NumberStyles.Float,CultureInfo.InvariantCulture,out var n)&&double.IsFinite(n)))throw new ArgumentException("Enter numeric boundaries separated by commas.");
            boundaries=a.GetProperty("boundaries").GetString().Split(',').Select(s=>double.Parse(s,CultureInfo.InvariantCulture)).ToArray();
            if(boundaries.Length>1000||boundaries.Zip(boundaries.Skip(1),(x,y)=>x<y).Any(ok=>!ok))throw new ArgumentException("Use strictly increasing boundaries.");
        },"Values on a boundary belong to the lower category. Codes start at 1; missing values stay missing.");
        options.PassX=options.Data.Data.Select(n=>n==Constant.MISSING?n:(double)(Array.FindIndex(boundaries,b=>n<=b) is var i && i>=0?i+1:boundaries.Length+1)).ToArray();
        options.Categories=Enumerable.Range(0,boundaries.Length+1).Select(i=>i==0?"≤ "+boundaries[0]:i==boundaries.Length?"> "+boundaries[^1]:"> "+boundaries[i-1]+"; ≤ "+boundaries[i]).ToArray();
        options.Counts=Enumerable.Range(1,boundaries.Length+1).Select(i=>options.PassX.Count(n=>n==i)).ToArray();return context;
    }
    internal static ParameterBag Extract(OperationJob job,ExtractionOptions options,ParameterBag context) {
        var identifiers=options.IdentifiersFrame??options.DataFrame;
        Calcit calc=null;
        var a=HostAmendments.Form(job,"Extract matching rows",new[]{HostAmendments.Field("expression","Rule using X1, X2, …","X1>0","text")},v=>{
            try{calc=new Calcit(v.GetProperty("expression").GetString(),Enumerable.Repeat(DataType.Double,identifiers.VariableCount).ToArray(),false);if(calc.OutputType!=DataType.Boolean)throw new ArgumentException("The expression must return true or false.");}
            catch(Exception e){throw new ArgumentException(e.Message);}
        },options.IdentifierNames);
        var rows=Enumerable.Range(0,identifiers.MinRows).Where(r=>calc.Evaluate<bool>(identifiers.Variables.Cast<DoubleVariable>().Select(v=>v.Data[r]).ToArray())).ToArray();
        var result=new ParameterBag();result.AddOutput("extracted",TakeRows(options.DataFrame,rows,"Extracted data"));return result;
    }
    internal static ParameterBag Sort(OperationJob job,OperationHost host,ParameterBag context) {
        var data=context["data"].AsDataFrame;
        var a=HostAmendments.Form(job,"Sort data",new[]{HostAmendments.Field("column","Sort by column number",1,"integer",1,data.VariableCount),HostAmendments.Field("descending","Descending (0 = no, 1 = yes)",0,"integer",0,1)},v=>{
            double c=HostParameters.Number(v.GetProperty("column")),d=HostParameters.Number(v.GetProperty("descending"));if(c<1||c>data.VariableCount||c!=Math.Truncate(c)||d!=0&&d!=1)throw new ArgumentException("Choose a valid column and sort direction.");
        },"The Mac prototype opens a sorted copy of the selected columns in a new worksheet. Include every column that must stay aligned.");
        var key=data.Variables[(int)HostParameters.Number(a.GetProperty("column"))-1];
        var indices=Enumerable.Range(0,data.MaxRows);bool numeric=indices.All(r=>r>=key.Length||double.TryParse(Convert.ToString(key.DataAsObject(r)),NumberStyles.Float,CultureInfo.InvariantCulture,out _));
        var comparer=System.Collections.Generic.Comparer<int>.Create((x,y)=>{
            string l=x<key.Length?Convert.ToString(key.DataAsObject(x)):"",r=y<key.Length?Convert.ToString(key.DataAsObject(y)):"";
            return numeric&&double.TryParse(l,NumberStyles.Float,CultureInfo.InvariantCulture,out var ln)&&double.TryParse(r,NumberStyles.Float,CultureInfo.InvariantCulture,out var rn)?ln.CompareTo(rn):StringComparer.CurrentCulture.Compare(l,r);
        });
        var rows=(HostParameters.Number(a.GetProperty("descending"))==1?indices.OrderByDescending(i=>i,comparer):indices.OrderBy(i=>i,comparer)).ToArray();
        host.Frames.Add(HostParameters.FrameOutput(TakeRows(data,rows,"Sorted data"),false));return context;
    }
    internal static ParameterBag Filter(OperationJob job,OperationHost host,ParameterBag context) {
        var data=context["data"].AsDataFrame;
        var a=HostAmendments.Form(job,"Filter worksheet rows",new[]{HostAmendments.Field("column","Filter column number",1,"integer",1,data.VariableCount),HostAmendments.Field("match","Keep rows containing this text (blank keeps all)","","text")},v=>{
            double c=HostParameters.Number(v.GetProperty("column"));if(c<1||c>data.VariableCount||c!=Math.Truncate(c))throw new ArgumentException("Choose a valid column.");
        },"The Mac prototype opens matching rows in a new worksheet; it does not change Excel's filter arrows or hide source rows.");
        var key=data.Variables[(int)HostParameters.Number(a.GetProperty("column"))-1];string match=a.GetProperty("match").GetString();
        var rows=Enumerable.Range(0,data.MaxRows).Where(r=>(r<key.Length?Convert.ToString(key.DataAsObject(r)):"").Contains(match,StringComparison.CurrentCultureIgnoreCase)).ToArray();
        host.Frames.Add(HostParameters.FrameOutput(TakeRows(data,rows,"Filtered data"),false));return context;
    }
    static DataFrame TakeRows(DataFrame data,int[] rows,string name) {
        var output=new DataFrame{Name=name};
        foreach(var v in data.Variables) {
            if(v is DoubleVariable numbers)output.Variables.Add(new DoubleVariable(rows.Select(r=>r<v.Length?numbers.Data[r]:Constant.MISSING).ToArray(),v.Title));
            else output.Variables.Add(new StringVariable(rows.Select(r=>r<v.Length?Convert.ToString(v.DataAsObject(r),CultureInfo.InvariantCulture):"").ToArray(),v.Title));
        }
        return output;
    }
}
