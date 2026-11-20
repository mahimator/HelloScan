import React, { useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { ScanLine, Upload, FileJson, Search, Plus, Trash2, ArrowUpRight, Layers3, Check, Contact, ChevronDown, ImagePlus, Sparkles } from "lucide-react";
import "./styles.css";

const emptyCard = () => ({
  id: crypto.randomUUID(),
  front: null,
  back: null,
  sideMode: "front",
  person: "",
  title: "",
  company: "",
  email: "",
  phone: "",
  website: "",
  address: "",
  notes: "",
  status: "review"
};

function HelloScan() {
  const [cards, setCards] = useState([]);
  const [selected, setSelected] = useState(null);
  const [search, setSearch] = useState("");
  const frontInput = useRef(null);
  const backInput = useRef(null);
  const [exportToast, setExportToast] = useState("");
  const [pendingAttachSide, setPendingAttachSide] = useState(null);

  const active = cards.find(c => c.id === selected) || null;
  const filtered = useMemo(() => cards.filter(c =>
    [c.person,c.company,c.email,c.phone].join(" ").toLowerCase().includes(search.toLowerCase())
  ), [cards, search]);

  const update = (id, patch) => setCards(prev => prev.map(c => c.id === id ? {...c,...patch} : c));
  const addCard = () => {
    const card = emptyCard();
    setCards(prev => [card, ...prev]);
    setSelected(card.id);
  };
  const attachImage = (file, side, cardId) => {
    if (!file || !file.type.startsWith("image/")) return;
    const image = { name: file.name, url: URL.createObjectURL(file) };
    const target = cards.find(c => c.id === cardId);
    if (target?.[side]?.url) URL.revokeObjectURL(target[side].url);
    update(cardId, { [side]: image, sideMode: side });
  };
  const importImages = (files, side) => {
    const incoming = Array.from(files || []).filter(f => f.type.startsWith("image/"));
    if (!incoming.length) return;
    if (pendingAttachSide && selected) {
      attachImage(incoming[0], pendingAttachSide, selected);
      incoming.splice(0, 1);
      setPendingAttachSide(null);
    }
    if (!incoming.length) return;
    const newCards = incoming.map(file => {
      const card = emptyCard();
      card[side] = { name: file.name, url: URL.createObjectURL(file) };
      card.sideMode = side;
      return card;
    });
    setCards(prev => [...newCards, ...prev]);
    setSelected(newCards[0].id);
  };
  const removeCard = id => {
    const target = cards.find(c => c.id === id);
    if (target?.front?.url) URL.revokeObjectURL(target.front.url);
    if (target?.back?.url) URL.revokeObjectURL(target.back.url);
    setCards(prev => prev.filter(c => c.id !== id));
    if (selected === id) setSelected(cards.find(c => c.id !== id)?.id || null);
  };
  const exportJson = () => {
    const payload = {
      schema: "helloscan.contact-batch.v1",
      exported_at: new Date().toISOString(),
      total: cards.length,
      contacts: cards.map(({id,front,back,sideMode,status,person,title,company,email,phone,website,address,notes}) => ({
        person: { name: person || null, designation: title || null },
        organization: { name: company || null, website: website || null },
        contact: { emails: email ? [email] : [], phones: phone ? [phone] : [] },
        location: { full_address: address || null },
        notes: notes || null,
        source: { sides: [front && "front", back && "back"].filter(Boolean), review_status: status }
      }))
    };
    const blob = new Blob([JSON.stringify(payload, null, 2)], {type:"application/json"});
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "helloscan-batch.json";
    a.click();
    URL.revokeObjectURL(url);
    setExportToast("JSON batch exported");
    setTimeout(() => setExportToast(""), 2600);
  };

  const fields = [
    ["person","Full name"],["title","Designation"],["company","Company"],
    ["email","Email"],["phone","Phone"],["website","Website"],["address","Address"],["notes","Notes"]
  ];

  return <div className="shell">
    <header className="topbar">
      <div className="brand"><div className="brand-icon"><ScanLine size={19}/></div><span>Hello<span className="brand-accent">Scan</span></span>
      <div className="top-meta"><span className="privacy-dot"/> Local workspace <span className="meta-sep"/> <span>v0.1 prototype</span></div>
    </header>

    <main>
      <section className="hero">
        <div>
          <div className="eyebrow"><Sparkles size={14}/> CONTACT CAPTURE WORKSPACE</div>
          <h1>From card to<br/><span>CRM-ready data.</span></h1>
          <p>Capture business cards, review the details, export a clean batch. No permanent contact database.</p>
        </div>
        <div className="hero-stat"><strong>{cards.length.toString().padStart(2,"0")}</strong><span>cards in this batch</span></div>
      </section>

      <section className="actions">
        <button className="primary" onClick={() => frontInput.current?.click()}><Upload size={17}/> Import front images</button>
        <button className="secondary" onClick={() => backInput.current?.click()}><ImagePlus size={17}/> Import back images</button>
        <button className="secondary" onClick={addCard}><Plus size={17}/> Add manually</button>
        <button className="export" disabled={!cards.length} onClick={exportJson}><FileJson size={17}/> Export JSON <ArrowUpRight size={15}/></button>
        <input ref={frontInput} type="file" accept="image/*" multiple hidden onChange={e => importImages(e.target.files,"front")}/>
        <input ref={backInput} type="file" accept="image/*" multiple hidden onChange={e => importImages(e.target.files,"back")}/>
      </section>

      <section className="workspace">
        <aside className="card-list">
          <div className="list-head"><div><span className="section-label">CURRENT BATCH</span><h2>Scanned cards <span className="count">{cards.length}</span></h2></div></div>
          <div className="search"><Search size={16}/><input placeholder="Search batch…" value={search} onChange={e=>setSearch(e.target.value)}/></div>
          {filtered.length ? <div className="cards">
            {filtered.map(card=><button key={card.id} className={"card-row "+(selected===card.id?"selected":"")} onClick={()=>setSelected(card.id)}>
              <div className="avatar">{(card.person||card.company||"??").trim().slice(0,2).toUpperCase()}</div>
              <div className="card-row-copy"><strong>{card.person||"Untitled contact"}</strong><span>{card.company||"Company not identified"}</span><small>{card.front&&card.back?"Front + back":card.front?"Front side":card.back?"Back side":"Manual entry"}</small></div>
              <ChevronDown size={15} className="row-chevron"/>
            </button>)}
          </div> : <div className="empty-list"><Layers3 size={24}/><p>Your batch is empty.</p><span>Import cards to get started.</span></div>}
          <div className="list-footer"><span><span className="privacy-dot"/> Session batch</span><span>Not synced</span></div>
        </aside>

        <section className="editor">
          {active ? <>
            <div className="editor-head"><div><span className="section-label">CARD REVIEW</span><h2>Contact details</h2></div><button className="icon-button danger" title="Remove card" onClick={()=>removeCard(active.id)}><Trash2 size={17}/></button></div>
            <div className="image-pair">
              <div className="side-preview"><div className="side-head"><span>FRONT</span>{active.front?.name&&<span className="file-name">{active.front.name}</span>}</div>{active.front?<img src={active.front.url} alt="Card front"/>:<button className="image-placeholder" onClick={()=>{setPendingAttachSide("front");frontInput.current?.click();}}><ImagePlus size={21}/><span>Add front image</span></button>}</div>
              <div className="side-preview"><div className="side-head"><span>BACK</span>{active.back?.name&&<span className="file-name">{active.back.name}</span>}</div>{active.back?<img src={active.back.url} alt="Card back"/>:<button className="image-placeholder" onClick={()=>{setPendingAttachSide("back");backInput.current?.click();}}><ImagePlus size={21}/><span>Add back image</span></button>}</div>
            </div>
            <div className="fields">
              {fields.map(([key,label])=><label className={"field "+(key==="notes"?"wide":"")} key={key}><span>{label}</span>{key==="notes"?<textarea rows={2} value={active[key]} onChange={e=>update(active.id,{[key]:e.target.value})} placeholder="Additional context…"/>:<input value={active[key]} onChange={e=>update(active.id,{[key]:e.target.value})} placeholder={label}/>}</label>)}
            </div>
            <div className="editor-bottom"><span><Check size={14}/> Changes are staged locally</span><button onClick={()=>update(active.id,{status:"reviewed"})}>Mark reviewed <Check size={15}/></button></div>
          </> : <div className="editor-empty"><Contact size={35}/><h2>Ready when you are.</h2><p>Import a card or add a contact manually to begin reviewing your batch.</p><button className="primary" onClick={addCard}><Plus size={16}/> Add first contact</button></div>}
        </section>
      </section>
      <footer><span>HelloScan <span className="brand-accent">/</span> Temporary capture, intentional export.</span><span>Privacy-first by design</span></footer>
    </main>
    {exportToast&&<div className="toast"><Check size={16}/>{exportToast}</div>}
  </div>;
}

createRoot(document.getElementById("root")).render(<HelloScan />);
