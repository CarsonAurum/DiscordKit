#!/usr/bin/env python3
"""Run only the built RESTOnly reads and require confirmed dedicated application IDs.

The example deliberately prints categorized failures and returns normally, so a
successful process exit alone cannot establish a passed live smoke. No credential
is included in arguments, output artifacts or errors from this wrapper.
"""

import argparse
import json
import os
import re
import subprocess
from pathlib import Path


def validate_application_id(expected_application):
    """Reject absent/non-Snowflake configuration before any authenticated work."""
    if not re.fullmatch(r"[0-9]{1,20}", expected_application or "") or not 0 < int(expected_application) <= 2**64 - 1:
        raise ValueError("A valid dedicated test application ID is required")


def confirmed_identifiers(output, expected_application):
    """Require the example's exact two-read success line and expected test application."""
    validate_application_id(expected_application)
    match = re.fullmatch(r"Fetched bot ([0-9]{1,20}) and application ([0-9]{1,20})\.", output.strip())
    if match is None or match[2] != expected_application:
        raise ValueError("Live reads did not confirm the expected dedicated test application")
    return {"botID": match[1], "applicationID": match[2]}


def main():
    """Execute the prebuilt read-only consumer and fail on categorized API/config errors."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--application-id", default=os.environ.get("DISCORD_SMOKE_APPLICATION_ID"))
    parser.add_argument("--output", type=Path, default=Path(".build/live-rest-smoke.json"))
    arguments = parser.parse_args()
    if not os.environ.get("DISCORD_BOT_TOKEN"):
        parser.error("The protected test bot credential is missing")
    validate_application_id(arguments.application_id)
    result = subprocess.run(["swift", "run", "--skip-build", "--package-path",
                             str(arguments.repository.resolve() / "Examples/RESTOnly")],
                            check=True, capture_output=True, text=True)
    identifiers = confirmed_identifiers(result.stdout, arguments.application_id)
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps({"scope": "Read-only API v10 current user/application only",
                                            "result": "passed", **identifiers}, indent=2) + "\n")
    print("Live read-only REST smoke confirmed the dedicated test application")


if __name__ == "__main__":
    main()
