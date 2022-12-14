#!/bin/bash

# Positional arguments:
# 1. Name of the project
# 2. A name for the command that'll run
# 3. Command to run.

# Execute everything from the directory the script lives in, just in case.
REPO_ROOT=$(cd -P -- "$(dirname -- "$0")" && pwd -P)
cd "$REPO_ROOT" || exit 1

# Create files for output
echo "[no output]" > "$REPO_ROOT/stdout.log"
echo "[no output]" > "$REPO_ROOT/stderr.log"

# Execute the command that was passed
if eval "$3" > "$REPO_ROOT/stdout.log" 2> "$REPO_ROOT/stderr.log"; then
    echo "$2 ran successfully!" && exit 0 # If ok the journey ends here.
else
    echo "$2 failed!"
fi

# Truncate files if necessary (Slack is max 3000 chars per code block)
cat "$REPO_ROOT/stdout.log" | tail -c 2969 > "$REPO_ROOT/stdout.tmp"
rm "$REPO_ROOT/stdout.log" && mv "$REPO_ROOT/stdout.tmp" "$REPO_ROOT/stdout.log"
cat "$REPO_ROOT/stderr.log" | tail -c 2969 > "$REPO_ROOT/stderr.tmp"
rm "$REPO_ROOT/stderr.log" && mv "$REPO_ROOT/stderr.tmp" "$REPO_ROOT/stderr.log"

# Set some easily accessible variables for our Slack message.
REPO_REMOTE_NAME=$(if [ -n "$BITBUCKET_BUILD_NUMBER" ]; then echo Bitbucket; elif [ -n "$GITHUB_RUN_NUMBER" ]; then echo GitHub; else echo Unknown; fi)
REPO_REMOTE_URL=$(if [ -n "$BITBUCKET_GIT_HTTP_ORIGIN" ]; then echo "$BITBUCKET_GIT_HTTP_ORIGIN"; elif [ -n "$GITHUB_SERVER_URL" ]; then echo "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY"; else echo ""; fi)
REPO_REMOTE_FORMATTED=$(if [ -n "$REPO_REMOTE_URL" ]; then echo "<$REPO_REMOTE_URL|$REPO_REMOTE_NAME>"; else echo "$REPO_REMOTE_NAME" ; fi)
SCRIPT_TRIGGER=$(if [ -n "$BITBUCKET_PR_ID" ]; then echo "refs/pull/$BITBUCKET_PR_ID/merge"; elif [ -n "$BITBUCKET_BRANCH" ]; then echo "refs/heads/$BITBUCKET_BRANCH"; elif [ -n "$BITBUCKET_TAG" ]; then echo "refs/tags/$BITBUCKET_TAG"; elif [ -n "$GITHUB_REF" ]; then echo "$GITHUB_REF"; else echo Unknown; fi)
LAST_COMMITTER=$(git log -1 --pretty=format:'%an' | cat)

# Make a cool Slack message
SLACK_MESSAGE_CONTENT="{
    \"blocks\": [
        {
            \"type\": \"section\",
            \"text\": {
                \"type\": \"mrkdwn\",
                \"text\": \"Uh oh... $2 failing for *$1*:\"
            }
        },
        {
            \"type\": \"section\",
            \"text\": {
                \"type\": \"mrkdwn\",
                \"text\": \"*stdout*\n\`\`\`$(jq -Rs < "$REPO_ROOT/stdout.log" | sed 's/^"\(.*\)"$/\1/')\`\`\`\"
            }
        },
        {
            \"type\": \"section\",
            \"text\": {
                \"type\": \"mrkdwn\",
                \"text\": \"*stderr*\n\`\`\`$(jq -Rs < "$REPO_ROOT/stderr.log" | sed 's/^"\(.*\)"$/\1/')\`\`\`\"
            }
        },
        {
            \"type\": \"section\",
            \"fields\": [
                {
                    \"type\": \"mrkdwn\",
                    \"text\": \"*Remote*\n$REPO_REMOTE_FORMATTED\"
                },
                {
                    \"type\": \"mrkdwn\",
                    \"text\": \"*Trigger*\n\`$SCRIPT_TRIGGER\`\"
                }
            ]
        },
        {
            \"type\": \"divider\"
        },
        {
            \"type\": \"context\",
            \"elements\": [
                {
                    \"type\": \"mrkdwn\",
                    \"text\": \"Last commit was added by *$LAST_COMMITTER*. ????\"
                }
            ]
        }
    ]
}"

# Clean up after ourselves.
rm "$REPO_ROOT/stdout.log"
rm "$REPO_ROOT/stderr.log"

if [ -n "$SLACK_WEBHOOK_URL" ]; then
    # Send it.
    curl -X POST -H 'Content-type: application/json' --data "$SLACK_MESSAGE_CONTENT" "$SLACK_WEBHOOK_URL"
else
    # Multiple remotes... so we'll just skip sending to Slack if webhook is not set.
    echo SLACK_WEBHOOK_URL is not set!
    exit 0
fi

# Make the job fail
exit 1
