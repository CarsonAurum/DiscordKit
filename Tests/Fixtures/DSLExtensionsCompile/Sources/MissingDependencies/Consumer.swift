// File: Tests/Fixtures/DSLExtensionsCompile/Sources/MissingDependencies/Consumer.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandExtensions

/// Intentionally fails because the extension's required typed dependency contract cannot be omitted.
/// - Throws: Authoring validation would occur only if this deliberately invalid source could compile.
public func missingDependencies() throws { _ = try ExtensionCommands(id: "missing") }
