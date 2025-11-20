#!/bin/bash
set -e  # Exit on error

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR" || exit 1

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
  echo -e "${YELLOW}Warning: This script is designed for macOS. For Linux, use install.sh instead.${NC}"
  echo "Continuing anyway..."
fi

# Check for required commands
echo "Checking for required commands..."
for cmd in curl unzip conda; do
  if ! command -v $cmd &> /dev/null; then
    echo -e "${RED}Error: $cmd is not installed or not in PATH${NC}"
    if [ "$cmd" = "conda" ]; then
      echo "Please install Miniforge or Anaconda first:"
      echo "  curl -L -O https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-MacOSX-arm64.sh"
      echo "  bash Miniforge3-MacOSX-arm64.sh"
    fi
    exit 1
  fi
done
echo -e "${GREEN}✓ All required commands found${NC}"

# Download weight files if not present
REQUIRED_FILES=("./CryoAtom/checkpoint/CryNet.pth" "./CryoAtom/checkpoint/SimpleUnet.pth" "./CryoAtom/checkpoint/CryNet_no_seq.pth")
MISSING_FILES=false

for file in "${REQUIRED_FILES[@]}"; do
  if [ ! -f "$file" ]; then
    MISSING_FILES=true
    break
  fi
done

if [ "$MISSING_FILES" = true ]; then
  echo "Downloading the required weight files for CryoAtom..."

  # Try downloading with retries
  MAX_RETRIES=3
  RETRY_COUNT=0
  DOWNLOAD_SUCCESS=false

  while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$DOWNLOAD_SUCCESS" = false ]; do
    if [ $RETRY_COUNT -gt 0 ]; then
      echo "Retry attempt $RETRY_COUNT of $MAX_RETRIES..."
      sleep 2
    fi

    if curl -L -o checkpoints_v1.0.zip https://yanglab.qd.sdu.edu.cn/CryoAtom/download/checkpoints_v1.0.zip --insecure --fail --show-error; then
      DOWNLOAD_SUCCESS=true
    else
      RETRY_COUNT=$((RETRY_COUNT + 1))
    fi
  done

  if [ "$DOWNLOAD_SUCCESS" = false ]; then
    echo -e "${RED}Error: Failed to download weight files after $MAX_RETRIES attempts${NC}"
    echo "Please manually download from: https://yanglab.qd.sdu.edu.cn/CryoAtom/download/checkpoints_v1.0.zip"
    echo "Then extract to the CryoAtom/checkpoint directory"
    exit 1
  fi

  echo "Extracting weight files..."
  if ! unzip -q checkpoints_v1.0.zip; then
    echo -e "${RED}Error: Failed to extract weight files${NC}"
    exit 1
  fi
  rm -f checkpoints_v1.0.zip

  # Verify all required files are present
  for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
      echo -e "${RED}Error: Missing required file: $file${NC}"
      echo "Please manually download and extract checkpoints_v1.0.zip to CryoAtom/checkpoint/"
      exit 1
    fi
  done
fi
echo -e "${GREEN}✓ All weight files present${NC}"

# Check if CryoAtom conda environment already exists
echo "Checking for existing CryoAtom environment..."
is_env_installed=$(conda info --envs | grep -w CryoAtom -c)
if [[ "${is_env_installed}" == "0" ]];then
  echo "Deploying conda environment for macOS with Metal GPU support..."

  # Check if we're on Apple Silicon
  ARCH=$(uname -m)
  if [[ "$ARCH" == "arm64" ]]; then
      echo -e "${GREEN}✓ Detected Apple Silicon (M-series chip)${NC}"
      echo "  Metal GPU acceleration will be available"
  else
      echo -e "${YELLOW}⚠ Detected Intel Mac ($ARCH)${NC}"
      echo "  Metal GPU support may be limited or unavailable"
      echo "  Consider using CPU mode with: -d cpu"
  fi

  # Create conda environment
  echo "Creating conda environment (this may take several minutes)..."
  if ! conda env create -f macos.yml; then
    echo -e "${RED}Error: Failed to create conda environment${NC}"
    echo "Please check the error messages above and try again"
    exit 1
  fi
  echo -e "${GREEN}✓ Conda environment created successfully${NC}"
else
  echo -e "${YELLOW}Detected an existing CryoAtom environment${NC}"
  echo "To reinstall, first remove the existing environment:"
  echo "  conda remove -n CryoAtom --all"
  exit 1;
fi

# Activate the environment
echo "Activating CryoAtom environment..."
if [[ `command -v activate` ]]
then
  source `which activate` CryoAtom
else
  conda activate CryoAtom
fi

# Check to make sure CryoAtom is activated
if [[ "${CONDA_DEFAULT_ENV}" != "CryoAtom" ]]
then
  echo -e "${RED}Error: Could not activate CryoAtom environment${NC}"
  echo "Please try manually:"
  echo "  conda activate CryoAtom"
  exit 1;
fi
echo -e "${GREEN}✓ Environment activated${NC}"

python_exc="${CONDA_PREFIX}/bin/python"

# Install CryoAtom package
echo "Installing CryoAtom package..."
if ! $python_exc setup.py install; then
  echo -e "${RED}Error: Failed to install CryoAtom package${NC}"
  exit 1
fi
echo -e "${GREEN}✓ CryoAtom package installed${NC}"

# Check if MPS is available
echo ""
echo "Verifying installation and checking Metal GPU availability..."
MPS_STATUS=$($python_exc -c "import torch; print('MPS_AVAILABLE' if torch.backends.mps.is_available() else 'MPS_UNAVAILABLE'); print('MPS_BUILT' if torch.backends.mps.is_built() else 'MPS_NOT_BUILT')" 2>&1)

if echo "$MPS_STATUS" | grep -q "MPS_AVAILABLE"; then
  echo -e "${GREEN}✓ Metal GPU (MPS) is available and ready to use!${NC}"
elif echo "$MPS_STATUS" | grep -q "MPS_BUILT"; then
  echo -e "${YELLOW}⚠ Metal GPU (MPS) is built but not available${NC}"
  echo "  This is normal on Intel Macs or older macOS versions"
  echo "  CryoAtom will fall back to CPU mode"
else
  echo -e "${YELLOW}⚠ Metal GPU (MPS) is not available${NC}"
  echo "  CryoAtom will use CPU mode"
fi

# Verify CryoAtom command is available
if ! command -v cryoatom &> /dev/null; then
  echo -e "${YELLOW}⚠ Warning: 'cryoatom' command not found in PATH${NC}"
  echo "  You may need to restart your shell or run:"
  echo "    conda activate CryoAtom"
else
  echo -e "${GREEN}✓ CryoAtom command is available${NC}"
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Installation complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "To use CryoAtom:"
echo "  1. Activate the environment:"
echo "     conda activate CryoAtom"
echo ""
echo "  2. Run CryoAtom (device auto-detection enabled):"
echo "     cryoatom build -s protein.fasta -v map.mrc -o output"
echo ""
echo "  3. Or explicitly specify Metal GPU:"
echo "     cryoatom build -s protein.fasta -v map.mrc -o output -d mps"
echo ""
echo "For help:"
echo "  cryoatom build -h"
echo ""
