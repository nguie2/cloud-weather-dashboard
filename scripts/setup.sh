#!/bin/bash

# Multi-Cloud Weather Dashboard Setup Script
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Multi-Cloud Weather Dashboard Setup Script

Usage: $0 [OPTIONS]

Options:
    --install-tools     Install required tools (Node.js, Terraform, Cloud CLIs)
    --setup-env        Create environment file from template
    --install-deps     Install Node.js dependencies
    --init-terraform   Initialize Terraform modules
    --all              Run all setup steps
    -h, --help         Show this help message

Examples:
    $0 --all                    Run complete setup
    $0 --install-tools          Install only required tools
    $0 --setup-env             Create .env file from template

EOF
}

# Function to detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get >/dev/null 2>&1; then
            echo "ubuntu"
        elif command -v yum >/dev/null 2>&1; then
            echo "centos"
        else
            echo "linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
        echo "windows"
    else
        echo "unknown"
    fi
}

# Function to install Node.js
install_nodejs() {
    local os=$(detect_os)
    
    if command -v node >/dev/null 2>&1; then
        local node_version=$(node --version)
        print_success "Node.js already installed: $node_version"
        return 0
    fi
    
    print_status "Installing Node.js..."
    
    case $os in
        ubuntu)
            curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
            sudo apt-get install -y nodejs
            ;;
        centos)
            curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
            sudo yum install -y nodejs npm
            ;;
        macos)
            if command -v brew >/dev/null 2>&1; then
                brew install node
            else
                print_error "Homebrew not found. Please install Node.js manually from https://nodejs.org/"
                return 1
            fi
            ;;
        windows)
            print_error "Please install Node.js manually from https://nodejs.org/"
            return 1
            ;;
        *)
            print_error "Unsupported OS. Please install Node.js manually from https://nodejs.org/"
            return 1
            ;;
    esac
    
    print_success "Node.js installed successfully"
}

# Function to install Terraform
install_terraform() {
    if command -v terraform >/dev/null 2>&1; then
        local tf_version=$(terraform version | head -n1)
        print_success "Terraform already installed: $tf_version"
        return 0
    fi
    
    print_status "Installing Terraform..."
    
    local os=$(detect_os)
    local arch=$(uname -m)
    
    # Map architecture
    case $arch in
        x86_64) arch="amd64" ;;
        arm64|aarch64) arch="arm64" ;;
        *) print_error "Unsupported architecture: $arch"; return 1 ;;
    esac
    
    # Map OS
    case $os in
        ubuntu|centos|linux) os_name="linux" ;;
        macos) os_name="darwin" ;;
        windows) os_name="windows" ;;
        *) print_error "Unsupported OS for Terraform installation"; return 1 ;;
    esac
    
    # Download and install
    local tf_version="1.6.6"
    local tf_zip="terraform_${tf_version}_${os_name}_${arch}.zip"
    local tf_url="https://releases.hashicorp.com/terraform/${tf_version}/${tf_zip}"
    
    curl -LO "$tf_url"
    unzip "$tf_zip"
    sudo mv terraform /usr/local/bin/
    rm "$tf_zip"
    
    print_success "Terraform installed successfully"
}

# Function to install AWS CLI
install_aws_cli() {
    if command -v aws >/dev/null 2>&1; then
        local aws_version=$(aws --version)
        print_success "AWS CLI already installed: $aws_version"
        return 0
    fi
    
    print_status "Installing AWS CLI..."
    
    local os=$(detect_os)
    
    case $os in
        ubuntu|centos|linux)
            curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
            unzip awscliv2.zip
            sudo ./aws/install
            rm -rf aws awscliv2.zip
            ;;
        macos)
            if command -v brew >/dev/null 2>&1; then
                brew install awscli
            else
                curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
                sudo installer -pkg AWSCLIV2.pkg -target /
                rm AWSCLIV2.pkg
            fi
            ;;
        *)
            print_error "Please install AWS CLI manually from https://aws.amazon.com/cli/"
            return 1
            ;;
    esac
    
    print_success "AWS CLI installed successfully"
}

# Function to install Azure CLI
install_azure_cli() {
    if command -v az >/dev/null 2>&1; then
        local az_version=$(az version --output table | head -n3 | tail -n1)
        print_success "Azure CLI already installed: $az_version"
        return 0
    fi
    
    print_status "Installing Azure CLI..."
    
    local os=$(detect_os)
    
    case $os in
        ubuntu)
            curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
            ;;
        centos)
            sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            sudo sh -c 'echo -e "[azure-cli]
name=Azure CLI
baseurl=https://packages.microsoft.com/yumrepos/azure-cli
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/azure-cli.repo'
            sudo yum install azure-cli
            ;;
        macos)
            if command -v brew >/dev/null 2>&1; then
                brew install azure-cli
            else
                print_error "Please install Azure CLI manually from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
                return 1
            fi
            ;;
        *)
            print_error "Please install Azure CLI manually from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
            return 1
            ;;
    esac
    
    print_success "Azure CLI installed successfully"
}

# Function to install Google Cloud CLI
install_gcloud_cli() {
    if command -v gcloud >/dev/null 2>&1; then
        local gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null)
        print_success "Google Cloud CLI already installed: $gcloud_version"
        return 0
    fi
    
    print_status "Installing Google Cloud CLI..."
    
    local os=$(detect_os)
    
    case $os in
        ubuntu|centos|linux)
            curl https://sdk.cloud.google.com | bash
            exec -l $SHELL
            ;;
        macos)
            if command -v brew >/dev/null 2>&1; then
                brew install google-cloud-sdk
            else
                curl https://sdk.cloud.google.com | bash
                exec -l $SHELL
            fi
            ;;
        *)
            print_error "Please install Google Cloud CLI manually from https://cloud.google.com/sdk/docs/install"
            return 1
            ;;
    esac
    
    print_success "Google Cloud CLI installed successfully"
}

# Function to install Docker
install_docker() {
    if command -v docker >/dev/null 2>&1; then
        local docker_version=$(docker --version)
        print_success "Docker already installed: $docker_version"
        return 0
    fi
    
    print_status "Installing Docker..."
    
    local os=$(detect_os)
    
    case $os in
        ubuntu)
            sudo apt-get update
            sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io
            sudo usermod -aG docker $USER
            ;;
        centos)
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo yum install -y docker-ce docker-ce-cli containerd.io
            sudo systemctl start docker
            sudo systemctl enable docker
            sudo usermod -aG docker $USER
            ;;
        macos)
            if command -v brew >/dev/null 2>&1; then
                brew install --cask docker
                print_warning "Please start Docker Desktop manually"
            else
                print_error "Please install Docker Desktop manually from https://www.docker.com/products/docker-desktop"
                return 1
            fi
            ;;
        *)
            print_error "Please install Docker manually from https://docs.docker.com/get-docker/"
            return 1
            ;;
    esac
    
    print_success "Docker installed successfully"
    print_warning "You may need to log out and back in for Docker permissions to take effect"
}

# Function to setup environment file
setup_environment() {
    print_status "Setting up environment file..."
    
    local env_file="$ROOT_DIR/.env"
    local env_example="$ROOT_DIR/.env.example"
    
    if [[ -f "$env_file" ]]; then
        print_warning ".env file already exists"
        echo -n "Overwrite existing .env file? [y/N]: "
        read -r response
        case "$response" in
            [yY][eE][sS]|[yY]) 
                ;;
            *)
                print_status "Keeping existing .env file"
                return 0
                ;;
        esac
    fi
    
    if [[ ! -f "$env_example" ]]; then
        print_error ".env.example file not found"
        return 1
    fi
    
    cp "$env_example" "$env_file"
    
    print_success "Created .env file from template"
    print_warning "Please edit .env file and add your API keys and credentials"
    print_status "Required API keys:"
    print_status "  - OpenWeather API: https://openweathermap.org/api"
    print_status "  - WeatherAPI: https://www.weatherapi.com/"
    print_status "  - AccuWeather API: https://developer.accuweather.com/"
}

# Function to install Node.js dependencies
install_dependencies() {
    print_status "Installing Node.js dependencies..."
    
    cd "$ROOT_DIR"
    
    # Install main dependencies
    npm ci
    
    # Install Lambda function dependencies
    for lambda_dir in lambda/aws lambda/azure lambda/gcp lambda/aggregation; do
        if [[ -d "$lambda_dir" && -f "$lambda_dir/package.json" ]]; then
            print_status "Installing dependencies for $lambda_dir..."
            cd "$ROOT_DIR/$lambda_dir"
            npm ci
            cd "$ROOT_DIR"
        fi
    done
    
    print_success "All dependencies installed successfully"
}

# Function to initialize Terraform
init_terraform() {
    print_status "Initializing Terraform modules..."
    
    for tf_dir in terraform/aws terraform/azure terraform/gcp; do
        if [[ -d "$ROOT_DIR/$tf_dir" ]]; then
            print_status "Initializing $tf_dir..."
            cd "$ROOT_DIR/$tf_dir"
            terraform init
            cd "$ROOT_DIR"
        fi
    done
    
    print_success "Terraform modules initialized successfully"
}

# Function to run all setup steps
setup_all() {
    print_status "Running complete setup..."
    
    install_nodejs
    install_terraform
    install_aws_cli
    install_azure_cli
    install_gcloud_cli
    install_docker
    setup_environment
    install_dependencies
    init_terraform
    
    print_success "Setup completed successfully!"
    print_status ""
    print_status "Next steps:"
    print_status "1. Edit .env file with your API keys and credentials"
    print_status "2. Configure cloud provider authentication:"
    print_status "   - AWS: aws configure"
    print_status "   - Azure: az login"
    print_status "   - GCP: gcloud auth login && gcloud auth application-default login"
    print_status "3. Run deployment: ./scripts/deploy.sh"
}

# Main function
main() {
    # Parse command line arguments
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 1
    fi
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --install-tools)
                install_nodejs
                install_terraform
                install_aws_cli
                install_azure_cli
                install_gcloud_cli
                install_docker
                shift
                ;;
            --setup-env)
                setup_environment
                shift
                ;;
            --install-deps)
                install_dependencies
                shift
                ;;
            --init-terraform)
                init_terraform
                shift
                ;;
            --all)
                setup_all
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
}

# Run main function with all arguments
main "$@" 