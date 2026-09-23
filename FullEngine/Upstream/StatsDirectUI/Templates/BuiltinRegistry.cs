using System;
using System.Collections.Generic;

namespace StatsDirect.Templates
{
    public class BuiltinRegistry
    {
        private readonly Dictionary<string, IBuiltin> builtins;

        private static BuiltinRegistry soleInstance;

        public static BuiltinRegistry SoleInstance => soleInstance ?? (soleInstance = new BuiltinRegistry());

        private BuiltinRegistry()
        {
            builtins = new Dictionary<string, IBuiltin>();
        }

        public IBuiltin Builtin(string name)
        {
            if (!builtins.TryGetValue(name, out IBuiltin builtin))
                throw new Exception("No built-in operation named '" + name + "' exists in the function registry.");
            return builtin;
        }

        public void AddAll(ICollection<IBuiltin> candidates)
        {
            foreach (IBuiltin candidate in candidates)
                builtins.Add(candidate.Name, candidate);
        }
    }
}
