using System;
using System.Xml.Serialization;

using StatsDirect.Utilities;
using System.Collections.Generic;

namespace StatsDirect.Templates
{
    [Serializable]
    public sealed class FrameParameter: Parameter
    {
        /// <summary>
        /// If true, the grid can be selected from existing data (default).
        /// If false, the grid must be entered interactively.
        /// </summary>
        [XmlElement(ElementName = "can-select")]
        public bool CanSelect { get; set; } = true;

        /// <summary>
        /// If true, all columns selected must be of the same length.
        /// If false, columns may be of mixed lengths.
        /// </summary>
        [XmlElement(ElementName="same-length")]
        public bool ColumnsAreSameLength { get; set; }

        /// <summary>
        /// The mode in which the data should be loaded into the frame
        /// </summary>
        [XmlElement(ElementName = "mode")]
        public DataAcquisitionMode DataAcquisitionMode { get; set; }

        /// <summary>
        /// If non-null and non-blank, all columns selected must be of the same length as the first column in the specified parameter.
        /// If null or blank, columns are not restricted.
        /// If multiple names are specified, they are checked in order and the first variable that is found by name is used for the length test.
        /// </summary>
        [XmlElement(ElementName = "same-length-as")]
        public List<string> SameLengthAsParameter { get; set; }

        /// <summary>
        /// If non-null and non-blank, variables are appended to the existing frame with this name.
        /// If null or blank, variables are added to a new frame.
        /// </summary>
        [XmlElement(ElementName = "append-to-frame")]
        public string AppendToFrame { get; set; }

        /// <summary>
        /// The exact number of rows that must be selected with this operation, or null for any number.
        /// </summary>
        public int Length(ITemplateProcessor processor, ParameterBag parameters)
        {
            return (int)processor.Evaluate(LengthExpression, parameters);
        }

        /// <summary>
        /// true iff the parameter defines the exact number of rows that must be selected with this operation.
        /// </summary>
        public bool HasLength => null != LengthExpression;

        /// <summary>
        /// The exact number of rows that must be selected with this operation, or null for any number.
        /// </summary>
        [XmlElement(ElementName = "length")]
        public Expression LengthExpression { get; set; }

        /// <summary>
        /// The smallest number of columns that may be selected with this operation.
        /// Must be less than or equal to MaximumColumns.
        /// </summary>
        public int MinimumColumns(ITemplateProcessor processor, ParameterBag parameters)
        {
            if (null == MinimumColumnsExpression)
                return 1;
            return (int)processor.Evaluate(MinimumColumnsExpression, parameters);
        }

        /// <summary>
        /// The smallest number of columns that may be selected with this operation.
        /// Must be less than or equal to MaximumColumns.
        /// </summary>
        [XmlElement(ElementName = "min-columns")]
        public Expression MinimumColumnsExpression { get; set; }

        /// <summary>
        /// The largest number of columns that may be selected with this operation.
        /// Must be greater than or equal to MinimumColumns.
        /// </summary>
        public int MaximumColumns(ITemplateProcessor processor, ParameterBag parameters)
        {
            if (null == MaximumColumnsExpression)
                return int.MaxValue;
            return (int)processor.Evaluate(MaximumColumnsExpression, parameters);
        }

        /// <summary>
        /// The expression for the largest number of columns that may be selected with this operation.
        /// </summary>
        [XmlElement(ElementName = "max-columns")]
        public Expression MaximumColumnsExpression { get; set; }

        /// <summary>
        /// If true, UIs should clear the user's selection before trying to obtain this parameter.
        /// If false, pre-existing selections should be honoured.
        /// </summary>
        [XmlElement(ElementName = "clear-selection-first")]
        public bool ShouldClearSelectionFirst { get; set; }

        /// <summary>
        /// If true, UIs should allow selection by group ID (if they permit this).
        /// If false, UIs should only allow selection by value.
        /// </summary>
        [XmlElement(ElementName = "ask-for-group-id")]
        public bool ShouldAskForGroupId { get; set; }

        /// <summary>
        /// If ShouldAskForGroupId is true, how should groups be selected?
        /// </summary>
        [XmlElement(ElementName = "group-id-mode")]
        public GroupIdentifierMode GroupIdentifierMode { get; set; }

        [XmlElement(ElementName = "data")]
        public FrameData Data { get; set; }

        public override bool RequiresGrid => CanSelect && null == Data;

        public override InputDuringStep RequiresInputGiven(ParameterBag parameters)
        {
            return MustRequest || null != Name && (null != parameters && !parameters.ContainsKey(Name) || null != Data) ? InputDuringStep.SometimesOrAlways : InputDuringStep.Never;
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
