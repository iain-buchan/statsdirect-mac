# Independent selected forest data, supplied in the order of the help workbook.
emit <- function(x) cat(formatC(as.double(x),digits=8,format="f"),"\n")
effect <- c(0.719714,0.68076,0.80287,0.800739,0.798143,1.132736,0.894969,0.896824)
limits <- cbind(c(0.47831,0.446423,0.599864,0.46972,0.545041,0.930385,0.828783,0.839992),c(1.077371,1.030758,1.072965,1.358784,1.177753,1.37967,0.966411,0.957475))
emit(c(length(effect),effect,apply(limits,1,min),apply(limits,1,max),c(1239,1529,1682,626,1216,4524,17187,28003),c(0,0,0,0,0,0,0,-1),rev(seq_along(effect))))
