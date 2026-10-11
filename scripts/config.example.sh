# Copy this file to config.sh and fill in the values printed by scripts/find-partitions.sh.
#
#   cp scripts/config.example.sh scripts/config.sh
#   $EDITOR scripts/config.sh
#
# Paths are macOS. On Linux, APP_* are typically under ~/.config/.

# ---- Source: the account/deployment that HAS your data ----
SRC_ACC="00000000-0000-0000-0000-000000000000"
SRC_ORG="00000000-0000-0000-0000-000000000000"

# ---- Target: the account/deployment the app is logged into NOW ----
DST_ACC="00000000-0000-0000-0000-000000000000"
DST_ORG="00000000-0000-0000-0000-000000000000"

# ---- Cowork (Chat/Cowork tab) uses its own account/org directory names ----
# In third-party ("3p") mode these are TRUNCATED to 8 characters, e.g. "a1b2c3d4" and "00000000".
# Read the real names with: ls "$HOME/Library/Application Support/Claude-3p/local-agent-mode-sessions/"
# If you do not want to migrate Cowork, set MIGRATE_COWORK=0.
MIGRATE_COWORK=1
SRC_ACC_COW=""
SRC_ORG_COW=""
DST_ACC_COW=""
DST_ORG_COW=""

# ---- App data directories ----
# Normal account mode uses "Claude"; third-party/gateway ("3p") mode uses "Claude-3p".
APP_OLD="$HOME/Library/Application Support/Claude"
APP_NEW="$HOME/Library/Application Support/Claude-3p"

CODE_SRC="$APP_OLD/claude-code-sessions/$SRC_ACC/$SRC_ORG"
CODE_DST="$APP_NEW/claude-code-sessions/$DST_ACC/$DST_ORG"
COW_SRC="$APP_OLD/local-agent-mode-sessions/$SRC_ACC_COW/$SRC_ORG_COW"
COW_DST="$APP_NEW/local-agent-mode-sessions/$DST_ACC_COW/$DST_ORG_COW"
