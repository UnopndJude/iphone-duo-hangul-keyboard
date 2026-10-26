#!/usr/bin/env python3
"""Regenerate a dependency-free, deterministic Xcode project from local Swift files."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT / "ThreePad.xcodeproj"
objects = {}


def ident(value):
    return hashlib.sha256(value.encode()).hexdigest()[:24].upper()


def add(key, isa, **fields):
    reference = ident(key)
    objects[reference] = {"isa": isa, **fields}
    return reference


def serialize(value, level=0):
    prefix = "\t" * level
    if isinstance(value, dict):
        return "{\n" + "".join(
            f'{prefix}\t{serialize(k)} = {serialize(v, level + 1)};\n'
            for k, v in value.items()
        ) + prefix + "}"
    if isinstance(value, list):
        return "(\n" + "".join(f'{prefix}\t{serialize(v, level + 1)},\n' for v in value) + prefix + ")"
    return json.dumps(str(value), ensure_ascii=False)


def sources(directory):
    return sorted(str(p.relative_to(ROOT)) for p in (ROOT / directory).rglob("*.swift"))


shared_sources = sources("Core") + sources("SharedUI")
app_sources = sources("App") + shared_sources
extension_sources = sources("KeyboardExtension") + sources("DocumentBridge") + shared_sources
files = {}
paths = sorted(set(app_sources + extension_sources + [
    "App/Info.plist", "App/PrivacyInfo.xcprivacy", "KeyboardExtension/Info.plist", "Config/Shared.xcconfig"
]))
for path in paths:
    suffix = Path(path).suffix
    kind = {".swift": "sourcecode.swift", ".plist": "text.plist.xml", ".xcprivacy": "text.xml", ".xcconfig": "text.xcconfig"}[suffix]
    files[path] = add("file:" + path, "PBXFileReference", lastKnownFileType=kind, path=path, sourceTree="<group>")

products = {}
for target, suffix, kind in [
    ("ThreePad", ".app", "wrapper.application"),
    ("ThreePadKeyboard", ".appex", "wrapper.app-extension")
]:
    products[target] = add("product:" + target, "PBXFileReference", explicitFileType=kind,
                           includeInIndex=0, path=target + suffix, sourceTree="BUILT_PRODUCTS_DIR")

groups = []
for directory in ["App", "Core", "SharedUI", "DocumentBridge", "KeyboardExtension", "Config"]:
    children = [files[path] for path in paths if path.startswith(directory + "/")]
    groups.append(add("group:" + directory, "PBXGroup", children=children, name=directory, sourceTree="<group>"))
product_group = add("group:Products", "PBXGroup", children=list(products.values()), name="Products", sourceTree="<group>")
main_group = add("group:main", "PBXGroup", children=groups + [product_group], sourceTree="<group>")


def configuration_list(owner, settings):
    configs = []
    for configuration in ["Debug", "Release"]:
        values = dict(settings)
        if owner == "project":
            values.update({
                "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if configuration == "Debug" else "-O",
                "DEBUG_INFORMATION_FORMAT": "dwarf" if configuration == "Debug" else "dwarf-with-dsym",
                "ENABLE_TESTABILITY": "YES" if configuration == "Debug" else "NO",
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) DEBUG" if configuration == "Debug" else "$(inherited)",
                "GCC_PREPROCESSOR_DEFINITIONS": ["$(inherited)", "DEBUG=1"] if configuration == "Debug" else ["$(inherited)"]
            })
        configs.append(add(f"config:{owner}:{configuration}", "XCBuildConfiguration",
                           baseConfigurationReference=files["Config/Shared.xcconfig"],
                           buildSettings=values, name=configuration))
    return add("configs:" + owner, "XCConfigurationList", buildConfigurations=configs,
               defaultConfigurationIsVisible=0, defaultConfigurationName="Release")


def source_phase(target, source_paths):
    build_files = [add(f"build:{target}:{path}", "PBXBuildFile", fileRef=files[path]) for path in source_paths]
    return add("sources:" + target, "PBXSourcesBuildPhase", buildActionMask=2147483647,
               files=build_files, runOnlyForDeploymentPostprocessing=0)


def resource_phase(target):
    privacy = add("privacy:" + target, "PBXBuildFile", fileRef=files["App/PrivacyInfo.xcprivacy"])
    return add("resources:" + target, "PBXResourcesBuildPhase", buildActionMask=2147483647,
               files=[privacy], runOnlyForDeploymentPostprocessing=0)


def dependency(owner, target):
    proxy = add(f"proxy:{owner}:{target}", "PBXContainerItemProxy", containerPortal=ident("project"),
                proxyType=1, remoteGlobalIDString=ident("target:" + target), remoteInfo=target)
    return add(f"dependency:{owner}:{target}", "PBXTargetDependency", target=ident("target:" + target), targetProxy=proxy)


extension = add("target:ThreePadKeyboard", "PBXNativeTarget",
    buildConfigurationList=configuration_list("ThreePadKeyboard", {
        "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "$(BUNDLE_ID_PREFIX).Keyboard",
        "INFOPLIST_FILE": "KeyboardExtension/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
        "APPLICATION_EXTENSION_API_ONLY": "YES", "SKIP_INSTALL": "YES",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"]
    }),
    buildPhases=[source_phase("ThreePadKeyboard", extension_sources), resource_phase("ThreePadKeyboard")],
    buildRules=[], dependencies=[], name="ThreePadKeyboard", productName="ThreePadKeyboard",
    productReference=products["ThreePadKeyboard"], productType="com.apple.product-type.app-extension")

embedded = add("embed:extension", "PBXBuildFile", fileRef=products["ThreePadKeyboard"],
               settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
embed_phase = add("phase:embed", "PBXCopyFilesBuildPhase", buildActionMask=2147483647, dstPath="",
                 dstSubfolderSpec=13, files=[embedded], name="Embed App Extensions", runOnlyForDeploymentPostprocessing=0)

app = add("target:ThreePad", "PBXNativeTarget",
    buildConfigurationList=configuration_list("ThreePad", {
        "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "$(BUNDLE_ID_PREFIX)",
        "INFOPLIST_FILE": "App/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"], "SKIP_INSTALL": "NO"
    }),
    buildPhases=[source_phase("ThreePad", app_sources), resource_phase("ThreePad"), embed_phase],
    buildRules=[], dependencies=[dependency("ThreePad", "ThreePadKeyboard")], name="ThreePad", productName="ThreePad",
    productReference=products["ThreePad"], productType="com.apple.product-type.application")

project = add("project", "PBXProject",
    attributes={"BuildIndependentTargetsInParallel": "YES", "LastSwiftUpdateCheck": "1600", "LastUpgradeCheck": "1600",
                "TargetAttributes": {app: {"CreatedOnToolsVersion": "16.0"}, extension: {"CreatedOnToolsVersion": "16.0"}}},
    buildConfigurationList=configuration_list("project", {
        "SDKROOT": "iphoneos", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
        "SUPPORTS_MACCATALYST": "NO", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
        "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "GCC_WARN_UNUSED_FUNCTION": "YES", "GCC_WARN_UNUSED_VARIABLE": "YES"
    }),
    compatibilityVersion="Xcode 14.0", developmentRegion="ko", hasScannedForEncodings=0,
    knownRegions=["ko", "en", "Base"], mainGroup=main_group, productRefGroup=product_group,
    projectDirPath="", projectRoot="", targets=[app, extension])
PROJECT.mkdir(exist_ok=True)
payload = {"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project}
(PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n" + serialize(payload) + "\n")

scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="ThreePad.app" BlueprintName="ThreePad" ReferencedContainer="container:ThreePad.xcodeproj"/>
    </BuildActionEntry></BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
    <Testables/>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="ThreePad.app" BlueprintName="ThreePad" ReferencedContainer="container:ThreePad.xcodeproj"/></BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
    <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="ThreePad.app" BlueprintName="ThreePad" ReferencedContainer="container:ThreePad.xcodeproj"/></BuildableProductRunnable>
  </ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
scheme_dir = PROJECT / "xcshareddata/xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
(scheme_dir / "ThreePad.xcscheme").write_text(scheme)
print(f"Generated ThreePad.xcodeproj: app {len(app_sources)} Swift files, extension {len(extension_sources)}.")
