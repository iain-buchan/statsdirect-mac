// The explicit pinned import validates these data files before offline builds.
// The publisher's bank.mjs is retained for provenance, never executed here.
import authoredQuestions from './AuthoredTutor/questions.json' with {type:'json'};
import authoredTracks from './AuthoredTutor/tracks.json' with {type:'json'};
import publication from './AuthoredTutor/manifest.json' with {type:'json'};
import provenance from '../Content/learning-manifest.json' with {type:'json'};
export const bankVersion = publication.bankVersion;
export const tracks = authoredTracks;
export const questions = authoredQuestions;
export const bankPublication = {repository:provenance.repository,commit:provenance.commit,
  source:provenance.source,producerManifestSHA256:provenance.producerManifestSHA256,
  publicationManifestSHA256:provenance.publicationManifestSHA256??null,
  reviewProofBinding:provenance.publicationTutorReviewProofBinding??'authoring-source-before-generated-sync-v1',publication};
