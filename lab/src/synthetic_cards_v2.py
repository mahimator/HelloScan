#!/usr/bin/env python3
"""Synthetic visiting-card dataset v2 for HelloScan Lab.

Uses fabricated identities and reserved .example domains only. Layout families are
split across train/validation/test to reduce layout leakage.
"""
from __future__ import annotations
import argparse, json, random, math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance

W,H = 1200,700
NAMES=["Aarav Mehta","Mira Shah","Kabir Patel","Anaya Rao","Rohan Iyer","Zoya Khan","Dev Malhotra","Nisha Desai","Ishaan Rao","Tara Kapoor","Neel Joshi","Sana Khan","Arjun Menon","Kiara Das","Reyansh Shah","Aditi Nair"]
ROLES=["Product Designer","Operations Manager","Creative Director","Software Engineer","Sales Lead","Founder","Consultant","Architect","Marketing Manager","Data Analyst","Project Lead"]
COMPANIES=["Northstar Studio","Copperleaf Labs","Pixel Orchard","Blue Kite Systems","Juniper Works","Orbit Field","Brightline Media","Cedar Analytics","Lumen Craft","Riverstone Group"]
CITIES=["Vadodara, Gujarat, India","Kampala, Uganda","Mumbai, Maharashtra, India","Nairobi, Kenya","Pune, Maharashtra, India","Ahmedabad, Gujarat, India","Chennai, Tamil Nadu, India"]
PALETTES=[("#f5f0e8","#17232d","#d36a38"),("#101820","#f5f5f5","#5ad6a3"),("#e7f3ef","#183b36","#e09b45"),("#f3e3d3","#4a2515","#bd4c2f"),("#eee9fb","#30234f","#9d7bdd"),("#fff5c8","#26344a","#e06c75"),("#dce9f7","#102e4c","#f2b134")]
LAYOUTS=["classic","bold","split","compact","centered","minimal","dense","vertical"]
EMAIL_DOMAINS=["example.com","example.org","example.net"]
def get_font(sz,bold=False):
    candidates=("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
                "/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf")
    for p in candidates:
        if Path(p).exists(): return ImageFont.truetype(p,sz)
    return ImageFont.load_default()
def fit_text(draw,text,max_width,size,fill,fontbold=False):
    f=get_font(size,fontbold)
    while size>12 and draw.textbbox((0,0),text,font=f)[2]>max_width:
        size-=2; f=get_font(size,fontbold)
    draw.text((0,0),text,font=f,fill=fill)
    return f
def draw_lines(draw, lines, xy, fill, sizes, spacing=16, bold_first=False):
    x,y=xy
    for i,t in enumerate(lines):
        if t:
            f=get_font(sizes[min(i,len(sizes)-1)], bold_first and i==0)
            draw.text((x,y),t,fill=fill,font=f)
            y += f.getbbox(t)[3]+spacing
def render_side(seed,side,fields,layout,bg,fg,accent):
    rng=random.Random(seed+ (0 if side=="front" else 999))
    im=Image.new("RGB",(W,H),bg); d=ImageDraw.Draw(im)
    # Style-specific geometry
    if layout in ("classic","compact","dense"):
        d.rounded_rectangle((24,24,W-24,H-24),radius=24,outline=accent,width=5)
    if layout=="bold":
        d.rectangle((0,0,350,H),fill=accent)
    elif layout=="split":
        d.rectangle((0,0,W//3,H),fill=accent)
    elif layout=="vertical":
        d.rectangle((0,0,150,H),fill=accent)
    # light geometric decoration
    if layout in ("minimal","centered"):
        d.ellipse((W-250,-130,W+30,110),fill=accent)
    name=fields["person"]["name"] or ""
    role=fields["person"]["designation"] or ""
    org=fields["organization"]["name"] or ""
    website=fields["organization"]["website"] or ""
    emails=fields["contact"]["emails"]; phones=fields["contact"]["phones"]
    address=fields["location"]["full_address"] or ""
    if side=="front":
        if layout=="centered":
            for txt,sz,bold,yy in [(name,58,True,130),(role,32,False,225),(org,42,True,330),(website,25,False,460)]:
                f=get_font(sz,bold); d.text((W//2,yy),txt,fill=fg,font=f,anchor="mm")
        elif layout=="vertical":
            d.text((190,115),name,fill=fg,font=get_font(58,True))
            d.text((190,215),role,fill=fg,font=get_font(32))
            d.text((190,340),org,fill=fg,font=get_font(42,True))
            d.text((190,480),website,fill=fg,font=get_font(26))
        else:
            x=400 if layout=="split" else 85
            if layout=="bold": x=390
            if layout=="dense": x=65
            d.text((x,95),name,fill=fg,font=get_font(54 if layout!="dense" else 40,True))
            d.text((x,195),role,fill=fg,font=get_font(30 if layout!="dense" else 25))
            d.text((x,305),org,fill=fg,font=get_font(40 if layout!="dense" else 32,True))
            if website: d.text((x,450),website,fill=fg,font=get_font(25))
        # randomly place optional details on front too
        if rng.random()<0.45:
            x=70 if layout in ("centered","vertical") else 720
            d.text((x,570),phones[0] if phones else "",fill=fg,font=get_font(22))
    else:
        # back layouts intentionally differ from front placement
        title="CONTACT" if rng.random()<0.7 else org.upper()
        d.text((75,65),title,fill=accent if layout!="bold" else fg,font=get_font(34,True))
        items=[]
        if emails: items.extend(["EMAIL", " / ".join(emails)])
        if phones: items.extend(["PHONE", "  •  ".join(phones)])
        if address: items.extend(["ADDRESS",address])
        if website: items.extend(["WEB",website])
        x,y=75,155
        if layout=="centered": x=100
        for i in range(0,len(items),2):
            label=items[i]; value=items[i+1] if i+1<len(items) else ""
            d.text((x,y),label,fill=accent,font=get_font(22,True)); y+=38
            d.text((x,y),value,fill=fg,font=get_font(26)); y+=72
    # subtle small-print texture / decorative dots
    for _ in range(rng.randint(2,9)):
        px,py=rng.randint(20,W-20),rng.randint(20,H-20)
        if rng.random()<0.15: d.ellipse((px,py,px+6,py+6),fill=accent)
    return im
def distort(im,rng,augment):
    if not augment:return im
    if rng.random()<0.45: im=im.rotate(rng.uniform(-3.5,3.5),resample=Image.Resampling.BICUBIC,expand=False,fillcolor=(245,245,245))
    if rng.random()<0.55: im=ImageEnhance.Contrast(im).enhance(rng.uniform(.75,1.25))
    if rng.random()<0.55: im=ImageEnhance.Brightness(im).enhance(rng.uniform(.75,1.2))
    if rng.random()<0.4: im=im.filter(ImageFilter.GaussianBlur(rng.uniform(.2,1.5)))
    if rng.random()<0.35: im=im.resize((rng.choice([720,840,960]),rng.choice([420,490,560]))).resize((W,H))
    return im
def make_sample(seed,layout,outdir,augment):
    rng=random.Random(seed)
    name=rng.choice(NAMES); role=rng.choice(ROLES); org=rng.choice(COMPANIES)
    email=name.lower().replace(" ",".")+"@"+rng.choice(EMAIL_DOMAINS)
    phone=f"+{rng.choice([91,256,254,255])} {rng.randint(700,999)} {rng.randint(100,999)} {rng.randint(1000,9999)}"
    emails=[email] if rng.random()<.82 else []
    if rng.random()<.18: emails.append("info@"+org.lower().replace(" ","")+".example")
    phones=[phone]
    if rng.random()<.25: phones.append(f"+{rng.choice([91,256,254])} {rng.randint(700,999)} {rng.randint(100,999)} {rng.randint(1000,9999)}")
    website=f"https://{org.lower().replace(' ','')}.example" if rng.random()<.75 else None
    address=rng.choice(CITIES) if rng.random()<.68 else None
    # intentionally omit a subset of semantic fields
    name=name if rng.random()<.97 else None
    role=role if rng.random()<.75 else None
    org=org if rng.random()<.92 else None
    bg,fg,accent=rng.choice(PALETTES)
    target={"person":{"name":name,"designation":role},
      "organization":{"name":org,"website":website},
      "contact":{"emails":emails,"phones":phones},
      "location":{"full_address":address},"notes":None}
    sid=f"card-{seed:07d}"
    # Some card pairs distribute all info across sides; some have partial content on each.
    front=render_side(seed,"front",target,layout,bg,fg,accent)
    back=render_side(seed,"back",target,layout,bg,fg,accent)
    front=distort(front,rng,augment); back=distort(back,rng,augment)
    imgdir=outdir/"images"; imgdir.mkdir(parents=True,exist_ok=True)
    fp,bp=imgdir/f"{sid}-front.png",imgdir/f"{sid}-back.png"
    front.save(fp); back.save(bp)
    return {"sample_id":sid,"layout_family":layout,"images":{"front":"images/"+fp.name,"back":"images/"+bp.name},"target":target}
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out",default="data/synthetic-v2")
    ap.add_argument("--count",type=int,default=1000)
    ap.add_argument("--seed",type=int,default=42)
    ap.add_argument("--no-augment",action="store_true")
    args=ap.parse_args()
    root=Path(args.out); samples=[]
    # Group holdout by layout family. This avoids test samples sharing the exact template family.
    splitmap={"train":["classic","bold","split","compact"],"validation":["centered","minimal"],"test":["dense","vertical"]}
    counts={k:0 for k in splitmap}
    for i in range(args.count):
        layout=LAYOUTS[i%len(LAYOUTS)]
        seed=args.seed+i
        sample=make_sample(seed,layout,root,not args.no_augment)
        split=next(k for k,v in splitmap.items() if layout in v)
        sample["split"]=split
        samples.append(sample); counts[split]+=1
    (root/"labels.jsonl").write_text("\n".join(json.dumps(s,ensure_ascii=False) for s in samples)+"\n",encoding="utf-8")
    (root/"split_summary.json").write_text(json.dumps({"seed":args.seed,"total":len(samples),"counts":counts,"split_layout_families":splitmap},indent=2),encoding="utf-8")
    print(json.dumps({"generated":len(samples),"splits":counts,"path":str(root.resolve())},indent=2))
if __name__=="__main__": main()
