# File: Tools/DiscordKitTools/scripts/publication.py
# Created by Carson Rau.
# Copyright (c) 2026 Aurum Studios.
# https://aurum-studios.com

"""Publication attribution shared by explicitly regenerated source fixtures."""


def swift_header(path):
    """Return a Swift comment header for a full repository-relative file path."""
    return (f"// File: {path}\n// Created by Carson Rau.\n"
            "// Copyright (c) 2026 Aurum Studios.\n// https://aurum-studios.com\n\n")
