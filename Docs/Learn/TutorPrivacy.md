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

The native app and tutor transport check this policy before starting the connection,
signing in, sending a question or returning host-tool data. A detected policy change stops
an existing tutor connection. Connection and sharing controls become unavailable. Bundled
lessons, question bank, help, local analysis, R examples and learning-record exports remain
available. This setting does not sign the learner out of other applications.

## Verification

`Tests/tutor-policy-driver.swift` uses a local mock server to check disabled startup and
in-flight cancellation. `Tests/run_beta_feedback.py` checks the native confirmation, saved
record, refusal before consent, failed-save/changed-data handling, single-document scope,
and offline UI with the policy enabled. No live AI request is needed by these tests.
