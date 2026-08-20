import { AppSidebar } from "@/components/AppSidebar";

export default function AppLayout({children}:{children:React.ReactNode}){
  return <div className="app-layout"><AppSidebar/><main className="main">{children}</main></div>;
}
