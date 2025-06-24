#!/usr/bin/env python3
"""
check_bedrock_access.py  –  sanity-check that the supplied AWS
credentials can invoke a particular Amazon Bedrock model.

❯ python check_bedrock_access.py \
      --access-key AKIA... \
      --secret-key wJalr... \
      --region us-east-1 \
      --model-id anthropic.claude-3-sonnet-20240229-v1
"""

import argparse, json, sys
import boto3
from botocore.exceptions import ClientError

# ---------------------------------------------------------------------------


def build_payload(model_id: str) -> dict:
    """
    Return the smallest legal JSON body for the provider that owns model_id.
    Raise ValueError if we don't recognise the provider prefix.
    """
    provider = model_id.split(".")[0].lower()
    if provider == "anthropic":
        return {
            "anthropic_version": "bedrock-2023-05-31",
            "messages": [{"role": "user", "content": "Hello"}],
            "max_tokens": 1,
        }
    if provider == "meta":
        return {
            "prompt": "Hello",
            "max_gen_len": 1,
            "temperature": 0.01,
            "top_p": 0.5,
        }
    if provider == "ai21":
        return {
            "prompt": "Hello",
            "maxTokens": 1,
            "temperature": 0.0,
            "topP": 0.5,
        }
    if provider == "amazon":
        # Works for Titan-Text Express / Lite
        return {
            "inputText": "Hello",
            "textGenerationConfig": {
                "maxTokenCount": 1,
                "temperature": 0,
                "topP": 0.5,
            },
        }
    raise ValueError(
        f"Don't know how to build a request for provider prefix '{provider}'"
    )


# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(description="Test InvokeModel permission")
    parser.add_argument("--access-key", required=True, help="AWS_ACCESS_KEY_ID")
    parser.add_argument("--secret-key", required=True, help="AWS_SECRET_ACCESS_KEY")
    parser.add_argument("--session-token", help="AWS_SESSION_TOKEN (if any)")
    parser.add_argument(
        "--region", default="us-east-1", help="AWS region that hosts the model"
    )
    parser.add_argument(
        "--model-id", required=True, help="Full Bedrock modelId to test"
    )
    args = parser.parse_args()

    client = boto3.client(
        "bedrock-runtime",
        region_name=args.region,
        aws_access_key_id=args.access_key,
        aws_secret_access_key=args.secret_key,
        aws_session_token=args.session_token,
    )

    try:
        body = json.dumps(build_payload(args.model_id))
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    try:
        client.invoke_model(
            modelId=args.model_id,
            body=body,
            accept="application/json",
            contentType="application/json",
        )
        print(f"✅  Success – principal can invoke {args.model_id} in {args.region}")
        sys.exit(0)

    except ClientError as e:
        code = e.response["Error"]["Code"]
        http = e.response.get("ResponseMetadata", {}).get("HTTPStatusCode")
        if http == 403 or code in ("AccessDeniedException", "ForbiddenException"):
            print(f"❌  Access denied – {code}: {e.response['Error']['Message']}")
            sys.exit(2)
        else:
            print(f"⚠️  Invoke failed ({code}) but not a permission error:")
            print(e.response["Error"]["Message"])
            sys.exit(1)


# ---------------------------------------------------------------------------

if __name__ == "__main__":
    main()
