using System.Collections.Generic;
using System.Linq;
using System.Xml.Serialization;

namespace StatsDirect.Templates
{
    public class OperationTest
    {
        [XmlAttribute("reason")]
        public string Reason { get; set; }

        public OperationTest()
        {
            Inputs = new List<OperationTestInputParameter>();
            Outputs = new List<OperationTestOutputParameter>();
        }

        [XmlArray(ElementName = "inputs"),
        XmlArrayItem(ElementName = "parameter", Type = typeof(OperationTestInputParameter))]
        public OperationTestInputParameter[] InputsForXml
        {
            get => Inputs.ToArray();
            set
            {
                Inputs.Clear();
                if (null != value)
                    foreach (OperationTestInputParameter input in value)
                        Inputs.Add(input);
            }
        }

        [XmlIgnore]
        public IList<OperationTestInputParameter> Inputs { get; set; }

        [XmlArray(ElementName = "outputs"),
        XmlArrayItem(ElementName = "output", Type = typeof(OperationTestOutputParameter))]
        public OperationTestOutputParameter[] OutputsForXml
        {
            get => Outputs.ToArray();
            set
            {
                Outputs.Clear();
                if (null != value)
                    foreach (OperationTestOutputParameter output in value)
                        Outputs.Add(output);
            }
        }

        [XmlIgnore]
        public IList<OperationTestOutputParameter> Outputs { get; set; }
    }
}