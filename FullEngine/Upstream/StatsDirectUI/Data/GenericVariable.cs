using System;
using System.Xml.Serialization;

namespace StatsDirect.Data
{
    [Serializable]
    public abstract class GenericVariable<T> : IVariable
    {
        private T[] data;

        protected GenericVariable()
        {
            //  Do nothing
        }

        protected GenericVariable(T[] data)
        {
            this.data = data;
        }

        protected GenericVariable(T[] data, string title)
        {
            this.data = data;
            Title = title;
        }

        protected GenericVariable(int length, string title)
        {
            EnsureLength(length);
            Title = title;
        }

        ///  <summary>
        ///  The title (name) of the variable
        ///  </summary>
        [XmlElement("title")]
        public string Title { get; set; }

        ///  <summary>
        ///  Where the variable came from
        ///  </summary>
        [XmlIgnore]
        public IOrigin Origin { get; set; }

        [XmlElement("worksheet-origin", typeof(WorksheetOrigin))]
        public object OriginForXml
        {
            get => Origin;
            set => Origin = (IOrigin)value;
        }

        ///  <summary>
        ///  Manage the entire data array at one time
        ///  </summary>
        ///  <value>The new data array to set</value>
        ///  <returns>The current data array</returns>
        ///  <remarks></remarks>
        public T[] Data
        {
            get => data;
            set
            {
                data = value;
                Invalidate();
            }
        }

        ///  <summary>
        ///  Access a single element of the data array
        ///  </summary>
        ///  <param name="index">The element to access</param>
        ///  <param name="value">The new value to set. Storage management is done internally, so the array is always sufficently large to hold the value</param>
        ///  <returns>The value at the specified index, or an exception if the index is out of bounds</returns>
        ///  <remarks></remarks>
        public void SetData(int index, T value)
        {
            EnsureLength(index + 1);
            data[index] = value;
            Invalidate();
        }

        public int Length => data == null ? 0 : data.Length;

        public void EnsureLength(int minimumLength)
        {
            if (data == null)
            {
                data = new T[minimumLength];
            }
            else
            {
                if (data.Length < minimumLength)
                {
                    T[] longer = new T[minimumLength];
                    Array.Copy(data, longer, data.Length);
                    data = longer;
                    Invalidate();
                }
            }
        }

        public void EnsureLength(int minimumLength, T fillValue)
        {
            if (data == null)
            {
                data = new T[minimumLength];
                for (int i = 0; i < minimumLength; i++)
                    data[i] = fillValue;
                Invalidate();
            }
            else
            {
                if (data.Length < minimumLength)
                {
                    int oldLength = data.Length;
                    T[] longer = new T[minimumLength];
                    Array.Copy(data, longer, data.Length);
                    data = longer;
                    for (int i = oldLength; i < minimumLength; i++)
                        data[i] = fillValue;
                    Invalidate();
                }
            }
        }

        public void TruncateDataToLength(int maximumLength)
        {
            if (data.Length > maximumLength)
            {
                T[] shorter = new T[maximumLength];
                Array.Copy(data, shorter, Math.Min(data.Length, shorter.Length));
                data = shorter;
                Invalidate();
            }
        }

        public virtual void StealDataFrom(IVariable victim)
        {
            if (!(victim is GenericVariable<T>))
                throw new InvalidCastException("Victim must be of the same type when stealing variables");
            data = ((GenericVariable<T>)victim).data;
            Invalidate();
        }

        public object DataAsObject(int i)
        {
            return Data[i];
        }

        public void DataAsObject(int i, object value)
        {
            Data[i] = (T)Convert.ChangeType(value, typeof(T));
        }

        protected virtual bool HasData => data != null;

        protected virtual void Invalidate()
        {
            // Default: Do nothing.
        }

        public abstract void Accept(IVariableVisitor visitor);

        public virtual void EnsureLengthAndPadWithMissing(int minimumLength)
        {
            EnsureLength(minimumLength);
        }
    }
}
