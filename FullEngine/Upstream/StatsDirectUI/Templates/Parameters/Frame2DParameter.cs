using System;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    public enum DataAcquisitionMode2D
    {
        NotSet = 0,
        GroupThenBlock,
        BlockThenGroup
    }

    [Serializable]
    public sealed class Frame2DParameter: Parameter
    {
        private bool columnsAreSameLength;
        private Expression length;
        private Expression minimumColumns;
        private Expression maximumColumns;
        private DataAcquisitionMode2D dataAcquisitionMode;
        private bool shouldClearSelectionFirst;
        private bool shouldAskForGroupId;
        private bool shouldSquare;
        private Expression subPrompt;

        public string SubPrompt(ITemplateProcessor processor, ParameterBag parameters)
        {
            if (null == subPrompt)
                return null;
            return (string)processor.Evaluate(subPrompt, parameters);
        }

        [XmlElement(ElementName = "sub-prompt")]
        public Expression SubPromptExpression
        {
            get => subPrompt;
            set => subPrompt = value;
        }

        /// <summary>
        /// If true, all columns selected must be of the same length.
        /// If false, columns may be of mixed lengths.
        /// </summary>
        [XmlElement(ElementName="same-length")]
        public bool ColumnsAreSameLength
        {
            get => columnsAreSameLength;
            set => columnsAreSameLength = value;
        }

        /// <summary>
        /// The mode in which the data should be loaded into the frame
        /// </summary>
        [XmlElement(ElementName = "mode")]
        public DataAcquisitionMode2D DataAcquisitionMode
        {
            get => dataAcquisitionMode;
            set => dataAcquisitionMode = value;
        }

        /// <summary>
        /// The exact number of rows that must be selected with this operation, or null for any number.
        /// </summary>
        public int Length(ITemplateProcessor processor, ParameterBag parameters)
        {
            return (int)processor.Evaluate(length, parameters);
        }

        /// <summary>
        /// true iff the parameter defines the exact number of rows that must be selected with this operation.
        /// </summary>
        public bool HasLength => null != length;

        /// <summary>
        /// The exact number of rows that must be selected with this operation, or null for any number.
        /// </summary>
        [XmlElement(ElementName = "length")]
        public Expression LengthExpression
        {
            get => length;
            set => length = value;
        }

        /// <summary>
        /// The smallest number of columns that may be selected with this operation.
        /// Must be less than or equal to MaximumColumns.
        /// </summary>
        public int MinimumColumns(ITemplateProcessor processor, ParameterBag parameters)
        {
            return (int)processor.Evaluate(minimumColumns, parameters);
        }

        /// <summary>
        /// The smallest number of columns that may be selected with this operation.
        /// Must be less than or equal to MaximumColumns.
        /// </summary>
        [XmlElement(ElementName = "min-columns")]
        public Expression MinimumColumnsExpression
        {
            get => minimumColumns;
            set => minimumColumns = value;
        }

        /// <summary>
        /// The largest number of columns that may be selected with this operation.
        /// Must be greater than or equal to MinimumColumns.
        /// </summary>
        public int MaximumColumns(ITemplateProcessor processor, ParameterBag parameters)
        {
            return (int)processor.Evaluate(maximumColumns, parameters);
        }

        /// <summary>
        /// The expression for the largest number of columns that may be selected with this operation.
        /// </summary>
        [XmlElement(ElementName = "max-columns")]
        public Expression MaximumColumnsExpression
        {
            get => maximumColumns;
            set => maximumColumns = value;
        }

        /// <summary>
        /// If true, UIs should clear the user's selection before trying to obtain this parameter.
        /// If false, pre-existing selections should be honoured.
        /// </summary>
        [XmlElement(ElementName = "clear-selection-first")]
        public bool ShouldClearSelectionFirst
        {
            get => shouldClearSelectionFirst;
            set => shouldClearSelectionFirst = value;
        }

        /// <summary>
        /// If true, UIs should clear the user's selection before trying to obtain this parameter.
        /// If false, pre-existing selections should be honoured.
        /// </summary>
        [XmlElement(ElementName = "ask-for-group-id")]
        public bool ShouldAskForGroupId
        {
            get => shouldAskForGroupId;
            set => shouldAskForGroupId = value;
        }

        /// <summary>
        /// If true, UIs should square up the number of sub-variables and each variable's length before returning.
        /// If false, jagged sub-variables and lengths are allowed.
        /// </summary>
        [XmlElement(ElementName = "should-square")]
        public bool ShouldSquare
        {
            get => shouldSquare;
            set => shouldSquare = value;
        }

        public override bool RequiresGrid => true;

        public override InputDuringStep RequiresInputGiven(ParameterBag parameters)
        {
            return MustRequest || null != Name && null != parameters && !parameters.ContainsKey(Name) ? InputDuringStep.SometimesOrAlways : InputDuringStep.Never;
        }

        public override void Accept(IParameterVisitor visitor)
        {
            visitor.Visit(this);
        }

        public override ParameterBag AllDefaults(ITemplateProcessor processor, ParameterBag context)
        {
            return new ParameterBag();
        }
    }
}
