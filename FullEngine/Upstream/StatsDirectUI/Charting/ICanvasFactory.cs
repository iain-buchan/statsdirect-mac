namespace StatsDirect.Charting
{
    public interface ICanvasFactory
    {
        IStatsDirectCanvas Create(int width, int height);
    }
}
