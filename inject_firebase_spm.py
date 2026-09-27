#!/usr/bin/env python3
"""
Firebase SPM Injector for Janarym.xcodeproj
Adds FirebaseAuth, FirebaseFirestore, FirebaseStorage via Swift Package Manager
"""

import re

import os

BASE = os.path.dirname(os.path.abspath(__file__))
PBXPROJ = os.path.join(BASE, "Janarym.xcodeproj/project.pbxproj")

PKG_REF         = "FB00001234567890ABCDEF01"
AUTH_DEP        = "FB00001234567890ABCDEF02"
FIRESTORE_DEP   = "FB00001234567890ABCDEF03"
STORAGE_DEP     = "FB00001234567890ABCDEF04"
AUTH_BUILD      = "FB00001234567890ABCDEF05"
FIRESTORE_BUILD = "FB00001234567890ABCDEF06"
STORAGE_BUILD   = "FB00001234567890ABCDEF07"
AUTH_FILE_REF      = "FB00001234567890ABCDEF08"
FIRESTORE_FILE_REF = "FB00001234567890ABCDEF09"
STORAGE_FILE_REF   = "FB00001234567890ABCDEF10"
AUTH_SRC_BUILD     = "FB00001234567890ABCDEF11"
FIRESTORE_SRC_BUILD= "FB00001234567890ABCDEF12"
STORAGE_SRC_BUILD  = "FB00001234567890ABCDEF13"
FIREBASE_GROUP     = "FB00001234567890ABCDEF14"
GSERVICE_REF       = "FB00001234567890ABCDEF15"
GSERVICE_BUILD     = "FB00001234567890ABCDEF16"

with open(PBXPROJ, "r", encoding="utf-8") as f:
    content = f.read()

if PKG_REF in content:
    print("✅ Firebase SPM already present — nothing to do.")
    exit(0)

# 1. PBXBuildFile — Framework build files
content = content.replace(
    "/* End PBXBuildFile section */",
    (
        f"\t\t{AUTH_BUILD} /* FirebaseAuth in Frameworks */ = {{isa = PBXBuildFile; productRef = {AUTH_DEP} /* FirebaseAuth */; }};\n"
        f"\t\t{FIRESTORE_BUILD} /* FirebaseFirestore in Frameworks */ = {{isa = PBXBuildFile; productRef = {FIRESTORE_DEP} /* FirebaseFirestore */; }};\n"
        f"\t\t{STORAGE_BUILD} /* FirebaseStorage in Frameworks */ = {{isa = PBXBuildFile; productRef = {STORAGE_DEP} /* FirebaseStorage */; }};\n"
        f"\t\t{AUTH_SRC_BUILD} /* AuthService.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {AUTH_FILE_REF} /* AuthService.swift */; }};\n"
        f"\t\t{FIRESTORE_SRC_BUILD} /* FirestoreService.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {FIRESTORE_FILE_REF} /* FirestoreService.swift */; }};\n"
        f"\t\t{STORAGE_SRC_BUILD} /* StorageService.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {STORAGE_FILE_REF} /* StorageService.swift */; }};\n"
        f"\t\t{GSERVICE_BUILD} /* GoogleService-Info.plist in Resources */ = {{isa = PBXBuildFile; fileRef = {GSERVICE_REF} /* GoogleService-Info.plist */; }};\n"
        "/* End PBXBuildFile section */"
    )
)

# 2. PBXFileReference
content = content.replace(
    "/* End PBXFileReference section */",
    (
        f"\t\t{AUTH_FILE_REF} /* AuthService.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = AuthService.swift; path = mobile/Services/Firebase/AuthService.swift; sourceTree = SOURCE_ROOT; }};\n"
        f"\t\t{FIRESTORE_FILE_REF} /* FirestoreService.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = FirestoreService.swift; path = mobile/Services/Firebase/FirestoreService.swift; sourceTree = SOURCE_ROOT; }};\n"
        f"\t\t{STORAGE_FILE_REF} /* StorageService.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = StorageService.swift; path = mobile/Services/Firebase/StorageService.swift; sourceTree = SOURCE_ROOT; }};\n"
        f"\t\t{GSERVICE_REF} /* GoogleService-Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; name = \"GoogleService-Info.plist\"; path = \"mobile/App/GoogleService-Info.plist\"; sourceTree = SOURCE_ROOT; }};\n"
        "/* End PBXFileReference section */"
    )
)

# 3. PBXFrameworksBuildPhase — fill empty files list
content = content.replace(
    "\t\t\t\tfiles = (\n\t\t\t\t);\n\t\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t\t};\n/* End PBXFrameworksBuildPhase section */",
    (
        f"\t\t\t\tfiles = (\n"
        f"\t\t\t\t\t{AUTH_BUILD} /* FirebaseAuth in Frameworks */,\n"
        f"\t\t\t\t\t{FIRESTORE_BUILD} /* FirebaseFirestore in Frameworks */,\n"
        f"\t\t\t\t\t{STORAGE_BUILD} /* FirebaseStorage in Frameworks */,\n"
        f"\t\t\t\t);\n"
        f"\t\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t\t}};\n"
        "/* End PBXFrameworksBuildPhase section */"
    )
)

# 4. Firebase PBXGroup
content = content.replace(
    "/* End PBXGroup section */",
    (
        f"\t\t{FIREBASE_GROUP} /* Firebase */ = {{\n"
        f"\t\t\tisa = PBXGroup;\n"
        f"\t\t\tchildren = (\n"
        f"\t\t\t\t{AUTH_FILE_REF} /* AuthService.swift */,\n"
        f"\t\t\t\t{FIRESTORE_FILE_REF} /* FirestoreService.swift */,\n"
        f"\t\t\t\t{STORAGE_FILE_REF} /* StorageService.swift */,\n"
        f"\t\t\t);\n"
        f"\t\t\tpath = Firebase;\n"
        f"\t\t\tsourceTree = \"<group>\";\n"
        f"\t\t}};\n"
        "/* End PBXGroup section */"
    )
)

# 5. Add Firebase group to Services children
content = content.replace(
    "\t\t\t\tFDC7D01BE5224383A9F07A92 /* Speech */,\n"
    "\t\t\t\tSUB006FF00000006FF000006 /* Subscription */,",
    (
        f"\t\t\t\tFDC7D01BE5224383A9F07A92 /* Speech */,\n"
        f"\t\t\t\t{FIREBASE_GROUP} /* Firebase */,\n"
        f"\t\t\t\tSUB006FF00000006FF000006 /* Subscription */,"
    )
)

# 6. Add GoogleService-Info.plist to App group
content = content.replace(
    "\t\t\t\t913554885FF7475597B94D70 /* JanarymApp.swift */,",
    (
        f"\t\t\t\t913554885FF7475597B94D70 /* JanarymApp.swift */,\n"
        f"\t\t\t\t{GSERVICE_REF} /* GoogleService-Info.plist */,"
    )
)

# 7. PBXNativeTarget — add packageProductDependencies
content = content.replace(
    "\t\t\tdependencies = (\n\t\t\t);\n\t\t\tname = Janarym;\n\t\t\tproductName = Janarym;",
    (
        f"\t\t\tdependencies = (\n\t\t\t);\n"
        f"\t\t\tname = Janarym;\n"
        f"\t\t\tpackageProductDependencies = (\n"
        f"\t\t\t\t{AUTH_DEP} /* FirebaseAuth */,\n"
        f"\t\t\t\t{FIRESTORE_DEP} /* FirebaseFirestore */,\n"
        f"\t\t\t\t{STORAGE_DEP} /* FirebaseStorage */,\n"
        f"\t\t\t);\n"
        f"\t\t\tproductName = Janarym;"
    )
)

# 8. PBXProject — add packageReferences
content = content.replace(
    "\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n\t\t\ttargets = (",
    (
        f"\t\t\tpackageReferences = (\n"
        f"\t\t\t\t{PKG_REF} /* XCRemoteSwiftPackageReference \"firebase-ios-sdk\" */,\n"
        f"\t\t\t);\n"
        f"\t\t\tprojectDirPath = \"\";\n"
        f"\t\t\tprojectRoot = \"\";\n"
        f"\t\t\ttargets = ("
    )
)

# 9. Add to Sources build phase
content = content.replace(
    "\t\t\t\t69CF0799AC9D4A7A995C0855 /* SpeechSynthesizerService.swift in Sources */,",
    (
        f"\t\t\t\t69CF0799AC9D4A7A995C0855 /* SpeechSynthesizerService.swift in Sources */,\n"
        f"\t\t\t\t{AUTH_SRC_BUILD} /* AuthService.swift in Sources */,\n"
        f"\t\t\t\t{FIRESTORE_SRC_BUILD} /* FirestoreService.swift in Sources */,\n"
        f"\t\t\t\t{STORAGE_SRC_BUILD} /* StorageService.swift in Sources */,"
    )
)

# 10. Add to Resources build phase
content = content.replace(
    "\t\t\t\tB6331FEA89B14983A0C1175A /* Secrets.plist in Resources */,",
    (
        f"\t\t\t\tB6331FEA89B14983A0C1175A /* Secrets.plist in Resources */,\n"
        f"\t\t\t\t{GSERVICE_BUILD} /* GoogleService-Info.plist in Resources */,"
    )
)

# 11. XCRemoteSwiftPackageReference + XCSwiftPackageProductDependency sections
new_spm_sections = (
    "/* Begin XCRemoteSwiftPackageReference section */\n"
    f"\t\t{PKG_REF} /* XCRemoteSwiftPackageReference \"firebase-ios-sdk\" */ = {{\n"
    f"\t\t\tisa = XCRemoteSwiftPackageReference;\n"
    f"\t\t\trepositoryURL = \"https://github.com/firebase/firebase-ios-sdk\";\n"
    f"\t\t\trequirement = {{\n"
    f"\t\t\t\tkind = upToNextMajorVersion;\n"
    f"\t\t\t\tminimumVersion = 11.0.0;\n"
    f"\t\t\t}};\n"
    f"\t\t}};\n"
    "/* End XCRemoteSwiftPackageReference section */\n\n"
    "/* Begin XCSwiftPackageProductDependency section */\n"
    f"\t\t{AUTH_DEP} /* FirebaseAuth */ = {{\n"
    f"\t\t\tisa = XCSwiftPackageProductDependency;\n"
    f"\t\t\tpackage = {PKG_REF} /* XCRemoteSwiftPackageReference \"firebase-ios-sdk\" */;\n"
    f"\t\t\tproductName = FirebaseAuth;\n"
    f"\t\t}};\n"
    f"\t\t{FIRESTORE_DEP} /* FirebaseFirestore */ = {{\n"
    f"\t\t\tisa = XCSwiftPackageProductDependency;\n"
    f"\t\t\tpackage = {PKG_REF} /* XCRemoteSwiftPackageReference \"firebase-ios-sdk\" */;\n"
    f"\t\t\tproductName = FirebaseFirestore;\n"
    f"\t\t}};\n"
    f"\t\t{STORAGE_DEP} /* FirebaseStorage */ = {{\n"
    f"\t\t\tisa = XCSwiftPackageProductDependency;\n"
    f"\t\t\tpackage = {PKG_REF} /* XCRemoteSwiftPackageReference \"firebase-ios-sdk\" */;\n"
    f"\t\t\tproductName = FirebaseStorage;\n"
    f"\t\t}};\n"
    "/* End XCSwiftPackageProductDependency section */\n\n"
)
content = content.replace(
    "/* Begin XCConfigurationList section */",
    new_spm_sections + "/* Begin XCConfigurationList section */"
)

with open(PBXPROJ, "w", encoding="utf-8") as f:
    f.write(content)

print("✅ Firebase SPM successfully injected into Janarym.xcodeproj!")
print("   Packages: FirebaseAuth, FirebaseFirestore, FirebaseStorage")
print("   Files: AuthService.swift, FirestoreService.swift, StorageService.swift")
print("   Resources: GoogleService-Info.plist")
