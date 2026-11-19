// Types that the C# compiler needs for tuples; .NET Framework 4.0 does not have them.
using System.Collections.Generic;

namespace System
{
    public struct ValueTuple<T1, T2>
    {
        public T1 Item1; public T2 Item2;
        public ValueTuple(T1 item1, T2 item2) { Item1 = item1; Item2 = item2; }
        public override string ToString() => "(" + Item1 + ", " + Item2 + ")";
    }

    public struct ValueTuple<T1, T2, T3>
    {
        public T1 Item1; public T2 Item2; public T3 Item3;
        public ValueTuple(T1 item1, T2 item2, T3 item3) { Item1 = item1; Item2 = item2; Item3 = item3; }
        public override string ToString() => "(" + Item1 + ", " + Item2 + ", " + Item3 + ")";
    }
}

namespace System.Runtime.CompilerServices
{
    [AttributeUsage(AttributeTargets.Field | AttributeTargets.Parameter | AttributeTargets.Property | AttributeTargets.ReturnValue | AttributeTargets.Class | AttributeTargets.Struct)]
    public sealed class TupleElementNamesAttribute : Attribute
    {
        public TupleElementNamesAttribute(string[] transformNames) { TransformNames = transformNames; }
        public IList<string> TransformNames { get; }
    }
}
