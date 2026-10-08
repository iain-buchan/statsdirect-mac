// A conservative heading screen, not a detector of all identifying data. No cell values
// are inspected or exported by this function. Explicit learner confirmation is still required.
export function identifierHeading(value) {
  const text=String(value??'').replace(/([a-z])([A-Z])/g,'$1 $2').normalize('NFKC').toLowerCase().replace(/[^a-z0-9]+/g,' ').trim();
  const compact=text.replaceAll(' ','');
  if(['dateofbirth','nhsnumber','nhsno','patientid','patientidentifier','hospitalnumber','hospitalno','medicalrecordnumber','medicalrecordno','phonenumber','emailaddress','firstname','lastname','patientname','fullname','homeaddress','clinicalnotes','freetextnotes'].includes(compact))return true;
  return /\b(name|names|forename|surname|dob|birthdate|postcode|postcodes|address|email|telephone|phone|mobile|nhs|mrn|ssn)\b/.test(text)
    || /\b(date of birth|birth date|post code|zip code|hospital (number|no|id)|patient (number|no|id|identifier)|medical record|national (number|id)|social security|free text|clinical notes|patient notes|case notes|contact details)\b/.test(text)
    || /^(notes?|comments?)$/.test(text);
}
export const identifierWarning='This column has a heading that may identify a person. It cannot be shared with the tutor. Use a de-identified teaching copy and review all its contents first; changing a heading alone does not remove identifiers.';
