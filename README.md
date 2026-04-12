# aws-vpc-lambda-rds-fintech

> **Production-ready Terraform infrastructure** for a Fintech market-data pipeline on AWS US East (use-east-1).  
> Connects a Python 3.12 Lambda function to a private RDS PostgreSQL 15.4 instance inside a secure multi-tier VPC.

---

## Architecture

> *A detailed Architecture Diagram will be published shortly*

---

## File Structure

```
aws-vpc-lambda-rds-fintech/
├── main.tf                    # Terraform & provider config
├── variables.tf               # Input variables & locals
├── terraform.tfvars.example   # Variable template (copy → terraform.tfvars)
├── vpc.tf                     # VPC, subnets, IGW, NAT GW, routing
├── security_groups.tf         # Lambda & RDS security groups
├── rds.tf                     # RDS PostgreSQL instance & monitoring
├── lambda.tf                  # Lambda function, IAM role, log group
├── outputs.tf                 # Key resource outputs
├── lambda/
│   └── function.py            # Python 3.12 Lambda handler
└── .gitignore
```

---

## Prerequisites

| Tool        | Minimum Version | Install                        |
|-------------|-----------------|--------------------------------|
| Terraform   | 1.5.0+          | https://developer.hashicorp.com/terraform/downloads |
| AWS CLI     | 2.x             | https://aws.amazon.com/cli/    |
| AWS Profile | Configured      | `aws configure`                |

Your AWS IAM principal needs permissions to manage VPC, EC2, RDS, Lambda, IAM, and CloudWatch resources.

---

## Quick Start

### 1. Clone / navigate to project directory

```bash
cd aws-vpc-lambda-rds-fintech
```

### 2. Create your tfvars file

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — fill in db_username and db_password at minimum
```

### 3. Initialise Terraform

```bash
terraform init
```

### 4. Preview the plan

```bash
terraform plan
```

### 5. Apply infrastructure (~10-15 min due to RDS creation)

```bash
terraform apply
```

Type `yes` when prompted. Note the output values — you will need `lambda_function_name`.

---

## Testing the Lambda Function

### Invoke directly via AWS CLI

```bash
# Basic invocation
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_name) \
  --region use-east-1 \
  --payload '{}' \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json | python3 -m json.tool
```

### Expected response shape

```json
{
  "statusCode": 200,
  "body": {
    "message": "Market data processed successfully",
    "records_inserted": 5,
    "records_returned": 10,
    "total_volume": 50900000,
    "market_data": [
      { "id": 5, "symbol": "LOGI_E", "price": 30.91, "volume": 5600000, "timestamp": "..." },
      ...
    ],
    "processed_at": "2024-04-12T07:45:00Z"
  }
}
```

### View CloudWatch Logs

```bash
aws logs tail $(terraform output -raw lambda_log_group) \
  --region use-east-1 \
  --follow
```

---

## Cost Breakdown (use-east-1 · Monthly Estimate)

| Resource              | Config              | Est. Cost (USD/mo) |
|-----------------------|---------------------|--------------------|
| RDS PostgreSQL        | db.t3.micro, 20 GB  | ~$18 – $22         |
| NAT Gateway           | 1 AZ, low traffic   | ~$36 (fixed)       |
| Lambda                | 256 MB, dev traffic | ~$0 – $1           |
| CloudWatch Logs       | 7-day retention     | ~$0.50             |
| Elastic IP (NAT)      | 1 EIP (in use)      | Free while attached|
| **Total**             |                     | **~$55 – $60**     |

> **Cost tip:** The NAT Gateway dominates cost. For pure dev, consider a NAT Instance (t3.nano ~$4/mo) instead.

---

## Cleanup

```bash
# Destroy ALL resources (data will be lost — no final snapshot in dev config)
terraform destroy
```

Type `yes` to confirm. RDS deletion may take 3–5 minutes.

---

## Security Considerations

- **No public RDS access** — `publicly_accessible = false`
- **Storage encrypted at rest** — KMS default key
- **TLS in transit** — Lambda connects with `sslmode=require`
- **Least-privilege SGs** — Lambda SG can only egress to RDS:5432 + internet:443/80
- **Sensitive outputs** — `db_username` is marked sensitive in Terraform
- **Production recommendations:**
  - Enable automated backups (`backup_retention_period = 7`)
  - Use AWS Secrets Manager instead of env-var credentials
  - Enable Multi-AZ for RDS (`multi_az = true`)
  - Add a second NAT Gateway for HA in prod

---

## Tags Applied to All Resources

| Tag Key    | Example Value                    |
|------------|----------------------------------|
| Project    | aws-vpc-lambda-rds-fintech       |
| Environment| dev                              |
| ManagedBy  | Terraform                        |
| Region     | use-east-1                       |
