#!/usr/bin/env bash
set -euo pipefail

##############################################################################
# CONFIG –- edit only if your naming or regions change
##############################################################################
USER_NAME="bedrock-app-user"
POLICY_NAME="Bedrock-MultiRegion-ClaudePolicy"

# Regions that the app is prepared to use
REGIONS=("us-west-2" "us-east-1")

# Primary & secondary model IDs
DEFAULT_MODEL_ID="anthropic.claude-3-7-sonnet-20250219-v1:0"
RELEVANCY_MODEL_ID="anthropic.claude-3-5-haiku-20241022-v1:0"

##############################################################################
# 1. Create (or reuse) IAM user
##############################################################################
echo "➤ Ensuring IAM user ${USER_NAME} exists…"
aws iam create-user --user-name "$USER_NAME" 2>/dev/null || echo "   (user already exists)"

##############################################################################
# 2. Build least-privilege policy document for BOTH models in BOTH regions
##############################################################################
echo "➤ Building multi-region policy document…"
POLICY_FILE=$(mktemp)
{
  echo '{ "Version":"2012-10-17", "Statement":['
  first=true
  for region in "${REGIONS[@]}"; do
    for model_id in "$DEFAULT_MODEL_ID" "$RELEVANCY_MODEL_ID"; do
      arn="arn:aws:bedrock:${region}::foundation-model/${model_id}"
      $first || echo ','
      first=false
      cat <<EOF
    {
      "Sid": "${region//-/_}_${model_id//[:.]/_}",
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ],
      "Resource": "${arn}"
    }
EOF
    done
  done
  echo '] }'
} > "${POLICY_FILE}"

##############################################################################
# 3. Create or update the customer-managed policy
##############################################################################
POLICY_ARN=$(aws iam list-policies --scope Local \
             --query "Policies[?PolicyName=='${POLICY_NAME}'].Arn" \
             --output text)

if [[ -z "$POLICY_ARN" ]]; then
  echo "➤ Creating policy ${POLICY_NAME}…"
  POLICY_ARN=$(aws iam create-policy \
                 --policy-name "$POLICY_NAME" \
                 --policy-document "file://${POLICY_FILE}" \
                 --query 'Policy.Arn' --output text)
else
  echo "➤ Policy exists – updating to latest document…"
  aws iam create-policy-version \
        --policy-arn "$POLICY_ARN" \
        --policy-document "file://${POLICY_FILE}" \
        --set-as-default >/dev/null
fi

##############################################################################
# 4. Attach policy
##############################################################################
echo "➤ Attaching policy to user…"
aws iam attach-user-policy --user-name "$USER_NAME" --policy-arn "$POLICY_ARN" 2>/dev/null || true

##############################################################################
# 5. Generate one-time access keys
##############################################################################
echo "➤ Creating access key pair (shown only once)…"
CREDS_JSON=$(aws iam create-access-key --user-name "$USER_NAME")
ACCESS_KEY_ID=$(echo "$CREDS_JSON" | jq -r '.AccessKey.AccessKeyId')
SECRET_ACCESS_KEY=$(echo "$CREDS_JSON" | jq -r '.AccessKey.SecretAccessKey')

##############################################################################
# 6. Print exactly what your app or CI needs
##############################################################################
cat <<EOM

====================================================================
✅  Add the following to your secret store or CI/CD environment
====================================================================
AWS_ACCESS_KEY_ID=${ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${SECRET_ACCESS_KEY}

# Primary and fail-over regions your code will try in order
AWS_BEDROCK_REGION1=${REGIONS[0]}
AWS_BEDROCK_REGION2=${REGIONS[1]}

LLM_DEFAULT_PROVIDER=bedrock
LLM_DEFAULT_MODEL=${DEFAULT_MODEL_ID}
LLM_DOCUMENT_RELEVANCY_MODEL=${RELEVANCY_MODEL_ID}
====================================================================

Store the secret key securely!  This is the only time it will be shown.
EOM