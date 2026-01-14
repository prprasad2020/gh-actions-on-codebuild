output "codebuild_project_name" {
  description = "Name of the CodeBuild project"
  value       = aws_codebuild_project.github_actions_runner.name
}

output "codebuild_project_arn" {
  description = "ARN of the CodeBuild project"
  value       = aws_codebuild_project.github_actions_runner.arn
}

output "codeconnection_arn" {
  description = "ARN of the CodeConnection (needs manual activation)"
  value       = aws_codestarconnections_connection.github.arn
}

output "codebuild_role_arn" {
  description = "ARN of the CodeBuild IAM role"
  value       = aws_iam_role.codebuild_role.arn
}

output "runner_labels" {
  description = "Labels to use in GitHub Actions runs-on"
  value       = ["codebuild", "aws", "self-hosted"]
}

output "setup_instructions" {
  description = "Instructions to complete the setup"
  value       = <<-EOT
    
    1. Activate the CodeConnection:
       aws codestar-connections update-connection-status \
         --connection-arn ${aws_codestarconnections_connection.github.arn} \
         --status AVAILABLE
    
    2. In your GitHub repository, go to Settings > Secrets and Variables > Actions
       Add the following repository variable:
       - Name: AWS_CODEBUILD_PROJECT
       - Value: ${aws_codebuild_project.github_actions_runner.name}
    
    3. Use in your workflow:
       runs-on: codebuild, aws, self-hosted
  EOT
}
