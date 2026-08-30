export const areaUnits=["sqyd","sqm","sqft","acre","hectare"] as const;
export const dimensionUnits=["ft","m","yd"] as const;

export type AreaUnit=(typeof areaUnits)[number];
export type DimensionUnit=(typeof dimensionUnits)[number];

const gstinPattern=/^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/;

export type PlotParcel={
  id:string;
  label:string;
  surveyNumber:string;
  area:string;
  areaUnit:AreaUnit;
  facing:string;
  front:string;
  rear:string;
  left:string;
  right:string;
  dimensionUnit:DimensionUnit;
  sharedBoundary:string;
};

const squareMetresPerUnit:Record<AreaUnit,number>={
  sqyd:0.83612736,
  sqm:1,
  sqft:0.09290304,
  acre:4046.8564224,
  hectare:10000
};

export function createParcel(ordinal:number):PlotParcel{
  return {id:`parcel-${ordinal}`,label:`Plot ${ordinal}`,surveyNumber:"",area:"",areaUnit:"sqyd",facing:"",front:"",rear:"",left:"",right:"",dimensionUnit:"ft",sharedBoundary:""};
}

export function calculateCombinedArea(parcels:PlotParcel[],unit:AreaUnit):number|null{
  if(!parcels.length) return null;
  let squareMetres=0;
  for(const parcel of parcels){
    const area=Number(parcel.area);
    if(!Number.isFinite(area)||area<=0) return null;
    squareMetres+=area*squareMetresPerUnit[parcel.areaUnit];
  }
  return squareMetres/squareMetresPerUnit[unit];
}

export function formatMeasurement(value:number):string{
  return new Intl.NumberFormat("en-IN",{maximumFractionDigits:2}).format(value);
}

export function normaliseGstin(value:unknown):string{
  return typeof value==="string"?value.toUpperCase().replace(/[\s-]+/g,""):"";
}

export function isValidGstin(value:unknown):boolean{
  return gstinPattern.test(normaliseGstin(value));
}

function cleanText(value:unknown,maxLength:number):string{
  return typeof value==="string"?value.trim().slice(0,maxLength):"";
}

export function normaliseParcels(value:unknown):PlotParcel[]{
  if(!Array.isArray(value)) return [];
  return value.slice(0,25).map((candidate,index)=>{
    const row=candidate&&typeof candidate==="object"?candidate as Record<string,unknown>:{};
    const areaUnit=areaUnits.includes(row.areaUnit as AreaUnit)?row.areaUnit as AreaUnit:"sqyd";
    const dimensionUnit=dimensionUnits.includes(row.dimensionUnit as DimensionUnit)?row.dimensionUnit as DimensionUnit:"ft";
    return {
      id:cleanText(row.id,80)||`parcel-${index+1}`,
      label:cleanText(row.label,120)||`Plot ${index+1}`,
      surveyNumber:cleanText(row.surveyNumber,160),
      area:cleanText(row.area,40),
      areaUnit,
      facing:cleanText(row.facing,120),
      front:cleanText(row.front,40),
      rear:cleanText(row.rear,40),
      left:cleanText(row.left,40),
      right:cleanText(row.right,40),
      dimensionUnit,
      sharedBoundary:cleanText(row.sharedBoundary,500)
    };
  });
}
