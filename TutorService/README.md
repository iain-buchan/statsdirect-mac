# StatsDirect managed tutor service

The learner opens Learning and sends a question. The Mac automatically obtains an anonymous, limited session from this service and keeps that service token in Keychain. The service calls OpenAI using its administrator's credential. Learners need neither an OpenAI account nor an OpenAI key. The model, teaching instructions and request limits are controlled by the server.

**Current deployment status:** implemented and tested locally with a simulated provider. No public host, administrator credential, live OpenAI call or billing account has been configured. Shipping the app alone does not activate the shared tutor.

## Run and publish

This is an ASP.NET Core 10 service without third-party packages. It runs on a .NET 10 host on Linux, Windows or macOS. From the repository root:

```sh
dotnet build TutorService/TutorService.csproj
dotnet publish TutorService/TutorService.csproj -c Release -o .build/tutor-service
python3 Tests/test_tutor_service.py
```

The publish directory includes the executable assembly, server-owned tutor policy and trusted lesson definitions. Start it with `dotnet TutorService.dll` from that directory after configuring the host. Keep its writable session directory on persistent storage, outside any public/static web directory. Run **one service instance**: the pilot ledger uses atomic durable file replacement and an exclusive instance lock. Multiple replicas require a shared transactional quota store before deployment; do not give each replica its own allowance.

For a conventional host behind a local HTTPS reverse proxy, set these in the hosting platform's configuration and secret store:

| Setting | Purpose / initial value |
| --- | --- |
| `OPENAI_API_KEY` | Administrator's project key, stored only as a server secret. Never include it in an app, connection file, source control or deployment archive. |
| `TUTOR_MODEL` | Model available to that API project; defaults to `gpt-6-sol`. |
| `ASPNETCORE_ENVIRONMENT` | `Production` |
| `ASPNETCORE_URLS` | Private listener, e.g. `http://127.0.0.1:8787` |
| `TUTOR_TRUSTED_PROXIES` | Comma-separated **actual** ingress IP addresses; e.g. `127.0.0.1` for a local reverse proxy. No wildcard trust. |
| `TUTOR_DATA_DIRECTORY` | Private persistent directory writable only by the service account. |
| `TUTOR_DAILY_REQUESTS` | Global daily paid-request cap; default 100. |
| `TUTOR_SESSION_DAILY_REQUESTS` | Daily cap per session; default 20. |
| `TUTOR_IP_DAILY_REQUESTS` | Daily cap per source network address; default 30. University/shared networks may require a larger explicit allowance. |
| `TUTOR_DAILY_SESSIONS` | Global new-session cap; default 100 per day. |
| `TUTOR_IP_DAILY_SESSIONS` | New sessions per source address; default 5 per day. |
| `TUTOR_OUTPUT_TOKENS` | Maximum response tokens including reasoning; default 4,000, maximum 8,000. |

The ingress must terminate valid public HTTPS, overwrite forwarded headers with the actual scheme/client address, and keep the private HTTP listener inaccessible from the public internet. Production requests require HTTPS, including trusted forwarded HTTPS; unknown forwarded addresses are ignored. Configure the actual ingress topology using [Microsoft's proxy guidance](https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/proxy-load-balancer?view=aspnetcore-10.0). `GET /health` reports service protocol and whether a provider credential is configured; it does not verify that credential or make an OpenAI call.

Request caps are **not a monetary budget**: cost varies with the administrator's model and usage. Set and review the OpenAI project's spend limit before public activation, following [OpenAI production guidance](https://developers.openai.com/api/docs/guides/production-best-practices). The app's session controls do not protect other applications using the same project credential.

## Connect the Mac app

Once the service has a real HTTPS URL, embed that public address at build time:

```sh
STATSDIRECT_TUTOR_SERVICE_URL=https://YOUR-REAL-TUTOR-HOST ./build.sh
```

The publisher sets this once; learners see a Send button and no configuration requirement. For an existing pilot build, an administrator can supply a JSON connection file:

```json
{"schemaVersion":1,"serviceURL":"https://YOUR-REAL-TUTOR-HOST"}
```

In **Tutor connection → Import Connection…**, the user sees the destination before accepting it. The file contains only the public address. The Mac shares learning context with the chosen service only on Send; importing a connection makes no network request. Switching service addresses uses separate Keychain sessions. The Mac refuses redirects so a session credential or conversation is not forwarded to a new address.

## Protocol and pilot limits

- `POST /v1/sessions` creates a random 256-bit session, expiring after 30 days. No learner identity, provider credential or course code is required. Session creation is rate-limited and capped.
- `POST /v1/tutor` requires that session's bearer token and a versioned request: lesson ID, bounded reference context and user/assistant conversation messages. Unknown fields, provider model/tool/instruction overrides, invalid lessons and oversized input are rejected. The model has no tools. The server supplies the original tutoring policy and lesson independently.
- `DELETE /v1/session` revokes the presented session. Administrators can revoke a session by removing its hash from the ledger while the service is stopped.
- Quotas are reserved and flushed to disk **before** calling OpenAI. Failed/cancelled paid requests retain their reservation. Limits reset at UTC midnight. Reinstalling or creating another session cannot bypass the global/source-address caps; this is an anonymous pilot, not verified student authentication. Named courses, licences and university SSO can replace anonymous registration later.
- Only hashed session tokens, salted address hashes, expiry times and counters are persisted by the service. Conversations, course excerpts and replies pass through memory to OpenAI with `store:false`. Application logging excludes bodies/credentials; the hosting operator must also configure ingress and monitoring logs appropriately. OpenAI's own data controls still apply.
- This is not an authenticated examination or an accreditation service. Existing local first-answer records and external review remain separate.

## Verification

`Tests/test_tutor_service.py` starts the real service with a loopback synthetic provider. It checks automatic sessions, credentials confined to the provider request, fixed instructions/model, no prompt data in the ledger, schema limits, authentication, revocation, safe provider errors, daily quotas across restart, spoofed forwarded headers, inactive service and production HTTPS enforcement. `Tests/learning-client-test.swift` verifies native HTTPS/session boundaries, request limits and safe response parsing. No live OpenAI calls or emails are made by these tests.

For local tests only, `TUTOR_TEST_UPSTREAM` accepts a loopback HTTP address in `Development`; production refuses this override. A separate native test bundle can enable `StatsDirectTutorAllowLocalTesting` in its Info.plist. The normal build script removes that flag and accepts only HTTPS service addresses.
