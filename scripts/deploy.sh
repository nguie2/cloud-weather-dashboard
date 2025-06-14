#!/bin/bash

# Multi-Cloud Weather Dashboard Deployment Script
# Author: Nguie Angoue Jean Roch Junior <nguierochjunior@gmail.com>
# Version: 1.0.0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="cloud-weather-dashboard"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$ROOT_DIR/deployment.log"

# Default values
DEPLOY_TARGET="all"
SKIP_TESTS=false
SKIP_BUILD=false
FORCE_DEPLOY=false
DRY_RUN=false

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Function to show usage
show_usage() {
    cat << EOF
Multi-Cloud Weather Dashboard Deployment Script

Usage: $0 [OPTIONS]

Options:
    -t, --target TARGET     Deployment target: all, aws, azure, gcp, frontend
    -s, --skip-tests        Skip running tests
    -b, --skip-build        Skip build step
    -f, --force             Force deployment without confirmation
    -d, --dry-run           Show what would be deployed without actually deploying
    -h, --help              Show this help message

Examples:
    $0                      Deploy to all cloud providers
    $0 -t aws               Deploy only to AWS
    $0 -t frontend          Deploy only the frontend
    $0 -s -f                Skip tests and force deploy to all
    $0 -d                   Dry run to see what would be deployed

Environment Variables Required:
    AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION
    AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID
    GCP_PROJECT_ID, GOOGLE_APPLICATION_CREDENTIALS
    OPENWEATHER_API_KEY, WEATHER_API_KEY, ACCUWEATHER_API_KEY

EOF
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check required tools
    command -v node >/dev/null 2>&1 || missing_tools+=("node")
    command -v npm >/dev/null 2>&1 || missing_tools+=("npm")
    command -v terraform >/dev/null 2>&1 || missing_tools+=("terraform")
    
    if [[ "$DEPLOY_TARGET" == "all" || "$DEPLOY_TARGET" == "aws" ]]; then
        command -v aws >/dev/null 2>&1 || missing_tools+=("aws-cli")
    fi
    
    if [[ "$DEPLOY_TARGET" == "all" || "$DEPLOY_TARGET" == "azure" ]]; then
        command -v az >/dev/null 2>&1 || missing_tools+=("azure-cli")
    fi
    
    if [[ "$DEPLOY_TARGET" == "all" || "$DEPLOY_TARGET" == "gcp" ]]; then
        command -v gcloud >/dev/null 2>&1 || missing_tools+=("gcloud")
        command -v docker >/dev/null 2>&1 || missing_tools+=("docker")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_error "Please install the missing tools and try again."
        exit 1
    fi
    
    print_success "All required tools are available"
}

# Function to check environment variables
check_environment() {
    print_status "Checking environment variables..."
    
    local missing_vars=()
    
    # Weather API keys (required for all deployments)
    [[ -z "$OPENWEATHER_API_KEY" ]] && missing_vars+=("OPENWEATHER_API_KEY")
    [[ -z "$WEATHER_API_KEY" ]] && missing_vars+=("WEATHER_API_KEY")
    [[ -z "$ACCUWEATHER_API_KEY" ]] && missing_vars+=("ACCUWEATHER_API_KEY")
    
    # AWS specific
    if [[ "$DEPLOY_TARGET" == "all" || "$DEPLOY_TARGET" == "aws" ]]; then
        [[ -z "$AWS_ACCESS_KEY_ID" ]] && missing_vars+=("AWS_ACCESS_KEY_ID")
        [[ -z "$AWS_SECRET_ACCESS_KEY" ]] && missing_vars+=("AWS_SECRET_ACCESS_KEY")
        [[ -z "$AWS_REGION" ]] && missing_vars+=("AWS_REGION")
    fi
    
    # Azure specific
    if [[ "$DEPLOY_TARGET" == "all" || "$DEPLOY_TARGET" == "azure" ]]; then
        [[ -z "$AZURE_CLIENT_ID" ]] && missing_vars+=("AZURE_CLIENT_ID")
        [[ -z "$AZURE_CLIENT_SECRET" ]] && missing_vars+=("AZURE_CLIENT_SECRET")
        [[ -z "$AZURE_TENANT_ID" ]] && missing_vars+=("AZURE_TENANT_ID")
        [[ -z "$AZURE_SUBSCRIPTION_ID" ]] && missing_vars+=("AZURE_SUBSCRIPTION_ID")
    fi
    
    # GCP specific
    if [[ "$DEPLOY_TARGET" == "all" || "$DEPLOY_TARGET" == "gcp" ]]; then
        [[ -z "$GCP_PROJECT_ID" ]] && missing_vars+=("GCP_PROJECT_ID")
        [[ -z "$GOOGLE_APPLICATION_CREDENTIALS" ]] && missing_vars+=("GOOGLE_APPLICATION_CREDENTIALS")
    fi
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        print_error "Missing required environment variables: ${missing_vars[*]}"
        print_error "Please set the missing variables and try again."
        print_error "See .env.example for reference."
        exit 1
    fi
    
    print_success "All required environment variables are set"
}

# Function to run tests
run_tests() {
    if [[ "$SKIP_TESTS" == true ]]; then
        print_warning "Skipping tests as requested"
        return 0
    fi
    
    print_status "Running tests..."
    cd "$ROOT_DIR"
    
    if ! npm test; then
        print_error "Tests failed"
        return 1
    fi
    
    print_success "All tests passed"
}

# Function to build application
build_application() {
    if [[ "$SKIP_BUILD" == true ]]; then
        print_warning "Skipping build as requested"
        return 0
    fi
    
    print_status "Building application..."
    cd "$ROOT_DIR"
    
    # Install dependencies
    npm ci
    
    # Build Next.js application
    npm run build
    
    # Build Lambda functions
    for lambda_dir in lambda/aws lambda/azure lambda/gcp lambda/aggregation; do
        if [[ -d "$lambda_dir" ]]; then
            print_status "Building $lambda_dir..."
            cd "$ROOT_DIR/$lambda_dir"
            npm ci --production
            cd "$ROOT_DIR"
        fi
    done
    
    print_success "Application built successfully"
}

# Function to deploy to AWS
deploy_aws() {
    print_status "Deploying to AWS..."
    
    if [[ "$DRY_RUN" == true ]]; then
        print_status "DRY RUN: Would deploy AWS resources with Terraform"
        return 0
    fi
    
    cd "$ROOT_DIR/terraform/aws"
    
    # Initialize Terraform
    terraform init
    
    # Plan deployment
    terraform plan \
        -var="openweather_api_key=$OPENWEATHER_API_KEY" \
        -var="weather_api_key=$WEATHER_API_KEY" \
        -var="accuweather_api_key=$ACCUWEATHER_API_KEY" \
        -out=tfplan
    
    # Apply if not dry run
    if [[ "$FORCE_DEPLOY" == true ]] || confirm_deployment "AWS"; then
        terraform apply tfplan
        
        # Export outputs
        export AWS_API_URL=$(terraform output -raw api_gateway_url)
        print_success "AWS deployment completed. API URL: $AWS_API_URL"
    else
        print_warning "AWS deployment cancelled by user"
        return 1
    fi
}

# Function to deploy to Azure
deploy_azure() {
    print_status "Deploying to Azure..."
    
    if [[ "$DRY_RUN" == true ]]; then
        print_status "DRY RUN: Would deploy Azure resources with Terraform"
        return 0
    fi
    
    # Login to Azure
    az login --service-principal \
        --username "$AZURE_CLIENT_ID" \
        --password "$AZURE_CLIENT_SECRET" \
        --tenant "$AZURE_TENANT_ID"
    
    az account set --subscription "$AZURE_SUBSCRIPTION_ID"
    
    cd "$ROOT_DIR/terraform/azure"
    
    # Initialize Terraform
    terraform init
    
    # Plan deployment
    terraform plan \
        -var="openweather_api_key=$OPENWEATHER_API_KEY" \
        -var="weather_api_key=$WEATHER_API_KEY" \
        -var="accuweather_api_key=$ACCUWEATHER_API_KEY" \
        -out=tfplan
    
    # Apply if not dry run
    if [[ "$FORCE_DEPLOY" == true ]] || confirm_deployment "Azure"; then
        terraform apply tfplan
        
        # Deploy function code
        cd "$ROOT_DIR/lambda/azure"
        zip -r function.zip . -x "node_modules/*"
        
        RESOURCE_GROUP=$(cd "$ROOT_DIR/terraform/azure" && terraform output -raw resource_group_name)
        FUNCTION_APP=$(cd "$ROOT_DIR/terraform/azure" && terraform output -raw function_app_name)
        
        az functionapp deployment source config-zip \
            --resource-group "$RESOURCE_GROUP" \
            --name "$FUNCTION_APP" \
            --src function.zip
        
        # Export outputs
        export AZURE_API_URL=$(cd "$ROOT_DIR/terraform/azure" && terraform output -raw function_app_url)
        print_success "Azure deployment completed. API URL: $AZURE_API_URL"
    else
        print_warning "Azure deployment cancelled by user"
        return 1
    fi
}

# Function to deploy to GCP
deploy_gcp() {
    print_status "Deploying to GCP..."
    
    if [[ "$DRY_RUN" == true ]]; then
        print_status "DRY RUN: Would deploy GCP resources with Terraform and Cloud Run"
        return 0
    fi
    
    # Authenticate with GCP
    gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS"
    gcloud config set project "$GCP_PROJECT_ID"
    
    cd "$ROOT_DIR/terraform/gcp"
    
    # Initialize Terraform
    terraform init
    
    # Plan deployment
    terraform plan \
        -var="gcp_project_id=$GCP_PROJECT_ID" \
        -var="openweather_api_key=$OPENWEATHER_API_KEY" \
        -var="weather_api_key=$WEATHER_API_KEY" \
        -var="accuweather_api_key=$ACCUWEATHER_API_KEY" \
        -out=tfplan
    
    # Apply if not dry run
    if [[ "$FORCE_DEPLOY" == true ]] || confirm_deployment "GCP"; then
        terraform apply tfplan
        
        # Configure Docker for Artifact Registry
        REGION=$(terraform output -raw project_id | cut -d'-' -f2 || echo "us-central1")
        gcloud auth configure-docker "$REGION-docker.pkg.dev"
        
        # Build and push Docker image
        cd "$ROOT_DIR"
        IMAGE_NAME="$REGION-docker.pkg.dev/$GCP_PROJECT_ID/$PROJECT_NAME-repo/weather-function:$(date +%s)"
        
        docker build -t "$IMAGE_NAME" -f docker/gcp/Dockerfile .
        docker push "$IMAGE_NAME"
        
        # Deploy to Cloud Run
        gcloud run deploy "$PROJECT_NAME-weather-function" \
            --image "$IMAGE_NAME" \
            --region "$REGION" \
            --platform managed \
            --allow-unauthenticated
        
        # Export outputs
        export GCP_API_URL=$(gcloud run services describe "$PROJECT_NAME-weather-function" \
            --region="$REGION" --format="value(status.url)")
        print_success "GCP deployment completed. API URL: $GCP_API_URL"
    else
        print_warning "GCP deployment cancelled by user"
        return 1
    fi
}

# Function to deploy frontend
deploy_frontend() {
    print_status "Deploying frontend..."
    
    if [[ "$DRY_RUN" == true ]]; then
        print_status "DRY RUN: Would deploy frontend to Vercel"
        return 0
    fi
    
    cd "$ROOT_DIR"
    
    # Set API URLs for build
    export NEXT_PUBLIC_AWS_API_URL="$AWS_API_URL"
    export NEXT_PUBLIC_AZURE_API_URL="$AZURE_API_URL"
    export NEXT_PUBLIC_GCP_API_URL="$GCP_API_URL"
    
    # Build with environment variables
    npm run build
    
    # Deploy to Vercel (requires Vercel CLI and authentication)
    if command -v vercel >/dev/null 2>&1; then
        vercel --prod --yes
        print_success "Frontend deployed to Vercel"
    else
        print_warning "Vercel CLI not found. Please deploy frontend manually or install Vercel CLI"
        print_status "Frontend build completed and ready for deployment"
    fi
}

# Function to confirm deployment
confirm_deployment() {
    local target="$1"
    
    if [[ "$FORCE_DEPLOY" == true ]]; then
        return 0
    fi
    
    echo -n "Deploy to $target? [y/N]: "
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to cleanup on exit
cleanup() {
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        print_error "Deployment failed with exit code $exit_code"
        print_error "Check $LOG_FILE for details"
    fi
    
    # Cleanup temporary files
    find "$ROOT_DIR" -name "tfplan" -delete 2>/dev/null || true
    find "$ROOT_DIR" -name "function.zip" -delete 2>/dev/null || true
    
    exit $exit_code
}

# Main deployment function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--target)
                DEPLOY_TARGET="$2"
                shift 2
                ;;
            -s|--skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            -b|--skip-build)
                SKIP_BUILD=true
                shift
                ;;
            -f|--force)
                FORCE_DEPLOY=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Validate deployment target
    case "$DEPLOY_TARGET" in
        all|aws|azure|gcp|frontend)
            ;;
        *)
            print_error "Invalid deployment target: $DEPLOY_TARGET"
            print_error "Valid targets: all, aws, azure, gcp, frontend"
            exit 1
            ;;
    esac
    
    # Setup logging
    echo "=== Multi-Cloud Weather Dashboard Deployment ===" > "$LOG_FILE"
    echo "Date: $(date)" >> "$LOG_FILE"
    echo "Target: $DEPLOY_TARGET" >> "$LOG_FILE"
    echo "=============================================" >> "$LOG_FILE"
    
    print_status "Starting deployment to: $DEPLOY_TARGET"
    print_status "Log file: $LOG_FILE"
    
    if [[ "$DRY_RUN" == true ]]; then
        print_warning "DRY RUN MODE - No actual deployments will be performed"
    fi
    
    # Set trap for cleanup
    trap cleanup EXIT
    
    # Run checks
    check_prerequisites
    check_environment
    
    # Run tests and build
    run_tests
    build_application
    
    # Deploy based on target
    case "$DEPLOY_TARGET" in
        all)
            deploy_aws
            deploy_azure
            deploy_gcp
            deploy_frontend
            ;;
        aws)
            deploy_aws
            ;;
        azure)
            deploy_azure
            ;;
        gcp)
            deploy_gcp
            ;;
        frontend)
            deploy_frontend
            ;;
    esac
    
    print_success "Deployment completed successfully!"
    
    # Show summary
    echo ""
    print_status "=== Deployment Summary ==="
    [[ -n "$AWS_API_URL" ]] && print_status "AWS API: $AWS_API_URL"
    [[ -n "$AZURE_API_URL" ]] && print_status "Azure API: $AZURE_API_URL"
    [[ -n "$GCP_API_URL" ]] && print_status "GCP API: $GCP_API_URL"
    print_status "=========================="
}

# Run main function with all arguments
main "$@" 