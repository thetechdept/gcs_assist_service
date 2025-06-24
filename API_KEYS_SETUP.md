# AI Service API Keys Configuration Guide

This document explains how to configure API keys for various AI services in the GCS Assist Service.

## Overview

The application supports multiple AI service providers:

- **AWS Bedrock** (default) - Uses AWS credentials/IAM roles
- **OpenAI** - Requires API key
- **Anthropic** - Requires API key (for direct API usage)
- **Cohere** - Requires API key
- **Hugging Face** - Requires API key

## Configuration Files

### Environment Variables

API keys are configured through environment variables in the following files:

- **`.env.local`** - Local development configuration (gitignored)
- **`.env`** - Development defaults (gitignored)
- **Production** - Set as environment variables in your deployment platform

### Configuration Loading

The `app/config.py` file loads and validates API keys:

- Loads environment variables using `python-dotenv`
- Validates required keys based on the configured provider
- Logs warnings for missing keys without failing startup

## Setting Up API Keys

### 1. Development Setup

Edit `.env.local` and uncomment/set the appropriate keys:

```bash
### OpenAI Configuration
OPENAI_API_KEY=sk-your_openai_api_key_here
OPENAI_ORG_ID=org-your_openai_org_id_here

### Anthropic Configuration (for direct API usage, not Bedrock)
ANTHROPIC_API_KEY=sk-ant-your_anthropic_api_key_here

### Other AI Service Keys
COHERE_API_KEY=your_cohere_api_key_here
HUGGINGFACE_API_KEY=hf_your_huggingface_api_key_here
```

### 2. Production Setup

Set environment variables in your deployment platform:

**Docker Compose:**

```yaml
environment:
  - OPENAI_API_KEY=sk-your_openai_api_key_here
  - OPENAI_ORG_ID=org-your_openai_org_id_here
```

**Kubernetes:**

```yaml
env:
  - name: OPENAI_API_KEY
    valueFrom:
      secretKeyRef:
        name: ai-service-secrets
        key: openai-api-key
```

**AWS ECS/Fargate:**

```json
{
  "environment": [
    {
      "name": "OPENAI_API_KEY",
      "value": "sk-your_openai_api_key_here"
    }
  ]
}
```

## Provider Configuration

### Switching AI Providers

To change the default AI provider, set the `LLM_DEFAULT_PROVIDER` environment variable:

```bash
# Use OpenAI instead of Bedrock
LLM_DEFAULT_PROVIDER=openai

# Use Anthropic direct API
LLM_DEFAULT_PROVIDER=anthropic
```

### AWS Bedrock (Default)

- **No API key required**
- Uses AWS credentials from:
  - AWS CLI configuration (`~/.aws/credentials`)
  - IAM roles (recommended for production)
  - Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)

### OpenAI

- **Required:** `OPENAI_API_KEY`
- **Optional:** `OPENAI_ORG_ID`
- Get your API key from: https://platform.openai.com/api-keys

### Anthropic

- **Required:** `ANTHROPIC_API_KEY`
- Get your API key from: https://console.anthropic.com/

## Security Best Practices

### 1. Never Commit API Keys

- API keys are automatically excluded by `.gitignore`
- Use environment variables or secure secret management
- Rotate keys regularly

### 2. Use Different Keys for Different Environments

- Separate development, staging, and production keys
- Use lower-tier keys for development/testing

### 3. Implement Key Rotation

- Set up automated key rotation where possible
- Monitor key usage and expiration dates

### 4. Use IAM Roles When Possible

- For AWS Bedrock, prefer IAM roles over API keys
- Reduces key management overhead
- Better security through temporary credentials

## Validation and Troubleshooting

### Startup Validation

The application validates API keys at startup:

- Logs warnings for missing keys (doesn't fail startup)
- Validates keys based on the configured provider
- Check application logs for validation messages

### Common Issues

**Missing API Key Warning:**

```
WARNING: OpenAI API key not found. Set OPENAI_API_KEY environment variable.
```

**Solution:** Set the required environment variable for your chosen provider.

**Invalid API Key:**

- Check the key format and validity
- Ensure the key has the correct permissions
- Verify the key hasn't expired

### Testing Configuration

You can test your configuration by:

1. Starting the application
2. Checking the startup logs for validation messages
3. Making a test API call to verify the AI service works

## Environment Variable Reference

| Variable               | Required | Provider     | Description                                      |
| ---------------------- | -------- | ------------ | ------------------------------------------------ |
| `LLM_DEFAULT_PROVIDER` | No       | All          | Default AI provider (bedrock, openai, anthropic) |
| `OPENAI_API_KEY`       | Yes\*    | OpenAI       | OpenAI API key                                   |
| `OPENAI_ORG_ID`        | No       | OpenAI       | OpenAI organization ID                           |
| `ANTHROPIC_API_KEY`    | Yes\*    | Anthropic    | Anthropic API key                                |
| `COHERE_API_KEY`       | Yes\*    | Cohere       | Cohere API key                                   |
| `HUGGINGFACE_API_KEY`  | Yes\*    | Hugging Face | Hugging Face API key                             |

\*Required only when using the corresponding provider

## Support

For issues with API key configuration:

1. Check the application startup logs
2. Verify environment variables are set correctly
3. Test API keys directly with the provider's API
4. Consult the provider's documentation for key format and requirements
