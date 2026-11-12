"""Rebuild the .rbxlx place file from src/.

Usage: python3 tools/build.py <base.rbxlx> <src dir> <out.rbxlx>

Every script in the base place gets its Source replaced by the matching
src/<instance path>.luau file. A .luau file with no matching instance is added
as a new ModuleScript under the instance its directory maps to. Everything else
in the place (parts, folders, properties) is kept as is.
"""
import os
import sys
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape, quoteattr

SCRIPT_CLASSES = ("Script", "LocalScript", "ModuleScript")


def prop(item, name):
    props = item.find("Properties")
    if props is None:
        return None
    for child in props:
        if child.get("name") == name:
            return child
    return None


def item_name(item):
    node = prop(item, "Name")
    return node.text if node is not None and node.text else item.get("class")


def index(parent, path, table):
    for item in parent.findall("Item"):
        here = path + (item_name(item),)
        table[here] = item
        index(item, here, table)


def new_module(name, source, referent):
    item = ET.Element("Item", {"class": "ModuleScript", "referent": referent})
    props = ET.SubElement(item, "Properties")
    ET.SubElement(props, "string", {"name": "Name"}).text = name
    ET.SubElement(props, "string", {"name": "Source"}).text = source
    item.tail = "\n"
    return item


def serialize(node, out):
    attrs = "".join(f" {k}={quoteattr(v)}" for k, v in node.attrib.items())
    out.append(f"<{node.tag}{attrs}>")
    text = node.text or ""
    if node.tag == "string" and node.get("name") == "Source":
        out.append("<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>")
    else:
        out.append(escape(text))
    for child in node:
        serialize(child, out)
        out.append(escape(child.tail or ""))
    out.append(f"</{node.tag}>")


def main(base, src, out_path):
    root = ET.parse(base).getroot()
    items = {}
    index(root, (), items)

    sources = {}
    for folder, _, files in os.walk(src):
        for file in files:
            if file.endswith(".luau"):
                full = os.path.join(folder, file)
                rel = os.path.relpath(full, src)[: -len(".luau")]
                with open(full, encoding="utf-8") as f:
                    sources[tuple(rel.split(os.sep))] = f.read()

    updated, added = 0, 0
    for path in sorted(sources):
        item = items.get(path)
        if item is not None:
            if item.get("class") not in SCRIPT_CLASSES:
                sys.exit(f"{'/'.join(path)} is a {item.get('class')}, not a script")
            node = prop(item, "Source")
            if node.text != sources[path]:
                updated += 1
            node.text = sources[path]
            continue
        parent = items.get(path[:-1])
        if parent is None:
            sys.exit(f"no parent instance for {'/'.join(path)}")
        added += 1
        item = new_module(path[-1], sources[path], f"RBXBUILD{len(items)}")
        parent.append(item)
        items[path] = item
        print("added", "/".join(path))

    missing = [p for p, i in items.items() if i.get("class") in SCRIPT_CLASSES and p not in sources]
    if missing:
        sys.exit("scripts in the place without a source file: " + ", ".join("/".join(p) for p in missing))

    out = []
    serialize(root, out)
    with open(out_path, "w", encoding="utf-8", newline="") as f:
        f.write("".join(out) + "\n")
    print(f"{out_path}: {updated} scripts updated, {added} added, {len(sources)} total")


if __name__ == "__main__":
    main(*sys.argv[1:4])
