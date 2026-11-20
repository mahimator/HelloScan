#!/usr/bin/env python3
"""Create fake visiting-card image pairs and JSON labels for HelloScan Lab.

Only fabricated identities and reserved example domains are used.
"""
from __future__ import annotations
import argparse, json, random
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

NAMES = ["Aarav Mehta", "Mira Shah", "Kabir Patel", "Anaya Rao", "Rohan Iyer", "Zoya Khan", "Dev Malhotra", "Nisha Desai"]
ROLES = ["Product Designer", "Operations Manager", "Creative Director", "Software Engineer", "Sales Lead", "Founder"]
COMPANIES = ["Northstar Studio", "Copperleaf Labs", "Pixel Orchard", "Blue Kite Systems", "Juniper Works", "Orbit Field"]
CITIES = ["Vadodara, Gujarat, India", "Kampala, Uganda", "Mumbai, Maharashtra, India", "Nairobi, Kenya", "Pune, Maharashtra, India"]
PALETTES = [("#f5f0e8", "#17232d"), ("#101820", "#f5f5f5"), ("#e7f3ef", "#183b36"), ("#f3e3d3", "#4a2515"), ("#eee9fb", "#30234f")]

def font(size):
    candidates = ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf"]
    for p in candidates:
        if Path(p).exists():
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()

def card(seed, out_dir):
    rng = random.Random(seed)
    name, role, company = rng.choice(NAMES), rng.choice(ROLES), rng.choice(COMPANIES)
    email = name.lower().replace(" ", ".") + "@example.com"
    phone = f"+91 90000 {rng.randint(10000,99999)}"
    website = f"https://{company.lower().replace(' ','')}.example"
    address = rng.choice(CITIES)
    bg, fg = rng.choice(PALETTES)
    front = Image.new("RGB", (1050, 600), bg)
    d = ImageDraw.Draw(front)
    d.rounded_rectangle((28,28,1022,572), radius=30, outline=fg, width=3)
    d.text((80,90), name, fill=fg, font=font(62))
    d.text((82,180), role, fill=fg, font=font(34))
    d.text((82,270), company, fill=fg, font=font(45))
    d.text((82,390), website, fill=fg, font=font(28))
    back = Image.new("RGB", (1050, 600), bg)
    b = ImageDraw.Draw(back)
    b.rounded_rectangle((28,28,1022,572), radius=30, outline=fg, width=3)
    b.text((80,80), "CONTACT", fill=fg, font=font(38))
    b.text((80,170), email, fill=fg, font=font(30))
    b.text((80,250), phone, fill=fg, font=font(30))
    b.text((80,340), address, fill=fg, font=font(27))
    out_dir.mkdir(parents=True, exist_ok=True)
    sid = f"synthetic-{seed:06d}"
    front_path, back_path = out_dir / f"{sid}-front.png", out_dir / f"{sid}-back.png"
    front.save(front_path); back.save(back_path)
    target = {"person":{"name":name,"designation":role},
              "organization":{"name":company,"website":website},
              "contact":{"emails":[email],"phones":[phone]},
              "location":{"full_address":address},"notes":None}
    return {"sample_id":sid,"images":{"front":front_path.name,"back":back_path.name},"target":target}

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--out", default="data/synthetic")
    ap.add_argument("--count", type=int, default=100)
    ap.add_argument("--seed", type=int, default=42)
    args=ap.parse_args()
    root=Path(args.out); imgs=root/"images"; samples=[]
    for i in range(args.count):
        sample=card(args.seed+i, imgs)
        sample["images"]["front"]="images/"+sample["images"]["front"]
        sample["images"]["back"]="images/"+sample["images"]["back"]
        samples.append(sample)
    (root/"labels.jsonl").write_text("\n".join(json.dumps(s,ensure_ascii=False) for s in samples)+"\n",encoding="utf-8")
    print(f"Generated {len(samples)} samples at {root.resolve()}")
if __name__=="__main__":
    main()
