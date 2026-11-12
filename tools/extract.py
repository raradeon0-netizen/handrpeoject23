"""Extract every script Source from an .rbxlx into src/<instance path>.luau."""
import os
import sys
import xml.etree.ElementTree as ET

SCRIPT_CLASSES = ("Script", "LocalScript", "ModuleScript")


def prop(item, name):
    p = item.find("Properties")
    if p is None:
        return None
    for c in p:
        if c.get("name") == name:
            return c.text or ""
    return None


def walk(e, path, out):
    for it in e.findall("Item"):
        name = prop(it, "Name") or it.get("class")
        here = path + [name]
        if it.get("class") in SCRIPT_CLASSES:
            dest = os.path.join(out, *here) + ".luau"
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, "w", encoding="utf-8", newline="") as f:
                f.write(prop(it, "Source") or "")
            print(dest)
        walk(it, here, out)


walk(ET.parse(sys.argv[1]).getroot(), [], sys.argv[2])
