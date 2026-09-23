using System;
using System.Collections.Generic;

namespace StatsDirect.Data
{
    [Serializable]
    public class DataFrame2D
    {
        public DataFrame2D()
        {
            Variables = new List<IList<IVariable>>();
        }

        public DataFrame2D(IVariable v)
        {
            Variables = new List<IList<IVariable>>();
            IList<IVariable> subV = new List<IVariable>();
            subV.Add(v);
            Variables.Add(subV);
        }

        public DataFrame2D(IVariable v, string name)
        {
            Variables = new List<IList<IVariable>>();
            IList<IVariable> subV = new List<IVariable> { v };
            Variables.Add(subV);
            Name = name;
        }

        ///  <summary>
        ///  A name that can be used to identify the frame by the user
        ///  </summary>
        public string Name { get; set; }

        public IList<IList<IVariable>> Variables { get; set; }

        public int VariableCount => Variables.Count;

        public int VariableCountTheOtherWay
        {
            get
            {
                int maxCount = 0;
                foreach (IList<IVariable> vl in Variables)
                    maxCount = Math.Max(maxCount, vl.Count);
                return maxCount;
            }
        }

        ///  <summary>
        ///  Ensure there are at least MinimumSize1 variable sets, with all able to hold at least MinimumSize2 variables.
        ///  </summary>
        ///  <param name="minimumSize1"></param>
        ///  <param name="minimumSize2"></param>
        ///  <remarks></remarks>
        public void EnsureVariablesSquare(int minimumSize1, int minimumSize2)
        {
            //  Ensure MinimumSize1 variable lists
            while (Variables.Count < minimumSize1)
            {
                IList<IVariable> vbls = new List<IVariable>(minimumSize2);
                Variables.Add(vbls);
            }
            //  Ensure Minimum1 is at least MinimumSize2 in size
            foreach (IList<IVariable> vbls in Variables)
                while (vbls.Count < minimumSize2)
                    vbls.Add(null);
        }

        ///  <summary>
        ///  Ensure there are at least MinimumSize1 variable sets, with the Minimum1th able to hold at least MinimumSize2 variables.
        ///  </summary>
        ///  <param name="minimumSize1"></param>
        ///  <param name="minimumSize2"></param>
        ///  <remarks></remarks>
        public void EnsureVariablesJagged(int minimumSize1, int minimumSize2)
        {
            //  Ensure MinimumSize1 variable lists
            while (Variables.Count < minimumSize1)
                Variables.Add(new List<IVariable>(minimumSize2));

            //  Ensure Minimum1 is at least MinimumSize2 in size
            IList<IVariable> vbls1 = Variables[minimumSize1 - 1];
            while (vbls1.Count < minimumSize2)
                vbls1.Add(null);
        }

        public int MaxRows
        {
            get
            {
                int maxLength = 0;
                foreach (IList<IVariable> vl in Variables)
                    foreach (IVariable v in vl)
                        if (v != null)
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
                foreach (IList<IVariable> vl in Variables)
                    foreach (IVariable v in vl)
                        if (v != null)
                            minLength = Math.Min(minLength, v.Length);
                return minLength;
            }
        }

        public void TruncateToLength(int maximumLength)
        {
            while (Variables.Count > maximumLength)
                Variables.RemoveAt(maximumLength);
        }
    }
}
