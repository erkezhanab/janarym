#!/usr/bin/env python3
"""Generate Janarym.xcodeproj for the SwiftUI iOS app."""

from __future__ import annotations

import hashlib
import os
from pathlib import Path

BASE = Path(__file__).resolve().parent
PROJ_DIR = BASE / "Janarym.xcodeproj"
PBXPROJ = PROJ_DIR / "project.pbxproj"

PRODUCT_NAME = "Janarym"
BUNDLE_ID = "com.example.Janarym-A"
DEVELOPMENT_TEAM = "DDAR3RG3X4"
DEPLOYMENT_TARGET = "16.0"


def uid(seed: str) -> str:
    return hashlib.sha1(seed.encode("utf-8")).hexdigest()[:24].upper()


def q(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def all_files(root: Path, suffixes: tuple[str, ...]) -> list[Path]:
    return sorted(
        path
        for path in root.rglob("*")
        if path.is_file() and path.suffix in suffixes
    )


PROJ_DIR.mkdir(exist_ok=True)

swift_files = all_files(BASE / "mobile", (".swift",))
swift_files = [
    path for path in swift_files
    if path.relative_to(BASE).as_posix() != "mobile/Features/Dashboard/MentorDashboardView.swift"
]
resource_files = [
    BASE / "mobile/Resources/Assets.xcassets",
    BASE / "mobile/Resources/Secrets.plist",
    BASE / "mobile/Resources/Secrets.example.plist",
    BASE / "mobile/Resources/Janarym.storekit",
]
google_service = BASE / "mobile/App/GoogleService-Info.plist"
if google_service.exists():
    resource_files.append(google_service)
resource_files = [path for path in resource_files if path.exists()]

PROJECT = uid("project")
TARGET = uid("target")
MAIN_GROUP = uid("main-group")
PRODUCTS_GROUP = uid("products-group")
SOURCES_PHASE = uid("sources-phase")
RESOURCES_PHASE = uid("resources-phase")
FRAMEWORKS_PHASE = uid("frameworks-phase")
PRODUCT_REF = uid("product-ref")
PROJ_CONFIG_LIST = uid("project-config-list")
TARGET_CONFIG_LIST = uid("target-config-list")
PROJ_DEBUG = uid("project-debug")
PROJ_RELEASE = uid("project-release")
TARGET_DEBUG = uid("target-debug")
TARGET_RELEASE = uid("target-release")
FIREBASE_PKG = uid("firebase-package")
FIREBASE_CORE = uid("firebase-core")
FIREBASE_AUTH = uid("firebase-auth")
FIREBASE_FIRESTORE = uid("firebase-firestore")
FIREBASE_STORAGE = uid("firebase-storage")
FIREBASE_CORE_BUILD = uid("firebase-core-build")
FIREBASE_AUTH_BUILD = uid("firebase-auth-build")
FIREBASE_FIRESTORE_BUILD = uid("firebase-firestore-build")
FIREBASE_STORAGE_BUILD = uid("firebase-storage-build")

source_entries = []
for path in swift_files:
    rel = path.relative_to(BASE).as_posix()
    source_entries.append(
        {
            "name": path.name,
            "path": rel,
            "file": uid(f"file:{rel}"),
            "build": uid(f"build:{rel}"),
        }
    )

resource_entries = []
for path in resource_files:
    rel = path.relative_to(BASE).as_posix()
    resource_entries.append(
        {
            "name": path.name,
            "path": rel,
            "file": uid(f"file:{rel}"),
            "build": uid(f"build:{rel}"),
            "type": "folder.assetcatalog" if path.suffix == ".xcassets" else "file",
        }
    )


lines: list[str] = []


def L(line: str = "") -> None:
    lines.append(line)


L("// !$*UTF8*$!")
L("{")
L("\tarchiveVersion = 1;")
L("\tclasses = {")
L("\t};")
L("\tobjectVersion = 56;")
L("\tobjects = {")
L()

L("/* Begin PBXBuildFile section */")
for entry in source_entries:
    L(f"\t\t{entry['build']} /* {entry['name']} in Sources */ = {{isa = PBXBuildFile; fileRef = {entry['file']} /* {entry['name']} */; }};")
for entry in resource_entries:
    L(f"\t\t{entry['build']} /* {entry['name']} in Resources */ = {{isa = PBXBuildFile; fileRef = {entry['file']} /* {entry['name']} */; }};")
L(f"\t\t{FIREBASE_CORE_BUILD} /* FirebaseCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {FIREBASE_CORE} /* FirebaseCore */; }};")
L(f"\t\t{FIREBASE_AUTH_BUILD} /* FirebaseAuth in Frameworks */ = {{isa = PBXBuildFile; productRef = {FIREBASE_AUTH} /* FirebaseAuth */; }};")
L(f"\t\t{FIREBASE_FIRESTORE_BUILD} /* FirebaseFirestore in Frameworks */ = {{isa = PBXBuildFile; productRef = {FIREBASE_FIRESTORE} /* FirebaseFirestore */; }};")
L(f"\t\t{FIREBASE_STORAGE_BUILD} /* FirebaseStorage in Frameworks */ = {{isa = PBXBuildFile; productRef = {FIREBASE_STORAGE} /* FirebaseStorage */; }};")
L("/* End PBXBuildFile section */")
L()

L("/* Begin PBXFileReference section */")
L(f"\t\t{PRODUCT_REF} /* {PRODUCT_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {PRODUCT_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
for entry in source_entries:
    L(f"\t\t{entry['file']} /* {entry['name']} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = {q(entry['name'])}; path = {q(entry['path'])}; sourceTree = SOURCE_ROOT; }};")
for entry in resource_entries:
    kind = "folder.assetcatalog" if entry["type"] == "folder.assetcatalog" else "text.plist.xml"
    if entry["name"].endswith(".storekit"):
        kind = "text"
    L(f"\t\t{entry['file']} /* {entry['name']} */ = {{isa = PBXFileReference; lastKnownFileType = {kind}; name = {q(entry['name'])}; path = {q(entry['path'])}; sourceTree = SOURCE_ROOT; }};")
L("/* End PBXFileReference section */")
L()

L("/* Begin PBXFrameworksBuildPhase section */")
L(f"\t\t{FRAMEWORKS_PHASE} /* Frameworks */ = {{")
L("\t\t\tisa = PBXFrameworksBuildPhase;")
L("\t\t\tbuildActionMask = 2147483647;")
L("\t\t\tfiles = (")
for build, name in (
    (FIREBASE_CORE_BUILD, "FirebaseCore"),
    (FIREBASE_AUTH_BUILD, "FirebaseAuth"),
    (FIREBASE_FIRESTORE_BUILD, "FirebaseFirestore"),
    (FIREBASE_STORAGE_BUILD, "FirebaseStorage"),
):
    L(f"\t\t\t\t{build} /* {name} in Frameworks */,")
L("\t\t\t);")
L("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
L("\t\t};")
L("/* End PBXFrameworksBuildPhase section */")
L()

L("/* Begin PBXGroup section */")
L(f"\t\t{MAIN_GROUP} = {{")
L("\t\t\tisa = PBXGroup;")
L("\t\t\tchildren = (")
for entry in source_entries + resource_entries:
    L(f"\t\t\t\t{entry['file']} /* {entry['name']} */,")
L(f"\t\t\t\t{PRODUCTS_GROUP} /* Products */,")
L("\t\t\t);")
L("\t\t\tsourceTree = \"<group>\";")
L("\t\t};")
L(f"\t\t{PRODUCTS_GROUP} /* Products */ = {{")
L("\t\t\tisa = PBXGroup;")
L("\t\t\tchildren = (")
L(f"\t\t\t\t{PRODUCT_REF} /* {PRODUCT_NAME}.app */,")
L("\t\t\t);")
L("\t\t\tname = Products;")
L("\t\t\tsourceTree = \"<group>\";")
L("\t\t};")
L("/* End PBXGroup section */")
L()

L("/* Begin PBXNativeTarget section */")
L(f"\t\t{TARGET} /* {PRODUCT_NAME} */ = {{")
L("\t\t\tisa = PBXNativeTarget;")
L(f"\t\t\tbuildConfigurationList = {TARGET_CONFIG_LIST} /* Build configuration list for PBXNativeTarget \"{PRODUCT_NAME}\" */;")
L("\t\t\tbuildPhases = (")
L(f"\t\t\t\t{SOURCES_PHASE} /* Sources */,")
L(f"\t\t\t\t{RESOURCES_PHASE} /* Resources */,")
L(f"\t\t\t\t{FRAMEWORKS_PHASE} /* Frameworks */,")
L("\t\t\t);")
L("\t\t\tbuildRules = (")
L("\t\t\t);")
L("\t\t\tdependencies = (")
L("\t\t\t);")
L(f"\t\t\tname = {PRODUCT_NAME};")
L("\t\t\tpackageProductDependencies = (")
for dep, name in (
    (FIREBASE_CORE, "FirebaseCore"),
    (FIREBASE_AUTH, "FirebaseAuth"),
    (FIREBASE_FIRESTORE, "FirebaseFirestore"),
    (FIREBASE_STORAGE, "FirebaseStorage"),
):
    L(f"\t\t\t\t{dep} /* {name} */,")
L("\t\t\t);")
L(f"\t\t\tproductName = {PRODUCT_NAME};")
L(f"\t\t\tproductReference = {PRODUCT_REF} /* {PRODUCT_NAME}.app */;")
L("\t\t\tproductType = \"com.apple.product-type.application\";")
L("\t\t};")
L("/* End PBXNativeTarget section */")
L()

L("/* Begin PBXProject section */")
L(f"\t\t{PROJECT} /* Project object */ = {{")
L("\t\t\tisa = PBXProject;")
L("\t\t\tattributes = {")
L("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
L("\t\t\t\tLastSwiftUpdateCheck = 1500;")
L("\t\t\t\tLastUpgradeCheck = 1500;")
L("\t\t\t\tTargetAttributes = {")
L(f"\t\t\t\t\t{TARGET} = {{")
L("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
L("\t\t\t\t\t};")
L("\t\t\t\t};")
L("\t\t\t};")
L(f"\t\t\tbuildConfigurationList = {PROJ_CONFIG_LIST} /* Build configuration list for PBXProject \"{PRODUCT_NAME}\" */;")
L("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
L("\t\t\tdevelopmentRegion = en;")
L("\t\t\thasScannedForEncodings = 0;")
L("\t\t\tknownRegions = (")
L("\t\t\t\ten,")
L("\t\t\t\tBase,")
L("\t\t\t);")
L(f"\t\t\tmainGroup = {MAIN_GROUP};")
L("\t\t\tpackageReferences = (")
L(f"\t\t\t\t{FIREBASE_PKG} /* XCRemoteSwiftPackageReference \"firebase-ios-sdk\" */,")
L("\t\t\t);")
L(f"\t\t\tproductRefGroup = {PRODUCTS_GROUP} /* Products */;")
L("\t\t\tprojectDirPath = \"\";")
L("\t\t\tprojectRoot = \"\";")
L("\t\t\ttargets = (")
L(f"\t\t\t\t{TARGET} /* {PRODUCT_NAME} */,")
L("\t\t\t);")
L("\t\t};")
L("/* End PBXProject section */")
L()

L("/* Begin PBXResourcesBuildPhase section */")
L(f"\t\t{RESOURCES_PHASE} /* Resources */ = {{")
L("\t\t\tisa = PBXResourcesBuildPhase;")
L("\t\t\tbuildActionMask = 2147483647;")
L("\t\t\tfiles = (")
for entry in resource_entries:
    L(f"\t\t\t\t{entry['build']} /* {entry['name']} in Resources */,")
L("\t\t\t);")
L("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
L("\t\t};")
L("/* End PBXResourcesBuildPhase section */")
L()

L("/* Begin PBXSourcesBuildPhase section */")
L(f"\t\t{SOURCES_PHASE} /* Sources */ = {{")
L("\t\t\tisa = PBXSourcesBuildPhase;")
L("\t\t\tbuildActionMask = 2147483647;")
L("\t\t\tfiles = (")
for entry in source_entries:
    L(f"\t\t\t\t{entry['build']} /* {entry['name']} in Sources */,")
L("\t\t\t);")
L("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
L("\t\t};")
L("/* End PBXSourcesBuildPhase section */")
L()

common_project_settings = f"""
\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\tDEVELOPMENT_TEAM = {DEVELOPMENT_TEAM};
\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};
\t\t\tSDKROOT = iphoneos;
\t\t\tSWIFT_VERSION = 5.0;""".strip()

common_target_settings = f"""
\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\tDEVELOPMENT_TEAM = {DEVELOPMENT_TEAM};
\t\t\tENABLE_PREVIEWS = YES;
\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\tINFOPLIST_FILE = mobile/Resources/Info.plist;
\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};
\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\"$(inherited)\",
\t\t\t\t\"@executable_path/Frameworks\",
\t\t\t);
\t\t\tMARKETING_VERSION = 1.0;
\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};
\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";
\t\t\tSUPPORTED_PLATFORMS = iphoneos;
\t\t\tSUPPORTS_MACCATALYST = NO;
\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\tSWIFT_VERSION = 5.0;
\t\t\tTARGETED_DEVICE_FAMILY = 1;""".strip()

L("/* Begin XCBuildConfiguration section */")
for config_id, name, extra in (
    (PROJ_DEBUG, "Debug", "\n\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;\n\t\t\tENABLE_TESTABILITY = YES;\n\t\t\tONLY_ACTIVE_ARCH = YES;\n\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;\n\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";"),
    (PROJ_RELEASE, "Release", "\n\t\t\tDEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";\n\t\t\tSWIFT_COMPILATION_MODE = wholemodule;\n\t\t\tVALIDATE_PRODUCT = YES;"),
):
    L(f"\t\t{config_id} /* {name} */ = {{")
    L("\t\t\tisa = XCBuildConfiguration;")
    L("\t\t\tbuildSettings = {")
    L(common_project_settings)
    L(extra.rstrip())
    L("\t\t\t};")
    L(f"\t\t\tname = {name};")
    L("\t\t};")
for config_id, name, extra in (
    (TARGET_DEBUG, "Debug", "\n\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";"),
    (TARGET_RELEASE, "Release", ""),
):
    L(f"\t\t{config_id} /* {name} */ = {{")
    L("\t\t\tisa = XCBuildConfiguration;")
    L("\t\t\tbuildSettings = {")
    L(common_target_settings)
    if extra:
        L(extra.rstrip())
    L("\t\t\t};")
    L(f"\t\t\tname = {name};")
    L("\t\t};")
L("/* End XCBuildConfiguration section */")
L()

L("/* Begin XCConfigurationList section */")
for list_id, owner, debug_id, release_id in (
    (PROJ_CONFIG_LIST, f'PBXProject "{PRODUCT_NAME}"', PROJ_DEBUG, PROJ_RELEASE),
    (TARGET_CONFIG_LIST, f'PBXNativeTarget "{PRODUCT_NAME}"', TARGET_DEBUG, TARGET_RELEASE),
):
    L(f"\t\t{list_id} /* Build configuration list for {owner} */ = {{")
    L("\t\t\tisa = XCConfigurationList;")
    L("\t\t\tbuildConfigurations = (")
    L(f"\t\t\t\t{debug_id} /* Debug */,")
    L(f"\t\t\t\t{release_id} /* Release */,")
    L("\t\t\t);")
    L("\t\t\tdefaultConfigurationIsVisible = 0;")
    L("\t\t\tdefaultConfigurationName = Release;")
    L("\t\t};")
L("/* End XCConfigurationList section */")
L()

L("/* Begin XCRemoteSwiftPackageReference section */")
L(f"\t\t{FIREBASE_PKG} /* XCRemoteSwiftPackageReference \"firebase-ios-sdk\" */ = {{")
L("\t\t\tisa = XCRemoteSwiftPackageReference;")
L("\t\t\trepositoryURL = \"https://github.com/firebase/firebase-ios-sdk\";")
L("\t\t\trequirement = {")
L("\t\t\t\tkind = upToNextMajorVersion;")
L("\t\t\t\tminimumVersion = 11.0.0;")
L("\t\t\t};")
L("\t\t};")
L("/* End XCRemoteSwiftPackageReference section */")
L()

L("/* Begin XCSwiftPackageProductDependency section */")
for dep, product in (
    (FIREBASE_CORE, "FirebaseCore"),
    (FIREBASE_AUTH, "FirebaseAuth"),
    (FIREBASE_FIRESTORE, "FirebaseFirestore"),
    (FIREBASE_STORAGE, "FirebaseStorage"),
):
    L(f"\t\t{dep} /* {product} */ = {{")
    L("\t\t\tisa = XCSwiftPackageProductDependency;")
    L(f"\t\t\tpackage = {FIREBASE_PKG} /* XCRemoteSwiftPackageReference \"firebase-ios-sdk\" */;")
    L(f"\t\t\tproductName = {product};")
    L("\t\t};")
L("/* End XCSwiftPackageProductDependency section */")
L()

L("\t};")
L(f"\trootObject = {PROJECT} /* Project object */;")
L("}")

PBXPROJ.write_text("\n".join(lines), encoding="utf-8")

print(f"Created: {PBXPROJ}")
print(f"Swift files: {len(source_entries)}")
print(f"Resources: {len(resource_entries)}")
