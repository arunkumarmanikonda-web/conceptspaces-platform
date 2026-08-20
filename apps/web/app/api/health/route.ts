export async function GET(){
  return Response.json({
    service:"conceptspaces-web",
    status:"ok",
    version:"0.1.0",
    timestamp:new Date().toISOString()
  });
}
