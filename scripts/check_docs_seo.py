#!/usr/bin/env python3
"""Validate static docs SEO and i18n invariants for macfusegui.app."""

from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse
import posixpath


ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
SITE_URL = "https://www.macfusegui.app"

LOCALES = {
    "en": {"hreflang": "en", "html_lang": "en"},
    "zh-hans": {"hreflang": "zh-Hans", "html_lang": "zh-Hans"},
    "ja": {"hreflang": "ja", "html_lang": "ja"},
    "de": {"hreflang": "de", "html_lang": "de"},
    "fr": {"hreflang": "fr", "html_lang": "fr"},
    "pt-br": {"hreflang": "pt-BR", "html_lang": "pt-BR"},
    "es": {"hreflang": "es", "html_lang": "es"},
    "ko": {"hreflang": "ko", "html_lang": "ko"},
}

PAGES = {
    "home": {"file_name": "index.html", "url_path": "", "keywords": ("macfuse gui", "sshfs", "macos")},
    "product": {"file_name": "macfuse-gui.html", "url_path": "macfuse-gui.html", "keywords": ("macfuse gui", "sshfs", "macos")},
    "sshfs": {"file_name": "sshfs-gui-mac.html", "url_path": "sshfs-gui-mac.html", "keywords": ("sshfs", "macos", "macfusegui")},
    "install": {"file_name": "install-macfuse-sshfs-mac.html", "url_path": "install-macfuse-sshfs-mac.html", "keywords": ("macfuse", "sshfs", "macos")},
    "troubleshooting": {"file_name": "macfusegui-troubleshooting.html", "url_path": "macfusegui-troubleshooting.html", "keywords": ("macfusegui", "sshfs", "macos")},
}

KEYWORD_PATTERN = re.compile(r"(macfuse|sshfs|macos)", re.IGNORECASE)


class PageInspector(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.title_count = 0
        self.meta_description_count = 0
        self.meta_description: str | None = None
        self.canonical_hrefs: list[str] = []
        self.h1_count = 0
        self.html_lang: str | None = None
        self.json_ld_count = 0
        self.breadcrumb_nav_count = 0
        self.related_guides_count = 0
        self.alternates: dict[str, list[str]] = {}
        self.headings: list[tuple[int, str]] = []
        self._current_heading: str | None = None
        self._heading_chunks: list[str] = []
        self.current_tag: str | None = None
        self.links: list[str] = []
        self.image_alts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attr_map = dict(attrs)
        if tag == "html":
            self.html_lang = attr_map.get("lang")
        if tag == "title":
            self.title_count += 1
        elif tag == "meta" and attr_map.get("name") == "description":
            self.meta_description_count += 1
            self.meta_description = attr_map.get("content")
        elif tag == "link" and attr_map.get("rel") == "canonical":
            href = attr_map.get("href")
            if href:
                self.canonical_hrefs.append(href)
        elif tag == "link" and attr_map.get("rel") == "alternate":
            hreflang = attr_map.get("hreflang")
            href = attr_map.get("href")
            if hreflang and href:
                self.alternates.setdefault(hreflang, []).append(href)
        elif tag == "h1":
            self.h1_count += 1
            self._current_heading = "h1"
            self._heading_chunks = []
        elif tag in {"h2", "h3", "h4", "h5", "h6"}:
            self._current_heading = tag
            self._heading_chunks = []
        elif tag == "nav" and (
            attr_map.get("data-breadcrumb") == "true"
            or attr_map.get("aria-label") == "Breadcrumb"
        ):
            self.breadcrumb_nav_count += 1
        elif tag == "section" and attr_map.get("data-related-guides") == "true":
            self.related_guides_count += 1
        elif tag == "script" and attr_map.get("type") == "application/ld+json":
            self.json_ld_count += 1
        elif tag == "a":
            href = attr_map.get("href")
            if href:
                self.links.append(href)
        elif tag == "img":
            alt = attr_map.get("alt")
            if alt is not None:
                self.image_alts.append(alt)
        self.current_tag = tag

    def handle_data(self, data: str) -> None:
        if self._current_heading:
            self._heading_chunks.append(data)

    def handle_endtag(self, tag: str) -> None:
        if self._current_heading == tag:
            text = " ".join("".join(self._heading_chunks).split())
            self.headings.append((int(tag[1]), text))
            self._current_heading = None
            self._heading_chunks = []
        if self.current_tag == tag:
            self.current_tag = None


def fail(errors: list[str], message: str) -> None:
    errors.append(message)


def build_expected_pages() -> dict[str, dict[str, str]]:
    expected: dict[str, dict[str, str]] = {}
    for locale_slug in LOCALES:
        for page_id, page in PAGES.items():
            if locale_slug == "en":
                rel_path = page["file_name"]
                expected_url = f"{SITE_URL}/" if page_id == "home" else f"{SITE_URL}/{page['file_name']}"
            else:
                rel_path = f"{locale_slug}/{page['file_name']}"
                expected_url = (
                    f"{SITE_URL}/{locale_slug}/"
                    if page_id == "home"
                    else f"{SITE_URL}/{locale_slug}/{page['file_name']}"
                )
            expected[rel_path] = {
                "url": expected_url,
                "locale_slug": locale_slug,
                "page_id": page_id,
            }
    return expected


def resolve_internal_href(current_rel_path: str, href: str) -> str | None:
    if href.startswith(("http://", "https://", "mailto:", "tel:", "#")):
        return None
    clean_href = href.split("#", 1)[0].split("?", 1)[0]
    if not clean_href:
        return None
    current_dir = posixpath.dirname(current_rel_path)
    resolved = posixpath.normpath(posixpath.join(current_dir, clean_href))
    if clean_href.endswith("/"):
        resolved = posixpath.join(resolved, "index.html")
    elif clean_href in {".", "./"}:
        resolved = posixpath.join(current_dir, "index.html")
    return resolved


def inspect_heading_outline(page: Path, headings: list[tuple[int, str]], errors: list[str]) -> None:
    max_level = 0
    prev_level = None
    for level, _text in headings:
        max_level = max(max_level, level)
        if prev_level is not None and level > prev_level + 1:
            fail(errors, f"{page.as_posix()}: skipped heading level from h{prev_level} to h{level}")
        prev_level = level
    if max_level > 3:
        fail(errors, f"{page.as_posix()}: max heading depth exceeds h3")


def inspect_html(page: Path, expected: dict[str, str], expected_pages: dict[str, dict[str, str]], errors: list[str]) -> None:
    content = page.read_text(encoding="utf-8")
    parser = PageInspector()
    parser.feed(content)
    rel_path = page.relative_to(DOCS).as_posix()
    locale_slug = expected["locale_slug"]
    page_id = expected["page_id"]
    expected_url = expected["url"]

    if parser.title_count != 1:
        fail(errors, f"{rel_path}: expected 1 <title>, found {parser.title_count}")
    if parser.meta_description_count != 1:
        fail(errors, f"{rel_path}: expected 1 meta description, found {parser.meta_description_count}")
    elif not parser.meta_description:
        fail(errors, f"{rel_path}: meta description is empty")
    else:
        meta_lower = parser.meta_description.casefold()
        keywords = PAGES[page_id]["keywords"]
        if not any(keyword in meta_lower for keyword in keywords):
            fail(errors, f"{rel_path}: meta description is missing page keywords")
    if len(parser.canonical_hrefs) != 1:
        fail(errors, f"{rel_path}: expected 1 canonical link, found {len(parser.canonical_hrefs)}")
    elif parser.canonical_hrefs[0] != expected_url:
        fail(errors, f"{rel_path}: canonical {parser.canonical_hrefs[0]!r} != {expected_url!r}")
    if parser.h1_count != 1:
        fail(errors, f"{rel_path}: expected 1 <h1>, found {parser.h1_count}")
    if parser.html_lang != LOCALES[locale_slug]["html_lang"]:
        fail(errors, f"{rel_path}: html lang {parser.html_lang!r} != {LOCALES[locale_slug]['html_lang']!r}")

    expected_alternates = {
        locale_info["hreflang"]: [
            build_expected_pages()[(
                PAGES[page_id]["file_name"] if locale_name == "en" else f"{locale_name}/{PAGES[page_id]['file_name']}"
            )]["url"]
        ]
        for locale_name, locale_info in LOCALES.items()
    }
    expected_alternates["x-default"] = [build_expected_pages()[PAGES[page_id]["file_name"]]["url"]]
    if set(parser.alternates.keys()) != set(expected_alternates.keys()):
        fail(errors, f"{rel_path}: hreflang set mismatch")
    else:
        for hreflang, expected_hrefs in expected_alternates.items():
            if parser.alternates.get(hreflang) != expected_hrefs:
                fail(errors, f"{rel_path}: hreflang {hreflang!r} does not match expected URL")

    if parser.json_ld_count < 1:
        fail(errors, f"{rel_path}: missing JSON-LD block")

    if not parser.image_alts:
        fail(errors, f"{rel_path}: expected at least one <img> alt")
    elif not all(KEYWORD_PATTERN.search(alt or "") for alt in parser.image_alts):
        fail(errors, f"{rel_path}: image alt text is missing SEO keywords")

    if "@tailwindcss/browser" in content:
        fail(errors, f"{rel_path}: still references @tailwindcss/browser")
    if 'type="text/tailwindcss"' in content:
        fail(errors, f"{rel_path}: still contains text/tailwindcss block")

    if page_id != "home":
        if parser.breadcrumb_nav_count != 1:
            fail(errors, f"{rel_path}: expected 1 breadcrumb nav, found {parser.breadcrumb_nav_count}")
        if parser.related_guides_count != 1:
            fail(errors, f"{rel_path}: expected 1 related guides section, found {parser.related_guides_count}")

    inspect_heading_outline(page, parser.headings, errors)

    for href in parser.links:
        resolved = resolve_internal_href(rel_path, href)
        if not resolved:
            continue
        if resolved not in expected_pages:
            continue
        target_locale = expected_pages[resolved]["locale_slug"]
        if target_locale != locale_slug:
            fail(errors, f"{rel_path}: internal docs link {href!r} crosses locales unexpectedly")


def inspect_sitemap(errors: list[str]) -> None:
    sitemap = DOCS / "sitemap.xml"
    root = ET.fromstring(sitemap.read_text(encoding="utf-8"))
    ns = {"sm": "http://www.sitemaps.org/schemas/sitemap/0.9"}
    xhtml_ns = {"xhtml": "http://www.w3.org/1999/xhtml"}
    url_nodes = root.findall("sm:url", ns)
    urls = set()
    expected_pages = build_expected_pages()
    expected = {data["url"] for data in expected_pages.values()}
    expected_hreflangs = {locale_info["hreflang"] for locale_info in LOCALES.values()} | {"x-default"}

    for url_node in url_nodes:
        loc = url_node.find("sm:loc", ns)
        if loc is None or not loc.text:
            fail(errors, "sitemap.xml: url entry missing <loc>")
            continue
        url = loc.text.strip()
        urls.add(url)
        alternates = {
            link.attrib.get("hreflang")
            for link in url_node.findall("xhtml:link", xhtml_ns)
            if link.attrib.get("rel") == "alternate"
        }
        if alternates != expected_hreflangs:
            fail(errors, f"sitemap.xml: alternate cluster mismatch for {url}")

    missing = sorted(expected - urls)
    extra = sorted(urls - expected)

    if missing:
        fail(errors, f"sitemap.xml: missing URLs: {', '.join(missing)}")
    if extra:
        fail(errors, f"sitemap.xml: unexpected URLs: {', '.join(extra)}")


def main() -> int:
    errors: list[str] = []
    expected_pages = build_expected_pages()
    actual_pages = {
        page.relative_to(DOCS).as_posix()
        for page in DOCS.rglob("*.html")
        if "assets/" not in page.as_posix()
    }
    expected_page_paths = set(expected_pages.keys())

    missing_pages = sorted(expected_page_paths - actual_pages)
    extra_pages = sorted(actual_pages - expected_page_paths)
    if missing_pages:
        fail(errors, f"docs inventory: missing HTML pages: {', '.join(missing_pages)}")
    if extra_pages:
        fail(errors, f"docs inventory: unexpected HTML pages: {', '.join(extra_pages)}")

    for rel_path, expected in expected_pages.items():
        page = DOCS / rel_path
        if not page.exists():
            fail(errors, f"missing page: {rel_path}")
            continue
        inspect_html(page, expected, expected_pages, errors)

    inspect_sitemap(errors)

    if errors:
        for error in errors:
            print(f"FAIL: {error}")
        return 1

    print("PASS: docs SEO checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
