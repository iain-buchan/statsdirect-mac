// Reject truncated streams and record-limit overflows before conversion. A renderer
// may otherwise return a plausible-looking partial statistical chart.
export function validateMetafile(bytes, format) {
  const v=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);
  const fail=()=>{throw new Error('Incomplete or oversized metafile');};
  if(format==='emf') {
    if(v.byteLength<88||v.getUint32(0,true)!==1||v.getUint32(40,true)!==0x464d4520)fail();
    const end=v.getUint32(48,true),expected=v.getUint32(52,true);
    if(end>v.byteLength||end<88||expected>200000)fail();
    let offset=0,count=0,eof=false,plusCount=0;
    while(offset<end) {
      if(offset+8>end||++count>200000)fail();
      const type=v.getUint32(offset,true),size=v.getUint32(offset+4,true);
      if(size<8||size%4||offset+size>end)fail();
      if(type===70&&size>=16&&v.getUint32(offset+12,true)===0x2b464d45) {
        const limit=offset+12+v.getUint32(offset+8,true);let record=offset+16;
        if(limit>offset+size)fail();
        while(record<limit){if(record+12>limit||++plusCount>200000)fail();const length=v.getUint32(record+4,true);if(length<12||record+length>limit)fail();record+=length;}
      }
      offset+=size;
      if(type===14){eof=offset===end;break;}
    }
    if(!eof||count!==expected)fail();
  } else {
    if(v.byteLength<18)fail();
    const base=v.getUint32(0,true)===0x9ac6cdd7?22:0;
    if(base+18>v.byteLength||v.getUint16(base+2,true)!==9)fail();
    const end=base+v.getUint32(base+6,true)*2;
    if(end>v.byteLength||end<base+24)fail();
    let offset=base+18,count=0,eof=false;
    while(offset<end){if(offset+6>end||++count>200000)fail();const size=v.getUint32(offset,true)*2,type=v.getUint16(offset+4,true);if(size<6||offset+size>end)fail();offset+=size;if(type===0){eof=offset===end;break;}}
    if(!eof)fail();
  }
}
