namespace StatsDirect.Expressions
{
    public static class TypePromoter
    {
        public static bool CanBePromotedFromTo(DataType from, DataType to)
        {
            // Common case: Identical
            if (from == to)
                return true;
            // Integers can be promoted to doubles
            if (from == DataType.Integer && to == DataType.Double)
                return true;
            // Everything else is incompatible.  In particular, we don't automatically promote to string, as otherwise we get dangerous things like boolean + double returning a string.
            return false;
        }
    }
}
