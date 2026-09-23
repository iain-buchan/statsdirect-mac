namespace StatsDirect.Charting
{
    class EmfCanvasFactory : ICanvasFactory
    {
        IStatsDirectCanvas ICanvasFactory.Create(int width, int height)
        {
            return new EmfCanvas(width, height);
        }
    }
}
