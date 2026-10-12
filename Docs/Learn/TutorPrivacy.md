# Tutor sharing and institutional policy

Learning starts in **Lessons only** whenever its window opens, including after upgrading
an existing installation. Old sharing preferences are not reused. The learner can select
one document or **All open documents** in the context strip at the bottom.

For each question using document context, a native confirmation lists the documents.
**Share for This Question** stays disabled until the learner confirms they have checked
for person identifiers. **Use Lessons Only** sends the question without new document
context; **Cancel** sends nothing. Before any document metadata is sent, StatsDirect
saves the confirmation, timestamp, question ID, document list and worksheet revisions in
the learning record. Confirmations are included in JSON, text, HTML, PDF and Word exports.
If confirmation cannot be saved, document sharing does not proceed.

A confirmed question can read only those documents. Newly opened documents are excluded;
a changed worksheet requires a new question and confirmation. Selecting a single document
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

Each script has a separate conversation. Document sharing starts off. The user can
choose the current script and R output, one named workbook, both, or neither. Sharing
documents requires a no-person-identifiers confirmation for each question. The reminder
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
available. The policy also disables the script AI dock's connection and Send controls.
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
