from __future__ import annotations

from bs4 import BeautifulSoup


def parse_texts(content: bytes | str, css_selector: str) -> list[str]:
    soup = BeautifulSoup(content, "html.parser")
    items = soup.select(css_selector)
    return [item.text for item in items]
