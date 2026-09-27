#!/usr/bin/env python3
"""
WebRTC SPM Injector for Janarym.xcodeproj
Adds stasel/WebRTC via Swift Package Manager
"""

import os

BASE = os.path.dirname(os.path.abspath(__file__))
PBXPROJ = os.path.join(BASE, "Janarym.xcodeproj/project.pbxproj")

PKG_REF      = "WR00001234567890ABCDEF01"
WEBRTC_DEP   = "WR00001234567890ABCDEF02"
WEBRTC_BUILD = "WR00001234567890ABCDEF03"

with open(PBXPROJ, "r", encoding="utf-8") as f:
    content = f.read()

if PKG_REF in content:
    print("✅ WebRTC SPM already present — nothing to do.")
    exit(0)

# 1. PBXBuildFile
content = content.replace(
    "/* End PBXBuildFile section */",
    (
        f"\t\t{WEBRTC_BUILD} /* WebRTC in Frameworks */ = {{isa = PBXBuildFile; productRef = {WEBRTC_DEP} /* WebRTC */; }};\n"
        "/* End PBXBuildFile section */"
    )
)

# 2. PBXFrameworksBuildPhase — add WebRTC
content = content.replace(
    f"\t\t\t\t{  'FB00001234567890ABCDEF07'  } /* FirebaseStorage in Frameworks */,",
    f"\t\t\t\tFB00001234567890ABCDEF07 /* FirebaseStorage in Frameworks */,\n"
    f"\t\t\t\t{WEBRTC_BUILD} /* WebRTC in Frameworks */,",
)

# Fallback: find Frameworks build phase files list
import re
def add_to_frameworks(text, entry):
    pattern = r'(files = \([^)]*)(FirebaseStorage in Frameworks \*/,)'
    replacement = r'\1FirebaseStorage in Frameworks */,\n\t\t\t\t\t' + entry
    return re.sub(pattern, replacement, text)

content = add_to_frameworks(content, f"{WEBRTC_BUILD} /* WebRTC in Frameworks */,")

# 3. packageProductDependencies in PBXNativeTarget
content = content.replace(
    f"\t\t\t\tFB00001234567890ABCDEF04 /* FirebaseStorage */,\n"
    f"\t\t\t);\n"
    f"\t\t\tproductName = Janarym;",
    (
        f"\t\t\t\tFB00001234567890ABCDEF04 /* FirebaseStorage */,\n"
        f"\t\t\t\t{WEBRTC_DEP} /* WebRTC */,\n"
        f"\t\t\t);\n"
        f"\t\t\tproductName = Janarym;"
    )
)

# 4. packageReferences in PBXProject
content = content.replace(
    f"\t\t\t\tFB00001234567890ABCDEF01 /* XCRemoteSwiftPackageReference \"firebase-ios-sdk\" */,\n"
    f"\t\t\t);\n"
    f"\t\t\tprojectDirPath",
    (
        f"\t\t\t\tFB00001234567890ABCDEF01 /* XCRemoteSwiftPackageReference \"firebase-ios-sdk\" */,\n"
        f"\t\t\t\t{PKG_REF} /* XCRemoteSwiftPackageReference \"WebRTC\" */,\n"
        f"\t\t\t);\n"
        f"\t\t\tprojectDirPath"
    )
)

# 5. XCRemoteSwiftPackageReference + XCSwiftPackageProductDependency
new_sections = (
    f"\t\t{PKG_REF} /* XCRemoteSwiftPackageReference \"WebRTC\" */ = {{\n"
    f"\t\t\tisa = XCRemoteSwiftPackageReference;\n"
    f"\t\t\trepositoryURL = \"https://github.com/stasel/WebRTC.git\";\n"
    f"\t\t\trequirement = {{\n"
    f"\t\t\t\tkind = upToNextMajorVersion;\n"
    f"\t\t\t\tminimumVersion = 125.0.0;\n"
    f"\t\t\t}};\n"
    f"\t\t}};\n"
    f"\t\t{WEBRTC_DEP} /* WebRTC */ = {{\n"
    f"\t\t\tisa = XCSwiftPackageProductDependency;\n"
    f"\t\t\tpackage = {PKG_REF} /* XCRemoteSwiftPackageReference \"WebRTC\" */;\n"
    f"\t\t\tproductName = WebRTC;\n"
    f"\t\t}};\n"
)

content = content.replace(
    "/* End XCRemoteSwiftPackageReference section */",
    new_sections + "/* End XCRemoteSwiftPackageReference section */"
)

with open(PBXPROJ, "w", encoding="utf-8") as f:
    f.write(content)

print("✅ WebRTC SPM successfully injected!")
print("   Package: stasel/WebRTC >= 125.0.0")
