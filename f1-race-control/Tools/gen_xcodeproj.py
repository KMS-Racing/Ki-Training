#!/usr/bin/env python3
"""Erzeugt Xcode/F1RaceControl.xcodeproj aus den Quellen in App/.

Warum ein Generator und keine von Hand gepflegte Projektdatei:

Eine .xcodeproj ist im Kern eine Textdatei (project.pbxproj), in der jede
Quelldatei zweimal mit einer 24-stelligen Kennung steht. Wer eine neue Ansicht
hinzufuegt und die Datei von Hand pflegt, vergisst frueher oder spaeter eine
Haelfte -- und Xcode meldet dann nichts, sondern uebersetzt die Datei einfach
nicht mit. Hier wird die Liste stattdessen aus dem Ordner gelesen.

Die Kennungen werden aus dem Dateinamen abgeleitet (md5). Dadurch aendert sich
die erzeugte Datei nicht bei jedem Lauf, und ein git diff zeigt wirklich nur das,
was neu ist.

    python3 Tools/gen_xcodeproj.py

Danach:  open Xcode/F1RaceControl.xcodeproj
"""
import hashlib
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent      # f1-race-control/
APP_DIR = ROOT / "App"
PROJECT_DIR = ROOT / "Xcode" / "F1RaceControl.xcodeproj"

APP_NAME = "F1RaceControl"
BUNDLE_ID = "de.kmsracing.F1RaceControl"

# Das Projekt liegt in Xcode/, die Quellen daneben in App/, das Swift-Paket eine
# Ebene darueber. Deshalb ueberall "..".
#
# Es liegt bewusst NICHT in App/: Auf dem Mac ist App/ der Ordner des SwiftPM-Ziels
# F1RaceControlApp (siehe Package.swift). Ein .xcodeproj mittendrin waere fuer
# SwiftPM eine unbekannte Datei im Quellordner.
PACKAGE_RELATIVE_PATH = ".."
APP_GROUP_PATH = "../App"


def oid(name: str) -> str:
    """Stabile 24-stellige Kennung, wie Xcode sie vergibt."""
    return hashlib.md5(name.encode("utf-8")).hexdigest()[:24].upper()


# ---------------------------------------------------------------------------
#  Quelldateien einsammeln
# ---------------------------------------------------------------------------

def swift_files(directory: pathlib.Path) -> list:
    return sorted(p.name for p in directory.glob("*.swift"))


root_sources = swift_files(APP_DIR)
view_sources = swift_files(APP_DIR / "Views")

if not root_sources:
    raise SystemExit("Keine Quelldateien in App/ gefunden.")

# (Anzeigename, Pfad-in-der-Gruppe, Schluessel fuer die Kennung)
all_sources = (
    [(n, n, "App/" + n) for n in root_sources]
    + [(n, n, "App/Views/" + n) for n in view_sources]
)

# ---------------------------------------------------------------------------
#  Kennungen
# ---------------------------------------------------------------------------

PROJECT = oid("project")
TARGET = oid("target")
PRODUCT_REF = oid("product")
MAIN_GROUP = oid("group:main")
APP_GROUP = oid("group:app")
VIEWS_GROUP = oid("group:views")
PRODUCTS_GROUP = oid("group:products")
SOURCES_PHASE = oid("phase:sources")
FRAMEWORKS_PHASE = oid("phase:frameworks")
RESOURCES_PHASE = oid("phase:resources")
PROJECT_CONFIG_LIST = oid("configlist:project")
TARGET_CONFIG_LIST = oid("configlist:target")
PROJECT_DEBUG = oid("config:project:debug")
PROJECT_RELEASE = oid("config:project:release")
TARGET_DEBUG = oid("config:target:debug")
TARGET_RELEASE = oid("config:target:release")
PACKAGE_REF = oid("package:local")
ENGINE_DEPENDENCY = oid("package:product:RaceEngine")
ENGINE_BUILD_FILE = oid("build:RaceEngine")


def file_ref(key: str) -> str:
    return oid("fileref:" + key)


def build_file(key: str) -> str:
    return oid("buildfile:" + key)


# ---------------------------------------------------------------------------
#  Bau-Einstellungen
# ---------------------------------------------------------------------------

PROJECT_COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_NO_COMMON_BLOCKS": "YES",
    # Der Sprachmodus 5 passt zum Paket (tools-version 5.9). Swift 6 wuerde die
    # Nebenlaeufigkeitsregeln verschaerfen -- das ist ein eigener Umbau, kein
    # Nebeneffekt der Projektdatei.
    "SWIFT_VERSION": "5.0",
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    # Zwei Plattformen aus einem Ziel: Mac und iPad.
    "SDKROOT": "auto",
    "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator macosx"',
}

PROJECT_DEBUG_SETTINGS = {
    "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
    "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
}

PROJECT_RELEASE_SETTINGS = {
    "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
    "ENABLE_NS_ASSERTIONS": "NO",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": '"-O"',
}

TARGET_COMMON = {
    "CODE_SIGN_STYLE": "Automatic",
    # Auf dem Mac reicht "lokal signieren" -- damit laeuft die App ohne
    # Entwicklerkonto. Fuer das iPad traegt Xcode das Team selbst ein.
    '"CODE_SIGN_IDENTITY[sdk=macosx*]"': '"-"',
    "COMBINE_HIDPI_IMAGES": "YES",
    "CURRENT_PROJECT_VERSION": "1",
    "ENABLE_HARDENED_RUNTIME": "YES",
    # Kein Info.plist im Ordner: Xcode erzeugt sie aus diesen Schluesseln.
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": (
        '"UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"'
    ),
    "LD_RUNPATH_SEARCH_PATHS": (
        '(\n\t\t\t\t\t"$(inherited)",\n'
        '\t\t\t\t\t"@executable_path/Frameworks",\n'
        '\t\t\t\t\t"@executable_path/../Frameworks",\n\t\t\t\t)'
    ),
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    # 2 = iPad. Ein iPhone-Layout gibt es bewusst nicht -- das Dashboard braucht
    # Breite, auf einem Telefon waere der Timing Tower unlesbar.
    "TARGETED_DEVICE_FAMILY": '"2"',
}


def settings_block(settings: dict, indent: str = "\t\t\t\t") -> str:
    return "\n".join(f"{indent}{key} = {value};" for key, value in sorted(settings.items()))


# ---------------------------------------------------------------------------
#  project.pbxproj zusammensetzen
# ---------------------------------------------------------------------------

lines = []
add = lines.append

add("// !$*UTF8*$!")
add("{")
add("\tarchiveVersion = 1;")
add("\tclasses = {")
add("\t};")
add("\tobjectVersion = 56;")
add("\tobjects = {")

# --- PBXBuildFile -----------------------------------------------------------
add("")
add("/* Begin PBXBuildFile section */")
for name, _, key in all_sources:
    add(
        f"\t\t{build_file(key)} /* {name} in Sources */ = {{isa = PBXBuildFile; "
        f"fileRef = {file_ref(key)} /* {name} */; }};"
    )
add(
    f"\t\t{ENGINE_BUILD_FILE} /* RaceEngine in Frameworks */ = {{isa = PBXBuildFile; "
    f"productRef = {ENGINE_DEPENDENCY} /* RaceEngine */; }};"
)
add("/* End PBXBuildFile section */")

# --- PBXFileReference -------------------------------------------------------
add("")
add("/* Begin PBXFileReference section */")
add(
    f"\t\t{PRODUCT_REF} /* {APP_NAME}.app */ = {{isa = PBXFileReference; "
    f"explicitFileType = wrapper.application; includeInIndex = 0; "
    f'path = "{APP_NAME}.app"; sourceTree = BUILT_PRODUCTS_DIR; }};'
)
for name, path, key in all_sources:
    add(
        f"\t\t{file_ref(key)} /* {name} */ = {{isa = PBXFileReference; "
        f"lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};"
    )
add("/* End PBXFileReference section */")

# --- PBXFrameworksBuildPhase ------------------------------------------------
add("")
add("/* Begin PBXFrameworksBuildPhase section */")
add(f"\t\t{FRAMEWORKS_PHASE} /* Frameworks */ = {{")
add("\t\t\tisa = PBXFrameworksBuildPhase;")
add("\t\t\tbuildActionMask = 2147483647;")
add("\t\t\tfiles = (")
add(f"\t\t\t\t{ENGINE_BUILD_FILE} /* RaceEngine in Frameworks */,")
add("\t\t\t);")
add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
add("\t\t};")
add("/* End PBXFrameworksBuildPhase section */")

# --- PBXGroup ---------------------------------------------------------------
add("")
add("/* Begin PBXGroup section */")

add(f"\t\t{MAIN_GROUP} = {{")
add("\t\t\tisa = PBXGroup;")
add("\t\t\tchildren = (")
add(f"\t\t\t\t{APP_GROUP} /* App */,")
add(f"\t\t\t\t{PRODUCTS_GROUP} /* Products */,")
add("\t\t\t);")
add("\t\t\tsourceTree = \"<group>\";")
add("\t\t};")

add(f"\t\t{APP_GROUP} /* App */ = {{")
add("\t\t\tisa = PBXGroup;")
add("\t\t\tchildren = (")
for name, _, key in [(n, p, k) for n, p, k in all_sources if k.count("/") == 1]:
    add(f"\t\t\t\t{file_ref(key)} /* {name} */,")
add(f"\t\t\t\t{VIEWS_GROUP} /* Views */,")
add("\t\t\t);")
add(f'\t\t\tname = App;')
add(f'\t\t\tpath = "{APP_GROUP_PATH}";')
add("\t\t\tsourceTree = \"<group>\";")
add("\t\t};")

add(f"\t\t{VIEWS_GROUP} /* Views */ = {{")
add("\t\t\tisa = PBXGroup;")
add("\t\t\tchildren = (")
for name, _, key in [(n, p, k) for n, p, k in all_sources if k.count("/") == 2]:
    add(f"\t\t\t\t{file_ref(key)} /* {name} */,")
add("\t\t\t);")
add("\t\t\tpath = Views;")
add("\t\t\tsourceTree = \"<group>\";")
add("\t\t};")

add(f"\t\t{PRODUCTS_GROUP} /* Products */ = {{")
add("\t\t\tisa = PBXGroup;")
add("\t\t\tchildren = (")
add(f"\t\t\t\t{PRODUCT_REF} /* {APP_NAME}.app */,")
add("\t\t\t);")
add("\t\t\tname = Products;")
add("\t\t\tsourceTree = \"<group>\";")
add("\t\t};")

add("/* End PBXGroup section */")

# --- PBXNativeTarget --------------------------------------------------------
add("")
add("/* Begin PBXNativeTarget section */")
add(f"\t\t{TARGET} /* {APP_NAME} */ = {{")
add("\t\t\tisa = PBXNativeTarget;")
add(f"\t\t\tbuildConfigurationList = {TARGET_CONFIG_LIST};")
add("\t\t\tbuildPhases = (")
add(f"\t\t\t\t{SOURCES_PHASE} /* Sources */,")
add(f"\t\t\t\t{FRAMEWORKS_PHASE} /* Frameworks */,")
add(f"\t\t\t\t{RESOURCES_PHASE} /* Resources */,")
add("\t\t\t);")
add("\t\t\tbuildRules = (")
add("\t\t\t);")
add("\t\t\tdependencies = (")
add("\t\t\t);")
add(f"\t\t\tname = {APP_NAME};")
add("\t\t\tpackageProductDependencies = (")
add(f"\t\t\t\t{ENGINE_DEPENDENCY} /* RaceEngine */,")
add("\t\t\t);")
add(f"\t\t\tproductName = {APP_NAME};")
add(f"\t\t\tproductReference = {PRODUCT_REF} /* {APP_NAME}.app */;")
add('\t\t\tproductType = "com.apple.product-type.application";')
add("\t\t};")
add("/* End PBXNativeTarget section */")

# --- PBXProject -------------------------------------------------------------
add("")
add("/* Begin PBXProject section */")
add(f"\t\t{PROJECT} /* Project object */ = {{")
add("\t\t\tisa = PBXProject;")
add("\t\t\tattributes = {")
add("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
add("\t\t\t\tLastSwiftUpdateCheck = 1520;")
add("\t\t\t\tLastUpgradeCheck = 1520;")
add("\t\t\t\tTargetAttributes = {")
add(f"\t\t\t\t\t{TARGET} = {{")
add("\t\t\t\t\t\tCreatedOnToolsVersion = 15.2;")
add("\t\t\t\t\t};")
add("\t\t\t\t};")
add("\t\t\t};")
add(f"\t\t\tbuildConfigurationList = {PROJECT_CONFIG_LIST};")
add('\t\t\tcompatibilityVersion = "Xcode 14.0";')
add("\t\t\tdevelopmentRegion = en;")
add("\t\t\thasScannedForEncodings = 0;")
add("\t\t\tknownRegions = (")
add("\t\t\t\ten,")
add("\t\t\t\tBase,")
add("\t\t\t);")
add(f"\t\t\tmainGroup = {MAIN_GROUP};")
add("\t\t\tpackageReferences = (")
add(f"\t\t\t\t{PACKAGE_REF} /* XCLocalSwiftPackageReference */,")
add("\t\t\t);")
add(f"\t\t\tproductRefGroup = {PRODUCTS_GROUP} /* Products */;")
add('\t\t\tprojectDirPath = "";')
add('\t\t\tprojectRoot = "";')
add("\t\t\ttargets = (")
add(f"\t\t\t\t{TARGET} /* {APP_NAME} */,")
add("\t\t\t);")
add("\t\t};")
add("/* End PBXProject section */")

# --- PBXResourcesBuildPhase -------------------------------------------------
add("")
add("/* Begin PBXResourcesBuildPhase section */")
add(f"\t\t{RESOURCES_PHASE} /* Resources */ = {{")
add("\t\t\tisa = PBXResourcesBuildPhase;")
add("\t\t\tbuildActionMask = 2147483647;")
add("\t\t\tfiles = (")
add("\t\t\t);")
add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
add("\t\t};")
add("/* End PBXResourcesBuildPhase section */")

# --- PBXSourcesBuildPhase ---------------------------------------------------
add("")
add("/* Begin PBXSourcesBuildPhase section */")
add(f"\t\t{SOURCES_PHASE} /* Sources */ = {{")
add("\t\t\tisa = PBXSourcesBuildPhase;")
add("\t\t\tbuildActionMask = 2147483647;")
add("\t\t\tfiles = (")
for name, _, key in all_sources:
    add(f"\t\t\t\t{build_file(key)} /* {name} in Sources */,")
add("\t\t\t);")
add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
add("\t\t};")
add("/* End PBXSourcesBuildPhase section */")

# --- XCBuildConfiguration ---------------------------------------------------
add("")
add("/* Begin XCBuildConfiguration section */")

for config_id, config_name, extra in [
    (PROJECT_DEBUG, "Debug", PROJECT_DEBUG_SETTINGS),
    (PROJECT_RELEASE, "Release", PROJECT_RELEASE_SETTINGS),
]:
    merged = dict(PROJECT_COMMON)
    merged.update(extra)
    add(f"\t\t{config_id} /* {config_name} */ = {{")
    add("\t\t\tisa = XCBuildConfiguration;")
    add("\t\t\tbuildSettings = {")
    add(settings_block(merged))
    add("\t\t\t};")
    add(f"\t\t\tname = {config_name};")
    add("\t\t};")

for config_id, config_name in [(TARGET_DEBUG, "Debug"), (TARGET_RELEASE, "Release")]:
    add(f"\t\t{config_id} /* {config_name} */ = {{")
    add("\t\t\tisa = XCBuildConfiguration;")
    add("\t\t\tbuildSettings = {")
    add(settings_block(TARGET_COMMON))
    add("\t\t\t};")
    add(f"\t\t\tname = {config_name};")
    add("\t\t};")

add("/* End XCBuildConfiguration section */")

# --- XCConfigurationList ----------------------------------------------------
add("")
add("/* Begin XCConfigurationList section */")
for list_id, label, debug_id, release_id in [
    (PROJECT_CONFIG_LIST, "PBXProject", PROJECT_DEBUG, PROJECT_RELEASE),
    (TARGET_CONFIG_LIST, "PBXNativeTarget", TARGET_DEBUG, TARGET_RELEASE),
]:
    add(f"\t\t{list_id} /* Build configuration list for {label} */ = {{")
    add("\t\t\tisa = XCConfigurationList;")
    add("\t\t\tbuildConfigurations = (")
    add(f"\t\t\t\t{debug_id} /* Debug */,")
    add(f"\t\t\t\t{release_id} /* Release */,")
    add("\t\t\t);")
    add("\t\t\tdefaultConfigurationIsVisible = 0;")
    add("\t\t\tdefaultConfigurationName = Release;")
    add("\t\t};")
add("/* End XCConfigurationList section */")

# --- XCLocalSwiftPackageReference -------------------------------------------
add("")
add("/* Begin XCLocalSwiftPackageReference section */")
add(f'\t\t{PACKAGE_REF} /* XCLocalSwiftPackageReference "{PACKAGE_RELATIVE_PATH}" */ = {{')
add("\t\t\tisa = XCLocalSwiftPackageReference;")
add(f'\t\t\trelativePath = "{PACKAGE_RELATIVE_PATH}";')
add("\t\t};")
add("/* End XCLocalSwiftPackageReference section */")

# --- XCSwiftPackageProductDependency ----------------------------------------
add("")
add("/* Begin XCSwiftPackageProductDependency section */")
add(f"\t\t{ENGINE_DEPENDENCY} /* RaceEngine */ = {{")
add("\t\t\tisa = XCSwiftPackageProductDependency;")
add("\t\t\tproductName = RaceEngine;")
add("\t\t};")
add("/* End XCSwiftPackageProductDependency section */")

add("\t};")
add(f"\trootObject = {PROJECT} /* Project object */;")
add("}")

pbxproj = "\n".join(lines) + "\n"

# ---------------------------------------------------------------------------
#  Schema und Arbeitsbereich
# ---------------------------------------------------------------------------

BUILDABLE = (
    '<BuildableReference\n'
    '               BuildableIdentifier = "primary"\n'
    f'               BlueprintIdentifier = "{TARGET}"\n'
    f'               BuildableName = "{APP_NAME}.app"\n'
    f'               BlueprintName = "{APP_NAME}"\n'
    f'               ReferencedContainer = "container:{APP_NAME}.xcodeproj">\n'
    '            </BuildableReference>'
)

scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1520"
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
            {BUILDABLE}
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
         {BUILDABLE}
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
         {BUILDABLE}
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

workspace = """<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
"""

# ---------------------------------------------------------------------------
#  Schreiben
# ---------------------------------------------------------------------------

schemes_dir = PROJECT_DIR / "xcshareddata" / "xcschemes"
workspace_dir = PROJECT_DIR / "project.xcworkspace"
schemes_dir.mkdir(parents=True, exist_ok=True)
workspace_dir.mkdir(parents=True, exist_ok=True)

(PROJECT_DIR / "project.pbxproj").write_text(pbxproj, encoding="utf-8")
(schemes_dir / f"{APP_NAME}.xcscheme").write_text(scheme, encoding="utf-8")
(workspace_dir / "contents.xcworkspacedata").write_text(workspace, encoding="utf-8")

print(f"{PROJECT_DIR.relative_to(ROOT)} geschrieben")
print(f"  {len(root_sources)} Dateien aus App/")
print(f"  {len(view_sources)} Dateien aus App/Views/")
print(f"  Paket: {PACKAGE_RELATIVE_PATH} (RaceEngine)")
