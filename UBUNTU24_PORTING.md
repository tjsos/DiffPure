# Porting DiffPure to Ubuntu 24.04 + CUDA 12.6

Steps taken to make the original Ubuntu 20.04 + CUDA 11.0 setup work on Ubuntu 24.04 + CUDA 12.6.

---

## 1. Extract requirements into a separate file

The original `diffpure.Dockerfile` had all pip packages hardcoded inline. Extracted them into `requirements.txt` and updated the Dockerfile to reference it:

```dockerfile
COPY requirements.txt .
RUN pip install -r requirements.txt
```

---

## 2. Create a new Dockerfile and requirements file for Ubuntu 24.04

Created `diffpure_ubuntu24.Dockerfile` and `requirements_ubuntu24.txt` as separate files so the original setup remains untouched.

---

## 3. Update the base image

```dockerfile
# Before
FROM nvidia/cuda:11.0.3-devel-ubuntu20.04

# After
FROM nvidia/cuda:12.6.0-devel-ubuntu24.04
```

---

## 4. Remove `python` from apt packages

Ubuntu 24.04 dropped the bare `python` package — only `python3` exists. Removed it from the `apt-get install` list to prevent a build failure.

Also removed the duplicate `ca-certificates` entry that was present in the original.

---

## 5. Fix pip bootstrapping

The original approach symlinked `/usr/bin/pip3` which does not exist in the Ubuntu 24.04 CUDA base image before pip is installed. Two fixes applied:

**Remove the `EXTERNALLY-MANAGED` marker** (safe inside Docker — this file blocks pip installs in Ubuntu 24.04 by default):
```dockerfile
RUN rm -f /usr/lib/python3.12/EXTERNALLY-MANAGED
```

**Bootstrap pip via `get-pip.py`** instead of relying on the system pip3 binary:
```dockerfile
RUN rm -f /usr/lib/python3.12/EXTERNALLY-MANAGED && \
    ln -sf /usr/bin/python3 /usr/local/bin/python && \
    curl -sS https://bootstrap.pypa.io/get-pip.py | python3 && \
    pip install --upgrade pip setuptools
```

Also removed `python3-pip` from apt since `get-pip.py` handles it.

---

## 6. Install PyTorch separately via the CUDA 12.6 wheel index

Pinning `torch==x.x.x+cu126` in requirements caused resolution failures. Instead, torch is installed in a dedicated step using `--index-url` which lets pip pick the latest compatible build:

```dockerfile
RUN pip install torch torchvision --index-url https://download.pytorch.org/whl/cu126
```

torch and torchvision are not listed in `requirements_ubuntu24.txt`.

---

## 7. Update pinned package versions for Python 3.12

The original pins were too old for Python 3.12. Updated versions:

| Package | Original | Ubuntu 24 |
|---|---|---|
| numpy | 1.19.4 | 1.26.4 |
| scipy | 1.5.2 | 1.13.0 |
| pillow | 7.2.0 | 10.3.0 |
| pandas | 1.2.0 | 2.2.0 |
| matplotlib | 3.3.0 | 3.9.0 |
| seaborn | 0.10.1 | 0.13.2 |
| timm | 0.5.4 | >=1.0.9 |
| tqdm | 4.56.1 | 4.66.4 |
| tensorboardX | 2.0 | 2.6.2 |
| requests | 2.25.0 | 2.31.0 |
| pyyaml | 5.3.1 | 6.0.1 |
| wheel | 0.34.2 | 0.43.0 |
| torchdiffeq | 0.2.1 | 0.2.3 |
| torchsde | (unpinned) | 0.2.6 |

`timm` specifically needed `>=1.0.9` because `robustbench==1.1` depends on it.

---

## 8. Fix `--gpus 0` in docker run

`--gpus 0` means **0 GPUs**, not GPU device 0. Changed to `--gpus all` in the README and run instructions:

```bash
# Before (broken)
docker run -it -d --gpus 0 ...

# After
docker run -it -d --gpus all ...
```

---

## 9. Install NVIDIA Container Toolkit

The `docker run --gpus` flag requires the NVIDIA Container Toolkit on the host. Install it with:

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

Verify: `docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi`

---

## 10. Fix SyntaxWarning in Python 3.12

Python 3.12 is stricter about invalid escape sequences in non-raw strings. Fixed in `stadv_eot/recoloradv/mister_ed/utils/checkpoints.py:87`:

```python
# Before
re_prefix = '%s\.%s\.' % (experiment_name, architecture)

# After
re_prefix = r'%s\.%s\.' % (experiment_name, architecture)
```

---

## 11. Fix AutoAttack `attacks_to_run` compatibility

Newer versions of the `autoattack` library raise a `ValueError` if `attacks_to_run` is passed when `version` is not `'custom'` — for `rand` and `standard` the library defines the attack list itself. Fixed both `AutoAttack` calls in `eval_sde_adv.py`:

```python
# Before
adversary = AutoAttack(..., version=attack_version, attacks_to_run=attack_list, ...)

# After
adversary = AutoAttack(..., version=attack_version,
                       attacks_to_run=attack_list if attack_version == 'custom' else [], ...)
```

---

## 12. Apptainer support for HPC environments

Docker is typically unavailable on HPC clusters. Created `diffpure_ubuntu24.def` as an Apptainer definition file equivalent to `diffpure_ubuntu24.Dockerfile`.

Key differences from Docker:
- `ENV` → `%environment` section
- `RUN` → commands inside `%post` section  
- `COPY` → `%files` section (source destination pairs)
- `CMD` → `%runscript` section

Build and run:
```bash
apptainer build diffpure_ubuntu24.sif diffpure_ubuntu24.def
apptainer run --nv --bind $(pwd):/workspace diffpure_ubuntu24.sif
```

- `--nv` passes through host NVIDIA GPU drivers (equivalent to `--gpus all`)
- `--bind` mounts the repo directory into the container (equivalent to `-v`)

---

## Files changed

| File | Change |
|---|---|
| `diffpure_ubuntu24.Dockerfile` | New — Ubuntu 24.04 + CUDA 12.6 Dockerfile |
| `diffpure_ubuntu24.def` | New — Apptainer definition file for HPC environments |
| `requirements_ubuntu24.txt` | New — Python 3.12 compatible dependencies |
| `requirements.txt` | New — extracted from original Dockerfile |
| `diffpure.Dockerfile` | Updated to use `requirements.txt` |
| `README.md` | Added Ubuntu 24.04 setup, NVIDIA toolkit install, fixed `--gpus` flag, added Apptainer instructions |
| `stadv_eot/recoloradv/mister_ed/utils/checkpoints.py` | Fixed invalid escape sequence |
| `eval_sde_adv.py` | Fixed AutoAttack `attacks_to_run` compatibility |
