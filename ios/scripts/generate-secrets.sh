#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${SRCROOT}/../.env"
OUTPUT_FILE="${SRCROOT}/FitnessLoadTracker/Secrets.swift"

if [ ! -f "$ENV_FILE" ]; then
    echo "error: Missing $ENV_FILE"
    echo "error: Copy ios/.env.example to ios/.env and fill in your Strava credentials."
    exit 1
fi

CLIENT_ID=$(grep '^STRAVA_CLIENT_ID=' "$ENV_FILE" | head -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'")
CLIENT_SECRET=$(grep '^STRAVA_CLIENT_SECRET=' "$ENV_FILE" | head -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'")

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
    echo "error: STRAVA_CLIENT_ID or STRAVA_CLIENT_SECRET missing or empty in $ENV_FILE"
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"
cat > "$OUTPUT_FILE" <<EOF
//
//  Secrets.swift  — OVERWRITTEN BY ios/scripts/generate-secrets.sh from ios/.env.
//  Do not commit this file's runtime state. See the committed stub for context.
//

enum Secrets {
    static let stravaClientId = "$CLIENT_ID"
    static let stravaClientSecret = "$CLIENT_SECRET"
}
EOF

echo "Generated $OUTPUT_FILE"
