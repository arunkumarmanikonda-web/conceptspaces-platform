export function Brand({light=false}:{light?:boolean}) {
  return <div className={`brand-lockup ${light ? "brand-lockup-light" : ""}`} aria-label="Concept Spaces — Intelligence, Given Form.">
    <img src="/brand/concept-spaces-horizontal.svg" alt="Concept Spaces — Intelligence, Given Form." className="brand-image" />
  </div>;
}
