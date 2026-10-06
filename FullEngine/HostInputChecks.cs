using System;
using StatsDirect.Templates;

// Validate the Mac form before calling unchanged Windows random-number routines.
internal static class HostInputChecks {
 internal static void Validate(string operation, string name, ParameterBag filled, ParameterBag context) {
  if (!operation.StartsWith("Rnd") || !filled.ContainsKey(name)) return;
  if (name == "seed" || name == "numberType") return;
  double x = filled[name].AsDouble;
  bool positive = (operation is "RndBeta" or "RndGamma" or "RndWeibull") && (name is "a" or "b")
   || (operation is "RndT" or "RndChiSquare") && name == "df"
   || operation == "RndF" && (name is "dfn" or "dfd")
   || operation == "RndCauchy" && name == "s"
   || operation == "RndLogit" && name == "sigma"
   || operation == "RndExponential" && name == "xm"
   || operation == "RndNegativeBinomial" && name == "n";
  if (positive && x <= 0) throw new ArgumentException("This parameter must be greater than zero.");
  if ((operation == "RndPoisson" && name == "xm" || (operation is "RndNormal" or "RndLogNormal") && name == "sd" || operation == "RndBinomial" && name == "nn") && x < 0)
   throw new ArgumentException("This parameter must be zero or greater.");
  if (name == "p" && (x > 1 || x < 0 || (operation is "RndGeometric" or "RndNegativeBinomial") && x == 0))
   throw new ArgumentException(operation == "RndBinomial" ? "Probability must be between 0 and 1." : "Probability must be greater than 0 and no greater than 1.");
  if (operation == "RndUniformAB" && name == "b" && x < context["a"].AsDouble)
   throw new ArgumentException("The upper limit must be at least the lower limit.");
 }
}
