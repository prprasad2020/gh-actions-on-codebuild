# GitHub Actions Runner on AWS CodeBuild

This Terraform configuration sets up a self-hosted GitHub Actions runner using AWS CodeBuild.

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5
- GitHub repository where you want to run the actions

## Files

| File | Description |
|------|-------------|
| `versions.tf` | Provider configuration |
| `iam.tf` | IAM roles and policies |
| `codeconnection.tf` | GitHub CodeConnection |
| `logs.tf` | CloudWatch log group |
| `codebuild.tf` | CodeBuild project and webhook |
| `outputs.tf` | Output values |

## Configuration

All values are hardcoded in the respective files. Update these before deploying:

| File | Value | Current Setting |
|------|-------|-----------------|
| `versions.tf` | AWS Region | `us-east-1` |
| `codebuild.tf` | GitHub Org | `priyankarprasad` |
| `codebuild.tf` | GitHub Repo | `donprasad` |
| `codebuild.tf` | Compute Type | `BUILD_GENERAL1_SMALL` |

## Quick Start

1. **Update the GitHub org/repo in `codebuild.tf`** (line 44)

2. **Initialize Terraform:**
   ```bash
   terraform init
   ```

3. **Review the plan:**
   ```bash
   terraform plan
   ```

4. **Apply the configuration:**
   ```bash
   terraform apply
   ```

5. **Activate the CodeConnection:**
   
   After applying, complete the GitHub OAuth handshake:
   - Go to AWS Console > Developer Tools > Connections
   - Click on your connection and complete the GitHub authorization

## Using in GitHub Actions

Once set up, use the runner in your workflows:

```yaml
name: Build with CodeBuild

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: [codebuild, aws, self-hosted]
    
    container:
      image: node:18-alpine
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Build
        run: npm install && npm run build
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

## References

- [AWS CodeBuild Documentation](https://docs.aws.amazon.com/codebuild/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Blog Post: Running GitHub Actions on AWS CodeBuild](./github-actions-codebuild-terraform.md)
