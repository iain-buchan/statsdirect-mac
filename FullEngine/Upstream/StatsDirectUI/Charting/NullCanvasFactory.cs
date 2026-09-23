namespace StatsDirect.Charting
{
    class NullCanvasFactory : ICanvasFactory
    {
        IStatsDirectCanvas ICanvasFactory.Create(int width, int height)
        {
            return new NullCanvas(width, height);
        }
    }
}
