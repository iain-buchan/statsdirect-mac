using System.Xml.Serialization;
using System;
using System.Collections.Generic;
namespace StatsDirect.Data
{
    [Serializable]
    public class DataFrame
    {
        public DataFrame()
        {
            Variables = new List<IVariable>();
        }

        public DataFrame(IVariable v)
        {
            Variables = new List<IVariable> { v };
        }

        public DataFrame(IVariable v, string name)
            : this(v)
        {
            Name = name;
        }

        ///  <summary>
        ///  A name that can be used to identify the frame by the user
        ///  </summary>
        [XmlElement("name")]
        public string Name { get; set; }

        [XmlIgnore]
        public IList<IVariable> Variables { get; set; }

        [XmlArray("variables")]
        [XmlArrayItem("boolean-variable", typeof(BooleanVariable))]
        [XmlArrayItem("classifier-variable", typeof(ClassifierVariable))]
        [XmlArrayItem("date-variable", typeof(DateVariable))]
        [XmlArrayItem("double-variable", typeof(DoubleVariable))]
        [XmlArrayItem("string-variable", typeof(StringVariable))]
        [XmlArrayItem("variant-variable", typeof(VariantVariable))]
        public IVariable[] VariablesForXml
        {
            get
            {
                IVariable[] retval = new IVariable[Variables.Count];
                int i = 0;
                foreach (IVariable v in Variables)
                    retval[i++] = v;
                return retval;
            }
            set
            {
                Variables.Clear();
                foreach (IVariable v in value)
                    Variables.Add(v);
            }
        }

        public int VariableCount => Variables.Count;

        public void EnsureVariables(int MinimumSize)
        {
            while (Variables.Count < MinimumSize)
                Variables.Add(null);
        }

        public int MaxRows
        {
            get
            {
                int maxLength = 0;
                foreach (IVariable v in Variables)
                    maxLength = Math.Max(maxLength, v.Length);
                return maxLength;
            }
        }

        public int MinRows
        {
            get
            {
                if (Variables.Count == 0)
                    return 0;

                int minLength = int.MaxValue;
                foreach (IVariable v in Variables)
                    minLength = Math.Min(minLength, v.Length);
                return minLength;
            }
        }

        ///  <summary>
        ///  Fill the specified target array as (row, column) from our own variables.
        ///  </summary>
        ///  <param name="target"></param>
        ///  <remarks>The array is assumed to be large enough to hold all of our contents.  Non-double values in the source are represented as Double.NaN.</remarks>
        public void FillArray(double[,] target)
        {
            for (int c = 0; c < Variables.Count; c++)
            {
                DoubleVariable v = (DoubleVariable)Variables[c];
                for (int r = 0; r < v.Length; r++)
                    target[r, c] = v.Data[r];
            }
        }

        public IVariable FindVariable(string title)
        {
            foreach (IVariable v in Variables)
                if (v.Title != null && v.Title.Equals(title))
                    return v;
            return null;
        }
    }
}
