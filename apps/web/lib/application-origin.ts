import "server-only";
import { headers } from "next/headers";

export async function applicationOrigin(){
  const configured=process.env.NEXT_PUBLIC_APP_URL?.trim();
  if(configured){
    try{return new URL(configured).origin;}catch{/* Fall through to the request origin. */}
  }
  const requestOrigin=(await headers()).get("origin");
  if(requestOrigin){
    try{
      const parsed=new URL(requestOrigin);
      if(parsed.protocol==="https:"||parsed.hostname==="localhost") return parsed.origin;
    }catch{/* Use the canonical production origin below. */}
  }
  return "https://www.conceptspaces.live";
}
