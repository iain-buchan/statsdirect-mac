namespace StatsDirect.Charting
{
    class SvgCanvasFactory : ICanvasFactory
    {
        IStatsDirectCanvas ICanvasFactory.Create(int width, int height)
        {
            return new SvgCanvas(width, height);
        }
    }
}
