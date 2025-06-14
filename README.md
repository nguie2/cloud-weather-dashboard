# Multi-Cloud Weather API Backend

A serverless weather API backend that aggregates weather data from AWS, Azure, and Google Cloud Platform in parallel, providing reliable weather data through RESTful APIs with global redundancy.

**Author**: Nguie Angoue Jean Roch Junior  
**Email**: nguierochjunior@gmail.com  
**License**: MIT

![Multi-Cloud Weather API](https://img.shields.io/badge/Multi--Cloud-Weather%20API-blue?style=for-the-badge)
![TypeScript](https://img.shields.io/badge/TypeScript-5.0-blue?style=flat-square&logo=typescript)
![AWS](https://img.shields.io/badge/AWS-Lambda-orange?style=flat-square&logo=amazon-aws)
![Azure](https://img.shields.io/badge/Azure-Functions-blue?style=flat-square&logo=microsoft-azure)
![GCP](https://img.shields.io/badge/GCP-Cloud%20Run-green?style=flat-square&logo=google-cloud)

## 🌟 Features

### ☁️ **Multi-Cloud Architecture**
- **AWS Integration**: Lambda functions with DynamoDB storage
- **Azure Integration**: Function Apps with CosmosDB storage
- **GCP Integration**: Cloud Run services with Firestore storage
- **Cross-Cloud Consensus**: Data agreement scoring and validation
- **Automatic Failover**: Seamless switching between cloud providers

### 📊 **API Features**
- **RESTful APIs**: Clean, well-documented endpoints
- **Data Aggregation**: Cross-cloud weather data consolidation
- **Real-time Processing**: Live weather data from multiple sources
- **Error Handling**: Comprehensive error responses and retry logic
- **Performance Monitoring**: Response time tracking and health checks

### 🔧 **Infrastructure**
- **Infrastructure as Code**: Complete Terraform modules for all clouds
- **Serverless Architecture**: Auto-scaling, pay-per-use functions
- **Database Replication**: Multi-cloud data synchronization
- **CI/CD Pipeline**: Automated deployment workflows

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   AWS Lambda    │    │ Azure Functions │    │ GCP Cloud Run   │
│   Weather API   │    │   Weather API   │    │   Weather API   │
└─────────┬───────┘    └─────────┬───────┘    └─────────┬───────┘
          │                      │                      │
          ▼                      ▼                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                Cross-Cloud Aggregation Lambda                   │
│              (Data Consolidation & Processing)                  │
└─────────────────────┬───────────────────────────────────────────┘
                      │
    ┌─────────────────┼─────────────────┐
    ▼                 ▼                 ▼
┌──────────┐   ┌─────────────┐   ┌─────────────┐
│ DynamoDB │   │  CosmosDB   │   │  Firestore  │
│ (Primary)│   │ (Secondary) │   │ (Tertiary)  │
└──────────┘   └─────────────┘   └─────────────┘
```

## 🚀 Quick Start

### Prerequisites

- **Node.js** >= 18.0.0
- **npm** or **yarn**
- **Terraform** >= 1.0
- **AWS CLI** configured
- **Azure CLI** logged in
- **Google Cloud SDK** authenticated

### 1. Clone and Setup

```bash
git clone https://github.com/nguieangoue/cloud-weather-dashboard.git
cd cloud-weather-dashboard
npm install
```

### 2. Environment Configuration

```bash
cp .env.example .env
```

Edit `.env` with your configuration:

```env
# Weather API Keys
OPENWEATHER_API_KEY=your_openweather_api_key
WEATHER_API_KEY=your_weatherapi_key
ACCUWEATHER_API_KEY=your_accuweather_api_key

# Cloud Provider Configurations
AWS_REGION=us-east-1
AZURE_REGION=eastus
GCP_REGION=us-central1

# Database Connections
DYNAMODB_TABLE=weather-data
COSMOSDB_CONNECTION_STRING=your_cosmosdb_connection_string
FIRESTORE_PROJECT_ID=your_gcp_project_id
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform for all clouds
npm run tf:init

# Plan deployments
npm run tf:plan

# Deploy to all cloud providers
npm run deploy:all
```

## 🛠️ Development

### Project Structure

```
cloud-weather-dashboard/
├── src/
│   └── app/
│       └── api/               # API routes
│           ├── aggregation/   # Cross-cloud aggregation
│           └── aws/          # AWS-specific endpoints
├── lambda/                    # Serverless functions
│   ├── aws/                  # AWS Lambda functions
│   ├── azure/                # Azure Functions
│   ├── gcp/                  # GCP Cloud Functions
│   └── aggregation/          # Cross-cloud aggregation
├── terraform/                 # Infrastructure as Code
│   ├── aws/                  # AWS resources
│   ├── azure/                # Azure resources
│   └── gcp/                  # GCP resources
└── scripts/                   # Deployment scripts
```

### Available Scripts

```bash
# Development
npm run type-check      # TypeScript type checking
npm run build:lambda    # Build Lambda functions
npm run test:api        # Test API endpoints

# Infrastructure
npm run tf:init         # Initialize Terraform
npm run tf:plan         # Plan infrastructure changes
npm run deploy:aws      # Deploy AWS resources
npm run deploy:azure    # Deploy Azure resources
npm run deploy:gcp      # Deploy GCP resources
npm run deploy:all      # Deploy to all clouds
npm run tf:destroy      # Destroy all infrastructure
```

## 🌐 API Endpoints

### Aggregation API

- **GET** `/api/aggregation/weather?location={location}`
  - Returns consolidated weather data from all available cloud providers
  - Includes data agreement scoring and provider status

### Individual Provider APIs

- **GET** `/api/aws/weather?location={location}`
  - Direct access to AWS Lambda weather data
  
### Response Format

```json
{
  "aggregatedData": {
    "locations": [
      {
        "locationId": "new-york-ny",
        "locationName": "New York, NY",
        "lat": 40.7128,
        "lon": -74.0060,
        "agreement": 95,
        "consensus": {
          "temperature": 72,
          "humidity": 65,
          "description": "Partly Cloudy",
          "windSpeed": 8,
          "pressure": 30.15,
          "precipitation": 0,
          "sunrise": "6:18 AM",
          "sunset": "7:27 PM"
        },
        "providers": [
          {
            "name": "aws",
            "status": "healthy",
            "responseTime": 150
          }
        ]
      }
    ]
  },
  "cloudProviders": ["aws", "azure", "gcp"],
  "executionTimeMs": 245,
  "timestamp": "2024-01-15T10:30:00Z"
}
```

## 📊 Data Sources

The API aggregates data from multiple weather services:

- **OpenWeatherMap API**: Real-time weather data
- **WeatherAPI.com**: Extended forecasts and historical data
- **AccuWeather**: Detailed meteorological information

## 🔧 Configuration

### Environment Variables

See `.env.example` for a complete list of configuration options:

- **Weather API Keys**: Authentication for weather data sources
- **Cloud Provider Settings**: Regions, credentials, and endpoints
- **Database Connections**: Connection strings for each cloud database
- **Security Settings**: API keys, JWT secrets, and encryption keys

### Lambda Function Configuration

Each cloud provider has its own Lambda function configuration:

- **AWS Lambda**: Node.js runtime, environment variables, IAM roles
- **Azure Functions**: Function app settings, connection strings
- **GCP Cloud Run**: Container configuration, service accounts

## 🚀 Deployment

### Automatic Deployment

Push to `main` branch triggers deployment to all clouds via GitHub Actions:

```yaml
# .github/workflows/deploy.yml
- Build and test Lambda functions
- Deploy AWS Lambda functions
- Deploy Azure Function Apps
- Deploy GCP Cloud Run services
- Run integration tests
```

### Manual Deployment

```bash
# Deploy specific cloud
npm run deploy:aws
npm run deploy:azure
npm run deploy:gcp

# Deploy everything
npm run deploy:all
```

### Environment-Specific Deployments

```bash
# Development
npm run deploy:dev

# Staging
npm run deploy:staging

# Production
npm run deploy:prod
```

## 📈 Monitoring

### Built-in Monitoring

- **Provider Health**: Real-time status monitoring for all cloud services
- **Response Times**: Track API performance across providers
- **Data Agreement**: Monitor consensus scoring between providers
- **Error Tracking**: Comprehensive error logging and reporting

### External Monitoring

- **AWS CloudWatch**: Lambda metrics and logs
- **Azure Monitor**: Function app performance
- **GCP Operations**: Cloud Run monitoring
- **Custom Dashboards**: Cross-cloud metrics aggregation

## 🔒 Security

### API Security

- **Rate Limiting**: Configurable request throttling
- **CORS Configuration**: Proper cross-origin settings
- **API Key Management**: Secure storage in cloud secret managers
- **Input Validation**: Comprehensive request validation

### Data Security

- **Encryption**: At-rest and in-transit encryption
- **Access Control**: IAM roles and permissions
- **Audit Logging**: Comprehensive activity logging
- **Data Retention**: Configurable data lifecycle policies

## 🧪 Testing

### API Testing

```bash
# Test aggregation endpoint
curl "https://your-api-url/api/aggregation/weather?location=New York"

# Test individual providers
curl "https://your-api-url/api/aws/weather?location=London"
```

### Load Testing

```bash
# Install artillery for load testing
npm install -g artillery

# Run load tests
artillery run tests/load-test.yml
```

## 🤝 Contributing

1. **Fork the repository**
2. **Create feature branch**: `git checkout -b feature/amazing-feature`
3. **Commit changes**: `git commit -m 'Add amazing feature'`
4. **Push to branch**: `git push origin feature/amazing-feature`
5. **Open Pull Request**

### Development Guidelines

- **TypeScript**: Use strict typing throughout
- **Testing**: Write tests for new API endpoints
- **Documentation**: Update API documentation
- **Code Style**: Follow ESLint and Prettier configurations

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Issues**: [GitHub Issues](https://github.com/nguieangoue/cloud-weather-dashboard/issues)
- **Email**: nguierochjunior@gmail.com
- **API Documentation**: `/docs` directory

## 🗺️ Roadmap

### Phase 1 (Current)
- [x] Multi-cloud weather data aggregation
- [x] RESTful API endpoints
- [x] Cross-cloud consensus system
- [x] Infrastructure as Code

### Phase 2 (Next)
- [ ] GraphQL API endpoints
- [ ] Real-time WebSocket connections
- [ ] Advanced caching strategies
- [ ] API rate limiting and quotas

### Phase 3 (Future)
- [ ] Machine learning weather predictions
- [ ] Historical weather data APIs
- [ ] Weather alerts and notifications
- [ ] Multi-language support

## 🏆 Acknowledgments

- **Weather APIs**: OpenWeatherMap, WeatherAPI.com, AccuWeather
- **Cloud Providers**: AWS, Microsoft Azure, Google Cloud Platform
- **Open Source**: Node.js, TypeScript, and the amazing open source community

---

**Built with ❤️ by [Nguie Angoue Jean Roch Junior](https://github.com/nguieangoue)**
