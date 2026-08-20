import { AppSidebar } from "@/components/AppSidebar";
import { requireWorkspaceUser } from "@/lib/auth";

export default async function AppLayout({children}:{children:React.ReactNode}){
  await requireWorkspaceUser();
  return <div className="app-layout"><AppSidebar/><main className="main">{children}</main></div>;
}
