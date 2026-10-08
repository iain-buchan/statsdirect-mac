import test from 'node:test';
import assert from 'node:assert/strict';
import {identifierHeading} from './tutor-privacy.mjs';
test('identifier heading screen covers common spellings without blocking ordinary measurements',()=>{
 for(const h of ['Full Name','surname','Forename','DOB','date of birth','birth_date','BirthDate','Postcode','post-code','Zip code','NHS number','NHSNumber','PATIENTID','Hospital number','PatientID','Medical record no','MRN','Email','Phone','Contact details','Clinical notes','Notes','Comments','FREE_TEXT'])assert.equal(identifierHeading(h),true,h);
 for(const h of ['Before','After','age','sex','Treatment','Subject code','Block','Group','PEFR','Diagnosis count','Year','BMI','Unnamed measurement'])assert.equal(identifierHeading(h),false,h);
});
