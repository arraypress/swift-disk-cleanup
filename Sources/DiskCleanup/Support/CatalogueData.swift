//
//  CatalogueData.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//
//  The rule catalogue, compiled in. JSON so it reads as data and can be
//  printed, checked and diffed; a Swift string so it ships inside the binary
//  (a Homebrew-symlinked tool cannot find a resource bundle).
//
//  ORDER IS PRIORITY: when two rules find overlapping paths, the earlier one
//  keeps it. Specific rules first, the broad sweeps of ~/Library/Caches and
//  ~/Library/Logs last. Written for this library; the open-source cleaners in
//  the README were read for where things live, not copied.
//

enum CatalogueData {

    static let json = #"""
{
  "version": 1,
  "protect": [
    "~/Library/Keychains",
    "~/.ssh",
    "~/.gnupg",
    "~/Library/LaunchAgents",
    "~/Library/Group Containers",
    "~/Library/Mobile Documents",
    "~/Library/CloudStorage",
    "~/Library/Mail",
    "~/Library/Messages",
    "~/Library/Preferences",
    "~/Library/Accounts",
    "~/Library/Cookies",
    "~/Library/Application Support/MobileSync",
    "~/Library/Application Support/diskmaid",
    "~/.config/arraypress/credentials.json",
    "~/.cache/huggingface/token",
    "~/.cache/huggingface/stored_tokens",
    "~/Pictures",
    "~/Music",
    "~/Movies"
  ],
  "protectNames": [
    "keychain", "1password", "agilebits", "bitwarden", "lastpass", "dashlane",
    "keepass", "enpass", "strongbox", "passwords", "ssh", "gnupg", "gpg"
  ],
  "rules": [
    {
      "id": "installers",
      "category": "installers",
      "detector": "installers",
      "regenerable": false,
      "tier": "safe",
      "removal": "trash",
      "note": "Dead only when the same or a newer version of its app is installed. A newer installer is a pending update and stays; no answer means unknown, never 'not installed'."
    },
    {
      "id": "xcode-derived-data",
      "category": "xcode",
      "globs": ["~/Library/Developer/Xcode/DerivedData/*"],
      "owner": "Xcode",
      "regenerable": true,
      "tier": "safe",
      "removal": "delete",
      "note": "Build products and indexes per project; the next build makes them again."
    },
    {
      "id": "xcode-device-support",
      "category": "xcode",
      "detector": "device-support",
      "globs": ["~/Library/Developer/Xcode/*DeviceSupport/*"],
      "owner": "Xcode",
      "regenerable": true,
      "tier": "safe",
      "removal": "delete",
      "keepNewest": 1,
      "note": "Debug symbols copied off a device. The newest build per device model is kept; Xcode copies the rest again when that device is next plugged in."
    },
    {
      "id": "xcode-archives",
      "category": "xcode",
      "globs": ["~/Library/Developer/Xcode/Archives/*/*.xcarchive"],
      "owner": "Xcode",
      "regenerable": false,
      "tier": "report",
      "removal": "trash",
      "note": "An archive is what symbolicates crash reports from that build. Prune old ones in Xcode's Organizer."
    },
    {
      "id": "xcode-documentation-cache",
      "category": "xcode",
      "paths": ["~/Library/Developer/Xcode/DocumentationCache"],
      "owner": "Xcode",
      "regenerable": true,
      "tier": "safe",
      "removal": "delete",
      "note": "Downloaded documentation; fetched again on demand."
    },
    {
      "id": "xcode-caches",
      "category": "xcode",
      "paths": ["~/Library/Caches/com.apple.dt.Xcode"],
      "owner": "Xcode",
      "regenerable": true,
      "tier": "safe",
      "removal": "delete",
      "minAgeDays": 1,
      "note": "Xcode's own cache."
    },
    {
      "id": "xcode-previews",
      "category": "xcode",
      "paths": ["~/Library/Developer/Xcode/UserData/Previews"],
      "owner": "Xcode",
      "regenerable": true,
      "tier": "review",
      "removal": "delete",
      "minAgeDays": 1,
      "note": "The simulators SwiftUI previews run in; the next preview builds them again, slowly."
    },
    {
      "id": "simulator-devices",
      "category": "xcode",
      "detector": "simulator-devices",
      "owner": "Xcode",
      "regenerable": true,
      "tier": "safe",
      "removal": ["xcrun", "simctl", "delete", "{udid}"],
      "note": "A device whose runtime is gone can never boot again and is removed through simctl. Devices that still work are listed for their size only."
    },
    {
      "id": "simulator-runtimes",
      "category": "xcode",
      "detector": "simulator-runtimes",
      "owner": "Xcode",
      "regenerable": true,
      "tier": "review",
      "removal": ["xcrun", "simctl", "runtime", "delete", "{identifier}"],
      "note": "Offered only when two images provide the same runtime; getting one back is a multi-gigabyte download. Never removed with rm: the images are root-owned and simctl keeps its own books."
    },
    {
      "id": "simulator-caches",
      "category": "xcode",
      "paths": ["~/Library/Developer/CoreSimulator/Caches"],
      "owner": "Xcode",
      "regenerable": true,
      "tier": "safe",
      "removal": "delete",
      "minAgeDays": 1,
      "note": "CoreSimulator's dyld and asset caches; rebuilt at the next boot of a simulator."
    },
    {
      "id": "build-swift",
      "category": "build-folders",
      "detector": "marker",
      "marker": [
        "Package.swift"
      ],
      "paths": [
        ".build"
      ],
      "regenerable": true,
      "tier": "safe",
      "removal": "delete",
      "minAgeDays": 7,
      "note": ".build is SwiftPM's output; the next build makes it again."
    },
    {
      "id": "build-swiftpm",
      "category": "build-folders",
      "detector": "marker",
      "marker": [
        "Package.swift"
      ],
      "paths": [
        ".swiftpm"
      ],
      "regenerable": true,
      "tier": "review",
      "removal": "delete",
      "minAgeDays": 7,
      "note": "Xcode's per-user state for a package (schemes, settings). Rebuilt, but customised schemes are lost unless git tracks them."
    },
    {
      "id": "build-node",
      "category": "build-folders",
      "detector": "marker",
      "marker": [
        "package.json"
      ],
      "paths": [
        "node_modules"
      ],
      "regenerable": true,
      "tier": "safe",
      "removal": "delete",
      "minAgeDays": 7,
      "note": "Reinstalled by npm, pnpm or yarn install."
    },
    {
      "id": "build-node-frameworks",
      "category": "build-folders",
      "detector": "marker",
      "marker": [
        "package.json"
      ],
      "paths": [
        ".next",
        ".nuxt",
        ".svelte-kit",
        ".parcel-cache",
        ".turbo",
        ".angular"
      ],
      "regenerable": true,
      "tier": "safe",
      "removal": "delete",
      "minAgeDays": 7
    },
    {
      "id": "build-python-venv",
      "category": "build-folders",
      "detector": "marker",
      "marker": [
        "pyproject.toml",
        "requirements.txt",
        "setup.py",
        "Pipfile",
        "uv.lock"
      ],
      "paths": [
        ".venv",
        "venv"
      ],
      "regenerable": true,
      "tier": "review",
      "removal": "delete",
      "minAgeDays": 7,
      "note": "A virtual environment can hold packages installed by hand that no lockfile lists."
    },
    {
      "id": "build-python-caches",
      "category": "build-folders",
      "detector": "marker",
      "marker": [
        "pyproject.toml",
        "requirements.txt",
        "setup.py",
        "Pipfile",
        "uv.lock",
        "tox.ini"
      ],
      "paths": [
        ".pytest_cache",
        ".mypy_cache",
        ".ruff_cache",
        ".tox",
        ".nox"
      ],
      "regenerable": true,
      "tier": "safe",
      "removal": "delete",
      "minAgeDays": 7
    },
    {
      "id": "build-rust",
      "category": "build-folders",
      "detector": "marker",
      "marker": [
        "Cargo.toml"
      ],
      "paths": [
        "target"
      ],
      "regenerable": true,
      "tier": "safe",
      "removal": "delete",
      "minAgeDays": 7,
      "note": "Cargo's output; often the biggest folder in a Rust project."
    },
    {
      "id": "build-maven",
      "category": "build-folders",
      "detector": "marker",
      "marker": [
        "pom.xml"
      ],
      "paths": [
        "target"
      ],
      "regenerable": true,
      "tier": "safe",
      "removal": "delete",
      "minAgeDays": 7
    },
    {
      "id": "build-gradle",
      "category": "build-folders",
      "detector": "marker",
      "marker": [
        "build.gradle",
        "build.gradle.kts",
        "settings.gradle",
        "settings.gradle.kts"
      ],
      "paths": [
        "build",
        ".gradle"
      ],
      "regenerable": true,
      "tier": "safe",
      "removal": "delete",
      "minAgeDays": 7
    },
    {
      "id": "build-dotnet",
      "category": "build-folders",
      "detector": "marker",
      "marker": [
        "*.csproj",
        "*.fsproj",
        "*.vbproj"
      ],
      "paths": [
        "bin",
        "obj"
      ],
      "regenerable": true,
      "tier": "safe",
      "removal": "delete",
      "minAgeDays": 7
    },
    {
      "id": "build-cmake",
      "category": "build-folders",
      "detector": "marker",
      "marker": [
        "CMakeLists.txt"
      ],
      "paths": [
        "cmake-build-*"
      ],
      "regenerable": true,
      "tier": "safe",
      "removal": "delete",
      "minAgeDays": 7,
      "note": "CLion's per-configuration build folders."
    },
    {
      "id": "build-elixir",
      "category": "build-folders",
      "detector": "marker",
      "marker": [
        "mix.exs"
      ],
      "paths": [
        "_build",
        "deps"
      ],
      "regenerable": true,
      "tier": "safe",
      "removal": "delete",
      "minAgeDays": 7
    },
    {
      "id": "build-haskell",
      "category": "build-folders",
      "detector": "marker",
      "marker": [
        "stack.yaml",
        "cabal.project"
      ],
      "paths": [
        ".stack-work",
        "dist-newstyle"
      ],
      "regenerable": true,
      "tier": "safe",
      "removal": "delete",
      "minAgeDays": 7
    },
    {
      "id": "build-dart",
      "category": "build-folders",
      "detector": "marker",
      "marker": [
        "pubspec.yaml"
      ],
      "paths": [
        ".dart_tool",
        "build"
      ],
      "regenerable": true,
      "tier": "safe",
      "removal": "delete",
      "minAgeDays": 7
    },
    {
      "id": "build-zig",
      "category": "build-folders",
      "detector": "marker",
      "marker": [
        "build.zig"
      ],
      "paths": [
        "zig-cache",
        ".zig-cache",
        "zig-out"
      ],
      "regenerable": true,
      "tier": "safe",
      "removal": "delete",
      "minAgeDays": 7
    },
    {
      "id": "build-terraform",
      "category": "build-folders",
      "detector": "marker",
      "marker": [
        "*.tf"
      ],
      "paths": [
        ".terraform"
      ],
      "regenerable": true,
      "tier": "review",
      "removal": "delete",
      "minAgeDays": 7,
      "note": "Provider binaries; 'terraform init' fetches them again."
    },
    {
      "id": "build-composer",
      "category": "build-folders",
      "detector": "marker",
      "marker": [
        "composer.json"
      ],
      "paths": [
        "vendor"
      ],
      "regenerable": true,
      "tier": "review",
      "removal": "delete",
      "minAgeDays": 7,
      "note": "Some projects commit vendor/; git-tracked folders are protected anyway."
    },
    {
      "id": "homebrew-cleanup",
      "category": "package-caches",
      "detector": "homebrew",
      "paths": ["~/Library/Caches/Homebrew"],
      "owner": "Homebrew",
      "regenerable": true,
      "tier": "safe",
      "removal": ["brew", "cleanup"],
      "note": "What 'brew cleanup' would remove: old versions and downloads. The size is Homebrew's own dry-run figure."
    },
    {
      "id": "uv-cache",
      "category": "package-caches",
      "paths": ["~/.cache/uv"],
      "owner": "uv",
      "regenerable": true,
      "tier": "safe",
      "removal": ["uv", "cache", "prune"],
      "note": "Prune keeps what is still in use, so it frees up to the size shown."
    },
    {
      "id": "npm-cache",
      "category": "package-caches",
      "paths": ["~/.npm/_cacache"],
      "owner": "npm",
      "regenerable": true,
      "tier": "safe",
      "removal": ["npm", "cache", "clean", "--force"],
      "note": "npm asks for --force because its cache heals itself; the cost is downloading again."
    },
    {
      "id": "pnpm-store",
      "category": "package-caches",
      "paths": ["~/Library/pnpm/store"],
      "owner": "pnpm",
      "regenerable": true,
      "tier": "safe",
      "removal": ["pnpm", "store", "prune"],
      "note": "Prune removes packages no project links to."
    },
    {
      "id": "yarn-cache",
      "category": "package-caches",
      "paths": ["~/Library/Caches/Yarn"],
      "owner": "Yarn",
      "regenerable": true,
      "tier": "safe",
      "removal": ["yarn", "cache", "clean"]
    },
    {
      "id": "swiftpm-cache",
      "category": "package-caches",
      "paths": ["~/Library/Caches/org.swift.swiftpm"],
      "owner": "SwiftPM",
      "regenerable": true,
      "tier": "safe",
      "removal": ["swift", "package", "purge-cache"],
      "note": "Cloned package repositories and manifests. A tool's cache, not an app's: never a leftover."
    },
    {
      "id": "pip-cache",
      "category": "package-caches",
      "paths": ["~/Library/Caches/pip"],
      "owner": "pip",
      "regenerable": true,
      "tier": "safe",
      "removal": "delete"
    },
    {
      "id": "go-build-cache",
      "category": "package-caches",
      "paths": ["~/Library/Caches/go-build"],
      "owner": "Go",
      "regenerable": true,
      "tier": "safe",
      "removal": ["go", "clean", "-cache"]
    },
    {
      "id": "cocoapods-cache",
      "category": "package-caches",
      "paths": ["~/Library/Caches/CocoaPods"],
      "owner": "CocoaPods",
      "regenerable": true,
      "tier": "safe",
      "removal": ["pod", "cache", "clean", "--all"]
    },
    {
      "id": "bun-cache",
      "category": "package-caches",
      "paths": ["~/.bun/install/cache"],
      "owner": "Bun",
      "regenerable": true,
      "tier": "safe",
      "removal": ["bun", "pm", "cache", "rm"]
    },
    {
      "id": "gradle-caches",
      "category": "package-caches",
      "paths": ["~/.gradle/caches"],
      "owner": "Gradle",
      "regenerable": true,
      "tier": "review",
      "removal": "delete",
      "note": "Gradle has no prune command; deleting means the next build downloads everything."
    },
    {
      "id": "cargo-registry-cache",
      "category": "package-caches",
      "paths": ["~/.cargo/registry/cache"],
      "owner": "Cargo",
      "regenerable": true,
      "tier": "review",
      "removal": "delete",
      "note": "Downloaded crate archives; offline builds need them."
    },
    {
      "id": "deno-cache",
      "category": "package-caches",
      "paths": ["~/Library/Caches/deno"],
      "owner": "Deno",
      "regenerable": true,
      "tier": "review",
      "removal": "delete"
    },
    {
      "id": "coreai-cache",
      "category": "ml-caches",
      "detector": "coreai-builds",
      "paths": ["~/Library/Caches/coreai-cache", "~/Library/Application Support/coreai-cache"],
      "owner": "Core AI",
      "regenerable": true,
      "tier": "safe",
      "removal": "delete",
      "note": "Models compiled for one macOS build. Another build's folder is dead after an update; this build's rebuilds itself but slowly, so it is review — except a compiled copy whose model is on the disk no more (no .aimodel has its hash), which nothing can load again."
    },
    {
      "id": "hf-hub",
      "category": "ml-caches",
      "detector": "hf-repos",
      "paths": ["~/.cache/huggingface/hub"],
      "owner": "Hugging Face",
      "regenerable": true,
      "tier": "review",
      "removal": "delete",
      "note": "One item per repo. A repo's folder holds its own blobs, so removing a whole repo touches no other; single revisions are for 'hf cache' to remove, never a blanket rm."
    },
    {
      "id": "hf-xet-cache",
      "category": "ml-caches",
      "paths": ["~/.cache/huggingface/xet"],
      "owner": "Hugging Face",
      "regenerable": true,
      "tier": "review",
      "removal": "delete",
      "note": "Chunk cache for Xet-backed downloads."
    },
    {
      "id": "torch-hub",
      "category": "ml-caches",
      "paths": ["~/.cache/torch"],
      "owner": "PyTorch",
      "regenerable": true,
      "tier": "review",
      "removal": "delete",
      "note": "Downloaded checkpoints; fetched again on first use."
    },
    {
      "id": "ollama-models",
      "category": "ml-caches",
      "detector": "ollama-models",
      "paths": ["~/.ollama/models"],
      "owner": "Ollama",
      "regenerable": true,
      "tier": "report",
      "removal": ["ollama", "rm", "{model}"],
      "note": "Models share layers, so each total counts a shared layer again. Remove one with 'ollama rm <model>'."
    },
    {
      "id": "lmstudio-models",
      "category": "ml-caches",
      "detector": "lmstudio-models",
      "paths": ["~/.lmstudio/models", "~/.cache/lm-studio/models"],
      "owner": "LM Studio",
      "regenerable": true,
      "tier": "report",
      "removal": "delete",
      "note": "Remove in LM Studio's model list."
    },
    {
      "id": "fleet-models-imagine",
      "category": "ml-caches",
      "globs": ["~/Library/Application Support/imagine-*"],
      "owner": "imagine",
      "regenerable": true,
      "tier": "report",
      "removal": "delete",
      "note": "Remove with 'imagine model remove'."
    },
    {
      "id": "fleet-models-speak",
      "category": "ml-caches",
      "globs": ["~/Library/Application Support/speak/*"],
      "owner": "speak",
      "regenerable": true,
      "tier": "report",
      "removal": "delete",
      "note": "Remove with 'speak models remove <name>'."
    },
    {
      "id": "fleet-models-song",
      "category": "ml-caches",
      "globs": ["~/Library/Application Support/song/*"],
      "owner": "song",
      "regenerable": true,
      "tier": "report",
      "removal": "delete",
      "note": "Remove with 'song models remove <name>'."
    },
    {
      "id": "fleet-models-stems",
      "category": "ml-caches",
      "globs": ["~/Library/Application Support/stems/*"],
      "owner": "stems",
      "regenerable": true,
      "tier": "report",
      "removal": "delete",
      "note": "stems fetches a model again on first use."
    },
    {
      "id": "fleet-models-upscale",
      "category": "ml-caches",
      "globs": ["~/Library/Application Support/upscale/*"],
      "owner": "upscale",
      "regenerable": true,
      "tier": "report",
      "removal": "delete",
      "note": "upscale fetches a model again on first use."
    },
    {
      "id": "fleet-models-cutout",
      "category": "ml-caches",
      "globs": ["~/Library/Application Support/cutout/*"],
      "owner": "cutout",
      "regenerable": true,
      "tier": "report",
      "removal": "delete",
      "note": "cutout fetches its model again on first use."
    },
    {
      "id": "fleet-models-img",
      "category": "ml-caches",
      "globs": ["~/Library/Application Support/img/*.aimodel", "~/Library/Application Support/segment-*"],
      "owner": "img",
      "regenerable": true,
      "tier": "report",
      "removal": "delete",
      "note": "img's depth and mask models; fetched again on first use."
    },
    {
      "id": "fleet-models-tune",
      "category": "ml-caches",
      "globs": ["~/Library/Application Support/tune/*.aimodel"],
      "owner": "tune",
      "regenerable": true,
      "tier": "report",
      "removal": "delete"
    },
    {
      "id": "fleet-models-embed",
      "category": "ml-caches",
      "globs": ["~/Library/Application Support/embed/*.aimodel", "~/Library/Application Support/embed/embed-support"],
      "owner": "embed",
      "regenerable": true,
      "tier": "report",
      "removal": "delete",
      "note": "The model only; embed's indexes beside it are data, not cache. 'embed model install' fetches it again."
    },
    {
      "id": "fleet-models-crate",
      "category": "ml-caches",
      "globs": ["~/Library/Application Support/crate/*.aimodel", "~/Library/Application Support/crate/clap-support"],
      "owner": "crate",
      "regenerable": true,
      "tier": "report",
      "removal": "delete",
      "note": "The model only; crate's indexes beside it are data. 'crate model install' fetches it again."
    },
    {
      "id": "fleet-models-pix",
      "category": "ml-caches",
      "globs": ["~/Library/Application Support/pix/*.aimodel"],
      "owner": "pix",
      "regenerable": true,
      "tier": "report",
      "removal": "delete",
      "note": "The model only; pix's photo index beside it is data."
    },
    {
      "id": "fleet-models-scribe",
      "category": "ml-caches",
      "paths": ["~/Library/Application Support/scribe/models"],
      "owner": "scribe",
      "regenerable": true,
      "tier": "report",
      "removal": "delete",
      "note": "'scribe model install' fetches it again."
    },
    {
      "id": "fleet-models-muse",
      "category": "ml-caches",
      "paths": ["~/.config/arraypress/muse/models"],
      "owner": "muse",
      "regenerable": false,
      "tier": "report",
      "removal": "trash",
      "note": "muse's optional classifiers; installed by hand, so keep them."
    },
    {
      "id": "logic-sound-library",
      "category": "leftovers",
      "detector": "app-libraries",
      "paths": [
        "/Library/Application Support/Logic",
        "/Library/Application Support/GarageBand",
        "/Library/Audio/Apple Loops",
        "/Library/Audio/Impulse Responses"
      ],
      "apps": ["com.apple.logic10", "com.apple.garageband10", "com.apple.mainstage3"],
      "owner": "Logic Pro, GarageBand, MainStage",
      "regenerable": false,
      "tier": "review",
      "removal": "sudo",
      "note": "Sound library left by Logic Pro, GarageBand or MainStage, none of which is installed; reinstalling one downloads it again. Owned by root: diskmaid prints the sudo command instead of running it."
    },
    {
      "id": "reason-sound-library",
      "category": "leftovers",
      "detector": "app-libraries",
      "paths": ["/Library/Application Support/Propellerhead Software"],
      "apps": ["se.propellerheads.reason", "com.reasonstudios.reason"],
      "owner": "Reason",
      "regenerable": false,
      "tier": "review",
      "removal": "sudo",
      "note": "Reason's sound banks, left with no Reason installed (any Propellerhead or Reason Studios app keeps them). Owned by root: diskmaid prints the sudo command instead of running it."
    },
    {
      "id": "leftover-caches",
      "category": "leftovers",
      "detector": "leftovers",
      "globs": ["~/Library/Caches/*"],
      "regenerable": false,
      "tier": "review",
      "removal": "trash",
      "minAgeDays": 30,
      "note": "Named by the exact bundle id of an app that is in no app folder, not running, not in a launch agent, unknown to LaunchServices and Spotlight, and untouched for 30 days."
    },
    {
      "id": "leftover-logs",
      "category": "leftovers",
      "detector": "leftovers",
      "globs": ["~/Library/Logs/*"],
      "regenerable": false,
      "tier": "review",
      "removal": "trash",
      "minAgeDays": 30
    },
    {
      "id": "leftover-saved-state",
      "category": "leftovers",
      "detector": "leftovers",
      "globs": ["~/Library/Saved Application State/*.savedState"],
      "regenerable": false,
      "tier": "review",
      "removal": "trash",
      "minAgeDays": 30
    },
    {
      "id": "leftover-containers",
      "category": "leftovers",
      "detector": "leftovers",
      "globs": ["~/Library/Containers/*"],
      "regenerable": false,
      "tier": "review",
      "removal": "trash",
      "minAgeDays": 30,
      "note": "The owner is read from the container's own metadata, not its folder name."
    },
    {
      "id": "leftover-group-containers",
      "category": "leftovers",
      "detector": "group-containers",
      "globs": ["~/Library/Group Containers/*"],
      "regenerable": false,
      "tier": "report",
      "removal": "trash",
      "minAgeDays": 30,
      "note": "Report only: group names carry a team prefix and are shared between apps, so 'no owner found' is a guess."
    },
    {
      "id": "leftover-launch-agents",
      "category": "leftovers",
      "detector": "launch-agents",
      "globs": ["~/Library/LaunchAgents/*.plist"],
      "regenerable": false,
      "tier": "report",
      "removal": "trash",
      "note": "Report only: a launch agent whose program no longer exists. Unload it with launchctl before removing it."
    },
    {
      "id": "chrome-cache",
      "category": "user-caches",
      "globs": ["~/Library/Caches/Google/Chrome/*/Cache", "~/Library/Caches/Google/Chrome/*/Code Cache"],
      "owner": "Google Chrome",
      "regenerable": true,
      "tier": "safe",
      "removal": "delete",
      "minAgeDays": 1
    },
    {
      "id": "edge-cache",
      "category": "user-caches",
      "globs": ["~/Library/Caches/Microsoft Edge*/*/Cache", "~/Library/Caches/Microsoft Edge*/*/Code Cache"],
      "owner": "Microsoft Edge",
      "regenerable": true,
      "tier": "safe",
      "removal": "delete",
      "minAgeDays": 1
    },
    {
      "id": "firefox-cache",
      "category": "user-caches",
      "globs": ["~/Library/Caches/Firefox/Profiles/*/cache2"],
      "owner": "Firefox",
      "regenerable": true,
      "tier": "safe",
      "removal": "delete",
      "minAgeDays": 1
    },
    {
      "id": "spotify-cache",
      "category": "user-caches",
      "paths": ["~/Library/Caches/com.spotify.client"],
      "owner": "Spotify",
      "regenerable": true,
      "tier": "safe",
      "removal": "delete",
      "minAgeDays": 1,
      "note": "Streamed audio; downloaded songs live elsewhere and are untouched."
    },
    {
      "id": "user-caches",
      "category": "user-caches",
      "globs": ["~/Library/Caches/*"],
      "regenerable": true,
      "tier": "review",
      "removal": "delete",
      "minAgeDays": 1,
      "protect": ["com.apple.*"],
      "note": "Apps rebuild their caches, some slowly. Anything a rule above names is counted there instead; Apple's own are shown, never cleaned."
    },
    {
      "id": "user-logs",
      "category": "user-caches",
      "globs": ["~/Library/Logs/*"],
      "regenerable": false,
      "tier": "review",
      "removal": "trash",
      "minAgeDays": 7,
      "note": "Old logs and crash reports; nothing needs them to run."
    },
    {
      "id": "trash",
      "category": "report-only",
      "paths": ["~/.Trash"],
      "regenerable": false,
      "tier": "report",
      "removal": "trash",
      "note": "Emptying the Trash is what frees it. diskmaid never empties it."
    },
    {
      "id": "time-machine-snapshots",
      "category": "report-only",
      "detector": "snapshots",
      "owner": "Time Machine",
      "regenerable": false,
      "tier": "report",
      "removal": "delete",
      "note": "'tmutil thinlocalsnapshots /' asks macOS to free them. com.apple.os.update snapshots belong to the system."
    },
    {
      "id": "ios-backups",
      "category": "report-only",
      "globs": ["~/Library/Application Support/MobileSync/Backup/*"],
      "regenerable": false,
      "tier": "report",
      "removal": "trash",
      "note": "Delete old ones in Finder, under the device, Manage Backups."
    },
    {
      "id": "mail-downloads",
      "category": "report-only",
      "paths": ["~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"],
      "owner": "Mail",
      "regenerable": false,
      "tier": "report",
      "removal": "trash"
    },
    {
      "id": "messages-attachments",
      "category": "report-only",
      "paths": ["~/Library/Messages/Attachments"],
      "owner": "Messages",
      "regenerable": false,
      "tier": "report",
      "removal": "trash",
      "note": "Manage in Messages, Settings, keep messages for."
    },
    {
      "id": "chat-stores",
      "category": "report-only",
      "detector": "chat-stores",
      "globs": [
        "~/Library/Group Containers/group.net.whatsapp.WhatsApp.shared",
        "~/Library/Group Containers/*.net.whatsapp.WhatsApp.shared",
        "~/Library/Containers/net.whatsapp.WhatsApp",
        "~/Library/Group Containers/*.ru.keepcoder.Telegram",
        "~/Library/Application Support/Slack",
        "~/Library/Application Support/discord",
        "~/Library/Application Support/Signal"
      ],
      "regenerable": false,
      "tier": "report",
      "removal": "trash",
      "note": "Each chat app manages its own storage; clear it from inside the app."
    },
    {
      "id": "claude-vm-bundles",
      "category": "report-only",
      "paths": ["~/Library/Application Support/Claude/vm_bundles"],
      "owner": "Claude",
      "regenerable": true,
      "tier": "report",
      "removal": "delete",
      "note": "The Claude desktop app's virtual machine; it downloads again when next needed. Remove it with Claude quit."
    },
    {
      "id": "claude-code-sessions",
      "category": "report-only",
      "paths": ["~/.claude/projects"],
      "owner": "Claude Code",
      "regenerable": false,
      "tier": "report",
      "removal": "trash",
      "note": "Claude Code's session history and memory, per project folder: what --resume reads. Not a cache."
    }
  ]
}
"""#
}
