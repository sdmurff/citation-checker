import streamlit as st
import requests
from urllib.parse import quote_plus
from scholarly import scholarly
from bibtexparser import loads

def find_doi_crossref(title):
    try:
        resp = requests.get(
            "https://api.crossref.org/works",
            params={"query.bibliographic": title, "rows": 1},
            timeout=10,
        )
        resp.raise_for_status()
        items = resp.json().get("message", {}).get("items", [])
        if items:
            return items[0].get("DOI", "")
    except Exception as e:
        st.error(f"Crossref lookup failed: {e}")
    return ""

def find_doi_openalex(title):
    try:
        resp = requests.get(
            "https://api.openalex.org/works",
            params={"filter": f"title.search:{title}", "per-page": 1},
            timeout=10,
        )
        resp.raise_for_status()
        results = resp.json().get("results", [])
        if results:
            return results[0].get("doi", "")
    except Exception as e:
        st.error(f"OpenAlex lookup failed: {e}")
    return ""

def find_url_scholar(title):
    try:
        search = scholarly.search_pubs(title)
        pub = next(search, None)
        if pub:
            return pub.get("pub_url", "")
    except Exception as e:
        st.error(f"Google Scholar lookup failed: {e}")
    return ""

def google_scholar_search_url(title):
    return f"https://scholar.google.com/scholar?q={quote_plus(title)}"

def get_crossref_metadata(doi):
    try:
        resp = requests.get(f"https://api.crossref.org/works/{doi}", timeout=10)
        resp.raise_for_status()
        msg = resp.json().get("message", {})

        author_names = []
        for a in msg.get("author", []):
            fam = a.get("family", "")
            giv = a.get("given", "")
            if fam and giv:
                author_names.append(f"{fam}, {giv[0]}.")
            else:
                author_names.append(fam)
        authors_str = ", ".join(author_names)

        year = msg.get("issued", {}).get("date-parts", [[None]])[0][0]
        title = msg.get("title", [""])[0]
        journal = msg.get("container-title", [""])[0]
        volume = msg.get("volume", "")
        issue = msg.get("issue", "")
        pages = msg.get("page", "")
        doi_url = f"https://doi.org/{doi}"

        apa = f"{authors_str} ({year}). {title}. *{journal}*, {volume}({issue}), {pages}. {doi_url}"

        return {
            "APA Citation": apa,
            "Title": title,
            "Year": year,
            "Journal": journal,
            "Volume": volume,
            "Issue": issue,
            "Pages": pages,
            "DOI URL": doi_url,
        }
    except Exception as e:
        st.error(f"Metadata fetch failed: {e}")
    return {}

def extract_title_from_bibtex(bibtex_text):
    try:
        db = loads(bibtex_text)
        if db.entries:
            return db.entries[0].get("title", "").strip("{}")
    except Exception as e:
        st.error(f"BibTeX parse failed: {e}")
    return ""

# --- Streamlit UI ---
st.set_page_config(page_title="Reference Checker", layout="centered")
st.title("📘 Reference DOI & Metadata Checker")

mode = st.radio("Select Input Mode", ["Paste Reference", "Paste BibTeX"], key="mode")

if mode == "Paste Reference":
    reference_input = st.text_area("Paste your reference:", height=150, key="ref_input")
    title_guess = reference_input.strip()
else:
    bibtex_input = st.text_area("Paste your BibTeX entry:", height=200, key="bib_input")
    title_guess = extract_title_from_bibtex(bibtex_input)

if st.button("🔍 Check Reference", key="check_ref"):
    if not title_guess:
        st.warning("Please provide a reference or BibTeX first.")
    else:
        with st.spinner("Searching..."):
            doi = find_doi_crossref(title_guess) or find_doi_openalex(title_guess)
            scholar_url = "" if doi else find_url_scholar(title_guess)
            gs_url = google_scholar_search_url(title_guess)
            metadata = get_crossref_metadata(doi) if doi else {}

        st.markdown("### ✅ Results")

        if doi:
            st.success(f"**DOI Found:** {doi}")
            st.markdown(f"🔗 [DOI URL]({metadata.get('DOI URL','')})")
        else:
            st.warning("DOI not found.")

        st.markdown(f"🔗 [Google Scholar Search]({gs_url})")
        if scholar_url:
            st.markdown(f"🔗 [Likely Google Scholar Match]({scholar_url})")

        if metadata:
            st.markdown("#### 📄 APA Citation")
            st.code(metadata["APA Citation"], language="markdown")
            st.markdown("#### 📊 Extracted Metadata")
            st.json(metadata)
