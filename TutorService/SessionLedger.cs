using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

// A bounded, single-instance pilot store. Counts are reserved durably before a paid request.
// No prompts, course notes, replies, raw bearer tokens or raw IP addresses are stored here.
sealed class SessionLedger : IDisposable
{
    public sealed class Session
    {
        public DateTimeOffset ExpiresAt { get; set; }
        public string Day { get; set; } = "";
        public int Requests { get; set; }
    }
    public sealed class Ledger
    {
        public int SchemaVersion { get; set; } = 1;
        public string Salt { get; set; } = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
        public string Day { get; set; } = "";
        public int Requests { get; set; }
        public int Registrations { get; set; }
        public Dictionary<string, int> IPRequests { get; set; } = [];
        public Dictionary<string, int> IPRegistrations { get; set; } = [];
        public Dictionary<string, Session> Sessions { get; set; } = [];
    }
    readonly object gate = new();
    readonly string file;
    readonly FileStream instanceLock;
    readonly ServiceSettings settings;
    readonly HashSet<string> busy = [];
    readonly Dictionary<string, DateTimeOffset> recent = [];
    Ledger state;

    public SessionLedger(ServiceSettings settings)
    {
        this.settings = settings;
        Directory.CreateDirectory(settings.DataDirectory);
        if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(settings.DataDirectory, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        file = Path.Combine(settings.DataDirectory, "sessions.json");
        instanceLock = new FileStream(Path.Combine(settings.DataDirectory, "instance.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        state = File.Exists(file) ? JsonSerializer.Deserialize<Ledger>(File.ReadAllBytes(file)) ?? throw new InvalidDataException("Invalid session ledger") : new Ledger();
        if (state.SchemaVersion != 1 || state.Salt.Length != 64 || state.Sessions == null || state.IPRequests == null || state.IPRegistrations == null)
            throw new InvalidDataException("Invalid session ledger; restore it before restarting the service.");
        Save();
    }
    static string Hash(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
    string Peer(string ip) => Hash(state.Salt + ":" + ip);
    void RollDay(DateTimeOffset now)
    {
        var day = now.UtcDateTime.ToString("yyyy-MM-dd");
        if (state.Day == day) return;
        state.Day = day; state.Requests = 0; state.Registrations = 0;
        state.IPRequests.Clear(); state.IPRegistrations.Clear(); recent.Clear();
        foreach (var id in state.Sessions.Where(p => p.Value.ExpiresAt <= now).Select(p => p.Key).ToArray()) state.Sessions.Remove(id);
    }
    void Save()
    {
        var temp = file + ".new";
        using (var stream = new FileStream(temp, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(temp, UnixFileMode.UserRead | UnixFileMode.UserWrite);
            JsonSerializer.Serialize(stream, state); stream.Flush(true);
        }
        File.Move(temp, file, true);
    }
    public (string Token, DateTimeOffset ExpiresAt) Create(string ip)
    {
        lock (gate)
        {
            var now = DateTimeOffset.UtcNow; RollDay(now); var peer = Peer(ip);
            if (state.Registrations >= settings.RegistrationsPerDay || state.IPRegistrations.GetValueOrDefault(peer) >= settings.RegistrationsPerIP || state.Sessions.Count >= 1000)
                throw new TutorFailure(429, "session_limit", "New learning sessions are temporarily limited. Please try again tomorrow.");
            var token = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
            var expires = now.AddDays(30);
            state.Sessions.Add(Hash(token), new Session { ExpiresAt = expires });
            state.Registrations++; state.IPRegistrations[peer] = state.IPRegistrations.GetValueOrDefault(peer) + 1;
            Save(); return (token, expires);
        }
    }
    public string Reserve(string token, string ip)
    {
        lock (gate)
        {
            var now = DateTimeOffset.UtcNow; RollDay(now); var id = Hash(token); var peer = Peer(ip);
            if (!state.Sessions.TryGetValue(id, out var session) || session.ExpiresAt <= now)
                throw new TutorFailure(401, "session_expired", "Your learning connection has expired. Send again to reconnect.");
            if (session.Day != state.Day) { session.Day = state.Day; session.Requests = 0; }
            if (busy.Contains(id) || recent.TryGetValue(id, out var last) && now - last < TimeSpan.FromSeconds(2))
                throw new TutorFailure(429, "busy", "Please wait a moment before asking another question.");
            if (session.Requests >= settings.SessionRequestsPerDay || state.Requests >= settings.TotalRequestsPerDay || state.IPRequests.GetValueOrDefault(peer) >= settings.IPRequestsPerDay)
                throw new TutorFailure(429, "daily_limit", "Today's learning allowance has been reached. Please return tomorrow.");
            session.Requests++; state.Requests++; state.IPRequests[peer] = state.IPRequests.GetValueOrDefault(peer) + 1;
            Save(); busy.Add(id); recent[id] = now; return id;
        }
    }
    public void Release(string id) { lock (gate) busy.Remove(id); }
    public void Revoke(string token)
    {
        lock (gate) { state.Sessions.Remove(Hash(token)); Save(); }
    }
    public void Dispose() => instanceLock.Dispose();
}
