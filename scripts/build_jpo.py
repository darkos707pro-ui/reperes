"""Construit jpo.json (journées portes ouvertes) et orientation.json (CIO et services
d'orientation universitaires) pour les onglets « Portes ouvertes » et « Qui contacter ».

Sources (open data) :
- Onisep, Idéo-Structures d'enseignement supérieur et secondaire (licence ODbL),
  colonne « journées portes ouvertes ».
- Ministère de l'Agriculture, RefEA « Les journées portes ouvertes » (licence ouverte).
- Onisep, Idéo-Organismes d'information et d'orientation (licence ODbL) : CIO et SCUIO.
- MESR, Parcoursup 2025 (cod_aff_form -> cod_uai), pour relier chaque formation
  de la carte aux portes ouvertes de son établissement.

Usage, depuis la racine du dépôt :
    python3 scripts/build_jpo.py [dossier-de-cache]
Le script télécharge les sources (avec plusieurs essais), puis réécrit jpo.json et orientation.json.
Avec un dossier de cache, les fichiers déjà téléchargés sont réutilisés.
"""
import csv, datetime, io, json, math, re, sys, urllib.request

ONISEP_SUP = "https://data.onisep.fr/api/v1/downloads/5fa586da5c4b6/5fa586da5c4b6.csv"
DATAGOUV = "https://www.data.gouv.fr/api/1/datasets/?q=Ideo+Structures+enseignement+secondaire&page_size=5"
AGRI = "https://enseignement-agricole.opendatasoft.com/api/explore/v2.1/catalog/datasets/uai-evenement/exports/json"
PARCOURSUP = ("https://data.enseignementsup-recherche.gouv.fr/api/explore/v2.1/catalog/datasets/"
              "fr-esr-parcoursup/exports/csv?select=cod_aff_form,cod_uai&where=session%3D%272025%27&delimiter=%3B")
SAME_SITE_M = 150          # distance max pour « même adresse »
KEEP_FROM = "2026-09-01"   # on ignore les dates plus anciennes


CACHE = sys.argv[1] if len(sys.argv) > 1 else None   # dossier de cache optionnel


def get(url, timeout=300):
    import hashlib, os, time
    path = os.path.join(CACHE, hashlib.md5(url.encode()).hexdigest()) if CACHE else None
    if path and os.path.exists(path):
        return open(path, encoding="utf-8").read()
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "reperes-build/1.0"})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                text = r.read().decode("utf-8-sig")
            break
        except OSError as e:
            if attempt == 3:
                raise
            print(f"  nouvel essai ({e})", file=sys.stderr)
            time.sleep(5 * (attempt + 1))
    if path:
        os.makedirs(CACHE, exist_ok=True)
        open(path, "w", encoding="utf-8").write(text)
    return text


def rows(text):
    return list(csv.DictReader(io.StringIO(text), delimiter=";"))


def datagouv_csv(title):
    q = urllib.request.quote(title)
    for d in json.loads(get("https://www.data.gouv.fr/api/1/datasets/?q=" + q + "&page_size=10"))["data"]:
        if d["title"] == title:
            return next(r["url"] for r in d["resources"] if r["format"] == "csv")
    raise SystemExit("Jeu introuvable sur data.gouv.fr : " + title)


def build_orientation():
    """CIO et SCUIO : nom, type, adresse, commune, département, téléphone, lat, lon, lien Onisep."""
    out = []
    for r in rows(get(datagouv_csv("Idéo-Organismes d'information et d'orientation (Enseignement secondaire et supérieur)"))):
        try:
            lat, lon = round(float(r["latitude (Y)"]), 5), round(float(r["longitude (X)"]), 5)
        except ValueError:
            continue
        t = "CIO" if "(CIO)" in r["type d'organisme"] else "SCUIO"
        adr = " ".join(x for x in (r["adresse"].strip(), r["CP"].strip(), r["commune"].strip()) if x)
        out.append([r["nom"].strip(), t, adr, r["commune"].strip(), r["département"].split(" - ")[0].strip(),
                    r["téléphone"].strip(), lat, lon, r["lien site onisep.fr"].strip()])
    out.sort(key=lambda x: (x[4], x[3], x[0]))
    with open("orientation.json", "w", encoding="utf-8") as f:
        json.dump({"generated": datetime.date.today().isoformat(), "orgs": out}, f, ensure_ascii=False, separators=(",", ":"))
    print(f"{len(out)} CIO et services d'orientation universitaires", file=sys.stderr)


def onisep_secondaire_url():
    for d in json.loads(get(DATAGOUV))["data"]:
        if d["title"] == "Idéo-Structures d'enseignement secondaire":
            return next(r["url"] for r in d["resources"] if r["format"] == "csv")
    raise SystemExit("Jeu Onisep secondaire introuvable sur data.gouv.fr")


def dist(a, b, c, d):
    p = math.radians
    h = math.sin(p(c - a) / 2) ** 2 + math.cos(p(a)) * math.cos(p(c)) * math.sin(p(d - b) / 2) ** 2
    return 6371000 * 2 * math.asin(math.sqrt(h))


DATE = r"(\d\d)/(\d\d)/(\d{4})"
SEG = re.compile(r"^(?:le " + DATE + r"|du " + DATE + r" au " + DATE + r")"
                 r"(?: de (\d\d)h(\d\d) à (\d\d)h(\d\d))?(,? en virtuel)?(?: \((.*)\))?(?: voir (\S+))?$")


def iso(d, m, y):
    return f"{y}-{m}-{d}"


def parse_onisep(txt):
    out = []
    for s in (x.strip() for x in txt.split(" | ")):
        m = SEG.match(s)
        if not m:
            print("  segment ignoré :", s[:120], file=sys.stderr)
            continue
        g = m.groups()
        d1 = iso(*g[0:3]) if g[0] else iso(*g[3:6])
        d2 = d1 if g[0] else iso(*g[6:9])
        hrs = f"{g[9]}h{g[10]}–{g[11]}h{g[12]}".replace("h00", "h") if g[9] else ""
        out.append([d1, d2, hrs, (g[14] or "").strip(), g[15] or "", 1 if g[13] else 0])
    return out


def short_type(t):
    t = t.lower()
    for k, v in (("universit", "Université"), ("iut", "IUT"), ("unité de formation", "UFR"), ("ingénieur", "École d'ingénieurs"),
                 ("commerce", "École de commerce"), ("lycée", "Lycée"), ("art", "École d'art"), ("santé", "Santé / social"),
                 ("social", "Santé / social"), ("agricole", "Enseignement agricole"), ("rurale", "Enseignement agricole")):
        if k in t:
            return v
    return "Autre école"


def main():
    formations = json.load(open("formations-2025.json", encoding="utf-8"))
    print("Téléchargement des sources…", file=sys.stderr)
    sup = rows(get(ONISEP_SUP))
    sec = rows(get(onisep_secondaire_url()))
    agri = json.loads(get(AGRI))
    ps = {r["cod_aff_form"]: r["cod_uai"] for r in rows(get(PARCOURSUP))}
    ps_uai = set(ps.values())
    S, sites, F = formations["strs"], formations["sites"], formations["f"]

    # Coordonnées des sites Parcoursup, pour filtrer les lycées et les établissements agricoles
    site_of_uai = {}
    for a in F:
        site_of_uai.setdefault(ps.get(a[21]), a[0])

    ests, events, by_uai = [], [], {}
    seen_events = set()

    def add_est(key, rec):
        if key in by_uai:
            return by_uai[key]
        by_uai[key] = len(ests)
        ests.append(rec)
        return by_uai[key]

    K = "journées portes ouvertes"
    for src, data in (("sup", sup), ("sec", sec)):
        for r in data:
            if not r.get(K, "").strip():
                continue
            uai = r["code UAI"].strip()
            try:
                lat, lon = round(float(r["latitude (Y)"]), 5), round(float(r["longitude (X)"]), 5)
            except ValueError:
                lat = lon = None
            if src == "sec" and uai not in ps_uai:
                # Lycée : on ne garde que ceux qui ont une formation post-bac sur Parcoursup (même UAI ou même adresse)
                if lat is None or not any(dist(lat, lon, s[0], s[1]) < SAME_SITE_M for s in sites):
                    continue
            evs = [e for e in parse_onisep(r[K]) if e[1] >= KEEP_FROM]
            if not evs:
                continue
            key = uai or ("onisep:" + r["URL et ID Onisep"])
            i = add_est(key, [r["nom"].strip(), r["commune"].strip(), r["département"].split(" - ")[0].strip(), r["région"].strip().replace("Ile-de-France", "Île-de-France"),
                              lat, lon, r["statut"].strip(), r["URL et ID Onisep"].strip(), short_type(r["type d'établissement"]), uai])
            for e in evs:
                k = (i, e[0], e[1], e[2])
                if k not in seen_events:
                    seen_events.add(k)
                    events.append([i] + e)

    L = "ABCDEFGHJKLMNPRSTUVWXYZ"
    for x in agri:
        n = x["uai_dger_rfa"][:7]
        uai = n + L[int(n) % 23]
        if uai not in ps_uai or not x["uaievt_debut_dt"] or (x["uaievt_fin_dt"] or x["uaievt_debut_dt"]) < KEEP_FROM:
            continue
        s = sites[site_of_uai[uai]]
        i = add_est(uai, [x["uailib_com"].strip(), x["comgeo_libusage"].title(), x["uai_insee_dep"].lstrip("0").zfill(2), x["reg_libusage"],
                          s[0], s[1], x["sectuai_libusage"], "", "Enseignement agricole", uai])
        hrs = (x.get("uaievt_comment_txt") or "").strip()
        k = (i, x["uaievt_debut_dt"], x["uaievt_fin_dt"], hrs)
        if k not in seen_events:
            seen_events.add(k)
            events.append([i, x["uaievt_debut_dt"], x["uaievt_fin_dt"] or x["uaievt_debut_dt"], "", hrs, "", 0])

    # Lien formation -> établissement qui organise les portes ouvertes
    # 0 = même établissement (UAI identique) ; 1 = même adresse (< 150 m), établissement différent
    link, kinds = {}, [0, 0]
    geo = [(i, e[4], e[5]) for i, e in enumerate(ests) if e[4] is not None]
    for a in F:
        cod, uai = a[21], ps.get(a[21])
        if uai in by_uai:
            link[cod] = [by_uai[uai], 0]; kinds[0] += 1
            continue
        s = sites[a[0]]
        best = min(((dist(s[0], s[1], la, lo), i) for i, la, lo in geo if abs(la - s[0]) < .01 and abs(lo - s[1]) < .015), default=None)
        if best and best[0] < SAME_SITE_M:
            link[cod] = [best[1], 1]; kinds[1] += 1

    events.sort(key=lambda e: (e[1], ests[e[0]][0]))
    out = {
        "generated": datetime.date.today().isoformat(),
        "sources": "Onisep (Idéo-Structures, ODbL) · Ministère de l'Agriculture (RefEA) · MESR (Parcoursup 2025)",
        "ests": ests, "events": events, "link": link,
    }
    with open("jpo.json", "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    print(f"{len(ests)} établissements, {len(events)} journées, {len(link)} formations reliées "
          f"({kinds[0]} même établissement, {kinds[1]} même adresse)", file=sys.stderr)
    build_orientation()


if __name__ == "__main__":
    main()
