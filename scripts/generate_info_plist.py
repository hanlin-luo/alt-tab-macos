#!/usr/bin/env python3
"""Generate the app's Info.plist from the template, substituting the xcconfig build settings.

Xcode does this substitution at build time (INFOPLIST_PREPROCESS / build setting expansion).
Without Xcode we do it ourselves, reading the same xcconfig files the Xcode project reads, so the
two paths can't drift: config/base.xcconfig, then config/release.xcconfig, then the developer
override config/local.xcconfig (which is included last by release.xcconfig and therefore wins).

Usage: generate_info_plist.py <output.plist>
"""
import os
import plistlib
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
XCCONFIGS = ["config/base.xcconfig", "config/release.xcconfig", "config/local.xcconfig"]

SETTING_RE = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$")


def read_settings():
    settings = {}
    for rel in XCCONFIGS:
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            continue
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                line = line.split("//", 1)[0] if line.lstrip().startswith("//") else line
                stripped = line.strip()
                if not stripped or stripped.startswith("//") or stripped.startswith("#include"):
                    continue
                match = SETTING_RE.match(stripped)
                if match:
                    settings[match.group(1)] = match.group(2)
    return settings


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: generate_info_plist.py <output.plist>")
    output = sys.argv[1]

    settings = read_settings()
    settings.setdefault("PRODUCT_NAME", "AltTab")
    # EXECUTABLE_NAME is not an xcconfig setting: Xcode derives it from the product name.
    settings.setdefault("EXECUTABLE_NAME", settings["PRODUCT_NAME"])
    settings.setdefault("APPCENTER_SECRET", "")

    template = os.path.join(ROOT, "Info.plist")
    with open(template, encoding="utf-8") as handle:
        text = handle.read()

    def substitute(match):
        key = match.group(1)
        if key not in settings:
            sys.exit("Info.plist references $(%s) but no xcconfig defines it" % key)
        return settings[key]

    text = re.sub(r"\$\(([A-Za-z_][A-Za-z0-9_]*)\)", substitute, text)

    with open(output, "wb") as handle:
        plistlib.dump(plistlib.loads(text.encode("utf-8")), handle, fmt=plistlib.FMT_BINARY)

    print("wrote %s (version %s, bundle %s)" % (
        output, settings.get("CURRENT_PROJECT_VERSION", "?"),
        settings.get("PRODUCT_BUNDLE_IDENTIFIER", "?")))


if __name__ == "__main__":
    main()
