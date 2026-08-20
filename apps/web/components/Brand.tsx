export function Brand({light=false}:{light?:boolean}) {
  return <div className={`brand-lockup ${light ? "brand-lockup-light" : ""}`} aria-label="Concept Spaces — Intelligence, Given Form.">
    <span className="brand-mark" aria-hidden="true"><span>C</span><span>S</span></span>
    <span className="brand-wording"><strong>CONCEPT SPACES</strong><small>INTELLIGENCE, GIVEN FORM.</small></span>
  </div>;
}
