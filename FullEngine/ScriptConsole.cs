using System;
using System.IO;
using System.Text;
using System.Threading;

// Prompts release the engine lock. Route console output per execution context,
// so two scripts suspended at different prompts cannot capture one another.
internal static class ScriptConsole {
    static readonly AsyncLocal<TextWriter> current = new();
    static ScriptConsole() {
        Console.SetOut(new Router(Console.Out)); Console.SetError(new Router(Console.Error));
    }
    public static IDisposable Capture(TextWriter writer) {
        var previous = current.Value; current.Value = TextWriter.Synchronized(writer);
        return new Scope(() => current.Value = previous);
    }
    sealed class Scope(Action close) : IDisposable { public void Dispose() => close(); }
    sealed class Router(TextWriter fallback) : TextWriter {
        public override Encoding Encoding => fallback.Encoding;
        public override void Write(char value) => (current.Value ?? fallback).Write(value);
        public override void Write(string value) => (current.Value ?? fallback).Write(value);
        public override void Write(char[] buffer, int index, int count) => (current.Value ?? fallback).Write(buffer,index,count);
        public override void WriteLine(string value) => (current.Value ?? fallback).WriteLine(value);
        public override void Flush() => (current.Value ?? fallback).Flush();
    }
}
