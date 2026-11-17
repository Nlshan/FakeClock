#!/usr/bin/env python3
"""Deterministic Xcode project generator for FakeClock.

Writes a complete FakeClock.xcodeproj/project.pbxproj (plus the shared scheme
and workspace data) that references every Swift source file under FakeClock/,
Assets.xcassets, and Info.plist.

Every PBX object ID is exactly 24 uppercase hexadecimal characters derived
from SHA-256 of a stable seed string, so output is byte-identical across runs.
The generator validates its own output before reporting success.

Run:  python3 generate_project.py
"""

import hashlib
import os
import re
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC_DIR = "FakeClock"
TARGET_NAME = "FakeClock"
BUNDLE_ID = "com.fake.clock"
DEPLOYMENT_TARGET = "16.3"
SWIFT_VERSION = "5.0"
XCODEPROJ = os.path.join(ROOT, "FakeClock.xcodeproj")

ID_RE = re.compile(r"[0-9A-F]{24}")
BARE_OK = re.compile(r"[A-Za-z0-9_.$/-]+")


def oid(seed: str) -> str:
    """Deterministic 24-char uppercase hex object id."""
    return hashlib.sha256(("fakeclock|" + seed).encode("utf-8")).hexdigest()[:24].upper()


def val(v: str) -> str:
    """Quote a pbxproj string value only when necessary."""
    if BARE_OK.fullmatch(v):
        return v
    return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'


# ---------------------------------------------------------------- collection

def collect_files():
    swift = []
    for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, SRC_DIR)):
        dirnames.sort()
        for f in sorted(filenames):
            if f.endswith(".swift"):
                rel = os.path.relpath(os.path.join(dirpath, f), ROOT).replace("\\", "/")
                swift.append(rel)
    swift.sort()
    if not swift:
        sys.exit("ERROR: no Swift files found under %s" % SRC_DIR)
    resources = []
    for extra in (SRC_DIR + "/Info.plist", SRC_DIR + "/Assets.xcassets"):
        if os.path.exists(os.path.join(ROOT, extra)):
            resources.append(extra)
        else:
            sys.exit("ERROR: required resource missing: " + extra)
    return swift, resources


SWIFT_FILES, RESOURCE_FILES = collect_files()


# ------------------------------------------------------------------- groups

class Group:
    def __init__(self, name, path, gid):
        self.name = name          # display name ("" for root)
        self.path = path          # pbxproj path component (None for root/products)
        self.id = gid
        self.subgroups = {}       # relpath -> Group
        self.files = []           # list of (file_name, fileref_id, comment_suffix)


root_group = Group("", None, oid("group|<root>"))
products_group = Group("Products", None, oid("group|Products"))

group_index = {"": root_group}


def get_group(reldir: str) -> Group:
    if reldir in group_index:
        return group_index[reldir]
    parts = reldir.split("/")
    parent = get_group("/".join(parts[:-1]))
    g = Group(parts[-1], parts[-1], oid("group|" + reldir))
    group_index[reldir] = g
    parent.subgroups[reldir] = g
    return g


FILE_TYPE = {
    ".swift": "sourcecode.swift",
    ".plist": "text.plist.xml",
    ".xcassets": "folder.assetcatalog",
}


def file_type(path):
    for ext, t in FILE_TYPE.items():
        if path.endswith(ext):
            return t
    return "text"


all_project_files = sorted(SWIFT_FILES + RESOURCE_FILES)

fileref_id = {}
buildfile_id = {}

for rel in all_project_files:
    reldir, fname = os.path.split(rel)
    g = get_group(reldir)
    fid = oid("fileref|" + rel)
    fileref_id[rel] = fid
    g.files.append((fname, fid))
    if rel.endswith(".swift"):
        buildfile_id[rel] = oid("buildfile|" + rel)
    elif rel.endswith(".xcassets"):
        buildfile_id[rel] = oid("buildfile|" + rel)

APP_FILE_ID = oid("fileref|product:FakeClock.app")

# ------------------------------------------------------------------ object ids

PROJECT_ID = oid("object|PBXProject")
TARGET_ID = oid("object|PBXNativeTarget|FakeClock")
SOURCES_PHASE_ID = oid("object|phase|sources")
FRAMEWORKS_PHASE_ID = oid("object|phase|frameworks")
RESOURCES_PHASE_ID = oid("object|phase|resources")
PROJECT_CONF_LIST_ID = oid("object|confList|project")
TARGET_CONF_LIST_ID = oid("object|confList|target")
CONF_IDS = {
    ("project", "Debug"): oid("object|conf|project|Debug"),
    ("project", "Release"): oid("object|conf|project|Release"),
    ("target", "Debug"): oid("object|conf|target|Debug"),
    ("target", "Release"): oid("object|conf|target|Release"),
}

# Collision + format validation before anything is written.
all_ids = list(fileref_id.values()) + list(buildfile_id.values()) + \
    [g.id for g in group_index.values()] + \
    [products_group.id, APP_FILE_ID, PROJECT_ID, TARGET_ID, SOURCES_PHASE_ID,
     FRAMEWORKS_PHASE_ID, RESOURCES_PHASE_ID, PROJECT_CONF_LIST_ID,
     TARGET_CONF_LIST_ID] + list(CONF_IDS.values())

for i in all_ids:
    if not ID_RE.fullmatch(i):
        sys.exit("ERROR: malformed object id: " + i)
if len(set(all_ids)) != len(all_ids):
    seen, dup = set(), []
    for i in all_ids:
        if i in seen:
            dup.append(i)
        seen.add(i)
    sys.exit("ERROR: duplicate object ids: " + ", ".join(dup))

# ------------------------------------------------------------------- builders

T = "\t"


def emit_groups(out):
    children = []
    top = group_index[""]
    if top.subgroups:
        children.append(SRC_DIR)      # the FakeClock/ folder wraps everything
    children.append("Products")

    def block(gid, name_comment, path, child_ids):
        b = ["%s%s /* %s */ = {" % (T * 2, gid, name_comment),
             "%s%sisa = PBXGroup;" % (T * 3, T),
             "%s%schildren = (" % (T * 3, T)]
        for cid, cname in child_ids:
            b.append("%s%s%s /* %s */," % (T * 4, T, cid, cname))
        b.append("%s%s);" % (T * 3, T))
        if path is not None:
            b.append("%s%spath = %s;" % (T * 3, T, val(path)))
        b.append('%s%sourceTree = "<group>";' % (T * 3, T))
        b.append("%s};" % (T * 2,))
        return "\n".join(b)

    blocks = {}

    def child_ids(g, is_products=False):
        ids = [(g.subgroups[r].id, g.subgroups[r].name) for r in sorted(g.subgroups)]
        ids += [(fid, fname) for fname, fid in sorted(g.files)]
        if is_products:
            ids = [(APP_FILE_ID, "FakeClock.app")]
        return ids

    # nested groups under FakeClock/, deepest first is irrelevant (we key by id)
    for rel in sorted(group_index):
        if rel == "":
            continue
        g = group_index[rel]
        blocks[g.id] = block(g.id, g.name, g.path, child_ids(g))

    # root group (no path key)
    root_child_ids = []
    if SRC_DIR in group_index:
        root_child_ids.append((group_index[SRC_DIR].id, SRC_DIR))
    root_child_ids.append((products_group.id, "Products"))
    blocks[root_group.id] = block(root_group.id, "", None, root_child_ids)
    blocks[products_group.id] = block(products_group.id, "Products", None, child_ids(products_group, is_products=True))

    out.append("/* Begin PBXGroup section */")
    out.extend(blocks[k] for k in sorted(blocks))
    out.append("/* End PBXGroup section */")
    out.append("")


def emit_filerefs(out):
    out.append("/* Begin PBXFileReference section */")
    lines = []
    for rel in all_project_files:
        fname = rel.split("/")[-1]
        lines.append('%s%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; path = %s; sourceTree = "<group>"; };'
                     % (T * 2, fileref_id[rel], fname, file_type(rel), val(fname)))
    lines.append('%s%s /* FakeClock.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = FakeClock.app; sourceTree = BUILT_PRODUCTS_DIR; };'
                 % (T * 2, APP_FILE_ID))
    out.extend(sorted(lines))
    out.append("/* End PBXFileReference section */")
    out.append("")


def emit_buildfiles(out):
    out.append("/* Begin PBXBuildFile section */")
    lines = []
    for rel in SWIFT_FILES:
        fname = rel.split("/")[-1]
        lines.append('%s%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };'
                     % (T * 2, buildfile_id[rel], fname, fileref_id[rel], fname))
    assets = SRC_DIR + "/Assets.xcassets"
    lines.append('%s%s /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = %s /* Assets.xcassets */; };'
                 % (T * 2, buildfile_id[assets], fileref_id[assets]))
    out.extend(sorted(lines))
    out.append("/* End PBXBuildFile section */")
    out.append("")


PROJECT_COMMON = [
    ("ALWAYS_SEARCH_USER_PATHS", "NO"),
    ("CLANG_ANALYZER_NONNULL", "YES"),
    ("CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION", "YES_AGGRESSIVE"),
    ("CLANG_CXX_LANGUAGE_STANDARD", "gnu++20"),
    ("CLANG_CXX_LIBRARY", "libc++"),
    ("CLANG_ENABLE_MODULES", "YES"),
    ("CLANG_ENABLE_OBJC_ARC", "YES"),
    ("CLANG_ENABLE_OBJC_WEAK", "YES"),
    ("CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING", "YES"),
    ("CLANG_WARN_BOOL_CONVERSION", "YES"),
    ("CLANG_WARN_COMMA", "YES"),
    ("CLANG_WARN_CONSTANT_CONVERSION", "YES"),
    ("CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS", "YES"),
    ("CLANG_WARN_DIRECT_OBJC_ISA_USAGE", "YES_ERROR"),
    ("CLANG_WARN_DOCUMENTATION_COMMENTS", "YES"),
    ("CLANG_WARN_EMPTY_BODY", "YES"),
    ("CLANG_WARN_ENUM_CONVERSION", "YES"),
    ("CLANG_WARN_INFINITE_RECURSION", "YES"),
    ("CLANG_WARN_INT_CONVERSION", "YES"),
    ("CLANG_WARN_NON_LITERAL_NULL_CONVERSION", "YES"),
    ("CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF", "YES"),
    ("CLANG_WARN_OBJC_LITERAL_CONVERSION", "YES"),
    ("CLANG_WARN_OBJC_ROOT_CLASS", "YES_ERROR"),
    ("CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER", "YES"),
    ("CLANG_WARN_RANGE_LOOP_ANALYSIS", "YES"),
    ("CLANG_WARN_STRICT_PROTOTYPES", "YES"),
    ("CLANG_WARN_SUSPICIOUS_MOVE", "YES"),
    ("CLANG_WARN_UNGUARDED_AVAILABILITY", "YES_AGGRESSIVE"),
    ("CLANG_WARN_UNREACHABLE_CODE", "YES"),
    ("CLANG_WARN__DUPLICATE_METHOD_MATCH", "YES"),
    ("COPY_PHASE_STRIP", "NO"),
    ("ENABLE_STRICT_OBJC_MSGSEND", "YES"),
    ("GCC_C_LANGUAGE_STANDARD", "gnu17"),
    ("GCC_NO_COMMON_BLOCKS", "YES"),
    ("GCC_WARN_64_TO_32_BIT_CONVERSION", "YES"),
    ("GCC_WARN_ABOUT_RETURN_TYPE", "YES_ERROR"),
    ("GCC_WARN_UNDECLARED_SELECTOR", "YES"),
    ("GCC_WARN_UNINITIALIZED_AUTOS", "YES_AGGRESSIVE"),
    ("GCC_WARN_UNUSED_FUNCTION", "YES"),
    ("GCC_WARN_UNUSED_VARIABLE", "YES"),
    ("IPHONEOS_DEPLOYMENT_TARGET", DEPLOYMENT_TARGET),
    ("LOCALIZATION_PREFERS_STRING_CATALOGS", "YES"),
    ("MTL_FAST_MATH", "YES"),
    ("SDKROOT", "iphoneos"),
]

PROJECT_DEBUG = PROJECT_COMMON + [
    ("DEBUG_INFORMATION_FORMAT", "dwarf"),
    ("ENABLE_TESTABILITY", "YES"),
    ("GCC_DYNAMIC_NO_PIC", "NO"),
    ("GCC_OPTIMIZATION_LEVEL", "0"),
    ("MTL_ENABLE_DEBUG_INFO", "INCLUDE_SOURCE"),
    ("ONLY_ACTIVE_ARCH", "YES"),
    ("SWIFT_OPTIMIZATION_LEVEL", "-Onone"),
]

PROJECT_RELEASE = PROJECT_COMMON + [
    ("DEBUG_INFORMATION_FORMAT", "dwarf-with-dsym"),
    ("ENABLE_NS_ASSERTIONS", "NO"),
    ("MTL_ENABLE_DEBUG_INFO", "NO"),
    ("SWIFT_COMPILATION_MODE", "wholemodule"),
    ("VALIDATE_PRODUCT", "YES"),
]

LIST_SETTINGS = {
    "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["DEBUG", "$(inherited)"],
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
}

TARGET_SETTINGS = [
    ("ASSETCATALOG_COMPILER_APPICON_NAME", "AppIcon"),
    ("ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME", "AccentColor"),
    ("CODE_SIGN_STYLE", "Automatic"),
    ("CURRENT_PROJECT_VERSION", "1"),
    ("ENABLE_PREVIEWS", "YES"),
    ("GENERATE_INFOPLIST_FILE", "NO"),
    ("INFOPLIST_FILE", SRC_DIR + "/Info.plist"),
    ("IPHONEOS_DEPLOYMENT_TARGET", DEPLOYMENT_TARGET),
    ("LD_RUNPATH_SEARCH_PATHS", "@LIST@"),
    ("MARKETING_VERSION", "1.0"),
    ("PRODUCT_BUNDLE_IDENTIFIER", BUNDLE_ID),
    ("PRODUCT_NAME", "$(TARGET_NAME)"),
    ("SWIFT_EMIT_LOC_STRINGS", "YES"),
    ("SWIFT_VERSION", SWIFT_VERSION),
    ("TARGETED_DEVICE_FAMILY", "1,2"),
]


def settings_lines(pairs, indent):
    lines = []
    for k, v in sorted(pairs):
        if v == "@LIST@" and k in LIST_SETTINGS:
            lines.append("%s%s = (" % (indent, k))
            for item in LIST_SETTINGS[k]:
                lines.append("%s\t%s," % (indent, val(item)))
            lines.append("%s);" % indent)
        else:
            lines.append("%s%s = %s;" % (indent, k, val(v)))
    return lines


def emit_configs(out):
    out.append("/* Begin XCBuildConfiguration section */")
    blocks = []

    def config_block(cid, scope, name, pairs, indent):
        b = ["%s%s /* %s */ = {" % (T * 2, cid, name),
             "%s%sisa = XCBuildConfiguration;" % (T * 3, T),
             "%s%sbuildSettings = {" % (T * 3, T)]
        b += settings_lines(pairs, T * 4)
        b += ["%s%s};" % (T * 3, T),
              "%s%sname = %s;" % (T * 3, T, name),
              "%s};" % (T * 2,)]
        return b

    blocks.append("\n".join(config_block(CONF_IDS[("project", "Debug")], "project", "Debug", PROJECT_DEBUG, T * 4)))
    blocks.append("\n".join(config_block(CONF_IDS[("project", "Release")], "project", "Release", PROJECT_RELEASE, T * 4)))
    blocks.append("\n".join(config_block(CONF_IDS[("target", "Debug")], "target", "Debug", TARGET_SETTINGS, T * 4)))
    blocks.append("\n".join(config_block(CONF_IDS[("target", "Release")], "target", "Release", TARGET_SETTINGS, T * 4)))
    out.extend(sorted(blocks))
    out.append("/* End XCBuildConfiguration section */")
    out.append("")


def emit_conf_lists(out):
    out.append("/* Begin XCConfigurationList section */")
    blocks = [
        "%s%s /* Build configuration list for PBXNativeTarget \"FakeClock\" */ = {\n"
        "%s%sisa = XCConfigurationList;\n"
        "%s%sbuildConfigurations = (\n"
        "%s%s%s /* Debug */,\n"
        "%s%s%s /* Release */,\n"
        "%s%s);\n"
        "%s%sdefaultConfigurationIsVisible = 0;\n"
        "%s%sdefaultConfigurationName = Release;\n"
        "%s};" % (T * 2, TARGET_CONF_LIST_ID, T * 3, T, T * 3, T, T * 4, T,
                  CONF_IDS[("target", "Debug")], T * 4, T, CONF_IDS[("target", "Release")],
                  T * 3, T, T * 3, T, T * 3, T, T * 2),
        "%s%s /* Build configuration list for PBXProject \"FakeClock\" */ = {\n"
        "%s%sisa = XCConfigurationList;\n"
        "%s%sbuildConfigurations = (\n"
        "%s%s%s /* Debug */,\n"
        "%s%s%s /* Release */,\n"
        "%s%s);\n"
        "%s%sdefaultConfigurationIsVisible = 0;\n"
        "%s%sdefaultConfigurationName = Release;\n"
        "%s};" % (T * 2, PROJECT_CONF_LIST_ID, T * 3, T, T * 3, T, T * 4, T,
                  CONF_IDS[("project", "Debug")], T * 4, T, CONF_IDS[("project", "Release")],
                  T * 3, T, T * 3, T, T * 3, T, T * 2),
    ]
    out.extend(sorted(blocks))
    out.append("/* End XCConfigurationList section */")
    out.append("")


SCHEME_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1540"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "%(target)s"
               BuildableName = "FakeClock.app"
               BlueprintName = "FakeClock"
               ReferencedContainer = "container:FakeClock.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "%(target)s"
            BuildableName = "FakeClock.app"
            BlueprintName = "FakeClock"
            ReferencedContainer = "container:FakeClock.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "%(target)s"
            BuildableName = "FakeClock.app"
            BlueprintName = "FakeClock"
            ReferencedContainer = "container:FakeClock.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


def main():
    out = ["// !$*UTF8*$!", "{",
           "%sarchiveVersion = 1;" % T,
           "%sclasses = {" % T, "%s};" % T,
           "%sobjectVersion = 56;" % T,
           "%sobjects = {" % T, ""]

    emit_buildfiles(out)
    emit_filerefs(out)

    i2, i3, i4 = T * 2, T * 3, T * 4

    def obj(gid, comment, body):
        head = ("%s%s /* %s */ = {" % (i2, gid, comment)) if comment else ("%s%s = {" % (i2, gid))
        return "\n".join([head] + body + ["%s};" % i2])

    # Frameworks phase
    out.append("/* Begin PBXFrameworksBuildPhase section */")
    out.append(obj(FRAMEWORKS_PHASE_ID, "Frameworks", [
        "%sisa = PBXFrameworksBuildPhase;" % i3,
        "%sbuildActionMask = 2147483647;" % i3,
        "%sfiles = (" % i3,
        "%s);" % i3,
        "%srunOnlyForDeploymentPostprocessing = 0;" % i3,
    ]))
    out.append("/* End PBXFrameworksBuildPhase section */")
    out.append("")

    emit_groups(out)

    # Native target
    out.append("/* Begin PBXNativeTarget section */")
    out.append(obj(TARGET_ID, "FakeClock", [
        "%sisa = PBXNativeTarget;" % i3,
        '%sbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget "FakeClock" */;' % (i3, TARGET_CONF_LIST_ID),
        "%sbuildPhases = (" % i3,
        "%s%s /* Sources */," % (i4, SOURCES_PHASE_ID),
        "%s%s /* Frameworks */," % (i4, FRAMEWORKS_PHASE_ID),
        "%s%s /* Resources */," % (i4, RESOURCES_PHASE_ID),
        "%s);" % i3,
        "%sbuildRules = (" % i3,
        "%s);" % i3,
        "%sdependencies = (" % i3,
        "%s);" % i3,
        "%sname = FakeClock;" % i3,
        "%sproductName = FakeClock;" % i3,
        "%sproductReference = %s /* FakeClock.app */;" % (i3, APP_FILE_ID),
        '%sproductType = "com.apple.product-type.application";' % i3,
    ]))
    out.append("/* End PBXNativeTarget section */")
    out.append("")

    # Project
    i5, i6 = T * 5, T * 6
    out.append("/* Begin PBXProject section */")
    out.append(obj(PROJECT_ID, "Project object", [
        "%sisa = PBXProject;" % i3,
        "%sattributes = {" % i3,
        '%sBuildVersion = "15F31d";' % i4,
        "%sLastSwiftUpdateCheck = 1540;" % i4,
        "%sLastUpgradeCheck = 1540;" % i4,
        "%sTargetAttributes = {" % i4,
        "%s%s = {" % (i5, TARGET_ID),
        "%sCreatedOnToolsVersion = 15.4;" % i6,
        "%s};" % i5,
        "%s};" % i4,
        "%s};" % i3,
        '%sbuildConfigurationList = %s /* Build configuration list for PBXProject "FakeClock" */;' % (i3, PROJECT_CONF_LIST_ID),
        '%scompatibilityVersion = "Xcode 14.0";' % i3,
        "%sdevelopmentRegion = en;" % i3,
        "%shasScannedForEncodings = 0;" % i3,
        "%sknownRegions = (" % i3,
        "%sen," % i4,
        "%sBase," % i4,
        "%s);" % i3,
        "%smainGroup = %s;" % (i3, root_group.id),
        "%sproductRefGroup = %s /* Products */;" % (i3, products_group.id),
        '%sprojectDirPath = "";' % i3,
        "%sprojectRoot = \"\";" % i3,
        "%stargets = (" % i3,
        "%s%s /* FakeClock */," % (i4, TARGET_ID),
        "%s);" % i3,
    ]))
    out.append("/* End PBXProject section */")
    out.append("")

    # Resources phase
    assets_rel = SRC_DIR + "/Assets.xcassets"
    out.append("/* Begin PBXResourcesBuildPhase section */")
    out.append(obj(RESOURCES_PHASE_ID, "Resources", [
        "%sisa = PBXResourcesBuildPhase;" % i3,
        "%sbuildActionMask = 2147483647;" % i3,
        "%sfiles = (" % i3,
        "%s%s /* Assets.xcassets in Resources */," % (i4, buildfile_id[assets_rel]),
        "%s);" % i3,
        "%srunOnlyForDeploymentPostprocessing = 0;" % i3,
    ]))
    out.append("/* End PBXResourcesBuildPhase section */")
    out.append("")

    # Sources phase
    out.append("/* Begin PBXSourcesBuildPhase section */")
    src_body = [
        "%sisa = PBXSourcesBuildPhase;" % i3,
        "%sbuildActionMask = 2147483647;" % i3,
        "%sfiles = (" % i3,
    ]
    for rel in SWIFT_FILES:
        fname = rel.split("/")[-1]
        src_body.append("%s%s /* %s in Sources */," % (i4, buildfile_id[rel], fname))
    src_body += [
        "%s);" % i3,
        "%srunOnlyForDeploymentPostprocessing = 0;" % i3,
    ]
    out.append(obj(SOURCES_PHASE_ID, "Sources", src_body))
    out.append("/* End PBXSourcesBuildPhase section */")
    out.append("")

    emit_configs(out)
    emit_conf_lists(out)

    out.append("\t};")
    out.append("\trootObject = %s /* Project object */;" % PROJECT_ID)
    out.append("}")

    text = "\n".join(out) + "\n"

    # ------------------------------------------------ self-validation on output
    defined = set(re.findall(r"^\t\t([0-9A-F]{24})(?: /\* [^*]* \*/)? = \{", text, re.M))
    defined |= set(re.findall(r"^\t\t([0-9A-F]{24}) /\* [^*]* \*/ = \{", text, re.M))
    referenced = set(re.findall(r"\b([0-9A-F]{24})\b", text))
    missing = referenced - defined
    if missing:
        sys.exit("ERROR: %d referenced ids never defined: %s" % (len(missing), sorted(missing)[:5]))
    bad = [i for i in referenced if not ID_RE.fullmatch(i)]
    if bad:
        sys.exit("ERROR: malformed ids: " + str(bad[:5]))

    os.makedirs(XCODEPROJ, exist_ok=True)
    pbx_path = os.path.join(XCODEPROJ, "project.pbxproj")
    with open(pbx_path, "w", newline="\n", encoding="utf-8") as f:
        f.write(text)

    # Shared scheme + workspace data
    scheme_dir = os.path.join(XCODEPROJ, "xcshareddata", "xcschemes")
    os.makedirs(scheme_dir, exist_ok=True)
    with open(os.path.join(scheme_dir, "FakeClock.xcscheme"), "w", newline="\n", encoding="utf-8") as f:
        f.write(SCHEME_TEMPLATE % {"target": TARGET_ID})

    ws_dir = os.path.join(XCODEPROJ, "project.xcworkspace")
    os.makedirs(ws_dir, exist_ok=True)
    with open(os.path.join(ws_dir, "contents.xcworkspacedata"), "w", newline="\n", encoding="utf-8") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n')

    n_build = text.count("isa = PBXBuildFile")
    n_fileref = text.count("isa = PBXFileReference")
    n_sources = len(SWIFT_FILES)
    print("OK  wrote %s" % pbx_path)
    print("    swift sources in Sources phase : %d" % n_sources)
    print("    PBXBuildFile objects           : %d (expect %d)" % (n_build, n_sources + 1))
    print("    PBXFileReference objects       : %d (expect %d)" % (n_fileref, len(all_project_files) + 1))
    print("    defined object ids             : %d, all 24-hex, all unique" % len(defined))
    print("    scheme                         : FakeClock.xcodeproj/xcshareddata/xcschemes/FakeClock.xcscheme")
    assert n_build == n_sources + 1
    assert n_fileref == len(all_project_files) + 1


if __name__ == "__main__":
    main()
