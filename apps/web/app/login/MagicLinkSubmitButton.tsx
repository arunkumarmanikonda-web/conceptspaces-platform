"use client";

import {useFormStatus} from "react-dom";

export function MagicLinkSubmitButton(){
  const {pending}=useFormStatus();
  return <button
    className="btn ghost"
    type="submit"
    disabled={pending}
    aria-disabled={pending}
    style={{width:"100%",marginTop:14}}
  >{pending?"Sending secure link…":"Email me a secure link"}</button>;
}
