# Tutor sharing and institutional policy

Learning starts in **Lessons only** whenever its window opens, including after upgrading
an existing installation. Old sharing preferences are not reused. The learner can select
one document or **All open documents** in the context strip at the bottom.

On first use of document sharing, a native confirmation lists the context and explains
that acceptance lasts for this app session across Learning, Report and Script. It is
held only in memory: restarting the app or selecting a different data document clears
it. Switching between Report and Script, asking a follow-up, or starting a new
conversation does not require another acknowledgement. A different worksheet within
the same workbook does not count as a new document. The selected context and question
are still checked independently on every Send; acceptance does not share everything
that is open.

Learning records the sharing statement, timestamp, question ID, selected documents,
worksheet revisions and whether session acceptance was reused before granting that
question access. If this record cannot be saved, no document context is sent. Learning
can also send with **Use Lessons Only**, or cancel without sending.

A confirmed question can read only those documents. Newly opened documents are excluded;
a changed worksheet invalidates the current question's snapshot and requires a new question, retaining acceptance for the same data document. Selecting a single document
does not give the tutor access to other open documents. Heading checks withhold likely
identifier headings and refuse reads of those columns, including requests by column index.
Names, dates of birth, postcodes, NHS/hospital numbers, contact details and identifying
free text must be removed from a teaching copy before sharing. This conservative heading
screen cannot detect all identifiers or anonymise data; renaming a column is insufficient.

Questions, recent conversation, learning options and course excerpts still go to OpenAI
when sending in Lessons only mode. Previously shared content may remain in that conversation.
Do not put person identifiers in any of these materials. These local controls do not establish
an institution's contractual, account, retention or residency arrangements with its AI provider.

## R script assistance

The script toolbar's **AI assistance** icon opens a right-hand conversation dock using
the same **Use my ChatGPT** account connection. ChatGPT is currently the supported
provider; this feature does not add Claude, Gemini or another sign-in mechanism.

Each script has a separate conversation. Document sharing starts off on app launch;
the chosen sharing options and acceptance are reused across the app session. The user can
choose the current script and R output, one named workbook, both, or neither. Sharing
documents requires a no-person-identifiers confirmation for the app session. Selecting
a different data document requires confirmation again. The reminder
covers script comments, output and identifying free text as well as workbook cells.
Opening the dock checks the account connection but sends no document context or question.

Approved script/output are fixed excerpts (up to 12,000/8,000 characters, with explicit
truncation); approved workbook reads use the existing identifier-heading protections,
exact missing-cell positions and 4,000-cell/32-column limit. Workbook edits invalidate
that question's document access. Other documents, including those opened afterwards,
are excluded. The assistant can read approved context and bundled method help, but has
no tools to run R, change documents, execute analyses or read arbitrary files. Suggested
code is for the user to review and run.

Question-only mode still sends the question and recent conversation. Earlier shared
content may remain in replies; **New conversation** removes the earlier history from
subsequent requests. Each sent question is annotated locally with its sharing choice.
Unlike the Learning portfolio, script conversations are held in memory only and are
discarded when their script closes or StatsDirect quits. They are not saved in the R
script or included in the learning record. No chat logging or provider key is added.

## Conversation display

Report and Script AI replies are rendered in a local, nonpersistent WKWebView. Headings,
tables, lists, mathematical notation and syntax-highlighted R code use the existing
Learning rich-text renderer. Raw HTML is escaped and sanitized; remote resources,
frames, media and automatic popups are blocked. External links open only on a user
click. Native handlers validate the conversation/message before opening R code or
copying a code block. R suggestions remain unexecuted until the user chooses Run.

Streaming preserves selected text and the reading position. WebKit renderer failure
recreates the isolated view from native conversation state, including received partial
text, without resending the question. Question drafts remain native as well.

## Report interpretation assistance

The report toolbar's **AI assistance** icon and **AI Assistance…** right-click item
open the same right-hand dock, with a separate conversation for each report. The
existing ChatGPT connection is reused. The assistant is instructed to explain the
results, uncertainty, assumptions and methods, using the focused result and bundled
method help. It does not change the report or run analyses.

Report sharing uses the same session acceptance and context choices as Script and Learning. A shared
report is a fixed snapshot of its displayed text (up to 18,000 characters), the focused
result (up to 6,000 characters), titles/method IDs for up to 40 results, and chart labels
(up to 2,000 characters). Truncation is explicit. Chart images are not sent; the assistant
must not infer visual patterns from labels. Hidden run records and original worksheet
values are excluded unless visible in the report. A workbook must be approved separately.
Edits during capture require a fresh question; subsequent edits cannot expand an
already captured snapshot. Other reports and scripts are inaccessible.

Report conversations have the same in-memory lifetime, sharing annotations, question-only
mode and **New conversation** behaviour as script conversations. Switching between reports
and scripts restores each document's own draft and conversation. Help and AI occupy the
same dock. **Open in R** on suggested code opens it for review without execution.

## Disable the online tutor

Administrators can deploy the Boolean managed preference **DisableOnlineTutor = true**
for domain **com.statsdirect.viewer.prototype**. Use a **forced** macOS managed preference
through your device-management system to prevent a learner overriding it. Restart StatsDirect
after deploying or removing the policy. A local setting for testing/unmanaged installations is:

```sh
defaults write com.statsdirect.viewer.prototype DisableOnlineTutor -bool true
```

To reverse that local setting, use `-bool false` and restart. An ordinary defaults setting
is user-editable; it is not an enforced institutional policy.

The native app, first-use installer and tutor transport check this policy before downloading or starting the connection,
signing in, sending a question or returning host-tool data. A detected policy change stops
an existing tutor connection. Connection and sharing controls become unavailable. Bundled
lessons, question bank, help, local analysis, R examples and learning-record exports remain
available. The policy also disables the report and script AI docks' connection and Send controls.
This setting does not sign the learner out of other applications.

## Verification

`Tests/tutor-policy-driver.swift` uses a local mock server to check disabled startup and
in-flight cancellation. `Tests/run_beta_feedback.py` checks the native confirmation, saved
record, refusal before consent, failed-save/changed-data handling, single-document scope,
and offline UI with the policy enabled. No live AI request is needed by these tests.

`Scripts/test-script-ai.sh` runs the native dock against a local protocol fixture with
fictional data. It checks question-only requests, consent enforcement, scoped workbook
reads, identifier rejection, frozen script excerpts, changed-workbook rejection,
conversation isolation, cancellation, keyboard handling and Help/AI dock switching.

`Scripts/test-report-ai.sh` checks the native report toolbar and context-menu entry,
right dock, real paired t/agreement engine results, report-specific provider instructions,
method help, explicit sharing, snapshot boundaries, absence of hidden records and unshared
documents, isolated conversations, cancellation, R suggestions, large/empty reports and
policy, app-wide session acceptance, workbook-change resets and renderer recovery. It uses a local protocol fixture, not a live AI account.
