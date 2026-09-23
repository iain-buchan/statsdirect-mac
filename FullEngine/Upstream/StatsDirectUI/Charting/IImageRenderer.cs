using System.IO;

namespace StatsDirect.Charting
{
    /// <summary>
    /// Renders an image from one form (a stream with dimensions provided) to another.
    /// </summary>
    public interface IImageRenderer
    {
        object Render(Stream inputImage, int width, int height);
    }
}
