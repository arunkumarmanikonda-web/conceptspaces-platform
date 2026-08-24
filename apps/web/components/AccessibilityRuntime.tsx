"use client";
import {useEffect} from "react";

export default function AccessibilityRuntime(){
 useEffect(()=>{
  const controls=Array.from(document.querySelectorAll<HTMLElement>(".field input,.field select,.field textarea"));
  controls.forEach((control,index)=>{
   const field=control.closest(".field");const label=field?.querySelector<HTMLLabelElement>("label");
   if(label){if(!control.id)control.id=`cs-field-${index}-${Math.random().toString(36).slice(2,7)}`;if(!label.htmlFor)label.htmlFor=control.id;}
   if(control.getAttribute("aria-invalid")==="true"&&!control.getAttribute("aria-describedby")){const message=field?.querySelector<HTMLElement>(".field-error");if(message){if(!message.id)message.id=`${control.id}-error`;control.setAttribute("aria-describedby",message.id);}}
  });
  document.querySelectorAll<HTMLTableCellElement>("table thead th").forEach(th=>{if(!th.scope)th.scope="col";});
  document.querySelectorAll<HTMLElement>("[data-live-message]").forEach(el=>{el.setAttribute("role","status");el.setAttribute("aria-live","polite");el.setAttribute("aria-atomic","true");});
 },[]);
 return null;
}
