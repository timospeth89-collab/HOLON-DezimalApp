#!/usr/bin/env python3
"""Setzt src/*.js + src/vendor/xlsx.full.min.js + src/style.css zu einer
einzigen, eigenstaendigen berichtsheft.html zusammen. Keine Laufzeit-
Internetverbindung noetig -- alles ist eingebettet, damit die Datei auch
auf einem abgeriegelten Firmenrechner funktioniert.

Aufruf:  python3 build.py
"""
import pathlib

ROOT = pathlib.Path(__file__).parent
SRC = ROOT / "src"


def read(name: str) -> str:
    return (SRC / name).read_text(encoding="utf-8")


def main() -> None:
    xlsx_lib = read("vendor/xlsx.full.min.js")
    style = read("style.css")
    model_js = read("model.js")
    xlsx_io_js = read("xlsx-io.js")
    app_js = read("app.js")

    html = f"""<!doctype html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Berichtsheft</title>
<style>
{style}
</style>
</head>
<body>
<div id="app"></div>
<script>
{xlsx_lib}
</script>
<script>
{model_js}
</script>
<script>
{xlsx_io_js}
</script>
<script>
{app_js}
</script>
</body>
</html>
"""
    out = ROOT / "berichtsheft.html"
    out.write_text(html, encoding="utf-8")
    print(f"geschrieben: {out} ({out.stat().st_size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
