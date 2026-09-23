using StatsDirect.Data;
using StatsDirect.UI;

namespace StatsDirect.Templates
{
    /// <summary>
    /// User interface communication between engine and host.  TODO: This needs a complete rework for a web-based interface.
    /// </summary>
    public interface IUserInterface
    {
        bool GetBoolean(string prompt, string title, bool initialValue, out bool cancelled);

        /// <summary>
        /// Cause the report to be output in some way, for example by asking the user where to render it, then rendering it.
        /// </summary>
        /// <param name="renderable">The thing to be rendered as a report. Passed in this way as different template hosts might need to render in different ways.</param>
        /// <param name="operation"></param>
        /// <param name="preferredOutputLocation">If non-null, indicates a possible host-controlled place to put the output</param>
        /// <returns>The host-assigned identity of the report that was used, or null if the report was not output at all.</returns>
        object OutputReport(IRenderable renderable, Operation operation, object preferredOutputLocation);

        /// <summary>
        /// The user (or similar decision-maker) should be allowed to amend whatever is deemed appropriate of the options.
        /// </summary>
        /// <param name="options"></param>
        /// <param name="context"></param>
        /// <returns>a parameter bag if the options shold be processed, null if the user cancelled or the operation failed</returns>
        ParameterBag Amend(IFillable options, ParameterBag context);

        /// <summary>
        /// Show/log an error to the user.
        /// </summary>
        /// <param name="message"></param>
        /// <param name="caption"></param>
        void Error(string message, string caption);

        /// <summary>
        /// Show/log a warning to the user.
        /// </summary>
        /// <param name="message"></param>
        /// <param name="caption"></param>
        void Warning(string message, string caption);

        /// <summary>
        /// Returns true if the host is willing to combine this parameter with any previous parameters requested with FillParameter and shouldCombine=true; false if not.
        /// </summary>
        /// <param name="parameter"></param>
        /// <returns></returns>
        bool CanCombine(Parameter parameter);

        /// <summary>
        /// Present and allow the user to fill any outstanding parameters.  Keep going until they validate or the user cancels.
        /// </summary>
        /// <param name="processor"></param>
        /// <param name="context">The already filled-in parameters - some parameters require these</param>
        /// <returns>The filled-in parameters</returns>
        /// <exception cref="TemplateOperationCancelledException">if the user cancels the acquisition of the parameter</exception>
        ParameterBag FillAndValidateCombinedParameters(ITemplateProcessor processor, ParameterBag context);

        /// <summary>
        /// Get the value(s) of the user-entered parameter(s) and return them in a new ParameterBag to be merged with the other parameters.
        /// This must be able to deal with all subclasses of Parameter.
        /// </summary>
        /// <param name="processor"></param>
        /// <param name="parameter"></param>
        /// <param name="context">The already filled-in parameters - some parameters require these</param>
        /// <param name="shouldCombine">If true, the host should batch this Parameter with any others it receives until a call to FillCombinedParameters.  If false, the parameter should be filled immediately.</param>
        /// <returns>The filled-in parameters, or null if shouldCombine is true</returns>
        /// <exception cref="TemplateOperationCancelledException">if the user cancels the acquisition of the parameter</exception>
        ParameterBag FillParameter(ITemplateProcessor processor, Parameter parameter, ParameterBag context, bool shouldCombine);

        /// <summary>
        /// Notes that this user-entered parameter will at some point be required, and prepares to produce it.
        /// This must be able to deal with all subclasses of Parameter.
        /// </summary>
        /// <param name="processor"></param>
        /// <param name="parameter"></param>
        /// <param name="context"></param>
        /// <returns></returns>
        void PrepareParameter(ITemplateProcessor processor, Parameter parameter, ParameterBag context);

        /// <summary>
        /// Cause the frame to be output in some way, for example by asking the user in which grid to put it, then filling in the grid.
        /// </summary>
        /// <param name="frame">The frame to be output</param>
        /// <param name="keepSelection">If true, the host should keep outputting to the current location; if false, the host should internally SelectOutputForFrame().</param>
        /// <param name="isFormulae">If true, the frame is assumed to contain strings to be set as formulae; if false, the frame is assumed to contain data values.</param>
        /// <param name="missingIndicator">The text to place in the output if a value in the frame is missing.</param>
        /// <param name="preferredOutputLocation">If non-null, indicates a possible host-controlled place to put the output</param>
        /// <param name="defaultPosition">A hint for the step's preferred place to put the output. TODO: This is user-interfacey; we should find a better way of communicating this.</param>
        void OutputFrame(DataFrame frame, bool keepSelection, bool isFormulae, string missingIndicator, PaneAndPosition preferredOutputLocation, RelativePosition defaultPosition);

        Operation Operation { get; set; }
    }
}
