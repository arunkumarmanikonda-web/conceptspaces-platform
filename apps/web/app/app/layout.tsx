import {AppSidebar} from "@/components/AppSidebar";
import AccessibilityRuntime from "@/components/AccessibilityRuntime";
import {requireWorkspaceUser} from "@/lib/auth";

export default async function AppLayout({children}:{children:React.ReactNode}){
 await requireWorkspaceUser();
 return <div className="app-layout"><a className="skip-link" href="#main-content">Skip to main content</a><AccessibilityRuntime/><AppSidebar/><main className="main" id="main-content" tabIndex={-1}>{children}</main></div>;
}
