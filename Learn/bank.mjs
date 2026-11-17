// The explicit pinned import validates these data files before offline builds.
// The publisher's bank.mjs is retained for provenance, never executed here.
import authoredQuestions from './AuthoredTutor/questions.json' with {type:'json'};
import authoredTracks from './AuthoredTutor/tracks.json' with {type:'json'};
import publication from './AuthoredTutor/manifest.json' with {type:'json'};
import provenance from '../Content/learning-manifest.json' with {type:'json'};
export const bankVersion = publication.bankVersion;
export const tracks = authoredTracks;
export const questions = authoredQuestions;
// Every practice attempt records where its questions came from, and every exported attempt repeats that record. It names
// the publication exactly (repository, commit, the manifests' hashes, the bank version, the counts and the outcome of the
// review gate). The publisher's lists of reviewed items and review notes stay in the manifest those hashes identify:
// copied into each attempt they were 35,000 characters that nothing reads.
const {reviewIssues,reviewedChangedItems,unreviewedChangedItems,...publicationSummary} = publication;
export const bankPublication = {repository:provenance.repository,commit:provenance.commit,
  source:provenance.source,producerManifestSHA256:provenance.producerManifestSHA256,
  publicationManifestSHA256:provenance.publicationManifestSHA256??null,
  reviewProofBinding:provenance.publicationTutorReviewProofBinding??'authoring-source-before-generated-sync-v1',
  publication:{...publicationSummary,reviewedChangedItemCount:reviewedChangedItems.length,unreviewedChangedItemCount:unreviewedChangedItems.length}};
