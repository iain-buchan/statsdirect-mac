using System;
using System.Collections.Generic;
using System.Xml.Serialization;
using StatsDirect.Data;
using StatsDirect.UI;
using StatsDirect.Charting;

namespace StatsDirect.Templates
{
    [XmlRoot("filled-parameter")]
    [Serializable]
    public abstract class FilledParameter
    {
        protected FilledParameter()
        {
        }

        protected FilledParameter(FilledParameterDirection direction)
        {
            Direction = direction;
        }

        [XmlIgnore]
        public abstract bool HasData { get; }

        [XmlIgnore]
        public bool IsInputParameter => FilledParameterDirection.Input == Direction;

        [XmlElement("direction")]
        public FilledParameterDirection Direction { get; set; }

        [XmlIgnore]
        public virtual bool AsBoolean { get => throw new ArgumentException("FilledParameter is not a Boolean"); }

        [XmlIgnore]
        public virtual ChartOptions AsChartOptions { get => throw new ArgumentException("FilledParameter is not a ChartOptions"); }

        [XmlIgnore]
        public virtual DataFrame AsDataFrame { get => throw new ArgumentException("FilledParameter is not a DataFrame"); }

        [XmlIgnore]
        public virtual DataFrame2D AsDataFrame2D { get => throw new ArgumentException("FilledParameter is not a DataFrame2D"); }

        [XmlIgnore]
        public virtual DateTime AsDate { get => throw new ArgumentException("FilledParameter is not a Date"); }

        [XmlIgnore]
        public virtual double AsDouble { get => throw new ArgumentException("FilledParameter is not a Double"); }

        [XmlIgnore]
        public virtual int AsInt32 { get => throw new ArgumentException("FilledParameter is not an Int32"); }

        [XmlIgnore]
        public abstract object AsObject { get; }

        [XmlIgnore]
        public virtual Pane AsPane { get => throw new ArgumentException("FilledParameter is not a Pane"); }

        [XmlIgnore]
        public virtual PaneAndPosition AsPaneAndPosition { get => throw new ArgumentException("FilledParameter is not a PaneAndPosition"); }

        [XmlIgnore]
        public virtual ParameterBag AsParameterBag { get => throw new ArgumentException("FilledParameter is not a ParameterBag"); }

        [XmlIgnore]
        public virtual IList<ParameterBag> AsParameterBagList { get => throw new ArgumentException("FilledParameter is not a IList<ParameterBag>"); }

        [XmlIgnore]
        public virtual ScaleParameters AsScaleParameters { get => throw new ArgumentException("FilledParameter is not a ScaleParameters"); }

        [XmlIgnore]
        public virtual string AsString { get => throw new ArgumentException("FilledParameter is not a string"); }

        [XmlIgnore]
        public virtual IList<string> AsStringList { get => throw new ArgumentException("FilledParameter is not a IList<string>"); }

        [XmlIgnore]
        public virtual bool IsBoolean { get => false; }

        [XmlIgnore]
        public virtual bool IsDataFrame { get => false; }

        [XmlIgnore]
        public virtual bool IsDouble { get => false; }

        [XmlIgnore]
        public virtual bool IsInt32 { get => false; }

        [XmlIgnore]
        public virtual bool IsParameterBag { get => false; }

        [XmlIgnore]
        public virtual bool IsParameterBagList { get => false; }

        [XmlIgnore]
        public virtual bool IsString { get => false; }

        public abstract void Accept(IFilledParameterVisitor visitor);
    }
}
