#!/bin/bash
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR" || exit 1

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
  echo "Warning: This script is designed for macOS. For Linux, use install.sh instead."
  echo "Continuing anyway..."
fi

# Download weight files if not present
if [ ! -f "./CryoAtom/checkpoint/CryNet.pth" ] || [ ! -f "./CryoAtom/checkpoint/SimpleUnet.pth" ]; then
  echo "Downloading the required weight files for CryoAtom:"
  curl -L -o checkpoints_v1.0.zip https://yanglab.qd.sdu.edu.cn/CryoAtom/download/checkpoints_v1.0.zip --insecure
  unzip checkpoints_v1.0.zip
  rm -f checkpoints_v1.0.zip
  if [ ! -f "./CryoAtom/checkpoint/CryNet.pth" ] || [ ! -f "./CryoAtom/checkpoint/SimpleUnet.pth" ]; then
      echo "Please manually download the weight file from https://yanglab.qd.sdu.edu.cn/CryoAtom/download/checkpoints_v1.0.zip, and download it to the checkpoint folder within the CryoAtom directory."
      exit 1
  fi
fi
echo "Detected weight files exist"

# Check if CryoAtom conda environment already exists
is_env_installed=$(conda info --envs | grep CryoAtom -c)
if [[ "${is_env_installed}" == "0" ]];then
  echo "Deploying conda environment for macOS with Metal GPU support..."

  # Check if we're on Apple Silicon
  if [[ $(uname -m) == "arm64" ]]; then
      echo "Detected Apple Silicon (M-series chip)"
      echo "Metal GPU acceleration will be available"
  else
      echo "Detected Intel Mac - Metal support may be limited"
  fi

  conda env create -f macos.yml
else
  echo "Detected an existing CryoAtom environment, exiting installation";
  exit 1;
fi

# Activate the environment
if [[ `command -v activate` ]]
then
  source `which activate` CryoAtom
else
  conda activate CryoAtom
fi

# Check to make sure CryoAtom is activated
if [[ "${CONDA_DEFAULT_ENV}" != "CryoAtom" ]]
then
  echo "Could not run conda activate CryoAtom, please check the errors";
  exit 1;
fi

python_exc="${CONDA_PREFIX}/bin/python"

# Install CryoAtom package
$python_exc setup.py install

# Check if MPS is available
echo ""
echo "Checking Metal GPU availability..."
$python_exc -c "import torch; print('Metal GPU (MPS) available:', torch.backends.mps.is_available()); print('Metal GPU built:', torch.backends.mps.is_built())"

echo ""
echo "Installation complete!"
echo ""
echo "To use CryoAtom with Metal GPU acceleration:"
echo "  conda activate CryoAtom"
echo "  cryoatom build -s protein.fasta -v map.mrc -o output -d mps"
echo ""
echo "The device will auto-detect Metal GPU by default if available."
echo "done!"
