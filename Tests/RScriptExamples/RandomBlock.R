# Independent reference for selected fixed blocks: 20 subjects, 2 treatments, b=4.
n <- 20; t <- 2; b <- 4; seed <- 10
set.seed(seed)
allocation <- unlist(lapply(seq_len(n / b), function(i) sample(rep(LETTERS[seq_len(t)], b / t))))
cat("Random allocation in blocks\nRandomized with seed:", seed, "\nSubjects:", n,
    "\nBlock size:", b, "\nTreatments:", t, "\n")
print(data.frame(Subject=seq_len(n),Treatment=allocation),row.names=FALSE)
cat("Block sizes drawn:",rep(b,n/b),"\n")
print(table(allocation))
