import Foundation

/// App-level AI configuration.
///
/// Real per-machine values live in a LOCAL, skip-worktree copy of this file so
/// production secrets are never committed (this repository is public). The
/// committed version keeps them empty — AI cloud features then fall back to
/// on-device heuristics.
///
/// To set real values locally without committing them:
///   git update-index --skip-worktree Glutt/Services/AI/Secrets.swift
///   (then edit this file; git will ignore the change)
enum Secrets {
    /// Backend proxy base URL. Empty string = AI cloud features disabled.
    static let aiProxyBaseURL = ""

    /// Optional shared secret for proxy requests. Keep empty in git.
    static let aiProxyClientKey = ""
}
