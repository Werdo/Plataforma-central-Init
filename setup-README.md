I've created a comprehensive setup script for Ubuntu 24.04 LTS that will orchestrate the deployment of your Central Platform system. The script `setup-central-platform.sh` provides a complete automation solution that:

1. Creates the necessary directory structure for your project
2. Generates all deployment scripts for each zone
3. Creates Kubernetes configuration files
4. Installs prerequisites (Docker, kubectl, Minikube, Helm)
5. Offers options to start Minikube and deploy all components

## Script Features

- **Modular Design**: Organizes deployment by zones (A-G)
- **Prerequisite Installation**: Automatically installs all required tools
- **Detailed Logging**: Records all operations to a log file
- **Color-Coded Output**: Uses colors for better readability
- **Error Handling**: Checks success of each operation
- **Interactive Options**: Asks user before starting Minikube or deploying

## How to Use

1. Save the script to a file named `setup-central-platform.sh`
2. Make it executable: `chmod +x setup-central-platform.sh`
3. Run it: `./setup-central-platform.sh`

The script will:
- Install all necessary prerequisites
- Create the project directory structure at `~/central-platform/`
- Generate deployment scripts for each zone
- Create Kubernetes manifests
- Optionally start Minikube and deploy components

## Deployment Order

The script follows a logical deployment order for dependencies:

1. Zone E (Persistence) - Databases first
2. Zone G (Security) - Security components
3. Zone D (Messaging) - Message queues
4. Zone B (Backend) - Backend services
5. Zone C (IoT Gateways) - IoT connectors
6. Zone A (Frontend) - User interface
7. Monitoring - Observability tools

## Additional Notes

- The script uses `cat > file << 'EOF'` pattern to create files, avoiding issues with bash interpretation.
- Each deployment step is logged and verified.
- For local development, Minikube is used with appropriate resources.
- A detailed README is created in the project directory.

You can modify the script as needed to adjust resource requirements, add more components, or integrate with your existing CI/CD pipeline.
