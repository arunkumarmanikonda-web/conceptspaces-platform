export type LocalVertex={x:number;y:number};
export type GeoVertex={lat:number;lng:number};
export type ParcelInput={vertices:Array<LocalVertex|GeoVertex>;unit?:"m"|"ft";coordinate_system?:string;source_type?:"survey"|"cadastral"|"dwg"|"dxf"|"point_cloud"|"lidar"|"manual";source_reference?:string};
export type ParcelResult={engine:string;engine_version:string;valid:boolean;validation_messages:string[];input_mode:"local"|"geographic";unit:"m";coordinate_system:string|null;vertices:LocalVertex[];area:number;perimeter:number;centroid:LocalVertex;orientation:"clockwise"|"counterclockwise";edges:Array<{index:number;length:number;bearing:number}>};

const ENGINE="conceptspaces-precision-geometry";const VERSION="1.0.0";const EARTH_RADIUS=6378137;
const finite=(n:unknown):n is number=>typeof n==="number"&&Number.isFinite(n);
const round=(n:number,p=6)=>Number(n.toFixed(p));
function isGeo(v:LocalVertex|GeoVertex):v is GeoVertex{return "lat" in v&&"lng" in v;}
function isLocal(v:LocalVertex|GeoVertex):v is LocalVertex{return "x" in v&&"y" in v;}

function toMetric(input:ParcelInput):{vertices:LocalVertex[];mode:"local"|"geographic";coordinateSystem:string|null}{
  if(input.vertices.length<3)throw new Error("at_least_three_vertices_required");
  const geo=input.vertices.every(isGeo),local=input.vertices.every(isLocal);if(!geo&&!local)throw new Error("mixed_or_invalid_vertex_mode");
  if(local){const factor=input.unit==="ft"?0.3048:1;return {vertices:(input.vertices as LocalVertex[]).map(v=>{if(!finite(v.x)||!finite(v.y))throw new Error("non_finite_coordinate");return{x:v.x*factor,y:v.y*factor};}),mode:"local",coordinateSystem:input.coordinate_system||null};}
  const vertices=input.vertices as GeoVertex[];for(const v of vertices){if(!finite(v.lat)||!finite(v.lng)||Math.abs(v.lat)>90||Math.abs(v.lng)>180)throw new Error("invalid_geographic_coordinate");}
  const lat0=vertices.reduce((s,v)=>s+v.lat,0)/vertices.length;const lng0=vertices.reduce((s,v)=>s+v.lng,0)/vertices.length;const phi0=lat0*Math.PI/180;
  return {vertices:vertices.map(v=>({x:EARTH_RADIUS*(v.lng-lng0)*Math.PI/180*Math.cos(phi0),y:EARTH_RADIUS*(v.lat-lat0)*Math.PI/180})),mode:"geographic",coordinateSystem:input.coordinate_system||"WGS84 / local tangent approximation"};
}
function cross(a:LocalVertex,b:LocalVertex,c:LocalVertex){return (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x);}
function onSegment(a:LocalVertex,b:LocalVertex,p:LocalVertex){return Math.min(a.x,b.x)-1e-9<=p.x&&p.x<=Math.max(a.x,b.x)+1e-9&&Math.min(a.y,b.y)-1e-9<=p.y&&p.y<=Math.max(a.y,b.y)+1e-9&&Math.abs(cross(a,b,p))<1e-9;}
function intersects(a:LocalVertex,b:LocalVertex,c:LocalVertex,d:LocalVertex){const c1=cross(a,b,c),c2=cross(a,b,d),c3=cross(c,d,a),c4=cross(c,d,b);if(((c1>0&&c2<0)||(c1<0&&c2>0))&&((c3>0&&c4<0)||(c3<0&&c4>0)))return true;return (Math.abs(c1)<1e-9&&onSegment(a,b,c))||(Math.abs(c2)<1e-9&&onSegment(a,b,d))||(Math.abs(c3)<1e-9&&onSegment(c,d,a))||(Math.abs(c4)<1e-9&&onSegment(c,d,b));}
function selfIntersects(v:LocalVertex[]){const n=v.length;for(let i=0;i<n;i++){const a=v[i],b=v[(i+1)%n];for(let j=i+1;j<n;j++){if(j===i||j===(i+1)%n||(i===0&&j===n-1))continue;const c=v[j],d=v[(j+1)%n];if(intersects(a,b,c,d))return true;}}return false;}
function distance(a:LocalVertex,b:LocalVertex){return Math.hypot(b.x-a.x,b.y-a.y);}
function bearing(a:LocalVertex,b:LocalVertex){const deg=Math.atan2(b.x-a.x,b.y-a.y)*180/Math.PI;return (deg+360)%360;}

export function computeParcel(input:ParcelInput):ParcelResult{
  if(!input||!Array.isArray(input.vertices))throw new Error("vertices_required");if(input.vertices.length>10000)throw new Error("too_many_vertices");const normalized=toMetric(input);const v=normalized.vertices;const messages:string[]=[];
  for(let i=0;i<v.length;i++){if(distance(v[i],v[(i+1)%v.length])<1e-6)messages.push(`zero_length_edge:${i}`);}if(selfIntersects(v))messages.push("self_intersection_detected");
  let twiceArea=0,cx=0,cy=0,perimeter=0;const edges=[] as ParcelResult["edges"];
  for(let i=0;i<v.length;i++){const a=v[i],b=v[(i+1)%v.length],term=a.x*b.y-b.x*a.y;twiceArea+=term;cx+=(a.x+b.x)*term;cy+=(a.y+b.y)*term;const len=distance(a,b);perimeter+=len;edges.push({index:i,length:round(len),bearing:round(bearing(a,b),4)});}
  const signedArea=twiceArea/2;const area=Math.abs(signedArea);if(area<1e-6)messages.push("degenerate_polygon_area");const centroid=Math.abs(twiceArea)>1e-12?{x:cx/(3*twiceArea),y:cy/(3*twiceArea)}:{x:v.reduce((s,p)=>s+p.x,0)/v.length,y:v.reduce((s,p)=>s+p.y,0)/v.length};
  const valid=messages.length===0;return {engine:ENGINE,engine_version:VERSION,valid,validation_messages:messages,input_mode:normalized.mode,unit:"m",coordinate_system:normalized.coordinateSystem,vertices:v.map(p=>({x:round(p.x),y:round(p.y)})),area:round(area,4),perimeter:round(perimeter,4),centroid:{x:round(centroid.x),y:round(centroid.y)},orientation:signedArea>=0?"counterclockwise":"clockwise",edges};
}

export function canonicalGeometryInput(input:ParcelInput){return JSON.stringify({vertices:input.vertices.map(v=>isGeo(v)?{lat:round(v.lat,9),lng:round(v.lng,9)}:{x:round(v.x,9),y:round(v.y,9)}),unit:input.unit||"m",coordinate_system:input.coordinate_system||null,source_type:input.source_type||"manual",source_reference:input.source_reference||null});}
