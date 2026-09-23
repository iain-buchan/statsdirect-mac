using System;
using System.Collections.Generic;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    /// <summary>
    /// Might an action require input?
    /// </summary>
    public enum InputDuringStep
    {
        /// <summary>
        /// This action will never require input
        /// </summary>
        Never,
        /// <summary>
        /// This action will always require input
        /// </summary>
        SometimesOrAlways
    }

    /// <summary>
    /// The base class of anything that performs processing during an Operation.
    /// </summary>
    [Serializable]
    public abstract class Step : IMightRequireInput
    {
        private string name;

        /// <summary>
        /// Note non-default value: by default, parameters are *kept*, not discarded.  This is to assist in follow-on operations, where parameters may need to be kept between ops.
        /// </summary>
        private bool shouldCopyInputParameters = true;

        private Operation operation;

        [XmlIgnore]
        public Operation Operation => operation;

        [XmlAttribute(AttributeName = "name")]
        public string Name
        {
            get => name;
            set => name = value;
        }

        /// <summary>
        /// If true, input parameters are copied to the output after the step is processed but before the next step is processed.
        /// Parameters that already exist in the output will <strong>not</strong> be overwritten if this flag is used.
        /// </summary>
        [XmlAttribute(AttributeName = "copy-input-parameters")]
        public bool ShouldCopyInputParameters
        {
            get => shouldCopyInputParameters;
            set => shouldCopyInputParameters = value;
        }

        /// <summary>
        /// Execute the operation with the passed-in parameters, returning some results that can be used for the next operation.
        /// Implementers <strong>must</strong> ensure that a new dictionary is used for the output.
        /// </summary>
        /// <param name="parameters"></param>
        /// <param name="processor"></param>
        /// <param name="isRedo"></param>
        /// <returns></returns>
        public abstract StepOutput ExecuteInternal(ITemplateProcessor processor, ParameterBag parameters);

        internal virtual void NoteOperation(Operation op)
        {
            operation = op;
        }

        public virtual void PrepareInternal(ITemplateProcessor processor, ParameterBag parms)
        {
            // Default: No preparation required
        }

        [XmlIgnore]
        public virtual bool RequiresGrid => false;

        public abstract InputDuringStep RequiresInputGiven(ParameterBag parameters);

        public virtual bool IsOrContains(Step step)
        {
            return this == step;
        }

        internal static InputDuringStep GetInputRequirement(IList<Step> steps, ParameterBag parameters)
        {
            foreach (Step step in steps)
            {
                switch (step.RequiresInputGiven(parameters))
                {
                    case InputDuringStep.SometimesOrAlways:
                        // If any step requires input, so does the overall set of steps
                        return InputDuringStep.SometimesOrAlways;
                    default:
                        // Do nothing
                        break;
                }
            }

            // If we get here, there are no steps that require input.
            return InputDuringStep.Never;
        }

        /// <summary>
        /// Returns true if there is at least one step of the requested type and nothing between step and that typed step will ever ask for input.
        /// </summary>
        /// <param name="stepToFind"></param>
        /// <param name="steps"></param>
        /// <param name="stepType"></param>
        /// <param name="found"></param>
        /// <param name="stepFound"></param>
        /// <returns></returns>
        public static HasInput ShouldRequestTargetAfter(Step stepToFind, IList<Step> steps, Type stepType, bool found, out Step stepFound)
        {
            // TODO: How to handle conditionals and recursion?  eg Paired T asking for report inside its conditional

            // Approach: Go through the operation (found = false) until we find the given step (found = true).
            // Then keep going until we hit something else that will request input (can't aggregate) or something of the relevant step type (can aggregate) or the end of the report (don't know).
            // TODO: Do we ever need to pass real parameters into this?
            ParameterBag parameters = new();
            foreach (Step candidate in steps)
            {
                if (found)
                {
                    // Some previous step was the one we saw, and we've not yet reached a decision as to whether we should request a report target.
                    if (stepType.IsInstanceOfType(candidate))
                    {
                        // We've reached a report step with no intervening steps that might require user input.
                        stepFound = candidate;
                        return HasInput.NoAndTypeFound;
                    }
                    if (candidate.RequiresInputGiven(parameters) != InputDuringStep.Never)
                    {
                        // We've not reached a report step, and something wants input.
                        stepFound = null;
                        return HasInput.Yes;
                    }
                    // Otherwise there's no reason to believe we can't do this - keep looking.
                }
                else if (candidate.IsOrContains(stepToFind))
                {
                    HasInput nestedHasInput = candidate.ShouldRequestTargetAfter(stepToFind, stepType, found, out Step _);
                    if (nestedHasInput == HasInput.Yes)
                    {
                        stepFound = null;
                        return HasInput.Yes;
                    }

                    // Set *after* the test for found, so that we don't examine the candidate (almost certainly a parameters step) to see if it wants input.
                    found = true;

                }
            }
            // If we get here, the step wasn't found at all or there was no report step.  Tell the caller, as they may want to make a slightly custom decision based on that.
            stepFound = null;
            return HasInput.NoAndTypeNotFound;
        }

        public virtual HasInput ShouldRequestTargetAfter(Step stepToFind, Type stepType, bool found, out Step foundStep)
        {
            foundStep = null;
            return HasInput.NoAndTypeNotFound;
        }

        public abstract void Accept(IStepVisitor visitor);
    }
}
