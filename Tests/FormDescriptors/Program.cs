// Checks the Mac descriptor contract against the Windows InlineParameterPreparer
// semantics for every XML parameter, including parameters inside conditional steps.
// This is a descriptor audit with controlled contexts, not a numerical branch replay.
using System.Reflection;
using System.Text.Json;
using System.Text.RegularExpressions;
using StatsDirect.Data;
using StatsDirect.Templates;
using StatsDirect.TemplateProcessing;
using StatsDirect.UI;

_ = SdApplication.SoleInstance;
var engine = typeof(Parameter).Assembly;
var host = (ITemplateHost)Activator.CreateInstance(engine.GetType("StatsDirect.UI.ViewerHost")!, new object[]{new List<OperationTestInputParameter>()})!;
ITemplateProcessor processor = new TemplateProcessor(host);
var describe = engine.GetType("HostParameters")!.GetMethod("Describe", BindingFlags.NonPublic|BindingFlags.Static)!;
var parse = engine.GetType("HostParameters")!.GetMethod("Parse", BindingFlags.NonPublic|BindingFlags.Static)!;
var results = new List<object>(); var failures = new List<string>(); int checkedCount=0, routed=0;
var controls=new Dictionary<string,JsonElement>();
void Control(JsonElement descriptor) {
    string kind=descriptor.GetProperty("kind").GetString();
    if(kind=="grid")return; // Real Cuzick and stratified grids are covered by the native engine test.
    string key=kind=="selectList"?kind+":"+descriptor.GetProperty("multiple")+":"+descriptor.GetProperty("allowNone"):kind;
    if(!controls.ContainsKey(key))controls[key]=descriptor.Clone();
}
JsonElement Describe(Parameter p, ParameterBag context) => JsonSerializer.SerializeToElement(describe.Invoke(null,new object[]{p,processor,context,host.Preferences,null}));
ParameterBag Parse(Parameter p, object value, ParameterBag context) => (ParameterBag)parse.Invoke(null,new object[]{p,JsonSerializer.SerializeToElement(value),processor,context,null})!;
void Equal(object actual, object expected, string field) {
    if(JsonSerializer.Serialize(actual)!=JsonSerializer.Serialize(expected)) throw new Exception(field+": expected "+JsonSerializer.Serialize(expected)+", got "+JsonSerializer.Serialize(actual));
}
DataFrame Frame(int width=3, int rows=6) {
    var frame=new DataFrame();for(int c=0;c<width;c++)frame.Variables.Add(new DoubleVariable(Enumerable.Range(1,rows).Select(r=>(double)(r+c)).ToArray(),"Variable "+(c+1)));return frame;
}
DataFrame Labels() {var f=new DataFrame();f.Variables.Add(new StringVariable(new[]{"First","Second","Third"},"Name"));f.Variables.Add(new StringVariable(new[]{"1","2","3"},"Value"));return f;}
IEnumerable<(Parameter p,string path)> Parameters(IEnumerable<Step> steps,string prefix="steps") {
    int i=0;foreach(var step in steps) {
        string path=prefix+"/"+(++i);
        if(step is ParametersStep ps) {int j=0;foreach(var p in ps.Parameters)yield return(p,path+"/parameters/"+(++j));}
        if(step is TestStep t) {foreach(var x in Parameters(t.TrueSteps,path+"/true"))yield return x;foreach(var x in Parameters(t.FalseSteps,path+"/false"))yield return x;}
        if(step is IterationStep it)foreach(var x in Parameters(it.Steps,path+"/iteration"))yield return x;
    }
}
ParameterBag Context(Operation operation) {
    var b=new ParameterBag();
    foreach(var (p,_) in Parameters(operation.Steps)) {
        if(p.Name==null)continue;
        object value=p switch {
            BooleanParameter=>true, IntegerParameter=>3, ConfidenceIntervalParameter=>.95,
            DoubleParameter=>2.5, DateParameter=>new DateTime(2026,1,2),
            OptionParameter o=>o.Options.FirstOrDefault()?.Value??"", StringParameter=>"Label",
            _=>Frame()
        }; b[p.Name]=FilledParameterFactory.Input(value);
        if(p is PickFromListParameter pick)b[pick.Source]=FilledParameterFactory.Output(Labels());
        if(p is EditGridParameter edit)b[edit.Source]=FilledParameterFactory.Output(Labels());
        if(p is PickVariablesParameter pickVars)b[pickVars.ParameterName]=FilledParameterFactory.Input(Frame());
    }
    foreach(var name in new[]{"ng","ycats","xcats","group-index","i","repeat"})b[name]=FilledParameterFactory.Output(3);
    foreach(var name in new[]{"a_min","natst-min","mx0","timesAdjustment"})b[name]=FilledParameterFactory.Output(1.5);
    foreach(var name in new[]{"variable_list","default_new_column_name"})b[name]=FilledParameterFactory.Output("Fixture");
    b["standardisation"]=FilledParameterFactory.Input("weight|age|male");b["age-unit"]=FilledParameterFactory.Input("year");
    b["stat_in"]=FilledParameterFactory.Output("Odds ratio");b["use_ratio"]=FilledParameterFactory.Output(true);
    return b;
}
foreach(var operation in TemplateFactory.Operations.Values.OrderBy(o=>o.Name)) {
 foreach(var (p,path) in Parameters(operation.Steps)) {
    var id=operation.Name+"/"+path+"/"+p.GetType().Name+":"+p.Name;
    // These are routed before Describe, not silently missing descriptors.
    string route=p switch {
        Frame2DParameter=>"HostComplexData.Frame2D", GroupedCovarianceParameter=>"HostComplexData.GroupedCovariance",
        SpecialParameter s when s.SpecialType is "frame" or "report"=>"output destination",
        SpecialParameter s when s.SpecialType=="rubric"=>"report rubric",
        SpecialParameter s when s.SpecialType=="addedConstant"=>"OperationHost added constant",
        SpecialParameter s when s.SpecialType=="textToNumbers"=>"HostDataForms.TextCodes",
        SpecialParameter s when s.SpecialType=="scores"=>"HostAmendments.ScoresOptions", _=>null
    };
    if(route!=null) {results.Add(new{id,status="host-route",route});routed++;continue;}
    try {
        var context=Context(operation);
        if(p.Name!=null && p is not EditGridParameter) context.Remove(p.Name);
        if(p is SpecialParameter special && special.SpecialType=="1-to-n")context.AddInput(p.Name,Frame(1,3));
        var fresh=Describe(p,context);
        Equal(fresh.GetProperty("name"),p.Name,"parameter name");
        Equal(fresh.GetProperty("prompt"),p.Prompt(processor,context,p.Title??"Enter a value"),"prompt");
        Equal(fresh.GetProperty("skip"),p.CancelSkipsParameter,"skip action");
        object retained=null; object defaultValue=null;
        switch(p) {
            case BooleanParameter b: defaultValue=b.DefaultValue(processor,context)??false;retained=!(bool)defaultValue;break;
            case ConfidenceIntervalParameter c: defaultValue=(c.DefaultValue(processor,context)??host.Preferences.DefaultConfidenceInterval)*100;retained=.975;break;
            case DoubleParameter n:
                defaultValue=n.DefaultValue(processor,context);retained=12.5;
                Equal(fresh.GetProperty("min"),n.MinimumValue(processor,context),"minimum");Equal(fresh.GetProperty("max"),n.MaximumValue(processor,context),"maximum");break;
            case IntegerParameter n: defaultValue=n.DefaultValue(processor,context);retained=7;break;
            case StringParameter s: defaultValue=s.DefaultValue(processor,context);retained="Retained text";Equal(fresh.GetProperty("maxLength"),s.MaxLength,"maximum text length");break;
            case DateParameter date: defaultValue=(date.HasDefaultValue?date.DefaultValue(processor,context):DateTime.Today).ToString("yyyy-MM-dd HH:mm:ss");retained=new DateTime(2024,5,6,13,14,15);break;
            case OptionParameter o:
                defaultValue=o.DefaultValue(processor,context);var available=o.Options.Where(x=>x.AvailableIf(processor,context)).ToArray();
                Equal(fresh.GetProperty("options").EnumerateArray().Select(x=>x.GetProperty("value").GetString()).ToArray(),available.Select(x=>x.Value).ToArray(),"available choices");
                retained=available.LastOrDefault()?.Value;break;
            case OptionsParameter o:
                foreach(var option in o.Options)context.AddInput(option.Name,!option.Selected);
                var choices=Describe(p,context).GetProperty("options").EnumerateArray().ToArray();
                for(int i=0;i<o.Options.Count;i++)Equal(choices[i].GetProperty("selected"),!o.Options[i].Selected,"retained tick "+o.Options[i].Name);
                break;
            case FrameParameter f:
                Equal(fresh.GetProperty("minColumns"),f.MinimumColumns(processor,context),"minimum columns");Equal(fresh.GetProperty("maxColumns"),f.MaximumColumns(processor,context),"maximum columns");
                if(!f.CanSelect)Equal(fresh.GetProperty("screen"),true,"embedded table");
                if(f.HasLength)Equal(fresh.GetProperty("length"),f.Length(processor,context),"required rows");
                context.AddInput(p.Name,Frame(2,4));var initialized=Describe(p,context);Equal(initialized.GetProperty("rows"),4,"prepared rows");Equal(initialized.GetProperty("initial").GetProperty("columns").GetArrayLength(),2,"prepared columns");break;
            case Double2By2Parameter t:
                context.AddInput(t.TopLeftName,1d);context.AddInput(t.TopRightName,2d);context.AddInput(t.BottomLeftName,3d);context.AddInput(t.BottomRightName,4d);
                var table=Describe(p,context);Equal(table.GetProperty("initial").GetProperty("columns").EnumerateArray().Select(c=>c.GetProperty("values").EnumerateArray().Select(x=>x.GetDouble()).ToArray()).ToArray(),new[]{new[]{1d,3d},new[]{2d,4d}},"retained 2×2 values");break;
            case PickVariablesParameter pick:
                Equal(fresh.GetProperty("defaultValue"),pick.PreSelectVariables?Enumerable.Range(0,Math.Min(pick.MinimumVariables,context[pick.ParameterName].AsDataFrame.VariableCount)).ToArray():Array.Empty<int>(),"preselected variables");break;
            case PickFromListParameter pick:
                Equal(fresh.GetProperty("defaultValue"),pick.AllowMultiple||pick.IncludeNoneEntry?Array.Empty<int>():new[]{0},"initial list selection");
                if(pick.AllowMultiple)Parse(p,Array.Empty<int>(),context);
                if(pick.IncludeNoneEntry&&!pick.AllowMultiple)Equal(Parse(p,Array.Empty<int>(),context).Count,0,"none omits reference parameter");break;
        }
        if(retained!=null) {
            // Random seeds cannot be compared twice because their defaults are generated afresh.
            bool generated=p is IntegerParameter seed && seed.DefaultValueExpression?.Body?.Contains("DefaultSeed") == true;
            if(!generated)Equal(fresh.GetProperty("defaultValue"),defaultValue,"fresh default");
            context.AddInput(p.Name,retained);var restored=Describe(p,context);
            bool forced=p is RangeParameter range && range.ForceDefault;
            var expected=forced?defaultValue:p is ConfidenceIntervalParameter?(double)retained*100:p is DateParameter?((DateTime)retained).ToString("yyyy-MM-dd HH:mm:ss"):retained;
            if(!generated)Equal(restored.GetProperty("defaultValue"),expected,"retained default / force-default");
            if(!generated)Control(restored);
            // Calculated outputs must never seed an input merely because their names match.
            context[p.Name]=FilledParameterFactory.Output(retained);
            if(!generated)Equal(Describe(p,context).GetProperty("defaultValue"),defaultValue,"output is not a retained input");
        }
        else Control(fresh);
        checkedCount++;results.Add(new{id,status="pass"});
    } catch(Exception error) {
        while(error is TargetInvocationException && error.InnerException!=null)error=error.InnerException;
        failures.Add(id+": "+error.Message);results.Add(new{id,status="fail",error=error.Message});
    }
 }
}
string report=args.FirstOrDefault()??"form-descriptors.json";
File.WriteAllText(report,JsonSerializer.Serialize(new{operations=TemplateFactory.Operations.Count,checkedCount,routed,failures=failures.Count,results},new JsonSerializerOptions{WriteIndented=true}));
File.WriteAllText(Path.Combine(Path.GetDirectoryName(Path.GetFullPath(report))!,"form-controls.json"),JsonSerializer.Serialize(controls.Values));
foreach(var error in failures.Take(25))Console.WriteLine("FAIL "+error);
Console.WriteLine($"Descriptor audit: {checkedCount} passed, {routed} explicit host routes, {failures.Count} failed; {report}");
return failures.Count==0?0:1;
