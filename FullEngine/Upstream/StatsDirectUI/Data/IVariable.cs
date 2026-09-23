using System.Xml.Serialization;

namespace StatsDirect.Data
{
    ///  <summary>
    ///  Represents a single variable/factor/column/field.
    ///  </summary>
    public interface IVariable
    {
        ///  <summary>
        ///  The title (name) of the variable
        ///  </summary>
        string Title { get; set; }

        ///  <summary>
        ///  Where the variable came from
        ///  </summary>
        IOrigin Origin { get; set; }

        [XmlIgnore]
        int Length { get; }

        ///  <summary>
        ///  Ensure the data array is allocated and at least MinimumLength items in length.  Any new elements will be filled with the platform default value.
        ///  </summary>
        ///  <param name="minimumLength">The minimum length of the array.  Note this is a length, not a bound.  The array will have items from 0 to MinimumLength - 1.</param>
        void EnsureLength(int minimumLength);

        ///  <summary>
        ///  Ensure the data has at most MaximumLength rows
        ///  </summary>
        ///  <param name="maximumLength"></param>
        void TruncateDataToLength(int maximumLength);

        ///  <summary>
        ///  A fast but destructive way of transferring victim's data to this variable.  Victim should not be used after this operation.
        ///  </summary>
        void StealDataFrom(IVariable victim);

        /// <summary>
        /// Polymorphism: return the ith element of this variable's data encapsulated as an object.
        /// </summary>
        object DataAsObject(int i);

        /// <summary>
        /// Polymorphism: set the ith element of this variable's data to value, or fail if can't convert.
        /// </summary>
        void DataAsObject(int i, object value);

        void Accept(IVariableVisitor visitor);

        void EnsureLengthAndPadWithMissing(int maxRows);
    }
}
