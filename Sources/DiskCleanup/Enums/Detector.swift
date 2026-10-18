//
//  Detector.swift
//  DiskCleanup
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// The built-in logic a rule uses to turn its paths into items. Most rules
/// are plain `paths`; the rest need to read something first.
public enum Detector: String, Codable, CaseIterable, Sendable {
    /// Every match of `paths` and `globs` is one item.
    case paths
    /// `paths` are folder names beside a `marker` file, found under the
    /// project roots.
    case marker
    /// Installers in the installer folders, judged against what is installed.
    case installers
    /// Device support folders: everything but the newest build per device model.
    case deviceSupport = "device-support"
    /// Simulator devices, by `simctl list devices`.
    case simulatorDevices = "simulator-devices"
    /// Simulator runtimes, by `simctl runtime list`.
    case simulatorRuntimes = "simulator-runtimes"
    /// Core AI's compiled-model cache, split by OS build.
    case coreAIBuilds = "coreai-builds"
    /// Hugging Face hub repos, one item per repo.
    case huggingFaceRepos = "hf-repos"
    /// Ollama models, one item per manifest.
    case ollamaModels = "ollama-models"
    /// LM Studio models, one item per model folder.
    case lmStudioModels = "lmstudio-models"
    /// What `brew cleanup -n` says it would free.
    case homebrew
    /// Caches, logs, saved state and containers of apps that are gone.
    case leftovers
    /// Libraries outside the home folder that belong to apps (`apps`), found
    /// only when none of those apps is installed.
    case appLibraries = "app-libraries"
    /// Group containers whose owner is not installed: report only.
    case groupContainers = "group-containers"
    /// Chat apps' stores, report only; WhatsApp's also says how much media
    /// its own database no longer lists.
    case chatStores = "chat-stores"
    /// Launch agents pointing at a program that no longer exists: report only.
    case launchAgents = "launch-agents"
    /// Time Machine local snapshots, by `tmutil`.
    case snapshots
}
