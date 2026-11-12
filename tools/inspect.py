"""Print the instance tree of an .rbxlx place file (scripts, remotes, folders)."""
import sys
import xml.etree.ElementTree as ET

SHOWN = ("RemoteEvent", "RemoteFunction", "Folder", "ScreenGui", "ModuleScript")


def walk(e, d=0):
    for it in e.findall("Item"):
        name = None
        src = None
        p = it.find("Properties")
        if p is not None:
            for c in p:
                if c.get("name") == "Name":
                    name = c.text
                if c.get("name") == "Source":
                    src = c.text or ""
        cls = it.get("class")
        nchild = len(it.findall("Item"))
        if d < 2 or src is not None or cls in SHOWN:
            line = "  " * d + f"{cls} {name}"
            if src is not None:
                line += f" [src {len(src.splitlines())} lines]"
            if nchild:
                line += f" ({nchild} children)"
            print(line)
        walk(it, d + 1)


walk(ET.parse(sys.argv[1]).getroot())
