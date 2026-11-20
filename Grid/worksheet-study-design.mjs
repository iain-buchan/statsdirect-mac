// Reviewed against the bundled Help topics for paired_t, wilcoxon_signed_ranks,
// chi_square_tests/mcnemar, proportions/paired and exact_tests_on_counts/sign.
// Both McNemar operation IDs use the same documented matched-pairs method.
export const pairedStudyMethods = {
  TPaired: {
    outcome: 'Continuous paired measurements',
    purpose: 'Tests the mean difference within pairs, with optional limits of agreement.',
    terms: ['paired continuous', 'matched measurements', 'before and after', 'within-pair difference'],
  },
  Wilcoxon: {
    outcome: 'Paired measurements with symmetric differences',
    purpose: 'Tests whether the centre of symmetric paired differences is zero.',
    terms: ['paired nonparametric', 'paired ranks', 'matched measurements', 'before and after'],
  },
  ExactMcNamar: {
    outcome: 'Binary outcomes in matched pairs',
    purpose: 'Tests whether the discordant counts in matched binary pairs are balanced.',
    terms: ['paired binary', 'paired categorical', 'matched pairs', 'discordant pairs', 'Liddell'],
  },
  ExactMcNamarChi: {
    outcome: 'Binary outcomes in matched pairs',
    purpose: 'Tests whether the discordant counts in matched binary pairs are balanced.',
    terms: ['paired binary', 'paired categorical', 'matched pairs', 'discordant pairs', 'Liddell'],
  },
  PropPairs: {
    outcome: 'Two proportions measured in the same pairs',
    purpose: 'Estimates and tests the difference between paired binary proportions.',
    terms: ['paired binary', 'matched proportions', 'paired categorical', 'before and after'],
  },
  ExactSign: {
    outcome: 'Direction of change within pairs',
    purpose: 'Tests whether increases and decreases are equally likely, omitting unchanged pairs.',
    terms: ['paired sign', 'direction of change', 'positive and negative differences', 'before and after'],
  },
};
