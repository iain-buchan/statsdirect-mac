namespace StatsDirect.Templates
{
    public interface IMightRequireInput
    {
        InputDuringStep RequiresInputGiven(ParameterBag parameters);
    }
}
