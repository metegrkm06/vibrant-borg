#!/usr/bin/env python3
"""
Generates a minimal iOSVideoPlayer.xcodeproj/project.pbxproj
suitable for xcodebuild without needing XcodeGen.
Run from the repo root.
"""
import os, uuid, textwrap

def make_id():
    return uuid.uuid4().hex[:24].upper()

# Collect all Swift sources
sources_dir = "iOSVideoPlayer"
swift_files = []
for root, dirs, files in os.walk(sources_dir):
    for f in files:
        if f.endswith(".swift"):
            rel = os.path.relpath(os.path.join(root, f)).replace("\\", "/")
            swift_files.append((f, rel))

# Generate UUIDs
PROJECT_ID     = make_id()
TARGET_ID      = make_id()
GROUP_ID       = make_id()
BUILD_FILE_IDS = [make_id() for _ in swift_files]
FILE_REF_IDS   = [make_id() for _ in swift_files]
SOURCES_PHASE  = make_id()
FRAMEWORKS_PHASE = make_id()
RESOURCES_PHASE  = make_id()
PLIST_REF_ID   = make_id()
CONFIG_LIST_PROJ = make_id()
CONFIG_LIST_TGT  = make_id()
CONFIG_DEBUG_PROJ = make_id()
CONFIG_REL_PROJ   = make_id()
CONFIG_DEBUG_TGT  = make_id()
CONFIG_REL_TGT    = make_id()

# Build file section
build_files = "\n".join(
    f"\t\t{bid} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {name} */; }};"
    for (name, _), bid, fid in zip(swift_files, BUILD_FILE_IDS, FILE_REF_IDS)
)

# File reference section
file_refs = "\n".join(
    f"\t\t{fid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"{name}\"; sourceTree = \"<group>\"; }};"
    for (name, _), fid in zip(swift_files, FILE_REF_IDS)
)

# Info.plist ref
plist_ref = f'\t\t{PLIST_REF_ID} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};'

# Group children - file ref IDs
children = "\n".join(f"\t\t\t\t{fid} /* {name} */," for (name, _), fid in zip(swift_files, FILE_REF_IDS))
children += f"\n\t\t\t\t{PLIST_REF_ID} /* Info.plist */,"

# Sources build phase
sources_build = "\n".join(
    f"\t\t\t\t{bid} /* {name} in Sources */,"
    for (name, _), bid in zip(swift_files, BUILD_FILE_IDS)
)

pbxproj = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{build_files}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{file_refs}
{plist_ref}
\t\t{TARGET_ID}PRODUCT /* iOSVideoPlayer.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = iOSVideoPlayer.app; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{FRAMEWORKS_PHASE} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{GROUP_ID} /* iOSVideoPlayer */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{children}
\t\t\t);
\t\t\tpath = iOSVideoPlayer;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{PROJECT_ID}MAINGROUP /* = */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{GROUP_ID} /* iOSVideoPlayer */,
\t\t\t\t{TARGET_ID}PRODUCT /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{TARGET_ID}PRODUCT /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{TARGET_ID}PRODUCT /* iOSVideoPlayer.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{TARGET_ID} /* iOSVideoPlayer */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {CONFIG_LIST_TGT} /* Build configuration list for PBXNativeTarget "iOSVideoPlayer" */;
\t\t\tbuildPhases = (
\t\t\t\t{SOURCES_PHASE} /* Sources */,
\t\t\t\t{FRAMEWORKS_PHASE} /* Frameworks */,
\t\t\t\t{RESOURCES_PHASE} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = iOSVideoPlayer;
\t\t\tproductName = iOSVideoPlayer;
\t\t\tproductReference = {TARGET_ID}PRODUCT /* iOSVideoPlayer.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{PROJECT_ID} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tLastSwiftUpdateCheck = 1500;
\t\t\t\tLastUpgradeCheck = 1500;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{TARGET_ID} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {CONFIG_LIST_PROJ} /* Build configuration list for PBXProject */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {PROJECT_ID}MAINGROUP;
\t\t\tproductRefGroup = {TARGET_ID}PRODUCT /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{TARGET_ID} /* iOSVideoPlayer */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{RESOURCES_PHASE} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{SOURCES_PHASE} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{sources_build}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
\t\t{CONFIG_DEBUG_PROJ} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_VERSION = 5.9;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{CONFIG_REL_PROJ} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_VERSION = 5.9;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{CONFIG_DEBUG_TGT} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_IDENTITY = "-";
\t\t\t\tCODE_SIGNING_ALLOWED = YES;
\t\t\t\tCODE_SIGNING_REQUIRED = YES;
\t\t\t\tAD_HOC_CODE_SIGNING_ALLOWED = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 15.0;
\t\t\t\tINFOPLIST_FILE = iOSVideoPlayer/Info.plist;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "com.vibrantborg.iosvideoplayer";
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_VERSION = 5.9;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{CONFIG_REL_TGT} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_IDENTITY = "-";
\t\t\t\tCODE_SIGNING_ALLOWED = YES;
\t\t\t\tCODE_SIGNING_REQUIRED = YES;
\t\t\t\tAD_HOC_CODE_SIGNING_ALLOWED = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 15.0;
\t\t\t\tINFOPLIST_FILE = iOSVideoPlayer/Info.plist;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "com.vibrantborg.iosvideoplayer";
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_VERSION = 5.9;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{CONFIG_LIST_PROJ} /* Build configuration list for PBXProject */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{CONFIG_DEBUG_PROJ} /* Debug */,
\t\t\t\t{CONFIG_REL_PROJ} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{CONFIG_LIST_TGT} /* Build configuration list for PBXNativeTarget "iOSVideoPlayer" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{CONFIG_DEBUG_TGT} /* Debug */,
\t\t\t\t{CONFIG_REL_TGT} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */

\t}};
\trootObject = {PROJECT_ID} /* Project object */;
}}
"""

os.makedirs("iOSVideoPlayer.xcodeproj", exist_ok=True)
with open("iOSVideoPlayer.xcodeproj/project.pbxproj", "w") as f:
    f.write(pbxproj)

print(f"Generated project with {len(swift_files)} Swift sources:")
for name, path in swift_files:
    print(f"  {path}")
