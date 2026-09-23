using System;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    [Serializable,
       XmlInclude(typeof(BooleanParameter)),
       XmlInclude(typeof(ConfidenceIntervalParameter)),
       XmlInclude(typeof(DateParameter)),
       XmlInclude(typeof(DoubleParameter)),
       XmlInclude(typeof(Double2By2Parameter)),
       XmlInclude(typeof(Double2By2ByKParameter)),
       XmlInclude(typeof(EditGridParameter)),
       XmlInclude(typeof(FrameParameter)),
       XmlInclude(typeof(Frame2DParameter)),
       XmlInclude(typeof(GroupedCovarianceParameter)),
       XmlInclude(typeof(IntegerParameter)),
       XmlInclude(typeof(OptionParameter)),
       XmlInclude(typeof(OptionsParameter)),
       XmlInclude(typeof(PickFromListParameter)),
       XmlInclude(typeof(PickVariablesParameter)),
       XmlInclude(typeof(SpecialParameter)),
       XmlInclude(typeof(StringParameter))]
    public abstract class Parameter : IMightRequireInput
    {
        protected Parameter()
        {
            Column = 1;
        }

        public bool AcquireIfTrue(ITemplateProcessor processor, ParameterBag parameters)
        {
            if (null == AcquireIfTrueExpression || null == AcquireIfTrueExpression.Body)
                return true;
            return (bool)processor.Evaluate(AcquireIfTrueExpression, parameters);
        }

        public string Prompt(ITemplateProcessor processor, ParameterBag parameters, string defaultPrompt = null)
        {
            if (null == PromptExpression || null == PromptExpression.Body)
                return defaultPrompt;
            return (string)processor.Evaluate(PromptExpression, parameters);
        }

        public string Rubric(ITemplateProcessor processor, ParameterBag parameters)
        {
            if (null == RubricExpression || null == RubricExpression.Body)
                return null;
            return (string)processor.Evaluate(RubricExpression, parameters);
        }

        [XmlIgnore]
        public Operation Operation { get; set; }

        [XmlElement(ElementName = "lifetime")]
        public ParameterLifetime Lifetime { get; set; }

        [XmlElement(ElementName="title")]
        public string Title { get; set; }

        /// <summary>
        /// If true, this parameter must be requested from the user (if there is a user) even if it is already present as an input parameter.
        /// The new parameter must overwrite the old one.
        /// This is generally used in post-hoc processing to ensure that repeated operations are handled correctly.
        /// </summary>
        [XmlElement(ElementName = "must-request")]
        public bool MustRequest { get; set; }

        [XmlIgnore]
        public bool HasPrompt => null != PromptExpression && null != PromptExpression.Body;

        [XmlIgnore]
        public bool HasAcquireIfTrue => null != AcquireIfTrueExpression && null != AcquireIfTrueExpression.Body;

        [XmlElement(ElementName = "prompt")]
        public Expression PromptExpression { get; set; }

        [XmlElement(ElementName = "rubric")]
        public Expression RubricExpression { get; set; }

        [XmlElement(ElementName = "acquire-if-true")]
        public Expression AcquireIfTrueExpression { get; set; }

        /// <summary>
        /// The name of another parameter which must be present and non-blank in the parameters collection for this parameter to be requested.
        /// </summary>
        [XmlElement(ElementName = "requires-parameter")]
        public string RequiresParameter { get; set; }

        /// <summary>
        /// The name by which the parameter will be known within the parameters collection.
        /// </summary>
        [XmlElement(ElementName = "name")]
        public string Name { get; set; }

        /// <summary>
        /// Ways by which the parameter should be validated
        /// </summary>
        [XmlArray(ElementName = "validators"), XmlArrayItem(ElementName = "validator", Type = typeof (Validator))]
        public Validator[] Validators { get; set; }

        /// <summary>
        /// The error message that should be shown if there is a validator and it fails.
        /// If this is not set, the default error message should be used.
        /// </summary>
        [XmlElement(ElementName = "validation-fail-message")]
        public string ValidationFailMessage { get; set; }

        /// <summary>
        /// If non-null, UIs should fill a null value if the user cancels entry of the value (and should display the value of the parameter as a prompt on any interface they may present).
        /// If null, UIs should throw a user cancelled exception if the user cancels entry of the value.
        /// </summary>
        [XmlElement(ElementName = "cancel-skips-parameter")]
        public string CancelSkipsParameter { get; set; }

        /// <summary>
        /// If true, UIs should render the prompt before the input for the parameter.
        /// If false (default), UIs should render the prompt after the parameter.
        /// </summary>
        [XmlElement(ElementName = "prompt-precedes-parameter")]
        public bool PromptPrecedesParameter { get; set; }

        /// <summary>
        /// The column in which the UI should render the element.  Defaults to 1.
        /// </summary>
        [XmlElement(ElementName = "column")]
        public int Column { get; set; }

        [XmlElement(ElementName = "help")]
        public HelpTip Help { get; set; }

        public virtual bool RequiresGrid => false;

        public abstract InputDuringStep RequiresInputGiven(ParameterBag parameters);

        public abstract void Accept(IParameterVisitor visitor);

        /// <summary>
        /// If the parameter has any defaults, return them as inputs in a ParameterBag.
        /// </summary>
        /// <param name="processor">The processor to use while evaluating any defaults</param>
        /// <param name="context">Existing variables against which the values could be evaluated.</param>
        public abstract ParameterBag AllDefaults(ITemplateProcessor processor, ParameterBag context);
    }
}
